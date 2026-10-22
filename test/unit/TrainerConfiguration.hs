{-# LANGUAGE OverloadedStrings #-}

-- Offline data/callback controls. No hardware, training qualification or origin
-- is inferred. Malformed public DTOs below are deliberate boundary negatives.
module TrainerConfiguration (trainerConfigurationTests) where

import Control.Exception (SomeException, displayException, try)
import Control.Monad (forM_)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.Text (Text)
import Data.Text qualified as Text
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.Numerics.MlpDevice (MlpDevice (..), pureReferenceMlpDevice)
import JitML.RL.Algorithms.Common qualified as Common
import JitML.RL.Algorithms.ContinuousTrainer qualified as Continuous
import JitML.RL.Algorithms.DqnTrainer qualified as Dqn
import JitML.RL.Algorithms.HerTrainer qualified as Her
import JitML.RL.Algorithms.PpoTrainer qualified as Ppo
import JitML.RL.Algorithms.QrDqnTrainer qualified as Qr
import JitML.RL.Algorithms.Registry qualified as Registry
import JitML.RL.ProductBudget qualified as Budget
import JitML.RL.Simulator qualified as Sim
import JitML.RL.TrainerConfiguration qualified as Configuration
import JitML.RL.TrainerExecution qualified as Execution
import JitML.RL.TrainerObservation qualified as Observation
import JitML.Substrate (Substrate (LinuxCPU))

trainerConfigurationTests :: TestTree
trainerConfigurationTests =
  testGroup
    "shared neural trainer configuration"
    [ testCase "the thirteen legacy neural selectors retain their exact diagnostic order" $
        Configuration.knownNeuralTrainerKinds
          @?= [ "ppo"
              , "a2c"
              , "trpo"
              , "maskableppo"
              , "recurrentppo"
              , "dqn"
              , "qrdqn"
              , "ddpg"
              , "td3"
              , "sac"
              , "crossq"
              , "tqc"
              , "her"
              ]
    , testCase
        "all thirty nine compatible neural registry cohorts resolve their actual plan and environment"
        $ do
          length neuralCohorts @?= 39
          forM_ neuralCohorts $ \cohort -> do
            plan <- compileFor (Registry.cohortTrainerKind cohort) (Registry.cohortEnvironmentName cohort) 42 1
            recipe <- mustRight (Configuration.resolveNeuralTrainerRecipe plan)
            Configuration.neuralTrainerPlan recipe @?= plan
            assertRecipeContext plan recipe
    , testCase "family elimination selects exactly one actual handler without demanding alternatives" $
        forM_ neuralCohorts $ \cohort -> do
          let kind = Registry.cohortTrainerKind cohort
          plan <- compileFor kind (Registry.cohortEnvironmentName cohort) 42 1
          recipe <- mustRight (Configuration.resolveNeuralTrainerRecipe plan)
          selectedFamily kind recipe @?= kind
    , testCase "changing only the compiled seed preserves every other configuration field" $
        forM_ neuralCohorts $ \cohort -> do
          first <- compileFor (Registry.cohortTrainerKind cohort) (Registry.cohortEnvironmentName cohort) 7 1
          second <-
            compileFor (Registry.cohortTrainerKind cohort) (Registry.cohortEnvironmentName cohort) 42 1
          a <- mustRight (Configuration.resolveNeuralTrainerRecipe first)
          b <- mustRight (Configuration.resolveNeuralTrainerRecipe second)
          configSeed (Configuration.neuralTrainerConfiguration a) @?= 7
          configSeed (Configuration.neuralTrainerConfiguration b) @?= 42
          eraseSeed (Configuration.neuralTrainerConfiguration a)
            @?= eraseSeed (Configuration.neuralTrainerConfiguration b)
    , testCase "evaluation count cannot alter any full training configuration field" $
        forM_ neuralCohorts $ \cohort -> do
          first <- compileFor (Registry.cohortTrainerKind cohort) (Registry.cohortEnvironmentName cohort) 42 1
          second <-
            compileFor (Registry.cohortTrainerKind cohort) (Registry.cohortEnvironmentName cohort) 42 20
          a <- mustRight (Configuration.resolveNeuralTrainerRecipe first)
          b <- mustRight (Configuration.resolveNeuralTrainerRecipe second)
          Configuration.neuralTrainerConfiguration a @?= Configuration.neuralTrainerConfiguration b
    , testCase "the actual public compiler vector width reaches the on policy configuration" $ do
        plan <- compileFor "ppo" "cartpole" 42 1
        let training = (Budget.compiledRlTraining plan) {Budget.trainingPlanVectorEnvironments = Just 3}
        vectorPlan <- mustRight (Budget.compileRlPlan training (Budget.compiledRlEvaluation plan))
        recipe <- mustRight (Configuration.resolveNeuralTrainerRecipe vectorPlan)
        case Configuration.neuralTrainerConfiguration recipe of
          Configuration.OnPolicyConfiguration config -> Ppo.ppoVectorEnvCount config @?= 3
          _ -> assertFailure "PPO resolved to a different family"
    , testCase "changed public transition requests reach the scheduled fixed step configuration" $ do
        plan <- compileFor "dqn" "cartpole" 42 1
        let training = Budget.compiledRlTraining plan
            requested target =
              Budget.compileRlPlan
                (training {Budget.trainingPlanRequestedTransitionFloor = Just target})
                (Budget.compiledRlEvaluation plan)
        first <- mustRight (requested 1000000)
        second <- mustRight (requested 2000000)
        a <- mustRight (Configuration.resolveNeuralTrainerRecipe first)
        b <- mustRight (Configuration.resolveNeuralTrainerRecipe second)
        assertRecipeContext first a
        assertRecipeContext second b
        assertBool
          "different requests must produce different actual schedules"
          (Budget.compiledRlSchedule first /= Budget.compiledRlSchedule second)
    , testCase "unknown pure selectors fail without producing a recipe" $ do
        plan <- compileFor "ppo" "cartpole" 42 1
        let bad = alterTraining (\training -> training {Budget.trainingPlanTrainerKind = "unknown-neural"}) plan
        expectLeft "unhandled RL trainer: unknown-neural" (Configuration.resolveNeuralTrainerRecipe bad)
    , testCase "discrete environment lookup rejects before demanding a malformed schedule" $
        forM_ ["ppo", "dqn", "qrdqn"] $ \kind -> do
          plan <- compileFor kind "cartpole" 42 1
          let bad =
                (alterTraining (\training -> training {Budget.trainingPlanEnvironment = "missing-discrete"}) plan)
                  { Budget.compiledRlSchedule = Just (error "schedule must remain undemanded")
                  }
          expectLeft
            "unknown discrete RL environment: missing-discrete"
            (Configuration.resolveNeuralTrainerRecipe bad)
    , testCase "continuous environment lookup rejects before demanding a malformed schedule" $ do
        plan <- compileFor "sac" "pendulum" 42 1
        let bad =
              (alterTraining (\training -> training {Budget.trainingPlanEnvironment = "missing-continuous"}) plan)
                { Budget.compiledRlSchedule = Just (error "schedule must remain undemanded")
                }
        expectLeft
          "unknown continuous RL environment: missing-continuous"
          (Configuration.resolveNeuralTrainerRecipe bad)
    , testCase "every known family rejects absent schedules at its original boundary" $
        forM_ neuralCohorts $ \cohort -> do
          let kind = Registry.cohortTrainerKind cohort
          plan <- compileFor kind (Registry.cohortEnvironmentName cohort) 42 1
          expectLeft
            ("internal RL schedule kind mismatch for " <> kind)
            (Configuration.resolveNeuralTrainerRecipe (plan {Budget.compiledRlSchedule = Nothing}))
    , testCase "known environments reject a foreign schedule constructor" $ do
        onPolicy <- compileFor "ppo" "cartpole" 42 1
        dqn <- compileFor "dqn" "cartpole" 42 1
        her <- compileFor "her" "goal-reaching" 42 1
        expectLeft
          "internal RL schedule kind mismatch for ppo"
          ( Configuration.resolveNeuralTrainerRecipe
              (onPolicy {Budget.compiledRlSchedule = Budget.compiledRlSchedule dqn})
          )
        expectLeft
          "internal RL schedule kind mismatch for dqn"
          ( Configuration.resolveNeuralTrainerRecipe
              (dqn {Budget.compiledRlSchedule = Budget.compiledRlSchedule her})
          )
        expectLeft
          "internal RL schedule kind mismatch for her"
          ( Configuration.resolveNeuralTrainerRecipe
              (her {Budget.compiledRlSchedule = Budget.compiledRlSchedule onPolicy})
          )
    , testCase "legacy unknown selector rejection precedes every device callback" $ do
        plan <- compileFor "ppo" "cartpole" 42 1
        let bad = alterTraining (\training -> training {Budget.trainingPlanTrainerKind = "unknown-neural"}) plan
        events <- newIORef []
        result <- Execution.runTrainerEpisodesForPlan LinuxCPU (recordingDevice events False) Nothing bad
        case result of
          Left message ->
            assertBool
              "unknown diagnostic preserved"
              ("unknown RL trainer: unknown-neural" `Text.isPrefixOf` message)
          Right _ -> assertFailure "unknown selector unexpectedly succeeded"
        readIORef events >>= (@?= [])
    , testCase "legacy incompatible cohort rejection precedes every device callback" $ do
        plan <- compileFor "ppo" "cartpole" 42 1
        let bad = alterTraining (\training -> training {Budget.trainingPlanTrainerKind = "her"}) plan
        expected <-
          maybe
            (assertFailure "fixture must be incompatible" >> fail "incompatible fixture")
            pure
            (Budget.rlTrainerEnvironmentCompatibilityError "her" "cartpole")
        events <- newIORef []
        result <- Execution.runTrainerEpisodesForPlan LinuxCPU (recordingDevice events False) Nothing bad
        expectLeft expected result
        readIORef events >>= (@?= [])
    , testCase "legacy probe failure precedes schedule demand and never queries a witness" $ do
        plan <- compileFor "ppo" "cartpole" 42 1
        let bad = plan {Budget.compiledRlSchedule = Just (error "schedule demanded after failed probe")}
        events <- newIORef []
        result <- Execution.runTrainerEpisodesForPlan LinuxCPU (recordingDevice events False) Nothing bad
        expectLeft "RL substrate device unavailable for trainer ppo: fixture-probe-stop" result
        readIORef events >>= (@?= ["forward-batch"])
    , testCase "legacy successful probe reaches the original schedule demand before training" $ do
        plan <- compileFor "ppo" "cartpole" 42 1
        let bad = plan {Budget.compiledRlSchedule = Just (error "actual-post-probe-schedule-demand")}
        events <- newIORef []
        attempted <-
          try (Execution.runTrainerEpisodesForPlan LinuxCPU (recordingDevice events True) Nothing bad)
            :: IO (Either SomeException (Either Text Execution.TrainerRun))
        case attempted of
          Left exception ->
            assertBool
              "actual schedule error retained"
              ("actual-post-probe-schedule-demand" `Text.isInfixOf` Text.pack (displayException exception))
          Right _ -> assertFailure "malformed schedule was not demanded"
        readIORef events >>= (@?= ["forward-batch"])
    , testCase "legacy zero iteration raw return is rejected before final evaluation and witness" $ do
        plan <- zeroIterationPlan
        events <- newIORef []
        result <- Execution.runTrainerEpisodesForPlan LinuxCPU (recordingDevice events True) Nothing plan
        expectLeft "RL measured environment-transition count must be positive" result
        readIORef events >>= (@?= ["forward-batch"])
    , testCase "raw zero iteration result retains its actual failed final evaluation without witness" $ do
        plan <- zeroIterationPlan
        events <- newIORef []
        result <-
          Execution.runRawTrainerObservationForPlan LinuxCPU (recordingDevice events True) Nothing plan
        case result of
          Observation.TrainerReturned observed -> do
            Common.observedEnvironmentTransitionCount
              (Observation.returnedCounters (Observation.observedPolicy observed))
              @?= 0
            Common.observedOptimizerUpdateCount
              (Observation.returnedCounters (Observation.observedPolicy observed))
              @?= 0
            Observation.observedEvaluation observed
              @?= Observation.EvaluationFailed
                ( Observation.EvaluationRejected
                    "on-policy device forward kernel failed during evaluation: fixture-final-forward-stop"
                )
          other -> assertFailure ("expected an actual zero raw return, got " <> show other)
        readIORef events >>= (@?= ["forward-batch", "forward"])
    ]

-- Includes all generic neural compatibility rows, broader than the ProductRow
-- catalogue. It contains no copied default/configuration table.
neuralCohorts :: [Registry.RLCohort]
neuralCohorts =
  filter
    ((`elem` Configuration.knownNeuralTrainerKinds) . Registry.cohortTrainerKind)
    Registry.allCohorts

compileFor :: Text -> Text -> Int -> Int -> IO Budget.CompiledRlPlan
compileFor kind environment seed evaluations =
  mustRight $
    Budget.compileRlPlan
      Budget.TrainingPlan
        { Budget.trainingPlanTrainerKind = kind
        , Budget.trainingPlanEnvironment = environment
        , Budget.trainingPlanSeed = seed
        , Budget.trainingPlanMaxEpisodeSteps = 1
        , Budget.trainingPlanEpisodeBudgetFloor = 1
        , Budget.trainingPlanVectorEnvironments = Just 1
        , Budget.trainingPlanRequestedTransitionFloor = Nothing
        , Budget.trainingPlanExactTransitionTarget = Nothing
        }
      (Budget.EvaluationPlan evaluations)

alterTraining
  :: (Budget.TrainingPlan -> Budget.TrainingPlan) -> Budget.CompiledRlPlan -> Budget.CompiledRlPlan
alterTraining change plan = plan {Budget.compiledRlTraining = change (Budget.compiledRlTraining plan)}

zeroIterationPlan :: IO Budget.CompiledRlPlan
zeroIterationPlan = do
  plan <- compileFor "ppo" "cartpole" 42 1
  case Budget.compiledRlSchedule plan of
    Just schedule@Budget.OnPolicyTrainingSchedule {} ->
      pure
        ( plan
            { Budget.compiledRlSchedule =
                Just (schedule {Budget.scheduleOnPolicyIterations = 0, Budget.scheduleObservedEnvironmentSteps = 0})
            }
        )
    _ -> assertFailure "compiler returned the wrong schedule" >> fail "schedule fixture"

mustRight :: (Show e) => Either e a -> IO a
mustRight result = case result of
  Left err -> assertFailure (show err) >> fail "unexpected Left"
  Right value -> pure value

expectLeft :: Text -> Either Text a -> Assertion
expectLeft expected result = case result of
  Left actual -> actual @?= expected
  Right _ -> assertFailure ("expected Left: " <> Text.unpack expected)

selectedFamily :: Text -> Configuration.NeuralTrainerRecipe -> Text
selectedFamily expected =
  Configuration.foldNeuralTrainerRecipe
    ( \variant _ _ ->
        checked
          ( case variant of
              Ppo.VariantPPO -> "ppo"
              Ppo.VariantA2C -> "a2c"
              Ppo.VariantTRPO -> "trpo"
              Ppo.VariantMaskablePPO -> "maskableppo"
              Ppo.VariantRecurrentPPO -> "recurrentppo"
          )
    )
    (\_ _ -> checked "dqn")
    (\_ _ -> checked "qrdqn")
    ( \_ config ->
        checked
          ( case Continuous.ctVariant config of
              Continuous.VariantDDPG -> "ddpg"
              Continuous.VariantTD3 -> "td3"
              Continuous.VariantSAC -> "sac"
              Continuous.VariantCrossQ -> "crossq"
              Continuous.VariantTQC -> "tqc"
          )
    )
    (const (checked "her"))
 where
  checked actual
    | actual == expected = actual
    | otherwise = error "an unselected family handler was demanded"

configSeed :: Configuration.NeuralTrainerConfiguration -> Int
configSeed config = case config of
  Configuration.OnPolicyConfiguration value -> Ppo.ppoSeed value
  Configuration.DqnConfiguration value -> Dqn.dqnSeed value
  Configuration.QrDqnConfiguration value -> Qr.qrSeed value
  Configuration.ContinuousConfiguration value -> Continuous.ctSeed value
  Configuration.HerConfiguration value -> Her.herSeed value

eraseSeed :: Configuration.NeuralTrainerConfiguration -> Configuration.NeuralTrainerConfiguration
eraseSeed config = case config of
  Configuration.OnPolicyConfiguration value -> Configuration.OnPolicyConfiguration (value {Ppo.ppoSeed = 0})
  Configuration.DqnConfiguration value -> Configuration.DqnConfiguration (value {Dqn.dqnSeed = 0})
  Configuration.QrDqnConfiguration value -> Configuration.QrDqnConfiguration (value {Qr.qrSeed = 0})
  Configuration.ContinuousConfiguration value -> Configuration.ContinuousConfiguration (value {Continuous.ctSeed = 0})
  Configuration.HerConfiguration value -> Configuration.HerConfiguration (value {Her.herSeed = 0})

assertRecipeContext :: Budget.CompiledRlPlan -> Configuration.NeuralTrainerRecipe -> Assertion
assertRecipeContext plan =
  Configuration.foldNeuralTrainerRecipe
    ( \variant (Sim.SomeSimulatedEnvironment environment) config -> do
        Ppo.ppoVariant config @?= variant
        Ppo.ppoSeed config @?= Budget.compiledRlSeed plan
        Ppo.ppoObsSize config @?= Sim.envObservationSize environment
        Ppo.ppoActionCount config @?= Sim.envActionCount environment
        case Budget.compiledRlSchedule plan of
          Just schedule@Budget.OnPolicyTrainingSchedule {} -> do
            Ppo.ppoNumIterations config @?= Budget.scheduleOnPolicyIterations schedule
            Ppo.ppoRolloutSteps config @?= Budget.scheduleOnPolicyRolloutSteps schedule
            Ppo.ppoVectorEnvCount config @?= Budget.scheduleOnPolicyVectorEnvironments schedule
            Ppo.ppoMaxEpisodeSteps config @?= Budget.scheduleOnPolicyMaxEpisodeSteps schedule
          _ -> assertFailure "on-policy schedule mismatch"
    )
    ( \(Sim.SomeSimulatedEnvironment environment) config -> do
        Dqn.dqnSeed config @?= Budget.compiledRlSeed plan
        Dqn.dqnObsSize config @?= Sim.envObservationSize environment
        Dqn.dqnActionCount config @?= Sim.envActionCount environment
        assertFixed plan (Dqn.dqnNumSteps config) (Dqn.dqnMaxEpisodeSteps config)
    )
    ( \(Sim.SomeSimulatedEnvironment environment) config -> do
        Qr.qrSeed config @?= Budget.compiledRlSeed plan
        Qr.qrObsSize config @?= Sim.envObservationSize environment
        Qr.qrActionCount config @?= Sim.envActionCount environment
        assertFixed plan (Qr.qrNumSteps config) (Qr.qrMaxEpisodeSteps config)
    )
    ( \(Sim.SomeContinuousEnvironment environment) config -> do
        Continuous.ctSeed config @?= Budget.compiledRlSeed plan
        Continuous.ctObsSize config @?= Sim.cEnvObservationSize environment
        Continuous.ctActionLow config @?= Sim.cEnvActionLow environment
        Continuous.ctActionHigh config @?= Sim.cEnvActionHigh environment
        Continuous.ctEnvName config @?= Budget.compiledRlEnvironment plan
        assertFixed plan (Continuous.ctNumSteps config) (Continuous.ctMaxEpisodeSteps config)
    )
    ( \config -> do
        Her.herSeed config @?= Budget.compiledRlSeed plan
        case Budget.compiledRlSchedule plan of
          Just schedule@Budget.HerTrainingSchedule {} -> Her.herEpisodes config @?= Budget.scheduleHerEpisodes schedule
          _ -> assertFailure "HER schedule mismatch"
    )

assertFixed :: Budget.CompiledRlPlan -> Int -> Int -> Assertion
assertFixed plan steps horizon = case Budget.compiledRlSchedule plan of
  Just schedule@Budget.FixedStepTrainingSchedule {} -> do
    steps @?= Budget.scheduleFixedSteps schedule
    horizon @?= Budget.scheduleFixedMaxEpisodeSteps schedule
  _ -> assertFailure "fixed-step schedule mismatch"

recordingDevice :: IORef [Text] -> Bool -> MlpDevice
recordingDevice events probeSucceeds =
  pureReferenceMlpDevice
    { mlpdForwardBatch = \params inputs -> do
        record "forward-batch"
        if probeSucceeds
          then mlpdForwardBatch pureReferenceMlpDevice params inputs
          else pure (Left "fixture-probe-stop")
    , mlpdForward = \_ _ -> record "forward" >> pure (Left "fixture-final-forward-stop")
    , mlpdBackward = \_ _ _ -> record "backward" >> pure (Left "unexpected-backward")
    , mlpdBatchGradient = \_ _ -> record "batch-gradient" >> pure (Left "unexpected-batch-gradient")
    , mlpdInputGradientBatch = \_ _ -> record "input-gradient" >> pure (Left "unexpected-input-gradient")
    , mlpdExecutionWitness = record "witness" >> pure (Right Nothing)
    }
 where
  record event = modifyIORef' events (<> [event])
