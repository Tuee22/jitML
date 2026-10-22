{-# LANGUAGE OverloadedStrings #-}

module OffPolicyEvaluation (offPolicyEvaluationTests) where

import Control.Exception (IOException, throwIO, try)
import Control.Monad (forM_, void)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU
import System.Random qualified as Random
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.Numerics.Mlp qualified as Mlp
import JitML.Numerics.MlpDevice (MlpDevice (..), pureReferenceMlpDevice)
import JitML.RL.Algorithms.Common qualified as Common
import JitML.RL.Algorithms.ContinuousTrainer qualified as Continuous
import JitML.RL.Algorithms.HerTrainer qualified as Her
import JitML.RL.Algorithms.QrDqnTrainer qualified as Qr
import JitML.RL.Simulator qualified as Sim

-- Offline numerical/error-boundary controls. Injected pure/hostile callbacks
-- are explicit fixtures; this family makes no hardware or convergence claim.
offPolicyEvaluationTests :: TestTree
offPolicyEvaluationTests =
  testGroup
    "off-policy selected-device final evaluation"
    [ testGroup
        "QR-DQN"
        [ testCase "quantile means use every injected decision and exact episode resets" $ do
            inputs <- newIORef []
            let device = recordingDevice inputs (outputDevice [10, -10, 1, 1])
            actual <- qrEval device discrete qrConfig qrParams 2 >>= expectRight
            actual @?= replicate 2 (Common.EvaluationEpisodeResult 2 2 True)
            Qr.evaluateQrDqnPolicyWithEnvironment (Sim.SomeSimulatedEnvironment discrete) qrConfig qrParams 2
              @?= replicate 2 (Common.EvaluationEpisodeResult 0 2 True)
            readIORef inputs >>= (@?= [[1, 0], [1, 1], [1, 0], [1, 1]])
        , testCase "explicit reference device matches the untouched pure quantile oracle" $ do
            let params = Qr.initialQrDqnParams qrConfig
            actual <- qrEval pureReferenceMlpDevice discrete qrConfig params 3 >>= expectRight
            actual
              @?= Qr.evaluateQrDqnPolicyWithEnvironment (Sim.SomeSimulatedEnvironment discrete) qrConfig params 3
        , testCase "leftmost ties masks terminal reward and horizon retain their semantics" $ do
            tied <- qrEval (outputDevice [1, 1, 1, 1]) discrete qrConfig qrParams 1 >>= expectRight
            tied @?= [Common.EvaluationEpisodeResult 0 2 True]
            masked <-
              qrEval
                (outputDevice [5, 5, 0, 0])
                (discrete {Sim.envActionMask = Just (const [False, True])})
                qrConfig
                qrParams
                1
                >>= expectRight
            masked @?= [Common.EvaluationEpisodeResult 2 2 True]
            terminal <-
              qrEval
                (outputDevice [0, 0, 1, 1])
                (discrete {Sim.envStep = \state _ -> Sim.SimStep (state + 1) (-7) True})
                qrConfig
                qrParams
                1
                >>= expectRight
            terminal @?= [Common.EvaluationEpisodeResult (-7) 1 True]
            horizon <-
              qrEval
                (outputDevice [0, 0, 1, 1])
                (discrete {Sim.envStep = \state action -> Sim.SimStep (state + 1) (fromIntegral action) False})
                qrConfig
                qrParams
                1
                >>= expectRight
            horizon @?= [Common.EvaluationEpisodeResult 3 3 False]
        , testCase "a mid-episode device Left rejects the partial QR cohort" $ do
            calls <- newIORef (0 :: Int)
            actual <- qrEval (failSecond calls) discrete qrConfig qrParams 2
            expectLeft "fixture forward failure" actual
            readIORef calls >>= (@?= 2)
        , testCase "wrong-width nonfinite and ABI-overflow QR outputs fail before stepping" $
            forM_ [[], [0], [0, 0, 0], [0, 0, 0, 0, 0], [0, 0, 0, 0 / 0], [0, 0, 0, 1 / 0], [0, 0, 0, 1e300]] $ \output -> do
              calls <- newIORef (0 :: Int)
              actual <- qrEval (countingDevice calls (outputDevice output)) discrete qrConfig qrParams 1
              expectLeft "output" actual
              readIORef calls >>= (@?= 1)
        , testCase "malformed QR inputs fail before the device and finite Float32 rounding is allowed" $ do
            calls <- newIORef (0 :: Int)
            let device = countingDevice calls pureReferenceMlpDevice
            forM_
              [ qrParams {Mlp.paramB2 = VU.singleton 0}
              , qrParams {Mlp.paramB1 = VU.fromList [0 / 0, 0]}
              , qrParams {Mlp.paramB1 = VU.fromList [1e300, 0]}
              ]
              $ \params ->
                qrEval device discrete qrConfig params 1 >>= expectLeft "parameters"
            qrEval device discrete (qrConfig {Qr.qrNumQuantiles = 0}) qrParams 1 >>= expectLeft "configuration"
            qrEval device discrete (qrConfig {Qr.qrActionCount = maxBound}) qrParams 1
              >>= expectLeft "configuration"
            qrEval device discrete qrConfig qrParams 0 >>= expectLeft "configuration"
            qrEval
              device
              (discrete {Sim.envRenderFrame = const (Sim.RenderFrame [0] "bad")})
              qrConfig
              qrParams
              1
              >>= expectLeft "observation"
            qrEval
              device
              (discrete {Sim.envRenderFrame = const (Sim.RenderFrame [1 / 0, 0] "bad")})
              qrConfig
              qrParams
              1
              >>= expectLeft "observation"
            qrEval device (discrete {Sim.envActionMask = Just (const [False, False])}) qrConfig qrParams 1
              >>= expectLeft "mask"
            readIORef calls >>= (@?= 0)
            let rounded = qrParams {Mlp.paramB1 = VU.fromList [0.1, 1e-300]}
            qrEval device discrete qrConfig rounded 1 >>= expectRight >> pure ()
        , testCase "QR device IO exceptions propagate" $
            assertIOException (qrEval ioFailure discrete qrConfig qrParams 1)
        ]
    , testGroup
        "continuous"
        [ testCase "the injected actor output determines action squash and resets" $ do
            inputs <- newIORef []
            let device = recordingDevice inputs (outputDevice [0.5])
                reward = 2 * (2 * tanh 0.5)
            actual <- continuousEval device continuous continuousConfig continuousParams 2 >>= expectRight
            actual @?= replicate 2 (Common.EvaluationEpisodeResult reward 2 True)
            Continuous.evaluateContinuousPolicyWithEnvironment
              (Sim.SomeContinuousEnvironment continuous)
              continuousConfig
              continuousParams
              2
              @?= replicate 2 (Common.EvaluationEpisodeResult 0 2 True)
            readIORef inputs >>= (@?= [[1, 0], [1, 1], [1, 0], [1, 1]])
        , testCase "all five continuous variants retain the explicit pure actor oracle"
            $ forM_
              [ Continuous.VariantDDPG
              , Continuous.VariantTD3
              , Continuous.VariantSAC
              , Continuous.VariantCrossQ
              , Continuous.VariantTQC
              ]
            $ \variant -> do
              let config = continuousConfig {Continuous.ctVariant = variant}
                  params = Continuous.initialContinuousActor config
              actual <- continuousEval pureReferenceMlpDevice continuous config params 2 >>= expectRight
              actual
                @?= Continuous.evaluateContinuousPolicyWithEnvironment
                  (Sim.SomeContinuousEnvironment continuous)
                  config
                  params
                  2
        , testCase "continuous terminal reward and horizon remain separate" $ do
            terminal <-
              continuousEval
                (outputDevice [0])
                (continuous {Sim.cEnvStep = \state _ -> Sim.ContinuousSimStep (state + 1) (-5) True})
                continuousConfig
                continuousParams
                1
                >>= expectRight
            terminal @?= [Common.EvaluationEpisodeResult (-5) 1 True]
            horizon <-
              continuousEval
                (outputDevice [0])
                (continuous {Sim.cEnvStep = \state _ -> Sim.ContinuousSimStep (state + 1) 2 False})
                continuousConfig
                continuousParams
                1
                >>= expectRight
            horizon @?= [Common.EvaluationEpisodeResult 6 3 False]
        , testCase "a device Left rejects partial continuous results" $ do
            calls <- newIORef (0 :: Int)
            continuousEval (failSecond calls) continuous continuousConfig continuousParams 2
              >>= expectLeft "fixture forward failure"
            readIORef calls >>= (@?= 2)
        , testCase "continuous wrong-width nonfinite outputs and rewards fail closed" $ do
            forM_ [[], [0, 1], [0 / 0], [1 / 0], [1e300]] $ \output ->
              continuousEval (outputDevice output) continuous continuousConfig continuousParams 1
                >>= expectLeft "output"
            continuousEval
              (outputDevice [0])
              (continuous {Sim.cEnvStep = \state _ -> Sim.ContinuousSimStep (state + 1) (0 / 0) True})
              continuousConfig
              continuousParams
              1
              >>= expectLeft "reward"
        , testCase "continuous invalid parameters bounds and observations never call the device" $ do
            calls <- newIORef (0 :: Int)
            let device = countingDevice calls pureReferenceMlpDevice
            continuousEval device continuous continuousConfig (continuousParams {Mlp.paramB2 = VU.empty}) 1
              >>= expectLeft "parameters"
            forM_ [0 / 0, 1 / 0, 1e300] $ \bad ->
              continuousEval
                device
                continuous
                continuousConfig
                (continuousParams {Mlp.paramB2 = VU.singleton bad})
                1
                >>= expectLeft "parameters"
            continuousEval device continuous (continuousConfig {Continuous.ctActionLow = 2}) continuousParams 1
              >>= expectLeft "configuration"
            continuousEval
              device
              (continuous {Sim.cEnvObservation = const [1]})
              continuousConfig
              continuousParams
              1
              >>= expectLeft "observation"
            continuousEval
              device
              (continuous {Sim.cEnvObservation = const [1, 1e300]})
              continuousConfig
              continuousParams
              1
              >>= expectLeft "observation"
            readIORef calls >>= (@?= 0)
            continuousEval
              device
              continuous
              continuousConfig
              (continuousParams {Mlp.paramB1 = VU.fromList [0.1, 1e-300]})
              1
              >>= expectRight
              >> pure ()
        , testCase "continuous device IO exceptions propagate" $
            assertIOException (continuousEval ioFailure continuous continuousConfig continuousParams 1)
        ]
    , testGroup
        "HER"
        [ testCase "actual greedy device decisions preserve complete sequential goal RNG outcomes" $
            forM_ [0, 1, 42, 123] $ \seed -> do
              inputs <- newIORef []
              let device = recordingDevice inputs pureReferenceMlpDevice
                  expected = Her.evaluateHerGreedy herConfig herParams 20 seed
              actual <- Her.evaluateHerGreedyOnDevice device herConfig herParams 20 seed >>= expectRight
              actual @?= expected
              observations <- readIORef inputs
              length observations @?= sum [steps | (_, _, steps) <- expected]
              assertBool
                "fixture has no two-step goal to exercise RNG progression"
                (any (\(_, _, steps) -> steps > 1) actual)
              assertBool "goal-conditioned input was lost" (all ((== 4) . length) observations)
              let episodeSteps = [steps | (_, _, steps) <- expected]
                  starts = init (scanl (+) 0 episodeSteps)
                  goals = [drop 2 (observations !! index) | index <- starts]
              goals @?= twoBitGoalSchedule seed episodeSteps
        , testCase "hostile device logits drive HER instead of a pure fallback" $ do
            let constant = herParams {Mlp.paramW2 = VU.replicate 4 0, Mlp.paramB2 = VU.fromList [2, -2]}
                expected = Her.evaluateHerGreedy herConfig constant 20 42
            actual <-
              Her.evaluateHerGreedyOnDevice (outputDevice [2, -2]) herConfig herParams 20 42 >>= expectRight
            actual @?= expected
            assertBool
              "hostile device did not change the evaluated policy"
              (actual /= Her.evaluateHerGreedy herConfig herParams 20 42)
        , testCase "HER exact leftmost ties and one-bit terminal boundary use one decision" $ do
            let config = herConfig {Her.herNumBits = 1}
                params = Her.initialHerParams config
            calls <- newIORef (0 :: Int)
            actual <-
              Her.evaluateHerGreedyOnDevice (countingDevice calls (outputDevice [0])) config params 3 42
                >>= expectRight
            actual @?= replicate 3 (True, 0, 1)
            readIORef calls >>= (@?= 3)
        , testCase "a failed HER device call cannot return a partial goal cohort" $ do
            calls <- newIORef (0 :: Int)
            Her.evaluateHerGreedyOnDevice (failSecond calls) herConfig herParams 20 42
              >>= expectLeft "fixture forward failure"
            readIORef calls >>= (@?= 2)
        , testCase "HER malformed and nonfinite output is rejected at the forward boundary" $
            forM_ [[], [0], [0, 0, 0], [0, 0 / 0], [0, 1 / 0], [0, 1e300]] $ \output ->
              Her.evaluateHerGreedyOnDevice (outputDevice output) herConfig herParams 1 42 >>= expectLeft "output"
        , testCase "HER dimensions and malformed or overflowing parameters fail before device calls" $ do
            calls <- newIORef (0 :: Int)
            let device = countingDevice calls pureReferenceMlpDevice
            Her.evaluateHerGreedyOnDevice device (herConfig {Her.herNumBits = 0}) herParams 1 42
              >>= expectLeft "dimensions"
            Her.evaluateHerGreedyOnDevice device (herConfig {Her.herNumBits = maxBound}) herParams 1 42
              >>= expectLeft "dimensions"
            Her.evaluateHerGreedyOnDevice device herConfig herParams 0 42 >>= expectLeft "episode"
            forM_
              [ herParams {Mlp.paramB1 = VU.empty}
              , herParams {Mlp.paramB2 = VU.fromList [0, 1e300]}
              , herParams {Mlp.paramB2 = VU.fromList [0, 0 / 0]}
              ]
              $ \params ->
                Her.evaluateHerGreedyOnDevice device herConfig params 1 42 >>= expectLeft "parameters"
            readIORef calls >>= (@?= 0)
            Her.evaluateHerGreedyOnDevice
              device
              herConfig
              (herParams {Mlp.paramB1 = VU.fromList [0.1, 1e-300]})
              1
              42
              >>= expectRight
              >> pure ()
        , testCase "HER device IO exceptions propagate" $
            assertIOException (Her.evaluateHerGreedyOnDevice ioFailure herConfig herParams 1 42)
        ]
    , testCase
        "QR-DQN excludes masked slots even below the former finite sentinel and keeps original tie indices"
        $ do
          let environment = discrete {Sim.envActionCount = 3, Sim.envActionMask = Just (const [False, True, True])}
              config = qrConfig {Qr.qrActionCount = 3}
              params = zeroParams (Mlp.MlpShape 2 2 6)
          actual <-
            qrEval (outputDevice [1, 1, -2e12, -2e12, -2e12, -2e12]) environment config params 1 >>= expectRight
          actual @?= [Common.EvaluationEpisodeResult 2 2 True]
    ]

qrConfig :: Qr.QrDqnTrainConfig
qrConfig =
  Qr.defaultQrDqnTrainConfig
    { Qr.qrObsSize = 2
    , Qr.qrHiddenUnits = 2
    , Qr.qrActionCount = 2
    , Qr.qrNumQuantiles = 2
    , Qr.qrMaxEpisodeSteps = 3
    }
qrParams :: Mlp.MlpParams
qrParams = zeroParams (Mlp.MlpShape 2 2 4)
continuousConfig :: Continuous.ContinuousTrainConfig
continuousConfig =
  (Continuous.defaultContinuousTrainConfig Continuous.VariantDDPG)
    { Continuous.ctObsSize = 2
    , Continuous.ctHidden = 2
    , Continuous.ctActionLow = -2
    , Continuous.ctActionHigh = 2
    , Continuous.ctMaxEpisodeSteps = 3
    , Continuous.ctEnvName = "fixture"
    }
continuousParams :: Mlp.MlpParams
continuousParams = zeroParams (Mlp.MlpShape 2 2 1)
herConfig :: Her.HerTrainConfig
herConfig = Her.defaultHerTrainConfig {Her.herNumBits = 2, Her.herHiddenUnits = 2}
herParams :: Mlp.MlpParams
herParams =
  Mlp.MlpParams
    (Mlp.MlpShape 4 2 2)
    (VU.fromList [-1, 0, 1, 0, 0, -1, 0, 1])
    (VU.replicate 2 0)
    (VU.fromList [1, 0, 0, 1])
    (VU.replicate 2 0)

discrete :: Sim.SimulatedEnvironment Int
discrete =
  Sim.SimulatedEnvironment
    "fixture"
    0
    (\state action -> Sim.SimStep (state + 1) (fromIntegral action) (state >= 1))
    (\state -> Sim.RenderFrame [1, fromIntegral state] "fixture")
    2
    2
    3
    Nothing
    Nothing
continuous :: Sim.ContinuousEnvironment Int
continuous =
  Sim.ContinuousEnvironment
    "fixture"
    0
    (\state action -> Sim.ContinuousSimStep (state + 1) action (state >= 1))
    (\state -> [1, fromIntegral state])
    (-2)
    2
    2
    3

qrEval
  :: MlpDevice
  -> Sim.SimulatedEnvironment Int
  -> Qr.QrDqnTrainConfig
  -> Mlp.MlpParams
  -> Int
  -> IO (Either Text [Common.EvaluationEpisodeResult])
qrEval device environment = Qr.evaluateQrDqnPolicyOnDeviceWithEnvironment device (Sim.SomeSimulatedEnvironment environment)
continuousEval
  :: MlpDevice
  -> Sim.ContinuousEnvironment Int
  -> Continuous.ContinuousTrainConfig
  -> Mlp.MlpParams
  -> Int
  -> IO (Either Text [Common.EvaluationEpisodeResult])
continuousEval device environment =
  Continuous.evaluateContinuousPolicyOnDeviceWithEnvironment
    device
    (Sim.SomeContinuousEnvironment environment)

zeroParams :: Mlp.MlpShape -> Mlp.MlpParams
zeroParams shape =
  Mlp.MlpParams
    shape
    (VU.replicate (Mlp.mlpInputs shape * Mlp.mlpHidden shape) 0)
    (VU.replicate (Mlp.mlpHidden shape) 0)
    (VU.replicate (Mlp.mlpOutputs shape * Mlp.mlpHidden shape) 0)
    (VU.replicate (Mlp.mlpOutputs shape) 0)
outputDevice :: [Double] -> MlpDevice
outputDevice output =
  pureReferenceMlpDevice
    { mlpdForward = \params observation -> pure (Right ((Mlp.mlpForward params observation) {Mlp.forwardOutput = VU.fromList output}))
    }
recordingDevice :: IORef [[Double]] -> MlpDevice -> MlpDevice
recordingDevice inputs device =
  device
    { mlpdForward = \params observation -> modifyIORef' inputs (<> [VU.toList observation]) >> mlpdForward device params observation
    }
countingDevice :: IORef Int -> MlpDevice -> MlpDevice
countingDevice calls device =
  device
    { mlpdForward = \params observation -> modifyIORef' calls (+ 1) >> mlpdForward device params observation
    }
failSecond :: IORef Int -> MlpDevice
failSecond calls =
  pureReferenceMlpDevice
    { mlpdForward = \params observation -> do
        modifyIORef' calls (+ 1)
        count <- readIORef calls
        if count == 2
          then pure (Left "fixture forward failure")
          else mlpdForward pureReferenceMlpDevice params observation
    }
ioFailure :: MlpDevice
ioFailure = pureReferenceMlpDevice {mlpdForward = \_ _ -> throwIO (userError "fixture IO failure")}
assertIOException :: IO value -> Assertion
assertIOException action = do
  result <- try (void action) :: IO (Either IOException ())
  case result of Left _ -> pure (); Right () -> assertFailure "device IO exception was swallowed"
expectLeft :: Text -> Either Text value -> Assertion
expectLeft fragment result = case result of
  Left detail ->
    assertBool (Text.unpack ("wrong failure boundary: " <> detail)) (fragment `Text.isInfixOf` detail)
  Right _ -> assertFailure "invalid device evaluation returned a cohort"
expectRight :: Either Text value -> IO value
expectRight result = case result of
  Left err -> fail (Text.unpack err)
  Right value -> pure value

-- Independent two-bit input schedule: existing pure-oracle episode lengths
-- determine how many pairs of uniform draws must precede the next goal. This
-- checks actual callback goal inputs, not a stored trajectory or the new loop.
twoBitGoalSchedule :: Int -> [Int] -> [[Double]]
twoBitGoalSchedule seed = go (Random.mkStdGen seed)
 where
  go _ [] = []
  go generator (steps : rest) =
    let (goal, afterGoal) = nonzero generator
        afterRollout = iterate consumePair afterGoal !! steps
     in goal : go afterRollout rest
  nonzero generator =
    let (first, next) = Random.uniformR (0 :: Int, 1) generator
        (second, after) = Random.uniformR (0 :: Int, 1) next
     in if first == 0 && second == 0
          then nonzero after
          else ([fromIntegral second, fromIntegral first], after)
  consumePair generator =
    let (_, next) = Random.uniformR (0.0 :: Double, 1.0) generator
        (_, after) = Random.uniformR (0 :: Int, 1) next
     in after
