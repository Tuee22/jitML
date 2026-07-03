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
  , TrainingEvidenceConfig (..)
  , CompletedTrainingWitnessConfig (..)
  , InferenceSelectorConfig (..)
  , RunConfigLoadResult (..)
  , trainingRunConfigDecoder
  , tuneRunConfigDecoder
  , rlRunConfigDecoder
  , trainingEvidenceConfigDecoder
  , completedTrainingWitnessConfigDecoder
  , inferenceSelectorConfigDecoder
  , loadTrainingRunConfig
  , loadTuneRunConfig
  , loadRlRunConfig
  , loadInferenceSelectorConfig
  , tryLoadTrainingRunConfig
  , tryLoadTuneRunConfig
  , tryLoadRlRunConfig
  , tryLoadInferenceSelectorConfig
  , validateInferenceSelectorConfig
  , renderTrainingRunConfigDhall
  , renderTuneRunConfigDhall
  , renderRlRunConfigDhall
  )
where

import Control.Exception (SomeException, try)
import Control.Exception qualified as Exception
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

data TrainingEvidenceConfig = TrainingEvidenceConfig
  { tecInitialWeightHash :: Text
  , tecFinalWeightHash :: Text
  , tecUpdateCount :: Int
  , tecDatasetShaAtRead :: Text
  }
  deriving stock (Eq, Show)

data CompletedTrainingWitnessConfig = CompletedTrainingWitnessConfig
  { ctwExperimentHash :: Text
  , ctwManifestSha :: Text
  , ctwProvenanceKind :: Text
  , ctwEvidence :: TrainingEvidenceConfig
  , ctwConvergencePassed :: Bool
  }
  deriving stock (Eq, Show)

data InferenceSelectorConfig = InferenceSelectorConfig
  { iscExperimentHash :: Text
  , iscManifestSha :: Text
  , iscCompletedTraining :: CompletedTrainingWitnessConfig
  }
  deriving stock (Eq, Show)

data RunConfigLoadResult a
  = RunConfigMissing
  | RunConfigLoaded a
  | RunConfigDecodeFailed Text
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

trainingEvidenceConfigDecoder :: Dhall.Decoder TrainingEvidenceConfig
trainingEvidenceConfigDecoder =
  Dhall.record $
    TrainingEvidenceConfig
      <$> Dhall.field "initialWeightHash" Dhall.strictText
      <*> Dhall.field "finalWeightHash" Dhall.strictText
      <*> fmap naturalToInt (Dhall.field "updateCount" Dhall.natural)
      <*> Dhall.field "datasetShaAtRead" Dhall.strictText

completedTrainingWitnessConfigDecoder :: Dhall.Decoder CompletedTrainingWitnessConfig
completedTrainingWitnessConfigDecoder =
  Dhall.record $
    CompletedTrainingWitnessConfig
      <$> Dhall.field "experimentHash" Dhall.strictText
      <*> Dhall.field "manifestSha" Dhall.strictText
      <*> Dhall.field "provenanceKind" Dhall.strictText
      <*> Dhall.field "evidence" trainingEvidenceConfigDecoder
      <*> Dhall.field "convergencePassed" Dhall.bool

inferenceSelectorConfigDecoder :: Dhall.Decoder InferenceSelectorConfig
inferenceSelectorConfigDecoder =
  Dhall.record $
    InferenceSelectorConfig
      <$> Dhall.field "experimentHash" Dhall.strictText
      <*> Dhall.field "manifestSha" Dhall.strictText
      <*> Dhall.field "completedTraining" completedTrainingWitnessConfigDecoder

loadTrainingRunConfig :: FilePath -> IO TrainingRunConfig
loadTrainingRunConfig = Dhall.inputFile trainingRunConfigDecoder

loadTuneRunConfig :: FilePath -> IO TuneRunConfig
loadTuneRunConfig = Dhall.inputFile tuneRunConfigDecoder

loadRlRunConfig :: FilePath -> IO RlRunConfig
loadRlRunConfig = Dhall.inputFile rlRunConfigDecoder

loadInferenceSelectorConfig :: FilePath -> IO InferenceSelectorConfig
loadInferenceSelectorConfig path = do
  result <- tryLoadInferenceSelectorConfig path
  case result of
    RunConfigLoaded selector -> pure selector
    RunConfigMissing -> fail ("missing inference selector config: " <> path)
    RunConfigDecodeFailed err -> fail (Text.unpack err)

-- | Sprint 5.17 — distinguish an absent per-run @RunConfig.dhall@ from a
-- present file that fails Dhall decoding. Local developer invocations may fall
-- back only on 'RunConfigMissing'; mounted worker decode failures are fatal at
-- the caller boundary.
tryLoadTrainingRunConfig :: FilePath -> IO (RunConfigLoadResult TrainingRunConfig)
tryLoadTrainingRunConfig = tryLoadFile trainingRunConfigDecoder

tryLoadTuneRunConfig :: FilePath -> IO (RunConfigLoadResult TuneRunConfig)
tryLoadTuneRunConfig = tryLoadFile tuneRunConfigDecoder

tryLoadRlRunConfig :: FilePath -> IO (RunConfigLoadResult RlRunConfig)
tryLoadRlRunConfig = tryLoadFile rlRunConfigDecoder

tryLoadInferenceSelectorConfig :: FilePath -> IO (RunConfigLoadResult InferenceSelectorConfig)
tryLoadInferenceSelectorConfig =
  tryLoadValidatedFile inferenceSelectorConfigDecoder validateInferenceSelectorConfig

tryLoadFile :: forall a. Dhall.Decoder a -> FilePath -> IO (RunConfigLoadResult a)
tryLoadFile decoder path = do
  exists <- doesFileExist path
  if not exists
    then pure RunConfigMissing
    else do
      attempt <- try (Dhall.inputFile decoder path) :: IO (Either SomeException a)
      case attempt of
        Left err -> pure (RunConfigDecodeFailed (Text.pack (Exception.displayException err)))
        Right value -> pure (RunConfigLoaded value)

tryLoadValidatedFile
  :: forall a. Dhall.Decoder a -> (a -> Either Text a) -> FilePath -> IO (RunConfigLoadResult a)
tryLoadValidatedFile decoder validate path = do
  loaded <- tryLoadFile decoder path
  pure $
    case loaded of
      RunConfigLoaded value ->
        either RunConfigDecodeFailed RunConfigLoaded (validate value)
      RunConfigMissing -> RunConfigMissing
      RunConfigDecodeFailed err -> RunConfigDecodeFailed err

validateInferenceSelectorConfig :: InferenceSelectorConfig -> Either Text InferenceSelectorConfig
validateInferenceSelectorConfig selector
  | Text.null (iscExperimentHash selector) =
      Left "inference selector requires a non-empty experimentHash"
  | Text.null (iscManifestSha selector) =
      Left "inference selector requires a non-empty manifestSha"
  | iscExperimentHash selector /= ctwExperimentHash witness =
      Left "inference selector experimentHash does not match completed-training witness"
  | iscManifestSha selector /= ctwManifestSha witness =
      Left "inference selector manifestSha does not match completed-training witness"
  | ctwProvenanceKind witness /= "completed-training" =
      Left "inference selector requires completed-training provenance"
  | not (ctwConvergencePassed witness) =
      Left "inference selector completed-training witness has failed convergence"
  | Text.null (tecInitialWeightHash evidence) =
      Left "inference selector requires an initialWeightHash"
  | Text.null (tecFinalWeightHash evidence) =
      Left "inference selector requires a finalWeightHash"
  | tecInitialWeightHash evidence == tecFinalWeightHash evidence =
      Left "inference selector requires changed weights"
  | tecUpdateCount evidence <= 0 =
      Left "inference selector requires a positive updateCount"
  | Text.null (tecDatasetShaAtRead evidence) =
      Left "inference selector requires datasetShaAtRead provenance"
  | otherwise =
      Right selector
 where
  witness = iscCompletedTraining selector
  evidence = ctwEvidence witness

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
