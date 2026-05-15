{-# LANGUAGE OverloadedStrings #-}

module JitML.Engines.Engine
  ( Engine (..)
  , compileSubprocess
  , deterministicFlags
  , engineForSubstrate
  , renderBuildPlan
  , renderEnginePlan
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
import JitML.Tart.Exec (tartSshSubprocess)
import JitML.Tart.Lifecycle (VmName (..))

data Engine = Engine
  { engineSubstrate :: Substrate
  , engineBackend :: Text
  , engineArtifactExtension :: Text
  }
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

compileSubprocess :: Engine -> RuntimeSource -> Cache.Hash -> Subprocess
compileSubprocess engine source hash =
  case engineSubstrate engine of
    AppleSilicon ->
      tartSshSubprocess
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
        ]
    LinuxCUDA ->
      subprocess
        "nvcc"
        [ "--shared"
        , "--compiler-options=-fPIC"
        , "--use_fast_math=false"
        , "-arch=sm_70"
        , "-o"
        , artifactPathText engine hash
        , sourceDir <> "/kernel.cu"
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
