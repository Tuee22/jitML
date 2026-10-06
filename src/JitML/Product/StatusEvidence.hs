{-# LANGUAGE OverloadedStrings #-}

-- | Phase 288 - the pure model behind the journal-derived status registry.
--
-- Sprint status is a /projection/ over versioned validation evidence and
-- explicit obligations, not a literal. This module holds everything that needs
-- no I/O: the closed sums that say what is required ('Obligation') and why it is
-- not yet satisfied ('Unmet'), the catalogue types, the status relation, and the
-- 'ClosureVerdict' that closure-claim guards consume. Reading committed files is
-- the job of "JitML.Product.StatusLoader"; the catalogue data lives in
-- "JitML.Product.PhaseStatus".
--
-- = The status relation
--
-- For a sprint whose closure is 'Evidenced':
--
-- * __Done__ iff every obligation is 'Proven' and every upstream sprint is Done;
-- * __Blocked__ iff an upstream sprint is not Done, or an external prerequisite
--   is open and the sprint has not started;
-- * __Active__ iff the sprint is declared 'Started', is not blocked by an
--   upstream sprint, and still has an unproven obligation;
-- * __Planned__ otherwise (declared 'NotStarted', unblocked, work remaining).
--
-- 'Started' versus 'NotStarted' is the one fact a person declares, because
-- whether work has begun is not derivable from evidence. It can never mint
-- Done: with any obligation unproven the sprint is not Done whatever it
-- declares, and an unproven upstream sprint blocks it whatever it declares. An
-- open external obligation blocks a sprint that has not started, but a started
-- sprint stays Active with it listed as remaining work.
--
-- A missing transcript, journal, or aggregate is 'Unproven', never Done.
--
-- Lane journals, the aggregate, and standing gates are re-read on every
-- projection, so a sprint that owns one stops being Done when that evidence goes
-- stale (a contract change, a re-pinned journal, an edit to the code a standing
-- transcript ran against): the audit finding defines status, and the sprint's
-- document must follow. A 'GateTranscript' is different: it records that a gate
-- passed once, is never compared with the current tree, and so cannot demote a
-- sprint because later work moved the code.
--
-- = Legacy attestation
--
-- Sprints closed before machine evidence existed cannot be re-proven. They are
-- represented by an explicit, frozen, shrink-only 'LegacyAttested' class that
-- names the section of the phase document that records the closure. It satisfies
-- the status relation for those sprints and nothing else: it can never be used to
-- mint a new Done, it is disclosed by every 'Closed' verdict, and a guard rejects
-- any entry that is not in the frozen set (see "JitML.Product.PhaseStatus").
--
-- = Computed, never attested
--
-- @jitml docs check@ and @jitml check-code@ results are not obligations. They are
-- computed by running them against the tree being evaluated; a file recording
-- that they passed would sit inside the tree they check and could never be both
-- current and committed.
module JitML.Product.StatusEvidence
  ( -- * Sprint identity and status
    SprintId
  , SprintStatus (..)
  , compareSprintId
  , parseSprintStatus
  , renderSprintStatus
  , sprintPhaseNumber

    -- * Obligations, proof, and unmet reasons
  , Derived (..)
  , EvidenceRef (..)
  , Obligation (..)
  , Unmet (..)
  , renderObligation
  , renderUnmet

    -- * What a loader observed
  , EvidenceIndex (..)
  , TranscriptEvidence (..)
  , emptyEvidenceIndex
  , observeObligation
  , pendingControlOwner

    -- * The catalogue
  , Closure (..)
  , LegacyCitation (..)
  , PhaseEntry (..)
  , SprintEntry (..)
  , WorkState (..)
  , catalogueSprints
  , evidencedSprint
  , isLegacyClosure
  , legacyAttested
  , validateCatalogue

    -- * Projection
  , Basis (..)
  , ClosureVerdict
  , Refusal (..)
  , Scope (..)
  , SprintProjection (..)
  , StatusCounts (..)
  , StatusReport
  , closureOutcome
  , closureVerdictSummary
  , openChain
  , projectStatusReport
  , projectionOpen
  , renderRefusal
  , renderStatusCounts
  , renderStatusReport
  , reportLegacy
  , reportProjections
  , reportStanding
  , reportVerdict
  , statusCounts
  )
where

import Data.Char (isDigit)
import Data.List (sortBy)
import Data.List qualified as List
import Data.List.NonEmpty (NonEmpty (..))
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Ord (comparing)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Text.Read (readMaybe)

import JitML.Product.SourceDigest (SourceStamp (..))
import JitML.Product.ValidationRecord (ValidationGate, renderValidationGate)
import JitML.Substrate (Substrate, renderSubstrate)

-- ---------------------------------------------------------------------------
-- Sprint identity and status
-- ---------------------------------------------------------------------------

-- | A sprint identifier such as @278.1@.
type SprintId = Text

data SprintStatus
  = Done
  | Active
  | Planned
  | Blocked
  deriving stock (Eq, Ord, Show)

renderSprintStatus :: SprintStatus -> Text
renderSprintStatus Done = "Done"
renderSprintStatus Active = "Active"
renderSprintStatus Planned = "Planned"
renderSprintStatus Blocked = "Blocked"

parseSprintStatus :: Text -> Maybe SprintStatus
parseSprintStatus value =
  case Text.strip value of
    "Done" -> Just Done
    "Active" -> Just Active
    "Planned" -> Just Planned
    "Blocked" -> Just Blocked
    _ -> Nothing

-- | The phase number of a sprint id: @278.1@ belongs to phase @278@.
sprintPhaseNumber :: SprintId -> Maybe Int
sprintPhaseNumber sprint =
  case Text.splitOn "." sprint of
    [phase, minor]
      | Just number <- digitsToInt phase
      , Just _ <- digitsToInt minor ->
          Just number
    _ -> Nothing

digitsToInt :: Text -> Maybe Int
digitsToInt digits
  | not (Text.null digits) && Text.all isDigit digits = readMaybe (Text.unpack digits)
  | otherwise = Nothing

-- | Numeric, component-wise order (@23.2 < 24.1@, @9.1 < 10.1@). Ids that are
-- not dotted numbers still order deterministically, after their numeric prefix,
-- by their text; the catalogue validator rejects them.
compareSprintId :: SprintId -> SprintId -> Ordering
compareSprintId = comparing sprintKey

sprintKey :: SprintId -> ([Int], Text)
sprintKey sprint = (mapMaybe digitsToInt (Text.splitOn "." sprint), sprint)

-- ---------------------------------------------------------------------------
-- Obligations, proof, and unmet reasons
-- ---------------------------------------------------------------------------

-- | Something a sprint owns that a machine can observe.
data Obligation
  = -- | A committed transcript of the gate's standing invocation on the substrate,
    -- recording a pass. Historical: it is not compared with the current tree. For
    -- a gate that proves live-only code (the end-to-end stanza) the pass must also
    -- have been a @--live@ run.
    GateTranscript !ValidationGate !Substrate
  | -- | The same, but the transcript's source stamp must equal the stamp of the
    -- tree being evaluated. Standing gates are evaluated only for the closure
    -- verdict, because a per-sprint Done must not evaporate when a later sprint
    -- edits code.
    StandingGate !ValidationGate !Substrate
  | -- | The pinned lane journal admits under the current contract.
    LaneJournal !Substrate
  | -- | The retained three-lane aggregate is the current projection of the pinned
    -- lane journals.
    Aggregate
  | -- | No pending production-path negative control is owned by this phase.
    NoPendingControls !Int
  | -- | The legacy ledger has no Pending Removal row.
    LedgerClear
  | -- | A prerequisite outside the repository's machine reach, for example
    -- hardware or a host. It is always open while it is declared; the only way to
    -- clear one is to delete it from the catalogue in a change that replaces it
    -- with machine-observable obligations.
    ExternalContext !Text
  | -- | A declared dependency edge, expanded by the projection from the sprint's
    -- upstream list. It is not written in a catalogue obligation list.
    UpstreamSprint !SprintId
  deriving stock (Eq, Ord, Show)

-- | Why one obligation is not proven. Closed, so every consumer decides each
-- case.
data Unmet
  = -- | The evidence artifact is absent. Names the expected file.
    Missing !Text
  | -- | Well-formed evidence bound to another version than the current one:
    -- subject, the digest the current tree requires, and the digest the evidence
    -- carries.
    Stale !Text !Text !Text
  | -- | Evidence that attests another subject than the obligation names, or
    -- violates its own structure: wrong gate, substrate, or command, a pin that
    -- differs from the retained bytes, malformed or non-canonical bytes.
    Mismatched !Text
  | -- | Evidence that records a run which failed.
    FailedRun !Text
  | -- | Evidence that covers less than the obligation requires: a run that never
    -- ran, a passing non-live run where a live one is required, missing lanes or
    -- rows, controls still pending.
    Incomplete !Text
  | -- | An upstream sprint that must be Done first is not.
    AwaitsSprint !SprintId
  | -- | An external prerequisite is open.
    External !Text
  deriving stock (Eq, Ord, Show)

-- | A pointer to what proved an obligation: a committed file or code-resident
-- source, and the digest of the bytes that were admitted where one exists.
data EvidenceRef = EvidenceRef
  { evidenceSubject :: !Text
  , evidenceDigest :: !(Maybe Text)
  }
  deriving stock (Eq, Ord, Show)

data Derived
  = Proven !(NonEmpty EvidenceRef)
  | Unproven !(NonEmpty Unmet)
  deriving stock (Eq, Show)

renderObligation :: Obligation -> Text
renderObligation obligation =
  case obligation of
    GateTranscript gate substrate ->
      "gate-transcript " <> renderValidationGate gate <> " " <> renderSubstrate substrate
    StandingGate gate substrate ->
      "standing-gate " <> renderValidationGate gate <> " " <> renderSubstrate substrate
    LaneJournal substrate -> "lane-journal " <> renderSubstrate substrate
    Aggregate -> "product-aggregate"
    NoPendingControls phase -> "no-pending-controls phase " <> tshow phase
    LedgerClear -> "pending-removal-ledger-clear"
    ExternalContext _ -> "external-context"
    UpstreamSprint sprint -> "upstream-sprint " <> sprint

renderUnmet :: Unmet -> Text
renderUnmet unmet =
  case unmet of
    Missing what -> "missing: " <> what
    Stale subject expected actual ->
      "stale: " <> subject <> " expected " <> expected <> " but evidence carries " <> actual
    Mismatched detail -> "mismatched: " <> detail
    FailedRun detail -> "failed run: " <> detail
    Incomplete detail -> "incomplete: " <> detail
    AwaitsSprint sprint -> "awaits sprint " <> sprint
    External description -> "external: " <> description

-- ---------------------------------------------------------------------------
-- What a loader observed
-- ---------------------------------------------------------------------------

-- | The judgement of one transcript file plus the source stamp its record
-- carried, when a record was admitted.
data TranscriptEvidence = TranscriptEvidence
  { transcriptJudgement :: !Derived
  , transcriptSource :: !(Maybe SourceStamp)
  }
  deriving stock (Eq, Show)

-- | Everything the projection reads, already reduced by the loader. Building an
-- index by hand is how fixtures drive every case without touching a file.
data EvidenceIndex = EvidenceIndex
  { indexLanes :: !(Map Substrate Derived)
  , indexAggregate :: !(Maybe Derived)
  , indexTranscripts :: !(Map (ValidationGate, Substrate) TranscriptEvidence)
  , indexCurrentSource :: !(Either Text SourceStamp)
  , indexPendingControls :: !(Maybe [Text])
  , indexLedger :: !(Maybe Derived)
  }
  deriving stock (Eq, Show)

-- | Nothing observed. Every obligation observed against it is 'Missing'.
emptyEvidenceIndex :: EvidenceIndex
emptyEvidenceIndex =
  EvidenceIndex
    { indexLanes = Map.empty
    , indexAggregate = Nothing
    , indexTranscripts = Map.empty
    , indexCurrentSource = Left "current source digest was not computed"
    , indexPendingControls = Nothing
    , indexLedger = Nothing
    }

-- | The derived state of one obligation. Total: an obligation the index knows
-- nothing about is 'Missing', never proven by default.
observeObligation :: EvidenceIndex -> Obligation -> Derived
observeObligation index obligation =
  case obligation of
    GateTranscript gate substrate ->
      maybe
        (missing (transcriptSubject gate substrate))
        transcriptJudgement
        (Map.lookup (gate, substrate) (indexTranscripts index))
    StandingGate gate substrate ->
      case Map.lookup (gate, substrate) (indexTranscripts index) of
        Nothing -> missing (transcriptSubject gate substrate)
        Just evidence -> freshTranscript index evidence
    LaneJournal substrate ->
      fromMaybe
        (missing ("lane journal for " <> renderSubstrate substrate))
        (Map.lookup substrate (indexLanes index))
    Aggregate ->
      fromMaybe (missing "retained product aggregate") (indexAggregate index)
    NoPendingControls phase ->
      case indexPendingControls index of
        Nothing -> missing "the pending production control list"
        Just controls ->
          case [entry | entry <- controls, pendingControlOwner entry == Just phase] of
            [] ->
              Proven
                ( EvidenceRef
                    { evidenceSubject = "pendingProductionControls (src/JitML/Test/NegativeControls/Pending.hs)"
                    , evidenceDigest = Nothing
                    }
                    :| []
                )
            firstOwned : moreOwned ->
              Unproven
                (fmap (Incomplete . ("pending production control: " <>)) (firstOwned :| moreOwned))
    LedgerClear ->
      fromMaybe (missing "the legacy ledger") (indexLedger index)
    ExternalContext description ->
      Unproven (External description :| [])
    UpstreamSprint sprint ->
      Unproven
        ( Mismatched
            ( "upstream edge "
                <> sprint
                <> " is declared through dependsOn, not as an obligation"
            )
            :| []
        )
 where
  missing what = Unproven (Missing what :| [])
  transcriptSubject gate substrate =
    "validation record for " <> renderValidationGate gate <> " on " <> renderSubstrate substrate

-- | A judged transcript is fresh only when the record's source stamp is the
-- stamp of the tree being evaluated.
freshTranscript :: EvidenceIndex -> TranscriptEvidence -> Derived
freshTranscript index evidence =
  case transcriptJudgement evidence of
    unproven@(Unproven _) -> unproven
    proven@(Proven _) ->
      case (indexCurrentSource index, transcriptSource evidence) of
        (Left reason, _) ->
          Unproven (Mismatched ("the current source digest is unavailable: " <> reason) :| [])
        (_, Nothing) ->
          Unproven (Mismatched "the admitted record carries no source stamp" :| [])
        (Right current, Just recorded)
          | stampAlgorithm current /= stampAlgorithm recorded ->
              Unproven
                ( Mismatched
                    ( "source digest algorithm "
                        <> tshow (stampAlgorithm recorded)
                        <> " is not the current algorithm "
                        <> tshow (stampAlgorithm current)
                    )
                    :| []
                )
          | stampSha256 current /= stampSha256 recorded ->
              Unproven
                ( Stale
                    "source tree"
                    (stampSha256 current)
                    (stampSha256 recorded)
                    :| []
                )
          | otherwise -> proven

-- | The phase that owns a pending production control, read from its
-- @Phase <n>:@ prefix. An entry with no such prefix is owned by nobody, so no
-- 'NoPendingControls' obligation covers it and a catalogue test rejects it.
pendingControlOwner :: Text -> Maybe Int
pendingControlOwner entry = do
  afterPrefix <- Text.stripPrefix "Phase " entry
  let (digits, rest) = Text.span isDigit afterPrefix
  _ <- Text.stripPrefix ":" rest
  digitsToInt digits

-- ---------------------------------------------------------------------------
-- The catalogue
-- ---------------------------------------------------------------------------

-- | Whether work on a sprint has begun. A human declaration: it is the one status
-- input that evidence cannot supply, and it can never make a sprint Done.
data WorkState
  = NotStarted
  | Started
  deriving stock (Eq, Show)

-- | The section of the sprint's phase document that records its closure.
newtype LegacyCitation = LegacyCitation
  { citedSection :: Text
  }
  deriving stock (Eq, Show)

data Closure
  = -- | Closed before machine evidence existed. Frozen and shrink-only.
    LegacyAttested !LegacyCitation
  | -- | Done only when every obligation is proven: work state, upstream sprints,
    -- and a non-empty obligation list, so an evidenced sprint cannot be Done
    -- vacuously.
    Evidenced !WorkState ![SprintId] !(NonEmpty Obligation)
  deriving stock (Eq, Show)

data SprintEntry = SprintEntry
  { entrySprintId :: !SprintId
  , entrySprintTitle :: !Text
  , entryClosure :: !Closure
  }
  deriving stock (Eq, Show)

data PhaseEntry = PhaseEntry
  { entryPhaseNumber :: !Int
  , entryPhaseTitle :: !Text
  , entryPhaseDocument :: !FilePath
  , entrySprints :: ![SprintEntry]
  }
  deriving stock (Eq, Show)

legacyAttested :: Text -> Closure
legacyAttested = LegacyAttested . LegacyCitation

evidencedSprint :: WorkState -> [SprintId] -> NonEmpty Obligation -> Closure
evidencedSprint = Evidenced

isLegacyClosure :: Closure -> Bool
isLegacyClosure (LegacyAttested _) = True
isLegacyClosure Evidenced {} = False

-- | Every sprint of the catalogue in ascending sprint order.
catalogueSprints :: [PhaseEntry] -> [SprintEntry]
catalogueSprints phases =
  sortBy (comparing' entrySprintId) (concatMap entrySprints phases)
 where
  comparing' key left right = compareSprintId (key left) (key right)

-- | Structural problems in a catalogue, each a one-line description. An empty
-- list means every edge is forward-only and resolvable, ids belong to their
-- phase, and no legacy citation is blank.
validateCatalogue :: [PhaseEntry] -> [Text]
validateCatalogue phases =
  duplicatePhases
    <> emptyPhases
    <> concatMap sprintProblems sprints
    <> duplicateSprints
 where
  sprints = catalogueSprints phases
  sprintIds = fmap entrySprintId sprints
  known = Set.fromList sprintIds
  duplicatePhases =
    [ "duplicate product phase: " <> tshow number
    | number <- duplicates (fmap entryPhaseNumber phases)
    ]
  emptyPhases =
    [ "phase " <> tshow (entryPhaseNumber phase) <> " has no sprints"
    | phase <- phases
    , null (entrySprints phase)
    ]
  duplicateSprints =
    ["duplicate sprint id: " <> sprint | sprint <- duplicates sprintIds]
  phaseOf =
    Map.fromList
      [ (entrySprintId sprint, entryPhaseNumber phase)
      | phase <- phases
      , sprint <- entrySprints phase
      ]
  sprintProblems entry =
    idProblems entry <> closureProblems entry
  idProblems entry =
    case (sprintPhaseNumber (entrySprintId entry), Map.lookup (entrySprintId entry) phaseOf) of
      (Nothing, _) -> ["sprint id is not <phase>.<n>: " <> entrySprintId entry]
      (Just number, Just owner)
        | number /= owner ->
            [ "sprint "
                <> entrySprintId entry
                <> " is listed under phase "
                <> tshow owner
            ]
      _ -> []
  closureProblems entry =
    case entryClosure entry of
      LegacyAttested citation ->
        [ "legacy sprint " <> entrySprintId entry <> " cites no closure section"
        | Text.null (Text.strip (citedSection citation))
            || Text.strip (citedSection citation) /= citedSection citation
        ]
      Evidenced _ upstream obligations ->
        concatMap (edgeProblems entry) upstream
          <> [ entrySprintId entry <> " declares an upstream edge as an obligation"
             | any isUpstream (NonEmpty.toList obligations)
             ]
  isUpstream (UpstreamSprint _) = True
  isUpstream _ = False
  edgeProblems entry upstream
    | upstream == entrySprintId entry =
        [entrySprintId entry <> " depends on itself"]
    | not (Set.member upstream known) =
        [entrySprintId entry <> " depends on unknown sprint " <> upstream]
    | compareSprintId upstream (entrySprintId entry) /= LT =
        [ entrySprintId entry
            <> " declares a backward Blocked-by edge to higher-numbered "
            <> upstream
        ]
    | otherwise = []

duplicates :: (Ord a) => [a] -> [a]
duplicates values =
  [value | value : _ : _ <- List.group (List.sort values)]

-- ---------------------------------------------------------------------------
-- Projection
-- ---------------------------------------------------------------------------

-- | What a sprint's status rests on.
data Basis
  = BasisLegacy !LegacyCitation
  | -- | The declared work state, and every obligation (upstream edges first)
    -- with its derived state.
    BasisEvidence !WorkState ![(Obligation, Derived)]
  deriving stock (Eq, Show)

data SprintProjection = SprintProjection
  { projectionSprint :: !SprintId
  , projectionTitle :: !Text
  , projectionStatus :: !SprintStatus
  , projectionBasis :: !Basis
  }
  deriving stock (Eq, Show)

-- | Where a refusal comes from: one sprint, or the standing set that guards the
-- closure verdict.
data Scope
  = SprintScope !SprintId
  | StandingScope
  deriving stock (Eq, Ord, Show)

-- | One unmet obligation with its location.
data Refusal = Refusal
  { refusalScope :: !Scope
  , refusalObligation :: !Obligation
  , refusalReason :: !Unmet
  }
  deriving stock (Eq, Show)

-- | The verdict closure-claim guards consume. A closed verdict lists the
-- legacy-attested sprints it rests on, so a full closure is never silently more
-- than the machine-proven sprints; the list is empty only when no sprint is
-- legacy.
--
-- The constructors are private. A closed verdict is evidence that every
-- obligation was observed proven, so the only way to obtain one is
-- 'projectStatusReport', and a consumer reads it through 'closureOutcome'; no
-- caller can mint a closed verdict by writing one down.
data ClosureVerdict
  = Closed ![SprintId]
  | Refused !(NonEmpty Refusal)
  deriving stock (Eq, Show)

-- | The result of one projection. The constructor is private for the same
-- reason as 'ClosureVerdict': the verdict a report carries must be the one its
-- own projections and standing obligations produced.
data StatusReport = StatusReport
  { reportProjections :: ![SprintProjection]
  , reportStanding :: ![(Obligation, Derived)]
  , reportVerdict :: !ClosureVerdict
  }
  deriving stock (Eq, Show)

-- | The verdict as data: the refusals that keep closure from holding, or the
-- legacy-attested sprints a closed verdict rests on. This is the only way to
-- take a verdict apart, so a consumer decides both cases and can never build one.
closureOutcome :: ClosureVerdict -> Either (NonEmpty Refusal) [SprintId]
closureOutcome verdict =
  case verdict of
    Closed legacy -> Right legacy
    Refused refusals -> Left refusals

data StatusCounts = StatusCounts
  { countDone :: !Int
  , countActive :: !Int
  , countPlanned :: !Int
  , countBlocked :: !Int
  }
  deriving stock (Eq, Show)

-- | Every unmet obligation of a projection: empty exactly when it is Done.
projectionOpen :: SprintProjection -> [Refusal]
projectionOpen projection =
  case projectionBasis projection of
    BasisLegacy _ -> []
    BasisEvidence _ checked ->
      [ Refusal (SprintScope (projectionSprint projection)) obligation reason
      | (obligation, Unproven reasons) <- checked
      , reason <- NonEmpty.toList reasons
      ]

-- | Project the catalogue over an evidence index. Sprints are evaluated in
-- ascending sprint order, so every upstream sprint is already projected when a
-- sprint reads its status; the input order of the catalogue cannot matter.
projectStatusReport :: [PhaseEntry] -> [Obligation] -> EvidenceIndex -> StatusReport
projectStatusReport phases standing index =
  StatusReport
    { reportProjections = projections
    , reportStanding = standingChecked
    , reportVerdict = closureVerdict projections standingChecked
    }
 where
  projections = reverse (snd (foldl' step (Map.empty, []) (catalogueSprints phases)))
  step (statuses, acc) entry =
    let projection = projectSprint index (`Map.lookup` statuses) entry
     in (Map.insert (entrySprintId entry) (projectionStatus projection) statuses, projection : acc)
  standingChecked = [(obligation, observeObligation index obligation) | obligation <- standing]

projectSprint
  :: EvidenceIndex
  -> (SprintId -> Maybe SprintStatus)
  -> SprintEntry
  -> SprintProjection
projectSprint index upstreamStatus entry =
  case entryClosure entry of
    LegacyAttested citation ->
      SprintProjection
        { projectionSprint = entrySprintId entry
        , projectionTitle = entrySprintTitle entry
        , projectionStatus = Done
        , projectionBasis = BasisLegacy citation
        }
    Evidenced work upstream obligations ->
      let checked =
            [(UpstreamSprint sprint, upstreamDerived sprint) | sprint <- upstream]
              <> [(obligation, observeObligation index obligation) | obligation <- NonEmpty.toList obligations]
          reasons = [reason | (_, Unproven unmet) <- checked, reason <- NonEmpty.toList unmet]
          blockedUpstream = any isAwaiting reasons
          externalOpen = any isExternal reasons
          status
            | null reasons = Done
            | blockedUpstream = Blocked
            | work == Started = Active
            | externalOpen = Blocked
            | otherwise = Planned
       in SprintProjection
            { projectionSprint = entrySprintId entry
            , projectionTitle = entrySprintTitle entry
            , projectionStatus = status
            , projectionBasis = BasisEvidence work checked
            }
 where
  upstreamDerived sprint =
    case upstreamStatus sprint of
      Just Done ->
        Proven
          (EvidenceRef {evidenceSubject = "sprint " <> sprint <> " is Done", evidenceDigest = Nothing} :| [])
      _ -> Unproven (AwaitsSprint sprint :| [])
  isAwaiting (AwaitsSprint _) = True
  isAwaiting _ = False
  isExternal (External _) = True
  isExternal _ = False

closureVerdict :: [SprintProjection] -> [(Obligation, Derived)] -> ClosureVerdict
closureVerdict projections standing =
  case NonEmpty.nonEmpty (concatMap projectionOpen projections <> standingRefusals) of
    Nothing -> Closed (reportLegacyOf projections)
    Just refusals -> Refused refusals
 where
  standingRefusals =
    [ Refusal StandingScope obligation reason
    | (obligation, Unproven reasons) <- standing
    , reason <- NonEmpty.toList reasons
    ]

reportLegacyOf :: [SprintProjection] -> [SprintId]
reportLegacyOf projections =
  [ projectionSprint projection
  | projection <- projections
  , BasisLegacy _ <- [projectionBasis projection]
  ]

-- | The legacy-attested sprints, ascending.
reportLegacy :: StatusReport -> [SprintId]
reportLegacy = reportLegacyOf . reportProjections

statusCounts :: StatusReport -> StatusCounts
statusCounts report =
  StatusCounts
    { countDone = count Done
    , countActive = count Active
    , countPlanned = count Planned
    , countBlocked = count Blocked
    }
 where
  count status = length [() | projection <- reportProjections report, projectionStatus projection == status]

-- | @63 Done / 1 Active / 0 Planned / 6 Blocked@, the tally the plan documents
-- otherwise type by hand.
renderStatusCounts :: StatusCounts -> Text
renderStatusCounts counts =
  Text.intercalate
    " / "
    [ tshow (countDone counts) <> " Done"
    , tshow (countActive counts) <> " Active"
    , tshow (countPlanned counts) <> " Planned"
    , tshow (countBlocked counts) <> " Blocked"
    ]

-- | Every sprint that is not Done, ascending. The open chain is derived, not
-- written down.
openChain :: StatusReport -> [SprintId]
openChain report =
  [ projectionSprint projection
  | projection <- reportProjections report
  , projectionStatus projection /= Done
  ]

renderRefusal :: Refusal -> Text
renderRefusal refusal =
  scope
    <> " "
    <> renderObligation (refusalObligation refusal)
    <> ": "
    <> renderUnmet (refusalReason refusal)
 where
  scope =
    case refusalScope refusal of
      SprintScope sprint -> sprint
      StandingScope -> "standing"

-- | A short description of the verdict for drift messages: the tally of unmet
-- obligations and the first one.
closureVerdictSummary :: ClosureVerdict -> Text
closureVerdictSummary verdict =
  case verdict of
    Closed legacy ->
      "closure holds on machine evidence with "
        <> tshow (length legacy)
        <> " legacy-attested sprint(s)"
    Refused refusals@(first :| _) ->
      "closure is refused: "
        <> tshow (length refusals)
        <> " unmet obligation(s); first: "
        <> renderRefusal first

-- | The full report @jitml docs status@ prints. Deterministic: sprint order,
-- obligation order, and every digest come from the projection, never a clock.
renderStatusReport :: StatusReport -> Text
renderStatusReport report =
  Text.unlines
    ( [ "status: " <> renderStatusCounts counts <> " across " <> tshow (length projections) <> " sprints"
      , "legacy attested: "
          <> tshow (length legacy)
          <> " sprint(s), frozen and shrink-only; legacy attestation never mints a Done"
      , "open chain: " <> chain
      , verdictLine
      , "docs check and check-code are computed when they run, never attested"
      ]
        <> concatMap renderProjection evidenced
        <> standingBlock
    )
 where
  projections = reportProjections report
  counts = statusCounts report
  legacy = reportLegacy report
  evidenced = [projection | projection <- projections, isEvidenced (projectionBasis projection)]
  isEvidenced (BasisEvidence _ _) = True
  isEvidenced (BasisLegacy _) = False
  chain =
    case openChain report of
      [] -> "(none)"
      sprints -> Text.intercalate " -> " (fmap (maybe "?" tshow . sprintPhaseNumber) sprints)
  verdictLine =
    case reportVerdict report of
      Closed _ ->
        "closure: closed on machine evidence ("
          <> tshow (length legacy)
          <> " legacy-attested sprints disclosed)"
      Refused refusals -> "closure: refused (" <> tshow (length refusals) <> " unmet obligations)"
  renderProjection projection =
    ( "sprint "
        <> projectionSprint projection
        <> " "
        <> renderSprintStatus (projectionStatus projection)
        <> " - "
        <> projectionTitle projection
    )
      : case projectionBasis projection of
        BasisLegacy citation ->
          ["  legacy attestation: " <> citedSection citation]
        BasisEvidence work checked ->
          ["  work: " <> (if work == Started then "started" else "not started")]
            <> concatMap renderChecked checked
  renderChecked (obligation, derived) =
    case derived of
      Proven evidence ->
        [ "  proven  " <> renderObligation obligation <> ": " <> renderEvidence ref
        | ref <- NonEmpty.toList evidence
        ]
      Unproven reasons ->
        [ "  unmet   " <> renderObligation obligation <> ": " <> renderUnmet reason
        | reason <- NonEmpty.toList reasons
        ]
  renderEvidence ref =
    evidenceSubject ref <> maybe "" (" sha256=" <>) (evidenceDigest ref)
  standingBlock =
    case reportStanding report of
      [] -> []
      standing -> "standing obligations guard the closure verdict:" : concatMap renderChecked standing

tshow :: (Show a) => a -> Text
tshow = Text.pack . show
