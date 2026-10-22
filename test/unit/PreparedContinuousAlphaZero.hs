{-# LANGUAGE OverloadedStrings #-}

-- Offline numerical callbacks only. These controls confer no selected hardware,
-- producer origin, durable barrier, canonical-row or qualification authority.
module PreparedContinuousAlphaZero (preparedContinuousAlphaZeroTests) where

import Control.Concurrent (forkIO, newEmptyMVar, putMVar, takeMVar)
import Control.Exception (SomeException, throwIO, try)
import Control.Monad (void)
import Data.Either (isLeft, isRight, rights)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word64)
import GHC.Float (castDoubleToWord64)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

import JitML.Numerics.Mlp
  ( AdamState (..)
  , MlpForward (..)
  , MlpGradient (..)
  , MlpParams (..)
  , MlpShape (..)
  , adamInit
  , mlpInit
  , mlpParamsToFlat
  )
import JitML.Numerics.MlpDevice (MlpDevice (..), pureReferenceMlpDevice)
import JitML.RL.Algorithms.Common qualified as Common
import JitML.RL.Algorithms.ContinuousTrainer qualified as C
import JitML.RL.AlphaZero qualified as Game
import JitML.RL.AlphaZero.PolicyValueNet qualified as PVN
import JitML.RL.AlphaZero.PreparedTrainer qualified as AZ
import JitML.RL.Simulator (SomeContinuousEnvironment (..), pendulumEnvironment)

bits :: VU.Vector Double -> [Word64]
bits = map castDoubleToWord64 . VU.toList

parameterBits :: MlpParams -> [Word64]
parameterBits = bits . VU.fromList . mlpParamsToFlat

gradientBits :: MlpGradient -> [[Word64]]
gradientBits gradient = map bits [gradW1 gradient, gradB1 gradient, gradW2 gradient, gradB2 gradient]

forwardBits :: MlpForward -> [[Word64]]
forwardBits f = map bits [forwardInput f, forwardHiddenPre f, forwardHiddenAct f, forwardOutput f]

record :: (Show a) => IORef [String] -> String -> a -> IO ()
record ref tag payload = modifyIORef' ref ((tag <> " " <> show payload) :)

-- Keep strict pair-pattern demand in the lossless callback trace.
{- HLINT ignore traceDevice "Use bimap" -}
{- HLINT ignore traceDevice "Use both" -}
traceDevice :: IORef [String] -> MlpDevice
traceDevice events =
  pureReferenceMlpDevice
    { mlpdForward = \p x -> do
        r <- mlpdForward pureReferenceMlpDevice p x
        record events "forward" (parameterBits p, bits x, fmap forwardBits r)
        pure r
    , mlpdBackward = \p f u -> do
        r <- mlpdBackward pureReferenceMlpDevice p f u
        record events "backward" (parameterBits p, forwardBits f, bits u, fmap gradientBits r)
        pure r
    , mlpdForwardBatch = \p xs -> do
        r <- mlpdForwardBatch pureReferenceMlpDevice p xs
        record events "forward-batch" (parameterBits p, map bits xs, fmap (map bits) r)
        pure r
    , mlpdBatchGradient = \p xs -> do
        r <- mlpdBatchGradient pureReferenceMlpDevice p xs
        record
          events
          "batch-gradient"
          (parameterBits p, map (\(x, u) -> (bits x, bits u)) xs, fmap gradientBits r)
        pure r
    , mlpdInputGradientBatch = \p xs -> do
        r <- mlpdInputGradientBatch pureReferenceMlpDevice p xs
        record
          events
          "input-gradient-batch"
          (parameterBits p, map (\(x, u) -> (bits x, bits u)) xs, fmap (map bits) r)
        pure r
    , mlpdExecutionWitness = do
        record events "unexpected-witness" ()
        pure (Left "raw prepared trainer must not query a witness")
    }

requireRight :: (Show e) => Either e a -> IO a
requireRight result = case result of
  Right value -> pure value
  Left err -> assertFailure (show err) >> fail "unreachable"

expectLeft :: Text -> Either Text a -> IO ()
expectLeft fragment result = case result of
  Left err -> assertBool (Text.unpack err) (fragment `Text.isInfixOf` err)
  Right _ -> assertFailure ("expected Left containing " <> Text.unpack fragment)

smallContinuous :: C.ContinuousTrainConfig
smallContinuous =
  (C.defaultContinuousTrainConfig C.VariantDDPG)
    { C.ctHidden = 2
    , C.ctNumSteps = 4
    , C.ctBatchSize = 1
    , C.ctTrainStart = 0
    , C.ctStartSteps = 0
    , C.ctMaxEpisodeSteps = 2
    , C.ctStatInterval = 1
    }

preparedContinuousAlphaZeroTests :: TestTree
preparedContinuousAlphaZeroTests =
  testGroup
    "Prepared continuous and AlphaZero initialization"
    [ testCase
        "continuous cold snapshot owns exact initializer and untouched scheduled state without device IO"
        $ do
          events <- newIORef []
          cold <-
            C.prepareContinuousOnDeviceWithEnvironment (traceDevice events) pendulumEnvironment smallContinuous
          let s = C.preparedContinuousColdSnapshot cold
              actor = mlpInit (MlpShape 3 2 1) 42
              criticA = mlpInit (MlpShape 4 2 1) 143
          C.continuousPreparedStage s @?= C.ContinuousCold
          C.continuousPreparedConfig s @?= smallContinuous
          parameterBits (C.continuousPreparedColdActor s) @?= parameterBits actor
          parameterBits (C.continuousPreparedActor s) @?= parameterBits actor
          parameterBits (C.continuousPreparedCriticA s) @?= parameterBits criticA
          C.continuousPreparedActorAdam s @?= adamInit (MlpShape 3 2 1)
          C.continuousPreparedStep s @?= 0
          C.continuousPreparedReplay s @?= []
          C.continuousPreparedStatistics s @?= []
          C.continuousPreparedWarmAdam s @?= Nothing
          readIORef events >>= (@?= [])
    , testCase "continuous effective actor and critics are the actual first update callback parameters" $ do
        observedParams <- newIORef []
        let device =
              pureReferenceMlpDevice
                { mlpdForwardBatch = \p xs -> do
                    modifyIORef' observedParams (p :)
                    mlpdForwardBatch pureReferenceMlpDevice p xs
                }
        cold <- C.prepareContinuousOnDeviceWithEnvironment device pendulumEnvironment smallContinuous
        effective <- C.continuePreparedContinuousInitialization cold >>= requireRight
        let s = C.preparedContinuousSnapshot effective
        raw <- C.continuePreparedContinuousRaw effective >>= requireRight
        ps <- reverse <$> readIORef observedParams
        case ps of
          first : _ -> parameterBits first @?= parameterBits (C.continuousPreparedCriticA s)
          [] -> assertFailure "actual update did not call selected callback"
        case filter ((== 3) . mlpInputs . paramShape) ps of
          firstActor : _ -> parameterBits firstActor @?= parameterBits (C.continuousPreparedActor s)
          [] -> assertFailure "actual actor callback was absent"
        parameterBits (Common.rawTrainerInitialParams raw) @?= parameterBits (C.continuousPreparedActor s)
        Common.observedEnvironmentTransitionCount (Common.rawTrainerCounters raw) @?= 4
        Common.observedOptimizerUpdateCount (Common.rawTrainerCounters raw) @?= 4
    , testCase
        "continuous public legacy wrapper and explicit continuation preserve complete callback and result bytes"
        $ do
          oldEvents <- newIORef []
          newEvents <- newIORef []
          oldResult <-
            C.trainContinuousOnDeviceWithEnvironmentRaw
              (traceDevice oldEvents)
              (SomeContinuousEnvironment pendulumEnvironment)
              smallContinuous
          cold <-
            C.prepareContinuousOnDeviceWithEnvironment
              (traceDevice newEvents)
              pendulumEnvironment
              smallContinuous
          effective <- C.continuePreparedContinuousInitialization cold >>= requireRight
          newResult <- C.continuePreparedContinuousRaw effective
          oldResult @?= newResult
          case (oldResult, newResult) of
            (Right a, Right b) ->
              parameterBits (Common.rawTrainerFinalParams a) @?= parameterBits (Common.rawTrainerFinalParams b)
            _ -> assertFailure "small actual training failed"
          readIORef oldEvents >>= \a -> readIORef newEvents >>= (@?= a)
    , testCase
        "continuous zero scheduled work remains raw zero without callbacks or invented positive counters"
        $ do
          events <- newIORef []
          cold <-
            C.prepareContinuousOnDeviceWithEnvironment
              (traceDevice events)
              pendulumEnvironment
              smallContinuous {C.ctNumSteps = 0}
          effective <- C.continuePreparedContinuousInitialization cold >>= requireRight
          raw <- C.continuePreparedContinuousRaw effective >>= requireRight
          Common.observedEnvironmentTransitionCount (Common.rawTrainerCounters raw) @?= 0
          Common.observedOptimizerUpdateCount (Common.rawTrainerCounters raw) @?= 0
          assertBool
            "strict legacy positive refinement must still fail"
            (isLeft (C.refineContinuousTrainObservation raw))
          parameterBits (Common.rawTrainerInitialParams raw)
            @?= parameterBits (Common.rawTrainerFinalParams raw)
          readIORef events >>= (@?= [])
    , testCase
        "continuous actual SAC warm optimizer is retained and discarded before fresh scheduled Adam"
        $ do
          events <- newIORef []
          let config =
                (C.defaultContinuousTrainConfig C.VariantSAC)
                  { C.ctHidden = 1
                  , C.ctNumSteps = 0
                  , C.ctEnvName = "pendulum"
                  }
          cold <- C.prepareContinuousOnDeviceWithEnvironment (traceDevice events) pendulumEnvironment config
          let coldSnapshot = C.preparedContinuousColdSnapshot cold
              coldBits = parameterBits (C.continuousPreparedColdActor coldSnapshot)
          C.continuousPreparedWarmAdam coldSnapshot @?= Just (adamInit (MlpShape 3 1 1))
          C.continuousPreparedWarmUpdateCount coldSnapshot @?= 0
          C.continuousPreparedTargetActor coldSnapshot @?= Nothing
          C.continuousPreparedTargetCriticA coldSnapshot @?= Nothing
          C.continuousPreparedTargetCriticB coldSnapshot @?= Nothing
          C.continuousPreparedCountEntries coldSnapshot @?= []
          effective <- C.continuePreparedContinuousInitialization cold >>= requireRight
          let s = C.preparedContinuousSnapshot effective
          C.continuousPreparedStage s @?= C.ContinuousEffective
          C.continuousPreparedTargetActor s @?= Just (C.continuousPreparedActor s)
          C.continuousPreparedTargetCriticA s @?= Just (C.continuousPreparedCriticA s)
          C.continuousPreparedTargetCriticB s @?= Just (C.continuousPreparedCriticB s)
          C.continuousPreparedCountEntries s @?= []
          C.continuousPreparedWarmUpdateCount s @?= 340000
          assertBool "warm actor actually changed" (parameterBits (C.continuousPreparedActor s) /= coldBits)
          case C.continuousPreparedWarmAdam s of
            Nothing -> assertFailure "actual warm Adam missing"
            Just warmAdam -> do
              adamStep_ warmAdam @?= 340000
              assertBool
                "actual warm first moment is not fresh zero"
                ( any
                    (any (/= 0) . VU.toList)
                    [gradW1 (adamM warmAdam), gradB1 (adamM warmAdam), gradW2 (adamM warmAdam), gradB2 (adamM warmAdam)]
                )
          adamStep_ (C.continuousPreparedActorAdam s) @?= 0
          C.continuousPreparedActorAdam s @?= adamInit (MlpShape 3 1 1)
          raw <- C.continuePreparedContinuousRaw effective >>= requireRight
          parameterBits (Common.rawTrainerInitialParams raw) @?= parameterBits (C.continuousPreparedActor s)
          parameterBits (Common.rawTrainerFinalParams raw) @?= parameterBits (C.continuousPreparedActor s)
          Common.observedOptimizerUpdateCount (Common.rawTrainerCounters raw) @?= 0
          readIORef events >>= (@?= [])
    , testCase "continuous cold and effective stages each reject a second claim before callbacks" $ do
        events <- newIORef []
        cold <-
          C.prepareContinuousOnDeviceWithEnvironment (traceDevice events) pendulumEnvironment smallContinuous
        effective <- C.continuePreparedContinuousInitialization cold >>= requireRight
        C.continuePreparedContinuousInitialization cold
          >>= expectLeft "initialization has already been consumed"
        void (C.continuePreparedContinuousRaw effective >>= requireRight)
        before <- readIORef events
        C.continuePreparedContinuousRaw effective >>= expectLeft "continuation has already been consumed"
        readIORef events >>= (@?= before)
    , testCase "continuous callback Left is preserved and consumed without later callbacks or witness" $ do
        events <- newIORef []
        let device =
              (traceDevice events)
                { mlpdForwardBatch = \_ _ -> modifyIORef' events ("first-forward-left" :) >> pure (Left "chosen failure")
                }
        cold <- C.prepareContinuousOnDeviceWithEnvironment device pendulumEnvironment smallContinuous
        effective <- C.continuePreparedContinuousInitialization cold >>= requireRight
        C.continuePreparedContinuousRaw effective
          >>= expectLeft "continuous device forward kernel (critic) failed mid-run: chosen failure"
        readIORef events >>= (@?= ["first-forward-left"])
        C.continuePreparedContinuousRaw effective >>= expectLeft "already been consumed"
        readIORef events >>= (@?= ["first-forward-left"])
    , testCase "continuous thrown callback leaves continuation consumed" $ do
        calls <- newIORef (0 :: Int)
        let device =
              pureReferenceMlpDevice
                { mlpdForwardBatch = \_ _ -> modifyIORef' calls (+ 1) >> throwIO (userError "chosen throw")
                }
        cold <- C.prepareContinuousOnDeviceWithEnvironment device pendulumEnvironment smallContinuous
        effective <- C.continuePreparedContinuousInitialization cold >>= requireRight
        result <-
          try (C.continuePreparedContinuousRaw effective)
            :: IO (Either SomeException (Either Text C.ContinuousTrainObservation))
        assertBool "callback exception was preserved" (isLeft result)
        C.continuePreparedContinuousRaw effective >>= expectLeft "already been consumed"
        readIORef calls >>= (@?= 1)
    , testCase "continuous concurrent claims execute one complete selected callback trace" $ do
        events <- newIORef []
        cold <-
          C.prepareContinuousOnDeviceWithEnvironment (traceDevice events) pendulumEnvironment smallContinuous
        effective <- C.continuePreparedContinuousInitialization cold >>= requireRight
        results <- newEmptyMVar
        void (forkIO (C.continuePreparedContinuousRaw effective >>= putMVar results))
        void (forkIO (C.continuePreparedContinuousRaw effective >>= putMVar results))
        a <- takeMVar results
        b <- takeMVar results
        length (filter isRight [a, b]) @?= 1
        length (filter isLeft [a, b]) @?= 1
        calls <- readIORef events
        assertBool "actual trace ran" (not (null calls))
        assertBool
          "raw path never queries witness"
          (not (any (Text.isPrefixOf "unexpected-witness" . Text.pack) calls))
    , testCase "AlphaZero snapshot owns actual game-shaped initializer and fresh Adam without callbacks" $ do
        events <- newIORef []
        prepared <- AZ.prepareAlphaZeroWithDevice (traceDevice events) "connect4" 2 42 1 1 2 2 1
        let s = AZ.preparedAlphaZeroSnapshot prepared
            expected = PVN.initPolicyValueNet (Game.observationSizeFor "connect4") (Game.actionCountFor "connect4") 2 42
        AZ.alphaZeroPreparedInitialState s @?= Game.initialStateFor "connect4"
        AZ.alphaZeroPreparedInitialNet s @?= expected
        AZ.alphaZeroPreparedInitialAdam s @?= PVN.initAdamFor expected
        AZ.alphaZeroPreparedHiddenUnits s @?= 2
        AZ.alphaZeroPreparedSeed s @?= 42
        AZ.alphaZeroPreparedGenerationTarget s @?= 1
        AZ.alphaZeroPreparedGames s @?= 1
        AZ.alphaZeroPreparedSimulations s @?= 2
        AZ.alphaZeroPreparedMaxPlies s @?= 2
        AZ.alphaZeroPreparedUpdates s @?= 1
        readIORef events >>= (@?= [])
    , testCase "AlphaZero zero generation retains initial network and no callback or invented samples" $ do
        events <- newIORef []
        prepared <- AZ.prepareAlphaZeroWithDevice (traceDevice events) "connect4" 2 42 0 1 2 2 1
        observed <- AZ.continuePreparedAlphaZeroRaw prepared >>= requireRight
        let (net, samples, count) = AZ.alphaZeroObservationLegacyResult observed
            initial = AZ.preparedAlphaZeroSnapshot prepared
        net @?= AZ.alphaZeroPreparedInitialNet initial
        samples @?= []
        count @?= 0
        AZ.alphaZeroObservedInitialState observed @?= AZ.alphaZeroPreparedInitialState initial
        AZ.alphaZeroObservedInitialNet observed @?= AZ.alphaZeroPreparedInitialNet initial
        AZ.alphaZeroObservedInitialAdam observed @?= AZ.alphaZeroPreparedInitialAdam initial
        AZ.alphaZeroObservedFinalAdam observed @?= AZ.alphaZeroPreparedInitialAdam initial
        AZ.alphaZeroObservedOptimizerApplicationDelta observed @?= 0
        AZ.alphaZeroObservedGenerationTarget observed @?= 0
        AZ.alphaZeroObservedGames observed @?= 1
        AZ.alphaZeroObservedSimulations observed @?= 2
        AZ.alphaZeroObservedMaxPlies observed @?= 2
        AZ.alphaZeroObservedUpdates observed @?= 1
        AZ.alphaZeroObservedSeed observed @?= 42
        readIORef events >>= (@?= [])
    , testCase
        "AlphaZero single generation equals actual public sampling and update primitives including callback bytes"
        $ do
          directEvents <- newIORef []
          preparedEvents <- newIORef []
          let directDevice = traceDevice directEvents
              state0 = Game.initialStateFor "connect4"
              net0 = PVN.initPolicyValueNet (Game.observationSizeFor "connect4") (Game.actionCountFor "connect4") 2 42
              adam0 = PVN.initAdamFor net0
          samples <-
            PVN.generatePolicyValueSamplesWithDeviceFrom state0 directDevice net0 42 2 2 >>= requireRight
          (expected, expectedAdam) <-
            PVN.trainPolicyValueNetOnSamplesWithDevice directDevice net0 adam0 1.0e-3 1 samples >>= requireRight
          adamStep_ expectedAdam @?= 1
          prepared <- AZ.prepareAlphaZeroWithDevice (traceDevice preparedEvents) "connect4" 2 42 1 1 2 2 1
          observed <- AZ.continuePreparedAlphaZeroRaw prepared >>= requireRight
          let (actual, actualSamples, generations) = AZ.alphaZeroObservationLegacyResult observed
              actualAdam = AZ.alphaZeroObservedFinalAdam observed
          bits (VU.fromList (PVN.policyValueNetToFlat actual))
            @?= bits (VU.fromList (PVN.policyValueNetToFlat expected))
          actualSamples @?= samples
          generations @?= 1
          AZ.alphaZeroObservedInitialState observed @?= state0
          AZ.alphaZeroObservedInitialNet observed @?= net0
          AZ.alphaZeroObservedInitialAdam observed @?= adam0
          adamStep_ actualAdam @?= adamStep_ expectedAdam
          gradientBits (adamM actualAdam) @?= gradientBits (adamM expectedAdam)
          gradientBits (adamV actualAdam) @?= gradientBits (adamV expectedAdam)
          AZ.alphaZeroObservedOptimizerApplicationDelta observed @?= 1
          PVN.policyValueTrainingSamplesSha256 (AZ.alphaZeroObservedSamples observed)
            @?= PVN.policyValueTrainingSamplesSha256 samples
          readIORef directEvents >>= \a -> readIORef preparedEvents >>= (@?= a)
    , testCase
        "AlphaZero legacy delegation and prepared multigeneration preserve results order seeds and full callback trace"
        $ do
          legacyEvents <- newIORef []
          preparedEvents <- newIORef []
          let net0 = PVN.initPolicyValueNet (Game.observationSizeFor "connect4") (Game.actionCountFor "connect4") 2 42
          legacy <-
            AZ.trainAlphaZeroGenerationsWithDevice
              (traceDevice legacyEvents)
              (Game.initialStateFor "connect4")
              net0
              (PVN.initAdamFor net0)
              2
              2
              2
              2
              1
              42
          prepared <- AZ.prepareAlphaZeroWithDevice (traceDevice preparedEvents) "connect4" 2 42 2 2 2 2 1
          actual <- AZ.continuePreparedAlphaZeroRaw prepared
          fmap AZ.alphaZeroObservationLegacyResult actual @?= legacy
          readIORef legacyEvents >>= \a -> readIORef preparedEvents >>= (@?= a)
    , testCase "AlphaZero selected update error is retained and no second claim retries it" $ do
        calls <- newIORef (0 :: Int)
        let device =
              pureReferenceMlpDevice
                { mlpdBatchGradient = \_ _ -> modifyIORef' calls (+ 1) >> pure (Left "chosen update failure")
                }
        prepared <- AZ.prepareAlphaZeroWithDevice device "connect4" 2 42 1 1 2 2 1
        AZ.continuePreparedAlphaZeroRaw prepared >>= expectLeft "chosen update failure"
        AZ.continuePreparedAlphaZeroRaw prepared >>= expectLeft "already been consumed"
        readIORef calls >>= (@?= 1)
    , testCase "AlphaZero callback exception consumes continuation before an attempted retry" $ do
        calls <- newIORef (0 :: Int)
        let device =
              pureReferenceMlpDevice
                { mlpdBatchGradient = \_ _ -> modifyIORef' calls (+ 1) >> throwIO (userError "AZ chosen throw")
                }
        prepared <- AZ.prepareAlphaZeroWithDevice device "connect4" 2 42 1 1 2 2 1
        result <-
          try (AZ.continuePreparedAlphaZeroRaw prepared)
            :: IO (Either SomeException (Either Text AZ.AlphaZeroTrainObservation))
        assertBool "selected callback exception preserved" (isLeft result)
        AZ.continuePreparedAlphaZeroRaw prepared >>= expectLeft "already been consumed"
        readIORef calls >>= (@?= 1)
    , testCase "AlphaZero concurrent zero-generation claims return exactly once" $ do
        prepared <- AZ.prepareAlphaZeroWithDevice pureReferenceMlpDevice "connect4" 2 42 0 1 2 2 1
        results <- newEmptyMVar
        void (forkIO (AZ.continuePreparedAlphaZeroRaw prepared >>= putMVar results))
        void (forkIO (AZ.continuePreparedAlphaZeroRaw prepared >>= putMVar results))
        a <- takeMVar results
        b <- takeMVar results
        length (filter isRight [a, b]) @?= 1
        length (filter isLeft [a, b]) @?= 1
    , testCase "continuous scheduled targets are absent before creation and exact after initialization" $ do
        cold <-
          C.prepareContinuousOnDeviceWithEnvironment
            pureReferenceMlpDevice
            pendulumEnvironment
            smallContinuous
        let initial = C.preparedContinuousColdSnapshot cold
        C.continuousPreparedTargetActor initial @?= Nothing
        C.continuousPreparedTargetCriticA initial @?= Nothing
        C.continuousPreparedTargetCriticB initial @?= Nothing
        C.continuousPreparedCountEntries initial @?= []
        effective <- C.continuePreparedContinuousInitialization cold >>= requireRight
        let ready = C.preparedContinuousSnapshot effective
        C.continuousPreparedTargetActor ready @?= Just (C.continuousPreparedActor ready)
        C.continuousPreparedTargetCriticA ready @?= Just (C.continuousPreparedCriticA ready)
        C.continuousPreparedTargetCriticB ready @?= Just (C.continuousPreparedCriticB ready)
        C.continuousPreparedCountEntries ready @?= []
    , testCase "continuous warm optimizer exists only for the unchanged SAC pendulum recipe" $ do
        let check config = do
              cold <- C.prepareContinuousOnDeviceWithEnvironment pureReferenceMlpDevice pendulumEnvironment config
              let initial = C.preparedContinuousColdSnapshot cold
              C.continuousPreparedWarmAdam initial @?= Nothing
              effective <- C.continuePreparedContinuousInitialization cold >>= requireRight
              let ready = C.preparedContinuousSnapshot effective
              C.continuousPreparedWarmAdam ready @?= Nothing
              C.continuousPreparedWarmUpdateCount ready @?= 0
              parameterBits (C.continuousPreparedActor ready)
                @?= parameterBits (C.continuousPreparedColdActor initial)
        check smallContinuous {C.ctEnvName = "pendulum"}
        check smallContinuous {C.ctVariant = C.VariantSAC, C.ctEnvName = ""}
    , testCase "continuous concurrent cold claims create only one effective continuation" $ do
        events <- newIORef []
        cold <-
          C.prepareContinuousOnDeviceWithEnvironment (traceDevice events) pendulumEnvironment smallContinuous
        results <- newEmptyMVar
        void (forkIO (C.continuePreparedContinuousInitialization cold >>= putMVar results))
        void (forkIO (C.continuePreparedContinuousInitialization cold >>= putMVar results))
        a <- takeMVar results
        b <- takeMVar results
        length (filter isRight [a, b]) @?= 1
        length (filter isLeft [a, b]) @?= 1
        readIORef events >>= (@?= [])
        case rights [a, b] of
          [effective] -> do
            raw <- C.continuePreparedContinuousRaw effective >>= requireRight
            Common.observedEnvironmentTransitionCount (Common.rawTrainerCounters raw) @?= 4
            C.continuousPreparedCountEntries (C.preparedContinuousColdSnapshot cold) @?= []
          _ -> assertFailure "no unique effective continuation"
    ]
