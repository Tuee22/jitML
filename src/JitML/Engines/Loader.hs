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
import System.Directory (copyFile, createDirectoryIfMissing, doesFileExist, getCurrentDirectory, renameFile)
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
import JitML.Tart.Lifecycle qualified as TartLifecycle

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
      vmReady <- ensureBuildVmForSubstrate (engineSubstrate engine)
      case vmReady of
        Left err ->
          pure
            ( Left
                ( "Apple Silicon build VM not ready for "
                    <> kernelHandleArtifactPath missedHandle
                    <> ": "
                    <> err
                )
            )
        Right () -> do
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
                -- Sprint 7.10 — the in-VM `swift build` writes the dylib under
                -- the package's `.build/release/` (host-visible via the shared
                -- mount); publish it to the content-addressed cache path and
                -- repoint the stable FFI symlink.
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

-- | Sprint 7.10 — before an Apple Silicon JIT build, ensure the jitml-managed
-- Tart build VM is up with the repository mounted (the in-VM `swift build`
-- writes its dylib to a host-visible path). The mount root is the current
-- working directory (the repository root, where the build's relative source and
-- artifact paths resolve). Other substrates need no VM.
ensureBuildVmForSubstrate :: Substrate -> IO (Either Text ())
ensureBuildVmForSubstrate AppleSilicon = do
  root <- getCurrentDirectory
  result <- TartLifecycle.ensureBuildVmUp (TartLifecycle.defaultBuildVmConfig root)
  pure (() <$ result)
ensureBuildVmForSubstrate _ = pure (Right ())

-- | Publish the Apple `swift build` product into the content-addressed cache.
-- The in-VM `swift build` writes `libJitMLMetal.dylib` under the generated
-- package's `.build/release/` (host-visible via the shared mount); copy it
-- atomically to `<hash>.dylib` and repoint the stable
-- `host/apple-silicon/<model-id>.dylib` FFI symlink.
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
