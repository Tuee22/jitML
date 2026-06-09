-- | Pure-Haskell oracle reproducing the exact numeric contract of the weighted
-- family kernels emitted by "JitML.Codegen.Cuda", "JitML.Codegen.OneDnn", and
-- "JitML.Codegen.Metal". Its purpose is to let a backend kernel's output be
-- checked for numeric /correctness/ — within single-precision tolerance —
-- rather than merely for run-to-run determinism. A kernel that is
-- deterministically wrong passes a determinism check but fails against this
-- reference.
--
-- The reference uses the same flat @[Float]@ input/weights ABI the runners
-- ('JitML.Engines.Local.runLinuxCpuWeightedFamilyKernel',
-- 'JitML.Engines.CudaLocal.runCudaWeightedFamilyKernel',
-- 'JitML.Engines.MetalLocal.runMetalWeightedFamilyKernel') accept, and returns
-- the expected length-@n@ output (@n@ = length of the input — every weighted
-- family's @jitml_kernel_output_count(n)@ is @n@; only the unweighted
-- 'Reduction' differs).
--
-- Computation is carried in 'Double' for headroom, mirroring how the MLP
-- reference is checked against the CUDA device kernel within @1e-3@. The
-- weights buffer is padded with each family's canonical default for indices
-- beyond its length, matching the @(idx < weights_count) ? weights[idx] :
-- default@ guards in the emitted kernels. This module is the single Haskell
-- source of truth for the family semantics that previously lived only inside
-- the per-backend emitters.
module JitML.Numerics.FamilyReference
  ( familyReference
  , familyReferenceVec
  ) where

import Data.Vector.Unboxed qualified as VU

import JitML.Codegen.KernelFamily (KernelFamily (..))

-- | Expected output for @family@ given the flat @input@ and @weights@ buffers,
-- in the same @[Float]@ shape the kernel runners return.
familyReference :: KernelFamily -> [Float] -> [Float] -> [Float]
familyReference family inputF weightsF =
  map realToFrac (VU.toList (familyReferenceVec family input weights))
 where
  input = VU.fromList (map realToFrac inputF) :: VU.Vector Double
  weights = VU.fromList (map realToFrac weightsF) :: VU.Vector Double

-- | 'Double'-precision core, exposed for callers that already work in
-- 'VU.Vector' 'Double' (e.g. tolerance comparisons via @approxEqualVec@).
familyReferenceVec
  :: KernelFamily -> VU.Vector Double -> VU.Vector Double -> VU.Vector Double
familyReferenceVec family input weights =
  case family of
    -- Unweighted bodies: the weighted ABI falls through to the plain kernel.
    Identity -> input
    Reduction -> VU.singleton (VU.sum input)
    -- out[i] = sum_j input[j] * W[j*n + i]   (row-major n*n, missing -> 0)
    Dense2D ->
      VU.generate n $ \i ->
        sum [input VU.! j * wAt 0 (j * n + i) | j <- [0 .. n - 1]]
    -- 1x1 conv: out[i] = input[i] * W[0]   (empty weights -> filter 1.0)
    Conv2DKernel -> VU.map (* conv1x1) input
    Conv3DKernel -> VU.map (* conv1x1) input
    -- weights = [scale(n), shift(n), mean(n), var(n)]; defaults 1/0/0/1.
    BatchNormKernel ->
      VU.generate n $ \i ->
        let scale = wAt 1 i
            shift = wAt 0 (n + i)
            mean = wAt 0 (2 * n + i)
            var = wAt 1 (3 * n + i)
         in (input VU.! i - mean) / sqrt (var + eps) * scale + shift
    -- weights = [scale(n), shift(n)]; normalize over the input's own mean/var.
    LayerNormKernel ->
      VU.generate n $ \i ->
        let scale = wAt 1 i
            shift = wAt 0 (n + i)
         in (input VU.! i - lnMean) / sqrt (lnVar + eps) * scale + shift
    -- row-major table (rows*n); row = trunc(max 0 input[i]) mod rows.
    EmbeddingKernel
      | VU.null weights -> input
      | otherwise ->
          VU.generate n $ \i ->
            let tableRows = max 1 (VU.length weights `div` n)
                row = truncate (max 0 (input VU.! i)) `mod` tableRows
                off = row * n + i
             in if off < VU.length weights then weights VU.! off else 0
    -- weights = [Wq, Wk, Wv] (n*n each); no softmax (determinism contract):
    --   q[j] = sum_k input[k]*Wq[k*n+j];  k[j] = sum_k input[k]*Wk[k*n+j]
    --   out[i] = sum_j q[j]*k[j]*Wv[j*n+i]
    MultiHeadAttentionKernel ->
      VU.generate n $ \i ->
        let blockSize = n * n
         in sum
              [ let qsum = sum [input VU.! k * wAt 0 (k * n + j) | k <- [0 .. n - 1]]
                    ksum = sum [input VU.! k * wAt 0 (blockSize + k * n + j) | k <- [0 .. n - 1]]
                    wv = wAt 0 (2 * blockSize + j * n + i)
                 in qsum * ksum * wv
              | j <- [0 .. n - 1]
              ]
 where
  n = VU.length input
  eps = 1.0e-5 :: Double
  wAt def i = if i >= 0 && i < VU.length weights then weights VU.! i else def
  conv1x1 = if VU.null weights then 1 else VU.head weights
  lnMean = VU.sum input / fromIntegral n
  lnVar = VU.sum (VU.map (\x -> (x - lnMean) * (x - lnMean)) input) / fromIntegral n
