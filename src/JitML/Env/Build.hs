module JitML.Env.Build
  ( GlobalFlags (..)
  , buildEnv
  , defaultGlobalFlags
  )
where

import Data.Maybe (fromMaybe)
import Path.IO (resolveDir')
import System.Environment (lookupEnv)
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
  cacheDir <- resolveDir' =<< resolvePath (globalCacheDir flags) "JITML_BUILD_DIR" ".build"
  dataDir <- resolveDir' =<< resolvePath (globalDataDir flags) "JITML_DATA_DIR" ".data"
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

resolvePath :: Maybe FilePath -> String -> FilePath -> IO FilePath
resolvePath cliValue envName defaultValue =
  case cliValue of
    Just path -> pure path
    Nothing -> do
      envValue <- lookupEnv envName
      pure (fromMaybe defaultValue envValue)

resolveOutputFormat :: Maybe OutputFormat -> IO OutputFormat
resolveOutputFormat (Just format) = pure format
resolveOutputFormat Nothing = do
  terminal <- hIsTerminalDevice stdout
  pure $
    if terminal
      then OutputTable
      else OutputPlain
