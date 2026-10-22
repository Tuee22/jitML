{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

module NativeReturnReferences (nativeReturnReferencesTests) where

import Control.Monad (forM_)
import Data.List (find, nub, sort)
import Data.List.NonEmpty qualified as NE
import Data.Text (Text)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.Plan.Plan qualified as Plan
import JitML.Product.Matrix qualified as Matrix
import JitML.RL.ConvergenceThresholds qualified as Thresholds
import JitML.RL.NativeReturnReferences qualified as Ref
import JitML.RL.ProductBudget qualified as ProductBudget
import JitML.RL.Simulator qualified as Sim
import JitML.Substrate (Substrate (..))
import JitML.Training.Budget qualified as Budget

-- Fresh simulator comparisons, metadata and raw observations only. No literal
-- numerical quality fixture, training/model execution or provider authority.
nativeReturnReferencesTests :: TestTree
nativeReturnReferencesTests =
  testGroup
    "canonical native return task references"
    [ testCase "all thirty eight canonical return rows have exact checked specifications" $ do
        specs <- expectRight Ref.allCanonicalNativeReturnSpecs
        length specs @?= 38
        fmap Ref.nativeReturnSpecRowId specs
          @?= [ Thresholds.fbrAlgorithm row <> "/" <> Thresholds.fbrEnvironment row
              | row <- Thresholds.fixedBudgetRlConvergenceRows
              ]
        length [() | spec <- specs, Ref.NativeContinuous {} <- [Ref.nativeReturnSpecDomain spec]] @?= 6
        length [() | spec <- specs, Ref.NativeMaskedDiscrete {} <- [Ref.nativeReturnSpecDomain spec]] @?= 8
        length (nub (fmap Ref.nativeReturnSpecRowId specs)) @?= 38
        forM_ specs $ \spec -> do
          Ref.nativeReturnSpecEpisodeCount spec @?= ProductBudget.productRlDefaultEvaluationEpisodes
          Ref.nativeReturnSpecEpisodeCount spec @?= 20
          Ref.nativeReturnSpecTrainer spec
            @?= ProductBudget.trainerKindForAlgorithm (Ref.nativeReturnSpecAlgorithm spec)
          Budget.trainingBudgetTargetUnits (Ref.nativeReturnSpecBudget spec)
            @?= ProductBudget.scheduleObservedEnvironmentSteps (Ref.nativeReturnSpecSchedule spec)
    , testCase "every reference descriptor matches all three actual Matrix projections" $ do
        specs <- expectRight Ref.allCanonicalNativeReturnSpecs
        forM_ specs $ \spec -> do
          row <-
            maybe
              (assertFailure "canonical Matrix row absent")
              pure
              (find ((== Ref.nativeReturnSpecRowId spec) . Matrix.rowId) Matrix.allProductRows)
          forM_ [AppleSilicon, LinuxCPU, LinuxCUDA] (assertProjection spec row)
    , testCase "canonical refinement rejects aliases unsupported rows and altered full declarations" $ do
        forM_
          [ ("ppo", "cartpole")
          , ("PPO", "CartPole")
          , ("HER", "goal-reaching")
          , ("AlphaZero", "connect4")
          , ("SAC", "cartpole")
          ]
          $ \(algorithm, environment) ->
            expectLeft
              "native return reference row is not canonical"
              (Ref.canonicalNativeReturnSpec algorithm environment)
        row <- firstRow
        let threshold = Thresholds.fbrThreshold row
        expectLeft
          "native return reference row differs from the exact canonical declaration"
          ( Ref.mkCanonicalNativeReturnSpec
              row {Thresholds.fbrThreshold = threshold {Thresholds.slack = Thresholds.slack threshold + 1}}
          )
        budget <-
          expectRight
            ( Budget.mkTrainingBudget
                Budget.RlEnvironmentStepBudget
                (Budget.trainingBudgetTargetUnits (Thresholds.fbrBudget row) + 1)
                Nothing
            )
        expectLeft
          "native return reference row differs from the exact canonical declaration"
          (Ref.mkCanonicalNativeReturnSpec row {Thresholds.fbrBudget = budget})
    , testCase "horizons derive from each actual schedule and ARS lander stays discrete" $ do
        specs <- expectRight Ref.allCanonicalNativeReturnSpecs
        assertBool
          "canonical horizons are not all the global requested floor"
          (length (nub (fmap Ref.nativeReturnSpecHorizon specs)) > 1)
        forM_ specs $ \spec -> do
          let actual = case Ref.nativeReturnSpecSchedule spec of
                ProductBudget.OnPolicyTrainingSchedule {} -> ProductBudget.scheduleOnPolicyMaxEpisodeSteps (Ref.nativeReturnSpecSchedule spec)
                ProductBudget.FixedStepTrainingSchedule {} -> ProductBudget.scheduleFixedMaxEpisodeSteps (Ref.nativeReturnSpecSchedule spec)
                ProductBudget.ArsTrainingSchedule {} -> ProductBudget.scheduleArsMaxEpisodeSteps (Ref.nativeReturnSpecSchedule spec)
                ProductBudget.HerTrainingSchedule {} -> 0
          Ref.nativeReturnSpecHorizon spec @?= actual
        ars <- expectRight (Ref.canonicalNativeReturnSpec "ARS" "lunar-lander")
        Ref.nativeReturnSpecDomain ars
          @?= Ref.NativeUnmaskedDiscrete (Sim.envActionCount Sim.lunarLanderEnvironment)
        forM_ ["DDPG", "TD3", "SAC", "CrossQ", "TQC"] $ \algorithm -> do
          spec <- expectRight (Ref.canonicalNativeReturnSpec algorithm "lunar-lander")
          Ref.nativeReturnSpecDomain spec
            @?= Ref.NativeContinuous
              (Sim.cEnvActionLow Sim.lunarLanderContinuousEnvironment)
              (Sim.cEnvActionHigh Sim.lunarLanderContinuousEnvironment)
    , testCase "unmasked domains collapse to exactly one fixed controller per actual action" $ do
        forM_
          [ Sim.SomeSimulatedEnvironment Sim.cartPoleEnvironment
          , Sim.SomeSimulatedEnvironment Sim.mountainCarEnvironment
          , Sim.SomeSimulatedEnvironment Sim.acrobotEnvironment
          , Sim.SomeSimulatedEnvironment Sim.lunarLanderEnvironment
          , Sim.SomeSimulatedEnvironment Sim.gridWorldEnvironment
          ]
          $ \(Sim.SomeSimulatedEnvironment env) -> do
            controllers <- expectRight (Ref.discreteReferenceControllers env)
            controllers @?= fmap Ref.ConstantDiscrete [0 .. Sim.envActionCount env - 1]
            length (nub (fmap Ref.nativeReturnControllerId controllers)) @?= length controllers
    , testCase "masked families enumerate every complete preference in stable action-domain order" $ do
        let env = fixtureDiscrete {Sim.envActionMask = Just (const [True, True, True])}
            permutations3 = [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]
        Ref.discreteReferenceControllers env @?= Right (fmap Ref.FixedMaskedPreference permutations3)
        actual <- expectRight (Ref.discreteReferenceControllers Sim.keyDoorGridEnvironment)
        let count = Sim.envActionCount Sim.keyDoorGridEnvironment
            preferences = [p | Ref.FixedMaskedPreference p <- actual]
        toInteger (length actual) @?= product [1 .. toInteger count]
        length (nub preferences) @?= length preferences
        preferences @?= sort preferences
        forM_ preferences $ \preference -> sort preference @?= [0 .. count - 1]
    , testCase "fixed preferences select the first legal action from the current state mask" $ do
        let env =
              fixtureDiscrete
                { Sim.envActionMask = Just (\state -> if even state then [False, True, True] else [True, False, True])
                }
        Ref.selectDiscreteReferenceAction env (Ref.FixedMaskedPreference [2, 1, 0]) 0 @?= Right 2
        Ref.selectDiscreteReferenceAction env (Ref.FixedMaskedPreference [1, 0, 2]) 0 @?= Right 1
        Ref.selectDiscreteReferenceAction env (Ref.FixedMaskedPreference [1, 0, 2]) 1 @?= Right 0
    , testCase "complete preference validation cannot hide malformed trailing or duplicate actions" $ do
        let env = fixtureDiscrete {Sim.envActionMask = Just (const [True, True, True])}
        forM_ [[], [0], [0, 0, 2], [0, 1, 3], [0, 1, 2, 2], [-1, 0, 1]] $ \preference ->
          expectLeft
            "masked reference preference is not a complete action-domain permutation"
            (Ref.selectDiscreteReferenceAction env (Ref.FixedMaskedPreference preference) 0)
    , testCase "empty wrong-width and all-illegal masks fail without fallback" $ do
        let preference = Ref.FixedMaskedPreference [0, 1, 2]
        forM_ [[], [True], [True, True, True, True]] $ \mask ->
          expectLeft
            "native return action mask width differs from the action domain"
            ( Ref.selectDiscreteReferenceAction
                fixtureDiscrete {Sim.envActionMask = Just (const mask)}
                preference
                0
            )
        expectLeft
          "native return action mask has no legal action"
          ( Ref.selectDiscreteReferenceAction
              fixtureDiscrete {Sim.envActionMask = Just (const [False, False, False])}
              preference
              0
          )
    , testCase "invalid constants and controller domain substitutions reject specifically" $ do
        forM_ [-1, 3] $ \action ->
          expectLeft
            "discrete reference constant is outside the actual action domain"
            (Ref.selectDiscreteReferenceAction fixtureDiscrete (Ref.ConstantDiscrete action) 0)
        expectLeft
          "native return controller does not match the simulator action domain"
          (Ref.evaluateDiscreteReference fixtureDiscrete 1 1 (Ref.FixedMaskedPreference [0, 1, 2]))
        expectLeft
          "native return controller does not match the simulator action domain"
          ( Ref.evaluateDiscreteReference
              fixtureDiscrete {Sim.envActionMask = Just (const [True, True, True])}
              1
              1
              (Ref.ConstantDiscrete 0)
          )
        expectLeft
          "native return controller does not match the simulator action domain"
          (Ref.evaluateContinuousReference fixtureContinuous 1 1 (Ref.ConstantDiscrete 0))
    , testCase "continuous references are native zero and actual endpoints without universal transforms" $ do
        let env = fixtureContinuous {Sim.cEnvActionLow = -3, Sim.cEnvActionHigh = 7}
            expected =
              [ Ref.ConstantContinuous Ref.NativeZero 0
              , Ref.ConstantContinuous Ref.NativeLowerEndpoint (-3)
              , Ref.ConstantContinuous Ref.NativeUpperEndpoint 7
              ]
        Ref.continuousReferenceControllers env @?= Right expected
        forM_ expected $ \controller -> do
          actual <- expectRight (Ref.evaluateContinuousReference env 20 1 controller)
          let value = case controller of Ref.ConstantContinuous _ action -> action; _ -> 0
          fmap Ref.nativeReturnEpisodeReward (Ref.nativeReturnObservedEpisodes actual) @?= replicate 20 value
        forM_
          [ Sim.SomeContinuousEnvironment Sim.pendulumEnvironment
          , Sim.SomeContinuousEnvironment Sim.lunarLanderContinuousEnvironment
          ]
          $ \(Sim.SomeContinuousEnvironment actual) ->
            Ref.continuousReferenceControllers actual
              @?= Right
                [ Ref.ConstantContinuous Ref.NativeZero 0
                , Ref.ConstantContinuous Ref.NativeLowerEndpoint (Sim.cEnvActionLow actual)
                , Ref.ConstantContinuous Ref.NativeUpperEndpoint (Sim.cEnvActionHigh actual)
                ]
    , testCase "continuous labels bounds and zero feasibility reject malformed inputs" $ do
        forM_
          [ fixtureContinuous {Sim.cEnvActionLow = 0 / 0}
          , fixtureContinuous {Sim.cEnvActionHigh = 1 / 0}
          , fixtureContinuous {Sim.cEnvActionLow = 1, Sim.cEnvActionHigh = 1}
          ]
          $ \env ->
            expectLeft
              "native continuous simulator metadata or bounds are invalid"
              (Ref.continuousReferenceControllers env)
        expectLeft
          "native zero reference is outside the actual action bounds"
          (Ref.continuousReferenceControllers fixtureContinuous {Sim.cEnvActionLow = 2, Sim.cEnvActionHigh = 4})
        forM_
          [ Ref.ConstantContinuous Ref.NativeZero 1
          , Ref.ConstantContinuous Ref.NativeLowerEndpoint 2
          , Ref.ConstantContinuous Ref.NativeUpperEndpoint (-2)
          , Ref.ConstantContinuous Ref.NativeZero (0 / 0)
          , Ref.ConstantContinuous Ref.NativeZero (-0.0)
          ]
          $ \controller ->
            expectLeft
              "continuous reference is not its declared native zero or endpoint"
              (Ref.evaluateContinuousReference fixtureContinuous 1 1 controller)
    , testCase "fresh production simulator direct rollouts agree for every canonical return row" $ do
        specs <- expectRight Ref.allCanonicalNativeReturnSpecs
        forM_ specs $ \spec -> case Ref.nativeReturnSpecDomain spec of
          Ref.NativeContinuous {} -> do
            wrapped <-
              maybe
                (assertFailure "actual continuous simulator absent")
                pure
                (Sim.lookupContinuousEnvironmentByName (Ref.nativeReturnSpecEnvironment spec))
            case wrapped of
              Sim.SomeContinuousEnvironment env -> do
                controller <- firstValue =<< expectRight (Ref.continuousReferenceControllers env)
                actual <-
                  expectRight
                    ( Ref.evaluateContinuousReference
                        env
                        (Ref.nativeReturnSpecEpisodeCount spec)
                        (Ref.nativeReturnSpecHorizon spec)
                        controller
                    )
                let value = case controller of Ref.ConstantContinuous _ action -> action; _ -> 0
                    expected = directContinuous env value (Ref.nativeReturnSpecHorizon spec)
                triples actual @?= replicate 20 expected
          _ -> do
            wrapped <-
              maybe
                (assertFailure "actual discrete simulator absent")
                pure
                (Sim.lookupSimulatedEnvironmentByName (Ref.nativeReturnSpecEnvironment spec))
            case wrapped of
              Sim.SomeSimulatedEnvironment env -> do
                controller <- firstValue =<< expectRight (Ref.discreteReferenceControllers env)
                actual <-
                  expectRight
                    ( Ref.evaluateDiscreteReference
                        env
                        (Ref.nativeReturnSpecEpisodeCount spec)
                        (Ref.nativeReturnSpecHorizon spec)
                        controller
                    )
                triples actual @?= replicate 20 (directDiscrete env controller (Ref.nativeReturnSpecHorizon spec))
    , testCase
        "canonical masked cohort retains all controllers all twenty keys and exact represented work"
        $ do
          spec <- expectRight (Ref.canonicalNativeReturnSpec "PPO" "key-door-grid")
          actual <- expectRight (Ref.evaluateCanonicalNativeReturnReferences spec)
          expected <- expectRight (Ref.discreteReferenceControllers Sim.keyDoorGridEnvironment)
          Ref.nativeReturnObservedSpec actual @?= spec
          fmap Ref.nativeReturnObservedController (Ref.nativeReturnObservedReferences actual) @?= expected
          forM_ (Ref.nativeReturnObservedReferences actual) $ \observed -> do
            fmap Ref.nativeReturnEpisodeId (Ref.nativeReturnObservedEpisodes observed) @?= [0 .. 19]
            length (Ref.nativeReturnObservedEpisodes observed) @?= 20
            Ref.nativeReturnObservedEvaluationTransitions observed
              @?= sum (fmap (toInteger . Ref.nativeReturnEpisodeSteps) (Ref.nativeReturnObservedEpisodes observed))
          Ref.nativeReturnTotalEvaluationTransitions actual
            @?= sum (fmap Ref.nativeReturnObservedEvaluationTransitions (Ref.nativeReturnObservedReferences actual))
    , testCase "canonical continuous cohort retains all three native controllers and twenty complete keys" $ do
        spec <- expectRight (Ref.canonicalNativeReturnSpec "SAC" "pendulum")
        actual <- expectRight (Ref.evaluateCanonicalNativeReturnReferences spec)
        expected <- expectRight (Ref.continuousReferenceControllers Sim.pendulumEnvironment)
        fmap Ref.nativeReturnObservedController (Ref.nativeReturnObservedReferences actual) @?= expected
        forM_ (Ref.nativeReturnObservedReferences actual) $ \observed -> fmap Ref.nativeReturnEpisodeId (Ref.nativeReturnObservedEpisodes observed) @?= [0 .. 19]
    , testCase "early termination horizon exhaustion and terminal-at-horizon have exact distinct flags" $ do
        let controller = Ref.ConstantDiscrete 0
            endless = fixtureDiscrete {Sim.envStep = \state _ -> Sim.SimStep (state + 1) 1 False}
            terminalAt target = fixtureDiscrete {Sim.envStep = \state _ -> Sim.SimStep (state + 1) 1 (state + 1 >= target)}
        full <- expectRight (Ref.evaluateDiscreteReference endless 20 3 controller)
        early <- expectRight (Ref.evaluateDiscreteReference (terminalAt 2) 20 3 controller)
        boundary <- expectRight (Ref.evaluateDiscreteReference (terminalAt 3) 20 3 controller)
        triples full @?= replicate 20 (3, 3, False)
        triples early @?= replicate 20 (2, 2, True)
        triples boundary @?= replicate 20 (3, 3, True)
        fmap Ref.nativeReturnObservedEvaluationTransitions [full, early, boundary] @?= [60, 40, 60]
    , testCase "every episode resets to envInitial and never consumes training exploring starts" $ do
        let env =
              fixtureDiscrete
                { Sim.envTrainingStart = Just (\_ _ -> 100)
                , Sim.envStep = \state _ -> Sim.SimStep (state + 1) (if state == 0 then 10 else 1) False
                }
        actual <- expectRight (Ref.evaluateDiscreteReference env 20 2 (Ref.ConstantDiscrete 0))
        triples actual @?= replicate 20 (11, 2, False)
        fmap Ref.nativeReturnEpisodeId (Ref.nativeReturnObservedEpisodes actual) @?= [0 .. 19]
    , testCase "no post-terminal step or padded transition enters represented evaluation work" $ do
        let env =
              fixtureDiscrete
                { Sim.envStep = \state _ -> Sim.SimStep (state + 1) (if state >= 1 then 0 / 0 else 5) True
                }
        actual <- expectRight (Ref.evaluateDiscreteReference env 20 100 (Ref.ConstantDiscrete 0))
        triples actual @?= replicate 20 (5, 1, True)
        Ref.nativeReturnObservedEvaluationTransitions actual @?= 20
    , testCase "nonfinite individual rewards accumulated returns and terminal observations fail closed" $ do
        forM_
          [ fixtureDiscrete {Sim.envStep = \state _ -> Sim.SimStep (state + 1) (0 / 0) True}
          , fixtureDiscrete {Sim.envStep = \state _ -> Sim.SimStep (state + 1) 1.0e308 False}
          ]
          $ \env ->
            expectLeft
              "native return reward or accumulated return is nonfinite"
              (Ref.evaluateDiscreteReference env 20 2 (Ref.ConstantDiscrete 0))
        expectLeft
          "native return reward or accumulated return is nonfinite"
          ( Ref.evaluateContinuousReference
              fixtureContinuous {Sim.cEnvStep = \state _ -> Sim.ContinuousSimStep (state + 1) (1 / 0) True}
              20
              1
              (Ref.ConstantContinuous Ref.NativeZero 0)
          )
        expectLeft
          "native return simulator observation shape or finite values differ"
          ( Ref.evaluateDiscreteReference
              fixtureDiscrete
                { Sim.envRenderFrame = \state -> Sim.RenderFrame [if state == 0 then 0 else 0 / 0] "bad terminal"
                }
              20
              1
              (Ref.ConstantDiscrete 0)
          )
    , testCase "invalid dimensions and simulator metadata reject before reference execution" $ do
        forM_ [(0, 1), (1, 0), (-1, 1), (1, -1)] $ \(count, horizon) ->
          expectLeft
            "native return evaluation count and horizon must be positive"
            (Ref.evaluateDiscreteReference fixtureDiscrete count horizon (Ref.ConstantDiscrete 0))
        forM_
          [ fixtureDiscrete {Sim.envActionCount = 0}
          , fixtureDiscrete {Sim.envObservationSize = 0}
          , fixtureDiscrete {Sim.envMaxEpisodeSteps = 0}
          ]
          $ \env ->
            expectLeft "native discrete simulator metadata is invalid" (Ref.discreteReferenceControllers env)
        expectLeft
          "native return simulator observation shape or finite values differ"
          ( Ref.evaluateContinuousReference
              fixtureContinuous {Sim.cEnvObservation = const []}
              20
              1
              (Ref.ConstantContinuous Ref.NativeZero 0)
          )
    , testCase "distinct native labels remain explicit when zero equals one endpoint" $ do
        let env = fixtureContinuous {Sim.cEnvActionLow = 0, Sim.cEnvActionHigh = 2}
        controllers <- expectRight (Ref.continuousReferenceControllers env)
        length controllers @?= 3
        length (nub (fmap Ref.nativeReturnControllerId controllers)) @?= 3
        fmap Ref.nativeReturnControllerId controllers
          @?= ["native-zero", "native-lower-endpoint", "native-upper-endpoint"]
        observations <- traverse (expectRight . Ref.evaluateContinuousReference env 20 1) controllers
        fmap triples observations
          @?= [replicate 20 (0, 1, False), replicate 20 (0, 1, False), replicate 20 (2, 1, False)]
    ]

assertProjection
  :: Ref.NativeReturnReferenceSpec -> Matrix.ProductRow 'Matrix.Declared -> Substrate -> Assertion
assertProjection spec row lane = case Matrix.projectProductRow lane row of
  Plan.Failure errors -> assertFailure (show errors)
  Plan.Success (Matrix.SomeProductProjection _ projection) -> do
    Matrix.productProjectionRowId projection @?= Ref.nativeReturnSpecRowId spec
    let seedlessBudget = Ref.nativeReturnSpecBudget spec
    Budget.trainingBudgetSeed seedlessBudget @?= Nothing
    expectedSeededBudget <-
      expectRight
        ( Budget.mkTrainingBudget
            (Budget.trainingBudgetKind seedlessBudget)
            (Budget.trainingBudgetTargetUnits seedlessBudget)
            (Just 42)
        )
    Matrix.productProjectionTrainingBudget projection @?= expectedSeededBudget
    fmap
      toInteger
      (NE.toList (Plan.seedCohortValues (Plan.runPlanSeeds (Matrix.productProjectionRunPlan projection))))
      @?= [42]
    case Matrix.productProjectionDescriptor projection of
      Matrix.RlProductDescriptor algorithm environment _ _ horizon count -> do
        algorithm @?= Ref.nativeReturnSpecAlgorithm spec
        environment @?= Ref.nativeReturnSpecEnvironment spec
        toInteger horizon @?= toInteger (Ref.nativeReturnSpecHorizon spec)
        toInteger count @?= toInteger (Ref.nativeReturnSpecEpisodeCount spec)
      _ -> assertFailure "return row projected a non-return descriptor"

firstRow :: IO Thresholds.FixedBudgetRlConvergenceRow
firstRow = firstValue Thresholds.fixedBudgetRlConvergenceRows
firstValue :: [value] -> IO value
firstValue values = case values of first : _ -> pure first; [] -> assertFailure "required actual canonical value absent"

triples :: Ref.NativeReturnReferenceObservation -> [(Double, Int, Bool)]
triples =
  fmap
    ( \e ->
        ( Ref.nativeReturnEpisodeReward e
        , Ref.nativeReturnEpisodeSteps e
        , Ref.nativeReturnEpisodeTerminated e
        )
    )
    . Ref.nativeReturnObservedEpisodes

-- Independent simple simulator oracles: fresh current functions, no stored
-- numerical return target, learner, learned-network or production-ref helper.
directDiscrete
  :: Sim.SimulatedEnvironment state -> Ref.NativeReturnController -> Int -> (Double, Int, Bool)
directDiscrete env controller horizon = go (Sim.envInitial env) 0 0
 where
  go state steps reward
    | steps == horizon = (reward, steps, False)
    | otherwise =
        let action = case controller of
              Ref.ConstantDiscrete value -> value
              Ref.FixedMaskedPreference preference -> case Sim.envActionMask env of
                Just maskFor -> case [a | a <- preference, maskFor state !! a] of
                  a : _ -> a
                  [] -> error "direct actual mask has no legal action"
                Nothing -> error "direct masked controller has no mask"
              _ -> error "direct discrete oracle got a continuous controller"
            result = Sim.envStep env state action
            total = reward + Sim.simStepReward result
         in if Sim.simStepDone result
              then (total, steps + 1, True)
              else go (Sim.simStepState result) (steps + 1) total

directContinuous :: Sim.ContinuousEnvironment state -> Double -> Int -> (Double, Int, Bool)
directContinuous env action horizon = go (Sim.cEnvInitial env) 0 0
 where
  go state steps reward
    | steps == horizon = (reward, steps, False)
    | otherwise =
        let result = Sim.cEnvStep env state action; total = reward + Sim.cStepReward result
         in if Sim.cStepDone result
              then (total, steps + 1, True)
              else go (Sim.cStepState result) (steps + 1) total

fixtureDiscrete :: Sim.SimulatedEnvironment Int
fixtureDiscrete =
  Sim.SimulatedEnvironment
    { Sim.envName = "offline-reference"
    , Sim.envInitial = 0
    , Sim.envStep = \state action -> Sim.SimStep (state + 1) (fromIntegral action) False
    , Sim.envRenderFrame = \state -> Sim.RenderFrame [fromIntegral state] "offline"
    , Sim.envActionCount = 3
    , Sim.envObservationSize = 1
    , Sim.envMaxEpisodeSteps = 10
    , Sim.envActionMask = Nothing
    , Sim.envTrainingStart = Nothing
    }

fixtureContinuous :: Sim.ContinuousEnvironment Int
fixtureContinuous =
  Sim.ContinuousEnvironment
    { Sim.cEnvName = "offline-native-control"
    , Sim.cEnvInitial = 0
    , Sim.cEnvStep = \state action -> Sim.ContinuousSimStep (state + 1) action False
    , Sim.cEnvObservation = \state -> [fromIntegral state]
    , Sim.cEnvActionLow = -2
    , Sim.cEnvActionHigh = 2
    , Sim.cEnvObservationSize = 1
    , Sim.cEnvMaxEpisodeSteps = 10
    }

expectRight :: (Show error) => Either error value -> IO value
expectRight actual = case actual of Right value -> pure value; Left reason -> assertFailure (show reason)
expectLeft :: (Show value) => Text -> Either Text value -> Assertion
expectLeft expected actual = case actual of
  Left reason -> reason @?= expected
  Right value -> assertFailure ("expected exact rejection " <> show expected <> "; got " <> show value)
