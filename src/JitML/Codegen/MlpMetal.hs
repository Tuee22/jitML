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
  , mlpMetalActivation
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

-- | The device function name used for every Metal MLP hidden activation.
-- Exported so the backend source guard can reject a return to MSL's native
-- @tanh@, whose float results diverge from the operation sequence used by the
-- two aligned Linux lanes.
mlpMetalActivation :: Text
mlpMetalActivation = "jitml_mlp_tanhf"

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
    , "#pragma clang fp contract(off)"
    , "using namespace metal;"
    , ""
    , activationHelpers
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
    , "  hidden_pre[i] = acc; hidden_act[i] = " <> mlpMetalActivation <> "(acc);"
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
    , "  hidden_act[b * hidden + i] = " <> mlpMetalActivation <> "(acc);"
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

-- | glibc's flt-32 @expm1f@/@tanhf@ operation sequence, expressed in MSL.
--
-- Phase 265 aligned the CUDA MLP with the oneDNN lane by rendering this
-- algorithm because native CUDA @tanhf@ and glibc @tanhf@ disagree at float
-- precision. Phase 271 completes that invariant for Apple Silicon: MSL's
-- native @tanh@ is a third implementation and drove deterministic RL policies
-- onto different trajectories. The fixed bridge compiles this source with
-- @fastMathEnabled = false@ and this source disables FP contraction, so the
-- individual float operations retain the ordered IEEE arithmetic expressed
-- below.
activationHelpers :: Text
activationHelpers =
  Text.unlines
    [ "// Phase 271 — glibc's flt-32 expm1f/tanhf algorithm, rendered so all"
    , "// three substrate MLP artifacts evaluate one hidden activation the same way."
    , "inline float jitml_mlp_expm1f(float x) {"
    , "  const float one = 1.0f;"
    , "  const float huge_v = 1.0e+30f;"
    , "  const float tiny_v = 1.0e-30f;"
    , "  const float o_threshold = 8.8721679688e+01f;"
    , "  const float ln2_hi = 6.9313812256e-01f;"
    , "  const float ln2_lo = 9.0580006145e-06f;"
    , "  const float invln2 = 1.4426950216e+00f;"
    , "  const float Q1 = -3.3333335072e-02f;"
    , "  const float Q2 = 1.5873016091e-03f;"
    , "  const float Q3 = -7.9365076090e-05f;"
    , "  const float Q4 = 4.0082177293e-06f;"
    , "  const float Q5 = -2.0109921195e-07f;"
    , "  float y, hi, lo, c, t, e, hxs, hfx, r1, twopk;"
    , "  int k = 0;"
    , "  int xsb;"
    , "  uint hx = as_type<uint>(x);"
    , "  xsb = int(hx & 0x80000000u);"
    , "  hx &= 0x7fffffffu;"
    , "  c = 0.0f;"
    , "  hi = 0.0f;"
    , "  lo = 0.0f;"
    , "  if (hx >= 0x4195b844u) {"
    , "    if (hx >= 0x42b17218u) {"
    , "      if (hx > 0x7f800000u) { return x + x; }"
    , "      if (hx == 0x7f800000u) { return (xsb == 0) ? x : -1.0f; }"
    , "      if (x > o_threshold) { return huge_v * huge_v; }"
    , "    }"
    , "    if (xsb != 0) {"
    , "      if (x + tiny_v < 0.0f) { return tiny_v - one; }"
    , "    }"
    , "  }"
    , "  if (hx > 0x3eb17218u) {"
    , "    if (hx < 0x3f851592u) {"
    , "      if (xsb == 0) { hi = x - ln2_hi; lo = ln2_lo; k = 1; }"
    , "      else { hi = x + ln2_hi; lo = -ln2_lo; k = -1; }"
    , "    } else {"
    , "      k = int(invln2 * x + ((xsb == 0) ? 0.5f : -0.5f));"
    , "      t = float(k);"
    , "      hi = x - t * ln2_hi;"
    , "      lo = t * ln2_lo;"
    , "    }"
    , "    x = hi - lo;"
    , "    c = (hi - x) - lo;"
    , "  } else if (hx < 0x33000000u) {"
    , "    t = huge_v + x;"
    , "    return x - (t - (huge_v + x));"
    , "  } else {"
    , "    k = 0;"
    , "  }"
    , "  hfx = 0.5f * x;"
    , "  hxs = x * hfx;"
    , "  r1 = one + hxs * (Q1 + hxs * (Q2 + hxs * (Q3 + hxs * (Q4 + hxs * Q5))));"
    , "  t = 3.0f - r1 * hfx;"
    , "  e = hxs * ((r1 - t) / (6.0f - x * t));"
    , "  if (k == 0) { return x - (x * e - hxs); }"
    , "  twopk = as_type<float>(uint((0x7f + k) << 23));"
    , "  e = x * (e - c) - c;"
    , "  e -= hxs;"
    , "  if (k == -1) { return 0.5f * (x - e) - 0.5f; }"
    , "  if (k == 1) {"
    , "    if (x < -0.25f) { return -2.0f * (e - (x + 0.5f)); }"
    , "    else { return one + 2.0f * (x - e); }"
    , "  }"
    , "  if (k <= -2 || k > 56) {"
    , "    y = one - (e - x);"
    , "    if (k == 128) { y = y * 2.0f * 0x1p127f; }"
    , "    else { y = y * twopk; }"
    , "    return y - one;"
    , "  }"
    , "  if (k < 23) {"
    , "    t = as_type<float>(uint(0x3f800000u - (0x1000000u >> uint(k))));"
    , "    y = t - (e - x);"
    , "    y = y * twopk;"
    , "  } else {"
    , "    t = as_type<float>(uint((0x7f - k) << 23));"
    , "    y = x - (e + t);"
    , "    y += one;"
    , "    y = y * twopk;"
    , "  }"
    , "  return y;"
    , "}"
    , ""
    , "inline float " <> mlpMetalActivation <> "(float x) {"
    , "  const float one = 1.0f;"
    , "  const float tiny_v = 1.0e-30f;"
    , "  float t, z;"
    , "  int jx = as_type<int>(x);"
    , "  int ix = jx & 0x7fffffff;"
    , "  if (ix >= 0x7f800000) {"
    , "    if (jx >= 0) { return one / x + one; }"
    , "    else { return one / x - one; }"
    , "  }"
    , "  if (ix < 0x41b00000) {"
    , "    if (ix < 0x24000000) { return x * (one + x); }"
    , "    if (ix >= 0x3f800000) {"
    , "      t = jitml_mlp_expm1f(2.0f * fabs(x));"
    , "      z = one - 2.0f / (t + 2.0f);"
    , "    } else {"
    , "      t = jitml_mlp_expm1f(-2.0f * fabs(x));"
    , "      z = -t / (t + 2.0f);"
    , "    }"
    , "  } else {"
    , "    z = one - tiny_v;"
    , "  }"
    , "  return (jx >= 0) ? z : -z;"
    , "}"
    , ""
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
