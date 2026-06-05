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
  , TrialTranscript (..)
  , deterministicTrials
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
  , trialStorageKey
  )
where

import Codec.Serialise (Serialise)
import Control.Exception.Safe (displayException, tryAny)
import Data.Text (Text)
import Data.Text qualified as Text
import Dhall qualified
import GHC.Generics (Generic)
import Numeric.Natural (Natural)

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

deterministicTrials :: Sampler -> Int -> [Double]
deterministicTrials sampler count =
  take count $
    normalize
      <$> iterate (\value -> (value * multiplier + 17) `mod` 10_000) (seed sampler)
 where
  multiplier =
    case sampler of
      Grid -> 97
      Sobol -> 101
      Random -> 137
      TPE -> 173
      GPBO -> 181
      GeneticAlgorithm -> 149
      NSGA2 -> 191
      MuLambdaES -> 197
      CMAES -> 199
      EvolutionStrategies -> 163
      PBT -> 211
  normalize value = fromIntegral value / 10_000

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
prunerFromText "NoPruner" = Just NoPruner
prunerFromText "MedianPruner" = Just MedianPruner
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
