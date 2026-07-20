{-# LANGUAGE OverloadedStrings #-}

module RuntimeOperationsAccelerators
  ( runtimeOperationsAcceleratorTests
  )
where

import Data.Foldable (traverse_)
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

import JitML.Codegen.RuntimeOperationsCuda
  ( renderRuntimeOperationsCudaSource
  )
import JitML.Codegen.RuntimeOperationsMetal
  ( renderRuntimeOperationsMetalMetadata
  , runtimeOperationsMetalSource
  )
import JitML.Codegen.SourceFile (SourceFile (..))
import JitML.Engines.RuntimeOperationsDevice
  ( RuntimeOperation (..)
  , RuntimeOperationsDeviceError (..)
  , runtimeOperationCapability
  , runtimeOperationsAllCapabilities
  )
import JitML.Engines.RuntimeOperationsMetal
  ( MetalRuntimeOperationsTransport (..)
  , classifyMetalRuntimeOperationsBridgeFailure
  , metalRuntimeOperationsProductionTransport
  , runMetalRuntimeOperation
  , verifyMetalRuntimeOperationsMetadata
  )
import JitML.Env.Env (Env)

runtimeOperationsAcceleratorTests :: TestTree
runtimeOperationsAcceleratorTests =
  testGroup
    "accelerator runtime operations"
    [ testCase "generated CUDA source owns the complete versioned native ABI" $ do
        source <- singleSource renderRuntimeOperationsCudaSource
        assertContains source "constexpr std::uint32_t JITML_RUNTIME_OPERATIONS_ABI = 1"
        assertContains source "constexpr std::uint64_t JITML_RUNTIME_CAPABILITIES = 0xffULL"
        assertContains source "cudaMalloc"
        assertContains source "cudaMemcpyHostToDevice"
        assertContains source "runtime_attention_kernel<<<1, 1>>>"
        assertContains
          source
          "output[token * width + channel] = mixed[channel * token_count + token];"
        assertContains source "output[query * width + channel] = attended;"
        assertNotContains
          source
          "tokens[token * width + channel] + mixed[channel * token_count + token]"
        assertNotContains source "tokens[query * width + channel] + attended"
        traverse_ (assertContains source) runtimeOperationSymbols
    , testCase "generated Metal metadata binds exact ABI, capabilities, fp32 transport, and source" $ do
        metadata <- singleSource renderRuntimeOperationsMetalMetadata
        assertContains metadata "\"abi_version\": 1"
        assertContains metadata "\"capabilities\": 255"
        assertContains metadata "fixed-bridge-fp32-host-buffers"
        assertContains metadata "\"source_sha256\""
        traverse_ (assertContains metadata) runtimeOperationSymbols
        traverse_ (assertContains runtimeOperationsMetalSource) runtimeOperationSymbols
        assertContains runtimeOperationsMetalSource "[[thread_position_in_grid]]"
        assertContains runtimeOperationsMetalSource "const device float *args [[buffer(2)]]"
        assertContains
          runtimeOperationsMetalSource
          "out[id] = input[count + channel * token_count + token];"
        assertContains runtimeOperationsMetalSource "} out[id] = attended;"
        assertNotContains
          runtimeOperationsMetalSource
          "out[id] = input[id] + input[count + channel * token_count + token];"
        assertNotContains runtimeOperationsMetalSource "out[id] = tokens[id] + attended;"
    , testCase "Metal callbacks require and dispatch every generated operation symbol" $ do
        observed <- newIORef []
        let transport =
              metalRuntimeOperationsProductionTransport
                { metalRuntimeOperationsDispatch =
                    \_env symbol input arguments outputCount -> do
                      modifyIORef' observed (<> [(symbol, length input, length arguments, outputCount)])
                      pure (Right (replicate outputCount 0.25))
                }
        traverse_
          ( \(operation, symbol) -> do
              result <-
                runMetalRuntimeOperation
                  transport
                  unusedEnv
                  operation
                  symbol
                  [1.0]
                  [1.0]
                  1
              result @?= Right (VU.singleton 0.25)
          )
          runtimeOperationEntries
        calls <- readIORef observed
        fmap (\(symbol, _, _, _) -> symbol) calls
          @?= fmap snd runtimeOperationEntries
    , testCase "Metal preflight rejects an incomplete capability envelope before dispatch" $ do
        let missing = runtimeOperationCapability RuntimeAttentionOperation
            transport =
              inertTransport
                { metalRuntimeOperationsCapabilities =
                    runtimeOperationsAllCapabilities - missing
                }
        result <-
          runMetalRuntimeOperation
            transport
            unusedEnv
            RuntimeAttentionOperation
            "jitml_runtime_attention"
            [1.0]
            [1.0]
            1
        result
          @?= Left
            RuntimeOperationsCapabilityMismatch
              { runtimeOperationsErrorRequiredCapabilities =
                  runtimeOperationsAllCapabilities
              , runtimeOperationsErrorActualCapabilities =
                  runtimeOperationsAllCapabilities - missing
              }
    , testCase "Metal preflight rejects an undeclared operation function before dispatch" $ do
        let symbol = "jitml_runtime_mean_pool"
            transport =
              inertTransport
                { metalRuntimeOperationsSymbols =
                    Set.delete symbol (metalRuntimeOperationsSymbols inertTransport)
                }
        result <-
          runMetalRuntimeOperation
            transport
            unusedEnv
            RuntimeMeanPoolOperation
            symbol
            [1.0]
            [1.0]
            1
        result
          @?= Left
            ( RuntimeOperationsSymbolError
                symbol
                "not declared by cached Metal metadata"
            )
    , testCase "Metal dispatch failures remain typed and stage-attributed" $ do
        let failure =
              RuntimeOperationsExecutionError
                "apple-silicon mean-pool fixed-bridge-fp32 dispatch"
                "command buffer failed"
            transport =
              inertTransport
                { metalRuntimeOperationsDispatch =
                    \_ _ _ _ _ -> pure (Left failure)
                }
        result <-
          runMetalRuntimeOperation
            transport
            unusedEnv
            RuntimeMeanPoolOperation
            "jitml_runtime_mean_pool"
            [1.0]
            [1.0]
            1
        result @?= Left failure
    , testCase "Metal bridge errors distinguish load, MSL function, bridge symbol, compile, and dispatch" $ do
        classifyMetalRuntimeOperationsBridgeFailure
          "jitml_runtime_attention"
          "fixed Metal bridge dylib not found"
          @?= RuntimeOperationsLoadError "fixed Metal bridge dylib not found"
        classifyMetalRuntimeOperationsBridgeFailure
          "jitml_runtime_attention"
          "Metal function not found: jitml_runtime_attention"
          @?= RuntimeOperationsSymbolError
            "jitml_runtime_attention"
            "Metal function not found: jitml_runtime_attention"
        classifyMetalRuntimeOperationsBridgeFailure
          "jitml_runtime_attention"
          "dlsym: symbol not found"
          @?= RuntimeOperationsSymbolError
            "jitml_metal_bridge_run"
            "dlsym: symbol not found"
        classifyMetalRuntimeOperationsBridgeFailure
          "jitml_runtime_attention"
          "Metal library compile failed"
          @?= RuntimeOperationsCompileError "Metal library compile failed"
        classifyMetalRuntimeOperationsBridgeFailure
          "jitml_runtime_attention"
          "command buffer failed"
          @?= RuntimeOperationsExecutionError
            "apple-silicon jitml_runtime_attention fixed-bridge-fp32 dispatch"
            "command buffer failed"
    , testCase "cached Metal metadata must equal the exact rendered envelope" $ do
        metadata <- singleSource renderRuntimeOperationsMetalMetadata
        verifyMetalRuntimeOperationsMetadata metadata @?= Right ()
        verifyMetalRuntimeOperationsMetadata (metadata <> "tampered")
          @?= Left
            ( RuntimeOperationsLoadError
                "cached Metal runtime metadata bytes do not match the exact generated ABI/capability/source envelope"
            )
    ]

runtimeOperationEntries :: [(RuntimeOperation, Text)]
runtimeOperationEntries =
  [ (RuntimeInputTransformOperation, "jitml_runtime_input_transform")
  , (RuntimeOutputTransformOperation, "jitml_runtime_output_transform")
  , (RuntimeResidualAddOperation, "jitml_runtime_residual_add")
  , (RuntimeLayerNormOperation, "jitml_runtime_layer_norm")
  , (RuntimeTokenMixOperation, "jitml_runtime_token_mix_pack")
  , (RuntimeTokenMixOperation, "jitml_runtime_token_mix_merge")
  , (RuntimePatchExtractOperation, "jitml_runtime_patch_extract")
  , (RuntimeAttentionOperation, "jitml_runtime_attention")
  , (RuntimeMeanPoolOperation, "jitml_runtime_mean_pool")
  ]

runtimeOperationSymbols :: [Text]
runtimeOperationSymbols = fmap snd runtimeOperationEntries

inertTransport :: MetalRuntimeOperationsTransport
inertTransport =
  metalRuntimeOperationsProductionTransport
    { metalRuntimeOperationsDispatch =
        \_ _ _ _ outputCount -> pure (Right (replicate outputCount 0.0))
    }

unusedEnv :: Env
unusedEnv = error "injected Metal runtime transport unexpectedly forced Env"

singleSource :: [SourceFile] -> IO Text
singleSource [SourceFile _ contents] = pure contents
singleSource sources =
  assertFailure
    ("expected one generated source file, got " <> show (length sources))
    >> pure ""

assertContains :: Text -> Text -> IO ()
assertContains haystack needle =
  assertBool
    ("generated source is missing: " <> Text.unpack needle)
    (needle `Text.isInfixOf` haystack)

assertNotContains :: Text -> Text -> IO ()
assertNotContains haystack needle =
  assertBool
    ("generated source unexpectedly contains: " <> Text.unpack needle)
    (not (needle `Text.isInfixOf` haystack))
