{-# LANGUAGE OverloadedStrings #-}

module JitML.Engines.Loader
  ( KernelArtifact (..)
  , ensureKernelArtifact
  , withKernelSymbol
  )
where

import Control.Exception (bracket)
import Control.Exception.Safe (displayException, tryAny)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import Foreign.Ptr (FunPtr)
import System.Directory
  ( createDirectoryIfMissing
  , doesFileExist
  , renameFile
  )
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory)
import System.Posix.DynamicLinker (RTLDFlags (RTLD_NOW), dlclose, dlopen, dlsym)

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
                  ( "Apple Silicon Metal source metadata write failed for "
                      <> kernelHandleArtifactPath missedHandle
                      <> ": "
                      <> err
                  )
        _ -> do
          _sourceDirectory <- materializeRuntimeSource env source hash
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
withKernelSymbol artifactPath symbolName useSymbol =
  bracket (dlopen artifactPath [RTLD_NOW]) dlclose $ \dynamicLibrary -> do
    symbol <- dlsym dynamicLibrary symbolName
    useSymbol symbol
