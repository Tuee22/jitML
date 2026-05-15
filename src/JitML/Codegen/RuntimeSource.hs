{-# LANGUAGE OverloadedStrings #-}

module JitML.Codegen.RuntimeSource
  ( RuntimeSource (..)
  , SourceFile (..)
  , materializeRuntimeSource
  , renderRuntimeSource
  , runtimeSourceDirectory
  , runtimeSourcePayload
  , runtimeSourceRelativeDirectory
  )
where

import Data.Foldable (traverse_)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import Path (Abs, Dir, Path, parseRelDir, toFilePath, (</>))
import System.Directory (createDirectoryIfMissing, renameFile)
import System.FilePath qualified as FilePath

import JitML.Cache.Key
  ( Hash
  , KernelSpec
  , Kind
  , RuntimeSourcePayload (..)
  , Substrate (..)
  , TuningChoice
  , hashHex
  , substrateText
  )
import JitML.Codegen.Cuda (renderCudaSource)
import JitML.Codegen.Metal (renderMetalPackage)
import JitML.Codegen.OneDnn (renderOneDnnSource)
import JitML.Codegen.SourceFile (SourceFile (..))
import JitML.Env.Env (Env (..))

data RuntimeSource
  = GeneratedCudaSource
      { runtimeSourceKernel :: KernelSpec
      , runtimeSourceKind :: Kind
      , runtimeSourceTuning :: TuningChoice
      , runtimeSourceFiles :: [SourceFile]
      }
  | GeneratedOneDnnSource
      { runtimeSourceKernel :: KernelSpec
      , runtimeSourceKind :: Kind
      , runtimeSourceTuning :: TuningChoice
      , runtimeSourceFiles :: [SourceFile]
      }
  | GeneratedMetalPackage
      { runtimeSourceKernel :: KernelSpec
      , runtimeSourceKind :: Kind
      , runtimeSourceTuning :: TuningChoice
      , runtimeSourceFiles :: [SourceFile]
      }
  deriving stock (Eq, Show)

renderRuntimeSource :: KernelSpec -> Kind -> Substrate -> TuningChoice -> RuntimeSource
renderRuntimeSource kernelSpec kind substrate tuningChoice =
  case substrate of
    AppleSilicon ->
      GeneratedMetalPackage kernelSpec kind tuningChoice (renderMetalPackage kernelSpec kind tuningChoice)
    LinuxCPU ->
      GeneratedOneDnnSource kernelSpec kind tuningChoice (renderOneDnnSource kernelSpec kind tuningChoice)
    LinuxCUDA ->
      GeneratedCudaSource kernelSpec kind tuningChoice (renderCudaSource kernelSpec kind tuningChoice)

runtimeSourcePayload :: RuntimeSource -> RuntimeSourcePayload
runtimeSourcePayload source =
  RuntimeSourcePayload $
    Text.intercalate
      "\n--- jitml-source-file ---\n"
      (runtimeSourceHeader source : fmap renderSourceFile (runtimeSourceFiles source))

runtimeSourceHeader :: RuntimeSource -> Text
runtimeSourceHeader source =
  Text.unlines
    [ "runtime_source: " <> runtimeSourceTag source
    , "substrate: " <> substrateText (runtimeSourceSubstrate source)
    , "kind: " <> Text.pack (show (runtimeSourceKind source))
    , "tuning: " <> Text.pack (show (runtimeSourceTuning source))
    ]

renderSourceFile :: SourceFile -> Text
renderSourceFile sourceFile =
  Text.unlines
    [ "path: " <> Text.pack (sourceRelativePath sourceFile)
    , sourceContents sourceFile
    ]

runtimeSourceTag :: RuntimeSource -> Text
runtimeSourceTag GeneratedCudaSource {} = "GeneratedCudaSource"
runtimeSourceTag GeneratedOneDnnSource {} = "GeneratedOneDnnSource"
runtimeSourceTag GeneratedMetalPackage {} = "GeneratedMetalPackage"

runtimeSourceSubstrate :: RuntimeSource -> Substrate
runtimeSourceSubstrate GeneratedCudaSource {} = LinuxCUDA
runtimeSourceSubstrate GeneratedOneDnnSource {} = LinuxCPU
runtimeSourceSubstrate GeneratedMetalPackage {} = AppleSilicon

runtimeSourceDirectory :: Env -> RuntimeSource -> Hash -> IO (Path Abs Dir)
runtimeSourceDirectory env source hash = do
  root <- parseRelDir "jit-src"
  substrateDir <- parseRelDir (Text.unpack (substrateText (runtimeSourceSubstrate source)))
  hashDir <- parseRelDir (Text.unpack (hashHex hash))
  pure (envCacheDir env </> root </> substrateDir </> hashDir)

runtimeSourceRelativeDirectory :: RuntimeSource -> Hash -> FilePath
runtimeSourceRelativeDirectory source hash =
  ".build"
    FilePath.</> "jit-src"
    FilePath.</> Text.unpack (substrateText (runtimeSourceSubstrate source))
    FilePath.</> Text.unpack (hashHex hash)

materializeRuntimeSource :: Env -> RuntimeSource -> Hash -> IO (Path Abs Dir)
materializeRuntimeSource env source hash = do
  directory <- runtimeSourceDirectory env source hash
  let root = toFilePath directory
  createDirectoryIfMissing True root
  traverse_ (writeSourceFile root) (runtimeSourceFiles source)
  pure directory

writeSourceFile :: FilePath -> SourceFile -> IO ()
writeSourceFile root sourceFile = do
  let path = root FilePath.</> sourceRelativePath sourceFile
      tmpPath = path <> ".tmp"
  createDirectoryIfMissing True (FilePath.takeDirectory path)
  Text.IO.writeFile tmpPath (sourceContents sourceFile)
  renameFile tmpPath path
