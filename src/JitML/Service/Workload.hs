{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TupleSections #-}

module JitML.Service.Workload
  ( LoadedWeightTensor
  , WorkloadKind (..)
  , WorkloadEffect (..)
  , WorkloadEffectResult (..)
  , WorkloadPlacement (..)
  , dispatchDomainPayload
  , dispatchDomainPayloadForResidency
  , dispatchDomainPayloadWithInference
  , dispatchDomainPayloadWithPlacement
  , dispatchDomainPayloadWithWeightedInference
  , dispatchWorkloadPayload
  , dispatchWorkloadPayloadWithInference
  , dispatchWorkloadPayloadWithWeightedInference
  , hostWorkloadCommandTopic
  , parseWorkloadEffectPayload
  , planWorkloadPlacement
  , renderRlJob
  , renderTrainingJob
  , renderTuneJob
  , rlTrainerForAlgorithm
  , renderWorkloadEffect
  , renderWorkloadEffectPayload
  , renderWorkloadEffectResult
  , runInferenceRequest
  , runInferenceRequestWith
  , runInferenceRequestWithWeightedInference
  , runListCheckpointsRequest
  , runLoadTranscriptRequest
  , seededDemoExperimentHashes
  , runWorkloadEffect
  , runWorkloadEffectWithInference
  , runWorkloadEffectWithWeightedInference
  , runWorkloadEffects
  , runWorkloadEffectsWithInference
  , runWorkloadEffectsWithWeightedInference
  )
where

import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.Char
  ( digitToInt
  , intToDigit
  , isAsciiLower
  , isAsciiUpper
  , isDigit
  , isHexDigit
  , toLower
  )
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Checkpoint.Format
  ( CheckpointManifest (..)
  , ModelFamily (..)
  , manifestContentSha
  )
import JitML.Checkpoint.Store (LoadedWeightTensor)
import JitML.Checkpoint.Store qualified as CheckpointStore
import JitML.Inference.AdversarialMove
  ( AdversarialMoveOutcome (..)
  , adversarialRuntimeInput
  , computeAdversarialMove
  )
import JitML.Inference.Decode qualified as Decode
import JitML.Proto.Inference
  ( AdversarialMoveCommand (..)
  , AdversarialMoveResult (..)
  , CheckpointCompareCommand (..)
  , CheckpointCompareResult (..)
  , InferenceRequest (..)
  , InferenceResult (..)
  , ListCheckpointsCommand (..)
  , LoadTranscriptCommand (..)
  , parseAdversarialMoveCommand
  , parseCheckpointCompareCommand
  , parseInferenceInput
  , parseInferenceRequest
  , parseListCheckpointsCommand
  , parseLoadTranscriptCommand
  , renderAdversarialMoveResult
  , renderCheckpointCompareResult
  , renderInferenceRequest
  , renderInferenceResult
  )
import JitML.Proto.Rl
  ( RlCommand (..)
  , StartRLRun (..)
  , StopRLRun (..)
  , parseRlCommand
  )
import JitML.Proto.Training
  ( StartTraining (..)
  , StopTraining (..)
  , TrainingCommand (..)
  , parseTrainingCommand
  )
import JitML.Proto.Tune
  ( StartSweep (..)
  , StopSweep (..)
  , TuneCommand (..)
  , parseTuneCommand
  )
import JitML.Service.BootConfig (Residency (..))
import JitML.Service.Capabilities
  ( BucketName (..)
  , ETag (..)
  , HasHarbor (..)
  , HasKubectl (..)
  , HasMinIO (..)
  , HasPulsar (..)
  , ImageRef (..)
  , KubeResource (..)
  , ObjectKey (..)
  , ObjectRef (..)
  , TopicName (..)
  )
import JitML.Service.Consumer (EventDomain (..))
import JitML.Service.Retry (ServiceError (..))
import JitML.Service.RunConfig
  ( RlRunConfig (..)
  , TrainingRunConfig (..)
  , TuneRunConfig (..)
  , renderRlRunConfigDhall
  , renderTrainingRunConfigDhall
  , renderTuneRunConfigDhall
  )
import JitML.Service.Transcript
  ( TranscriptRecord (..)
  , readTranscriptRecord
  , writeTranscriptRecord
  )
import JitML.Substrate (Substrate (..), renderSubstrate, substrateRuntimeClass)

data WorkloadKind
  = WorkloadInference
  | WorkloadTraining
  | WorkloadTune
  | WorkloadRl
  deriving stock (Eq, Show)

data WorkloadPlacement
  = WorkloadClusterJob
  | WorkloadHostCommand TopicName
  deriving stock (Eq, Show)

data WorkloadEffect
  = WriteCheckpointBlob ObjectRef ByteString
  | UpdateCheckpointPointer ObjectRef (Maybe ETag) Text
  | PromoteWorkloadImage ImageRef ImageRef
  | RunInference InferenceRequest
  | PublishHostWorkloadCommand TopicName Text
  | ApplyWorkloadResource KubeResource Text
  | ReadWorkloadResourceStatus KubeResource
  | DeleteWorkloadResource KubeResource
  deriving stock (Eq, Show)

data WorkloadEffectResult
  = CheckpointBlobWritten ETag
  | CheckpointPointerUpdated ETag
  | WorkloadImagePromoted ImageRef
  | InferenceResultPublished Text
  | HostWorkloadCommandPublished TopicName
  | WorkloadResourceApplied
  | WorkloadResourceStatus Text
  | WorkloadResourceDeleted
  deriving stock (Eq, Show)

runWorkloadEffect
  :: (HasHarbor m, HasKubectl m, HasMinIO m, HasPulsar m)
  => WorkloadEffect
  -> m (Either ServiceError WorkloadEffectResult)
runWorkloadEffect =
  runWorkloadEffectWithInference defaultCheckpointInference

runWorkloadEffectWithInference
  :: (HasHarbor m, HasKubectl m, HasMinIO m, HasPulsar m)
  => (CheckpointManifest -> [Double] -> m (Either Text [Double]))
  -> WorkloadEffect
  -> m (Either ServiceError WorkloadEffectResult)
runWorkloadEffectWithInference runInference effect =
  case effect of
    WriteCheckpointBlob ref payload ->
      fmap CheckpointBlobWritten <$> putBlobBytesIfAbsent ref payload
    UpdateCheckpointPointer ref expected payload ->
      fmap CheckpointPointerUpdated <$> casPointer ref expected payload
    PromoteWorkloadImage source target ->
      fmap WorkloadImagePromoted <$> harborPromoteImage source target
    RunInference request ->
      fmap InferenceResultPublished <$> runInferenceRequestWith runInference request
    PublishHostWorkloadCommand topic payload ->
      fmap (const (HostWorkloadCommandPublished topic)) <$> pulsarPublish topic payload
    ApplyWorkloadResource resource manifest ->
      fmap (const WorkloadResourceApplied) <$> kubectlApply resource manifest
    ReadWorkloadResourceStatus resource ->
      fmap WorkloadResourceStatus <$> kubectlStatus resource
    DeleteWorkloadResource resource ->
      fmap (const WorkloadResourceDeleted) <$> kubectlDelete resource

runWorkloadEffects
  :: (HasHarbor m, HasKubectl m, HasMinIO m, HasPulsar m)
  => [WorkloadEffect]
  -> m [Either ServiceError WorkloadEffectResult]
runWorkloadEffects =
  runWorkloadEffectsWithInference defaultCheckpointInference

runWorkloadEffectsWithInference
  :: (HasHarbor m, HasKubectl m, HasMinIO m, HasPulsar m)
  => (CheckpointManifest -> [Double] -> m (Either Text [Double]))
  -> [WorkloadEffect]
  -> m [Either ServiceError WorkloadEffectResult]
runWorkloadEffectsWithInference runInference =
  traverse (runWorkloadEffectWithInference runInference)

dispatchWorkloadPayload
  :: (HasHarbor m, HasKubectl m, HasMinIO m, HasPulsar m)
  => Text
  -> m (Maybe (Either ServiceError WorkloadEffectResult))
dispatchWorkloadPayload =
  dispatchWorkloadPayloadWithInference defaultCheckpointInference

dispatchWorkloadPayloadWithInference
  :: (HasHarbor m, HasKubectl m, HasMinIO m, HasPulsar m)
  => (CheckpointManifest -> [Double] -> m (Either Text [Double]))
  -> Text
  -> m (Maybe (Either ServiceError WorkloadEffectResult))
dispatchWorkloadPayloadWithInference runInference payload =
  case parseWorkloadEffectPayload payload of
    Nothing -> pure Nothing
    Just effect -> Just <$> runWorkloadEffectWithInference runInference effect

dispatchDomainPayload
  :: (HasHarbor m, HasKubectl m, HasMinIO m, HasPulsar m)
  => EventDomain
  -> Text
  -> m [Either ServiceError WorkloadEffectResult]
dispatchDomainPayload =
  dispatchDomainPayloadWithInference defaultCheckpointInference

dispatchDomainPayloadWithInference
  :: (HasHarbor m, HasKubectl m, HasMinIO m, HasPulsar m)
  => (CheckpointManifest -> [Double] -> m (Either Text [Double]))
  -> EventDomain
  -> Text
  -> m [Either ServiceError WorkloadEffectResult]
dispatchDomainPayloadWithInference runInference domain payload =
  case domain of
    InferenceDomain ->
      case parseInferenceRequest payload of
        Nothing -> pure []
        Just request ->
          fmap (pure . fmap InferenceResultPublished) (runInferenceRequestWith runInference request)
    _ ->
      runWorkloadEffectsWithInference runInference (workloadEffectsForDomainPayload domain payload)

workloadEffectsForDomainPayload :: EventDomain -> Text -> [WorkloadEffect]
workloadEffectsForDomainPayload =
  workloadEffectsForDomainPayloadForResidency Cluster

workloadEffectsForDomainPayloadForResidency
  :: Residency -> EventDomain -> Text -> [WorkloadEffect]
workloadEffectsForDomainPayloadForResidency residency domain payload =
  case domain of
    TrainingDomain ->
      maybe [] (trainingCommandEffects residency payload) (parseTrainingCommand payload)
    TuneDomain ->
      maybe [] (tuneCommandEffects residency payload) (parseTuneCommand payload)
    RlDomain ->
      maybe [] (rlCommandEffects residency payload) (parseRlCommand payload)
    InferenceDomain ->
      maybe [] (pure . RunInference) (parseInferenceRequest payload)

dispatchDomainPayloadForResidency
  :: (HasHarbor m, HasKubectl m, HasMinIO m, HasPulsar m)
  => Residency
  -> EventDomain
  -> Text
  -> m [Either ServiceError WorkloadEffectResult]
dispatchDomainPayloadForResidency residency domain payload =
  runWorkloadEffects (workloadEffectsForDomainPayloadForResidency residency domain payload)

dispatchDomainPayloadWithPlacement
  :: (HasHarbor m, HasKubectl m, HasMinIO m, HasPulsar m)
  => Residency
  -> EventDomain
  -> Text
  -> m [Either ServiceError WorkloadEffectResult]
dispatchDomainPayloadWithPlacement =
  dispatchDomainPayloadForResidency

trainingCommandEffects :: Residency -> Text -> TrainingCommand -> [WorkloadEffect]
trainingCommandEffects residency payload command =
  case command of
    TrainingStart start ->
      case planWorkloadPlacement residency WorkloadTraining (stSubstrate start) of
        WorkloadClusterJob ->
          let resource = KubeResource ("job/" <> workloadName "jitml-train" (stExperimentHash start))
           in [ApplyWorkloadResource resource (renderTrainingJob start)]
        WorkloadHostCommand topic ->
          [PublishHostWorkloadCommand topic payload]
    TrainingStop stop ->
      [ DeleteWorkloadResource
          (KubeResource ("job/" <> workloadName "jitml-train" (stopExperimentHash stop)))
      ]

tuneCommandEffects :: Residency -> Text -> TuneCommand -> [WorkloadEffect]
tuneCommandEffects residency payload command =
  case command of
    TuneStart start ->
      case planWorkloadPlacement residency WorkloadTune (ssSubstrate start) of
        WorkloadClusterJob ->
          let resource = KubeResource ("job/" <> workloadName "jitml-tune" (ssExperimentHash start))
           in [ApplyWorkloadResource resource (renderTuneJob start)]
        WorkloadHostCommand topic ->
          [PublishHostWorkloadCommand topic payload]
    TuneStop stop ->
      [ DeleteWorkloadResource
          (KubeResource ("job/" <> workloadName "jitml-tune" (ssStopExperimentHash stop)))
      ]

rlCommandEffects :: Residency -> Text -> RlCommand -> [WorkloadEffect]
rlCommandEffects residency payload command =
  case command of
    RlStart start ->
      case planWorkloadPlacement residency WorkloadRl (srlSubstrate start) of
        WorkloadClusterJob ->
          let resource = KubeResource ("job/" <> workloadName "jitml-rl" (srlExperimentHash start))
           in [ApplyWorkloadResource resource (renderRlJob start)]
        WorkloadHostCommand topic ->
          [PublishHostWorkloadCommand topic payload]
    RlStop stop ->
      [ DeleteWorkloadResource
          (KubeResource ("job/" <> workloadName "jitml-rl" (srStopExperimentHash stop)))
      ]

planWorkloadPlacement :: Residency -> WorkloadKind -> Substrate -> WorkloadPlacement
planWorkloadPlacement residency kind substrate =
  case (residency, kind, substrate) of
    (Cluster, WorkloadTraining, AppleSilicon) ->
      WorkloadHostCommand (hostWorkloadCommandTopic WorkloadTraining AppleSilicon)
    (Cluster, WorkloadTune, AppleSilicon) ->
      WorkloadHostCommand (hostWorkloadCommandTopic WorkloadTune AppleSilicon)
    (Cluster, WorkloadRl, AppleSilicon) ->
      WorkloadHostCommand (hostWorkloadCommandTopic WorkloadRl AppleSilicon)
    _ -> WorkloadClusterJob

hostWorkloadCommandTopic :: WorkloadKind -> Substrate -> TopicName
hostWorkloadCommandTopic kind substrate =
  TopicName $
    "persistent://public/default/"
      <> hostWorkloadCommandPrefix kind
      <> "."
      <> renderSubstrate substrate

hostWorkloadCommandPrefix :: WorkloadKind -> Text
hostWorkloadCommandPrefix kind =
  case kind of
    WorkloadTraining -> "training.host-command"
    WorkloadTune -> "tune.host-command"
    WorkloadRl -> "rl.host-command"
    WorkloadInference -> "inference.command"

runInferenceRequest
  :: (HasMinIO m, HasPulsar m)
  => InferenceRequest
  -> m (Either ServiceError Text)
runInferenceRequest =
  runInferenceRequestWith defaultCheckpointInference

runInferenceRequestWith
  :: (HasMinIO m, HasPulsar m)
  => (CheckpointManifest -> [Double] -> m (Either Text [Double]))
  -> InferenceRequest
  -> m (Either ServiceError Text)
runInferenceRequestWith runInference request = do
  result <-
    CheckpointStore.loadInferenceCheckpointWith
      runInference
      (irExperimentHash request)
      (irInput request)
  case result of
    Left err ->
      pure (Left (SETransient ("inference: " <> err)))
    Right output ->
      pulsarPublish
        (TopicName (irReplyTopic request))
        ( renderInferenceResult
            InferenceResult
              { iresCallId = irCallId request
              , iresExperimentHash = irExperimentHash request
              , iresOutput = output
              }
        )

defaultCheckpointInference
  :: (Applicative m)
  => CheckpointManifest
  -> [Double]
  -> m (Either Text [Double])
defaultCheckpointInference _manifest _input =
  pure (Left "weighted inference runner required")

-- | Weighted-callback variants of the dispatcher chain. Sprint 13.11: the
-- substrate-bound inference runners (`runLinuxCpuWeightedCheckpointInference`,
-- `runCudaWeightedCheckpointInference`) consume `LoadedWeightTensor`s decoded
-- from `.jmw1` blobs, so the daemon path needs to read them through
-- `loadInferenceCheckpointWithWeights` instead of the unweighted summary path.
-- These functions mirror the unweighted variants but plumb the weighted
-- callback through `runInferenceRequestWithWeightedInference`.
runWorkloadEffectWithWeightedInference
  :: (HasHarbor m, HasKubectl m, HasMinIO m, HasPulsar m)
  => (CheckpointManifest -> [LoadedWeightTensor] -> [Double] -> m (Either Text [Double]))
  -> WorkloadEffect
  -> m (Either ServiceError WorkloadEffectResult)
runWorkloadEffectWithWeightedInference runInference effect =
  case effect of
    WriteCheckpointBlob ref payload ->
      fmap CheckpointBlobWritten <$> putBlobBytesIfAbsent ref payload
    UpdateCheckpointPointer ref expected payload ->
      fmap CheckpointPointerUpdated <$> casPointer ref expected payload
    PromoteWorkloadImage source target ->
      fmap WorkloadImagePromoted <$> harborPromoteImage source target
    RunInference request ->
      fmap InferenceResultPublished
        <$> runInferenceRequestWithWeightedInference runInference request
    PublishHostWorkloadCommand topic payload ->
      fmap (const (HostWorkloadCommandPublished topic)) <$> pulsarPublish topic payload
    ApplyWorkloadResource resource manifest ->
      fmap (const WorkloadResourceApplied) <$> kubectlApply resource manifest
    ReadWorkloadResourceStatus resource ->
      fmap WorkloadResourceStatus <$> kubectlStatus resource
    DeleteWorkloadResource resource ->
      fmap (const WorkloadResourceDeleted) <$> kubectlDelete resource

runWorkloadEffectsWithWeightedInference
  :: (HasHarbor m, HasKubectl m, HasMinIO m, HasPulsar m)
  => (CheckpointManifest -> [LoadedWeightTensor] -> [Double] -> m (Either Text [Double]))
  -> [WorkloadEffect]
  -> m [Either ServiceError WorkloadEffectResult]
runWorkloadEffectsWithWeightedInference runInference =
  traverse (runWorkloadEffectWithWeightedInference runInference)

dispatchWorkloadPayloadWithWeightedInference
  :: (HasHarbor m, HasKubectl m, HasMinIO m, HasPulsar m)
  => (CheckpointManifest -> [LoadedWeightTensor] -> [Double] -> m (Either Text [Double]))
  -> Text
  -> m (Maybe (Either ServiceError WorkloadEffectResult))
dispatchWorkloadPayloadWithWeightedInference runInference payload =
  case parseWorkloadEffectPayload payload of
    Nothing -> pure Nothing
    Just effect -> Just <$> runWorkloadEffectWithWeightedInference runInference effect

dispatchDomainPayloadWithWeightedInference
  :: (HasHarbor m, HasKubectl m, HasMinIO m, HasPulsar m)
  => (CheckpointManifest -> [LoadedWeightTensor] -> [Double] -> m (Either Text [Double]))
  -> EventDomain
  -> Text
  -> m [Either ServiceError WorkloadEffectResult]
dispatchDomainPayloadWithWeightedInference runInference domain payload =
  case domain of
    InferenceDomain ->
      -- Sprint 11.10 — one inference lane carries three command kinds: a single
      -- inference, a checkpoint compare (two inferences + delta), and an
      -- adversarial move (inference + MCTS). All compute in the Engine.
      case parseInferenceRequest payload of
        Just request ->
          fmap
            (pure . fmap InferenceResultPublished)
            (runInferenceRequestWithWeightedInference runInference request)
        Nothing ->
          case parseCheckpointCompareCommand payload of
            Just command ->
              fmap
                (pure . fmap InferenceResultPublished)
                (runCheckpointCompareRequestWithWeightedInference runInference command)
            Nothing ->
              case parseAdversarialMoveCommand payload of
                Just command ->
                  fmap
                    (pure . fmap InferenceResultPublished)
                    (runAdversarialMoveRequestWithWeightedInference runInference command)
                Nothing ->
                  case parseListCheckpointsCommand payload of
                    Just command ->
                      fmap
                        (pure . fmap InferenceResultPublished)
                        (runListCheckpointsRequest command)
                    Nothing ->
                      case parseLoadTranscriptCommand payload of
                        Just command ->
                          fmap
                            (pure . fmap InferenceResultPublished)
                            (runLoadTranscriptRequest command)
                        Nothing -> pure []
    _ ->
      runWorkloadEffectsWithWeightedInference
        runInference
        (workloadEffectsForDomainPayload domain payload)

runInferenceRequestWithWeightedInference
  :: (HasMinIO m, HasPulsar m)
  => (CheckpointManifest -> [LoadedWeightTensor] -> [Double] -> m (Either Text [Double]))
  -> InferenceRequest
  -> m (Either ServiceError Text)
runInferenceRequestWithWeightedInference runInference request = do
  -- Sprint 11.10 — the Engine decodes the output (the manifest's output decoder)
  -- and appends the typed `decoded-*` lines to the `WorkResult` so the browser
  -- panels render the decoded value without computing.
  result <-
    CheckpointStore.loadInferenceCheckpointDecodedWithWeights
      runInference
      (irExperimentHash request)
      (irInput request)
  case result of
    Left err ->
      pure (Left (SETransient ("inference: " <> err)))
    Right (output, decoded) ->
      pulsarPublish
        (TopicName (irReplyTopic request))
        ( renderInferenceResult
            InferenceResult
              { iresCallId = irCallId request
              , iresExperimentHash = irExperimentHash request
              , iresOutput = output
              }
            <> Text.unlines (Decode.renderDecodedInference decoded)
        )

-- | Sprint 11.10 — checkpoint compare as an Engine job: run both inferences and
-- compute the delta in the daemon, then publish one 'CheckpointCompareResult'.
runCheckpointCompareRequestWithWeightedInference
  :: (HasMinIO m, HasPulsar m)
  => (CheckpointManifest -> [LoadedWeightTensor] -> [Double] -> m (Either Text [Double]))
  -> CheckpointCompareCommand
  -> m (Either ServiceError Text)
runCheckpointCompareRequestWithWeightedInference runInference command = do
  baseline <-
    CheckpointStore.loadInferenceCheckpointDecodedWithWeights
      runInference
      (cccBaselineExperimentHash command)
      (cccInput command)
  candidate <-
    CheckpointStore.loadInferenceCheckpointDecodedWithWeights
      runInference
      (cccCandidateExperimentHash command)
      (cccInput command)
  case (baseline, candidate) of
    (Left err, _) -> pure (Left (SETransient ("compare baseline: " <> err)))
    (_, Left err) -> pure (Left (SETransient ("compare candidate: " <> err)))
    (Right (baselineOutput, _), Right (candidateOutput, _)) ->
      let deltas = absoluteDeltas baselineOutput candidateOutput
       in pulsarPublish
            (TopicName (cccReplyTopic command))
            ( renderCheckpointCompareResult
                CheckpointCompareResult
                  { ccrCallId = cccCallId command
                  , ccrBaselineExperimentHash = cccBaselineExperimentHash command
                  , ccrCandidateExperimentHash = cccCandidateExperimentHash command
                  , ccrBaselineOutput = baselineOutput
                  , ccrCandidateOutput = candidateOutput
                  , ccrMaxAbsDelta = maximumOrZero deltas
                  , ccrMeanAbsDelta = meanOrZero deltas
                  }
            )

-- | Sprint 11.10 — adversarial move as an Engine job: run the policy/value
-- inference and the MCTS search in the daemon, then publish one
-- 'AdversarialMoveResult'.
runAdversarialMoveRequestWithWeightedInference
  :: (HasMinIO m, HasPulsar m)
  => (CheckpointManifest -> [LoadedWeightTensor] -> [Double] -> m (Either Text [Double]))
  -> AdversarialMoveCommand
  -> m (Either ServiceError Text)
runAdversarialMoveRequestWithWeightedInference runInference command = do
  let runtimeInput =
        adversarialRuntimeInput
          (amcGame command)
          (amcMoves command)
          (amcHumanIsPlayer command)
          (amcSimulationsPerMove command)
  result <-
    CheckpointStore.loadInferenceCheckpointDecodedWithWeights
      runInference
      (amcExperimentHash command)
      runtimeInput
  case result of
    Left err -> pure (Left (SETransient ("adversarial: " <> err)))
    Right (output, _) -> do
      let outcome =
            computeAdversarialMove
              (amcGame command)
              (amcMoves command)
              (amcHumanIsPlayer command)
              (amcSimulationsPerMove command)
              output
          -- Sprint 14.1 (Feature B) — the full move sequence (the human moves
          -- plus the AI's chosen column) is what the replay panel scrubs.
          fullMoves = amcMoves command <> [amoChosenColumn outcome]
          analysis =
            "value="
              <> Text.pack (show (amoValueEstimate outcome))
              <> " visits="
              <> Text.intercalate "," (fmap (Text.pack . show) (amoVisitCounts outcome))
          record =
            TranscriptRecord
              { transcriptGame = amcGame command
              , transcriptExperimentHash = amcExperimentHash command
              , transcriptMoves = fullMoves
              , transcriptAnalysis = analysis
              }
          -- The synthesized fallback id is only used if the persist write fails
          -- (so the move frame still carries a non-empty transcript reference).
          synthesizedId =
            Text.intercalate
              ":"
              [ amcGame command
              , Text.intercalate "," (fmap (Text.pack . show) fullMoves)
              , Text.pack (show (amcHumanIsPlayer command))
              ]
      -- Persist the transcript to the `jitml-transcripts` bucket and key the
      -- result frame to the REAL MinIO object key (the replay panel reads it
      -- back through `LoadTranscriptCommand`).
      persisted <- writeTranscriptRecord record
      let transcriptId =
            case persisted of
              Right (key, _etag) -> key
              Left _ -> synthesizedId
      pulsarPublish
        (TopicName (amcReplyTopic command))
        ( renderAdversarialMoveResult
            AdversarialMoveResult
              { amrCallId = amcCallId command
              , amrExperimentHash = amcExperimentHash command
              , amrGame = amcGame command
              , amrChosenColumn = amoChosenColumn outcome
              , amrLegalMoves = amoLegalMoves outcome
              , amrVisitCounts = amoVisitCounts outcome
              , amrPolicyPriors = amoPolicyPriors outcome
              , amrValueEstimate = amoValueEstimate outcome
              , amrGameOver = amoGameOver outcome
              , amrTranscriptId = transcriptId
              }
        )

-- | Sprint 14.1 (Feature A) — the five seeded demo experiment hashes the
-- checkpoint-browse panel lists (mirrors `runInternalSeedDemoCheckpoints` in
-- `JitML.App`). The browse Engine job lists each experiment's manifests from
-- MinIO and folds them into one `CheckpointList` frame.
seededDemoExperimentHashes :: [Text]
seededDemoExperimentHashes =
  [ "mnist-deep-mlp"
  , "generic-tensor-demo"
  , "generic-tensor-demo-candidate"
  , "cifar-imagenet"
  , "connect4-alphazero"
  ]

-- | Sprint 14.1 (Feature A) — checkpoint browse as an Engine job: for each
-- seeded experiment hash, list its manifests from the `jitml-checkpoints`
-- MinIO bucket and publish a single `CheckpointList` frame summarising every
-- manifest, on the command's reply topic.
runListCheckpointsRequest
  :: (HasMinIO m, HasPulsar m)
  => ListCheckpointsCommand
  -> m (Either ServiceError Text)
runListCheckpointsRequest command = do
  listings <-
    traverse
      ( \experimentHash -> do
          manifests <- CheckpointStore.listCheckpointManifestsMinIO experimentHash
          pure (fmap (experimentHash,) manifests)
      )
      seededDemoExperimentHashes
  case sequence listings of
    Left err -> pure (Left err)
    Right perExperiment ->
      let summaries = concatMap (uncurry checkpointSummaries) perExperiment
       in pulsarPublish
            (TopicName (lccReplyTopic command))
            (renderCheckpointListResult (lccCallId command) summaries)

-- | Render the per-experiment manifests into `checkpoint-summary:` lines, one
-- per manifest. Each summary is a tab-separated tuple of
-- experiment-hash / sha / step / model-family / tensor-count.
checkpointSummaries :: Text -> [CheckpointManifest] -> [Text]
checkpointSummaries experimentHash =
  fmap (checkpointSummaryLine experimentHash)

checkpointSummaryLine :: Text -> CheckpointManifest -> Text
checkpointSummaryLine experimentHash manifest =
  Text.intercalate
    "\t"
    [ experimentHash
    , manifestContentSha manifest
    , Text.pack (show (manifestStep manifest))
    , renderModelFamily (manifestModelFamily manifest)
    , Text.pack (show (length (manifestTensors manifest)))
    ]

renderModelFamily :: ModelFamily -> Text
renderModelFamily family =
  case family of
    GenericModelFamily -> "generic"
    SupervisedModelFamily -> "supervised"
    ReinforcementLearningPolicyFamily -> "rl-policy"
    AlphaZeroPolicyValueFamily -> "alphazero"
    HyperparameterTuningFamily -> "hyperparameter"

-- | Sprint 14.1 (Feature A) — the `CheckpointList` result frame. Each
-- `checkpoint-summary:` line carries one tab-separated manifest summary; the
-- browser panel splits them into a `CheckpointSummary` list.
renderCheckpointListResult :: Text -> [Text] -> Text
renderCheckpointListResult callId summaries =
  Text.unlines $
    [ "kind: CheckpointList"
    , "call-id: " <> callId
    , "panel: checkpoint-browse"
    , "count: " <> Text.pack (show (length summaries))
    ]
      <> fmap ("checkpoint-summary: " <>) summaries

-- | Sprint 14.1 (Feature B) — transcript replay as an Engine job: read the
-- persisted transcript record from the `jitml-transcripts` MinIO bucket keyed
-- by the command's transcript id and publish a `TranscriptReplay` frame on the
-- reply topic.
runLoadTranscriptRequest
  :: (HasMinIO m, HasPulsar m)
  => LoadTranscriptCommand
  -> m (Either ServiceError Text)
runLoadTranscriptRequest command = do
  record <- readTranscriptRecord (ltcTranscriptId command)
  -- A missing/unreadable transcript is terminal, not retryable: always publish a
  -- reply (an empty replay on failure) so the consumer acks rather than
  -- NACK-retrying a poison message forever (which would back the consumer up and
  -- delay real replies). The replay panel renders the empty frame as no moves.
  let transcript =
        case record of
          Right t -> t
          Left err ->
            TranscriptRecord
              { transcriptGame = ""
              , transcriptExperimentHash = ""
              , transcriptMoves = []
              , transcriptAnalysis = "transcript unavailable: " <> err
              }
  pulsarPublish
    (TopicName (ltcReplyTopic command))
    (renderTranscriptReplayResult (ltcCallId command) (ltcTranscriptId command) transcript)

renderTranscriptReplayResult :: Text -> Text -> TranscriptRecord -> Text
renderTranscriptReplayResult callId transcriptId record =
  Text.unlines
    [ "kind: TranscriptReplay"
    , "call-id: " <> callId
    , "panel: transcript-replay"
    , "transcript-id: " <> transcriptId
    , "game: " <> transcriptGame record
    , "experiment-hash: " <> transcriptExperimentHash record
    , "moves: " <> Text.intercalate "," (fmap (Text.pack . show) (transcriptMoves record))
    , "analysis: " <> Text.replace "\n" " " (transcriptAnalysis record)
    ]

absoluteDeltas :: [Double] -> [Double] -> [Double]
absoluteDeltas baseline candidate =
  let count = max (length baseline) (length candidate)
      padded values = take count (values <> repeat 0.0)
   in zipWith (\left right -> abs (left - right)) (padded baseline) (padded candidate)

maximumOrZero :: [Double] -> Double
maximumOrZero [] = 0.0
maximumOrZero values = maximum values

meanOrZero :: [Double] -> Double
meanOrZero [] = 0.0
meanOrZero values = sum values / fromIntegral (length values)

-- | Sprint 5.7 — render a typed 'TrainingRunConfig' from a 'StartTraining'
-- envelope. SL caps are left absent here: the worker uses sensible defaults
-- when the RunConfig leaves them as @None@.
trainingRunConfigFor :: StartTraining -> TrainingRunConfig
trainingRunConfigFor start =
  TrainingRunConfig
    { trcExperimentHash = stExperimentHash start
    , trcSubstrate = renderSubstrateText (stSubstrate start)
    , trcSeed = fromIntegral (stSeed start)
    , trcEpochs = fromIntegral (stEpochs start)
    , trcBatchSize = fromIntegral (stBatchSize start)
    , trcPulsarWsUrl = inClusterPulsarWsUrl
    , trcSlTrainLimit = Nothing
    , trcSlEpochs = Nothing
    , trcSlTestLimit = Nothing
    }

tuneRunConfigFor :: StartSweep -> TuneRunConfig
tuneRunConfigFor start =
  TuneRunConfig
    { turcExperimentHash = ssExperimentHash start
    , turcSubstrate = renderSubstrateText (ssSubstrate start)
    , turcSweepSeed = fromIntegral (ssSweepSeed start)
    , turcTrialBudget = fromIntegral (ssTrialBudget start)
    , turcBudgetPerTrial = fromIntegral (ssBudgetPerTrial start)
    , turcSampler = ssSampler start
    , turcScheduler = ssScheduler start
    , turcPruner = ssPruner start
    , turcPulsarWsUrl = inClusterPulsarWsUrl
    }

rlRunConfigFor :: StartRLRun -> RlRunConfig
rlRunConfigFor start =
  RlRunConfig
    { rlcExperimentHash = srlExperimentHash start
    , rlcAlgorithm = srlAlgorithm start
    , rlcEnvironment = srlEnvironment start
    , rlcSubstrate = renderSubstrateText (srlSubstrate start)
    , rlcSeed = fromIntegral (srlSeed start)
    , rlcMaxSteps = fromIntegral (srlMaxSteps start)
    , rlcEvalEpisodes = fromIntegral (srlEvalEpisodes start)
    , rlcTrainerKind = rlTrainerForAlgorithm (srlAlgorithm start)
    , rlcAtariRomPath = Nothing
    , rlcPulsarWsUrl = inClusterPulsarWsUrl
    }

renderTrainingJob :: StartTraining -> Text
renderTrainingJob start =
  renderJobWithRunConfig
    (stSubstrate start)
    "training"
    (workloadName "jitml-train" (stExperimentHash start))
    ["train", stDhallObjectKey start]
    (renderTrainingRunConfigDhall (trainingRunConfigFor start))

renderTuneJob :: StartSweep -> Text
renderTuneJob start =
  renderJobWithRunConfig
    (ssSubstrate start)
    "tune"
    (workloadName "jitml-tune" (ssExperimentHash start))
    ["tune", ssDhallObjectKey start]
    (renderTuneRunConfigDhall (tuneRunConfigFor start))

renderRlJob :: StartRLRun -> Text
renderRlJob start =
  renderJobWithRunConfig
    (srlSubstrate start)
    "rl"
    (workloadName "jitml-rl" (srlExperimentHash start))
    ["rl", "train", srlExperimentHash start]
    (renderRlRunConfigDhall (rlRunConfigFor start))

-- | Sprint 5.7 — kept for the alternate code path that still wants an
-- env-driven Job manifest (no current callers). The daemon path now uses
-- 'renderJobWithRunConfig'. Retained as the simple Job renderer so the
-- typed JSON envelope path can fall back to it if needed.
_renderRlJobLegacyEnv :: StartRLRun -> Text
_renderRlJobLegacyEnv start =
  renderJob
    (srlSubstrate start)
    "rl"
    (workloadName "jitml-rl" (srlExperimentHash start))
    ["rl", "train", srlExperimentHash start]
    [ ("JITML_EXPERIMENT_HASH", srlExperimentHash start)
    , ("JITML_ALGORITHM", srlAlgorithm start)
    , ("JITML_ENVIRONMENT", srlEnvironment start)
    , ("JITML_SUBSTRATE", renderSubstrateText (srlSubstrate start))
    , ("JITML_SEED", Text.pack (show (srlSeed start)))
    , ("JITML_MAX_STEPS", Text.pack (show (srlMaxSteps start)))
    , ("JITML_EVAL_EPISODES", Text.pack (show (srlEvalEpisodes start)))
    , -- Sprint 13.8 — route each catalog algorithm to its real
      -- network-backed trainer in the worker (PPO/A2C/TRPO/MaskablePPO/
      -- RecurrentPPO on-policy, DQN/QR-DQN/DDPG/TD3/SAC/CrossQ/TQC
      -- off-policy, ARS gradient-free, HER goal-conditioned). Unknown
      -- algorithm names fall back to the deterministic simulator loop.
      ("JITML_RL_TRAINER", rlTrainerForAlgorithm (srlAlgorithm start))
    , ("JITML_PULSAR_WS", inClusterPulsarWsUrl)
    ]

-- | The in-cluster Pulsar WebSocket endpoint a daemon-dispatched worker
-- Job uses to publish completion events back to the broker. A Job pod
-- cannot reach the host edge (@127.0.0.1:\<edge-port\>@); it reaches the
-- broker through the in-cluster service DNS instead. Matches the daemon's
-- own cluster WebSocket endpoint in 'JitML.Service.Clients'.
inClusterPulsarWsUrl :: Text
inClusterPulsarWsUrl = "ws://pulsar-broker.platform.svc.cluster.local:8080/ws"

-- | Map an RL algorithm name to the worker-side trainer selector the
-- worker's @jitml rl train@ command reads from @JITML_RL_TRAINER@. Each
-- catalog algorithm selects its real MLP-backed trainer; an unrecognised
-- name keeps the deterministic per-episode simulator loop.
rlTrainerForAlgorithm :: Text -> Text
rlTrainerForAlgorithm algorithm =
  case Text.toUpper (Text.strip algorithm) of
    "PPO" -> "ppo"
    "A2C" -> "a2c"
    "TRPO" -> "trpo"
    "MASKABLEPPO" -> "maskableppo"
    "RECURRENTPPO" -> "recurrentppo"
    "DQN" -> "dqn"
    "QR-DQN" -> "qrdqn"
    "QRDQN" -> "qrdqn"
    "DDPG" -> "ddpg"
    "TD3" -> "td3"
    "SAC" -> "sac"
    "CROSSQ" -> "crossq"
    "TQC" -> "tqc"
    "ARS" -> "ars"
    "HER" -> "her"
    _ -> "simulator"

renderJob :: Substrate -> Text -> Text -> [Text] -> [(Text, Text)] -> Text
renderJob substrate component name args envVars =
  Text.unlines $
    [ "apiVersion: batch/v1"
    , "kind: Job"
    , "metadata:"
    , "  name: " <> name
    , "  labels:"
    , "    app.kubernetes.io/name: jitml"
    , "    app.kubernetes.io/component: " <> component
    , "spec:"
    , "  template:"
    , "    spec:"
    , "      restartPolicy: Never"
    ]
      <> renderRuntimeClassLines substrate
      <> [ "      containers:"
         , "        - name: " <> component
         , "          image: jitml:local"
         , "          command:"
         , "            - " <> yamlString "jitml"
         , "          args:"
         ]
      <> fmap (("            - " <>) . yamlString) args
      <> renderContainerEnvLines (nvidiaEnvVars substrate <> envVars)

renderRuntimeClassLines :: Substrate -> [Text]
renderRuntimeClassLines substrate =
  case substrateRuntimeClass substrate of
    Nothing -> []
    Just runtimeClass ->
      ["      runtimeClassName: " <> runtimeClass]

nvidiaEnvVars :: Substrate -> [(Text, Text)]
nvidiaEnvVars substrate =
  case substrateRuntimeClass substrate of
    Nothing -> []
    Just _ ->
      [ ("NVIDIA_VISIBLE_DEVICES", "all")
      , ("NVIDIA_DRIVER_CAPABILITIES", "compute,utility")
      ]

renderContainerEnvLines :: [(Text, Text)] -> [Text]
renderContainerEnvLines [] = []
renderContainerEnvLines envVars =
  [ "          env:"
  ]
    <> concatMap renderEnvVar envVars

renderEnvVar :: (Text, Text) -> [Text]
renderEnvVar (name, value) =
  [ "            - name: " <> name
  , "              value: " <> yamlString value
  ]

-- | Sprint 5.7 — render two YAML documents: a per-run ConfigMap containing
-- @RunConfig.dhall@, and a Job whose pod mounts both that ConfigMap (at
-- @/etc/jitml/run/@) and the shared @jitml-service-config@ ConfigMap (at
-- @/etc/jitml/service/@). The Job's container takes no @JITML_*@ environment
-- variables; the worker reads typed Dhall instead.
renderJobWithRunConfig :: Substrate -> Text -> Text -> [Text] -> Text -> Text
renderJobWithRunConfig substrate component jobName args runConfigDhall =
  let configMapName = "runconfig-" <> jobName
   in renderRunConfigConfigMap configMapName runConfigDhall
        <> "---\n"
        <> renderJobMountedRunConfig substrate component jobName configMapName args

renderRunConfigConfigMap :: Text -> Text -> Text
renderRunConfigConfigMap name dhall =
  Text.unlines
    [ "apiVersion: v1"
    , "kind: ConfigMap"
    , "metadata:"
    , "  name: " <> name
    , "  namespace: platform"
    , "data:"
    , "  RunConfig.dhall: |"
    ]
    <> indentDhallBlock dhall

indentDhallBlock :: Text -> Text
indentDhallBlock dhall =
  Text.unlines (fmap ("    " <>) (Text.lines dhall))

renderJobMountedRunConfig :: Substrate -> Text -> Text -> Text -> [Text] -> Text
renderJobMountedRunConfig substrate component jobName configMapName args =
  Text.unlines $
    [ "apiVersion: batch/v1"
    , "kind: Job"
    , "metadata:"
    , "  name: " <> jobName
    , "  labels:"
    , "    app.kubernetes.io/name: jitml"
    , "    app.kubernetes.io/component: " <> component
    , "spec:"
    , "  template:"
    , "    spec:"
    , "      restartPolicy: Never"
    ]
      <> renderRuntimeClassLines substrate
      <> [ "      containers:"
         , "        - name: " <> component
         , "          image: jitml:local"
         , "          command:"
         , "            - " <> yamlString "jitml"
         , "          args:"
         ]
      <> fmap (("            - " <>) . yamlString) args
      <> renderContainerEnvLines (nvidiaEnvVars substrate)
      <> [ "          volumeMounts:"
         , "            - name: jitml-run-config"
         , "              mountPath: /etc/jitml/run"
         , "            - name: jitml-service-config"
         , "              mountPath: /etc/jitml/service"
         , "      volumes:"
         , "        - name: jitml-run-config"
         , "          configMap:"
         , "            name: " <> configMapName
         , "        - name: jitml-service-config"
         , "          configMap:"
         , "            name: jitml-service-config"
         ]

workloadName :: Text -> Text -> Text
workloadName prefix experimentHash =
  let suffix = kubeSafeName experimentHash
      base = prefix <> "-" <> suffix
   in Text.take 63 (Text.dropWhileEnd (== '-') base)

kubeSafeName :: Text -> Text
kubeSafeName value =
  case Text.dropWhileEnd (== '-') (Text.dropWhile (== '-') (Text.map kubeChar value)) of
    "" -> "unknown"
    safe -> safe

kubeChar :: Char -> Char
kubeChar char
  | isAsciiLower char || isDigit char = char
  | isAsciiUpper char = toLower char
  | otherwise = '-'

yamlString :: Text -> Text
yamlString value =
  "\"" <> Text.replace "\"" "\\\"" value <> "\""

renderSubstrateText :: Substrate -> Text
renderSubstrateText =
  renderSubstrate

renderWorkloadEffectPayload :: WorkloadEffect -> Text
renderWorkloadEffectPayload effect =
  Text.unlines $
    [ "kind: WorkloadEffect"
    , "effect: " <> workloadEffectTag effect
    ]
      <> workloadEffectFields effect

parseWorkloadEffectPayload :: Text -> Maybe WorkloadEffect
parseWorkloadEffectPayload payload = do
  let fields = mapMaybe parseField (Text.lines payload)
      value key = lookup key fields
  "WorkloadEffect" <- value "kind"
  effectTag <- value "effect"
  case effectTag of
    "WriteCheckpointBlob" -> do
      ref <- objectRefFromFields value
      payloadBytes <- value "payload-hex" >>= hexDecodeText
      pure (WriteCheckpointBlob ref payloadBytes)
    "UpdateCheckpointPointer" -> do
      ref <- objectRefFromFields value
      pointerPayload <- value "payload"
      let expected = ETag <$> value "expected-etag"
      pure (UpdateCheckpointPointer ref expected pointerPayload)
    "PromoteWorkloadImage" -> do
      source <- ImageRef <$> value "source-image"
      target <- ImageRef <$> value "target-image"
      pure (PromoteWorkloadImage source target)
    "RunInference" -> do
      callId <- value "call-id"
      experimentHash <- value "experiment-hash"
      replyTopic <- value "reply-topic"
      input <- value "input" >>= parseInferenceInput
      pure
        ( RunInference
            InferenceRequest
              { irCallId = callId
              , irExperimentHash = experimentHash
              , irReplyTopic = replyTopic
              , irInput = input
              }
        )
    "PublishHostWorkloadCommand" -> do
      topic <- TopicName <$> value "topic"
      hostPayload <- value "payload"
      pure (PublishHostWorkloadCommand topic (Text.replace "\\n" "\n" hostPayload))
    "ApplyWorkloadResource" -> do
      resource <- KubeResource <$> value "resource"
      manifest <- value "manifest"
      pure (ApplyWorkloadResource resource (Text.replace "\\n" "\n" manifest))
    "ReadWorkloadResourceStatus" -> do
      resource <- KubeResource <$> value "resource"
      pure (ReadWorkloadResourceStatus resource)
    "DeleteWorkloadResource" -> do
      resource <- KubeResource <$> value "resource"
      pure (DeleteWorkloadResource resource)
    _ -> Nothing

renderWorkloadEffect :: WorkloadEffect -> Text
renderWorkloadEffect effect =
  case effect of
    WriteCheckpointBlob ref _ ->
      "minio:write-checkpoint-blob " <> renderObjectRef ref
    UpdateCheckpointPointer ref expected _ ->
      "minio:update-checkpoint-pointer "
        <> renderObjectRef ref
        <> " expected="
        <> maybe "(none)" unETag expected
    PromoteWorkloadImage source target ->
      "harbor:promote-image " <> unImageRef source <> " -> " <> unImageRef target
    RunInference request ->
      "inference:run " <> irCallId request <> " -> " <> irReplyTopic request
    PublishHostWorkloadCommand (TopicName topic) _ ->
      "pulsar:publish-host-workload " <> topic
    ApplyWorkloadResource resource _ ->
      "kubectl:apply " <> unKubeResource resource
    ReadWorkloadResourceStatus resource ->
      "kubectl:status " <> unKubeResource resource
    DeleteWorkloadResource resource ->
      "kubectl:delete " <> unKubeResource resource

renderWorkloadEffectResult :: WorkloadEffectResult -> Text
renderWorkloadEffectResult result =
  case result of
    CheckpointBlobWritten etag ->
      "checkpoint-blob-written " <> unETag etag
    CheckpointPointerUpdated etag ->
      "checkpoint-pointer-updated " <> unETag etag
    WorkloadImagePromoted image ->
      "workload-image-promoted " <> unImageRef image
    InferenceResultPublished messageId ->
      "inference-result-published " <> messageId
    HostWorkloadCommandPublished (TopicName topic) ->
      "host-workload-command-published " <> topic
    WorkloadResourceApplied ->
      "workload-resource-applied"
    WorkloadResourceStatus status ->
      "workload-resource-status " <> Text.replace "\n" " " status
    WorkloadResourceDeleted ->
      "workload-resource-deleted"

renderObjectRef :: ObjectRef -> Text
renderObjectRef ref =
  let BucketName bucket = objectBucket ref
      ObjectKey key = objectKey ref
   in bucket <> "/" <> key

workloadEffectTag :: WorkloadEffect -> Text
workloadEffectTag effect =
  case effect of
    WriteCheckpointBlob _ _ -> "WriteCheckpointBlob"
    UpdateCheckpointPointer {} -> "UpdateCheckpointPointer"
    PromoteWorkloadImage _ _ -> "PromoteWorkloadImage"
    RunInference _ -> "RunInference"
    PublishHostWorkloadCommand _ _ -> "PublishHostWorkloadCommand"
    ApplyWorkloadResource _ _ -> "ApplyWorkloadResource"
    ReadWorkloadResourceStatus _ -> "ReadWorkloadResourceStatus"
    DeleteWorkloadResource _ -> "DeleteWorkloadResource"

workloadEffectFields :: WorkloadEffect -> [Text]
workloadEffectFields effect =
  case effect of
    WriteCheckpointBlob ref payload ->
      objectRefFields ref
        <> ["payload-hex: " <> hexEncodeText payload]
    UpdateCheckpointPointer ref expected payload ->
      objectRefFields ref
        <> maybe [] (\etag -> ["expected-etag: " <> unETag etag]) expected
        <> ["payload: " <> payload]
    PromoteWorkloadImage source target ->
      [ "source-image: " <> unImageRef source
      , "target-image: " <> unImageRef target
      ]
    RunInference request ->
      dropKindLine (renderInferenceRequest request)
    PublishHostWorkloadCommand (TopicName topic) payload ->
      [ "topic: " <> topic
      , "payload: " <> Text.replace "\n" "\\n" payload
      ]
    ApplyWorkloadResource resource manifest ->
      [ "resource: " <> unKubeResource resource
      , "manifest: " <> Text.replace "\n" "\\n" manifest
      ]
    ReadWorkloadResourceStatus resource ->
      ["resource: " <> unKubeResource resource]
    DeleteWorkloadResource resource ->
      ["resource: " <> unKubeResource resource]

dropKindLine :: Text -> [Text]
dropKindLine value =
  case Text.lines value of
    [] -> []
    _kindLine : rest -> rest

objectRefFields :: ObjectRef -> [Text]
objectRefFields ref =
  let BucketName bucket = objectBucket ref
      ObjectKey key = objectKey ref
   in [ "bucket: " <> bucket
      , "key: " <> key
      ]

objectRefFromFields :: (Text -> Maybe Text) -> Maybe ObjectRef
objectRefFromFields value = do
  bucket <- BucketName <$> value "bucket"
  key <- ObjectKey <$> value "key"
  pure (ObjectRef bucket key)

parseField :: Text -> Maybe (Text, Text)
parseField line =
  let (key, rest) = Text.breakOn ":" line
   in if Text.null rest
        then Nothing
        else Just (Text.strip key, Text.strip (Text.drop 1 rest))

hexEncodeText :: ByteString -> Text
hexEncodeText =
  Text.pack . concatMap byteToHex . ByteString.unpack
 where
  byteToHex byte =
    [ intToDigit (fromIntegral (byte `div` 16))
    , intToDigit (fromIntegral (byte `mod` 16))
    ]

hexDecodeText :: Text -> Maybe ByteString
hexDecodeText value =
  ByteString.pack <$> go (Text.unpack value)
 where
  go [] = Just []
  go [_] = Nothing
  go (hi : lo : rest)
    | isHexDigit hi && isHexDigit lo = do
        bytes <- go rest
        pure (fromIntegral (digitToInt hi * 16 + digitToInt lo) : bytes)
    | otherwise = Nothing
