{-# LANGUAGE OverloadedStrings #-}

-- Actual simulator/offline numerical callback controls. No provider, actual
-- training, convergence/quality threshold, canonical plan or origin claim.
module NativeReturnEvaluation (nativeReturnEvaluationTests) where

import Control.Exception (AsyncException (..), throwIO, try)
import Control.Monad (forM_)
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.List (groupBy)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU
import GHC.Float (castDoubleToWord64)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

import JitML.Numerics.Mlp (MlpForward (..), MlpParams (..), MlpShape (..), mlpInit, mlpParamsToFlat)
import JitML.Numerics.MlpDevice (MlpDevice (..), pureReferenceMlpDevice)
import JitML.RL.Algorithms.ArsTrainer qualified as Ars
import JitML.RL.Algorithms.Common qualified as Common
import JitML.RL.Algorithms.ContinuousTrainer qualified as C
import JitML.RL.Algorithms.DqnTrainer qualified as D
import JitML.RL.Algorithms.PpoTrainer qualified as P
import JitML.RL.Algorithms.QrDqnTrainer qualified as Q
import JitML.RL.NativeReturnEvaluation qualified as E
import JitML.RL.NativeReturnReferences qualified as R
import JitML.RL.Simulator qualified as Sim

right :: (Show e) => Either e a -> IO a
right result = case result of
  Right value -> pure value
  Left err -> assertFailure (show err) >> fail "unreachable"

specFor :: Text -> Text -> IO R.NativeReturnReferenceSpec
specFor algorithm environment = right (R.canonicalNativeReturnSpec algorithm environment)

paramsOf :: E.NativeNeuralPolicy -> MlpParams
paramsOf policy = case policy of
  E.NativeOnPolicy _ p -> p
  E.NativeDqn _ p -> p
  E.NativeQrDqn _ p -> p
  E.NativeContinuous _ p -> p

mapParams :: (MlpParams -> MlpParams) -> E.NativeNeuralPolicy -> E.NativeNeuralPolicy
mapParams f policy = case policy of
  E.NativeOnPolicy c p -> E.NativeOnPolicy c (f p)
  E.NativeDqn c p -> E.NativeDqn c (f p)
  E.NativeQrDqn c p -> E.NativeQrDqn c (f p)
  E.NativeContinuous c p -> E.NativeContinuous c (f p)

-- Tiny numerical fixtures with the exact evaluation context; never a claimed
-- canonical training architecture or budget-complete learner.
policyFor :: R.NativeReturnReferenceSpec -> Either Text E.NativeNeuralPolicy
policyFor spec = case R.nativeReturnSpecDomain spec of
  R.NativeContinuous lo hi -> do
    variant <- case algorithm of
      "DDPG" -> Right C.VariantDDPG
      "TD3" -> Right C.VariantTD3
      "SAC" -> Right C.VariantSAC
      "CrossQ" -> Right C.VariantCrossQ
      "TQC" -> Right C.VariantTQC
      _ -> Left "fixture continuous algorithm absent"
    let config =
          (C.defaultContinuousTrainConfig variant)
            { C.ctObsSize = width
            , C.ctHidden = 1
            , C.ctMaxEpisodeSteps = horizon
            , C.ctActionLow = lo
            , C.ctActionHigh = hi
            , C.ctEnvName = R.nativeReturnSpecEnvironment spec
            }
    Right (E.NativeContinuous config (mlpInit (MlpShape width 1 1) 42))
  _ -> case algorithm of
    "DQN" ->
      let config =
            D.defaultDqnTrainConfig
              { D.dqnObsSize = width
              , D.dqnActionCount = actions
              , D.dqnHiddenUnits = 1
              , D.dqnMaxEpisodeSteps = horizon
              }
       in Right (E.NativeDqn config (mlpInit (MlpShape width 1 actions) 42))
    "QR-DQN" ->
      let config =
            Q.defaultQrDqnTrainConfig
              { Q.qrObsSize = width
              , Q.qrActionCount = actions
              , Q.qrHiddenUnits = 1
              , Q.qrNumQuantiles = 2
              , Q.qrMaxEpisodeSteps = horizon
              }
       in Right (E.NativeQrDqn config (mlpInit (MlpShape width 1 (actions * 2)) 42))
    _ -> do
      variant <- case algorithm of
        "PPO" -> Right P.VariantPPO
        "A2C" -> Right P.VariantA2C
        "TRPO" -> Right P.VariantTRPO
        "MaskablePPO" -> Right P.VariantMaskablePPO
        "RecurrentPPO" -> Right P.VariantRecurrentPPO
        _ -> Left "fixture on-policy algorithm absent"
      let config =
            P.defaultPpoTrainConfig
              { P.ppoVariant = variant
              , P.ppoObsSize = width
              , P.ppoActionCount = actions
              , P.ppoHiddenUnits = 1
              , P.ppoMaxEpisodeSteps = horizon
              }
      Right (E.NativeOnPolicy config (mlpInit (MlpShape width 1 (actions + 1)) 42))
 where
  algorithm = R.nativeReturnSpecAlgorithm spec
  width = R.nativeReturnSpecObservationSize spec
  horizon = R.nativeReturnSpecHorizon spec
  actions = case R.nativeReturnSpecDomain spec of
    R.NativeUnmaskedDiscrete n -> n
    R.NativeMaskedDiscrete n -> n
    R.NativeContinuous {} -> 0

arsConfig :: R.NativeReturnReferenceSpec -> Ars.ArsTrainConfig
arsConfig spec =
  Ars.defaultArsTrainConfig
    { Ars.arsObsSize = R.nativeReturnSpecObservationSize spec
    , Ars.arsActionCount = case R.nativeReturnSpecDomain spec of
        R.NativeUnmaskedDiscrete n -> n
        R.NativeMaskedDiscrete n -> n
        R.NativeContinuous {} -> 0
    , Ars.arsMaxEpisodeSteps = R.nativeReturnSpecHorizon spec
    }

actualDelegate
  :: MlpDevice
  -> R.NativeReturnReferenceSpec
  -> E.NativeNeuralPolicy
  -> Int
  -> IO (Either Text [Common.EvaluationEpisodeResult])
actualDelegate device spec policy count = case policy of
  E.NativeContinuous config p -> case Sim.lookupContinuousEnvironmentByName (R.nativeReturnSpecEnvironment spec) of
    Nothing -> pure (Left "missing actual continuous fixture environment")
    Just environment -> C.evaluateContinuousPolicyOnDeviceWithEnvironment device environment config p count
  E.NativeOnPolicy config p ->
    discrete
      (\environment -> P.evaluateOnPolicyOnDeviceWithEnvironment device environment config p count)
  E.NativeDqn config p -> discrete (\environment -> D.evaluateDqnPolicyWithEnvironment device environment config p count)
  E.NativeQrDqn config p ->
    discrete
      (\environment -> Q.evaluateQrDqnPolicyOnDeviceWithEnvironment device environment config p count)
 where
  discrete run = case Sim.lookupSimulatedEnvironmentByName (R.nativeReturnSpecEnvironment spec) of
    Nothing -> pure (Left "missing actual discrete fixture environment")
    Just environment -> run environment

keyed :: [Common.EvaluationEpisodeResult] -> [R.NativeReturnEpisode]
keyed episodes =
  [ R.NativeReturnEpisode
      index
      (Common.evaluationEpisodeReward e)
      (Common.evaluationEpisodeSteps e)
      (Common.evaluationEpisodeTerminated e)
  | (index, e) <- zip [0 ..] episodes
  ]

failureReason :: E.RawNativeReturnEvaluation -> Text
failureReason raw = case E.nativeEvaluationStatus raw of
  E.NativeEvaluationRejected err -> err
  E.NativeEvaluationFailed _ _ err -> err
  E.NativeEvaluationComplete -> ""

failsWith :: Text -> E.RawNativeReturnEvaluation -> IO ()
failsWith fragment raw =
  assertBool
    (show (E.nativeEvaluationStatus raw))
    (not (Text.null (failureReason raw)) && fragment `Text.isInfixOf` failureReason raw)

complete :: E.RawNativeReturnEvaluation -> IO ()
complete raw = do
  E.nativeEvaluationStatus raw @?= E.NativeEvaluationComplete
  fmap R.nativeReturnEpisodeId (E.nativeEvaluationEpisodes raw) @?= [0 .. 19]
  E.nativeEvaluationWork raw
    @?= E.NativeCompleteWork
      (sum (fmap (toInteger . R.nativeReturnEpisodeSteps) (E.nativeEvaluationEpisodes raw)))

compareDelegate :: Text -> Text -> IO ()
compareDelegate algorithm environment = do
  spec <- specFor algorithm environment
  policy <- right (policyFor spec)
  expected <- actualDelegate pureReferenceMlpDevice spec policy 20 >>= right
  actual <- E.evaluateNativeNeuralReturnPolicy pureReferenceMlpDevice spec policy
  complete actual
  E.nativeEvaluationEpisodes actual @?= keyed expected
  E.nativeEvaluationObservedForwardCalls actual
    @?= sum (fmap (toInteger . Common.evaluationEpisodeSteps) expected)
  let wanted = map castDoubleToWord64 (mlpParamsToFlat (paramsOf policy))
  forM_ (E.nativeEvaluationForwards actual) $ \observed ->
    map castDoubleToWord64 (mlpParamsToFlat (E.nativeForwardParameters observed)) @?= wanted

-- Each lazy failure happens during the second real simulator case, after an
-- independently completed first case. Inspection below must itself stay safe.
assertLazyCallbackFailure :: Text -> Either Text MlpForward -> IO ()
assertLazyCallbackFailure marker lazyResult = do
  spec <- specFor "DQN" "cartpole"
  policy <- right (policyFor spec)
  first <- actualDelegate pureReferenceMlpDevice spec policy 1 >>= right
  firstSteps <- case first of
    [episode] -> pure (Common.evaluationEpisodeSteps episode)
    _ -> assertFailure "actual lazy-failure baseline malformed" >> fail "unreachable"
  calls <- newIORef (0 :: Int)
  let device =
        pureReferenceMlpDevice
          { mlpdForward = \p x -> do
              modifyIORef' calls (+ 1)
              count <- readIORef calls
              if count == firstSteps + 2 then pure lazyResult else mlpdForward pureReferenceMlpDevice p x
          }
  actual <- E.evaluateNativeNeuralReturnPolicy device spec policy
  case E.nativeEvaluationStatus actual of
    E.NativeEvaluationFailed 1 E.NativeSynchronousException message ->
      assertBool "actual lazy exception retained" (marker `Text.isInfixOf` message)
    status -> assertFailure ("unexpected lazy failure status: " <> show status)
  E.nativeEvaluationEpisodes actual @?= keyed first
  E.nativeEvaluationWork actual @?= E.NativeFailedWork (toInteger firstSteps) Nothing
  E.nativeEvaluationFailedReturnedEpisodes actual @?= Nothing
  E.nativeEvaluationObservedForwardCalls actual @?= toInteger (firstSteps + 2)
  readIORef calls >>= (@?= firstSteps + 2)
  case reverse (E.nativeEvaluationForwards actual) of
    event : _ -> do
      E.nativeForwardCaseIndex event @?= 1
      E.nativeForwardCallIndex event @?= 1
      case E.nativeForwardOutcome event of
        E.NativeForwardException message ->
          assertBool "raw exception is safely inspectable" (marker `Text.isInfixOf` message)
        _ -> assertFailure "lazy returned data escaped as a successful callback"
    [] -> assertFailure "lazy failed callback was not retained"

nativeReturnEvaluationTests :: TestTree
nativeReturnEvaluationTests =
  testGroup
    "native learned-policy fixed return evaluation"
    [ testCase "all thirty eight exact specs have the correct raw family and fixed context" $ do
        specs <- right R.allCanonicalNativeReturnSpecs
        length specs @?= 38
        forM_ specs $ \spec ->
          if R.nativeReturnSpecAlgorithm spec == "ARS"
            then do
              let config = arsConfig spec
                  theta = VU.replicate (Ars.arsObsSize config * Ars.arsActionCount config) 0
              complete (E.evaluateNativeArsReturnPolicy spec config theta)
            else
              right (policyFor spec) >>= \policy -> E.validateNativeNeuralReturnContext spec policy @?= Right ()
    , testCase "on-policy actual twenty cases and parameter callbacks equal the public selected evaluator" $ do
        compareDelegate "PPO" "cartpole"
        compareDelegate "MaskablePPO" "key-door-grid"
    , testCase "DQN actual twenty cases equal the reviewed checked public evaluator" $ do
        compareDelegate "DQN" "cartpole"
        compareDelegate "DQN" "key-door-grid"
    , testCase "QR actual twenty quantile cases equal the public selected evaluator" $ do
        compareDelegate "QR-DQN" "cartpole"
        compareDelegate "QR-DQN" "key-door-grid"
    , testCase "continuous actual twenty tanh cases equal the public selected evaluator" $
        compareDelegate "SAC" "pendulum"
    , testCase "ARS zero theta actual twenty cases equal the fixed native constant reference" $ do
        spec <- specFor "ARS" "cartpole"
        let config = arsConfig spec
            theta = VU.replicate (Ars.arsObsSize config * Ars.arsActionCount config) 0
            actual = E.evaluateNativeArsReturnPolicy spec config theta
        expected <-
          right
            ( R.evaluateDiscreteReference
                Sim.cartPoleEnvironment
                20
                (R.nativeReturnSpecHorizon spec)
                (R.ConstantDiscrete 0)
            )
        complete actual
        E.nativeEvaluationEpisodes actual @?= R.nativeReturnObservedEpisodes expected
        E.nativeEvaluationObservedForwardCalls actual @?= 0
    , testCase "case IDs and first observations prove every case uses the actual fresh reset" $ do
        spec <- specFor "PPO" "cartpole"
        policy <- right (policyFor spec)
        actual <- E.evaluateNativeNeuralReturnPolicy pureReferenceMlpDevice spec policy
        complete actual
        let groups =
              groupBy
                (\a b -> E.nativeForwardCaseIndex a == E.nativeForwardCaseIndex b)
                (E.nativeEvaluationForwards actual)
            initial =
              Sim.renderObservation
                (Sim.envRenderFrame Sim.cartPoleEnvironment (Sim.envInitial Sim.cartPoleEnvironment))
        length groups @?= 20
        forM_ (zip [0 .. 19] groups) $ \(index, observed) -> case observed of
          [] -> assertFailure "empty actual callback group"
          first : _ -> do
            E.nativeForwardCaseIndex first @?= index
            VU.toList (E.nativeForwardInput first) @?= initial
            fmap E.nativeForwardCallIndex observed @?= [0 .. toInteger (length observed) - 1]
    , testCase "supplied output parameters change the actual next simulator observation" $ do
        spec <- specFor "PPO" "cartpole"
        policy <- right (policyFor spec)
        let left = mapParams (\p -> p {paramB2 = VU.fromList [10, -10, 0]}) policy
            rightward = mapParams (\p -> p {paramB2 = VU.fromList [-10, 10, 0]}) policy
        a <- E.evaluateNativeNeuralReturnPolicy pureReferenceMlpDevice spec left
        b <- E.evaluateNativeNeuralReturnPolicy pureReferenceMlpDevice spec rightward
        let observations raw =
              fmap E.nativeForwardInput [f | f <- E.nativeEvaluationForwards raw, E.nativeForwardCaseIndex f == 0]
            next action =
              VU.fromList
                ( Sim.renderObservation
                    ( Sim.envRenderFrame
                        Sim.cartPoleEnvironment
                        ( Sim.simStepState
                            (Sim.envStep Sim.cartPoleEnvironment (Sim.envInitial Sim.cartPoleEnvironment) action)
                        )
                    )
                )
        case (observations a, observations b) of
          (_ : a1 : _, _ : b1 : _) -> do
            a1 @?= next 0
            b1 @?= next 1
            assertBool "actual states differ" (a1 /= b1)
          _ -> assertFailure "actual policy trajectory has no second forward"
    , testCase "wrong family or on-policy variant rejects before any selected callback" $ do
        spec <- specFor "PPO" "cartpole"
        other <- specFor "DQN" "cartpole" >>= right . policyFor
        actual <- E.evaluateNativeNeuralReturnPolicy pureReferenceMlpDevice spec other
        failsWith "family differs" actual
        E.nativeEvaluationWork actual @?= E.NativeRejectedWork
        E.nativeEvaluationForwards actual @?= []
        policy <- right (policyFor spec)
        case policy of
          E.NativeOnPolicy c p -> do
            wrong <-
              E.evaluateNativeNeuralReturnPolicy
                pureReferenceMlpDevice
                spec
                (E.NativeOnPolicy (c {P.ppoVariant = P.VariantTRPO}) p)
            failsWith "variant differs" wrong
            E.nativeEvaluationForwards wrong @?= []
          _ -> assertFailure "wrong fixture family"
    , testCase "wrong horizon observation and action context rejects before forwards" $ do
        spec <- specFor "PPO" "cartpole"
        policy <- right (policyFor spec)
        case policy of
          E.NativeOnPolicy c p -> forM_
            [ c {P.ppoMaxEpisodeSteps = P.ppoMaxEpisodeSteps c + 1}
            , c {P.ppoObsSize = P.ppoObsSize c + 1}
            , c {P.ppoActionCount = P.ppoActionCount c + 1}
            ]
            $ \bad -> do
              actual <- E.evaluateNativeNeuralReturnPolicy pureReferenceMlpDevice spec (E.NativeOnPolicy bad p)
              failsWith "dimensions differ" actual
              E.nativeEvaluationForwards actual @?= []
          _ -> assertFailure "wrong fixture family"
    , testCase "malformed nonfinite and Float32-overflow tensors fail checked guards without callbacks" $ do
        forM_ [("PPO", "cartpole"), ("DQN", "cartpole"), ("QR-DQN", "cartpole"), ("SAC", "pendulum")] $ \(a, e) -> do
          spec <- specFor a e
          policy <- right (policyFor spec)
          forM_
            [ \p -> p {paramW1 = VU.empty}
            , \p -> p {paramW1 = VU.map (const (0 / 0)) (paramW1 p)}
            , \p -> p {paramW1 = VU.map (const 1e300) (paramW1 p)}
            ]
            $ \bad -> do
              actual <- E.evaluateNativeNeuralReturnPolicy pureReferenceMlpDevice spec (mapParams bad policy)
              failsWith "parameters" actual
              E.nativeEvaluationForwards actual @?= []
    , testCase "wrong-width actual output is retained in failed callback data" $ do
        spec <- specFor "DQN" "cartpole"
        policy <- right (policyFor spec)
        let device =
              pureReferenceMlpDevice
                { mlpdForward = \p x -> fmap (fmap (\f -> f {forwardOutput = VU.empty})) (mlpdForward pureReferenceMlpDevice p x)
                }
        actual <- E.evaluateNativeNeuralReturnPolicy device spec policy
        failsWith "wrong shape" actual
        E.nativeEvaluationObservedForwardCalls actual @?= 1
        case E.nativeEvaluationForwards actual of
          [event] -> E.nativeForwardOutcome event @?= E.NativeForwardReturned (Right VU.empty)
          _ -> assertFailure "actual wrong-width callback missing"
    , testCase "nonfinite and Float32-overflow outputs retain raw failing values" $ do
        spec <- specFor "DQN" "cartpole"
        policy <- right (policyFor spec)
        forM_ [0 / 0, 1e300] $ \value -> do
          let device =
                pureReferenceMlpDevice
                  { mlpdForward = \p x ->
                      fmap
                        (fmap (\f -> f {forwardOutput = VU.replicate 2 value}))
                        (mlpdForward pureReferenceMlpDevice p x)
                  }
          actual <- E.evaluateNativeNeuralReturnPolicy device spec policy
          failsWith "not finite Float32" actual
          case E.nativeEvaluationForwards actual of
            [event] -> case E.nativeForwardOutcome event of
              E.NativeForwardReturned (Right output) -> map castDoubleToWord64 (VU.toList output) @?= replicate 2 (castDoubleToWord64 value)
              _ -> assertFailure "raw returned output missing"
            _ -> assertFailure "actual output event missing"
    , testCase "genuine mid-case delegated failure retains exact prefix and Unknown partial transitions" $ do
        spec <- specFor "PPO" "cartpole"
        policy <- right (policyFor spec)
        first <- actualDelegate pureReferenceMlpDevice spec policy 1 >>= right
        firstSteps <- case first of
          [episode] -> pure (Common.evaluationEpisodeSteps episode)
          _ -> assertFailure "actual one-case baseline malformed" >> fail "unreachable"
        calls <- newIORef (0 :: Int)
        let device =
              pureReferenceMlpDevice
                { mlpdForward = \p x -> do
                    modifyIORef' calls (+ 1)
                    n <- readIORef calls
                    if n == firstSteps + 2
                      then pure (Left "actual second-case failure")
                      else mlpdForward pureReferenceMlpDevice p x
                }
        actual <- E.evaluateNativeNeuralReturnPolicy device spec policy
        E.nativeEvaluationStatus actual
          @?= E.NativeEvaluationFailed
            1
            E.NativeDelegatedLeft
            "on-policy device forward kernel failed during evaluation: actual second-case failure"
        E.nativeEvaluationEpisodes actual @?= keyed first
        E.nativeEvaluationWork actual @?= E.NativeFailedWork (toInteger firstSteps) Nothing
        E.nativeEvaluationObservedForwardCalls actual @?= toInteger (firstSteps + 2)
        length [f | f <- E.nativeEvaluationForwards actual, E.nativeForwardCaseIndex f == 1] @?= 2
    , testCase "synchronous callback exceptions retain actual failure without invented cases" $ do
        spec <- specFor "DQN" "cartpole"
        policy <- right (policyFor spec)
        let device =
              pureReferenceMlpDevice
                { mlpdForward = \_ _ -> throwIO (userError "actual synchronous callback throw")
                }
        actual <- E.evaluateNativeNeuralReturnPolicy device spec policy
        failsWith "actual synchronous callback throw" actual
        E.nativeEvaluationEpisodes actual @?= []
        E.nativeEvaluationWork actual @?= E.NativeFailedWork 0 Nothing
        case E.nativeEvaluationForwards actual of
          [f] -> case E.nativeForwardOutcome f of
            E.NativeForwardException err ->
              assertBool "actual exception retained" ("actual synchronous callback throw" `Text.isInfixOf` err)
            _ -> assertFailure "exception callback falsely labeled returned"
          _ -> assertFailure "exception callback missing"
    , testCase "asynchronous callback cancellation propagates instead of minting failure results" $ do
        spec <- specFor "DQN" "cartpole"
        policy <- right (policyFor spec)
        let device = pureReferenceMlpDevice {mlpdForward = \_ _ -> throwIO ThreadKilled}
        result <-
          try (E.evaluateNativeNeuralReturnPolicy device spec policy)
            :: IO (Either AsyncException E.RawNativeReturnEvaluation)
        case result of
          Left ThreadKilled -> pure ()
          _ -> assertFailure "async cancellation was swallowed or returned as data"
    , testCase "forward attempts are not substituted for failed simulator work" $ do
        spec <- specFor "QR-DQN" "cartpole"
        policy <- right (policyFor spec)
        actual <-
          E.evaluateNativeNeuralReturnPolicy
            (pureReferenceMlpDevice {mlpdForward = \_ _ -> pure (Left "first actual forward failure")})
            spec
            policy
        E.nativeEvaluationObservedForwardCalls actual @?= 1
        E.nativeEvaluationWork actual @?= E.NativeFailedWork 0 Nothing
        E.nativeEvaluationEpisodes actual @?= []
    , testCase "fixed-case scoring never probes witnesses gradients or backward devices" $ do
        spec <- specFor "PPO" "cartpole"
        policy <- right (policyFor spec)
        unexpected <- newIORef (0 :: Int)
        let noCall :: IO (Either Text value)
            noCall = modifyIORef' unexpected (+ 1) >> pure (Left "unexpected nonforward callback")
            device =
              pureReferenceMlpDevice
                { mlpdBackward = \_ _ _ -> noCall
                , mlpdBatchGradient = \_ _ -> noCall
                , mlpdInputGradientBatch = \_ _ -> noCall
                , mlpdForwardBatch = \_ _ -> noCall
                , mlpdExecutionWitness = noCall
                }
        actual <- E.evaluateNativeNeuralReturnPolicy device spec policy
        complete actual
        readIORef unexpected >>= (@?= 0)
    , testCase "ARS finite legal scores below the old sentinel still choose a genuinely legal action" $ do
        let env = Sim.keyDoorGridEnvironment
            state = Sim.envInitial env
            obs = VU.fromList (Sim.renderObservation (Sim.envRenderFrame env state))
            count = Sim.envActionCount env
            width = Sim.envObservationSize env
            theta = VU.replicate (count * width) (-1e14)
            mask = Sim.envActionMask env <*> Just state
        flags <- maybe (assertFailure "actual KeyDoor mask absent" >> fail "unreachable") pure mask
        assertBool "fixture has an illegal competitor" (not (and flags))
        assertBool "legal dot scores really below finite sentinel" (VU.sum (VU.map (* (-1e14)) obs) < -1e12)
        chosen <- right (E.nativeArsLegalAction count width theta obs mask)
        let legalIndices = [i | (i, True) <- zip [0 ..] flags]
        assertBool "actual chosen index belongs to the actual legal set" (chosen `elem` legalIndices)
        case legalIndices of
          first : _ -> chosen @?= first
          [] -> assertFailure "actual fixture has no legal action"
    , testCase "ARS ties keep the lowest original legal action index" $ do
        let env = Sim.keyDoorGridEnvironment
            state = Sim.envInitial env
            obs = VU.fromList (Sim.renderObservation (Sim.envRenderFrame env state))
            count = Sim.envActionCount env
            width = Sim.envObservationSize env
            mask = Sim.envActionMask env <*> Just state
        flags <- maybe (assertFailure "actual mask absent" >> fail "unreachable") pure mask
        case [i | (i, True) <- zip [0 ..] flags] of
          first : _ -> E.nativeArsLegalAction count width (VU.replicate (count * width) 0) obs mask @?= Right first
          [] -> assertFailure "actual tie fixture has no legal action"
    , testCase "ARS rejects wrong-width and all-illegal masks before fallback" $ do
        let count = Sim.envActionCount Sim.keyDoorGridEnvironment
            width = Sim.envObservationSize Sim.keyDoorGridEnvironment
            obs =
              VU.fromList
                ( Sim.renderObservation
                    (Sim.envRenderFrame Sim.keyDoorGridEnvironment (Sim.envInitial Sim.keyDoorGridEnvironment))
                )
            theta = VU.replicate (count * width) 0
        forM_ [[], [True], replicate count False] $ \mask -> case E.nativeArsLegalAction count width theta obs (Just mask) of
          Left err -> assertBool "specific malformed mask" ("mask" `Text.isInfixOf` err)
          Right _ -> assertFailure "invalid ARS mask accepted"
    , testCase "ARS host finite Double weights beyond Float32 remain valid when legal dots stay finite" $ do
        spec <- specFor "ARS" "cartpole"
        let config = arsConfig spec
            theta = VU.replicate (Ars.arsObsSize config * Ars.arsActionCount config) 1e200
            actual = E.evaluateNativeArsReturnPolicy spec config theta
        complete actual
        E.nativeEvaluationForwards actual @?= []
        E.nativeArsLegalAction 2 4 theta (VU.replicate 4 1e-200) Nothing @?= Right 0
    , testCase "ARS malformed nonfinite overflow and incompatible contexts reject specifically" $ do
        spec <- specFor "ARS" "cartpole"
        let config = arsConfig spec; width = Ars.arsObsSize config; count = Ars.arsActionCount config
        forM_ [VU.empty, VU.replicate (width * count) (0 / 0)] $ \theta ->
          failsWith "parameter tensor" (E.evaluateNativeArsReturnPolicy spec config theta)
        case E.nativeArsLegalAction 2 4 (VU.replicate 8 1e308) (VU.replicate 4 1) Nothing of
          Left err -> assertBool "actual score overflow reason" ("score is nonfinite" `Text.isInfixOf` err)
          Right _ -> assertFailure "actual overflowing linear score accepted"
        E.nativeArsLegalAction maxBound 2 VU.empty VU.empty Nothing
          @?= Left "native ARS linear parameter dimensions are invalid"
        failsWith
          "dimensions differ"
          ( E.evaluateNativeArsReturnPolicy
              spec
              (config {Ars.arsObsSize = width + 1})
              (VU.replicate (width * count) 0)
          )
        case E.nativeArsLegalAction
          count
          width
          (VU.replicate (width * count) 0)
          (VU.replicate width (0 / 0))
          Nothing of
          Left err -> assertBool "actual bad observation reason" ("observation are nonfinite" `Text.isInfixOf` err)
          Right _ -> assertFailure "nonfinite host observation accepted"
    , testCase "complete work is actual returned steps and raw data contains no learning verdict" $ do
        spec <- specFor "PPO" "cartpole"
        policy <- right (policyFor spec)
        actual <- E.evaluateNativeNeuralReturnPolicy pureReferenceMlpDevice spec policy
        complete actual
        E.nativeEvaluationPolicy actual @?= E.NativeNeuralEvaluation policy
        E.nativeEvaluationFailedReturnedEpisodes actual @?= Nothing
        assertBool
          "not a target-derived fixture"
          (all ((> 0) . R.nativeReturnEpisodeSteps) (E.nativeEvaluationEpisodes actual))
    , testCase "lazy callback outer Either is captured with exact completed prefix and Unknown work" $
        assertLazyCallbackFailure "lazy outer callback Either" (error "lazy outer callback Either")
    , testCase "lazy callback Left text is captured before raw failure data is exposed" $
        assertLazyCallbackFailure "lazy callback Left text" (Left (error "lazy callback Left text"))
    , testCase "lazy callback Right forward is captured before raw output data is exposed" $
        assertLazyCallbackFailure
          "lazy callback Right forward"
          (Right (error "lazy callback Right forward"))
    ]
