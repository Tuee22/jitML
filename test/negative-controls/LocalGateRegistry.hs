{-# LANGUAGE OverloadedStrings #-}

-- | Proposed local-family commitment guard, not a behavioral truth detector.
-- Producer constructors choose the actual imported TestTree; a free-form name
-- cannot silently relabel that route. The expected inventory lives separately
-- in the negative-control Main, not in this committed registry.
module LocalGateRegistry
  ( LocalProducer (..)
  , LocalRegistration (..)
  , LocalRegistryFailure (..)
  , LocalTreeAnchor (..)
  , committedLocalRegistrations
  , localProducerName
  , localRegistrationFailures
  , registeredLocalFamilyTrees
  , registeredLocalTestTrees
  , localTreeAnchorFailures
  ) where

import Data.List (group, sort)
import Data.Text (Text)
import Data.Text qualified as Text
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Ingredients.Basic (testsNames)

import AlphaZeroEvaluation qualified
import ArsAppliedStep qualified
import ArsHostPhysicalAdmission qualified
import ArsHostRecordedData qualified
import ArsRecordedEvidence qualified
import ArsSingletonProducer qualified
import CheckpointPublication qualified
import CheckpointV1Admission qualified
import CriterionReviewData qualified
import DqnEvaluationControls qualified
import GenericArsHostPublication qualified
import GenericRlDeviceWitness qualified
import GenericRlPhysicalControls qualified
import InitialComparison qualified
import LaneRegistration qualified
import LearningSignal qualified
import NativeArenaEvaluation qualified
import NativeArenaLearningPolicy qualified
import NativeArenaReferences qualified
import NativeArenaTape qualified
import NativeCanonicalPublisher qualified
import NativeChildAssociation qualified
import NativeDetachedArtifactRead qualified
import NativeHerEvaluation qualified
import NativeHerLearningPolicy qualified
import NativeHerReferences qualified
import NativeLaneBundleAdmission qualified
import NativeLaneBundleData qualified
import NativeLaneBundleFiles qualified
import NativeParentAttemptRetention qualified
import NativeParentBindingData qualified
import NativeParentCompletionData qualified
import NativeParentEvaluationReplay qualified
import NativeParentEvaluationSummaryData qualified
import NativeParentExecution qualified
import NativeParentPhysicalRead qualified
import NativeParentPolicyData qualified
import NativePhaseCodec qualified
import NativePhaseContext qualified
import NativePhaseFailure qualified
import NativePhaseProducer qualified
import NativePhaseProjection qualified
import NativePhysicalRead qualified
import NativePreparedAlphaZeroAttempt qualified
import NativePreparedArsAttempt qualified
import NativePreparedNeuralAttempt qualified
import NativeProcessSpawn qualified
import NativeQualificationGc qualified
import NativeQualificationPublication qualified
import NativeQualificationReceiptData qualified
import NativeQualificationReference qualified
import NativeRecordedCheckpointData qualified
import NativeReferenceCalibration qualified
import NativeReplayObjectData qualified
import NativeReportExecution qualified
import NativeRetention qualified
import NativeRetentionReader qualified
import NativeReturnCeiling qualified
import NativeReturnEvaluation qualified
import NativeReturnLearningPolicy qualified
import NativeReturnReferences qualified
import NativeRlAssessment qualified
import NativeRlCohortPlan qualified
import NativeRlExecution qualified
import NativeRlProducer qualified
import NativeRlReplayRetention qualified
import NativeRlStoreLoadedReplay qualified
import NativeRlStoredServing qualified
import NativeScenarioReceiptData qualified
import NativeSourceJournalV5 qualified
import OffPolicyEvaluation qualified
import OnPolicyEvaluation qualified
import OnPolicyHorizon qualified
import Phase278ContextResolution qualified
import PreparedContinuousAlphaZero qualified
import PreparedNeuralAttempt qualified
import PreparedTrainers qualified
import ProducerObservation qualified
import ProductBarLocalControls qualified
import ProductExperimentExactness qualified
import ProductTruthScanner qualified
import ProtocolCodec qualified
import QualificationObjects qualified
import RegressionStandardization qualified
import ServedMetricVerification qualified
import SupervisedCheckpointV2 qualified
import SupervisedCohortExecution qualified
import SupervisedCohortPlan qualified
import SupervisedQualification qualified
import SupervisedQualificationPolicy qualified
import SupervisedQualificationReceipt qualified
import SupervisedTrainingSeed qualified
import TinyArchiveControls qualified
import TrainerConfiguration qualified
import TrainerObservation qualified
import TrpoFisherControls qualified

data LocalProducer
  = LearningSignalProducer
  | SupervisedQualificationPolicyProducer
  | SupervisedCohortPlanProducer
  | InitialComparisonProducer
  | SupervisedQualificationProducer
  | QualificationObjectsProducer
  | SupervisedCohortExecutionProducer
  | SupervisedQualificationReceiptProducer
  | ServedMetricVerificationProducer
  | SupervisedCheckpointV2Producer
  | ProductTruthScannerProducer
  | ProductExperimentExactnessProducer
  | RegressionStandardizationProducer
  | SupervisedTrainingSeedProducer
  | CheckpointV1AdmissionProducer
  | OnPolicyEvaluationProducer
  | OnPolicyHorizonProducer
  | ProductBarLocalControlsProducer
  | TinyArchiveControlsProducer
  | TrpoFisherControlsProducer
  | ProtocolCodecProducer
  | GenericRlDeviceWitnessProducer
  | CheckpointPublicationProducer
  | GenericRlPhysicalControlsProducer
  | OffPolicyEvaluationProducer
  | TrainerObservationProducer
  | AlphaZeroEvaluationProducer
  | PreparedTrainersProducer
  | DqnEvaluationControlsProducer
  | ArsAppliedStepProducer
  | PreparedContinuousAlphaZeroProducer
  | ProducerObservationProducer
  | ArsHostRecordedDataProducer
  | ArsRecordedEvidenceProducer
  | NativeChildAssociationProducer
  | ArsSingletonProducerProducer
  | TrainerConfigurationProducer
  | NativeReturnReferencesProducer
  | NativeHerReferencesProducer
  | NativeReturnEvaluationProducer
  | NativeHerEvaluationProducer
  | NativeRlCohortPlanProducer
  | PreparedNeuralAttemptProducer
  | NativePreparedNeuralAttemptProducer
  | NativePreparedArsAttemptProducer
  | NativeArenaEvaluationProducer
  | NativePreparedAlphaZeroAttemptProducer
  | NativeRetentionProducer
  | NativeReturnCeilingProducer
  | NativeReturnLearningPolicyProducer
  | NativeArenaTapeProducer
  | NativeArenaReferencesProducer
  | NativeHerLearningPolicyProducer
  | NativeArenaLearningPolicyProducer
  | NativePhaseCodecProducer
  | NativePhaseProjectionProducer
  | NativePhaseContextProducer
  | NativePhaseProducerProducer
  | NativePhaseFailureProducer
  | NativeRlProducerProducer
  | NativeReferenceCalibrationProducer
  | NativeRlAssessmentProducer
  | NativeRetentionReaderProducer
  | ArsHostPhysicalAdmissionProducer
  | NativeRlStoreLoadedReplayProducer
  | NativePhysicalReadProducer
  | NativeReportExecutionProducer
  | NativeCanonicalPublisherProducer
  | NativeRlStoredServingProducer
  | NativeDetachedArtifactReadProducer
  | NativeQualificationReceiptDataProducer
  | NativeScenarioReceiptDataProducer
  | NativeParentPolicyDataProducer
  | NativeParentCompletionDataProducer
  | NativeParentEvaluationSummaryDataProducer
  | NativeSourceJournalV5Producer
  | NativeParentBindingDataProducer
  | NativeParentPhysicalReadProducer
  | NativeParentExecutionProducer
  | NativeParentEvaluationReplayProducer
  | NativeProcessSpawnProducer
  | NativeParentAttemptRetentionProducer
  | NativeQualificationGcProducer
  | NativeRlExecutionProducer
  | NativeRlReplayRetentionProducer
  | NativeQualificationPublicationProducer
  | NativeQualificationReferenceProducer
  | NativeReplayObjectDataProducer
  | NativeRecordedCheckpointDataProducer
  | NativeLaneBundleAdmissionProducer
  | NativeLaneBundleDataProducer
  | NativeLaneBundleFilesProducer
  | GenericArsHostPublicationProducer
  | Phase278ContextResolutionProducer
  | LaneRegistrationProducer
  | CriterionReviewDataProducer
  deriving (Eq, Ord, Show)

data LocalRegistration = LocalRegistration
  { registeredLocalFamily :: Text
  , registeredLocalProducer :: LocalProducer
  }
  deriving (Eq, Show)

data LocalRegistryFailure
  = EmptyExpectedLocalInventory
  | DuplicateExpectedLocalFamily Text
  | MissingLocalFamily Text
  | DuplicateLocalFamily Text
  | UnexpectedLocalFamily Text
  | MisassignedLocalFamily Text Text
  | EmptyExpectedLocalTreeInventory
  | DuplicateExpectedLocalTreeFamily Text
  | MissingLocalTreeFamily Text
  | DuplicateLocalTreeFamily Text
  | UnexpectedLocalTreeFamily Text
  | EmptyLocalFamilyTree Text
  | WrongLocalTreeRoot Text Text
  | MissingLocalTreeLeafAnchor Text Text
  | DuplicateLocalTreeLeaf Text Text
  deriving (Eq, Ord, Show)

-- | Independently declared structural anchors. A leaf anchor is a literal leaf
-- title, independent of this module's producer dispatch and registration names.
-- It is intentionally weaker than semantic/behavioral proof of the test body.
data LocalTreeAnchor = LocalTreeAnchor
  { anchorLocalFamily :: Text
  , anchorLocalRoot :: Text
  , anchorLocalLeaf :: Text
  }
  deriving (Eq, Show)

localProducerName :: LocalProducer -> Text
localProducerName producer = case producer of
  LearningSignalProducer -> "LearningSignal"
  SupervisedQualificationPolicyProducer -> "SupervisedQualificationPolicy"
  SupervisedCohortPlanProducer -> "SupervisedCohortPlan"
  InitialComparisonProducer -> "InitialComparison"
  SupervisedQualificationProducer -> "SupervisedQualification"
  QualificationObjectsProducer -> "QualificationObjects"
  SupervisedCohortExecutionProducer -> "SupervisedCohortExecution"
  SupervisedQualificationReceiptProducer -> "SupervisedQualificationReceipt"
  ServedMetricVerificationProducer -> "ServedMetricVerification"
  SupervisedCheckpointV2Producer -> "SupervisedCheckpointV2"
  ProductTruthScannerProducer -> "ProductTruthScanner"
  ProductExperimentExactnessProducer -> "ProductExperimentExactness"
  RegressionStandardizationProducer -> "RegressionStandardization"
  SupervisedTrainingSeedProducer -> "SupervisedTrainingSeed"
  CheckpointV1AdmissionProducer -> "CheckpointV1Admission"
  OnPolicyEvaluationProducer -> "OnPolicyEvaluation"
  OnPolicyHorizonProducer -> "OnPolicyHorizon"
  ProductBarLocalControlsProducer -> "ProductBarLocalControls"
  TinyArchiveControlsProducer -> "TinyArchiveControls"
  TrpoFisherControlsProducer -> "TrpoFisherControls"
  ProtocolCodecProducer -> "ProtocolCodec"
  GenericRlDeviceWitnessProducer -> "GenericRlDeviceWitness"
  CheckpointPublicationProducer -> "CheckpointPublication"
  GenericRlPhysicalControlsProducer -> "GenericRlPhysicalControls"
  OffPolicyEvaluationProducer -> "OffPolicyEvaluation"
  TrainerObservationProducer -> "TrainerObservation"
  AlphaZeroEvaluationProducer -> "AlphaZeroEvaluation"
  PreparedTrainersProducer -> "PreparedTrainers"
  DqnEvaluationControlsProducer -> "DqnEvaluationControls"
  ArsAppliedStepProducer -> "ArsAppliedStep"
  PreparedContinuousAlphaZeroProducer -> "PreparedContinuousAlphaZero"
  ProducerObservationProducer -> "ProducerObservation"
  ArsHostRecordedDataProducer -> "ArsHostRecordedData"
  ArsRecordedEvidenceProducer -> "ArsRecordedEvidence"
  NativeChildAssociationProducer -> "NativeChildAssociation"
  ArsSingletonProducerProducer -> "ArsSingletonProducer"
  TrainerConfigurationProducer -> "TrainerConfiguration"
  NativeReturnReferencesProducer -> "NativeReturnReferences"
  NativeHerReferencesProducer -> "NativeHerReferences"
  NativeReturnEvaluationProducer -> "NativeReturnEvaluation"
  NativeHerEvaluationProducer -> "NativeHerEvaluation"
  NativeRlCohortPlanProducer -> "NativeRlCohortPlan"
  PreparedNeuralAttemptProducer -> "PreparedNeuralAttempt"
  NativePreparedNeuralAttemptProducer -> "NativePreparedNeuralAttempt"
  NativePreparedArsAttemptProducer -> "NativePreparedArsAttempt"
  NativeArenaEvaluationProducer -> "NativeArenaEvaluation"
  NativePreparedAlphaZeroAttemptProducer -> "NativePreparedAlphaZeroAttempt"
  NativeRetentionProducer -> "NativeRetention"
  NativeReturnCeilingProducer -> "NativeReturnCeiling"
  NativeReturnLearningPolicyProducer -> "NativeReturnLearningPolicy"
  NativeArenaTapeProducer -> "NativeArenaTape"
  NativeArenaReferencesProducer -> "NativeArenaReferences"
  NativeHerLearningPolicyProducer -> "NativeHerLearningPolicy"
  NativeArenaLearningPolicyProducer -> "NativeArenaLearningPolicy"
  NativePhaseCodecProducer -> "NativePhaseCodec"
  NativePhaseProjectionProducer -> "NativePhaseProjection"
  NativePhaseContextProducer -> "NativePhaseContext"
  NativePhaseProducerProducer -> "NativePhaseProducer"
  NativePhaseFailureProducer -> "NativePhaseFailure"
  NativeRlProducerProducer -> "NativeRlProducer"
  NativeReferenceCalibrationProducer -> "NativeReferenceCalibration"
  NativeRlAssessmentProducer -> "NativeRlAssessment"
  NativeRetentionReaderProducer -> "NativeRetentionReader"
  ArsHostPhysicalAdmissionProducer -> "ArsHostPhysicalAdmission"
  NativeRlStoreLoadedReplayProducer -> "NativeRlStoreLoadedReplay"
  NativePhysicalReadProducer -> "NativePhysicalRead"
  NativeReportExecutionProducer -> "NativeReportExecution"
  NativeCanonicalPublisherProducer -> "NativeCanonicalPublisher"
  NativeRlStoredServingProducer -> "NativeRlStoredServing"
  NativeDetachedArtifactReadProducer -> "NativeDetachedArtifactRead"
  NativeQualificationReceiptDataProducer -> "NativeQualificationReceiptData"
  NativeScenarioReceiptDataProducer -> "NativeScenarioReceiptData"
  NativeParentPolicyDataProducer -> "NativeParentPolicyData"
  NativeParentCompletionDataProducer -> "NativeParentCompletionData"
  NativeParentEvaluationSummaryDataProducer -> "NativeParentEvaluationSummaryData"
  NativeSourceJournalV5Producer -> "NativeSourceJournalV5"
  NativeParentBindingDataProducer -> "NativeParentBindingData"
  NativeParentPhysicalReadProducer -> "NativeParentPhysicalRead"
  NativeParentExecutionProducer -> "NativeParentExecution"
  NativeParentEvaluationReplayProducer -> "NativeParentEvaluationReplay"
  NativeProcessSpawnProducer -> "NativeProcessSpawn"
  NativeParentAttemptRetentionProducer -> "NativeParentAttemptRetention"
  NativeQualificationGcProducer -> "NativeQualificationGc"
  NativeRlExecutionProducer -> "NativeRlExecution"
  NativeRlReplayRetentionProducer -> "NativeRlReplayRetention"
  NativeQualificationPublicationProducer -> "NativeQualificationPublication"
  NativeQualificationReferenceProducer -> "NativeQualificationReference"
  NativeReplayObjectDataProducer -> "NativeReplayObjectData"
  NativeRecordedCheckpointDataProducer -> "NativeRecordedCheckpointData"
  NativeLaneBundleAdmissionProducer -> "NativeLaneBundleAdmission"
  NativeLaneBundleDataProducer -> "NativeLaneBundleData"
  NativeLaneBundleFilesProducer -> "NativeLaneBundleFiles"
  GenericArsHostPublicationProducer -> "GenericArsHostPublication"
  Phase278ContextResolutionProducer -> "Phase278ContextResolution"
  LaneRegistrationProducer -> "LaneRegistration"
  CriterionReviewDataProducer -> "CriterionReviewData"

localProducerTree :: LocalProducer -> TestTree
localProducerTree producer = case producer of
  LearningSignalProducer -> LearningSignal.learningSignalTests
  SupervisedQualificationPolicyProducer -> SupervisedQualificationPolicy.supervisedQualificationPolicyTests
  SupervisedCohortPlanProducer -> SupervisedCohortPlan.supervisedCohortPlanTests
  InitialComparisonProducer -> InitialComparison.initialComparisonTests
  SupervisedQualificationProducer -> SupervisedQualification.supervisedQualificationTests
  QualificationObjectsProducer -> QualificationObjects.qualificationObjectsTests
  SupervisedCohortExecutionProducer -> SupervisedCohortExecution.supervisedCohortExecutionTests
  SupervisedQualificationReceiptProducer -> SupervisedQualificationReceipt.supervisedQualificationReceiptTests
  ServedMetricVerificationProducer -> ServedMetricVerification.servedMetricVerificationTests
  SupervisedCheckpointV2Producer -> SupervisedCheckpointV2.supervisedCheckpointV2Tests
  ProductTruthScannerProducer -> ProductTruthScanner.productTruthScannerTests
  ProductExperimentExactnessProducer -> ProductExperimentExactness.productExperimentExactnessTests
  RegressionStandardizationProducer -> RegressionStandardization.regressionStandardizationTests
  SupervisedTrainingSeedProducer -> SupervisedTrainingSeed.supervisedTrainingSeedTests
  CheckpointV1AdmissionProducer -> CheckpointV1Admission.checkpointV1AdmissionTests
  OnPolicyEvaluationProducer -> OnPolicyEvaluation.onPolicyEvaluationTests
  OnPolicyHorizonProducer -> OnPolicyHorizon.onPolicyHorizonTests
  ProductBarLocalControlsProducer -> ProductBarLocalControls.productBarLocalControls
  TinyArchiveControlsProducer -> TinyArchiveControls.tinyArchiveControls
  TrpoFisherControlsProducer -> TrpoFisherControls.trpoFisherControls
  ProtocolCodecProducer -> ProtocolCodec.protocolCodecTests
  GenericRlDeviceWitnessProducer -> GenericRlDeviceWitness.genericRlDeviceWitnessTests
  CheckpointPublicationProducer -> CheckpointPublication.checkpointPublicationTests
  GenericRlPhysicalControlsProducer -> GenericRlPhysicalControls.genericRlPhysicalControls
  OffPolicyEvaluationProducer -> OffPolicyEvaluation.offPolicyEvaluationTests
  TrainerObservationProducer -> TrainerObservation.trainerObservationTests
  AlphaZeroEvaluationProducer -> AlphaZeroEvaluation.alphaZeroEvaluationTests
  PreparedTrainersProducer -> PreparedTrainers.preparedTrainerTests
  DqnEvaluationControlsProducer -> DqnEvaluationControls.dqnEvaluationTests
  ArsAppliedStepProducer -> ArsAppliedStep.arsAppliedStepTests
  PreparedContinuousAlphaZeroProducer -> PreparedContinuousAlphaZero.preparedContinuousAlphaZeroTests
  ProducerObservationProducer -> ProducerObservation.producerObservationTests
  ArsHostRecordedDataProducer -> ArsHostRecordedData.arsHostRecordedDataTests
  ArsRecordedEvidenceProducer -> ArsRecordedEvidence.arsRecordedEvidenceTests
  NativeChildAssociationProducer -> NativeChildAssociation.nativeChildAssociationTests
  ArsSingletonProducerProducer -> ArsSingletonProducer.arsSingletonProducerTests
  TrainerConfigurationProducer -> TrainerConfiguration.trainerConfigurationTests
  NativeReturnReferencesProducer -> NativeReturnReferences.nativeReturnReferencesTests
  NativeHerReferencesProducer -> NativeHerReferences.nativeHerReferencesTests
  NativeReturnEvaluationProducer -> NativeReturnEvaluation.nativeReturnEvaluationTests
  NativeHerEvaluationProducer -> NativeHerEvaluation.nativeHerEvaluationTests
  NativeRlCohortPlanProducer -> NativeRlCohortPlan.nativeRlCohortPlanTests
  PreparedNeuralAttemptProducer -> PreparedNeuralAttempt.preparedNeuralAttemptTests
  NativePreparedNeuralAttemptProducer -> NativePreparedNeuralAttempt.nativePreparedNeuralAttemptTests
  NativePreparedArsAttemptProducer -> NativePreparedArsAttempt.nativePreparedArsAttemptTests
  NativeArenaEvaluationProducer -> NativeArenaEvaluation.nativeArenaEvaluationTests
  NativePreparedAlphaZeroAttemptProducer -> NativePreparedAlphaZeroAttempt.nativePreparedAlphaZeroAttemptTests
  NativeRetentionProducer -> NativeRetention.nativeRetentionTests
  NativeReturnCeilingProducer -> NativeReturnCeiling.nativeReturnCeilingTests
  NativeReturnLearningPolicyProducer -> NativeReturnLearningPolicy.nativeReturnLearningPolicyTests
  NativeArenaTapeProducer -> NativeArenaTape.nativeArenaTapeTests
  NativeArenaReferencesProducer -> NativeArenaReferences.nativeArenaReferencesTests
  NativeHerLearningPolicyProducer -> NativeHerLearningPolicy.nativeHerLearningPolicyTests
  NativeArenaLearningPolicyProducer -> NativeArenaLearningPolicy.nativeArenaLearningPolicyTests
  NativePhaseCodecProducer -> NativePhaseCodec.nativePhaseCodecTests
  NativePhaseProjectionProducer -> NativePhaseProjection.nativePhaseProjectionTests
  NativePhaseContextProducer -> NativePhaseContext.nativePhaseContextTests
  NativePhaseProducerProducer -> NativePhaseProducer.nativePhaseProducerTests
  NativePhaseFailureProducer -> NativePhaseFailure.nativePhaseFailureTests
  NativeRlProducerProducer -> NativeRlProducer.nativeRlProducerTests
  NativeReferenceCalibrationProducer -> NativeReferenceCalibration.nativeReferenceCalibrationTests
  NativeRlAssessmentProducer -> NativeRlAssessment.nativeRlAssessmentTests
  NativeRetentionReaderProducer -> NativeRetentionReader.nativeRetentionReaderTests
  ArsHostPhysicalAdmissionProducer -> ArsHostPhysicalAdmission.arsHostPhysicalAdmissionTests
  NativeRlStoreLoadedReplayProducer -> NativeRlStoreLoadedReplay.nativeRlStoreLoadedReplayTests
  NativePhysicalReadProducer -> NativePhysicalRead.nativePhysicalReadTests
  NativeReportExecutionProducer -> NativeReportExecution.nativeReportExecutionTests
  NativeCanonicalPublisherProducer -> NativeCanonicalPublisher.nativeCanonicalPublisherTests
  NativeRlStoredServingProducer -> NativeRlStoredServing.nativeRlStoredServingTests
  NativeDetachedArtifactReadProducer -> NativeDetachedArtifactRead.nativeDetachedArtifactReadTests
  NativeQualificationReceiptDataProducer -> NativeQualificationReceiptData.nativeQualificationReceiptDataTests
  NativeScenarioReceiptDataProducer -> NativeScenarioReceiptData.nativeScenarioReceiptDataTests
  NativeParentPolicyDataProducer -> NativeParentPolicyData.nativeParentPolicyDataTests
  NativeParentCompletionDataProducer -> NativeParentCompletionData.nativeParentCompletionDataTests
  NativeParentEvaluationSummaryDataProducer -> NativeParentEvaluationSummaryData.nativeParentEvaluationSummaryDataTests
  NativeSourceJournalV5Producer -> NativeSourceJournalV5.nativeSourceJournalV5Tests
  NativeParentBindingDataProducer -> NativeParentBindingData.nativeParentBindingDataTests
  NativeParentPhysicalReadProducer -> NativeParentPhysicalRead.nativeParentPhysicalReadTests
  NativeParentExecutionProducer -> NativeParentExecution.nativeParentExecutionTests
  NativeParentEvaluationReplayProducer -> NativeParentEvaluationReplay.nativeParentEvaluationReplayTests
  NativeProcessSpawnProducer -> NativeProcessSpawn.nativeProcessSpawnTests
  NativeParentAttemptRetentionProducer -> NativeParentAttemptRetention.nativeParentAttemptRetentionTests
  NativeQualificationGcProducer -> NativeQualificationGc.nativeQualificationGcTests
  NativeRlExecutionProducer -> NativeRlExecution.nativeRlExecutionTests
  NativeRlReplayRetentionProducer -> NativeRlReplayRetention.nativeRlReplayRetentionTests
  NativeQualificationPublicationProducer -> NativeQualificationPublication.nativeQualificationPublicationTests
  NativeQualificationReferenceProducer -> NativeQualificationReference.nativeQualificationReferenceTests
  NativeReplayObjectDataProducer -> NativeReplayObjectData.nativeReplayObjectDataTests
  NativeRecordedCheckpointDataProducer -> NativeRecordedCheckpointData.nativeRecordedCheckpointDataTests
  NativeLaneBundleAdmissionProducer -> NativeLaneBundleAdmission.nativeLaneBundleAdmissionTests
  NativeLaneBundleDataProducer -> NativeLaneBundleData.nativeLaneBundleDataTests
  NativeLaneBundleFilesProducer -> NativeLaneBundleFiles.nativeLaneBundleFilesTests
  GenericArsHostPublicationProducer -> GenericArsHostPublication.genericArsHostPublicationTests
  Phase278ContextResolutionProducer -> Phase278ContextResolution.phase278ContextResolutionTests
  LaneRegistrationProducer -> LaneRegistration.laneRegistrationTests
  CriterionReviewDataProducer -> CriterionReviewData.criterionReviewDataTests

committedLocalRegistrations :: [LocalRegistration]
committedLocalRegistrations =
  [ LocalRegistration "LearningSignal" LearningSignalProducer
  , LocalRegistration "SupervisedQualificationPolicy" SupervisedQualificationPolicyProducer
  , LocalRegistration "SupervisedCohortPlan" SupervisedCohortPlanProducer
  , LocalRegistration "InitialComparison" InitialComparisonProducer
  , LocalRegistration "SupervisedQualification" SupervisedQualificationProducer
  , LocalRegistration "QualificationObjects" QualificationObjectsProducer
  , LocalRegistration "SupervisedCohortExecution" SupervisedCohortExecutionProducer
  , LocalRegistration "SupervisedQualificationReceipt" SupervisedQualificationReceiptProducer
  , LocalRegistration "ServedMetricVerification" ServedMetricVerificationProducer
  , LocalRegistration "SupervisedCheckpointV2" SupervisedCheckpointV2Producer
  , LocalRegistration "ProductTruthScanner" ProductTruthScannerProducer
  , LocalRegistration "ProductExperimentExactness" ProductExperimentExactnessProducer
  , LocalRegistration "RegressionStandardization" RegressionStandardizationProducer
  , LocalRegistration "SupervisedTrainingSeed" SupervisedTrainingSeedProducer
  , LocalRegistration "CheckpointV1Admission" CheckpointV1AdmissionProducer
  , LocalRegistration "OnPolicyEvaluation" OnPolicyEvaluationProducer
  , LocalRegistration "OnPolicyHorizon" OnPolicyHorizonProducer
  , LocalRegistration "ProductBarLocalControls" ProductBarLocalControlsProducer
  , LocalRegistration "TinyArchiveControls" TinyArchiveControlsProducer
  , LocalRegistration "TrpoFisherControls" TrpoFisherControlsProducer
  , LocalRegistration "ProtocolCodec" ProtocolCodecProducer
  , LocalRegistration "GenericRlDeviceWitness" GenericRlDeviceWitnessProducer
  , LocalRegistration "CheckpointPublication" CheckpointPublicationProducer
  , LocalRegistration "GenericRlPhysicalControls" GenericRlPhysicalControlsProducer
  , LocalRegistration "OffPolicyEvaluation" OffPolicyEvaluationProducer
  , LocalRegistration "TrainerObservation" TrainerObservationProducer
  , LocalRegistration "AlphaZeroEvaluation" AlphaZeroEvaluationProducer
  , LocalRegistration "PreparedTrainers" PreparedTrainersProducer
  , LocalRegistration "DqnEvaluationControls" DqnEvaluationControlsProducer
  , LocalRegistration "ArsAppliedStep" ArsAppliedStepProducer
  , LocalRegistration "PreparedContinuousAlphaZero" PreparedContinuousAlphaZeroProducer
  , LocalRegistration "ProducerObservation" ProducerObservationProducer
  , LocalRegistration "ArsHostRecordedData" ArsHostRecordedDataProducer
  , LocalRegistration "ArsRecordedEvidence" ArsRecordedEvidenceProducer
  , LocalRegistration "NativeChildAssociation" NativeChildAssociationProducer
  , LocalRegistration "ArsSingletonProducer" ArsSingletonProducerProducer
  , LocalRegistration "TrainerConfiguration" TrainerConfigurationProducer
  , LocalRegistration "NativeReturnReferences" NativeReturnReferencesProducer
  , LocalRegistration "NativeHerReferences" NativeHerReferencesProducer
  , LocalRegistration "NativeReturnEvaluation" NativeReturnEvaluationProducer
  , LocalRegistration "NativeHerEvaluation" NativeHerEvaluationProducer
  , LocalRegistration "NativeRlCohortPlan" NativeRlCohortPlanProducer
  , LocalRegistration "PreparedNeuralAttempt" PreparedNeuralAttemptProducer
  , LocalRegistration "NativePreparedNeuralAttempt" NativePreparedNeuralAttemptProducer
  , LocalRegistration "NativePreparedArsAttempt" NativePreparedArsAttemptProducer
  , LocalRegistration "NativeArenaEvaluation" NativeArenaEvaluationProducer
  , LocalRegistration "NativePreparedAlphaZeroAttempt" NativePreparedAlphaZeroAttemptProducer
  , LocalRegistration "NativeRetention" NativeRetentionProducer
  , LocalRegistration "NativeReturnCeiling" NativeReturnCeilingProducer
  , LocalRegistration "NativeReturnLearningPolicy" NativeReturnLearningPolicyProducer
  , LocalRegistration "NativeArenaTape" NativeArenaTapeProducer
  , LocalRegistration "NativeArenaReferences" NativeArenaReferencesProducer
  , LocalRegistration "NativeHerLearningPolicy" NativeHerLearningPolicyProducer
  , LocalRegistration "NativeArenaLearningPolicy" NativeArenaLearningPolicyProducer
  , LocalRegistration "NativePhaseCodec" NativePhaseCodecProducer
  , LocalRegistration "NativePhaseProjection" NativePhaseProjectionProducer
  , LocalRegistration "NativePhaseContext" NativePhaseContextProducer
  , LocalRegistration "NativePhaseProducer" NativePhaseProducerProducer
  , LocalRegistration "NativePhaseFailure" NativePhaseFailureProducer
  , LocalRegistration "NativeRlProducer" NativeRlProducerProducer
  , LocalRegistration "NativeReferenceCalibration" NativeReferenceCalibrationProducer
  , LocalRegistration "NativeRlAssessment" NativeRlAssessmentProducer
  , LocalRegistration "NativeRetentionReader" NativeRetentionReaderProducer
  , LocalRegistration "ArsHostPhysicalAdmission" ArsHostPhysicalAdmissionProducer
  , LocalRegistration "NativeRlStoreLoadedReplay" NativeRlStoreLoadedReplayProducer
  , LocalRegistration "NativePhysicalRead" NativePhysicalReadProducer
  , LocalRegistration "NativeReportExecution" NativeReportExecutionProducer
  , LocalRegistration "NativeCanonicalPublisher" NativeCanonicalPublisherProducer
  , LocalRegistration "NativeRlStoredServing" NativeRlStoredServingProducer
  , LocalRegistration "NativeDetachedArtifactRead" NativeDetachedArtifactReadProducer
  , LocalRegistration "NativeQualificationReceiptData" NativeQualificationReceiptDataProducer
  , LocalRegistration "NativeScenarioReceiptData" NativeScenarioReceiptDataProducer
  , LocalRegistration "NativeParentPolicyData" NativeParentPolicyDataProducer
  , LocalRegistration "NativeParentCompletionData" NativeParentCompletionDataProducer
  , LocalRegistration "NativeParentEvaluationSummaryData" NativeParentEvaluationSummaryDataProducer
  , LocalRegistration "NativeSourceJournalV5" NativeSourceJournalV5Producer
  , LocalRegistration "NativeParentBindingData" NativeParentBindingDataProducer
  , LocalRegistration "NativeParentPhysicalRead" NativeParentPhysicalReadProducer
  , LocalRegistration "NativeParentExecution" NativeParentExecutionProducer
  , LocalRegistration "NativeParentEvaluationReplay" NativeParentEvaluationReplayProducer
  , LocalRegistration "NativeProcessSpawn" NativeProcessSpawnProducer
  , LocalRegistration "NativeParentAttemptRetention" NativeParentAttemptRetentionProducer
  , LocalRegistration "NativeQualificationGc" NativeQualificationGcProducer
  , LocalRegistration "NativeRlExecution" NativeRlExecutionProducer
  , LocalRegistration "NativeRlReplayRetention" NativeRlReplayRetentionProducer
  , LocalRegistration "NativeQualificationPublication" NativeQualificationPublicationProducer
  , LocalRegistration "NativeQualificationReference" NativeQualificationReferenceProducer
  , LocalRegistration "NativeReplayObjectData" NativeReplayObjectDataProducer
  , LocalRegistration "NativeRecordedCheckpointData" NativeRecordedCheckpointDataProducer
  , LocalRegistration "NativeLaneBundleAdmission" NativeLaneBundleAdmissionProducer
  , LocalRegistration "NativeLaneBundleData" NativeLaneBundleDataProducer
  , LocalRegistration "NativeLaneBundleFiles" NativeLaneBundleFilesProducer
  , LocalRegistration "GenericArsHostPublication" GenericArsHostPublicationProducer
  , LocalRegistration "Phase278ContextResolution" Phase278ContextResolutionProducer
  , LocalRegistration "LaneRegistration" LaneRegistrationProducer
  , LocalRegistration "CriterionReviewData" CriterionReviewDataProducer
  ]

localRegistrationFailures :: [Text] -> [LocalRegistration] -> [LocalRegistryFailure]
localRegistrationFailures expected registrations =
  [EmptyExpectedLocalInventory | null expected]
    <> fmap DuplicateExpectedLocalFamily (duplicates expected)
    <> [MissingLocalFamily name | name <- expectedNames, name `notElem` registeredNames]
    <> fmap DuplicateLocalFamily (duplicates registeredNames)
    <> [UnexpectedLocalFamily name | name <- sortedDistinct registeredNames, name `notElem` expectedNames]
    <> [ MisassignedLocalFamily (registeredLocalFamily registration) actual
       | registration <- registrations
       , let actual = localProducerName (registeredLocalProducer registration)
       , registeredLocalFamily registration /= actual
       ]
 where
  expectedNames = sortedDistinct expected
  registeredNames = fmap registeredLocalFamily registrations
  duplicates names = [name | values@(name : _) <- group (sort names), length values > 1]

-- | This exact list is shared by the runner and its structural guard. Keeping
-- raw trees here lets the guard inspect the actual producer RHS, not just names.
registeredLocalFamilyTrees :: [LocalRegistration] -> [(Text, TestTree)]
registeredLocalFamilyTrees = fmap $ \registration ->
  (registeredLocalFamily registration, localProducerTree (registeredLocalProducer registration))

registeredLocalTestTrees :: [(Text, TestTree)] -> [TestTree]
registeredLocalTestTrees = fmap $ \(family, tree) ->
  testGroup (Text.unpack family) [tree]

-- | Enumerate with the empty option set, without executing tests or acquiring
-- resources. The Tasty listing fold passes an unevaluated throwing IO action to
-- resource-dependent trees; these selected families do not inspect that action
-- to choose their shape. Filters in the outer runner cannot hide an anchor.
localTreeAnchorFailures :: [LocalTreeAnchor] -> [(Text, TestTree)] -> [LocalRegistryFailure]
localTreeAnchorFailures expected trees =
  [EmptyExpectedLocalTreeInventory | null expected]
    <> fmap DuplicateExpectedLocalTreeFamily (duplicates expectedFamilies)
    <> [ MissingLocalTreeFamily family
       | family <- sortedDistinct expectedFamilies
       , family `notElem` actualFamilies
       ]
    <> fmap DuplicateLocalTreeFamily (duplicates actualFamilies)
    <> [ UnexpectedLocalTreeFamily family
       | family <- sortedDistinct actualFamilies
       , family `notElem` expectedFamilies
       ]
    <> concat
      [ treeFailures anchor tree
      | anchor <- expected
      , (family, tree) <- trees
      , family == anchorLocalFamily anchor
      ]
 where
  expectedFamilies = fmap anchorLocalFamily expected
  actualFamilies = fmap fst trees
  duplicates names = [name | values@(name : _) <- group (sort names), length values > 1]
  treeFailures anchor tree =
    let family = anchorLocalFamily anchor
        names = fmap Text.pack (testsNames mempty tree)
        rootPrefix = anchorLocalRoot anchor <> "."
        leafSuffix = "." <> anchorLocalLeaf anchor
     in [EmptyLocalFamilyTree family | null names]
          <> [WrongLocalTreeRoot family (anchorLocalRoot anchor) | not (all (Text.isPrefixOf rootPrefix) names)]
          <> [ MissingLocalTreeLeafAnchor family (anchorLocalLeaf anchor)
             | not (any (Text.isSuffixOf leafSuffix) names)
             ]
          <> fmap (DuplicateLocalTreeLeaf family) (duplicates names)

-- | Sorted uniqueness using only base; preserves the registry error ordering.
sortedDistinct :: (Ord a) => [a] -> [a]
sortedDistinct names = [name | name : _ <- group (sort names)]
