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
  , AlphaZeroRunConfig (..)
  , RlRunConfig (..)
  , TrainingEvidenceConfig (..)
  , CompletedTrainingWitnessConfig (..)
  , InferenceSelectorConfig (..)
  , RunConfigLoadResult (..)
  , trainingRunConfigDecoder
  , tuneRunConfigDecoder
  , alphaZeroRunConfigDecoder
  , rlRunConfigDecoder
  , trainingEvidenceConfigDecoder
  , completedTrainingWitnessConfigDecoder
  , inferenceSelectorConfigDecoder
  , loadTrainingRunConfig
  , loadTuneRunConfig
  , loadAlphaZeroRunConfig
  , loadRlRunConfig
  , loadInferenceSelectorConfig
  , tryLoadTrainingRunConfig
  , tryLoadTuneRunConfig
  , tryLoadAlphaZeroRunConfig
  , tryLoadRlRunConfig
  , tryLoadInferenceSelectorConfig
  , validateInferenceSelectorConfig
  , supervisedPlanFromRunConfig
  , tuningPlanFromRunConfig
  , alphaZeroPlanFromRunConfig
  , renderTrainingRunConfigDhall
  , renderTuneRunConfigDhall
  , renderAlphaZeroRunConfigDhall
  , renderRlRunConfigDhall
  )
where

import Control.Exception (SomeException, try)
import Control.Exception qualified as Exception
import Control.Monad (unless, when)
import Data.Bifunctor (first)
import Data.List.NonEmpty (NonEmpty)
import Data.Text (Text)
import Data.Text qualified as Text
import Dhall qualified
import Numeric.Natural (Natural)
import System.Directory (doesFileExist)

import JitML.Plan.Plan (Validation, planIdText, validationToEither)
import JitML.Plan.Workload
  ( AlphaZeroPlan
  , SupervisedPlan
  , TuningPlan
  , alphaZeroPlanId
  , parseAlphaZeroPlanTransport
  , parseSupervisedPlanTransport
  , parseTuningPlanTransport
  , renderAlphaZeroPlanTransport
  , renderSupervisedPlanTransport
  , renderTuningPlanTransport
  , supervisedPlanId
  , tuningPlanId
  )

data TrainingRunConfig = TrainingRunConfig
  { trcPlanId :: Text
  , trcResolvedPlan :: Text
  , trcPulsarWsUrl :: Text
  }
  deriving stock (Eq, Show)

data TuneRunConfig = TuneRunConfig
  { turcPlanId :: Text
  , turcResolvedPlan :: Text
  , turcPulsarWsUrl :: Text
  }
  deriving stock (Eq, Show)

data AlphaZeroRunConfig = AlphaZeroRunConfig
  { azrcPlanId :: Text
  , azrcResolvedPlan :: Text
  , azrcPulsarWsUrl :: Text
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
      <$> Dhall.field "planId" Dhall.strictText
      <*> Dhall.field "resolvedPlan" Dhall.strictText
      <*> Dhall.field "pulsarWsUrl" Dhall.strictText

tuneRunConfigDecoder :: Dhall.Decoder TuneRunConfig
tuneRunConfigDecoder =
  Dhall.record $
    TuneRunConfig
      <$> Dhall.field "planId" Dhall.strictText
      <*> Dhall.field "resolvedPlan" Dhall.strictText
      <*> Dhall.field "pulsarWsUrl" Dhall.strictText

alphaZeroRunConfigDecoder :: Dhall.Decoder AlphaZeroRunConfig
alphaZeroRunConfigDecoder =
  Dhall.record $
    AlphaZeroRunConfig
      <$> Dhall.field "planId" Dhall.strictText
      <*> Dhall.field "resolvedPlan" Dhall.strictText
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
loadTrainingRunConfig path = do
  config <- Dhall.inputFile trainingRunConfigDecoder path
  either (fail . Text.unpack) pure (validateTrainingRunConfig config)

loadTuneRunConfig :: FilePath -> IO TuneRunConfig
loadTuneRunConfig = Dhall.inputFile tuneRunConfigDecoder

loadAlphaZeroRunConfig :: FilePath -> IO AlphaZeroRunConfig
loadAlphaZeroRunConfig = Dhall.inputFile alphaZeroRunConfigDecoder

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
tryLoadTrainingRunConfig =
  tryLoadValidatedFile trainingRunConfigDecoder validateTrainingRunConfig

tryLoadTuneRunConfig :: FilePath -> IO (RunConfigLoadResult TuneRunConfig)
tryLoadTuneRunConfig = tryLoadValidatedFile tuneRunConfigDecoder validateTuneRunConfig

tryLoadAlphaZeroRunConfig :: FilePath -> IO (RunConfigLoadResult AlphaZeroRunConfig)
tryLoadAlphaZeroRunConfig =
  tryLoadValidatedFile alphaZeroRunConfigDecoder validateAlphaZeroRunConfig

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

validateTuneRunConfig :: TuneRunConfig -> Either Text TuneRunConfig
validateTuneRunConfig config = do
  _ <- tuningPlanFromRunConfig config
  requireNonEmpty "TuneRunConfig pulsarWsUrl" (turcPulsarWsUrl config)
  pure config

validateTrainingRunConfig :: TrainingRunConfig -> Either Text TrainingRunConfig
validateTrainingRunConfig config = do
  _ <- supervisedPlanFromRunConfig config
  requireNonEmpty "TrainingRunConfig pulsarWsUrl" (trcPulsarWsUrl config)
  pure config

validateAlphaZeroRunConfig :: AlphaZeroRunConfig -> Either Text AlphaZeroRunConfig
validateAlphaZeroRunConfig config = do
  _ <- alphaZeroPlanFromRunConfig config
  requireNonEmpty "AlphaZeroRunConfig pulsarWsUrl" (azrcPulsarWsUrl config)
  pure config

tuningPlanFromRunConfig :: TuneRunConfig -> Either Text TuningPlan
tuningPlanFromRunConfig config = do
  plan <- decodePlan "TuneRunConfig resolvedPlan" (parseTuningPlanTransport (turcResolvedPlan config))
  requireEqual "TuneRunConfig planId" (planIdText (tuningPlanId plan)) (turcPlanId config)
  requireEqual
    "TuneRunConfig canonical resolvedPlan"
    (renderTuningPlanTransport plan)
    (turcResolvedPlan config)
  pure plan

alphaZeroPlanFromRunConfig :: AlphaZeroRunConfig -> Either Text AlphaZeroPlan
alphaZeroPlanFromRunConfig config = do
  plan <-
    decodePlan "AlphaZeroRunConfig resolvedPlan" (parseAlphaZeroPlanTransport (azrcResolvedPlan config))
  requireEqual "AlphaZeroRunConfig planId" (planIdText (alphaZeroPlanId plan)) (azrcPlanId config)
  requireEqual
    "AlphaZeroRunConfig canonical resolvedPlan"
    (renderAlphaZeroPlanTransport plan)
    (azrcResolvedPlan config)
  pure plan

supervisedPlanFromRunConfig :: TrainingRunConfig -> Either Text SupervisedPlan
supervisedPlanFromRunConfig config = do
  plan <-
    decodePlan
      "TrainingRunConfig resolvedPlan"
      (parseSupervisedPlanTransport (trcResolvedPlan config))
  requireEqual
    "TrainingRunConfig planId"
    (planIdText (supervisedPlanId plan))
    (trcPlanId config)
  requireEqual
    "TrainingRunConfig canonical resolvedPlan"
    (renderSupervisedPlanTransport plan)
    (trcResolvedPlan config)
  pure plan

decodePlan
  :: (Show error)
  => Text
  -> Validation (NonEmpty error) value
  -> Either Text value
decodePlan label =
  first (((label <> ": ") <>) . Text.pack . show) . validationToEither

requireNonEmpty :: Text -> Text -> Either Text ()
requireNonEmpty label value =
  when (Text.null (Text.strip value)) (Left (label <> " must be non-empty"))

requireEqual :: (Eq value, Show value) => Text -> value -> value -> Either Text ()
requireEqual label expected observed =
  unless (expected == observed) $
    Left
      ( label
          <> " mismatch: expected "
          <> Text.pack (show expected)
          <> ", observed "
          <> Text.pack (show observed)
      )

renderOptionalText :: Maybe Text -> Text
renderOptionalText Nothing = "None Text"
renderOptionalText (Just t) = "Some " <> quote t

quote :: Text -> Text
quote t = "\"" <> t <> "\""

renderTrainingRunConfigDhall :: TrainingRunConfig -> Text
renderTrainingRunConfigDhall c =
  Text.unlines
    [ "{ planId = " <> quote (trcPlanId c)
    , ", resolvedPlan = " <> quote (trcResolvedPlan c)
    , ", pulsarWsUrl = " <> quote (trcPulsarWsUrl c)
    , "}"
    ]

renderTuneRunConfigDhall :: TuneRunConfig -> Text
renderTuneRunConfigDhall c =
  Text.unlines
    [ "{ planId = " <> quote (turcPlanId c)
    , ", resolvedPlan = " <> quote (turcResolvedPlan c)
    , ", pulsarWsUrl = " <> quote (turcPulsarWsUrl c)
    , "}"
    ]

renderAlphaZeroRunConfigDhall :: AlphaZeroRunConfig -> Text
renderAlphaZeroRunConfigDhall c =
  Text.unlines
    [ "{ planId = " <> quote (azrcPlanId c)
    , ", resolvedPlan = " <> quote (azrcResolvedPlan c)
    , ", pulsarWsUrl = " <> quote (azrcPulsarWsUrl c)
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
