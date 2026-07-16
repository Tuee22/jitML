{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StandaloneDeriving #-}

module JitML.Service.Workload
  ( LoadedWeightTensor
  , WorkloadEffectKind (..)
  , WorkloadEffect (..)
  , WorkloadEffectResult (..)
  , SomeWorkloadEffect (..)
  , SomeWorkloadOutcome (..)
  , WorkloadDecodeError (..)
  , ClusterJobSpec (..)
  , HostCommandSpec
  , InferenceResultTarget
  , WorkloadLaunch (..)
  , WorkloadPlacement (..)
  , buildInferenceWorkloadEffectsForTopic
  , buildRlWorkloadEffects
  , buildTrainingWorkloadEffects
  , buildTuneWorkloadEffects
  , dispatchInferenceCommandForTopic
  , dispatchInferenceCommandForTopicWithInference
  , dispatchInferenceCommandForTopicWithWeightedInference
  , dispatchRlCommand
  , dispatchTrainingCommand
  , dispatchTuneCommand
  , dispatchWorkloadPayload
  , hostCommandSpecPayload
  , hostCommandSpecTopicName
  , inferenceResultTargetSubstrate
  , inferenceResultTargetTopicName
  , parseWorkloadEffectPayload
  , planWorkloadPlacement
  , renderRlJob
  , renderAlphaZeroJob
  , renderTrainingJob
  , renderTuneJob
  , rlTrainerForAlgorithm
  , renderWorkloadEffect
  , renderWorkloadEffectPayload
  , renderWorkloadEffectResult
  , renderSomeWorkloadEffect
  , renderSomeWorkloadOutcome
  , checkpointSummaries
  , checkpointSummariesForRow
  , renderCheckpointListResult
  , renderCheckpointListResultWithSelectors
  , seededDemoExperimentHashes
  , runWorkloadEffect
  , runWorkloadEffectWithInference
  , runWorkloadEffectWithWeightedInference
  , runWorkloadEffects
  , runWorkloadEffectsWithInference
  , runWorkloadEffectsWithWeightedInference
  , someWorkloadEffectKind
  , workloadEffectKind
  , workloadOutcomeError
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
import Data.Either.Combinators (mapLeft)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Maybe (catMaybes, mapMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding

import JitML.Checkpoint.Format
  ( CheckpointManifest (..)
  , ModelFamily (..)
  , eligibleCheckpointCompletedTraining
  , manifestContentSha
  , requireInferenceEligibleCheckpoint
  )
import JitML.Checkpoint.Store (LoadedWeightTensor)
import JitML.Checkpoint.Store qualified as CheckpointStore
import JitML.Coordinator.Topology
  ( InferenceResultMessage
  , ProtocolRoute (..)
  , Topic
  , decodeTopicPayload
  , encodeTopicPayload
  , mkInferenceResultMessage
  , resolveTopic
  , topicFor
  , topicName
  , topicSubstrate
  )
import JitML.Inference.AdversarialMove
  ( AdversarialMoveOutcome (..)
  , adversarialRuntimeInput
  , computeAdversarialMove
  )
import JitML.Inference.Decode qualified as Decode
import JitML.Plan.Command qualified as PlanCommand
import JitML.Plan.Plan (planIdText)
import JitML.Plan.Workload
  ( AlphaZeroPlan
  , SupervisedPlan
  , TuningPlan
  , alphaZeroPlanId
  , renderAlphaZeroPlanTransport
  , renderSupervisedPlanTransport
  , renderTuningPlanTransport
  , supervisedPlanId
  , tuningPlanId
  )
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.Product.Pipeline qualified as ProductPipeline
import JitML.Proto.Inference
  ( AdversarialMoveCommand (..)
  , AdversarialMoveResult (..)
  , CheckpointCompareCommand (..)
  , CheckpointCompareResult (..)
  , InferenceCommand
  , InferenceRequest (..)
  , InferenceResult (..)
  , ListCheckpointsCommand (..)
  , LoadTranscriptCommand (..)
  , renderAdversarialMoveResult
  , renderCheckpointCompareResult
  , renderInferenceRequest
  , renderInferenceResult
  )
import JitML.Proto.Inference qualified as Inference
import JitML.Proto.Rl
  ( RlCommand (..)
  , StartAlphaZeroRun (..)
  , StartRLRun (..)
  , StopRLRun (..)
  )
import JitML.Proto.Training
  ( StartTraining (..)
  , StopTraining (..)
  , TrainingCommand (..)
  )
import JitML.Proto.Tune
  ( StartSweep (..)
  , StopSweep (..)
  , TuneCommand (..)
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
  )
import JitML.Service.Retry (ServiceError (..))
import JitML.Service.RunConfig
  ( AlphaZeroRunConfig (..)
  , RlRunConfig (..)
  , TrainingRunConfig (..)
  , TuneRunConfig (..)
  , renderAlphaZeroRunConfigDhall
  , renderRlRunConfigDhall
  , renderTrainingRunConfigDhall
  , renderTuneRunConfigDhall
  )
import JitML.Service.Transcript
  ( TranscriptRecord (..)
  , readTranscriptRecord
  , writeTranscriptRecord
  )
import JitML.Substrate
  ( Substrate (..)
  , parseSubstrate
  , renderSubstrate
  , substrateRuntimeClass
  )
import JitML.Training.Budget
  ( ConvergenceObservation
  , coMetricName
  , coMetricValue
  , completedTrainingBudget
  , completedTrainingMetrics
  , completedTrainingTensorBoard
  , renderTrainingBudget
  , tbrLogPrefix
  )

type InferenceRunner m =
  ProductPipeline.InferenceEligibleRef
  -> CheckpointManifest
  -> [Double]
  -> m (Either Text [Double])

type WeightedInferenceRunner m =
  ProductPipeline.InferenceEligibleRef
  -> CheckpointManifest
  -> [LoadedWeightTensor]
  -> [Double]
  -> m (Either Text [Double])

-- | Closed effect indices. A constructor of 'WorkloadEffect' fixes one of
-- these indices, and 'WorkloadEffectResult' uses the same index. It is
-- therefore impossible to pair, for example, a kubectl status effect with an
-- image-promotion result.
data WorkloadEffectKind
  = CheckpointBlobWrite
  | CheckpointPointerUpdate
  | WorkloadImagePromotion
  | InferenceCommandExecution
  | HostCommandPublication
  | WorkloadResourceApplication
  | WorkloadResourceStatusRead
  | WorkloadResourceDeletion
  deriving stock (Eq, Show)

data WorkloadEffect (kind :: WorkloadEffectKind) where
  WriteCheckpointBlob
    :: ObjectRef
    -> ByteString
    -> WorkloadEffect 'CheckpointBlobWrite
  UpdateCheckpointPointer
    :: ObjectRef
    -> Maybe ETag
    -> Text
    -> WorkloadEffect 'CheckpointPointerUpdate
  PromoteWorkloadImage
    :: ImageRef
    -> ImageRef
    -> WorkloadEffect 'WorkloadImagePromotion
  RunInference
    :: InferenceResultTarget
    -> InferenceRequest
    -> WorkloadEffect 'InferenceCommandExecution
  CompareInferenceCheckpoints
    :: InferenceResultTarget
    -> CheckpointCompareCommand
    -> WorkloadEffect 'InferenceCommandExecution
  RunAdversarialMove
    :: InferenceResultTarget
    -> AdversarialMoveCommand
    -> WorkloadEffect 'InferenceCommandExecution
  ListInferenceCheckpoints
    :: InferenceResultTarget
    -> ListCheckpointsCommand
    -> WorkloadEffect 'InferenceCommandExecution
  LoadInferenceTranscript
    :: InferenceResultTarget
    -> LoadTranscriptCommand
    -> WorkloadEffect 'InferenceCommandExecution
  PublishHostWorkloadCommand
    :: HostCommandSpec
    -> WorkloadEffect 'HostCommandPublication
  ApplyWorkloadResource
    :: KubeResource
    -> Text
    -> WorkloadEffect 'WorkloadResourceApplication
  ReadWorkloadResourceStatus
    :: KubeResource
    -> WorkloadEffect 'WorkloadResourceStatusRead
  DeleteWorkloadResource
    :: KubeResource
    -> WorkloadEffect 'WorkloadResourceDeletion

deriving stock instance Eq (WorkloadEffect kind)
deriving stock instance Show (WorkloadEffect kind)

data WorkloadEffectResult (kind :: WorkloadEffectKind) where
  CheckpointBlobWritten
    :: ETag
    -> WorkloadEffectResult 'CheckpointBlobWrite
  CheckpointPointerUpdated
    :: ETag
    -> WorkloadEffectResult 'CheckpointPointerUpdate
  WorkloadImagePromoted
    :: ImageRef
    -> WorkloadEffectResult 'WorkloadImagePromotion
  InferenceResultPublished
    :: Text
    -> WorkloadEffectResult 'InferenceCommandExecution
  HostWorkloadCommandPublished
    :: Text
    -> WorkloadEffectResult 'HostCommandPublication
  WorkloadResourceApplied
    :: WorkloadEffectResult 'WorkloadResourceApplication
  WorkloadResourceStatus
    :: Text
    -> WorkloadEffectResult 'WorkloadResourceStatusRead
  WorkloadResourceDeleted
    :: WorkloadEffectResult 'WorkloadResourceDeletion

deriving stock instance Eq (WorkloadEffectResult kind)
deriving stock instance Show (WorkloadEffectResult kind)

-- | Existential wrapper for a heterogeneous, non-empty effect program.
data SomeWorkloadEffect where
  SomeWorkloadEffect :: WorkloadEffect kind -> SomeWorkloadEffect

instance Eq SomeWorkloadEffect where
  left == right = renderWorkloadEffectPayloadForSome left == renderWorkloadEffectPayloadForSome right

instance Show SomeWorkloadEffect where
  show = Text.unpack . renderSomeWorkloadEffect

-- | The effect witness is retained beside its indexed outcome, so even a
-- failure still records which result type was expected.
data SomeWorkloadOutcome where
  SomeWorkloadOutcome
    :: WorkloadEffect kind
    -> Either ServiceError (WorkloadEffectResult kind)
    -> SomeWorkloadOutcome

instance Show SomeWorkloadOutcome where
  show = Text.unpack . renderSomeWorkloadOutcome

data WorkloadDecodeError
  = InvalidWorkloadEffectPayload Text
  | WorkloadCommandSubstrateMismatch Substrate Substrate
  | WorkloadTopologyError Text
  | WorkloadPlanError Text
  deriving stock (Eq, Show)

-- | Complete cluster placement evidence. Applying a placement never has to
-- reconstruct either the resource identity or its manifest later.
data ClusterJobSpec = ClusterJobSpec
  { clusterJobResource :: KubeResource
  , clusterJobManifest :: Text
  }
  deriving stock (Eq, Show)

-- | Existential typed host command. The topic and event share the same hidden
-- event parameter; arbitrary text cannot be paired with a typed topic.
data HostCommandSpec where
  HostCommandSpec :: Topic event -> event -> HostCommandSpec

instance Eq HostCommandSpec where
  left == right =
    hostCommandSpecTopicName left == hostCommandSpecTopicName right
      && hostCommandSpecPayload left == hostCommandSpecPayload right

instance Show HostCommandSpec where
  show spec =
    "HostCommandSpec "
      <> show (hostCommandSpecTopicName spec)
      <> " "
      <> show (hostCommandSpecPayload spec)

-- | The result route refined against the substrate of the consumed typed
-- inference-command topic. Its constructor is private, so daemon effects can
-- only obtain it through 'buildInferenceWorkloadEffectsForTopic'.
newtype InferenceResultTarget = InferenceResultTarget
  { inferenceResultTargetTopic :: Topic InferenceResultMessage
  }
  deriving stock (Eq, Show)

data WorkloadLaunch
  = TrainingLaunch StartTraining
  | ResolvedTrainingLaunch StartTraining SupervisedPlan
  | TuneLaunch StartSweep TuningPlan
  | RlLaunch StartRLRun
  | AlphaZeroLaunch StartAlphaZeroRun AlphaZeroPlan
  deriving stock (Eq, Show)

data WorkloadPlacement
  = WorkloadClusterJob ClusterJobSpec
  | WorkloadHostCommand HostCommandSpec
  deriving stock (Eq, Show)

hostCommandSpecTopicName :: HostCommandSpec -> Text
hostCommandSpecTopicName (HostCommandSpec topic _) = topicName topic

hostCommandSpecPayload :: HostCommandSpec -> Text
hostCommandSpecPayload (HostCommandSpec topic event) = encodeTopicPayload topic event

inferenceResultTargetTopicName :: InferenceResultTarget -> Text
inferenceResultTargetTopicName = topicName . inferenceResultTargetTopic

inferenceResultTargetSubstrate :: InferenceResultTarget -> Substrate
inferenceResultTargetSubstrate = topicSubstrate . inferenceResultTargetTopic

workloadEffectKind :: WorkloadEffect kind -> WorkloadEffectKind
workloadEffectKind effect =
  case effect of
    WriteCheckpointBlob {} -> CheckpointBlobWrite
    UpdateCheckpointPointer {} -> CheckpointPointerUpdate
    PromoteWorkloadImage {} -> WorkloadImagePromotion
    RunInference {} -> InferenceCommandExecution
    CompareInferenceCheckpoints {} -> InferenceCommandExecution
    RunAdversarialMove {} -> InferenceCommandExecution
    ListInferenceCheckpoints {} -> InferenceCommandExecution
    LoadInferenceTranscript {} -> InferenceCommandExecution
    PublishHostWorkloadCommand {} -> HostCommandPublication
    ApplyWorkloadResource {} -> WorkloadResourceApplication
    ReadWorkloadResourceStatus {} -> WorkloadResourceStatusRead
    DeleteWorkloadResource {} -> WorkloadResourceDeletion

someWorkloadEffectKind :: SomeWorkloadEffect -> WorkloadEffectKind
someWorkloadEffectKind (SomeWorkloadEffect effect) = workloadEffectKind effect

workloadOutcomeError :: SomeWorkloadOutcome -> Maybe ServiceError
workloadOutcomeError (SomeWorkloadOutcome _ result) =
  case result of
    Left err -> Just err
    Right _ -> Nothing

runWorkloadEffect
  :: (HasHarbor m, HasKubectl m, HasMinIO m, HasPulsar m)
  => WorkloadEffect kind
  -> m (Either ServiceError (WorkloadEffectResult kind))
runWorkloadEffect =
  runWorkloadEffectWithInference defaultCheckpointInference

runWorkloadEffectWithInference
  :: (HasHarbor m, HasKubectl m, HasMinIO m, HasPulsar m)
  => InferenceRunner m
  -> WorkloadEffect kind
  -> m (Either ServiceError (WorkloadEffectResult kind))
runWorkloadEffectWithInference runInference effect =
  case effect of
    WriteCheckpointBlob ref payload ->
      fmap CheckpointBlobWritten <$> putBlobBytesIfAbsent ref payload
    UpdateCheckpointPointer ref expected payload ->
      fmap CheckpointPointerUpdated <$> casPointer ref expected payload
    PromoteWorkloadImage source target ->
      fmap WorkloadImagePromoted <$> harborPromoteImage source target
    RunInference target request ->
      fmap InferenceResultPublished <$> runInferenceRequestWithTarget target runInference request
    CompareInferenceCheckpoints _ _ ->
      pure (Left (SETransient "checkpoint compare requires a weighted inference runner"))
    RunAdversarialMove _ _ ->
      pure (Left (SETransient "adversarial move requires a weighted inference runner"))
    ListInferenceCheckpoints target command ->
      fmap InferenceResultPublished <$> runListCheckpointsRequestWithTarget target command
    LoadInferenceTranscript target command ->
      fmap InferenceResultPublished <$> runLoadTranscriptRequestWithTarget target command
    PublishHostWorkloadCommand spec ->
      fmap (const (HostWorkloadCommandPublished (hostCommandSpecTopicName spec)))
        <$> publishHostCommand spec
    ApplyWorkloadResource resource manifest ->
      fmap (const WorkloadResourceApplied) <$> kubectlApply resource manifest
    ReadWorkloadResourceStatus resource ->
      fmap WorkloadResourceStatus <$> kubectlStatus resource
    DeleteWorkloadResource resource ->
      fmap (const WorkloadResourceDeleted) <$> kubectlDelete resource

runWorkloadEffects
  :: (HasHarbor m, HasKubectl m, HasMinIO m, HasPulsar m)
  => NonEmpty SomeWorkloadEffect
  -> m (NonEmpty SomeWorkloadOutcome)
runWorkloadEffects =
  runWorkloadEffectsWithInference defaultCheckpointInference

runWorkloadEffectsWithInference
  :: (HasHarbor m, HasKubectl m, HasMinIO m, HasPulsar m)
  => InferenceRunner m
  -> NonEmpty SomeWorkloadEffect
  -> m (NonEmpty SomeWorkloadOutcome)
runWorkloadEffectsWithInference runInference =
  traverse (runSomeWorkloadEffectWithInference runInference)

runSomeWorkloadEffectWithInference
  :: (HasHarbor m, HasKubectl m, HasMinIO m, HasPulsar m)
  => InferenceRunner m
  -> SomeWorkloadEffect
  -> m SomeWorkloadOutcome
runSomeWorkloadEffectWithInference runInference (SomeWorkloadEffect effect) =
  SomeWorkloadOutcome effect <$> runWorkloadEffectWithInference runInference effect

dispatchWorkloadPayload
  :: (HasHarbor m, HasKubectl m, HasMinIO m, HasPulsar m)
  => Text
  -> m (Either WorkloadDecodeError SomeWorkloadOutcome)
dispatchWorkloadPayload payload =
  case parseWorkloadEffectPayload payload of
    Left err -> pure (Left err)
    Right effect ->
      Right <$> runSomeWorkloadEffectWithInference defaultCheckpointInference effect

dispatchTrainingCommand
  :: (HasHarbor m, HasKubectl m, HasMinIO m, HasPulsar m)
  => Residency
  -> Substrate
  -> TrainingCommand
  -> m (Either WorkloadDecodeError (NonEmpty SomeWorkloadOutcome))
dispatchTrainingCommand residency substrate command =
  runBuiltWorkloadEffects (buildTrainingWorkloadEffects residency substrate command)

dispatchTuneCommand
  :: (HasHarbor m, HasKubectl m, HasMinIO m, HasPulsar m)
  => Residency
  -> Substrate
  -> TuneCommand
  -> m (Either WorkloadDecodeError (NonEmpty SomeWorkloadOutcome))
dispatchTuneCommand residency substrate command =
  runBuiltWorkloadEffects (buildTuneWorkloadEffects residency substrate command)

dispatchRlCommand
  :: (HasHarbor m, HasKubectl m, HasMinIO m, HasPulsar m)
  => Residency
  -> Substrate
  -> RlCommand
  -> m (Either WorkloadDecodeError (NonEmpty SomeWorkloadOutcome))
dispatchRlCommand residency substrate command =
  runBuiltWorkloadEffects (buildRlWorkloadEffects residency substrate command)

runBuiltWorkloadEffects
  :: (HasHarbor m, HasKubectl m, HasMinIO m, HasPulsar m)
  => Either WorkloadDecodeError (NonEmpty SomeWorkloadEffect)
  -> m (Either WorkloadDecodeError (NonEmpty SomeWorkloadOutcome))
runBuiltWorkloadEffects result =
  case result of
    Left err -> pure (Left err)
    Right effects -> Right <$> runWorkloadEffects effects

dispatchInferenceCommandForTopic
  :: (HasMinIO m, HasPulsar m)
  => Topic InferenceCommand
  -> InferenceCommand
  -> m (Either WorkloadDecodeError (NonEmpty SomeWorkloadOutcome))
dispatchInferenceCommandForTopic =
  dispatchInferenceCommandForTopicWithInference defaultCheckpointInference

dispatchInferenceCommandForTopicWithInference
  :: (HasMinIO m, HasPulsar m)
  => InferenceRunner m
  -> Topic InferenceCommand
  -> InferenceCommand
  -> m (Either WorkloadDecodeError (NonEmpty SomeWorkloadOutcome))
dispatchInferenceCommandForTopicWithInference runInference inputTopic command =
  case inferenceCommandEffectForTopic inputTopic command of
    Left err -> pure (Left err)
    Right effect -> do
      result <- runInferenceCommandEffectWithInference runInference effect
      pure (Right (SomeWorkloadOutcome effect result :| []))

dispatchInferenceCommandForTopicWithWeightedInference
  :: (HasMinIO m, HasPulsar m)
  => WeightedInferenceRunner m
  -> Topic InferenceCommand
  -> InferenceCommand
  -> m (Either WorkloadDecodeError (NonEmpty SomeWorkloadOutcome))
dispatchInferenceCommandForTopicWithWeightedInference runInference inputTopic command =
  case inferenceCommandEffectForTopic inputTopic command of
    Left err -> pure (Left err)
    Right effect -> do
      result <- runInferenceCommandEffectWithWeightedInference runInference effect
      pure (Right (SomeWorkloadOutcome effect result :| []))

runInferenceCommandEffectWithInference
  :: (HasMinIO m, HasPulsar m)
  => InferenceRunner m
  -> WorkloadEffect 'InferenceCommandExecution
  -> m (Either ServiceError (WorkloadEffectResult 'InferenceCommandExecution))
runInferenceCommandEffectWithInference runInference effect =
  case effect of
    RunInference target request ->
      fmap InferenceResultPublished <$> runInferenceRequestWithTarget target runInference request
    CompareInferenceCheckpoints _target _command ->
      pure (Left (SETransient "checkpoint compare requires a weighted inference runner"))
    RunAdversarialMove _target _command ->
      pure (Left (SETransient "adversarial move requires a weighted inference runner"))
    ListInferenceCheckpoints target command ->
      fmap InferenceResultPublished <$> runListCheckpointsRequestWithTarget target command
    LoadInferenceTranscript target command ->
      fmap InferenceResultPublished <$> runLoadTranscriptRequestWithTarget target command

runInferenceCommandEffectWithWeightedInference
  :: (HasMinIO m, HasPulsar m)
  => WeightedInferenceRunner m
  -> WorkloadEffect 'InferenceCommandExecution
  -> m (Either ServiceError (WorkloadEffectResult 'InferenceCommandExecution))
runInferenceCommandEffectWithWeightedInference runInference effect =
  case effect of
    RunInference target request ->
      fmap InferenceResultPublished
        <$> runInferenceRequestWithWeightedInferenceTo target runInference request
    CompareInferenceCheckpoints target command ->
      fmap InferenceResultPublished
        <$> runCheckpointCompareRequestWithWeightedInference target runInference command
    RunAdversarialMove target command ->
      fmap InferenceResultPublished
        <$> runAdversarialMoveRequestWithWeightedInference target runInference command
    ListInferenceCheckpoints target command ->
      fmap InferenceResultPublished <$> runListCheckpointsRequestWithTarget target command
    LoadInferenceTranscript target command ->
      fmap InferenceResultPublished <$> runLoadTranscriptRequestWithTarget target command

buildTrainingWorkloadEffects
  :: Residency
  -> Substrate
  -> TrainingCommand
  -> Either WorkloadDecodeError (NonEmpty SomeWorkloadEffect)
buildTrainingWorkloadEffects residency substrate command = do
  validateTrainingCommandSubstrate substrate command
  trainingCommandEffects residency substrate command

trainingCommandEffects
  :: Residency
  -> Substrate
  -> TrainingCommand
  -> Either WorkloadDecodeError (NonEmpty SomeWorkloadEffect)
trainingCommandEffects residency substrate command =
  case command of
    TrainingStart start -> do
      plan <- firstPlanError (PlanCommand.validateStartTraining start)
      placement <- planWorkloadPlacement residency (ResolvedTrainingLaunch start plan)
      pure (placementEffect placement :| [])
    TrainingStop stop
      | residency == Cluster && substrate == AppleSilicon ->
          (:| []) . placementEffect . WorkloadHostCommand
            <$> mkHostCommandSpec TrainingHostCommandRoute AppleSilicon (TrainingStop stop)
      | otherwise ->
          pure (clusterWorkloadStopEffects "jitml-train" (stopExperimentHash stop))

buildTuneWorkloadEffects
  :: Residency
  -> Substrate
  -> TuneCommand
  -> Either WorkloadDecodeError (NonEmpty SomeWorkloadEffect)
buildTuneWorkloadEffects residency substrate command = do
  validateTuneCommandSubstrate substrate command
  tuneCommandEffects residency substrate command

tuneCommandEffects
  :: Residency
  -> Substrate
  -> TuneCommand
  -> Either WorkloadDecodeError (NonEmpty SomeWorkloadEffect)
tuneCommandEffects residency substrate command =
  case command of
    TuneStart start -> do
      plan <- firstPlanError (PlanCommand.validateStartSweep start)
      placement <- planWorkloadPlacement residency (TuneLaunch start plan)
      pure (placementEffect placement :| [])
    TuneStop stop
      | residency == Cluster && substrate == AppleSilicon ->
          (:| []) . placementEffect . WorkloadHostCommand
            <$> mkHostCommandSpec TuneHostCommandRoute AppleSilicon (TuneStop stop)
      | otherwise ->
          pure (clusterWorkloadStopEffects "jitml-tune" (ssStopExperimentHash stop))

buildRlWorkloadEffects
  :: Residency
  -> Substrate
  -> RlCommand
  -> Either WorkloadDecodeError (NonEmpty SomeWorkloadEffect)
buildRlWorkloadEffects residency substrate command = do
  validateRlCommandSubstrate substrate command
  rlCommandEffects residency substrate command

rlCommandEffects
  :: Residency
  -> Substrate
  -> RlCommand
  -> Either WorkloadDecodeError (NonEmpty SomeWorkloadEffect)
rlCommandEffects residency substrate command =
  case command of
    RlStart start -> do
      placement <- planWorkloadPlacement residency (RlLaunch start)
      pure (placementEffect placement :| [])
    RlStartAlphaZero start -> do
      plan <- firstPlanError (PlanCommand.validateStartAlphaZeroRun start)
      placement <- planWorkloadPlacement residency (AlphaZeroLaunch start plan)
      pure (placementEffect placement :| [])
    RlStop stop
      | residency == Cluster && substrate == AppleSilicon ->
          (:| []) . placementEffect . WorkloadHostCommand
            <$> mkHostCommandSpec RlHostCommandRoute AppleSilicon (RlStop stop)
      | otherwise ->
          pure (clusterWorkloadStopEffects "jitml-rl" (srStopExperimentHash stop))

-- | A cluster Start applies one manifest containing both the Job and its
-- derived per-run RunConfig ConfigMap. Stop retains that ownership boundary as
-- two indexed deletion effects, so the interpreter attempts both resources
-- and reports their typed outcomes independently.
clusterWorkloadStopEffects :: Text -> Text -> NonEmpty SomeWorkloadEffect
clusterWorkloadStopEffects workloadPrefix experimentHash =
  let jobName = workloadName workloadPrefix experimentHash
      deleteResource resource =
        SomeWorkloadEffect (DeleteWorkloadResource (KubeResource resource))
   in deleteResource ("job/" <> jobName)
        :| [deleteResource ("configmap/runconfig-" <> jobName)]

validateTrainingCommandSubstrate
  :: Substrate
  -> TrainingCommand
  -> Either WorkloadDecodeError ()
validateTrainingCommandSubstrate consumed command =
  case command of
    TrainingStart start -> requireCommandSubstrate consumed (stSubstrate start)
    TrainingStop _stop -> Right ()

validateTuneCommandSubstrate
  :: Substrate
  -> TuneCommand
  -> Either WorkloadDecodeError ()
validateTuneCommandSubstrate consumed command =
  case command of
    TuneStart start -> requireCommandSubstrate consumed (ssSubstrate start)
    TuneStop _stop -> Right ()

validateRlCommandSubstrate
  :: Substrate
  -> RlCommand
  -> Either WorkloadDecodeError ()
validateRlCommandSubstrate consumed command =
  case command of
    RlStart start -> requireCommandSubstrate consumed (srlSubstrate start)
    RlStartAlphaZero start -> requireCommandSubstrate consumed (sazSubstrate start)
    RlStop _stop -> Right ()

firstPlanError :: Either Text value -> Either WorkloadDecodeError value
firstPlanError = mapLeft WorkloadPlanError

requireCommandSubstrate
  :: Substrate
  -> Substrate
  -> Either WorkloadDecodeError ()
requireCommandSubstrate consumed requested
  | consumed == requested = Right ()
  | otherwise = Left (WorkloadCommandSubstrateMismatch consumed requested)

-- | Daemon inference builder. The command's reply address is refined only
-- against the lane fixed by the consumed input topic. A valid address from a
-- different substrate is therefore an explicit topology error before any
-- effect is run.
buildInferenceWorkloadEffectsForTopic
  :: Topic InferenceCommand
  -> InferenceCommand
  -> Either WorkloadDecodeError (NonEmpty SomeWorkloadEffect)
buildInferenceWorkloadEffectsForTopic inputTopic command = do
  effect <- inferenceCommandEffectForTopic inputTopic command
  pure (SomeWorkloadEffect effect :| [])

inferenceCommandEffectForTopic
  :: Topic InferenceCommand
  -> InferenceCommand
  -> Either WorkloadDecodeError (WorkloadEffect 'InferenceCommandExecution)
inferenceCommandEffectForTopic inputTopic command = do
  resultTopic <-
    case resolveTopic
      InferenceResultRoute
      (topicSubstrate inputTopic)
      (inferenceCommandReplyTopic command) of
      Left err -> Left (WorkloadTopologyError (Text.pack (show err)))
      Right topic -> Right topic
  let target = InferenceResultTarget resultTopic
  pure (inferenceCommandEffect target command)

inferenceCommandEffect
  :: InferenceResultTarget
  -> InferenceCommand
  -> WorkloadEffect 'InferenceCommandExecution
inferenceCommandEffect target command =
  case command of
    Inference.RunInference request -> RunInference target request
    Inference.CompareCheckpoints request -> CompareInferenceCheckpoints target request
    Inference.SelectAdversarialMove request -> RunAdversarialMove target request
    Inference.ListCheckpoints request -> ListInferenceCheckpoints target request
    Inference.LoadTranscript request -> LoadInferenceTranscript target request

inferenceCommandReplyTopic :: InferenceCommand -> Text
inferenceCommandReplyTopic command =
  case command of
    Inference.RunInference request -> irReplyTopic request
    Inference.CompareCheckpoints request -> cccReplyTopic request
    Inference.SelectAdversarialMove request -> amcReplyTopic request
    Inference.ListCheckpoints request -> lccReplyTopic request
    Inference.LoadTranscript request -> ltcReplyTopic request

placementEffect :: WorkloadPlacement -> SomeWorkloadEffect
placementEffect placement =
  case placement of
    WorkloadClusterJob spec ->
      SomeWorkloadEffect (ApplyWorkloadResource (clusterJobResource spec) (clusterJobManifest spec))
    WorkloadHostCommand spec ->
      SomeWorkloadEffect (PublishHostWorkloadCommand spec)

planWorkloadPlacement
  :: Residency
  -> WorkloadLaunch
  -> Either WorkloadDecodeError WorkloadPlacement
planWorkloadPlacement residency launch =
  case launch of
    TrainingLaunch start -> do
      plan <- firstPlanError (PlanCommand.validateStartTraining start)
      planWorkloadPlacement residency (ResolvedTrainingLaunch start plan)
    ResolvedTrainingLaunch start plan
      | residency == Cluster && stSubstrate start == AppleSilicon ->
          WorkloadHostCommand
            <$> mkHostCommandSpec TrainingHostCommandRoute AppleSilicon (TrainingStart start)
      | otherwise ->
          Right
            ( WorkloadClusterJob
                ClusterJobSpec
                  { clusterJobResource =
                      KubeResource ("job/" <> workloadName "jitml-train" (stExperimentHash start))
                  , clusterJobManifest = renderResolvedTrainingJob start plan
                  }
            )
    TuneLaunch start plan
      | residency == Cluster && ssSubstrate start == AppleSilicon ->
          WorkloadHostCommand
            <$> mkHostCommandSpec TuneHostCommandRoute AppleSilicon (TuneStart start)
      | otherwise ->
          Right
            ( WorkloadClusterJob
                ClusterJobSpec
                  { clusterJobResource =
                      KubeResource ("job/" <> workloadName "jitml-tune" (ssExperimentHash start))
                  , clusterJobManifest = renderResolvedTuneJob start plan
                  }
            )
    RlLaunch start
      | residency == Cluster && srlSubstrate start == AppleSilicon ->
          WorkloadHostCommand
            <$> mkHostCommandSpec RlHostCommandRoute AppleSilicon (RlStart start)
      | otherwise ->
          Right
            ( WorkloadClusterJob
                ClusterJobSpec
                  { clusterJobResource =
                      KubeResource ("job/" <> workloadName "jitml-rl" (srlExperimentHash start))
                  , clusterJobManifest = renderRlJob start
                  }
            )
    AlphaZeroLaunch start plan
      | residency == Cluster && sazSubstrate start == AppleSilicon ->
          WorkloadHostCommand
            <$> mkHostCommandSpec RlHostCommandRoute AppleSilicon (RlStartAlphaZero start)
      | otherwise ->
          Right
            ( WorkloadClusterJob
                ClusterJobSpec
                  { clusterJobResource =
                      KubeResource ("job/" <> workloadName "jitml-alphazero" (sazExperimentHash start))
                  , clusterJobManifest = renderResolvedAlphaZeroJob start plan
                  }
            )

mkHostCommandSpec
  :: ProtocolRoute event
  -> Substrate
  -> event
  -> Either WorkloadDecodeError HostCommandSpec
mkHostCommandSpec route substrate event =
  (`HostCommandSpec` event) <$> topicOrWorkloadError route substrate

topicOrWorkloadError
  :: ProtocolRoute event
  -> Substrate
  -> Either WorkloadDecodeError (Topic event)
topicOrWorkloadError route substrate =
  case topicFor route substrate of
    Left err -> Left (WorkloadTopologyError (Text.pack (show err)))
    Right topic -> Right topic

publishHostCommand
  :: (HasPulsar m)
  => HostCommandSpec
  -> m (Either ServiceError Text)
publishHostCommand (HostCommandSpec topic event) = pulsarPublish topic event

publishInferenceResultTo
  :: (HasPulsar m)
  => InferenceResultTarget
  -> Text
  -> Text
  -> m (Either ServiceError Text)
publishInferenceResultTo target rawTopic payload =
  case resolveTopic
    InferenceResultRoute
    (inferenceResultTargetSubstrate target)
    rawTopic of
    Left err ->
      pure
        ( Left
            ( SETransient
                ("inference reply topic does not match its typed target: " <> Text.pack (show err))
            )
        )
    Right resolved
      | resolved /= inferenceResultTargetTopic target ->
          pure (Left (SETransient "inference reply topic changed after typed refinement"))
      | otherwise ->
          case mkInferenceResultMessage payload of
            Left err ->
              pure (Left (SETransient ("invalid inference result payload: " <> err)))
            Right message -> pulsarPublish (inferenceResultTargetTopic target) message

runInferenceRequestWithTarget
  :: (HasMinIO m, HasPulsar m)
  => InferenceResultTarget
  -> InferenceRunner m
  -> InferenceRequest
  -> m (Either ServiceError Text)
runInferenceRequestWithTarget target runInference request = do
  result <-
    CheckpointStore.loadInferenceCheckpointWith
      runInference
      (irExperimentHash request)
      (irInput request)
  case result of
    Left err ->
      pure (Left (SETransient ("inference: " <> err)))
    Right output ->
      publishInferenceResultTo
        target
        (irReplyTopic request)
        ( renderInferenceResult
            InferenceResult
              { iresCallId = irCallId request
              , iresExperimentHash = irExperimentHash request
              , iresOutput = output
              }
        )

defaultCheckpointInference
  :: (Applicative m)
  => ProductPipeline.InferenceEligibleRef
  -> CheckpointManifest
  -> [Double]
  -> m (Either Text [Double])
defaultCheckpointInference _modelRef _manifest _input =
  pure (Left "weighted inference runner required")

-- | Weighted-callback variants of the dispatcher chain. Sprint 13.11: the
-- substrate-bound inference runners (`runLinuxCpuWeightedCheckpointInference`,
-- `runCudaWeightedCheckpointInference`) consume `LoadedWeightTensor`s decoded
-- from `.jmw1` blobs, so the daemon path needs to read them through
-- `loadInferenceCheckpointWithWeights` instead of the unweighted summary path.
-- These functions mirror the unweighted variants but plumb the weighted
-- callback through the typed, target-bound inference effect runner.
runWorkloadEffectWithWeightedInference
  :: (HasHarbor m, HasKubectl m, HasMinIO m, HasPulsar m)
  => WeightedInferenceRunner m
  -> WorkloadEffect kind
  -> m (Either ServiceError (WorkloadEffectResult kind))
runWorkloadEffectWithWeightedInference runInference effect =
  case effect of
    WriteCheckpointBlob ref payload ->
      fmap CheckpointBlobWritten <$> putBlobBytesIfAbsent ref payload
    UpdateCheckpointPointer ref expected payload ->
      fmap CheckpointPointerUpdated <$> casPointer ref expected payload
    PromoteWorkloadImage source target ->
      fmap WorkloadImagePromoted <$> harborPromoteImage source target
    RunInference target request ->
      fmap InferenceResultPublished
        <$> runInferenceRequestWithWeightedInferenceTo target runInference request
    CompareInferenceCheckpoints target command ->
      fmap InferenceResultPublished
        <$> runCheckpointCompareRequestWithWeightedInference target runInference command
    RunAdversarialMove target command ->
      fmap InferenceResultPublished
        <$> runAdversarialMoveRequestWithWeightedInference target runInference command
    ListInferenceCheckpoints target command ->
      fmap InferenceResultPublished <$> runListCheckpointsRequestWithTarget target command
    LoadInferenceTranscript target command ->
      fmap InferenceResultPublished <$> runLoadTranscriptRequestWithTarget target command
    PublishHostWorkloadCommand spec ->
      fmap (const (HostWorkloadCommandPublished (hostCommandSpecTopicName spec)))
        <$> publishHostCommand spec
    ApplyWorkloadResource resource manifest ->
      fmap (const WorkloadResourceApplied) <$> kubectlApply resource manifest
    ReadWorkloadResourceStatus resource ->
      fmap WorkloadResourceStatus <$> kubectlStatus resource
    DeleteWorkloadResource resource ->
      fmap (const WorkloadResourceDeleted) <$> kubectlDelete resource

runWorkloadEffectsWithWeightedInference
  :: (HasHarbor m, HasKubectl m, HasMinIO m, HasPulsar m)
  => WeightedInferenceRunner m
  -> NonEmpty SomeWorkloadEffect
  -> m (NonEmpty SomeWorkloadOutcome)
runWorkloadEffectsWithWeightedInference runInference =
  traverse (runSomeWorkloadEffectWithWeightedInference runInference)

runSomeWorkloadEffectWithWeightedInference
  :: (HasHarbor m, HasKubectl m, HasMinIO m, HasPulsar m)
  => WeightedInferenceRunner m
  -> SomeWorkloadEffect
  -> m SomeWorkloadOutcome
runSomeWorkloadEffectWithWeightedInference runInference (SomeWorkloadEffect effect) =
  SomeWorkloadOutcome effect <$> runWorkloadEffectWithWeightedInference runInference effect

runInferenceRequestWithWeightedInferenceTo
  :: (HasMinIO m, HasPulsar m)
  => InferenceResultTarget
  -> WeightedInferenceRunner m
  -> InferenceRequest
  -> m (Either ServiceError Text)
runInferenceRequestWithWeightedInferenceTo target runInference request = do
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
      publishInferenceResultTo
        target
        (irReplyTopic request)
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
  => InferenceResultTarget
  -> WeightedInferenceRunner m
  -> CheckpointCompareCommand
  -> m (Either ServiceError Text)
runCheckpointCompareRequestWithWeightedInference target runInference command = do
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
       in publishInferenceResultTo
            target
            (cccReplyTopic command)
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
  => InferenceResultTarget
  -> WeightedInferenceRunner m
  -> AdversarialMoveCommand
  -> m (Either ServiceError Text)
runAdversarialMoveRequestWithWeightedInference target runInference command = do
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
      publishInferenceResultTo
        target
        (amcReplyTopic command)
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

-- | Historical name retained for call sites that only need the experiment
-- hashes. Phase 27.1 maps checkpoint browse to the product-row artifact
-- namespace rather than to seeded demo hashes.
seededDemoExperimentHashes :: [Text]
seededDemoExperimentHashes =
  fmap (ProductMatrix.productRowExperimentHash . snd) productRowCheckpointTargets

productRowCheckpointTargets :: [(Text, ProductMatrix.ProductRow 'ProductMatrix.Declared)]
productRowCheckpointTargets =
  [(ProductMatrix.productRowExperimentHash row, row) | row <- ProductMatrix.allProductRows]

-- | Checkpoint browse as an Engine job: for each product-row artifact
-- namespace, list manifests from the `jitml-checkpoints` MinIO bucket and
-- publish a single `CheckpointList` frame summarising eligible manifests plus
-- per-row selector state on the typed result target retained by the effect.
runListCheckpointsRequestWithTarget
  :: (HasMinIO m, HasPulsar m)
  => InferenceResultTarget
  -> ListCheckpointsCommand
  -> m (Either ServiceError Text)
runListCheckpointsRequestWithTarget target command = do
  let substrate = Just (inferenceResultTargetSubstrate target)
  listings <-
    traverse
      ( \(experimentHash, row) -> do
          manifests <- CheckpointStore.listCheckpointManifestsMinIO experimentHash
          pure (rowCheckpointResult substrate experimentHash row manifests)
      )
      productRowCheckpointTargets
  let summaries = concatMap productCheckpointSummaries listings
      selectors = fmap productRowSelectorLine listings
  publishInferenceResultTo
    target
    (lccReplyTopic command)
    (renderCheckpointListResultWithSelectors (lccCallId command) selectors summaries)

data ProductRowCheckpointResult = ProductRowCheckpointResult
  { prcrRowId :: !Text
  , prcrExperimentHash :: !Text
  , prcrRowFamily :: !Text
  , prcrDemoPanel :: !Text
  , prcrSelectorState :: !Text
  , prcrEligibleSummaries :: ![Text]
  }
  deriving stock (Eq, Show)

rowCheckpointResult
  :: Maybe Substrate
  -> Text
  -> ProductMatrix.ProductRow state
  -> Either ServiceError [CheckpointManifest]
  -> ProductRowCheckpointResult
rowCheckpointResult substrate experimentHash row manifestsResult =
  case productRowUnsupportedReason substrate row of
    Just _ ->
      baseResult "unsupported" []
    Nothing ->
      case manifestsResult of
        Left _ ->
          baseResult "error" []
        Right manifests ->
          let summaries = checkpointSummariesForRow (ProductMatrix.rowId row) experimentHash manifests
           in baseResult (productRowSelectorState summaries) summaries
 where
  baseResult selectorState summaries =
    ProductRowCheckpointResult
      { prcrRowId = ProductMatrix.rowId row
      , prcrExperimentHash = experimentHash
      , prcrRowFamily = ProductMatrix.renderRowFamily (ProductMatrix.family row)
      , prcrDemoPanel = ProductMatrix.demoPanel row
      , prcrSelectorState = selectorState
      , prcrEligibleSummaries = summaries
      }

productCheckpointSummaries :: ProductRowCheckpointResult -> [Text]
productCheckpointSummaries =
  prcrEligibleSummaries

productRowSelectorLine :: ProductRowCheckpointResult -> Text
productRowSelectorLine result =
  Text.intercalate
    "\t"
    [ prcrRowId result
    , prcrExperimentHash result
    , prcrRowFamily result
    , prcrSelectorState result
    , Text.pack (show (length (prcrEligibleSummaries result)))
    , prcrDemoPanel result
    ]

productRowSelectorState :: [Text] -> Text
productRowSelectorState [] = "training-required"
productRowSelectorState _ = "eligible"

productRowUnsupportedReason :: Maybe Substrate -> ProductMatrix.ProductRow state -> Maybe Text
productRowUnsupportedReason _ row =
  case ProductMatrix.rowClass row of
    ProductMatrix.RlAlgorithmEnvironment algorithm environment ->
      rlTrainerEnvironmentCompatibilityError (rlTrainerForAlgorithm algorithm) environment
    ProductMatrix.RlGoalConditioned environment ->
      rlTrainerEnvironmentCompatibilityError "her" environment
    _ -> Nothing

rlTrainerEnvironmentCompatibilityError :: Text -> Text -> Maybe Text
rlTrainerEnvironmentCompatibilityError rawTrainer rawEnvironment =
  case supportedEnvironments of
    Nothing -> Nothing
    Just envs
      | environment `elem` envs -> Nothing
      | otherwise ->
          Just
            ( "RL trainer "
                <> trainer
                <> " does not support environment "
                <> environment
                <> "; supported environments: "
                <> Text.intercalate ", " envs
            )
 where
  trainer = Text.toLower (Text.strip rawTrainer)
  environment = Text.toLower (Text.strip rawEnvironment)
  supportedEnvironments =
    case trainer of
      "ppo" -> Just discreteProductEnvironments
      "a2c" -> Just ["cartpole", "mountain-car", "lunar-lander", "key-door-grid"]
      "trpo" -> Just ["cartpole", "mountain-car", "lunar-lander", "key-door-grid"]
      "maskableppo" -> Just ["cartpole", "mountain-car", "lunar-lander", "key-door-grid"]
      "recurrentppo" -> Just ["cartpole", "mountain-car", "lunar-lander", "key-door-grid"]
      "dqn" -> Just ["cartpole", "mountain-car", "key-door-grid"]
      "qrdqn" -> Just ["cartpole", "mountain-car", "key-door-grid"]
      "ddpg" -> Just continuousProductEnvironments
      "td3" -> Just continuousProductEnvironments
      "sac" -> Just continuousProductEnvironments
      "crossq" -> Just continuousProductEnvironments
      "tqc" -> Just continuousProductEnvironments
      "ars" -> Just ["cartpole", "mountain-car", "lunar-lander", "key-door-grid"]
      "her" -> Just ["goal-reaching"]
      _ -> Nothing
  discreteProductEnvironments =
    ["cartpole", "mountain-car", "acrobot", "lunar-lander", "key-door-grid", "gridworld-deterministic"]
  continuousProductEnvironments =
    ["pendulum", "lunar-lander"]

-- | Render the per-experiment manifests into `checkpoint-summary:` lines, one
-- per inference-eligible manifest. Each summary is a tab-separated tuple of
-- row-id / experiment-hash / sha / step / model-family / tensor-count /
-- eligibility / completed budget / convergence metrics / TensorBoard prefix.
checkpointSummaries :: Text -> [CheckpointManifest] -> [Text]
checkpointSummaries experimentHash =
  checkpointSummariesForRow experimentHash experimentHash

checkpointSummariesForRow :: Text -> Text -> [CheckpointManifest] -> [Text]
checkpointSummariesForRow rowId experimentHash =
  mapMaybe (checkpointSummaryLine rowId experimentHash)

checkpointSummaryLine :: Text -> Text -> CheckpointManifest -> Maybe Text
checkpointSummaryLine rowId experimentHash manifest =
  let manifestSha = manifestContentSha manifest
   in case requireInferenceEligibleCheckpoint manifestSha manifest of
        Left _ -> Nothing
        Right eligible ->
          let completed = eligibleCheckpointCompletedTraining eligible
           in Just $
                Text.intercalate
                  "\t"
                  [ rowId
                  , experimentHash
                  , manifestSha
                  , Text.pack (show (manifestStep manifest))
                  , renderModelFamily (manifestModelFamily manifest)
                  , Text.pack (show (length (manifestTensors manifest)))
                  , "eligible"
                  , renderTrainingBudget (completedTrainingBudget completed)
                  , renderConvergenceMetrics (completedTrainingMetrics completed)
                  , tbrLogPrefix (completedTrainingTensorBoard completed)
                  ]

renderConvergenceMetrics :: [ConvergenceObservation] -> Text
renderConvergenceMetrics metrics =
  Text.intercalate
    ","
    [ coMetricName metric <> "=" <> Text.pack (show (coMetricValue metric))
    | metric <- metrics
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
renderCheckpointListResult callId =
  renderCheckpointListResultWithSelectors callId []

renderCheckpointListResultWithSelectors :: Text -> [Text] -> [Text] -> Text
renderCheckpointListResultWithSelectors callId selectors summaries =
  Text.unlines $
    [ "kind: CheckpointList"
    , "call-id: " <> callId
    , "panel: checkpoint-browse"
    , "status: published"
    , "count: " <> Text.pack (show (length summaries))
    , "selector-state: " <> checkpointSelectorState summaries
    ]
      <> fmap ("row-selector: " <>) selectors
      <> fmap ("checkpoint-summary: " <>) summaries

checkpointSelectorState :: [Text] -> Text
checkpointSelectorState [] = "fail-closed:no-inference-eligible-artifact"
checkpointSelectorState _ = "ready"

-- | Sprint 14.1 (Feature B) — transcript replay as an Engine job: read the
-- persisted transcript record from the `jitml-transcripts` MinIO bucket keyed
-- by the command's transcript id and publish a `TranscriptReplay` frame on the
-- typed result target retained by the effect.
runLoadTranscriptRequestWithTarget
  :: (HasMinIO m, HasPulsar m)
  => InferenceResultTarget
  -> LoadTranscriptCommand
  -> m (Either ServiceError Text)
runLoadTranscriptRequestWithTarget target command = do
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
  publishInferenceResultTo
    target
    (ltcReplyTopic command)
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

-- | Render only the canonical plan identity/transport and operational broker
-- endpoint.  Primitive command values never cross the worker mount boundary.
trainingRunConfigFor :: SupervisedPlan -> TrainingRunConfig
trainingRunConfigFor plan =
  TrainingRunConfig
    { trcPlanId = planIdText (supervisedPlanId plan)
    , trcResolvedPlan = renderSupervisedPlanTransport plan
    , trcPulsarWsUrl = inClusterPulsarWsUrl
    }

tuneRunConfigFor :: TuningPlan -> TuneRunConfig
tuneRunConfigFor plan =
  TuneRunConfig
    { turcPlanId = planIdText (tuningPlanId plan)
    , turcResolvedPlan = renderTuningPlanTransport plan
    , turcPulsarWsUrl = inClusterPulsarWsUrl
    }

alphaZeroRunConfigFor :: AlphaZeroPlan -> AlphaZeroRunConfig
alphaZeroRunConfigFor plan =
  AlphaZeroRunConfig
    { azrcPlanId = planIdText (alphaZeroPlanId plan)
    , azrcResolvedPlan = renderAlphaZeroPlanTransport plan
    , azrcPulsarWsUrl = inClusterPulsarWsUrl
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

renderTrainingJob :: StartTraining -> Either WorkloadDecodeError Text
renderTrainingJob start = do
  plan <- firstPlanError (PlanCommand.validateStartTraining start)
  pure (renderResolvedTrainingJob start plan)

renderResolvedTrainingJob :: StartTraining -> SupervisedPlan -> Text
renderResolvedTrainingJob start plan =
  renderJobWithRunConfig
    (stSubstrate start)
    "training"
    (workloadName "jitml-train" (stExperimentHash start))
    ["train", stDhallObjectKey start]
    (renderTrainingRunConfigDhall (trainingRunConfigFor plan))

renderTuneJob :: StartSweep -> Either WorkloadDecodeError Text
renderTuneJob start = do
  plan <- firstPlanError (PlanCommand.validateStartSweep start)
  pure (renderResolvedTuneJob start plan)

renderResolvedTuneJob :: StartSweep -> TuningPlan -> Text
renderResolvedTuneJob start plan =
  renderJobWithRunConfig
    (ssSubstrate start)
    "tune"
    (workloadName "jitml-tune" (ssExperimentHash start))
    ["tune", ssDhallObjectKey start]
    (renderTuneRunConfigDhall (tuneRunConfigFor plan))

renderRlJob :: StartRLRun -> Text
renderRlJob start =
  renderJobWithRunConfig
    (srlSubstrate start)
    "rl"
    (workloadName "jitml-rl" (srlExperimentHash start))
    ["rl", "train", srlExperimentHash start]
    (renderRlRunConfigDhall (rlRunConfigFor start))

renderAlphaZeroJob :: StartAlphaZeroRun -> Either WorkloadDecodeError Text
renderAlphaZeroJob start = do
  plan <- firstPlanError (PlanCommand.validateStartAlphaZeroRun start)
  pure (renderResolvedAlphaZeroJob start plan)

renderResolvedAlphaZeroJob :: StartAlphaZeroRun -> AlphaZeroPlan -> Text
renderResolvedAlphaZeroJob start plan =
  renderJobWithRunConfig
    (sazSubstrate start)
    "rl"
    (workloadName "jitml-alphazero" (sazExperimentHash start))
    ["rl", "alphazero", "self-play"]
    (renderAlphaZeroRunConfigDhall (alphaZeroRunConfigFor plan))

-- | The in-cluster Pulsar WebSocket endpoint a daemon-dispatched worker
-- Job uses to publish completion events back to the broker. A Job pod
-- cannot reach the host edge (@127.0.0.1:\<edge-port\>@); it reaches the
-- broker through the in-cluster service DNS instead. Matches the daemon's
-- own cluster WebSocket endpoint in 'JitML.Service.Clients'.
inClusterPulsarWsUrl :: Text
inClusterPulsarWsUrl = "ws://pulsar-broker.platform.svc.cluster.local:8080/ws"

-- | Map an RL algorithm name to the worker-side trainer selector the
-- worker's @jitml rl train@ command reads from @JITML_RL_TRAINER@. Each
-- catalog algorithm selects its real trainer; an unrecognised name is
-- preserved as an unknown selector so worker dispatch fails closed.
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
    _ ->
      let stripped = Text.toLower (Text.strip algorithm)
       in if Text.null stripped then "unknown" else stripped

renderRuntimeClassLines :: Substrate -> [Text]
renderRuntimeClassLines substrate =
  case substrateRuntimeClass substrate of
    Nothing -> []
    Just runtimeClass ->
      ["      runtimeClassName: " <> runtimeClass]

substrateHasClusterCompute :: Substrate -> Bool
substrateHasClusterCompute AppleSilicon = False
substrateHasClusterCompute LinuxCPU = True
substrateHasClusterCompute LinuxCUDA = True

yamlLabelBool :: Bool -> Text
yamlLabelBool True = "\"true\""
yamlLabelBool False = "\"false\""

clusterComputePlacementLines :: Substrate -> [Text]
clusterComputePlacementLines substrate
  | not (substrateHasClusterCompute substrate) = []
  | otherwise =
      [ "      nodeSelector:"
      , "        jitml.node-role/compute: \"true\""
      , "      affinity:"
      , "        podAntiAffinity:"
      , "          requiredDuringSchedulingIgnoredDuringExecution:"
      , "            - topologyKey: kubernetes.io/hostname"
      , "              labelSelector:"
      , "                matchLabels:"
      , "                  jitml.compute: \"true\""
      , "                  jitml.compute-scope: workload"
      , "      topologySpreadConstraints:"
      , "        - maxSkew: 1"
      , "          topologyKey: kubernetes.io/hostname"
      , "          whenUnsatisfiable: DoNotSchedule"
      , "          labelSelector:"
      , "            matchLabels:"
      , "              jitml.compute: \"true\""
      , "              jitml.compute-scope: workload"
      ]

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
    , "    metadata:"
    , "      labels:"
    , "        app.kubernetes.io/name: jitml"
    , "        app.kubernetes.io/component: " <> component
    , "        jitml.substrate: " <> renderSubstrate substrate
    , "        jitml.role: engine"
    , "        jitml.compute: " <> yamlLabelBool (substrateHasClusterCompute substrate)
    , "        jitml.compute-scope: workload"
    , "    spec:"
    , "      restartPolicy: Never"
    ]
      <> renderRuntimeClassLines substrate
      <> clusterComputePlacementLines substrate
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

renderWorkloadEffectPayload :: WorkloadEffect kind -> Text
renderWorkloadEffectPayload effect =
  Text.unlines $
    [ "kind: WorkloadEffect"
    , "effect: " <> workloadEffectTag effect
    ]
      <> workloadEffectFields effect

renderWorkloadEffectPayloadForSome :: SomeWorkloadEffect -> Text
renderWorkloadEffectPayloadForSome (SomeWorkloadEffect effect) =
  renderWorkloadEffectPayload effect

parseWorkloadEffectPayload
  :: Text
  -> Either WorkloadDecodeError SomeWorkloadEffect
parseWorkloadEffectPayload payload = do
  fields <- parseWorkloadFields payload
  requireExactValue "kind" "WorkloadEffect" fields
  effectTag <- requireWorkloadField "effect" fields
  case effectTag of
    "WriteCheckpointBlob" -> do
      requireOnlyWorkloadFields
        ["kind", "effect", "bucket", "key", "payload-hex"]
        fields
      ref <- objectRefFromFields fields
      encoded <- requireWorkloadField "payload-hex" fields
      bytes <-
        maybe
          (Left (InvalidWorkloadEffectPayload "payload-hex is not valid hexadecimal"))
          Right
          (hexDecodeText encoded)
      pure (SomeWorkloadEffect (WriteCheckpointBlob ref bytes))
    "UpdateCheckpointPointer" -> do
      requireOnlyWorkloadFields
        ["kind", "effect", "bucket", "key", "expected-etag", "payload-text-hex"]
        fields
      ref <- objectRefFromFields fields
      pointerPayload <- requireHexTextField "payload-text-hex" fields
      let expected = ETag <$> lookup "expected-etag" fields
      pure (SomeWorkloadEffect (UpdateCheckpointPointer ref expected pointerPayload))
    "PromoteWorkloadImage" -> do
      requireOnlyWorkloadFields
        ["kind", "effect", "source-image", "target-image"]
        fields
      source <- ImageRef <$> requireWorkloadField "source-image" fields
      target <- ImageRef <$> requireWorkloadField "target-image" fields
      pure (SomeWorkloadEffect (PromoteWorkloadImage source target))
    "RunInference" -> inferenceEffectRequiresTypedInputTopic
    "CompareInferenceCheckpoints" -> inferenceEffectRequiresTypedInputTopic
    "RunAdversarialMove" -> inferenceEffectRequiresTypedInputTopic
    "ListInferenceCheckpoints" -> inferenceEffectRequiresTypedInputTopic
    "LoadInferenceTranscript" -> inferenceEffectRequiresTypedInputTopic
    "PublishHostWorkloadCommand" -> do
      requireOnlyWorkloadFields
        ["kind", "effect", "topic", "payload-text-hex"]
        fields
      rawTopic <- requireWorkloadField "topic" fields
      hostPayload <- requireHexTextField "payload-text-hex" fields
      spec <- decodeHostCommandSpec rawTopic hostPayload
      pure (SomeWorkloadEffect (PublishHostWorkloadCommand spec))
    "ApplyWorkloadResource" -> do
      requireOnlyWorkloadFields
        ["kind", "effect", "resource", "manifest-text-hex"]
        fields
      resource <- KubeResource <$> requireWorkloadField "resource" fields
      manifest <- requireHexTextField "manifest-text-hex" fields
      pure (SomeWorkloadEffect (ApplyWorkloadResource resource manifest))
    "ReadWorkloadResourceStatus" -> do
      requireOnlyWorkloadFields ["kind", "effect", "resource"] fields
      resource <- KubeResource <$> requireWorkloadField "resource" fields
      pure (SomeWorkloadEffect (ReadWorkloadResourceStatus resource))
    "DeleteWorkloadResource" -> do
      requireOnlyWorkloadFields ["kind", "effect", "resource"] fields
      resource <- KubeResource <$> requireWorkloadField "resource" fields
      pure (SomeWorkloadEffect (DeleteWorkloadResource resource))
    unknown -> Left (InvalidWorkloadEffectPayload ("unknown effect tag: " <> unknown))

inferenceEffectRequiresTypedInputTopic
  :: Either WorkloadDecodeError SomeWorkloadEffect
inferenceEffectRequiresTypedInputTopic =
  Left
    ( InvalidWorkloadEffectPayload
        "inference effects require a typed input topic"
    )

parseWorkloadFields
  :: Text
  -> Either WorkloadDecodeError [(Text, Text)]
parseWorkloadFields payload = do
  fields <-
    maybe
      (Left (InvalidWorkloadEffectPayload "every line must be a key/value field"))
      Right
      (traverse parseField (Text.lines payload))
  case duplicateFieldName fields of
    Nothing -> Right fields
    Just duplicate ->
      Left (InvalidWorkloadEffectPayload ("duplicate field: " <> duplicate))

duplicateFieldName :: [(Text, Text)] -> Maybe Text
duplicateFieldName fields =
  case [ key
       | (key, _) <- fields
       , length (filter ((== key) . fst) fields) > 1
       ] of
    [] -> Nothing
    duplicate : _ -> Just duplicate

requireWorkloadField
  :: Text
  -> [(Text, Text)]
  -> Either WorkloadDecodeError Text
requireWorkloadField key fields =
  case lookup key fields of
    Nothing -> Left (InvalidWorkloadEffectPayload ("missing field: " <> key))
    Just value -> Right value

requireExactValue
  :: Text
  -> Text
  -> [(Text, Text)]
  -> Either WorkloadDecodeError ()
requireExactValue key expected fields = do
  actual <- requireWorkloadField key fields
  if actual == expected
    then Right ()
    else
      Left
        ( InvalidWorkloadEffectPayload
            ("expected " <> key <> "=" <> expected <> ", got " <> actual)
        )

requireOnlyWorkloadFields
  :: [Text]
  -> [(Text, Text)]
  -> Either WorkloadDecodeError ()
requireOnlyWorkloadFields allowed fields =
  case filter (`notElem` allowed) (fmap fst fields) of
    [] -> Right ()
    unknown : _ ->
      Left (InvalidWorkloadEffectPayload ("unknown field: " <> unknown))

requireHexTextField
  :: Text
  -> [(Text, Text)]
  -> Either WorkloadDecodeError Text
requireHexTextField key fields = do
  encoded <- requireWorkloadField key fields
  bytes <-
    maybe
      (Left (InvalidWorkloadEffectPayload (key <> " is not valid hexadecimal")))
      Right
      (hexDecodeText encoded)
  case Text.Encoding.decodeUtf8' bytes of
    Left _ -> Left (InvalidWorkloadEffectPayload (key <> " is not valid UTF-8"))
    Right value -> Right value

decodeHostCommandSpec
  :: Text
  -> Text
  -> Either WorkloadDecodeError HostCommandSpec
decodeHostCommandSpec rawTopic payload =
  case parseSubstrate (Text.takeWhileEnd (/= '.') (Text.strip rawTopic)) of
    Nothing -> invalidTopic
    Just substrate ->
      case candidates substrate of
        [] -> invalidTopic
        candidate : _ -> candidate
 where
  invalidTopic =
    Left
      ( InvalidWorkloadEffectPayload
          ("host command topic is outside the registered topology: " <> rawTopic)
      )
  candidates substrate =
    catMaybes
      [ decodeHostRoute TrainingHostCommandRoute rawTopic payload substrate
      , decodeHostRoute TuneHostCommandRoute rawTopic payload substrate
      , decodeHostRoute RlHostCommandRoute rawTopic payload substrate
      , decodeHostRoute InferenceHostCommandRoute rawTopic payload substrate
      ]

decodeHostRoute
  :: ProtocolRoute event
  -> Text
  -> Text
  -> Substrate
  -> Maybe (Either WorkloadDecodeError HostCommandSpec)
decodeHostRoute route rawTopic payload substrate =
  case resolveTopic route substrate rawTopic of
    Left _ -> Nothing
    Right topic ->
      Just $
        case decodeTopicPayload topic payload of
          Left err ->
            Left
              ( InvalidWorkloadEffectPayload
                  ("host command payload failed its topic codec: " <> Text.pack (show err))
              )
          Right event -> Right (HostCommandSpec topic event)

renderSomeWorkloadEffect :: SomeWorkloadEffect -> Text
renderSomeWorkloadEffect (SomeWorkloadEffect effect) = renderWorkloadEffect effect

renderSomeWorkloadOutcome :: SomeWorkloadOutcome -> Text
renderSomeWorkloadOutcome (SomeWorkloadOutcome effect result) =
  renderWorkloadEffect effect
    <> " => "
    <> either (Text.pack . show) renderWorkloadEffectResult result

renderWorkloadEffect :: WorkloadEffect kind -> Text
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
    RunInference _ request ->
      "inference:run " <> irCallId request <> " -> " <> irReplyTopic request
    CompareInferenceCheckpoints _ command ->
      "inference:compare " <> cccCallId command <> " -> " <> cccReplyTopic command
    RunAdversarialMove _ command ->
      "inference:adversarial " <> amcCallId command <> " -> " <> amcReplyTopic command
    ListInferenceCheckpoints _ command ->
      "inference:list-checkpoints " <> lccCallId command <> " -> " <> lccReplyTopic command
    LoadInferenceTranscript _ command ->
      "inference:load-transcript " <> ltcCallId command <> " -> " <> ltcReplyTopic command
    PublishHostWorkloadCommand spec ->
      "pulsar:publish-host-workload " <> hostCommandSpecTopicName spec
    ApplyWorkloadResource resource _ ->
      "kubectl:apply " <> unKubeResource resource
    ReadWorkloadResourceStatus resource ->
      "kubectl:status " <> unKubeResource resource
    DeleteWorkloadResource resource ->
      "kubectl:delete " <> unKubeResource resource

renderWorkloadEffectResult :: WorkloadEffectResult kind -> Text
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
    HostWorkloadCommandPublished topic ->
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

workloadEffectTag :: WorkloadEffect kind -> Text
workloadEffectTag effect =
  case effect of
    WriteCheckpointBlob _ _ -> "WriteCheckpointBlob"
    UpdateCheckpointPointer {} -> "UpdateCheckpointPointer"
    PromoteWorkloadImage _ _ -> "PromoteWorkloadImage"
    RunInference _ _ -> "RunInference"
    CompareInferenceCheckpoints _ _ -> "CompareInferenceCheckpoints"
    RunAdversarialMove _ _ -> "RunAdversarialMove"
    ListInferenceCheckpoints _ _ -> "ListInferenceCheckpoints"
    LoadInferenceTranscript _ _ -> "LoadInferenceTranscript"
    PublishHostWorkloadCommand _ -> "PublishHostWorkloadCommand"
    ApplyWorkloadResource _ _ -> "ApplyWorkloadResource"
    ReadWorkloadResourceStatus _ -> "ReadWorkloadResourceStatus"
    DeleteWorkloadResource _ -> "DeleteWorkloadResource"

workloadEffectFields :: WorkloadEffect kind -> [Text]
workloadEffectFields effect =
  case effect of
    WriteCheckpointBlob ref payload ->
      objectRefFields ref
        <> ["payload-hex: " <> hexEncodeText payload]
    UpdateCheckpointPointer ref expected payload ->
      objectRefFields ref
        <> maybe [] (\etag -> ["expected-etag: " <> unETag etag]) expected
        <> ["payload-text-hex: " <> hexEncodeText (Text.Encoding.encodeUtf8 payload)]
    PromoteWorkloadImage source target ->
      [ "source-image: " <> unImageRef source
      , "target-image: " <> unImageRef target
      ]
    RunInference target request ->
      [ "result-topic: " <> inferenceResultTargetTopicName target
      , "command-text-hex: " <> hexEncodeText (Text.Encoding.encodeUtf8 (renderInferenceRequest request))
      ]
    CompareInferenceCheckpoints target command ->
      [ "result-topic: " <> inferenceResultTargetTopicName target
      , "command-text-hex: "
          <> hexEncodeText (Text.Encoding.encodeUtf8 (Inference.renderCheckpointCompareCommand command))
      ]
    RunAdversarialMove target command ->
      [ "result-topic: " <> inferenceResultTargetTopicName target
      , "command-text-hex: "
          <> hexEncodeText (Text.Encoding.encodeUtf8 (Inference.renderAdversarialMoveCommand command))
      ]
    ListInferenceCheckpoints target command ->
      [ "result-topic: " <> inferenceResultTargetTopicName target
      , "command-text-hex: "
          <> hexEncodeText (Text.Encoding.encodeUtf8 (Inference.renderListCheckpointsCommand command))
      ]
    LoadInferenceTranscript target command ->
      [ "result-topic: " <> inferenceResultTargetTopicName target
      , "command-text-hex: "
          <> hexEncodeText (Text.Encoding.encodeUtf8 (Inference.renderLoadTranscriptCommand command))
      ]
    PublishHostWorkloadCommand spec ->
      [ "topic: " <> hostCommandSpecTopicName spec
      , "payload-text-hex: " <> hexEncodeText (Text.Encoding.encodeUtf8 (hostCommandSpecPayload spec))
      ]
    ApplyWorkloadResource resource manifest ->
      [ "resource: " <> unKubeResource resource
      , "manifest-text-hex: " <> hexEncodeText (Text.Encoding.encodeUtf8 manifest)
      ]
    ReadWorkloadResourceStatus resource ->
      ["resource: " <> unKubeResource resource]
    DeleteWorkloadResource resource ->
      ["resource: " <> unKubeResource resource]

objectRefFields :: ObjectRef -> [Text]
objectRefFields ref =
  let BucketName bucket = objectBucket ref
      ObjectKey key = objectKey ref
   in [ "bucket: " <> bucket
      , "key: " <> key
      ]

objectRefFromFields
  :: [(Text, Text)]
  -> Either WorkloadDecodeError ObjectRef
objectRefFromFields fields =
  ObjectRef
    . BucketName
    <$> requireWorkloadField "bucket" fields
    <*> (ObjectKey <$> requireWorkloadField "key" fields)

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
