{-# LANGUAGE OverloadedStrings #-}

-- | Mathematical audits and comparisons of complete recorded HER DATA.
-- No result proves training, initial ownership, selected-device execution,
-- completed budgets, producer/parent origin, retention or serving eligibility.
module JitML.Product.NativeHerLearningPolicy
  ( NativeHerSeedObservation (..)
  , NativeHerLearningStatisticsData (..)
  , NativeHerLearningRelation
  , compareNativeHerLearningStatisticsData
  , nativeHerRelationInitialSuccessGain
  , nativeHerRelationInitialDistanceGain
  , nativeHerRelationSuccessReference
  , nativeHerRelationDistanceReference
  , nativeHerRelationJointLearning
  , NativeHerSeedComparison
  , NativeHerCohortComparison
  , nativeHerLearningPolicyContract
  , compareNativeHerCohort
  , nativeHerComparisonReferences
  , nativeHerComparisonObservations
  , nativeHerComparisonSeeds
  , nativeHerComparisonJointCount
  , nativeHerComparisonMedianSuccessQuality
  , nativeHerComparisonMedianDistanceQuality
  , nativeHerComparisonFailures
  , nativeHerSeedComparisonIndex
  , nativeHerSeedComparisonInitialSuccessCount
  , nativeHerSeedComparisonFinalSuccessCount
  , nativeHerSeedComparisonInitialExactMeanDistance
  , nativeHerSeedComparisonFinalExactMeanDistance
  , nativeHerSeedComparisonLegacySuccessQuality
  , nativeHerSeedComparisonLegacyDistanceQuality
  , nativeHerSeedComparisonJointLearning
  , nativeHerSeedComparisonFindings
  ) where

import Control.Monad (foldM, unless)
import Data.List (sort)
import Data.Text (Text)
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word64)
import GHC.Float (castDoubleToWord64)

import JitML.Numerics.Mlp qualified as Mlp
import JitML.RL.Algorithms.HerTrainer qualified as Her
import JitML.RL.ConvergenceThresholds qualified as Thresholds
import JitML.RL.Framework qualified as Framework
import JitML.RL.NativeHerEvaluation qualified as Evaluation
import JitML.RL.NativeHerReferences qualified as References
import JitML.Training.Budget qualified as Budget

nativeHerLearningPolicyContract :: Text
nativeHerLearningPolicyContract =
  "native-her-learning-v1:canonical-base42-plus-0..4;served-index0;sampler-only-base42-plus104729-fixed20;complete6^6-reference-replay;recorded-forward-action-rule-audit;strict-initial-success-and-exact-binary64-distance-gains;both-reference-extrema-strict-except-global20success-or-zero-distance-equality;joint-at-least3of5;whole-five-legacy-quality-medians;served0-own-joint-and-both-unchanged-bars;finite-failures-retained;no-population-or-producer-claim"

-- Raw records may be supplied or decoded by anybody. Their booleans, summaries
-- and transcripts are checked below; none is assumed to prove actual origin.
data NativeHerSeedObservation = NativeHerSeedObservation
  { nativeHerObservedSeedIndex :: !Int
  , nativeHerObservedSeed :: !Word64
  , nativeHerObservedInitial :: !Evaluation.RawNativeHerEvaluation
  , nativeHerObservedFinal :: !Evaluation.RawNativeHerEvaluation
  }
  deriving stock (Eq, Show)

-- Range-checked mathematical summaries only. These public scalar claims do
-- not establish complete cases, calibrated references or actual trained models.
data NativeHerLearningStatisticsData = NativeHerLearningStatisticsData
  { nativeHerStatisticsSuccessCount :: !Int
  , nativeHerStatisticsExactMeanDistance :: !Rational
  }
  deriving stock (Eq, Show)

data NativeHerLearningRelation = NativeHerLearningRelation
  { internalHerInitialSuccessGain :: !Bool
  , internalHerInitialDistanceGain :: !Bool
  , internalHerSuccessReference :: !Bool
  , internalHerDistanceReference :: !Bool
  }
  deriving stock (Eq, Show)

nativeHerRelationInitialSuccessGain :: NativeHerLearningRelation -> Bool
nativeHerRelationInitialSuccessGain = internalHerInitialSuccessGain
nativeHerRelationInitialDistanceGain :: NativeHerLearningRelation -> Bool
nativeHerRelationInitialDistanceGain = internalHerInitialDistanceGain
nativeHerRelationSuccessReference :: NativeHerLearningRelation -> Bool
nativeHerRelationSuccessReference = internalHerSuccessReference
nativeHerRelationDistanceReference :: NativeHerLearningRelation -> Bool
nativeHerRelationDistanceReference = internalHerDistanceReference
nativeHerRelationJointLearning :: NativeHerLearningRelation -> Bool
nativeHerRelationJointLearning relation =
  nativeHerRelationInitialSuccessGain relation
    && nativeHerRelationInitialDistanceGain relation
    && nativeHerRelationSuccessReference relation
    && nativeHerRelationDistanceReference relation

-- | Shared arithmetic only. Full cohort comparison constructs these summaries
-- internally AFTER complete reference replay and learned-transcript audits.
-- An arbitrary supplied summary cannot construct a cohort comparison.
compareNativeHerLearningStatisticsData
  :: NativeHerLearningStatisticsData
  -> NativeHerLearningStatisticsData
  -> NativeHerLearningStatisticsData
  -> Either Text NativeHerLearningRelation
compareNativeHerLearningStatisticsData initial final reference = do
  mapM_ validateStatistics [initial, final, reference]
  let initialSuccess = nativeHerStatisticsSuccessCount initial
      finalSuccess = nativeHerStatisticsSuccessCount final
      referenceSuccess = nativeHerStatisticsSuccessCount reference
      initialDistance = nativeHerStatisticsExactMeanDistance initial
      finalDistance = nativeHerStatisticsExactMeanDistance final
      referenceDistance = nativeHerStatisticsExactMeanDistance reference
  pure
    ( NativeHerLearningRelation
        (finalSuccess > initialSuccess)
        (finalDistance < initialDistance)
        (finalSuccess > referenceSuccess || (finalSuccess == referenceSuccess && referenceSuccess == 20))
        (finalDistance < referenceDistance || (finalDistance == referenceDistance && referenceDistance == 0))
    )
 where
  validateStatistics value = do
    let successes = nativeHerStatisticsSuccessCount value
        distance = nativeHerStatisticsExactMeanDistance value
    require
      (successes >= 0 && successes <= 20)
      "native HER statistics success count is outside0..20"
    require
      (distance >= 0 && distance <= 1)
      "native HER statistics exact mean distance is outside0..1"
    require
      ((successes == 20) == (distance == 0))
      "native HER statistics endpoint pair is inconsistent"

data NativeHerSeedComparison = NativeHerSeedComparison
  { internalHerSeedIndex :: !Int
  , internalHerInitialSuccess :: !Int
  , internalHerFinalSuccess :: !Int
  , internalHerInitialDistance :: !Rational
  , internalHerFinalDistance :: !Rational
  , internalHerSuccessQuality :: !Double
  , internalHerDistanceQuality :: !Double
  , internalHerJoint :: !Bool
  , internalHerFindings :: ![Text]
  }
  deriving stock (Eq, Show)

data NativeHerCohortComparison = NativeHerCohortComparison
  { internalHerReferences :: !References.NativeHerReferenceFamily
  , internalHerObservations :: ![NativeHerSeedObservation]
  , internalHerComparisons :: ![NativeHerSeedComparison]
  , internalHerJointCount :: !Int
  , internalHerMedianSuccess :: !Double
  , internalHerMedianDistance :: !Double
  , internalHerCohortFindings :: ![Text]
  }
  deriving stock (Eq, Show)

nativeHerComparisonReferences :: NativeHerCohortComparison -> References.NativeHerReferenceFamily
nativeHerComparisonReferences = internalHerReferences
nativeHerComparisonObservations :: NativeHerCohortComparison -> [NativeHerSeedObservation]
nativeHerComparisonObservations = internalHerObservations
nativeHerComparisonSeeds :: NativeHerCohortComparison -> [NativeHerSeedComparison]
nativeHerComparisonSeeds = internalHerComparisons
nativeHerComparisonJointCount :: NativeHerCohortComparison -> Int
nativeHerComparisonJointCount = internalHerJointCount
nativeHerComparisonMedianSuccessQuality :: NativeHerCohortComparison -> Double
nativeHerComparisonMedianSuccessQuality = internalHerMedianSuccess
nativeHerComparisonMedianDistanceQuality :: NativeHerCohortComparison -> Double
nativeHerComparisonMedianDistanceQuality = internalHerMedianDistance
nativeHerComparisonFailures :: NativeHerCohortComparison -> [Text]
nativeHerComparisonFailures = internalHerCohortFindings
nativeHerSeedComparisonIndex :: NativeHerSeedComparison -> Int
nativeHerSeedComparisonIndex = internalHerSeedIndex
nativeHerSeedComparisonInitialSuccessCount :: NativeHerSeedComparison -> Int
nativeHerSeedComparisonInitialSuccessCount = internalHerInitialSuccess
nativeHerSeedComparisonFinalSuccessCount :: NativeHerSeedComparison -> Int
nativeHerSeedComparisonFinalSuccessCount = internalHerFinalSuccess
nativeHerSeedComparisonInitialExactMeanDistance :: NativeHerSeedComparison -> Rational
nativeHerSeedComparisonInitialExactMeanDistance = internalHerInitialDistance
nativeHerSeedComparisonFinalExactMeanDistance :: NativeHerSeedComparison -> Rational
nativeHerSeedComparisonFinalExactMeanDistance = internalHerFinalDistance
nativeHerSeedComparisonLegacySuccessQuality :: NativeHerSeedComparison -> Double
nativeHerSeedComparisonLegacySuccessQuality = internalHerSuccessQuality
nativeHerSeedComparisonLegacyDistanceQuality :: NativeHerSeedComparison -> Double
nativeHerSeedComparisonLegacyDistanceQuality = internalHerDistanceQuality
nativeHerSeedComparisonJointLearning :: NativeHerSeedComparison -> Bool
nativeHerSeedComparisonJointLearning = internalHerJoint
nativeHerSeedComparisonFindings :: NativeHerSeedComparison -> [Text]
nativeHerSeedComparisonFindings = internalHerFindings

data ReferenceSummary = ReferenceSummary !Int ![Text] !Rational ![Text] !Integer
data EvaluationSummary = EvaluationSummary !Int !Rational !Double !Double

-- | Invalid/incomplete data is Left. A mathematically failing but complete
-- finite five-member cohort is Right with every original observation retained.
compareNativeHerCohort
  :: References.NativeHerReferenceFamily
  -> [NativeHerSeedObservation]
  -> Either Text NativeHerCohortComparison
compareNativeHerCohort references observations = do
  canonical <- References.canonicalNativeHerReferenceSpec
  let schedule = References.nativeHerObservedSchedule references
      spec = References.nativeHerScheduleSpec schedule
  require
    ( spec == canonical
        && References.nativeHerSpecBits spec == 6
        && References.nativeHerSpecHorizon spec == 6
        && References.nativeHerSpecEpisodeCount spec == 20
        && References.nativeHerSpecBaseSeed spec == 42
        && References.nativeHerSpecEvaluationSeed spec == 42 + 104729
    )
    "native HER comparison requires the complete current canonical fixed-goal specification"
  -- Re-refinement checks the existing sampler, IDs and every goal bit; it never
  -- replaces supplied cases with a seed selected from learner observations.
  checkedSchedule <-
    References.refineNativeHerGoalSchedule spec (References.nativeHerScheduleCases schedule)
  require
    (sameSchedule schedule checkedSchedule)
    "native HER comparison schedule changed during refinement"
  ReferenceSummary maximumSuccess _ minimumDistance _ _ <- validateReferences schedule references
  require
    (map nativeHerObservedSeedIndex observations == [0 .. 4])
    "native HER comparison requires exactly five ordered indices0..4"
  comparisons <- traverse (compareSeed schedule maximumSuccess minimumDistance) observations
  successMedian <- middleOfFive (sort (map nativeHerSeedComparisonLegacySuccessQuality comparisons))
  distanceMedian <- middleOfFive (sort (map nativeHerSeedComparisonLegacyDistanceQuality comparisons))
  (successPass, distancePass) <- qualityPasses successMedian distanceMedian
  case comparisons of
    served : _ -> do
      let jointCount = length (filter nativeHerSeedComparisonJointLearning comparisons)
          findings =
            ["native HER cohort has fewer than three same-seed joint learning successes" | jointCount < 3]
              <> ["native HER whole-five success-quality median fails the unchanged bar" | not successPass]
              <> ["native HER whole-five distance-quality median fails the unchanged bar" | not distancePass]
              <> map ("native HER served index0 fails: " <>) (nativeHerSeedComparisonFindings served)
      pure
        ( NativeHerCohortComparison
            references
            observations
            comparisons
            jointCount
            successMedian
            distanceMedian
            findings
        )
    [] -> Left "native HER comparison has no predetermined serving member"

compareSeed
  :: References.NativeHerGoalSchedule
  -> Int
  -> Rational
  -> NativeHerSeedObservation
  -> Either Text NativeHerSeedComparison
compareSeed schedule referenceSuccess referenceDistance observed = do
  let index = nativeHerObservedSeedIndex observed
      seed = nativeHerObservedSeed observed
      initial = nativeHerObservedInitial observed
      final = nativeHerObservedFinal observed
  require
    (seed == 42 + fromIntegral index)
    "native HER comparison seed differs from prescribed42+index"
  require
    ( sameConfig
        (Evaluation.nativeHerEvaluationConfig initial)
        (Evaluation.nativeHerEvaluationConfig final)
    )
    "native HER paired evaluation configuration fields differ"
  EvaluationSummary initialSuccess initialDistance _ _ <- validateEvaluation schedule seed initial
  EvaluationSummary finalSuccess finalDistance successQuality distanceQuality <-
    validateEvaluation schedule seed final
  (successPass, distancePass) <- qualityPasses successQuality distanceQuality
  relation <-
    compareNativeHerLearningStatisticsData
      (NativeHerLearningStatisticsData initialSuccess initialDistance)
      (NativeHerLearningStatisticsData finalSuccess finalDistance)
      (NativeHerLearningStatisticsData referenceSuccess referenceDistance)
  let initialSuccessGain = nativeHerRelationInitialSuccessGain relation
      initialDistanceGain = nativeHerRelationInitialDistanceGain relation
      successReference = nativeHerRelationSuccessReference relation
      distanceReference = nativeHerRelationDistanceReference relation
      joint = nativeHerRelationJointLearning relation
      findings =
        ["final success count does not strictly exceed its paired initial count" | not initialSuccessGain]
          <> [ "final exact mean distance does not strictly improve its paired initial distance"
             | not initialDistanceGain
             ]
          <> [ "final success count does not beat the exhaustive reference maximum or equal the proved global20-success optimum"
             | not successReference
             ]
          <> [ "final exact mean distance does not beat the exhaustive reference minimum or equal the proved global-zero-distance optimum"
             | not distanceReference
             ]
          <> ["final legacy success-quality metric fails the unchanged bar" | not successPass]
          <> ["final legacy distance-quality metric fails the unchanged bar" | not distancePass]
  pure
    ( NativeHerSeedComparison
        index
        initialSuccess
        finalSuccess
        initialDistance
        finalDistance
        successQuality
        distanceQuality
        joint
        findings
    )

-- Replay each twenty-case public reference separately. No second complete
-- 46,656-reference family is constructed, and raw summary/extrema fields are
-- never accepted as authority for their own values.
validateReferences
  :: References.NativeHerGoalSchedule
  -> References.NativeHerReferenceFamily
  -> Either Text ReferenceSummary
validateReferences schedule family = do
  let spec = References.nativeHerScheduleSpec schedule
      expected = References.allNativeHerGoalBlindSequences spec
      actual = References.nativeHerObservedReferences family
  require
    (length expected == 46656 && length actual == length expected)
    "native HER references require all46656 complete goal-blind sequences"
  accumulated <- foldM inspect Nothing (zip expected actual)
  case accumulated of
    Nothing -> Left "native HER complete reference family is empty"
    Just summary@(ReferenceSummary successes successIdsRev distance distanceIdsRev work) -> do
      let extrema = References.nativeHerObservedExtrema family
      require
        ( References.nativeHerMaximumSuccessCount extrema == successes
            && References.nativeHerMaximumSuccessSequenceIds extrema == reverse successIdsRev
            && References.nativeHerMinimumExactMeanDistance extrema == distance
            && References.nativeHerMinimumDistanceSequenceIds extrema == reverse distanceIdsRev
        )
        "native HER exhaustive reference extrema or all attaining sequence IDs differ"
      require
        (References.nativeHerTotalEvaluationTransitions family == work)
        "native HER whole reference transition count differs"
      pure summary
 where
  inspect accumulated (expectedSequence, observed) = do
    require
      ( References.nativeHerSequenceActions (References.nativeHerObservedSequence observed)
          == References.nativeHerSequenceActions expectedSequence
      )
      "native HER reference sequence inventory is missing duplicated foreign or reordered"
    replayed <- References.evaluateNativeHerGoalBlindSequence schedule expectedSequence
    require
      (sameReference observed replayed)
      "native HER reference outcome summary or transition work differs from actual public-rule replay"
    let successes = References.nativeHerObservedSuccessCount replayed
        distance = References.nativeHerObservedExactMeanDistance replayed
        work = References.nativeHerObservedEvaluationTransitions replayed
        identity = References.nativeHerSequenceId expectedSequence
    pure . Just $ case accumulated of
      Nothing -> ReferenceSummary successes [identity] distance [identity] work
      Just (ReferenceSummary oldSuccess successIds oldDistance distanceIds oldWork) ->
        let (newSuccess, newSuccessIds)
              | successes > oldSuccess = (successes, [identity])
              | successes == oldSuccess = (oldSuccess, identity : successIds)
              | otherwise = (oldSuccess, successIds)
            (newDistance, newDistanceIds)
              | distance < oldDistance = (distance, [identity])
              | distance == oldDistance = (oldDistance, identity : distanceIds)
              | otherwise = (oldDistance, distanceIds)
         in ReferenceSummary newSuccess newSuccessIds newDistance newDistanceIds (oldWork + work)

validateEvaluation
  :: References.NativeHerGoalSchedule
  -> Word64
  -> Evaluation.RawNativeHerEvaluation
  -> Either Text EvaluationSummary
validateEvaluation schedule seed raw = do
  let config = Evaluation.nativeHerEvaluationConfig raw
      params = Evaluation.nativeHerEvaluationParameters raw
      cases = References.nativeHerScheduleCases schedule
      outcomes = Evaluation.nativeHerEvaluationOutcomes raw
      forwards = Evaluation.nativeHerEvaluationForwards raw
  require
    (sameSchedule schedule (Evaluation.nativeHerEvaluationSchedule raw))
    "native HER learned evaluation names different fixed goals or case order"
  require
    (toInteger (Her.herSeed config) == toInteger seed)
    "native HER learned evaluation configuration seed differs from its prescribed member"
  require
    (all finite [Her.herLearningRate config, Her.herGamma config, Her.herEpsilon config])
    "native HER learned evaluation configuration is nonfinite"
  Evaluation.validateNativeHerEvaluationContext schedule config params
  case Evaluation.nativeHerEvaluationStatus raw of
    Evaluation.NativeHerEvaluationComplete -> pure ()
    _ -> Left "native HER learned evaluation is incomplete or failed"
  case Evaluation.nativeHerEvaluationFailedProgress raw of
    Nothing -> pure ()
    Just _ -> Left "native HER complete learned evaluation retains failed progress"
  require
    ( length outcomes == length cases
        && map References.nativeHerOutcomeCaseId outcomes == map References.rawNativeHerCaseId cases
    )
    "native HER learned evaluation has missing duplicated foreign or reordered cases"
  remaining <- foldM (auditCase params) forwards (zip cases outcomes)
  require
    (null remaining)
    "native HER learned evaluation contains extra or foreign forward observations"
  let work = sum (map (toInteger . References.nativeHerOutcomeSteps) outcomes)
  require
    (Evaluation.nativeHerEvaluationWork raw == Evaluation.NativeHerCompleteWork work)
    "native HER learned evaluation complete transition work differs"
  let successes = length (filter References.nativeHerOutcomeSuccess outcomes)
      exactDistance =
        sum (map (toRational . References.nativeHerOutcomeNormalizedDistance) outcomes)
          / fromIntegral (length outcomes)
  -- Same operation order as TrainerExecution.herEvaluationEpisodes followed by
  -- Completion.rlCompletionMetrics. No fake positive trainer counters are made.
  evaluation <-
    Framework.mkEvaluationSet
      (fromIntegral (length cases))
      [ ( fromIntegral (References.nativeHerOutcomeCaseId outcome)
        , 1.0 - References.nativeHerOutcomeNormalizedDistance outcome
        , References.nativeHerOutcomeSteps outcome
        , References.nativeHerOutcomeTerminated outcome
        )
      | outcome <- outcomes
      ]
  let successQuality = clamp01 (fromIntegral successes / fromIntegral (length outcomes))
      distanceQuality = clamp01 (1.0 - Framework.evaluationSetMeanReward evaluation)
  require
    (finite successQuality && finite distanceQuality)
    "native HER legacy quality summary is nonfinite"
  pure (EvaluationSummary successes exactDistance successQuality distanceQuality)
 where
  bits = References.nativeHerSpecBits (References.nativeHerScheduleSpec schedule)
  horizon = References.nativeHerSpecHorizon (References.nativeHerScheduleSpec schedule)
  auditCase params forwards (planned, outcome) = do
    let goal = References.rawNativeHerGoal planned
        actions = References.nativeHerOutcomeConsumedActions outcome
        steps = References.nativeHerOutcomeSteps outcome
    require
      (sameVector goal (References.nativeHerOutcomeGoal outcome))
      "native HER learned outcome goal differs from its exact planned case"
    require
      (steps > 0 && steps <= horizon && length actions == steps)
      "native HER learned outcome steps or consumed action prefix is incomplete"
    (finalState, remaining) <-
      foldM
        (auditAction params goal (References.rawNativeHerCaseId planned))
        (VU.replicate bits 0, forwards)
        (zip [0 :: Int ..] actions)
    require
      (sameVector finalState (References.nativeHerOutcomeFinalState outcome))
      "native HER learned final state differs from actual bit-flip action replay"
    let distance = Her.bitDistance finalState goal
        normalized = distance / fromIntegral bits
        reached = finalState == goal
    require
      ( finite distance
          && distance >= 0
          && distance <= fromIntegral bits
          && distance == fromIntegral (round distance :: Int)
      )
      "native HER public-rule Hamming distance is invalid"
    require
      ( finite (References.nativeHerOutcomeNormalizedDistance outcome)
          && sameDouble normalized (References.nativeHerOutcomeNormalizedDistance outcome)
          && References.nativeHerOutcomeHammingDistance outcome == round distance
      )
      "native HER learned normalized or Hamming distance differs from actual rule replay"
    require
      ( References.nativeHerOutcomeSuccess outcome == reached
          && References.nativeHerOutcomeTerminated outcome == reached
          && (reached || steps == horizon)
      )
      "native HER learned success termination or horizon differs from actual rule replay"
    pure remaining
  auditAction params goal caseId (state, forwards) (ordinal, action) = do
    require (state /= goal) "native HER learned action follows an already reached goal"
    require (action >= 0 && action < bits) "native HER learned action is outside the actual domain"
    case forwards of
      [] -> Left "native HER learned transition has no recorded forward"
      forwarded : rest -> do
        require
          ( Evaluation.nativeHerForwardCaseId forwarded == caseId
              && Evaluation.nativeHerForwardCallIndex forwarded == ordinal
          )
          "native HER learned forward case or within-case ordinal differs"
        require
          (sameParams params (Evaluation.nativeHerForwardParameters forwarded))
          "native HER learned forward parameters differ from the evaluated policy bytes"
        require
          (sameVector (state VU.++ goal) (Evaluation.nativeHerForwardInput forwarded))
          "native HER learned forward input differs from the actual current state and goal"
        output <- case Evaluation.nativeHerForwardOutcome forwarded of
          Evaluation.NativeHerForwardReturned (Right values) -> Right values
          _ -> Left "native HER complete learned trace contains a rejected or throwing forward"
        require
          (VU.length output == bits && VU.all float32Finite output)
          "native HER complete learned forward output is malformed or nonfinite Float32"
        require
          (leftmostMaximum action output)
          "native HER learned consumed action differs from the recorded output's leftmost maximum"
        let next = Her.flipBit action state
        require
          (VU.length next == bits && VU.all (\value -> finite value && (value == 0 || value == 1)) next)
          "native HER actual bit-flip successor is malformed"
        pure (next, rest)

-- A predicate over a retained chosen action, not a second evaluator/argmax.
-- Both the action domain and output width are checked before this call.
leftmostMaximum :: Int -> VU.Vector Double -> Bool
leftmostMaximum action values = case drop action (VU.toList values) of
  [] -> False
  chosen : _ ->
    and
      [ if index < action then value < chosen else value <= chosen
      | (index, value) <- zip [0 :: Int ..] (VU.toList values)
      ]

qualityPasses :: Double -> Double -> Either Text (Bool, Bool)
qualityPasses success distance = do
  successObservation <-
    Budget.remeasureCriterion success (Thresholds.hgmSuccessRate Thresholds.herGoalMetric)
  distanceObservation <-
    Budget.remeasureCriterion distance (Thresholds.hgmAchievedGoalDistance Thresholds.herGoalMetric)
  pure (Budget.convergencePassed successObservation, Budget.convergencePassed distanceObservation)

middleOfFive :: [Double] -> Either Text Double
middleOfFive [_, _, middle, _, _] = Right middle
middleOfFive _ = Left "native HER quality median requires all five final metrics"

sameSchedule :: References.NativeHerGoalSchedule -> References.NativeHerGoalSchedule -> Bool
sameSchedule left right =
  References.nativeHerScheduleSpec left == References.nativeHerScheduleSpec right
    && let actual = References.nativeHerScheduleCases left
           expected = References.nativeHerScheduleCases right
        in length actual == length expected
             && and
               [ References.rawNativeHerCaseId first == References.rawNativeHerCaseId second
                   && sameVector (References.rawNativeHerGoal first) (References.rawNativeHerGoal second)
               | (first, second) <- zip actual expected
               ]

sameReference
  :: References.NativeHerReferenceObservation -> References.NativeHerReferenceObservation -> Bool
sameReference left right =
  References.nativeHerSequenceActions (References.nativeHerObservedSequence left)
    == References.nativeHerSequenceActions (References.nativeHerObservedSequence right)
    && length actual == length expected
    && and (zipWith sameOutcome actual expected)
    && References.nativeHerObservedSuccessCount left == References.nativeHerObservedSuccessCount right
    && References.nativeHerObservedExactMeanDistance left
      == References.nativeHerObservedExactMeanDistance right
    && References.nativeHerObservedEvaluationTransitions left
      == References.nativeHerObservedEvaluationTransitions right
 where
  actual = References.nativeHerObservedOutcomes left
  expected = References.nativeHerObservedOutcomes right

sameOutcome :: References.NativeHerReferenceOutcome -> References.NativeHerReferenceOutcome -> Bool
sameOutcome left right =
  References.nativeHerOutcomeCaseId left == References.nativeHerOutcomeCaseId right
    && sameVector (References.nativeHerOutcomeGoal left) (References.nativeHerOutcomeGoal right)
    && sameVector
      (References.nativeHerOutcomeFinalState left)
      (References.nativeHerOutcomeFinalState right)
    && References.nativeHerOutcomeSuccess left == References.nativeHerOutcomeSuccess right
    && sameDouble
      (References.nativeHerOutcomeNormalizedDistance left)
      (References.nativeHerOutcomeNormalizedDistance right)
    && References.nativeHerOutcomeHammingDistance left == References.nativeHerOutcomeHammingDistance right
    && References.nativeHerOutcomeSteps left == References.nativeHerOutcomeSteps right
    && References.nativeHerOutcomeTerminated left == References.nativeHerOutcomeTerminated right
    && References.nativeHerOutcomeConsumedActions left == References.nativeHerOutcomeConsumedActions right

-- Exhaustive positional patterns make a newly added config field a compiler
-- error instead of silently ignoring it. Double fields compare exact bits.
sameConfig :: Her.HerTrainConfig -> Her.HerTrainConfig -> Bool
sameConfig
  ( Her.HerTrainConfig
      seed
      bits
      hidden
      episodes
      capacity
      batch
      rate
      gamma
      target
      epsilon
      hindsight
      strategy
      interval
      updates
    )
  ( Her.HerTrainConfig
      seed'
      bits'
      hidden'
      episodes'
      capacity'
      batch'
      rate'
      gamma'
      target'
      epsilon'
      hindsight'
      strategy'
      interval'
      updates'
    ) =
    (seed, bits, hidden, episodes, capacity, batch, target, hindsight, strategy, interval, updates)
      == ( seed'
         , bits'
         , hidden'
         , episodes'
         , capacity'
         , batch'
         , target'
         , hindsight'
         , strategy'
         , interval'
         , updates'
         )
      && and (zipWith sameDouble [rate, gamma, epsilon] [rate', gamma', epsilon'])

sameParams :: Mlp.MlpParams -> Mlp.MlpParams -> Bool
sameParams left right =
  Mlp.paramShape left == Mlp.paramShape right
    && and
      ( zipWith
          sameVector
          [Mlp.paramW1 left, Mlp.paramB1 left, Mlp.paramW2 left, Mlp.paramB2 left]
          [Mlp.paramW1 right, Mlp.paramB1 right, Mlp.paramW2 right, Mlp.paramB2 right]
      )

sameVector :: VU.Vector Double -> VU.Vector Double -> Bool
sameVector left right = VU.length left == VU.length right && VU.and (VU.zipWith sameDouble left right)
sameDouble :: Double -> Double -> Bool
sameDouble left right = castDoubleToWord64 left == castDoubleToWord64 right
float32Finite :: Double -> Bool
float32Finite value =
  finite value && let encoded = realToFrac value :: Float in not (isNaN encoded || isInfinite encoded)
finite :: Double -> Bool
finite value = not (isNaN value || isInfinite value)
clamp01 :: Double -> Double
clamp01 value = max 0.0 (min 1.0 value)
require :: Bool -> Text -> Either Text ()
require condition reason = unless condition (Left reason)
