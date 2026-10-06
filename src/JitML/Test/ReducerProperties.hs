{-# LANGUAGE DataKinds #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Phase 281 — property tests for the contract reducers.
--
-- The event reducer must stay total and deterministic under reordering and
-- redelivery.  Each property below states one law in its comment and checks it
-- over generated event streams.  Generators are hand-written and valid by
-- construction (no discarded cases, no @quickcheck-instances@); sizes are
-- bounded so a run is fast and never flaky.
--
-- 'reducerPropertyTests' is registered in the @jitml-unit@ RunContract group.
-- 'reducerPropertySubset' is a small fixed-seed slice that the standing
-- @jitml-negative-controls@ stanza also runs, so the laws that make the
-- negative controls meaningful are pinned there deterministically.
module JitML.Test.ReducerProperties
  ( reducerPropertySubset
  , reducerPropertyTests
  )
where

import Control.Monad (foldM)
import Data.List.NonEmpty (NonEmpty (..))
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict qualified as Map
import Data.Maybe (mapMaybe)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Test.Tasty (TestTree, localOption, testGroup)
import Test.Tasty.QuickCheck
  ( Gen
  , Property
  , QuickCheckMaxSize (..)
  , QuickCheckReplay (..)
  , QuickCheckTests (..)
  , choose
  , conjoin
  , counterexample
  , elements
  , forAll
  , listOf1
  , shuffle
  , sublistOf
  , testProperty
  , (.&&.)
  , (===)
  )

import JitML.Plan.Plan
  ( PlanId
  , Validation (..)
  , planIdFromCanonicalText
  , planIdText
  )
import JitML.Plan.Workload
  ( AlphaZeroPlan
  , TuningPlan
  , alphaZeroPlanId
  , tuningPlanId
  )
import JitML.Proto.Rl qualified as Rl
import JitML.Proto.Tune qualified as Tune
import JitML.Run.Contract
  ( AtLeastOne
  , Contract
  , ContractViolation (..)
  , EvidenceEvent
  , ExactKeyed
  , ExactlyOne
  , MissingEvidence (..)
  , RequirementState
  , atLeastOne
  , atLeastOneValues
  , evidenceEvent
  , evidenceEventId
  , exactKeyedRange
  , exactKeyedValues
  , exactlyOne
  , finishContract
  , ingestEvent
  , initialProgress
  , productContract
  , selectContract
  )
import JitML.Run.WorkloadContract
  ( WorkloadContractViolation (..)
  , alphaZeroCompletionContract
  , ingestAlphaZeroEvent
  , ingestTuneEvent
  , tuningCompletionContract
  )
import JitML.Test.ControlFixtures
  ( alphaZeroArenaEvent
  , alphaZeroGenerationEvent
  , alphaZeroPlanFor
  , rlCompletedCheckpointFor
  , rlEvaluationEvent
  , rlMetricEvent
  , supervisedCompletedCheckpointFor
  , sweepCompletedEvent
  , sweepFinishedRecord
  , tuneTrialFinishedEvent
  , tuningPlanFor
  , tuningSeed
  )
import JitML.Test.LiveEvidence qualified as LiveEvidence
import JitML.Test.LiveWorkflow qualified as LiveWorkflow
import JitML.Training.Budget qualified as TrainingBudget

-- | Every reducer property.
reducerPropertyTests :: TestTree
reducerPropertyTests =
  testGroup
    "reducer properties"
    [ testGroup
        "keyed-exact contracts"
        [ permutationInvariance
        , permutationInvariantAtLeastOne
        , redeliveryIdempotent
        , conflictingDuplicateSameEventId
        , conflictingDuplicateSameKeyDifferentEventId
        , missingKeysAreTheAscendingDifference
        , wrongPlanRejectedByEveryContract
        ]
    , testGroup
        "product composition"
        [ productDiagnosticsLeftThenRight
        , nestedProductDiagnosticsInOrder
        ]
    , testGroup
        "workload contracts"
        [ tuningPermutationInvariant
        , alphaZeroPermutationInvariant
        , tuningWrongPlanRejected
        , alphaZeroWrongPlanRejected
        ]
    , testGroup
        "live reducers"
        [ rlWrongPlanTextRejected
        , liveCheckpointWrongPlanRejected
        ]
    , testGroup
        "completion join"
        [ joinCommutative
        , joinIdempotent
        , joinRejectsConflictingTerminals
        , joinRejectsConflictingEvidence
        ]
    ]

-- | A small, fast, fixed-seed slice of 'reducerPropertyTests' for the
-- negative-control stanza.  The seed pins the generated cases, so a failure
-- there is reproducible byte for byte.
reducerPropertySubset :: TestTree
reducerPropertySubset =
  localOption (QuickCheckReplayLegacy 281) $
    localOption (QuickCheckTests 40) $
      localOption (QuickCheckMaxSize 8) $
        testGroup
          "reducer properties (fixed-seed subset)"
          [ permutationInvariance
          , redeliveryIdempotent
          , conflictingDuplicateSameEventId
          , conflictingDuplicateSameKeyDifferentEventId
          , missingKeysAreTheAscendingDifference
          , wrongPlanRejectedByEveryContract
          , productDiagnosticsLeftThenRight
          , joinCommutative
          , joinRejectsConflictingTerminals
          ]

-- Generators -----------------------------------------------------------------

-- | Plan identities drawn from a fixed pool of distinct, valid ids.
planPool :: [PlanId]
planPool =
  [ planId
  | number <- [1 .. 6 :: Int]
  , Success planId <- [planIdFromCanonicalText (Text.pack ("reducer-property-plan-" <> show number))]
  ]

genPlanId :: Gen PlanId
genPlanId = elements planPool

-- | A plan id distinct from the given one.
genOtherPlan :: PlanId -> Gen PlanId
genOtherPlan planId = elements (filter (/= planId) planPool)

-- | A non-empty set of keys drawn from @[0 .. 15]@, so that some keys have two
-- digits and a lexicographic order would differ from the numeric one.
genKeys :: Gen [Int]
genKeys = Set.toAscList . Set.fromList <$> listOf1 (choose (0, 15))

-- | Values for a list of keys.
genValues :: [Int] -> Gen [(Int, Int)]
genValues = traverse (\key -> (,) key <$> choose (0, 99))

-- | One keyed event of the standard kind.
keyedEvent :: PlanId -> Int -> Int -> Maybe (EvidenceEvent Int Int)
keyedEvent planId key value =
  case evidenceEvent planId "observation" key value of
    Success built -> Just built
    Failure _ -> Nothing

keyedEvents :: PlanId -> [(Int, Int)] -> [EvidenceEvent Int Int]
keyedEvents planId = mapMaybe (uncurry (keyedEvent planId))

type KeyedContract =
  Contract
    (EvidenceEvent Int Int)
    (RequirementState Int Int)
    (ExactKeyed Int Int)

cohortContract :: PlanId -> [Int] -> Maybe KeyedContract
cohortContract planId keys =
  case keys of
    [] -> Nothing
    first : rest -> Just (exactKeyedRange "cohort" planId (first :| rest))

-- | Ingest events in order, stopping at the first rejection.
ingestAll
  :: Contract event progress evidence
  -> [event]
  -> Either ContractViolation progress
ingestAll contract = foldM (ingestEvent contract) (initialProgress contract)

-- | A property over a contract that is present for any non-empty key set.
withCohort :: PlanId -> [Int] -> (KeyedContract -> Property) -> Property
withCohort planId keys body =
  case cohortContract planId keys of
    Nothing -> counterexample "an empty key set produced no contract" (False === True)
    Just contract -> body contract

-- Keyed-exact contracts ---------------------------------------------------------

-- | Law: a keyed-exact contract does not depend on arrival order.  Every
-- permutation of the events for its expected keys is accepted and yields the
-- same requirement state and the same completion.
permutationInvariance :: TestTree
permutationInvariance =
  testProperty "exact-keyed contract is permutation-invariant" $
    forAll genPlanId $ \planId ->
      forAll genKeys $ \keys ->
        forAll (genValues keys) $ \assignments ->
          forAll (shuffle (keyedEvents planId assignments)) $ \permuted ->
            withCohort planId keys $ \contract ->
              let ordered = keyedEvents planId assignments
                  expectedValues = Map.fromList assignments
               in ingestAll contract permuted
                    === ingestAll contract ordered
                    .&&. fmap (finishContract contract) (ingestAll contract permuted)
                    === fmap (finishContract contract) (ingestAll contract ordered)
                    .&&. fmap (fmap exactKeyedValues . finishContract contract) (ingestAll contract permuted)
                    === Right (Success expectedValues)

-- | Law: an at-least-one contract completes with the recorded pairs in
-- ascending key order whatever the arrival order.
permutationInvariantAtLeastOne :: TestTree
permutationInvariantAtLeastOne =
  testProperty "at-least-one contract completes in ascending key order under any arrival order" $
    forAll genPlanId $ \planId ->
      forAll genKeys $ \keys ->
        forAll (genValues keys) $ \assignments ->
          forAll (shuffle (keyedEvents planId assignments)) $ \permuted ->
            let contract = atLeastOne "telemetry" planId :: AtLeastOneKeyed
                finished =
                  fmap
                    (fmap (NonEmpty.toList . atLeastOneValues) . finishContract contract)
                    (ingestAll contract permuted)
             in finished === Right (Success (Map.toAscList (Map.fromList assignments)))

type AtLeastOneKeyed =
  Contract
    (EvidenceEvent Int Int)
    (RequirementState Int Int)
    (AtLeastOne Int Int)

-- | Law: redelivering an identical event at any later position is idempotent.
-- Inserting a copy of an already-ingested event anywhere after it leaves every
-- step accepted and the final state unchanged.
redeliveryIdempotent :: TestTree
redeliveryIdempotent =
  testProperty "identical redelivery is idempotent at any position" $
    forAll genPlanId $ \planId ->
      forAll genKeys $ \keys ->
        forAll (genValues keys) $ \assignments ->
          let events = keyedEvents planId assignments
           in forAll (choose (1, length events)) $ \position ->
                forAll (choose (0, position - 1)) $ \earlier ->
                  withCohort planId keys $ \contract ->
                    let redelivered =
                          take position events
                            <> take 1 (drop earlier events)
                            <> drop position events
                     in ingestAll contract redelivered === ingestAll contract events

-- | Law: the same 'EventId' carrying a different value is rejected with a
-- 'ConflictingDuplicate' naming that id twice, deterministically, and the
-- rejection leaves the recorded progress usable: the caller's progress is
-- untouched, so an identical redelivery of the recorded event is still
-- accepted from it.
conflictingDuplicateSameEventId :: TestTree
conflictingDuplicateSameEventId =
  testProperty "same EventId with a different value is rejected deterministically and preserves state" $
    forAll genPlanId $ \planId ->
      forAll genKeys $ \keys ->
        forAll (elements keys) $ \key ->
          forAll (choose (0, 99)) $ \value ->
            forAll (choose (1, 99)) $ \delta ->
              withCohort planId keys $ \contract ->
                case (keyedEvent planId key value, keyedEvent planId key (value + delta)) of
                  (Just original, Just conflicting) ->
                    let recorded = ingestAll contract [original]
                        violation =
                          ConflictingDuplicate
                            "cohort"
                            (Text.pack (show key))
                            (evidenceEventId original)
                            (evidenceEventId original)
                        attempt = recorded >>= \progress -> ingestEvent contract progress conflicting
                        again = recorded >>= \progress -> ingestEvent contract progress conflicting
                        redelivery = recorded >>= \progress -> ingestEvent contract progress original
                     in attempt
                          === Left violation
                          .&&. again
                          === attempt
                          .&&. redelivery
                          === recorded
                  _ -> counterexample "an event failed to build" (False === True)

-- | Law: a second 'EventId' for an already-populated key is rejected, even with
-- an equal value, and the violation's existing/incoming roles follow arrival
-- order: swapping which event arrives first swaps the roles.
conflictingDuplicateSameKeyDifferentEventId :: TestTree
conflictingDuplicateSameKeyDifferentEventId =
  testProperty "same key with a different EventId is rejected and its roles follow arrival order" $
    forAll genPlanId $ \planId ->
      forAll genKeys $ \keys ->
        forAll (elements keys) $ \key ->
          forAll (choose (0, 99)) $ \first' ->
            forAll (choose (0, 99)) $ \second ->
              withCohort planId keys $ \contract ->
                case (kindedEvent planId "kind-a" key first', kindedEvent planId "kind-b" key second) of
                  (Just left, Just right) ->
                    let rejects arrivalFirst arrivalSecond =
                          ingestAll contract [arrivalFirst]
                            >>= \progress -> ingestEvent contract progress arrivalSecond
                        violation existing incoming =
                          ConflictingDuplicate
                            "cohort"
                            (Text.pack (show key))
                            (evidenceEventId existing)
                            (evidenceEventId incoming)
                     in rejects left right
                          === Left (violation left right)
                          .&&. rejects right left
                          === Left (violation right left)
                  _ -> counterexample "an event failed to build" (False === True)

kindedEvent :: PlanId -> Text -> Int -> Int -> Maybe (EvidenceEvent Int Int)
kindedEvent planId kind key value =
  case evidenceEvent planId kind key value of
    Success built -> Just built
    Failure _ -> Nothing

-- | Law: completion reports exactly the missing keys, as the ascending
-- difference between the expected range and what arrived, in numeric (not
-- lexicographic) order; when nothing is missing it completes with exactly the
-- arrived values.
missingKeysAreTheAscendingDifference :: TestTree
missingKeysAreTheAscendingDifference =
  testProperty "missing keys are the exact ascending difference" $
    forAll genPlanId $ \planId ->
      forAll genKeys $ \keys ->
        forAll (sublistOf keys) $ \arrived ->
          forAll (genValues arrived) $ \assignments ->
            forAll (shuffle (keyedEvents planId assignments)) $ \permuted ->
              withCohort planId keys $ \contract ->
                let missing = Set.toAscList (Set.fromList keys `Set.difference` Set.fromList arrived)
                    expected =
                      case missing of
                        [] -> Right (Success (Map.fromList assignments))
                        first : rest ->
                          Right
                            ( Failure
                                ( MissingKeys
                                    "cohort"
                                    (fmap (Text.pack . show) (first :| rest))
                                    :| []
                                )
                            )
                 in fmap (fmap exactKeyedValues . finishContract contract) (ingestAll contract permuted)
                      === expected

-- | Law: an event stamped with any other plan is rejected on arrival by every
-- cardinality combinator, whatever progress has been recorded, and the
-- violation names the expected and the observed plan.
wrongPlanRejectedByEveryContract :: TestTree
wrongPlanRejectedByEveryContract =
  testProperty "a wrong-plan event is rejected by every contract at any progress" $
    forAll genPlanId $ \planId ->
      forAll (genOtherPlan planId) $ \otherPlan ->
        forAll genKeys $ \keys ->
          forAll (genValues keys) $ \assignments ->
            forAll (choose (0, length assignments)) $ \prefixLength ->
              forAll (elements keys) $ \key ->
                forAll (choose (0, 99)) $ \value ->
                  withCohort planId keys $ \contract ->
                    case (keyedEvent otherPlan key value, evidenceEvent otherPlan "single" () value) of
                      (Just foreignEvent, Success foreignSingle) ->
                        let prefix = take prefixLength (keyedEvents planId assignments)
                            single = exactlyOne "single" planId :: ExactlyOneInt
                            telemetry = atLeastOne "telemetry" planId :: AtLeastOneKeyed
                            wrongPlan label = WrongPlan label planId otherPlan
                         in conjoin
                              [ (ingestAll contract prefix >>= \progress -> ingestEvent contract progress foreignEvent)
                                  === Left (wrongPlan "cohort")
                              , ingestEvent single (initialProgress single) foreignSingle
                                  === Left (wrongPlan "single")
                              , ingestEvent telemetry (initialProgress telemetry) foreignEvent
                                  === Left (wrongPlan "telemetry")
                              ]
                      _ -> counterexample "an event failed to build" (False === True)

type ExactlyOneInt =
  Contract
    (EvidenceEvent () Int)
    (RequirementState () Int)
    (ExactlyOne Int)

-- Product composition -----------------------------------------------------------

-- | Events for the two arms of a product.
data Arm
  = LeftArm (EvidenceEvent Int Int)
  | RightArm (EvidenceEvent () Int)
  | MiddleArm (EvidenceEvent () Int)
  deriving stock (Eq, Show)

armContracts
  :: PlanId
  -> NonEmpty Int
  -> Contract
       Arm
       ( ( RequirementState Int Int
         , RequirementState () Int
         )
       , RequirementState () Int
       )
       ( (ExactKeyed Int Int, ExactlyOne Int)
       , ExactlyOne Int
       )
armContracts planId keys =
  productContract
    ( productContract
        ( selectContract
            (\case LeftArm event' -> Just event'; _ -> Nothing)
            (exactKeyedRange "left" planId keys)
        )
        ( selectContract
            (\case MiddleArm event' -> Just event'; _ -> Nothing)
            (exactlyOne "middle" planId)
        )
    )
    ( selectContract
        (\case RightArm event' -> Just event'; _ -> Nothing)
        (exactlyOne "right" planId)
    )

-- | Law: a product of requirements reports the missing evidence of the left
-- requirement, then the right one, in that order, and only what is missing.
productDiagnosticsLeftThenRight :: TestTree
productDiagnosticsLeftThenRight =
  testProperty "product diagnostics accumulate left then right" $
    forAll genPlanId $ \planId ->
      forAll genKeys $ \keys ->
        forAll (sublistOf keys) $ \arrived ->
          forAll (elements [False, True]) $ \middlePresent ->
            forAll (elements [False, True]) $ \rightPresent ->
              case keys of
                first : rest ->
                  let contract = armContracts planId (first :| rest)
                      leftEvents = LeftArm <$> keyedEvents planId [(key, key) | key <- arrived]
                      middleEvents =
                        [MiddleArm built | middlePresent, Success built <- [evidenceEvent planId "middle" () 1]]
                      rightEvents =
                        [RightArm built | rightPresent, Success built <- [evidenceEvent planId "right" () 2]]
                      missingKeys = Set.toAscList (Set.fromList keys `Set.difference` Set.fromList arrived)
                      expectedMissing =
                        [ MissingKeys "left" (fmap (Text.pack . show) (k :| ks))
                        | k : ks <- [missingKeys]
                        ]
                          <> [MissingExactlyOne "middle" | not middlePresent]
                          <> [MissingExactlyOne "right" | not rightPresent]
                   in forAll (shuffle (leftEvents <> middleEvents <> rightEvents)) $ \stream ->
                        fmap (isFailureWith expectedMissing . finishContract contract) (ingestAll contract stream)
                          === Right True
                [] -> counterexample "an empty key set" (False === True)
 where
  isFailureWith expected result =
    case (result, expected) of
      (Success _, []) -> True
      (Failure missing, _ : _) -> NonEmpty.toList missing == expected
      _ -> False

-- | Law: composing products keeps every arm's diagnostics in arrival-independent
-- left-to-right order, so nesting does not reorder them.
nestedProductDiagnosticsInOrder :: TestTree
nestedProductDiagnosticsInOrder =
  testProperty "an empty nested product reports every arm in order" $
    forAll genPlanId $ \planId ->
      forAll genKeys $ \case
        first : rest ->
          let contract = armContracts planId (first :| rest)
              missingKeys = fmap (Text.pack . show) (first :| rest)
           in case finishContract contract (initialProgress contract) of
                Failure missing ->
                  NonEmpty.toList missing
                    === [MissingKeys "left" missingKeys, MissingExactlyOne "middle", MissingExactlyOne "right"]
                Success _ -> counterexample "an empty product completed" (False === True)
        [] -> counterexample "an empty key set" (False === True)

-- Workload contracts --------------------------------------------------------------

-- | A tuning plan of @trials@ trials.
withTuningPlan :: Integer -> (TuningPlan -> Property) -> Property
withTuningPlan trials body =
  case tuningPlanFor "reducer-property-tuning" trials of
    Right plan -> body plan
    Left err -> counterexample (Text.unpack err) (False === True)

withAlphaZeroPlan :: Integer -> (AlphaZeroPlan -> Property) -> Property
withAlphaZeroPlan generations body =
  case alphaZeroPlanFor "reducer-property-alphazero" generations of
    Right plan -> body plan
    Left err -> counterexample (Text.unpack err) (False === True)

-- | Law: the tuning completion contract is permutation-invariant over its
-- trial results and its sweep terminal.
tuningPermutationInvariant :: TestTree
tuningPermutationInvariant =
  testProperty "tuning completion is permutation-invariant" $
    forAll (choose (1, 6)) $ \trials ->
      forAll (traverse (const (choose (0, 9 :: Int))) [1 .. trials :: Int]) $ \objectives ->
        withTuningPlan (fromIntegral trials) $ \plan ->
          case sweepCompletedEvent
            (sweepFinishedRecord plan (fromIntegral trials) 1 0.25)
            (tuningPlanId plan)
            TrainingBudget.TuningTrialBudget
            (fromIntegral trials)
            (tuningSeed plan) of
            Left err -> counterexample (Text.unpack err) (False === True)
            Right sweep ->
              let events =
                    [ tuneTrialFinishedEvent plan (fromIntegral index) (fromIntegral objective)
                    | (index, objective) <- zip [0 :: Int ..] objectives
                    ]
                      <> [sweep]
                  contract = tuningCompletionContract plan
                  run = foldM (ingestTuneEvent plan) (initialProgress contract)
               in forAll (shuffle events) $ \permuted ->
                    fmap (finishContract contract) (run permuted)
                      === fmap (finishContract contract) (run events)
                      .&&. fmap (isSuccess . finishContract contract) (run permuted)
                      === Right True

-- | Law: the AlphaZero completion contract is permutation-invariant over its
-- generations and its arena terminal.
alphaZeroPermutationInvariant :: TestTree
alphaZeroPermutationInvariant =
  testProperty "AlphaZero completion is permutation-invariant" $
    forAll (choose (1, 6)) $ \generations ->
      withAlphaZeroPlan (fromIntegral generations) $ \plan ->
        let events =
              [ alphaZeroGenerationEvent plan (fromIntegral index) 4 (1000 + fromIntegral index)
              | index <- [0 .. generations - 1 :: Int]
              ]
                <> [alphaZeroArenaEvent plan 6 0.75]
            contract = alphaZeroCompletionContract plan
            run = foldM (ingestAlphaZeroEvent plan) (initialProgress contract)
         in forAll (shuffle events) $ \permuted ->
              fmap (finishContract contract) (run permuted)
                === fmap (finishContract contract) (run events)
                .&&. fmap (isSuccess . finishContract contract) (run permuted)
                === Right True

-- | Law: a tuning event stamped with any other plan text is rejected by the
-- workload correlation before it reaches the shared algebra.
tuningWrongPlanRejected :: TestTree
tuningWrongPlanRejected =
  testProperty "a wrong-plan tuning event is rejected with the observed plan" $
    forAll genWrongPlanText $ \wrong ->
      withTuningPlan 3 $ \plan ->
        let event' =
              case tuneTrialFinishedEvent plan 0 1.0 of
                Tune.TuneTrialFinished finished -> Tune.TuneTrialFinished finished {Tune.tfTunePlanId = wrong}
                other -> other
         in ingestTuneEvent plan (initialProgress (tuningCompletionContract plan)) event'
              === Left
                ( WorkloadEventPlanMismatch
                    "tuning-trial-finished"
                    (planIdText (tuningPlanId plan))
                    wrong
                )

-- | Law: the same for an AlphaZero generation.
alphaZeroWrongPlanRejected :: TestTree
alphaZeroWrongPlanRejected =
  testProperty "a wrong-plan AlphaZero event is rejected with the observed plan" $
    forAll genWrongPlanText $ \wrong ->
      withAlphaZeroPlan 3 $ \plan ->
        let event' =
              case alphaZeroGenerationEvent plan 0 4 1000 of
                Rl.RlGenerationCompleted done -> Rl.RlGenerationCompleted done {Rl.gcPlanId = wrong}
                other -> other
         in ingestAlphaZeroEvent plan (initialProgress (alphaZeroCompletionContract plan)) event'
              === Left
                ( WorkloadEventPlanMismatch
                    "alphazero-generation-completed"
                    (planIdText (alphaZeroPlanId plan))
                    wrong
                )

-- | A short lowercase word: never a 64-character plan digest, so never the
-- plan's own identity.
genWrongPlanText :: Gen Text
genWrongPlanText = Text.pack <$> listOf1 (elements ['a' .. 'z'])

isSuccess :: Validation missing evidence -> Bool
isSuccess = \case
  Success _ -> True
  Failure _ -> False

-- Live reducers ------------------------------------------------------------------

liveExperiment :: Text
liveExperiment = "reducer-property-live"

-- | Law: an RL evaluation outcome or median metric stamped with any other plan
-- text is rejected on arrival, naming the expected and the observed plan.
rlWrongPlanTextRejected :: TestTree
rlWrongPlanTextRejected =
  testProperty "a wrong-plan RL evaluation or metric is rejected with the observed plan text" $
    forAll genPlanId $ \planId ->
      forAll genWrongPlanText $ \wrong ->
        forAll (choose (1, 6)) $ \episodes ->
          case LiveEvidence.rlLiveContract planId episodes of
            Left violation -> counterexample (show violation) (False === True)
            Right contract ->
              let ingest = LiveEvidence.ingestRlLiveEvent planId liveExperiment contract
                  progress = initialProgress contract
                  mismatch = LiveEvidence.LiveEvidenceRlPlanMismatch (planIdText planId) wrong
               in ingest progress (rlEvaluationEvent wrong liveExperiment 0 1.0 4)
                    === Left mismatch
                    .&&. ingest progress (rlMetricEvent wrong liveExperiment 1.0)
                    === Left mismatch

-- | Law: a completed checkpoint proven under any other plan is rejected by the
-- supervised and RL live reducers, naming the expected and the observed plan.
liveCheckpointWrongPlanRejected :: TestTree
liveCheckpointWrongPlanRejected =
  testProperty "a completed checkpoint of another plan is rejected by the live reducers" $
    forAll genPlanId $ \planId ->
      forAll (genOtherPlan planId) $ \other ->
        forAll (choose (1, 6)) $ \units ->
          case ( LiveEvidence.supervisedLiveContract planId 3
               , LiveEvidence.rlLiveContract planId 2
               , supervisedCompletedCheckpointFor
                   other
                   TrainingBudget.SupervisedEpochBudget
                   units
                   liveExperiment
               , rlCompletedCheckpointFor
                   other
                   TrainingBudget.RlEnvironmentStepBudget
                   units
                   liveExperiment
               ) of
            (Right supervised, Right rl, Right supervisedEvent, Right rlEvent) ->
              LiveEvidence.ingestSupervisedLiveEvent
                planId
                liveExperiment
                supervised
                (initialProgress supervised)
                supervisedEvent
                === Left (LiveEvidence.LiveEvidencePlanMismatch planId other)
                .&&. LiveEvidence.ingestRlLiveEvent
                  planId
                  liveExperiment
                  rl
                  (initialProgress rl)
                  rlEvent
                === Left (LiveEvidence.LiveEvidencePlanMismatch planId other)
            _ -> counterexample "a live-reducer fixture failed to build" (False === True)

-- Completion join ------------------------------------------------------------------

-- | An observation fed to the terminal/evidence join.
data JoinFact
  = TerminalFact Text
  | EvidenceFact Text
  deriving stock (Eq, Show)

type Join = LiveWorkflow.CompletionJoin Text Text

applyFact
  :: Join
  -> JoinFact
  -> Either LiveWorkflow.CompletionJoinError Join
applyFact state = \case
  TerminalFact terminal -> LiveWorkflow.completionJoinTerminal terminal state
  EvidenceFact evidence -> LiveWorkflow.completionJoinEvidence evidence state

runFacts :: [JoinFact] -> Either LiveWorkflow.CompletionJoinError Join
runFacts = foldM applyFact LiveWorkflow.emptyCompletionJoin

-- | A stream of consistent facts: one terminal value and one evidence value,
-- each observed one to three times, in any order.
genConsistentFacts :: Gen [JoinFact]
genConsistentFacts = do
  terminal <- elements ["job-succeeded", "job-a"]
  evidence <- elements ["proof-a", "proof-b"]
  terminals <- choose (1, 3)
  evidences <- choose (1, 3)
  shuffle
    ( replicate terminals (TerminalFact terminal)
        <> replicate evidences (EvidenceFact evidence)
    )

-- | Law: the join of consistent facts is commutative: every arrival order
-- yields the same joined completion.
joinCommutative :: TestTree
joinCommutative =
  testProperty "terminal and evidence join is commutative" $
    forAll genConsistentFacts $ \facts ->
      forAll (shuffle facts) $ \permuted ->
        runFacts permuted
          === runFacts facts
          .&&. fmap LiveWorkflow.joinedCompletion (runFacts permuted)
          === Right (expectedPair facts)
 where
  expectedPair facts =
    case ([terminal | TerminalFact terminal <- facts], [evidence | EvidenceFact evidence <- facts]) of
      (terminal : _, evidence : _) -> Just (terminal, evidence)
      _ -> Nothing

-- | Law: redelivering a fact any number of times, at any position, does not
-- change the join.
joinIdempotent :: TestTree
joinIdempotent =
  testProperty "terminal and evidence join is idempotent under redelivery" $
    forAll genConsistentFacts $ \facts ->
      forAll (choose (0, length facts)) $ \position ->
        forAll (choose (0, length facts - 1)) $ \earlier ->
          let redelivered = take position facts <> take 1 (drop earlier facts) <> drop position facts
           in fmap LiveWorkflow.joinedCompletion (runFacts redelivered)
                === fmap LiveWorkflow.joinedCompletion (runFacts facts)

-- | Law: two different terminal observations are rejected as conflicting
-- terminals in every arrival order, however the consistent evidence is
-- interleaved.
joinRejectsConflictingTerminals :: TestTree
joinRejectsConflictingTerminals =
  testProperty "conflicting terminal observations are rejected in every arrival order" $
    forAll (elements [0, 1, 2]) $ \evidenceCopies ->
      forAll
        ( shuffle
            ( [TerminalFact "job-a", TerminalFact "job-b"]
                <> replicate evidenceCopies (EvidenceFact "proof-a")
            )
        )
        $ \facts ->
          runFacts facts === Left LiveWorkflow.ConflictingTerminalObservation

-- | Law: two different pieces of completed evidence are rejected as
-- conflicting evidence in every arrival order.
joinRejectsConflictingEvidence :: TestTree
joinRejectsConflictingEvidence =
  testProperty "conflicting completed evidence is rejected in every arrival order" $
    forAll (elements [0, 1, 2]) $ \terminalCopies ->
      forAll
        ( shuffle
            ( [EvidenceFact "proof-a", EvidenceFact "proof-b"]
                <> replicate terminalCopies (TerminalFact "job-a")
            )
        )
        $ \facts ->
          runFacts facts === Left LiveWorkflow.ConflictingCompletedEvidence
