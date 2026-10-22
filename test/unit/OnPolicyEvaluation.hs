{-# LANGUAGE OverloadedStrings #-}

module OnPolicyEvaluation (onPolicyEvaluationTests) where

import Control.Monad (forM_)
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.Numerics.Mlp qualified as Mlp
import JitML.Numerics.MlpDevice (MlpDevice (..), pureReferenceMlpDevice)
import JitML.RL.Algorithms.Common qualified as Common
import JitML.RL.Algorithms.PpoTrainer qualified as Ppo
import JitML.RL.Simulator qualified as Sim

onPolicyEvaluationTests :: TestTree
onPolicyEvaluationTests =
  testGroup
    "selected-device on-policy evaluation"
    [ testCase "every greedy decision uses the injected device and fixed evaluation start" $ do
        observations <- newIORef []
        let device =
              (outputDevice [0.0, 3.0, 0.0])
                { mlpdForward = \current observation -> do
                    current @?= params
                    modifyIORef' observations (<> [VU.toList observation])
                    mlpdForward (outputDevice [0.0, 3.0, 0.0]) current observation
                }
        result <- evaluate device environment config params 2 >>= expectRight
        result @?= replicate 2 (Common.EvaluationEpisodeResult 3.0 3 True)
        Ppo.evaluateOnPolicyWithEnvironment (Sim.SomeSimulatedEnvironment environment) config params 2
          @?= replicate 2 (Common.EvaluationEpisodeResult 0.0 3 True)
        readIORef observations >>= (@?= [[0.0], [1.0], [2.0], [0.0], [1.0], [2.0]])
    , testCase "explicit pure device retains the reference evaluator across all five variants"
        $ forM_
          [Ppo.VariantPPO, Ppo.VariantA2C, Ppo.VariantTRPO, Ppo.VariantMaskablePPO, Ppo.VariantRecurrentPPO]
        $ \variant -> do
          let current = config {Ppo.ppoVariant = variant}
          actual <- evaluate pureReferenceMlpDevice environment current params 2 >>= expectRight
          actual
            @?= Ppo.evaluateOnPolicyWithEnvironment (Sim.SomeSimulatedEnvironment environment) current params 2
    , testCase "greedy ties choose the first action and MaskablePPO preserves legal-action masking" $ do
        let terminal =
              environment
                { Sim.envStep = \state action -> Sim.SimStep (state + 1) (if action == 0 then 7.0 else 11.0) True
                , Sim.envActionMask = Just (const [False, True])
                }
        tie <- evaluate (outputDevice [1.0, 1.0, 0.0]) terminal config params 1 >>= expectRight
        tie @?= [Common.EvaluationEpisodeResult 7.0 1 True]
        masked <-
          evaluate
            (outputDevice [20.0, 0.0, 0.0])
            terminal
            (config {Ppo.ppoVariant = Ppo.VariantMaskablePPO})
            params
            1
            >>= expectRight
        masked @?= [Common.EvaluationEpisodeResult 11.0 1 True]
    , testCase "horizon truncation stays false and natural termination retains its actual reward and step" $ do
        truncated <-
          evaluate (outputDevice [0.0, 1.0, 0.0]) environment (config {Ppo.ppoMaxEpisodeSteps = 2}) params 1
            >>= expectRight
        truncated @?= [Common.EvaluationEpisodeResult 2.0 2 False]
        let terminal = environment {Sim.envStep = \state _ -> Sim.SimStep (state + 1) 0.0 True}
        natural <- evaluate pureReferenceMlpDevice terminal config params 1 >>= expectRight
        natural @?= [Common.EvaluationEpisodeResult 0.0 1 True]
    , testCase "later device errors discard partial episodes and partial evaluation cohorts" $
        forM_ [2, 4] $ \failureAt -> do
          calls <- newIORef (0 :: Int)
          let device =
                pureReferenceMlpDevice
                  { mlpdForward = \current observation -> do
                      modifyIORef' calls (+ 1)
                      count <- readIORef calls
                      if count == failureAt
                        then pure (Left "evaluation device unavailable")
                        else mlpdForward pureReferenceMlpDevice current observation
                  }
          actual <- evaluate device environment config params 2
          expectLeft
            "on-policy device forward kernel failed during evaluation: evaluation device unavailable"
            actual
          readIORef calls >>= (@?= failureAt)
    , testCase "wrong-width and non-finite device outputs fail before greedy action selection"
        $ forM_
          [ ([0.0, 1.0], "unexpected output width")
          , ([0.0, 1.0, 2.0, 3.0], "unexpected output width")
          , ([0.0 / 0.0, 1.0, 0.0], "non-finite output")
          , ([0.0, 1.0, 1.0 / 0.0], "non-finite output")
          ]
        $ \(output, expected) -> do
          actual <- evaluate (outputDevice output) environment config params 1
          expectLeft expected actual
    , testCase "invalid evaluation inputs fail before any device call" $ do
        calls <- newIORef (0 :: Int)
        let device =
              pureReferenceMlpDevice
                { mlpdForward = \_ _ -> modifyIORef' calls (+ 1) >> pure (Left "invalid input reached device")
                }
            badObservation values = environment {Sim.envRenderFrame = const (Sim.RenderFrame values "invalid observation fixture")}
            masked mask = environment {Sim.envActionMask = Just (const mask)}
            maskConfig = config {Ppo.ppoVariant = Ppo.VariantMaskablePPO}
            cases =
              [ ("positive episode count", evaluate device environment config params 0)
              , ("positive episode count", evaluate device environment config params (-1))
              ,
                ( "positive episode count"
                , evaluate device environment (config {Ppo.ppoMaxEpisodeSteps = 0}) params 1
                )
              , ("configuration", evaluate device environment (config {Ppo.ppoActionCount = 3}) params 1)
              , ("configuration", evaluate device environment (config {Ppo.ppoObsSize = 2}) params 1)
              , ("configuration", evaluate device environment (config {Ppo.ppoHiddenUnits = 0}) params 1)
              , ("parameters", evaluate device environment config (params {Mlp.paramB2 = VU.empty}) 1)
              ,
                ( "parameters"
                , evaluate device environment config (params {Mlp.paramW1 = VU.singleton (0.0 / 0.0)}) 1
                )
              , ("parameters", evaluate device environment config (params {Mlp.paramW1 = VU.singleton 1.0e300}) 1)
              , ("observation", evaluate device (badObservation []) config params 1)
              , ("observation", evaluate device (badObservation [0.0 / 0.0]) config params 1)
              , ("observation", evaluate device (badObservation [1.0e300]) config params 1)
              , ("action mask", evaluate device (masked [True]) maskConfig params 1)
              , ("action mask", evaluate device (masked [False, False]) maskConfig params 1)
              ]
        forM_ cases $ \(expected, action) -> action >>= expectLeft expected
        readIORef calls >>= (@?= 0)
    , testCase "non-finite environment rewards cannot become a completed evaluation" $ do
        let invalid = environment {Sim.envStep = \state _ -> Sim.SimStep state (1.0 / 0.0) True}
        actual <- evaluate pureReferenceMlpDevice invalid config params 1
        expectLeft "non-finite reward" actual
    ]

config :: Ppo.PpoTrainConfig
config =
  Ppo.defaultPpoTrainConfig
    { Ppo.ppoHiddenUnits = 1
    , Ppo.ppoObsSize = 1
    , Ppo.ppoActionCount = 2
    , Ppo.ppoMaxEpisodeSteps = 5
    }

params :: Mlp.MlpParams
params =
  Mlp.MlpParams
    (Mlp.MlpShape 1 1 3)
    (VU.singleton 0.0)
    (VU.singleton 0.0)
    (VU.replicate 3 0.0)
    (VU.fromList [2.0, 0.0, 0.0])

-- Explicit synthetic evaluator-control environment: no ProductRow completion.
-- The training-only start differs so accidental evaluation randomization fails.
environment :: Sim.SimulatedEnvironment Int
environment =
  Sim.SimulatedEnvironment
    { Sim.envName = "on-policy-evaluation-control"
    , Sim.envInitial = 0
    , Sim.envStep = \state action -> Sim.SimStep (state + 1) (fromIntegral action) (state >= 2)
    , Sim.envRenderFrame = \state -> Sim.RenderFrame [fromIntegral state] "evaluation control"
    , Sim.envActionCount = 2
    , Sim.envObservationSize = 1
    , Sim.envMaxEpisodeSteps = 5
    , Sim.envActionMask = Nothing
    , Sim.envTrainingStart = Just (\_ _ -> 99)
    }

evaluate
  :: MlpDevice
  -> Sim.SimulatedEnvironment state
  -> Ppo.PpoTrainConfig
  -> Mlp.MlpParams
  -> Int
  -> IO (Either Text [Common.EvaluationEpisodeResult])
evaluate device current = Ppo.evaluateOnPolicyOnDeviceWithEnvironment device (Sim.SomeSimulatedEnvironment current)

outputDevice :: [Double] -> MlpDevice
outputDevice values =
  pureReferenceMlpDevice
    { mlpdForward = \current observation -> do
        result <- mlpdForward pureReferenceMlpDevice current observation
        pure (fmap (\forward -> forward {Mlp.forwardOutput = VU.fromList values}) result)
    }

expectRight :: (Show error) => Either error value -> IO value
expectRight = either (assertFailure . show) pure

expectLeft :: Text -> Either Text value -> Assertion
expectLeft expected result = case result of
  Left err -> assertBool ("unexpected error: " <> Text.unpack err) (expected `Text.isInfixOf` err)
  Right _ -> assertFailure ("expected evaluation failure containing " <> Text.unpack expected)
