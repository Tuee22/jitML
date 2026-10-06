{-# LANGUAGE OverloadedStrings #-}

module JitML.Sub.Subprocess
  ( Subprocess (..)
  , niceArguments
  , niceExecutable
  , subprocess
  , subprocessWithStdin
  , underNice
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

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

-- | The executable that lowers a process's CPU priority.
niceExecutable :: FilePath
niceExecutable = "/usr/bin/nice"

-- | The leading arguments 'niceExecutable' is given.
niceArguments :: [Text]
niceArguments = ["-n", "10"]

-- | Run a subprocess under 'niceExecutable', keeping its working directory and
-- stdin. @jitml test --live@ puts cabal under it, and the rendering of
-- 'niceExecutable' and 'niceArguments' is how a recorded validation command is
-- recognised as a live run (see "JitML.Product.StatusLoader").
underNice :: Subprocess -> Subprocess
underNice command =
  ( subprocess
      niceExecutable
      (niceArguments <> (Text.pack (subprocessPath command) : subprocessArguments command))
  )
    { subprocessWorkingDirectory = subprocessWorkingDirectory command
    , subprocessStdin = subprocessStdin command
    }
