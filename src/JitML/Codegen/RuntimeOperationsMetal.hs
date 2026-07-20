{-# LANGUAGE OverloadedStrings #-}

-- | Generated Apple-Silicon Metal source and cache metadata for the complete
-- supervised-runtime structural operation set. The MSL is retained only as a
-- value inside content-addressed @.metal.json@ metadata and is compiled
-- in-process by the fixed host bridge on a cache miss.
module JitML.Codegen.RuntimeOperationsMetal
  ( renderRuntimeOperationsMetalMetadata
  , runtimeOperationsMetalKernelSpec
  , runtimeOperationsMetalSource
  )
where

import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString qualified as ByteString
import Data.Char (intToDigit)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Word (Word8)

import JitML.Cache.Key (KernelSpec (..))
import JitML.Codegen.Metal (metalBridgeAbiVersion)
import JitML.Codegen.SourceFile (SourceFile (..))

runtimeOperationsMetalKernelSpec :: KernelSpec
runtimeOperationsMetalKernelSpec =
  KernelSpec "supervised-runtime-structural-operations-v1"

renderRuntimeOperationsMetalMetadata :: [SourceFile]
renderRuntimeOperationsMetalMetadata =
  [SourceFile "kernel.metal.json" runtimeOperationsMetalMetadata]

runtimeOperationsMetalMetadata :: Text
runtimeOperationsMetalMetadata =
  Text.unlines
    [ "{"
    , "  \"abi\": \"jitml-runtime-operations-v1\","
    , "  \"abi_version\": 1,"
    , "  \"capabilities\": 255,"
    , "  \"bridge_abi\": " <> jsonString metalBridgeAbiVersion <> ","
    , "  \"substrate\": \"apple-silicon\","
    , "  \"transport\": \"fixed-bridge-fp32-host-buffers\","
    , "  \"functions\": ["
    , "    \"jitml_runtime_input_transform\","
    , "    \"jitml_runtime_output_transform\","
    , "    \"jitml_runtime_residual_add\","
    , "    \"jitml_runtime_layer_norm\","
    , "    \"jitml_runtime_token_mix_pack\","
    , "    \"jitml_runtime_token_mix_merge\","
    , "    \"jitml_runtime_patch_extract\","
    , "    \"jitml_runtime_attention\","
    , "    \"jitml_runtime_mean_pool\""
    , "  ],"
    , "  \"compile_options\": {\"fast_math\": false, \"math_mode\": \"safe\"},"
    , "  \"launch_policy\": \"single-stream-launch-order\","
    , "  \"source_sha256\": " <> jsonString (sha256HexText runtimeOperationsMetalSource) <> ","
    , "  \"source\": " <> jsonString runtimeOperationsMetalSource
    , "}"
    ]

-- Buffer ABI supplied by @jitml_metal_bridge_run@:
-- output=0, input=1, arguments=2, input-count=3, argument-count=4.
runtimeOperationsMetalSource :: Text
runtimeOperationsMetalSource =
  Text.unlines
    [ "#include <metal_stdlib>"
    , "using namespace metal;"
    , ""
    , "kernel void jitml_runtime_input_transform("
    , "    device float *out [[buffer(0)]], const device float *input [[buffer(1)]],"
    , "    const device float *args [[buffer(2)]], constant uint &n [[buffer(3)]],"
    , "    constant uint &wn [[buffer(4)]], uint id [[thread_position_in_grid]]) {"
    , "  if (id >= n || wn < 1u) { return; }"
    , "  uint transform = uint(args[0]);"
    , "  if (transform == 2u && wn >= 1u + 2u * n) { out[id] = (input[id] - args[1u + id]) / args[1u + n + id]; }"
    , "  else { out[id] = input[id]; }"
    , "}"
    , ""
    , "kernel void jitml_runtime_output_transform("
    , "    device float *out [[buffer(0)]], const device float *input [[buffer(1)]],"
    , "    const device float *args [[buffer(2)]], constant uint &n [[buffer(3)]],"
    , "    constant uint &wn [[buffer(4)]], uint id [[thread_position_in_grid]]) {"
    , "  if (wn < 2u) { return; }"
    , "  uint transform = uint(args[0]); uint output_count = uint(args[1]);"
    , "  if (id >= output_count || id >= n) { return; }"
    , "  if (transform == 2u && wn >= 2u + 2u * output_count) {"
    , "    out[id] = input[id] * args[2u + output_count + id] + args[2u + id];"
    , "  } else { out[id] = input[id]; }"
    , "}"
    , ""
    , "kernel void jitml_runtime_residual_add("
    , "    device float *out [[buffer(0)]], const device float *input [[buffer(1)]],"
    , "    const device float *args [[buffer(2)]], constant uint &n [[buffer(3)]],"
    , "    constant uint &wn [[buffer(4)]], uint id [[thread_position_in_grid]]) {"
    , "  if (wn < 2u) { return; } uint count = uint(args[0]);"
    , "  if (id >= count || n < 2u * count) { return; }"
    , "  out[id] = input[id] + args[1] * input[count + id];"
    , "}"
    , ""
    , "kernel void jitml_runtime_layer_norm("
    , "    device float *out [[buffer(0)]], const device float *input [[buffer(1)]],"
    , "    const device float *args [[buffer(2)]], constant uint &n [[buffer(3)]],"
    , "    constant uint &wn [[buffer(4)]], uint id [[thread_position_in_grid]]) {"
    , "  if (wn < 1u) { return; } uint count = uint(args[0]);"
    , "  if (id >= count || n < count) { return; }"
    , "  float total = 0.0f; for (uint i = 0u; i < count; ++i) { total += input[i]; }"
    , "  float mean = total / float(count); float squared = 0.0f;"
    , "  for (uint i = 0u; i < count; ++i) { float centered = input[i] - mean; squared += centered * centered; }"
    , "  out[id] = (input[id] - mean) / sqrt(squared / float(count) + 1.0e-5f);"
    , "}"
    , ""
    , "kernel void jitml_runtime_token_mix_pack("
    , "    device float *out [[buffer(0)]], const device float *input [[buffer(1)]],"
    , "    const device float *args [[buffer(2)]], constant uint &n [[buffer(3)]],"
    , "    constant uint &wn [[buffer(4)]], uint id [[thread_position_in_grid]]) {"
    , "  if (wn < 2u) { return; } uint token_count = uint(args[0]); uint width = uint(args[1]);"
    , "  uint count = token_count * width; if (id >= count || n < count) { return; }"
    , "  uint channel = id / token_count; uint token = id % token_count;"
    , "  out[id] = input[token * width + channel];"
    , "}"
    , ""
    , "kernel void jitml_runtime_token_mix_merge("
    , "    device float *out [[buffer(0)]], const device float *input [[buffer(1)]],"
    , "    const device float *args [[buffer(2)]], constant uint &n [[buffer(3)]],"
    , "    constant uint &wn [[buffer(4)]], uint id [[thread_position_in_grid]]) {"
    , "  if (wn < 2u) { return; } uint token_count = uint(args[0]); uint width = uint(args[1]);"
    , "  uint count = token_count * width; if (id >= count || n < 2u * count) { return; }"
    , "  uint token = id / width; uint channel = id % width;"
    , "  out[id] = input[count + channel * token_count + token];"
    , "}"
    , ""
    , "kernel void jitml_runtime_patch_extract("
    , "    device float *out [[buffer(0)]], const device float *input [[buffer(1)]],"
    , "    const device float *args [[buffer(2)]], constant uint &n [[buffer(3)]],"
    , "    constant uint &wn [[buffer(4)]], uint id [[thread_position_in_grid]]) {"
    , "  if (wn < 6u) { return; }"
    , "  uint input_count = uint(args[0]); uint image_width = uint(args[1]);"
    , "  uint image_height = uint(args[2]); uint channels = uint(args[3]);"
    , "  uint patch_count = uint(args[4]); uint value_width = uint(args[5]);"
    , "  uint patch_width = value_width + 2u; uint output_count = patch_count * patch_width;"
    , "  if (id >= output_count || n < input_count || wn < 6u + patch_count * value_width) { return; }"
    , "  uint patch = id / patch_width; uint offset = id % patch_width; uint index_base = 6u + patch * value_width;"
    , "  if (offset < value_width) { out[id] = input[uint(args[index_base + offset])]; return; }"
    , "  uint first = uint(args[index_base]); uint pixel = first / channels; uint x = pixel % image_width; uint y = pixel / image_width;"
    , "  if (offset == value_width) { out[id] = image_width <= 1u ? 0.0f : (float(x) / float(image_width - 1u)) * 2.0f - 1.0f; }"
    , "  else { out[id] = image_height <= 1u ? 0.0f : (float(y) / float(image_height - 1u)) * 2.0f - 1.0f; }"
    , "}"
    , ""
    , "inline float jitml_attention_score(const device float *qkv, uint query, uint key, uint width, float scale) {"
    , "  float dot = 0.0f; for (uint channel = 0u; channel < width; ++channel) {"
    , "    dot += qkv[query * 3u * width + channel] * qkv[key * 3u * width + width + channel];"
    , "  } return dot * scale;"
    , "}"
    , ""
    , "kernel void jitml_runtime_attention("
    , "    device float *out [[buffer(0)]], const device float *input [[buffer(1)]],"
    , "    const device float *args [[buffer(2)]], constant uint &n [[buffer(3)]],"
    , "    constant uint &wn [[buffer(4)]], uint id [[thread_position_in_grid]]) {"
    , "  if (wn < 2u) { return; } uint token_count = uint(args[0]); uint width = uint(args[1]);"
    , "  uint token_values = token_count * width; if (id >= token_values || n < 4u * token_values) { return; }"
    , "  const device float *tokens = input; const device float *qkv = input + token_values;"
    , "  uint query = id / width; uint channel = id % width; float scale = 1.0f / sqrt(float(width));"
    , "  float maximum = -INFINITY; for (uint key = 0u; key < token_count; ++key) { maximum = max(maximum, jitml_attention_score(qkv, query, key, width, scale)); }"
    , "  float denominator = 0.0f; for (uint key = 0u; key < token_count; ++key) { denominator += exp(jitml_attention_score(qkv, query, key, width, scale) - maximum); }"
    , "  float attended = 0.0f; for (uint value = 0u; value < token_count; ++value) {"
    , "    float weight = exp(jitml_attention_score(qkv, query, value, width, scale) - maximum) / denominator;"
    , "    attended += weight * qkv[value * 3u * width + 2u * width + channel];"
    , "  } out[id] = attended;"
    , "}"
    , ""
    , "kernel void jitml_runtime_mean_pool("
    , "    device float *out [[buffer(0)]], const device float *input [[buffer(1)]],"
    , "    const device float *args [[buffer(2)]], constant uint &n [[buffer(3)]],"
    , "    constant uint &wn [[buffer(4)]], uint id [[thread_position_in_grid]]) {"
    , "  if (wn < 2u) { return; } uint token_count = uint(args[0]); uint width = uint(args[1]);"
    , "  if (id >= width || n < token_count * width) { return; }"
    , "  float total = 0.0f; for (uint token = 0u; token < token_count; ++token) { total += input[token * width + id]; }"
    , "  out[id] = total / float(token_count);"
    , "}"
    ]

jsonString :: Text -> Text
jsonString value =
  "\"" <> Text.concatMap escapeJson value <> "\""

escapeJson :: Char -> Text
escapeJson '"' = "\\\""
escapeJson '\\' = "\\\\"
escapeJson '\n' = "\\n"
escapeJson '\r' = "\\r"
escapeJson '\t' = "\\t"
escapeJson character = Text.singleton character

sha256HexText :: Text -> Text
sha256HexText =
  Text.pack
    . concatMap byteHex
    . ByteString.unpack
    . SHA256.hash
    . Text.Encoding.encodeUtf8

byteHex :: Word8 -> String
byteHex byte =
  [intToDigit (fromIntegral byte `div` 16), intToDigit (fromIntegral byte `mod` 16)]
