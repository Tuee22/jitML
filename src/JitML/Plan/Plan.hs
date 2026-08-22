{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StandaloneDeriving #-}

module JitML.Plan.Plan
  ( CommandInputs (..)
  , CommandResult (..)
  , EventId
  , FiniteMeasurement
  , Plan (..)
  , PlanError (..)
  , PlanId
  , PlanStep (..)
  , Quantity
  , RawRunBudget (..)
  , RawRunRequest (..)
  , RunKind (..)
  , RunKindWitness (..)
  , RunPlacement (..)
  , RunPlan
  , SeedCohort
  , Unit (..)
  , Validation (..)
  , buildCommandPlan
  , deriveEventId
  , deriveEventIdForPlanId
  , eventIdText
  , finiteMeasurementValue
  , mkFiniteMeasurement
  , mkQuantity
  , planIdFromCanonicalText
  , planIdText
  , refinePlanIdText
  , quantityValue
  , resolveRun
  , runPlanArtifactId
  , runPlanAlphaZeroBudget
  , runPlanBudgetSummary
  , runPlanExperimentId
  , runPlanId
  , runPlanPlacement
  , runPlanRlBudget
  , runPlanSeeds
  , runPlanSubjectId
  , runPlanSubstrate
  , runPlanSupervisedBudget
  , runPlanTopicId
  , runPlanTuningBudget
  , runPlanVersion
  , seedCohortValues
  , validationToEither
  )
where

import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString qualified as ByteString
import Data.Char (intToDigit, isDigit)
import Data.List qualified as List
import Data.List.NonEmpty (NonEmpty (..))
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Word (Word64)

import JitML.Substrate (Substrate (..), renderSubstrate)

-- | A small accumulating validation type.  Unlike 'Either', the Applicative
-- instance retains every independent error, which is the required boundary
-- behavior for raw run requests.
data Validation error value
  = Failure error
  | Success value
  deriving stock (Eq, Show)

instance Functor (Validation error) where
  fmap _ (Failure err) = Failure err
  fmap f (Success value) = Success (f value)

instance (Semigroup error) => Applicative (Validation error) where
  pure = Success
  Failure left <*> Failure right = Failure (left <> right)
  Failure err <*> Success _ = Failure err
  Success _ <*> Failure err = Failure err
  Success f <*> Success value = Success (f value)

validationToEither :: Validation error value -> Either error value
validationToEither (Failure err) = Left err
validationToEither (Success value) = Right value

data RunKind
  = SupervisedTraining
  | ReinforcementLearning
  | HyperparameterTuning
  | AlphaZeroSelfPlay

data RunKindWitness (kind :: RunKind) where
  SupervisedTrainingWitness :: RunKindWitness 'SupervisedTraining
  ReinforcementLearningWitness :: RunKindWitness 'ReinforcementLearning
  HyperparameterTuningWitness :: RunKindWitness 'HyperparameterTuning
  AlphaZeroSelfPlayWitness :: RunKindWitness 'AlphaZeroSelfPlay

deriving instance Eq (RunKindWitness kind)
deriving instance Show (RunKindWitness kind)

data Unit
  = Epoch
  | EnvTransition
  | RolloutTickPerEnv
  | VectorEnvironment
  | EpisodeStep
  | EvaluationEpisode
  | OptimizerUpdate
  | Trial
  | Generation
  | TrainingExample
  | EvaluationExample
  | BatchExample
  | ParallelTrial
  | Promotion
  | PerTrialOptimizerUpdate
  | SelfPlayGame
  | MctsSimulationPerMove
  | AlphaZeroPly
  | AlphaZeroOptimizerUpdate
  | ArenaGame

newtype Quantity (unit :: Unit) = Quantity Word64
  deriving stock (Eq, Ord, Show)

quantityValue :: Quantity unit -> Word64
quantityValue (Quantity value) = value

newtype FiniteMeasurement = FiniteMeasurement Double
  deriving stock (Eq, Ord, Show)

finiteMeasurementValue :: FiniteMeasurement -> Double
finiteMeasurementValue (FiniteMeasurement value) = value

newtype SeedCohort = SeedCohort (NonEmpty Word64)
  deriving stock (Eq, Ord, Show)

seedCohortValues :: SeedCohort -> NonEmpty Word64
seedCohortValues (SeedCohort values) = values

newtype PlanId = PlanId Text
  deriving stock (Eq, Ord, Show)

planIdText :: PlanId -> Text
planIdText (PlanId value) = value

-- | Refine an already-derived SHA-256 plan identity from a raw wire or
-- persistence field. This validates the canonical lowercase hexadecimal
-- representation; it never hashes or otherwise changes the observed value.
refinePlanIdText :: Text -> Either Text PlanId
refinePlanIdText raw
  | Text.length raw == 64 && Text.all isLowerHex raw = Right (PlanId raw)
  | otherwise = Left "plan-id must be exactly 64 lowercase hexadecimal characters"
 where
  isLowerHex char = isDigit char || (char >= 'a' && char <= 'f')

newtype EventId = EventId Text
  deriving stock (Eq, Ord, Show)

eventIdText :: EventId -> Text
eventIdText (EventId value) = value

data RunPlacement
  = ClusterRun
  | HostRun
  | InProcessRun
  deriving stock (Eq, Ord, Show)

data PlanError
  = EmptyPlanField Text
  | UnsupportedRunPlanVersion Word64
  | NonPositiveQuantity Text
  | QuantityOutOfRange Text Integer
  | QuantityExceeds Text Integer Text Integer
  | DerivedQuantityMismatch Text Integer Integer
  | NonFiniteMeasurement Text
  | EmptySeedCohort
  | DuplicateSeed Word64
  | InvalidRunPlacement Substrate RunPlacement
  | InvalidPlanId Text
  | EmptyEventKind
  | EmptyEventLogicalKey
  deriving stock (Eq, Ord, Show)

data RawRunBudget (kind :: RunKind) where
  RawSupervisedBudget
    :: { rawSupervisedEpochs :: Integer
       , rawSupervisedTrainingExamples :: Integer
       , rawSupervisedEvaluationExamples :: Integer
       , rawSupervisedBatchExamples :: Integer
       , rawSupervisedOptimizerUpdates :: Integer
       }
    -> RawRunBudget 'SupervisedTraining
  RawRlBudget
    :: { rawRlEnvironmentTransitions :: Integer
       , rawRlRolloutTicksPerEnv :: Integer
       , rawRlVectorEnvironments :: Integer
       , rawRlEpisodeSteps :: Integer
       , rawRlEvaluationEpisodes :: Integer
       }
    -> RawRunBudget 'ReinforcementLearning
  RawTuningBudget
    :: { rawTuningTrials :: Integer
       , rawTuningParallelTrials :: Integer
       , rawTuningPromotions :: Integer
       , rawTuningPerTrialOptimizerUpdates :: Integer
       }
    -> RawRunBudget 'HyperparameterTuning
  RawAlphaZeroBudget
    :: { rawAlphaZeroGenerations :: Integer
       , rawAlphaZeroSelfPlayGamesPerGeneration :: Integer
       , rawAlphaZeroMctsSimulationsPerMove :: Integer
       , rawAlphaZeroMaxPliesPerGame :: Integer
       , rawAlphaZeroOptimizerUpdatesPerGeneration :: Integer
       , rawAlphaZeroArenaGames :: Integer
       }
    -> RawRunBudget 'AlphaZeroSelfPlay

deriving instance Eq (RawRunBudget kind)
deriving instance Show (RawRunBudget kind)

data RawRunRequest (kind :: RunKind) = RawRunRequest
  { rawRunVersion :: Word64
  , rawRunKind :: RunKindWitness kind
  , rawRunExperimentId :: Text
  , rawRunSubjectId :: Text
  , rawRunArtifactId :: Text
  , rawRunTopicId :: Text
  , rawRunSubstrate :: Substrate
  , rawRunPlacement :: RunPlacement
  , rawRunSeeds :: [Word64]
  , rawRunBudget :: RawRunBudget kind
  }

deriving instance Eq (RawRunRequest kind)
deriving instance Show (RawRunRequest kind)

data RunBudget (kind :: RunKind) where
  SupervisedBudget
    :: Quantity 'Epoch
    -> Quantity 'TrainingExample
    -> Quantity 'EvaluationExample
    -> Quantity 'BatchExample
    -> Quantity 'OptimizerUpdate
    -> RunBudget 'SupervisedTraining
  RlBudget
    :: Quantity 'EnvTransition
    -> Quantity 'RolloutTickPerEnv
    -> Quantity 'VectorEnvironment
    -> Quantity 'EpisodeStep
    -> Quantity 'EvaluationEpisode
    -> RunBudget 'ReinforcementLearning
  TuningBudget
    :: Quantity 'Trial
    -> Quantity 'ParallelTrial
    -> Quantity 'Promotion
    -> Quantity 'PerTrialOptimizerUpdate
    -> RunBudget 'HyperparameterTuning
  AlphaZeroBudget
    :: Quantity 'Generation
    -> Quantity 'SelfPlayGame
    -> Quantity 'MctsSimulationPerMove
    -> Quantity 'AlphaZeroPly
    -> Quantity 'AlphaZeroOptimizerUpdate
    -> Quantity 'ArenaGame
    -> RunBudget 'AlphaZeroSelfPlay

deriving instance Eq (RunBudget kind)
deriving instance Show (RunBudget kind)

-- | A resolved run plan.  Its constructor is intentionally private: callers
-- receive one only through 'resolveRun'.
data RunPlan (kind :: RunKind) = RunPlan
  { resolvedPlanVersion :: Word64
  , resolvedPlanKind :: RunKindWitness kind
  , resolvedPlanExperimentId :: Text
  , resolvedPlanSubjectId :: Text
  , resolvedPlanArtifactId :: Text
  , resolvedPlanTopicId :: Text
  , resolvedPlanSubstrate :: Substrate
  , resolvedPlanPlacement :: RunPlacement
  , resolvedPlanSeeds :: SeedCohort
  , resolvedPlanBudget :: RunBudget kind
  , resolvedPlanIdentity :: PlanId
  }

deriving instance Eq (RunPlan kind)
deriving instance Show (RunPlan kind)

-- These are ordinary read-only functions rather than exported record field
-- selectors.  Exporting a selector for a hidden constructor would still allow
-- downstream record update to forge a resolved plan.
runPlanVersion :: RunPlan kind -> Word64
runPlanVersion = resolvedPlanVersion

runPlanExperimentId :: RunPlan kind -> Text
runPlanExperimentId = resolvedPlanExperimentId

runPlanSubjectId :: RunPlan kind -> Text
runPlanSubjectId = resolvedPlanSubjectId

runPlanArtifactId :: RunPlan kind -> Text
runPlanArtifactId = resolvedPlanArtifactId

runPlanTopicId :: RunPlan kind -> Text
runPlanTopicId = resolvedPlanTopicId

runPlanSubstrate :: RunPlan kind -> Substrate
runPlanSubstrate = resolvedPlanSubstrate

runPlanPlacement :: RunPlan kind -> RunPlacement
runPlanPlacement = resolvedPlanPlacement

runPlanSeeds :: RunPlan kind -> SeedCohort
runPlanSeeds = resolvedPlanSeeds

runPlanId :: RunPlan kind -> PlanId
runPlanId = resolvedPlanIdentity

mkQuantity
  :: Text
  -> Integer
  -> Validation (NonEmpty PlanError) (Quantity unit)
mkQuantity label value
  | value <= 0 = failure (NonPositiveQuantity label)
  | value > toInteger (maxBound :: Word64) = failure (QuantityOutOfRange label value)
  | otherwise = Success (Quantity (fromInteger value))

mkFiniteMeasurement
  :: Text
  -> Double
  -> Validation (NonEmpty PlanError) FiniteMeasurement
mkFiniteMeasurement label value
  | isNaN value || isInfinite value = failure (NonFiniteMeasurement label)
  | otherwise = Success (FiniteMeasurement value)

resolveRun
  :: RawRunRequest kind
  -> Validation (NonEmpty PlanError) (RunPlan kind)
resolveRun raw =
  buildResolved
    <$> validateRunPlanVersion (rawRunVersion raw)
    <*> validateNonEmpty "experiment-id" (rawRunExperimentId raw)
    <*> validateNonEmpty "subject-id" (rawRunSubjectId raw)
    <*> validateNonEmpty "artifact-id" (rawRunArtifactId raw)
    <*> validateNonEmpty "topic-id" (rawRunTopicId raw)
    <*> validatePlacement (rawRunSubstrate raw) (rawRunPlacement raw)
    <*> validateSeedCohort (rawRunSeeds raw)
    <*> validateBudget (rawRunBudget raw)
 where
  buildResolved version experimentId subjectId artifactId topicId placement seeds budget =
    let planWithoutId =
          ( version
          , rawRunKind raw
          , experimentId
          , subjectId
          , artifactId
          , topicId
          , rawRunSubstrate raw
          , placement
          , seeds
          , budget
          )
        identity = PlanId (sha256Text (canonicalPlan planWithoutId))
     in RunPlan
          { resolvedPlanVersion = version
          , resolvedPlanKind = rawRunKind raw
          , resolvedPlanExperimentId = experimentId
          , resolvedPlanSubjectId = subjectId
          , resolvedPlanArtifactId = artifactId
          , resolvedPlanTopicId = topicId
          , resolvedPlanSubstrate = rawRunSubstrate raw
          , resolvedPlanPlacement = placement
          , resolvedPlanSeeds = seeds
          , resolvedPlanBudget = budget
          , resolvedPlanIdentity = identity
          }

validateBudget
  :: RawRunBudget kind
  -> Validation (NonEmpty PlanError) (RunBudget kind)
validateBudget rawBudget =
  case rawBudget of
    RawSupervisedBudget epochs trainingExamples evaluationExamples batchExamples optimizerUpdates ->
      SupervisedBudget
        <$> mkQuantity "epochs" epochs
        <*> mkQuantity "training-examples" trainingExamples
        <*> mkQuantity "evaluation-examples" evaluationExamples
        <*> mkQuantity "batch-examples" batchExamples
        <*> mkQuantity "optimizer-updates" optimizerUpdates
        <* validateDerivedOptimizerUpdates
          epochs
          trainingExamples
          batchExamples
          optimizerUpdates
    RawRlBudget
      transitions
      rolloutTicks
      vectorEnvironments
      episodeSteps
      evaluationEpisodes ->
        RlBudget
          <$> mkQuantity "environment-transitions" transitions
          <*> mkQuantity "rollout-ticks-per-environment" rolloutTicks
          <*> mkQuantity "vector-environments" vectorEnvironments
          <*> mkQuantity "episode-steps" episodeSteps
          <*> mkQuantity "evaluation-episodes" evaluationEpisodes
    RawTuningBudget trials parallelTrials promotions perTrialOptimizerUpdates ->
      TuningBudget
        <$> mkQuantity "trials" trials
        <*> mkQuantity "parallel-trials" parallelTrials
        <*> mkQuantity "promotions" promotions
        <*> mkQuantity "per-trial-optimizer-updates" perTrialOptimizerUpdates
        <* validateAtMost "parallel-trials" parallelTrials "trials" trials
        <* validateAtMost "promotions" promotions "trials" trials
    RawAlphaZeroBudget generations selfPlayGames simulations maxPlies optimizerUpdates arenaGames ->
      AlphaZeroBudget
        <$> mkQuantity "generations" generations
        <*> mkQuantity "self-play-games-per-generation" selfPlayGames
        <*> mkQuantity "mcts-simulations-per-move" simulations
        <*> mkQuantity "max-plies-per-game" maxPlies
        <*> mkQuantity "optimizer-updates-per-generation" optimizerUpdates
        <*> mkQuantity "arena-games" arenaGames

validateNonEmpty :: Text -> Text -> Validation (NonEmpty PlanError) Text
validateNonEmpty label value
  | Text.null normalized = failure (EmptyPlanField label)
  | otherwise = Success normalized
 where
  normalized = Text.strip value

validateAtMost
  :: Text
  -> Integer
  -> Text
  -> Integer
  -> Validation (NonEmpty PlanError) ()
validateAtMost smallerLabel smaller largerLabel larger
  | smaller <= 0 || larger <= 0 = Success ()
  | smaller <= larger = Success ()
  | otherwise = failure (QuantityExceeds smallerLabel smaller largerLabel larger)

validateDerivedOptimizerUpdates
  :: Integer
  -> Integer
  -> Integer
  -> Integer
  -> Validation (NonEmpty PlanError) ()
validateDerivedOptimizerUpdates epochs trainingExamples batchExamples observed
  | any (<= 0) [epochs, trainingExamples, batchExamples, observed] = Success ()
  | observed == expected = Success ()
  | otherwise = failure (DerivedQuantityMismatch "optimizer-updates" expected observed)
 where
  expected = epochs * ceilingDivide trainingExamples batchExamples

ceilingDivide :: Integer -> Integer -> Integer
ceilingDivide numerator denominator =
  (numerator + denominator - 1) `div` denominator

validateRunPlanVersion :: Word64 -> Validation (NonEmpty PlanError) Word64
validateRunPlanVersion 1 = Success 1
validateRunPlanVersion version = failure (UnsupportedRunPlanVersion version)

validatePlacement
  :: Substrate
  -> RunPlacement
  -> Validation (NonEmpty PlanError) RunPlacement
validatePlacement AppleSilicon HostRun = Success HostRun
validatePlacement LinuxCPU ClusterRun = Success ClusterRun
validatePlacement LinuxCUDA ClusterRun = Success ClusterRun
validatePlacement _ InProcessRun = Success InProcessRun
validatePlacement substrate placement = failure (InvalidRunPlacement substrate placement)

validateSeedCohort :: [Word64] -> Validation (NonEmpty PlanError) SeedCohort
validateSeedCohort [] = failure EmptySeedCohort
validateSeedCohort seeds =
  case duplicateSeeds canonicalSeeds of
    [] ->
      case canonicalSeeds of
        firstSeed : rest -> Success (SeedCohort (firstSeed :| rest))
        [] -> failure EmptySeedCohort
    firstDuplicate : restDuplicates ->
      Failure (DuplicateSeed firstDuplicate :| fmap DuplicateSeed restDuplicates)
 where
  canonicalSeeds = List.sort seeds

duplicateSeeds :: [Word64] -> [Word64]
duplicateSeeds values =
  Set.toAscList
    ( snd
        ( foldl
            ( \(seen, duplicates) value ->
                if value `Set.member` seen
                  then (seen, Set.insert value duplicates)
                  else (Set.insert value seen, duplicates)
            )
            (Set.empty, Set.empty)
            values
        )
    )

runPlanBudgetSummary :: RunPlan kind -> [(Text, Word64)]
runPlanBudgetSummary plan =
  case resolvedPlanBudget plan of
    SupervisedBudget epochs trainingExamples evaluationExamples batchExamples optimizerUpdates ->
      [ ("epochs", quantityValue epochs)
      , ("training-examples", quantityValue trainingExamples)
      , ("evaluation-examples", quantityValue evaluationExamples)
      , ("batch-examples", quantityValue batchExamples)
      , ("optimizer-updates", quantityValue optimizerUpdates)
      ]
    RlBudget
      transitions
      rolloutTicks
      vectorEnvironments
      episodeSteps
      evaluationEpisodes ->
        [ ("environment-transitions", quantityValue transitions)
        , ("rollout-ticks-per-environment", quantityValue rolloutTicks)
        , ("vector-environments", quantityValue vectorEnvironments)
        , ("episode-steps", quantityValue episodeSteps)
        , ("evaluation-episodes", quantityValue evaluationEpisodes)
        ]
    TuningBudget trials parallelTrials promotions perTrialOptimizerUpdates ->
      [ ("trials", quantityValue trials)
      , ("parallel-trials", quantityValue parallelTrials)
      , ("promotions", quantityValue promotions)
      , ("per-trial-optimizer-updates", quantityValue perTrialOptimizerUpdates)
      ]
    AlphaZeroBudget generations selfPlayGames simulations maxPlies optimizerUpdates arenaGames ->
      [ ("generations", quantityValue generations)
      , ("self-play-games-per-generation", quantityValue selfPlayGames)
      , ("mcts-simulations-per-move", quantityValue simulations)
      , ("max-plies-per-game", quantityValue maxPlies)
      , ("optimizer-updates-per-generation", quantityValue optimizerUpdates)
      , ("arena-games", quantityValue arenaGames)
      ]

runPlanTuningBudget
  :: RunPlan 'HyperparameterTuning
  -> ( Quantity 'Trial
     , Quantity 'ParallelTrial
     , Quantity 'Promotion
     , Quantity 'PerTrialOptimizerUpdate
     )
runPlanTuningBudget plan =
  case resolvedPlanBudget plan of
    TuningBudget trials parallelTrials promotions perTrialOptimizerUpdates ->
      (trials, parallelTrials, promotions, perTrialOptimizerUpdates)

runPlanRlBudget
  :: RunPlan 'ReinforcementLearning
  -> ( Quantity 'EnvTransition
     , Quantity 'RolloutTickPerEnv
     , Quantity 'VectorEnvironment
     , Quantity 'EpisodeStep
     , Quantity 'EvaluationEpisode
     )
runPlanRlBudget plan =
  case resolvedPlanBudget plan of
    RlBudget
      transitions
      rolloutTicks
      vectorEnvironments
      episodeSteps
      evaluationEpisodes ->
        ( transitions
        , rolloutTicks
        , vectorEnvironments
        , episodeSteps
        , evaluationEpisodes
        )

runPlanSupervisedBudget
  :: RunPlan 'SupervisedTraining
  -> ( Quantity 'Epoch
     , Quantity 'TrainingExample
     , Quantity 'EvaluationExample
     , Quantity 'BatchExample
     , Quantity 'OptimizerUpdate
     )
runPlanSupervisedBudget plan =
  case resolvedPlanBudget plan of
    SupervisedBudget epochs trainingExamples evaluationExamples batchExamples optimizerUpdates ->
      (epochs, trainingExamples, evaluationExamples, batchExamples, optimizerUpdates)

runPlanAlphaZeroBudget
  :: RunPlan 'AlphaZeroSelfPlay
  -> ( Quantity 'Generation
     , Quantity 'SelfPlayGame
     , Quantity 'MctsSimulationPerMove
     , Quantity 'AlphaZeroPly
     , Quantity 'AlphaZeroOptimizerUpdate
     , Quantity 'ArenaGame
     )
runPlanAlphaZeroBudget plan =
  case resolvedPlanBudget plan of
    AlphaZeroBudget generations selfPlayGames simulations maxPlies optimizerUpdates arenaGames ->
      (generations, selfPlayGames, simulations, maxPlies, optimizerUpdates, arenaGames)

planIdFromCanonicalText
  :: Text
  -> Validation (NonEmpty PlanError) PlanId
planIdFromCanonicalText canonical =
  PlanId . sha256Text . ("jitml-plan-id-v1\NUL" <>)
    <$> validateNonEmpty "canonical-plan" canonical

deriveEventId
  :: RunPlan kind
  -> Text
  -> Text
  -> Validation (NonEmpty PlanError) EventId
deriveEventId plan = deriveEventIdForPlanId (runPlanId plan)

deriveEventIdForPlanId
  :: PlanId
  -> Text
  -> Text
  -> Validation (NonEmpty PlanError) EventId
deriveEventIdForPlanId planId rawKind rawLogicalKey =
  buildEventId
    <$> validateEventKind rawKind
    <*> validateEventLogicalKey rawLogicalKey
 where
  buildEventId kind logicalKey =
    EventId
      ( sha256Text
          ( Text.intercalate
              "\NUL"
              [ "jitml-event-id-v1"
              , planIdText planId
              , kind
              , logicalKey
              ]
          )
      )

validateEventKind :: Text -> Validation (NonEmpty PlanError) Text
validateEventKind value
  | Text.null normalized = failure EmptyEventKind
  | otherwise = Success normalized
 where
  normalized = Text.strip value

validateEventLogicalKey :: Text -> Validation (NonEmpty PlanError) Text
validateEventLogicalKey value
  | Text.null normalized = failure EmptyEventLogicalKey
  | otherwise = Success normalized
 where
  normalized = Text.strip value

canonicalPlan
  :: ( Word64
     , RunKindWitness kind
     , Text
     , Text
     , Text
     , Text
     , Substrate
     , RunPlacement
     , SeedCohort
     , RunBudget kind
     )
  -> Text
canonicalPlan (version, kind, experimentId, subjectId, artifactId, topicId, substrate, placement, seeds, budget) =
  canonicalFields
    ( [ "jitml-run-plan-v1"
      , Text.pack (show version)
      , renderRunKind kind
      , experimentId
      , subjectId
      , artifactId
      , topicId
      , renderSubstrate substrate
      , renderPlacement placement
      ]
        <> fmap (Text.pack . show) (List.sort (toListNonEmpty (seedCohortValues seeds)))
        <> concatMap (\(label, value) -> [label, Text.pack (show value)]) (budgetSummary budget)
    )

budgetSummary :: RunBudget kind -> [(Text, Word64)]
budgetSummary budget =
  case budget of
    SupervisedBudget epochs trainingExamples evaluationExamples batchExamples optimizerUpdates ->
      [ ("epochs", quantityValue epochs)
      , ("training-examples", quantityValue trainingExamples)
      , ("evaluation-examples", quantityValue evaluationExamples)
      , ("batch-examples", quantityValue batchExamples)
      , ("optimizer-updates", quantityValue optimizerUpdates)
      ]
    RlBudget
      transitions
      rolloutTicks
      vectorEnvironments
      episodeSteps
      evaluationEpisodes ->
        [ ("environment-transitions", quantityValue transitions)
        , ("rollout-ticks-per-environment", quantityValue rolloutTicks)
        , ("vector-environments", quantityValue vectorEnvironments)
        , ("episode-steps", quantityValue episodeSteps)
        , ("evaluation-episodes", quantityValue evaluationEpisodes)
        ]
    TuningBudget trials parallelTrials promotions perTrialOptimizerUpdates ->
      [ ("trials", quantityValue trials)
      , ("parallel-trials", quantityValue parallelTrials)
      , ("promotions", quantityValue promotions)
      , ("per-trial-optimizer-updates", quantityValue perTrialOptimizerUpdates)
      ]
    AlphaZeroBudget generations selfPlayGames simulations maxPlies optimizerUpdates arenaGames ->
      [ ("generations", quantityValue generations)
      , ("self-play-games-per-generation", quantityValue selfPlayGames)
      , ("mcts-simulations-per-move", quantityValue simulations)
      , ("max-plies-per-game", quantityValue maxPlies)
      , ("optimizer-updates-per-generation", quantityValue optimizerUpdates)
      , ("arena-games", quantityValue arenaGames)
      ]

renderRunKind :: RunKindWitness kind -> Text
renderRunKind SupervisedTrainingWitness = "supervised-training"
renderRunKind ReinforcementLearningWitness = "reinforcement-learning"
renderRunKind HyperparameterTuningWitness = "hyperparameter-tuning"
renderRunKind AlphaZeroSelfPlayWitness = "alphazero-self-play"

renderPlacement :: RunPlacement -> Text
renderPlacement ClusterRun = "cluster"
renderPlacement HostRun = "host"
renderPlacement InProcessRun = "in-process"

canonicalFields :: [Text] -> Text
canonicalFields =
  Text.concat . fmap (\field -> Text.pack (show (Text.length field)) <> ":" <> field)

sha256Text :: Text -> Text
sha256Text =
  Text.pack
    . concatMap byteHex
    . ByteString.unpack
    . SHA256.hash
    . Text.Encoding.encodeUtf8
 where
  byteHex byte =
    [ intToDigit (fromIntegral byte `div` 16)
    , intToDigit (fromIntegral byte `mod` 16)
    ]

toListNonEmpty :: NonEmpty value -> [value]
toListNonEmpty (firstValue :| restValues) = firstValue : restValues

failure :: PlanError -> Validation (NonEmpty PlanError) value
failure err = Failure (err :| [])

data Plan inputs result = Plan
  { planName :: Text
  , planInputs :: inputs
  , planSteps :: [PlanStep]
  , planResult :: result
  }
  deriving stock (Eq, Show)

data PlanStep = PlanStep
  { stepName :: Text
  , stepDescription :: Text
  }
  deriving stock (Eq, Show)

data CommandInputs = CommandInputs
  { inputCommand :: Text
  , inputOptions :: [(Text, [Text])]
  }
  deriving stock (Eq, Show)

newtype CommandResult = CommandResult
  { resultSummary :: Text
  }
  deriving stock (Eq, Show)

buildCommandPlan :: [Text] -> [(Text, [Text])] -> Either Text (Plan CommandInputs CommandResult)
buildCommandPlan path optionPairs =
  Right
    Plan
      { planName = "command plan"
      , planInputs =
          CommandInputs
            { inputCommand = commandText
            , inputOptions = optionPairs
            }
      , planSteps =
          commandPlanSteps path
      , planResult =
          CommandResult
            { resultSummary = "No side effects are performed while rendering a plan."
            }
      }
 where
  commandText = Text.unwords ("jitml" : path)

commandPlanSteps :: [Text] -> [PlanStep]
commandPlanSteps ["bootstrap"] =
  [ PlanStep "check-prerequisites" "Reconcile the cluster prerequisite graph."
  , PlanStep "render-kind-config" "Write kind/cluster-<substrate>.yaml from the typed KindConfig."
  , PlanStep
      "render-chart"
      "Write the storage, gateway, route, platform-service, daemon, and demo manifests."
  , PlanStep
      "build-helm-dependencies"
      "Prepare subchart dependencies with the typed helm dependency build chart subprocess before live apply."
  , PlanStep
      "publish-runtime"
      "Write ./.build/runtime/cluster-publication.json and per-substrate Dhall."
  ]
commandPlanSteps ["cluster", "up"] =
  [ PlanStep "materialize-substrate" "Render the selected substrate's Kind and chart inputs."
  , PlanStep "build-helm-dependencies" "Prepare subchart dependencies with helm dependency build chart."
  , PlanStep
      "create-kind-cluster"
      "Create/export the Kind cluster kubeconfig, then copy it to ./.build/jitml.kubeconfig."
  , PlanStep "apply-chart" "Apply the umbrella Helm chart in phased order."
  ]
commandPlanSteps ["service"] =
  [ PlanStep "load-config" "Load BootConfig and LiveConfig."
  , PlanStep "acquire-capabilities" "Acquire MinIO, Pulsar, image-registry, and kubectl capabilities."
  , PlanStep "serve" "Expose health, readiness, metrics, and at-least-once consumers."
  ]
commandPlanSteps ["train"] =
  [ PlanStep "decode-experiment" "Decode supervised training Dhall into typed records."
  , PlanStep "compile-kernels" "Resolve or JIT-compile deterministic kernels."
  , PlanStep "run-training" "Run the supervised loop and emit checkpoints and TensorBoard events."
  ]
commandPlanSteps ["tune"] =
  [ PlanStep "decode-tuning" "Decode sampler, scheduler, and pruner configuration."
  , PlanStep "schedule-trials" "Produce deterministic trial candidates."
  , PlanStep "persist-frontier" "Persist trial state and Pareto frontier records."
  ]
commandPlanSteps ["rl", "train"] =
  [ PlanStep "decode-rl-experiment" "Decode environment, policy, and algorithm configuration."
  , PlanStep "run-rollouts" "Run deterministic vectorized rollouts."
  , PlanStep "update-policy" "Update the policy and checkpoint the result."
  ]
commandPlanSteps ["test", "all"] =
  [ PlanStep "run-cabal-tests" "Run every Cabal test stanza."
  , PlanStep "run-report-card" "Collect target stanza results and report-card knobs."
  , PlanStep "render-summary" "Render the typed report card."
  ]
commandPlanSteps ["internal", "gc"] =
  [ PlanStep "load-retention-policy" "Load checkpoint retention from the experiment manifest."
  , PlanStep "list-checkpoints" "List checkpoint manifests from MinIO."
  , PlanStep "delete-expired" "Delete checkpoint blobs no longer retained by the policy."
  ]
commandPlanSteps _ =
  [ PlanStep "parse-command" "Parse and validate the command surface from CommandSpec."
  , PlanStep "check-prerequisites" "Run the prerequisite gate for the command before mutation."
  , PlanStep "apply-command" "Apply the command implementation through the typed boundary."
  ]
