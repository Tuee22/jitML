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

import Control.Monad (void)
import Data.Text (Text)
import Data.Text qualified as Text
import Path (Abs, Dir, Path)
import System.Exit (ExitCode (..))

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
            "repoint-stable-ffi-symlink"
            (RepointStableFfiSymlink modelId hash (Cache.Extension "dylib"))
        ]
    }
 where
  sourceDir = Text.pack (runtimeSourceRelativeDirectory source hash)
  appleJitDir = ".build/jit/apple-silicon"
  appleHostDir = ".build/host/apple-silicon"
  buildProduct = sourceDir <> "/.build/release/libJitMLMetal.dylib"
  artifactPath = appleJitDir <> "/" <> Cache.hashHex hash <> ".dylib"
  artifactTempPath = artifactPath <> ".tmp"
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
