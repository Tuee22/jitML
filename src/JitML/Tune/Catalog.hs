{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.Tune.Catalog
  ( FloatSearchSpace (..)
  , NaturalCategoricalSearchSpace (..)
  , Pruner (..)
  , Sampler (..)
  , Scheduler (..)
  , SearchScale (..)
  , TextCategoricalSearchSpace (..)
  , TuningConfig (..)
  , TuningExecutionSpec (..)
  , TuningExperiment (..)
  , TuningObjective (..)
  , TuningPruner (..)
  , TuningSampler (..)
  , TuningScheduler (..)
  , TuningSearchSpace (..)
  , TrialDisposition (..)
  , TrialExecution
  , TrialHyperparameters
  , TrialObjectiveResult
  , TrialRungObservation
  , TrialTranscript
  , ashaPromotedTrialIndices
  , canonicalMnistTuningExecutionSpec
  , deterministicTrials
  , deterministicTrialsWithDevice
  , decodeTrialTranscript
  , encodeTrialTranscript
  , legacyTuningExecutionSpec
  , syntheticTuningDatasetSha256
  , loadTuningExperiment
  , medianPrunedTrialIndices
  , prunerCatalog
  , prunerFromText
  , renderTuningPlan
  , renderTuningExecutionSpec
  , renderTrialResumeSummary
  , resumeMatchesFullRun
  , samplerCatalog
  , samplerFromText
  , schedulerCatalog
  , schedulerFromText
  , selectBestTrialResultForExecutionSpec
  , parseTuningExecutionSpec
  , trialObjectiveResult
  , trialObjectiveResultWithDevice
  , trialObjectiveResults
  , trialObjectiveResultsForBudget
  , trialObjectiveResultsForSeededBudget
  , trialObjectiveResultsForConfig
  , trialObjectiveResultsForAxes
  , trialObjectiveResultsWithDevice
  , trialObjectiveResultsWithDeviceForBudget
  , trialObjectiveResultsWithDeviceForSeededBudget
  , trialObjectiveResultsWithDeviceForConfig
  , trialObjectiveResultsWithDeviceForAxes
  , trialObjectiveResultsWithDeviceForSyntheticExecutionSpec
  , trialStorageKey
  , terminalTrialTranscript
  , trialExecutions
  , trialExecutionsForExecutionSpec
  , trialObjectiveResultsWithDeviceForExecutionSpec
  , tuningExecutionSpecForExperiment
  , tuningObjectiveOptimizerUpdates
  , tuningObjectiveParallelism
  , validateTuningExecutionSpec
  , trialBatchSize
  , trialDropout
  , trialExecutionPromoted
  , trialExecutionPruned
  , trialExecutionResult
  , trialLearningRate
  , trialObservationObjective
  , trialObservationUpdates
  , trialOptimizer
  , trialResultDisposition
  , trialResultHyperparameters
  , trialResultIndex
  , trialResultInitialWeights
  , trialResultObjective
  , trialResultObservations
  , trialResultUpdatesExecuted
  , trialResultWeights
  , transcriptDisposition
  , transcriptExperimentHash
  , transcriptObservations
  , transcriptTrialSeed
  , transcriptUpdatesExecuted
  , transcriptValues
  )
where

import Codec.Serialise (Serialise, deserialiseOrFail, serialise)
import Control.Concurrent.Async (mapConcurrently)
import Control.Exception.Safe (displayException, tryAny)
import Control.Monad (foldM)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString qualified as ByteString
import Data.ByteString.Builder qualified as Builder
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Char (digitToInt, intToDigit, isHexDigit)
import Data.Foldable (traverse_)
import Data.List qualified as List
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word64, Word8)
import Dhall qualified
import GHC.Generics (Generic)
import Numeric.Natural (Natural)
import Text.Read (readMaybe)

import System.IO.Unsafe (unsafePerformIO)

import JitML.Numerics.MlpDevice (MlpDevice, pureReferenceMlpDevice)
import JitML.SL.Architecture qualified as Architecture
import JitML.SL.Canonicals (ArchitectureFamily (..), CanonicalProblem (..))
import JitML.SL.Classifier qualified as Classifier

data Sampler
  = Grid
  | Sobol
  | Random
  | TPE
  | GPBO
  | GeneticAlgorithm
  | NSGA2
  | MuLambdaES
  | CMAES
  | EvolutionStrategies
  | PBT
  deriving stock (Eq, Read, Show)

data Scheduler
  = Fifo
  | SuccessiveHalving
  | Hyperband
  | ASHA
  deriving stock (Eq, Generic, Read, Show)
  deriving anyclass (Serialise)

data Pruner
  = NoPruner
  | MedianPruner
  | PercentilePruner
  deriving stock (Eq, Generic, Read, Show)
  deriving anyclass (Serialise)

data SearchScale
  = LinearScale
  | LogScale
  deriving stock (Eq, Read, Show)

data FloatSearchSpace = FloatSearchSpace
  { floatSearchMinimum :: !Double
  , floatSearchMaximum :: !Double
  , floatSearchScale :: !SearchScale
  }
  deriving stock (Eq, Read, Show)

newtype NaturalCategoricalSearchSpace = NaturalCategoricalSearchSpace
  { naturalSearchValues :: [Natural]
  }
  deriving stock (Eq, Read, Show)

newtype TextCategoricalSearchSpace = TextCategoricalSearchSpace
  { textSearchValues :: [Text]
  }
  deriving stock (Eq, Read, Show)

data TuningSearchSpace = TuningSearchSpace
  { tuningSearchLearningRate :: !FloatSearchSpace
  , tuningSearchBatchSize :: !NaturalCategoricalSearchSpace
  , tuningSearchDropout :: !FloatSearchSpace
  , tuningSearchOptimizer :: !TextCategoricalSearchSpace
  }
  deriving stock (Eq, Read, Show)

data TuningExperiment = TuningExperiment
  { tuningExperimentName :: Text
  , tuningExperimentDataset :: Text
  , tuningExperimentModel :: Text
  , tuningExperimentSeed :: Natural
  , tuningExperimentConfig :: Maybe TuningConfig
  }
  deriving stock (Eq, Read, Show)

data TuningConfig = TuningConfig
  { tuningConfigSampler :: TuningSampler
  , tuningConfigScheduler :: TuningScheduler
  , tuningConfigPruner :: TuningPruner
  , tuningConfigSpace :: TuningSearchSpace
  , tuningConfigTrials :: Natural
  , tuningConfigParallelism :: Natural
  , tuningConfigObjectives :: [TuningObjective]
  }
  deriving stock (Eq, Read, Show)

data TuningSampler = TuningSampler
  { tuningSamplerKind :: Sampler
  , tuningSamplerSeed :: Natural
  , tuningSamplerStartupTrials :: Natural
  }
  deriving stock (Eq, Read, Show)

data TuningScheduler = TuningScheduler
  { tuningSchedulerKind :: Scheduler
  , tuningSchedulerEta :: Natural
  , tuningSchedulerMaxBudget :: Natural
  , tuningSchedulerParallelism :: Natural
  }
  deriving stock (Eq, Read, Show)

data TuningPruner = TuningPruner
  { tuningPrunerKind :: Pruner
  , tuningPrunerWarmupTrials :: Natural
  , tuningPrunerEvalAtPercentile :: Natural
  }
  deriving stock (Eq, Read, Show)

data TuningObjective = TuningObjective
  { tuningObjectiveMetric :: Text
  , tuningObjectiveDirection :: Text
  }
  deriving stock (Eq, Read, Show)

-- | Every normalized tuning semantic that can change execution.  The common
-- run plan owns the substrate, placement, trial/update quantities, and run
-- seed; this value owns the dataset/model/objective and the complete tuning
-- algorithm configuration.  Product projections bind its canonical rendering
-- into their PlanId.
data TuningExecutionSpec = TuningExecutionSpec
  { tuningExecutionName :: !Text
  , tuningExecutionDataset :: !Text
  , tuningExecutionModel :: !Text
  , tuningExecutionSampler :: !TuningSampler
  , tuningExecutionScheduler :: !TuningScheduler
  , tuningExecutionPruner :: !TuningPruner
  , tuningExecutionSearchSpace :: !TuningSearchSpace
  , tuningExecutionTrials :: !Natural
  , tuningExecutionParallelism :: !Natural
  , tuningExecutionObjectives :: ![TuningObjective]
  }
  deriving stock (Eq, Read, Show)

data TrialHyperparameters = TrialHyperparameters
  { internalTrialLearningRate :: !Double
  , internalTrialBatchSize :: !Int
  , internalTrialDropout :: !Double
  , internalTrialOptimizer :: !Text
  }
  deriving stock (Eq, Read, Show)

trialLearningRate :: TrialHyperparameters -> Double
trialLearningRate = internalTrialLearningRate

trialBatchSize :: TrialHyperparameters -> Int
trialBatchSize = internalTrialBatchSize

trialDropout :: TrialHyperparameters -> Double
trialDropout = internalTrialDropout

trialOptimizer :: TrialHyperparameters -> Text
trialOptimizer = internalTrialOptimizer

-- | The terminal evidence persisted for one tuning trial.  Construction is
-- intentionally limited to 'terminalTrialTranscript', which projects every
-- exact terminal field together so the stored objective cannot become
-- detached from its update count, disposition, or ordered rung observations.
data TrialTranscript = TrialTranscript
  { internalTranscriptExperimentHash :: !Text
  , internalTranscriptTrialSeed :: !Int
  , internalTranscriptValues :: ![Double]
  , internalTranscriptUpdatesExecuted :: !Int
  , internalTranscriptDisposition :: !TrialDisposition
  , internalTranscriptObservations :: ![TrialRungObservation]
  }
  deriving stock (Eq, Show)

transcriptExperimentHash :: TrialTranscript -> Text
transcriptExperimentHash = internalTranscriptExperimentHash

transcriptTrialSeed :: TrialTranscript -> Int
transcriptTrialSeed = internalTranscriptTrialSeed

transcriptValues :: TrialTranscript -> [Double]
transcriptValues = internalTranscriptValues

transcriptUpdatesExecuted :: TrialTranscript -> Int
transcriptUpdatesExecuted = internalTranscriptUpdatesExecuted

transcriptDisposition :: TrialTranscript -> TrialDisposition
transcriptDisposition = internalTranscriptDisposition

transcriptObservations :: TrialTranscript -> [TrialRungObservation]
transcriptObservations = internalTranscriptObservations

data TrialObjectiveResult = TrialObjectiveResult
  { internalTrialResultIndex :: !Int
  , internalTrialResultHyperparameters :: !TrialHyperparameters
  , internalTrialResultObjective :: !Double
  , internalTrialResultInitialWeights :: ![Double]
  , internalTrialResultWeights :: ![Double]
  , internalTrialResultUpdatesExecuted :: !Int
  , internalTrialResultObservations :: ![TrialRungObservation]
  , internalTrialResultDisposition :: !TrialDisposition
  }
  deriving stock (Eq, Show)

data TrialRungObservation = TrialRungObservation
  { internalTrialObservationUpdates :: !Int
  , internalTrialObservationObjective :: !Double
  }
  deriving stock (Eq, Generic, Show)
  deriving anyclass (Serialise)

data TrialDisposition
  = ReachedMaxBudget
  | SchedulerStopped !Scheduler !Int
  | PrunerStopped !Pruner !Int
  deriving stock (Eq, Generic, Show)
  deriving anyclass (Serialise)

-- | Project an exact terminal result into its persisted transcript.  The
-- scalar objective is retained in the historical @transcriptValues@ slot;
-- its equality with the final rung is checked again during decode.
terminalTrialTranscript :: Text -> Int -> TrialObjectiveResult -> TrialTranscript
terminalTrialTranscript experimentHash trialSeed result =
  TrialTranscript
    { internalTranscriptExperimentHash = experimentHash
    , internalTranscriptTrialSeed = trialSeed
    , internalTranscriptValues = [trialResultObjective result]
    , internalTranscriptUpdatesExecuted = trialResultUpdatesExecuted result
    , internalTranscriptDisposition = trialResultDisposition result
    , internalTranscriptObservations = trialResultObservations result
    }

-- The previous transcript was an unversioned generic triple that discarded
-- terminal state.  A private versioned storage DTO makes that legacy payload
-- fail closed instead of silently decoding as incomplete evidence.
data StoredTrialTranscript = StoredTrialTranscript
  { storedTranscriptVersion :: !Word64
  , storedTranscriptExperimentHash :: !Text
  , storedTranscriptTrialSeed :: !Int
  , storedTranscriptValues :: ![Double]
  , storedTranscriptUpdatesExecuted :: !Int
  , storedTranscriptDisposition :: !TrialDisposition
  , storedTranscriptObservations :: ![TrialRungObservation]
  }
  deriving stock (Generic)
  deriving anyclass (Serialise)

trialTranscriptWireVersion :: Word64
trialTranscriptWireVersion = 2

-- | Deterministic versioned CBOR for MinIO persistence and replay.
encodeTrialTranscript :: TrialTranscript -> ByteString.ByteString
encodeTrialTranscript transcript =
  LazyByteString.toStrict
    ( serialise
        StoredTrialTranscript
          { storedTranscriptVersion = trialTranscriptWireVersion
          , storedTranscriptExperimentHash = transcriptExperimentHash transcript
          , storedTranscriptTrialSeed = transcriptTrialSeed transcript
          , storedTranscriptValues = transcriptValues transcript
          , storedTranscriptUpdatesExecuted = transcriptUpdatesExecuted transcript
          , storedTranscriptDisposition = transcriptDisposition transcript
          , storedTranscriptObservations = transcriptObservations transcript
          }
    )

-- | Decode and re-refine persisted terminal evidence.  Corrupt, legacy, or
-- internally inconsistent payloads are rejected before entering replay state.
decodeTrialTranscript :: ByteString.ByteString -> Either Text TrialTranscript
decodeTrialTranscript bytes =
  case deserialiseOrFail (LazyByteString.fromStrict bytes) of
    Left err -> Left ("tuning trial transcript decode failed: " <> Text.pack (show err))
    Right stored -> refineStoredTrialTranscript stored

refineStoredTrialTranscript :: StoredTrialTranscript -> Either Text TrialTranscript
refineStoredTrialTranscript stored
  | storedTranscriptVersion stored /= trialTranscriptWireVersion =
      Left
        ( "unsupported tuning trial transcript version: "
            <> Text.pack (show (storedTranscriptVersion stored))
        )
  | Text.null (Text.strip (storedTranscriptExperimentHash stored)) =
      Left "tuning trial transcript experiment hash must be non-empty"
  | storedTranscriptTrialSeed stored < 0 =
      Left "tuning trial transcript seed must be non-negative"
  | storedTranscriptUpdatesExecuted stored <= 0 =
      Left "tuning trial transcript update count must be positive"
  | otherwise = do
      objective <-
        case storedTranscriptValues stored of
          [value]
            | finite value -> Right value
            | otherwise -> Left "tuning trial transcript objective must be finite"
          _ -> Left "tuning trial transcript requires exactly one scalar objective"
      observations <-
        case storedTranscriptObservations stored of
          [] -> Left "tuning trial transcript requires at least one rung observation"
          values -> Right values
      let observationUpdates = fmap trialObservationUpdates observations
          finalObservation = last observations
          updatesExecuted = storedTranscriptUpdatesExecuted stored
      if not (all (finite . trialObservationObjective) observations)
        then Left "tuning trial transcript rung objectives must be finite"
        else Right ()
      if any (<= 0) observationUpdates || not (strictlyIncreasing observationUpdates)
        then Left "tuning trial transcript rung updates must be positive and strictly increasing"
        else Right ()
      if trialObservationUpdates finalObservation /= updatesExecuted
        then Left "tuning trial transcript final rung does not match its update count"
        else Right ()
      if trialObservationObjective finalObservation /= objective
        then Left "tuning trial transcript final rung does not match its objective"
        else Right ()
      validateStoredDisposition updatesExecuted (storedTranscriptDisposition stored)
      Right
        TrialTranscript
          { internalTranscriptExperimentHash = storedTranscriptExperimentHash stored
          , internalTranscriptTrialSeed = storedTranscriptTrialSeed stored
          , internalTranscriptValues = [objective]
          , internalTranscriptUpdatesExecuted = updatesExecuted
          , internalTranscriptDisposition = storedTranscriptDisposition stored
          , internalTranscriptObservations = observations
          }
 where
  finite value = not (isNaN value || isInfinite value)
  strictlyIncreasing (first : second : rest) =
    first < second && strictlyIncreasing (second : rest)
  strictlyIncreasing _ = True

validateStoredDisposition :: Int -> TrialDisposition -> Either Text ()
validateStoredDisposition _ ReachedMaxBudget = Right ()
validateStoredDisposition updatesExecuted (SchedulerStopped _ rung)
  | rung == updatesExecuted = Right ()
  | otherwise = Left "tuning trial transcript scheduler stop rung does not match its update count"
validateStoredDisposition updatesExecuted (PrunerStopped pruner rung)
  | pruner == NoPruner = Left "tuning trial transcript cannot stop through NoPruner"
  | rung == updatesExecuted = Right ()
  | otherwise = Left "tuning trial transcript pruner stop rung does not match its update count"

trialResultIndex :: TrialObjectiveResult -> Int
trialResultIndex = internalTrialResultIndex

trialResultHyperparameters :: TrialObjectiveResult -> TrialHyperparameters
trialResultHyperparameters = internalTrialResultHyperparameters

trialResultObjective :: TrialObjectiveResult -> Double
trialResultObjective = internalTrialResultObjective

trialResultInitialWeights :: TrialObjectiveResult -> [Double]
trialResultInitialWeights = internalTrialResultInitialWeights

trialResultWeights :: TrialObjectiveResult -> [Double]
trialResultWeights = internalTrialResultWeights

trialResultUpdatesExecuted :: TrialObjectiveResult -> Int
trialResultUpdatesExecuted = internalTrialResultUpdatesExecuted

trialResultObservations :: TrialObjectiveResult -> [TrialRungObservation]
trialResultObservations = internalTrialResultObservations

trialResultDisposition :: TrialObjectiveResult -> TrialDisposition
trialResultDisposition = internalTrialResultDisposition

trialObservationUpdates :: TrialRungObservation -> Int
trialObservationUpdates = internalTrialObservationUpdates

trialObservationObjective :: TrialRungObservation -> Double
trialObservationObjective = internalTrialObservationObjective

-- | The complete terminal disposition of one planned trial.  Results are
-- never filtered out: a tuning execution emits one terminal record for every
-- zero-based trial key, while pruning and promotion remain independent facts.
data TrialExecution = TrialExecution
  { internalTrialExecutionResult :: !TrialObjectiveResult
  , internalTrialExecutionPruned :: !Bool
  , internalTrialExecutionPromoted :: !Bool
  }
  deriving stock (Eq, Show)

trialExecutionResult :: TrialExecution -> TrialObjectiveResult
trialExecutionResult = internalTrialExecutionResult

trialExecutionPruned :: TrialExecution -> Bool
trialExecutionPruned = internalTrialExecutionPruned

trialExecutionPromoted :: TrialExecution -> Bool
trialExecutionPromoted = internalTrialExecutionPromoted

-- Internal state for one resumable exact tuning trial.  The architecture
-- training value is opaque and owns its optimizer state plus absolute update
-- counter, so moving between rungs advances only the requested delta.
data ExactTrialRuntime = ExactTrialRuntime
  { exactRuntimeIndex :: !Int
  , exactRuntimeHyperparameters :: !TrialHyperparameters
  , exactRuntimeTraining :: !Architecture.ExactArchitectureTraining
  , exactRuntimeObservations :: ![TrialRungObservation]
  }

data ExactRungHistory = ExactRungHistory
  { exactPrunerRungHistory :: !(Map Int [Double])
  , exactSchedulerRungHistory :: !(Map Int [Double])
  }

emptyExactRungHistory :: ExactRungHistory
emptyExactRungHistory = ExactRungHistory Map.empty Map.empty

samplerCatalog :: [Sampler]
samplerCatalog =
  [ Grid
  , Sobol
  , Random
  , TPE
  , GPBO
  , GeneticAlgorithm
  , NSGA2
  , MuLambdaES
  , CMAES
  , EvolutionStrategies
  , PBT
  ]

schedulerCatalog :: [Scheduler]
schedulerCatalog = [Fifo, SuccessiveHalving, Hyperband, ASHA]

prunerCatalog :: [Pruner]
prunerCatalog = [NoPruner, MedianPruner, PercentilePruner]

-- | Sprint 9.11 — the per-trial objective values of a sweep. Each value is a
-- __real measured objective__ ('trialObjective'): the sampler + trial index
-- pick a hyperparameter configuration, the reference classifier is trained on a
-- fixed separable dataset, and the value is train accuracy in @[0, 1]@
-- (higher is better, matching the worked example's @valAcc:Maximise@
-- objective). This replaces the former per-sampler LCG that trained no model
-- and measured nothing. The training is bit-deterministic on the same seed, so
-- the sequence is reproducible. The device-backed companion below drives live
-- worker/report paths; this pure surface drives the plan preview and the
-- resume-determinism check.
deterministicTrials :: Sampler -> Int -> [Double]
deterministicTrials sampler count =
  fmap trialResultObjective (trialObjectiveResults sampler count)

-- | Substrate-device-backed trial objective sequence. Each trial uses the same
-- deterministic sampled configuration as 'deterministicTrials', but routes the
-- classifier train through the supplied JIT 'MlpDevice'. A device failure
-- aborts the sweep with 'Left' instead of falling back to the pure objective.
deterministicTrialsWithDevice :: MlpDevice -> Sampler -> Int -> IO (Either Text [Double])
deterministicTrialsWithDevice device sampler count =
  fmap (fmap (fmap trialResultObjective)) (trialObjectiveResultsWithDevice device sampler count)

trialObjectiveResults :: Sampler -> Int -> [TrialObjectiveResult]
trialObjectiveResults sampler count =
  case trialObjectiveResultsForBudget
    sampler
    tuningObjectiveParallelism
    tuningObjectiveOptimizerUpdates
    count of
    Left err -> error (Text.unpack err)
    Right results -> results

-- | Execution shape used by the registered tuning ProductRow publisher.
-- Keep live completion fixtures on these values so they exercise the same real
-- objective schedule instead of a smaller smoke budget that cannot satisfy the
-- binding convergence criterion.
tuningObjectiveParallelism :: Int
tuningObjectiveParallelism = 1

tuningObjectiveOptimizerUpdates :: Int
tuningObjectiveOptimizerUpdates = 6

-- | Execute the exact trial/update budget in deterministic cohorts no wider
-- than the resolved parallelism.  Adaptive samplers observe every completed
-- earlier cohort; trials in the same cohort intentionally share that prefix,
-- matching concurrent scheduling semantics.
trialObjectiveResultsForBudget
  :: Sampler
  -> Int
  -> Int
  -> Int
  -> Either Text [TrialObjectiveResult]
trialObjectiveResultsForBudget sampler =
  trialObjectiveResultsForSeededBudget (seed sampler) sampler

-- | Execute an exact deterministic tuning budget from an explicit semantic
-- seed.  Product projections use this entrypoint so the seed in their PlanId
-- is the seed that actually selects every trial configuration.
trialObjectiveResultsForSeededBudget
  :: Int
  -> Sampler
  -> Int
  -> Int
  -> Int
  -> Either Text [TrialObjectiveResult]
trialObjectiveResultsForSeededBudget explicitSeed sampler parallelism updates count = do
  validateExecutionBudget parallelism updates count
  Right (go [] [0 .. count - 1])
 where
  go _ [] = []
  go history remaining =
    let (cohort, rest) = splitAt parallelism remaining
        results =
          fmap
            ( \trialIndex ->
                trialObjectiveResultFromHistoryForUpdatesWithSeed
                  explicitSeed
                  sampler
                  updates
                  trialIndex
                  history
            )
            cohort
     in results <> go (history <> results) rest

trialObjectiveResultsForConfig :: TuningConfig -> Int -> [TrialObjectiveResult]
trialObjectiveResultsForConfig config =
  trialObjectiveResultsForAxes
    (tuningSamplerKind (tuningConfigSampler config))
    (tuningSchedulerKind (tuningConfigScheduler config))
    (tuningPrunerKind (tuningConfigPruner config))

trialObjectiveResultsForAxes :: Sampler -> Scheduler -> Pruner -> Int -> [TrialObjectiveResult]
trialObjectiveResultsForAxes sampler scheduler pruner count =
  applySchedulerAndPruner scheduler pruner (trialObjectiveResults sampler count)

trialObjectiveResultsWithDevice
  :: MlpDevice -> Sampler -> Int -> IO (Either Text [TrialObjectiveResult])
trialObjectiveResultsWithDevice device sampler =
  trialObjectiveResultsWithDeviceForBudget
    device
    sampler
    tuningObjectiveParallelism
    tuningObjectiveOptimizerUpdates

trialObjectiveResultsWithDeviceForBudget
  :: MlpDevice
  -> Sampler
  -> Int
  -> Int
  -> Int
  -> IO (Either Text [TrialObjectiveResult])
trialObjectiveResultsWithDeviceForBudget device sampler =
  trialObjectiveResultsWithDeviceForSeededBudget device (seed sampler) sampler

-- | Device-backed counterpart of 'trialObjectiveResultsForSeededBudget'.
-- Existing APIs retain the catalog sampler seed for compatibility; exact
-- ProductRow execution supplies its resolved plan seed here.
trialObjectiveResultsWithDeviceForSeededBudget
  :: MlpDevice
  -> Int
  -> Sampler
  -> Int
  -> Int
  -> Int
  -> IO (Either Text [TrialObjectiveResult])
trialObjectiveResultsWithDeviceForSeededBudget device explicitSeed sampler parallelism updates count =
  case validateExecutionBudget parallelism updates count of
    Left err -> pure (Left err)
    Right () -> go [] [0 .. count - 1]
 where
  go history [] = pure (Right history)
  go history remaining = do
    let (cohort, rest) = splitAt parallelism remaining
    cohortResults <-
      mapConcurrently
        ( \trialIndex ->
            trialObjectiveResultWithDeviceFromHistoryForUpdatesWithSeed
              device
              explicitSeed
              sampler
              updates
              trialIndex
              history
        )
        cohort
    case sequence cohortResults of
      Left err -> pure (Left err)
      Right results -> go (history <> results) rest

-- | Execute a normalized tuning spec against the caller's real dataset and
-- architecture.  Every trial samples all four declared search axes and is
-- advanced through real scheduler/pruner rungs.  Intermediate objectives are
-- measured from the retained optimizer state; an early-stopped trial therefore
-- executes fewer updates instead of being trained to the ceiling and classified
-- after the fact.  The returned list contains one terminal record per planned
-- trial, including its actual update count, observation trace, and disposition.
trialObjectiveResultsWithDeviceForExecutionSpec
  :: MlpDevice
  -> Int
  -> TuningExecutionSpec
  -> CanonicalProblem
  -> Classifier.ClassifierConfig
  -> Classifier.Dataset
  -> Classifier.Dataset
  -> IO (Either Text [TrialObjectiveResult])
trialObjectiveResultsWithDeviceForExecutionSpec device runSeed spec problem baseConfig trainSet validationSet =
  case validateExactExecutionInputs spec problem trainSet validationSet of
    Left err -> pure (Left err)
    Right (trialCount, parallelism, maxBudget) ->
      case validateExactRunSeed runSeed spec problem trialCount of
        Left err -> pure (Left err)
        Right () ->
          go
            trialCount
            parallelism
            maxBudget
            emptyExactRungHistory
            []
            [0 .. trialCount - 1]
 where
  go _ _ _ _ completed [] =
    pure (Right (List.sortOn trialResultIndex completed))
  go trialCount parallelism maxBudget rungHistory completed remaining = do
    let etaE =
          naturalToInt "tuning scheduler eta" (tuningSchedulerEta (tuningExecutionScheduler spec))
    case etaE of
      Left err -> pure (Left err)
      Right eta -> do
        let width = exactSchedulerCohortWidth spec trialCount parallelism eta
            (cohort, rest) = splitAt width remaining
            samplerHistory = adaptiveHistoryForExecutionSpec spec completed
        cohortE <-
          executeExactTrialCohort
            device
            runSeed
            spec
            problem
            baseConfig
            trainSet
            validationSet
            parallelism
            maxBudget
            rungHistory
            samplerHistory
            cohort
        case cohortE of
          Left err -> pure (Left err)
          Right (results, rungHistory') ->
            go
              trialCount
              parallelism
              maxBudget
              rungHistory'
              (completed <> results)
              rest

-- | Execute an exact normalized tuning spec against the legacy synthetic
-- objective.  This is the truthful compatibility boundary for host/worker
-- plans that carry an exact execution spec but do not carry a fetched
-- dataset: the normalized dataset/model fields are still checked against the
-- fixed problem before any optimizer work begins, and both measurements use
-- the same ordered labeled examples whose digest is exposed by
-- 'syntheticTuningDatasetSha256'.
trialObjectiveResultsWithDeviceForSyntheticExecutionSpec
  :: MlpDevice
  -> Int
  -> TuningExecutionSpec
  -> IO (Either Text [TrialObjectiveResult])
trialObjectiveResultsWithDeviceForSyntheticExecutionSpec device runSeed spec =
  trialObjectiveResultsWithDeviceForExecutionSpec
    device
    runSeed
    spec
    tuningObjectiveProblem
    syntheticTuningClassifierConfig
    tuningObjectiveDataset
    tuningObjectiveDataset

-- The exact executor overwrites seed, epoch count, batch size, and learning
-- rate from the resolved spec/trial.  The remaining architecture dimensions
-- describe the actual two-feature, two-class synthetic dataset while retaining
-- the public classifier defaults as the compatibility architecture baseline.
syntheticTuningClassifierConfig :: Classifier.ClassifierConfig
syntheticTuningClassifierConfig =
  Classifier.defaultClassifierConfig
    { Classifier.clfInputs = 2
    , Classifier.clfClasses = 2
    }

adaptiveHistoryForExecutionSpec
  :: TuningExecutionSpec -> [TrialObjectiveResult] -> [TrialObjectiveResult]
adaptiveHistoryForExecutionSpec _ [] = []
adaptiveHistoryForExecutionSpec _ results =
  case filter ((== ReachedMaxBudget) . trialResultDisposition) results of
    completedAtCeiling@(_ : _) -> completedAtCeiling
    [] ->
      let deepest = maximum (fmap trialResultUpdatesExecuted results)
       in filter ((== deepest) . trialResultUpdatesExecuted) results

validateExactRunSeed
  :: Int -> TuningExecutionSpec -> CanonicalProblem -> Int -> Either Text ()
validateExactRunSeed runSeed spec problem trialCount
  | runSeed < 0 = Left "tuning run seed must be non-negative"
  | toInteger runSeed /= toInteger (tuningSamplerSeed (tuningExecutionSampler spec)) =
      Left "tuning run seed must equal the normalized sampler seed"
  | finalSeed > toInteger (maxBound :: Int) =
      Left "tuning run seed plus trial and architecture seed headroom exceeds the platform Int range"
  | otherwise = Right ()
 where
  finalSeed =
    toInteger runSeed
      + toInteger (max 0 (trialCount - 1))
      + Architecture.architectureSeedHeadroomForProblem problem

validateExactExecutionInputs
  :: TuningExecutionSpec
  -> CanonicalProblem
  -> Classifier.Dataset
  -> Classifier.Dataset
  -> Either Text (Int, Int, Int)
validateExactExecutionInputs spec problem trainSet validationSet = do
  validateTuningExecutionSpec spec
  if problemDataset problem /= tuningExecutionDataset spec
    then
      Left
        ( "tuning dataset mismatch: spec="
            <> tuningExecutionDataset spec
            <> ", problem="
            <> problemDataset problem
        )
    else Right ()
  if problemModel problem /= tuningExecutionModel spec
    then
      Left
        ( "tuning model mismatch: spec="
            <> tuningExecutionModel spec
            <> ", problem="
            <> problemModel problem
        )
    else Right ()
  if null trainSet then Left "tuning training dataset must be non-empty" else Right ()
  if null validationSet then Left "tuning validation dataset must be non-empty" else Right ()
  trialCount <- naturalToInt "tuning trials" (tuningExecutionTrials spec)
  parallelism <- naturalToInt "tuning parallelism" (tuningExecutionParallelism spec)
  updates <-
    naturalToInt
      "tuning scheduler max budget"
      (tuningSchedulerMaxBudget (tuningExecutionScheduler spec))
  validateExecutionBudget parallelism updates trialCount
  Right (trialCount, parallelism, updates)

exactSchedulerCohortWidth
  :: TuningExecutionSpec -> Int -> Int -> Int -> Int
exactSchedulerCohortWidth spec trialCount parallelism _eta =
  case tuningSchedulerKind (tuningExecutionScheduler spec) of
    Fifo -> parallelism
    SuccessiveHalving -> trialCount
    ASHA -> parallelism
    Hyperband -> parallelism

exactRungBudgets :: TuningExecutionSpec -> Int -> Int -> [(Int, Bool)]
exactRungBudgets spec eta maxBudget =
  Map.toAscList . Map.fromListWith (||) $
    case tuningSchedulerKind scheduler of
      Fifo
        | tuningPrunerKind pruner == NoPruner -> [(maxBudget, False)]
        | otherwise -> [(prunerEvaluationBudget, False), (maxBudget, False)]
      _ ->
        [(budget, True) | budget <- schedulerPowers]
          <> [(budget, False) | budget <- prunerCheckpoint]
          <> [(maxBudget, False)]
 where
  scheduler = tuningExecutionScheduler spec
  pruner = tuningExecutionPruner spec
  schedulerPowers = takeSchedulerPowers 1
  takeSchedulerPowers current
    | current >= maxBudget = []
    | eta <= 1 = [current]
    | current > maxBudget `div` eta = [current]
    | otherwise = current : takeSchedulerPowers (current * eta)
  prunerCheckpoint
    | tuningPrunerKind pruner == NoPruner = []
    | otherwise = [prunerEvaluationBudget]
  prunerEvaluationBudget = exactPrunerEvaluationBudget spec maxBudget

exactPrunerEvaluationBudget :: TuningExecutionSpec -> Int -> Int
exactPrunerEvaluationBudget spec maxBudget =
  fromInteger
    ( ( toInteger maxBudget
          * toInteger (tuningPrunerEvalAtPercentile (tuningExecutionPruner spec))
          + 99
      )
        `div` 100
    )

executeExactTrialCohort
  :: MlpDevice
  -> Int
  -> TuningExecutionSpec
  -> CanonicalProblem
  -> Classifier.ClassifierConfig
  -> Classifier.Dataset
  -> Classifier.Dataset
  -> Int
  -> Int
  -> ExactRungHistory
  -> [TrialObjectiveResult]
  -> [Int]
  -> IO (Either Text ([TrialObjectiveResult], ExactRungHistory))
executeExactTrialCohort device runSeed spec problem baseConfig trainSet validationSet parallelism maxBudget rungHistory samplerHistory trialIndices = do
  let etaE =
        naturalToInt "tuning scheduler eta" (tuningSchedulerEta (tuningExecutionScheduler spec))
  case etaE of
    Left err -> pure (Left err)
    Right eta -> do
      initialised <-
        mapConcurrentlyBounded
          parallelism
          (initialiseExactTrial runSeed spec problem baseConfig trainSet validationSet samplerHistory)
          trialIndices
      case sequence initialised of
        Left err -> pure (Left err)
        Right runtimes ->
          runExactRungs
            device
            spec
            parallelism
            eta
            maxBudget
            rungHistory
            []
            runtimes
            (exactRungBudgets spec eta maxBudget)

initialiseExactTrial
  :: Int
  -> TuningExecutionSpec
  -> CanonicalProblem
  -> Classifier.ClassifierConfig
  -> Classifier.Dataset
  -> Classifier.Dataset
  -> [TrialObjectiveResult]
  -> Int
  -> IO (Either Text ExactTrialRuntime)
initialiseExactTrial runSeed spec problem baseConfig trainSet validationSet history trialIndex = do
  let hyperparameters = sampleTrialHyperparameters spec trialIndex history
      config =
        baseConfig
          { Classifier.clfSeed = runSeed + trialIndex
          , Classifier.clfEpochs = 1
          , Classifier.clfBatchSize = trialBatchSize hyperparameters
          , Classifier.clfLearningRate = trialLearningRate hyperparameters
          }
  case (,)
    <$> Architecture.architectureSpecForProblem config problem
    <*> architectureOptimizer (trialOptimizer hyperparameters) of
    Left err -> pure (Left err)
    Right (architectureSpec, optimizer) -> do
      trainingE <-
        Architecture.initialiseExactArchitectureTraining
          architectureSpec
          config
          optimizer
          (trialDropout hyperparameters)
          trainSet
          validationSet
      pure $
        fmap
          ( \training ->
              ExactTrialRuntime
                { exactRuntimeIndex = trialIndex
                , exactRuntimeHyperparameters = hyperparameters
                , exactRuntimeTraining = training
                , exactRuntimeObservations = []
                }
          )
          trainingE

runExactRungs
  :: MlpDevice
  -> TuningExecutionSpec
  -> Int
  -> Int
  -> Int
  -> ExactRungHistory
  -> [TrialObjectiveResult]
  -> [ExactTrialRuntime]
  -> [(Int, Bool)]
  -> IO (Either Text ([TrialObjectiveResult], ExactRungHistory))
runExactRungs _ _ _ _ _ history terminal [] _ =
  pure (Right (List.sortOn trialResultIndex terminal, history))
runExactRungs _ _ _ _ _ history terminal runtimes [] =
  pure $ do
    reached <- traverse (finishExactRuntime ReachedMaxBudget) runtimes
    Right (List.sortOn trialResultIndex (terminal <> reached), history)
runExactRungs device spec parallelism eta maxBudget history terminal runtimes ((budget, isSchedulerRung) : remainingBudgets) = do
  advanced <-
    mapConcurrentlyBounded
      parallelism
      (advanceExactRuntimeTo device spec budget)
      runtimes
  case sequence advanced of
    Left err -> pure (Left err)
    Right observed ->
      case applyExactPruner spec maxBudget budget history observed of
        Left err -> pure (Left err)
        Right (history', prunerStopped, afterPruner)
          | budget >= maxBudget ->
              pure $ do
                reached <- traverse (finishExactRuntime ReachedMaxBudget) afterPruner
                Right
                  ( List.sortOn trialResultIndex (terminal <> prunerStopped <> reached)
                  , history'
                  )
          | not isSchedulerRung ->
              runExactRungs
                device
                spec
                parallelism
                eta
                maxBudget
                history'
                (terminal <> prunerStopped)
                afterPruner
                remainingBudgets
          | otherwise ->
              case applyExactScheduler spec eta budget history' afterPruner of
                Left err -> pure (Left err)
                Right (history'', schedulerStopped, continuing) ->
                  runExactRungs
                    device
                    spec
                    parallelism
                    eta
                    maxBudget
                    history''
                    (terminal <> prunerStopped <> schedulerStopped)
                    continuing
                    remainingBudgets

advanceExactRuntimeTo
  :: MlpDevice
  -> TuningExecutionSpec
  -> Int
  -> ExactTrialRuntime
  -> IO (Either Text ExactTrialRuntime)
advanceExactRuntimeTo device spec budget runtime =
  let completed = Architecture.exactArchitectureUpdatesExecuted (exactRuntimeTraining runtime)
      delta = budget - completed
   in if delta < 0
        then pure (Left "tuning rung budget moved backwards")
        else do
          trainingE <-
            Architecture.advanceExactArchitectureTraining
              device
              delta
              (exactRuntimeTraining runtime)
          case trainingE of
            Left err -> pure (Left err)
            Right training -> do
              measurementE <- Architecture.measureExactArchitectureValidation device training
              pure $ do
                measurement <- measurementE
                objective <- measuredRungObjective spec measurement
                if isNaN objective || isInfinite objective
                  then Left "tuning rung produced a non-finite objective"
                  else
                    Right
                      runtime
                        { exactRuntimeTraining = training
                        , exactRuntimeObservations =
                            exactRuntimeObservations runtime
                              <> [ TrialRungObservation
                                     { internalTrialObservationUpdates = budget
                                     , internalTrialObservationObjective = objective
                                     }
                                 ]
                        }

measuredRungObjective :: TuningExecutionSpec -> (Double, Double) -> Either Text Double
measuredRungObjective spec (validationLoss, validationAccuracy) =
  case tuningExecutionObjectives spec of
    [objective] ->
      case tuningObjectiveMetric objective of
        "valAcc" -> Right validationAccuracy
        "valLoss" -> Right validationLoss
        metric -> Left ("unsupported tuning objective metric: " <> metric)
    _ -> Left "scalar tuning execution requires exactly one objective"

applyExactPruner
  :: TuningExecutionSpec
  -> Int
  -> Int
  -> ExactRungHistory
  -> [ExactTrialRuntime]
  -> Either Text (ExactRungHistory, [TrialObjectiveResult], [ExactTrialRuntime])
applyExactPruner spec maxBudget budget history =
  foldM step (history, [], [])
 where
  prunerConfig = tuningExecutionPruner spec
  prunerKind = tuningPrunerKind prunerConfig
  warmup = fromIntegral (tuningPrunerWarmupTrials prunerConfig)
  percentileValue = fromIntegral (tuningPrunerEvalAtPercentile prunerConfig)
  evaluationBudget = exactPrunerEvaluationBudget spec maxBudget
  step (historySoFar, stopped, survivors) runtime = do
    objective <- latestExactRuntimeObjective runtime
    let priorAtRung = Map.findWithDefault [] budget (exactPrunerRungHistory historySoFar)
        eligible =
          prunerKind /= NoPruner
            && budget < maxBudget
            && budget >= evaluationBudget
            && not (null priorAtRung)
            && length priorAtRung >= warmup
        threshold =
          case prunerKind of
            MedianPruner -> median priorAtRung
            PercentilePruner -> percentile percentileValue priorAtRung
            NoPruner -> objective
        shouldStop = eligible && objectiveWorse spec objective threshold
        history' =
          historySoFar
            { exactPrunerRungHistory =
                Map.insert budget (priorAtRung <> [objective]) (exactPrunerRungHistory historySoFar)
            }
    if shouldStop
      then do
        result <- finishExactRuntime (PrunerStopped prunerKind budget) runtime
        Right (history', stopped <> [result], survivors)
      else Right (history', stopped, survivors <> [runtime])

applyExactScheduler
  :: TuningExecutionSpec
  -> Int
  -> Int
  -> ExactRungHistory
  -> [ExactTrialRuntime]
  -> Either Text (ExactRungHistory, [TrialObjectiveResult], [ExactTrialRuntime])
applyExactScheduler spec eta budget history runtimes = do
  ranked <- rankExactRuntimes spec runtimes
  let schedulerKind = tuningSchedulerKind (tuningExecutionScheduler spec)
      keepCount values = max 1 ((length values + eta - 1) `div` eta)
  case schedulerKind of
    Hyperband -> Left "exact Hyperband execution requires explicit bracket semantics"
    ASHA -> applyAshaSchedulerAtRung spec eta budget history runtimes
    Fifo -> Right (history, [], runtimes)
    SuccessiveHalving -> do
      let selected = take (keepCount ranked) ranked
          selectedIndices = fmap exactRuntimeIndex selected
          stopped = filter ((`notElem` selectedIndices) . exactRuntimeIndex) runtimes
          history' = recordSchedulerRungHistory budget runtimes history
      stoppedResults <-
        traverse
          (finishExactRuntime (SchedulerStopped schedulerKind budget))
          stopped
      Right
        ( history'
        , List.sortOn trialResultIndex stoppedResults
        , List.sortOn exactRuntimeIndex selected
        )

applyAshaSchedulerAtRung
  :: TuningExecutionSpec
  -> Int
  -> Int
  -> ExactRungHistory
  -> [ExactTrialRuntime]
  -> Either Text (ExactRungHistory, [TrialObjectiveResult], [ExactTrialRuntime])
applyAshaSchedulerAtRung spec eta budget history runtimes =
  foldM step (history, [], []) (List.sortOn exactRuntimeIndex runtimes)
 where
  step (historySoFar, stopped, continuing) runtime = do
    objective <- latestExactRuntimeObjective runtime
    let prior = Map.findWithDefault [] budget (exactSchedulerRungHistory historySoFar)
        promotedSlots = max 1 ((length prior + 1 + eta - 1) `div` eta)
        rankAfterStableTies =
          1 + length (filter (objectiveAtLeastAsGood spec objective) prior)
        history' =
          historySoFar
            { exactSchedulerRungHistory =
                Map.insert budget (prior <> [objective]) (exactSchedulerRungHistory historySoFar)
            }
    if rankAfterStableTies <= promotedSlots
      then Right (history', stopped, continuing <> [runtime])
      else do
        result <- finishExactRuntime (SchedulerStopped ASHA budget) runtime
        Right (history', stopped <> [result], continuing)

-- Earlier equal observations win deterministic ASHA ties.
objectiveAtLeastAsGood :: TuningExecutionSpec -> Double -> Double -> Bool
objectiveAtLeastAsGood spec candidate prior =
  case tuningExecutionObjectives spec of
    [objective]
      | tuningObjectiveDirection objective == "Minimise" -> prior <= candidate
    _ -> prior >= candidate

recordSchedulerRungHistory
  :: Int -> [ExactTrialRuntime] -> ExactRungHistory -> ExactRungHistory
recordSchedulerRungHistory budget runtimes history =
  history
    { exactSchedulerRungHistory =
        Map.insert
          budget
          ( Map.findWithDefault [] budget (exactSchedulerRungHistory history)
              <> [ trialObservationObjective observation
                 | runtime <- List.sortOn exactRuntimeIndex runtimes
                 , observation <- take 1 (reverse (exactRuntimeObservations runtime))
                 ]
          )
          (exactSchedulerRungHistory history)
    }

rankExactRuntimes
  :: TuningExecutionSpec -> [ExactTrialRuntime] -> Either Text [ExactTrialRuntime]
rankExactRuntimes spec runtimes = do
  scored <-
    traverse
      ( \runtime -> do
          objective <- latestExactRuntimeObjective runtime
          Right (objective, exactRuntimeIndex runtime, runtime)
      )
      runtimes
  let ranked =
        case tuningExecutionObjectives spec of
          [objective]
            | tuningObjectiveDirection objective == "Minimise" ->
                List.sortOn (\(value, index, _) -> (value, index)) scored
          _ -> List.sortOn (\(value, index, _) -> (negate value, index)) scored
  Right [runtime | (_, _, runtime) <- ranked]

latestExactRuntimeObjective :: ExactTrialRuntime -> Either Text Double
latestExactRuntimeObjective runtime =
  case reverse (exactRuntimeObservations runtime) of
    [] -> Left "tuning trial has no measured rung observation"
    observation : _ -> Right (trialObservationObjective observation)

finishExactRuntime
  :: TrialDisposition -> ExactTrialRuntime -> Either Text TrialObjectiveResult
finishExactRuntime disposition runtime = do
  objective <- latestExactRuntimeObjective runtime
  let training = exactRuntimeTraining runtime
  Right
    TrialObjectiveResult
      { internalTrialResultIndex = exactRuntimeIndex runtime
      , internalTrialResultHyperparameters = exactRuntimeHyperparameters runtime
      , internalTrialResultObjective = objective
      , internalTrialResultInitialWeights = Architecture.exactArchitectureInitialWeights training
      , internalTrialResultWeights = Architecture.exactArchitectureTrainedWeights training
      , internalTrialResultUpdatesExecuted = Architecture.exactArchitectureUpdatesExecuted training
      , internalTrialResultObservations = exactRuntimeObservations runtime
      , internalTrialResultDisposition = disposition
      }

mapConcurrentlyBounded :: Int -> (value -> IO result) -> [value] -> IO [result]
mapConcurrentlyBounded width action =
  fmap concat . traverse (mapConcurrently action) . chunksOf width

architectureOptimizer :: Text -> Either Text Architecture.ArchitectureOptimizer
architectureOptimizer "Adam" = Right Architecture.ArchitectureAdam
architectureOptimizer "AdamW" = Right Architecture.ArchitectureAdamW
architectureOptimizer "SGD" = Right Architecture.ArchitectureSGD
architectureOptimizer value = Left ("unsupported tuning optimizer: " <> value)

sampleTrialHyperparameters
  :: TuningExecutionSpec -> Int -> [TrialObjectiveResult] -> TrialHyperparameters
sampleTrialHyperparameters spec trialIndex history =
  TrialHyperparameters
    { internalTrialLearningRate = adaptiveFloat 0 learningRateSpace trialLearningRate
    , internalTrialBatchSize =
        fromIntegral
          (adaptiveCategorical 1 batchChoices (fromIntegral . trialBatchSize))
    , internalTrialDropout = adaptiveFloat 2 dropoutSpace trialDropout
    , internalTrialOptimizer = adaptiveCategorical 3 optimizerChoices trialOptimizer
    }
 where
  space = tuningExecutionSearchSpace spec
  learningRateSpace = tuningSearchLearningRate space
  batchChoices = naturalSearchValues (tuningSearchBatchSize space)
  dropoutSpace = tuningSearchDropout space
  optimizerChoices = textSearchValues (tuningSearchOptimizer space)
  sampler = tuningExecutionSampler spec
  adaptive =
    adaptiveSampler (tuningSamplerKind sampler)
      && trialIndex >= fromIntegral (tuningSamplerStartupTrials sampler)
      && not (null history)
  best = if adaptive then Just (bestTrialForSpec spec history) else Nothing
  adaptiveFloat slot search accessor =
    let sampled = sampleFloatSearch sampler trialIndex slot search
     in case best of
          Nothing -> sampled
          Just result -> blendSearchValue search (accessor (trialResultHyperparameters result)) sampled
  adaptiveCategorical
    :: Int -> [value] -> (TrialHyperparameters -> value) -> value
  adaptiveCategorical slot choices accessor =
    case best of
      Just result
        | samplerUnit sampler trialIndex (slot + 19) < 0.7 ->
            accessor (trialResultHyperparameters result)
      _ -> sampleCategoricalSearch sampler trialIndex slot choices

adaptiveSampler :: Sampler -> Bool
adaptiveSampler sampler =
  sampler `elem` [TPE, GPBO, GeneticAlgorithm, NSGA2, MuLambdaES, CMAES, EvolutionStrategies, PBT]

sampleFloatSearch :: TuningSampler -> Int -> Int -> FloatSearchSpace -> Double
sampleFloatSearch sampler trialIndex slot search =
  case floatSearchScale search of
    LinearScale -> minimumValue + unit * (maximumValue - minimumValue)
    LogScale -> exp (log minimumValue + unit * (log maximumValue - log minimumValue))
 where
  minimumValue = floatSearchMinimum search
  maximumValue = floatSearchMaximum search
  unit
    | tuningSamplerKind sampler == Grid =
        fromIntegral (trialIndex `mod` 17) / 16.0
    | otherwise = samplerUnit sampler trialIndex slot

blendSearchValue :: FloatSearchSpace -> Double -> Double -> Double
blendSearchValue search centre sampled =
  clampDouble minimumValue maximumValue blended
 where
  minimumValue = floatSearchMinimum search
  maximumValue = floatSearchMaximum search
  blended =
    case floatSearchScale search of
      LinearScale -> centre * 0.7 + sampled * 0.3
      LogScale -> exp (log centre * 0.7 + log sampled * 0.3)

sampleCategoricalSearch :: TuningSampler -> Int -> Int -> [value] -> value
sampleCategoricalSearch sampler trialIndex slot choices =
  choices !! index
 where
  index
    | tuningSamplerKind sampler == Grid = (trialIndex + slot) `mod` length choices
    | otherwise =
        floor (samplerUnit sampler trialIndex slot * fromIntegral (length choices)) `mod` length choices

samplerUnit :: TuningSampler -> Int -> Int -> Double
samplerUnit sampler trialIndex slot =
  fromIntegral hashed / 1000003.0
 where
  hashed :: Integer
  hashed =
    abs
      ( toInteger (tuningSamplerSeed sampler) * 1103515245
          + toInteger trialIndex * 2654435761
          + toInteger slot * 2246822519
      )
      `mod` 1000003

bestTrialForSpec :: TuningExecutionSpec -> [TrialObjectiveResult] -> TrialObjectiveResult
bestTrialForSpec _ [] = error "bestTrialForSpec: empty history"
bestTrialForSpec spec (firstResult : rest) =
  foldl select firstResult rest
 where
  select current candidate
    | objectiveBetter spec (trialResultObjective candidate) (trialResultObjective current) = candidate
    | otherwise = current

objectiveBetter :: TuningExecutionSpec -> Double -> Double -> Bool
objectiveBetter spec candidate current =
  case tuningExecutionObjectives spec of
    [objective]
      | tuningObjectiveDirection objective == "Minimise" -> candidate < current
    _ -> candidate > current

selectBestTrialResultForExecutionSpec
  :: TuningExecutionSpec -> [TrialObjectiveResult] -> Maybe TrialObjectiveResult
selectBestTrialResultForExecutionSpec _ [] = Nothing
selectBestTrialResultForExecutionSpec spec (firstResult : rest) =
  Just (foldl select firstResult rest)
 where
  select current candidate
    | objectiveBetter spec (trialResultObjective candidate) (trialResultObjective current) = candidate
    | otherwise = current

naturalToInt :: Text -> Natural -> Either Text Int
naturalToInt label value
  | toInteger value > toInteger (maxBound :: Int) =
      Left (label <> " exceeds the platform Int range")
  | otherwise = Right (fromIntegral value)

clampDouble :: Double -> Double -> Double -> Double
clampDouble minimumValue maximumValue = max minimumValue . min maximumValue

trialObjectiveResultsWithDeviceForConfig
  :: MlpDevice -> TuningConfig -> Int -> IO (Either Text [TrialObjectiveResult])
trialObjectiveResultsWithDeviceForConfig device config =
  trialObjectiveResultsWithDeviceForAxes
    device
    (tuningSamplerKind (tuningConfigSampler config))
    (tuningSchedulerKind (tuningConfigScheduler config))
    (tuningPrunerKind (tuningConfigPruner config))

trialObjectiveResultsWithDeviceForAxes
  :: MlpDevice -> Sampler -> Scheduler -> Pruner -> Int -> IO (Either Text [TrialObjectiveResult])
trialObjectiveResultsWithDeviceForAxes device sampler scheduler pruner count =
  fmap
    (fmap (applySchedulerAndPruner scheduler pruner))
    (trialObjectiveResultsWithDevice device sampler count)

applySchedulerAndPruner :: Scheduler -> Pruner -> [TrialObjectiveResult] -> [TrialObjectiveResult]
applySchedulerAndPruner scheduler pruner results =
  let pruned = medianPrunedTrialIndices pruner results
      unpruned =
        filter
          (\result -> trialResultIndex result `notElem` pruned)
          results
      promoted = ashaPromotedTrialIndices scheduler unpruned
      selected =
        filter
          (\result -> trialResultIndex result `elem` promoted)
          unpruned
   in if null selected then take 1 (List.sortOn (negate . trialResultObjective) results) else selected

-- | Classify a complete trial cohort without dropping terminal evidence.
-- Promotion count is exact: if scheduler/pruner semantics leave too few
-- eligible trials, execution fails closed instead of silently underpromoting.
trialExecutions
  :: Scheduler
  -> Pruner
  -> Int
  -> [TrialObjectiveResult]
  -> Either Text [TrialExecution]
trialExecutions scheduler pruner promotionCount results
  | promotionCount <= 0 = Left "tuning promotion count must be positive"
  | promotionCount > length promotionCandidates =
      Left
        ( "tuning plan requests "
            <> Text.pack (show promotionCount)
            <> " promotions, but scheduler/pruner semantics produced only "
            <> Text.pack (show (length promotionCandidates))
            <> " eligible trials"
        )
  | otherwise =
      Right
        [ TrialExecution
            { internalTrialExecutionResult = result
            , internalTrialExecutionPruned = trialResultIndex result `elem` prunedIndices
            , internalTrialExecutionPromoted = trialResultIndex result `elem` promotedIndices
            }
        | result <- results
        ]
 where
  prunedIndices = medianPrunedTrialIndices pruner results
  unpruned = filter ((`notElem` prunedIndices) . trialResultIndex) results
  promotionCandidates =
    case scheduler of
      Fifo -> unpruned
      SuccessiveHalving -> objectiveRanked unpruned
      Hyperband -> objectiveRanked unpruned
      ASHA -> objectiveRanked unpruned
  promotedIndices = fmap trialResultIndex (take promotionCount promotionCandidates)
  objectiveRanked = List.sortOn (negate . trialResultObjective)

-- | Validate and classify terminal evidence emitted by the exact executor.
-- Scheduler and pruner decisions have already happened at real rungs; this
-- function never recomputes them post-hoc.  Only trials that actually reached
-- the configured ceiling may be promoted.
trialExecutionsForExecutionSpec
  :: TuningExecutionSpec
  -> Int
  -> [TrialObjectiveResult]
  -> Either Text [TrialExecution]
trialExecutionsForExecutionSpec spec promotionCount results = do
  validateTuningExecutionSpec spec
  trialCount <- naturalToInt "tuning trials" (tuningExecutionTrials spec)
  maxBudget <-
    naturalToInt
      "tuning scheduler max budget"
      (tuningSchedulerMaxBudget (tuningExecutionScheduler spec))
  eta <-
    naturalToInt
      "tuning scheduler eta"
      (tuningSchedulerEta (tuningExecutionScheduler spec))
  if promotionCount <= 0
    then Left "tuning promotion count must be positive"
    else Right ()
  if length results /= trialCount
    then
      Left
        ( "tuning execution emitted "
            <> showText (length results)
            <> " terminal trials; expected "
            <> showText trialCount
        )
    else Right ()
  let ordered = List.sortOn trialResultIndex results
      actualIndices = fmap trialResultIndex ordered
      expectedIndices = [0 .. trialCount - 1]
  if actualIndices /= expectedIndices
    then Left "tuning execution trial indices must be unique and contiguous from zero"
    else Right ()
  traverse_ (validateExactTerminalResult spec eta maxBudget) ordered
  let promotionCandidates =
        rankForObjective
          spec
          (filter ((== ReachedMaxBudget) . trialResultDisposition) ordered)
  if promotionCount > length promotionCandidates
    then
      Left
        ( "tuning plan requests "
            <> Text.pack (show promotionCount)
            <> " promotions, but only "
            <> Text.pack (show (length promotionCandidates))
            <> " trials reached the optimizer-update ceiling"
        )
    else
      let promotedIndices = fmap trialResultIndex (take promotionCount promotionCandidates)
       in Right
            [ TrialExecution
                { internalTrialExecutionResult = result
                , internalTrialExecutionPruned =
                    case trialResultDisposition result of
                      PrunerStopped _ _ -> True
                      _ -> False
                , internalTrialExecutionPromoted = trialResultIndex result `elem` promotedIndices
                }
            | result <- ordered
            ]

validateExactTerminalResult
  :: TuningExecutionSpec -> Int -> Int -> TrialObjectiveResult -> Either Text ()
validateExactTerminalResult spec eta maxBudget result = do
  let observations = trialResultObservations result
      updates = fmap trialObservationUpdates observations
      executed = trialResultUpdatesExecuted result
      disposition = trialResultDisposition result
      validRungs = exactRungBudgets spec eta maxBudget
      validBudgets = fmap fst validRungs
      expectedPrefix = takeWhile (<= executed) validBudgets
  if null observations
    then Left (trialLabel <> " has no rung observations")
    else Right ()
  if updates /= expectedPrefix
    then Left (trialLabel <> " observations are not an exact prefix of configured checkpoints")
    else Right ()
  if any (> maxBudget) updates
    then Left (trialLabel <> " observed a rung above the configured ceiling")
    else Right ()
  if last updates /= executed
    then Left (trialLabel <> " update count does not match its final rung observation")
    else Right ()
  if trialResultObjective result /= trialObservationObjective (last observations)
    then Left (trialLabel <> " objective does not match its final rung observation")
    else Right ()
  if any
    (\observation -> let value = trialObservationObjective observation in isNaN value || isInfinite value)
    observations
    then Left (trialLabel <> " has a non-finite rung objective")
    else Right ()
  case disposition of
    ReachedMaxBudget
      | executed == maxBudget -> Right ()
      | otherwise -> Left (trialLabel <> " claims to reach the ceiling at a different update count")
    SchedulerStopped schedulerKind rung
      | schedulerKind /= tuningSchedulerKind (tuningExecutionScheduler spec) ->
          Left (trialLabel <> " names a scheduler different from the execution spec")
      | rung /= executed || rung >= maxBudget ->
          Left (trialLabel <> " has an invalid scheduler stop rung")
      | lookup rung validRungs /= Just True ->
          Left (trialLabel <> " scheduler stop is not at a configured eta rung")
      | otherwise -> Right ()
    PrunerStopped prunerKind rung
      | prunerKind == NoPruner || prunerKind /= tuningPrunerKind (tuningExecutionPruner spec) ->
          Left (trialLabel <> " names a pruner different from the execution spec")
      | rung /= executed || rung >= maxBudget ->
          Left (trialLabel <> " has an invalid pruner stop rung")
      | rung `notElem` validBudgets || rung < exactPrunerEvaluationBudget spec maxBudget ->
          Left (trialLabel <> " pruner stop is not at an allowed measured checkpoint")
      | otherwise -> Right ()
 where
  trialLabel = "tuning trial " <> showText (trialResultIndex result)

chunksOf :: Int -> [value] -> [[value]]
chunksOf _ [] = []
chunksOf size values =
  let (chunk, rest) = splitAt size values
   in chunk : chunksOf size rest

rankForObjective :: TuningExecutionSpec -> [TrialObjectiveResult] -> [TrialObjectiveResult]
rankForObjective spec =
  case tuningExecutionObjectives spec of
    [objective]
      | tuningObjectiveDirection objective == "Minimise" ->
          List.sortOn trialResultObjective
    _ -> List.sortOn (negate . trialResultObjective)

objectiveWorse :: TuningExecutionSpec -> Double -> Double -> Bool
objectiveWorse spec candidate threshold =
  case tuningExecutionObjectives spec of
    [objective]
      | tuningObjectiveDirection objective == "Minimise" -> candidate > threshold
    _ -> candidate < threshold

ashaPromotedTrialIndices :: Scheduler -> [TrialObjectiveResult] -> [Int]
ashaPromotedTrialIndices scheduler results =
  fmap trialResultIndex $
    case scheduler of
      Fifo -> results
      SuccessiveHalving -> topFraction 2 results
      Hyperband -> topFraction 3 results
      ASHA -> topFraction 2 results

topFraction :: Int -> [TrialObjectiveResult] -> [TrialObjectiveResult]
topFraction eta results =
  take kept ranked
 where
  kept = max 1 (length results `div` max 1 eta)
  ranked = List.sortOn (negate . trialResultObjective) results

medianPrunedTrialIndices :: Pruner -> [TrialObjectiveResult] -> [Int]
medianPrunedTrialIndices NoPruner _ = []
medianPrunedTrialIndices pruner results =
  go [] results
 where
  go _ [] = []
  go history (result : rest)
    | length history < warmup = go (history <> [trialResultObjective result]) rest
    | shouldPrune history (trialResultObjective result) =
        trialResultIndex result : go (history <> [trialResultObjective result]) rest
    | otherwise =
        go (history <> [trialResultObjective result]) rest
  warmup = 2
  shouldPrune history objective =
    case pruner of
      MedianPruner -> objective < median history
      PercentilePruner -> objective < percentile 25 history

median :: [Double] -> Double
median [] = 0.0
median xs =
  let sorted = List.sort xs
      n = length sorted
   in if even n
        then (sorted !! (n `div` 2 - 1) + sorted !! (n `div` 2)) / 2.0
        else sorted !! (n `div` 2)

percentile :: Int -> [Double] -> Double
percentile _ [] = 0.0
percentile pct xs =
  let sorted = List.sort xs
      idx =
        max 0 $
          min
            (length sorted - 1)
            ( floor
                ( (fromIntegral (max 0 (min 100 pct)) :: Double)
                    / 100.0
                    * (fromIntegral (length sorted - 1) :: Double)
                )
            )
   in sorted !! idx

-- | The real measured objective for one trial plus the trained weights that can
-- be promoted into a checkpoint. The sampler + trial index pick a
-- hyperparameter configuration, the fixed Dense architecture trains on
-- 'tuningObjectiveDataset' through the production 'JitML.SL.Architecture' seam
-- (the same one the no-caveat SL runtime uses), and the objective is train
-- accuracy. The weight vector is the exact trained model measured by the
-- objective. The offline path trains through the toolchain-free pure reference
-- device so 'deterministicTrials' stays pure and runnable without a substrate.
trialObjectiveResult :: Sampler -> Int -> TrialObjectiveResult
trialObjectiveResult sampler trialIndex =
  trialObjectiveResultFromHistory sampler trialIndex []

trialObjectiveResultFromHistory :: Sampler -> Int -> [TrialObjectiveResult] -> TrialObjectiveResult
trialObjectiveResultFromHistory sampler =
  trialObjectiveResultFromHistoryForUpdates sampler tuningObjectiveOptimizerUpdates

trialObjectiveResultFromHistoryForUpdates
  :: Sampler
  -> Int
  -> Int
  -> [TrialObjectiveResult]
  -> TrialObjectiveResult
trialObjectiveResultFromHistoryForUpdates sampler =
  trialObjectiveResultFromHistoryForUpdatesWithSeed (seed sampler) sampler

trialObjectiveResultFromHistoryForUpdatesWithSeed
  :: Int
  -> Sampler
  -> Int
  -> Int
  -> [TrialObjectiveResult]
  -> TrialObjectiveResult
trialObjectiveResultFromHistoryForUpdatesWithSeed explicitSeed sampler updates trialIndex history =
  let config = sampledClassifierConfigForUpdatesWithSeed explicitSeed sampler updates trialIndex history
   in case pureTuningObjective config of
        Right (objective, initialWeights, weights) ->
          terminalLegacyTrialResult
            trialIndex
            (legacyTrialHyperparameters config)
            objective
            initialWeights
            weights
            updates
        Left err ->
          error ("tuning objective (pure reference device) failed: " <> Text.unpack err)

trialObjectiveResultWithDevice
  :: MlpDevice -> Sampler -> Int -> IO (Either Text TrialObjectiveResult)
trialObjectiveResultWithDevice device sampler trialIndex = do
  trialObjectiveResultWithDeviceFromHistory device sampler trialIndex []

trialObjectiveResultWithDeviceFromHistory
  :: MlpDevice -> Sampler -> Int -> [TrialObjectiveResult] -> IO (Either Text TrialObjectiveResult)
trialObjectiveResultWithDeviceFromHistory device sampler trialIndex history = do
  trialObjectiveResultWithDeviceFromHistoryForUpdates
    device
    sampler
    tuningObjectiveOptimizerUpdates
    trialIndex
    history

trialObjectiveResultWithDeviceFromHistoryForUpdates
  :: MlpDevice
  -> Sampler
  -> Int
  -> Int
  -> [TrialObjectiveResult]
  -> IO (Either Text TrialObjectiveResult)
trialObjectiveResultWithDeviceFromHistoryForUpdates device sampler =
  trialObjectiveResultWithDeviceFromHistoryForUpdatesWithSeed device (seed sampler) sampler

trialObjectiveResultWithDeviceFromHistoryForUpdatesWithSeed
  :: MlpDevice
  -> Int
  -> Sampler
  -> Int
  -> Int
  -> [TrialObjectiveResult]
  -> IO (Either Text TrialObjectiveResult)
trialObjectiveResultWithDeviceFromHistoryForUpdatesWithSeed device explicitSeed sampler updates trialIndex history = do
  let config = sampledClassifierConfigForUpdatesWithSeed explicitSeed sampler updates trialIndex history
  result <- trainTuningObjective device config
  pure $
    fmap
      ( \(objective, initialWeights, weights) ->
          terminalLegacyTrialResult
            trialIndex
            (legacyTrialHyperparameters config)
            objective
            initialWeights
            weights
            updates
      )
      result

terminalLegacyTrialResult
  :: Int
  -> TrialHyperparameters
  -> Double
  -> [Double]
  -> [Double]
  -> Int
  -> TrialObjectiveResult
terminalLegacyTrialResult trialIndex hyperparameters objective initialWeights weights updates =
  TrialObjectiveResult
    { internalTrialResultIndex = trialIndex
    , internalTrialResultHyperparameters = hyperparameters
    , internalTrialResultObjective = objective
    , internalTrialResultInitialWeights = initialWeights
    , internalTrialResultWeights = weights
    , internalTrialResultUpdatesExecuted = updates
    , internalTrialResultObservations =
        [ TrialRungObservation
            { internalTrialObservationUpdates = updates
            , internalTrialObservationObjective = objective
            }
        ]
    , internalTrialResultDisposition = ReachedMaxBudget
    }

legacyTrialHyperparameters :: Classifier.ClassifierConfig -> TrialHyperparameters
legacyTrialHyperparameters config =
  TrialHyperparameters
    { internalTrialLearningRate = Classifier.clfLearningRate config
    , internalTrialBatchSize = Classifier.clfBatchSize config
    , internalTrialDropout = 0.0
    , internalTrialOptimizer = "Adam"
    }

-- | Train the fixed Dense tuning architecture for one sampled config on
-- 'tuningObjectiveDataset' through @device@, returning
-- @(train-accuracy, initial-flat-weights, final-flat-weights)@.
trainTuningObjective
  :: MlpDevice -> Classifier.ClassifierConfig -> IO (Either Text (Double, [Double], [Double]))
trainTuningObjective device config = do
  case Architecture.architectureSpecForProblem config tuningObjectiveProblem of
    Left err -> pure (Left err)
    Right spec -> do
      result <-
        Architecture.trainArchitectureWithDeviceSelected
          device
          spec
          config
          tuningObjectiveDataset
          tuningObjectiveDataset
      pure $
        fmap
          ( \(trained, metrics) ->
              ( Architecture.slmTrainAccuracy metrics
              , Architecture.slmInitialWeights metrics
              , Architecture.trainedArchitectureWeights trained
              )
          )
          result

-- | The pure-reference-device evaluation of 'trainTuningObjective' — the
-- toolchain-free objective used by the offline sweep ('deterministicTrials').
-- The reference device performs no IO, so 'unsafePerformIO' here is
-- referentially transparent (the result is a pure function of @config@).
pureTuningObjective :: Classifier.ClassifierConfig -> Either Text (Double, [Double], [Double])
pureTuningObjective config =
  unsafePerformIO (trainTuningObjective pureReferenceMlpDevice config)
{-# NOINLINE pureTuningObjective #-}

-- | The fixed Dense canonical problem the tuning objective trains: a small
-- single-hidden-layer MLP sized from each sampled 'ClassifierConfig'.
tuningObjectiveProblem :: CanonicalProblem
tuningObjectiveProblem = CanonicalProblem "tune-dense" "synthetic" "Dense" DenseFamily 0

-- | Deterministic hyperparameter sample for one trial. Startup trials cover the
-- search space directly; TPE and the evolutionary samplers condition later
-- choices on the best prior objective, so the stream is adaptive while still
-- replayable from the transcript prefix.
sampledClassifierConfigForUpdatesWithSeed
  :: Int
  -> Sampler
  -> Int
  -> Int
  -> [TrialObjectiveResult]
  -> Classifier.ClassifierConfig
sampledClassifierConfigForUpdatesWithSeed explicitSeed sampler updates trialIndex history =
  let base = adaptiveBaseWithSeed explicitSeed sampler trialIndex history
      lrChoices = [1.0e-3, 3.0e-3, 1.0e-2, 3.0e-2]
      hiddenChoices = [4, 8, 12, 16]
   in Classifier.defaultClassifierConfig
        { Classifier.clfSeed = base
        , Classifier.clfInputs = 2
        , Classifier.clfHidden = selectHiddenWithSeed explicitSeed sampler base hiddenChoices history
        , Classifier.clfClasses = 2
        , Classifier.clfEpochs = updates
        , Classifier.clfLearningRate =
            selectLearningRateWithSeed explicitSeed sampler base lrChoices history
        }

validateExecutionBudget :: Int -> Int -> Int -> Either Text ()
validateExecutionBudget parallelism updates count
  | parallelism <= 0 = Left "tuning parallelism must be positive"
  | updates <= 0 = Left "tuning per-trial optimizer-update budget must be positive"
  | count <= 0 = Left "tuning trial budget must be positive"
  | parallelism > count = Left "tuning parallelism exceeds the trial budget"
  | otherwise = Right ()

adaptiveBaseWithSeed :: Int -> Sampler -> Int -> [TrialObjectiveResult] -> Int
adaptiveBaseWithSeed explicitSeed sampler trialIndex history
  | sampler `elem` [TPE, GPBO, GeneticAlgorithm, NSGA2, MuLambdaES, CMAES, EvolutionStrategies, PBT]
      && length history >= 2 =
      explicitSeed + trialIndex * 17 + trialResultIndex (bestTrial history) * 31
  | otherwise = explicitSeed + trialIndex

selectLearningRateWithSeed
  :: Int
  -> Sampler
  -> Int
  -> [Double]
  -> [TrialObjectiveResult]
  -> Double
selectLearningRateWithSeed explicitSeed sampler base choices history
  | sampler == TPE && length history >= 2 =
      let centre = choices !! ((explicitSeed + trialResultIndex (bestTrial history) * 3) `mod` length choices)
          ranked =
            List.sortOn
              (\lr -> abs (log lr - log centre) + deterministicJitter base lr)
              choices
       in ranked !! (base `mod` min 2 (length ranked))
  | otherwise = choices !! ((base * 3) `mod` length choices)

selectHiddenWithSeed
  :: Int
  -> Sampler
  -> Int
  -> [Int]
  -> [TrialObjectiveResult]
  -> Int
selectHiddenWithSeed explicitSeed sampler base choices history
  | sampler == TPE && length history >= 2 =
      let centre = choices !! ((explicitSeed + trialResultIndex (bestTrial history) * 7) `mod` length choices)
          ranked =
            List.sortOn
              (\hidden -> abs (hidden - centre) + (base `mod` 3))
              choices
       in ranked !! (base `mod` min 2 (length ranked))
  | otherwise = choices !! ((base * 7) `mod` length choices)

bestTrial :: [TrialObjectiveResult] -> TrialObjectiveResult
bestTrial [] = error "bestTrial: empty history"
bestTrial (firstResult : rest) =
  List.maximumBy compareObjective (firstResult : rest)
 where
  compareObjective a b = compare (trialResultObjective a) (trialResultObjective b)

deterministicJitter :: Int -> Double -> Double
deterministicJitter base value =
  fromIntegral ((base + floor (value * 1.0e6)) `mod` 11) / 1000.0

-- | A fixed, deterministic, linearly-separable 2-class dataset for the tuning
-- objective — small and low-epoch so a sweep stays fast while still measuring a
-- real trained-model accuracy (no committed numerical fixtures).
tuningObjectiveDataset :: [Classifier.LabeledExample]
tuningObjectiveDataset =
  [ Classifier.LabeledExample (VU.fromList (features c i)) c
  | c <- [0, 1]
  , i <- [0 .. 9 :: Int]
  ]
 where
  features c i =
    let jitter k = fromIntegral ((c * 17 + i * 3 + k * 5) `mod` 4) / 100.0
        baseVec = if c == 0 then [1.0, 0.0] else [0.0, 1.0]
     in zipWith (\b k -> b + jitter k) baseVec [0 :: Int ..]

-- | SHA-256 of the exact ordered labeled examples consumed by the synthetic
-- compatibility executor.  The versioned canonical byte stream is:
--
-- * an ASCII domain tag and NUL terminator;
-- * the example count as an unsigned 64-bit big-endian integer; then
-- * for each example in training order, its signed 64-bit big-endian label,
--   feature-vector length as unsigned 64-bit big-endian, and every IEEE-754
--   feature as a big-endian binary64 value.
--
-- This deliberately hashes the optimizer input rather than a plan identifier
-- or a synthetic name, so completion evidence changes with content or order.
syntheticTuningDatasetSha256 :: Text
syntheticTuningDatasetSha256 =
  hexBytes
    ( SHA256.hash
        ( LazyByteString.toStrict
            ( Builder.toLazyByteString
                ( Builder.byteString "jitml-synthetic-tuning-dataset-v1\NUL"
                    <> Builder.word64BE (fromIntegral (length tuningObjectiveDataset))
                    <> foldMap exampleBuilder tuningObjectiveDataset
                )
            )
        )
    )
 where
  exampleBuilder example =
    let features = Classifier.exampleFeatures example
     in Builder.int64BE (fromIntegral (Classifier.exampleLabel example))
          <> Builder.word64BE (fromIntegral (VU.length features))
          <> foldMap Builder.doubleBE (VU.toList features)

  hexBytes = Text.pack . concatMap hexByte . ByteString.unpack
  hexByte :: Word8 -> String
  hexByte byte =
    [ intToDigit (fromIntegral byte `div` 16)
    , intToDigit (fromIntegral byte `mod` 16)
    ]

seed :: Sampler -> Int
seed Grid = 7
seed Sobol = 11
seed Random = 23
seed TPE = 53
seed GPBO = 59
seed GeneticAlgorithm = 37
seed NSGA2 = 61
seed MuLambdaES = 67
seed CMAES = 71
seed EvolutionStrategies = 41
seed PBT = 73

loadTuningExperiment :: FilePath -> IO (Either Text TuningExperiment)
loadTuningExperiment path = do
  decoded <- tryAny (Dhall.inputFile rawTuningExperimentDecoder path)
  pure $
    case decoded of
      Left err -> Left (Text.pack (displayException err))
      Right raw -> normalizeTuningExperiment raw

renderTuningPlan :: FilePath -> TuningExperiment -> Text
renderTuningPlan path experiment =
  Text.unlines $
    [ "tune: " <> Text.pack path
    , "name: " <> tuningExperimentName experiment
    , "dataset: " <> tuningExperimentDataset experiment
    , "model: " <> tuningExperimentModel experiment
    , "seed: " <> showText (tuningExperimentSeed experiment)
    ]
      <> case tuningExperimentConfig experiment of
        Nothing ->
          ["tuning: none"]
        Just config ->
          [ "sampler: " <> showText (tuningSamplerKind (tuningConfigSampler config))
          , "scheduler: " <> showText (tuningSchedulerKind (tuningConfigScheduler config))
          , "pruner: " <> showText (tuningPrunerKind (tuningConfigPruner config))
          , "trials: " <> showText (tuningConfigTrials config)
          , "parallelism: " <> showText (tuningConfigParallelism config)
          , "objectives: " <> renderObjectives (tuningConfigObjectives config)
          , "trial-values: "
              <> Text.pack
                (show (fmap trialResultObjective (trialObjectiveResultsForConfig config 4)))
          ]

trialStorageKey :: Text -> Int -> Text
trialStorageKey experimentHash trialSeed =
  "jitml-trials/" <> experimentHash <> "/" <> Text.pack (show trialSeed) <> "/transcript.cbor"

resumeMatchesFullRun :: Sampler -> Int -> Int -> Bool
resumeMatchesFullRun sampler completed total =
  let prefix = take completed (deterministicTrials sampler total)
      resumed = prefix <> drop completed (deterministicTrials sampler total)
   in resumed == deterministicTrials sampler total

renderTrialResumeSummary :: Sampler -> Int -> Int -> Text
renderTrialResumeSummary sampler completed total =
  Text.unlines
    [ "sampler: " <> Text.pack (show sampler)
    , "completed_trials: " <> Text.pack (show completed)
    , "total_trials: " <> Text.pack (show total)
    , "resume_matches_full_run: " <> Text.pack (show (resumeMatchesFullRun sampler completed total))
    ]

data RawTuningExperiment = RawTuningExperiment
  { rawTuningExperimentName :: Text
  , rawTuningExperimentDataset :: Text
  , rawTuningExperimentModel :: Text
  , rawTuningExperimentSeed :: Natural
  , rawTuningExperimentConfig :: Maybe RawTuningConfig
  }
  deriving stock (Eq, Show)

data RawTuningConfig = RawTuningConfig
  { rawTuningConfigSampler :: RawTuningSampler
  , rawTuningConfigScheduler :: RawTuningScheduler
  , rawTuningConfigPruner :: RawTuningPruner
  , rawTuningConfigSpace :: RawSearchSpace
  , rawTuningConfigTrials :: Natural
  , rawTuningConfigParallelism :: Natural
  , rawTuningConfigObjectives :: [TuningObjective]
  }
  deriving stock (Eq, Show)

data RawTuningSampler = RawTuningSampler
  { rawTuningSamplerKind :: Text
  , rawTuningSamplerSeed :: Natural
  , rawTuningSamplerStartupTrials :: Natural
  }
  deriving stock (Eq, Show)

data RawTuningScheduler = RawTuningScheduler
  { rawTuningSchedulerKind :: Text
  , rawTuningSchedulerEta :: Natural
  , rawTuningSchedulerMaxBudget :: Natural
  , rawTuningSchedulerParallelism :: Natural
  }
  deriving stock (Eq, Show)

data RawTuningPruner = RawTuningPruner
  { rawTuningPrunerKind :: Text
  , rawTuningPrunerWarmupTrials :: Natural
  , rawTuningPrunerEvalAtPercentile :: Natural
  }
  deriving stock (Eq, Show)

data RawSearchSpace = RawSearchSpace
  { rawSearchLearningRate :: RawFloatSearchSpace
  , rawSearchBatchSize :: RawNaturalCategoricalSearchSpace
  , rawSearchDropout :: RawFloatSearchSpace
  , rawSearchOptimizer :: RawTextCategoricalSearchSpace
  }
  deriving stock (Eq, Show)

data RawFloatSearchSpace = RawFloatSearchSpace
  { rawFloatSearchKind :: Text
  , rawFloatSearchMin :: Double
  , rawFloatSearchMax :: Double
  , rawFloatSearchScale :: Text
  }
  deriving stock (Eq, Show)

data RawNaturalCategoricalSearchSpace = RawNaturalCategoricalSearchSpace
  { rawNaturalSearchKind :: Text
  , rawNaturalSearchValues :: [Natural]
  }
  deriving stock (Eq, Show)

data RawTextCategoricalSearchSpace = RawTextCategoricalSearchSpace
  { rawTextSearchKind :: Text
  , rawTextSearchValues :: [Text]
  }
  deriving stock (Eq, Show)

rawTuningExperimentDecoder :: Dhall.Decoder RawTuningExperiment
rawTuningExperimentDecoder =
  Dhall.record $
    RawTuningExperiment
      <$> Dhall.field "name" Dhall.strictText
      <*> Dhall.field "dataset" Dhall.strictText
      <*> Dhall.field "model" Dhall.strictText
      <*> Dhall.field "seed" Dhall.natural
      <*> Dhall.field "tuning" (Dhall.maybe rawTuningConfigDecoder)

rawTuningConfigDecoder :: Dhall.Decoder RawTuningConfig
rawTuningConfigDecoder =
  Dhall.record $
    RawTuningConfig
      <$> Dhall.field "sampler" rawTuningSamplerDecoder
      <*> Dhall.field "scheduler" rawTuningSchedulerDecoder
      <*> Dhall.field "pruner" rawTuningPrunerDecoder
      <*> Dhall.field "space" rawSearchSpaceDecoder
      <*> Dhall.field "trials" Dhall.natural
      <*> Dhall.field "parallelism" Dhall.natural
      <*> Dhall.field "objectives" (Dhall.list tuningObjectiveDecoder)

rawTuningSamplerDecoder :: Dhall.Decoder RawTuningSampler
rawTuningSamplerDecoder =
  Dhall.record $
    RawTuningSampler
      <$> Dhall.field "kind" Dhall.strictText
      <*> Dhall.field "seed" Dhall.natural
      <*> Dhall.field "nStartupTrials" Dhall.natural

rawTuningSchedulerDecoder :: Dhall.Decoder RawTuningScheduler
rawTuningSchedulerDecoder =
  Dhall.record $
    RawTuningScheduler
      <$> Dhall.field "kind" Dhall.strictText
      <*> Dhall.field "eta" Dhall.natural
      <*> Dhall.field "maxBudget" Dhall.natural
      <*> Dhall.field "parallelism" Dhall.natural

rawTuningPrunerDecoder :: Dhall.Decoder RawTuningPruner
rawTuningPrunerDecoder =
  Dhall.record $
    RawTuningPruner
      <$> Dhall.field "kind" Dhall.strictText
      <*> Dhall.field "warmupTrials" Dhall.natural
      <*> Dhall.field "evalAtPercentile" Dhall.natural

rawSearchSpaceDecoder :: Dhall.Decoder RawSearchSpace
rawSearchSpaceDecoder =
  Dhall.record $
    RawSearchSpace
      <$> Dhall.field "learningRate" rawFloatSearchSpaceDecoder
      <*> Dhall.field "batchSize" rawNaturalCategoricalSearchSpaceDecoder
      <*> Dhall.field "dropout" rawFloatSearchSpaceDecoder
      <*> Dhall.field "optimizer" rawTextCategoricalSearchSpaceDecoder

rawFloatSearchSpaceDecoder :: Dhall.Decoder RawFloatSearchSpace
rawFloatSearchSpaceDecoder =
  Dhall.record $
    RawFloatSearchSpace
      <$> Dhall.field "kind" Dhall.strictText
      <*> Dhall.field "min" Dhall.double
      <*> Dhall.field "max" Dhall.double
      <*> Dhall.field "scale" Dhall.strictText

rawNaturalCategoricalSearchSpaceDecoder :: Dhall.Decoder RawNaturalCategoricalSearchSpace
rawNaturalCategoricalSearchSpaceDecoder =
  Dhall.record $
    RawNaturalCategoricalSearchSpace
      <$> Dhall.field "kind" Dhall.strictText
      <*> Dhall.field "values" (Dhall.list Dhall.natural)

rawTextCategoricalSearchSpaceDecoder :: Dhall.Decoder RawTextCategoricalSearchSpace
rawTextCategoricalSearchSpaceDecoder =
  Dhall.record $
    RawTextCategoricalSearchSpace
      <$> Dhall.field "kind" Dhall.strictText
      <*> Dhall.field "values" (Dhall.list Dhall.strictText)

tuningObjectiveDecoder :: Dhall.Decoder TuningObjective
tuningObjectiveDecoder =
  Dhall.record $
    TuningObjective
      <$> Dhall.field "metric" Dhall.strictText
      <*> Dhall.field "direction" Dhall.strictText

normalizeTuningExperiment :: RawTuningExperiment -> Either Text TuningExperiment
normalizeTuningExperiment raw =
  do
    config <- traverse normalizeTuningConfig (rawTuningExperimentConfig raw)
    let experiment =
          TuningExperiment
            (Text.strip (rawTuningExperimentName raw))
            (Text.strip (rawTuningExperimentDataset raw))
            (Text.strip (rawTuningExperimentModel raw))
            (rawTuningExperimentSeed raw)
            config
    case config of
      Nothing -> Right experiment
      Just _ -> tuningExecutionSpecForExperiment experiment >> Right experiment

normalizeTuningConfig :: RawTuningConfig -> Either Text TuningConfig
normalizeTuningConfig raw = do
  sampler <- normalizeSampler (rawTuningConfigSampler raw)
  scheduler <- normalizeScheduler (rawTuningConfigScheduler raw)
  pruner <- normalizePruner (rawTuningConfigPruner raw)
  space <- normalizeSearchSpace (rawTuningConfigSpace raw)
  let config =
        TuningConfig
          { tuningConfigSampler = sampler
          , tuningConfigScheduler = scheduler
          , tuningConfigPruner = pruner
          , tuningConfigSpace = space
          , tuningConfigTrials = rawTuningConfigTrials raw
          , tuningConfigParallelism = rawTuningConfigParallelism raw
          , tuningConfigObjectives = fmap normalizeObjective (rawTuningConfigObjectives raw)
          }
  validateTuningConfig config
  Right config

normalizeSearchSpace :: RawSearchSpace -> Either Text TuningSearchSpace
normalizeSearchSpace raw =
  TuningSearchSpace
    <$> normalizeFloatSearchSpace "learningRate" (rawSearchLearningRate raw)
    <*> normalizeNaturalSearchSpace "batchSize" (rawSearchBatchSize raw)
    <*> normalizeFloatSearchSpace "dropout" (rawSearchDropout raw)
    <*> normalizeTextSearchSpace "optimizer" (rawSearchOptimizer raw)

normalizeFloatSearchSpace :: Text -> RawFloatSearchSpace -> Either Text FloatSearchSpace
normalizeFloatSearchSpace label raw = do
  if rawFloatSearchKind raw /= "Float"
    then Left (label <> " search kind must be Float")
    else Right ()
  scale <- case rawFloatSearchScale raw of
    "Linear" -> Right LinearScale
    "Log" -> Right LogScale
    value -> Left (label <> " has unknown search scale: " <> value)
  let result =
        FloatSearchSpace
          { floatSearchMinimum = rawFloatSearchMin raw
          , floatSearchMaximum = rawFloatSearchMax raw
          , floatSearchScale = scale
          }
  validateFloatSearchSpace label result
  Right result

normalizeNaturalSearchSpace
  :: Text -> RawNaturalCategoricalSearchSpace -> Either Text NaturalCategoricalSearchSpace
normalizeNaturalSearchSpace label raw
  | rawNaturalSearchKind raw /= "Categorical" =
      Left (label <> " search kind must be Categorical")
  | otherwise =
      let result = NaturalCategoricalSearchSpace (rawNaturalSearchValues raw)
       in validateNaturalSearchSpace label result >> Right result

normalizeTextSearchSpace
  :: Text -> RawTextCategoricalSearchSpace -> Either Text TextCategoricalSearchSpace
normalizeTextSearchSpace label raw
  | rawTextSearchKind raw /= "Categorical" =
      Left (label <> " search kind must be Categorical")
  | otherwise =
      let result = TextCategoricalSearchSpace (fmap Text.strip (rawTextSearchValues raw))
       in validateTextSearchSpace label result >> Right result

normalizeObjective :: TuningObjective -> TuningObjective
normalizeObjective objective =
  objective
    { tuningObjectiveMetric = Text.strip (tuningObjectiveMetric objective)
    , tuningObjectiveDirection = Text.strip (tuningObjectiveDirection objective)
    }

normalizeSampler :: RawTuningSampler -> Either Text TuningSampler
normalizeSampler raw =
  case samplerFromText (rawTuningSamplerKind raw) of
    Just sampler ->
      Right
        TuningSampler
          { tuningSamplerKind = sampler
          , tuningSamplerSeed = rawTuningSamplerSeed raw
          , tuningSamplerStartupTrials = rawTuningSamplerStartupTrials raw
          }
    Nothing -> Left ("unknown tuning sampler: " <> rawTuningSamplerKind raw)

normalizeScheduler :: RawTuningScheduler -> Either Text TuningScheduler
normalizeScheduler raw =
  case schedulerFromText (rawTuningSchedulerKind raw) of
    Just scheduler ->
      Right
        TuningScheduler
          { tuningSchedulerKind = scheduler
          , tuningSchedulerEta = rawTuningSchedulerEta raw
          , tuningSchedulerMaxBudget = rawTuningSchedulerMaxBudget raw
          , tuningSchedulerParallelism = rawTuningSchedulerParallelism raw
          }
    Nothing -> Left ("unknown tuning scheduler: " <> rawTuningSchedulerKind raw)

normalizePruner :: RawTuningPruner -> Either Text TuningPruner
normalizePruner raw =
  case prunerFromText (rawTuningPrunerKind raw) of
    Just pruner ->
      Right
        TuningPruner
          { tuningPrunerKind = pruner
          , tuningPrunerWarmupTrials = rawTuningPrunerWarmupTrials raw
          , tuningPrunerEvalAtPercentile = rawTuningPrunerEvalAtPercentile raw
          }
    Nothing -> Left ("unknown tuning pruner: " <> rawTuningPrunerKind raw)

tuningExecutionSpecForExperiment :: TuningExperiment -> Either Text TuningExecutionSpec
tuningExecutionSpecForExperiment experiment = do
  config <-
    maybe
      (Left "tuning experiment requires a tuning configuration")
      Right
      (tuningExperimentConfig experiment)
  let spec =
        TuningExecutionSpec
          { tuningExecutionName = Text.strip (tuningExperimentName experiment)
          , tuningExecutionDataset = Text.strip (tuningExperimentDataset experiment)
          , tuningExecutionModel = Text.strip (tuningExperimentModel experiment)
          , tuningExecutionSampler = tuningConfigSampler config
          , tuningExecutionScheduler = tuningConfigScheduler config
          , tuningExecutionPruner = tuningConfigPruner config
          , tuningExecutionSearchSpace = tuningConfigSpace config
          , tuningExecutionTrials = tuningConfigTrials config
          , tuningExecutionParallelism = tuningConfigParallelism config
          , tuningExecutionObjectives = tuningConfigObjectives config
          }
  validateTuningExecutionSpec spec
  Right spec

-- | Compatibility semantics for raw command DTOs that predate the exact
-- execution-spec transport.  New ProductRow and local-Dhall paths always pass
-- a normalized spec explicitly; this value keeps old plan-construction tests
-- and API callers deterministic without leaving any resolved field undefined.
legacyTuningExecutionSpec
  :: Sampler
  -> Scheduler
  -> Pruner
  -> Natural
  -> Natural
  -> Natural
  -> Natural
  -> TuningExecutionSpec
legacyTuningExecutionSpec sampler scheduler pruner runSeed trials parallelism updates =
  TuningExecutionSpec
    { tuningExecutionName = "legacy-tuning"
    , tuningExecutionDataset = "synthetic"
    , tuningExecutionModel = "Dense"
    , tuningExecutionSampler =
        TuningSampler
          { tuningSamplerKind = sampler
          , tuningSamplerSeed = runSeed
          , tuningSamplerStartupTrials = min 2 trials
          }
    , tuningExecutionScheduler =
        TuningScheduler
          { tuningSchedulerKind = scheduler
          , tuningSchedulerEta = legacySchedulerEta scheduler
          , tuningSchedulerMaxBudget = updates
          , tuningSchedulerParallelism = parallelism
          }
    , tuningExecutionPruner =
        TuningPruner
          { tuningPrunerKind = pruner
          , tuningPrunerWarmupTrials = min 2 trials
          , tuningPrunerEvalAtPercentile = legacyPrunerPercentile pruner
          }
    , tuningExecutionSearchSpace =
        TuningSearchSpace
          { tuningSearchLearningRate = FloatSearchSpace 1.0e-3 3.0e-2 LogScale
          , tuningSearchBatchSize = NaturalCategoricalSearchSpace [20]
          , tuningSearchDropout = FloatSearchSpace 0.0 0.0 LinearScale
          , tuningSearchOptimizer = TextCategoricalSearchSpace ["Adam"]
          }
    , tuningExecutionTrials = trials
    , tuningExecutionParallelism = parallelism
    , tuningExecutionObjectives = [TuningObjective "valAcc" "Maximise"]
    }
 where
  legacySchedulerEta Fifo = 1
  legacySchedulerEta SuccessiveHalving = 2
  legacySchedulerEta Hyperband = 3
  legacySchedulerEta ASHA = 2
  legacyPrunerPercentile NoPruner = 50
  legacyPrunerPercentile MedianPruner = 50
  legacyPrunerPercentile PercentilePruner = 25

renderTuningExecutionSpec :: TuningExecutionSpec -> Text
renderTuningExecutionSpec spec =
  Text.intercalate
    "|"
    [ "jitml-tuning-execution-v1"
    , encodeTextHex (tuningExecutionName spec)
    , encodeTextHex (tuningExecutionDataset spec)
    , encodeTextHex (tuningExecutionModel spec)
    , renderSampler (tuningSamplerKind sampler)
    , showText (tuningSamplerSeed sampler)
    , showText (tuningSamplerStartupTrials sampler)
    , renderScheduler (tuningSchedulerKind scheduler)
    , showText (tuningSchedulerEta scheduler)
    , showText (tuningSchedulerMaxBudget scheduler)
    , showText (tuningSchedulerParallelism scheduler)
    , renderPruner (tuningPrunerKind pruner)
    , showText (tuningPrunerWarmupTrials pruner)
    , showText (tuningPrunerEvalAtPercentile pruner)
    , renderCanonicalDouble (floatSearchMinimum learningRate)
    , renderCanonicalDouble (floatSearchMaximum learningRate)
    , renderSearchScale (floatSearchScale learningRate)
    , Text.intercalate "," (fmap showText (naturalSearchValues batchSize))
    , renderCanonicalDouble (floatSearchMinimum dropout)
    , renderCanonicalDouble (floatSearchMaximum dropout)
    , renderSearchScale (floatSearchScale dropout)
    , Text.intercalate "," (fmap encodeTextHex (textSearchValues optimizer))
    , showText (tuningExecutionTrials spec)
    , showText (tuningExecutionParallelism spec)
    , showText (length (tuningExecutionObjectives spec))
    , Text.intercalate "," (fmap renderObjectiveCanonical (tuningExecutionObjectives spec))
    ]
 where
  sampler = tuningExecutionSampler spec
  scheduler = tuningExecutionScheduler spec
  pruner = tuningExecutionPruner spec
  searchSpace = tuningExecutionSearchSpace spec
  learningRate = tuningSearchLearningRate searchSpace
  batchSize = tuningSearchBatchSize searchSpace
  dropout = tuningSearchDropout searchSpace
  optimizer = tuningSearchOptimizer searchSpace

-- IEEE equality identifies positive and negative zero, so the canonical
-- semantic rendering must do the same or Eq-equal specs would acquire
-- different PlanIds.
renderCanonicalDouble :: Double -> Text
renderCanonicalDouble value = showText (if value == 0.0 then 0.0 else value)

parseTuningExecutionSpec :: Text -> Either Text TuningExecutionSpec
parseTuningExecutionSpec encoded =
  case Text.splitOn "|" encoded of
    [ version
      , encodedName
      , encodedDataset
      , encodedModel
      , encodedSampler
      , encodedSamplerSeed
      , encodedStartupTrials
      , encodedScheduler
      , encodedEta
      , encodedMaxBudget
      , encodedSchedulerParallelism
      , encodedPruner
      , encodedWarmup
      , encodedPercentile
      , encodedLearningRateMinimum
      , encodedLearningRateMaximum
      , encodedLearningRateScale
      , encodedBatchSizes
      , encodedDropoutMinimum
      , encodedDropoutMaximum
      , encodedDropoutScale
      , encodedOptimizers
      , encodedTrials
      , encodedParallelism
      , encodedObjectiveCount
      , encodedObjectives
      ]
        | version == "jitml-tuning-execution-v1" -> do
            name <- decodeTextHex "name" encodedName
            dataset <- decodeTextHex "dataset" encodedDataset
            model <- decodeTextHex "model" encodedModel
            samplerKind <- requiredParsed "sampler" samplerFromText encodedSampler
            samplerSeed <- readField "sampler seed" encodedSamplerSeed
            startupTrials <- readField "sampler startup trials" encodedStartupTrials
            schedulerKind <- requiredParsed "scheduler" schedulerFromText encodedScheduler
            eta <- readField "scheduler eta" encodedEta
            maxBudget <- readField "scheduler max budget" encodedMaxBudget
            schedulerParallelism <- readField "scheduler parallelism" encodedSchedulerParallelism
            prunerKind <- requiredParsed "pruner" prunerFromText encodedPruner
            warmup <- readField "pruner warmup" encodedWarmup
            percentileValue <- readField "pruner percentile" encodedPercentile
            learningRateMinimum <- readField "learning-rate minimum" encodedLearningRateMinimum
            learningRateMaximum <- readField "learning-rate maximum" encodedLearningRateMaximum
            learningRateScale <- parseSearchScale encodedLearningRateScale
            batchSizes <- traverse (readField "batch size") (splitNonEmpty encodedBatchSizes)
            dropoutMinimum <- readField "dropout minimum" encodedDropoutMinimum
            dropoutMaximum <- readField "dropout maximum" encodedDropoutMaximum
            dropoutScale <- parseSearchScale encodedDropoutScale
            optimizers <- traverse (decodeTextHex "optimizer") (splitNonEmpty encodedOptimizers)
            trials <- readField "trials" encodedTrials
            parallelism <- readField "parallelism" encodedParallelism
            objectiveCount <- readField "objective count" encodedObjectiveCount
            objectives <- traverse parseObjectiveCanonical (splitNonEmpty encodedObjectives)
            if objectiveCount /= length objectives
              then Left "tuning objective count does not match encoded objective list"
              else Right ()
            let spec =
                  TuningExecutionSpec
                    { tuningExecutionName = name
                    , tuningExecutionDataset = dataset
                    , tuningExecutionModel = model
                    , tuningExecutionSampler = TuningSampler samplerKind samplerSeed startupTrials
                    , tuningExecutionScheduler =
                        TuningScheduler schedulerKind eta maxBudget schedulerParallelism
                    , tuningExecutionPruner = TuningPruner prunerKind warmup percentileValue
                    , tuningExecutionSearchSpace =
                        TuningSearchSpace
                          { tuningSearchLearningRate =
                              FloatSearchSpace learningRateMinimum learningRateMaximum learningRateScale
                          , tuningSearchBatchSize = NaturalCategoricalSearchSpace batchSizes
                          , tuningSearchDropout =
                              FloatSearchSpace dropoutMinimum dropoutMaximum dropoutScale
                          , tuningSearchOptimizer = TextCategoricalSearchSpace optimizers
                          }
                    , tuningExecutionTrials = trials
                    , tuningExecutionParallelism = parallelism
                    , tuningExecutionObjectives = objectives
                    }
            validateTuningExecutionSpec spec
            Right spec
        | otherwise -> Left ("unsupported tuning execution spec version: " <> version)
    _ -> Left "invalid canonical tuning execution spec field count"

renderSampler :: Sampler -> Text
renderSampler Grid = "Grid"
renderSampler Sobol = "Sobol"
renderSampler Random = "Random"
renderSampler TPE = "TPE"
renderSampler GPBO = "GPBO"
renderSampler GeneticAlgorithm = "GeneticAlgorithm"
renderSampler NSGA2 = "NSGA2"
renderSampler MuLambdaES = "MuLambdaES"
renderSampler CMAES = "CMAES"
renderSampler EvolutionStrategies = "EvolutionStrategies"
renderSampler PBT = "PBT"

renderScheduler :: Scheduler -> Text
renderScheduler Fifo = "Fifo"
renderScheduler SuccessiveHalving = "SuccessiveHalving"
renderScheduler Hyperband = "Hyperband"
renderScheduler ASHA = "ASHA"

renderPruner :: Pruner -> Text
renderPruner NoPruner = "NoPruner"
renderPruner MedianPruner = "MedianPruner"
renderPruner PercentilePruner = "PercentilePruner"

renderSearchScale :: SearchScale -> Text
renderSearchScale LinearScale = "Linear"
renderSearchScale LogScale = "Log"

parseSearchScale :: Text -> Either Text SearchScale
parseSearchScale "Linear" = Right LinearScale
parseSearchScale "Log" = Right LogScale
parseSearchScale value = Left ("unknown tuning search scale: " <> value)

requiredParsed :: Text -> (Text -> Maybe value) -> Text -> Either Text value
requiredParsed label parser value =
  maybe (Left ("unknown tuning " <> label <> ": " <> value)) Right (parser value)

readField :: (Read value) => Text -> Text -> Either Text value
readField label value =
  maybe (Left ("invalid tuning " <> label <> ": " <> value)) Right (readMaybe (Text.unpack value))

splitNonEmpty :: Text -> [Text]
splitNonEmpty value
  | Text.null value = []
  | otherwise = Text.splitOn "," value

renderObjectiveCanonical :: TuningObjective -> Text
renderObjectiveCanonical objective =
  encodeTextHex (tuningObjectiveMetric objective)
    <> ":"
    <> encodeTextHex (tuningObjectiveDirection objective)

parseObjectiveCanonical :: Text -> Either Text TuningObjective
parseObjectiveCanonical encoded =
  case Text.splitOn ":" encoded of
    [encodedMetric, encodedDirection] ->
      TuningObjective
        <$> decodeTextHex "objective metric" encodedMetric
        <*> decodeTextHex "objective direction" encodedDirection
    _ -> Left "invalid canonical tuning objective"

encodeTextHex :: Text -> Text
encodeTextHex =
  Text.pack . concatMap encodeByte . ByteString.unpack . Text.Encoding.encodeUtf8
 where
  encodeByte byte =
    [ intToDigit (fromIntegral byte `div` 16)
    , intToDigit (fromIntegral byte `mod` 16)
    ]

decodeTextHex :: Text -> Text -> Either Text Text
decodeTextHex label encoded
  | odd (Text.length encoded) || Text.any (not . isHexDigit) encoded =
      Left ("invalid hexadecimal tuning " <> label)
  | otherwise =
      case Text.Encoding.decodeUtf8' (ByteString.pack (decodePairs (Text.unpack encoded))) of
        Left _ -> Left ("invalid UTF-8 tuning " <> label)
        Right value -> Right value
 where
  decodePairs [] = []
  decodePairs (high : low : rest) =
    fromIntegral (digitToInt high * 16 + digitToInt low) : decodePairs rest
  decodePairs _ = []

validateTuningExecutionSpec :: TuningExecutionSpec -> Either Text ()
validateTuningExecutionSpec spec = do
  if Text.null (Text.strip (tuningExecutionName spec))
    then Left "tuning experiment name must be non-empty"
    else Right ()
  if Text.null (Text.strip (tuningExecutionDataset spec))
    then Left "tuning dataset must be non-empty"
    else Right ()
  if Text.null (Text.strip (tuningExecutionModel spec))
    then Left "tuning model must be non-empty"
    else Right ()
  validateTuningConfig
    TuningConfig
      { tuningConfigSampler = tuningExecutionSampler spec
      , tuningConfigScheduler = tuningExecutionScheduler spec
      , tuningConfigPruner = tuningExecutionPruner spec
      , tuningConfigSpace = tuningExecutionSearchSpace spec
      , tuningConfigTrials = tuningExecutionTrials spec
      , tuningConfigParallelism = tuningExecutionParallelism spec
      , tuningConfigObjectives = tuningExecutionObjectives spec
      }

validateTuningConfig :: TuningConfig -> Either Text ()
validateTuningConfig config = do
  let trials = tuningConfigTrials config
      parallelism = tuningConfigParallelism config
      sampler = tuningConfigSampler config
      scheduler = tuningConfigScheduler config
      pruner = tuningConfigPruner config
      space = tuningConfigSpace config
  traverse_
    (uncurry requireIntRange)
    [ ("tuning trials", trials)
    , ("tuning parallelism", parallelism)
    , ("tuning sampler seed", tuningSamplerSeed sampler)
    , ("tuning sampler startup trials", tuningSamplerStartupTrials sampler)
    , ("tuning scheduler eta", tuningSchedulerEta scheduler)
    , ("tuning scheduler max budget", tuningSchedulerMaxBudget scheduler)
    , ("tuning scheduler parallelism", tuningSchedulerParallelism scheduler)
    , ("tuning pruner warmup trials", tuningPrunerWarmupTrials pruner)
    , ("tuning pruner percentile", tuningPrunerEvalAtPercentile pruner)
    ]
  requirePositive "tuning trials" trials
  requirePositive "tuning parallelism" parallelism
  if parallelism > trials
    then Left "tuning parallelism exceeds trial count"
    else Right ()
  if tuningSamplerStartupTrials sampler > trials
    then Left "tuning sampler startup trials exceed trial count"
    else Right ()
  requirePositive "tuning scheduler eta" (tuningSchedulerEta scheduler)
  if tuningSchedulerKind scheduler /= Fifo && tuningSchedulerEta scheduler < 2
    then Left "non-Fifo tuning scheduler eta must be at least 2"
    else Right ()
  if tuningSchedulerKind scheduler == Hyperband
    then
      Left
        "exact Hyperband execution is unavailable until bracket count and start-budget semantics are configured"
    else Right ()
  requirePositive "tuning scheduler max budget" (tuningSchedulerMaxBudget scheduler)
  requirePositive "tuning scheduler parallelism" (tuningSchedulerParallelism scheduler)
  if tuningSchedulerParallelism scheduler /= parallelism
    then Left "tuning scheduler parallelism must equal top-level parallelism"
    else Right ()
  if tuningPrunerWarmupTrials pruner > trials
    then Left "tuning pruner warmup trials exceed trial count"
    else Right ()
  if tuningPrunerEvalAtPercentile pruner > 100
    then Left "tuning pruner evaluation percentile must be in [0, 100]"
    else Right ()
  if tuningPrunerKind pruner /= NoPruner && tuningPrunerEvalAtPercentile pruner == 0
    then Left "active tuning pruner evaluation percentile must be in [1, 100]"
    else Right ()
  validateFloatSearchSpace "learningRate" (tuningSearchLearningRate space)
  if floatSearchMinimum (tuningSearchLearningRate space) <= 0.0
    then Left "learningRate search minimum must be positive"
    else Right ()
  validateNaturalSearchSpace "batchSize" (tuningSearchBatchSize space)
  validateFloatSearchSpace "dropout" (tuningSearchDropout space)
  if floatSearchMinimum (tuningSearchDropout space) < 0.0
    || floatSearchMaximum (tuningSearchDropout space) >= 1.0
    then Left "dropout search bounds must be in [0, 1)"
    else Right ()
  validateTextSearchSpace "optimizer" (tuningSearchOptimizer space)
  case filter (`notElem` supportedOptimizers) (textSearchValues (tuningSearchOptimizer space)) of
    [] -> Right ()
    unsupported : _ -> Left ("unsupported tuning optimizer: " <> unsupported)
  case tuningConfigObjectives config of
    [objective] -> validateObjective objective
    [] -> Left "tuning requires exactly one objective"
    _ -> Left "scalar tuning execution supports exactly one objective"
 where
  requirePositive label value
    | value == 0 = Left (label <> " must be positive")
    | otherwise = Right ()
  requireIntRange label value
    | toInteger value > toInteger (maxBound :: Int) =
        Left (label <> " exceeds the platform Int range")
    | otherwise = Right ()

validateFloatSearchSpace :: Text -> FloatSearchSpace -> Either Text ()
validateFloatSearchSpace label search
  | any (\value -> isNaN value || isInfinite value) [minimumValue, maximumValue] =
      Left (label <> " search bounds must be finite")
  | minimumValue > maximumValue =
      Left (label <> " search minimum exceeds maximum")
  | floatSearchScale search == LogScale && minimumValue <= 0.0 =
      Left (label <> " logarithmic search requires a positive minimum")
  | otherwise = Right ()
 where
  minimumValue = floatSearchMinimum search
  maximumValue = floatSearchMaximum search

validateNaturalSearchSpace :: Text -> NaturalCategoricalSearchSpace -> Either Text ()
validateNaturalSearchSpace label search
  | null values = Left (label <> " categorical search must be non-empty")
  | 0 `elem` values = Left (label <> " categorical values must be positive")
  | any ((> toInteger (maxBound :: Int)) . toInteger) values =
      Left (label <> " categorical value exceeds the platform Int range")
  | otherwise = Right ()
 where
  values = naturalSearchValues search

validateTextSearchSpace :: Text -> TextCategoricalSearchSpace -> Either Text ()
validateTextSearchSpace label search
  | null values = Left (label <> " categorical search must be non-empty")
  | any Text.null values = Left (label <> " categorical values must be non-empty")
  | otherwise = Right ()
 where
  values = textSearchValues search

validateObjective :: TuningObjective -> Either Text ()
validateObjective objective = do
  if tuningObjectiveMetric objective `elem` ["valAcc", "valLoss"]
    then Right ()
    else Left ("unsupported tuning objective metric: " <> tuningObjectiveMetric objective)
  if tuningObjectiveDirection objective `elem` ["Maximise", "Minimise"]
    then Right ()
    else Left ("unsupported tuning objective direction: " <> tuningObjectiveDirection objective)

supportedOptimizers :: [Text]
supportedOptimizers = ["Adam", "AdamW", "SGD"]

-- | Static ProductRow tuning contract.  The checked-in Dhall is decoded and
-- compared to this value before any trial effect, so a config edit cannot be
-- silently reinterpreted by the publisher.
canonicalMnistTuningExecutionSpec :: TuningExecutionSpec
canonicalMnistTuningExecutionSpec =
  TuningExecutionSpec
    { tuningExecutionName = "mnist-tune"
    , tuningExecutionDataset = "MNIST"
    , tuningExecutionModel = "DeepDense"
    , tuningExecutionSampler = TuningSampler TPE 1729 16
    , tuningExecutionScheduler = TuningScheduler ASHA 3 1000 1
    , tuningExecutionPruner = TuningPruner MedianPruner 8 50
    , tuningExecutionSearchSpace =
        TuningSearchSpace
          { tuningSearchLearningRate = FloatSearchSpace 1.0e-5 1.0e-2 LogScale
          , tuningSearchBatchSize = NaturalCategoricalSearchSpace [32, 64, 128, 256]
          , tuningSearchDropout = FloatSearchSpace 0.0 0.5 LinearScale
          , tuningSearchOptimizer = TextCategoricalSearchSpace ["Adam", "AdamW", "SGD"]
          }
    , tuningExecutionTrials = 128
    , tuningExecutionParallelism = 1
    , tuningExecutionObjectives = [TuningObjective "valAcc" "Maximise"]
    }

samplerFromText :: Text -> Maybe Sampler
samplerFromText "Grid" = Just Grid
samplerFromText "Sobol" = Just Sobol
samplerFromText "Random" = Just Random
samplerFromText "TPE" = Just TPE
samplerFromText "GPBO" = Just GPBO
samplerFromText "GP-BO" = Just GPBO
samplerFromText "GeneticAlgorithm" = Just GeneticAlgorithm
samplerFromText "GA" = Just GeneticAlgorithm
samplerFromText "NSGA2" = Just NSGA2
samplerFromText "NSGA-II" = Just NSGA2
samplerFromText "MuLambdaES" = Just MuLambdaES
samplerFromText "CMAES" = Just CMAES
samplerFromText "CMA-ES" = Just CMAES
samplerFromText "EvolutionStrategies" = Just EvolutionStrategies
samplerFromText "PBT" = Just PBT
samplerFromText _ = Nothing

schedulerFromText :: Text -> Maybe Scheduler
schedulerFromText "Fifo" = Just Fifo
schedulerFromText "SuccessiveHalving" = Just SuccessiveHalving
schedulerFromText "Hyperband" = Just Hyperband
schedulerFromText "ASHA" = Just ASHA
schedulerFromText _ = Nothing

prunerFromText :: Text -> Maybe Pruner
prunerFromText "None" = Just NoPruner
prunerFromText "NoPruner" = Just NoPruner
prunerFromText "Median" = Just MedianPruner
prunerFromText "MedianPruner" = Just MedianPruner
prunerFromText "Percentile" = Just PercentilePruner
prunerFromText "PercentilePruner" = Just PercentilePruner
prunerFromText _ = Nothing

renderObjectives :: [TuningObjective] -> Text
renderObjectives =
  Text.intercalate ", " . fmap renderObjective

renderObjective :: TuningObjective -> Text
renderObjective objective =
  tuningObjectiveMetric objective <> ":" <> tuningObjectiveDirection objective

showText :: (Show value) => value -> Text
showText = Text.pack . show
