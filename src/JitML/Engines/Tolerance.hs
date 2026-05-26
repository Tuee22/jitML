{-# LANGUAGE OverloadedStrings #-}

-- | In-code per-layer-family cross-substrate tolerance band for the canonical
-- determinism contract. Each `KernelFamily` from
-- `JitML.Codegen.KernelFamily` has an L∞ bound on the maximum absolute
-- per-tensor delta between two substrate variants of the same forward pass.
-- The bound is calibrated from the public literature on cuDNN / Metal /
-- oneDNN float32 reduction-order drift and is intentionally per-family
-- because reduction-heavy families (`Conv*`, `Dense2D`,
-- `MultiHeadAttentionKernel`) drift more than elementwise families
-- (`Identity`).
--
-- The convergence assertion (Phase 15 Sprint 15.1) is
--
--   max(abs(out_substrate_A - out_substrate_B)) <= toleranceBound family
--
-- where `family` is the layer-family classifier from
-- `JitML.Codegen.KernelFamily.familyForLayer`. The constants live here, not
-- in committed `.bin`/`.json` fixtures, because the producing host's
-- float-reduction behaviour must not be encoded as an authoritative
-- per-tensor snapshot — see
-- [../../../README.md → Snapshot targets → Numerical-fixture prohibition](../../../README.md#snapshot-targets).
--
-- The values reflect the float32 envelope. Float16/BF16 / Int8 paths get
-- looser bounds when those kinds land (currently the codegen only emits
-- float32 paths).
module JitML.Engines.Tolerance
  ( LayerFamilyTolerance (..)
  , layerFamilyTolerance
  , toleranceBound
  , withinTolerance
  )
where

import JitML.Codegen.KernelFamily (KernelFamily (..))

-- | The L∞ tolerance band for a single kernel family.
data LayerFamilyTolerance = LayerFamilyTolerance
  { tolerance :: Double
  -- ^ Maximum absolute per-element delta allowed between two substrate
  --   variants of the same forward pass.
  , rationale :: String
  -- ^ Short literature-grounded rationale string used in failure
  --   diagnostics. Not displayed to end users; surfaces in
  --   `jitml-cross-backend` failure output.
  }
  deriving stock (Eq, Show)

-- | Look up the tolerance for a kernel family.
layerFamilyTolerance :: KernelFamily -> LayerFamilyTolerance
layerFamilyTolerance Identity =
  LayerFamilyTolerance
    1.0e-6
    "Identity is a pure copy; no FMA / reduction order ambiguity."
layerFamilyTolerance Reduction =
  LayerFamilyTolerance
    1.0e-4
    "Tree reduction order varies across cuBLAS / oneDNN / Metal; the\
    \ literature reports ~1e-5..1e-4 worst-case per-element drift for\
    \ float32 sum reductions over O(1e3)-element tensors."
layerFamilyTolerance Dense2D =
  LayerFamilyTolerance
    5.0e-4
    "Dense GEMM accumulates O(K) FMAs per output element; cuBLAS\
    \ tensor-core paths drift from oneDNN refs by ~1e-4..5e-4 for K=4096."
layerFamilyTolerance Conv2DKernel =
  LayerFamilyTolerance
    1.0e-3
    "Conv2D im2col + GEMM stacks reduction order + tile partitioning;\
    \ cuDNN-vs-oneDNN deltas of 5e-4..1e-3 are routinely reported on\
    \ ResNet conv blocks."
layerFamilyTolerance Conv3DKernel =
  LayerFamilyTolerance
    2.0e-3
    "Conv3D widens the spatial reduction one more order of magnitude\
    \ vs Conv2D; double the conv2d budget."
layerFamilyTolerance BatchNormKernel =
  LayerFamilyTolerance
    5.0e-4
    "BatchNorm running-mean/var uses a parallel two-pass reduction;\
    \ similar envelope to Dense2D once the variance reduction is folded."
layerFamilyTolerance LayerNormKernel =
  LayerFamilyTolerance
    5.0e-4
    "LayerNorm reduces along the feature axis; analogous to BatchNorm\
    \ on the variance computation."
layerFamilyTolerance MultiHeadAttentionKernel =
  LayerFamilyTolerance
    2.0e-3
    "Multi-head attention chains GEMM + softmax + GEMM; the softmax\
    \ exp/sum normalisation amplifies upstream FMA drift. cuDNN\
    \ scaled-dot-product attention reports ~1e-3..2e-3 vs reference."
layerFamilyTolerance EmbeddingKernel =
  LayerFamilyTolerance
    1.0e-6
    "Embedding is a table lookup; no FMA ambiguity at float32 lookup."

-- | Just the tolerance value, dropping the rationale.
toleranceBound :: KernelFamily -> Double
toleranceBound = tolerance . layerFamilyTolerance

-- | Test whether the observed L∞ delta clears the family's band.
withinTolerance :: KernelFamily -> Double -> Bool
withinTolerance family observed =
  observed <= toleranceBound family
