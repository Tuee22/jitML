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
  , engineCompileFlags
  , engineCompiler
  , engineEnvelope
  , engineForSubstrate
  , engineLinkFlags
  , engineSourceFileName
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
import JitML.Substrate
  ( Substrate (..)
  , SubstrateProfile (..)
  , profileFor
  , renderSubstrate
  )

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

-- | The engine record is a projection of the profile, so the two cannot
-- disagree about a substrate's backend or artifact extension.
engineForSubstrate :: Substrate -> Engine
engineForSubstrate substrate =
  Engine
    { engineSubstrate = profileSubstrate profile
    , engineBackend = profileBackend profile
    , engineArtifactExtension = profileArtifactExtension profile
    }
 where
  profile = profileFor substrate

deterministicFlags :: Engine -> [Text]
deterministicFlags = profileDeterminism . profileFor . engineSubstrate

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

-- | The program each substrate's cache-miss path invokes.
--
-- Apple cache misses are metadata writes handled in-process by
-- 'JitML.Engines.Loader'; the named program is retained only as a typed,
-- renderable diagnostic in the existing cache-miss status shape.
engineCompiler :: Engine -> Text
engineCompiler engine =
  case engineSubstrate engine of
    AppleSilicon -> "jitml-metal-metadata-cache"
    LinuxCPU -> "g++"
    LinuxCUDA -> "nvcc"

-- | The hash-free compile arguments, split out of 'compileSubprocess' so the
-- toolchain fingerprint (Sprint `78.1`) can name the flags the compile command
-- actually passes without becoming circular in the cache key: the artifact and
-- source paths depend on the hash, these do not.
engineCompileFlags :: Engine -> [Text]
engineCompileFlags engine =
  case engineSubstrate engine of
    AppleSilicon -> []
    LinuxCPU ->
      [ "-std=c++20"
      , "-O2"
      , "-fPIC"
      , "-shared"
      , "-DJITML_DETERMINISTIC_REDUCTIONS=1"
      ]
    LinuxCUDA ->
      [ "--shared"
      , "--compiler-options=-fPIC"
      , -- `--use_fast_math` is a presence flag; omitting it (the default)
        -- means fast-math is off, which is what the determinism contract
        -- requires. Earlier versions wrote `--use_fast_math=false` here;
        -- the modern nvcc parser rejects that with `no argument expected
        -- after '--use_fast_math'`. `deterministicFlags` still records
        -- `--use_fast_math=false` + `tf32=disabled` as the readable intent.
        "-arch=sm_70"
      , -- Disable FMA contraction so the device multiply-adds round the same
        -- way the CPU (oneDNN) build does with its separate multiply-then-add
        -- and fixed reduction order. With `--fmad=true` (the nvcc default) the
        -- MLP kernels contract `acc += w*x` into a fused op that rounds once
        -- instead of twice; in the chaotic RL training loop that sub-ULP skew
        -- amplifies into materially different convergence (e.g. PPO/cartpole
        -- 450 on oneDNN vs 286 on CUDA at the same seed/config). Matching the
        -- rounding makes the substrates track and keeps the determinism
        -- contract's cross-substrate intent honest.
        "--fmad=false"
      , "-DJITML_USE_CUBLAS=1"
      , "-DJITML_USE_CUDNN=1"
      ]

-- | The link arguments each substrate passes after its source file.
engineLinkFlags :: Engine -> [Text]
engineLinkFlags engine =
  case engineSubstrate engine of
    AppleSilicon -> []
    LinuxCPU -> ["-ldnnl"]
    LinuxCUDA ->
      [ -- Sprint 13.11 — the CUDA-shipped stubs dir holds a link-time
        -- `libcuda.so` that we need at compile time but not at runtime.
        -- Pass it explicitly so link succeeds without leaving stubs on
        -- LD_LIBRARY_PATH, which would otherwise shadow the real driver
        -- library injected by the NVIDIA Container Toolkit.
        "-L/usr/local/cuda/lib64/stubs"
      , "-lcudart"
      , "-lcublas"
      , "-lcudnn"
      ]

-- | The generated source file each substrate compiles.
engineSourceFileName :: Engine -> Text
engineSourceFileName engine =
  case engineSubstrate engine of
    AppleSilicon -> "kernel.metal.json"
    LinuxCPU -> "kernel.cc"
    LinuxCUDA -> "kernel.cu"

compileSubprocess :: Engine -> RuntimeSource -> Cache.Hash -> Subprocess
compileSubprocess engine source hash =
  subprocess (Text.unpack (engineCompiler engine)) arguments
 where
  sourceDir = Text.pack (runtimeSourceRelativeDirectory source hash)
  sourcePath = sourceDir <> "/" <> engineSourceFileName engine
  artifact = artifactPathText engine hash
  arguments =
    case engineSubstrate engine of
      AppleSilicon -> [artifact, sourcePath]
      LinuxCPU -> hostCompileArguments
      LinuxCUDA -> hostCompileArguments
  hostCompileArguments =
    engineCompileFlags engine
      <> ["-o", artifact, sourcePath]
      <> engineLinkFlags engine

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
