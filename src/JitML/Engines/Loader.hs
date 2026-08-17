{-# LANGUAGE OverloadedStrings #-}

module JitML.Engines.Loader
  ( KernelArtifact (..)
  , KernelArtifactError (..)
  , ensureKernelArtifact
  , executedArtifactIdentity
  , loadKernelLibrary
  , metalArtifactFamily
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
import Foreign.C.String (CString, peekCString)
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
import JitML.Substrate
  ( ArtifactFill (..)
  , KernelLaunch (..)
  , SubstrateProfile (..)
  , profileFor
  )

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
      -- Sprint `79.1`: dispatch on the profile's `ArtifactFill` value rather
      -- than on a wildcard over `Substrate`. A fourth substrate now fails the
      -- build in `profileFor` instead of silently taking the compile arm.
      case profileArtifactFill (profileFor (engineSubstrate engine)) of
        SourceMetadataWriteFill -> do
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
        CompileSubprocessFill -> do
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

foreign import ccall "dynamic"
  mkKernelFamilyNameFun :: FunPtr (IO CString) -> IO CString

-- | Ask a compiled artifact which kernel family it implements.
--
-- Sprint `79.1` made this the one identity read for both launch kinds, keyed by
-- the profile's 'KernelLaunch' rather than by an @isMetal@ branch. It is the
-- difference between evidence and a tautology: before this, the Apple family
-- driver reported the family the /host had asked for/, so
-- 'JitML.Engines.HasEngine.toMetalEngineRun''s mismatch guard compared a value
-- with itself and could never reject anything.
executedArtifactIdentity :: KernelLaunch -> FilePath -> IO (Either Text Text)
executedArtifactIdentity launch artifactPath =
  case launch of
    LoadableSymbolLaunch -> do
      resolved <-
        tryAny
          ( withKernelSymbol artifactPath "jitml_kernel_family_name" $ \familySymbol ->
              Text.pack <$> (mkKernelFamilyNameFun familySymbol >>= peekCString)
          )
      pure $
        case resolved of
          Left err ->
            Left ("loaded artifact family name unreadable: " <> Text.pack (displayException err))
          Right familyName -> Right familyName
    FixedBridgeLaunch -> metalArtifactFamily artifactPath

-- | Recover the family the Apple Metal source-metadata artifact declares.
--
-- The artifact is the exact document the renderer wrote, so its @family@ field
-- is the identity of the shader the fixed bridge compiles and dispatches.
metalArtifactFamily :: FilePath -> IO (Either Text Text)
metalArtifactFamily artifactPath = do
  readResult <- tryAny (Text.IO.readFile artifactPath)
  pure $
    case readResult of
      Left err ->
        Left ("Metal source-metadata artifact unreadable: " <> Text.pack (displayException err))
      Right contents ->
        case [line | line <- Text.lines contents, "\"family\":" `Text.isInfixOf` line] of
          [] -> Left "Metal source-metadata artifact declares no family"
          line : _ ->
            case Text.splitOn "\"" (Text.drop 1 (Text.dropWhile (/= ':') line)) of
              _ : value : _
                | not (Text.null value) -> Right value
              _ -> Left "Metal source-metadata artifact has a malformed family field"

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
