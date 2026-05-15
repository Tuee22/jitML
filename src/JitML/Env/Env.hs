module JitML.Env.Env
  ( App
  , ColorMode (..)
  , Env (..)
  , MonotonicTime (..)
  , OutputFormat (..)
  )
where

import Control.Monad.Reader (ReaderT)
import Data.Text (Text)
import Path (Abs, Dir, Path)
import System.Exit (ExitCode)

import JitML.Sub.Subprocess (Subprocess)

type App = ReaderT Env IO

data Env = Env
  { envCacheDir :: Path Abs Dir
  , envDataDir :: Path Abs Dir
  , envFormat :: OutputFormat
  , envColor :: ColorMode
  , envLogger :: Subprocess -> ExitCode -> Text -> IO ()
  , envClock :: IO MonotonicTime
  }

data OutputFormat
  = OutputPlain
  | OutputTable
  | OutputJson
  deriving stock (Eq, Show)

data ColorMode
  = ColorAuto
  | ColorNever
  | ColorAlways
  deriving stock (Eq, Show)

newtype MonotonicTime = MonotonicTime
  { unMonotonicTime :: Integer
  }
  deriving stock (Eq, Show)
