{-# LANGUAGE OverloadedStrings #-}

-- | Fixed-case mathematical observations only. These comparisons establish no
-- five-model execution, authentic initialization, device/provider origin,
-- durable retention, parent authentication, qualification or Store admission.
module JitML.Product.NativeArenaLearningPolicy
  ( NativeArenaScoreCounts
  , mkNativeArenaScoreCounts
  , nativeArenaCountsWins
  , nativeArenaCountsDraws
  , nativeArenaCountsLosses
  , nativeArenaCountsExactScore
  , nativeArenaCountsBeatReference
  , NativeArenaSeedObservation (..)
  , NativeArenaReferenceCalibration
  , NativeArenaSeedComparison
  , NativeArenaCohortComparison
  , nativeArenaLearningPolicyContract
  , observeNativeArenaReferenceCalibration
  , observeNativeArenaReferenceCalibrationOnTape
  , compareNativeArenaCohort
  , NativeArenaCohortComparisonData (..)
  , compareNativeArenaCohortData
  , nativeArenaCalibrationSpec
  , nativeArenaCalibrationTape
  , nativeArenaCalibrationReferences
  , nativeArenaCalibrationCounts
  , nativeArenaCalibrationMaximum
  , nativeArenaComparisonCalibration
  , nativeArenaComparisonObservations
  , nativeArenaComparisonSeeds
  , nativeArenaComparisonJointCount
  , nativeArenaComparisonMedianCriteria
  , nativeArenaComparisonFindings
  , nativeArenaSeedComparisonIndex
  , nativeArenaSeedComparisonInitialCounts
  , nativeArenaSeedComparisonFinalCounts
  , nativeArenaSeedComparisonReferenceDecisions
  , nativeArenaSeedComparisonLegacyCriteria
  , nativeArenaSeedComparisonJointLearning
  , nativeArenaSeedComparisonFindings
  ) where

import Control.Exception (evaluate)
import Control.Exception.Safe (tryAny)
import Control.Monad (foldM, unless, when)
import Data.Either.Combinators (mapLeft)
import Data.List (sort)
import Data.Ratio ((%))
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word64)
import GHC.Float (castDoubleToWord64)

import JitML.RL.AlphaZero qualified as Game
import JitML.RL.AlphaZero.ArenaTape qualified as Tape
import JitML.RL.AlphaZero.NativeArenaEvaluation qualified as Arena
import JitML.RL.AlphaZero.NativeArenaReferences qualified as Ref
import JitML.RL.ConvergenceThresholds qualified as Thresholds
import JitML.Training.Budget qualified as Budget

nativeArenaLearningPolicyContract :: Text
nativeArenaLearningPolicyContract =
  "native-arena-learning-v1:canonical-four-games;fixed-row-base7961-nine-addressed-cases;training-seeds42..46;served-index0;exact-wdl-rational;strict-initial-gain;each-uniform-and-neutral-mcts-reference-strict-except-equality-at-structural-maximum1;joint-at-least3of5;whole-five-median-both-unchanged-criteria;served0-own-both-criteria;complete-finite-failures-retained;no-population-or-origin-claim"

-- Arithmetic DATA only. The constructor is hidden; this refiner cannot mint a
-- calibration, raw evaluation, per-seed comparison or cohort comparison.
data NativeArenaScoreCounts = NativeArenaScoreCounts !Int !Int !Int
  deriving stock (Eq, Show)

mkNativeArenaScoreCounts :: Int -> Int -> Int -> Either Text NativeArenaScoreCounts
mkNativeArenaScoreCounts wins draws losses = do
  require
    (wins >= 0 && draws >= 0 && losses >= 0)
    "native arena score counts must be nonnegative"
  require
    (toInteger wins + toInteger draws + toInteger losses == 9)
    "native arena score counts must cover exactly nine cases"
  pure (NativeArenaScoreCounts wins draws losses)

nativeArenaCountsWins :: NativeArenaScoreCounts -> Int
nativeArenaCountsWins (NativeArenaScoreCounts value _ _) = value
nativeArenaCountsDraws :: NativeArenaScoreCounts -> Int
nativeArenaCountsDraws (NativeArenaScoreCounts _ value _) = value
nativeArenaCountsLosses :: NativeArenaScoreCounts -> Int
nativeArenaCountsLosses (NativeArenaScoreCounts _ _ value) = value
nativeArenaCountsExactScore :: NativeArenaScoreCounts -> Rational
nativeArenaCountsExactScore (NativeArenaScoreCounts wins draws _) =
  (2 * toInteger wins + toInteger draws) % 18

-- Every valid case contributes 0, one half or 1. Equality is allowed only at
-- the universal score bound and only when this actual reference attains it.
nativeArenaCountsBeatReference :: NativeArenaScoreCounts -> NativeArenaScoreCounts -> Bool
nativeArenaCountsBeatReference final reference =
  let finalScore = nativeArenaCountsExactScore final
      referenceScore = nativeArenaCountsExactScore reference
   in finalScore > referenceScore || (finalScore == referenceScore && referenceScore == 1)

-- Labels and raw observations are supplied DATA. A later concrete producer
-- must independently bind them to the actual child and its numerical history.
data NativeArenaSeedObservation = NativeArenaSeedObservation
  { nativeArenaObservedSeedIndex :: !Int
  , nativeArenaObservedSeed :: !Word64
  , nativeArenaObservedInitial :: !Arena.RawNativeArenaEvaluation
  , nativeArenaObservedFinal :: !Arena.RawNativeArenaEvaluation
  }
  deriving stock (Eq, Show)

-- No raw/decoder/callback constructor for this actual host calculation.
-- Getters return ordinary immutable data, not authentication authority.
data NativeArenaReferenceCalibration
  = NativeArenaReferenceCalibration
      !Ref.NativeArenaSpec
      !Tape.ArenaTape
      !Ref.NativeArenaReferenceSet
      ![(Ref.NativeArenaReference, NativeArenaScoreCounts)]
  deriving stock (Eq, Show)

data NativeArenaSeedComparison
  = NativeArenaSeedComparison
      !Int
      !NativeArenaScoreCounts
      !NativeArenaScoreCounts
      ![(Ref.NativeArenaReference, Bool)]
      ![Budget.ConvergenceObservation]
      !Bool
      ![Text]
  deriving stock (Eq, Show)

data NativeArenaCohortComparison
  = NativeArenaCohortComparison
      !NativeArenaReferenceCalibration
      ![NativeArenaSeedObservation]
      ![NativeArenaSeedComparison]
      !Int
      ![Budget.ConvergenceObservation]
      ![Text]
  deriving stock (Eq, Show)

nativeArenaCalibrationSpec :: NativeArenaReferenceCalibration -> Ref.NativeArenaSpec
nativeArenaCalibrationSpec (NativeArenaReferenceCalibration value _ _ _) = value
nativeArenaCalibrationTape :: NativeArenaReferenceCalibration -> Tape.ArenaTape
nativeArenaCalibrationTape (NativeArenaReferenceCalibration _ value _ _) = value
nativeArenaCalibrationReferences :: NativeArenaReferenceCalibration -> Ref.NativeArenaReferenceSet
nativeArenaCalibrationReferences (NativeArenaReferenceCalibration _ _ value _) = value
nativeArenaCalibrationCounts
  :: NativeArenaReferenceCalibration -> [(Ref.NativeArenaReference, NativeArenaScoreCounts)]
nativeArenaCalibrationCounts (NativeArenaReferenceCalibration _ _ _ value) = value
nativeArenaCalibrationMaximum :: NativeArenaReferenceCalibration -> Rational
nativeArenaCalibrationMaximum _ = 1

nativeArenaComparisonCalibration :: NativeArenaCohortComparison -> NativeArenaReferenceCalibration
nativeArenaComparisonCalibration (NativeArenaCohortComparison value _ _ _ _ _) = value
nativeArenaComparisonObservations :: NativeArenaCohortComparison -> [NativeArenaSeedObservation]
nativeArenaComparisonObservations (NativeArenaCohortComparison _ value _ _ _ _) = value
nativeArenaComparisonSeeds :: NativeArenaCohortComparison -> [NativeArenaSeedComparison]
nativeArenaComparisonSeeds (NativeArenaCohortComparison _ _ value _ _ _) = value
nativeArenaComparisonJointCount :: NativeArenaCohortComparison -> Int
nativeArenaComparisonJointCount (NativeArenaCohortComparison _ _ _ value _ _) = value
nativeArenaComparisonMedianCriteria
  :: NativeArenaCohortComparison -> [Budget.ConvergenceObservation]
nativeArenaComparisonMedianCriteria (NativeArenaCohortComparison _ _ _ _ value _) = value
nativeArenaComparisonFindings :: NativeArenaCohortComparison -> [Text]
nativeArenaComparisonFindings (NativeArenaCohortComparison _ _ _ _ _ value) = value

nativeArenaSeedComparisonIndex :: NativeArenaSeedComparison -> Int
nativeArenaSeedComparisonIndex (NativeArenaSeedComparison value _ _ _ _ _ _) = value
nativeArenaSeedComparisonInitialCounts :: NativeArenaSeedComparison -> NativeArenaScoreCounts
nativeArenaSeedComparisonInitialCounts (NativeArenaSeedComparison _ value _ _ _ _ _) = value
nativeArenaSeedComparisonFinalCounts :: NativeArenaSeedComparison -> NativeArenaScoreCounts
nativeArenaSeedComparisonFinalCounts (NativeArenaSeedComparison _ _ value _ _ _ _) = value
nativeArenaSeedComparisonReferenceDecisions
  :: NativeArenaSeedComparison -> [(Ref.NativeArenaReference, Bool)]
nativeArenaSeedComparisonReferenceDecisions (NativeArenaSeedComparison _ _ _ value _ _ _) = value
nativeArenaSeedComparisonLegacyCriteria
  :: NativeArenaSeedComparison -> [Budget.ConvergenceObservation]
nativeArenaSeedComparisonLegacyCriteria (NativeArenaSeedComparison _ _ _ _ value _ _) = value
nativeArenaSeedComparisonJointLearning :: NativeArenaSeedComparison -> Bool
nativeArenaSeedComparisonJointLearning (NativeArenaSeedComparison _ _ _ _ _ value _) = value
nativeArenaSeedComparisonFindings :: NativeArenaSeedComparison -> [Text]
nativeArenaSeedComparisonFindings (NativeArenaSeedComparison _ _ _ _ _ _ value) = value

-- The evaluator owns the two actual reference calculations. Strictly inspect
-- every returned field before creating a calibration; never accept supplied
-- reference results or retry failures. Safe tryAny propagates async exceptions.
observeNativeArenaReferenceCalibration
  :: Ref.NativeArenaSpec -> IO (Either Text NativeArenaReferenceCalibration)
observeNativeArenaReferenceCalibration = observeReferenceCalibration Nothing

-- Supplied opaque tape remains the actual evaluator input. Validation reuses
-- the public complete-byte verifier; it never replaces the supplied tape.
-- This calculates reference DATA only, with no parent/training authority.
observeNativeArenaReferenceCalibrationOnTape
  :: Ref.NativeArenaSpec -> Tape.ArenaTape -> IO (Either Text NativeArenaReferenceCalibration)
observeNativeArenaReferenceCalibrationOnTape supplied tape = observeReferenceCalibration (Just tape) supplied

observeReferenceCalibration
  :: Maybe Tape.ArenaTape -> Ref.NativeArenaSpec -> IO (Either Text NativeArenaReferenceCalibration)
observeReferenceCalibration suppliedTape supplied = do
  attempted <- tryAny $ do
    _ <- evaluate (length (show supplied))
    case canonicalSpec supplied of
      Left reason -> forceLeft reason
      Right spec -> do
        let tape = case suppliedTape of
              Nothing -> Ref.materializeNativeArenaTape spec
              Just actual -> actual
            checkedTape = case suppliedTape of
              Nothing -> Right ()
              Just actual -> do
                verified <-
                  mapLeft
                    (Text.pack . show)
                    (Tape.verifyArenaTape (Ref.nativeArenaSpecTape spec) (Tape.arenaTapeBytes actual))
                require
                  (verified == actual)
                  "native arena supplied calibration tape differs from its verified complete bytes"
        _ <- evaluate (length (show tape))
        returned <- case checkedTape of
          Left reason -> pure (Left reason)
          Right () -> Ref.evaluateNativeArenaReferences spec tape >>= evaluate
        case returned of
          Left reason -> forceLeft reason
          Right family -> do
            -- Show instances are derived over the complete finite nested DATA
            -- fields. Demanding the full rendered spine forces all retained
            -- fields, not merely their outer constructors or a display prefix.
            _ <- evaluate (length (show family))
            case validateReferenceFamily spec tape family of
              Left reason -> forceLeft reason
              Right counts -> do
                _ <- evaluate (length (show counts))
                pure (Right (NativeArenaReferenceCalibration spec tape family counts))
  case attempted of
    Left _ -> pure (Left "native arena reference calibration synchronous failure")
    Right result -> pure result
 where
  forceLeft reason = do
    _ <- evaluate (Text.length reason)
    pure (Left reason)

canonicalSpec :: Ref.NativeArenaSpec -> Either Text Ref.NativeArenaSpec
canonicalSpec supplied = do
  canonical <- Ref.canonicalNativeArenaSpec (Ref.nativeArenaSpecRowId supplied)
  require
    (supplied == canonical)
    "native arena calibration specification differs from complete current declaration"
  pure canonical

validateReferenceFamily
  :: Ref.NativeArenaSpec
  -> Tape.ArenaTape
  -> Ref.NativeArenaReferenceSet
  -> Either Text [(Ref.NativeArenaReference, NativeArenaScoreCounts)]
validateReferenceFamily spec tape family = do
  require
    (Ref.nativeArenaObservedSpec family == spec)
    "native arena actual reference family specification differs"
  let values = Ref.nativeArenaObservedReferences family
  require
    (map Ref.nativeArenaObservedReference values == [Ref.PlainLegalUniform, Ref.NeutralLegalMcts])
    "native arena actual reference family inventory differs"
  counts <- traverse (validateReference spec tape) values
  require
    ( Ref.nativeArenaTotalEvaluationTransitions family
        == sum (map Ref.nativeArenaObservedEvaluationTransitions values)
        && Ref.nativeArenaTotalSearchRootVisits family
          == sum (map Ref.nativeArenaObservedSearchRootVisits values)
    )
    "native arena actual reference family work differs"
  pure (zip (map Ref.nativeArenaObservedReference values) counts)

validateReference
  :: Ref.NativeArenaSpec
  -> Tape.ArenaTape
  -> Ref.NativeArenaObservation
  -> Either Text NativeArenaScoreCounts
validateReference spec tape observed = do
  require
    (Ref.nativeArenaObservedTape observed == tape)
    "native arena actual reference tape differs"
  let episodes = Ref.nativeArenaObservedEpisodes observed
  require
    (map Ref.nativeArenaEpisodeId episodes == [0 .. 8])
    "native arena actual reference requires all nine cases in order"
  mapM_ (validateReferenceEpisode spec tape (Ref.nativeArenaObservedReference observed)) episodes
  counts <- episodeCounts episodes
  let exact = nativeArenaCountsExactScore counts
      decisions = concatMap Ref.nativeArenaEpisodeDecisions episodes
  require
    ( Ref.nativeArenaObservedWins observed == nativeArenaCountsWins counts
        && Ref.nativeArenaObservedDraws observed == nativeArenaCountsDraws counts
        && Ref.nativeArenaObservedLosses observed == nativeArenaCountsLosses counts
        && Ref.nativeArenaObservedExactScore observed == exact
        && sameDouble (Ref.nativeArenaObservedScore observed) (fromRational exact)
    )
    "native arena actual reference scoring differs"
  require
    ( Ref.nativeArenaObservedEvaluationTransitions observed == toInteger (length decisions)
        && Ref.nativeArenaObservedSearchRootVisits observed
          == sum (map (toInteger . Ref.nativeArenaDecisionSearchRootVisits) decisions)
    )
    "native arena actual reference work differs"
  pure counts

-- Recorded-rule replay only: use actual public game transitions and selectors,
-- never reimplement MCTS or play another reference game during validation.
validateReferenceEpisode
  :: Ref.NativeArenaSpec
  -> Tape.ArenaTape
  -> Ref.NativeArenaReference
  -> Ref.NativeArenaEpisode
  -> Either Text ()
validateReferenceEpisode spec tape reference episode = do
  let initial = Game.initialStateFor (Ref.nativeArenaSpecRowId spec)
      decisions = Ref.nativeArenaEpisodeDecisions episode
      horizon = Ref.nativeArenaSpecMaxPlies spec
  require
    (Ref.nativeArenaEpisodeInitialState episode == initial)
    "native arena actual reference initial state differs"
  final <- foldM one initial (zip [0 :: Int ..] decisions)
  let normalized = Game.normaliseForcedPass final
      outcome = Game.gameOutcome normalized
      truncated = Ref.nativeArenaEpisodeHorizonTruncated episode
  require
    ( length decisions <= horizon
        && Ref.nativeArenaEpisodeFinalState episode == normalized
        && Ref.nativeArenaEpisodeRuleOutcome episode == outcome
    )
    "native arena actual reference final state differs"
  require
    ( if truncated
        then length decisions == horizon && Ref.nativeArenaEpisodeScoredOutcome episode == Game.GameDraw
        else outcome /= Game.GameInProgress && Ref.nativeArenaEpisodeScoredOutcome episode == outcome
    )
    "native arena actual reference terminal or horizon score differs"
 where
  one raw (slot, decision) = do
    let state = Game.normaliseForcedPass raw
        player = Game.gameCurrentPlayer state
        legal = Game.legalMoves state
        actions = Ref.nativeArenaSpecActionCount spec
        expectedVisits =
          if player == 1 && reference == Ref.NeutralLegalMcts
            then Ref.nativeArenaSpecArenaSimulations spec
            else 0
    require
      ( slot < Ref.nativeArenaSpecMaxPlies spec
          && Game.gameOutcome state == Game.GameInProgress
          && Ref.nativeArenaDecisionSlot decision == slot
          && Ref.nativeArenaDecisionRawState decision == raw
          && Ref.nativeArenaDecisionNormalizedState decision == state
          && Ref.nativeArenaDecisionForcedPass decision == (raw /= state)
          && Ref.nativeArenaDecisionPlayer decision == player
          && Ref.nativeArenaDecisionLegalActions decision == legal
      )
      "native arena actual reference decision state or legal domain differs"
    entry <-
      mapTape
        ( Tape.arenaTapeLookup
            tape
            (fromIntegral (Ref.nativeArenaEpisodeId episode))
            (fromIntegral slot)
            player
        )
    require
      ( Ref.nativeArenaDecisionTapeEntry decision == entry
          && Ref.nativeArenaDecisionSearchRootVisits decision == expectedVisits
      )
      "native arena actual reference addressed tape or search visits differ"
    let distribution = Ref.nativeArenaDecisionDistribution decision
    when (reference == Ref.PlainLegalUniform || player == -1) $ do
      uniform <- Ref.nativeArenaUniformDistribution actions legal
      require
        (sameVector distribution uniform)
        "native arena actual reference uniform distribution differs"
    action <-
      if player == 1
        then Ref.sampleNativeArenaPlayerAction actions legal distribution entry
        else Ref.sampleNativeArenaOpponentAction actions legal entry
    let next = Game.applyMove action state
    require
      ( Ref.nativeArenaDecisionAction decision == action
          && Ref.nativeArenaDecisionPostState decision == next
          && Ref.nativeArenaDecisionPostOutcome decision == Game.gameOutcome next
      )
      "native arena actual reference sampled transition differs"
    pure next

episodeCounts :: [Ref.NativeArenaEpisode] -> Either Text NativeArenaScoreCounts
episodeCounts episodes = do
  require (length episodes == 9) "native arena score requires exactly nine episodes"
  let outcomes = map Ref.nativeArenaEpisodeScoredOutcome episodes
  require (all validOutcome outcomes) "native arena score has an unfinished or invalid outcome"
  mkNativeArenaScoreCounts
    (length (filter (== Game.GameWon 1) outcomes))
    (length (filter (== Game.GameDraw) outcomes))
    (length (filter (== Game.GameWon (-1)) outcomes))
 where
  validOutcome outcome = case outcome of
    Game.GameWon player -> player == 1 || player == -1
    Game.GameDraw -> True
    Game.GameInProgress -> False

-- | Ordinary decoded mathematical DATA. These public fields cannot create an
-- actual reference calibration, producer, model or qualification capability.
data NativeArenaCohortComparisonData = NativeArenaCohortComparisonData
  { nativeArenaDataSpecification :: !Ref.NativeArenaSpec
  , nativeArenaDataTape :: !Tape.ArenaTape
  , nativeArenaDataReferences :: !Ref.NativeArenaReferenceSet
  , nativeArenaDataObservations :: ![NativeArenaSeedObservation]
  , nativeArenaDataSeeds :: ![NativeArenaSeedComparison]
  , nativeArenaDataJointCount :: !Int
  , nativeArenaDataMedianCriteria :: ![Budget.ConvergenceObservation]
  , nativeArenaDataFindings :: ![Text]
  }
  deriving stock (Eq, Show)

-- Existing actual-calibration route keeps its canonical check, references and
-- all seed/median/served checks in the same order. No additional observation.
compareNativeArenaCohort
  :: NativeArenaReferenceCalibration
  -> [NativeArenaSeedObservation]
  -> Either Text NativeArenaCohortComparison
compareNativeArenaCohort calibration observations = do
  spec <- canonicalSpec (nativeArenaCalibrationSpec calibration)
  let tape = nativeArenaCalibrationTape calibration
      references = nativeArenaCalibrationCounts calibration
  (comparisons, jointCount, medians, findings) <-
    compareCohortRecords spec tape references observations
  pure (NativeArenaCohortComparison calibration observations comparisons jointCount medians findings)

-- | Parent mathematical audit of retained records only. Verify the complete
-- canonical tape and both reference transcripts before the shared comparison;
-- never construct NativeArenaReferenceCalibration from decoded DATA.
compareNativeArenaCohortData
  :: Ref.NativeArenaSpec
  -> Tape.ArenaTape
  -> Ref.NativeArenaReferenceSet
  -> [NativeArenaSeedObservation]
  -> Either Text NativeArenaCohortComparisonData
compareNativeArenaCohortData supplied tape references observations = do
  spec <- canonicalSpec supplied
  checkedTape <-
    mapTape (Tape.verifyArenaTape (Ref.nativeArenaSpecTape spec) (Tape.arenaTapeBytes tape))
  require (checkedTape == tape) "native arena decoded canonical tape differs"
  counts <- validateReferenceFamily spec tape references
  (comparisons, jointCount, medians, findings) <- compareCohortRecords spec tape counts observations
  pure
    ( NativeArenaCohortComparisonData
        spec
        tape
        references
        observations
        comparisons
        jointCount
        medians
        findings
    )

compareCohortRecords
  :: Ref.NativeArenaSpec
  -> Tape.ArenaTape
  -> [(Ref.NativeArenaReference, NativeArenaScoreCounts)]
  -> [NativeArenaSeedObservation]
  -> Either Text ([NativeArenaSeedComparison], Int, [Budget.ConvergenceObservation], [Text])
compareCohortRecords spec tape references observations = do
  require
    (map nativeArenaObservedSeedIndex observations == [0 .. 4])
    "native arena cohort requires all five indices in original order"
  require
    (map nativeArenaObservedSeed observations == [42 .. 46])
    "native arena cohort seeds differ from prescribed42..46"
  declaration <- currentDeclaration spec
  comparisons <- traverse (compareSeed spec tape references declaration) observations
  medians <- medianCriteria declaration comparisons
  case comparisons of
    served : _ -> do
      let jointCount = length (filter nativeArenaSeedComparisonJointLearning comparisons)
          findings =
            ["native arena cohort has fewer than three joint learning successes" | jointCount < 3]
              <> [ "native arena whole-five median fails unchanged criterion: " <> Budget.coMetricName criterion
                 | criterion <- medians
                 , not (Budget.convergencePassed criterion)
                 ]
              <> map ("native arena served index0 fails: " <>) (nativeArenaSeedComparisonFindings served)
      pure (comparisons, jointCount, medians, findings)
    [] -> Left "native arena cohort has no original served observation"

currentDeclaration :: Ref.NativeArenaSpec -> Either Text Thresholds.AlphaZeroGameConvergenceRow
currentDeclaration spec = case filter
  ((== Ref.nativeArenaSpecRowId spec) . Thresholds.azgGame)
  Thresholds.alphaZeroGameConvergenceRows of
  [row] -> do
    require
      ( Thresholds.azgBudget row == Ref.nativeArenaSpecTrainingBudget spec
          && Thresholds.azgMctsSimulationsPerMove row == Ref.nativeArenaSpecTrainingSimulations spec
      )
      "native arena current quality declaration differs from canonical specification"
    pure row
  _ -> Left "native arena quality declaration is not a unique current canonical game"

-- Retain the existing strict tuple-pattern demand in the recorded reference
-- mapping. Data.Bifunctor.second documents increased laziness for this lambda.
{- HLINT ignore compareSeed "Use second" -}
compareSeed
  :: Ref.NativeArenaSpec
  -> Tape.ArenaTape
  -> [(Ref.NativeArenaReference, NativeArenaScoreCounts)]
  -> Thresholds.AlphaZeroGameConvergenceRow
  -> NativeArenaSeedObservation
  -> Either Text NativeArenaSeedComparison
compareSeed spec tape references declaration observed = do
  initial <- validateLearned spec tape (nativeArenaObservedInitial observed)
  final <- validateLearned spec tape (nativeArenaObservedFinal observed)
  let improves = nativeArenaCountsExactScore final > nativeArenaCountsExactScore initial
      referenceDecisions = map (\(reference, counts) -> (reference, nativeArenaCountsBeatReference final counts)) references
      beatsReferences = all snd referenceDecisions
      joint = improves && beatsReferences
  legalRate <- learnedLegalRate (nativeArenaObservedFinal observed)
  criteria <-
    sequence
      [ Budget.remeasureCriterion
          (fromRational (nativeArenaCountsExactScore final))
          (Thresholds.azgArenaWinRate declaration)
      , Budget.remeasureCriterion legalRate (Thresholds.azgLegalMoveRate declaration)
      ]
  let findings =
        ["final exact arena score does not strictly exceed its initial observation" | not improves]
          <> [ "final exact arena score does not exceed reference or equal its maximum: "
                 <> referenceName reference
             | (reference, passed) <- referenceDecisions
             , not passed
             ]
          <> [ "final metric fails unchanged criterion: " <> Budget.coMetricName criterion
             | criterion <- criteria
             , not (Budget.convergencePassed criterion)
             ]
  pure
    ( NativeArenaSeedComparison
        (nativeArenaObservedSeedIndex observed)
        initial
        final
        referenceDecisions
        criteria
        joint
        findings
    )

validateLearned
  :: Ref.NativeArenaSpec
  -> Tape.ArenaTape
  -> Arena.RawNativeArenaEvaluation
  -> Either Text NativeArenaScoreCounts
validateLearned spec tape raw = do
  input <-
    maybe
      (Left "native arena comparison has no safely observed policy input")
      Right
      (Arena.nativeArenaEvaluationInput raw)
  Arena.validateNativeArenaEvaluationData spec tape (Arena.nativeArenaInputPolicy input) raw
  counts <- episodeCounts (Arena.nativeArenaEvaluationEpisodes raw)
  require
    (Arena.nativeArenaEvaluationExactScore raw == Just (nativeArenaCountsExactScore counts))
    "native arena complete learned score differs from actual outcomes"
  pure counts

learnedLegalRate :: Arena.RawNativeArenaEvaluation -> Either Text Double
learnedLegalRate raw = do
  let decisions = concatMap Ref.nativeArenaEpisodeDecisions (Arena.nativeArenaEvaluationEpisodes raw)
      count = length decisions
      legal =
        length
          ( filter
              ( \decision -> Ref.nativeArenaDecisionAction decision `elem` Ref.nativeArenaDecisionLegalActions decision
              )
              decisions
          )
  require
    (count > 0 && legal == count)
    "native arena canonical legal metric requires a nonempty complete legal decision inventory"
  pure (fromIntegral legal / fromIntegral count)

medianCriteria
  :: Thresholds.AlphaZeroGameConvergenceRow
  -> [NativeArenaSeedComparison]
  -> Either Text [Budget.ConvergenceObservation]
medianCriteria declaration comparisons = do
  let rows = map nativeArenaSeedComparisonLegacyCriteria comparisons
  require (all ((== 2) . length) rows) "native arena per-member legacy metric inventory differs"
  arena <- medianFive [Budget.coMetricValue value | [value, _] <- rows]
  legal <- medianFive [Budget.coMetricValue value | [_, value] <- rows]
  sequence
    [ Budget.remeasureCriterion arena (Thresholds.azgArenaWinRate declaration)
    , Budget.remeasureCriterion legal (Thresholds.azgLegalMoveRate declaration)
    ]

medianFive :: [Double] -> Either Text Double
medianFive values = do
  require (all finite values) "native arena median contains a nonfinite value"
  case sort values of
    [_, _, value, _, _] -> Right value
    _ -> Left "native arena median requires all five values"

referenceName :: Ref.NativeArenaReference -> Text
referenceName reference = case reference of
  Ref.PlainLegalUniform -> "plain-legal-uniform"
  Ref.NeutralLegalMcts -> "neutral-legal-mcts"

mapTape :: Either Tape.ArenaTapeError value -> Either Text value
mapTape result = case result of
  Left _ -> Left "native arena actual reference address differs from canonical tape"
  Right value -> Right value

sameDouble :: Double -> Double -> Bool
sameDouble left right = castDoubleToWord64 left == castDoubleToWord64 right
sameVector :: VU.Vector Double -> VU.Vector Double -> Bool
sameVector left right = VU.length left == VU.length right && VU.and (VU.zipWith sameDouble left right)
finite :: Double -> Bool
finite value = not (isNaN value || isInfinite value)
require :: Bool -> Text -> Either Text ()
require condition reason = unless condition (Left reason)
