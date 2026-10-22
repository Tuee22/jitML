{-# LANGUAGE OverloadedStrings #-}

module TrainerObservation (trainerObservationTests) where

import Control.Exception (IOException, throwIO, try)
import Control.Monad (forM_)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word64)
import JitML.Checkpoint.Format qualified as Checkpoint
import JitML.Numerics.Mlp qualified as Mlp
import JitML.Numerics.MlpDevice (MlpDevice (..), pureReferenceMlpDevice)
import JitML.RL.Algorithms.ArsTrainer qualified as Ars
import JitML.RL.Algorithms.Common qualified as Common
import JitML.RL.Algorithms.ContinuousTrainer qualified as Continuous
import JitML.RL.Algorithms.DqnTrainer qualified as Dqn
import JitML.RL.Algorithms.HerTrainer qualified as Her
import JitML.RL.Algorithms.PpoTrainer qualified as Ppo
import JitML.RL.Algorithms.QrDqnTrainer qualified as Qr
import JitML.RL.EpisodeEnvelope qualified as Episode
import JitML.RL.Framework qualified as Framework
import JitML.RL.ProductBudget qualified as Plan
import JitML.RL.Simulator qualified as Sim
import JitML.RL.TrainerExecution qualified as Execution
import JitML.RL.TrainerObservation qualified as Observation
import JitML.Substrate (Substrate (..))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

-- Offline numerical/callback controls only. Pure and hostile fixture devices
-- do not attest real substrate execution, convergence or producer identity.
trainerObservationTests :: TestTree
trainerObservationTests =
  testGroup
    "raw RL initial state and uncensored returns"
    [ testCase "raw counters retain zero without weakening the existing positive constructor" $ do
        zero <- expectRight (Common.mkObservedTrainerCounters 3 0)
        Common.observedEnvironmentTransitionCount zero @?= 3
        Common.observedOptimizerUpdateCount zero @?= 0
        expectLeft "optimizer-update count must be positive" (Common.refineObservedTrainerCounters zero)
        expectLeft "environment-transition count must be positive" (Common.mkMeasuredTrainerCounters 0 1)
        expectLeft "non-negative" (Common.mkObservedTrainerCounters (-1) 0)
        expectLeft "Word64" (Common.mkObservedTrainerCounters 1 (toInteger (maxBound :: Word64) + 1))
    , testCase "actual PPO callback initial parameters survive training and strict result refinement" $ do
        calls <- newIORef []
        raw <-
          Ppo.trainOnPolicyOnDeviceWithEnvironmentRaw (recording calls) cartpole Ppo.VariantPPO ppoConfig
            >>= expectRight
        firstActual calls >>= (\initial -> assertSameParams initial (Common.rawTrainerInitialParams raw))
        assertBool
          "a genuine optimizer application changed the returned tensor"
          (Common.rawTrainerFinalParams raw /= Common.rawTrainerInitialParams raw)
        strict <- expectRight (Ppo.refinePpoTrainObservation raw)
        Ppo.resultInitialParams strict @?= Common.rawTrainerInitialParams raw
        Ppo.resultFinalParams strict @?= Common.rawTrainerFinalParams raw
        Ppo.resultConfig strict @?= Common.rawTrainerConfig raw
        Ppo.resultIterations strict @?= Common.rawTrainerStats raw
    , testCase "actual DQN online callback initial parameters survive all recursive steps" $ do
        calls <- newIORef []
        raw <- Dqn.trainDqnOnDeviceWithEnvironmentRaw (recording calls) cartpole dqnConfig >>= expectRight
        firstActual calls >>= (\initial -> assertSameParams initial (Common.rawTrainerInitialParams raw))
        strict <- expectRight (Dqn.refineDqnTrainObservation raw)
        Dqn.dqnResultInitialParams strict @?= Common.rawTrainerInitialParams raw
        assertBool
          "DQN performed actual updates"
          (Common.observedOptimizerUpdateCount (Common.rawTrainerCounters raw) > 0)
        assertBool
          "DQN final tensor changed"
          (Common.rawTrainerFinalParams raw /= Common.rawTrainerInitialParams raw)
    , testCase "actual quantile callback initial parameters survive all recursive steps" $ do
        calls <- newIORef []
        raw <- Qr.trainQrDqnOnDeviceWithEnvironmentRaw (recording calls) cartpole qrConfig >>= expectRight
        firstActual calls >>= (\initial -> assertSameParams initial (Common.rawTrainerInitialParams raw))
        strict <- expectRight (Qr.refineQrDqnTrainObservation raw)
        Qr.qrResultInitialParams strict @?= Common.rawTrainerInitialParams raw
        assertBool
          "quantile tensor changed"
          (Common.rawTrainerFinalParams raw /= Common.rawTrainerInitialParams raw)
    , testCase "SAC retains the actual warm-start actor seen by the first device callback" $ do
        calls <- newIORef []
        raw <-
          Continuous.trainContinuousOnDeviceWithEnvironmentRaw
            (recording calls)
            (Sim.SomeContinuousEnvironment Sim.pendulumEnvironment)
            sacConfig
            >>= expectRight
        observed <- reverse <$> readIORef calls
        let actualActorCalls = [p | p <- observed, Mlp.paramShape p == Mlp.MlpShape 3 1 1]
        case actualActorCalls of
          first : _ -> assertSameParams first (Common.rawTrainerInitialParams raw)
          [] -> assertFailure "actual SAC actor device callbacks were not executed"
        assertBool
          "retained initialization includes actual warm-start fitting"
          (Common.rawTrainerInitialParams raw /= Mlp.mlpInit (Mlp.MlpShape 3 1 1) (Continuous.ctSeed sacConfig))
        strict <- expectRight (Continuous.refineContinuousTrainObservation raw)
        Continuous.contResultInitialActor strict @?= Common.rawTrainerInitialParams raw
    , testCase "actual HER online callback initial parameters survive the episode recursion" $ do
        calls <- newIORef []
        raw <- Her.trainHerOnDeviceRaw (recording calls) herConfig >>= expectRight
        firstActual calls >>= (\initial -> assertSameParams initial (Common.rawTrainerInitialParams raw))
        strict <- expectRight (Her.refineHerTrainObservation raw)
        Her.herResultInitialParams strict @?= Common.rawTrainerInitialParams raw
        assertBool
          "HER final tensor changed"
          (Common.rawTrainerFinalParams raw /= Common.rawTrainerInitialParams raw)
    , testCase "pure entrypoints retain their actual initial policies and configuration too" $ do
        p <- Ppo.trainPpoOnCartpole ppoConfig
        d <- Dqn.trainDqnOnCartpole dqnConfig
        q <- Qr.trainQrDqnOnCartpole qrConfig
        c <- Continuous.trainContinuousOnPendulum continuousConfig
        h <- Her.trainHerOnBitFlip herConfig
        a <- Ars.trainArsOnCartpole arsConfig
        Ppo.resultConfig p @?= ppoConfig
        Dqn.dqnResultConfig d @?= dqnConfig
        Qr.qrResultConfig q @?= qrConfig
        Continuous.contResultConfig c @?= continuousConfig
        Her.herResultConfig h @?= herConfig
        Ars.arsResultConfig a @?= arsConfig
        Ppo.resultInitialParams p @?= Ppo.initialPpoParams ppoConfig
        Dqn.dqnResultInitialParams d @?= Dqn.initialDqnParams dqnConfig
        Qr.qrResultInitialParams q @?= Qr.initialQrDqnParams qrConfig
        Continuous.contResultInitialActor c @?= Continuous.initialContinuousActor continuousConfig
        Her.herResultInitialParams h @?= Her.initialHerParams herConfig
        -- ARS is an explicit linear host policy; this test asks for no MLP witness.
        Ars.arsResultInitialParams a @?= VU.replicate 8 0
        Common.measuredEnvironmentTransitionCount (Ars.arsResultMeasuredCounters a) @?= 12
        Common.measuredOptimizerUpdateCount (Ars.arsResultMeasuredCounters a) @?= 1
    , testCase "a genuine zero-update return rejects before the strict evaluator action" $ do
        callbacks <- newIORef []
        let config =
              dqnConfig
                { Dqn.dqnTrainStart = 100
                , Dqn.dqnEpsilonStart = 1
                , Dqn.dqnEpsilonEnd = 1
                , Dqn.dqnStatInterval = 100
                }
        raw <- Dqn.trainDqnOnDeviceWithEnvironmentRaw (recording callbacks) cartpole config >>= expectRight
        Common.observedEnvironmentTransitionCount (Common.rawTrainerCounters raw) @?= 3
        Common.observedOptimizerUpdateCount (Common.rawTrainerCounters raw) @?= 0
        Common.rawTrainerFinalParams raw @?= Common.rawTrainerInitialParams raw
        Common.rawTrainerStats raw @?= []
        readIORef callbacks >>= (@?= [])
        evaluations <- newIORef (0 :: Int)
        let evaluate = modifyIORef' evaluations (+ 1) >> pure (Right ())
        actual <- Execution.evaluateStrictTrainerReturn (Observation.ReturnedDqn raw) evaluate
        expectLeft "optimizer-update count must be positive" actual
        readIORef evaluations >>= (@?= 0)
        old <- Dqn.trainDqnOnDeviceWithEnvironment (recording callbacks) cartpole config
        expectLeft "optimizer-update count must be positive" old
        readIORef callbacks >>= (@?= [])
    , testCase "budget-complete refinement retains actual zero-update motionless empty-curve data" $ do
        (plan, raw, observation) <- actualZeroBudgetReturn
        complete <- expectRight (Observation.refineBudgetCompleteTrainerObservation observation)
        Observation.budgetCompleteObservation complete @?= observation
        Observation.observedPlan observation @?= plan
        Common.rawTrainerInitialParams raw @?= Common.rawTrainerFinalParams raw
        Common.rawTrainerStats raw @?= []
        Common.observedOptimizerUpdateCount (Common.rawTrainerCounters raw) @?= 0
        expectLeft "optimizer-update count must be positive" (Dqn.refineDqnTrainObservation raw)
        let (_, filtered) = Observation.returnedLearningStatistics (Observation.observedPolicy observation)
        filtered @?= []
        expectLeft "at least one" (Framework.mkLearningCurve [])
    , testCase "raw refinement rejects physical-budget configuration shape and finite-data substitutions" $ do
        (_, raw, observation) <- actualZeroBudgetReturn
        wrong <- expectRight (Common.mkObservedTrainerCounters 1 0)
        let mutate changed = observation {Observation.observedPolicy = Observation.ReturnedDqn changed}
        expectLeft
          "transition budget"
          (Observation.refineBudgetCompleteTrainerObservation (mutate raw {Common.rawTrainerCounters = wrong}))
        expectLeft
          "configuration"
          ( Observation.refineBudgetCompleteTrainerObservation
              (mutate raw {Common.rawTrainerConfig = (Common.rawTrainerConfig raw) {Dqn.dqnSeed = 999}})
          )
        expectLeft
          "shape"
          ( Observation.refineBudgetCompleteTrainerObservation
              ( mutate
                  raw {Common.rawTrainerInitialParams = (Common.rawTrainerInitialParams raw) {Mlp.paramB2 = VU.empty}}
              )
          )
        expectLeft
          "shape"
          ( Observation.refineBudgetCompleteTrainerObservation
              ( mutate
                  raw
                    { Common.rawTrainerFinalParams =
                        (Common.rawTrainerFinalParams raw) {Mlp.paramB2 = VU.fromList [0 / 0, 0]}
                    }
              )
          )
        expectLeft
          "statistics"
          ( Observation.refineBudgetCompleteTrainerObservation
              (mutate raw {Common.rawTrainerStats = [Dqn.DqnIterationStat 1 0 (1 / 0) 0]})
          )
    , testCase "raw and strict probe failures retain the same reason and execute no trainer or witness" $ do
        plan <- compiledPlan "her" "goal-reaching"
        rawTrace <- newIORef []
        strictTrace <- newIORef []
        raw <-
          Execution.runRawTrainerObservationForPlan LinuxCPU (fixture rawTrace ProbeFailure) Nothing plan
        case raw of
          Observation.TrainerDidNotReturn (Observation.TrainingRejected err) -> assertBool "probe reason" ("probe sentinel" `Text.isInfixOf` err)
          _ -> assertFailure (show raw)
        Execution.runTrainerEpisodesForPlan LinuxCPU (fixture strictTrace ProbeFailure) Nothing plan
          >>= expectLeft "probe sentinel"
        readIORef rawTrace >>= (@?= ["probe"])
        readIORef strictTrace >>= (@?= ["probe"])
    , testCase "training Left and synchronous throw retain no invented returned state" $ do
        plan <- compiledPlan "her" "goal-reaching"
        forM_ [TrainingLeft, TrainingThrow] $ \failure -> do
          trace <- newIORef []
          raw <- Execution.runRawTrainerObservationForPlan LinuxCPU (fixture trace failure) Nothing plan
          case (failure, raw) of
            (TrainingLeft, Observation.TrainerDidNotReturn (Observation.TrainingRejected reason)) -> assertBool "actual Left" ("training sentinel" `Text.isInfixOf` reason)
            (TrainingThrow, Observation.TrainerDidNotReturn (Observation.TrainingThrew reason)) -> assertBool "actual exception" ("training throw sentinel" `Text.isInfixOf` reason)
            _ -> assertFailure (show raw)
          let expectedCalls =
                if failure == TrainingThrow
                  then ["probe", "batch-forward"]
                  else ["probe", "batch-forward", "batch-forward"]
          readIORef trace >>= (@?= expectedCalls) . reverse
          strictTrace <- newIORef []
          strict <-
            try (Execution.runTrainerEpisodesForPlan LinuxCPU (fixture strictTrace failure) Nothing plan)
              :: IO (Either IOException (Either Text Execution.TrainerRun))
          case (failure, strict) of
            (TrainingLeft, Right result) -> expectLeft "training sentinel" result
            (TrainingThrow, Left err) ->
              assertBool
                "strict still propagates IO exception"
                ("training throw sentinel" `Text.isInfixOf` Text.pack (show err))
            _ -> assertFailure (show strict)
          strictCalls <- readIORef strictTrace
          rawCalls <- readIORef trace
          strictCalls @?= rawCalls
    , testCase "failed final evaluation retains actual returned parameters counters and typed failure" $ do
        plan <- compiledPlan "her" "goal-reaching"
        forM_ [EvaluationLeft, EvaluationThrow] $ \failure -> do
          trace <- newIORef []
          raw <- Execution.runRawTrainerObservationForPlan LinuxCPU (fixture trace failure) Nothing plan
          observation <- expectReturned raw
          case (failure, Observation.observedEvaluation observation) of
            (EvaluationLeft, Observation.EvaluationFailed (Observation.EvaluationRejected reason)) -> assertBool "actual evaluation Left" ("evaluation sentinel" `Text.isInfixOf` reason)
            (EvaluationThrow, Observation.EvaluationFailed (Observation.EvaluationThrew reason)) -> assertBool "actual evaluation exception" ("evaluation throw sentinel" `Text.isInfixOf` reason)
            _ -> assertFailure (show observation)
          complete <- expectRight (Observation.refineBudgetCompleteTrainerObservation observation)
          Observation.budgetCompleteObservation complete @?= observation
          let policy = Observation.observedPolicy observation
          assertBool
            "the actual completed tensor is retained"
            (not (null (Observation.returnedFinalWeights policy)))
          assertBool
            "real updates were observed"
            (Common.observedOptimizerUpdateCount (Observation.returnedCounters policy) > 0)
          calls <- reverse <$> readIORef trace
          assertBool
            "actual train callbacks precede failed final evaluator"
            ("batch-gradient" `elem` calls && last calls == "forward")
          assertBool "raw numerical execution never queries a witness" ("witness" `notElem` calls)
          strictTrace <- newIORef []
          strict <-
            try (Execution.runTrainerEpisodesForPlan LinuxCPU (fixture strictTrace failure) Nothing plan)
              :: IO (Either IOException (Either Text Execution.TrainerRun))
          case (failure, strict) of
            (EvaluationLeft, Right result) -> expectLeft "evaluation sentinel" result
            (EvaluationThrow, Left err) ->
              assertBool
                "strict IO exception unchanged"
                ("evaluation throw sentinel" `Text.isInfixOf` Text.pack (show err))
            _ -> assertFailure (show strict)
          readIORef strictTrace >>= (@?= reverse calls)
    , testCase "strict motionless evidence failure occurs after evaluation without a witness" $ do
        plan <- compiledPlan "her" "goal-reaching"
        trace <- newIORef []
        actual <- Execution.runTrainerEpisodesForPlan LinuxCPU (fixture trace ZeroGradient) Nothing plan
        expectLeft "weight" actual
        calls <- reverse <$> readIORef trace
        assertBool
          "training and evaluation both ran"
          ("batch-gradient" `elem` calls && last calls == "forward")
        assertBool "failed evidence never queries a witness" ("witness" `notElem` calls)
    ]

cartpole :: Sim.SomeSimulatedEnvironment
cartpole = Sim.SomeSimulatedEnvironment Sim.cartPoleEnvironment

ppoConfig :: Ppo.PpoTrainConfig
ppoConfig =
  Ppo.defaultPpoTrainConfig
    { Ppo.ppoSeed = 13
    , Ppo.ppoHiddenUnits = 2
    , Ppo.ppoVectorEnvCount = 1
    , Ppo.ppoNumIterations = 1
    , Ppo.ppoRolloutSteps = 3
    , Ppo.ppoMiniBatchSize = 1
    , Ppo.ppoEpochsPerUpdate = 1
    }

dqnConfig :: Dqn.DqnTrainConfig
dqnConfig =
  Dqn.defaultDqnTrainConfig
    { Dqn.dqnSeed = 13
    , Dqn.dqnHiddenUnits = 2
    , Dqn.dqnNumSteps = 3
    , Dqn.dqnBatchSize = 1
    , Dqn.dqnTrainStart = 1
    , Dqn.dqnStatInterval = 1
    , Dqn.dqnEpsilonStart = 0
    , Dqn.dqnEpsilonEnd = 0
    }

qrConfig :: Qr.QrDqnTrainConfig
qrConfig =
  Qr.defaultQrDqnTrainConfig
    { Qr.qrSeed = 13
    , Qr.qrHiddenUnits = 2
    , Qr.qrNumQuantiles = 2
    , Qr.qrNumSteps = 3
    , Qr.qrBatchSize = 1
    , Qr.qrTrainStart = 1
    , Qr.qrStatInterval = 1
    }

continuousConfig :: Continuous.ContinuousTrainConfig
continuousConfig =
  (Continuous.defaultContinuousTrainConfig Continuous.VariantDDPG)
    { Continuous.ctSeed = 13
    , Continuous.ctHidden = 2
    , Continuous.ctNumSteps = 3
    , Continuous.ctBatchSize = 1
    , Continuous.ctTrainStart = 1
    , Continuous.ctStartSteps = 0
    , Continuous.ctStatInterval = 1
    }

sacConfig :: Continuous.ContinuousTrainConfig
sacConfig =
  (Continuous.defaultContinuousTrainConfig Continuous.VariantSAC)
    { Continuous.ctSeed = 13
    , Continuous.ctHidden = 1
    , Continuous.ctNumSteps = 1
    , Continuous.ctBatchSize = 1
    , Continuous.ctTrainStart = 1
    , Continuous.ctStartSteps = 0
    , Continuous.ctStatInterval = 1
    , Continuous.ctEnvName = "pendulum"
    }

herConfig :: Her.HerTrainConfig
herConfig =
  Her.defaultHerTrainConfig
    { Her.herSeed = 13
    , Her.herNumBits = 2
    , Her.herHiddenUnits = 2
    , Her.herEpisodes = 2
    , Her.herBatchSize = 1
    , Her.herUpdatesPerEpisode = 1
    , Her.herStatInterval = 1
    }

arsConfig :: Ars.ArsTrainConfig
arsConfig =
  Ars.defaultArsTrainConfig
    { Ars.arsSeed = 13
    , Ars.arsIterations = 1
    , Ars.arsNumDirections = 2
    , Ars.arsTopB = 1
    , Ars.arsMaxEpisodeSteps = 3
    }

-- Real public compiler; no opaque-plan forging or record update.
compiledPlan :: Text -> Text -> IO Plan.CompiledRlPlan
compiledPlan trainer environment =
  expectRight
    ( Plan.compileRlPlan
        Plan.TrainingPlan
          { Plan.trainingPlanTrainerKind = trainer
          , Plan.trainingPlanEnvironment = environment
          , Plan.trainingPlanSeed = 13
          , Plan.trainingPlanMaxEpisodeSteps = 1
          , Plan.trainingPlanEpisodeBudgetFloor = 1
          , Plan.trainingPlanVectorEnvironments = Just 1
          , Plan.trainingPlanRequestedTransitionFloor = Nothing
          , Plan.trainingPlanExactTransitionTarget = Nothing
          }
        (Plan.EvaluationPlan 1)
    )

actualZeroBudgetReturn
  :: IO (Plan.CompiledRlPlan, Dqn.DqnTrainObservation, Observation.RawTrainerObservation)
actualZeroBudgetReturn = do
  plan <- compiledPlan "dqn" "cartpole"
  schedule <- maybe (assertFailure "missing compiled schedule") pure (Plan.compiledRlSchedule plan)
  let config =
        dqnConfig
          { Dqn.dqnNumSteps = Plan.scheduleFixedSteps schedule
          , Dqn.dqnMaxEpisodeSteps = Plan.scheduleFixedMaxEpisodeSteps schedule
          , Dqn.dqnTrainStart = maxBound
          , Dqn.dqnEpsilonStart = 1
          , Dqn.dqnEpsilonEnd = 1
          , Dqn.dqnStatInterval = maxBound
          }
  raw <- Dqn.trainDqnOnDeviceWithEnvironmentRaw pureReferenceMlpDevice cartpole config >>= expectRight
  evaluations <-
    Dqn.evaluateDqnPolicyWithEnvironment
      pureReferenceMlpDevice
      cartpole
      config
      (Common.rawTrainerFinalParams raw)
      1
      >>= expectRight
  let episodes =
        [ Episode.SimulatedEpisode
            index
            (Common.evaluationEpisodeSteps value)
            (Common.evaluationEpisodeReward value)
            (Common.evaluationEpisodeTerminated value)
            []
        | (index, value) <- zip [0 ..] evaluations
        ]
  pure
    ( plan
    , raw
    , Observation.RawTrainerObservation
        plan
        (Observation.ReturnedDqn raw)
        (Observation.EvaluationReturned episodes)
    )

recording :: IORef [Mlp.MlpParams] -> MlpDevice
recording calls =
  pureReferenceMlpDevice
    { mlpdForward = \p x -> record p >> mlpdForward pureReferenceMlpDevice p x
    , mlpdForwardBatch = \p x -> record p >> mlpdForwardBatch pureReferenceMlpDevice p x
    , mlpdBatchGradient = \p x -> record p >> mlpdBatchGradient pureReferenceMlpDevice p x
    }
 where
  record p = modifyIORef' calls (p :)

assertSameParams :: Mlp.MlpParams -> Mlp.MlpParams -> IO ()
assertSameParams actual retained = do
  Mlp.paramShape actual @?= Mlp.paramShape retained
  -- Frozen F64 codec compares exact binary64 bits, including signed zero.
  Checkpoint.encodeJmw1 (Mlp.mlpParamsToFlat actual)
    @?= Checkpoint.encodeJmw1 (Mlp.mlpParamsToFlat retained)

firstActual :: IORef [Mlp.MlpParams] -> IO Mlp.MlpParams
firstActual calls =
  readIORef calls >>= \values -> case reverse values of
    p : _ -> pure p
    [] -> assertFailure "actual injected callbacks were not executed"

data FailurePoint
  = ProbeFailure
  | TrainingLeft
  | TrainingThrow
  | EvaluationLeft
  | EvaluationThrow
  | ZeroGradient
  deriving stock (Eq, Show)

fixture :: IORef [Text] -> FailurePoint -> MlpDevice
fixture calls failure =
  pureReferenceMlpDevice
    { mlpdForward = \p x -> do
        record "forward"
        if failure == EvaluationThrow
          then throwIO (userError "evaluation throw sentinel")
          else
            pure (if failure == EvaluationLeft then Left "evaluation sentinel" else Right (fixedForward p x))
    , mlpdForwardBatch = \p xs -> do
        let probe = Mlp.paramShape p == Mlp.MlpShape 1 1 1
        record (if probe then "probe" else "batch-forward")
        if not probe && failure == TrainingThrow
          then throwIO (userError "training throw sentinel")
          else
            pure
              ( if probe && failure == ProbeFailure
                  then Left "probe sentinel"
                  else
                    if not probe && failure == TrainingLeft
                      then Left "training sentinel"
                      else Right (map (Mlp.forwardOutput . fixedForward p) xs)
              )
    , mlpdBatchGradient = \p _ ->
        record "batch-gradient"
          >> pure
            ( Right
                ( (Mlp.mlpZeroGradient (Mlp.paramShape p))
                    { Mlp.gradB2 =
                        VU.replicate (Mlp.mlpOutputs (Mlp.paramShape p)) (if failure == ZeroGradient then 0 else 0.001)
                    }
                )
            )
    , mlpdExecutionWitness = record "witness" >> fail "unexpected witness query"
    }
 where
  record event = modifyIORef' calls (event :)

fixedForward :: Mlp.MlpParams -> VU.Vector Double -> Mlp.MlpForward
fixedForward params observation =
  Mlp.MlpForward
    observation
    (VU.replicate hidden 0)
    (VU.replicate hidden 0)
    (VU.replicate (Mlp.mlpOutputs shape) 0)
 where
  shape = Mlp.paramShape params; hidden = Mlp.mlpHidden shape

expectReturned :: Observation.RawTrainerAttempt -> IO Observation.RawTrainerObservation
expectReturned attempted = case attempted of
  Observation.TrainerReturned value -> pure value
  _ -> assertFailure (show attempted)

expectRight :: (Show e) => Either e a -> IO a
expectRight value = case value of Right x -> pure x; Left err -> assertFailure (show err)

expectLeft :: (Show a) => Text -> Either Text a -> IO ()
expectLeft fragment value = case value of
  Left err -> assertBool (Text.unpack err) (fragment `Text.isInfixOf` err)
  Right x -> assertFailure ("unexpected Right: " <> show x)
