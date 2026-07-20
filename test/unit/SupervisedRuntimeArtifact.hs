{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

module SupervisedRuntimeArtifact
  ( supervisedRuntimeArtifactTests
  , main
  )
where

import Control.Exception (throwIO)
import Data.Bits ((.|.))
import Data.ByteString.Lazy qualified as LazyByteString
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.List (find)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU
import System.Directory (doesFileExist)
import Test.Tasty (TestTree, defaultMain, testGroup)
import Test.Tasty.HUnit
  ( Assertion
  , assertBool
  , assertFailure
  , testCase
  , (@?=)
  )

import JitML.Checkpoint.Format qualified as Checkpoint
import JitML.Checkpoint.WeightCodec qualified as WeightCodec
import JitML.Codegen.RuntimeOperationsCpu qualified as RuntimeOperationsCodegen
import JitML.Codegen.SourceFile (SourceFile (..))
import JitML.Engines.Engine qualified as Engine
import JitML.Engines.RuntimeOperations qualified as RuntimeOperations
import JitML.Engines.RuntimeOperationsDevice qualified as RuntimeOperationsDevice
import JitML.Env.Build (buildEnv, defaultGlobalFlags)
import JitML.Numerics.Mlp qualified as Mlp
import JitML.Plan.Plan (Validation (..), planIdText)
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.SL.RuntimeArtifact qualified as Runtime
import JitML.Substrate (Substrate (..))

supervisedRuntimeArtifactTests :: TestTree
supervisedRuntimeArtifactTests =
  testGroup
    "SupervisedRuntimeArtifact"
    [ testCase "isolated JMW1 codec preserves the frozen bytes exactly" $ do
        let values = [0.0, -1.25, pi, 1.0e-200]
            bytes = WeightCodec.encodeJmw1 values
        bytes
          @?= LazyByteString.pack
            [ 74
            , 77
            , 87
            , 49
            , 7
            , 0
            , 0
            , 0
            , 131
            , 0
            , 99
            , 70
            , 54
            , 52
            , 4
            , 0
            , 0
            , 0
            , 0
            , 0
            , 0
            , 0
            , 0
            , 0
            , 0
            , 0
            , 0
            , 0
            , 0
            , 244
            , 191
            , 24
            , 45
            , 68
            , 84
            , 251
            , 33
            , 9
            , 64
            , 172
            , 247
            , 78
            , 21
            , 146
            , 126
            , 104
            , 22
            ]
        WeightCodec.decodeJmw1 bytes @?= Right values
        Text.length (WeightCodec.jmw1ContentSha bytes) @?= 64
    , testCase "virtual W1/b1/W2/b2 slices are derived in graph order" $ do
        runtime <- expectRight (Runtime.refineSupervisedRuntime denseRuntime)
        let slices = Runtime.supervisedRuntimeVirtualSlices runtime
        fmap Runtime.runtimeVirtualSliceParameterName slices
          @?= ["W1", "b1", "W2", "b2"]
        fmap Runtime.runtimeVirtualSliceOffset slices @?= [0, 4, 6, 12]
        fmap Runtime.runtimeVirtualSliceLength slices @?= [4, 2, 6, 3]
        Runtime.supervisedRuntimeParameterCount runtime @?= 15
        Runtime.supervisedRuntimeToRaw runtime @?= denseRuntime
    , testCase "exact artifact load rejects hash/count substitution" $ do
        let initialBytes =
              WeightCodec.encodeJmw1 (fmap fromIntegral [0 :: Int .. 14])
            finalBytes =
              WeightCodec.encodeJmw1 (fmap fromIntegral [1 :: Int .. 15])
        payload <- expectRight (payloadFor denseRuntime initialBytes finalBytes)
        _ <-
          expectRight
            (Runtime.mkTrainingRuntimeArtifact payload initialBytes finalBytes)
        assertLeft
          "substituted bytes"
          ( Runtime.loadSupervisedRuntime
              payload
              (WeightCodec.encodeJmw1 (replicate 15 0.0))
          )
        let shortInitialBytes = WeightCodec.encodeJmw1 (replicate 14 0.0)
            shortFinalBytes = WeightCodec.encodeJmw1 (1.0 : replicate 13 0.0)
        shortPayload <-
          expectRight
            (payloadFor denseRuntime shortInitialBytes shortFinalBytes)
        assertLeft
          "wrong exact tensor count"
          (Runtime.loadSupervisedRuntime shortPayload shortFinalBytes)
        assertLeft
          "unchanged training hashes"
          (payloadFor denseRuntime initialBytes initialBytes)
    , testCase "refinement rejects duplicate names and representation drift" $ do
        let duplicate =
              denseRuntime
                { Runtime.rawSupervisedRuntimeFamily =
                    Runtime.RawDeepDenseRuntimeFamily
                , Runtime.rawSupervisedRuntimeLayers =
                    [ Runtime.RawDenseLayer "same" (Runtime.RawRuntimeMlpShape 2 2 2)
                    , Runtime.RawDenseLayer "same" (Runtime.RawRuntimeMlpShape 2 2 2)
                    ]
                , Runtime.rawSupervisedRuntimeOutputTransform =
                    Runtime.RawIdentityOutput
                }
            invalidTransition =
              denseRuntime
                { Runtime.rawSupervisedRuntimeLayers =
                    [Runtime.RawLayerNormLayer "flat-layernorm"]
                }
        assertLeft "duplicate layer name" (Runtime.refineSupervisedRuntime duplicate)
        assertLeft
          "flat-to-layernorm transition"
          (Runtime.refineSupervisedRuntime invalidTransition)
    , testCase "tabular regression has a distinct exact family mapping" $ do
        refined <- expectRight (Runtime.refineSupervisedRuntime tabularRuntime)
        Runtime.supervisedRuntimeToRaw refined @?= tabularRuntime
        let mislabeled =
              tabularRuntime
                { Runtime.rawSupervisedRuntimeFamily =
                    Runtime.RawDenseRuntimeFamily
                }
        assertLeft
          "regression mislabeled as dense classification family"
          (Runtime.refineSupervisedRuntime mislabeled)
    , testCase "tabular standardize and destandardize programs execute exactly" $ do
        let initialBytes = WeightCodec.encodeJmw1 (replicate 9 0.0)
            finalBytes = WeightCodec.encodeJmw1 (1.0 : replicate 8 0.0)
        payload <- expectRight (payloadFor tabularRuntime initialBytes finalBytes)
        loaded <- expectRight (Runtime.loadSupervisedRuntime payload finalBytes)
        result <-
          Runtime.executeLoadedRuntime
            (testBackend (\_ input -> pure (Right (VU.singleton (VU.sum input)))))
            loaded
            (VU.fromList [12.0, 24.0])
        output <- expectRight result
        assertVectorApprox [110.0] output
    , testCase "classification standardization refines, round-trips, and executes exactly" $ do
        let standardizedRuntime =
              denseRuntime
                { Runtime.rawSupervisedRuntimeInputTransform =
                    Runtime.RawStandardizeInput [10.0, 20.0] [2.0, 4.0]
                }
            initialBytes = WeightCodec.encodeJmw1 (replicate 15 0.0)
            finalBytes = WeightCodec.encodeJmw1 (1.0 : replicate 14 0.0)
        refined <- expectRight (Runtime.refineSupervisedRuntime standardizedRuntime)
        Runtime.supervisedRuntimeToRaw refined @?= standardizedRuntime
        payload <- expectRight (payloadFor standardizedRuntime initialBytes finalBytes)
        loaded <- expectRight (Runtime.loadSupervisedRuntime payload finalBytes)
        result <-
          Runtime.executeLoadedRuntime
            ( testBackend
                ( \_ input ->
                    pure
                      ( Right
                          ( VU.fromList
                              [ input VU.! 0
                              , input VU.! 1
                              , 999.0
                              ]
                          )
                      )
                )
            )
            loaded
            (VU.fromList [12.0, 24.0])
        output <- expectRight result
        assertVectorApprox [1.0, 1.0] output
        assertLeft
          "classification zero standardization scale"
          ( Runtime.refineSupervisedRuntime
              standardizedRuntime
                { Runtime.rawSupervisedRuntimeInputTransform =
                    Runtime.RawStandardizeInput [10.0, 20.0] [2.0, 0.0]
                }
          )
        assertLeft
          "classification standardization width drift"
          ( Runtime.refineSupervisedRuntime
              standardizedRuntime
                { Runtime.rawSupervisedRuntimeInputTransform =
                    Runtime.RawStandardizeInput [10.0] [2.0]
                }
          )
    , testCase "patch/token-mix/attention execute the exact pre-23.1 semantics" $ do
        runtime <- expectRight (Runtime.refineSupervisedRuntime visionRuntime)
        let count = Runtime.supervisedRuntimeParameterCount runtime
            initialBytes = WeightCodec.encodeJmw1 (replicate count 0.0)
            finalBytes = WeightCodec.encodeJmw1 (1.0 : replicate (count - 1) 0.0)
        payload <- expectRight (payloadFor visionRuntime initialBytes finalBytes)
        loaded <- expectRight (Runtime.loadSupervisedRuntime payload finalBytes)
        result <-
          Runtime.executeLoadedRuntime
            (testBackend exactVisionCallback)
            loaded
            (VU.fromList [1.0, 0.0, 0.0, 1.0])
        output <- expectRight result
        assertVectorApprox [0.25, 0.0] output
        outOfRange <-
          Runtime.executeLoadedRuntime
            (testBackend exactVisionCallback)
            loaded
            (VU.fromList [255.0, 0.0, 0.0, 255.0])
        assertLeft "unit-image out-of-range tensor" outOfRange
    , testCase "executor never pads or trims callback results" $ do
        let initialBytes = WeightCodec.encodeJmw1 (replicate 15 0.0)
            finalBytes = WeightCodec.encodeJmw1 (1.0 : replicate 14 0.0)
        payload <- expectRight (payloadFor denseRuntime initialBytes finalBytes)
        loaded <- expectRight (Runtime.loadSupervisedRuntime payload finalBytes)
        result <-
          Runtime.executeLoadedRuntime
            (testBackend (\_ _ -> pure (Right (VU.singleton 0.0))))
            loaded
            (VU.fromList [1.0, 2.0])
        assertLeft "short callback output" result
    , testCase "selected backend owns every persisted graph operation" $ do
        runtime <- expectRight (Runtime.refineSupervisedRuntime completeDispatchRuntime)
        let count = Runtime.supervisedRuntimeParameterCount runtime
            initialBytes = WeightCodec.encodeJmw1 (replicate count 0.0)
            finalBytes = WeightCodec.encodeJmw1 (1.0 : replicate (count - 1) 0.0)
        payload <- expectRight (payloadFor completeDispatchRuntime initialBytes finalBytes)
        loaded <- expectRight (Runtime.loadSupervisedRuntime payload finalBytes)
        calls <- newIORef []
        result <-
          Runtime.executeLoadedRuntime
            (spyBackend calls exactVisionCallback)
            loaded
            (VU.fromList [1.0, 0.0, 0.0, 1.0])
        _ <- expectRight result
        observed <- Set.fromList <$> readIORef calls
        observed
          @?= Set.fromList
            [ "attention"
            , "input-transform"
            , "layer-norm"
            , "mean-pool"
            , "mlp"
            , "output-transform"
            , "patch-extract"
            , "residual-add"
            , "token-mix"
            ]
    , testCase "selected backend unsupported operation fails without fallback" $ do
        runtime <- expectRight (Runtime.refineSupervisedRuntime visionRuntime)
        let count = Runtime.supervisedRuntimeParameterCount runtime
            initialBytes = WeightCodec.encodeJmw1 (replicate count 0.0)
            finalBytes = WeightCodec.encodeJmw1 (1.0 : replicate (count - 1) 0.0)
        payload <- expectRight (payloadFor visionRuntime initialBytes finalBytes)
        loaded <- expectRight (Runtime.loadSupervisedRuntime payload finalBytes)
        let backend =
              (testBackend exactVisionCallback)
                { Runtime.runtimeBackendPatchExtractExecutor =
                    \_ _ _ -> pure (Left "patch extraction unsupported")
                }
        result <-
          Runtime.executeLoadedRuntime
            backend
            loaded
            (VU.fromList [1.0, 0.0, 0.0, 1.0])
        assertLeft "unsupported selected-backend patch extraction" result
    , testCase "linux-cpu runtime-operation renderer owns the complete versioned ABI" $ do
        case RuntimeOperationsCodegen.renderRuntimeOperationsCpuSource of
          [SourceFile path contents] -> do
            path @?= "kernel.cc"
            mapM_
              ( \symbol ->
                  assertBool
                    ("generated runtime source is missing " <> Text.unpack symbol)
                    (symbol `Text.isInfixOf` contents)
              )
              [ "jitml_runtime_operations_abi_version"
              , "jitml_runtime_operations_capabilities"
              , "jitml_runtime_input_transform"
              , "jitml_runtime_output_transform"
              , "jitml_runtime_residual_add"
              , "jitml_runtime_layer_norm"
              , "jitml_runtime_token_mix_pack"
              , "jitml_runtime_token_mix_merge"
              , "jitml_runtime_patch_extract"
              , "jitml_runtime_attention"
              , "jitml_runtime_mean_pool"
              , "double *output"
              ]
            assertBool
              "generated CPU token mix must preserve pre-23.1 replacement semantics"
              ( "mixed_channels[channel * token_count + token];"
                  `Text.isInfixOf` contents
              )
            assertBool
              "generated CPU attention must preserve pre-23.1 attended-value semantics"
              ("output[query_token * width + channel] = attended;" `Text.isInfixOf` contents)
            assertBool
              "generated CPU token mix must not add an implicit residual"
              ( not
                  ( "+ mixed_channels[channel * token_count + token]"
                      `Text.isInfixOf` contents
                  )
              )
            assertBool
              "generated CPU attention must not add an implicit residual"
              ( not
                  ( "tokens[query_token * width + channel] + attended"
                      `Text.isInfixOf` contents
                  )
              )
          sources ->
            assertFailure
              ("expected one generated runtime source file, got " <> show sources)
    , testCase "linux-cpu runtime operations compile, load, probe, and execute natively" $ do
        env <- buildEnv defaultGlobalFlags
        artifact <-
          expectRight
            =<< RuntimeOperationsDevice.probeRuntimeOperationsBackend
              RuntimeOperationsDevice.linuxCpuRuntimeOperationsSpec
              env
        RuntimeOperationsDevice.runtimeOperationsArtifactAbiVersion artifact
          @?= RuntimeOperationsDevice.runtimeOperationsAbiVersion
        RuntimeOperationsDevice.runtimeOperationsArtifactCapabilities artifact
          @?= RuntimeOperationsDevice.runtimeOperationsAllCapabilities
        let artifactPath =
              Text.unpack
                ( Engine.kernelHandleArtifactPath
                    (RuntimeOperationsDevice.runtimeOperationsArtifactHandle artifact)
                )
        assertBool "native runtime-operation artifact exists" =<< doesFileExist artifactPath

        runtime <- expectRight (Runtime.refineSupervisedRuntime completeDispatchRuntime)
        let count = Runtime.supervisedRuntimeParameterCount runtime
            initialBytes = WeightCodec.encodeJmw1 (replicate count 0.0)
            finalBytes = WeightCodec.encodeJmw1 (1.0 : replicate (count - 1) 0.0)
        payload <- expectRight (payloadFor completeDispatchRuntime initialBytes finalBytes)
        loaded <- expectRight (Runtime.loadSupervisedRuntime payload finalBytes)
        let input = VU.fromList [1.0, 0.0, 0.0, 1.0]
            nativeBackend =
              RuntimeOperationsDevice.runtimeOperationsBackendExecutor
                RuntimeOperationsDevice.linuxCpuRuntimeOperationsSpec
                env
                exactVisionCallback
        nativeResult <- Runtime.executeLoadedRuntime nativeBackend loaded input
        referenceResult <-
          Runtime.executeLoadedRuntime (testBackend exactVisionCallback) loaded input
        nativeOutput <- expectRight nativeResult
        referenceOutput <- expectRight referenceResult
        assertVectorNear 1.0e-12 referenceOutput nativeOutput
        repeated <- Runtime.executeLoadedRuntime nativeBackend loaded input >>= expectRight
        repeated @?= nativeOutput

        let tabularInitial = WeightCodec.encodeJmw1 (replicate 9 0.0)
            tabularFinal = WeightCodec.encodeJmw1 (1.0 : replicate 8 0.0)
            tabularMlp _ values = pure (Right (VU.singleton (VU.sum values)))
            tabularInput = VU.fromList [12.0, 24.0]
        tabularPayload <-
          expectRight (payloadFor tabularRuntime tabularInitial tabularFinal)
        tabularLoaded <-
          expectRight (Runtime.loadSupervisedRuntime tabularPayload tabularFinal)
        nativeTabular <-
          Runtime.executeLoadedRuntime
            ( RuntimeOperationsDevice.runtimeOperationsBackendExecutor
                RuntimeOperationsDevice.linuxCpuRuntimeOperationsSpec
                env
                tabularMlp
            )
            tabularLoaded
            tabularInput
            >>= expectRight
        referenceTabular <-
          Runtime.executeLoadedRuntime
            (testBackend tabularMlp)
            tabularLoaded
            tabularInput
            >>= expectRight
        assertVectorNear 1.0e-12 referenceTabular nativeTabular
        assertVectorApprox [110.0] nativeTabular

        let denseInitial = WeightCodec.encodeJmw1 (replicate 15 0.0)
            denseFinal = WeightCodec.encodeJmw1 (1.0 : replicate 14 0.0)
            denseMlp _ values =
              pure
                ( Right
                    ( VU.fromList
                        [ VU.sum values
                        , VU.product values
                        , 999.0
                        ]
                    )
                )
            denseInput = VU.fromList [2.0, 3.0]
        densePayload <- expectRight (payloadFor denseRuntime denseInitial denseFinal)
        denseLoaded <- expectRight (Runtime.loadSupervisedRuntime densePayload denseFinal)
        nativeDense <-
          Runtime.executeLoadedRuntime
            ( RuntimeOperationsDevice.runtimeOperationsBackendExecutor
                RuntimeOperationsDevice.linuxCpuRuntimeOperationsSpec
                env
                denseMlp
            )
            denseLoaded
            denseInput
            >>= expectRight
        referenceDense <-
          Runtime.executeLoadedRuntime
            (testBackend denseMlp)
            denseLoaded
            denseInput
            >>= expectRight
        assertVectorNear 1.0e-12 referenceDense nativeDense
        assertVectorApprox [5.0, 6.0] nativeDense

        unitTransform <-
          expectRight
            (Runtime.refineRuntimeInputTransform (Runtime.RawUnitImageInput geometry2x2))
        rejected <-
          RuntimeOperationsDevice.runtimeOperationsInputTransform
            RuntimeOperationsDevice.linuxCpuRuntimeOperationsSpec
            env
            unitTransform
            (VU.fromList [2.0, 0.0, 0.0, 0.0])
        assertLeft "native unit-image range validation" rejected
        let spec = RuntimeOperationsDevice.linuxCpuRuntimeOperationsSpec
            wrongAbi =
              spec
                { RuntimeOperationsDevice.runtimeOperationsBackendExpectedAbi =
                    RuntimeOperationsDevice.runtimeOperationsAbiVersion + 1
                }
            unknownCapability =
              RuntimeOperationsDevice.runtimeOperationsAllCapabilities .|. 0x100
            wrongCapabilities =
              spec
                { RuntimeOperationsDevice.runtimeOperationsBackendRequiredCapabilities =
                    unknownCapability
                }
        abiResult <- RuntimeOperationsDevice.probeRuntimeOperationsBackend wrongAbi env
        case abiResult of
          Left RuntimeOperationsDevice.RuntimeOperationsAbiMismatch {} -> pure ()
          other -> assertFailure ("expected typed ABI mismatch, got " <> show other)
        capabilityResult <-
          RuntimeOperationsDevice.probeRuntimeOperationsBackend wrongCapabilities env
        case capabilityResult of
          Left RuntimeOperationsDevice.RuntimeOperationsCapabilityMismatch {} -> pure ()
          other -> assertFailure ("expected typed capability mismatch, got " <> show other)
        symbolResult <-
          RuntimeOperationsDevice.probeRuntimeOperationsSymbol
            spec
            env
            "jitml_runtime_symbol_that_does_not_exist"
        case symbolResult of
          Left (RuntimeOperationsDevice.RuntimeOperationsSymbolError symbol _) ->
            symbol @?= "jitml_runtime_symbol_that_does_not_exist"
          other -> assertFailure ("expected typed symbol failure, got " <> show other)

        let throwingMlp params values =
              case Mlp.paramShape params of
                Mlp.MlpShape 4 _ 4 ->
                  throwIO (userError "selected-backend callback exploded")
                _ -> exactVisionCallback params values
            throwingBackend =
              RuntimeOperationsDevice.runtimeOperationsBackendExecutor
                spec
                env
                throwingMlp
        callbackException <-
          Runtime.executeLoadedRuntime throwingBackend loaded input
        case callbackException of
          Left err -> do
            assertBool
              "callback exception is typed as execution, not artifact load"
              ("execution exception" `Text.isInfixOf` err)
            assertBool
              "callback exception is not mislabeled as a load failure"
              (not ("artifact load failed" `Text.isInfixOf` err))
          Right output ->
            assertFailure
              ("throwing selected-backend callback unexpectedly returned " <> show output)
    , testCase "V2 PlanId rejects the wrong selected backend before dispatch" $ do
        row <-
          maybe
            (assertFailure "missing authoritative mnist-shallow-mlp ProductRow")
            pure
            (find ((== "mnist-shallow-mlp") . ProductMatrix.rowId) ProductMatrix.allProductRows)
        cpuPlanId <-
          case ProductMatrix.projectProductRow LinuxCPU row of
            Failure errors -> assertFailure (show errors)
            Success (ProductMatrix.SomeProductProjection _ projection) ->
              pure (planIdText (ProductMatrix.productProjectionPlanId projection))
        let initialBytes = WeightCodec.encodeJmw1 (replicate 15 0.0)
            finalBytes = WeightCodec.encodeJmw1 (1.0 : replicate 14 0.0)
        payload <-
          expectRight
            ( Runtime.refineSupervisedRuntimePayload
                Runtime.RawSupervisedRuntimePayload
                  { Runtime.rawRuntimePayloadRowId = "mnist-shallow-mlp"
                  , Runtime.rawRuntimePayloadOrigin = Runtime.RawProductRowProjectionOrigin
                  , Runtime.rawRuntimePayloadPlanId = cpuPlanId
                  , Runtime.rawRuntimePayloadDatasetSha256 = Text.replicate 64 "b"
                  , Runtime.rawRuntimePayloadInitialJmw1Sha256 =
                      WeightCodec.jmw1ContentSha initialBytes
                  , Runtime.rawRuntimePayloadFinalJmw1Sha256 =
                      WeightCodec.jmw1ContentSha finalBytes
                  , Runtime.rawRuntimePayloadRuntime = denseRuntime
                  }
            )
        Checkpoint.validateSupervisedRuntimePlanForSubstrate LinuxCPU payload
          @?= Right ()
        assertLeft
          "linux-cpu PlanId accepted by linux-cuda"
          (Checkpoint.validateSupervisedRuntimePlanForSubstrate LinuxCUDA payload)
    ]

main :: IO ()
main = defaultMain supervisedRuntimeArtifactTests

denseRuntime :: Runtime.RawSupervisedRuntime
denseRuntime =
  Runtime.RawSupervisedRuntime
    { Runtime.rawSupervisedRuntimeFamily = Runtime.RawDenseRuntimeFamily
    , Runtime.rawSupervisedRuntimeTask = Runtime.RawClassificationRuntimeTask 2
    , Runtime.rawSupervisedRuntimeInputTransform = Runtime.RawIdentityInput 2
    , Runtime.rawSupervisedRuntimeOutputTransform =
        Runtime.RawSemanticPrefixOutput 2
    , Runtime.rawSupervisedRuntimeLayers =
        [ Runtime.RawDenseLayer
            "classifier"
            Runtime.RawRuntimeMlpShape
              { Runtime.rawRuntimeMlpInputs = 2
              , Runtime.rawRuntimeMlpHidden = 2
              , Runtime.rawRuntimeMlpOutputs = 3
              }
        ]
    }

visionRuntime :: Runtime.RawSupervisedRuntime
visionRuntime =
  Runtime.RawSupervisedRuntime
    { Runtime.rawSupervisedRuntimeFamily =
        Runtime.RawVisionTransformerRuntimeFamily
    , Runtime.rawSupervisedRuntimeTask = Runtime.RawClassificationRuntimeTask 2
    , Runtime.rawSupervisedRuntimeInputTransform =
        Runtime.RawUnitImageInput geometry
    , Runtime.rawSupervisedRuntimeOutputTransform = Runtime.RawIdentityOutput
    , Runtime.rawSupervisedRuntimeLayers =
        [ Runtime.RawPatchLayer "patch" geometry 1 1 1 2
        , Runtime.RawTokenMixLayer "token-mix" 4 1
        , Runtime.RawAttentionLayer "attention" 2 1
        , Runtime.RawMeanPoolLayer "mean-pool"
        , Runtime.RawDenseLayer "classifier" (Runtime.RawRuntimeMlpShape 2 1 2)
        ]
    }
 where
  geometry = geometry2x2

completeDispatchRuntime :: Runtime.RawSupervisedRuntime
completeDispatchRuntime =
  visionRuntime
    { Runtime.rawSupervisedRuntimeLayers =
        [ Runtime.RawPatchLayer "patch" geometry 1 1 1 2
        , Runtime.RawLayerNormLayer "layer-norm"
        , Runtime.RawTokenMixLayer "token-mix" 4 1
        , Runtime.RawAttentionLayer "attention" 2 1
        , Runtime.RawResidualLayer
            "residual"
            0.5
            (Runtime.RawRuntimeMlpShape 2 1 2)
        , Runtime.RawMeanPoolLayer "mean-pool"
        , Runtime.RawDenseLayer "classifier" (Runtime.RawRuntimeMlpShape 2 1 2)
        ]
    }
 where
  geometry = geometry2x2

geometry2x2 :: Runtime.RawRuntimeImageGeometry
geometry2x2 = Runtime.RawRuntimeImageGeometry 2 2 1

tabularRuntime :: Runtime.RawSupervisedRuntime
tabularRuntime =
  Runtime.RawSupervisedRuntime
    { Runtime.rawSupervisedRuntimeFamily =
        Runtime.RawTabularRegressionRuntimeFamily
    , Runtime.rawSupervisedRuntimeTask = Runtime.RawRegressionRuntimeTask 1
    , Runtime.rawSupervisedRuntimeInputTransform =
        Runtime.RawStandardizeInput [10.0, 20.0] [2.0, 4.0]
    , Runtime.rawSupervisedRuntimeOutputTransform =
        Runtime.RawDestandardizeOutput [100.0] [5.0]
    , Runtime.rawSupervisedRuntimeLayers =
        [ Runtime.RawDenseLayer
            "regressor"
            (Runtime.RawRuntimeMlpShape 2 2 1)
        ]
    }

payloadFor
  :: Runtime.RawSupervisedRuntime
  -> LazyByteString.ByteString
  -> LazyByteString.ByteString
  -> Either Text Runtime.SupervisedRuntimePayload
payloadFor runtime initialBytes finalBytes =
  Runtime.refineSupervisedRuntimePayload
    Runtime.RawSupervisedRuntimePayload
      { Runtime.rawRuntimePayloadRowId = "test-row"
      , Runtime.rawRuntimePayloadOrigin = Runtime.RawProductRowProjectionOrigin
      , Runtime.rawRuntimePayloadPlanId = Text.replicate 64 "a"
      , Runtime.rawRuntimePayloadDatasetSha256 = Text.replicate 64 "b"
      , Runtime.rawRuntimePayloadInitialJmw1Sha256 =
          WeightCodec.jmw1ContentSha initialBytes
      , Runtime.rawRuntimePayloadFinalJmw1Sha256 =
          WeightCodec.jmw1ContentSha finalBytes
      , Runtime.rawRuntimePayloadRuntime = runtime
      }

exactVisionCallback
  :: Mlp.MlpParams
  -> VU.Vector Double
  -> IO (Either Text (VU.Vector Double))
exactVisionCallback params input =
  pure $
    case Mlp.paramShape params of
      Mlp.MlpShape 3 _ 2 ->
        Right (VU.fromList [input VU.! 0, input VU.! 1 + input VU.! 2])
      Mlp.MlpShape 4 _ 4 -> Right (VU.map (* 0.5) input)
      Mlp.MlpShape 2 _ 6 ->
        Right (VU.fromList [0.0, 0.0, 0.0, 0.0] VU.++ input)
      Mlp.MlpShape 2 _ 2 -> Right input
      shape -> Left ("unexpected test MLP shape: " <> Text.pack (show shape))

testBackend :: Runtime.RuntimeMlpExecutor -> Runtime.RuntimeBackendExecutor
testBackend executeMlp =
  Runtime.RuntimeBackendExecutor
    { Runtime.runtimeBackendLabel = "unit-test"
    , Runtime.runtimeBackendInputTransformExecutor =
        RuntimeOperations.hostInputTransform
    , Runtime.runtimeBackendOutputTransformExecutor =
        RuntimeOperations.hostOutputTransform
    , Runtime.runtimeBackendMlpExecutor = executeMlp
    , Runtime.runtimeBackendResidualAddExecutor =
        RuntimeOperations.hostResidualAdd
    , Runtime.runtimeBackendLayerNormExecutor =
        RuntimeOperations.hostLayerNorm
    , Runtime.runtimeBackendTokenMixExecutor =
        RuntimeOperations.hostTokenMix
    , Runtime.runtimeBackendPatchExtractExecutor =
        RuntimeOperations.hostPatchExtract
    , Runtime.runtimeBackendAttentionExecutor =
        RuntimeOperations.hostAttention
    , Runtime.runtimeBackendMeanPoolExecutor =
        RuntimeOperations.hostMeanPool
    }

spyBackend
  :: IORef [Text]
  -> Runtime.RuntimeMlpExecutor
  -> Runtime.RuntimeBackendExecutor
spyBackend calls executeMlp =
  Runtime.RuntimeBackendExecutor
    { Runtime.runtimeBackendLabel = "spy-backend"
    , Runtime.runtimeBackendInputTransformExecutor =
        \transform input -> do
          record "input-transform"
          RuntimeOperations.hostInputTransform transform input
    , Runtime.runtimeBackendOutputTransformExecutor =
        \task transform output -> do
          record "output-transform"
          RuntimeOperations.hostOutputTransform task transform output
    , Runtime.runtimeBackendMlpExecutor =
        \params input -> do
          record "mlp"
          executeMlp params input
    , Runtime.runtimeBackendResidualAddExecutor =
        \scale input residual -> do
          record "residual-add"
          RuntimeOperations.hostResidualAdd scale input residual
    , Runtime.runtimeBackendLayerNormExecutor =
        \input -> do
          record "layer-norm"
          RuntimeOperations.hostLayerNorm input
    , Runtime.runtimeBackendTokenMixExecutor =
        \backend layer tokens width shape params input -> do
          record "token-mix"
          RuntimeOperations.hostTokenMix backend layer tokens width shape params input
    , Runtime.runtimeBackendPatchExtractExecutor =
        \geometry positions input -> do
          record "patch-extract"
          RuntimeOperations.hostPatchExtract geometry positions input
    , Runtime.runtimeBackendAttentionExecutor =
        \backend layer width shape params input -> do
          record "attention"
          RuntimeOperations.hostAttention backend layer width shape params input
    , Runtime.runtimeBackendMeanPoolExecutor =
        \input -> do
          record "mean-pool"
          RuntimeOperations.hostMeanPool input
    }
 where
  record operation = modifyIORef' calls (operation :)

expectRight :: (Show error) => Either error value -> IO value
expectRight result =
  case result of
    Left err -> assertFailure (show err)
    Right value -> pure value

assertLeft :: (Show value) => String -> Either Text value -> Assertion
assertLeft label result =
  case result of
    Left _ -> pure ()
    Right value -> assertFailure (label <> " unexpectedly succeeded: " <> show value)

assertVectorApprox :: [Double] -> VU.Vector Double -> Assertion
assertVectorApprox expected actual = do
  VU.length actual @?= length expected
  assertBool
    ("expected " <> show expected <> ", got " <> show (VU.toList actual))
    (and (zipWith (\left right -> abs (left - right) <= 1.0e-12) expected (VU.toList actual)))

assertVectorNear
  :: Double -> VU.Vector Double -> VU.Vector Double -> Assertion
assertVectorNear tolerance expected actual = do
  VU.length actual @?= VU.length expected
  assertBool
    ( "expected "
        <> show (VU.toList expected)
        <> ", got "
        <> show (VU.toList actual)
    )
    ( VU.and
        ( VU.zipWith
            (\left right -> abs (left - right) <= tolerance)
            expected
            actual
        )
    )
