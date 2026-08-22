{-# LANGUAGE OverloadedStrings #-}

-- | Sprint 78.1 — every JIT cache key's toolchain fingerprint, __derived__ from
-- the toolchain and the emitter set it covers.
--
-- Before this sprint each of the eight fingerprints was hand-written prose
-- restating C signatures beside the renderer that emits them, and the prose had
-- already drifted three ways:
--
--   * it described a compile command that no longer matched — the @linux-cpu@
--     entry omitted @-O2@, @-fPIC@ and @-ldnnl@, the CUDA entry omitted the
--     stubs link path and the cuBLAS/cuDNN defines — and because
--     'JitML.Engines.Engine.compileSubprocess' is not itself a cache-key input,
--     a flag or link-line change invalidated nothing at all;
--   * one fingerprint described an @extern "C"@ ABI its artifact does not
--     export: the Apple MLP artifact is Metal source metadata whose entry
--     points are MSL kernels, and the C name it claimed
--     (@jitml_mlp_forward@) is defined in no rendered source;
--   * the Metal bridge-ABI token was interpolated at one site and hardcoded at
--     another, so bumping it invalidated one lane and not the other.
--
-- Here every fingerprint is a rendering of 'ToolchainFacts', and every field is
-- read off the thing it describes: the compiler, its flags, and its link line
-- come from 'JitML.Engines.Engine.engineCompiler' /
-- 'JitML.Engines.Engine.engineCompileFlags' /
-- 'JitML.Engines.Engine.engineLinkFlags' — the same lists
-- 'JitML.Engines.Engine.compileSubprocess' passes, so a flag edit moves the
-- command and the fingerprint together; the determinism facts come from
-- 'JitML.Engines.Engine.deterministicFlags', itself a projection of that same
-- argument list plus the substrate's runtime properties, so no fingerprint can
-- advertise a determinism argument its compile line does not pass; the ABI is a
-- typed 'AbiKind', so
-- the Metal bridge token is interpolated from
-- 'JitML.Codegen.Metal.metalBridgeAbiVersion' at every site by construction;
-- the numeric knobs come from the renderers' own constants
-- ('JitML.Codegen.OneDnn.oneDnnFixedReductionBlock',
-- 'JitML.Codegen.Metal.threadgroupSizeFor'); and the emitter set comes from the
-- vocabulary the artifact covers — 'JitML.Codegen.KernelFamily.kernelFamilies'
-- for the family kernels, 'JitML.Numerics.LayerGraph.allLayerKinds' for the
-- layer-graph training kernel — so widening either vocabulary invalidates the
-- artifacts that execute it.
--
-- Rendered kernel bodies are deliberately __not__ restated here: the rendered
-- source payload is already a separate cache-key input
-- ('JitML.Cache.Key.cacheKey'), so a renderer body change invalidates its
-- artifact through the payload. The fingerprint's job is the toolchain, the
-- ABI, and the vocabulary.
--
-- Every entry point is total over 'Substrate'. There is no shared fallback
-- literal, so a substrate cannot inherit a fingerprint that names no compiler.
module JitML.Engines.Fingerprint
  ( -- * Facts
    AbiKind (..)
  , ToolchainFacts (..)
  , toolchainFingerprint
  , renderAbiKind
  , hostArtifactAbi

    -- * Derived fingerprints
  , buildToolchainFingerprint
  , engineFamilyToolchainFingerprint
  , mlpToolchainFingerprint
  , layerTrainingToolchainFingerprint

    -- * The entry points each fingerprint names
  , familyKernelEntryPoints
  , metalFamilyEntryPoints
  , mlpHostEntryPoints
  , mlpMetalEntryPoints
  , layerTrainingEntryPoints
  )
where

import Data.Text (Text)
import Data.Text qualified as Text
import System.Info qualified as SystemInfo

import JitML.Cache.Key qualified as Cache
import JitML.Codegen.CudaLayerTraining (cudaLayerTrainingDeterminismChoices)
import JitML.Codegen.KernelFamily (familyName, kernelFamilies)
import JitML.Codegen.Metal (metalBridgeAbiVersion, threadgroupSizeFor)
import JitML.Codegen.OneDnn (oneDnnFixedReductionBlock)
import JitML.Codegen.RuntimeSource (KernelProgram (..))
import JitML.Engines.Engine
  ( compileLineReproducibility
  , deterministicFlags
  , engineCompileFlags
  , engineCompiler
  , engineForSubstrate
  , engineLinkFlags
  )
import JitML.Numerics.LayerGraph (allLayerKinds, layerKindName)
import JitML.Substrate (Substrate (..))

-- | How a compiled artifact is entered. 'FixedMetalBridge' carries the bridge
-- ABI version, so the token cannot be written as a literal at a call site.
data AbiKind
  = ExternC
  | ExternCHostWrapper
  | ExternCLayerGraphTraining
  | FixedMetalBridge !Text
  deriving stock (Eq, Show)

renderAbiKind :: AbiKind -> [Text]
renderAbiKind kind =
  case kind of
    ExternC -> ["abi=extern-c"]
    ExternCHostWrapper -> ["abi=extern-c-host-wrapper"]
    ExternCLayerGraphTraining -> ["abi=extern-c-layer-graph-training"]
    FixedMetalBridge version ->
      [ "abi=fixed-bridge-host-buffers"
      , "bridge-abi=" <> version
      ]

-- | Everything a cache key must separate on, each field derived from the
-- surface it describes rather than restated beside it.
data ToolchainFacts = ToolchainFacts
  { factsCompiler :: !Text
  , factsCompileFlags :: ![Text]
  , factsLinkFlags :: ![Text]
  , factsDeterminism :: ![Text]
  , factsReproducibility :: ![Text]
  , factsKnobs :: ![Text]
  , factsAbi :: !AbiKind
  , factsEntryPoints :: ![Text]
  , factsEmitters :: ![Text]
  }
  deriving stock (Eq, Show)

-- | Render facts into the on-disk fingerprint. The host artifact ABI is added
-- here rather than at each site, so no fingerprint can forget it.
toolchainFingerprint :: ToolchainFacts -> Cache.ToolchainFingerprint
toolchainFingerprint facts =
  Cache.ToolchainFingerprint
    ( Text.intercalate
        ";"
        ( [ factsCompiler facts
          , "artifact-abi=" <> hostArtifactAbi
          , labelled "flags" (factsCompileFlags facts)
          , labelled "link" (factsLinkFlags facts)
          , labelled "determinism" (factsDeterminism facts)
          , labelled "reproducibility" (factsReproducibility facts)
          , labelled "knobs" (factsKnobs facts)
          ]
            <> renderAbiKind (factsAbi facts)
            <> [ labelled "entry" (factsEntryPoints facts)
               , labelled "emitters" (factsEmitters facts)
               ]
        )
    )
 where
  labelled label values = label <> "=" <> Text.intercalate "," values

-- | The host's OS and architecture, so a container-built artifact and a
-- host-built artifact never share a cache slot.
hostArtifactAbi :: Text
hostArtifactAbi = Text.pack SystemInfo.os <> "-" <> Text.pack SystemInfo.arch

-- | The four @extern "C"@ entry points a host-compiled family kernel exports.
familyKernelEntryPoints :: [Text]
familyKernelEntryPoints =
  [ "jitml_kernel"
  , "jitml_weighted_kernel"
  , "jitml_kernel_family_name"
  , "jitml_kernel_output_count"
  ]

-- | The two MSL kernels an Apple family artifact defines. The family name and
-- the output count are metadata fields of the rendered @.metal.json@, not
-- callable entry points, so naming the host C pair here would describe symbols
-- the artifact does not expose.
metalFamilyEntryPoints :: [Text]
metalFamilyEntryPoints =
  [ "jitml_kernel"
  , "jitml_weighted_kernel"
  ]

-- | The five host-callable MLP entry points the oneDNN and CUDA renderers
-- export.
mlpHostEntryPoints :: [Text]
mlpHostEntryPoints =
  [ -- Sprint `229.1` — the MLP artifact declares its own executed identity, so
    -- the device-execution witness reads what ran rather than resolving a
    -- family symbol the artifact never exported.
    "jitml_kernel_family_name"
  , "jitml_mlp_forward"
  , "jitml_mlp_backward"
  , "jitml_mlp_batch_gradient"
  , "jitml_mlp_forward_batch"
  , "jitml_mlp_input_gradient_batch"
  ]

-- | The ten MSL kernels the Apple MLP artifact actually defines. The Apple
-- artifact is Metal source metadata, not a shared library: it exports no C
-- symbols, so naming a host C ABI here would describe an ABI that does not
-- exist.
mlpMetalEntryPoints :: [Text]
mlpMetalEntryPoints =
  [ "jitml_mlp_hidden"
  , "jitml_mlp_output"
  , "jitml_mlp_grad_output"
  , "jitml_mlp_grad_hidden"
  , "jitml_mlp_batch_hidden"
  , "jitml_mlp_batch_output"
  , "jitml_mlp_batch_grad_output"
  , "jitml_mlp_batch_grad_hidden"
  , "jitml_mlp_dpre_batch"
  , "jitml_mlp_dx_batch"
  ]

-- | The layer-graph training kernel's exported entry points.
layerTrainingEntryPoints :: [Text]
layerTrainingEntryPoints =
  [ "jitml_layer_forward"
  , "jitml_layer_backward_data"
  , "jitml_layer_backward_weights"
  , "jitml_conv2d_spatial_forward"
  , "jitml_conv2d_spatial_backward_data"
  , "jitml_conv2d_spatial_backward_weights"
  , -- Sprint `241.1` — the 3-D spatial convolution is a real device kernel
    -- rather than a fail-closed rejection, so the artifact exports it and this
    -- vocabulary keys on it.
    "jitml_conv3d_spatial_forward"
  , "jitml_conv3d_spatial_backward_data"
  , "jitml_conv3d_spatial_backward_weights"
  , "jitml_op_train"
  , "jitml_layer_training_backend"
  , "jitml_layer_forward_primitive"
  , "jitml_layer_backward_data_primitive"
  , "jitml_layer_backward_weights_primitive"
  ]

-- | The kernel-family emitter set, derived from the family vocabulary rather
-- than a hand-written @all-families@ tag.
familyEmitters :: [Text]
familyEmitters = fmap familyName kernelFamilies

-- | The layer-graph training emitter set, derived from the declared layer kinds
-- the IR executes. Widening the operator vocabulary therefore invalidates the
-- training artifact automatically.
layerTrainingEmitters :: [Text]
layerTrainingEmitters = fmap layerKindName allLayerKinds

abiFor :: Substrate -> AbiKind
abiFor substrate =
  case substrate of
    AppleSilicon -> FixedMetalBridge metalBridgeAbiVersion
    LinuxCPU -> ExternC
    LinuxCUDA -> ExternCHostWrapper

-- | Renderer constants that change numerical behaviour without changing the
-- toolchain, read off the renderer that emits them.
familyKnobs :: Substrate -> [Text]
familyKnobs substrate =
  case substrate of
    AppleSilicon ->
      [ "threadgroup-" <> familyName family <> "=" <> tshow (threadgroupSizeFor family)
      | family <- kernelFamilies
      ]
    LinuxCPU -> ["reduction-block=" <> tshow oneDnnFixedReductionBlock]
    LinuxCUDA -> []

tshow :: (Show value) => value -> Text
tshow = Text.pack . show

-- | The generated per-family kernel fingerprint for a substrate.
engineFamilyToolchainFingerprint :: Substrate -> Cache.ToolchainFingerprint
engineFamilyToolchainFingerprint substrate =
  toolchainFingerprint
    ToolchainFacts
      { factsCompiler = engineCompiler engine
      , factsCompileFlags = engineCompileFlags engine FamilyProgram
      , factsLinkFlags = engineLinkFlags engine FamilyProgram
      , factsDeterminism = deterministicFlags engine
      , factsReproducibility = compileLineReproducibility engine
      , factsKnobs = familyKnobs substrate
      , factsAbi = abiFor substrate
      , factsEntryPoints = familyEntryPoints
      , factsEmitters = familyEmitters
      }
 where
  engine = engineForSubstrate substrate
  familyEntryPoints =
    case substrate of
      AppleSilicon -> metalFamilyEntryPoints
      LinuxCPU -> familyKernelEntryPoints
      LinuxCUDA -> familyKernelEntryPoints

-- | The shared-MLP kernel fingerprint for a substrate. Apple names its MSL
-- kernels; the host-compiled substrates name their C entry points.
mlpToolchainFingerprint :: Substrate -> Cache.ToolchainFingerprint
mlpToolchainFingerprint substrate =
  toolchainFingerprint
    ToolchainFacts
      { factsCompiler = engineCompiler engine
      , factsCompileFlags = engineCompileFlags engine MlpProgram
      , factsLinkFlags = engineLinkFlags engine MlpProgram
      , factsDeterminism = deterministicFlags engine
      , factsReproducibility = compileLineReproducibility engine
      , factsKnobs = mlpKnobs
      , factsAbi = abiFor substrate
      , factsEntryPoints = mlpEntryPoints
      , factsEmitters = ["mlp-forward-backward-tanh-linear"]
      }
 where
  engine = engineForSubstrate substrate
  mlpEntryPoints =
    case substrate of
      AppleSilicon -> mlpMetalEntryPoints
      LinuxCPU -> mlpHostEntryPoints
      LinuxCUDA -> mlpHostEntryPoints
  mlpKnobs =
    case substrate of
      AppleSilicon -> []
      LinuxCPU -> ["reduction-block=" <> tshow oneDnnFixedReductionBlock]
      LinuxCUDA -> []

-- | The layer-graph training kernel fingerprint for a lane. Sprint @264.1@ made
-- it substrate-taking: the @linux-cpu@ and @linux-cuda@ artifacts render the same
-- entry-point vocabulary over different primitives, so they must key on their own
-- compiler, flags, link line, and renderer constants or one lane would install at
-- the other's cache address. Its emitter set is the executed operator vocabulary,
-- so Sprint @241.1@ widening that vocabulary invalidates the training artifact
-- without touching this module.
layerTrainingToolchainFingerprint :: Substrate -> Cache.ToolchainFingerprint
layerTrainingToolchainFingerprint substrate =
  toolchainFingerprint
    ToolchainFacts
      { factsCompiler = engineCompiler engine
      , factsCompileFlags = engineCompileFlags engine LayerTrainingProgram
      , factsLinkFlags = engineLinkFlags engine LayerTrainingProgram
      , factsDeterminism = deterministicFlags engine
      , factsReproducibility = compileLineReproducibility engine
      , factsKnobs = layerTrainingKnobs substrate
      , factsAbi = ExternCLayerGraphTraining
      , factsEntryPoints = layerTrainingEntryPoints
      , factsEmitters = layerTrainingEmitters
      }
 where
  engine = engineForSubstrate substrate

-- | Renderer constants the layer-training kernel bakes in. The @linux-cpu@
-- artifact reduces in the pinned oneDNN block; the CUDA artifact pins its math
-- mode and its deterministic cuDNN algorithm choices instead, so the two lanes
-- key on different constants and cannot collide in the cache.
--
-- Both sides are read off the renderer that emits them —
-- 'JitML.Codegen.OneDnn.oneDnnFixedReductionBlock' and
-- 'JitML.Codegen.CudaLayerTraining.cudaLayerTrainingDeterminismChoices' — so a
-- lane cannot be addressed by an algorithm choice its source stopped making
-- (Sprint `78.1`).
layerTrainingKnobs :: Substrate -> [Text]
layerTrainingKnobs substrate =
  case substrate of
    AppleSilicon -> []
    LinuxCPU -> ["reduction-block=" <> tshow oneDnnFixedReductionBlock]
    LinuxCUDA -> cudaLayerTrainingDeterminismChoices

-- | The fingerprint @jitml build@ keys its artifact on. Total over 'Substrate',
-- and equal to the per-substrate family fingerprint, so the build path and the
-- benchmark-tuning candidate runners cannot key the same artifact differently.
buildToolchainFingerprint :: Substrate -> Cache.ToolchainFingerprint
buildToolchainFingerprint substrate =
  case substrate of
    AppleSilicon -> engineFamilyToolchainFingerprint AppleSilicon
    LinuxCPU -> engineFamilyToolchainFingerprint LinuxCPU
    LinuxCUDA -> engineFamilyToolchainFingerprint LinuxCUDA
