{-# LANGUAGE OverloadedStrings #-}

-- | Mathematical comparisons of raw native return observations. No value in
-- this module proves execution, budget completion, source/device provenance,
-- ARS applied-step lineage, checkpoint admission or five actual training runs.
module JitML.Product.NativeReturnLearningPolicy
  ( NativeReturnSeedObservation (..)
  , NativeReturnSeedComparison
  , NativeReturnCohortComparison
  , nativeReturnLearningPolicyContract
  , compareNativeReturnCohort
  , nativeReturnComparisonReferences
  , nativeReturnComparisonObservations
  , nativeReturnComparisonSeeds
  , nativeReturnComparisonJointCount
  , nativeReturnComparisonMedianQuality
  , nativeReturnComparisonFailures
  , nativeReturnComparisonCeiling
  , nativeReturnSeedComparisonIndex
  , nativeReturnSeedComparisonInitialMedian
  , nativeReturnSeedComparisonFinalMedian
  , nativeReturnSeedComparisonLegacyQuality
  , nativeReturnSeedComparisonJointLearning
  , nativeReturnSeedComparisonFindings
  ) where

import Control.Monad (unless)
import Data.List (find, sort)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)
import GHC.Float (castDoubleToWord64)

import JitML.RL.ConvergenceThresholds qualified as Thresholds
import JitML.RL.Framework qualified as Framework
import JitML.RL.NativeReturnCeiling qualified as Ceiling
import JitML.RL.NativeReturnReferences qualified as References
import JitML.RL.Simulator qualified as Sim

nativeReturnLearningPolicyContract :: Text
nativeReturnLearningPolicyContract =
  "native-return-learning-v2:canonical-base42-plus-0..4;served-index0;exact-paired-initial-median-strict;all-fixed-task-references-strict-except-equality-at-current-proven-maximum;keydoor-current-full-state-dp-v1;other-returns-no-tie;joint-at-least3of5;whole-five-median-unchanged-quality;served0-own-quality;finite-failures-retained;no-population-claim"

-- Public data only. A later authenticated producer must bind every episode to
-- the SAME preallocated case schedule and actual initial/final policy bytes.
data NativeReturnSeedObservation = NativeReturnSeedObservation
  { nativeReturnObservedSeedIndex :: !Int
  , nativeReturnObservedSeed :: !Word64
  , nativeReturnObservedInitialEpisodes :: ![References.NativeReturnEpisode]
  , nativeReturnObservedFinalEpisodes :: ![References.NativeReturnEpisode]
  }
  deriving stock (Eq, Show)

data NativeReturnSeedComparison
  = NativeReturnSeedComparison
      !Int
      !Rational
      !Rational
      !Double
      !Bool
      ![Text]
  deriving stock (Eq, Show)

-- Opaque comparisons keep the complete raw inputs, including finite failed
-- seeds. Empty findings are a mathematical result, never eligibility authority.
data NativeReturnCohortComparison
  = NativeReturnCohortComparison
      !References.NativeReturnReferenceSet
      ![NativeReturnSeedObservation]
      ![NativeReturnSeedComparison]
      !Int
      !Double
      ![Text]
      !(Maybe Ceiling.NativeReturnCeiling)
  deriving stock (Eq, Show)

nativeReturnComparisonReferences
  :: NativeReturnCohortComparison -> References.NativeReturnReferenceSet
nativeReturnComparisonReferences (NativeReturnCohortComparison value _ _ _ _ _ _) = value
nativeReturnComparisonObservations :: NativeReturnCohortComparison -> [NativeReturnSeedObservation]
nativeReturnComparisonObservations (NativeReturnCohortComparison _ value _ _ _ _ _) = value
nativeReturnComparisonSeeds :: NativeReturnCohortComparison -> [NativeReturnSeedComparison]
nativeReturnComparisonSeeds (NativeReturnCohortComparison _ _ value _ _ _ _) = value
nativeReturnComparisonJointCount :: NativeReturnCohortComparison -> Int
nativeReturnComparisonJointCount (NativeReturnCohortComparison _ _ _ value _ _ _) = value
nativeReturnComparisonMedianQuality :: NativeReturnCohortComparison -> Double
nativeReturnComparisonMedianQuality (NativeReturnCohortComparison _ _ _ _ value _ _) = value
nativeReturnComparisonFailures :: NativeReturnCohortComparison -> [Text]
nativeReturnComparisonFailures (NativeReturnCohortComparison _ _ _ _ _ value _) = value
nativeReturnComparisonCeiling :: NativeReturnCohortComparison -> Maybe Ceiling.NativeReturnCeiling
nativeReturnComparisonCeiling (NativeReturnCohortComparison _ _ _ _ _ _ value) = value
nativeReturnSeedComparisonIndex :: NativeReturnSeedComparison -> Int
nativeReturnSeedComparisonIndex (NativeReturnSeedComparison value _ _ _ _ _) = value
nativeReturnSeedComparisonInitialMedian :: NativeReturnSeedComparison -> Rational
nativeReturnSeedComparisonInitialMedian (NativeReturnSeedComparison _ value _ _ _ _) = value
nativeReturnSeedComparisonFinalMedian :: NativeReturnSeedComparison -> Rational
nativeReturnSeedComparisonFinalMedian (NativeReturnSeedComparison _ _ value _ _ _) = value
nativeReturnSeedComparisonLegacyQuality :: NativeReturnSeedComparison -> Double
nativeReturnSeedComparisonLegacyQuality (NativeReturnSeedComparison _ _ _ value _ _) = value
nativeReturnSeedComparisonJointLearning :: NativeReturnSeedComparison -> Bool
nativeReturnSeedComparisonJointLearning (NativeReturnSeedComparison _ _ _ _ value _) = value
nativeReturnSeedComparisonFindings :: NativeReturnSeedComparison -> [Text]
nativeReturnSeedComparisonFindings (NativeReturnSeedComparison _ _ _ _ _ value) = value

-- | Structural invalidity is Left. Every finite valid five-member input is
-- retained in Right, including a failed majority, quality or serving result.
-- Reference reward values are raw observations: structure/finite validation
-- here does not substitute actual simulator replay or producer authentication.
compareNativeReturnCohort
  :: References.NativeReturnReferenceSet
  -> [NativeReturnSeedObservation]
  -> Either Text NativeReturnCohortComparison
compareNativeReturnCohort references observations = do
  let spec = References.nativeReturnObservedSpec references
  canonical <-
    References.canonicalNativeReturnSpec
      (References.nativeReturnSpecAlgorithm spec)
      (References.nativeReturnSpecEnvironment spec)
  require
    (spec == canonical)
    "native return comparison spec differs from the complete current canonical declaration"
  declaration <-
    maybe
      (Left "native return comparison canonical quality declaration is absent")
      Right
      ( find
          ( \row ->
              Thresholds.fbrAlgorithm row == References.nativeReturnSpecAlgorithm spec
                && Thresholds.fbrEnvironment row == References.nativeReturnSpecEnvironment spec
          )
          Thresholds.fixedBudgetRlConvergenceRows
      )
  expectedControllers <- canonicalControllers spec
  let rawReferences = References.nativeReturnObservedReferences references
  require
    ( length rawReferences == length expectedControllers
        && and
          ( zipWith
              sameController
              (fmap References.nativeReturnObservedController rawReferences)
              expectedControllers
          )
    )
    "native return comparison requires every prescribed controller exactly once in canonical order"
  referenceMedians <- traverse (checkReference spec) rawReferences
  maximumProof <- Ceiling.proveCanonicalNativeReturnCeiling spec
  mapM_ (validateKnownCeiling maximumProof . References.nativeReturnObservedEpisodes) rawReferences
  require
    ( References.nativeReturnTotalEvaluationTransitions references
        == sum (fmap References.nativeReturnObservedEvaluationTransitions rawReferences)
    )
    "native return comparison whole reference transition count differs"
  require
    (fmap nativeReturnObservedSeedIndex observations == [0 .. 4])
    "native return comparison requires exactly five ordered indices0..4"
  comparisons <-
    traverse
      (compareSeed spec (Thresholds.fbrThreshold declaration) referenceMedians maximumProof)
      observations
  median <- middleOfFive (sort (fmap nativeReturnSeedComparisonLegacyQuality comparisons))
  case comparisons of
    served : _ -> do
      let jointCount = length (filter nativeReturnSeedComparisonJointLearning comparisons)
          failures =
            ["native return cohort has fewer than three joint learning successes" | jointCount < 3]
              <> [ "native return whole-five median fails the unchanged quality floor (median "
                     <> Text.pack (show median)
                     <> ", ordered per-seed quality "
                     <> Text.pack (show (fmap nativeReturnSeedComparisonLegacyQuality comparisons))
                     <> ", per-seed initial/final exact median "
                     <> Text.pack
                       ( show
                           [ (fromRational initial :: Double, fromRational final :: Double)
                           | comparison <- comparisons
                           , let initial = nativeReturnSeedComparisonInitialMedian comparison
                           , let final = nativeReturnSeedComparisonFinalMedian comparison
                           ]
                       )
                     <> ")"
                 | not (Thresholds.passesConvergence (Thresholds.fbrThreshold declaration) median)
                 ]
              <> fmap ("native return served index0 fails: " <>) (nativeReturnSeedComparisonFindings served)
      pure
        ( NativeReturnCohortComparison
            references
            observations
            comparisons
            jointCount
            median
            failures
            maximumProof
        )
    [] -> Left "native return comparison has no original served observation"
 where
  compareSeed spec threshold referenceMedians maximumProof observed = do
    let index = nativeReturnObservedSeedIndex observed
    require
      (nativeReturnObservedSeed observed == 42 + fromIntegral index)
      "native return comparison seed differs from prescribed42+index"
    (initialExact, _) <- summarizeEpisodes spec (nativeReturnObservedInitialEpisodes observed)
    (finalExact, legacyQuality) <- summarizeEpisodes spec (nativeReturnObservedFinalEpisodes observed)
    validateKnownCeiling maximumProof (nativeReturnObservedInitialEpisodes observed)
    validateKnownCeiling maximumProof (nativeReturnObservedFinalEpisodes observed)
    let improves = finalExact > initialExact
        beatsReferences = all (passesReference maximumProof finalExact) referenceMedians
        joint = improves && beatsReferences
        findings =
          ["final exact median does not strictly exceed its authentic initial observation" | not improves]
            <> [ "final exact median does not strictly exceed every fixed task reference or equal its independently proved maximum"
               | not beatsReferences
               ]
            <> [ "final primary metric fails the unchanged quality floor"
               | not (Thresholds.passesConvergence threshold legacyQuality)
               ]
    pure (NativeReturnSeedComparison index initialExact finalExact legacyQuality joint findings)

-- The exception is available only from the actual complete canonical solver.
-- In particular neither equality below its bound nor a supplied number passes.
passesReference :: Maybe Ceiling.NativeReturnCeiling -> Rational -> Rational -> Bool
passesReference maximumProof final reference =
  final > reference || case maximumProof of
    Just proof ->
      let maximumValue = Ceiling.nativeReturnCeilingUpperBound proof
       in reference == maximumValue && final == maximumValue
    Nothing -> False

-- All episodes have already passed finite/complete evaluation validation.
-- Reject an impossible value rather than allowing a forged above-bound value
-- through the ordinary strict-reference branch or hiding it in a median.
validateKnownCeiling
  :: Maybe Ceiling.NativeReturnCeiling -> [References.NativeReturnEpisode] -> Either Text ()
validateKnownCeiling Nothing _ = Right ()
validateKnownCeiling (Just proof) episodes =
  require
    ( all
        ((<= Ceiling.nativeReturnCeilingUpperBound proof) . toRational . References.nativeReturnEpisodeReward)
        episodes
    )
    "native return episode exceeds the independently proved current task maximum"

checkReference
  :: References.NativeReturnReferenceSpec
  -> References.NativeReturnReferenceObservation
  -> Either Text Rational
checkReference spec observed = do
  let episodes = References.nativeReturnObservedEpisodes observed
  (exact, _) <- summarizeEpisodes spec episodes
  require
    ( References.nativeReturnObservedEvaluationTransitions observed
        == sum (fmap (toInteger . References.nativeReturnEpisodeSteps) episodes)
    )
    "native return comparison controller transition count differs"
  pure exact

summarizeEpisodes
  :: References.NativeReturnReferenceSpec
  -> [References.NativeReturnEpisode]
  -> Either Text (Rational, Double)
summarizeEpisodes spec episodes = do
  let count = References.nativeReturnSpecEpisodeCount spec
      horizon = References.nativeReturnSpecHorizon spec
  require
    (fmap References.nativeReturnEpisodeId episodes == [0 .. count - 1])
    "native return comparison requires every case exactly once in canonical order"
  require
    ( all
        ( \episode ->
            References.nativeReturnEpisodeSteps episode > 0
              && References.nativeReturnEpisodeSteps episode <= horizon
              && ( References.nativeReturnEpisodeTerminated episode
                     || References.nativeReturnEpisodeSteps episode == horizon
                 )
        )
        episodes
    )
    "native return comparison episode termination or horizon is incomplete"
  evaluation <-
    Framework.mkEvaluationSet
      (fromIntegral count)
      [ ( fromIntegral (References.nativeReturnEpisodeId episode)
        , References.nativeReturnEpisodeReward episode
        , References.nativeReturnEpisodeSteps episode
        , References.nativeReturnEpisodeTerminated episode
        )
      | episode <- episodes
      ]
  let legacy = Framework.evaluationSetMedianReward evaluation
  require (finite legacy) "native return comparison legacy primary summary is nonfinite"
  exact <- exactMedian (fmap (toRational . References.nativeReturnEpisodeReward) episodes)
  pure (exact, legacy)

canonicalControllers
  :: References.NativeReturnReferenceSpec -> Either Text [References.NativeReturnController]
canonicalControllers spec = case References.nativeReturnSpecDomain spec of
  References.NativeContinuous {} -> do
    wrapped <-
      maybe
        (Left "native return comparison canonical continuous simulator is absent")
        Right
        (Sim.lookupContinuousEnvironmentByName (References.nativeReturnSpecEnvironment spec))
    case wrapped of Sim.SomeContinuousEnvironment env -> References.continuousReferenceControllers env
  _ -> do
    wrapped <-
      maybe
        (Left "native return comparison canonical discrete simulator is absent")
        Right
        (Sim.lookupSimulatedEnvironmentByName (References.nativeReturnSpecEnvironment spec))
    case wrapped of Sim.SomeSimulatedEnvironment env -> References.discreteReferenceControllers env

sameController :: References.NativeReturnController -> References.NativeReturnController -> Bool
sameController first second = case (first, second) of
  (References.ConstantDiscrete action, References.ConstantDiscrete expected) -> action == expected
  (References.FixedMaskedPreference order, References.FixedMaskedPreference expected) -> order == expected
  (References.ConstantContinuous kind value, References.ConstantContinuous expectedKind expectedValue) ->
    kind == expectedKind && castDoubleToWord64 value == castDoubleToWord64 expectedValue
  _ -> False

exactMedian :: [Rational] -> Either Text Rational
exactMedian values =
  let count = length values
      (lower, upper) = splitAt (count `div` 2) (sort values)
   in case (reverse lower, upper) of
        (left : _, right : _) | even count -> Right ((left + right) / 2)
        (_, middle : _) | odd count -> Right middle
        _ -> Left "native return exact median requires nonempty complete observations"

middleOfFive :: [Double] -> Either Text Double
middleOfFive [_, _, middle, _, _] = Right middle
middleOfFive _ = Left "native return quality median requires exactly five observations"

require :: Bool -> Text -> Either Text ()
require condition message = unless condition (Left message)
finite :: Double -> Bool
finite value = not (isNaN value || isInfinite value)
