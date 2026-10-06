{-# LANGUAGE OverloadedStrings #-}

-- | Phase 288 - read the committed evidence the status projection consumes.
--
-- Everything here reads /committed, versioned files/ (or code-resident lists) and
-- nothing else; it never reads @.build/@, never consults version control, and
-- never runs a gate. Lane journals and the aggregate are read through the
-- production readers, and every typed reader error is mapped to an 'Unmet' by
-- constructor:
--
-- * lane journal: a row whose contract digest is not the current one is 'Stale';
--   a rejected row, malformed or non-canonical bytes, and a pin that differs from
--   the retained bytes are 'Mismatched'; an unreadable file is 'Missing';
-- * aggregate: lane coverage and a missing row are 'Incomplete'; an unregistered
--   input, an unprojectable lane, and report drift are 'Mismatched'; an unreadable
--   file is 'Missing'; a rejected lane contributes that lane's reasons. A retained
--   aggregate that embeds a pin other than the current one is 'Stale' even when
--   the lanes it joins cannot be read;
-- * gate transcript: an absent or unreadable file is 'Missing'; a rejected record,
--   another gate, substrate, or command is 'Mismatched'; a failed run is
--   'FailedRun'; a run that never ran, or a passing non-live run of a gate that
--   proves live-only code ('gateRequiresLiveRun'), is 'Incomplete'; a standing
--   transcript for another source tree is 'Stale' (judged by
--   "JitML.Product.StatusEvidence").
--
-- The mapping is total: adding a reader constructor is a compile error here until
-- it is classified, so no new failure mode can be read as proof.
--
-- The pure judgement functions are exported so fixtures can drive them without a
-- file; only the @load*@ functions perform I/O. Every loader has an @...In@ form
-- that reads below an explicit repository root, so a test can drive the real
-- disk path over a temporary tree; the unsuffixed form is that root @.@. Paths in
-- evidence pointers and messages stay repository-relative whatever the root is.
module JitML.Product.StatusLoader
  ( TranscriptFile (..)
  , aggregateErrorUnmet
  , aggregatePinDrift
  , commandIsStanding
  , commandRanLive
  , gateRequiresLiveRun
  , judgeAggregate
  , judgeLaneJournalBytes
  , judgeLedger
  , judgeTranscriptFile
  , laneErrorUnmet
  , ledgerPendingRows
  , legacyLedgerPath
  , listCommittedValidationFiles
  , listCommittedValidationFilesIn
  , loadEvidenceIndex
  , loadEvidenceIndexIn
  , loadLaneJournalIn
  , loadProductAggregationIn
  , loadProductPhaseStatuses
  , loadProductStatusReport
  , loadProductStatusReportIn
  , standingCommandTail
  , underRoot
  , unexpectedValidationFiles
  )
where

import Control.Exception (IOException, evaluate, try)
import Data.Aeson (Value (..), eitherDecodeStrict')
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Bifunctor (first)
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.Char (isDigit, isSpace)
import Data.Foldable (toList)
import Data.List (sort)
import Data.List.NonEmpty (NonEmpty (..))
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory)
import System.FilePath (takeFileName, (</>))

import JitML.Plan.Plan (Validation (..))
import JitML.Product.Matrix qualified as Product
import JitML.Product.PhaseStatus
  ( ProductPhaseStatus
  , productPhaseStatuses
  , projectProductStatus
  )
import JitML.Product.SourceDigest (computeSourceStampIn)
import JitML.Product.StatusEvidence
  ( Derived (..)
  , EvidenceIndex (..)
  , EvidenceRef (..)
  , StatusReport
  , TranscriptEvidence (..)
  , Unmet (..)
  )
import JitML.Product.ValidationRecord
  ( FailedEvidence (..)
  , RecordEvidence (..)
  , ValidationGate (..)
  , ValidationRecord
  , ValidationRecordError
  , admitValidationRecord
  , allValidationGates
  , committedValidationDirectory
  , renderValidationGate
  , renderValidationRecordError
  , sha256Hex
  , validationRecordCommand
  , validationRecordEvidence
  , validationRecordFileName
  , validationRecordGate
  , validationRecordSource
  , validationRecordSubstrate
  )
import JitML.Sub.Render (renderSubprocess)
import JitML.Sub.Subprocess (niceArguments, niceExecutable, subprocess)
import JitML.Substrate (Substrate (..), allSubstrates, renderSubstrate)
import JitML.Test.NegativeControls.Pending (pendingProductionControls)
import JitML.Test.ProductAggregation
  ( ProductAggregation
  , ProductAggregationError (..)
  , ProductLaneInput (..)
  )
import JitML.Test.ProductAggregation qualified as Aggregate
import JitML.Test.ProductLaneJournal qualified as Lane
import JitML.Test.Report (substrateTestInvocations)

-- ---------------------------------------------------------------------------
-- Lane journals
-- ---------------------------------------------------------------------------

-- | One lane-journal reader error as an unmet reason. @context@ names the lane so
-- a reason read out of the aggregate is still attributable.
laneErrorUnmet :: Text -> Lane.ProductLaneJournalError -> Unmet
laneErrorUnmet context err =
  case err of
    Lane.ProductLaneJournalContractStale row expected actual ->
      Stale (context <> " " <> row <> " contract_sha256") expected actual
    Lane.ProductLaneJournalSourceRejected detail ->
      Mismatched (context <> ": " <> detail)
    Lane.ProductLaneJournalMalformed detail ->
      Mismatched (context <> ": malformed lane journal: " <> detail)
    Lane.ProductLaneJournalNonCanonical ->
      Mismatched (context <> ": lane journal bytes are not canonical JSON")
    Lane.ProductLaneJournalDigestMismatch expected actual ->
      Mismatched
        ( context
            <> ": retained bytes have sha256 "
            <> actual
            <> " but the pin is "
            <> expected
        )
    Lane.ProductLaneJournalIOFailure path _detail ->
      Missing (Text.pack path)

-- | Admit one pinned lane journal against the current projection.
judgeLaneJournalBytes :: ProductLaneInput -> ByteString -> Derived
judgeLaneJournalBytes input bytes =
  case Product.projectProductRows lane Product.allProductRows of
    Failure errors ->
      Unproven
        ( Mismatched
            ( context
                <> ": the current registry cannot project this lane ("
                <> Text.pack (show (NonEmpty.length errors))
                <> " error(s))"
            )
            :| []
        )
    Success batch ->
      case Lane.admitProductLaneJournal (productLaneInputSha256 input) batch bytes of
        Left errors -> Unproven (fmap (laneErrorUnmet context) errors)
        Right _admitted ->
          Proven
            ( EvidenceRef
                { evidenceSubject = Text.pack (productLaneInputPath input)
                , evidenceDigest = Just (productLaneInputSha256 input)
                }
                :| []
            )
 where
  lane = productLaneInputSubstrate input
  context = renderSubstrate lane

-- | Read and admit one pinned lane journal below @root@. The pin is data, so a
-- test can judge bytes it wrote under another pin; the registered pins are
-- 'Aggregate.productLaneInputs'.
loadLaneJournalIn :: FilePath -> ProductLaneInput -> IO (Substrate, Derived)
loadLaneJournalIn root input = do
  bytes <- tryIO (ByteString.readFile (underRoot root (productLaneInputPath input)))
  derived <-
    case bytes of
      Left _ -> pure (Unproven (Missing (Text.pack (productLaneInputPath input)) :| []))
      Right content -> evaluate (judgeLaneJournalBytes input content)
  pure (productLaneInputSubstrate input, derived)

-- ---------------------------------------------------------------------------
-- The three-lane aggregate
-- ---------------------------------------------------------------------------

-- | One aggregation reader error as unmet reasons.
aggregateErrorUnmet :: ProductAggregationError -> [Unmet]
aggregateErrorUnmet err =
  case err of
    ProductAggregationLaneCoverage counts ->
      [ Incomplete
          ( "the aggregate needs exactly one journal per lane, found "
              <> Text.intercalate
                ", "
                [renderSubstrate lane <> " x" <> Text.pack (show count) | (lane, count) <- counts]
          )
      ]
    ProductAggregationUnregisteredInput lane ->
      [Mismatched (renderSubstrate lane <> ": the aggregate input is not a registered pin")]
    ProductAggregationProjectionRejected lane _errors ->
      [Mismatched (renderSubstrate lane <> ": the current registry cannot project this lane")]
    ProductAggregationLaneRejected lane errors ->
      toList (fmap (laneErrorUnmet (renderSubstrate lane)) errors)
    ProductAggregationMissingRow lane rowId ->
      [Incomplete (renderSubstrate lane <> ": the lane journal has no row " <> rowId)]
    ProductAggregationIOFailure path _detail ->
      [Missing (Text.pack path)]
    ProductAggregationReportDrift path ->
      [Mismatched (Text.pack path <> " differs from the recomputed aggregate")]

-- | Compare the pins a retained aggregate embeds with the current pins. The
-- aggregate is a projection of the pinned lane journals, so an embedded pin that
-- is not the current pin marks it stale even when the lanes it joins cannot be
-- read.
aggregatePinDrift :: [ProductLaneInput] -> ByteString -> [Unmet]
aggregatePinDrift pins retained =
  case eitherDecodeStrict' retained of
    Left detail ->
      [Mismatched ("retained aggregate is not readable JSON: " <> Text.pack detail)]
    Right (Object record) ->
      case KeyMap.lookup (Key.fromText "sources") record of
        Just (Array sources) -> concatMap (sourceDrift . embeddedPin) sources
        _ -> [Mismatched "retained aggregate has no sources array"]
    Right _ -> [Mismatched "retained aggregate is not a JSON object"]
 where
  embeddedPin (Object source) =
    (,)
      <$> textField "substrate" source
      <*> textField "sha256" source
  embeddedPin _ = Nothing
  textField name source =
    case KeyMap.lookup (Key.fromText name) source of
      Just (String value) -> Just value
      _ -> Nothing
  sourceDrift Nothing = [Mismatched "retained aggregate has a source without substrate and sha256"]
  sourceDrift (Just (substrate, embedded)) =
    case [input | input <- pins, renderSubstrate (productLaneInputSubstrate input) == substrate] of
      [] -> [Mismatched ("retained aggregate names an unregistered lane " <> substrate)]
      input : _
        | productLaneInputSha256 input == embedded -> []
        | otherwise ->
            [ Stale
                (substrate <> " journal pin embedded in the retained aggregate")
                (productLaneInputSha256 input)
                embedded
            ]

-- | Judge the retained aggregate from what the production reader made of the
-- pinned lane journals and the retained bytes. @loaded@ is the aggregate the
-- reader recomputed from the lanes, as the bytes it renders to (or the reader's
-- errors); the retained file is proven only when it embeds the current pins and
-- is byte-identical to that recomputation. Every applicable unmet is reported,
-- not the first.
judgeAggregate
  :: FilePath
  -> [ProductLaneInput]
  -> Either (NonEmpty ProductAggregationError) ByteString
  -> Either Text ByteString
  -> Derived
judgeAggregate path pins loaded retained =
  case NonEmpty.nonEmpty (retainedProblems <> readerProblems) of
    Just problems -> Unproven problems
    Nothing ->
      Proven
        ( EvidenceRef
            { evidenceSubject = Text.pack path
            , evidenceDigest = either (const Nothing) (Just . sha256Hex) retained
            }
            :| []
        )
 where
  retainedProblems =
    case retained of
      Left _ -> [Missing (Text.pack path)]
      Right bytes -> aggregatePinDrift pins bytes
  readerProblems =
    case loaded of
      Left errors -> concatMap aggregateErrorUnmet errors
      Right recomputed ->
        case retained of
          Left _ -> []
          Right bytes
            | recomputed == bytes -> []
            | otherwise ->
                [ Stale
                    "retained product aggregate"
                    (sha256Hex recomputed)
                    (sha256Hex bytes)
                ]

-- | 'Aggregate.loadProductAggregation' below @root@: every registered pin is
-- read from its registered relative path and joined by the production reader.
-- The registered inputs are passed through unchanged (the reader rejects any
-- other), so only where the bytes are read from depends on the root. At the
-- working-directory root this is the production loader, which a unit test pins.
loadProductAggregationIn
  :: FilePath
  -> IO (Either (NonEmpty ProductAggregationError) ProductAggregation)
loadProductAggregationIn root = do
  loaded <- traverse readInput Aggregate.productLaneInputs
  pure (sequence loaded >>= Aggregate.aggregateProductLaneJournals)
 where
  readInput input = do
    result <- tryIO (ByteString.readFile (underRoot root (productLaneInputPath input)))
    pure $ case result of
      Left exception ->
        Left
          ( ProductAggregationIOFailure
              (productLaneInputPath input)
              (Text.pack (show exception))
              :| []
          )
      Right bytes -> Right (input, bytes)

loadAggregateIn :: FilePath -> IO Derived
loadAggregateIn root = do
  loaded <- loadProductAggregationIn root
  retained <- readBytes (underRoot root Aggregate.productAggregatePath)
  evaluate
    ( judgeAggregate
        Aggregate.productAggregatePath
        Aggregate.productLaneInputs
        (Aggregate.productAggregationBytes <$> loaded)
        retained
    )

-- ---------------------------------------------------------------------------
-- Gate transcripts
-- ---------------------------------------------------------------------------

-- | What reading one transcript file produced.
data TranscriptFile
  = TranscriptAbsent
  | TranscriptUnreadable !Text
  | TranscriptRejected !ValidationRecordError
  | -- | The SHA-256 of the file's bytes and the admitted record.
    TranscriptAdmitted !Text !ValidationRecord

-- | The argument tail of the standing invocation of a gate on a substrate, as
-- @jitml test@ renders it: exactly what @cabal@ is asked to run, so the record
-- and the check share one derivation.
standingCommandTail :: ValidationGate -> Substrate -> Text
standingCommandTail gate substrate =
  case substrateTestInvocations (Just substrate) [renderValidationGate gate] Nothing of
    [args] -> Text.drop (Text.length "cabal ") (renderSubprocess (subprocess "cabal" args))
    _ -> ""

-- | Whether a recorded command is the standing invocation: a cabal executable
-- (any directory; the file name is @cabal@ or @cabal-<version>@, see
-- 'isCabalFileName'), optionally under the live @nice@ wrapper, followed by
-- exactly the standing arguments. A focused run (@--test-options '-p ...'@),
-- another stanza, or extra flags are not the standing gate and cannot satisfy it.
commandIsStanding :: ValidationGate -> Substrate -> Text -> Bool
commandIsStanding gate substrate command =
  case Text.stripSuffix (" " <> standingCommandTail gate substrate) command of
    Nothing -> False
    Just prefix -> isCabalToken (unwrapNice prefix)
 where
  unwrapNice prefix = fromMaybe prefix (Text.stripPrefix liveNicePrefix prefix)
  -- A quoted path may contain spaces (that is how the renderer writes one); an
  -- unquoted token must be a single word, so a shell prefix cannot hide in front
  -- of the executable.
  isCabalToken token =
    case Text.stripPrefix "'" token >>= Text.stripSuffix "'" of
      Just quoted -> isCabalFileName (Text.pack (takeFileName (Text.unpack quoted)))
      Nothing ->
        not (Text.null token)
          && not (Text.any isSpace token)
          && isCabalFileName (Text.pack (takeFileName (Text.unpack token)))

-- | What @jitml test --live@ puts in front of the cabal executable ('underNice'),
-- as the renderer writes it into a record, and so the only difference between a
-- live run's recorded command and a non-live one's.
liveNicePrefix :: Text
liveNicePrefix = renderSubprocess (subprocess niceExecutable niceArguments) <> " "

-- | Whether a recorded command ran under the live @nice@ wrapper, that is,
-- whether the record describes a @--live@ run.
commandRanLive :: Text -> Bool
commandRanLive = Text.isPrefixOf liveNicePrefix

-- | Whether a gate's transcript proves its obligation only when it records a
-- @--live@ run. The end-to-end stanza is the one gate that is: the live
-- orchestration Phase 289 owns (the measurement glue in "JitML.Test.Command")
-- executes only under @--live@, so a passing non-live run leaves it unexercised
-- and cannot stand for it.
gateRequiresLiveRun :: ValidationGate -> Bool
gateRequiresLiveRun gate = gate == JitmlE2e

-- | The file name of a cabal executable once its path is resolved. @jitml test@
-- records the canonical path of the @cabal@ it found, and a ghcup layout links
-- @cabal@ to @cabal-<version>@, so the recorded name is @cabal@ or, resolved,
-- @cabal-3.16.1.0@: the prefix and a dotted run of decimal components, nothing
-- else. Anything that merely starts with @cabal@ is not cabal.
isCabalFileName :: Text -> Bool
isCabalFileName name =
  name == "cabal" || maybe False isVersion (Text.stripPrefix "cabal-" name)
 where
  isVersion version =
    all
      (\component -> not (Text.null component) && Text.all isDigit component)
      (Text.splitOn "." version)

-- | Judge one transcript file for the obligation @(gate, substrate)@.
judgeTranscriptFile
  :: ValidationGate
  -> Substrate
  -> FilePath
  -> TranscriptFile
  -> TranscriptEvidence
judgeTranscriptFile gate substrate path file =
  case file of
    TranscriptAbsent ->
      unproven Nothing (Missing pathText)
    TranscriptUnreadable detail ->
      unproven Nothing (Missing (pathText <> " (unreadable: " <> detail <> ")"))
    TranscriptRejected err ->
      unproven Nothing (Mismatched (pathText <> ": " <> renderValidationRecordError err))
    TranscriptAdmitted fileSha record ->
      TranscriptEvidence
        { transcriptJudgement =
            case NonEmpty.nonEmpty
              (subjectProblems record <> outcomeProblems record <> liveProblems record) of
              Just problems -> Unproven problems
              Nothing ->
                Proven
                  ( EvidenceRef {evidenceSubject = pathText, evidenceDigest = Just fileSha}
                      :| []
                  )
        , transcriptSource = Just (validationRecordSource record)
        }
 where
  pathText = Text.pack path
  unproven source reason =
    TranscriptEvidence {transcriptJudgement = Unproven (reason :| []), transcriptSource = source}
  subjectProblems record =
    [ Mismatched
        ( pathText
            <> " records gate "
            <> renderValidationGate (validationRecordGate record)
            <> ", expected "
            <> renderValidationGate gate
        )
    | validationRecordGate record /= gate
    ]
      <> [ Mismatched
             ( pathText
                 <> " records substrate "
                 <> renderSubstrate (validationRecordSubstrate record)
                 <> ", expected "
                 <> renderSubstrate substrate
             )
         | validationRecordSubstrate record /= substrate
         ]
      <> [ Mismatched
             ( pathText
                 <> " records command `"
                 <> validationRecordCommand record
                 <> "`, which is not the standing invocation `cabal "
                 <> standingCommandTail gate substrate
                 <> "`"
             )
         | not (commandIsStanding gate substrate (validationRecordCommand record))
         ]
  outcomeProblems record =
    case validationRecordEvidence record of
      EvidencePassed _ _ -> []
      EvidenceFailed failed ->
        [ FailedRun
            ( pathText
                <> ": "
                <> maybe
                  "the runner raised before an exit status"
                  (("exit " <>) . Text.pack . show)
                  (failedExitCode failed)
                <> "; both output streams are retained in the record"
            )
        ]
      EvidenceNotRun stanza detail ->
        [ Incomplete
            ( pathText
                <> ": the gate did not run, blocked by "
                <> stanza
                <> " ("
                <> detail
                <> ")"
            )
        ]
  liveProblems record =
    case validationRecordEvidence record of
      EvidencePassed _ _
        | gateRequiresLiveRun gate
        , validationRecordGate record == gate
        , not (commandRanLive (validationRecordCommand record)) ->
            [ Incomplete
                ( pathText
                    <> " records a passing non-live run of "
                    <> renderValidationGate gate
                    <> "; only a `--live` run executes the code this gate proves"
                )
            ]
      _ -> []

loadTranscriptIn
  :: FilePath -> (ValidationGate, Substrate) -> IO ((ValidationGate, Substrate), TranscriptEvidence)
loadTranscriptIn root key@(gate, substrate) = do
  exists <- doesFileExist (underRoot root path)
  file <-
    if exists
      then do
        bytes <- tryIO (ByteString.readFile (underRoot root path))
        pure $ case bytes of
          Left exception -> TranscriptUnreadable (Text.pack (show exception))
          Right content ->
            case admitValidationRecord content of
              Left err -> TranscriptRejected err
              Right record -> TranscriptAdmitted (sha256Hex content) record
      else pure TranscriptAbsent
  evidence <- evaluate (judgeTranscriptFile gate substrate path file)
  pure (key, evidence)
 where
  path = committedValidationDirectory </> validationRecordFileName gate substrate

-- | The entries of the committed validation directory, or none when the
-- directory does not exist yet.
listCommittedValidationFiles :: IO [FilePath]
listCommittedValidationFiles = listCommittedValidationFilesIn "."

-- | 'listCommittedValidationFiles' below @root@.
listCommittedValidationFilesIn :: FilePath -> IO [FilePath]
listCommittedValidationFilesIn root = do
  exists <- doesDirectoryExist directory
  if exists
    then sort <$> listDirectory directory
    else pure []
 where
  directory = underRoot root committedValidationDirectory

-- | Names in the committed validation directory that are not one of the
-- @<gate>.<substrate>.json@ files the projection reads. A misnamed record would
-- otherwise be ignored and read as absent; hidden files such as @.gitkeep@ are
-- not records and are not reported.
unexpectedValidationFiles :: [FilePath] -> [FilePath]
unexpectedValidationFiles names =
  [name | name <- names, take 1 name /= ".", name `notElem` expected]
 where
  expected =
    [ validationRecordFileName gate substrate
    | gate <- allValidationGates
    , substrate <- allSubstrates
    ]

-- ---------------------------------------------------------------------------
-- The legacy ledger
-- ---------------------------------------------------------------------------

legacyLedgerPath :: FilePath
legacyLedgerPath = "DEVELOPMENT_PLAN" </> "legacy-tracking-for-deletion.md"

-- | The number of data rows in the ledger's Pending Removal table. 'Nothing'
-- when the section or its table cannot be read as one, which callers treat as
-- unproven rather than as an empty ledger.
ledgerPendingRows :: Text -> Maybe Int
ledgerPendingRows content = do
  section <- pendingRemovalSection (Text.lines content)
  let tableLines = filter (isTableLine . Text.strip) section
  case tableLines of
    [] | any ((== "None.") . Text.strip) section -> Just 0
    [] -> Nothing
    header : rest
      | isItemHeader header ->
          let body = dropWhile isSeparator rest
           in if all isSeparatorOrRow body
                then Just (length (filter (not . isSeparator) body))
                else Nothing
      | otherwise -> Nothing
 where
  pendingRemovalSection allLines =
    case dropWhile ((/= "## Pending Removal") . Text.strip) allLines of
      [] -> Nothing
      (_ : afterHeading) -> Just (takeWhile (not . Text.isPrefixOf "## ") afterHeading)
  isTableLine line = "|" `Text.isPrefixOf` line
  isItemHeader line = "| Item |" `Text.isPrefixOf` Text.strip line
  isSeparator line =
    let stripped = Text.strip line
     in "|" `Text.isPrefixOf` stripped && Text.all (\c -> c `elem` ("|-: " :: String)) stripped
  isSeparatorOrRow line = "|" `Text.isPrefixOf` Text.strip line

-- | Judge the ledger text: proven only when the Pending Removal table is
-- readable and has no rows.
judgeLedger :: FilePath -> Either Text Text -> Derived
judgeLedger path content =
  case content of
    Left _ -> Unproven (Missing (Text.pack path) :| [])
    Right text ->
      case ledgerPendingRows text of
        Nothing ->
          Unproven
            ( Mismatched
                (Text.pack path <> ": the Pending Removal table cannot be read")
                :| []
            )
        Just 0 ->
          Proven
            ( EvidenceRef
                { evidenceSubject = Text.pack path <> " has no Pending Removal row"
                , evidenceDigest = Just (sha256Hex (Text.Encoding.encodeUtf8 text))
                }
                :| []
            )
        Just rows ->
          Unproven
            ( Incomplete
                ( Text.pack path
                    <> ": "
                    <> Text.pack (show rows)
                    <> " row(s) remain in Pending Removal"
                )
                :| []
            )

loadLedgerIn :: FilePath -> IO Derived
loadLedgerIn root = do
  content <- tryIO (ByteString.readFile (underRoot root legacyLedgerPath))
  evaluate
    ( judgeLedger
        legacyLedgerPath
        (either (Left . Text.pack . show) (Right . Text.Encoding.decodeUtf8Lenient) content)
    )

-- ---------------------------------------------------------------------------
-- Assembly
-- ---------------------------------------------------------------------------

-- | Read every committed input the projection consumes from the working
-- directory, which is the repository root.
loadEvidenceIndex :: IO EvidenceIndex
loadEvidenceIndex = loadEvidenceIndexIn "."

-- | 'loadEvidenceIndex' below @root@: the lane journals, the retained aggregate,
-- the validation records, the source stamp of the code roots, and the legacy
-- ledger all come from that tree, and the pending-control list from the code.
loadEvidenceIndexIn :: FilePath -> IO EvidenceIndex
loadEvidenceIndexIn root = do
  lanes <- traverse (loadLaneJournalIn root) Aggregate.productLaneInputs
  aggregate <- loadAggregateIn root
  transcripts <-
    traverse
      (loadTranscriptIn root)
      [(gate, substrate) | gate <- allValidationGates, substrate <- allSubstrates]
  source <- computeSourceStampIn root
  ledger <- loadLedgerIn root
  pure
    EvidenceIndex
      { indexLanes = Map.fromList lanes
      , indexAggregate = Just aggregate
      , indexTranscripts = Map.fromList transcripts
      , indexCurrentSource = source
      , indexPendingControls = Just pendingProductionControls
      , indexLedger = Just ledger
      }

-- | The projection of the catalogue over the evidence committed in this tree.
loadProductStatusReport :: IO StatusReport
loadProductStatusReport = loadProductStatusReportIn "."

-- | The projection of the catalogue over the evidence committed below @root@.
loadProductStatusReportIn :: FilePath -> IO StatusReport
loadProductStatusReportIn root = projectProductStatus <$> loadEvidenceIndexIn root

-- | The registry view of that projection: the derived replacement for the
-- literal @allProductPhaseStatuses@ the registry used to be. It is @IO@ because
-- status now depends on committed files.
loadProductPhaseStatuses :: IO [ProductPhaseStatus]
loadProductPhaseStatuses = productPhaseStatuses <$> loadProductStatusReport

-- | @underRoot root path@ is @path@ inside @root@. The working-directory root
-- @.@ leaves the path exactly as written, so messages that quote a path stay
-- repository-relative.
underRoot :: FilePath -> FilePath -> FilePath
underRoot "." path = path
underRoot root path = root </> path

readBytes :: FilePath -> IO (Either Text ByteString)
readBytes path = do
  result <- tryIO (ByteString.readFile path)
  pure (first (Text.pack . show) result)

tryIO :: IO value -> IO (Either IOException value)
tryIO = try
