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
    , metalKernelHelpers
    , ""
    , unweightedBody family
    , ""
    , weightedBody family
    ]

metalKernelHelpers :: Text
metalKernelHelpers =
  Text.unlines
    [ "inline float jitml_weight_or_default(const device float *weights, uint wn, uint idx, float fallback) {"
    , "  return (idx < wn) ? weights[idx] : fallback;"
    , "}"
    , ""
    , "inline uint jitml_ceil_sqrt(uint n) {"
    , "  uint side = 1u;"
    , "  while (side * side < n) { side += 1u; }"
    , "  return side;"
    , "}"
    , ""
    , "inline uint jitml_ceil_cuberoot(uint n) {"
    , "  uint side = 1u;"
    , "  while (side * side * side < n) { side += 1u; }"
    , "  return side;"
    , "}"
    ]

-- | Unweighted `jitml_kernel`. Every thread bound-checks against the element
-- count at buffer index 3 so the launcher can dispatch full threadgroups
-- without reading or writing out of range.
unweightedBody :: KernelFamily -> Text
unweightedBody Identity =
  Text.unlines
    [ "// Identity kernel: bounded elementwise copy."
    , "kernel void jitml_kernel("
    , "    device float *out [[buffer(0)]],"
    , "    const device float *input [[buffer(1)]],"
    , "    constant uint &n [[buffer(3)]],"
    , "    uint id [[thread_position_in_grid]]) {"
    , "  if (id >= n) { return; }"
    , "  out[id] = input[id];"
    , "}"
    ]
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
unweightedBody Dense2D =
  Text.unlines
    [ "// Dense2D unweighted path: explicit identity GEMM over the flat vector."
    , "kernel void jitml_kernel("
    , "    device float *out [[buffer(0)]],"
    , "    const device float *input [[buffer(1)]],"
    , "    constant uint &n [[buffer(3)]],"
    , "    uint id [[thread_position_in_grid]]) {"
    , "  if (id >= n) { return; }"
    , "  float acc = 0.0f;"
    , "  for (uint j = 0u; j < n; ++j) {"
    , "    acc += input[j] * ((j == id) ? 1.0f : 0.0f);"
    , "  }"
    , "  out[id] = acc;"
    , "}"
    ]
unweightedBody Conv2DKernel =
  Text.unlines
    [ "// Conv2D unweighted path: 3x3 windowed convolution with a unit center filter."
    , "kernel void jitml_kernel("
    , "    device float *out [[buffer(0)]],"
    , "    const device float *input [[buffer(1)]],"
    , "    constant uint &n [[buffer(3)]],"
    , "    uint id [[thread_position_in_grid]]) {"
    , "  if (id >= n) { return; }"
    , "  uint width = jitml_ceil_sqrt(n);"
    , "  uint height = (n + width - 1u) / width;"
    , "  uint x0 = id % width;"
    , "  uint y0 = id / width;"
    , "  float acc = 0.0f;"
    , "  for (int dy = -1; dy <= 1; ++dy) {"
    , "    for (int dx = -1; dx <= 1; ++dx) {"
    , "      int x = int(x0) + dx;"
    , "      int y = int(y0) + dy;"
    , "      if (x >= 0 && y >= 0 && x < int(width) && y < int(height)) {"
    , "        uint sample = uint(y) * width + uint(x);"
    , "        if (sample < n) {"
    , "          float filter = (dx == 0 && dy == 0) ? 1.0f : 0.0f;"
    , "          acc += input[sample] * filter;"
    , "        }"
    , "      }"
    , "    }"
    , "  }"
    , "  out[id] = acc;"
    , "}"
    ]
unweightedBody Conv3DKernel =
  Text.unlines
    [ "// Conv3D unweighted path: 3x3x3 windowed convolution with a unit center filter."
    , "kernel void jitml_kernel("
    , "    device float *out [[buffer(0)]],"
    , "    const device float *input [[buffer(1)]],"
    , "    constant uint &n [[buffer(3)]],"
    , "    uint id [[thread_position_in_grid]]) {"
    , "  if (id >= n) { return; }"
    , "  uint side = jitml_ceil_cuberoot(n);"
    , "  uint plane = side * side;"
    , "  uint z0 = id / plane;"
    , "  uint rem = id % plane;"
    , "  uint y0 = rem / side;"
    , "  uint x0 = rem % side;"
    , "  float acc = 0.0f;"
    , "  for (int dz = -1; dz <= 1; ++dz) {"
    , "    for (int dy = -1; dy <= 1; ++dy) {"
    , "      for (int dx = -1; dx <= 1; ++dx) {"
    , "        int x = int(x0) + dx;"
    , "        int y = int(y0) + dy;"
    , "        int z = int(z0) + dz;"
    , "        if (x >= 0 && y >= 0 && z >= 0 && x < int(side) && y < int(side) && z < int(side)) {"
    , "          uint sample = uint(z) * plane + uint(y) * side + uint(x);"
    , "          if (sample < n) {"
    , "            float filter = (dx == 0 && dy == 0 && dz == 0) ? 1.0f : 0.0f;"
    , "            acc += input[sample] * filter;"
    , "          }"
    , "        }"
    , "      }"
    , "    }"
    , "  }"
    , "  out[id] = acc;"
    , "}"
    ]
unweightedBody BatchNormKernel =
  Text.unlines
    [ "// BatchNorm unweighted path with canonical affine/global-stat defaults."
    , "kernel void jitml_kernel("
    , "    device float *out [[buffer(0)]],"
    , "    const device float *input [[buffer(1)]],"
    , "    constant uint &n [[buffer(3)]],"
    , "    uint id [[thread_position_in_grid]]) {"
    , "  if (id >= n) { return; }"
    , "  out[id] = input[id] / sqrt(1.0f + 1.0e-5f);"
    , "}"
    ]
unweightedBody LayerNormKernel =
  Text.unlines
    [ "// LayerNorm unweighted path: normalize over the flat input vector."
    , "kernel void jitml_kernel("
    , "    device float *out [[buffer(0)]],"
    , "    const device float *input [[buffer(1)]],"
    , "    constant uint &n [[buffer(3)]],"
    , "    uint id [[thread_position_in_grid]]) {"
    , "  if (id >= n) { return; }"
    , "  float sum = 0.0f;"
    , "  for (uint j = 0u; j < n; ++j) { sum += input[j]; }"
    , "  float mean = sum / float(n);"
    , "  float varSum = 0.0f;"
    , "  for (uint j = 0u; j < n; ++j) { float d = input[j] - mean; varSum += d * d; }"
    , "  float var = varSum / float(n);"
    , "  out[id] = (input[id] - mean) / sqrt(var + 1.0e-5f);"
    , "}"
    ]
unweightedBody MultiHeadAttentionKernel =
  Text.unlines
    [ "// MHA unweighted path: identity Q/K/V projections with elementwise Q*K."
    , "kernel void jitml_kernel("
    , "    device float *out [[buffer(0)]],"
    , "    const device float *input [[buffer(1)]],"
    , "    constant uint &n [[buffer(3)]],"
    , "    uint id [[thread_position_in_grid]]) {"
    , "  if (id >= n) { return; }"
    , "  out[id] = input[id] * input[id];"
    , "}"
    ]
unweightedBody EmbeddingKernel =
  Text.unlines
    [ "// Embedding without a table preserves the supplied indices."
    , "kernel void jitml_kernel("
    , "    device float *out [[buffer(0)]],"
    , "    const device float *input [[buffer(1)]],"
    , "    constant uint &n [[buffer(3)]],"
    , "    uint id [[thread_position_in_grid]]) {"
    , "  if (id >= n) { return; }"
    , "  out[id] = input[id];"
    , "}"
    ]

-- | Weighted `jitml_weighted_kernel`. Each family shares the same buffer
-- binding contract (out=0, input=1, weights=2, n=3, wn=4) and per-thread bound
-- check; only the compute differs by family.
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

-- | Per-family weighted compute for the Metal source bridge.
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
weightedFamilyCompute Conv2DKernel = conv2dWeightedCompute
weightedFamilyCompute Conv3DKernel = conv3dWeightedCompute
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

conv2dWeightedCompute :: Text
conv2dWeightedCompute =
  Text.unlines
    [ "  if (wn <= 1u) {"
    , "    float w = (wn > 0u) ? weights[0] : 1.0f;"
    , "    out[id] = input[id] * w;"
    , "    return;"
    , "  }"
    , "  uint width = jitml_ceil_sqrt(n);"
    , "  uint height = (n + width - 1u) / width;"
    , "  uint x0 = id % width;"
    , "  uint y0 = id / width;"
    , "  float acc = 0.0f;"
    , "  for (int dy = -1; dy <= 1; ++dy) {"
    , "    for (int dx = -1; dx <= 1; ++dx) {"
    , "      int x = int(x0) + dx;"
    , "      int y = int(y0) + dy;"
    , "      if (x >= 0 && y >= 0 && x < int(width) && y < int(height)) {"
    , "        uint sample = uint(y) * width + uint(x);"
    , "        if (sample < n) {"
    , "          uint k = uint((dy + 1) * 3 + (dx + 1));"
    , "          acc += input[sample] * jitml_weight_or_default(weights, wn, k, (k == 4u) ? 1.0f : 0.0f);"
    , "        }"
    , "      }"
    , "    }"
    , "  }"
    , "  out[id] = acc;"
    ]

conv3dWeightedCompute :: Text
conv3dWeightedCompute =
  Text.unlines
    [ "  if (wn <= 1u) {"
    , "    float w = (wn > 0u) ? weights[0] : 1.0f;"
    , "    out[id] = input[id] * w;"
    , "    return;"
    , "  }"
    , "  uint side = jitml_ceil_cuberoot(n);"
    , "  uint plane = side * side;"
    , "  uint z0 = id / plane;"
    , "  uint rem = id % plane;"
    , "  uint y0 = rem / side;"
    , "  uint x0 = rem % side;"
    , "  float acc = 0.0f;"
    , "  for (int dz = -1; dz <= 1; ++dz) {"
    , "    for (int dy = -1; dy <= 1; ++dy) {"
    , "      for (int dx = -1; dx <= 1; ++dx) {"
    , "        int x = int(x0) + dx;"
    , "        int y = int(y0) + dy;"
    , "        int z = int(z0) + dz;"
    , "        if (x >= 0 && y >= 0 && z >= 0 && x < int(side) && y < int(side) && z < int(side)) {"
    , "          uint sample = uint(z) * plane + uint(y) * side + uint(x);"
    , "          if (sample < n) {"
    , "            uint k = uint((dz + 1) * 9 + (dy + 1) * 3 + (dx + 1));"
    , "            acc += input[sample] * jitml_weight_or_default(weights, wn, k, (k == 13u) ? 1.0f : 0.0f);"
    , "          }"
    , "        }"
    , "      }"
    , "    }"
    , "  }"
    , "  out[id] = acc;"
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
