{-# LANGUAGE OverloadedStrings #-}

module JitML.Sub.Outcome
  ( ObservedProcessFailure (..)
  , ObservedProcessOutcome (..)
  , ProcessAttemptFailure (..)
  , ProcessDuration (..)
  , ProcessFailure
  , ProcessOutcome (..)
  , ProcessTranscript (..)
  , fromProcessOutcome
  , mkProcessFailure
  , observedProcessFailureCommand
  , observedProcessFailureDuration
  , observedProcessFailureExitCode
  , observedProcessFailureStderr
  , observedProcessFailureStdout
  , observedProcessFailureWorkingDirectory
  , processFailureCommand
  , processFailureDuration
  , processFailureExitCode
  , processFailureStderr
  , processFailureStdout
  , processFailureTranscript
  , processFailureWorkingDirectory
  , processOutcome
  , renderObservedProcessFailure
  , renderObservedProcessOutcome
  , renderProcessAttemptFailure
  , renderProcessFailure
  , renderProcessOutcome
  )
where

import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)
import System.Exit (ExitCode (..))

-- | Elapsed duration measured with a monotonic clock.
newtype ProcessDuration = ProcessDuration
  { processDurationNanoseconds :: Word64
  }
  deriving stock (Eq, Ord, Show)

-- | The complete observable transcript shared by successful and failed
-- process executions. Exit status belongs to 'ProcessOutcome': success is
-- represented by 'ProcessSucceeded', while a failure carries an opaque,
-- non-zero status in 'ProcessFailure'.
data ProcessTranscript = ProcessTranscript
  { processTranscriptCommand :: Text
  , processTranscriptStdout :: Text
  , processTranscriptStderr :: Text
  , processTranscriptWorkingDirectory :: Maybe FilePath
  , processTranscriptDuration :: ProcessDuration
  }
  deriving stock (Eq, Show)

-- | A process failure whose constructor is deliberately hidden. The only
-- construction path rejects both 'ExitSuccess' and the degenerate
-- @ExitFailure 0@ representation, so every inhabitant carries a genuinely
-- non-zero exit status.
data ProcessFailure = ProcessFailure
  { processFailureExitCodeInternal :: ExitCode
  , processFailureTranscriptInternal :: ProcessTranscript
  }
  deriving stock (Eq, Show)

data ProcessOutcome
  = ProcessSucceeded ProcessTranscript
  | ProcessFailed ProcessFailure
  deriving stock (Eq, Show)

-- | A synchronous exception raised while attempting to execute or capture a
-- process.  This is deliberately not a 'ProcessFailure': no exit status was
-- observed, so inventing one would corrupt the process evidence.  'Nothing'
-- for either stream means capture did not make that stream available; 'Just'
-- of empty text means the stream was observed and was empty.
data ProcessAttemptFailure = ProcessAttemptFailure
  { processAttemptFailureCommand :: !Text
  , processAttemptFailureStdout :: !(Maybe Text)
  , processAttemptFailureStderr :: !(Maybe Text)
  , processAttemptFailureWorkingDirectory :: !(Maybe FilePath)
  , processAttemptFailureDuration :: !ProcessDuration
  , processAttemptFailureException :: !Text
  }
  deriving stock (Eq, Show)

-- | Lossless failure sum for an observed process attempt.  A real non-zero
-- process exit and a runner exception remain distinct, so callers never need
-- to synthesize an exit status for launch/capture failures.
data ObservedProcessFailure
  = ObservedProcessExitFailure !ProcessFailure
  | ObservedProcessAttemptFailure !ProcessAttemptFailure
  deriving stock (Eq, Show)

-- | Additive process-attempt boundary used by orchestration/reporting code.
-- The original 'ProcessOutcome' remains unchanged for existing callers.
data ObservedProcessOutcome
  = ObservedProcessSucceeded !ProcessTranscript
  | ObservedProcessFailed !ObservedProcessFailure
  deriving stock (Eq, Show)

mkProcessFailure :: ExitCode -> ProcessTranscript -> Maybe ProcessFailure
mkProcessFailure ExitSuccess _ = Nothing
mkProcessFailure (ExitFailure 0) _ = Nothing
mkProcessFailure exitCode@(ExitFailure _) transcript =
  Just
    ProcessFailure
      { processFailureExitCodeInternal = exitCode
      , processFailureTranscriptInternal = transcript
      }

processOutcome :: ExitCode -> ProcessTranscript -> ProcessOutcome
processOutcome exitCode transcript =
  case mkProcessFailure exitCode transcript of
    Nothing -> ProcessSucceeded transcript
    Just failure -> ProcessFailed failure

fromProcessOutcome :: ProcessOutcome -> ObservedProcessOutcome
fromProcessOutcome (ProcessSucceeded transcript) =
  ObservedProcessSucceeded transcript
fromProcessOutcome (ProcessFailed failure) =
  ObservedProcessFailed (ObservedProcessExitFailure failure)

processFailureExitCode :: ProcessFailure -> ExitCode
processFailureExitCode = processFailureExitCodeInternal

processFailureTranscript :: ProcessFailure -> ProcessTranscript
processFailureTranscript = processFailureTranscriptInternal

processFailureCommand :: ProcessFailure -> Text
processFailureCommand = processTranscriptCommand . processFailureTranscriptInternal

processFailureStdout :: ProcessFailure -> Text
processFailureStdout = processTranscriptStdout . processFailureTranscriptInternal

processFailureStderr :: ProcessFailure -> Text
processFailureStderr = processTranscriptStderr . processFailureTranscriptInternal

processFailureWorkingDirectory :: ProcessFailure -> Maybe FilePath
processFailureWorkingDirectory = processTranscriptWorkingDirectory . processFailureTranscriptInternal

processFailureDuration :: ProcessFailure -> ProcessDuration
processFailureDuration = processTranscriptDuration . processFailureTranscriptInternal

observedProcessFailureCommand :: ObservedProcessFailure -> Text
observedProcessFailureCommand (ObservedProcessExitFailure failure) =
  processFailureCommand failure
observedProcessFailureCommand (ObservedProcessAttemptFailure failure) =
  processAttemptFailureCommand failure

observedProcessFailureStdout :: ObservedProcessFailure -> Maybe Text
observedProcessFailureStdout (ObservedProcessExitFailure failure) =
  Just (processFailureStdout failure)
observedProcessFailureStdout (ObservedProcessAttemptFailure failure) =
  processAttemptFailureStdout failure

observedProcessFailureStderr :: ObservedProcessFailure -> Maybe Text
observedProcessFailureStderr (ObservedProcessExitFailure failure) =
  Just (processFailureStderr failure)
observedProcessFailureStderr (ObservedProcessAttemptFailure failure) =
  processAttemptFailureStderr failure

observedProcessFailureWorkingDirectory :: ObservedProcessFailure -> Maybe FilePath
observedProcessFailureWorkingDirectory (ObservedProcessExitFailure failure) =
  processFailureWorkingDirectory failure
observedProcessFailureWorkingDirectory (ObservedProcessAttemptFailure failure) =
  processAttemptFailureWorkingDirectory failure

observedProcessFailureDuration :: ObservedProcessFailure -> ProcessDuration
observedProcessFailureDuration (ObservedProcessExitFailure failure) =
  processFailureDuration failure
observedProcessFailureDuration (ObservedProcessAttemptFailure failure) =
  processAttemptFailureDuration failure

observedProcessFailureExitCode :: ObservedProcessFailure -> Maybe ExitCode
observedProcessFailureExitCode (ObservedProcessExitFailure failure) =
  Just (processFailureExitCode failure)
observedProcessFailureExitCode (ObservedProcessAttemptFailure _) = Nothing

renderProcessFailure :: ProcessFailure -> Text
renderProcessFailure failure =
  renderProcessTranscript (processFailureExitCode failure) (processFailureTranscript failure)

renderProcessAttemptFailure :: ProcessAttemptFailure -> Text
renderProcessAttemptFailure failure =
  Text.unlines
    [ "command: " <> processAttemptFailureCommand failure
    , "exit: (unavailable; no exit status observed)"
    , "working-directory: "
        <> maybe
          "(inherited)"
          Text.pack
          (processAttemptFailureWorkingDirectory failure)
    , "duration-nanoseconds: "
        <> Text.pack
          (show (processDurationNanoseconds (processAttemptFailureDuration failure)))
    , "stdout: " <> renderCapturedStream (processAttemptFailureStdout failure)
    , "stderr: " <> renderCapturedStream (processAttemptFailureStderr failure)
    , "exception: " <> processAttemptFailureException failure
    ]

renderObservedProcessFailure :: ObservedProcessFailure -> Text
renderObservedProcessFailure (ObservedProcessExitFailure failure) =
  renderProcessFailure failure
renderObservedProcessFailure (ObservedProcessAttemptFailure failure) =
  renderProcessAttemptFailure failure

renderProcessOutcome :: ProcessOutcome -> Text
renderProcessOutcome (ProcessSucceeded transcript) = renderProcessTranscript ExitSuccess transcript
renderProcessOutcome (ProcessFailed failure) = renderProcessFailure failure

renderObservedProcessOutcome :: ObservedProcessOutcome -> Text
renderObservedProcessOutcome (ObservedProcessSucceeded transcript) =
  renderProcessTranscript ExitSuccess transcript
renderObservedProcessOutcome (ObservedProcessFailed failure) =
  renderObservedProcessFailure failure

renderProcessTranscript :: ExitCode -> ProcessTranscript -> Text
renderProcessTranscript exitCode transcript =
  Text.unlines
    [ "command: " <> processTranscriptCommand transcript
    , "exit: " <> renderExitCode exitCode
    , "working-directory: "
        <> maybe "(inherited)" Text.pack (processTranscriptWorkingDirectory transcript)
    , "duration-nanoseconds: "
        <> Text.pack (show (processDurationNanoseconds (processTranscriptDuration transcript)))
    , "stdout: " <> emptyAsNone (processTranscriptStdout transcript)
    , "stderr: " <> emptyAsNone (processTranscriptStderr transcript)
    ]

renderExitCode :: ExitCode -> Text
renderExitCode ExitSuccess = "0"
renderExitCode (ExitFailure code) = Text.pack (show code)

emptyAsNone :: Text -> Text
emptyAsNone value
  | Text.null value = "(none)"
  | otherwise = value

renderCapturedStream :: Maybe Text -> Text
renderCapturedStream Nothing = "(unavailable; capture did not complete)"
renderCapturedStream (Just value) = emptyAsNone value
