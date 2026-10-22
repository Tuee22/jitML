{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}

-- | Bound numerical assessment of the same actual produced/replayed cohort and
-- its producer-owned pretraining references. Empty learning findings are not
-- CompletedTraining, parent authentication, physical Store or eligibility.
module JitML.Product.NativeRlAssessment
  ( NativeCohortAssessment
  , NativeAssessmentFailure (..)
  , NativeLearningComparisonData (..)
  , NativeObservedWorkData (..)
  , assessNativeReplayedCohort
  , nativeAssessmentReplay
  , nativeAssessmentReferences
  , nativeAssessmentReferenceObject
  , nativeAssessmentComparison
  , nativeAssessmentObservedWork
  , nativeAssessmentLearningFindings
  ) where

import Control.Exception (evaluate)
import Control.Exception.Safe (tryAny)
import Control.Monad (unless, zipWithM_)
import Data.Either.Combinators (mapLeft)
import Data.Ratio (denominator, numerator)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)
import GHC.Float (castDoubleToWord64)

import JitML.Checkpoint.NativePhase.Failure qualified as Failure
import JitML.Checkpoint.NativePhase.Types (hashBytes)
import JitML.Checkpoint.NativeRetention qualified as Retain
import JitML.Plan.NativeSingletonPlan qualified as Singleton
import JitML.Product.NativeArenaLearningPolicy qualified as ArenaPolicy
import JitML.Product.NativeHerLearningPolicy qualified as HerPolicy
import JitML.Product.NativePreparedAlphaZeroAttempt qualified as Arena
import JitML.Product.NativePreparedArsAttempt qualified as Ars
import JitML.Product.NativePreparedNeuralAttempt qualified as Neural
import JitML.Product.NativeReferenceCalibration qualified as Reference
import JitML.Product.NativeReturnLearningPolicy qualified as ReturnPolicy
import JitML.Product.NativeRlCohortPlan qualified as Cohort
import JitML.Product.NativeRlEvaluationReplay qualified as Replay
import JitML.Product.NativeRlProducer qualified as Producer
import JitML.RL.Algorithms.Common qualified as Common
import JitML.RL.Algorithms.ContinuousTrainer qualified as Continuous
import JitML.RL.AlphaZero.PreparedTrainer qualified as ArenaRaw
import JitML.RL.NativeReturnEvaluation qualified as Return
import JitML.RL.NativeReturnReferences qualified as ReturnReference
import JitML.RL.PreparedNeuralAttempt qualified as Low
import JitML.RL.TrainerObservation qualified as Observation
import JitML.Training.Budget qualified as Budget

data NativeAssessmentFailure
  = NativeAssessmentBindingRejected !Text
  | NativeAssessmentMathematicsRejected !Text
  | NativeAssessmentSynchronousFailure !Failure.NativeDiagnosticData
  deriving stock (Eq, Show)

-- Ordinary mathematical DATA. A comparison can be constructed separately but
-- cannot be supplied to this module to mint an assessment or replay capsule.
data NativeLearningComparisonData
  = NativeReturnLearningComparison !ReturnPolicy.NativeReturnCohortComparison
  | NativeHerLearningComparison !HerPolicy.NativeHerCohortComparison
  | NativeArenaLearningComparison !ArenaPolicy.NativeArenaCohortComparison
  deriving stock (Eq, Show)

-- Actual observations alongside declared budgets. They do not refine old
-- completion/curve/evidence requirements. SAC warm applications stay separate
-- from the unchanged scheduled transition/update counters.
data NativeObservedWorkData
  = NativeReturnObservedWork !Int !Word64 !Budget.TrainingBudget !Word64 !Word64 !(Maybe Int)
  | NativeArenaObservedWork !Int !Word64 !Budget.TrainingBudget !Int !Int !Integer !Integer
  deriving stock (Eq, Show)

-- No constructor, labels, Read/Generic, restore or arbitrary result factory.
data NativeCohortAssessment
  = NativeCohortAssessment
      !Replay.NativeEvaluationReplayedCohort
      !Reference.CapturedNativeReferences
      !Retain.NativeRetainedObjectData
      !NativeLearningComparisonData
      ![NativeObservedWorkData]

nativeAssessmentReplay :: NativeCohortAssessment -> Replay.NativeEvaluationReplayedCohort
nativeAssessmentReplay (NativeCohortAssessment actual _ _ _ _) = actual
nativeAssessmentReferences :: NativeCohortAssessment -> Reference.CapturedNativeReferences
nativeAssessmentReferences (NativeCohortAssessment _ actual _ _ _) = actual
nativeAssessmentReferenceObject :: NativeCohortAssessment -> Retain.NativeRetainedObjectData
nativeAssessmentReferenceObject (NativeCohortAssessment _ _ actual _ _) = actual
nativeAssessmentComparison :: NativeCohortAssessment -> NativeLearningComparisonData
nativeAssessmentComparison (NativeCohortAssessment _ _ _ actual _) = actual
nativeAssessmentObservedWork :: NativeCohortAssessment -> [NativeObservedWorkData]
nativeAssessmentObservedWork (NativeCohortAssessment _ _ _ _ actual) = actual
nativeAssessmentLearningFindings :: NativeCohortAssessment -> [Text]
nativeAssessmentLearningFindings = comparisonFindings . nativeAssessmentComparison

-- No calibration argument to re-pair with a different actual cohort; no
-- callback, device, model, evaluator or decoded-data input is accepted.
assessNativeReplayedCohort
  :: Replay.NativeEvaluationReplayedCohort
  -> IO (Either NativeAssessmentFailure NativeCohortAssessment)
assessNativeReplayedCohort replayed = do
  attempted <- tryAny $ do
    result <- evaluate (bindAssessment replayed)
    case result of
      Left failure -> evaluate (forceFailure failure) >> pure (Left failure)
      Right assessment -> evaluate (forceAssessment assessment) >> pure (Right assessment)
  case attempted of
    Right result -> pure result
    Left exception -> do
      diagnostic <- Failure.captureNativeExceptionDiagnostic exception
      pure (Left (NativeAssessmentSynchronousFailure diagnostic))

bindAssessment
  :: Replay.NativeEvaluationReplayedCohort
  -> Either NativeAssessmentFailure NativeCohortAssessment
bindAssessment replayed = do
  let produced = Replay.nativeEvaluationReplayedProducer replayed
      references = Producer.nativeProducedReferences produced
      referenceObject = Producer.nativeProducedReferenceObject produced
      cohort = Reference.nativeCapturedReferenceCohort references
      children = Producer.nativeProducedChildren produced
      actualModels = map Producer.nativeProducedModelData children
      expected = Cohort.nativeRlCohortPlanChildren cohort
      indices =
        map
          (Cohort.nativeSeedIndexValue . Producer.nativeChildIndex . Producer.nativeProducedChildData)
          children
      seedPlans = map modelSeedPlan actualModels
      seeds = map Cohort.nativeRlSeedPlanSeed seedPlans
      inventory = Producer.nativeProducedInventory produced
  require
    (indices == [0 .. 4] && length expected == 5)
    "native assessment requires all five original produced indices0..4"
  require (seeds == [42 .. 46]) "native assessment actual model seeds differ from42..46"
  require
    (Producer.nativeInventoryRow inventory == rowId actualModels)
    "native assessment retained inventory row differs from its actual models"
  require
    (referenceObject `elem` Producer.nativeInventoryPreludeObjects inventory)
    "native assessment calibration ACK is not in this exact inventory's retained prelude"
  -- The ACK SHA identifies NativeRetention's outer phase envelope, not these
  -- raw payload bytes. The producer's private pair retains both identities.
  require
    ( Producer.nativeProducedReferencePayloadDigest produced
        == hashBytes (Reference.nativeCapturedReferenceBytes references)
    )
    "native assessment captured reference payload differs from its producer-owned payload digest"
  zipWithM_ (bindChild cohort) expected (zip children actualModels)
  comparison <- case Reference.nativeCapturedReferenceObservations references of
    Reference.NativeReferenceReturnObservations actualReferences -> do
      observations <-
        traverse
          (returnObservation (ReturnReference.nativeReturnObservedSpec actualReferences))
          (zip indices actualModels)
      NativeReturnLearningComparison
        <$> mathematical (ReturnPolicy.compareNativeReturnCohort actualReferences observations)
    Reference.NativeReferenceHerObservations actualReferences -> do
      observations <- traverse herObservation (zip indices actualModels)
      NativeHerLearningComparison
        <$> mathematical (HerPolicy.compareNativeHerCohort actualReferences observations)
    Reference.NativeReferenceArenaObservations actualReferences -> do
      observations <- traverse arenaObservation (zip indices actualModels)
      NativeArenaLearningComparison
        <$> mathematical (ArenaPolicy.compareNativeArenaCohort actualReferences observations)
  let work = map observedWork actualModels
  pure (NativeCohortAssessment replayed references referenceObject comparison work)
 where
  rowId models = case models of
    first : _ -> case first of
      Producer.NativeNeuralNumericalData value ->
        Neural.nativeNeuralRowId
          (Neural.nativeNeuralChildRow (Neural.nativeReturnedChild (Neural.nativeEvaluatedReturnedData value)))
      Producer.NativeArsNumericalData value ->
        Ars.nativeArsRowId
          (Ars.nativeArsChildRow (Ars.nativeArsReturnedChild (Ars.nativeArsFinalReturned value)))
      Producer.NativeArenaNumericalData value ->
        Arena.nativeAlphaZeroRowId
          ( Arena.nativeAlphaZeroChildRow
              (Arena.nativeAlphaZeroReturnedChild (Arena.nativeAlphaZeroEvaluatedReturnedData value))
          )
    [] -> ""

bindChild
  :: Cohort.NativeRlCohortPlan
  -> Cohort.NativeRlSeedPlan
  -> (Producer.NativeProducedChild, Producer.NativeNumericalModelData)
  -> Either NativeAssessmentFailure ()
bindChild expectedCohort expected (produced, model) = do
  let actualCohort = modelCohort model
      actual = modelSeedPlan model
      actualSingleton = Cohort.nativeRlSeedPlanSingleton actual
      expectedSingleton = Cohort.nativeRlSeedPlanSingleton expected
  require
    ( Cohort.nativeRlCohortPlanId actualCohort == Cohort.nativeRlCohortPlanId expectedCohort
        && Cohort.nativeRlCohortPlanTransport actualCohort == Cohort.nativeRlCohortPlanTransport expectedCohort
    )
    "native assessment actual full child cohort differs from captured reference cohort"
  require
    ( Cohort.nativeRlSeedPlanIndex actual == Cohort.nativeRlSeedPlanIndex expected
        && Producer.nativeChildIndex (Producer.nativeProducedChildData produced)
          == Cohort.nativeRlSeedPlanIndex actual
        && Cohort.nativeRlSeedPlanSeed actual == Cohort.nativeRlSeedPlanSeed expected
        && Singleton.nativeSingletonPlanId actualSingleton == Singleton.nativeSingletonPlanId expectedSingleton
        && Singleton.renderNativeSingletonPlan actualSingleton
          == Singleton.renderNativeSingletonPlan expectedSingleton
        && Cohort.nativeRlSeedPlanTrainingBudget actual == Cohort.nativeRlSeedPlanTrainingBudget expected
    )
    "native assessment actual full singleton index seed ID transport or budget differs"

modelCohort :: Producer.NativeNumericalModelData -> Cohort.NativeRlCohortPlan
modelCohort model = case model of
  Producer.NativeNeuralNumericalData value ->
    Neural.nativeNeuralRowCohort
      (Neural.nativeNeuralChildRow (Neural.nativeReturnedChild (Neural.nativeEvaluatedReturnedData value)))
  Producer.NativeArsNumericalData value ->
    Ars.nativeArsRowCohort
      (Ars.nativeArsChildRow (Ars.nativeArsReturnedChild (Ars.nativeArsFinalReturned value)))
  Producer.NativeArenaNumericalData value ->
    Arena.nativeAlphaZeroRowCohort
      ( Arena.nativeAlphaZeroChildRow
          (Arena.nativeAlphaZeroReturnedChild (Arena.nativeAlphaZeroEvaluatedReturnedData value))
      )

modelSeedPlan :: Producer.NativeNumericalModelData -> Cohort.NativeRlSeedPlan
modelSeedPlan model = case model of
  Producer.NativeNeuralNumericalData value ->
    Neural.nativeNeuralChildSeedPlan
      (Neural.nativeReturnedChild (Neural.nativeEvaluatedReturnedData value))
  Producer.NativeArsNumericalData value -> Ars.nativeArsChildSeedPlan (Ars.nativeArsReturnedChild (Ars.nativeArsFinalReturned value))
  Producer.NativeArenaNumericalData value ->
    Arena.nativeAlphaZeroChildSeedPlan
      (Arena.nativeAlphaZeroReturnedChild (Arena.nativeAlphaZeroEvaluatedReturnedData value))

returnObservation
  :: ReturnReference.NativeReturnReferenceSpec
  -> (Int, Producer.NativeNumericalModelData)
  -> Either NativeAssessmentFailure ReturnPolicy.NativeReturnSeedObservation
returnObservation referenceSpec (index, model) = do
  (initial, final) <- case model of
    Producer.NativeNeuralNumericalData value -> case ( Neural.nativeReturnedInitialEvaluation (Neural.nativeEvaluatedReturnedData value)
                                                     , Neural.nativeEvaluatedFinalEvaluation value
                                                     ) of
      (Neural.NativeReturnEvaluation first, Neural.NativeReturnEvaluation lastValue) -> Right (first, lastValue)
      _ -> Left (NativeAssessmentBindingRejected "native RETURN reference family contains a HER model")
    Producer.NativeArsNumericalData value -> case Ars.nativeArsFinalEvaluation value of
      Just final -> Right (Ars.nativeArsReturnedInitialEvaluation (Ars.nativeArsFinalReturned value), final)
      Nothing -> Left (NativeAssessmentBindingRejected "actual produced ARS final evaluation is absent")
    Producer.NativeArenaNumericalData _ -> Left (NativeAssessmentBindingRejected "native RETURN reference family contains an arena model")
  require
    ( Return.nativeEvaluationSpec initial == referenceSpec
        && Return.nativeEvaluationSpec final == referenceSpec
        && Return.nativeEvaluationStatus initial == Return.NativeEvaluationComplete
        && Return.nativeEvaluationStatus final == Return.NativeEvaluationComplete
    )
    "native RETURN initial/final complete fixed-case specification differs from actual references"
  pure
    ( ReturnPolicy.NativeReturnSeedObservation
        index
        (Cohort.nativeRlSeedPlanSeed (modelSeedPlan model))
        (Return.nativeEvaluationEpisodes initial)
        (Return.nativeEvaluationEpisodes final)
    )

herObservation
  :: (Int, Producer.NativeNumericalModelData)
  -> Either NativeAssessmentFailure HerPolicy.NativeHerSeedObservation
herObservation (index, model) = case model of
  Producer.NativeNeuralNumericalData value -> case ( Neural.nativeReturnedInitialEvaluation (Neural.nativeEvaluatedReturnedData value)
                                                   , Neural.nativeEvaluatedFinalEvaluation value
                                                   ) of
    (Neural.NativeHerEvaluation initial, Neural.NativeHerEvaluation final) ->
      Right
        ( HerPolicy.NativeHerSeedObservation
            index
            (Cohort.nativeRlSeedPlanSeed (modelSeedPlan model))
            initial
            final
        )
    _ -> Left (NativeAssessmentBindingRejected "native HER reference family contains a RETURN model")
  _ ->
    Left (NativeAssessmentBindingRejected "native HER reference family contains a host or arena model")

arenaObservation
  :: (Int, Producer.NativeNumericalModelData)
  -> Either NativeAssessmentFailure ArenaPolicy.NativeArenaSeedObservation
arenaObservation (index, model) = case model of
  Producer.NativeArenaNumericalData value ->
    Right
      ( ArenaPolicy.NativeArenaSeedObservation
          index
          (Cohort.nativeRlSeedPlanSeed (modelSeedPlan model))
          (Arena.nativeAlphaZeroReturnedInitialEvaluation (Arena.nativeAlphaZeroEvaluatedReturnedData value))
          (Arena.nativeAlphaZeroEvaluatedFinalEvaluation value)
      )
  _ ->
    Left
      (NativeAssessmentBindingRejected "native arena reference family contains a RETURN or HER model")

observedWork :: Producer.NativeNumericalModelData -> NativeObservedWorkData
observedWork model =
  let plan = modelSeedPlan model
      index = Cohort.nativeSeedIndexValue (Cohort.nativeRlSeedPlanIndex plan)
      seed = Cohort.nativeRlSeedPlanSeed plan
      budget = Cohort.nativeRlSeedPlanTrainingBudget plan
      fromCounters counters =
        NativeReturnObservedWork
          index
          seed
          budget
          (Common.observedEnvironmentTransitionCount counters)
          (Common.observedOptimizerUpdateCount counters)
   in case model of
        Producer.NativeNeuralNumericalData value ->
          let returned = Neural.nativeEvaluatedReturnedData value
              snapshot = Neural.nativeReturnedSnapshot returned
              warm =
                Low.foldNeuralSnapshot
                  (const Nothing)
                  (const Nothing)
                  (const Nothing)
                  ( \actual -> case Continuous.continuousPreparedWarmAdam actual of
                      Nothing -> Nothing
                      Just _ -> Just (Continuous.continuousPreparedWarmUpdateCount actual)
                  )
                  (const Nothing)
                  snapshot
           in fromCounters (Observation.returnedCounters (Neural.nativeReturnedPolicy returned)) warm
        Producer.NativeArsNumericalData value ->
          fromCounters
            (Common.rawTrainerCounters (Ars.nativeArsReturnedPolicy (Ars.nativeArsFinalReturned value)))
            Nothing
        Producer.NativeArenaNumericalData value ->
          let actual = Arena.nativeAlphaZeroReturnedRawObservation (Arena.nativeAlphaZeroEvaluatedReturnedData value)
           in NativeArenaObservedWork
                index
                seed
                budget
                (ArenaRaw.alphaZeroObservedGenerationTarget actual)
                (ArenaRaw.alphaZeroObservedGenerationCount actual)
                (ArenaRaw.alphaZeroObservedOptimizerApplicationDelta actual)
                (foldr (\_ count -> count + 1) 0 (ArenaRaw.alphaZeroObservedSamples actual))

comparisonFindings :: NativeLearningComparisonData -> [Text]
comparisonFindings actual = case actual of
  NativeReturnLearningComparison value -> ReturnPolicy.nativeReturnComparisonFailures value
  NativeHerLearningComparison value -> HerPolicy.nativeHerComparisonFailures value
  NativeArenaLearningComparison value -> ArenaPolicy.nativeArenaComparisonFindings value

require :: Bool -> Text -> Either NativeAssessmentFailure ()
require condition reason = unless condition (Left (NativeAssessmentBindingRejected reason))

mathematical :: Either Text a -> Either NativeAssessmentFailure a
mathematical = mapLeft NativeAssessmentMathematicsRejected

forceFailure :: NativeAssessmentFailure -> ()
forceFailure actual = case actual of
  NativeAssessmentBindingRejected detail -> Text.length detail `seq` ()
  NativeAssessmentMathematicsRejected detail -> Text.length detail `seq` ()
  NativeAssessmentSynchronousFailure detail -> detail `seq` ()

forceAssessment :: NativeCohortAssessment -> ()
forceAssessment actual =
  forceComparison (nativeAssessmentComparison actual) `seq`
    foldr (\work rest -> forceWork work `seq` rest) () (nativeAssessmentObservedWork actual)

forceTexts :: [Text] -> ()
forceTexts = foldr (\detail rest -> Text.length detail `seq` rest) ()
forceRational :: Rational -> ()
forceRational value = numerator value `seq` denominator value `seq` ()
forceDouble :: Double -> ()
forceDouble value = castDoubleToWord64 value `seq` ()

forceComparison :: NativeLearningComparisonData -> ()
forceComparison actual =
  forceTexts (comparisonFindings actual) `seq` case actual of
    NativeReturnLearningComparison value ->
      ReturnPolicy.nativeReturnComparisonJointCount value `seq`
        forceDouble (ReturnPolicy.nativeReturnComparisonMedianQuality value) `seq`
          foldr
            ( \seed rest ->
                ReturnPolicy.nativeReturnSeedComparisonIndex seed `seq`
                  forceRational (ReturnPolicy.nativeReturnSeedComparisonInitialMedian seed) `seq`
                    forceRational (ReturnPolicy.nativeReturnSeedComparisonFinalMedian seed) `seq`
                      forceDouble (ReturnPolicy.nativeReturnSeedComparisonLegacyQuality seed) `seq`
                        ReturnPolicy.nativeReturnSeedComparisonJointLearning seed `seq`
                          forceTexts (ReturnPolicy.nativeReturnSeedComparisonFindings seed) `seq`
                            rest
            )
            ()
            (ReturnPolicy.nativeReturnComparisonSeeds value)
    NativeHerLearningComparison value ->
      HerPolicy.nativeHerComparisonJointCount value `seq`
        forceDouble (HerPolicy.nativeHerComparisonMedianSuccessQuality value) `seq`
          forceDouble (HerPolicy.nativeHerComparisonMedianDistanceQuality value) `seq`
            foldr
              ( \seed rest ->
                  HerPolicy.nativeHerSeedComparisonIndex seed `seq`
                    HerPolicy.nativeHerSeedComparisonInitialSuccessCount seed `seq`
                      HerPolicy.nativeHerSeedComparisonFinalSuccessCount seed `seq`
                        forceRational (HerPolicy.nativeHerSeedComparisonInitialExactMeanDistance seed) `seq`
                          forceRational (HerPolicy.nativeHerSeedComparisonFinalExactMeanDistance seed) `seq`
                            forceDouble (HerPolicy.nativeHerSeedComparisonLegacySuccessQuality seed) `seq`
                              forceDouble (HerPolicy.nativeHerSeedComparisonLegacyDistanceQuality seed) `seq`
                                HerPolicy.nativeHerSeedComparisonJointLearning seed `seq`
                                  forceTexts (HerPolicy.nativeHerSeedComparisonFindings seed) `seq`
                                    rest
              )
              ()
              (HerPolicy.nativeHerComparisonSeeds value)
    NativeArenaLearningComparison value ->
      ArenaPolicy.nativeArenaComparisonJointCount value `seq`
        forceCriteria (ArenaPolicy.nativeArenaComparisonMedianCriteria value) `seq`
          foldr
            ( \seed rest ->
                ArenaPolicy.nativeArenaSeedComparisonIndex seed
                  `seq` forceCounts (ArenaPolicy.nativeArenaSeedComparisonInitialCounts seed)
                  `seq` forceCounts (ArenaPolicy.nativeArenaSeedComparisonFinalCounts seed)
                  `seq` foldr
                    (\(reference, passed) later -> reference `seq` passed `seq` later)
                    ()
                    (ArenaPolicy.nativeArenaSeedComparisonReferenceDecisions seed)
                  `seq` forceCriteria (ArenaPolicy.nativeArenaSeedComparisonLegacyCriteria seed)
                  `seq` ArenaPolicy.nativeArenaSeedComparisonJointLearning seed
                  `seq` forceTexts (ArenaPolicy.nativeArenaSeedComparisonFindings seed)
                  `seq` rest
            )
            ()
            (ArenaPolicy.nativeArenaComparisonSeeds value)
 where
  forceCounts value =
    ArenaPolicy.nativeArenaCountsWins value `seq`
      ArenaPolicy.nativeArenaCountsDraws value `seq`
        ArenaPolicy.nativeArenaCountsLosses value `seq`
          ()
  forceCriteria =
    foldr
      ( \criterion rest ->
          Text.length (Budget.coMetricName criterion) `seq`
            forceDouble (Budget.coMetricValue criterion) `seq`
              forceDouble (Budget.coThreshold criterion) `seq`
                Budget.coMetricGoal criterion `seq`
                  Budget.convergencePassed criterion `seq`
                    rest
      )
      ()

forceWork :: NativeObservedWorkData -> ()
forceWork value = case value of
  NativeReturnObservedWork index seed budget transitions updates warm ->
    index `seq`
      seed `seq`
        forceBudget budget `seq`
          transitions `seq`
            updates `seq`
              maybe () (`seq` ()) warm
  NativeArenaObservedWork index seed budget target observed updates samples ->
    index `seq`
      seed `seq`
        forceBudget budget `seq`
          target `seq`
            observed `seq`
              updates `seq`
                samples `seq`
                  ()
 where
  forceBudget budget =
    Budget.trainingBudgetKind budget `seq`
      Budget.trainingBudgetTargetUnits budget `seq`
        maybe () (`seq` ()) (Budget.trainingBudgetSeed budget)
