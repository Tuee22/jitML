{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Prospective finite HER comparison data only. No old evaluator/trainer is
-- changed and no raw record here authenticates a producer or qualifies a model.
module JitML.RL.NativeHerReferences
  ( NativeHerReferenceSpec
  , NativeHerGoalSchedule
  , NativeHerGoalBlindSequence
  , RawNativeHerGoalCase (..)
  , NativeHerReferenceOutcome (..)
  , NativeHerReferenceObservation (..)
  , NativeHerReferenceExtrema (..)
  , NativeHerReferenceFamily (..)
  , nativeHerReferenceContract
  , canonicalNativeHerReferenceSpec
  , mkCanonicalNativeHerReferenceSpec
  , nativeHerSpecRowId
  , nativeHerSpecBits
  , nativeHerSpecHorizon
  , nativeHerSpecEpisodeCount
  , nativeHerSpecBaseSeed
  , nativeHerSpecEvaluationSeed
  , nativeHerSpecTrainingBudget
  , generateNativeHerGoalSchedule
  , refineNativeHerGoalSchedule
  , nativeHerScheduleSpec
  , nativeHerScheduleCases
  , allNativeHerGoalBlindSequences
  , refineNativeHerGoalBlindSequence
  , nativeHerSequenceActions
  , nativeHerSequenceId
  , evaluateNativeHerGoalBlindSequence
  , evaluateNativeHerReferenceFamily
  , evaluateHerSequenceFixture
  ) where

import Control.Monad (replicateM, unless)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU
import GHC.Float (castDoubleToWord64)
import System.Random qualified as Random

import JitML.RL.Algorithms.HerTrainer qualified as Her
import JitML.RL.Algorithms.Registry qualified as Registry
import JitML.RL.ConvergenceThresholds qualified as Thresholds
import JitML.RL.ProductBudget qualified as Budget
import JitML.Training.Budget
  ( BudgetKind (..)
  , TrainingBudget
  , trainingBudgetKind
  , trainingBudgetTargetUnits
  )

nativeHerReferenceContract :: Text
nativeHerReferenceContract = "native-her-sampler-only-goals-complete-goal-blind-sequences-v1"

-- Private constructors and ordinary observers prohibit post-refinement update.
data NativeHerReferenceSpec = NativeHerReferenceSpec !Thresholds.HerGoalMetric !Int !Int !Int !Int
  deriving stock (Eq, Show)
data NativeHerGoalSchedule = NativeHerGoalSchedule !NativeHerReferenceSpec ![RawNativeHerGoalCase]
  deriving stock (Eq, Show)
newtype NativeHerGoalBlindSequence = NativeHerGoalBlindSequence [Int]
  deriving stock (Eq, Show)

data RawNativeHerGoalCase = RawNativeHerGoalCase
  { rawNativeHerCaseId :: !Int
  , rawNativeHerGoal :: !(VU.Vector Double)
  }
  deriving stock (Eq, Show)

data NativeHerReferenceOutcome = NativeHerReferenceOutcome
  { nativeHerOutcomeCaseId :: !Int
  , nativeHerOutcomeGoal :: !(VU.Vector Double)
  , nativeHerOutcomeFinalState :: !(VU.Vector Double)
  , nativeHerOutcomeSuccess :: !Bool
  , nativeHerOutcomeNormalizedDistance :: !Double
  , nativeHerOutcomeHammingDistance :: !Int
  , nativeHerOutcomeSteps :: !Int
  , nativeHerOutcomeTerminated :: !Bool
  , nativeHerOutcomeConsumedActions :: ![Int]
  }
  deriving stock (Eq, Show)

data NativeHerReferenceObservation = NativeHerReferenceObservation
  { nativeHerObservedSequence :: !NativeHerGoalBlindSequence
  , nativeHerObservedOutcomes :: ![NativeHerReferenceOutcome]
  , nativeHerObservedSuccessCount :: !Int
  , nativeHerObservedExactMeanDistance :: !Rational
  , nativeHerObservedEvaluationTransitions :: !Integer
  }
  deriving stock (Eq, Show)

data NativeHerReferenceExtrema = NativeHerReferenceExtrema
  { nativeHerMaximumSuccessCount :: !Int
  , nativeHerMaximumSuccessSequenceIds :: ![Text]
  , nativeHerMinimumExactMeanDistance :: !Rational
  , nativeHerMinimumDistanceSequenceIds :: ![Text]
  }
  deriving stock (Eq, Show)

data NativeHerReferenceFamily = NativeHerReferenceFamily
  { nativeHerObservedSchedule :: !NativeHerGoalSchedule
  , nativeHerObservedReferences :: ![NativeHerReferenceObservation]
  , nativeHerObservedExtrema :: !NativeHerReferenceExtrema
  , nativeHerTotalEvaluationTransitions :: !Integer
  }
  deriving stock (Eq, Show)

canonicalNativeHerReferenceSpec :: Either Text NativeHerReferenceSpec
canonicalNativeHerReferenceSpec = mkCanonicalNativeHerReferenceSpec Thresholds.herGoalMetric

mkCanonicalNativeHerReferenceSpec :: Thresholds.HerGoalMetric -> Either Text NativeHerReferenceSpec
mkCanonicalNativeHerReferenceSpec row = do
  require
    (row == Thresholds.herGoalMetric)
    "native HER reference declaration differs from the exact canonical row"
  require
    (Thresholds.hgmEnvironment row == "goal-reaching")
    "native HER reference environment is not canonical"
  cohort <- Registry.mkCohort "HER" "goal-reaching"
  require
    ( Registry.cohortActionDomain cohort == Registry.GoalConditionedDomain
        && Registry.cohortTrainerKind cohort == "her"
    )
    "native HER reference cohort metadata differs"
  schedule <- Budget.canonicalProductRlSchedule "HER" "goal-reaching"
  bits <- case schedule of
    Budget.HerTrainingSchedule {} -> Right (Budget.scheduleHerEnvironmentStepsPerEpisode schedule)
    _ -> Left "native HER reference schedule is not a HER schedule"
  let base = Her.herSeed Her.defaultHerTrainConfig
      count = Budget.productRlDefaultEvaluationEpisodes
      seed = toInteger base + 104729
  require
    (bits == 6 && Her.herNumBits Her.defaultHerTrainConfig == bits && count == 20 && base == 42)
    "native HER references require the canonical six-bit six-step twenty-case base-forty-two recipe"
  require
    (seed >= toInteger (minBound :: Int) && seed <= toInteger (maxBound :: Int))
    "native HER reference evaluation seed exceeds the actual Int range"
  require
    ( trainingBudgetKind (Thresholds.hgmBudget row) == RlEnvironmentStepBudget
        && trainingBudgetTargetUnits (Thresholds.hgmBudget row)
          == Budget.scheduleObservedEnvironmentSteps schedule
    )
    "native HER reference budget differs from the canonical schedule"
  pure (NativeHerReferenceSpec row bits count base (fromInteger seed))

nativeHerSpecRowId :: NativeHerReferenceSpec -> Text
nativeHerSpecRowId _ = "HER/goal-reaching"
nativeHerSpecBits :: NativeHerReferenceSpec -> Int
nativeHerSpecBits (NativeHerReferenceSpec _ bits _ _ _) = bits
nativeHerSpecHorizon :: NativeHerReferenceSpec -> Int
nativeHerSpecHorizon = nativeHerSpecBits
nativeHerSpecEpisodeCount :: NativeHerReferenceSpec -> Int
nativeHerSpecEpisodeCount (NativeHerReferenceSpec _ _ count _ _) = count
nativeHerSpecBaseSeed :: NativeHerReferenceSpec -> Int
nativeHerSpecBaseSeed (NativeHerReferenceSpec _ _ _ base _) = base
nativeHerSpecEvaluationSeed :: NativeHerReferenceSpec -> Int
nativeHerSpecEvaluationSeed (NativeHerReferenceSpec _ _ _ _ seed) = seed
nativeHerSpecTrainingBudget :: NativeHerReferenceSpec -> TrainingBudget
nativeHerSpecTrainingBudget (NativeHerReferenceSpec row _ _ _ _) = Thresholds.hgmBudget row

nativeHerScheduleSpec :: NativeHerGoalSchedule -> NativeHerReferenceSpec
nativeHerScheduleSpec (NativeHerGoalSchedule spec _) = spec
nativeHerScheduleCases :: NativeHerGoalSchedule -> [RawNativeHerGoalCase]
nativeHerScheduleCases (NativeHerGoalSchedule _ cases) = cases

-- Only the goal sampler advances this generator. No policy, episode duration,
-- action draw, controller, case result, or training seed can influence it.
generateNativeHerGoalSchedule :: NativeHerReferenceSpec -> Either Text NativeHerGoalSchedule
generateNativeHerGoalSchedule spec = do
  validateCurrentSpec spec
  pure (NativeHerGoalSchedule spec (sampleGoalCases spec))

sampleGoalCases :: NativeHerReferenceSpec -> [RawNativeHerGoalCase]
sampleGoalCases spec = go 0 (Random.mkStdGen (nativeHerSpecEvaluationSeed spec))
 where
  go index generator
    | index >= nativeHerSpecEpisodeCount spec = []
    | otherwise =
        let (goal, nextGenerator) = Her.randomNonInitialGoal (nativeHerSpecBits spec) generator
         in RawNativeHerGoalCase index goal : go (index + 1) nextGenerator

refineNativeHerGoalSchedule
  :: NativeHerReferenceSpec -> [RawNativeHerGoalCase] -> Either Text NativeHerGoalSchedule
refineNativeHerGoalSchedule spec cases = do
  validateCurrentSpec spec
  require (length cases == nativeHerSpecEpisodeCount spec) "native HER goal case count differs"
  require
    (fmap rawNativeHerCaseId cases == [0 .. nativeHerSpecEpisodeCount spec - 1])
    "native HER goal case IDs or order differ"
  mapM_ (validateGoal (nativeHerSpecBits spec) . rawNativeHerGoal) cases
  let expected = sampleGoalCases spec
  require
    ( and
        ( zipWith
            (\actual wanted -> sameVector (rawNativeHerGoal actual) (rawNativeHerGoal wanted))
            cases
            expected
        )
    )
    "native HER goals differ from the sampler-only canonical schedule"
  pure (NativeHerGoalSchedule spec cases)

allNativeHerGoalBlindSequences :: NativeHerReferenceSpec -> [NativeHerGoalBlindSequence]
allNativeHerGoalBlindSequences spec =
  fmap
    NativeHerGoalBlindSequence
    (replicateM (nativeHerSpecHorizon spec) [0 .. nativeHerSpecBits spec - 1])

refineNativeHerGoalBlindSequence
  :: NativeHerReferenceSpec -> [Int] -> Either Text NativeHerGoalBlindSequence
refineNativeHerGoalBlindSequence spec actions = do
  validateCurrentSpec spec
  validateSequence (nativeHerSpecBits spec) actions
  pure (NativeHerGoalBlindSequence actions)

nativeHerSequenceActions :: NativeHerGoalBlindSequence -> [Int]
nativeHerSequenceActions (NativeHerGoalBlindSequence actions) = actions
nativeHerSequenceId :: NativeHerGoalBlindSequence -> Text
nativeHerSequenceId =
  ("goal-blind-sequence/" <>)
    . Text.intercalate ","
    . fmap (Text.pack . show)
    . nativeHerSequenceActions

evaluateNativeHerGoalBlindSequence
  :: NativeHerGoalSchedule -> NativeHerGoalBlindSequence -> Either Text NativeHerReferenceObservation
evaluateNativeHerGoalBlindSequence schedule goalBlindSequence = do
  let spec = nativeHerScheduleSpec schedule
      actions = nativeHerSequenceActions goalBlindSequence
  validateCurrentSpec spec
  validateSequence (nativeHerSpecBits spec) actions
  outcomes <- traverse (evaluateCase actions) (nativeHerScheduleCases schedule)
  let successes = length (filter nativeHerOutcomeSuccess outcomes)
      totalDistance = sum (fmap (toRational . nativeHerOutcomeNormalizedDistance) outcomes)
      meanDistance = totalDistance / fromIntegral (length outcomes)
      transitions = sum (fmap (toInteger . nativeHerOutcomeSteps) outcomes)
  pure (NativeHerReferenceObservation goalBlindSequence outcomes successes meanDistance transitions)
 where
  evaluateCase actions raw = do
    outcome <- evaluateHerSequenceFixture (rawNativeHerGoal raw) actions
    pure outcome {nativeHerOutcomeCaseId = rawNativeHerCaseId raw}

evaluateNativeHerReferenceFamily :: NativeHerGoalSchedule -> Either Text NativeHerReferenceFamily
evaluateNativeHerReferenceFamily schedule = do
  let spec = nativeHerScheduleSpec schedule
  validateCurrentSpec spec
  references <-
    traverse (evaluateNativeHerGoalBlindSequence schedule) (allNativeHerGoalBlindSequences spec)
  extrema <- referenceExtrema references
  pure
    ( NativeHerReferenceFamily
        schedule
        references
        extrema
        (sum (fmap nativeHerObservedEvaluationTransitions references))
    )

referenceExtrema :: [NativeHerReferenceObservation] -> Either Text NativeHerReferenceExtrema
referenceExtrema [] = Left "native HER reference family is empty"
referenceExtrema (first : rest) =
  let maximumSuccess = foldl' max (nativeHerObservedSuccessCount first) (fmap nativeHerObservedSuccessCount rest)
      minimumDistance =
        foldl' min (nativeHerObservedExactMeanDistance first) (fmap nativeHerObservedExactMeanDistance rest)
      allReferences = first : rest
   in Right
        ( NativeHerReferenceExtrema
            maximumSuccess
            [ nativeHerSequenceId (nativeHerObservedSequence ref)
            | ref <- allReferences
            , nativeHerObservedSuccessCount ref == maximumSuccess
            ]
            minimumDistance
            [ nativeHerSequenceId (nativeHerObservedSequence ref)
            | ref <- allReferences
            , nativeHerObservedExactMeanDistance ref == minimumDistance
            ]
        )

-- Explicitly noncanonical fixture seam; it returns raw observations only.
-- The canonical path supplies six-bit nonzero goals and complete six-actions.
-- Every action, including an unused suffix after early success, is validated.
evaluateHerSequenceFixture :: VU.Vector Double -> [Int] -> Either Text NativeHerReferenceOutcome
evaluateHerSequenceFixture goal actions = do
  let bits = VU.length goal
  require (bits > 0) "HER sequence fixture requires a positive bit dimension"
  validateGoal bits goal
  validateSequence bits actions
  loop bits (VU.replicate bits 0) 0 [] actions
 where
  loop bits !state !steps consumed remaining
    | steps >= bits || state == goal = do
        let distance = Her.bitDistance state goal
            normalized = distance / fromIntegral bits
            reached = state == goal
        require
          ( finite distance
              && finite normalized
              && distance >= 0
              && distance <= fromIntegral bits
              && distance == fromIntegral (round distance :: Int)
          )
          "HER reference distance is invalid"
        pure
          ( NativeHerReferenceOutcome
              0
              goal
              state
              reached
              normalized
              (round distance)
              steps
              reached
              (reverse consumed)
          )
    | otherwise = case remaining of
        [] -> Left "HER reference sequence ended before its validated horizon"
        action : rest ->
          let next = Her.flipBit action state
           in loop bits next (steps + 1) (action : consumed) rest

validateCurrentSpec :: NativeHerReferenceSpec -> Either Text ()
validateCurrentSpec spec = do
  expected <- canonicalNativeHerReferenceSpec
  require
    (spec == expected)
    "native HER reference specification differs from its canonical declaration"
validateGoal :: Int -> VU.Vector Double -> Either Text ()
validateGoal bits goal = do
  require
    (VU.length goal == bits && VU.all (\value -> finite value && (value == 0 || value == 1)) goal)
    "native HER goal has an invalid bit shape or nonbinary value"
  require (VU.any (== 1) goal) "native HER goal is the initial all-zero state"
validateSequence :: Int -> [Int] -> Either Text ()
validateSequence bits actions =
  require
    (length actions == bits && all (\action -> action >= 0 && action < bits) actions)
    "native HER sequence must contain the complete horizon of in-domain actions"
require :: Bool -> Text -> Either Text ()
require condition reason = unless condition (Left reason)
finite :: Double -> Bool
finite value = not (isNaN value || isInfinite value)
sameVector :: VU.Vector Double -> VU.Vector Double -> Bool
sameVector left right = fmap castDoubleToWord64 (VU.toList left) == fmap castDoubleToWord64 (VU.toList right)
