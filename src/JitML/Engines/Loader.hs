{-# LANGUAGE OverloadedStrings #-}

module JitML.Engines.Loader
  ( KernelArtifact (..)
  , KernelArtifactError (..)
  , ensureKernelArtifact
  , loadKernelLibrary
  , renderKernelArtifactError
  , withKernelSymbol
  )
where

import Control.Concurrent.MVar (MVar, modifyMVar, newMVar)
import Control.Exception.Safe (displayException, tryAny)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import Foreign.Ptr (FunPtr)
import System.Directory
  ( createDirectoryIfMissing
  , doesFileExist
  , renameFile
  )
import System.FilePath (takeDirectory)
import System.IO.Unsafe (unsafePerformIO)
import System.Posix.DynamicLinker (DL, RTLDFlags (RTLD_NOW), dlopen, dlsym)

import JitML.Cache.Key qualified as Cache
import JitML.Codegen.RuntimeSource
  ( RuntimeSource (..)
  , materializeRuntimeSource
  )
import JitML.Codegen.SourceFile (SourceFile (..))
import JitML.Engines.Engine
  ( Engine (..)
  , JitCacheStatus (..)
  , KernelHandle (..)
  , compileSubprocess
  , resolveKernelCache
  )
import JitML.Env.Env (Env (..))
import JitML.Sub.Outcome (ProcessFailure, ProcessOutcome (..), renderProcessFailure)
import JitML.Sub.Render (renderSubprocess)
import JitML.Sub.Stream (defaultSubprocessEnv, runStreaming)
import JitML.Substrate (Substrate (..))

data KernelArtifact = KernelArtifact
  { kernelArtifactHandle :: KernelHandle
  , kernelArtifactStatus :: JitCacheStatus
  , kernelArtifactCompiled :: Bool
  , kernelArtifactCompileCommand :: Text
  }
  deriving stock (Eq, Show)

data KernelArtifactError
  = KernelArtifactProcessFailure ProcessFailure
  | KernelArtifactSemanticError Text
  deriving stock (Eq, Show)

renderKernelArtifactError :: KernelArtifactError -> Text
renderKernelArtifactError (KernelArtifactProcessFailure failure) = renderProcessFailure failure
renderKernelArtifactError (KernelArtifactSemanticError message) = message

ensureKernelArtifact
  :: Env -> Engine -> RuntimeSource -> Cache.Hash -> IO (Either KernelArtifactError KernelArtifact)
ensureKernelArtifact env engine source hash = do
  artifactExists <- doesFileExist artifactPath
  case resolveKernelCache engine source hash artifactExists of
    hit@(JitCacheHit hitHandle) ->
      pure (Right (artifactFor hitHandle hit False))
    miss@(JitCacheMiss missedHandle command) -> do
      createDirectoryIfMissing True (takeDirectory artifactPath)
      case engineSubstrate engine of
        AppleSilicon -> do
          written <- writeAppleMetalMetadata source artifactPath
          pure $
            case written of
              Right () -> Right (artifactFor missedHandle miss True)
              Left err ->
                Left
                  ( KernelArtifactSemanticError
                      ( "Apple Silicon Metal source metadata write failed for "
                          <> kernelHandleArtifactPath missedHandle
                          <> ": "
                          <> err
                      )
                  )
        _ -> do
          _sourceDirectory <- materializeRuntimeSource env source hash
          outcome <- runStreaming defaultSubprocessEnv command
          case outcome of
            ProcessFailed failure ->
              pure (Left (KernelArtifactProcessFailure failure))
            ProcessSucceeded _ ->
              pure (Right (artifactFor missedHandle miss True))
 where
  handle = case resolveKernelCache engine source hash False of
    JitCacheMiss missedHandle _ -> missedHandle
    JitCacheHit hitHandle -> hitHandle
  artifactPath = Text.unpack (kernelHandleArtifactPath handle)
  compileCommandText = renderSubprocess (compileSubprocess engine source hash)

  artifactFor handle' status compiled =
    KernelArtifact
      { kernelArtifactHandle = handle'
      , kernelArtifactStatus = status
      , kernelArtifactCompiled = compiled
      , kernelArtifactCompileCommand = compileCommandText
      }

writeAppleMetalMetadata :: RuntimeSource -> FilePath -> IO (Either Text ())
writeAppleMetalMetadata source artifactPath =
  case runtimeSourceFiles source of
    [SourceFile _ contents] ->
      writeTextAtomic artifactPath contents
    [] ->
      pure (Left "Metal source metadata renderer produced no files")
    files ->
      pure
        ( Left
            ( "Metal source metadata renderer produced "
                <> Text.pack (show (length files))
                <> " files"
            )
        )

writeTextAtomic :: FilePath -> Text -> IO (Either Text ())
writeTextAtomic artifactPath contents = do
  result <- tryAny $ do
    Text.IO.writeFile tmpPath contents
    renameFile tmpPath artifactPath
  pure $
    case result of
      Right () -> Right ()
      Left err -> Left (Text.pack (displayException err))
 where
  tmpPath = artifactPath <> ".tmp"

withKernelSymbol :: FilePath -> String -> (FunPtr symbol -> IO result) -> IO result
withKernelSymbol artifactPath symbolName useSymbol = do
  dynamicLibrary <- cachedKernelLibrary artifactPath
  symbol <- dlsym dynamicLibrary symbolName
  useSymbol symbol

-- | Load an already-built shared artifact without resolving a symbol.  This
-- gives callers a distinct exception boundary for @dlopen@ versus @dlsym@.
loadKernelLibrary :: FilePath -> IO ()
loadKernelLibrary artifactPath = do
  _ <- cachedKernelLibrary artifactPath
  pure ()

cachedKernelLibrary :: FilePath -> IO DL
cachedKernelLibrary artifactPath =
  modifyMVar kernelLibraryCache $ \cache ->
    case Map.lookup artifactPath cache of
      Just dynamicLibrary -> pure (cache, dynamicLibrary)
      Nothing -> do
        dynamicLibrary <- dlopen artifactPath [RTLD_NOW]
        pure (Map.insert artifactPath dynamicLibrary cache, dynamicLibrary)

kernelLibraryCache :: MVar (Map.Map FilePath DL)
{-# NOINLINE kernelLibraryCache #-}
kernelLibraryCache = unsafePerformIO (newMVar Map.empty)
