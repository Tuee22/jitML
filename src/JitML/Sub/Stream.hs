module JitML.Sub.Stream
  ( SubprocessEnv (..)
  , capture
  , defaultSubprocessEnv
  , runStreaming
  , startDetached
  , withPipedProcess
  )
where

import Control.Monad (void)
import Data.ByteString.Lazy (ByteString)
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Text.Encoding.Error (lenientDecode)
import System.Exit (ExitCode)
import System.IO (Handle)
import System.Process.Typed qualified as Typed

import JitML.Sub.Subprocess (Subprocess (..))

data SubprocessEnv = SubprocessEnv
  deriving stock (Eq, Show)

defaultSubprocessEnv :: SubprocessEnv
defaultSubprocessEnv = SubprocessEnv

runStreaming :: SubprocessEnv -> Subprocess -> IO (ExitCode, Text, Text)
runStreaming env subprocessValue = do
  (exitCode, stdoutBytes, stderrBytes) <- capture env subprocessValue
  pure
    ( exitCode
    , Text.Encoding.decodeUtf8With lenientDecode (LazyByteString.toStrict stdoutBytes)
    , Text.Encoding.decodeUtf8With lenientDecode (LazyByteString.toStrict stderrBytes)
    )

-- | Start a long-lived process fully detached from the caller's standard
-- streams. The child's stdin/stdout/stderr are wired to @/dev/null@ rather than
-- inherited, so a process that outlives the caller (e.g. @tart run@, which keeps
-- the build VM up) cannot hold a parent's captured output pipe open. Without
-- this, starting the VM from inside an output-captured context (a @cabal test@
-- run, the daemon) would deadlock the parent's stream reader, which never sees
-- EOF while the detached process holds the inherited pipe.
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

capture :: SubprocessEnv -> Subprocess -> IO (ExitCode, ByteString, ByteString)
capture _env subprocessValue =
  case subprocessStdin subprocessValue of
    Nothing ->
      Typed.readProcess (baseProcessConfig subprocessValue)
    Just payload ->
      Typed.readProcess
        ( Typed.setStdin
            (Typed.byteStringInput (LazyByteString.fromStrict (Text.Encoding.encodeUtf8 payload)))
            (baseProcessConfig subprocessValue)
        )

withPipedProcess :: Subprocess -> (Handle -> Handle -> IO a) -> IO a
withPipedProcess subprocessValue action =
  Typed.withProcessWait
    ( Typed.setStdin Typed.createPipe $
        Typed.setStdout Typed.createPipe $
          Typed.setStderr Typed.nullStream $
            baseProcessConfig subprocessValue
    )
    ( \processHandle ->
        action
          (Typed.getStdin processHandle)
          (Typed.getStdout processHandle)
    )

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
