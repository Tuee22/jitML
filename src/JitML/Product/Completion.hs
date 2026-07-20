{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.Product.Completion
  ( SupervisedCompletionAttempt (..)
  , alphaZeroArtifactStep
  , alphaZeroCompletedTraining
  , alphaZeroCompletionBudget
  , checkedPositiveWord64FromInt
  , checkedWord64Product
  , completedTrainingForProductRow
  , completedTrainingForProductRowWithWeightHashes
  , attemptCompletedTrainingForProductRowWithWeightHashes
  , rlCompletedTraining
  , rlCompletedTrainingFailureMessage
  , rlCompletedTrainingWithBudget
  , rlCompletionMetrics
  , supervisedProductRowForProblem
  , tuneSweepCompletedTraining
  )
where

import Data.Char (isHexDigit, isUpper)
import Data.List (sort)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Maybe (listToMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word32, Word64)

import JitML.Checkpoint.WeightCodec qualified as WeightCodec
import JitML.Plan.Plan
  ( PlanId
  , planIdFromCanonicalText
  , quantityValue
  , runPlanSeeds
  , seedCohortValues
  , validationToEither
  )
import JitML.Plan.Workload qualified as WorkloadPlan
import JitML.Product.Convergence qualified as ProductConvergence
import JitML.Product.Evidence qualified as ProductEvidence
import JitML.Product.ExternalBars qualified as ProductExternalBars
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.RL.ConvergenceThresholds qualified as RLConvergence
import JitML.RL.EpisodeEnvelope qualified as EpisodeEnvelope
import JitML.RL.TrainerExecution qualified as TrainerExecution
import JitML.SL.Canonicals qualified as SL
import JitML.Training.Budget qualified as TrainingBudget
import JitML.Tune.Catalog qualified as Tune

supervisedProductRowForProblem
  :: SL.CanonicalProblem
  -> Maybe (ProductMatrix.ProductRow 'ProductMatrix.Declared)
supervisedProductRowForProblem problem =
  listToMaybe
    [ row
    | row <- ProductMatrix.allProductRows
    , ProductMatrix.family row == ProductMatrix.Supervised
    , ProductMatrix.rowId row == SL.problemName problem
    ]

-- | A fully validated supervised run can finish its exact budget without
-- clearing the externally owned convergence bar.  That is a legitimate
-- training result, but it cannot carry 'CompletedTraining' or be persisted as
-- an inference-eligible V2 checkpoint.  Structural failures remain 'Left'.
data SupervisedCompletionAttempt
  = SupervisedCompletionMiss
      !(NonEmpty.NonEmpty TrainingBudget.ConvergenceObservation)
  | SupervisedCompletionPassed !TrainingBudget.CompletedTraining
  deriving stock (Eq, Show)

completedTrainingForProductRow
  :: PlanId
  -> TrainingBudget.TrainingBudget
  -> ProductMatrix.ProductRow state
  -> Text
  -> Text
  -> Text
  -> Word64
  -> Word64
  -> [(Text, Double)]
  -> [Double]
  -> [Double]
  -> Either Text TrainingBudget.CompletedTraining
completedTrainingForProductRow planId budget row datasetShaAtRead experimentHash _tensorName observedBudgetUnits trainingUpdateCount metrics initialWeights finalWeights =
  completedTrainingForProductRowWithWeightHashes
    planId
    budget
    row
    datasetShaAtRead
    experimentHash
    observedBudgetUnits
    trainingUpdateCount
    metrics
    (jmw1WeightListSha initialWeights)
    (jmw1WeightListSha finalWeights)

-- | Mint ProductRow completion from exact physical-weight identities.
--
-- The caller has already bound each identity to the exact observed JMW1 bytes;
-- this boundary checks the canonical lowercase SHA-256 representation and does
-- not decode, re-encode, or otherwise reinterpret a weight list.
completedTrainingForProductRowWithWeightHashes
  :: PlanId
  -> TrainingBudget.TrainingBudget
  -> ProductMatrix.ProductRow state
  -> Text
  -> Text
  -> Word64
  -> Word64
  -> [(Text, Double)]
  -> Text
  -> Text
  -> Either Text TrainingBudget.CompletedTraining
completedTrainingForProductRowWithWeightHashes planId budget row datasetShaAtRead experimentHash observedBudgetUnits trainingUpdateCount metrics initialWeightHash finalWeightHash = do
  attempt <-
    attemptCompletedTrainingForProductRowWithWeightHashes
      planId
      budget
      row
      datasetShaAtRead
      experimentHash
      observedBudgetUnits
      trainingUpdateCount
      metrics
      initialWeightHash
      finalWeightHash
  case attempt of
    SupervisedCompletionPassed completed -> Right completed
    SupervisedCompletionMiss observations ->
      Left
        ( "supervised convergence criteria were not met: "
            <> Text.intercalate
              ","
              ( fmap
                  TrainingBudget.coMetricName
                  (NonEmpty.toList observations)
              )
        )

attemptCompletedTrainingForProductRowWithWeightHashes
  :: PlanId
  -> TrainingBudget.TrainingBudget
  -> ProductMatrix.ProductRow state
  -> Text
  -> Text
  -> Word64
  -> Word64
  -> [(Text, Double)]
  -> Text
  -> Text
  -> Either Text SupervisedCompletionAttempt
attemptCompletedTrainingForProductRowWithWeightHashes planId budget row datasetShaAtRead experimentHash observedBudgetUnits trainingUpdateCount metrics initialWeightHash finalWeightHash = do
  canonicalInitialHash <- requireCanonicalJmw1Sha256 "initial weight" initialWeightHash
  canonicalFinalHash <- requireCanonicalJmw1Sha256 "final weight" finalWeightHash
  if observedBudgetUnits == TrainingBudget.trainingBudgetTargetUnits budget
    then Right ()
    else
      Left
        ( "supervised observed budget does not equal the exact target (observed="
            <> Text.pack (show observedBudgetUnits)
            <> ", target="
            <> Text.pack (show (TrainingBudget.trainingBudgetTargetUnits budget))
            <> ")"
        )
  evidence <-
    ProductEvidence.mkTrainingEvidence
      canonicalInitialHash
      canonicalFinalHash
      trainingUpdateCount
      datasetShaAtRead
  observations <- convergenceObservationsForProductRow row metrics
  nonEmptyObservations <-
    maybe
      (Left "supervised completion requires at least one convergence observation")
      Right
      (NonEmpty.nonEmpty observations)
  if all TrainingBudget.convergencePassed observations
    then do
      completed <-
        TrainingBudget.completedTraining
          planId
          budget
          observedBudgetUnits
          evidence
          observations
          TrainingBudget.TensorBoardRunMetadata
            { TrainingBudget.tbrRunId = experimentHash
            , TrainingBudget.tbrLogPrefix = "jitml-tensorboard/" <> experimentHash
            , TrainingBudget.tbrScalarTags = fmap TrainingBudget.coMetricName observations
            }
      Right (SupervisedCompletionPassed completed)
    else Right (SupervisedCompletionMiss nonEmptyObservations)

-- | Compatibility identity for the non-ProductRow traditional-RL checkpoint
-- path.  Sprint 25.4 replaces that path with its resolved algorithm plan; it
-- is deliberately separate from the ProductRow projection closed here.
completionPlanIdFromCanonicalText :: Text -> Either Text PlanId
completionPlanIdFromCanonicalText canonical =
  case validationToEither (planIdFromCanonicalText canonical) of
    Right planId -> Right planId
    Left errors ->
      Left ("completion plan-id refinement failed: " <> Text.pack (show errors))

convergenceObservationsForProductRow
  :: ProductMatrix.ProductRow state
  -> [(Text, Double)]
  -> Either Text [TrainingBudget.ConvergenceObservation]
convergenceObservationsForProductRow row metrics = do
  observation <-
    ProductConvergence.evaluateConvergence
      (ProductMatrix.convergenceBar row)
      (ProductConvergence.MeasuredMetrics metrics)
  case ProductExternalBars.assertProductBarExternal
    (ProductMatrix.convergenceBar row)
    (TrainingBudget.coMetricValue observation) of
    [] -> Right [observation]
    failures -> Left (Text.intercalate "; " failures)

tuneSweepCompletedTraining
  :: WorkloadPlan.TuningPlan
  -> Text
  -> Text
  -> Word32
  -> Tune.TrialObjectiveResult
  -> Either Text TrainingBudget.CompletedTraining
tuneSweepCompletedTraining plan experimentHash datasetShaAtRead trialsCompleted bestResult =
  let observed = fromIntegral trialsCompleted
      planned = quantityValue (WorkloadPlan.tuningPlanTrials plan)
      seed = NonEmpty.head (seedCohortValues (runPlanSeeds (WorkloadPlan.tuningPlanRunPlan plan)))
      bestObjective = Tune.trialResultObjective bestResult
      metrics = [("best_objective", bestObjective)]
   in do
        if Tune.trialResultDisposition bestResult == Tune.ReachedMaxBudget
          then Right ()
          else Left "tuning completion requires a promoted trial that reached the optimizer-update ceiling"
        updateCount <-
          checkedPositiveWord64FromInt
            "tuning promoted-trial optimizer update count"
            (Tune.trialResultUpdatesExecuted bestResult)
        if updateCount == quantityValue (WorkloadPlan.tuningPlanMaxPerTrialUpdates plan)
          then Right ()
          else Left "tuning promoted-trial update count does not match the resolved plan ceiling"
        budget <-
          TrainingBudget.mkTrainingBudget
            TrainingBudget.TuningTrialBudget
            planned
            (Just seed)
        evidence <-
          ProductEvidence.mkTrainingEvidence
            (jmw1WeightListSha (Tune.trialResultInitialWeights bestResult))
            (jmw1WeightListSha (Tune.trialResultWeights bestResult))
            updateCount
            datasetShaAtRead
        observations <- convergenceObservationsForMetrics metrics
        TrainingBudget.completedTraining
          (WorkloadPlan.tuningPlanId plan)
          budget
          observed
          evidence
          observations
          TrainingBudget.TensorBoardRunMetadata
            { TrainingBudget.tbrRunId = experimentHash
            , TrainingBudget.tbrLogPrefix = "jitml-tensorboard/" <> experimentHash
            , TrainingBudget.tbrScalarTags = fmap fst metrics
            }

alphaZeroCompletedTraining
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
alphaZeroCompletedTraining planId budget experimentHash generationCount optimizerUpdateCount sampleDigest metrics initialWeights finalWeights = do
  evidence <-
    ProductEvidence.mkTrainingEvidence
      (jmw1WeightListSha initialWeights)
      (jmw1WeightListSha finalWeights)
      optimizerUpdateCount
      sampleDigest
  observations <- alphaZeroConvergenceObservations metrics
  TrainingBudget.completedTraining
    planId
    budget
    generationCount
    evidence
    observations
    TrainingBudget.TensorBoardRunMetadata
      { TrainingBudget.tbrRunId = experimentHash
      , TrainingBudget.tbrLogPrefix = "jitml-tensorboard/" <> experimentHash
      , TrainingBudget.tbrScalarTags = fmap TrainingBudget.coMetricName observations
      }

-- | AlphaZero budgets are counted in completed self-play generations. Sample
-- count remains useful diagnostic evidence, but it is not the checkpoint's
-- progress unit and can differ substantially between games and runs.
alphaZeroArtifactStep :: Word64 -> Int -> Word64
alphaZeroArtifactStep completedGenerations _sampleCount = completedGenerations

checkedWord64Product :: Text -> Word64 -> Word64 -> Either Text Word64
checkedWord64Product label left right
  | left == 0 || right == 0 = Left (label <> " factors must be positive")
  | left > maxBound `div` right = Left (label <> " exceeds the Word64 range")
  | otherwise = Right (left * right)

checkedPositiveWord64FromInt :: Text -> Int -> Either Text Word64
checkedPositiveWord64FromInt label value
  | value <= 0 = Left (label <> " must be positive")
  | toInteger value > toInteger (maxBound :: Word64) = Left (label <> " exceeds the Word64 range")
  | otherwise = Right (fromIntegral value)

alphaZeroCompletionBudget
  :: WorkloadPlan.AlphaZeroPlan
  -> Either Text TrainingBudget.TrainingBudget
alphaZeroCompletionBudget plan =
  TrainingBudget.mkTrainingBudget
    TrainingBudget.AlphaZeroSelfPlayBudget
    (quantityValue (WorkloadPlan.alphaZeroPlanGenerations plan))
    ( Just
        ( NonEmpty.head
            (seedCohortValues (runPlanSeeds (WorkloadPlan.alphaZeroPlanRunPlan plan)))
        )
    )

alphaZeroConvergenceObservations
  :: [(Text, Double)]
  -> Either Text [TrainingBudget.ConvergenceObservation]
alphaZeroConvergenceObservations metrics = do
  arenaWinRate <-
    maybe
      (Left "missing AlphaZero arena_win_rate metric")
      Right
      (lookup "arena_win_rate" metrics)
  let threshold = RLConvergence.alphaZeroArenaThreshold
      thresholdValue = RLConvergence.azTargetWinRate threshold - RLConvergence.azSlack threshold
  observation <-
    TrainingBudget.measureCriterionExcluding
      "arena_win_rate"
      TrainingBudget.MetricMaximise
      thresholdValue
      0.5
      1.0e-12
      arenaWinRate
  pure [observation]

convergenceObservationsForMetrics
  :: [(Text, Double)]
  -> Either Text [TrainingBudget.ConvergenceObservation]
convergenceObservationsForMetrics =
  ProductExternalBars.convergenceObservationsForMetrics

jmw1WeightListSha :: [Double] -> Text
jmw1WeightListSha =
  WeightCodec.jmw1ContentSha . WeightCodec.encodeJmw1

requireCanonicalJmw1Sha256 :: Text -> Text -> Either Text Text
requireCanonicalJmw1Sha256 label identity
  | Text.length identity /= 64 =
      Left (label <> " JMW1 SHA-256 identity must contain exactly 64 lowercase hexadecimal characters")
  | Text.any (not . isLowercaseHexDigit) identity =
      Left (label <> " JMW1 SHA-256 identity must contain exactly 64 lowercase hexadecimal characters")
  | otherwise = Right identity
 where
  isLowercaseHexDigit char =
    isHexDigit char && not (isUpper char)

rlCompletionMetrics
  :: Text
  -> Word64
  -> [EpisodeEnvelope.SimulatedEpisode]
  -> Either Text [(Text, Double)]
rlCompletionMetrics trainerKind observedUnits episodes = do
  evaluationObservedUnits <- TrainerExecution.rlObservedBudgetUnits episodes
  let rewards = fmap EpisodeEnvelope.simEpisodeReward episodes
      avgReward = meanOrZero rewards
      medianTail = medianValues (tailHalf rewards)
      envSteps = fromIntegral (max observedUnits evaluationObservedUnits)
      episodeCount = fromIntegral (length episodes)
      baseMetrics =
        [ ("avg_reward", avgReward)
        , ("median_final_reward", medianTail)
        , ("env_steps", envSteps)
        , ("episode_count", episodeCount)
        ]
      herMetrics =
        if trainerKind == "her"
          then
            -- Read the greedy-eval episodes directly: success = fraction that
            -- reached the goal (simEpisodeDone), achieved distance = mean
            -- normalized distance (= 1 - mean reward, since reward = 1 - dist).
            -- The old `lastOrZero rewards` read a padding zero once eval episodes
            -- exceeded the recorded training-stat intervals (so it reported 0.0),
            -- and derived distance as `1 - success` rather than a real distance.
            let reached = length (filter EpisodeEnvelope.simEpisodeDone episodes)
                successRate =
                  if null episodes
                    then 0.0
                    else fromIntegral reached / fromIntegral (length episodes)
                achievedDistance = clamp01 (1.0 - avgReward)
             in [ ("goal_success_rate", clamp01 successRate)
                , ("achieved_goal_distance", achievedDistance)
                ]
          else []
  Right (baseMetrics <> herMetrics)

rlCompletedTraining
  :: (Text -> Word64 -> Either Text TrainingBudget.TrainingBudget)
  -> Text
  -> Text
  -> Text
  -> Text
  -> Word64
  -> [(Text, Double)]
  -> ProductEvidence.TrainingEvidence
  -> Either Text (Maybe TrainingBudget.CompletedTraining)
rlCompletedTraining checkpointTrainingBudgetForTensor trainerKind envName experimentHash tensorName checkpointStep metrics evidence = do
  budget <- checkpointTrainingBudgetForTensor tensorName checkpointStep
  planId <-
    completionPlanIdFromCanonicalText
      ( Text.intercalate
          "\NUL"
          [ "jitml-rl-completion-plan-v1"
          , experimentHash
          , trainerKind
          , envName
          , TrainingBudget.renderTrainingBudget budget
          ]
      )
  Right
    ( rlCompletedTrainingWithBudget
        planId
        budget
        trainerKind
        envName
        experimentHash
        tensorName
        checkpointStep
        metrics
        evidence
    )

rlCompletedTrainingWithBudget
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
rlCompletedTrainingWithBudget planId budget trainerKind envName experimentHash _tensorName checkpointStep metrics evidence = do
  observations <- eitherToMaybe (rlConvergenceObservations trainerKind envName metrics)
  eitherToMaybe $
    TrainingBudget.completedTraining
      planId
      budget
      checkpointStep
      evidence
      observations
      TrainingBudget.TensorBoardRunMetadata
        { TrainingBudget.tbrRunId = experimentHash
        , TrainingBudget.tbrLogPrefix = "jitml-tensorboard/" <> experimentHash
        , TrainingBudget.tbrScalarTags = fmap TrainingBudget.coMetricName observations
        }

rlCompletedTrainingFailureMessage :: Text -> Text -> [(Text, Double)] -> Text
rlCompletedTrainingFailureMessage trainerKind envName metrics =
  case rlConvergenceObservations trainerKind envName metrics of
    Left err ->
      "RL row did not produce passing CompletedTraining evidence: "
        <> err
        <> "; metrics: "
        <> renderMetricPairs metrics
    Right observations ->
      "RL row did not produce passing CompletedTraining evidence: "
        <> Text.intercalate "; " (fmap renderObservation observations)
        <> "; metrics: "
        <> renderMetricPairs metrics

renderObservation :: TrainingBudget.ConvergenceObservation -> Text
renderObservation observation =
  TrainingBudget.coMetricName observation
    <> "="
    <> Text.pack (show (TrainingBudget.coMetricValue observation))
    <> " threshold="
    <> Text.pack (show (TrainingBudget.coThreshold observation))
    <> " passed="
    <> Text.toLower (Text.pack (show (TrainingBudget.convergencePassed observation)))

renderMetricPairs :: [(Text, Double)] -> Text
renderMetricPairs [] = "none"
renderMetricPairs metrics =
  Text.intercalate
    ", "
    [ name <> "=" <> Text.pack (show value)
    | (name, value) <- metrics
    ]

rlConvergenceObservations
  :: Text
  -> Text
  -> [(Text, Double)]
  -> Either Text [TrainingBudget.ConvergenceObservation]
rlConvergenceObservations trainerKind envName metrics
  | Text.toLower trainerKind == "her" = herConvergenceObservations metrics
  | otherwise = do
      algorithm <- algorithmNameForTrainer trainerKind
      threshold <-
        maybe
          (Left ("missing RL convergence threshold for " <> algorithm <> "/" <> envName))
          Right
          (RLConvergence.cohortThreshold algorithm envName)
      measured <- metricValue "median_final_reward" metrics
      let thresholdValue = RLConvergence.literatureTarget threshold - RLConvergence.slack threshold
      observation <-
        TrainingBudget.measureCriterion
          "median_final_reward"
          TrainingBudget.MetricMaximise
          thresholdValue
          measured
      pure [observation]

herConvergenceObservations
  :: [(Text, Double)]
  -> Either Text [TrainingBudget.ConvergenceObservation]
herConvergenceObservations metrics = do
  successRate <- metricValue "goal_success_rate" metrics
  achievedDistance <- metricValue "achieved_goal_distance" metrics
  let goalMetric = RLConvergence.herGoalMetric
  pure
    [ measuredObservation successRate (RLConvergence.hgmSuccessRate goalMetric)
    , measuredObservation achievedDistance (RLConvergence.hgmAchievedGoalDistance goalMetric)
    ]

measuredObservation
  :: Double -> TrainingBudget.ConvergenceObservation -> TrainingBudget.ConvergenceObservation
measuredObservation measured pinned =
  either
    (error . Text.unpack)
    id
    (TrainingBudget.remeasureCriterion measured pinned)

algorithmNameForTrainer :: Text -> Either Text Text
algorithmNameForTrainer trainerKind =
  case Text.toLower trainerKind of
    "ppo" -> Right "PPO"
    "a2c" -> Right "A2C"
    "trpo" -> Right "TRPO"
    "maskableppo" -> Right "MaskablePPO"
    "recurrentppo" -> Right "RecurrentPPO"
    "dqn" -> Right "DQN"
    "qrdqn" -> Right "QR-DQN"
    "ddpg" -> Right "DDPG"
    "td3" -> Right "TD3"
    "sac" -> Right "SAC"
    "crossq" -> Right "CrossQ"
    "tqc" -> Right "TQC"
    "ars" -> Right "ARS"
    other -> Left ("unknown RL trainer for convergence: " <> other)

metricValue :: Text -> [(Text, Double)] -> Either Text Double
metricValue name metrics =
  maybe (Left ("missing RL convergence metric: " <> name)) Right (lookup name metrics)

tailHalf :: [a] -> [a]
tailHalf [] = []
tailHalf values =
  drop (length values - max 1 (length values `div` 2)) values

meanOrZero :: [Double] -> Double
meanOrZero [] = 0.0
meanOrZero values = sum values / fromIntegral (length values)

medianValues :: [Double] -> Double
medianValues [] = 0.0
medianValues values =
  let sorted = sort values
      n = length sorted
      mid = n `div` 2
   in if even n
        then (sorted !! (mid - 1) + sorted !! mid) / 2
        else sorted !! mid

clamp01 :: Double -> Double
clamp01 value =
  max 0.0 (min 1.0 value)

eitherToMaybe :: Either a b -> Maybe b
eitherToMaybe (Right value) = Just value
eitherToMaybe (Left _) = Nothing

{-# NOINLINE alphaZeroArtifactStep #-}
{-# NOINLINE alphaZeroCompletedTraining #-}
{-# NOINLINE alphaZeroCompletionBudget #-}
{-# NOINLINE checkedPositiveWord64FromInt #-}
{-# NOINLINE checkedWord64Product #-}
{-# NOINLINE completedTrainingForProductRow #-}
{-# NOINLINE completedTrainingForProductRowWithWeightHashes #-}
{-# NOINLINE rlCompletedTraining #-}
{-# NOINLINE rlCompletedTrainingFailureMessage #-}
{-# NOINLINE rlCompletedTrainingWithBudget #-}
{-# NOINLINE rlCompletionMetrics #-}
{-# NOINLINE supervisedProductRowForProblem #-}
{-# NOINLINE tuneSweepCompletedTraining #-}
