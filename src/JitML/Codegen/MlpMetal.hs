{-# LANGUAGE OverloadedStrings #-}

-- | Apple-Silicon (Metal lane) MLP forward/backward kernel source, mirroring
-- "JitML.Codegen.MlpCuda" as Metal Shading Language for the fixed host bridge.
-- The persistent Apple artifact is source metadata; the core path does not
-- generate host-language glue packages or build per-kernel dynamic libraries.
--
-- The generated Metal program is validated by the apple-silicon backend lane on
-- a Mac. It is a faithful port of the verified CUDA kernels
-- ("JitML.Codegen.MlpCuda"): the MSL math mirrors the CUDA @__global__@ bodies,
-- and "JitML.Engines.MetalBridge" owns the fixed-bridge multi-function launch
-- ABI.
module JitML.Codegen.MlpMetal
  ( mlpMetalKernelSpec
  , renderMlpMetalProgram
  , renderMlpMetalSource
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

-- | Kernel-spec identifier for the MLP forward/backward Metal kernel. The cache
-- key disambiguates by substrate + toolchain fingerprint.
mlpMetalKernelSpec :: KernelSpec
mlpMetalKernelSpec = KernelSpec "mlp-forward-backward-tanh-linear"

-- | The persistent Apple cache payload for the MLP Metal source. The fixed
-- bridge owns the multi-function MLP ABI; this source metadata keeps the cache
-- path free of generated glue-package residue.
renderMlpMetalSource :: [SourceFile]
renderMlpMetalSource =
  [SourceFile "kernel.metal.json" mlpMetalMetadata]

renderMlpMetalProgram :: Text
renderMlpMetalProgram = metalKernels

mlpMetalMetadata :: Text
mlpMetalMetadata =
  Text.unlines
    [ "{"
    , "  \"abi\": \"jitml-metal-source-v1\","
    , "  \"bridge_abi\": " <> jsonString metalBridgeAbiVersion <> ","
    , "  \"substrate\": \"apple-silicon\","
    , "  \"kernel_spec\": " <> jsonString (kernelSpecPayload mlpMetalKernelSpec) <> ","
    , "  \"kind\": \"inference\","
    , "  \"tuning_choice\": \"default\","
    , "  \"family\": \"mlp-forward-backward-tanh-linear\","
    , "  \"functions\": {"
    , "    \"forward\": \"jitml_mlp_forward\","
    , "    \"backward\": \"jitml_mlp_backward\","
    , "    \"forward_batch\": \"jitml_mlp_forward_batch\","
    , "    \"batch_gradient\": \"jitml_mlp_batch_gradient\","
    , "    \"input_gradient_batch\": \"jitml_mlp_input_gradient_batch\""
    , "  },"
    , "  \"compile_options\": {"
    , "    \"fast_math\": false,"
    , "    \"math_mode\": \"safe\""
    , "  },"
    , "  \"launch_policy\": \"single-stream-launch-order\","
    , "  \"source_sha256\": " <> jsonString (sha256HexText metalKernels) <> ","
    , "  \"source\": " <> jsonString metalKernels
    , "}"
    ]

-- | MSL kernels mirroring the CUDA @__global__@ bodies in
-- "JitML.Codegen.MlpCuda" one-for-one. Buffer index conventions are local to
-- each kernel (bound by 'jitmlDispatch' in argument order, ints after buffers).
metalKernels :: Text
metalKernels =
  Text.unlines
    [ "#include <metal_stdlib>"
    , "using namespace metal;"
    , ""
    , "// hidden_pre[i] = b1[i] + sum_j W1[i*inputs+j]*input[j]; hidden_act = tanh."
    , "kernel void jitml_mlp_hidden("
    , "    device float *hidden_pre [[buffer(0)]], device float *hidden_act [[buffer(1)]],"
    , "    const device float *input [[buffer(2)]], const device float *w1 [[buffer(3)]],"
    , "    const device float *b1 [[buffer(4)]],"
    , "    constant int &inputs [[buffer(5)]], constant int &hidden [[buffer(6)]],"
    , "    uint gid [[thread_position_in_grid]]) {"
    , "  int i = int(gid); if (i >= hidden) { return; }"
    , "  float acc = b1[i];"
    , "  for (int j = 0; j < inputs; ++j) { acc += w1[i * inputs + j] * input[j]; }"
    , "  hidden_pre[i] = acc; hidden_act[i] = tanh(acc);"
    , "}"
    , ""
    , "// output[k] = b2[k] + sum_i W2[k*hidden+i]*hidden_act[i]."
    , "kernel void jitml_mlp_output("
    , "    device float *output [[buffer(0)]], const device float *hidden_act [[buffer(1)]],"
    , "    const device float *w2 [[buffer(2)]], const device float *b2 [[buffer(3)]],"
    , "    constant int &hidden [[buffer(4)]], constant int &outputs [[buffer(5)]],"
    , "    uint gid [[thread_position_in_grid]]) {"
    , "  int k = int(gid); if (k >= outputs) { return; }"
    , "  float acc = b2[k];"
    , "  for (int i = 0; i < hidden; ++i) { acc += w2[k * hidden + i] * hidden_act[i]; }"
    , "  output[k] = acc;"
    , "}"
    , ""
    , "// gB2[k] = dy[k]; gW2[k*hidden+i] = dy[k]*hidden_act[i]."
    , "kernel void jitml_mlp_grad_output("
    , "    device float *g_w2 [[buffer(0)]], device float *g_b2 [[buffer(1)]],"
    , "    const device float *d_l_dy [[buffer(2)]], const device float *hidden_act [[buffer(3)]],"
    , "    constant int &hidden [[buffer(4)]], constant int &outputs [[buffer(5)]],"
    , "    uint gid [[thread_position_in_grid]]) {"
    , "  int k = int(gid); if (k >= outputs) { return; }"
    , "  float dy = d_l_dy[k]; g_b2[k] = dy;"
    , "  for (int i = 0; i < hidden; ++i) { g_w2[k * hidden + i] = dy * hidden_act[i]; }"
    , "}"
    , ""
    , "// d_act[i] = sum_k W2[k*hidden+i]*dy[k]; d_pre = d_act*(1-h^2);"
    , "// gB1[i] = d_pre; gW1[i*inputs+j] = d_pre*input[j]."
    , "kernel void jitml_mlp_grad_hidden("
    , "    device float *g_w1 [[buffer(0)]], device float *g_b1 [[buffer(1)]],"
    , "    const device float *d_l_dy [[buffer(2)]], const device float *input [[buffer(3)]],"
    , "    const device float *hidden_act [[buffer(4)]], const device float *w2 [[buffer(5)]],"
    , "    constant int &inputs [[buffer(6)]], constant int &hidden [[buffer(7)]],"
    , "    constant int &outputs [[buffer(8)]], uint gid [[thread_position_in_grid]]) {"
    , "  int i = int(gid); if (i >= hidden) { return; }"
    , "  float d_act = 0.0f;"
    , "  for (int k = 0; k < outputs; ++k) { d_act += w2[k * hidden + i] * d_l_dy[k]; }"
    , "  float h = hidden_act[i]; float d_pre = d_act * (1.0f - h * h);"
    , "  g_b1[i] = d_pre;"
    , "  for (int j = 0; j < inputs; ++j) { g_w1[i * inputs + j] = d_pre * input[j]; }"
    , "}"
    , ""
    , "// Batched hidden activation: hidden_act[b*hidden+i] for one (b,i) per thread."
    , "kernel void jitml_mlp_batch_hidden("
    , "    device float *hidden_act [[buffer(0)]], const device float *input [[buffer(1)]],"
    , "    const device float *w1 [[buffer(2)]], const device float *b1 [[buffer(3)]],"
    , "    constant int &inputs [[buffer(4)]], constant int &hidden [[buffer(5)]],"
    , "    constant int &batch [[buffer(6)]], uint gid [[thread_position_in_grid]]) {"
    , "  int total = batch * hidden; int idx = int(gid); if (idx >= total) { return; }"
    , "  int b = idx / hidden; int i = idx % hidden; float acc = b1[i];"
    , "  for (int j = 0; j < inputs; ++j) { acc += w1[i * inputs + j] * input[b * inputs + j]; }"
    , "  hidden_act[b * hidden + i] = tanh(acc);"
    , "}"
    , ""
    , "// Batched output: output[b*outputs+k] for one (b,k) per thread."
    , "kernel void jitml_mlp_batch_output("
    , "    device float *output [[buffer(0)]], const device float *hidden_act [[buffer(1)]],"
    , "    const device float *w2 [[buffer(2)]], const device float *b2 [[buffer(3)]],"
    , "    constant int &hidden [[buffer(4)]], constant int &outputs [[buffer(5)]],"
    , "    constant int &batch [[buffer(6)]], uint gid [[thread_position_in_grid]]) {"
    , "  int total = batch * outputs; int idx = int(gid); if (idx >= total) { return; }"
    , "  int b = idx / outputs; int k = idx % outputs; float acc = b2[k];"
    , "  for (int i = 0; i < hidden; ++i) { acc += w2[k * hidden + i] * hidden_act[b * hidden + i]; }"
    , "  output[b * outputs + k] = acc;"
    , "}"
    , ""
    , "// Batched gradient over the batch, summed: g_b2[k], g_w2[k*hidden+i]."
    , "kernel void jitml_mlp_batch_grad_output("
    , "    device float *g_w2 [[buffer(0)]], device float *g_b2 [[buffer(1)]],"
    , "    const device float *d_l_dy [[buffer(2)]], const device float *hidden_act [[buffer(3)]],"
    , "    constant int &hidden [[buffer(4)]], constant int &outputs [[buffer(5)]],"
    , "    constant int &batch [[buffer(6)]], uint gid [[thread_position_in_grid]]) {"
    , "  int k = int(gid); if (k >= outputs) { return; }"
    , "  float gb = 0.0f;"
    , "  for (int b = 0; b < batch; ++b) { gb += d_l_dy[b * outputs + k]; }"
    , "  g_b2[k] = gb;"
    , "  for (int i = 0; i < hidden; ++i) {"
    , "    float gw = 0.0f;"
    , "    for (int b = 0; b < batch; ++b) { gw += d_l_dy[b * outputs + k] * hidden_act[b * hidden + i]; }"
    , "    g_w2[k * hidden + i] = gw;"
    , "  }"
    , "}"
    , ""
    , "// Batched gradient over the batch, summed: g_b1[i], g_w1[i*inputs+j]."
    , "kernel void jitml_mlp_batch_grad_hidden("
    , "    device float *g_w1 [[buffer(0)]], device float *g_b1 [[buffer(1)]],"
    , "    const device float *d_l_dy [[buffer(2)]], const device float *input [[buffer(3)]],"
    , "    const device float *hidden_act [[buffer(4)]], const device float *w2 [[buffer(5)]],"
    , "    constant int &inputs [[buffer(6)]], constant int &hidden [[buffer(7)]],"
    , "    constant int &outputs [[buffer(8)]], constant int &batch [[buffer(9)]],"
    , "    uint gid [[thread_position_in_grid]]) {"
    , "  int i = int(gid); if (i >= hidden) { return; }"
    , "  float gb1 = 0.0f;"
    , "  for (int j = 0; j < inputs; ++j) { g_w1[i * inputs + j] = 0.0f; }"
    , "  for (int b = 0; b < batch; ++b) {"
    , "    float d_act = 0.0f;"
    , "    for (int k = 0; k < outputs; ++k) { d_act += w2[k * hidden + i] * d_l_dy[b * outputs + k]; }"
    , "    float h = hidden_act[b * hidden + i]; float d_pre = d_act * (1.0f - h * h);"
    , "    gb1 += d_pre;"
    , "    for (int j = 0; j < inputs; ++j) { g_w1[i * inputs + j] += d_pre * input[b * inputs + j]; }"
    , "  }"
    , "  g_b1[i] = gb1;"
    , "}"
    , ""
    , "// d_pre[b*hidden+i] for the per-sample input gradient."
    , "kernel void jitml_mlp_dpre_batch("
    , "    device float *d_hidden_pre [[buffer(0)]], const device float *d_l_dy [[buffer(1)]],"
    , "    const device float *hidden_act [[buffer(2)]], const device float *w2 [[buffer(3)]],"
    , "    constant int &hidden [[buffer(4)]], constant int &outputs [[buffer(5)]],"
    , "    constant int &batch [[buffer(6)]], uint gid [[thread_position_in_grid]]) {"
    , "  int total = batch * hidden; int idx = int(gid); if (idx >= total) { return; }"
    , "  int b = idx / hidden; int i = idx % hidden; float d_act = 0.0f;"
    , "  for (int k = 0; k < outputs; ++k) { d_act += w2[k * hidden + i] * d_l_dy[b * outputs + k]; }"
    , "  float h = hidden_act[b * hidden + i];"
    , "  d_hidden_pre[b * hidden + i] = d_act * (1.0f - h * h);"
    , "}"
    , ""
    , "// dx[b*inputs+j] = sum_i W1[i*inputs+j] * d_hidden_pre[b*hidden+i]."
    , "kernel void jitml_mlp_dx_batch("
    , "    device float *dx [[buffer(0)]], const device float *d_hidden_pre [[buffer(1)]],"
    , "    const device float *w1 [[buffer(2)]],"
    , "    constant int &inputs [[buffer(3)]], constant int &hidden [[buffer(4)]],"
    , "    constant int &batch [[buffer(5)]], uint gid [[thread_position_in_grid]]) {"
    , "  int total = batch * inputs; int idx = int(gid); if (idx >= total) { return; }"
    , "  int b = idx / inputs; int j = idx % inputs; float acc = 0.0f;"
    , "  for (int i = 0; i < hidden; ++i) { acc += w1[i * inputs + j] * d_hidden_pre[b * hidden + i]; }"
    , "  dx[b * inputs + j] = acc;"
    , "}"
    ]

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
