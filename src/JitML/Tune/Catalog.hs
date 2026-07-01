{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.Tune.Catalog
  ( Pruner (..)
  , Sampler (..)
  , Scheduler (..)
  , TuningConfig (..)
  , TuningExperiment (..)
  , TuningObjective (..)
  , TuningPruner (..)
  , TuningSampler (..)
  , TuningScheduler (..)
  , TrialObjectiveResult (..)
  , TrialTranscript (..)
  , deterministicTrials
  , deterministicTrialsWithDevice
  , loadTuningExperiment
  , prunerCatalog
  , prunerFromText
  , renderTuningPlan
  , renderTrialResumeSummary
  , resumeMatchesFullRun
  , samplerCatalog
  , samplerFromText
  , schedulerCatalog
  , schedulerFromText
  , trialObjectiveResult
  , trialObjectiveResultWithDevice
  , trialObjectiveResults
  , trialObjectiveResultsWithDevice
  , trialStorageKey
  )
where

import Codec.Serialise (Serialise)
import Control.Exception.Safe (displayException, tryAny)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU
import Dhall qualified
import GHC.Generics (Generic)
import Numeric.Natural (Natural)

import System.IO.Unsafe (unsafePerformIO)

import JitML.Numerics.MlpDevice (MlpDevice, pureReferenceMlpDevice)
import JitML.SL.Architecture qualified as Architecture
import JitML.SL.Canonicals (CanonicalProblem (..))
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
  deriving stock (Eq, Show)

data Scheduler
  = Fifo
  | SuccessiveHalving
  | Hyperband
  | ASHA
  deriving stock (Eq, Show)

data Pruner
  = NoPruner
  | MedianPruner
  | PercentilePruner
  deriving stock (Eq, Show)

data TuningExperiment = TuningExperiment
  { tuningExperimentName :: Text
  , tuningExperimentDataset :: Text
  , tuningExperimentModel :: Text
  , tuningExperimentSeed :: Natural
  , tuningExperimentConfig :: Maybe TuningConfig
  }
  deriving stock (Eq, Show)

data TuningConfig = TuningConfig
  { tuningConfigSampler :: TuningSampler
  , tuningConfigScheduler :: TuningScheduler
  , tuningConfigPruner :: TuningPruner
  , tuningConfigTrials :: Natural
  , tuningConfigParallelism :: Natural
  , tuningConfigObjectives :: [TuningObjective]
  }
  deriving stock (Eq, Show)

data TuningSampler = TuningSampler
  { tuningSamplerKind :: Sampler
  , tuningSamplerSeed :: Natural
  , tuningSamplerStartupTrials :: Natural
  }
  deriving stock (Eq, Show)

data TuningScheduler = TuningScheduler
  { tuningSchedulerKind :: Scheduler
  , tuningSchedulerEta :: Natural
  , tuningSchedulerMaxBudget :: Natural
  , tuningSchedulerParallelism :: Natural
  }
  deriving stock (Eq, Show)

data TuningPruner = TuningPruner
  { tuningPrunerKind :: Pruner
  , tuningPrunerWarmupTrials :: Natural
  , tuningPrunerEvalAtPercentile :: Natural
  }
  deriving stock (Eq, Show)

data TuningObjective = TuningObjective
  { tuningObjectiveMetric :: Text
  , tuningObjectiveDirection :: Text
  }
  deriving stock (Eq, Show)

data TrialTranscript = TrialTranscript
  { transcriptExperimentHash :: Text
  , transcriptTrialSeed :: Int
  , transcriptValues :: [Double]
  }
  deriving stock (Eq, Generic, Show)
  deriving anyclass (Serialise)

data TrialObjectiveResult = TrialObjectiveResult
  { trialResultIndex :: !Int
  , trialResultObjective :: !Double
  , trialResultWeights :: ![Double]
  }
  deriving stock (Eq, Show)

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
  [trialObjectiveResult sampler i | i <- [0 .. count - 1]]

trialObjectiveResultsWithDevice
  :: MlpDevice -> Sampler -> Int -> IO (Either Text [TrialObjectiveResult])
trialObjectiveResultsWithDevice device sampler count =
  go [0 .. count - 1] []
 where
  go [] acc = pure (Right (reverse acc))
  go (trialIndex : rest) acc = do
    result <- trialObjectiveResultWithDevice device sampler trialIndex
    case result of
      Left err -> pure (Left err)
      Right value -> go rest (value : acc)

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
  let config = sampledClassifierConfig sampler trialIndex
   in case pureTuningObjective config of
        Right (objective, weights) ->
          TrialObjectiveResult
            { trialResultIndex = trialIndex
            , trialResultObjective = objective
            , trialResultWeights = weights
            }
        Left err ->
          error ("tuning objective (pure reference device) failed: " <> Text.unpack err)

trialObjectiveResultWithDevice
  :: MlpDevice -> Sampler -> Int -> IO (Either Text TrialObjectiveResult)
trialObjectiveResultWithDevice device sampler trialIndex = do
  let config = sampledClassifierConfig sampler trialIndex
  result <- trainTuningObjective device config
  pure $
    fmap
      ( \(objective, weights) ->
          TrialObjectiveResult
            { trialResultIndex = trialIndex
            , trialResultObjective = objective
            , trialResultWeights = weights
            }
      )
      result

-- | Train the fixed Dense tuning architecture for one sampled config on
-- 'tuningObjectiveDataset' through @device@, returning
-- @(train-accuracy, flat-weights)@.
trainTuningObjective
  :: MlpDevice -> Classifier.ClassifierConfig -> IO (Either Text (Double, [Double]))
trainTuningObjective device config = do
  let spec = Architecture.architectureSpecForProblem config tuningObjectiveProblem
  result <- Architecture.trainArchitectureWithDevice device spec config tuningObjectiveDataset
  pure (fmap (\(trained, acc) -> (acc, Architecture.trainedArchitectureWeights trained)) result)

-- | The pure-reference-device evaluation of 'trainTuningObjective' — the
-- toolchain-free objective used by the offline sweep ('deterministicTrials').
-- The reference device performs no IO, so 'unsafePerformIO' here is
-- referentially transparent (the result is a pure function of @config@).
pureTuningObjective :: Classifier.ClassifierConfig -> Either Text (Double, [Double])
pureTuningObjective config =
  unsafePerformIO (trainTuningObjective pureReferenceMlpDevice config)
{-# NOINLINE pureTuningObjective #-}

-- | The fixed Dense canonical problem the tuning objective trains: a small
-- single-hidden-layer MLP sized from each sampled 'ClassifierConfig'.
tuningObjectiveProblem :: CanonicalProblem
tuningObjectiveProblem = CanonicalProblem "tune-dense" "synthetic" "Dense" 0

-- | Deterministic hyperparameter sample for one trial: the sampler seed and the
-- trial index pick a learning rate and hidden width from a fixed grid (the
-- sampler's job is to choose configurations; the objective measures them).
sampledClassifierConfig :: Sampler -> Int -> Classifier.ClassifierConfig
sampledClassifierConfig sampler trialIndex =
  let base = seed sampler + trialIndex
      lrChoices = [1.0e-3, 3.0e-3, 1.0e-2, 3.0e-2]
      hiddenChoices = [4, 8, 12, 16]
   in Classifier.defaultClassifierConfig
        { Classifier.clfSeed = base
        , Classifier.clfInputs = 2
        , Classifier.clfHidden = hiddenChoices !! ((base * 7) `mod` 4)
        , Classifier.clfClasses = 2
        , Classifier.clfEpochs = 6
        , Classifier.clfLearningRate = lrChoices !! ((base * 3) `mod` 4)
        }

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
                (show (deterministicTrials (tuningSamplerKind (tuningConfigSampler config)) 4))
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
  TuningExperiment
    (rawTuningExperimentName raw)
    (rawTuningExperimentDataset raw)
    (rawTuningExperimentModel raw)
    (rawTuningExperimentSeed raw)
    <$> traverse normalizeTuningConfig (rawTuningExperimentConfig raw)

normalizeTuningConfig :: RawTuningConfig -> Either Text TuningConfig
normalizeTuningConfig raw = do
  sampler <- normalizeSampler (rawTuningConfigSampler raw)
  scheduler <- normalizeScheduler (rawTuningConfigScheduler raw)
  pruner <- normalizePruner (rawTuningConfigPruner raw)
  pure
    TuningConfig
      { tuningConfigSampler = sampler
      , tuningConfigScheduler = scheduler
      , tuningConfigPruner = pruner
      , tuningConfigTrials = rawTuningConfigTrials raw
      , tuningConfigParallelism = rawTuningConfigParallelism raw
      , tuningConfigObjectives = rawTuningConfigObjectives raw
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
