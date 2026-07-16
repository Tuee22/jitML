module JitML.Sub.Stream
  ( SubprocessEnv (..)
  , capture
  , defaultSubprocessEnv
  , observeProcessAction
  , runStreaming
  , runStreamingObserved
  , startDetached
  )
where

import Control.Exception (evaluate)
import Control.Exception.Safe (displayException, tryAny)
import Control.Monad (void)
import Data.ByteString.Lazy (ByteString)
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Text.Encoding.Error (lenientDecode)
import GHC.Clock (getMonotonicTimeNSec)
import System.FilePath ((</>))
import System.IO (IOMode (WriteMode), hFlush, withBinaryFile)
import System.IO.Temp (withSystemTempDirectory)
import System.Process.Typed qualified as Typed

import JitML.Sub.Outcome
  ( ObservedProcessFailure (..)
  , ObservedProcessOutcome (..)
  , ProcessAttemptFailure (..)
  , ProcessDuration (..)
  , ProcessOutcome
  , ProcessTranscript (..)
  , fromProcessOutcome
  , processOutcome
  )
import JitML.Sub.Render (renderSubprocess)
import JitML.Sub.Subprocess (Subprocess (..))

data SubprocessEnv = SubprocessEnv
  deriving stock (Eq, Show)

defaultSubprocessEnv :: SubprocessEnv
defaultSubprocessEnv = SubprocessEnv

runStreaming :: SubprocessEnv -> Subprocess -> IO ProcessOutcome
runStreaming = capture

-- | Observe one process action without changing the established
-- 'ProcessOutcome' API.  Synchronous runner exceptions become explicit
-- attempt failures with no fabricated exit status.  'tryAny' from
-- @safe-exceptions@ rethrows asynchronous exceptions, preserving cancellation
-- identity for the surrounding bracket.
observeProcessAction
  :: Subprocess
  -> IO ProcessOutcome
  -> IO ObservedProcessOutcome
observeProcessAction subprocessValue action = do
  startedAt <- getMonotonicTimeNSec
  attempted <- tryAny action
  finishedAt <- getMonotonicTimeNSec
  pure $
    case attempted of
      Right outcome -> fromProcessOutcome outcome
      Left exception ->
        ObservedProcessFailed
          ( ObservedProcessAttemptFailure
              ProcessAttemptFailure
                { processAttemptFailureCommand = renderSubprocess subprocessValue
                , processAttemptFailureStdout = Nothing
                , processAttemptFailureStderr = Nothing
                , processAttemptFailureWorkingDirectory =
                    subprocessWorkingDirectory subprocessValue
                , processAttemptFailureDuration =
                    ProcessDuration (finishedAt - startedAt)
                , processAttemptFailureException =
                    Text.pack (displayException exception)
                }
          )

runStreamingObserved
  :: SubprocessEnv
  -> Subprocess
  -> IO ObservedProcessOutcome
runStreamingObserved env subprocessValue =
  observeProcessAction
    subprocessValue
    (runStreaming env subprocessValue)

-- | Start a long-lived process fully detached from the caller's standard
-- streams. The child's stdin/stdout/stderr are wired to @/dev/null@ rather than
-- inherited, so a process that outlives the caller cannot hold a parent's
-- captured output pipe open. Without this, starting a long-lived helper from
-- inside an output-captured context (a @cabal test@ run, the daemon) would
-- deadlock the parent's stream reader, which never sees EOF while the detached
-- process holds the inherited pipe.
startDetached :: SubprocessEnv -> Subprocess -> IO ()
startDetached _env subprocessValue =
  void
    ( Typed.startProcess
        ( Typed.setStdin Typed.nullStream $
            Typed.setStdout Typed.nullStream $
              Typed.setStderr Typed.nullStream $
                baseProcessConfig subprocessValue
        )
    )

capture :: SubprocessEnv -> Subprocess -> IO ProcessOutcome
capture _env subprocessValue =
  withSystemTempDirectory "jitml-subprocess" $ \dir -> do
    let stdoutPath = dir </> "stdout"
        stderrPath = dir </> "stderr"
    startedAt <- getMonotonicTimeNSec
    exitCode <-
      withBinaryFile stdoutPath WriteMode $ \stdoutHandle ->
        withBinaryFile stderrPath WriteMode $ \stderrHandle -> do
          code <-
            Typed.runProcess
              ( Typed.setStdout (Typed.useHandleOpen stdoutHandle) $
                  Typed.setStderr (Typed.useHandleOpen stderrHandle) $
                    applyStdin (baseProcessConfig subprocessValue)
              )
          hFlush stdoutHandle
          hFlush stderrHandle
          pure code
    finishedAt <- getMonotonicTimeNSec
    stdoutBytes <- LazyByteString.readFile stdoutPath
    stderrBytes <- LazyByteString.readFile stderrPath
    _ <- evaluate (LazyByteString.length stdoutBytes)
    _ <- evaluate (LazyByteString.length stderrBytes)
    let transcript =
          ProcessTranscript
            { processTranscriptCommand = renderSubprocess subprocessValue
            , processTranscriptStdout = decodeOutput stdoutBytes
            , processTranscriptStderr = decodeOutput stderrBytes
            , processTranscriptWorkingDirectory = subprocessWorkingDirectory subprocessValue
            , processTranscriptDuration = ProcessDuration (finishedAt - startedAt)
            }
    pure (processOutcome exitCode transcript)
 where
  decodeOutput :: ByteString -> Text
  decodeOutput =
    Text.Encoding.decodeUtf8With lenientDecode . LazyByteString.toStrict

  applyStdin config =
    case subprocessStdin subprocessValue of
      Nothing -> config
      Just payload ->
        Typed.setStdin
          (Typed.byteStringInput (LazyByteString.fromStrict (Text.Encoding.encodeUtf8 payload)))
          config

baseProcessConfig :: Subprocess -> Typed.ProcessConfig () () ()
baseProcessConfig subprocessValue =
  applyWorkingDirectory $
    Typed.proc
      (subprocessPath subprocessValue)
      (fmap showText (subprocessArguments subprocessValue))
 where
  applyWorkingDirectory config =
    maybe config (`Typed.setWorkingDir` config) (subprocessWorkingDirectory subprocessValue)

showText :: Text -> String
showText = showStringValue

showStringValue :: Text -> String
showStringValue = Text.unpack
