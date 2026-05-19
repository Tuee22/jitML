module JitML.Sub.Subprocess
  ( Subprocess (..)
  , subprocess
  , subprocessWithStdin
  )
where

import Data.Text (Text)

data Subprocess = Subprocess
  { subprocessPath :: FilePath
  , subprocessArguments :: [Text]
  , subprocessWorkingDirectory :: Maybe FilePath
  , subprocessStdin :: Maybe Text
  -- ^ Optional stdin payload. The typed boundary's `runStreaming` /
  -- `capture` feed the bytes verbatim when present. Used by, e.g.,
  -- `kubectl apply -f -` to thread YAML into the child process without
  -- shelling out.
  }
  deriving stock (Eq, Show)

subprocess :: FilePath -> [Text] -> Subprocess
subprocess path arguments =
  Subprocess
    { subprocessPath = path
    , subprocessArguments = arguments
    , subprocessWorkingDirectory = Nothing
    , subprocessStdin = Nothing
    }

-- | Same as `subprocess` but pipes the given `Text` payload as the child
-- process's stdin.
subprocessWithStdin :: FilePath -> [Text] -> Text -> Subprocess
subprocessWithStdin path arguments stdinPayload =
  (subprocess path arguments) {subprocessStdin = Just stdinPayload}
