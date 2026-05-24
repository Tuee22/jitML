{-# LANGUAGE OverloadedStrings #-}

module JitML.Engines.Engine
  ( Engine (..)
  , EngineEnvelope (..)
  , JitCacheStatus (..)
  , KernelHandle (..)
  , KernelInputs (..)
  , KernelOutputs (..)
  , compileSubprocess
  , deterministicFlags
  , engineEnvelope
  , engineForSubstrate
  , kernelHandleFor
  , renderBuildPlan
  , renderEngineEnvelope
  , renderEnginePlan
  , resolveKernelCache
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Cache.Key qualified as Cache
import JitML.Codegen.RuntimeSource
  ( RuntimeSource
  , runtimeSourceRelativeDirectory
  )
import JitML.Sub.Render (renderSubprocess)
import JitML.Sub.Subprocess (Subprocess, subprocess)
import JitML.Substrate (Substrate (..), renderSubstrate)
import JitML.Tart.Exec (tartExecSubprocess)
import JitML.Tart.Lifecycle (VmName (..))

data Engine = Engine
  { engineSubstrate :: Substrate
  , engineBackend :: Text
  , engineArtifactExtension :: Text
  }
  deriving stock (Eq, Show)

data KernelHandle = KernelHandle
  { kernelHandleEngine :: Engine
  , kernelHandleHash :: Cache.Hash
  , kernelHandleArtifactPath :: Text
  }
  deriving stock (Eq, Show)

data KernelInputs = KernelInputs
  { kernelInputShape :: [Int]
  , kernelInputBytes :: Int
  }
  deriving stock (Eq, Show)

data KernelOutputs = KernelOutputs
  { kernelOutputShape :: [Int]
  , kernelOutputBytes :: Int
  }
  deriving stock (Eq, Show)

data EngineEnvelope = EngineEnvelope
  { envelopeHandle :: KernelHandle
  , envelopeInputs :: KernelInputs
  , envelopeOutputs :: KernelOutputs
  , envelopeDeterminism :: [Text]
  , envelopeCompileCommand :: Text
  }
  deriving stock (Eq, Show)

data JitCacheStatus
  = JitCacheHit KernelHandle
  | JitCacheMiss KernelHandle Subprocess
  deriving stock (Eq, Show)

engineForSubstrate :: Substrate -> Engine
engineForSubstrate AppleSilicon = Engine AppleSilicon "metal" "dylib"
engineForSubstrate LinuxCPU = Engine LinuxCPU "onednn" "so"
engineForSubstrate LinuxCUDA = Engine LinuxCUDA "cuda" "so"

deterministicFlags :: Engine -> [Text]
deterministicFlags engine =
  case engineSubstrate engine of
    AppleSilicon -> ["single-stream-launch-order", "stable-ffi-symlink"]
    LinuxCPU -> ["onednn-fixed-block-reduction", "avx2-baseline"]
    LinuxCUDA -> ["--use_fast_math=false", "cudnn-explicit-algorithm-id", "warp-shuffle-deterministic"]

renderEnginePlan :: Engine -> Text
renderEnginePlan engine =
  Text.unlines
    [ "substrate: " <> renderSubstrate (engineSubstrate engine)
    , "backend: " <> engineBackend engine
    , "artifact_extension: " <> engineArtifactExtension engine
    , "determinism:"
    , "  - " <> Text.intercalate "\n  - " (deterministicFlags engine)
    ]

renderBuildPlan :: Engine -> RuntimeSource -> Cache.Hash -> Text
renderBuildPlan engine source hash =
  Text.unlines
    [ renderEnginePlan engine
    , "generated_source_dir: " <> Text.pack (runtimeSourceRelativeDirectory source hash)
    , "cache_artifact: " <> artifactPathText engine hash
    , "compile:"
    , "  - " <> renderSubprocess (compileSubprocess engine source hash)
    ]

kernelHandleFor :: Engine -> Cache.Hash -> KernelHandle
kernelHandleFor engine hash =
  KernelHandle
    { kernelHandleEngine = engine
    , kernelHandleHash = hash
    , kernelHandleArtifactPath = artifactPathText engine hash
    }

resolveKernelCache :: Engine -> RuntimeSource -> Cache.Hash -> Bool -> JitCacheStatus
resolveKernelCache engine source hash cacheArtifactExists =
  let handle = kernelHandleFor engine hash
   in if cacheArtifactExists
        then JitCacheHit handle
        else JitCacheMiss handle (compileSubprocess engine source hash)

engineEnvelope
  :: Engine -> RuntimeSource -> Cache.Hash -> KernelInputs -> KernelOutputs -> EngineEnvelope
engineEnvelope engine source hash inputs outputs =
  EngineEnvelope
    { envelopeHandle = kernelHandleFor engine hash
    , envelopeInputs = inputs
    , envelopeOutputs = outputs
    , envelopeDeterminism = deterministicFlags engine
    , envelopeCompileCommand = renderSubprocess (compileSubprocess engine source hash)
    }

renderEngineEnvelope :: EngineEnvelope -> Text
renderEngineEnvelope envelope =
  Text.unlines
    [ "artifact: " <> kernelHandleArtifactPath handle
    , "backend: " <> engineBackend (kernelHandleEngine handle)
    , "input_shape: " <> renderIntList (kernelInputShape (envelopeInputs envelope))
    , "input_bytes: " <> Text.pack (show (kernelInputBytes (envelopeInputs envelope)))
    , "output_shape: " <> renderIntList (kernelOutputShape (envelopeOutputs envelope))
    , "output_bytes: " <> Text.pack (show (kernelOutputBytes (envelopeOutputs envelope)))
    , "determinism:"
    , "  - " <> Text.intercalate "\n  - " (envelopeDeterminism envelope)
    , "compile: " <> envelopeCompileCommand envelope
    ]
 where
  handle = envelopeHandle envelope

compileSubprocess :: Engine -> RuntimeSource -> Cache.Hash -> Subprocess
compileSubprocess engine source hash =
  case engineSubstrate engine of
    AppleSilicon ->
      tartExecSubprocess
        (VmName "jitml-build")
        ["swift", "build", "--package-path", sourceDir, "-c", "release"]
    LinuxCPU ->
      subprocess
        "g++"
        [ "-std=c++20"
        , "-O2"
        , "-fPIC"
        , "-shared"
        , "-DJITML_DETERMINISTIC_REDUCTIONS=1"
        , "-o"
        , artifactPathText engine hash
        , sourceDir <> "/kernel.cc"
        , "-ldnnl"
        ]
    LinuxCUDA ->
      subprocess
        "nvcc"
        [ "--shared"
        , "--compiler-options=-fPIC"
        , "--use_fast_math=false"
        , "-arch=sm_70"
        , "-DJITML_USE_CUBLAS=1"
        , "-DJITML_USE_CUDNN=1"
        , "-o"
        , artifactPathText engine hash
        , sourceDir <> "/kernel.cu"
        , "-lcudart"
        , "-lcublas"
        , "-lcudnn"
        ]
 where
  sourceDir = Text.pack (runtimeSourceRelativeDirectory source hash)

artifactPathText :: Engine -> Cache.Hash -> Text
artifactPathText engine hash =
  Text.concat
    [ ".build/jit/"
    , renderSubstrate (engineSubstrate engine)
    , "/"
    , Cache.hashHex hash
    , "."
    , engineArtifactExtension engine
    ]

renderIntList :: [Int] -> Text
renderIntList values =
  "[" <> Text.intercalate ", " (fmap (Text.pack . show) values) <> "]"
