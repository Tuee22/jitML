{-# LANGUAGE OverloadedStrings #-}

module JitML.Engines.Loader
  ( KernelArtifact (..)
  , ensureKernelArtifact
  , withKernelSymbol
  )
where

import Control.Exception (bracket)
import Control.Exception.Safe (displayException, tryAny)
import Control.Monad (void)
import Data.Text (Text)
import Data.Text qualified as Text
import Foreign.Ptr (FunPtr)
import System.Directory (copyFile, createDirectoryIfMissing, doesFileExist, renameFile)
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory)
import System.Posix.DynamicLinker (RTLDFlags (RTLD_NOW), dlclose, dlopen, dlsym)

import JitML.Cache.Key qualified as Cache
import JitML.Cache.Symlink qualified as CacheSymlink
import JitML.Codegen.RuntimeSource
  ( RuntimeSource (..)
  , materializeRuntimeSource
  , runtimeSourceRelativeDirectory
  )
import JitML.Engines.Engine
  ( Engine (..)
  , JitCacheStatus (..)
  , KernelHandle (..)
  , compileSubprocess
  , resolveKernelCache
  )
import JitML.Env.Env (Env (..))
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

ensureKernelArtifact
  :: Env -> Engine -> RuntimeSource -> Cache.Hash -> IO (Either Text KernelArtifact)
ensureKernelArtifact env engine source hash = do
  void (materializeRuntimeSource env source hash)
  artifactExists <- doesFileExist artifactPath
  case resolveKernelCache engine source hash artifactExists of
    hit@(JitCacheHit hitHandle) ->
      pure (Right (artifactFor hitHandle hit False))
    miss@(JitCacheMiss missedHandle command) -> do
      createDirectoryIfMissing True (takeDirectory artifactPath)
      (exitCode, _stdoutText, stderrText) <- runStreaming defaultSubprocessEnv command
      case exitCode of
        ExitFailure _ ->
          pure
            ( Left
                ( "kernel compile failed for "
                    <> kernelHandleArtifactPath missedHandle
                    <> ": "
                    <> stderrText
                )
            )
        ExitSuccess ->
          case engineSubstrate engine of
            -- Sprint 7.8 — the Apple host `swift build` writes the dylib under
            -- the package's `.build/release/`; publish it to the
            -- content-addressed cache path and repoint the stable FFI symlink.
            AppleSilicon -> do
              published <- publishAppleArtifact env source hash artifactPath
              pure $
                case published of
                  Right () -> Right (artifactFor missedHandle miss True)
                  Left err ->
                    Left
                      ( "Apple Silicon kernel publish failed for "
                          <> kernelHandleArtifactPath missedHandle
                          <> ": "
                          <> err
                      )
            -- Linux substrates compile straight to the artifact path via `-o`.
            _ -> pure (Right (artifactFor missedHandle miss True))
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

kernelModelId :: RuntimeSource -> Text
kernelModelId source =
  Cache.kernelSpecPayload (runtimeSourceKernel source)

-- | Publish the Apple `swift build` product into the content-addressed cache.
-- The host `swift build` writes `libJitMLMetal.dylib` under the generated
-- package's `.build/release/`; copy it atomically to `<hash>.dylib` and repoint
-- the stable `host/apple-silicon/<model-id>.dylib` FFI symlink.
publishAppleArtifact
  :: Env -> RuntimeSource -> Cache.Hash -> FilePath -> IO (Either Text ())
publishAppleArtifact env source hash artifactPath = do
  result <- tryAny $ do
    copyFile buildProduct tmpPath
    renameFile tmpPath artifactPath
    void
      ( CacheSymlink.repointSymlink
          (envCacheDir env)
          (Cache.ModelId (kernelModelId source))
          hash
          (Cache.Extension "dylib")
      )
  pure $
    case result of
      Right () -> Right ()
      Left err -> Left (Text.pack (displayException err))
 where
  sourceDir = runtimeSourceRelativeDirectory source hash
  buildProduct = sourceDir <> "/.build/release/libJitMLMetal.dylib"
  tmpPath = artifactPath <> ".tmp"

withKernelSymbol :: FilePath -> String -> (FunPtr symbol -> IO result) -> IO result
withKernelSymbol artifactPath symbolName useSymbol =
  bracket (dlopen artifactPath [RTLD_NOW]) dlclose $ \dynamicLibrary -> do
    symbol <- dlsym dynamicLibrary symbolName
    useSymbol symbol
