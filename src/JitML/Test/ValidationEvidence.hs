{-# LANGUAGE OverloadedStrings #-}

-- | Phase 288 - turn a @jitml test@ invocation journal into validation records.
--
-- Every planned invocation of a substrate-flagged run becomes one
-- 'ValidationRecord', written next to the lane-journal candidate under
-- 'candidateValidationDirectory'. A person copies the records they want to keep
-- into @DEVELOPMENT_PLAN/attestations/validation/@ and commits them; nothing here
-- stages, commits, or reads that directory back.
--
-- A record is honest only if the tree did not change under the run, so the source
-- stamp is taken before the first invocation and again after the last; when the
-- two differ no record is written, and the reason goes to standard error. Writing
-- records never changes the outcome of the test command itself: the exit status
-- and report card are exactly what they were without it.
--
-- A record is also honest only if its command shows what ran. A @TASTY_*@
-- environment variable that selects a subset of the tests or loosens how they are
-- run is invisible in the recorded command, so no record is written under one
-- ('runAlteringEnvironment').
module JitML.Test.ValidationEvidence
  ( ValidationBaseline (..)
  , captureValidationBaseline
  , invocationRecords
  , runAlteringEnvironment
  , writeValidationRecords
  , writeValidationRecordsWith
  )
where

import Control.Exception (IOException, evaluate, try)
import Control.Monad (forM_)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString.Lazy qualified as LazyByteString
import Data.List (isPrefixOf, sort)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import System.Environment (getEnvironment, getExecutablePath)
import System.Exit (ExitCode (..))

import JitML.CLI.Output (writeErrorLineIO)
import JitML.Product.SourceDigest (SourceStamp (..), computeSourceStamp)
import JitML.Product.ValidationRecord
  ( FailedEvidence (..)
  , RecordEvidence (..)
  , ValidationRecord
  , candidateValidationDirectory
  , hexBytes
  , mkValidationRecord
  , parseValidationGate
  , renderValidationRecordError
  , sha256Hex
  , writeValidationRecordAtomic
  )
import JitML.Sub.Outcome
  ( ObservedProcessFailure (..)
  , ProcessAttemptFailure (..)
  , ProcessTranscript (..)
  , observedProcessFailureCommand
  , observedProcessFailureExitCode
  , observedProcessFailureStderr
  , observedProcessFailureStdout
  )
import JitML.Substrate (Substrate)
import JitML.Test.Report
  ( InvocationJournal
  , InvocationRecord
  , InvocationResult (..)
  , blockedByFailure
  , blockedByStanza
  , invocationCommand
  , invocationJournalEntries
  , invocationResult
  , invocationStanza
  , refinementBlockerDetail
  , refinementBlockerName
  , refinementBlockerStanza
  )

-- | What is fixed before the first invocation runs.
data ValidationBaseline = ValidationBaseline
  { baselineSubstrate :: !Substrate
  , baselineExecutableSha256 :: !Text
  , baselineSource :: !SourceStamp
  }

-- | Capture the executable digest and source stamp before a run. 'Nothing' when
-- the run selected no substrate: an unflagged run is not a lane run and yields no
-- evidence.
captureValidationBaseline :: Maybe Substrate -> IO (Maybe (Either Text ValidationBaseline))
captureValidationBaseline Nothing = pure Nothing
captureValidationBaseline (Just substrate) = do
  environment <- getEnvironment
  case runAlteringEnvironment environment of
    [] -> do
      executable <- executableSha256
      source <- computeSourceStamp
      pure . Just $ do
        executableSha <- executable
        stamp <- source
        Right
          ValidationBaseline
            { baselineSubstrate = substrate
            , baselineExecutableSha256 = executableSha
            , baselineSource = stamp
            }
    names ->
      pure . Just . Left $
        "the environment sets "
          <> Text.intercalate ", " names
          <> ", which changes which tests run or how they are judged in a way the recorded command does not show"

-- | The names of the environment variables that make a run something other than
-- the standing invocation its recorded command claims: any non-empty @TASTY_*@
-- variable except the presentational ones. @TASTY_PATTERN@ drops tests,
-- @TASTY_TIMEOUT@ and the @TASTY_QUICKCHECK_*@ variables weaken them, and none of
-- that appears in the command. Sorted, so the diagnostic is stable.
runAlteringEnvironment :: [(String, String)] -> [Text]
runAlteringEnvironment environment =
  sort
    [ Text.pack name
    | (name, value) <- environment
    , "TASTY_" `isPrefixOf` name
    , name `notElem` presentationalTastyVariables
    , not (null value)
    ]
 where
  presentationalTastyVariables =
    ["TASTY_ANSI_TRICKS", "TASTY_COLOR", "TASTY_HIDE_SUCCESSES", "TASTY_NUM_THREADS"]

-- | Write one record per journal entry, unless the tree changed during the run.
-- Anything that keeps a record from being written is reported on standard error
-- and never changes the outcome of the test command.
writeValidationRecords :: Maybe (Either Text ValidationBaseline) -> InvocationJournal -> IO ()
writeValidationRecords =
  writeValidationRecordsWith
    writeErrorLineIO
    computeSourceStamp
    candidateValidationDirectory

-- | 'writeValidationRecords' with the diagnostic sink, the post-run source stamp,
-- and the destination directory supplied, so a test can drive the tree-changed
-- refusal and the write without touching the working directory or standard error.
writeValidationRecordsWith
  :: (Text -> IO ())
  -> IO (Either Text SourceStamp)
  -> FilePath
  -> Maybe (Either Text ValidationBaseline)
  -> InvocationJournal
  -> IO ()
writeValidationRecordsWith _ _ _ Nothing _ = pure ()
writeValidationRecordsWith report _ _ (Just (Left reason)) _ =
  report ("validation records not written: " <> reason)
writeValidationRecordsWith report currentStamp directory (Just (Right baseline)) journal = do
  after <- currentStamp
  case after of
    Left reason ->
      report ("validation records not written: " <> reason)
    Right stamp
      | stamp /= baselineSource baseline ->
          report "validation records not written: the source tree changed while the gates ran"
      | otherwise ->
          forM_ (invocationRecords baseline journal) $ \case
            Left reason -> report ("validation record skipped: " <> reason)
            Right record -> do
              written <- writeValidationRecordAtomic directory record
              case written of
                Left reason -> report ("validation record not written: " <> reason)
                Right _path -> pure ()

-- | The records a journal yields. An entry whose stanza is not a validation gate
-- is skipped without a record; an entry the record constructor refuses is
-- reported with the reason.
invocationRecords
  :: ValidationBaseline
  -> InvocationJournal
  -> [Either Text ValidationRecord]
invocationRecords baseline journal =
  [ recordFor gate entry
  | entry <- invocationJournalEntries journal
  , Just gate <- [parseValidationGate (invocationStanza entry)]
  ]
 where
  recordFor gate entry =
    case mkValidationRecord
      gate
      (baselineSubstrate baseline)
      (invocationCommand entry)
      (baselineExecutableSha256 baseline)
      (baselineSource baseline)
      (evidenceFor entry) of
      Left err ->
        Left (invocationStanza entry <> ": " <> renderValidationRecordError err)
      Right record -> Right record

evidenceFor :: InvocationRecord -> RecordEvidence
evidenceFor entry =
  case invocationResult entry of
    Passed transcript ->
      EvidencePassed
        (streamDigest (processTranscriptStdout transcript))
        (streamDigest (processTranscriptStderr transcript))
    Failed failure ->
      EvidenceFailed
        FailedEvidence
          { failedExitCode = exitNumber <$> observedProcessFailureExitCode failure
          , failedStdout = observedProcessFailureStdout failure
          , failedStderr = observedProcessFailureStderr failure
          , failedException = attemptException failure
          }
    NotRun blocker ->
      EvidenceNotRun
        (blockedByStanza blocker)
        (observedProcessFailureCommand (blockedByFailure blocker))
    NotRunAfterRefinement blocker ->
      EvidenceNotRun
        (refinementBlockerStanza blocker)
        (refinementBlockerName blocker <> ": " <> refinementBlockerDetail blocker)
 where
  exitNumber ExitSuccess = 0
  exitNumber (ExitFailure code) = code
  attemptException failure =
    case failure of
      ObservedProcessExitFailure _ -> Nothing
      ObservedProcessAttemptFailure attempt ->
        Just
          ( nonEmptyOr
              "the runner raised without exception text"
              (Text.strip (processAttemptFailureException attempt))
          )
  nonEmptyOr fallback text
    | Text.null text = fallback
    | otherwise = text

streamDigest :: Text -> Text
streamDigest = sha256Hex . Text.Encoding.encodeUtf8

-- | The SHA-256 of the running executable, streamed so a large binary is never
-- held in memory.
executableSha256 :: IO (Either Text Text)
executableSha256 = do
  path <- getExecutablePath
  hashed <- try (LazyByteString.readFile path >>= evaluate . SHA256.hashlazy)
  pure $ case hashed of
    Left exception ->
      Left ("could not hash the running executable: " <> Text.pack (show (exception :: IOException)))
    Right digest -> Right (hexBytes digest)
