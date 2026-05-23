{-# LANGUAGE OverloadedStrings #-}

module JitML.Engines.Loader
  ( KernelArtifact (..)
  , ensureKernelArtifact
  , withKernelSymbol
  )
where

import Control.Exception (bracket)
import Control.Monad (void)
import Data.Text (Text)
import Data.Text qualified as Text
import Foreign.Ptr (FunPtr)
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory)
import System.Posix.DynamicLinker (RTLDFlags (RTLD_NOW), dlclose, dlopen, dlsym)

import JitML.Cache.Key qualified as Cache
import JitML.Codegen.RuntimeSource (RuntimeSource (..), materializeRuntimeSource)
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
import JitML.Tart.Build qualified as TartBuild
import JitML.Tart.Lifecycle (VmName (..))

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
      case engineSubstrate engine of
        AppleSilicon -> do
          tartResult <-
            TartBuild.executeTartCacheMissBuildPlan
              (envCacheDir env)
              ( TartBuild.tartCacheMissBuildPlan
                  (VmName "jitml-build")
                  (Cache.ModelId (kernelModelId source))
                  source
                  hash
              )
          pure $
            case tartResult of
              Right _ -> Right (artifactFor missedHandle miss True)
              Left err ->
                Left
                  ( "Apple Silicon kernel build failed for "
                      <> kernelHandleArtifactPath missedHandle
                      <> ": "
                      <> err
                  )
        _ -> do
          (exitCode, _stdoutText, stderrText) <- runStreaming defaultSubprocessEnv command
          pure $
            case exitCode of
              ExitSuccess -> Right (artifactFor missedHandle miss True)
              ExitFailure _ ->
                Left
                  ( "kernel compile failed for "
                      <> kernelHandleArtifactPath missedHandle
                      <> ": "
                      <> stderrText
                  )
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

withKernelSymbol :: FilePath -> String -> (FunPtr symbol -> IO result) -> IO result
withKernelSymbol artifactPath symbolName useSymbol =
  bracket (dlopen artifactPath [RTLD_NOW]) dlclose $ \dynamicLibrary -> do
    symbol <- dlsym dynamicLibrary symbolName
    useSymbol symbol
