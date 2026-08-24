{-# LANGUAGE OverloadedStrings #-}

module JitML.Codegen.RuntimeSource
  ( KernelProgram (..)
  , RuntimeSource (..)
  , SourceFile (..)
  , materializeRuntimeSource
  , renderRuntimeSource
  , runtimeSourceDirectory
  , runtimeSourcePayload
  , runtimeSourceProgram
  , runtimeSourceRelativeDirectory
  )
where

import Data.Foldable (traverse_)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import Data.Unique (hashUnique, newUnique)
import Path (Abs, Dir, Path, parseRelDir, toFilePath, (</>))
import System.Directory (createDirectoryIfMissing, renameFile)
import System.FilePath qualified as FilePath
import System.Posix.Process (getProcessID)

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
import JitML.Codegen.KernelFamily (KernelFamily (..))
import JitML.Codegen.Metal (renderMetalMetadata)
import JitML.Codegen.OneDnn (renderOneDnnSource)
import JitML.Codegen.SourceFile (SourceFile (..))
import JitML.Env.Env (Env (..))

-- | Which generated program an artifact is.
--
-- Sprint `265.1` — the CUDA libraries an artifact links follow from this rather
-- than from its substrate. The family and layer-training programs really call
-- cuBLAS and cuDNN; the MLP program is hand-written elementwise CUDA that calls
-- neither, so linking them onto its @.so@ made the artifact depend on two
-- libraries it never enters and over-constrained its cache key.
data KernelProgram
  = -- | The per-'KernelFamily' kernels.
    FamilyProgram
  | -- | The shared MLP forward/backward program.
    MlpProgram
  | -- | The layer-graph training program.
    LayerTrainingProgram
  deriving stock (Bounded, Enum, Eq, Ord, Show)

-- | The program a rendered source belongs to.
runtimeSourceProgram :: RuntimeSource -> KernelProgram
runtimeSourceProgram GeneratedCudaSource {runtimeSourceProgramKind = program} = program
runtimeSourceProgram GeneratedOneDnnSource {runtimeSourceProgramKind = program} = program
runtimeSourceProgram GeneratedMetalSourceMetadata {runtimeSourceProgramKind = program} = program

data RuntimeSource
  = GeneratedCudaSource
      { runtimeSourceKernel :: KernelSpec
      , runtimeSourceKind :: Kind
      , runtimeSourceTuning :: TuningChoice
      , runtimeSourceProgramKind :: KernelProgram
      , runtimeSourceFiles :: [SourceFile]
      }
  | GeneratedOneDnnSource
      { runtimeSourceKernel :: KernelSpec
      , runtimeSourceKind :: Kind
      , runtimeSourceTuning :: TuningChoice
      , runtimeSourceProgramKind :: KernelProgram
      , runtimeSourceFiles :: [SourceFile]
      }
  | GeneratedMetalSourceMetadata
      { runtimeSourceKernel :: KernelSpec
      , runtimeSourceKind :: Kind
      , runtimeSourceTuning :: TuningChoice
      , runtimeSourceKernelFamily :: Maybe KernelFamily
      , runtimeSourceProgramKind :: KernelProgram
      , runtimeSourceFiles :: [SourceFile]
      }
  deriving stock (Eq, Show)

renderRuntimeSource :: KernelSpec -> Kind -> Substrate -> TuningChoice -> RuntimeSource
renderRuntimeSource kernelSpec kind substrate tuningChoice =
  case substrate of
    AppleSilicon ->
      GeneratedMetalSourceMetadata
        kernelSpec
        kind
        tuningChoice
        (Just Identity)
        FamilyProgram
        (renderMetalMetadata kernelSpec kind tuningChoice)
    LinuxCPU ->
      GeneratedOneDnnSource
        kernelSpec
        kind
        tuningChoice
        FamilyProgram
        (renderOneDnnSource kernelSpec kind tuningChoice)
    LinuxCUDA ->
      GeneratedCudaSource
        kernelSpec
        kind
        tuningChoice
        FamilyProgram
        (renderCudaSource kernelSpec kind tuningChoice)

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
runtimeSourceTag GeneratedMetalSourceMetadata {} = "GeneratedMetalSourceMetadata"

runtimeSourceSubstrate :: RuntimeSource -> Substrate
runtimeSourceSubstrate GeneratedCudaSource {} = LinuxCUDA
runtimeSourceSubstrate GeneratedOneDnnSource {} = LinuxCPU
runtimeSourceSubstrate GeneratedMetalSourceMetadata {} = AppleSilicon

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

-- | Publish a rendered source file by atomic rename from a per-invocation path.
--
-- The staging name must be unique per writer, not per destination. Rendered
-- sources are content-addressed, so concurrent publishers routinely materialise
-- the *same* address at the same time — 24 parallel single-row publishers
-- against a cold cache do it constantly. With a shared @.tmp@ name they raced:
-- the first rename moved the file, and every other writer's rename then failed
-- with \"does not exist\", killing the run. Sprint `78.1` fixed exactly this for
-- compiled artifacts; the rendered-source path had the same defect.
--
-- Overwriting the destination is safe precisely because the address is a hash of
-- the contents: every racing writer publishes identical bytes.
writeSourceFile :: FilePath -> SourceFile -> IO ()
writeSourceFile root sourceFile = do
  let path = root FilePath.</> sourceRelativePath sourceFile
  createDirectoryIfMissing True (FilePath.takeDirectory path)
  processId <- getProcessID
  unique <- hashUnique <$> newUnique
  let tmpPath =
        path <> "." <> show processId <> "." <> show unique <> ".tmp"
  Text.IO.writeFile tmpPath (sourceContents sourceFile)
  renameFile tmpPath path
