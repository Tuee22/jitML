{-# LANGUAGE OverloadedStrings #-}

module JitML.Experiment.Overrides
  ( ExperimentOverrides (..)
  , TuningOverrides (..)
  , OverrideError (..)
  , emptyExperimentOverrides
  , emptyTuningOverrides
  , hasExperimentOverrides
  , hasTuningOverrides
  , parseExperimentOverrides
  , parseTuningOverrides
  , applyOverrides
  , overrideSubstrate
  , overrideSeed
  , overrideSampler
  , overrideScheduler
  , overridePruner
  , overrideTrials
  , overrideParallelism
  , renderOverrideError
  , renderExperimentOverrides
  , renderTuningOverrides
  )
where

import Data.Maybe (fromMaybe, isJust)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)
import Numeric.Natural (Natural)
import Text.Read (readMaybe)

import JitML.CLI.Parser (ParsedOption (..))
import JitML.Substrate (Substrate, parseSubstrate, renderSubstrate)
import JitML.Tune.Catalog
  ( Pruner
  , Sampler
  , Scheduler
  , TuningConfig (..)
  , TuningExperiment (..)
  , TuningPruner (..)
  , TuningSampler (..)
  , TuningScheduler (..)
  , prunerFromText
  , samplerFromText
  , schedulerFromText
  )

-- | CLI overrides for `jitml train` and `jitml rl train`. Each field is
-- optional; an absent override leaves the corresponding Dhall field
-- untouched. Per the project doctrine at
-- README.md → Why this exists (pillar 2), CLI flags layered on top
-- override the Dhall on each axis, never replace the surrounding record.
data ExperimentOverrides = ExperimentOverrides
  { eoSubstrate :: !(Maybe Substrate)
  , eoSeed :: !(Maybe Word64)
  }
  deriving stock (Eq, Show)

emptyExperimentOverrides :: ExperimentOverrides
emptyExperimentOverrides = ExperimentOverrides Nothing Nothing

hasExperimentOverrides :: ExperimentOverrides -> Bool
hasExperimentOverrides (ExperimentOverrides s e) = isJust s || isJust e

-- | CLI overrides for `jitml tune`. The five Tuning axes are independently
-- substitutable; absent fields preserve the Dhall.
data TuningOverrides = TuningOverrides
  { toSampler :: !(Maybe Sampler)
  , toScheduler :: !(Maybe Scheduler)
  , toPruner :: !(Maybe Pruner)
  , toTrials :: !(Maybe Natural)
  , toParallelism :: !(Maybe Natural)
  }
  deriving stock (Eq, Show)

emptyTuningOverrides :: TuningOverrides
emptyTuningOverrides = TuningOverrides Nothing Nothing Nothing Nothing Nothing

hasTuningOverrides :: TuningOverrides -> Bool
hasTuningOverrides (TuningOverrides s c p t pa) =
  isJust s || isJust c || isJust p || isJust t || isJust pa

-- | Parse-time errors. The CLI layer renders these through the existing
-- AppError surface; the resolver returns them as data.
data OverrideError
  = InvalidSubstrate Text
  | InvalidSeed Text
  | InvalidSampler Text
  | InvalidScheduler Text
  | InvalidPruner Text
  | InvalidTrials Text
  | InvalidParallelism Text
  deriving stock (Eq, Show)

renderOverrideError :: OverrideError -> Text
renderOverrideError = \case
  InvalidSubstrate raw ->
    "invalid --substrate value: "
      <> quote raw
      <> "; expected one of apple-silicon, linux-cpu, linux-cuda"
  InvalidSeed raw ->
    "invalid --seed value: " <> quote raw <> "; expected an unsigned 64-bit integer"
  InvalidSampler raw ->
    "invalid --sampler value: "
      <> quote raw
      <> "; expected one of "
      <> samplerHint
  InvalidScheduler raw ->
    "invalid --scheduler value: "
      <> quote raw
      <> "; expected one of "
      <> schedulerHint
  InvalidPruner raw ->
    "invalid --pruner value: "
      <> quote raw
      <> "; expected one of "
      <> prunerHint
  InvalidTrials raw ->
    "invalid --trials value: " <> quote raw <> "; expected a non-negative integer"
  InvalidParallelism raw ->
    "invalid --parallelism value: " <> quote raw <> "; expected a non-negative integer"
 where
  quote raw = "\"" <> raw <> "\""
  samplerHint =
    "Grid, Sobol, Random, TPE, GPBO, GeneticAlgorithm, NSGA2, MuLambdaES, CMAES, EvolutionStrategies, PBT"
  schedulerHint = "Fifo, SuccessiveHalving, Hyperband, ASHA"
  prunerHint = "NoPruner, MedianPruner, PercentilePruner"

parseExperimentOverrides :: [ParsedOption] -> Either OverrideError ExperimentOverrides
parseExperimentOverrides parsedOptions = do
  substrate <- optionalDecode "substrate" parsedSubstrate parsedOptions
  seed <- optionalDecode "seed" parsedSeed parsedOptions
  pure (ExperimentOverrides substrate seed)
 where
  parsedSubstrate raw =
    maybe (Left (InvalidSubstrate raw)) Right (parseSubstrate raw)
  parsedSeed raw =
    maybe (Left (InvalidSeed raw)) Right (readMaybe (Text.unpack raw) :: Maybe Word64)

parseTuningOverrides :: [ParsedOption] -> Either OverrideError TuningOverrides
parseTuningOverrides parsedOptions = do
  sampler <- optionalDecode "sampler" parsedSampler parsedOptions
  scheduler <- optionalDecode "scheduler" parsedScheduler parsedOptions
  pruner <- optionalDecode "pruner" parsedPruner parsedOptions
  trials <- optionalDecode "trials" (parsedNatural InvalidTrials) parsedOptions
  parallelism <- optionalDecode "parallelism" (parsedNatural InvalidParallelism) parsedOptions
  pure (TuningOverrides sampler scheduler pruner trials parallelism)
 where
  parsedSampler raw =
    maybe (Left (InvalidSampler raw)) Right (samplerFromText raw)
  parsedScheduler raw =
    maybe (Left (InvalidScheduler raw)) Right (schedulerFromText raw)
  parsedPruner raw =
    maybe (Left (InvalidPruner raw)) Right (prunerFromText raw)
  parsedNatural mkError raw =
    case readMaybe (Text.unpack raw) :: Maybe Integer of
      Just n | n >= 0 -> Right (fromInteger n)
      _ -> Left (mkError raw)

optionalDecode
  :: Text -> (Text -> Either OverrideError a) -> [ParsedOption] -> Either OverrideError (Maybe a)
optionalDecode name decode parsedOptions =
  case lastValueFor name parsedOptions of
    Nothing -> Right Nothing
    Just raw -> Just <$> decode raw

lastValueFor :: Text -> [ParsedOption] -> Maybe Text
lastValueFor name =
  lastMaybe . concatMap matching
 where
  matching option
    | parsedOptionName option == name = parsedOptionValues option
    | otherwise = []
  lastMaybe [] = Nothing
  lastMaybe xs = Just (last xs)

overrideSubstrate :: ExperimentOverrides -> Substrate -> Substrate
overrideSubstrate ovr base = fromMaybe base (eoSubstrate ovr)

overrideSeed :: ExperimentOverrides -> Word64 -> Word64
overrideSeed ovr base = fromMaybe base (eoSeed ovr)

overrideSampler :: TuningOverrides -> Sampler -> Sampler
overrideSampler ovr base = fromMaybe base (toSampler ovr)

overrideScheduler :: TuningOverrides -> Scheduler -> Scheduler
overrideScheduler ovr base = fromMaybe base (toScheduler ovr)

overridePruner :: TuningOverrides -> Pruner -> Pruner
overridePruner ovr base = fromMaybe base (toPruner ovr)

overrideTrials :: TuningOverrides -> Natural -> Natural
overrideTrials ovr base = fromMaybe base (toTrials ovr)

overrideParallelism :: TuningOverrides -> Natural -> Natural
overrideParallelism ovr base = fromMaybe base (toParallelism ovr)

applyOverrides :: TuningOverrides -> TuningExperiment -> TuningExperiment
applyOverrides ovr experiment =
  experiment {tuningExperimentConfig = fmap applyConfig (tuningExperimentConfig experiment)}
 where
  applyConfig config =
    config
      { tuningConfigSampler =
          (tuningConfigSampler config)
            { tuningSamplerKind =
                overrideSampler ovr (tuningSamplerKind (tuningConfigSampler config))
            }
      , tuningConfigScheduler =
          (tuningConfigScheduler config)
            { tuningSchedulerKind =
                overrideScheduler ovr (tuningSchedulerKind (tuningConfigScheduler config))
            }
      , tuningConfigPruner =
          (tuningConfigPruner config)
            { tuningPrunerKind =
                overridePruner ovr (tuningPrunerKind (tuningConfigPruner config))
            }
      , tuningConfigTrials = overrideTrials ovr (tuningConfigTrials config)
      , tuningConfigParallelism = overrideParallelism ovr (tuningConfigParallelism config)
      }

-- | Human-readable summary of which overrides are present, suitable for
-- inclusion in `--dry-run` plan output and CLI summaries.
renderExperimentOverrides :: ExperimentOverrides -> Text
renderExperimentOverrides ovr =
  case parts of
    [] -> "(none)"
    items -> Text.intercalate ", " items
 where
  parts =
    [ "substrate=" <> renderSubstrate s | Just s <- [eoSubstrate ovr]
    ]
      <> [ "seed=" <> Text.pack (show n) | Just n <- [eoSeed ovr]
         ]

renderTuningOverrides :: TuningOverrides -> Text
renderTuningOverrides ovr =
  case parts of
    [] -> "(none)"
    items -> Text.intercalate ", " items
 where
  parts =
    [ "sampler=" <> renderShow s | Just s <- [toSampler ovr]
    ]
      <> [ "scheduler=" <> renderShow s | Just s <- [toScheduler ovr]
         ]
      <> [ "pruner=" <> renderShow p | Just p <- [toPruner ovr]
         ]
      <> [ "trials=" <> Text.pack (show n) | Just n <- [toTrials ovr]
         ]
      <> [ "parallelism=" <> Text.pack (show n) | Just n <- [toParallelism ovr]
         ]
  renderShow :: (Show a) => a -> Text
  renderShow = Text.pack . show
