{-# LANGUAGE OverloadedStrings #-}

-- | Phase 288 - the versioned @jitml-validation-record@ that persists one gate
-- invocation as committed evidence.
--
-- One record describes one @(gate, substrate)@ run: the exact rendered command,
-- whether it @Passed@, @Failed@, or was @NotRun@, digests of the streams it
-- produced, the SHA-256 of the executable that ran it, and the
-- 'JitML.Product.SourceDigest.SourceStamp' of the code roots it ran against.
-- A failed run retains both complete output streams (development-plan standards
-- rule N); a passed run retains only their digests, because the committed record
-- must stay small enough to live in the tree. The record carries no clock and no
-- duration, so the same run always renders the same bytes.
--
-- The wire is one line of canonical JSON followed by a newline. Admission
-- decodes strictly (unknown or missing fields are rejected), re-runs the same
-- cross-field validation the smart constructor applies, and finally requires the
-- decoded value to re-render to the exact input bytes. The record is not signed:
-- its integrity rests on that consistency (a failed run's streams must hash to
-- the recorded digests, a passed run may retain none, and the outcome fixes which
-- other fields may be present) and on the reviewed commit that adds it. Nothing
-- pins a record's digest in @src/@, which would change the very source digest the
-- record is bound to.
module JitML.Product.ValidationRecord
  ( FailedEvidence (..)
  , RecordEvidence (..)
  , ValidationGate (..)
  , ValidationRecord
  , ValidationRecordError (..)
  , admitValidationRecord
  , allValidationGates
  , candidateValidationDirectory
  , committedValidationDirectory
  , mkValidationRecord
  , parseValidationGate
  , renderValidationGate
  , renderValidationRecord
  , renderValidationRecordError
  , hexBytes
  , sha256Hex
  , validationRecordCommand
  , validationRecordEvidence
  , validationRecordExecutableSha256
  , validationRecordFileName
  , validationRecordFormat
  , validationRecordGate
  , validationRecordSource
  , validationRecordSubstrate
  , validationRecordVersion
  , writeValidationRecordAtomic
  )
where

import Control.Exception (IOException, onException, try)
import Control.Monad (unless)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.Aeson
  ( FromJSON (..)
  , Value
  , eitherDecodeStrict'
  , encode
  , object
  , withObject
  , (.:)
  , (.=)
  )
import Data.Aeson.Key qualified as AesonKey
import Data.Aeson.KeyMap qualified as AesonKeyMap
import Data.Aeson.Types (Object, Parser)
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Char (intToDigit, isControl)
import Data.List qualified as List
import Data.Maybe (isNothing)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Word (Word64, Word8)
import System.Directory (createDirectoryIfMissing, removeFile, renameFile)
import System.FilePath ((</>))
import System.IO (hClose, hFlush, openBinaryTempFile)
import System.Posix.Files (setFileMode)

import JitML.Product.SourceDigest (SourceStamp (..))
import JitML.Substrate (Substrate, parseSubstrate, renderSubstrate)

-- | The test stanzas @jitml test@ runs. Each is a gate whose invocation can be
-- retained as a record. @jitml docs check@ and @jitml check-code@ are
-- deliberately absent: they are computed when the closure is evaluated, never
-- attested by a file that itself sits inside the tree they check.
data ValidationGate
  = JitmlUnit
  | JitmlIntegration
  | JitmlSlCanonicals
  | JitmlRlCanonicals
  | JitmlHyperparameter
  | JitmlBackends
  | JitmlDaemonLifecycle
  | JitmlE2e
  | JitmlNegativeControls
  | JitmlModelConvergence
  deriving stock (Bounded, Enum, Eq, Ord, Show)

allValidationGates :: [ValidationGate]
allValidationGates = [minBound .. maxBound]

-- | The stanza name, exactly as @jitml test <stanza>@ spells it.
renderValidationGate :: ValidationGate -> Text
renderValidationGate gate =
  case gate of
    JitmlUnit -> "jitml-unit"
    JitmlIntegration -> "jitml-integration"
    JitmlSlCanonicals -> "jitml-sl-canonicals"
    JitmlRlCanonicals -> "jitml-rl-canonicals"
    JitmlHyperparameter -> "jitml-hyperparameter"
    JitmlBackends -> "jitml-backends"
    JitmlDaemonLifecycle -> "jitml-daemon-lifecycle"
    JitmlE2e -> "jitml-e2e"
    JitmlNegativeControls -> "jitml-negative-controls"
    JitmlModelConvergence -> "jitml-model-convergence"

parseValidationGate :: Text -> Maybe ValidationGate
parseValidationGate name =
  List.find ((== name) . renderValidationGate) allValidationGates

-- | What a failed run leaves behind. Streams are complete when present; a stream
-- is absent only when capture did not complete. The exit code is absent only when
-- the runner raised before any exit status existed, in which case the exception
-- text is present instead.
data FailedEvidence = FailedEvidence
  { failedExitCode :: !(Maybe Int)
  , failedStdout :: !(Maybe Text)
  , failedStderr :: !(Maybe Text)
  , failedException :: !(Maybe Text)
  }
  deriving stock (Eq, Show)

data RecordEvidence
  = -- | The stdout and stderr SHA-256 of a run that exited zero.
    EvidencePassed !Text !Text
  | EvidenceFailed !FailedEvidence
  | -- | The stanza whose failure stopped the run, and a description of it.
    EvidenceNotRun !Text !Text
  deriving stock (Eq, Show)

data ValidationRecord = ValidationRecord
  { recordGate :: !ValidationGate
  , recordSubstrate :: !Substrate
  , recordCommand :: !Text
  , recordExecutableSha256 :: !Text
  , recordSource :: !SourceStamp
  , recordEvidence :: !RecordEvidence
  }
  deriving stock (Eq, Show)

data ValidationRecordError
  = RecordMalformed !Text
  | RecordNonCanonical
  | RecordUnsupported !Text
  | RecordInconsistent !Text
  deriving stock (Eq, Show)

validationRecordFormat :: Text
validationRecordFormat = "jitml-validation-record"

validationRecordVersion :: Word64
validationRecordVersion = 1

-- | Where committed records live, one file per @(gate, substrate)@.
committedValidationDirectory :: FilePath
committedValidationDirectory = "DEVELOPMENT_PLAN" </> "attestations" </> "validation"

-- | Where @jitml test@ writes the record candidates for a human to copy into
-- 'committedValidationDirectory'. Nothing reads this directory.
candidateValidationDirectory :: FilePath
candidateValidationDirectory = ".build" </> "runtime" </> "validation"

validationRecordFileName :: ValidationGate -> Substrate -> FilePath
validationRecordFileName gate substrate =
  Text.unpack (renderValidationGate gate <> "." <> renderSubstrate substrate <> ".json")

validationRecordGate :: ValidationRecord -> ValidationGate
validationRecordGate = recordGate

validationRecordSubstrate :: ValidationRecord -> Substrate
validationRecordSubstrate = recordSubstrate

validationRecordCommand :: ValidationRecord -> Text
validationRecordCommand = recordCommand

validationRecordExecutableSha256 :: ValidationRecord -> Text
validationRecordExecutableSha256 = recordExecutableSha256

validationRecordSource :: ValidationRecord -> SourceStamp
validationRecordSource = recordSource

validationRecordEvidence :: ValidationRecord -> RecordEvidence
validationRecordEvidence = recordEvidence

-- | The only way to build a record. Every cross-field rule the wire admission
-- enforces is enforced here too, so an issued record and an admitted record obey
-- one definition.
mkValidationRecord
  :: ValidationGate
  -> Substrate
  -> Text
  -> Text
  -> SourceStamp
  -> RecordEvidence
  -> Either ValidationRecordError ValidationRecord
mkValidationRecord gate substrate command executableSha source evidence =
  case commandProblems <> digestProblems <> evidenceProblems evidence of
    [] ->
      Right
        ValidationRecord
          { recordGate = gate
          , recordSubstrate = substrate
          , recordCommand = command
          , recordExecutableSha256 = executableSha
          , recordSource = source
          , recordEvidence = evidence
          }
    problem : _ -> Left (RecordInconsistent problem)
 where
  commandProblems =
    [ "command is empty, untrimmed, or contains control characters"
    | Text.null command || Text.strip command /= command || Text.any isControl command
    ]
  digestProblems =
    [ "executable_sha256 is not canonical SHA-256"
    | not (isCanonicalSha256 executableSha)
    ]
      <> [ "source_sha256 is not canonical SHA-256"
         | not (isCanonicalSha256 (stampSha256 source))
         ]

evidenceProblems :: RecordEvidence -> [Text]
evidenceProblems evidence =
  case evidence of
    EvidencePassed stdoutSha stderrSha ->
      [ "passed run has a stream digest that is not canonical SHA-256"
      | not (isCanonicalSha256 stdoutSha && isCanonicalSha256 stderrSha)
      ]
    EvidenceFailed failed ->
      failedProblems failed
    EvidenceNotRun stanza detail ->
      [ "not-run record has an empty or untrimmed blocker stanza or detail"
      | not (plainText stanza && plainText detail)
      ]

failedProblems :: FailedEvidence -> [Text]
failedProblems failed =
  case (failedExitCode failed, failedException failed) of
    (Just code, Nothing)
      | code /= 0 -> []
      | otherwise -> ["failed run records a zero exit code"]
    (Nothing, Just exception)
      | plainText exception -> []
      | otherwise -> ["failed run records an empty or untrimmed exception"]
    (Just _, Just _) -> ["failed run records both an exit code and an exception"]
    (Nothing, Nothing) -> ["failed run records neither an exit code nor an exception"]

plainText :: Text -> Bool
plainText value = not (Text.null value) && Text.strip value == value

-- | Canonical bytes: one line of JSON with sorted keys, then a newline.
renderValidationRecord :: ValidationRecord -> ByteString
renderValidationRecord record =
  LazyByteString.toStrict (encode (recordValue record)) <> "\n"

recordValue :: ValidationRecord -> Value
recordValue record =
  object
    [ "format" .= validationRecordFormat
    , "version" .= validationRecordVersion
    , "gate" .= renderValidationGate (recordGate record)
    , "substrate" .= renderSubstrate (recordSubstrate record)
    , "command" .= recordCommand record
    , "executable_sha256" .= recordExecutableSha256 record
    , "source_digest_algorithm" .= stampAlgorithm (recordSource record)
    , "source_sha256" .= stampSha256 (recordSource record)
    , "outcome" .= outcome
    , "exit_code" .= exitCode
    , "stdout" .= stdout
    , "stderr" .= stderr
    , "stdout_sha256" .= stdoutSha
    , "stderr_sha256" .= stderrSha
    , "exception" .= exception
    , "blocked_by_stanza" .= blockedStanza
    , "blocked_by_detail" .= blockedDetail
    ]
 where
  none = Nothing :: Maybe Text
  (outcome, exitCode, stdout, stderr, stdoutSha, stderrSha, exception, blockedStanza, blockedDetail) =
    case recordEvidence record of
      EvidencePassed stdoutDigest stderrDigest ->
        ( "Passed" :: Text
        , Just (0 :: Int)
        , none
        , none
        , Just stdoutDigest
        , Just stderrDigest
        , none
        , none
        , none
        )
      EvidenceFailed failed ->
        ( "Failed"
        , failedExitCode failed
        , failedStdout failed
        , failedStderr failed
        , streamDigest <$> failedStdout failed
        , streamDigest <$> failedStderr failed
        , failedException failed
        , none
        , none
        )
      EvidenceNotRun stanza detail ->
        ( "NotRun"
        , Nothing
        , none
        , none
        , none
        , none
        , none
        , Just stanza
        , Just detail
        )

data RecordWire = RecordWire
  { wireFormat :: !Text
  , wireVersion :: !Word64
  , wireGate :: !Text
  , wireSubstrate :: !Text
  , wireCommand :: !Text
  , wireExecutableSha :: !Text
  , wireSourceAlgorithm :: !Word64
  , wireSourceSha :: !Text
  , wireOutcome :: !Text
  , wireExitCode :: !(Maybe Int)
  , wireStdout :: !(Maybe Text)
  , wireStderr :: !(Maybe Text)
  , wireStdoutSha :: !(Maybe Text)
  , wireStderrSha :: !(Maybe Text)
  , wireException :: !(Maybe Text)
  , wireBlockedStanza :: !(Maybe Text)
  , wireBlockedDetail :: !(Maybe Text)
  }

instance FromJSON RecordWire where
  parseJSON =
    withObject "ValidationRecord" $ \record -> do
      requireExactFields "ValidationRecord" wireFields record
      RecordWire
        <$> record .: "format"
        <*> record .: "version"
        <*> record .: "gate"
        <*> record .: "substrate"
        <*> record .: "command"
        <*> record .: "executable_sha256"
        <*> record .: "source_digest_algorithm"
        <*> record .: "source_sha256"
        <*> record .: "outcome"
        <*> record .: "exit_code"
        <*> record .: "stdout"
        <*> record .: "stderr"
        <*> record .: "stdout_sha256"
        <*> record .: "stderr_sha256"
        <*> record .: "exception"
        <*> record .: "blocked_by_stanza"
        <*> record .: "blocked_by_detail"

wireFields :: [Text]
wireFields =
  [ "format"
  , "version"
  , "gate"
  , "substrate"
  , "command"
  , "executable_sha256"
  , "source_digest_algorithm"
  , "source_sha256"
  , "outcome"
  , "exit_code"
  , "stdout"
  , "stderr"
  , "stdout_sha256"
  , "stderr_sha256"
  , "exception"
  , "blocked_by_stanza"
  , "blocked_by_detail"
  ]

requireExactFields :: String -> [Text] -> Object -> Parser ()
requireExactFields label expected record =
  unless (null unexpected) $
    fail
      ( label
          <> " contains unknown fields: "
          <> Text.unpack (Text.intercalate ", " unexpected)
      )
 where
  expectedKeys = fmap AesonKey.fromText expected
  unexpected =
    List.sort
      [ AesonKey.toText key
      | key <- AesonKeyMap.keys record
      , key `notElem` expectedKeys
      ]

-- | Strict admission of persisted bytes.
admitValidationRecord :: ByteString -> Either ValidationRecordError ValidationRecord
admitValidationRecord bytes = do
  wire <-
    case eitherDecodeStrict' bytes of
      Left detail -> Left (RecordMalformed (Text.pack detail))
      Right value -> Right value
  unless (wireFormat wire == validationRecordFormat) $
    Left (RecordUnsupported ("format " <> wireFormat wire))
  unless (wireVersion wire == validationRecordVersion) $
    Left (RecordUnsupported ("version " <> Text.pack (show (wireVersion wire))))
  record <- fromWire wire
  unless (renderValidationRecord record == bytes) $
    Left RecordNonCanonical
  pure record

fromWire :: RecordWire -> Either ValidationRecordError ValidationRecord
fromWire wire = do
  gate <-
    maybe
      (Left (RecordInconsistent ("unknown gate " <> wireGate wire)))
      Right
      (parseValidationGate (wireGate wire))
  substrate <-
    maybe
      (Left (RecordInconsistent ("unknown substrate " <> wireSubstrate wire)))
      Right
      (parseSubstrate (wireSubstrate wire))
  evidence <- evidenceFromWire wire
  mkValidationRecord
    gate
    substrate
    (wireCommand wire)
    (wireExecutableSha wire)
    SourceStamp {stampAlgorithm = wireSourceAlgorithm wire, stampSha256 = wireSourceSha wire}
    evidence

-- | The outcome fixes which other fields may be present; every disagreement is a
-- typed inconsistency rather than a silently ignored field.
evidenceFromWire :: RecordWire -> Either ValidationRecordError RecordEvidence
evidenceFromWire wire =
  case wireOutcome wire of
    "Passed" -> do
      requireAbsent "passed run" "stdout" (wireStdout wire)
      requireAbsent "passed run" "stderr" (wireStderr wire)
      requireAbsent "passed run" "exception" (wireException wire)
      requireAbsent "passed run" "blocked_by_stanza" (wireBlockedStanza wire)
      requireAbsent "passed run" "blocked_by_detail" (wireBlockedDetail wire)
      unless (wireExitCode wire == Just 0) $
        Left (RecordInconsistent "passed run must record exit_code 0")
      stdoutSha <- requirePresent "passed run" "stdout_sha256" (wireStdoutSha wire)
      stderrSha <- requirePresent "passed run" "stderr_sha256" (wireStderrSha wire)
      Right (EvidencePassed stdoutSha stderrSha)
    "Failed" -> do
      requireAbsent "failed run" "blocked_by_stanza" (wireBlockedStanza wire)
      requireAbsent "failed run" "blocked_by_detail" (wireBlockedDetail wire)
      requireStream "stdout" (wireStdout wire) (wireStdoutSha wire)
      requireStream "stderr" (wireStderr wire) (wireStderrSha wire)
      Right
        ( EvidenceFailed
            FailedEvidence
              { failedExitCode = wireExitCode wire
              , failedStdout = wireStdout wire
              , failedStderr = wireStderr wire
              , failedException = wireException wire
              }
        )
    "NotRun" -> do
      requireAbsent "not-run record" "exit_code" (wireExitCode wire)
      requireAbsent "not-run record" "stdout" (wireStdout wire)
      requireAbsent "not-run record" "stderr" (wireStderr wire)
      requireAbsent "not-run record" "stdout_sha256" (wireStdoutSha wire)
      requireAbsent "not-run record" "stderr_sha256" (wireStderrSha wire)
      requireAbsent "not-run record" "exception" (wireException wire)
      stanza <- requirePresent "not-run record" "blocked_by_stanza" (wireBlockedStanza wire)
      detail <- requirePresent "not-run record" "blocked_by_detail" (wireBlockedDetail wire)
      Right (EvidenceNotRun stanza detail)
    other -> Left (RecordInconsistent ("unknown outcome " <> other))
 where
  requireAbsent :: (Show a) => Text -> Text -> Maybe a -> Either ValidationRecordError ()
  requireAbsent context field value =
    unless (isNothing value) $
      Left (RecordInconsistent (context <> " must not carry " <> field))
  requirePresent :: Text -> Text -> Maybe a -> Either ValidationRecordError a
  requirePresent context field =
    maybe (Left (RecordInconsistent (context <> " must carry " <> field))) Right
  -- A retained stream and its digest appear together, and the digest is the
  -- digest of exactly the retained text.
  requireStream :: Text -> Maybe Text -> Maybe Text -> Either ValidationRecordError ()
  requireStream name stream digest =
    case (stream, digest) of
      (Nothing, Nothing) -> Right ()
      (Just text, Just recorded)
        | streamDigest text == recorded -> Right ()
        | otherwise ->
            Left (RecordInconsistent ("failed run " <> name <> " does not hash to its recorded digest"))
      _ ->
        Left (RecordInconsistent ("failed run must carry " <> name <> " and its digest together"))

streamDigest :: Text -> Text
streamDigest = sha256Hex . Text.Encoding.encodeUtf8

renderValidationRecordError :: ValidationRecordError -> Text
renderValidationRecordError err =
  case err of
    RecordMalformed detail -> "malformed validation record: " <> detail
    RecordNonCanonical -> "validation record is not in canonical form"
    RecordUnsupported detail -> "unsupported validation record " <> detail
    RecordInconsistent detail -> "inconsistent validation record: " <> detail

-- | Lower-case hexadecimal SHA-256 of the input bytes.
sha256Hex :: ByteString -> Text
sha256Hex = hexBytes . SHA256.hash

-- | Lower-case hexadecimal rendering of raw bytes, such as a digest.
hexBytes :: ByteString -> Text
hexBytes = Text.pack . concatMap hexOctet . ByteString.unpack
 where
  hexOctet :: Word8 -> String
  hexOctet byte =
    [ intToDigit (fromIntegral byte `div` 16)
    , intToDigit (fromIntegral byte `mod` 16)
    ]

isCanonicalSha256 :: Text -> Bool
isCanonicalSha256 value =
  Text.length value == 64
    && Text.all (`elem` ("0123456789abcdef" :: String)) value

-- | Write one record candidate into @directory@ under its
-- @<gate>.<substrate>.json@ name. The file is created beside its destination and
-- renamed into place, so a reader never observes a partial record, and it is
-- world-readable because a person has to copy it out of a container-owned tree.
writeValidationRecordAtomic
  :: FilePath
  -> ValidationRecord
  -> IO (Either Text FilePath)
writeValidationRecordAtomic directory record = do
  written <- tryIO $ do
    createDirectoryIfMissing True directory
    (temporaryPath, handle) <- openBinaryTempFile directory (fileName <> ".tmp")
    let cleanup = do
          _ <- tryIO (hClose handle)
          _ <- tryIO (removeFile temporaryPath)
          pure ()
    ( ByteString.hPut handle (renderValidationRecord record)
        >> hFlush handle
        >> hClose handle
        >> setFileMode temporaryPath 0o644
        >> renameFile temporaryPath target
      )
      `onException` cleanup
  pure $ case written of
    Left exception ->
      Left ("could not write " <> Text.pack target <> ": " <> Text.pack (show exception))
    Right () -> Right target
 where
  fileName = validationRecordFileName (recordGate record) (recordSubstrate record)
  target = directory </> fileName

tryIO :: IO value -> IO (Either IOException value)
tryIO = try
