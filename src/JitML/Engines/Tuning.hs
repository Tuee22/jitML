{-# LANGUAGE OverloadedStrings #-}

module JitML.Engines.Tuning
  ( BenchmarkPlan (..)
  , KnobAxis (..)
  , KnobSpace (..)
  , TuningResult (..)
  , appleSiliconKnobs
  , benchmarkPlan
  , cuDnnDeterministicAlgorithms
  , knobSpace
  , linuxCpuKnobs
  , linuxCudaKnobs
  , renderBenchmarkPlan
  , renderKnobAxis
  , renderKnobSpace
  , renderTuningResult
  , selectDeterministic
  , tuningChoiceForResult
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Cache.Key (TuningChoice (..))
import JitML.Substrate (Substrate (..))

data KnobAxis = KnobAxis
  { knobName :: Text
  , knobChoices :: [Text]
  , knobDefault :: Text
  }
  deriving stock (Eq, Show)

data KnobSpace = KnobSpace
  { knobSpaceSubstrate :: Substrate
  , knobSpaceAxes :: [KnobAxis]
  }
  deriving stock (Eq, Show)

data TuningResult = TuningResult
  { tuningSubstrate :: Substrate
  , tuningSelections :: [(Text, Text)]
  }
  deriving stock (Eq, Show)

data BenchmarkPlan = BenchmarkPlan
  { benchmarkPlanSubstrate :: Substrate
  , benchmarkPlanResults :: [TuningResult]
  }
  deriving stock (Eq, Show)

knobSpace :: Substrate -> KnobSpace
knobSpace AppleSilicon = appleSiliconKnobs
knobSpace LinuxCPU = linuxCpuKnobs
knobSpace LinuxCUDA = linuxCudaKnobs

appleSiliconKnobs :: KnobSpace
appleSiliconKnobs =
  KnobSpace
    AppleSilicon
    [ KnobAxis
        "threadgroup-size"
        ["64", "128", "256", "512"]
        "256"
    , KnobAxis
        "matmul-tile"
        ["8x8", "16x16", "32x32"]
        "16x16"
    , KnobAxis
        "reduction-strategy"
        ["simdgroup-reduce", "threadgroup-reduce"]
        "simdgroup-reduce"
    , KnobAxis
        "command-queue-discipline"
        ["single-stream-launch-order"]
        "single-stream-launch-order"
    ]

linuxCpuKnobs :: KnobSpace
linuxCpuKnobs =
  KnobSpace
    LinuxCPU
    [ KnobAxis
        "micro-kernel"
        ["onednn-jit-avx2", "onednn-jit-avx512", "onednn-reference"]
        "onednn-jit-avx2"
    , KnobAxis
        "reduction-block"
        ["64", "128", "256", "512"]
        "256"
    , KnobAxis
        "thread-count"
        ["1", "2", "4", "8"]
        "1"
    , KnobAxis
        "fastmath"
        ["off"]
        "off"
    ]

linuxCudaKnobs :: KnobSpace
linuxCudaKnobs =
  KnobSpace
    LinuxCUDA
    [ KnobAxis
        "matmul-tile"
        ["64x64", "128x128", "256x128"]
        "128x128"
    , KnobAxis
        "block-dim"
        ["128", "256", "512"]
        "256"
    , KnobAxis
        "cudnn-conv-algo"
        cuDnnDeterministicAlgorithms
        "CUDNN_CONVOLUTION_FWD_ALGO_IMPLICIT_PRECOMP_GEMM"
    , KnobAxis
        "reduction-strategy"
        ["warp-shuffle-deterministic", "block-stride-deterministic"]
        "warp-shuffle-deterministic"
    , KnobAxis
        "use-tf32"
        ["off"]
        "off"
    , KnobAxis
        "use-fast-math"
        ["off"]
        "off"
    ]

cuDnnDeterministicAlgorithms :: [Text]
cuDnnDeterministicAlgorithms =
  [ "CUDNN_CONVOLUTION_FWD_ALGO_IMPLICIT_GEMM"
  , "CUDNN_CONVOLUTION_FWD_ALGO_IMPLICIT_PRECOMP_GEMM"
  , "CUDNN_CONVOLUTION_FWD_ALGO_FFT"
  , "CUDNN_CONVOLUTION_FWD_ALGO_FFT_TILING"
  ]

selectDeterministic :: KnobSpace -> TuningResult
selectDeterministic space =
  TuningResult
    (knobSpaceSubstrate space)
    [(knobName axis, knobDefault axis) | axis <- knobSpaceAxes space]

tuningChoiceForResult :: TuningResult -> TuningChoice
tuningChoiceForResult result =
  TuningChoice $
    Text.intercalate
      ";"
      [ name <> "=" <> value
      | (name, value) <- tuningSelections result
      ]

benchmarkPlan :: KnobSpace -> BenchmarkPlan
benchmarkPlan space =
  BenchmarkPlan
    (knobSpaceSubstrate space)
    (fmap (TuningResult (knobSpaceSubstrate space)) (selectionGrid (knobSpaceAxes space)))

renderKnobAxis :: KnobAxis -> Text
renderKnobAxis axis =
  knobName axis
    <> " ∈ {"
    <> Text.intercalate ", " (knobChoices axis)
    <> "} (default "
    <> knobDefault axis
    <> ")"

renderKnobSpace :: KnobSpace -> Text
renderKnobSpace space =
  Text.unlines $
    ("knob-space[" <> Text.pack (showSubstrate (knobSpaceSubstrate space)) <> "]:")
      : ["  - " <> renderKnobAxis axis | axis <- knobSpaceAxes space]

renderTuningResult :: TuningResult -> Text
renderTuningResult result =
  Text.unlines $
    ("tuning[" <> Text.pack (showSubstrate (tuningSubstrate result)) <> "]:")
      : [ "  - " <> name <> " = " <> value
        | (name, value) <- tuningSelections result
        ]

renderBenchmarkPlan :: BenchmarkPlan -> Text
renderBenchmarkPlan plan =
  Text.unlines $
    ("benchmark-plan[" <> Text.pack (showSubstrate (benchmarkPlanSubstrate plan)) <> "]:")
      : [ "  - " <> unTuningChoice (tuningChoiceForResult result)
        | result <- benchmarkPlanResults plan
        ]

selectionGrid :: [KnobAxis] -> [[(Text, Text)]]
selectionGrid [] = [[]]
selectionGrid (axis : rest) =
  [ (knobName axis, choice) : suffix
  | choice <- knobChoices axis
  , suffix <- selectionGrid rest
  ]

showSubstrate :: Substrate -> String
showSubstrate AppleSilicon = "apple-silicon"
showSubstrate LinuxCPU = "linux-cpu"
showSubstrate LinuxCUDA = "linux-cuda"
