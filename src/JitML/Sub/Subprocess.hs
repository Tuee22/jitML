module JitML.Sub.Subprocess
  ( Subprocess (..)
  , subprocess
  )
where

import Data.Text (Text)

data Subprocess = Subprocess
  { subprocessPath :: FilePath
  , subprocessArguments :: [Text]
  , subprocessEnvironment :: [(Text, Text)]
  , subprocessWorkingDirectory :: Maybe FilePath
  }
  deriving stock (Eq, Show)

subprocess :: FilePath -> [Text] -> Subprocess
subprocess path arguments =
  Subprocess
    { subprocessPath = path
    , subprocessArguments = arguments
    , subprocessEnvironment = []
    , subprocessWorkingDirectory = Nothing
    }
