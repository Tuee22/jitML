{-# LANGUAGE OverloadedStrings #-}

module JitML.Tart.Build
  ( TartCacheMissBuildExecutor (..)
  , TartCacheMissBuildPlan (..)
  , TartCacheMissBuildResult (..)
  , TartCacheMissBuildStep (..)
  , TartHostAction (..)
  , executeTartCacheMissBuildPlan
  , executeTartCacheMissBuildPlanWith
  , renderTartCacheMissBuildPlan
  , renderTartHostAction
  , tartCacheMissBuildPlan
  )
where

import Control.Monad (filterM, void)
import Data.Text (Text)
import Data.Text qualified as Text
import Path (Abs, Dir, Path)
import System.Directory
  ( copyFile
  , createDirectoryIfMissing
  , doesDirectoryExist
  , doesFileExist
  , listDirectory
  , renameFile
  )
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory, takeFileName, (</>))

import JitML.Cache.Key qualified as Cache
import JitML.Cache.Symlink qualified as CacheSymlink
import JitML.Codegen.RuntimeSource
  ( RuntimeSource
  , runtimeSourceRelativeDirectory
  )
import JitML.Sub.Render (renderSubprocess)
import JitML.Sub.Stream (defaultSubprocessEnv, runStreaming)
import JitML.Sub.Subprocess (Subprocess, subprocess)
import JitML.Tart.Exec (tartExecSubprocess)
import JitML.Tart.Lifecycle (VmName (..), ensureVmUpLive)

data TartCacheMissBuildPlan = TartCacheMissBuildPlan
  { tartCacheMissVmName :: VmName
  , tartCacheMissModelId :: Cache.ModelId
  , tartCacheMissSourceDir :: Text
  , tartCacheMissBuildProduct :: Text
  , tartCacheMissArtifactPath :: Text
  , tartCacheMissStableSymlinkPath :: Text
  , tartCacheMissSteps :: [TartCacheMissBuildStep]
  }
  deriving stock (Eq, Show)

data TartCacheMissBuildStep
  = TartHostStep Text TartHostAction
  | TartCommandStep Text Subprocess
  deriving stock (Eq, Show)

data TartHostAction
  = EnsureTartVmUp VmName
  | RepointStableFfiSymlink Cache.ModelId Cache.Hash Cache.Extension
  | -- | Find the @default.metallib@ produced by @swift build@ under the first
    -- argument (the package @.build/release@ tree) and publish it atomically to
    -- the content-addressed @<hash>.metallib@ path (second argument) next to the
    -- cached @<hash>.dylib@, so the generated Metal launcher can load it by URL
    -- after the dylib is relocated out of its SwiftPM resource bundle.
    PublishMetallib Text Text
  deriving stock (Eq, Show)

data TartCacheMissBuildExecutor m = TartCacheMissBuildExecutor
  { executeTartHostAction :: Text -> TartHostAction -> m (Either Text ())
  , executeTartCommand :: Text -> Subprocess -> m (Either Text ())
  }

newtype TartCacheMissBuildResult = TartCacheMissBuildResult
  { tartCacheMissExecutedSteps :: [Text]
  }
  deriving stock (Eq, Show)

executeTartCacheMissBuildPlan
  :: Path Abs Dir -> TartCacheMissBuildPlan -> IO (Either Text TartCacheMissBuildResult)
executeTartCacheMissBuildPlan buildRoot =
  executeTartCacheMissBuildPlanWith (liveTartCacheMissBuildExecutor buildRoot)

liveTartCacheMissBuildExecutor :: Path Abs Dir -> TartCacheMissBuildExecutor IO
liveTartCacheMissBuildExecutor buildRoot =
  TartCacheMissBuildExecutor
    { executeTartHostAction = \_stepName action ->
        case action of
          EnsureTartVmUp vmName ->
            void <$> ensureVmUpLive vmName
          RepointStableFfiSymlink modelId hash extension ->
            Right () <$ CacheSymlink.repointSymlink buildRoot modelId hash extension
          PublishMetallib releaseDir destPath ->
            publishMetallib (Text.unpack releaseDir) (Text.unpack destPath)
    , executeTartCommand = \_stepName command -> do
        (exitCode, _stdoutText, stderrText) <- runStreaming defaultSubprocessEnv command
        pure $
          case exitCode of
            ExitSuccess -> Right ()
            ExitFailure _ ->
              Left (renderSubprocess command <> " failed: " <> stderrText)
    }

tartCacheMissBuildPlan
  :: VmName -> Cache.ModelId -> RuntimeSource -> Cache.Hash -> TartCacheMissBuildPlan
tartCacheMissBuildPlan vmName modelId source hash =
  TartCacheMissBuildPlan
    { tartCacheMissVmName = vmName
    , tartCacheMissModelId = modelId
    , tartCacheMissSourceDir = sourceDir
    , tartCacheMissBuildProduct = buildProduct
    , tartCacheMissArtifactPath = artifactPath
    , tartCacheMissStableSymlinkPath = stableSymlinkPath
    , tartCacheMissSteps =
        [ TartHostStep
            "ensure-vm-up"
            (EnsureTartVmUp vmName)
        , TartCommandStep
            "validate-swift-toolchain"
            (tartExecSubprocess vmName ["swift", "--version"])
        , TartCommandStep
            "build-metal-package"
            (tartExecSubprocess vmName ["swift", "build", "--package-path", sourceDir, "-c", "release"])
        , TartCommandStep
            "prepare-cache-dirs"
            (subprocess "mkdir" ["-p", appleJitDir, appleHostDir])
        , TartCommandStep
            "copy-build-product"
            (subprocess "cp" [buildProduct, artifactTempPath])
        , TartCommandStep
            "publish-cache-artifact"
            (subprocess "mv" [artifactTempPath, artifactPath])
        , TartHostStep
            "publish-cache-metallib"
            (PublishMetallib releaseDir metallibPath)
        , TartHostStep
            "repoint-stable-ffi-symlink"
            (RepointStableFfiSymlink modelId hash (Cache.Extension "dylib"))
        ]
    }
 where
  sourceDir = Text.pack (runtimeSourceRelativeDirectory source hash)
  appleJitDir = ".build/jit/apple-silicon"
  appleHostDir = ".build/host/apple-silicon"
  releaseDir = sourceDir <> "/.build/release"
  buildProduct = releaseDir <> "/libJitMLMetal.dylib"
  artifactPath = appleJitDir <> "/" <> Cache.hashHex hash <> ".dylib"
  artifactTempPath = artifactPath <> ".tmp"
  metallibPath = appleJitDir <> "/" <> Cache.hashHex hash <> ".metallib"
  stableSymlinkPath = appleHostDir <> "/" <> Cache.unModelId modelId <> ".dylib"

executeTartCacheMissBuildPlanWith
  :: (Monad m)
  => TartCacheMissBuildExecutor m
  -> TartCacheMissBuildPlan
  -> m (Either Text TartCacheMissBuildResult)
executeTartCacheMissBuildPlanWith executor plan =
  go [] (tartCacheMissSteps plan)
 where
  go executed [] =
    pure (Right (TartCacheMissBuildResult (reverse executed)))
  go executed (step : rest) = do
    result <-
      case step of
        TartHostStep name action ->
          executeTartHostAction executor name action
        TartCommandStep name command ->
          executeTartCommand executor name command
    case result of
      Left err ->
        pure (Left (tartCacheMissStepName step <> ": " <> err))
      Right () ->
        go (tartCacheMissStepName step : executed) rest

tartCacheMissStepName :: TartCacheMissBuildStep -> Text
tartCacheMissStepName (TartHostStep name _) = name
tartCacheMissStepName (TartCommandStep name _) = name

renderTartCacheMissBuildPlan :: TartCacheMissBuildPlan -> Text
renderTartCacheMissBuildPlan plan =
  Text.unlines $
    [ "apple_cache_miss:"
    , "  vm: " <> unVmName (tartCacheMissVmName plan)
    , "  model_id: " <> Cache.unModelId (tartCacheMissModelId plan)
    , "  source_dir: " <> tartCacheMissSourceDir plan
    , "  build_product: " <> tartCacheMissBuildProduct plan
    , "  cache_artifact: " <> tartCacheMissArtifactPath plan
    , "  stable_symlink: " <> tartCacheMissStableSymlinkPath plan
    , "  steps:"
    ]
      <> fmap renderTartCacheMissBuildStep (tartCacheMissSteps plan)

renderTartCacheMissBuildStep :: TartCacheMissBuildStep -> Text
renderTartCacheMissBuildStep (TartHostStep name action) =
  "    - " <> name <> ": host-action " <> renderTartHostAction action
renderTartCacheMissBuildStep (TartCommandStep name command) =
  "    - " <> name <> ": " <> renderSubprocess command

renderTartHostAction :: TartHostAction -> Text
renderTartHostAction (EnsureTartVmUp vmName) =
  "JitML.Tart.ensureVmUpLive " <> unVmName vmName
renderTartHostAction (RepointStableFfiSymlink modelId hash extension) =
  "JitML.Cache.Symlink.repointSymlink .build "
    <> Cache.unModelId modelId
    <> " "
    <> Cache.hashHex hash
    <> " "
    <> Cache.unExtension extension
renderTartHostAction (PublishMetallib releaseDir destPath) =
  "JitML.Tart.publishMetallib " <> releaseDir <> " " <> destPath

-- | Locate the @default.metallib@ emitted by @swift build@'s `.process`
-- resource rule anywhere under the package @.build/release@ tree (the exact
-- SwiftPM resource-bundle layout varies by toolchain), and copy it atomically
-- to the content-addressed destination next to the cached dylib.
publishMetallib :: FilePath -> FilePath -> IO (Either Text ())
publishMetallib releaseDir destPath = do
  found <- findFileNamed "default.metallib" releaseDir
  case found of
    Nothing ->
      pure
        ( Left
            ( "default.metallib not found under "
                <> Text.pack releaseDir
                <> " (swift build did not produce a Metal library resource)"
            )
        )
    Just metallib -> do
      createDirectoryIfMissing True (takeDirectory destPath)
      let tmpPath = destPath <> ".tmp"
      copyFile metallib tmpPath
      renameFile tmpPath destPath
      pure (Right ())

-- | Depth-first search for the first file with the given name under a root.
findFileNamed :: String -> FilePath -> IO (Maybe FilePath)
findFileNamed name root = do
  isDir <- doesDirectoryExist root
  if not isDir
    then pure Nothing
    else do
      entries <- listDirectory root
      let paths = fmap (root </>) entries
      files <- filterM doesFileExist paths
      case filter ((== name) . takeFileName) files of
        (match : _) -> pure (Just match)
        [] -> do
          dirs <- filterM doesDirectoryExist paths
          searchSubdirs dirs
 where
  searchSubdirs [] = pure Nothing
  searchSubdirs (dir : rest) = do
    result <- findFileNamed name dir
    case result of
      Just match -> pure (Just match)
      Nothing -> searchSubdirs rest
