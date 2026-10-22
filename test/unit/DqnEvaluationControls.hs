{-# LANGUAGE OverloadedStrings #-}

module DqnEvaluationControls (dqnEvaluationTests) where

import Control.Exception (IOException, throwIO, try)
import Control.Monad (forM_, (>=>))
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.List (elemIndex)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.Numerics.Mlp qualified as Mlp
import JitML.Numerics.MlpDevice (MlpDevice (..), pureReferenceMlpDevice)
import JitML.RL.Algorithms.Common qualified as Common
import JitML.RL.Algorithms.DqnTrainer qualified as Dqn
import JitML.RL.Simulator qualified as Sim

-- Actual evaluator boundaries with explicit offline device/environment fixtures.
-- These controls make no hardware, canonical training or convergence claim.
dqnEvaluationTests :: TestTree
dqnEvaluationTests =
  testGroup
    "DQN checked selected-device final evaluation"
    [ testCase "every actual frozen-policy decision uses the supplied device and resets exactly" $ do
        inputs <- newIORef []
        actual <-
          evaluate (recordingDevice inputs (outputDevice [0, 3])) fixture config params 2 >>= expectRight
        actual @?= replicate 2 (Common.EvaluationEpisodeResult 2 2 True)
        readIORef inputs >>= (@?= [[1, 0], [1, 1], [1, 0], [1, 1]])
        reference <- evaluate pureReferenceMlpDevice fixture config params 2 >>= expectRight
        reference @?= replicate 2 (Common.EvaluationEpisodeResult 0 2 True)
    , testCase "a real pure reference forward agrees with an independent direct fixture rollout" $ do
        let initialized = Dqn.initialDqnParams config
            directAction state =
              leftmost
                (VU.toList (Mlp.forwardOutput (Mlp.mlpForward initialized (VU.fromList [1, fromIntegral state]))))
        first <- maybe (assertFailure "fixture first pure output is empty") pure (directAction (0 :: Int))
        second <- maybe (assertFailure "fixture second pure output is empty") pure (directAction (1 :: Int))
        let expectedReturn = fromIntegral (first + second)
        actual <- evaluate pureReferenceMlpDevice fixture config initialized 3 >>= expectRight
        actual @?= replicate 3 (Common.EvaluationEpisodeResult expectedReturn 2 True)
    , testCase "state-dependent legal masks are re-read on every device decision" $ do
        let environment =
              fixture {Sim.envActionMask = Just (\state -> if state == 0 then [False, True] else [True, False])}
        actual <- evaluate (outputDevice [100, 1]) environment config params 1 >>= expectRight
        actual @?= [Common.EvaluationEpisodeResult 1 2 True]
    , testCase "legal logits below the old finite sentinel cannot select an illegal action" $ do
        let three = config {Dqn.dqnActionCount = 3}
            environment = fixture {Sim.envActionCount = 3, Sim.envActionMask = Just (const [False, True, True])}
            weights = zeroParams (Mlp.MlpShape 2 2 3)
        actual <- evaluate (outputDevice [1e20, -2e12, -2e12]) environment three weights 1 >>= expectRight
        actual @?= [Common.EvaluationEpisodeResult 2 2 True]
    , testCase "unmasked exact ties retain the leftmost action" $ do
        actual <- evaluate (outputDevice [5, 5]) fixture config params 1 >>= expectRight
        actual @?= [Common.EvaluationEpisodeResult 0 2 True]
    , testCase "a genuine terminal step includes its negative reward and stops the episode" $ do
        calls <- newIORef (0 :: Int)
        let environment = fixture {Sim.envStep = \state _ -> Sim.SimStep (state + 1) (-7) True}
        actual <-
          evaluate (countingDevice calls (outputDevice [0, 1])) environment config params 2 >>= expectRight
        actual @?= replicate 2 (Common.EvaluationEpisodeResult (-7) 1 True)
        readIORef calls >>= (@?= 2)
        boundary <-
          evaluate
            (outputDevice [0, 1])
            (fixture {Sim.envStep = \state _ -> Sim.SimStep (state + 1) 1 (state + 1 == 3)})
            config
            params
            1
            >>= expectRight
        boundary @?= [Common.EvaluationEpisodeResult 3 3 True]
    , testCase "time-limit exhaustion remains distinct from environment termination" $ do
        calls <- newIORef (0 :: Int)
        let environment = fixture {Sim.envStep = \state action -> Sim.SimStep (state + 1) (fromIntegral action) False}
        actual <-
          evaluate (countingDevice calls (outputDevice [0, 1])) environment config params 1 >>= expectRight
        actual @?= [Common.EvaluationEpisodeResult 3 3 False]
        readIORef calls >>= (@?= 3)
    , testCase "a device failure after one completed episode rejects the entire requested cohort" $ do
        calls <- newIORef (0 :: Int)
        let device =
              pureReferenceMlpDevice
                { mlpdForward = \weights observation -> do
                    modifyIORef' calls (+ 1)
                    count <- readIORef calls
                    if count == 3
                      then pure (Left "fixture third forward failed")
                      else mlpdForward pureReferenceMlpDevice weights observation
                }
        evaluate device fixture config params 2 >>= expectLeft "fixture third forward failed"
        readIORef calls >>= (@?= 3)
    , testCase "device IO exceptions propagate without returning a partial cohort" $ do
        let device = pureReferenceMlpDevice {mlpdForward = \_ _ -> throwIO (userError "fixture IO failure")}
        result <-
          try (evaluate device fixture config params 2)
            :: IO (Either IOException (Either Text [Common.EvaluationEpisodeResult]))
        case result of Left _ -> pure (); Right _ -> assertFailure "device IO exception was swallowed"
    , testCase "wrong-width output rejects before the environment transition" $
        forM_ [[], [0], [0, 0, 0]] $ \output ->
          evaluate (outputDevice output) mustNotStep config params 1 >>= expectLeft "output"
    , testCase "nonfinite or Float32-overflow output rejects before the environment transition" $
        forM_ [0 / 0, 1 / 0, negate (1 / 0), 1e300] $ \bad ->
          evaluate (outputDevice [0, bad]) mustNotStep config params 1 >>= expectLeft "output"
    , testCase "nonpositive episode count and horizon reject before the device" $ do
        calls <- newIORef (0 :: Int)
        let device = countingDevice calls pureReferenceMlpDevice
        forM_ [0, -1] (evaluate device fixture config params >=> expectLeft "configuration")
        forM_ [0, -1] $ \horizon ->
          evaluate device fixture (config {Dqn.dqnMaxEpisodeSteps = horizon}) params 1
            >>= expectLeft "configuration"
        readIORef calls >>= (@?= 0)
    , testCase "environment dimensions and CInt-overflow configuration reject before the device" $ do
        calls <- newIORef (0 :: Int)
        let device = countingDevice calls pureReferenceMlpDevice
        forM_ [fixture {Sim.envObservationSize = 1}, fixture {Sim.envActionCount = 1}] $ \environment ->
          evaluate device environment config params 1 >>= expectLeft "configuration"
        forM_
          [ config {Dqn.dqnObsSize = 0}
          , config {Dqn.dqnHiddenUnits = 0}
          , config {Dqn.dqnActionCount = 0}
          , config {Dqn.dqnHiddenUnits = maxBound}
          ]
          $ \bad ->
            evaluate device fixture bad params 1 >>= expectLeft "configuration"
        let overflow = config {Dqn.dqnObsSize = 50000, Dqn.dqnHiddenUnits = 50000}
        evaluate device (fixture {Sim.envObservationSize = 50000}) overflow params 1
          >>= expectLeft "configuration"
        let outputOverflow = config {Dqn.dqnHiddenUnits = 50000, Dqn.dqnActionCount = 50000}
        evaluate device (fixture {Sim.envActionCount = 50000}) outputOverflow params 1
          >>= expectLeft "configuration"
        readIORef calls >>= (@?= 0)
    , testCase "each parameter buffer and declared network shape are checked before the device" $ do
        calls <- newIORef (0 :: Int)
        let device = countingDevice calls pureReferenceMlpDevice
        forM_
          [ params {Mlp.paramShape = Mlp.MlpShape 1 2 2}
          , params {Mlp.paramW1 = VU.empty}
          , params {Mlp.paramB1 = VU.empty}
          , params {Mlp.paramW2 = VU.empty}
          , params {Mlp.paramB2 = VU.empty}
          ]
          $ \bad ->
            evaluate device fixture config bad 1 >>= expectLeft "parameters"
        readIORef calls >>= (@?= 0)
    , testCase "nonfinite and Float32-overflow parameters reject before the device" $ do
        calls <- newIORef (0 :: Int)
        let device = countingDevice calls pureReferenceMlpDevice
        forM_ [0 / 0, 1 / 0, 1e300] $ \bad ->
          forM_
            [ params {Mlp.paramW1 = VU.fromList [bad, 0, 0, 0]}
            , params {Mlp.paramB1 = VU.fromList [bad, 0]}
            , params {Mlp.paramW2 = VU.fromList [bad, 0, 0, 0]}
            , params {Mlp.paramB2 = VU.fromList [bad, 0]}
            ]
            $ \weights ->
              evaluate device fixture config weights 1 >>= expectLeft "parameters"
        readIORef calls >>= (@?= 0)
    , testCase "observation width nonfinite values and Float32 overflow reject before the device" $ do
        calls <- newIORef (0 :: Int)
        let device = countingDevice calls pureReferenceMlpDevice
        forM_ [[0], [0, 0, 0], [0, 0 / 0], [0, 1 / 0], [0, 1e300]] $ \observation ->
          evaluate
            device
            (fixture {Sim.envRenderFrame = const (Sim.RenderFrame observation "invalid fixture")})
            config
            params
            1
            >>= expectLeft "observation"
        readIORef calls >>= (@?= 0)
    , testCase "short long empty and all-false masks reject before the device" $ do
        calls <- newIORef (0 :: Int)
        let device = countingDevice calls pureReferenceMlpDevice
        forM_ [[], [True], [True, True, True], [False, False]] $ \mask ->
          evaluate device (fixture {Sim.envActionMask = Just (const mask)}) config params 1
            >>= expectLeft "mask"
        readIORef calls >>= (@?= 0)
    , testCase "finite parameter and observation conversion rounding and underflow are permitted" $ do
        calls <- newIORef (0 :: Int)
        let rounded = params {Mlp.paramB1 = VU.fromList [0.1, 1e-300]}
            environment = fixture {Sim.envRenderFrame = const (Sim.RenderFrame [0.1, 1e-300] "finite fixture")}
        evaluate (countingDevice calls pureReferenceMlpDevice) environment config rounded 1
          >>= expectRight
          >>= (\episodes -> length episodes @?= 1)
        readIORef calls >>= (@?= 2)
    , testCase "nonfinite terminal rewards and overflowing finite accumulated returns reject" $ do
        forM_ [0 / 0, 1 / 0] $ \reward ->
          evaluate
            (outputDevice [0, 1])
            (fixture {Sim.envStep = \state _ -> Sim.SimStep (state + 1) reward True})
            config
            params
            1
            >>= expectLeft "reward"
        evaluate
          (outputDevice [0, 1])
          (fixture {Sim.envStep = \state _ -> Sim.SimStep (state + 1) 1e308 False})
          config
          params
          1
          >>= expectLeft "reward"
    ]

config :: Dqn.DqnTrainConfig
config =
  Dqn.defaultDqnTrainConfig
    { Dqn.dqnObsSize = 2
    , Dqn.dqnHiddenUnits = 2
    , Dqn.dqnActionCount = 2
    , Dqn.dqnMaxEpisodeSteps = 3
    }

params :: Mlp.MlpParams
params = zeroParams (Mlp.MlpShape 2 2 2)

fixture :: Sim.SimulatedEnvironment Int
fixture =
  Sim.SimulatedEnvironment
    "DQN evaluation fixture"
    0
    (\state action -> Sim.SimStep (state + 1) (fromIntegral action) (state >= 1))
    (\state -> Sim.RenderFrame [1, fromIntegral state] "DQN evaluation fixture")
    2
    2
    3
    Nothing
    Nothing

mustNotStep :: Sim.SimulatedEnvironment Int
mustNotStep = fixture {Sim.envStep = \_ _ -> error "invalid output reached environment transition"}

evaluate
  :: MlpDevice
  -> Sim.SimulatedEnvironment Int
  -> Dqn.DqnTrainConfig
  -> Mlp.MlpParams
  -> Int
  -> IO (Either Text [Common.EvaluationEpisodeResult])
evaluate device environment = Dqn.evaluateDqnPolicyWithEnvironment device (Sim.SomeSimulatedEnvironment environment)

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
    { mlpdForward = \weights observation -> pure (Right ((Mlp.mlpForward weights observation) {Mlp.forwardOutput = VU.fromList output}))
    }

recordingDevice :: IORef [[Double]] -> MlpDevice -> MlpDevice
recordingDevice inputs device =
  device
    { mlpdForward = \weights observation -> modifyIORef' inputs (<> [VU.toList observation]) >> mlpdForward device weights observation
    }

countingDevice :: IORef Int -> MlpDevice -> MlpDevice
countingDevice calls device =
  device
    { mlpdForward = \weights observation -> modifyIORef' calls (+ 1) >> mlpdForward device weights observation
    }

leftmost :: [Double] -> Maybe Int
leftmost [] = Nothing
leftmost values@(first : rest) = elemIndex (foldr max first rest) values

expectLeft :: Text -> Either Text value -> Assertion
expectLeft fragment result = case result of
  Left detail -> assertBool (Text.unpack ("wrong rejection: " <> detail)) (fragment `Text.isInfixOf` detail)
  Right _ -> assertFailure "invalid evaluation returned a cohort"

expectRight :: Either Text value -> IO value
expectRight result = case result of
  Left detail -> fail (Text.unpack detail)
  Right value -> pure value
