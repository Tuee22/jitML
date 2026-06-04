{-# LANGUAGE OverloadedStrings #-}

module JitML.Service.Workload
  ( LoadedWeightTensor
  , WorkloadEffect (..)
  , WorkloadEffectResult (..)
  , dispatchDomainPayload
  , dispatchDomainPayloadWithInference
  , dispatchDomainPayloadWithWeightedInference
  , dispatchWorkloadPayload
  , dispatchWorkloadPayloadWithInference
  , dispatchWorkloadPayloadWithWeightedInference
  , parseWorkloadEffectPayload
  , renderWorkloadEffect
  , renderWorkloadEffectPayload
  , renderWorkloadEffectResult
  , runInferenceRequest
  , runInferenceRequestWith
  , runInferenceRequestWithWeightedInference
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

import JitML.Checkpoint.Format (CheckpointManifest, inferFromManifest)
import JitML.Checkpoint.Store (LoadedWeightTensor)
import JitML.Checkpoint.Store qualified as CheckpointStore
import JitML.Proto.Inference
  ( InferenceRequest (..)
  , InferenceResult (..)
  , parseInferenceInput
  , parseInferenceRequest
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
import JitML.Substrate (Substrate, renderSubstrate)

data WorkloadEffect
  = WriteCheckpointBlob ObjectRef ByteString
  | UpdateCheckpointPointer ObjectRef (Maybe ETag) Text
  | PromoteWorkloadImage ImageRef ImageRef
  | RunInference InferenceRequest
  | ApplyWorkloadResource KubeResource Text
  | ReadWorkloadResourceStatus KubeResource
  | DeleteWorkloadResource KubeResource
  deriving stock (Eq, Show)

data WorkloadEffectResult
  = CheckpointBlobWritten ETag
  | CheckpointPointerUpdated ETag
  | WorkloadImagePromoted ImageRef
  | InferenceResultPublished Text
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
workloadEffectsForDomainPayload domain payload =
  case domain of
    TrainingDomain ->
      maybe [] trainingCommandEffects (parseTrainingCommand payload)
    TuneDomain ->
      maybe [] tuneCommandEffects (parseTuneCommand payload)
    RlDomain ->
      maybe [] rlCommandEffects (parseRlCommand payload)
    InferenceDomain ->
      maybe [] (pure . RunInference) (parseInferenceRequest payload)

trainingCommandEffects :: TrainingCommand -> [WorkloadEffect]
trainingCommandEffects command =
  case command of
    TrainingStart start ->
      let resource = KubeResource ("job/" <> workloadName "jitml-train" (stExperimentHash start))
       in [ApplyWorkloadResource resource (renderTrainingJob start)]
    TrainingStop stop ->
      [ DeleteWorkloadResource
          (KubeResource ("job/" <> workloadName "jitml-train" (stopExperimentHash stop)))
      ]

tuneCommandEffects :: TuneCommand -> [WorkloadEffect]
tuneCommandEffects command =
  case command of
    TuneStart start ->
      let resource = KubeResource ("job/" <> workloadName "jitml-tune" (ssExperimentHash start))
       in [ApplyWorkloadResource resource (renderTuneJob start)]
    TuneStop stop ->
      [ DeleteWorkloadResource
          (KubeResource ("job/" <> workloadName "jitml-tune" (ssStopExperimentHash stop)))
      ]

rlCommandEffects :: RlCommand -> [WorkloadEffect]
rlCommandEffects command =
  case command of
    RlStart start ->
      let resource = KubeResource ("job/" <> workloadName "jitml-rl" (srlExperimentHash start))
       in [ApplyWorkloadResource resource (renderRlJob start)]
    RlStop stop ->
      [ DeleteWorkloadResource
          (KubeResource ("job/" <> workloadName "jitml-rl" (srStopExperimentHash stop)))
      ]

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
defaultCheckpointInference manifest input =
  pure (Right (inferFromManifest manifest input))

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
      case parseInferenceRequest payload of
        Nothing -> pure []
        Just request ->
          fmap
            (pure . fmap InferenceResultPublished)
            (runInferenceRequestWithWeightedInference runInference request)
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
  result <-
    CheckpointStore.loadInferenceCheckpointWithWeights
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
    "training"
    (workloadName "jitml-train" (stExperimentHash start))
    ["train", stDhallObjectKey start]
    (renderTrainingRunConfigDhall (trainingRunConfigFor start))

renderTuneJob :: StartSweep -> Text
renderTuneJob start =
  renderJobWithRunConfig
    "tune"
    (workloadName "jitml-tune" (ssExperimentHash start))
    ["tune", ssDhallObjectKey start]
    (renderTuneRunConfigDhall (tuneRunConfigFor start))

renderRlJob :: StartRLRun -> Text
renderRlJob start =
  renderJobWithRunConfig
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

renderJob :: Text -> Text -> [Text] -> [(Text, Text)] -> Text
renderJob component name args envVars =
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
    , "      containers:"
    , "        - name: " <> component
    , "          image: jitml:local"
    , "          command:"
    , "            - " <> yamlString "jitml"
    , "          args:"
    ]
      <> fmap (("            - " <>) . yamlString) args
      <> [ "          env:"
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
renderJobWithRunConfig :: Text -> Text -> [Text] -> Text -> Text
renderJobWithRunConfig component jobName args runConfigDhall =
  let configMapName = "runconfig-" <> jobName
   in renderRunConfigConfigMap configMapName runConfigDhall
        <> "---\n"
        <> renderJobMountedRunConfig component jobName configMapName args

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

renderJobMountedRunConfig :: Text -> Text -> Text -> [Text] -> Text
renderJobMountedRunConfig component jobName configMapName args =
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
    , "      containers:"
    , "        - name: " <> component
    , "          image: jitml:local"
    , "          command:"
    , "            - " <> yamlString "jitml"
    , "          args:"
    ]
      <> fmap (("            - " <>) . yamlString) args
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
