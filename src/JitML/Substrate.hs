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
  , KernelLaunch (..)
  , Substrate (..)
  , SubstrateProfile (..)
  , allSubstrates
  , profileFor
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
    , profileLaunch = LoadableSymbolLaunch
    , profileArtifactFill = CompileSubprocessFill
    , profileHasClusterCompute = True
    , profileEdgePort = 9092
    , profileRuntimeClass = Just "nvidia"
    }

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
