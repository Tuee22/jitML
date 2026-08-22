{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

-- | The one closed substrate set, its one renderer, and its one wire codec.
--
-- Sprint `78.1` folded the structurally identical second copy that lived in
-- 'JitML.Cache.Key' into this module: the cache key needs a serialisable
-- substrate, but it needs /this/ substrate, not a parallel type with a parallel
-- renderer and codec. 'JitML.Cache.Key' now re-exports this type and defines
-- @substrateText = renderSubstrate@, so the on-disk cache layout and the CLI
-- cannot disagree about what a substrate is called.
module JitML.Substrate
  ( ArtifactFill (..)
  , ArtifactProducer (..)
  , InternalLinkageStyle (..)
  , KernelLaunch (..)
  , PinnedNonDeterminism (..)
  , Substrate (..)
  , SubstrateProfile (..)
  , allSubstrates
  , profileFor
  , producerPins
  , substrateLinkage
  , parseSubstrate
  , renderSubstrate
  , substrateClusterName
  , substrateEdgePort
  , substrateHasClusterCompute
  , substrateRuntimeClass
  )
where

import Codec.Serialise (Serialise)
import Data.Aeson (FromJSON (..), ToJSON (..), Value (..), withText)
import Data.Text (Text)
import Data.Text qualified as Text
import GHC.Generics (Generic)

data Substrate
  = AppleSilicon
  | LinuxCPU
  | LinuxCUDA
  deriving stock (Bounded, Enum, Eq, Generic, Ord, Show)
  deriving anyclass (Serialise)

instance ToJSON Substrate where
  toJSON = String . renderSubstrate

instance FromJSON Substrate where
  parseJSON =
    withText "Substrate" $ \value ->
      case parseSubstrate value of
        Just substrate -> pure substrate
        Nothing -> fail ("unknown substrate: " <> Text.unpack value)

allSubstrates :: [Substrate]
allSubstrates = [minBound .. maxBound]

renderSubstrate :: Substrate -> Text
renderSubstrate AppleSilicon = "apple-silicon"
renderSubstrate LinuxCPU = "linux-cpu"
renderSubstrate LinuxCUDA = "linux-cuda"

parseSubstrate :: Text -> Maybe Substrate
parseSubstrate "apple-silicon" = Just AppleSilicon
parseSubstrate "linux-cpu" = Just LinuxCPU
parseSubstrate "linux-cuda" = Just LinuxCUDA
parseSubstrate _ = Nothing

substrateClusterName :: Substrate -> Text
substrateClusterName substrate = "jitml-" <> renderSubstrate substrate

-- | How a substrate's cache miss fills its artifact. A total two-arm choice, so
-- the loader dispatches on a value rather than on a wildcard over 'Substrate'.
data ArtifactFill
  = -- | Materialize the generated source and run the typed compile 'Subprocess'.
    CompileSubprocessFill
  | -- | Write @\<hash\>.metal.json@ source metadata in-process.
    SourceMetadataWriteFill
  deriving stock (Eq, Show)

-- | How a substrate enters a compiled artifact. The @dlopen@/@dlsym@ versus
-- fixed-Metal-bridge difference is a value here rather than a branch inside
-- otherwise-generic code (Sprint `79.1`).
data KernelLaunch
  = -- | Resolve a symbol out of the loaded shared object.
    LoadableSymbolLaunch
  | -- | Dispatch through the fixed host Metal bridge.
    FixedBridgeLaunch
  deriving stock (Eq, Show)

-- | How a native renderer gives a file-scope helper internal linkage.
--
-- Sprint `78.1` — this is a substrate fact rather than a renderer preference,
-- because the two styles are not interchangeable under every compiler. @g++@
-- mangles an anonymous namespace deterministically; @cudafe@ mangles it
-- @_GLOBAL__N__\<random\>@, so the same source compiles to different bytes each
-- time. The lane whose artifact bytes are attested keeps the style its attested
-- bytes were produced with.
data InternalLinkageStyle
  = -- | @static@ free functions. Deterministic mangling under every compiler.
    StaticFunctions
  | -- | An anonymous namespace. Retained on @linux-cpu@: @g++@ mangles it
    -- deterministically and Sprint `263.1` pins those artifact bytes.
    AnonymousNamespace
  deriving stock (Bounded, Enum, Eq, Ord, Show)

-- | One way an artifact producer would inject an input that is __not__ a
-- cache-key input, paired with the pin that removes it.
--
-- Sprint `78.1` — there is deliberately no @Unpinned@ constructor. A producer
-- description cannot carry a known non-determinism source without also carrying
-- its remedy, so "we know about this and have not fixed it" is unrepresentable.
--
-- What the type cannot do is prove the set is __complete__; no type can. That is
-- the double-compile gate's job (@jitml-backends@), which detects a source
-- nobody has enumerated yet — including on the lanes whose set is empty.
data PinnedNonDeterminism
  = -- | The compiler derives an embedded identifier from its own intermediate
    -- file names. @nvcc@ names them @tmpxft_\<pid\>_…@, so the artifact carries
    -- the compiler's process id. Pinned by directing it at a caller-chosen
    -- scratch directory, whose path is not itself embedded.
    IntermediateFileNaming
  | -- | The compiler generates a random identifier for symbols that must be
    -- unique per translation unit. Pinned by rendering the construct that
    -- triggers it in the substrate's 'InternalLinkageStyle'.
    SymbolMangling
  deriving stock (Bounded, Enum, Eq, Ord, Show)

-- | The closed set of non-determinism sources a substrate's artifact producer
-- has, each already paired with its pin.
--
-- An empty set is a positive claim — "this producer injects nothing" — not an
-- omission. @linux-cpu@ carries it because @g++@ was measured reproducible both
-- for repeated compiles and across output names; @apple-silicon@ carries it
-- because there is no compiler at all: the artifact __is__ the rendered
-- document.
newtype ArtifactProducer = ArtifactProducer
  { producerNonDeterminism :: [PinnedNonDeterminism]
  }
  deriving stock (Eq, Show)

-- | Every fact that varies by substrate, in one record.
--
-- Sprint `79.1` replaced the scattered @case substrate of@ sites that restated
-- the same fact with reads off this record. Adding a substrate means filling
-- one more 'profileFor' equation, and every consumer stays total by
-- construction: 'profileFor' has one equation per constructor and no wildcard,
-- so a fourth substrate is a build failure under
-- @-Werror=incomplete-patterns@ rather than a silent default.
data SubstrateProfile = SubstrateProfile
  { profileSubstrate :: !Substrate
  , profileBackend :: !Text
  , profileArtifactExtension :: !Text
  , profileDeterminism :: ![Text]
  -- ^ The determinism properties this substrate's __runtime__ establishes,
  -- which no compile line and no kernel body states. Compile-line facts are
  -- derived from the compile arguments by
  -- 'JitML.Engines.Engine.compileLineDeterminism', and kernel-body facts are
  -- already keyed through the rendered-source cache-key input, so neither is
  -- restated here (Sprint `78.1`).
  , profileProducer :: !ArtifactProducer
  -- ^ The closed set of non-determinism sources this substrate's artifact
  -- producer has, each paired with its pin (Sprint `78.1`).
  , profileLinkage :: !InternalLinkageStyle
  -- ^ The internal-linkage style this substrate's native renderers emit.
  , profileLaunch :: !KernelLaunch
  , profileArtifactFill :: !ArtifactFill
  , profileHasClusterCompute :: !Bool
  , profileEdgePort :: !Int
  , profileRuntimeClass :: !(Maybe Text)
  }
  deriving stock (Eq, Show)

profileFor :: Substrate -> SubstrateProfile
profileFor AppleSilicon =
  SubstrateProfile
    { profileSubstrate = AppleSilicon
    , profileBackend = "metal"
    , profileArtifactExtension = "metal.json"
    , profileDeterminism =
        ["single-stream-launch-order", "fixed-metal-bridge", "source-metadata-cache"]
    , -- No compiler runs: the artifact is the rendered `.metal.json` document,
      -- so it is reproducible by construction and there is nothing to pin.
      profileProducer = ArtifactProducer []
    , profileLinkage = StaticFunctions
    , profileLaunch = FixedBridgeLaunch
    , profileArtifactFill = SourceMetadataWriteFill
    , profileHasClusterCompute = False
    , profileEdgePort = 9090
    , profileRuntimeClass = Nothing
    }
profileFor LinuxCPU =
  SubstrateProfile
    { profileSubstrate = LinuxCPU
    , profileBackend = "onednn"
    , profileArtifactExtension = "so"
    , profileDeterminism = ["onednn-fixed-block-reduction", "avx2-baseline"]
    , -- Measured empty: `g++` emits identical bytes for repeated compiles of one
      -- source and across differing output names, so no argument is needed. An
      -- unnecessary pin here would be a regression rather than hardening —
      -- supplying `-frandom-seed` changes anonymous-namespace symbols, and this
      -- lane's artifact bytes are attested by Sprint `263.1`.
      profileProducer = ArtifactProducer []
    , profileLinkage = AnonymousNamespace
    , profileLaunch = LoadableSymbolLaunch
    , profileArtifactFill = CompileSubprocessFill
    , profileHasClusterCompute = True
    , profileEdgePort = 9091
    , profileRuntimeClass = Nothing
    }
profileFor LinuxCUDA =
  SubstrateProfile
    { profileSubstrate = LinuxCUDA
    , profileBackend = "cuda"
    , profileArtifactExtension = "so"
    , -- Every determinism fact this lane can state is established either by the
      -- compile line, which 'JitML.Engines.Engine.compileLineDeterminism'
      -- derives, or by a kernel body, which the rendered-source payload already
      -- keys. Sprint `78.1` removed the four entries that used to sit here:
      -- `--use_fast_math=false` is passed by no compile line, `--fmad=false` is
      -- now read off the compile arguments themselves, and
      -- `cudnn-explicit-algorithm-id` / `warp-shuffle-deterministic` described
      -- the family and layer-training kernels rather than every CUDA artifact —
      -- the trainer MLP kernel uses neither cuDNN nor warp shuffles, yet keyed
      -- on both.
      profileDeterminism = []
    , -- `nvcc` injects two inputs the cache key never sees: its own process id,
      -- through the `tmpxft_<pid>_…` intermediate names it embeds, and a random
      -- per-translation-unit id for anonymous-namespace symbols.
      profileProducer = ArtifactProducer [IntermediateFileNaming, SymbolMangling]
    , profileLinkage = StaticFunctions
    , profileLaunch = LoadableSymbolLaunch
    , profileArtifactFill = CompileSubprocessFill
    , profileHasClusterCompute = True
    , profileEdgePort = 9092
    , profileRuntimeClass = Just "nvidia"
    }

-- | The non-determinism sources a substrate's producer has, each already pinned.
producerPins :: Substrate -> [PinnedNonDeterminism]
producerPins = producerNonDeterminism . profileProducer . profileFor

-- | The internal-linkage style a substrate's native renderers emit.
substrateLinkage :: Substrate -> InternalLinkageStyle
substrateLinkage = profileLinkage . profileFor

-- | Projections of the one profile. The former per-function @case substrate of@
-- equations are gone, and with them the @_ -> Nothing@ wildcard that let a new
-- substrate silently inherit "no runtime class".
substrateEdgePort :: Substrate -> Int
substrateEdgePort = profileEdgePort . profileFor

substrateRuntimeClass :: Substrate -> Maybe Text
substrateRuntimeClass = profileRuntimeClass . profileFor

-- | Whether a substrate runs numerical work inside the Kubernetes cluster.
-- @apple-silicon@ does not: its Metal work is host-resident. This was restated
-- in five shapes across four modules before Sprint `79.1`.
substrateHasClusterCompute :: Substrate -> Bool
substrateHasClusterCompute = profileHasClusterCompute . profileFor
