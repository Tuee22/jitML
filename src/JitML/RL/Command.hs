{-# LANGUAGE OverloadedStrings #-}

module JitML.RL.Command
  ( RlCommandRuntime (..)
  , RlWorkerServices (..)
  , rlAnimationEnvelope
  , runRl
  )
where

import Control.Monad.Reader (ask, liftIO)
import Data.Foldable (for_, traverse_)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word32, Word64)

import JitML.AppError.AppError (AppError (..))
import JitML.CLI.Output (exitWithError, writeText)
import JitML.CLI.Parser (ParsedOption (..))
import JitML.CLI.Spec (commandPathText)
import JitML.Checkpoint.Format qualified as Checkpoint
import JitML.Checkpoint.Store qualified as CheckpointStore
import JitML.Checkpoint.Writer qualified as CheckpointWriter
import JitML.Env.Env (App)
import JitML.Experiment.Overrides qualified as Overrides
import JitML.Experiment.Product qualified as ProductExperiment
import JitML.Numerics.MlpDeviceSelect (rlDeviceForSubstrate)
import JitML.Product.Completion qualified as ProductCompletion
import JitML.Proto.Rl qualified as ProtoRl
import JitML.RL.Algorithms qualified as RL
import JitML.RL.Command.AlphaZero qualified as AlphaZeroCommand
import JitML.RL.Command.Options
  ( envWithDefault
  , mountedRunConfigDecodeError
  , parsePositiveAppInt
  , requirePositiveAppInt
  , requireUserIntOptionAtLeast
  , selectedValue
  )
import JitML.RL.Command.Types
  ( RlCommandRuntime (..)
  , RlWorkerServices (..)
  )
import JitML.RL.EpisodeEnvelope qualified as EpisodeEnvelope
import JitML.RL.TrainerExecution
  ( trainerRunEpisodes
  , trainerRunEvidence
  , trainerRunObservedUnits
  , trainerRunWeights
  )
import JitML.RL.TrainerExecution qualified as TrainerExecution
import JitML.Service.RunConfig qualified as RunConfig
import JitML.Service.Workload qualified as Workload
import JitML.Substrate (renderSubstrate)
import JitML.Training.Budget qualified as TrainingBudget

-- | Persistence outcome for an RL run that produced weights. Absence of
-- weights is represented separately by the outer 'Maybe'; once a checkpoint
-- exists its candidate/completed state is closed and cannot be reconstructed
-- from an optional witness.
data PersistedRlCheckpoint
  = PersistedRlCandidateCheckpoint
      !CheckpointStore.StoredCandidateCheckpoint
  | PersistedRlCompletedCheckpoint
      !TrainingBudget.CompletedTraining
      !CheckpointStore.StoredCompletedCheckpoint

renderRlTrajectoryArtifact
  :: Text
  -> Text
  -> Text
  -> Int
  -> [EpisodeEnvelope.SimulatedEpisode]
  -> Text
renderRlTrajectoryArtifact experimentHash environment trainer seed episodes =
  Text.unlines $
    [ "kind: rl-trajectory-v1"
    , "experiment-hash: " <> experimentHash
    , "environment: " <> environment
    , "trainer: " <> trainer
    , "seed: " <> Text.pack (show seed)
    , "episodes: " <> Text.pack (show (length episodes))
    ]
      <> concatMap renderEpisode episodes
 where
  renderEpisode episode =
    [ "episode: " <> Text.pack (show (EpisodeEnvelope.simEpisodeIndex episode))
    , "episode-steps: " <> Text.pack (show (EpisodeEnvelope.simEpisodeSteps episode))
    , "episode-reward: " <> Text.pack (show (EpisodeEnvelope.simEpisodeReward episode))
    , "episode-done: " <> Text.pack (show (EpisodeEnvelope.simEpisodeDone episode))
    , "episode-frame-count: "
        <> Text.pack (show (length (EpisodeEnvelope.simEpisodeFrames episode)))
    ]
      <> concatMap renderFrame (EpisodeEnvelope.simEpisodeFrames episode)
  renderFrame frame =
    [ "frame-episode: " <> Text.pack (show (EpisodeEnvelope.simFrameEpisodeIndex frame))
    , "frame-step: " <> Text.pack (show (EpisodeEnvelope.simFrameStepIndex frame))
    , "frame-action: " <> Text.pack (show (EpisodeEnvelope.simFrameAction frame))
    , "frame-reward: " <> Text.pack (show (EpisodeEnvelope.simFrameReward frame))
    , "frame-done: " <> Text.pack (show (EpisodeEnvelope.simFrameDone frame))
    , "frame-observation: " <> Text.pack (show (EpisodeEnvelope.simFrameObservation frame))
    , "frame-next-observation: "
        <> Text.pack (show (EpisodeEnvelope.simFrameNextObservation frame))
    , "frame-action-probabilities: "
        <> Text.pack (show (EpisodeEnvelope.simFrameActionProbabilities frame))
    , "frame-caption: " <> EpisodeEnvelope.simFrameCaption frame
    ]

runRl :: RlCommandRuntime -> FilePath -> [Text] -> [ParsedOption] -> App ()
runRl runtime runConfigPath ["rl", "train"] parsedOptions = do
  -- Sprint 1.12 — parse the CLI overrides (--substrate / --seed) per
  -- README.md → Why this exists pillar 2 before any worker dispatch.
  overrides <- case Overrides.parseExperimentOverrides parsedOptions of
    Left err -> exitWithError (InvalidConfig (Overrides.renderOverrideError err))
    Right ovr -> pure ovr
  -- Sprint 5.7 — read the RL run parameters from the typed Dhall
  -- `RunConfig` the daemon mounted on the dispatched Job pod. Falls back to
  -- env vars + defaults when no mount is present (e.g., developer-side CLI
  -- invocation outside the cluster). Defaults match the
  -- `experiments/cartpole.dhall` worked example.
  let rlExperimentPath =
        Text.unpack (selectedValue "rl-experiment-dhall" "experiments/cartpole.dhall" parsedOptions)
  runConfigLoad <- liftIO (RunConfig.tryLoadRlRunConfig runConfigPath)
  (envName, seed, maxSteps, evalEpisodes, trainerKind, atariRomPath) <- case runConfigLoad of
    RunConfig.RunConfigLoaded rc -> do
      resolvedMaxSteps <-
        requirePositiveAppInt "RL maximum episode steps" (RunConfig.rlcMaxSteps rc)
      resolvedEvalEpisodes <-
        requirePositiveAppInt "RL evaluation episodes" (RunConfig.rlcEvalEpisodes rc)
      pure
        ( RunConfig.rlcEnvironment rc
        , RunConfig.rlcSeed rc
        , resolvedMaxSteps
        , resolvedEvalEpisodes
        , overrideTrainerKind overrides (Text.toLower (Text.strip (RunConfig.rlcTrainerKind rc)))
        , RunConfig.rlcAtariRomPath rc
        )
    RunConfig.RunConfigMissing -> do
      loaded <- liftIO (ProductExperiment.loadRlExperimentByPath rlExperimentPath)
      experiment <-
        case loaded of
          Left err -> exitWithError (DhallTypeError err)
          Right value -> pure value
      msR <- liftIO (envWithDefault "JITML_MAX_STEPS" "200")
      eeR <- liftIO (envWithDefault "JITML_EVAL_EPISODES" "4")
      resolvedMaxSteps <- parsePositiveAppInt "JITML_MAX_STEPS" msR
      resolvedEvalEpisodes <- parsePositiveAppInt "JITML_EVAL_EPISODES" eeR
      pure
        ( ProductExperiment.rlExperimentEnvironment experiment
        , fromIntegral (ProductExperiment.rlExperimentSeed experiment)
        , resolvedMaxSteps
        , resolvedEvalEpisodes
        , Workload.rlTrainerForAlgorithm
            (Overrides.overrideAlgorithm overrides (ProductExperiment.rlExperimentAlgorithm experiment))
        , Nothing
        )
    RunConfig.RunConfigDecodeFailed err ->
      exitWithError (mountedRunConfigDecodeError runConfigPath "RlRunConfig" err)
  -- Sprint 1.12 — apply the CLI seed override before dispatch so the
  -- override governs same-seed rollout generation. Substrate
  -- override is recorded in the summary; it flows through to deeper RL
  -- worker dispatch in follow-up work when RunConfig generation reads
  -- the resolved value.
  let resolvedSeed = fromIntegral (Overrides.overrideSeed overrides (fromIntegral seed)) :: Int
  -- Sprint 20.1 — route catalog trainers through the real dispatch path.
  -- Sprint 8.8 routes atari-subset through the runtime-loaded ALE adapter
  -- and an explicit uncommitted ROM path; all other recognized trainer
  -- selectors produce convergence statistics through the network seam, then
  -- project the per-iteration summary into the @EpisodeDone@ envelope shape
  -- so the dispatch chain stays observable end-to-end.
  -- Sprint 8.11 — resolve the substrate and route every MLP-backed trainer
  -- through its JIT-compiled device. An unknown trainer or an unavailable
  -- substrate device fails closed with a typed `InvalidConfig`; nothing is
  -- printed or published in that case.
  substrate <- Overrides.overrideSubstrate overrides <$> rlCommandWorkerSubstrateBase runtime
  env <- ask
  episodesE <-
    liftIO
      ( TrainerExecution.runTrainerEpisodes
          substrate
          (rlDeviceForSubstrate substrate env)
          atariRomPath
          trainerKind
          envName
          resolvedSeed
          evalEpisodes
          maxSteps
          Nothing
      )
  trainerRun <- case episodesE of
    Left err -> exitWithError (InvalidConfig err)
    Right run -> pure run
  let episodes = trainerRunEpisodes trainerRun
  liveExperimentHash <- rlCommandWorkerExperimentHash runtime
  let rlExperimentDhall = selectedValue "rl-experiment-dhall" "experiments/cartpole.dhall" parsedOptions
      derivedExperimentHash =
        Checkpoint.deriveExperimentHash
          rlExperimentDhall
          (renderSubstrate substrate <> ":" <> trainerKind <> ":" <> envName)
      experimentHash = fromMaybe derivedExperimentHash liveExperimentHash
      tensorName = "rl-" <> trainerKind <> "-weights"
  completionMetrics <-
    case ProductCompletion.rlCompletionMetrics trainerKind (trainerRunObservedUnits trainerRun) episodes of
      Left err -> exitWithError (InvalidConfig err)
      Right values -> pure values
  checkpointStep <-
    case TrainerExecution.rlObservedBudgetUnits episodes of
      Left err -> exitWithError (InvalidConfig err)
      Right value -> pure value
  completedTraining <-
    case trainerRunEvidence trainerRun of
      Nothing -> pure Nothing
      Just evidence ->
        case ProductCompletion.rlCompletedTraining
          CheckpointWriter.checkpointTrainingBudgetForTensor
          trainerKind
          envName
          experimentHash
          tensorName
          checkpointStep
          completionMetrics
          evidence of
          Left err -> exitWithError (InvalidConfig err)
          Right value -> pure value
  let
    averageReward = metricValueOrZero "avg_reward" completionMetrics
  checkpointMaybe <-
    case trainerRunWeights trainerRun of
      Nothing -> pure Nothing
      Just weights ->
        case completedTraining of
          Nothing -> do
            stored <-
              CheckpointWriter.writeLocalCandidateWeightCheckpoint
                experimentHash
                tensorName
                checkpointStep
                completionMetrics
                weights
            pure
              (Just (PersistedRlCandidateCheckpoint stored))
          Just completed -> do
            stored <-
              CheckpointWriter.writeLocalCompletedWeightCheckpoint
                completed
                experimentHash
                tensorName
                checkpointStep
                completionMetrics
                weights
            pure
              (Just (PersistedRlCompletedCheckpoint completed stored))
  replayArtifact <-
    CheckpointWriter.writeTextArtifact
      experimentHash
      "rl-trajectory"
      (renderRlTrajectoryArtifact experimentHash envName trainerKind resolvedSeed episodes)
  let replayArtifactLines = CheckpointWriter.renderStoredArtifactLines "rl-replay" replayArtifact
  writeText $
    Text.unlines
      ( [ "rl train: " <> rlExperimentDhall
        , "algorithms: " <> Text.pack (show (length RL.algorithmCatalog))
        , "environment: " <> envName
        , "trainer: " <> trainerKind
        , "episodes: " <> Text.pack (show (length episodes))
        , "avg-reward: " <> Text.pack (show averageReward)
        , "overrides: " <> Overrides.renderExperimentOverrides overrides
        ]
          <> maybe
            []
            ( CheckpointWriter.renderStoredCheckpointLines experimentHash
                . persistedRlStoredCheckpoint
            )
            checkpointMaybe
          <> replayArtifactLines
      )
  traverse_ (publishWorkerRlEpisode runtime envName) episodes
  publishWorkerRlCompletion runtime tensorName checkpointStep completionMetrics checkpointMaybe

-- Sprint 9.9 — `jitml rl eval` loads the named checkpoint and runs the real
-- substrate device forward (shared with `jitml eval`); a missing checkpoint →
-- `InferenceCheckpointMissing`, no echo stub.
runRl runtime _ ["rl", "eval"] parsedOptions =
  rlCommandRunCheckpointEval runtime "rl eval" parsedOptions
-- Sprint 9.9 — `jitml rl rollout --seed N` runs one real on-device PPO rollout
-- on cartpole through the resolved substrate's JIT engine and prints the
-- measured per-iteration episode rewards. No LCG `deterministicTrajectory`
-- stand-in; an unavailable substrate device fails closed with `InvalidConfig`.
runRl runtime _ ["rl", "rollout"] parsedOptions = do
  seed <- requireUserIntOptionAtLeast "seed" 42 0 parsedOptions
  substrate <- rlCommandWorkerSubstrateBase runtime
  env <- ask
  episodesE <-
    liftIO (TrainerExecution.runDeviceRollout (rlDeviceForSubstrate substrate env) seed)
  case episodesE of
    Left err -> exitWithError (InvalidConfig err)
    Right episodes -> do
      let experimentHash =
            Checkpoint.deriveExperimentHash
              "rl-rollout"
              (renderSubstrate substrate <> ":" <> Text.pack (show seed))
      replayArtifact <-
        CheckpointWriter.writeTextArtifact
          experimentHash
          "rl-rollout"
          (renderRlTrajectoryArtifact experimentHash "cartpole" "ppo-rollout" seed episodes)
      writeText $
        Text.unlines
          ( [ "rl rollout: seed="
                <> Text.pack (show seed)
                <> " substrate="
                <> renderSubstrate substrate
                <> " rewards="
                <> Text.pack (show (fmap EpisodeEnvelope.simEpisodeReward episodes))
            ]
              <> CheckpointWriter.renderStoredArtifactLines "rl-rollout" replayArtifact
          )
runRl runtime runConfigPath ["rl", "alphazero", "self-play"] parsedOptions = do
  AlphaZeroCommand.runAlphaZeroSelfPlay runtime runConfigPath parsedOptions
runRl _ _ path _ =
  exitWithError (UnknownCommand ("unknown rl command: " <> commandPathText path))
{-# NOINLINE runRl #-}

overrideTrainerKind :: Overrides.ExperimentOverrides -> Text -> Text
overrideTrainerKind overrides base =
  maybe base Workload.rlTrainerForAlgorithm (Overrides.eoAlgorithm overrides)

metricValueOrZero :: Text -> [(Text, Double)] -> Double
metricValueOrZero metricName =
  fromMaybe 0.0 . lookup metricName

publishWorkerRlCompletion
  :: RlCommandRuntime
  -> Text
  -> Word64
  -> [(Text, Double)]
  -> Maybe PersistedRlCheckpoint
  -> App ()
publishWorkerRlCompletion runtime _tensorName checkpointStep metrics checkpointMaybe = do
  target <- rlCommandWorkerBrokerTarget runtime
  experimentHashMaybe <- rlCommandWorkerExperimentHash runtime
  case (target, experimentHashMaybe) of
    (Just (substrate, pulsarSettings), Just experimentHash) -> do
      timestampNs <- liftIO (rlCommandTimestampNs runtime)
      let metricEvents =
            [ ProtoRl.RlMetric
                ProtoRl.MetricUpdate
                  { ProtoRl.muExperimentHash = experimentHash
                  , ProtoRl.muName = name
                  , ProtoRl.muValue = value
                  , ProtoRl.muTimestampNs = timestampNs
                  }
            | (name, value) <- metrics
            ]
      checkpointEvents <-
        case checkpointMaybe of
          Nothing -> pure []
          Just persisted -> do
            let stored = persistedRlStoredCheckpoint persisted
                checkpoint =
                  ProtoRl.CheckpointDoneRL
                    { ProtoRl.cdrlExperimentHash = experimentHash
                    , ProtoRl.cdrlManifestSha = CheckpointStore.storedManifestSha stored
                    , ProtoRl.cdrlStep = checkpointStep
                    , ProtoRl.cdrlPointerKey = Checkpoint.latestPointerKey experimentHash
                    }
            case persisted of
              PersistedRlCandidateCheckpoint _ ->
                pure [ProtoRl.RlCheckpoint checkpoint]
              PersistedRlCompletedCheckpoint completed _ ->
                case ProtoRl.completeCheckpointDoneRL checkpoint completed of
                  Left err ->
                    exitWithError (InvalidConfig ("RL completion event failed: " <> err))
                  Right completedCheckpoint ->
                    pure [ProtoRl.RlCompletedCheckpoint completedCheckpoint]
      for_ (metricEvents <> checkpointEvents) $ \event -> do
        result <-
          liftIO
            ( rlCommandPublishEvent
                runtime
                pulsarSettings
                substrate
                event
            )
        case result of
          Right _ -> pure ()
          Left err ->
            writeText
              ( "rl train: rl.event completion publish failed: "
                  <> Text.pack (show err)
                  <> "\n"
              )
    _ -> pure ()

persistedRlStoredCheckpoint
  :: PersistedRlCheckpoint
  -> CheckpointStore.StoredCheckpoint
persistedRlStoredCheckpoint persisted =
  case persisted of
    PersistedRlCandidateCheckpoint stored ->
      CheckpointStore.candidateStoredCheckpoint stored
    PersistedRlCompletedCheckpoint _ stored ->
      CheckpointStore.completedStoredCheckpoint stored

-- | Publish one @EpisodeDone@ envelope per trainer-produced episode. Gated on
-- @JITML_EXPERIMENT_HASH@ + live cluster publication so the worker can still
-- run offline without a broker.
publishWorkerRlEpisode
  :: RlCommandRuntime
  -> Text
  -> EpisodeEnvelope.SimulatedEpisode
  -> App ()
publishWorkerRlEpisode runtime environment episode = do
  target <- rlCommandWorkerBrokerTarget runtime
  experimentHashMaybe <- rlCommandWorkerExperimentHash runtime
  case (target, experimentHashMaybe) of
    (Just (substrate, pulsarSettings), Just experimentHash) -> do
      timestampNs <- liftIO (rlCommandTimestampNs runtime)
      let envelope =
            ProtoRl.RlEpisode
              ( ProtoRl.EpisodeDone
                  { ProtoRl.edExperimentHash = experimentHash
                  , ProtoRl.edEpisode =
                      fromIntegral (EpisodeEnvelope.simEpisodeIndex episode)
                  , ProtoRl.edReward = EpisodeEnvelope.simEpisodeReward episode
                  , ProtoRl.edSteps =
                      fromIntegral (EpisodeEnvelope.simEpisodeSteps episode)
                  , ProtoRl.edTimestampNs = timestampNs
                  }
              )
          animationEnvelopes =
            fmap
              (rlAnimationEnvelope experimentHash environment timestampNs)
              (EpisodeEnvelope.simEpisodeFrames episode)
      for_ (envelope : animationEnvelopes) $ \event -> do
        result <-
          liftIO
            ( rlCommandPublishEvent
                runtime
                pulsarSettings
                substrate
                event
            )
        case result of
          Right _ -> pure ()
          Left err ->
            writeText
              ( "rl train: rl.event publish failed: "
                  <> Text.pack (show err)
                  <> "\n"
              )
    _ -> pure ()

rlAnimationEnvelope
  :: Text
  -> Text
  -> Word64
  -> EpisodeEnvelope.SimulatedFrame
  -> ProtoRl.RlEvent
rlAnimationEnvelope experimentHash environment timestampNs frame =
  ProtoRl.RlAnimation
    ProtoRl.RlAnimationFrame
      { ProtoRl.rafExperimentHash = experimentHash
      , ProtoRl.rafEnvironment = environment
      , ProtoRl.rafEpisode = fromIntegral (EpisodeEnvelope.simFrameEpisodeIndex frame)
      , ProtoRl.rafStep = fromIntegral (EpisodeEnvelope.simFrameStepIndex frame)
      , ProtoRl.rafReward = EpisodeEnvelope.simFrameReward frame
      , ProtoRl.rafDone = EpisodeEnvelope.simFrameDone frame
      , ProtoRl.rafAction = fromIntegral (EpisodeEnvelope.simFrameAction frame)
      , ProtoRl.rafObservation = EpisodeEnvelope.simFrameNextObservation frame
      , ProtoRl.rafActionProbabilities = EpisodeEnvelope.simFrameActionProbabilities frame
      , ProtoRl.rafObservationHash =
          rlObservationHash (EpisodeEnvelope.simFrameNextObservation frame)
      , ProtoRl.rafReplayCursor =
          fromIntegral (EpisodeEnvelope.simFrameEpisodeIndex frame) * 1_000_000
            + fromIntegral (EpisodeEnvelope.simFrameStepIndex frame)
      , ProtoRl.rafTimestampNs = timestampNs
      }

rlObservationHash :: [Double] -> Word32
rlObservationHash =
  foldl' step 2166136261
 where
  step acc value =
    acc * 16777619 + fromIntegral (abs (round (value * 1_000_000) :: Int))

{-# NOINLINE rlAnimationEnvelope #-}
