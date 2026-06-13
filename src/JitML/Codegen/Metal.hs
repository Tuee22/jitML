{-# LANGUAGE OverloadedStrings #-}

module JitML.Codegen.Metal
  ( metalBridgeAbiVersion
  , metalOutputCountFor
  , renderMetalFamilyMetadata
  , renderMetalFamilySource
  , renderMetalMetadata
  , threadgroupSizeFor
  )
where

import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString qualified as ByteString
import Data.Char (intToDigit)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Word (Word8)

import JitML.Cache.Key (KernelSpec (..), Kind, TuningChoice (..), kindText)
import JitML.Codegen.KernelFamily (KernelFamily (..), familyName)
import JitML.Codegen.SourceFile (SourceFile (..))

metalBridgeAbiVersion :: Text
metalBridgeAbiVersion = "jitml-metal-bridge-v1"

renderMetalMetadata :: KernelSpec -> Kind -> TuningChoice -> [SourceFile]
renderMetalMetadata = renderMetalFamilyMetadata Identity

renderMetalFamilyMetadata
  :: KernelFamily -> KernelSpec -> Kind -> TuningChoice -> [SourceFile]
renderMetalFamilyMetadata family kernelSpec kind tuningChoice =
  [SourceFile "kernel.metal.json" (metalMetadataJson family kernelSpec kind tuningChoice)]

renderMetalFamilySource :: KernelFamily -> Text
renderMetalFamilySource = metalKernel

metalMetadataJson :: KernelFamily -> KernelSpec -> Kind -> TuningChoice -> Text
metalMetadataJson family kernelSpec kind tuningChoice =
  Text.unlines
    [ "{"
    , "  \"abi\": \"jitml-metal-source-v1\","
    , "  \"bridge_abi\": " <> jsonString metalBridgeAbiVersion <> ","
    , "  \"substrate\": \"apple-silicon\","
    , "  \"kernel_spec\": " <> jsonString (kernelSpecPayload kernelSpec) <> ","
    , "  \"kind\": " <> jsonString (kindText kind) <> ","
    , "  \"tuning_choice\": " <> jsonString (unTuningChoice tuningChoice) <> ","
    , "  \"family\": " <> jsonString (familyName family) <> ","
    , "  \"functions\": {"
    , "    \"unweighted\": \"jitml_kernel\","
    , "    \"weighted\": \"jitml_weighted_kernel\""
    , "  },"
    , "  \"output_count\": {"
    , "    \"kind\": " <> jsonString (metalOutputCountKind family)
    , "  },"
    , "  \"threadgroup_size\": " <> Text.pack (show (threadgroupSizeFor family)) <> ","
    , "  \"compile_options\": {"
    , "    \"fast_math\": false,"
    , "    \"math_mode\": \"safe\""
    , "  },"
    , "  \"launch_policy\": \"single-stream-launch-order\","
    , "  \"source_sha256\": " <> jsonString (sha256HexText source) <> ","
    , "  \"source\": " <> jsonString source
    , "}"
    ]
 where
  source = renderMetalFamilySource family

metalKernel :: KernelFamily -> Text
metalKernel family =
  Text.unlines
    [ "#include <metal_stdlib>"
    , "using namespace metal;"
    , ""
    , unweightedBody family
    , ""
    , weightedBody family
    ]

-- | Unweighted `jitml_kernel`. Every thread bound-checks against the element
-- count at buffer index 3 so the launcher can dispatch full (32-aligned)
-- threadgroups without reading or writing out of range.
unweightedBody :: KernelFamily -> Text
unweightedBody Reduction =
  Text.unlines
    [ "// Simdgroup reduction with deterministic single-stream launch order."
    , "// Padding lanes contribute 0.0f; lane 0 of each simdgroup whose base index"
    , "// is in range writes one partial, matching ceil(n / 32) outputs."
    , "kernel void jitml_kernel("
    , "    device float *out [[buffer(0)]],"
    , "    const device float *input [[buffer(1)]],"
    , "    constant uint &n [[buffer(3)]],"
    , "    uint id [[thread_position_in_grid]],"
    , "    uint tid_in_simd [[thread_index_in_simdgroup]]) {"
    , "  float v = (id < n) ? input[id] : 0.0f;"
    , "  v = simd_sum(v);"
    , "  uint base = id - tid_in_simd;"
    , "  if (tid_in_simd == 0u && base < n) { out[base / 32u] = v; }"
    , "}"
    ]
unweightedBody _family =
  Text.unlines
    [ "// Identity-class elementwise copy, bounded by the element count."
    , "kernel void jitml_kernel("
    , "    device float *out [[buffer(0)]],"
    , "    const device float *input [[buffer(1)]],"
    , "    constant uint &n [[buffer(3)]],"
    , "    uint id [[thread_position_in_grid]]) {"
    , "  if (id >= n) { return; }"
    , "  out[id] = input[id];"
    , "}"
    ]

-- | Weighted `jitml_weighted_kernel`. Sprint 14.5 lands the per-family
-- weighted Metal bodies, mirroring the CUDA `weightedFamilyImpl` math so the
-- cross-substrate parity cohort (Phase 15) compares like for like. Every body
-- shares the same buffer binding contract (out=0, input=1, weights=2, n=3,
-- wn=4) and per-thread bound check; only the compute differs by family.
weightedBody :: KernelFamily -> Text
weightedBody family =
  Text.unlines
    [ "kernel void jitml_weighted_kernel("
    , "    device float *out [[buffer(0)]],"
    , "    const device float *input [[buffer(1)]],"
    , "    const device float *weights [[buffer(2)]],"
    , "    constant uint &n [[buffer(3)]],"
    , "    constant uint &wn [[buffer(4)]],"
    , "    uint id [[thread_position_in_grid]]) {"
    , "  if (id >= n) { return; }"
    , weightedFamilyCompute family
    , "}"
    ]

-- | Per-family weighted compute, mirroring `JitML.Codegen.Cuda.weightedFamilyImpl`.
weightedFamilyCompute :: KernelFamily -> Text
weightedFamilyCompute Dense2D =
  -- out[i] = sum_j input[j] * W[j*n + i] (padded / truncated to n x n).
  Text.unlines
    [ "  float acc = 0.0f;"
    , "  for (uint j = 0u; j < n; ++j) {"
    , "    uint widx = j * n + id;"
    , "    float w = (widx < wn) ? weights[widx] : 0.0f;"
    , "    acc += input[j] * w;"
    , "  }"
    , "  out[id] = acc;"
    ]
weightedFamilyCompute Conv2DKernel = conv1x1WeightedCompute
weightedFamilyCompute Conv3DKernel = conv1x1WeightedCompute
weightedFamilyCompute BatchNormKernel =
  -- weights = [scale(n), shift(n), mean(n), variance(n)] with no-op defaults.
  Text.unlines
    [ "  float scale = (id < wn) ? weights[id] : 1.0f;"
    , "  float shift = (n + id < wn) ? weights[n + id] : 0.0f;"
    , "  float mean = (2u * n + id < wn) ? weights[2u * n + id] : 0.0f;"
    , "  float var = (3u * n + id < wn) ? weights[3u * n + id] : 1.0f;"
    , "  float eps = 1.0e-5f;"
    , "  out[id] = (input[id] - mean) / sqrt(var + eps) * scale + shift;"
    ]
weightedFamilyCompute LayerNormKernel =
  -- weights = [scale(n), shift(n)]; normalise over the input's own mean/var.
  Text.unlines
    [ "  float sum = 0.0f;"
    , "  for (uint j = 0u; j < n; ++j) { sum += input[j]; }"
    , "  float mean = sum / float(n);"
    , "  float varSum = 0.0f;"
    , "  for (uint j = 0u; j < n; ++j) { float d = input[j] - mean; varSum += d * d; }"
    , "  float var = varSum / float(n);"
    , "  float eps = 1.0e-5f;"
    , "  float scale = (id < wn) ? weights[id] : 1.0f;"
    , "  float shift = (n + id < wn) ? weights[n + id] : 0.0f;"
    , "  out[id] = ((input[id] - mean) / sqrt(var + eps)) * scale + shift;"
    ]
weightedFamilyCompute EmbeddingKernel =
  -- weights = row-major embedding table (table_rows * n); input supplies indices.
  Text.unlines
    [ "  if (wn == 0u) { out[id] = input[id]; return; }"
    , "  uint table_rows = wn / n;"
    , "  if (table_rows == 0u) { table_rows = 1u; }"
    , "  float fidx = input[id] < 0.0f ? 0.0f : input[id];"
    , "  uint row = (uint) fidx % table_rows;"
    , "  uint off = row * n + id;"
    , "  out[id] = (off < wn) ? weights[off] : 0.0f;"
    ]
weightedFamilyCompute MultiHeadAttentionKernel =
  -- weights = three n*n blocks (Wq, Wk, Wv);
  -- out[i] = sum_j (q[j] * k[j] * Wv[j*n+i]), q = input·Wq, k = input·Wk.
  -- No softmax (determinism contract: fixed-precision reduction only).
  Text.unlines
    [ "  uint block_size = n * n;"
    , "  float v = 0.0f;"
    , "  for (uint j = 0u; j < n; ++j) {"
    , "    float qsum = 0.0f;"
    , "    float ksum = 0.0f;"
    , "    for (uint k = 0u; k < n; ++k) {"
    , "      uint qi = k * n + j;"
    , "      uint ki = block_size + k * n + j;"
    , "      float wq = (qi < wn) ? weights[qi] : 0.0f;"
    , "      float wk = (ki < wn) ? weights[ki] : 0.0f;"
    , "      qsum += input[k] * wq;"
    , "      ksum += input[k] * wk;"
    , "    }"
    , "    uint vi = 2u * block_size + j * n + id;"
    , "    float wv = (vi < wn) ? weights[vi] : 0.0f;"
    , "    v += qsum * ksum * wv;"
    , "  }"
    , "  out[id] = v;"
    ]
weightedFamilyCompute _family =
  -- Identity / Reduction have no natural weight parameter: copy input through.
  "  out[id] = input[id];"

-- | 1x1 convolution: scale every position by the single filter coefficient
-- (defaulting to 1.0 when no weights are supplied). Shared by Conv2D / Conv3D.
conv1x1WeightedCompute :: Text
conv1x1WeightedCompute =
  Text.unlines
    [ "  float w = (wn > 0u) ? weights[0] : 1.0f;"
    , "  out[id] = input[id] * w;"
    ]

threadgroupSizeFor :: KernelFamily -> Int
threadgroupSizeFor Identity = 256
threadgroupSizeFor Reduction = 64
threadgroupSizeFor Dense2D = 128
threadgroupSizeFor Conv2DKernel = 256
threadgroupSizeFor Conv3DKernel = 256
threadgroupSizeFor BatchNormKernel = 128
threadgroupSizeFor LayerNormKernel = 128
threadgroupSizeFor MultiHeadAttentionKernel = 128
threadgroupSizeFor EmbeddingKernel = 64

metalOutputCountFor :: KernelFamily -> Int -> Int
metalOutputCountFor Reduction n
  | n <= 0 = 0
  | otherwise = ((n - 1) `div` 32) + 1
metalOutputCountFor _ n = max 0 n

metalOutputCountKind :: KernelFamily -> Text
metalOutputCountKind Reduction = "ceil-input-over-32"
metalOutputCountKind _ = "same-as-input"

jsonString :: Text -> Text
jsonString value =
  "\"" <> Text.concatMap escape value <> "\""

escape :: Char -> Text
escape '"' = "\\\""
escape '\\' = "\\\\"
escape '\n' = "\\n"
escape '\r' = "\\r"
escape '\t' = "\\t"
escape char = Text.singleton char

sha256HexText :: Text -> Text
sha256HexText =
  Text.pack . concatMap byteHex . ByteString.unpack . SHA256.hash . Text.Encoding.encodeUtf8
 where
  byteHex :: Word8 -> String
  byteHex byte =
    [ intToDigit (fromIntegral byte `div` 16)
    , intToDigit (fromIntegral byte `mod` 16)
    ]
