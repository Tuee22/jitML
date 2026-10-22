-- | Exact actual addressed-arena DATA, including forced passes, failure
-- progress and the limited first/failed-forward summary. No search is run.
module JitML.Checkpoint.NativePhase.Projection.Arena (arenaEvaluation) where

import JitML.Checkpoint.NativePhase.Projection.Build
import JitML.Checkpoint.NativePhase.Projection.Cases
import JitML.Checkpoint.NativePhase.Projection.Evaluations
import JitML.Checkpoint.NativePhase.Projection.Values
import JitML.Checkpoint.NativePhase.Types
import JitML.Numerics.Mlp qualified as Mlp
import JitML.RL.AlphaZero qualified as Game
import JitML.RL.AlphaZero.ArenaTape qualified as Tape
import JitML.RL.AlphaZero.NativeArenaEvaluation qualified as Arena
import JitML.RL.AlphaZero.NativeArenaReferences qualified as Ref
import JitML.RL.AlphaZero.PolicyValueNet qualified as Net

arenaEvaluation :: Arena.RawNativeArenaEvaluation -> Build Digest
arenaEvaluation actual = do
  (input, fixed) <- case Arena.nativeArenaEvaluationInput actual of
    Nothing -> pure (VNull, Nothing)
    Just value -> do
      (root, params) <- arenaInput value
      pure (VRef root, Just params)
  episodes <-
    referenceSequence
      (RefElement NArenaEpisode)
      arenaEpisode
      (Arena.nativeArenaEvaluationEpisodes actual)
  progress <- optional arenaProgress (Arena.nativeArenaEvaluationProgress actual)
  forwards <- arenaSummary fixed (Arena.nativeArenaEvaluationForwards actual)
  status <- arenaStatus (Arena.nativeArenaEvaluationStatus actual)
  work <- arenaWork (Arena.nativeArenaEvaluationWork actual)
  emit NArenaEvaluation [input, VRef episodes, progress, VRef forwards, status, work]

arenaInput :: Arena.NativeArenaInput -> Build (Digest, (Mlp.MlpParams, Digest))
arenaInput actual = do
  let scope = VWord $ case Arena.nativeArenaInputScope actual of
        Arena.CanonicalNativeArena -> 0
        Arena.BoundedNativeArenaFixture -> 1
  spec <- optional arenaSpec (Arena.nativeArenaInputSpecification actual)
  state <- gameState (Arena.nativeArenaInputInitialState actual)
  tape <- arenaTape (Arena.nativeArenaInputTape actual)
  let actualPolicy = Arena.nativeArenaInputPolicy actual
  (policy, params) <- policyValueNetWithParameters actualPolicy
  root <- emit NArenaInput [scope, spec, VRef state, VRef tape, VRef policy]
  pure (root, (Net.pvnParams actualPolicy, params))

arenaSummary :: Maybe (Mlp.MlpParams, Digest) -> Arena.NativeArenaForwardSummary -> Build Digest
arenaSummary fixed actual = do
  calls <- integerValue (Arena.nativeArenaForwardCalls actual)
  firsts <-
    referenceSequence
      (RefElement NArenaForward)
      (arenaForward fixed)
      (Arena.nativeArenaFirstForwards actual)
  failed <- optional (arenaForward fixed) (Arena.nativeArenaFailedForward actual)
  emit NArenaSummary [calls, VRef firsts, failed]

arenaForward :: Maybe (Mlp.MlpParams, Digest) -> Arena.NativeArenaForwardObservation -> Build Digest
arenaForward fixed actual = do
  game <- intValue (Arena.nativeArenaForwardGame actual)
  slot <- intValue (Arena.nativeArenaForwardSlot actual)
  ordinal <- integerValue (Arena.nativeArenaForwardOrdinal actual)
  params <- parametersFor fixed (Arena.nativeArenaForwardParameters actual)
  input <- tensor (Arena.nativeArenaForwardInput actual)
  outcome <- case Arena.nativeArenaForwardOutcome actual of
    Arena.NativeArenaForwardReturned value -> returnedForward value
    Arena.NativeArenaForwardException detail -> exceptionForward detail
  emit NArenaForward [game, slot, ordinal, VRef params, VRef input, outcome]

arenaEpisode :: Ref.NativeArenaEpisode -> Build Digest
arenaEpisode actual = do
  identity <- intValue (Ref.nativeArenaEpisodeId actual)
  initial <- gameState (Ref.nativeArenaEpisodeInitialState actual)
  final <- gameState (Ref.nativeArenaEpisodeFinalState actual)
  rule <- gameOutcome (Ref.nativeArenaEpisodeRuleOutcome actual)
  scored <- gameOutcome (Ref.nativeArenaEpisodeScoredOutcome actual)
  decisions <-
    referenceSequence (RefElement NArenaDecision) arenaDecision (Ref.nativeArenaEpisodeDecisions actual)
  emit
    NArenaEpisode
    [ identity
    , VRef initial
    , VRef final
    , rule
    , scored
    , VBool (Ref.nativeArenaEpisodeHorizonTruncated actual)
    , VRef decisions
    ]

arenaProgress :: Arena.NativeArenaCaseProgress -> Build Digest
arenaProgress actual = do
  game <- intValue (Arena.nativeArenaProgressGame actual)
  transitions <- intValue (Arena.nativeArenaProgressTransitions actual)
  state <- gameState (Arena.nativeArenaProgressState actual)
  decisions <-
    referenceSequence
      (RefElement NArenaDecision)
      arenaDecision
      (Arena.nativeArenaProgressDecisions actual)
  emit NArenaProgress [game, transitions, VRef state, VRef decisions]

arenaDecision :: Ref.NativeArenaDecision -> Build Digest
arenaDecision actual = do
  slot <- intValue (Ref.nativeArenaDecisionSlot actual)
  raw <- gameState (Ref.nativeArenaDecisionRawState actual)
  normalized <- gameState (Ref.nativeArenaDecisionNormalizedState actual)
  player <- intValue (Ref.nativeArenaDecisionPlayer actual)
  legal <- scalarSequenceWith ScalarInt intValue (Ref.nativeArenaDecisionLegalActions actual)
  distribution <- tensor (Ref.nativeArenaDecisionDistribution actual)
  action <- intValue (Ref.nativeArenaDecisionAction actual)
  entry <- tapeEntry (Ref.nativeArenaDecisionTapeEntry actual)
  visits <- intValue (Ref.nativeArenaDecisionSearchRootVisits actual)
  post <- gameState (Ref.nativeArenaDecisionPostState actual)
  outcome <- gameOutcome (Ref.nativeArenaDecisionPostOutcome actual)
  emit
    NArenaDecision
    [ slot
    , VRef raw
    , VRef normalized
    , VBool (Ref.nativeArenaDecisionForcedPass actual)
    , player
    , VRef legal
    , VRef distribution
    , action
    , VRef entry
    , visits
    , VRef post
    , outcome
    ]

tapeEntry :: Tape.ArenaTapeEntry -> Build Digest
tapeEntry actual = do
  player <- intValue (Tape.arenaEntrySignedPlayer actual)
  seed <- intValue (Tape.arenaEntryMctsSeed actual)
  emit
    NTapeEntry
    [ VWord (Tape.arenaEntryGame actual)
    , VWord (Tape.arenaEntrySlot actual)
    , player
    , VWord (Tape.arenaEntrySideCode actual)
    , VWord (Tape.arenaEntryQ actual)
    , bitValue (Tape.arenaEntryUnit actual)
    , seed
    ]

gameOutcome :: Game.GameOutcome -> Build NodeValue
gameOutcome actual = case actual of
  Game.GameInProgress -> pure (VList [VWord 0])
  Game.GameDraw -> pure (VList [VWord 1])
  Game.GameWon player -> do
    observed <- intValue player
    pure (VList [VWord 2, observed])

arenaStatus :: Arena.NativeArenaEvaluationStatus -> Build NodeValue
arenaStatus actual = case actual of
  Arena.NativeArenaEvaluationComplete -> pure (VList [VWord 0])
  Arena.NativeArenaEvaluationRejected detail -> do
    text <- textValue DiagnosticTextBytes detail
    pure (VList [VWord 1, text])
  Arena.NativeArenaEvaluationFailed game slot kind detail -> do
    g <- intValue game
    s <- intValue slot
    text <- textValue DiagnosticTextBytes detail
    pure (VList [VWord 2, g, s, failureKind kind, text])

failureKind :: Arena.NativeArenaFailureKind -> NodeValue
failureKind actual = VWord $ case actual of
  Arena.NativeArenaInputException -> 0
  Arena.NativeArenaStateException -> 1
  Arena.NativeArenaSearchRejected -> 2
  Arena.NativeArenaSearchException -> 3
  Arena.NativeArenaSelectionRejected -> 4
  Arena.NativeArenaSelectionException -> 5
  Arena.NativeArenaTransitionException -> 6

arenaWork :: Arena.NativeArenaEvaluationWork -> Build NodeValue
arenaWork actual = do
  completed <- integerValue (Arena.nativeArenaCompletedEpisodeTransitions actual)
  current <- integerValue (Arena.nativeArenaCurrentEpisodeTransitions actual)
  visits <- integerValue (Arena.nativeArenaCompletedSearchRootVisits actual)
  let unfinished = VWord $ case Arena.nativeArenaUnfinishedSearch actual of
        Arena.NoUnfinishedArenaSearch -> 0
        Arena.UnknownUnfinishedArenaSearch -> 1
  pure (VList [completed, current, visits, unfinished])
