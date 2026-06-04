{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Sprint 5.7 — typed worker `RunConfig`. The daemon writes one of these
-- (rendered to Dhall and mounted on the dispatched Job as a per-run
-- ConfigMap) before dispatching the worker, and the worker decodes it via
-- 'Dhall.inputFile' instead of reading the former @JITML_*@ environment
-- variables. Mirrors the three command envelopes 'StartTraining',
-- 'StartSweep', and 'StartRLRun'.
module JitML.Service.RunConfig
  ( TrainingRunConfig (..)
  , TuneRunConfig (..)
  , RlRunConfig (..)
  , trainingRunConfigDecoder
  , tuneRunConfigDecoder
  , rlRunConfigDecoder
  , loadTrainingRunConfig
  , loadTuneRunConfig
  , loadRlRunConfig
  , tryLoadTrainingRunConfig
  , tryLoadTuneRunConfig
  , tryLoadRlRunConfig
  , renderTrainingRunConfigDhall
  , renderTuneRunConfigDhall
  , renderRlRunConfigDhall
  )
where

import Control.Exception (SomeException, try)
import Data.Text (Text)
import Data.Text qualified as Text
import Dhall qualified
import Numeric.Natural (Natural)
import System.Directory (doesFileExist)

data TrainingRunConfig = TrainingRunConfig
  { trcExperimentHash :: Text
  , trcSubstrate :: Text
  , trcSeed :: Int
  , trcEpochs :: Int
  , trcBatchSize :: Int
  , trcPulsarWsUrl :: Text
  , trcSlTrainLimit :: Maybe Int
  , trcSlEpochs :: Maybe Int
  , trcSlTestLimit :: Maybe Int
  }
  deriving stock (Eq, Show)

data TuneRunConfig = TuneRunConfig
  { turcExperimentHash :: Text
  , turcSubstrate :: Text
  , turcSweepSeed :: Int
  , turcTrialBudget :: Int
  , turcBudgetPerTrial :: Int
  , turcSampler :: Text
  , turcScheduler :: Text
  , turcPruner :: Text
  , turcPulsarWsUrl :: Text
  }
  deriving stock (Eq, Show)

data RlRunConfig = RlRunConfig
  { rlcExperimentHash :: Text
  , rlcAlgorithm :: Text
  , rlcEnvironment :: Text
  , rlcSubstrate :: Text
  , rlcSeed :: Int
  , rlcMaxSteps :: Int
  , rlcEvalEpisodes :: Int
  , rlcTrainerKind :: Text
  , rlcAtariRomPath :: Maybe Text
  , rlcPulsarWsUrl :: Text
  }
  deriving stock (Eq, Show)

naturalToInt :: Natural -> Int
naturalToInt = fromIntegral

trainingRunConfigDecoder :: Dhall.Decoder TrainingRunConfig
trainingRunConfigDecoder =
  Dhall.record $
    TrainingRunConfig
      <$> Dhall.field "experimentHash" Dhall.strictText
      <*> Dhall.field "substrate" Dhall.strictText
      <*> fmap naturalToInt (Dhall.field "seed" Dhall.natural)
      <*> fmap naturalToInt (Dhall.field "epochs" Dhall.natural)
      <*> fmap naturalToInt (Dhall.field "batchSize" Dhall.natural)
      <*> Dhall.field "pulsarWsUrl" Dhall.strictText
      <*> fmap (fmap naturalToInt) (Dhall.field "slTrainLimit" (Dhall.maybe Dhall.natural))
      <*> fmap (fmap naturalToInt) (Dhall.field "slEpochs" (Dhall.maybe Dhall.natural))
      <*> fmap (fmap naturalToInt) (Dhall.field "slTestLimit" (Dhall.maybe Dhall.natural))

tuneRunConfigDecoder :: Dhall.Decoder TuneRunConfig
tuneRunConfigDecoder =
  Dhall.record $
    TuneRunConfig
      <$> Dhall.field "experimentHash" Dhall.strictText
      <*> Dhall.field "substrate" Dhall.strictText
      <*> fmap naturalToInt (Dhall.field "sweepSeed" Dhall.natural)
      <*> fmap naturalToInt (Dhall.field "trialBudget" Dhall.natural)
      <*> fmap naturalToInt (Dhall.field "budgetPerTrial" Dhall.natural)
      <*> Dhall.field "sampler" Dhall.strictText
      <*> Dhall.field "scheduler" Dhall.strictText
      <*> Dhall.field "pruner" Dhall.strictText
      <*> Dhall.field "pulsarWsUrl" Dhall.strictText

rlRunConfigDecoder :: Dhall.Decoder RlRunConfig
rlRunConfigDecoder =
  Dhall.record $
    RlRunConfig
      <$> Dhall.field "experimentHash" Dhall.strictText
      <*> Dhall.field "algorithm" Dhall.strictText
      <*> Dhall.field "environment" Dhall.strictText
      <*> Dhall.field "substrate" Dhall.strictText
      <*> fmap naturalToInt (Dhall.field "seed" Dhall.natural)
      <*> fmap naturalToInt (Dhall.field "maxSteps" Dhall.natural)
      <*> fmap naturalToInt (Dhall.field "evalEpisodes" Dhall.natural)
      <*> Dhall.field "trainerKind" Dhall.strictText
      <*> Dhall.field "atariRomPath" (Dhall.maybe Dhall.strictText)
      <*> Dhall.field "pulsarWsUrl" Dhall.strictText

loadTrainingRunConfig :: FilePath -> IO TrainingRunConfig
loadTrainingRunConfig = Dhall.inputFile trainingRunConfigDecoder

loadTuneRunConfig :: FilePath -> IO TuneRunConfig
loadTuneRunConfig = Dhall.inputFile tuneRunConfigDecoder

loadRlRunConfig :: FilePath -> IO RlRunConfig
loadRlRunConfig = Dhall.inputFile rlRunConfigDecoder

-- | Sprint 5.7 — return 'Nothing' when the per-run @RunConfig.dhall@ file is
-- absent (e.g., during a developer's local CLI invocation outside a Job pod).
-- Daemon-dispatched workers always see the file mounted by
-- 'JitML.Service.Workload.renderJobWithRunConfig'.
tryLoadTrainingRunConfig :: FilePath -> IO (Maybe TrainingRunConfig)
tryLoadTrainingRunConfig = tryLoadFile trainingRunConfigDecoder

tryLoadTuneRunConfig :: FilePath -> IO (Maybe TuneRunConfig)
tryLoadTuneRunConfig = tryLoadFile tuneRunConfigDecoder

tryLoadRlRunConfig :: FilePath -> IO (Maybe RlRunConfig)
tryLoadRlRunConfig = tryLoadFile rlRunConfigDecoder

tryLoadFile :: forall a. Dhall.Decoder a -> FilePath -> IO (Maybe a)
tryLoadFile decoder path = do
  exists <- doesFileExist path
  if not exists
    then pure Nothing
    else do
      attempt <- try (Dhall.inputFile decoder path) :: IO (Either SomeException a)
      case attempt of
        Left _ -> pure Nothing
        Right value -> pure (Just value)

renderOptionalNatural :: Maybe Int -> Text
renderOptionalNatural Nothing = "None Natural"
renderOptionalNatural (Just n) = "Some " <> Text.pack (show (max 0 n))

renderOptionalText :: Maybe Text -> Text
renderOptionalText Nothing = "None Text"
renderOptionalText (Just t) = "Some " <> quote t

quote :: Text -> Text
quote t = "\"" <> t <> "\""

renderTrainingRunConfigDhall :: TrainingRunConfig -> Text
renderTrainingRunConfigDhall c =
  Text.unlines
    [ "{ experimentHash = " <> quote (trcExperimentHash c)
    , ", substrate = " <> quote (trcSubstrate c)
    , ", seed = " <> Text.pack (show (trcSeed c))
    , ", epochs = " <> Text.pack (show (trcEpochs c))
    , ", batchSize = " <> Text.pack (show (trcBatchSize c))
    , ", pulsarWsUrl = " <> quote (trcPulsarWsUrl c)
    , ", slTrainLimit = " <> renderOptionalNatural (trcSlTrainLimit c)
    , ", slEpochs = " <> renderOptionalNatural (trcSlEpochs c)
    , ", slTestLimit = " <> renderOptionalNatural (trcSlTestLimit c)
    , "}"
    ]

renderTuneRunConfigDhall :: TuneRunConfig -> Text
renderTuneRunConfigDhall c =
  Text.unlines
    [ "{ experimentHash = " <> quote (turcExperimentHash c)
    , ", substrate = " <> quote (turcSubstrate c)
    , ", sweepSeed = " <> Text.pack (show (turcSweepSeed c))
    , ", trialBudget = " <> Text.pack (show (turcTrialBudget c))
    , ", budgetPerTrial = " <> Text.pack (show (turcBudgetPerTrial c))
    , ", sampler = " <> quote (turcSampler c)
    , ", scheduler = " <> quote (turcScheduler c)
    , ", pruner = " <> quote (turcPruner c)
    , ", pulsarWsUrl = " <> quote (turcPulsarWsUrl c)
    , "}"
    ]

renderRlRunConfigDhall :: RlRunConfig -> Text
renderRlRunConfigDhall c =
  Text.unlines
    [ "{ experimentHash = " <> quote (rlcExperimentHash c)
    , ", algorithm = " <> quote (rlcAlgorithm c)
    , ", environment = " <> quote (rlcEnvironment c)
    , ", substrate = " <> quote (rlcSubstrate c)
    , ", seed = " <> Text.pack (show (rlcSeed c))
    , ", maxSteps = " <> Text.pack (show (rlcMaxSteps c))
    , ", evalEpisodes = " <> Text.pack (show (rlcEvalEpisodes c))
    , ", trainerKind = " <> quote (rlcTrainerKind c)
    , ", atariRomPath = " <> renderOptionalText (rlcAtariRomPath c)
    , ", pulsarWsUrl = " <> quote (rlcPulsarWsUrl c)
    , "}"
    ]
