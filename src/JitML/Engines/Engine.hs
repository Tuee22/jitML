{-# LANGUAGE OverloadedStrings #-}

module JitML.Engines.Engine
    ( Engine (..)
    , deterministicFlags
    , engineForSubstrate
    , renderEnginePlan
    )
where

import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Substrate (Substrate (..), renderSubstrate)

data Engine = Engine
    { engineSubstrate :: Substrate
    , engineBackend :: Text
    , engineCodegenDir :: FilePath
    , engineArtifactExtension :: Text
    }
    deriving stock (Eq, Show)

engineForSubstrate :: Substrate -> Engine
engineForSubstrate AppleSilicon = Engine AppleSilicon "metal" "codegen-metal" "dylib"
engineForSubstrate LinuxCPU = Engine LinuxCPU "onednn" "codegen-onednn" "so"
engineForSubstrate LinuxCUDA = Engine LinuxCUDA "cuda" "codegen-cuda" "so"

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
        , "codegen_dir: " <> Text.pack (engineCodegenDir engine)
        , "artifact_extension: " <> engineArtifactExtension engine
        , "determinism:"
        , "  - " <> Text.intercalate "\n  - " (deterministicFlags engine)
        ]
