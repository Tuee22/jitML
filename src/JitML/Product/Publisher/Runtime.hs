{-# LANGUAGE DataKinds #-}

module JitML.Product.Publisher.Runtime
  ( ProductPublisherRuntime (..)
  , RlPublishRun
  , SupervisedPublishRun (..)
  , TuningPublishDataset (..)
  )
where

import Data.ByteString.Lazy qualified as LazyByteString
import Data.Text (Text)
import Data.Word (Word64)

import JitML.Checkpoint.Format qualified as Checkpoint
import JitML.Checkpoint.Store qualified as CheckpointStore
import JitML.Env.Env (App)
import JitML.Numerics.LayerGraphMetadata (LayerGraphMetadata)
import JitML.Numerics.MlpDevice (MlpDevice)
import JitML.Plan.Plan (PlanId)
import JitML.Product.Evidence qualified as ProductEvidence
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.RL.Algorithms.Common qualified as AlgorithmCommon
import JitML.RL.Framework qualified as Framework
import JitML.RL.ProductBudget qualified as ProductBudget
import JitML.RL.TrainerExecution qualified as TrainerExecution
import JitML.SL.Canonicals qualified as SL
import JitML.SL.Classifier qualified as Classifier
import JitML.SL.RuntimeArtifact qualified as RuntimeArtifact
import JitML.Substrate (Substrate)
import JitML.Training.Budget qualified as TrainingBudget
import JitML.Tune.Catalog qualified as Tune

data ProductPublisherRuntime = ProductPublisherRuntime
  { publisherRunSupervisedTraining
      :: Substrate
      -> SL.CanonicalProblem
      -> Int
      -> Int
      -> Int
      -> Int
      -> Double
      -> App (Either Text SupervisedPublishRun)
  , publisherRunRlTraining
      :: Substrate
      -> MlpDevice
      -> ProductBudget.CompiledRlPlan
      -> IO (Either Text RlPublishRun)
  , publisherCompleteProductRow
      :: PlanId
      -> TrainingBudget.TrainingBudget
      -> ProductMatrix.ProductRow 'ProductMatrix.Declared
      -> Text
      -> Text
      -> Text
      -> Word64
      -> Word64
      -> [(Text, Double)]
      -> [Double]
      -> [Double]
      -> Either Text TrainingBudget.CompletedTraining
  , publisherCompleteSupervisedProductRowWithWeightHashes
      :: PlanId
      -> TrainingBudget.TrainingBudget
      -> ProductMatrix.ProductRow 'ProductMatrix.Declared
      -> Text
      -> Text
      -> Word64
      -> Word64
      -> [(Text, Double)]
      -> Text
      -> Text
      -> Either Text TrainingBudget.CompletedTraining
  , publisherRlCompletionMetrics
      :: Text
      -> AlgorithmCommon.MeasuredTrainerCounters
      -> Framework.EvaluationSet
      -> Either Text [(Text, Double)]
  , publisherRlCompletedTraining
      :: PlanId
      -> TrainingBudget.TrainingBudget
      -> Text
      -> Text
      -> Text
      -> Text
      -> Word64
      -> [(Text, Double)]
      -> ProductEvidence.TrainingEvidence
      -> Maybe TrainingBudget.CompletedTraining
  , publisherRlCompletionFailure
      :: Text
      -> Text
      -> [(Text, Double)]
      -> Text
  , publisherAlphaZeroCompletedTraining
      :: PlanId
      -> TrainingBudget.TrainingBudget
      -> Text
      -> Word64
      -> Word64
      -> Text
      -> [(Text, Double)]
      -> [Double]
      -> [Double]
      -> Either Text TrainingBudget.CompletedTraining
  , publisherWriteCompletedWeightCheckpoint
      :: TrainingBudget.CompletedTraining
      -> Text
      -> Text
      -> Word64
      -> [(Text, Double)]
      -> [Double]
      -> [Checkpoint.ArtifactPointer]
      -> App CheckpointStore.StoredCompletedCheckpoint
  , publisherWriteCompletedSupervisedCheckpoint
      :: TrainingBudget.CompletedTraining
      -> Text
      -> [(Text, Double)]
      -> RuntimeArtifact.TrainingRuntimeArtifact
      -> App CheckpointStore.StoredCompletedCheckpoint
  , publisherAdmitCompletedCheckpoint
      :: Text
      -> CheckpointStore.StoredCompletedCheckpoint
      -> App
           ( Either
               CheckpointStore.CheckpointAdmissionError
               CheckpointStore.AdmittedCompletedCheckpoint
           )
  , publisherWriteTextArtifact :: Text -> Text -> Text -> App (Text, Text)
  , publisherLoadTuningDataset
      :: Tune.TuningExecutionSpec
      -> App (Either Text TuningPublishDataset)
  , publisherReuseAdmittedCheckpoint
      :: Text
      -> App (Maybe CheckpointStore.AdmittedCompletedCheckpoint)
  -- ^ Idempotent reuse: re-admit the latest checkpoint already persisted for
  -- this experiment hash by re-reading every persisted byte through the exact
  -- Store admission path, or 'Nothing' when no admissible checkpoint exists
  -- yet.  Never mints completion from anything but the persisted artifact, so
  -- reusing a prior deterministic training output is not fabrication.
  }

data SupervisedPublishRun = SupervisedPublishRun
  { supervisedPublishTrainLoss :: !Double
  , supervisedPublishValidationLoss :: !Double
  , supervisedPublishExamplesProcessed :: !Int
  , supervisedPublishHeldOutMetric :: !(Maybe (Text, Double))
  , supervisedPublishCompletedUnits :: !Word64
  , supervisedPublishOptimizerUpdatesExecuted :: !Word64
  , supervisedPublishRuntimeProgram :: !RuntimeArtifact.RawSupervisedRuntime
  , supervisedPublishLayerGraphMetadata :: !(Maybe LayerGraphMetadata)
  , supervisedPublishInitialJmw1Bytes :: !LazyByteString.ByteString
  , supervisedPublishFinalJmw1Bytes :: !LazyByteString.ByteString
  , supervisedPublishVerifiedDatasetShaAtRead :: !Text
  , -- Transitional projections are retained for callers which still display
    -- lists.  The publisher never reconstructs V2 identity from them; when a
    -- projection is present it must agree exactly with the canonical bytes.
    supervisedPublishInitialWeights :: !(Maybe [Double])
  , supervisedPublishCheckpointWeights :: !(Maybe [Double])
  , supervisedPublishDatasetShaAtRead :: !(Maybe Text)
  }
  deriving stock (Eq, Show)

type RlPublishRun = TrainerExecution.TrainerRun

data TuningPublishDataset = TuningPublishDataset
  { tuningPublishProblem :: !SL.CanonicalProblem
  , tuningPublishBaseConfig :: !Classifier.ClassifierConfig
  , tuningPublishTrainSet :: !Classifier.Dataset
  , tuningPublishValidationSet :: !Classifier.Dataset
  , tuningPublishDatasetShaAtRead :: !Text
  }
  deriving stock (Eq, Show)
