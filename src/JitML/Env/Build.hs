module JitML.Env.Build
  ( GlobalFlags (..)
  , buildEnv
  , defaultGlobalFlags
  )
where

import Data.Maybe (fromMaybe)
import Path.IO (resolveDir')
import System.IO (hIsTerminalDevice, stdout)

import JitML.Env.Env (ColorMode (..), Env (..), MonotonicTime (..), OutputFormat (..))

data GlobalFlags = GlobalFlags
  { globalCacheDir :: Maybe FilePath
  , globalDataDir :: Maybe FilePath
  , globalFormat :: Maybe OutputFormat
  , globalColor :: ColorMode
  }
  deriving stock (Eq, Show)

defaultGlobalFlags :: GlobalFlags
defaultGlobalFlags =
  GlobalFlags
    { globalCacheDir = Nothing
    , globalDataDir = Nothing
    , globalFormat = Nothing
    , globalColor = ColorAuto
    }

buildEnv :: GlobalFlags -> IO Env
buildEnv flags = do
  cacheDir <- resolveDir' (fromMaybe ".build" (globalCacheDir flags))
  dataDir <- resolveDir' (fromMaybe ".data" (globalDataDir flags))
  outputFormat <- resolveOutputFormat (globalFormat flags)
  pure
    Env
      { envCacheDir = cacheDir
      , envDataDir = dataDir
      , envFormat = outputFormat
      , envColor = globalColor flags
      , envLogger = \_subprocess _exitCode _message -> pure ()
      , envClock = pure (MonotonicTime 0)
      }

resolveOutputFormat :: Maybe OutputFormat -> IO OutputFormat
resolveOutputFormat (Just format) = pure format
resolveOutputFormat Nothing = do
  terminal <- hIsTerminalDevice stdout
  pure $
    if terminal
      then OutputTable
      else OutputPlain
