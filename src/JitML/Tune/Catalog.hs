{-# LANGUAGE OverloadedStrings #-}

module JitML.Tune.Catalog
  ( Pruner (..)
  , Sampler (..)
  , Scheduler (..)
  , TrialTranscript (..)
  , deterministicTrials
  , prunerCatalog
  , renderTrialResumeSummary
  , resumeMatchesFullRun
  , samplerCatalog
  , schedulerCatalog
  , trialStorageKey
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

data Sampler
  = Sobol
  | Random
  | GeneticAlgorithm
  | EvolutionStrategies
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

data TrialTranscript = TrialTranscript
  { transcriptExperimentHash :: Text
  , transcriptTrialSeed :: Int
  , transcriptValues :: [Double]
  }
  deriving stock (Eq, Show)

samplerCatalog :: [Sampler]
samplerCatalog = [Sobol, Random, GeneticAlgorithm, EvolutionStrategies]

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
      Sobol -> 101
      Random -> 137
      GeneticAlgorithm -> 149
      EvolutionStrategies -> 163
  normalize value = fromIntegral value / 10_000

seed :: Sampler -> Int
seed Sobol = 11
seed Random = 23
seed GeneticAlgorithm = 37
seed EvolutionStrategies = 41

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
