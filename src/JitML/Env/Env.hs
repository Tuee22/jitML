module JitML.Env.Env
  ( App
  , ColorMode (..)
  , Env (..)
  , MonotonicTime (..)
  , OutputFormat (..)
  )
where

import Control.Monad.Reader (ReaderT)
import Path (Abs, Dir, Path)

import JitML.Sub.Outcome (ProcessOutcome)

type App = ReaderT Env IO

data Env = Env
  { envCacheDir :: Path Abs Dir
  , envDataDir :: Path Abs Dir
  , envFormat :: OutputFormat
  , envColor :: ColorMode
  , envLogger :: ProcessOutcome -> IO ()
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
