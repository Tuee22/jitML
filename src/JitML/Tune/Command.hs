{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TupleSections #-}

module JitML.Tune.Command
  ( TuningCommandRuntime (..)
  , TuningExecutionDataset (..)
  , TuningWorkerServices (..)
  , loadTuningExecutionDataset
  , runTune
  )
where

import Control.Monad (unless, when)
import Control.Monad.Reader (ask, liftIO)
import Data.Foldable (traverse_)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word32, Word64)
import System.Environment (lookupEnv)

import JitML.AppError.AppError (AppError (..))
import JitML.CLI.Output (exitWithError, writeLine, writeText)
import JitML.CLI.Parser (ParsedOption (..))
import JitML.Checkpoint.Format qualified as Checkpoint
import JitML.Env.Env (App)
import JitML.Experiment.Overrides qualified as Overrides
import JitML.Numerics.MlpDeviceSelect (mlpDeviceForSubstrate)
import JitML.Plan.Apply (writePlanFile)
import JitML.Plan.Command qualified as PlanCommand
import JitML.Plan.Plan
  ( planIdText
  , quantityValue
  , runPlanExperimentId
  , runPlanSeeds
  , runPlanSubstrate
  , seedCohortValues
  )
import JitML.Plan.Workload qualified as WorkloadPlan
import JitML.Product.Completion qualified as ProductCompletion
import JitML.Proto.Tune qualified as ProtoTune
import JitML.SL.Canonicals qualified as SL
import JitML.SL.Classifier qualified as Classifier
import JitML.SL.Dataset qualified as Dataset
import JitML.SL.TrainingExecution qualified as TrainingExecution
import JitML.Service.MinIOSubprocess qualified as MinIOSubprocess
import JitML.Service.PulsarWebSocketSubprocess qualified as PulsarWebSocketSubprocess
import JitML.Service.Retry (ServiceError)
import JitML.Service.RunConfig qualified as RunConfig
import JitML.Substrate (Substrate, renderSubstrate)
import JitML.Tune.Catalog qualified as Tune
import JitML.Tune.Resume qualified as Tune

data TuningWorkerServices = TuningWorkerServices
  { tuningWorkerSubstrate :: Substrate
  , tuningWorkerMinIOSettings :: MinIOSubprocess.MinIOSettings
  , tuningWorkerPulsarSettings :: PulsarWebSocketSubprocess.PulsarWebSocketSettings
  }

data TuningExecutionDataset = TuningExecutionDataset
  { tuningDatasetProblem :: SL.CanonicalProblem
  , tuningDatasetBaseConfig :: Classifier.ClassifierConfig
  , tuningDatasetTrainSet :: Classifier.Dataset
  , tuningDatasetValidationSet :: Classifier.Dataset
  , tuningDatasetShaAtRead :: Text
  }

data TuningCommandRuntime = TuningCommandRuntime
  { tuningResolveWorkerServices :: App (Maybe TuningWorkerServices)
  , tuningResolveWorkerSubstrate :: App Substrate
  , tuningWriteLocalCheckpointLines
      :: Text
      -> Text
      -> Word64
      -> [(Text, Double)]
      -> [Double]
      -> App [Text]
  , tuningWriteLocalArtifactLines
      :: Text
      -> Text
      -> Text
      -> App [Text]
  , tuningWriteMinIOCheckpoint
      :: MinIOSubprocess.MinIOSettings
      -> Text
      -> Text
      -> Word64
      -> [(Text, Double)]
      -> [Double]
      -> IO (Either ServiceError ())
  , tuningPublishEvent
      :: PulsarWebSocketSubprocess.PulsarWebSocketSettings
      -> Substrate
      -> ProtoTune.TuneEvent
      -> IO (Either ServiceError ())
  , tuningTimestampNs :: IO Word64
  }

runTune :: TuningCommandRuntime -> FilePath -> [ParsedOption] -> App ()
runTune runtime runConfigPath parsedOptions = do
  mounted <- liftIO (RunConfig.tryLoadTuneRunConfig runConfigPath)
  case mounted of
    RunConfig.RunConfigLoaded config ->
      case RunConfig.tuningPlanFromRunConfig config of
        Left err -> exitWithError (mountedTuneRunConfigDecodeError runConfigPath err)
        Right plan -> do
          writeLine
            ( "tune resolved-plan: plan-id="
                <> planIdText (WorkloadPlan.tuningPlanId plan)
                <> " trials="
                <> Text.pack (show (quantityValue (WorkloadPlan.tuningPlanTrials plan)))
            )
          publishWorkerTuneEvent runtime plan
    RunConfig.RunConfigDecodeFailed err ->
      exitWithError (mountedTuneRunConfigDecodeError runConfigPath err)
    RunConfig.RunConfigMissing -> do
      rejectMissingMountedTuneRunConfigInKubernetes runConfigPath
      runLocalTune runtime parsedOptions
{-# NOINLINE runTune #-}

runLocalTune :: TuningCommandRuntime -> [ParsedOption] -> App ()
runLocalTune runtime parsedOptions = do
  overrides <- case Overrides.parseTuningOverrides parsedOptions of
    Left err -> exitWithError (InvalidConfig (Overrides.renderOverrideError err))
    Right ovr -> pure ovr
  let tunePath = Text.unpack (selectedValue "tune-dhall" "experiments/mnist-tune.dhall" parsedOptions)
  loaded <- liftIO (Tune.loadTuningExperiment tunePath)
  experiment <- case loaded of
    Left message -> exitWithError (DhallTypeError message)
    Right value -> pure (Overrides.applyOverrides overrides value)
  (start, plan) <- prepareLocalTuningPlan runtime tunePath experiment
  let rendered = Tune.renderTuningPlan tunePath experiment
      renderedWithOverrides =
        rendered
          <> "plan-id: "
          <> ProtoTune.ssPlanId start
          <> "\nresolved-plan: "
          <> ProtoTune.ssResolvedPlan start
          <> "\noverrides: "
          <> Overrides.renderTuningOverrides overrides
          <> "\n"
  tuneArtifactLines <- writeLocalTuneArtifacts runtime experiment plan
  case hasOptionValue "plan-file" parsedOptions of
    [] -> pure ()
    planPath : _ ->
      liftIO
        ( writePlanFile
            (Text.unpack planPath)
            (renderedWithOverrides <> Text.unlines tuneArtifactLines)
        )
  writeText (renderedWithOverrides <> Text.unlines tuneArtifactLines)

prepareLocalTuningPlan
  :: TuningCommandRuntime
  -> FilePath
  -> Tune.TuningExperiment
  -> App (ProtoTune.StartSweep, WorkloadPlan.TuningPlan)
prepareLocalTuningPlan runtime tunePath experiment = do
  config <- case Tune.tuningExperimentConfig experiment of
    Nothing -> exitWithError (InvalidConfig "tuning experiment requires a tuning configuration")
    Just value -> pure value
  executionSpec <-
    case Tune.tuningExecutionSpecForExperiment experiment of
      Left err -> exitWithError (InvalidConfig ("tuning execution-spec refinement failed: " <> err))
      Right value -> pure value
  substrate <- tuningResolveWorkerSubstrate runtime
  trials <- tuningWord32PlanValue "tuning trials" (toInteger (Tune.tuningConfigTrials config))
  parallelism <-
    tuningWord32PlanValue "tuning parallelism" (toInteger (Tune.tuningConfigParallelism config))
  -- One ceiling-reaching trial is the metric-independent frontier shared by
  -- every currently executable exact schedule.  In particular, canonical
  -- serial ASHA plus its active median pruner cannot guarantee a second trial.
  promotions <-
    tuningWord32PlanValue
      "tuning promotions"
      1
  updates <-
    tuningWord32PlanValue
      "tuning per-trial updates"
      (toInteger (Tune.tuningSchedulerMaxBudget (Tune.tuningConfigScheduler config)))
  let experimentHash =
        Checkpoint.deriveExperimentHash
          (Text.pack tunePath)
          (Tune.renderTuningPlan tunePath experiment)
      raw =
        ProtoTune.StartSweep
          { ProtoTune.ssExperimentHash = experimentHash
          , ProtoTune.ssDhallObjectKey = Text.pack tunePath
          , ProtoTune.ssSubstrate = substrate
          , ProtoTune.ssSweepSeed = fromIntegral (Tune.tuningExperimentSeed experiment)
          , ProtoTune.ssTrialBudget = trials
          , ProtoTune.ssBudgetPerTrial = updates
          , ProtoTune.ssSampler = Text.pack (show (Tune.tuningSamplerKind (Tune.tuningConfigSampler config)))
          , ProtoTune.ssScheduler =
              Text.pack (show (Tune.tuningSchedulerKind (Tune.tuningConfigScheduler config)))
          , ProtoTune.ssPruner = Text.pack (show (Tune.tuningPrunerKind (Tune.tuningConfigPruner config)))
          , ProtoTune.ssParallelism = parallelism
          , ProtoTune.ssPromotions = promotions
          , ProtoTune.ssPlanId = ""
          , ProtoTune.ssResolvedPlan = ""
          }
  case PlanCommand.prepareStartSweepWithExecutionSpec executionSpec raw of
    Left err -> exitWithError (InvalidConfig ("tuning plan refinement failed: " <> err))
    Right prepared -> pure prepared

writeLocalTuneArtifacts
  :: TuningCommandRuntime
  -> Tune.TuningExperiment
  -> WorkloadPlan.TuningPlan
  -> App [Text]
writeLocalTuneArtifacts runtime experiment plan = do
  env <- ask
  trialCount <-
    tuningIntPlanValue "tuning trials" (quantityValue (WorkloadPlan.tuningPlanTrials plan))
  promotions <-
    tuningIntPlanValue "tuning promotions" (quantityValue (WorkloadPlan.tuningPlanPromotions plan))
  sweepSeed <-
    tuningIntPlanValue
      "tuning sweep seed"
      (NonEmpty.head (seedCohortValues (runPlanSeeds (WorkloadPlan.tuningPlanRunPlan plan))))
  let runPlan = WorkloadPlan.tuningPlanRunPlan plan
      executionSpec = WorkloadPlan.tuningPlanExecutionSpec plan
      sampler = WorkloadPlan.tuningPlanSampler plan
      experimentHash = runPlanExperimentId runPlan
      device = mlpDeviceForSubstrate (runPlanSubstrate runPlan) env
  resultsE <-
    if Tune.tuningExecutionDataset executionSpec == "synthetic"
      then
        liftIO
          ( Tune.trialObjectiveResultsWithDeviceForSyntheticExecutionSpec
              device
              sweepSeed
              executionSpec
          )
      else do
        datasetE <- loadTuningExecutionDataset runtime executionSpec
        case datasetE of
          Left err -> pure (Left err)
          Right dataset ->
            liftIO
              ( Tune.trialObjectiveResultsWithDeviceForExecutionSpec
                  device
                  sweepSeed
                  executionSpec
                  (tuningDatasetProblem dataset)
                  (tuningDatasetBaseConfig dataset)
                  (tuningDatasetTrainSet dataset)
                  (tuningDatasetValidationSet dataset)
              )
  results <- case resultsE of
    Left err -> exitWithError (InvalidConfig ("resolved tuning execution failed: " <> err))
    Right values -> pure values
  when (length results /= trialCount) $
    exitWithError
      ( InvalidConfig
          ( "resolved tuning execution returned "
              <> Text.pack (show (length results))
              <> " trials; plan requires "
              <> Text.pack (show trialCount)
          )
      )
  executions <-
    case Tune.trialExecutionsForExecutionSpec executionSpec promotions results of
      Left err -> exitWithError (InvalidConfig ("resolved tuning execution failed: " <> err))
      Right values -> pure values
  let promotedResults =
        [ Tune.trialExecutionResult execution
        | execution <- executions
        , Tune.trialExecutionPromoted execution
        ]
      prunedCount = length (filter Tune.trialExecutionPruned executions)
  case Tune.selectBestTrialResultForExecutionSpec executionSpec promotedResults of
    Nothing -> exitWithError (InvalidConfig "resolved tuning plan produced no trials")
    Just best -> do
      storedPromotions <-
        traverse
          ( \result ->
              tuningWriteLocalCheckpointLines
                runtime
                experimentHash
                "tune-trial-weights"
                (fromIntegral (Tune.trialResultIndex result))
                [("objective", Tune.trialResultObjective result)]
                (Tune.trialResultWeights result)
          )
          promotedResults
      artifactLines <-
        tuningWriteLocalArtifactLines
          runtime
          experimentHash
          "tune-trials"
          (renderTuneTrialArtifact experiment sampler executions best)
      pure $
        [ "best-trial-index: " <> Text.pack (show (Tune.trialResultIndex best))
        , "best-trial-objective: " <> Text.pack (show (Tune.trialResultObjective best))
        , "trials-completed: " <> Text.pack (show (length executions))
        , "trials-pruned: " <> Text.pack (show prunedCount)
        , "trials-promoted: " <> Text.pack (show (length promotedResults))
        ]
          <> concat storedPromotions
          <> artifactLines
{-# NOINLINE writeLocalTuneArtifacts #-}

renderTuneTrialArtifact
  :: Tune.TuningExperiment
  -> Tune.Sampler
  -> [Tune.TrialExecution]
  -> Tune.TrialObjectiveResult
  -> Text
renderTuneTrialArtifact experiment sampler executions best =
  Text.unlines $
    [ "kind: tune-trials-v2"
    , "name: " <> Tune.tuningExperimentName experiment
    , "sampler: " <> Text.pack (show sampler)
    , "trial-count: " <> Text.pack (show (length executions))
    , "pruner-stopped-count: " <> Text.pack (show (length (filter isPrunerStopped executions)))
    , "scheduler-stopped-count: " <> Text.pack (show (length (filter isSchedulerStopped executions)))
    , "best-trial-index: " <> Text.pack (show (Tune.trialResultIndex best))
    , "best-trial-objective: " <> Text.pack (show (Tune.trialResultObjective best))
    ]
      <> concatMap renderTrial executions
 where
  renderTrial execution =
    let result = Tune.trialExecutionResult execution
     in [ "trial: " <> Text.pack (show (Tune.trialResultIndex result))
        , "objective: " <> Text.pack (show (Tune.trialResultObjective result))
        , "learning-rate: "
            <> Text.pack (show (Tune.trialLearningRate (Tune.trialResultHyperparameters result)))
        , "batch-size: " <> Text.pack (show (Tune.trialBatchSize (Tune.trialResultHyperparameters result)))
        , "dropout: " <> Text.pack (show (Tune.trialDropout (Tune.trialResultHyperparameters result)))
        , "optimizer: " <> Tune.trialOptimizer (Tune.trialResultHyperparameters result)
        , "updates-executed: " <> Text.pack (show (Tune.trialResultUpdatesExecuted result))
        , "disposition: " <> renderTuneTrialDisposition (Tune.trialResultDisposition result)
        , "rung-count: " <> Text.pack (show (length (Tune.trialResultObservations result)))
        , "pruned: " <> Text.pack (show (Tune.trialExecutionPruned execution))
        , "promoted: " <> Text.pack (show (Tune.trialExecutionPromoted execution))
        , "weight-count: " <> Text.pack (show (length (Tune.trialResultWeights result)))
        ]
          <> [ "rung: updates="
                 <> Text.pack (show (Tune.trialObservationUpdates observation))
                 <> ",objective="
                 <> Text.pack (show (Tune.trialObservationObjective observation))
             | observation <- Tune.trialResultObservations result
             ]
  isPrunerStopped execution =
    case Tune.trialResultDisposition (Tune.trialExecutionResult execution) of
      Tune.PrunerStopped _ _ -> True
      _ -> False
  isSchedulerStopped execution =
    case Tune.trialResultDisposition (Tune.trialExecutionResult execution) of
      Tune.SchedulerStopped _ _ -> True
      _ -> False

renderTuneTrialDisposition :: Tune.TrialDisposition -> Text
renderTuneTrialDisposition Tune.ReachedMaxBudget = "reached-max-budget"
renderTuneTrialDisposition (Tune.SchedulerStopped scheduler rung) =
  "scheduler-stopped:" <> Text.pack (show scheduler) <> ":" <> Text.pack (show rung)
renderTuneTrialDisposition (Tune.PrunerStopped pruner rung) =
  "pruner-stopped:" <> Text.pack (show pruner) <> ":" <> Text.pack (show rung)

-- | Sprint 13.10 / 9.16 — when running inside a daemon-dispatched tune Job
-- (live publication + JITML_EXPERIMENT_HASH set), run the sampler, scheduler,
-- and pruner selected by the mounted TuneRunConfig for the configured trial
-- budget.
-- Each trial:
--
--   1. uses the selected `(Sampler, Scheduler, Pruner)` axes;
--   2. trains the sampled trial through the substrate-selected JIT device and
--      returns both the measured objective and checkpointable weights;
--   3. persists a `TrialTranscript` to MinIO via `persistTrialTranscript`;
--   4. promotes the measured trial weights into `jitml-checkpoints`;
--   5. publishes `TuneTrialStarted` + `TuneTrialFinished` envelopes to
--      `tune.event.<substrate>`.
--
-- After the loop publishes `TuneSweepCompleted` with the exact planned count and
-- the best measured objective. The worker consumes only the already-refined
-- plan mounted by the daemon; it never re-reads or repairs primitive budgets.
publishWorkerTuneEvent :: TuningCommandRuntime -> WorkloadPlan.TuningPlan -> App ()
publishWorkerTuneEvent runtime plan = do
  env <- ask
  servicesMaybe <- tuningResolveWorkerServices runtime
  services <- case servicesMaybe of
    Nothing ->
      exitWithError
        (InvalidConfig "resolved tuning worker requires mounted service configuration")
    Just value -> pure value
  let substrate = tuningWorkerSubstrate services
      plannedSubstrate = runPlanSubstrate (WorkloadPlan.tuningPlanRunPlan plan)
      experimentHash = runPlanExperimentId (WorkloadPlan.tuningPlanRunPlan plan)
      planId = planIdText (WorkloadPlan.tuningPlanId plan)
      executionSpec = WorkloadPlan.tuningPlanExecutionSpec plan
      sampler = WorkloadPlan.tuningPlanSampler plan
      scheduler = WorkloadPlan.tuningPlanScheduler plan
      pruner = WorkloadPlan.tuningPlanPruner plan
      pulsarSettings = tuningWorkerPulsarSettings services
      minioSettings = tuningWorkerMinIOSettings services
      device = mlpDeviceForSubstrate substrate env
  unless (substrate == plannedSubstrate) $
    exitWithError
      ( InvalidConfig
          ( "resolved tuning plan substrate "
              <> renderSubstrate plannedSubstrate
              <> " does not match worker substrate "
              <> renderSubstrate substrate
          )
      )
  trialBudget <-
    tuningIntPlanValue "tuning trials" (quantityValue (WorkloadPlan.tuningPlanTrials plan))
  parallelism <-
    tuningIntPlanValue "tuning parallelism" (quantityValue (WorkloadPlan.tuningPlanParallelism plan))
  promotions <-
    tuningIntPlanValue "tuning promotions" (quantityValue (WorkloadPlan.tuningPlanPromotions plan))
  updates <-
    tuningIntPlanValue
      "tuning per-trial updates"
      (quantityValue (WorkloadPlan.tuningPlanPerTrialUpdates plan))
  sweepSeed <-
    tuningIntPlanValue
      "tuning sweep seed"
      (NonEmpty.head (seedCohortValues (runPlanSeeds (WorkloadPlan.tuningPlanRunPlan plan))))
  trialExecutionE <-
    if Tune.tuningExecutionDataset executionSpec == "synthetic"
      then do
        resultsE <-
          liftIO
            ( Tune.trialObjectiveResultsWithDeviceForSyntheticExecutionSpec
                device
                sweepSeed
                executionSpec
            )
        pure ((Tune.syntheticTuningDatasetSha256,) <$> resultsE)
      else do
        datasetE <- loadTuningExecutionDataset runtime executionSpec
        case datasetE of
          Left err -> pure (Left err)
          Right dataset -> do
            resultsE <-
              liftIO
                ( Tune.trialObjectiveResultsWithDeviceForExecutionSpec
                    device
                    sweepSeed
                    executionSpec
                    (tuningDatasetProblem dataset)
                    (tuningDatasetBaseConfig dataset)
                    (tuningDatasetTrainSet dataset)
                    (tuningDatasetValidationSet dataset)
                )
            pure ((tuningDatasetShaAtRead dataset,) <$> resultsE)
  (datasetShaAtRead, trialResults) <- case trialExecutionE of
    Left err -> exitWithError (InvalidConfig ("device-backed tuning execution failed: " <> err))
    Right values -> pure values
  when (length trialResults /= trialBudget) $
    exitWithError
      ( InvalidConfig
          ( "device-backed tuning execution returned "
              <> Text.pack (show (length trialResults))
              <> " trials; resolved plan requires "
              <> Text.pack (show trialBudget)
          )
      )
  executions <-
    case Tune.trialExecutionsForExecutionSpec executionSpec promotions trialResults of
      Left err -> exitWithError (InvalidConfig ("resolved tuning execution failed: " <> err))
      Right values -> pure values
  traverse_
    ( publishOneTrial
        pulsarSettings
        minioSettings
        substrate
        experimentHash
        planId
        sampler
        scheduler
        pruner
        parallelism
        promotions
        updates
        sweepSeed
    )
    executions
  let promotedResults =
        [ Tune.trialExecutionResult execution
        | execution <- executions
        , Tune.trialExecutionPromoted execution
        ]
      prunedCount = length (filter Tune.trialExecutionPruned executions)
      promotedCount = length promotedResults
  bestResult <-
    case Tune.selectBestTrialResultForExecutionSpec executionSpec promotedResults of
      Nothing -> exitWithError (InvalidConfig "resolved tuning plan produced no promoted ceiling-reaching trial")
      Just result -> pure result
  let bestObjective = Tune.trialResultObjective bestResult
      completed = fromIntegral (length trialResults)
      finished =
        ProtoTune.SweepFinished
          { ProtoTune.sfExperimentHash = experimentHash
          , ProtoTune.sfPlanId = planId
          , ProtoTune.sfTrialsCompleted = completed
          , ProtoTune.sfTrialsPruned = fromIntegral prunedCount
          , ProtoTune.sfTrialsPromoted = fromIntegral promotedCount
          , ProtoTune.sfBestObjective = bestObjective
          }
  completedTraining <-
    case ProductCompletion.tuneSweepCompletedTraining
      plan
      experimentHash
      datasetShaAtRead
      completed
      bestResult of
      Left err -> exitWithError (InvalidConfig ("tuning completion proof failed: " <> err))
      Right value -> pure value
  envelope <-
    case ProtoTune.completeSweep finished completedTraining of
      Left err -> exitWithError (InvalidConfig ("tuning completion event failed: " <> err))
      Right value -> pure (ProtoTune.TuneSweepCompleted value)
  publishResult <-
    liftIO (tuningPublishEvent runtime pulsarSettings substrate envelope)
  requireServiceSuccess "publish tuning completion" publishResult
 where
  publishOneTrial pulsarSettings minioSettings substrate experimentHash planId sampler scheduler pruner parallelism promotions updates sweepSeed execution = do
    let trialResult = Tune.trialExecutionResult execution
        trialIndex = Tune.trialResultIndex trialResult
        trialSeed = sweepSeed + trialIndex
        objective = Tune.trialResultObjective trialResult
        transcript =
          Tune.terminalTrialTranscript experimentHash trialSeed trialResult
        parametersJson =
          "{\"sampler\":\""
            <> Text.pack (show sampler)
            <> "\",\"scheduler\":\""
            <> Text.pack (show scheduler)
            <> "\",\"pruner\":\""
            <> Text.pack (show pruner)
            <> "\",\"parallelism\":"
            <> Text.pack (show parallelism)
            <> ",\"promotions\":"
            <> Text.pack (show promotions)
            <> ",\"perTrialOptimizerUpdates\":"
            <> Text.pack (show updates)
            <> "}"
    timestampStart <- liftIO (tuningTimestampNs runtime)
    let startEvent =
          ProtoTune.TuneTrialStarted
            ( ProtoTune.TrialStarted
                { ProtoTune.tsExperimentHash = experimentHash
                , ProtoTune.tsPlanId = planId
                , ProtoTune.tsTrial = fromIntegral trialIndex
                , ProtoTune.tsTrialSeed = fromIntegral trialSeed
                , ProtoTune.tsParametersJson = parametersJson
                , ProtoTune.tsTimestampNs = timestampStart
                }
            )
    startPublish <-
      liftIO (tuningPublishEvent runtime pulsarSettings substrate startEvent)
    requireServiceSuccess "publish tuning trial start" startPublish
    persistResult <-
      liftIO
        ( MinIOSubprocess.runMinIOSubprocess
            minioSettings
            (Tune.persistTrialTranscript transcript)
        )
    requireServiceSuccess "persist tuning trial transcript" persistResult
    when (Tune.trialExecutionPromoted execution) $ do
      checkpointResult <-
        liftIO
          ( tuningWriteMinIOCheckpoint
              runtime
              minioSettings
              experimentHash
              "tune-trial-weights"
              (fromIntegral trialSeed)
              [("objective", objective)]
              (Tune.trialResultWeights trialResult)
          )
      requireServiceSuccess "persist promoted tuning trial checkpoint" checkpointResult
    timestampEnd <- liftIO (tuningTimestampNs runtime)
    let finishedEvent =
          ProtoTune.TuneTrialFinished
            ( ProtoTune.TrialFinished
                { ProtoTune.tfTuneExperimentHash = experimentHash
                , ProtoTune.tfTunePlanId = planId
                , ProtoTune.tfTuneTrial = fromIntegral trialIndex
                , ProtoTune.tfTuneObjective = objective
                , ProtoTune.tfTunePruned = Tune.trialExecutionPruned execution
                , ProtoTune.tfTuneTranscriptObjectKey =
                    Tune.trialStorageKey experimentHash trialSeed
                , ProtoTune.tfTuneTimestampNs = timestampEnd
                }
            )
    finishPublish <-
      liftIO (tuningPublishEvent runtime pulsarSettings substrate finishedEvent)
    requireServiceSuccess "publish tuning trial finish" finishPublish
    pure objective

  requireServiceSuccess label result =
    case result of
      Left err -> exitWithError (InvalidConfig (label <> ": " <> Text.pack (show err)))
      Right _ -> pure ()
{-# NOINLINE publishWorkerTuneEvent #-}

loadTuningExecutionDataset
  :: TuningCommandRuntime
  -> Tune.TuningExecutionSpec
  -> App (Either Text TuningExecutionDataset)
loadTuningExecutionDataset runtime executionSpec =
  case [ problem
       | problem <- SL.canonicalProblems
       , SL.problemDataset problem == Tune.tuningExecutionDataset executionSpec
       , SL.problemModel problem == Tune.tuningExecutionModel executionSpec
       ] of
    [problem] -> loadProblem problem
    [] ->
      pure
        ( Left
            ( "no canonical tuning problem matches dataset/model "
                <> Tune.tuningExecutionDataset executionSpec
                <> "/"
                <> Tune.tuningExecutionModel executionSpec
            )
        )
    matches ->
      pure
        ( Left
            ( "tuning dataset/model is ambiguous across "
                <> Text.pack (show (length matches))
                <> " canonical problems"
            )
        )
 where
  loadProblem problem = do
    servicesMaybe <- tuningResolveWorkerServices runtime
    case servicesMaybe of
      Nothing -> pure (Left "no live cluster publication (run `jitml bootstrap --<substrate>`)")
      Just services ->
        case Dataset.datasetForProblem problem of
          Just trainRef
            | TrainingExecution.hasCanonicalLabels trainRef -> do
                let minioSettings = tuningWorkerMinIOSettings services
                    run :: MinIOSubprocess.MinIOSubprocess a -> App a
                    run action = liftIO (MinIOSubprocess.runMinIOSubprocess minioSettings action)
                imagesE <- run (Dataset.fetchVerifiedDatasetArtifactBytes trainRef Dataset.ImagesArtifact)
                labelsE <- run (Dataset.fetchVerifiedDatasetArtifactBytes trainRef Dataset.LabelsArtifact)
                case (imagesE, labelsE) of
                  (Right imageArtifact, Right labelArtifact) ->
                    let datasetShaAtRead =
                          Dataset.datasetReadShaForArtifacts [imageArtifact, labelArtifact]
                     in case Classifier.decodeBoundedDataset
                          Classifier.defaultClassifierConfig
                          (Just canonicalTuningMaterializedExamples)
                          (Dataset.maybeGunzip (Dataset.fetchedArtifactPayload imageArtifact))
                          (Dataset.maybeGunzip (Dataset.fetchedArtifactPayload labelArtifact)) of
                          Left err -> pure (Left (Text.pack err))
                          Right (baseConfig, dataset) ->
                            let trainSet = take canonicalTuningTrainingExamples dataset
                                validationSet =
                                  take
                                    canonicalTuningValidationExamples
                                    (drop canonicalTuningTrainingExamples dataset)
                             in if length trainSet /= canonicalTuningTrainingExamples
                                  || length validationSet /= canonicalTuningValidationExamples
                                  then
                                    pure
                                      ( Left
                                          "canonical tuning dataset cannot satisfy its exact 55,000/5,000 train/validation partition"
                                      )
                                  else
                                    pure
                                      ( Right
                                          TuningExecutionDataset
                                            { tuningDatasetProblem = problem
                                            , tuningDatasetBaseConfig = baseConfig
                                            , tuningDatasetTrainSet = trainSet
                                            , tuningDatasetValidationSet = validationSet
                                            , tuningDatasetShaAtRead = datasetShaAtRead
                                            }
                                      )
                  _ ->
                    pure
                      ( Left
                          ( TrainingExecution.datasetFetchFailure
                              ("dataset bytes not staged in MinIO for " <> Dataset.datasetName trainRef)
                              [imagesE, labelsE]
                          )
                      )
          _ -> pure (Left "tuning canonical problem has no staged image/label dataset")

canonicalTuningTrainingExamples :: Int
canonicalTuningTrainingExamples = 55000

canonicalTuningValidationExamples :: Int
canonicalTuningValidationExamples = 5000

canonicalTuningMaterializedExamples :: Int
canonicalTuningMaterializedExamples =
  canonicalTuningTrainingExamples + canonicalTuningValidationExamples
{-# NOINLINE loadTuningExecutionDataset #-}

tuningWord32PlanValue :: Text -> Integer -> App Word32
tuningWord32PlanValue label value
  | value < 0 || value > toInteger (maxBound :: Word32) =
      exitWithError (InvalidConfig (label <> " is outside the Word32 protocol range"))
  | otherwise = pure (fromInteger value)

tuningIntPlanValue :: Text -> Word64 -> App Int
tuningIntPlanValue label value
  | toInteger value > toInteger (maxBound :: Int) =
      exitWithError (InvalidConfig (label <> " exceeds the platform Int range"))
  | otherwise = pure (fromIntegral value)

hasOptionValue :: Text -> [ParsedOption] -> [Text]
hasOptionValue expected =
  concatMap selectedValues
 where
  selectedValues option
    | parsedOptionName option == expected = parsedOptionValues option
    | otherwise = []

selectedValue :: Text -> Text -> [ParsedOption] -> Text
selectedValue name fallback parsedOptions =
  case hasOptionValue name parsedOptions of
    value : _ -> value
    [] -> fallback

mountedTuneRunConfigDecodeError :: FilePath -> Text -> AppError
mountedTuneRunConfigDecodeError path detail =
  InvalidConfig
    ( "failed to decode mounted TuneRunConfig at "
        <> Text.pack path
        <> ": "
        <> detail
    )

rejectMissingMountedTuneRunConfigInKubernetes :: FilePath -> App ()
rejectMissingMountedTuneRunConfigInKubernetes path = do
  kubernetesHost <- liftIO (lookupEnv "KUBERNETES_SERVICE_HOST")
  when (maybe False (not . null) kubernetesHost) $
    exitWithError
      ( mountedTuneRunConfigDecodeError
          path
          "required resolved-plan mount is missing in a Kubernetes workload"
      )
