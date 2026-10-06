{-# LANGUAGE OverloadedStrings #-}

-- | Phase 288 - read the development plan's phase documents and check them
-- against the status projection.
--
-- These parsers used to live inside the @jitml-unit@ test driver, so the
-- registry-versus-document relation was enforced only when the unit stanza ran.
-- They live in @src/@ now, and @jitml docs check@ applies them to the worktree,
-- so a document that says Done without proof, or proof that outruns a non-Done
-- header, is a docs drift in the same gate that guards every other governed
-- document.
--
-- Everything here is pure text in, issues out; "JitML.Docs.Check" reads the files
-- and turns issues into drifts.
--
-- = Rules checked per sprint block
--
-- * the block has a bare-word @**Status**:@ line (@Done@, @Active@, @Planned@, or
--   @Blocked@), and its heading suffix and, for a single-sprint phase, the
--   @## Phase State@ line say the same;
-- * that status equals the status the evidence projection derives;
-- * every @**Blocked by**:@ edge points at a strictly lower sprint (rule M(a));
-- * a Blocked sprint has a @**Blocked by**:@ line naming every upstream sprint the
--   projection says is not Done, and a Planned or Done sprint has none;
-- * an evidenced sprint's @**Blocked by**:@ line names no sprint the catalogue does
--   not list as one of its upstream edges, so a document cannot declare a blocker
--   the projection cannot see;
-- * an Active sprint has a @### Remaining Work@ block that is not @None.@;
-- * the @### Validation@ block names a concrete gate command (rule M) and never
--   names both accelerators (rule M(b));
-- * every @jitml test <stanza> --<substrate>@ the @### Validation@ block of an
--   evidenced sprint names is a gate-transcript obligation of that sprint, so an
--   obligation cannot be dropped from the catalogue while the document still owes
--   the gate;
-- * a legacy-attested sprint cites a closure section that its block contains;
-- * every phase document from the first product phase on is in the catalogue, so
--   a phase cannot leave every closure verdict by being dropped from it.
module JitML.Product.PlanDoc
  ( PlanIssue (..)
  , PlanSprintFacts (..)
  , closureStatusHeading
  , closureStatusLengthIssue
  , closureStatusLineCap
  , closureStatusSectionLength
  , compareDottedId
  , extractDottedNumbers
  , parsePhaseStateStatus
  , parsePlanSprintFacts
  , parsePlanSprintStatuses
  , parseSprintHeader
  , phaseDocumentNumber
  , planDocumentIssues
  , unregisteredPhaseDocuments
  , validationGatesNamed
  )
where

import Data.Char (isDigit)
import Data.List (find, isSuffixOf, nub, stripPrefix)
import Data.Maybe (isJust)
import Data.Text (Text)
import Data.Text qualified as Text
import Text.Read (readMaybe)

import JitML.Product.StatusEvidence
  ( Basis (..)
  , LegacyCitation (..)
  , Obligation (..)
  , Refusal (..)
  , SprintId
  , SprintProjection (..)
  , SprintStatus (..)
  , Unmet (..)
  , compareSprintId
  , parseSprintStatus
  , projectionOpen
  , renderRefusal
  , renderSprintStatus
  , sprintPhaseNumber
  )
import JitML.Product.ValidationRecord
  ( ValidationGate
  , parseValidationGate
  , renderValidationGate
  )
import JitML.Substrate (Substrate, parseSubstrate, renderSubstrate)

-- | One violated rule, with the drift key it is reported under.
data PlanIssue = PlanIssue
  { issueKey :: !Text
  , issueMessage :: !Text
  }
  deriving stock (Eq, Show)

-- | The structural facts of one @## Sprint@ block.
data PlanSprintFacts = PlanSprintFacts
  { psfId :: Text
  , psfStatusText :: Maybe Text
  , psfHeaderStatus :: Maybe SprintStatus
  , psfHeadingStatus :: Maybe SprintStatus
  , psfBlockedByLines :: Int
  , psfBlockedBy :: [Text]
  , psfHasRemainingWork :: Bool
  , psfHasValidationGate :: Bool
  , psfValidationNamesCuda :: Bool
  , psfValidationNamesApple :: Bool
  , psfValidationGates :: [(ValidationGate, Substrate)]
  , psfHeadings :: [Text]
  }
  deriving stock (Eq, Show)

-- | @## Sprint 278.1: ...@ to @278.1@.
parseSprintHeader :: Text -> Maybe Text
parseSprintHeader line =
  case Text.stripPrefix "## Sprint " (Text.strip line) of
    Nothing -> Nothing
    Just rest ->
      let sprintId' = Text.takeWhile isSprintIdChar rest
       in if Text.null sprintId' then Nothing else Just sprintId'
 where
  isSprintIdChar char =
    char == '.' || isDigit char

-- | The bare-word @**Status**:@ of every sprint block, in document order.
parsePlanSprintStatuses :: Text -> Text -> Either Text [(Text, SprintStatus)]
parsePlanSprintStatuses path content =
  traverse status (sprintSections (Text.lines content))
 where
  status (sprintId', _heading, body) =
    case [rest | line <- body, Just rest <- [Text.stripPrefix "**Status**:" (Text.strip line)]] of
      [] -> Left (path <> ": no **Status**: line for " <> sprintId')
      rawStatus : _ ->
        case parseSprintStatus rawStatus of
          Just parsed -> Right (sprintId', parsed)
          Nothing ->
            Left
              ( path
                  <> ": unknown sprint status "
                  <> Text.strip rawStatus
                  <> " for "
                  <> sprintId'
              )

-- | Group lines into @(sprint id, heading line, body lines)@ per @## Sprint X.Y@
-- header; a body runs until the next level-two heading.
sprintSections :: [Text] -> [(Text, Text, [Text])]
sprintSections [] = []
sprintSections (line : rest)
  | Just sid <- parseSprintHeader line =
      let (body, after) = break isLevelTwoHeading rest
       in (sid, line, body) : sprintSections after
  | otherwise = sprintSections rest

isLevelTwoHeading :: Text -> Bool
isLevelTwoHeading line = "## " `Text.isPrefixOf` Text.strip line

-- | Structural facts per sprint block, in document order.
parsePlanSprintFacts :: Text -> [PlanSprintFacts]
parsePlanSprintFacts content =
  fmap sprintFacts (sprintSections (Text.lines content))
 where
  sprintFacts (sid, heading, body) =
    let validationBlock = validationBlockLines body
        statusText =
          case [rest | line <- body, Just rest <- [Text.stripPrefix "**Status**:" (Text.strip line)]] of
            [] -> Nothing
            rest : _ -> Just (Text.strip rest)
        blockedByLines = filter isBlockedByLine body
     in PlanSprintFacts
          { psfId = sid
          , psfStatusText = statusText
          , psfHeaderStatus = statusText >>= parseSprintStatus
          , psfHeadingStatus = headingStatus heading
          , psfBlockedByLines = length blockedByLines
          , psfBlockedBy = concatMap extractDottedNumbers blockedByLines
          , psfHasRemainingWork = remainingWorkHasContent body
          , psfHasValidationGate = any lineNamesGateCommand validationBlock
          , psfValidationNamesCuda = any (lineNamesAny cudaTokens) validationBlock
          , psfValidationNamesApple = any (lineNamesAny appleTokens) validationBlock
          , psfValidationGates = nub (concatMap validationGatesNamed validationBlock)
          , psfHeadings =
              [Text.strip (Text.dropWhile (== '#') (Text.strip line)) | line <- body, isSubHeading line]
          }
  isBlockedByLine line = "**Blocked by**:" `Text.isPrefixOf` Text.strip line
  isSubHeading line = "###" `Text.isPrefixOf` Text.strip line
  -- The lines of a sprint's `### Validation` block (up to the next heading).
  validationBlockLines body =
    case dropWhile (not . isValidationHeading) body of
      [] -> []
      (_ : afterHeading) -> takeWhile (not . isAnyHeading) afterHeading
  isValidationHeading line = "### Validation" `Text.isPrefixOf` Text.strip line
  isAnyHeading line = "##" `Text.isPrefixOf` Text.strip line
  lineNamesGateCommand line = any (`Text.isInfixOf` line) ["jitml", "bootstrap", "docker", "cabal"]
  lineNamesAny toks line = any (`Text.isInfixOf` line) toks
  cudaTokens = ["--linux-cuda", "-fcuda", "linux-cuda.sh"]
  appleTokens = ["--apple-silicon", "apple-silicon.sh"]

-- | The gate and substrate a validation line runs: every @jitml test <stanza>@
-- whose stanza is a validation gate, paired with each @--<substrate>@ flag on the
-- line. A line that runs @all@ stanzas, or that names no substrate flag, names
-- nothing here, so the rule that reads this can only be missed, never falsely
-- tripped.
validationGatesNamed :: Text -> [(ValidationGate, Substrate)]
validationGatesNamed line =
  case afterJitmlTest (Text.words line) of
    Nothing -> []
    Just rest ->
      [ (gate, substrate)
      | stanza <- take 1 rest
      , Just gate <- [parseValidationGate stanza]
      , flag <- rest
      , Just substrate <- [Text.stripPrefix "--" flag >>= parseSubstrate]
      ]
 where
  afterJitmlTest ("jitml" : "test" : rest) = Just rest
  afterJitmlTest (_ : rest) = afterJitmlTest rest
  afterJitmlTest [] = Nothing

-- | The phase number of a phase document file name: @phase-278-external-bars.md@
-- is phase @278@.
phaseDocumentNumber :: FilePath -> Maybe Int
phaseDocumentNumber name = do
  afterPrefix <- stripPrefix "phase-" name
  let (digits, rest) = span isDigit afterPrefix
  if not (null digits) && take 1 rest == "-" && ".md" `isSuffixOf` name
    then readMaybe digits
    else Nothing

-- | The phase documents at or above @first@ that the catalogue does not list,
-- each with the file it is reported against. Without this a phase could be
-- dropped from the catalogue, and so from every closure verdict, while its
-- document stayed in the plan.
unregisteredPhaseDocuments :: Int -> [Int] -> [FilePath] -> [(FilePath, PlanIssue)]
unregisteredPhaseDocuments first registered names =
  [ ( name
    , PlanIssue
        ("status-catalogue.unregistered-phase-" <> Text.pack (show number))
        ( Text.pack name
            <> " is phase "
            <> Text.pack (show number)
            <> "'s plan document, but the status catalogue has no entry for it"
        )
    )
  | name <- names
  , Just number <- [phaseDocumentNumber name]
  , number >= first
  , number `notElem` registered
  ]

-- | The status word in the trailing @[<emoji> <Word>]@ of a sprint heading.
headingStatus :: Text -> Maybe SprintStatus
headingStatus heading = do
  let stripped = Text.strip heading
  inner <- Text.stripSuffix "]" stripped
  let (_, afterBracket) = Text.breakOnEnd "[" inner
  word <- lastWord afterBracket
  parseSprintStatus word
 where
  lastWord text =
    case reverse (Text.words text) of
      [] -> Nothing
      word : _ -> Just word

-- | A @### Remaining Work@ heading followed by content other than @None.@.
remainingWorkHasContent :: [Text] -> Bool
remainingWorkHasContent body =
  case dropWhile (not . isRemainingHeading) body of
    [] -> False
    (_ : afterHeading) ->
      case filter (not . Text.null . Text.strip) (takeWhile (not . isHeading) afterHeading) of
        [] -> False
        [single] -> Text.strip single /= "None."
        _ -> True
 where
  isRemainingHeading line = "### Remaining Work" `Text.isPrefixOf` Text.strip line
  isHeading line = "##" `Text.isPrefixOf` Text.strip line

-- | The status word of the first bold token of the first line under
-- @## Phase State@.
parsePhaseStateStatus :: Text -> Maybe SprintStatus
parsePhaseStateStatus content =
  case dropWhile ((/= "## Phase State") . Text.strip) (Text.lines content) of
    [] -> Nothing
    (_ : after) ->
      case dropWhile (Text.null . Text.strip) after of
        [] -> Nothing
        first : _ ->
          case Text.splitOn "**" first of
            _ : word : _ : _ -> parseSprintStatus word
            _ -> Nothing

-- | Extract maximal digit/dot tokens containing a dot (i.e. @X.Y@ sprint ids).
extractDottedNumbers :: Text -> [Text]
extractDottedNumbers =
  filter (Text.any (== '.')) . Text.split (\c -> not (isDigit c || c == '.'))

-- | Compare two dotted numeric ids (@23.2@ against @24.1@) component-wise.
compareDottedId :: Text -> Text -> Ordering
compareDottedId = compareSprintId

-- | Every rule violated by one phase document, given the projections of the
-- sprints the catalogue expects it to contain.
planDocumentIssues :: [SprintProjection] -> Text -> [PlanIssue]
planDocumentIssues expected content =
  concatMap sprintIssues expected
    <> unregistered
    <> phaseState
 where
  facts = parsePlanSprintFacts content
  factsFor sprintId' = find ((== sprintId') . psfId) facts
  expectedIds = fmap projectionSprint expected
  unregistered =
    [ structure (psfId fact) "sprint-unregistered" "the block is not in the status catalogue"
    | fact <- facts
    , psfId fact `notElem` expectedIds
    ]
  sprintIssues projection =
    case factsFor (projectionSprint projection) of
      Nothing ->
        [ structure
            (projectionSprint projection)
            "sprint-missing"
            "the phase document has no `## Sprint` block for this sprint"
        ]
      Just fact -> sprintFactIssues projection fact
  -- A single-sprint phase's `## Phase State` line must agree with its sprint.
  phaseState =
    case (expected, facts) of
      ([projection], [fact])
        | Just header <- psfHeaderStatus fact
        , parsePhaseStateStatus content /= Just header ->
            [ structure
                (projectionSprint projection)
                "phase-state"
                ( "the `## Phase State` line does not say "
                    <> renderSprintStatus header
                )
            ]
      _ -> []

sprintFactIssues :: SprintProjection -> PlanSprintFacts -> [PlanIssue]
sprintFactIssues projection fact =
  statusLineIssues
    <> projectionIssues
    <> edgeIssues
    <> undeclaredEdgeIssues
    <> blockedByIssues
    <> remainingWorkIssues
    <> validationIssues
    <> validationObligationIssues
    <> legacyIssues
 where
  sprint = psfId fact
  header = psfHeaderStatus fact
  derived = projectionStatus projection
  open = projectionOpen projection

  statusLineIssues =
    case (psfStatusText fact, header) of
      (Nothing, _) -> [structure sprint "status-line" "the block has no **Status**: line"]
      (Just raw, Nothing) ->
        [structure sprint "status-line" ("unknown sprint status `" <> raw <> "`")]
      (Just _, Just status) ->
        [ structure
            sprint
            "heading-status"
            ( "the sprint heading says "
                <> maybe "nothing recognisable" renderSprintStatus (psfHeadingStatus fact)
                <> " but **Status**: says "
                <> renderSprintStatus status
            )
        | psfHeadingStatus fact /= Just status
        ]

  projectionIssues =
    case header of
      Nothing -> []
      Just status
        | status == derived -> omittedUpstream
        | status == Done ->
            [ projectionIssue
                ( "the header says Done without proof: "
                    <> unmetSummary open
                )
            ]
        | derived == Done ->
            [ projectionIssue
                ( "the evidence proves every obligation, so the header must say Done, but it says "
                    <> renderSprintStatus status
                )
            ]
        | otherwise ->
            [ projectionIssue
                ( "the header says "
                    <> renderSprintStatus status
                    <> " but the evidence derives "
                    <> renderSprintStatus derived
                    <> ": "
                    <> unmetSummary open
                )
            ]
  projectionIssue reason =
    PlanIssue ("status-projection." <> sprint) (sprint <> ": " <> reason)

  -- The Blocked by line must name every upstream sprint the projection says
  -- is not Done.
  omittedUpstream =
    [ projectionIssue ("the Blocked by line does not name upstream sprint " <> upstream)
    | derived == Blocked
    , upstream <- awaited
    , upstream `notElem` psfBlockedBy fact
    ]
  awaited = [upstream | Refusal {refusalReason = AwaitsSprint upstream} <- open]

  edgeIssues =
    [ structure
        sprint
        "backward-edge"
        ("declares a Blocked-by edge to " <> ref <> ", which is not a strictly lower sprint")
    | ref <- psfBlockedBy fact
    , compareSprintId ref sprint /= LT
    ]

  -- A sprint id the block names that the catalogue does not list as an upstream
  -- edge of this sprint is a blocker the projection cannot see. A backward edge is
  -- reported once, by 'edgeIssues', and a Planned or Done sprint that declares any
  -- blocker once, by 'blockedByIssues'.
  undeclaredEdgeIssues =
    [ structure
        sprint
        "undeclared-edge"
        ( "names "
            <> ref
            <> " in its **Blocked by**: line, which the status catalogue does not list as an upstream edge"
        )
    | header `elem` [Just Blocked, Just Active]
    , Just catalogued <- [catalogueUpstream]
    , ref <- psfBlockedBy fact
    , isJust (sprintPhaseNumber ref)
    , compareSprintId ref sprint == LT
    , ref `notElem` catalogued
    ]
  catalogueUpstream =
    case projectionBasis projection of
      BasisEvidence _ checked -> Just [upstream | (UpstreamSprint upstream, _) <- checked]
      BasisLegacy _ -> Nothing

  blockedByIssues =
    case header of
      Just Blocked ->
        [ structure sprint "blocked-by-missing" "a Blocked sprint has no **Blocked by**: line"
        | psfBlockedByLines fact == 0
        ]
      Just status
        | status `elem` [Planned, Done] ->
            [ structure
                sprint
                "blockers-declared"
                (renderSprintStatus status <> " sprint declares a **Blocked by**: line")
            | psfBlockedByLines fact > 0
            ]
      _ -> []

  remainingWorkIssues =
    [ structure
        sprint
        "remaining-work-missing"
        "an Active sprint has no `### Remaining Work` block naming its unmet obligations"
    | header == Just Active
    , not (psfHasRemainingWork fact)
    ]

  validationIssues =
    [ structure sprint "validation-gate" "the sprint has no non-empty `### Validation` gate"
    | not (psfHasValidationGate fact)
    ]
      <> [ structure
             sprint
             "dual-accelerator"
             "the validation block names both a linux-cuda and an apple-silicon lane"
         | psfValidationNamesCuda fact && psfValidationNamesApple fact
         ]

  -- The gates the document's Validation block runs are the gates the sprint owes:
  -- an evidenced sprint that dropped one of them from the catalogue could be Done
  -- without it.
  validationObligationIssues =
    case projectionBasis projection of
      BasisEvidence _ checked ->
        [ structure
            sprint
            "validation-obligation"
            ( "the ### Validation block runs "
                <> renderValidationGate gate
                <> " on "
                <> renderSubstrate substrate
                <> ", but the sprint owns no gate-transcript obligation for it"
            )
        | (gate, substrate) <- psfValidationGates fact
        , not (any (ownsGate gate substrate . fst) checked)
        ]
      BasisLegacy _ -> []
  ownsGate gate substrate obligation =
    case obligation of
      GateTranscript ownedGate ownedSubstrate -> ownedGate == gate && ownedSubstrate == substrate
      StandingGate ownedGate ownedSubstrate -> ownedGate == gate && ownedSubstrate == substrate
      LaneJournal _ -> False
      Aggregate -> False
      NoPendingControls _ -> False
      LedgerClear -> False
      ExternalContext _ -> False
      UpstreamSprint _ -> False

  legacyIssues =
    case projectionBasis projection of
      BasisLegacy citation
        | not (any (citedSection citation `Text.isPrefixOf`) (psfHeadings fact)) ->
            [ structure
                sprint
                "legacy-citation"
                ( "the legacy attestation cites the section `"
                    <> citedSection citation
                    <> "`, which the sprint block does not contain"
                )
            ]
      _ -> []

structure :: SprintId -> Text -> Text -> PlanIssue
structure sprint rule message =
  PlanIssue
    { issueKey = "plan-structure." <> sprint <> "." <> rule
    , issueMessage = sprint <> ": " <> message
    }

-- | The unmet obligations of a sprint for a drift message: how many, and the
-- first few.
unmetSummary :: [Refusal] -> Text
unmetSummary [] = "no unmet obligations"
unmetSummary refusals =
  Text.pack (show (length refusals))
    <> " unmet obligation(s): "
    <> Text.intercalate "; " (fmap renderRefusal (take 3 refusals))
    <> (if length refusals > 3 then "; ..." else "")

-- ---------------------------------------------------------------------------
-- The thin Closure Status section
-- ---------------------------------------------------------------------------

closureStatusHeading :: Text
closureStatusHeading = "## Closure Status"

-- | The longest @## Closure Status@ section, in lines including its heading,
-- that @jitml docs check@ accepts in @DEVELOPMENT_PLAN/README.md@. 'Nothing'
-- disables the check. Development-plan standards rule N requires the section to
-- stay thin: per-commit narrative belongs in the README's historical diary, and
-- current status is what @jitml docs status@ derives. This is the only place the
-- number is written.
closureStatusLineCap :: Maybe Int
closureStatusLineCap = Just 60

-- | The length in lines, heading included, of the @## Closure Status@ section:
-- from its heading to the line before the next level-two heading.
closureStatusSectionLength :: Text -> Maybe Int
closureStatusSectionLength content =
  case break ((== closureStatusHeading) . Text.strip) (Text.lines content) of
    (_, []) -> Nothing
    (_, _ : after) -> Just (1 + length (takeWhile (not . isLevelTwoHeading) after))

-- | The issue, if any, for a README under the given cap.
closureStatusLengthIssue :: Maybe Int -> Text -> [PlanIssue]
closureStatusLengthIssue Nothing _ = []
closureStatusLengthIssue (Just cap) content =
  case closureStatusSectionLength content of
    Nothing ->
      [PlanIssue "closure-status.length" "the plan README has no `## Closure Status` section"]
    Just lengthInLines
      | lengthInLines > cap ->
          [ PlanIssue
              "closure-status.length"
              ( "the Closure Status section is "
                  <> Text.pack (show lengthInLines)
                  <> " lines, over the cap of "
                  <> Text.pack (show cap)
                  <> "; rule N keeps it to status, gate commands, and links"
              )
          ]
      | otherwise -> []
