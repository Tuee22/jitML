{-# LANGUAGE OverloadedStrings #-}

-- | Structured runner for line-oriented child protocols. Raw process handles
-- never escape this package-internal boundary: writes and reads are serialized,
-- every stdout byte returned by a line read is tee'd into the final transcript,
-- and stderr is captured by a file-backed sink so a noisy child cannot fill a
-- pipe while the protocol action is waiting.
module JitML.Sub.Piped
  ( PipedSession
  , PipedSessionError (..)
  , PipedActionException (..)
  , closePipedStdin
  , readPipedStdoutLine
  , runPipedProcess
  , writePipedStdin
  )
where

import Control.Concurrent.MVar (MVar, modifyMVar, modifyMVar_, newMVar)
import Control.Exception
  ( Exception
  , IOException
  , SomeAsyncException
  , SomeException
  , displayException
  , fromException
  , mask
  , throwIO
  , try
  )
import Control.Monad (void)
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Text.Encoding.Error (lenientDecode)
import Data.Word (Word8)
import GHC.Clock (getMonotonicTimeNSec)
import System.FilePath ((</>))
import System.IO (Handle, IOMode (WriteMode), hClose, hFlush, withBinaryFile)
import System.IO.Temp (withSystemTempDirectory)
import System.Process.Typed qualified as Typed
import System.Timeout (timeout)

import JitML.Sub.Outcome
  ( ProcessDuration (..)
  , ProcessOutcome
  , ProcessTranscript (..)
  , processOutcome
  )
import JitML.Sub.Render (renderSubprocess)
import JitML.Sub.Subprocess (Subprocess (..))

data PipedSessionError
  = PipedStdinClosed
  | PipedWriteFailed Text
  deriving stock (Eq, Show)

-- | A synchronous protocol-action failure paired with the complete outcome of
-- the child after stdin closure, stdout draining, and bounded forced cleanup.
-- Async exceptions retain their original identity and are rethrown directly.
data PipedActionException = PipedActionException
  { pipedActionExceptionDetail :: Text
  , pipedActionExceptionOutcome :: ProcessOutcome
  }
  deriving stock (Show)

instance Exception PipedActionException

data PipedActionCompletion result
  = PipedActionSucceeded result
  | PipedActionThrew SomeException

data StdinState
  = StdinOpen Handle
  | StdinClosed

data StdoutState = StdoutState
  { stdoutBuffered :: ByteString
  , stdoutExhausted :: Bool
  }

data PipedSession = PipedSession
  { pipedStdinState :: MVar StdinState
  , pipedStdoutHandle :: Handle
  , pipedStdoutState :: MVar StdoutState
  , pipedStdoutTranscriptHandle :: Handle
  }

-- | Write one protocol command. The session lock makes concurrent callers
-- serialize complete writes and flushes before the next writer proceeds.
writePipedStdin :: PipedSession -> ByteString -> IO (Either PipedSessionError ())
writePipedStdin session bytes =
  modifyMVar (pipedStdinState session) $ \state ->
    case state of
      StdinClosed -> pure (StdinClosed, Left PipedStdinClosed)
      StdinOpen handle -> do
        writeResult <- tryIOException (ByteString.hPut handle bytes >> hFlush handle)
        case writeResult of
          Left exception -> do
            -- Mark the typed-process-owned handle closed here as well as in
            -- our logical state. Otherwise typed-process closes the same
            -- broken pipe during scope cleanup and can replace the typed write
            -- result with an escaping @hClose: Broken pipe@ exception.
            _closeResult <- tryIOException (hClose handle)
            pure
              ( StdinClosed
              , Left (PipedWriteFailed (Text.pack (displayException exception)))
              )
          Right () -> pure (state, Right ())

-- | Close child stdin exactly once. Subsequent closes are harmless; writes
-- after the first close return 'PipedStdinClosed'.
closePipedStdin :: PipedSession -> IO ()
closePipedStdin session =
  modifyMVar_ (pipedStdinState session) closeState
 where
  closeState StdinClosed = pure StdinClosed
  closeState (StdinOpen handle) = do
    _closeResult <- tryIOException (hClose handle)
    pure StdinClosed

-- | Read one exact NDJSON line, including its newline terminator. A final
-- unterminated fragment is returned as-is. Every returned byte is written to
-- the stdout transcript before the caller observes it.
readPipedStdoutLine :: PipedSession -> IO (Maybe ByteString)
readPipedStdoutLine session =
  modifyMVar (pipedStdoutState session) $ \state -> do
    (nextState, maybeLine) <- readLine state
    case maybeLine of
      Nothing -> pure ()
      Just line -> do
        ByteString.hPut (pipedStdoutTranscriptHandle session) line
        hFlush (pipedStdoutTranscriptHandle session)
    pure (nextState, maybeLine)
 where
  readLine state
    | stdoutExhausted state = pure (state, Nothing)
    | otherwise = gather (stdoutBuffered state)

  gather buffered =
    case ByteString.elemIndex newlineByte buffered of
      Just newlineIndex ->
        let lineLength = newlineIndex + 1
         in pure
              ( StdoutState
                  { stdoutBuffered = ByteString.drop lineLength buffered
                  , stdoutExhausted = False
                  }
              , Just (ByteString.take lineLength buffered)
              )
      Nothing -> do
        chunk <- ByteString.hGetSome (pipedStdoutHandle session) stdoutChunkSize
        if ByteString.null chunk
          then
            pure
              ( StdoutState
                  { stdoutBuffered = ByteString.empty
                  , stdoutExhausted = True
                  }
              , if ByteString.null buffered then Nothing else Just buffered
              )
          else gather (buffered <> chunk)

-- | Run a structured pipe action, close stdin, drain and transcript any stdout
-- the action did not consume, wait for child exit, and return the action value
-- independently from the process outcome.
runPipedProcess
  :: Subprocess
  -> (PipedSession -> IO actionResult)
  -> IO (actionResult, ProcessOutcome)
runPipedProcess subprocessValue action =
  withSystemTempDirectory "jitml-piped-process" $ \directory -> do
    let stdoutPath = directory </> "stdout"
        stderrPath = directory </> "stderr"
    (actionCompletion, exitCode, startedAt, finishedAt) <-
      withBinaryFile stdoutPath WriteMode $ \stdoutTranscriptHandle ->
        withBinaryFile stderrPath WriteMode $ \stderrHandle -> do
          startedAt <- getMonotonicTimeNSec
          (actionCompletion, exitCode) <-
            Typed.withProcessTerm
              (pipedProcessConfig subprocessValue stderrHandle)
              (runAction stdoutTranscriptHandle)
          finishedAt <- getMonotonicTimeNSec
          hFlush stdoutTranscriptHandle
          hFlush stderrHandle
          pure (actionCompletion, exitCode, startedAt, finishedAt)
    stdoutBytes <- ByteString.readFile stdoutPath
    stderrBytes <- ByteString.readFile stderrPath
    let transcript =
          ProcessTranscript
            { processTranscriptCommand = renderSubprocess subprocessValue
            , processTranscriptStdout = decodeOutput stdoutBytes
            , processTranscriptStderr = decodeOutput stderrBytes
            , processTranscriptWorkingDirectory = subprocessWorkingDirectory subprocessValue
            , processTranscriptDuration = ProcessDuration (finishedAt - startedAt)
            }
        outcome = processOutcome exitCode transcript
    case actionCompletion of
      PipedActionSucceeded actionResult -> pure (actionResult, outcome)
      PipedActionThrew exception
        | Just asyncException <- fromException exception ->
            throwIO (asyncException :: SomeAsyncException)
        | otherwise ->
            throwIO
              PipedActionException
                { pipedActionExceptionDetail = Text.pack (displayException exception)
                , pipedActionExceptionOutcome = outcome
                }
 where
  runAction stdoutTranscriptHandle processHandle = do
    session <-
      PipedSession
        <$> newMVar (StdinOpen (Typed.getStdin processHandle))
        <*> pure (Typed.getStdout processHandle)
        <*> newMVar
          StdoutState
            { stdoutBuffered = ByteString.empty
            , stdoutExhausted = False
            }
        <*> pure stdoutTranscriptHandle
    writeInitialStdin session
    mask $ \restore -> do
      actionResult <- tryAny (restore (action session))
      case actionResult of
        Right result -> do
          closePipedStdin session
          completion <- tryAny (drainPipedStdout session >> Typed.waitExitCode processHandle)
          case completion of
            Right exitCode -> pure (PipedActionSucceeded result, exitCode)
            Left exception -> do
              exitCode <- stopAndWait processHandle
              pure (PipedActionThrew exception, exitCode)
        Left exception -> do
          closePipedStdin session
          completion <-
            timeout pipedExceptionDrainTimeoutMicroseconds $ do
              tryAny (drainPipedStdout session >> Typed.waitExitCode processHandle)
          exitCode <-
            case completion of
              Just (Right completedExitCode) -> pure completedExitCode
              Just (Left _cleanupException) -> stopAndWait processHandle
              Nothing -> stopAndWait processHandle
          pure (PipedActionThrew exception, exitCode)

  stopAndWait processHandle = do
    _stopResult <- tryAny (Typed.stopProcess processHandle)
    Typed.waitExitCode processHandle

  writeInitialStdin session =
    case subprocessStdin subprocessValue of
      Nothing -> pure ()
      Just payload ->
        void
          ( writePipedStdin
              session
              (Text.Encoding.encodeUtf8 payload)
          )

pipedProcessConfig :: Subprocess -> Handle -> Typed.ProcessConfig Handle Handle ()
pipedProcessConfig subprocessValue stderrHandle =
  Typed.setStdin Typed.createPipe $
    Typed.setStdout Typed.createPipe $
      Typed.setStderr (Typed.useHandleOpen stderrHandle) $
        applyWorkingDirectory $
          Typed.proc
            (subprocessPath subprocessValue)
            (fmap Text.unpack (subprocessArguments subprocessValue))
 where
  applyWorkingDirectory config =
    maybe config (`Typed.setWorkingDir` config) (subprocessWorkingDirectory subprocessValue)

drainPipedStdout :: PipedSession -> IO ()
drainPipedStdout session = do
  maybeLine <- readPipedStdoutLine session
  case maybeLine of
    Nothing -> pure ()
    Just _line -> drainPipedStdout session

decodeOutput :: ByteString -> Text
decodeOutput = Text.Encoding.decodeUtf8With lenientDecode

newlineByte :: Word8
newlineByte = 10

stdoutChunkSize :: Int
stdoutChunkSize = 32 * 1024

pipedExceptionDrainTimeoutMicroseconds :: Int
pipedExceptionDrainTimeoutMicroseconds = 30 * 1000 * 1000

tryAny :: IO value -> IO (Either SomeException value)
tryAny = try

tryIOException :: IO value -> IO (Either IOException value)
tryIOException = try
