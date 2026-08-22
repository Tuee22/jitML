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
import Control.Exception.Safe (displayException, finally, onException, tryAny)
import Control.Monad (void)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import Data.Unique (hashUnique, newUnique)
import Foreign.C.String (CString, peekCString)
import Foreign.Ptr (FunPtr)
import Path (toFilePath)
import System.Directory
  ( createDirectoryIfMissing
  , doesFileExist
  , removeFile
  , removePathForcibly
  , renameFile
  )
import System.FilePath (takeDirectory)
import System.FilePath qualified as FilePath
import System.IO.Unsafe (unsafePerformIO)
import System.Posix.DynamicLinker (DL, RTLDFlags (RTLD_NOW), dlopen, dlsym)
import System.Posix.Process (getProcessID)

import JitML.Cache.Key qualified as Cache
import JitML.Codegen.RuntimeSource
  ( RuntimeSource (..)
  , materializeRuntimeSource
  )
import JitML.Codegen.SourceFile (SourceFile (..))
import JitML.Engines.CudaRuntime (probeNvccVersion)
import JitML.Engines.Engine
  ( Engine (..)
  , JitCacheStatus (..)
  , KernelHandle (..)
  , compileSubprocess
  , renderedScratchDirectory
  , renderedStagingPath
  , resolveKernelCache
  )
import JitML.Env.Env (Env (..))
import JitML.Sub.Outcome (ProcessFailure, ProcessOutcome (..), renderProcessFailure)
import JitML.Sub.Render (renderSubprocess)
import JitML.Sub.Stream (defaultSubprocessEnv, runStreaming)
import JitML.Substrate
  ( ArtifactFill (..)
  , KernelLaunch (..)
  , Substrate (..)
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
  artifactPresent <- doesFileExist artifactPath
  -- Sprint `78.1`: an artifact is a cache hit only if the toolchain that
  -- produced it is the toolchain present now. The cache key cannot carry the
  -- compiler version — it is a pure value and the version is an `IO` probe — so
  -- a toolkit upgrade would otherwise serve stale machine code forever at an
  -- unchanged content address. This is a cache-*validity* check, not a
  -- cache-*key* change: the published six-tuple is untouched.
  toolchainCurrent <- artifactToolchainMatches engine artifactPath
  let artifactExists = artifactPresent && toolchainCurrent
  case resolveKernelCache engine source hash artifactExists of
    hit@(JitCacheHit hitHandle) ->
      pure (Right (artifactFor hitHandle hit False))
    miss@(JitCacheMiss missedHandle _) -> do
      createDirectoryIfMissing True (takeDirectory artifactPath)
      -- Sprint `79.1`: dispatch on the profile's `ArtifactFill` value rather
      -- than on a wildcard over `Substrate`. A fourth substrate now fails the
      -- build in `profileFor` instead of silently taking the compile arm.
      --
      -- Sprint `78.1`: both arms now stage into a per-invocation path and
      -- publish by rename, so no arm can leave a partially written artifact at
      -- a content-addressed address that the next run reports as a cache hit.
      withStagedArtifact artifactPath $ \stagingPath ->
        case profileArtifactFill (profileFor (engineSubstrate engine)) of
          SourceMetadataWriteFill -> do
            written <- writeAppleMetalMetadata source stagingPath
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
            withCompileScratchDirectory env hash $ \scratchDir -> do
              let command = compileSubprocess engine source hash scratchDir stagingPath
              outcome <- runStreaming defaultSubprocessEnv command
              case outcome of
                ProcessFailed failure ->
                  pure (Left (KernelArtifactProcessFailure failure))
                ProcessSucceeded _ -> do
                  recordArtifactToolchain engine artifactPath
                  pure (Right (artifactFor missedHandle miss True))
 where
  handle = case resolveKernelCache engine source hash False of
    JitCacheMiss missedHandle _ -> missedHandle
    JitCacheHit hitHandle -> hitHandle
  artifactPath = Text.unpack (kernelHandleArtifactPath handle)
  compileCommandText =
    renderSubprocess
      ( compileSubprocess
          engine
          source
          hash
          renderedScratchDirectory
          (renderedStagingPath engine hash)
      )

  artifactFor handle' status compiled =
    KernelArtifact
      { kernelArtifactHandle = handle'
      , kernelArtifactStatus = status
      , kernelArtifactCompiled = compiled
      , kernelArtifactCompileCommand = compileCommandText
      }

-- | Run a fill against a per-invocation staging path and publish it by rename.
--
-- Sprint `78.1` — the one publish path for every substrate. `rename` within a
-- directory is atomic on POSIX, so a reader either sees no artifact or sees a
-- complete one; a killed or failed fill leaves the cache address untouched
-- rather than occupying it with a truncated file that `doesFileExist` would
-- report as a hit. The staging suffix is unique per invocation, so two
-- processes filling the same address concurrently cannot overwrite each other's
-- partial output.
withStagedArtifact
  :: FilePath
  -> (FilePath -> IO (Either KernelArtifactError a))
  -> IO (Either KernelArtifactError a)
withStagedArtifact artifactPath fill = do
  unique <- stagingToken
  let stagingPath = artifactPath <> "." <> unique <> ".partial"
  outcome <- fill stagingPath `onException` removeIfPresent stagingPath
  case outcome of
    Left err -> do
      removeIfPresent stagingPath
      pure (Left err)
    Right value -> do
      renamed <- tryAny (renameFile stagingPath artifactPath)
      case renamed of
        Right () -> pure (Right value)
        Left err -> do
          removeIfPresent stagingPath
          pure
            ( Left
                ( KernelArtifactSemanticError
                    ( "publishing the compiled artifact to "
                        <> Text.pack artifactPath
                        <> " failed: "
                        <> Text.pack (displayException err)
                    )
                )
            )

-- | A per-invocation scratch directory for a producer's intermediate files.
--
-- Sprint `78.1` — `nvcc` embeds its own intermediate file names in the artifact,
-- and those names carry its process id unless it is directed at a chosen
-- directory. The directory's *path* is measured not to be embedded, so a unique
-- directory per invocation keeps the bytes reproducible while keeping two
-- concurrent compiles of the same kernel from sharing intermediate files. It
-- lives under the build root so it is gitignored and skipped by `jitml lint`.
withCompileScratchDirectory :: Env -> Cache.Hash -> (FilePath -> IO a) -> IO a
withCompileScratchDirectory env hash useScratch = do
  unique <- stagingToken
  let scratchDir =
        toFilePath (envCacheDir env)
          FilePath.</> "jit-scratch"
          FilePath.</> Text.unpack (Cache.hashHex hash)
          <> "-"
          <> unique
  createDirectoryIfMissing True scratchDir
  useScratch scratchDir `finally` removeDirectoryIfPresent scratchDir

-- | A token unique to this invocation, so concurrent fills of one cache address
-- never share a staging path or a scratch directory.
stagingToken :: IO String
stagingToken = do
  pid <- getProcessID
  unique <- newUnique
  pure (show (fromIntegral pid :: Integer) <> "-" <> show (hashUnique unique))

removeIfPresent :: FilePath -> IO ()
removeIfPresent path = void (tryAny (removeFile path))

removeDirectoryIfPresent :: FilePath -> IO ()
removeDirectoryIfPresent path = void (tryAny (removePathForcibly path))

-- | The sidecar naming the toolchain an artifact was produced by.
artifactToolchainPath :: FilePath -> FilePath
artifactToolchainPath artifactPath = artifactPath <> ".toolchain"

-- | Whether a cached artifact was produced by the toolchain present now.
--
-- Absent probe (no compiler on this host) or absent sidecar (an artifact from
-- before this check existed) is treated as current: this gate exists to catch a
-- toolkit *upgrade*, not to invalidate every pre-existing cache entry or to
-- fail a lane whose compiler is legitimately unavailable.
artifactToolchainMatches :: Engine -> FilePath -> IO Bool
artifactToolchainMatches engine artifactPath = do
  probed <- probeArtifactToolchain engine
  case probed of
    Nothing -> pure True
    Just current -> do
      recorded <- tryAny (Text.IO.readFile (artifactToolchainPath artifactPath))
      pure $
        case recorded of
          Left _ -> True
          Right stored -> Text.strip stored == current

-- | Write the sidecar next to a freshly published artifact.
recordArtifactToolchain :: Engine -> FilePath -> IO ()
recordArtifactToolchain engine artifactPath = do
  probed <- probeArtifactToolchain engine
  case probed of
    Nothing -> pure ()
    Just current ->
      void (tryAny (Text.IO.writeFile (artifactToolchainPath artifactPath) current))

-- | How each substrate names the toolchain version that produced its artifact.
--
-- Total over 'Substrate' rather than a CUDA branch: `apple-silicon` has no
-- compiler, so its artifact carries no toolchain identity beyond the rendered
-- document already keyed by the cache.
probeArtifactToolchain :: Engine -> IO (Maybe Text)
probeArtifactToolchain engine =
  modifyMVar artifactToolchainCache $ \cache ->
    case Map.lookup substrate cache of
      Just probed -> pure (cache, probed)
      Nothing -> do
        probed <- probeSubstrateToolchain substrate
        pure (Map.insert substrate probed cache, probed)
 where
  substrate = engineSubstrate engine

-- | The uncached probe, one arm per substrate.
probeSubstrateToolchain :: Substrate -> IO (Maybe Text)
probeSubstrateToolchain = \case
  AppleSilicon -> pure Nothing
  LinuxCPU -> pure Nothing
  LinuxCUDA -> fmap (fmap ("nvcc-" <>)) probeNvccVersion

-- | The probed toolchain identity, resolved once per substrate per process.
--
-- 'ensureKernelArtifact' runs on every device operation, not only on a cache
-- miss, so an unmemoised probe forks @nvcc --version@ once per kernel launch:
-- a @linux-cuda@ PPO rollout measured __20,692__ spawns in 60 seconds, none of
-- them a compile, which is what put the lane's live RL workflow past its
-- placement budget. A compiler cannot be upgraded underneath a running process,
-- so resolving the identity once preserves the Sprint `78.1` upgrade gate
-- exactly — the sidecar comparison in 'artifactToolchainMatches' is unchanged
-- and still runs per artifact — while removing the per-launch subprocess.
artifactToolchainCache :: MVar (Map.Map Substrate (Maybe Text))
{-# NOINLINE artifactToolchainCache #-}
artifactToolchainCache = unsafePerformIO (newMVar Map.empty)

writeAppleMetalMetadata :: RuntimeSource -> FilePath -> IO (Either Text ())
writeAppleMetalMetadata source artifactPath =
  case runtimeSourceFiles source of
    [SourceFile _ contents] ->
      writeArtifactText artifactPath contents
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

-- | Write a rendered document to the staging path 'withStagedArtifact' supplies.
-- Publication is the caller's rename, so this no longer owns a `.tmp` name of
-- its own — the fixed suffix it used to use was shared by every concurrent
-- writer of the same artifact (Sprint `78.1`).
writeArtifactText :: FilePath -> Text -> IO (Either Text ())
writeArtifactText stagingPath contents = do
  result <- tryAny (Text.IO.writeFile stagingPath contents)
  pure $
    case result of
      Right () -> Right ()
      Left err -> Left (Text.pack (displayException err))

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
