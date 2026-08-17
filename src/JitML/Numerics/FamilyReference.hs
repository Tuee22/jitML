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
  ( defaultFamilyWeights
  , familyReference
  , familyReferenceVec
  , unweightedFamilyReference
  , unweightedFamilyReferenceVec
  ) where

import Data.Vector.Unboxed qualified as VU

import JitML.Codegen.KernelFamily (KernelFamily (..))

-- | The canonical no-op weights for a family at input length @n@ — the values
-- that make the weighted kernel compute exactly what the unweighted kernel is
-- supposed to compute.
--
-- This is the __semantics contract__ (Sprint `80.1`, enforced across all three
-- renderers by Sprint `84.1`). Before it, each substrate's unweighted body was
-- written independently and they disagreed: for multi-head attention the CUDA
-- and Metal renderers produced an elementwise square while the oneDNN renderer
-- returned the input unchanged, and nothing detected it because the unweighted
-- ABI was only smoke-asserted. Defining the unweighted arm /as/ the weighted
-- arm at these defaults makes that class of divergence unrepresentable.
--
-- Total over 'KernelFamily': a new family fails
-- @-Werror=incomplete-patterns@ here rather than silently acquiring whatever
-- an unweighted body happened to do.
defaultFamilyWeights :: KernelFamily -> Int -> VU.Vector Double
defaultFamilyWeights family n =
  case family of
    -- No weight parameter at all; the unweighted body is the whole semantics.
    Identity -> VU.empty
    Reduction -> VU.empty
    -- An empty table passes indices through.
    EmbeddingKernel -> VU.empty
    -- out = input · I
    Dense2D -> identityMatrix
    -- Unit-centre filter: the identity convolution.
    Conv2DKernel -> unitCentre 9 4
    Conv3DKernel -> unitCentre 27 13
    -- scale 1, shift 0, mean 0, var 1
    BatchNormKernel ->
      VU.concat [VU.replicate n 1, VU.replicate n 0, VU.replicate n 0, VU.replicate n 1]
    -- scale 1, shift 0
    LayerNormKernel -> VU.concat [VU.replicate n 1, VU.replicate n 0]
    -- Wq = Wk = Wv = I, which degenerates the attention algebra to
    -- @out[i] = input[i]^2@.
    MultiHeadAttentionKernel -> VU.concat [identityMatrix, identityMatrix, identityMatrix]
 where
  identityMatrix =
    VU.generate (n * n) (\i -> if i `div` max 1 n == i `mod` max 1 n then 1 else 0)
  unitCentre taps centre =
    VU.generate taps (\i -> if i == centre then 1 else 0)

-- | The unweighted kernel's expected output: the weighted reference evaluated
-- at the family's canonical no-op weights. The unweighted ABI has no separate
-- definition, so a renderer cannot drift from it without failing the oracle.
unweightedFamilyReferenceVec :: KernelFamily -> VU.Vector Double -> VU.Vector Double
unweightedFamilyReferenceVec family input =
  familyReferenceVec family input (defaultFamilyWeights family (VU.length input))

-- | 'unweightedFamilyReferenceVec' in the flat @[Float]@ ABI the runners use.
unweightedFamilyReference :: KernelFamily -> [Float] -> [Float]
unweightedFamilyReference family inputF =
  map realToFrac (VU.toList (unweightedFamilyReferenceVec family input))
 where
  input = VU.fromList (map realToFrac inputF) :: VU.Vector Double

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
    -- Flat-window Conv2D/Conv3D. Missing weights default to a unit center
    -- filter, so an empty weight buffer is the identity convolution.
    Conv2DKernel -> conv2dWindow input weights
    Conv3DKernel -> conv3dWindow input weights
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
  lnMean = VU.sum input / fromIntegral n
  lnVar = VU.sum (VU.map (\x -> (x - lnMean) * (x - lnMean)) input) / fromIntegral n

conv2dWindow :: VU.Vector Double -> VU.Vector Double -> VU.Vector Double
conv2dWindow input weights =
  VU.generate n outputAt
 where
  n = VU.length input
  width = ceilSqrtInt n
  height = (n + width - 1) `div` width
  weightAt k
    | k >= 0 && k < VU.length weights = weights VU.! k
    | k == 4 = 1.0
    | otherwise = 0.0
  outputAt idx =
    let x0 = idx `mod` width
        y0 = idx `div` width
     in sum
          [ (input VU.! sample) * weightAt ((dy + 1) * 3 + (dx + 1))
          | dy <- [-1 .. 1]
          , dx <- [-1 .. 1]
          , let x = x0 + dx
          , let y = y0 + dy
          , x >= 0
          , y >= 0
          , x < width
          , y < height
          , let sample = y * width + x
          , sample < n
          ]

conv3dWindow :: VU.Vector Double -> VU.Vector Double -> VU.Vector Double
conv3dWindow input weights =
  VU.generate n outputAt
 where
  n = VU.length input
  side = ceilCubeRootInt n
  plane = side * side
  weightAt k
    | k >= 0 && k < VU.length weights = weights VU.! k
    | k == 13 = 1.0
    | otherwise = 0.0
  outputAt idx =
    let z0 = idx `div` plane
        rem0 = idx `mod` plane
        y0 = rem0 `div` side
        x0 = rem0 `mod` side
     in sum
          [ (input VU.! sample) * weightAt ((dz + 1) * 9 + (dy + 1) * 3 + (dx + 1))
          | dz <- [-1 .. 1]
          , dy <- [-1 .. 1]
          , dx <- [-1 .. 1]
          , let x = x0 + dx
          , let y = y0 + dy
          , let z = z0 + dz
          , x >= 0
          , y >= 0
          , z >= 0
          , x < side
          , y < side
          , z < side
          , let sample = z * plane + y * side + x
          , sample < n
          ]

ceilSqrtInt :: Int -> Int
ceilSqrtInt n =
  go 1
 where
  go side
    | side * side >= max 1 n = side
    | otherwise = go (side + 1)

ceilCubeRootInt :: Int -> Int
ceilCubeRootInt n =
  go 1
 where
  go side
    | side * side * side >= max 1 n = side
    | otherwise = go (side + 1)
