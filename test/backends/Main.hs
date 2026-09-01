{-# LANGUAGE OverloadedStrings #-}

module Main where

import Data.Foldable (for_)
import Data.Text qualified as Text
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

import Control.Exception qualified
import Data.Bits qualified as Bits
import Data.ByteString qualified as ByteString
import Data.Either (isRight, lefts)
import Data.List qualified as List
import Data.Time.Clock.POSIX (getPOSIXTime)
import Data.Vector.Unboxed qualified as VU
import GHC.Float qualified
import JitML.Cache.Key qualified as Cache
import JitML.Codegen.Cuda qualified as CudaCodegen
import JitML.Codegen.KernelFamily (KernelFamily (..), familyName, kernelFamilies)
import JitML.Codegen.Metal qualified as MetalCodegen
import JitML.Codegen.MetalLayerTraining qualified as MetalLayerTraining
import JitML.Codegen.MlpCuda qualified as MlpCudaCodegen
import JitML.Codegen.MlpMetal qualified as MlpMetalCodegen
import JitML.Codegen.RuntimeSource qualified as RuntimeSource
import JitML.Codegen.SourceFile (SourceFile (..))
import JitML.Engines.CublasBindings qualified as Cublas
import JitML.Engines.CudaLocal
  ( cudaKernelOutput
  , cudaKernelReportedFamily
  , runCudaFamilyKernel
  )
import JitML.Engines.CudaLocal qualified as Cuda
import JitML.Engines.CudaRuntime qualified as CudaRuntime
import JitML.Engines.CudnnBindings qualified as Cudnn
import JitML.Engines.Engine qualified as Engine
import JitML.Engines.Fingerprint qualified as Fingerprint
import JitML.Engines.HasEngine
  ( EngineRequest (..)
  , engineRunOutput
  , engineRunReportedFamily
  , runLinuxCpuEngine
  )
import JitML.Engines.Loader qualified as Loader
import JitML.Engines.Local
  ( linuxCpuKernelOutput
  , linuxCpuKernelReportedFamily
  , runLinuxCpuFamilyKernel
  , runLinuxCpuIdentityKernel
  )
import JitML.Engines.Local qualified as Local
import JitML.Engines.MetalLocal qualified as Metal
import JitML.Engines.MetalRuntime qualified as MetalRuntime
import JitML.Engines.Tuning qualified as Tuning
import JitML.Engines.TuningBenchmark qualified as TuningBenchmark
import JitML.Env.Build (buildEnv, defaultGlobalFlags)
import JitML.Env.Env (Env, envCacheDir)
import JitML.Numerics.FamilyReference (familyReference, unweightedFamilyReference)
import JitML.Numerics.LayerGraph qualified as LayerGraph
import JitML.Numerics.LayerGraphDevice qualified as LayerGraphDevice
import JitML.Numerics.Mlp
  ( MlpForward (..)
  , MlpGradient (..)
  , MlpParams (..)
  , MlpShape (..)
  , mlpBackward
  , mlpForward
  , mlpInit
  , mlpInputGradient
  )
import JitML.Numerics.MlpCuda
  ( mlpBackwardCuda
  , mlpBatchGradientCuda
  , mlpForwardBatchCuda
  , mlpForwardCuda
  , mlpInputGradientBatchCuda
  )
import JitML.Numerics.MlpMetal
  ( mlpBackwardMetal
  , mlpBatchGradientMetal
  , mlpForwardBatchMetal
  , mlpForwardMetal
  , mlpInputGradientBatchMetal
  )
import JitML.Numerics.MlpOneDnn
  ( mlpBackwardOneDnn
  , mlpBatchGradientOneDnn
  , mlpForwardBatchOneDnn
  , mlpForwardOneDnn
  , mlpInputGradientBatchOneDnn
  )
import JitML.RL.Algorithms.ContinuousTrainer
  ( ContinuousIterationStat (..)
  , ContinuousTrainConfig (..)
  , ContinuousTrainResult (..)
  , ContinuousVariant (..)
  , defaultContinuousTrainConfig
  , trainContinuousOnPendulumCuda
  , trainContinuousOnPendulumMetal
  , trainContinuousOnPendulumOneDnn
  )
import JitML.RL.Algorithms.DqnTrainer
  ( DqnIterationStat (..)
  , DqnTrainConfig (..)
  , DqnTrainResult (..)
  , defaultDqnTrainConfig
  , trainDqnOnCartpoleCuda
  , trainDqnOnCartpoleMetal
  , trainDqnOnCartpoleOneDnn
  )
import JitML.RL.Algorithms.HerTrainer
  ( HerIterationStat (..)
  , HerTrainConfig (..)
  , HerTrainResult (..)
  , defaultHerTrainConfig
  , trainHerOnBitFlipCuda
  , trainHerOnBitFlipMetal
  , trainHerOnBitFlipOneDnn
  )
import JitML.RL.Algorithms.PpoTrainer
  ( OnPolicyVariant (..)
  , PpoIterationStat (..)
  , PpoTrainConfig (..)
  , PpoTrainResult (..)
  , defaultPpoTrainConfig
  , trainOnPolicyOnCartpoleCuda
  , trainOnPolicyOnCartpoleMetal
  , trainOnPolicyOnCartpoleOneDnn
  )
import JitML.RL.Algorithms.QrDqnTrainer
  ( QrDqnIterationStat (..)
  , QrDqnTrainConfig (..)
  , QrDqnTrainResult (..)
  , defaultQrDqnTrainConfig
  , trainQrDqnOnCartpoleCuda
  , trainQrDqnOnCartpoleMetal
  , trainQrDqnOnCartpoleOneDnn
  )
import JitML.RL.AlphaZero (initialConnect4)
import JitML.RL.AlphaZero.PolicyValueNet qualified as PVN
import JitML.Substrate qualified as Substrate
import Path (toFilePath)
import System.Directory (listDirectory)
import System.Environment (lookupEnv)
import System.FilePath ((</>))

expectRight :: String -> Either Text.Text a -> IO a
expectRight label result =
  case result of
    Right value -> pure value
    Left err -> assertFailure (label <> ": " <> Text.unpack err)

-- | Compile one rendered source twice, at two distinct cache addresses, and
-- return the two artifacts' bytes.
--
-- Sprint `78.1` — this is the gate that discharges
-- 'JitML.Substrate.ArtifactProducer'. The type can make every *known*
-- non-determinism source unpinnable-by-omission, but it cannot prove the set is
-- complete; only compiling twice and comparing can. It therefore runs on every
-- lane, including the two whose pin set is empty, because an empty set is a
-- claim rather than an absence of one.
--
-- Two distinct synthetic hashes give two source directories, two artifact
-- paths, and two scratch directories in one move, so a producer that embedded
-- any of those paths would be caught here.
compileArtifactTwice
  :: Substrate.Substrate -> IO (Either Text.Text (ByteString.ByteString, ByteString.ByteString))
compileArtifactTwice substrate = do
  env <- buildEnv defaultGlobalFlags
  case LayerGraphDevice.layerTrainingBackendFor substrate of
    Left err -> pure (Left err)
    Right backend -> compileBoth env backend
 where
  compileBoth env backend = do
    let source = LayerGraphDevice.layerGraphDeviceRuntimeSource backend
        hashes =
          [ Cache.cacheKey
              (Cache.KernelSpec ("phase-78-reproducibility-" <> Text.pack (show index)))
              Cache.Training
              substrate
              (Fingerprint.layerTrainingToolchainFingerprint substrate)
              (RuntimeSource.runtimeSourcePayload source)
              Cache.defaultTuningChoice
          | index <- [0 :: Int, 1]
          ]
    outcomes <- traverse (compileOnce env source) hashes
    pure $
      case outcomes of
        [Right first, Right second] -> Right (first, second)
        failures -> Left (Text.intercalate "; " (lefts failures))

  compileOnce env source hash = do
    artifact <- Loader.ensureKernelArtifact env (Engine.engineForSubstrate substrate) source hash
    case artifact of
      Left err -> pure (Left (Loader.renderKernelArtifactError err))
      Right built -> do
        let path = Text.unpack (Engine.kernelHandleArtifactPath (Loader.kernelArtifactHandle built))
        bytes <- ByteString.readFile path
        pure (Right bytes)

main :: IO ()
main =
  defaultMain $
    testGroup
      "jitml-backends"
      [ testCase "linux-cpu JIT compile/load/run executes the generated identity kernel" $ do
          env <- buildEnv defaultGlobalFlags
          result <- runLinuxCpuIdentityKernel env [1.25, 2.5, -3.75]
          case result of
            Left message -> assertBool ("linux-cpu JIT run failed: " <> show message) False
            Right kernelRun -> do
              linuxCpuKernelReportedFamily kernelRun @?= "identity"
              linuxCpuKernelOutput kernelRun @?= [1.25, 2.5, -3.75]
      , testCase "linux-cpu reduction family compiles through the generated FFI path" $ do
          env <- buildEnv defaultGlobalFlags
          result <- runLinuxCpuFamilyKernel env Reduction [4.0, -2.0, 1.0, 3.0]
          case result of
            Left message -> assertBool ("linux-cpu reduction JIT run failed: " <> show message) False
            Right kernelRun -> do
              linuxCpuKernelReportedFamily kernelRun @?= "reduction"
              linuxCpuKernelOutput kernelRun @?= [6.0]
      , testCase "linux-cpu family scaffolds compile/load/run through the generated FFI path" $ do
          env <- buildEnv defaultGlobalFlags
          mapM_ (assertFamilySmoke env) kernelFamilies
      , testCase "linux-cpu HasEngine boundary dispatches generated family kernels" $ do
          env <- buildEnv defaultGlobalFlags
          result <- runLinuxCpuEngine env (EngineRequest Dense2D [4.0, -2.0, 1.0, 3.0])
          case result of
            Left message -> assertBool ("linux-cpu HasEngine run failed: " <> show message) False
            Right engineRun -> do
              engineRunReportedFamily engineRun @?= "dense"
              engineRunOutput engineRun @?= [4.0, -2.0, 1.0, 3.0]
      , testCase "linux-cpu runs representative oneDNN reduction, matmul, and convolution primitives" $ do
          env <- buildEnv defaultGlobalFlags
          assertOneDnnOutput env Reduction [4.0, -2.0, 1.0, 3.0] [6.0]
          assertOneDnnOutput env Dense2D [4.0, -2.0, 1.0, 3.0] [4.0, -2.0, 1.0, 3.0]
          assertOneDnnOutput env Conv2DKernel [4.0, -2.0, 1.0, 3.0] [4.0, -2.0, 1.0, 3.0]
          assertOneDnnOutput env Conv3DKernel [4.0, -2.0, 1.0, 3.0] [4.0, -2.0, 1.0, 3.0]
      , testCase "linux-cpu kernel output is bit-equal across repeated runs (Sprint 7.6)" $ do
          -- Sprint 7.6 same-host kernel-output equality test: two
          -- successive invocations against the same input through the
          -- generated identity kernel must produce bit-identical output.
          -- Validates the local determinism contract for `linux-cpu` per
          -- documents/engineering/determinism_contract.md.
          env <- buildEnv defaultGlobalFlags
          let payload = [0.0, 1.5, -2.25, 3.875, -4.125]
          first <- runLinuxCpuIdentityKernel env payload
          second <- runLinuxCpuIdentityKernel env payload
          third <- runLinuxCpuIdentityKernel env payload
          case (first, second, third) of
            (Right a, Right b, Right c) -> do
              linuxCpuKernelOutput a @?= linuxCpuKernelOutput b
              linuxCpuKernelOutput b @?= linuxCpuKernelOutput c
              linuxCpuKernelOutput a @?= payload
            _ ->
              assertBool "all three linux-cpu kernel runs succeed" False
      , testCase "linux-cpu weighted Dense2D kernel runs real GEMM bit-deterministically (Sprint 13.11)" $ do
          -- Sprint 13.11 same-host bit-equality for the weighted kernel
          -- ABI. Three successive invocations of the generated Dense2D
          -- `jitml_weighted_kernel` with the same input + weight buffer
          -- must produce bit-identical output. Confirms the new ABI is
          -- deterministic per the determinism contract.
          env <- buildEnv defaultGlobalFlags
          let input = [1.0, 2.0, 3.0]
              -- Row-major 3x3 weight matrix. Picks values that test
              -- multiple non-zero columns so the GEMM exercises every
              -- row of W (not just the diagonal):
              --   W = [[1, 0, 0],
              --        [0, 2, 0],
              --        [0, 0, 3]]
              -- input * W = [1, 4, 9].
              weights = [1, 0, 0, 0, 2, 0, 0, 0, 3]
          first <- Local.runLinuxCpuWeightedFamilyKernel env Dense2D input weights
          second <- Local.runLinuxCpuWeightedFamilyKernel env Dense2D input weights
          third <- Local.runLinuxCpuWeightedFamilyKernel env Dense2D input weights
          case (first, second, third) of
            (Right a, Right b, Right c) -> do
              Local.linuxCpuWeightedKernelReportedFamily a @?= "dense"
              Local.linuxCpuWeightedKernelOutput a @?= Local.linuxCpuWeightedKernelOutput b
              Local.linuxCpuWeightedKernelOutput b @?= Local.linuxCpuWeightedKernelOutput c
              Local.linuxCpuWeightedKernelOutput a @?= [1.0, 4.0, 9.0]
            _ ->
              assertBool "all three linux-cpu weighted kernel runs succeed" False
      , testCase
          "linux-cpu weighted Conv2D / Conv3D / BatchNorm / LayerNorm / Embedding bodies compile and run deterministically (Sprint 13.11)"
          $ do
            -- Sprint 13.11 closure for the other family weighted bodies.
            -- Each family's weighted ABI is exercised twice against the
            -- same input + weight buffer; the second invocation must be
            -- bit-equal to the first (determinism contract). The expected
            -- output values aren't asserted against literature fixtures
            -- (per README.md → Snapshot targets → Numerical-fixture
            -- prohibition); only run-to-run equality is the assertion.
            env <- buildEnv defaultGlobalFlags
            let input = [0.5, 1.5, 2.5, 3.5]
            let families =
                  [ (Conv2DKernel, [0, 1, 0, 1, 2, 1, 0, 1, 0 :: Float])
                  ,
                    ( Conv3DKernel
                    , [if i == 13 then 2.0 else 1.0 | i <- [0 :: Int .. 26]]
                    )
                  , (BatchNormKernel, [1.0, 1.0, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0])
                  , (LayerNormKernel, [1.0, 1.0, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0])
                  , (EmbeddingKernel, [10.0, 11.0, 12.0, 13.0, 20.0, 21.0, 22.0, 23.0])
                  ]
            for_ families $ \(family, weights) -> do
              first <- Local.runLinuxCpuWeightedFamilyKernel env family input weights
              second <- Local.runLinuxCpuWeightedFamilyKernel env family input weights
              case (first, second) of
                (Right a, Right b) ->
                  Local.linuxCpuWeightedKernelOutput a
                    @?= Local.linuxCpuWeightedKernelOutput b
                _ ->
                  assertBool
                    ( "linux-cpu weighted "
                        <> show family
                        <> " kernel must produce deterministic output"
                    )
                    False
      , testCase
          "linux-cpu weighted families match the pure reference within 1e-3 (Phase 1 rebalance)"
          $ do
            -- Numeric-correctness check (not just determinism): every weighted
            -- family's oneDNN output must agree with the pure-Haskell
            -- `familyReference` oracle within single-precision tolerance. A
            -- deterministically-wrong kernel passes the determinism cases above
            -- but fails here. Backend-vs-oracle, in-process — not a
            -- cross-substrate parity assertion.
            env <- buildEnv defaultGlobalFlags
            for_ weightedFamilyFixtures $ \(family, input, weights) -> do
              result <- Local.runLinuxCpuWeightedFamilyKernel env family input weights
              case result of
                Right run ->
                  assertWeightedMatchesReference
                    "linux-cpu"
                    family
                    input
                    weights
                    (Local.linuxCpuWeightedKernelOutput run)
                Left message ->
                  assertBool
                    ("linux-cpu weighted " <> show family <> " run failed: " <> show message)
                    False
      , testCase
          "linux-cuda weighted families match the pure reference within 1e-3 (Phase 1 rebalance)"
          $ do
            env <- buildEnv defaultGlobalFlags
            for_ weightedFamilyFixtures $ \(family, input, weights) -> do
              result <- Cuda.runCudaWeightedFamilyKernel env family input weights
              case result of
                Right run ->
                  assertWeightedMatchesReference
                    "linux-cuda"
                    family
                    input
                    weights
                    (Cuda.cudaWeightedKernelOutput run)
                Left message ->
                  assertBool
                    ("linux-cuda weighted " <> show family <> " run failed: " <> show message)
                    False
      , testCase
          "linux-cuda generated product-family CUDA source calls real cuBLAS/cuDNN entry points (Phase 29.1)"
          $ do
            let rendered family =
                  Text.concat
                    [ contents
                    | SourceFile _ contents <-
                        CudaCodegen.renderCudaFamilySource
                          family
                          (Cache.KernelSpec "phase-29:real-cuda-kernels")
                          Cache.Training
                          Cache.defaultTuningChoice
                    ]
                assertHas family needle =
                  assertBool
                    (show family <> " CUDA source should contain " <> Text.unpack needle)
                    (needle `Text.isInfixOf` rendered family)
                assertNotHas family needle =
                  assertBool
                    (show family <> " CUDA source should not contain " <> Text.unpack needle)
                    (not (needle `Text.isInfixOf` rendered family))
                assertNoScaffold family =
                  assertBool
                    (show family <> " CUDA source should not contain scaffold language")
                    (not ("scaffold" `Text.isInfixOf` Text.toLower (rendered family)))
            for_
              [Dense2D, Conv2DKernel, Conv3DKernel, BatchNormKernel, LayerNormKernel, MultiHeadAttentionKernel]
              assertNoScaffold
            assertHas Dense2D "jitml_cublas_sgemm_vector(out, input, n"
            assertHas Dense2D "cublasSgemm("
            assertHas MultiHeadAttentionKernel "jitml_cublas_sgemm_vector(q, input, n"
            assertHas MultiHeadAttentionKernel "jitml_cublas_sgemm_vector(out, qk, n"
            assertHas Conv2DKernel "jitml_cudnn_conv2d_forward(out, input, n"
            assertHas Conv2DKernel "cudnnConvolutionForward("
            assertHas
              Conv2DKernel
              "cudnnSetFilter4dDescriptor(filterDesc, CUDNN_DATA_FLOAT, CUDNN_TENSOR_NCHW, 1, 1, 3, 3)"
            assertHas Conv2DKernel "jitml_fill_filter_2d"
            assertHas Conv2DKernel "cudaMemcpy(conv2d-crop-output)"
            assertNotHas Conv2DKernel "jitml_fill_single_filter"
            assertHas Conv3DKernel "jitml_cudnn_conv3d_forward(out, input, n"
            assertHas Conv3DKernel "cudnnSetTensorNdDescriptor"
            assertHas Conv3DKernel "int filterDims[5] = {1, 1, 3, 3, 3};"
            assertHas Conv3DKernel "jitml_fill_filter_3d"
            assertHas Conv3DKernel "cudaMemcpy(conv3d-crop-output)"
            assertNotHas Conv3DKernel "jitml_fill_single_filter"
            assertHas BatchNormKernel "jitml_cudnn_batchnorm_forward(out, input, n"
            assertHas BatchNormKernel "cudnnBatchNormalizationForwardInference"
            assertHas LayerNormKernel "jitml_cudnn_layernorm_forward(out, input, n"
            assertHas LayerNormKernel "CUDNN_BATCHNORM_PER_ACTIVATION"
      , testCase
          "linux-cuda MLP source keeps persistent device weight buffers (Phase 29.4)"
          $ do
            let rendered =
                  Text.concat
                    [ contents
                    | SourceFile _ contents <- MlpCudaCodegen.renderMlpCudaSource
                    ]
                assertHas needle =
                  assertBool
                    ("MLP CUDA source should contain " <> Text.unpack needle)
                    (needle `Text.isInfixOf` rendered)
                assertNotHas needle =
                  assertBool
                    ("MLP CUDA source should not contain " <> Text.unpack needle)
                    (not (needle `Text.isInfixOf` rendered))
            assertHas "jitml_mlp_weight_cache[4]"
            assertHas "jitml_mlp_clear_weight_cache()"
            assertHas "jitml_mlp_check(status, \"cudaMalloc out\")"
            assertHas "jitml_mlp_weight_to_device(0, w1"
            assertHas "jitml_mlp_weight_to_device(1, b1"
            assertHas "jitml_mlp_weight_to_device(2, w2"
            assertHas "jitml_mlp_weight_to_device(3, b2"
            assertHas "jitml_mlp_batch_grad_w1_kernel"
            assertHas "jitml_mlp_batch_grad_w2_kernel"
            assertHas "std::size_t total = static_cast<std::size_t>(hidden) * static_cast<std::size_t>(inputs);"
            assertHas
              "std::size_t total = static_cast<std::size_t>(outputs) * static_cast<std::size_t>(hidden);"
            assertNotHas "jitml_mlp_free(d_w1)"
            assertNotHas "jitml_mlp_free(d_b1)"
            assertNotHas "jitml_mlp_free(d_w2)"
            assertNotHas "jitml_mlp_free(d_b2)"
      , testCase
          "apple-silicon weighted families match the pure reference within 1e-3 (Phase 1 rebalance)"
          $ do
            env <- buildEnv defaultGlobalFlags
            for_ weightedFamilyFixtures $ \(family, input, weights) -> do
              result <- Metal.runMetalWeightedFamilyKernel env family input weights
              case result of
                Right run ->
                  assertWeightedMatchesReference
                    "apple-silicon"
                    family
                    input
                    weights
                    (Metal.metalWeightedKernelOutput run)
                Left message ->
                  assertBool
                    ("apple-silicon weighted " <> show family <> " run failed: " <> show message)
                    False
      , testCase
          "apple-silicon generated Metal source uses real family kernels and no copy/1x1 scaffold (Phase 30.1)"
          $ do
            let rendered = MetalCodegen.renderMetalFamilySource
                assertHas family needle =
                  assertBool
                    (show family <> " Metal source should contain " <> Text.unpack needle)
                    (needle `Text.isInfixOf` rendered family)
                assertNotHas family needle =
                  assertBool
                    (show family <> " Metal source should not contain " <> Text.unpack needle)
                    (not (needle `Text.isInfixOf` rendered family))
            for_ kernelFamilies $ \family -> do
              assertNotHas family "Identity-class elementwise copy"
              assertNotHas family "conv1x1WeightedCompute"
            assertHas Conv2DKernel "3x3 windowed convolution"
            assertHas Conv2DKernel "jitml_ceil_sqrt"
            assertNotHas Conv2DKernel "wn <= 1u"
            assertHas Conv3DKernel "3x3x3 windowed convolution"
            assertHas Conv3DKernel "jitml_ceil_cuberoot"
            assertNotHas Conv3DKernel "wn <= 1u"
            assertHas MultiHeadAttentionKernel "qsum * ksum * wv"
            assertHas BatchNormKernel "sqrt(var + eps)"
            assertHas LayerNormKernel "sqrt(var + eps)"
      , testCase
          "apple-silicon Metal Conv2D/Conv3D multi-tap kernels match windowed references (Phase 30.1)"
          $ do
            env <- buildEnv defaultGlobalFlags
            let input2d = [1.0 .. 9.0]
                weights2d = [0, 1, 0, 1, 2, 1, 0, 1, 0]
                expected2d = metalWindowedConv2DReference input2d weights2d
                degenerate2d = fmap (* (weights2d !! 4)) input2d
            conv2d <- Metal.runMetalWeightedFamilyKernel env Conv2DKernel input2d weights2d
            case conv2d of
              Left message ->
                assertBool ("apple-silicon Conv2D Metal run failed: " <> show message) False
              Right run -> do
                assertListClose
                  "apple-silicon Conv2D windowed output"
                  expected2d
                  (Metal.metalWeightedKernelOutput run)
                assertBool
                  "Conv2D output must not collapse to the center-only 1x1 result"
                  (not (approxEqualFloatList 1.0e-3 degenerate2d (Metal.metalWeightedKernelOutput run)))
            let input3d = [1.0 .. 8.0]
                weights3d =
                  [ if i == 13 then 2.0 else 1.0
                  | i <- [0 :: Int .. 26]
                  ]
                expected3d = metalWindowedConv3DReference input3d weights3d
                degenerate3d = fmap (* (weights3d !! 13)) input3d
            conv3d <- Metal.runMetalWeightedFamilyKernel env Conv3DKernel input3d weights3d
            case conv3d of
              Left message ->
                assertBool ("apple-silicon Conv3D Metal run failed: " <> show message) False
              Right run -> do
                assertListClose
                  "apple-silicon Conv3D windowed output"
                  expected3d
                  (Metal.metalWeightedKernelOutput run)
                assertBool
                  "Conv3D output must not collapse to the center-only 1x1 result"
                  (not (approxEqualFloatList 1.0e-3 degenerate3d (Metal.metalWeightedKernelOutput run)))
      , testCase
          "apple-silicon total LayerGraph lowering runs on Metal and matches the pure oracle (Phase 270)"
          $ do
            env <- buildEnv defaultGlobalFlags
            graph <- either (assertFailure . Text.unpack) pure layerGraphDeviceFixture
            let input = VU.fromList [0.15, -0.25, 0.35, -0.45]
                target = VU.fromList [-0.05, 0.10, -0.15, 0.20]
            (_tape, reference) <-
              either
                (assertFailure . Text.unpack)
                pure
                (LayerGraph.layerGraphSquaredErrorGradient graph input target)
            run <-
              LayerGraphDevice.layerGraphSquaredErrorGradientDevice
                Substrate.AppleSilicon
                env
                graph
                input
                target
                >>= expectRight "Metal LayerGraph gradient failed"
            assertLayerGraphGradientClose
              3.0e-3
              (LayerGraphDevice.layerGraphDeviceGradient run)
              reference
            let evidence = LayerGraphDevice.layerGraphDeviceEvidence run
            length evidence @?= length deviceSupportedLayerKinds
            assertBool
              "every typed operator reports fixed-bridge Metal evidence"
              ( all
                  ( \entry ->
                      LayerGraphDevice.layerEvidenceBackend entry
                        == "apple-metal-fixed-bridge"
                        && "metal-"
                          `Text.isPrefixOf` LayerGraphDevice.layerEvidenceForwardPrimitive entry
                  )
                  evidence
              )
      , testCase
          "apple-silicon production LayerGraph callbacks use staged element-parallel Metal opcodes (Phase 271)"
          $ do
            let source = MetalLayerTraining.metalLayerTrainingProgram
                assertHas needle =
                  assertBool
                    ("Metal layer-training source should contain " <> Text.unpack needle)
                    (needle `Text.isInfixOf` source)
            for_
              [ "case 20: jitml_dense_forward_element"
              , "case 21: jitml_dense_backward_data_element"
              , "case 22: jitml_dense_backward_weights_element"
              , "case 23: jitml_conv2d_forward_element"
              , "case 24: jitml_conv2d_backward_data_element"
              , "case 25: jitml_conv2d_backward_weights_element"
              , "case 26: jitml_conv3d_forward_element"
              , "case 27: jitml_conv3d_backward_data_element"
              , "case 28: jitml_conv3d_backward_weights_element"
              , "case 31: jitml_norm_batch_sample"
              ]
              assertHas
            assertBool
              "production stages must not restore the global single-thread return"
              (not ("if (gid != 0u) { return; }" `Text.isInfixOf` source))
      , testCase
          "apple-silicon batched LayerGraph conv/block/norm gradient matches the summed oracle (Phase 271)"
          $ do
            env <- buildEnv defaultGlobalFlags
            graph <- either (assertFailure . Text.unpack) pure layerGraphDeviceFixture
            let batch =
                  [ (VU.fromList [0.15, -0.25, 0.35, -0.45], VU.fromList [-0.05, 0.10, -0.15, 0.20])
                  , (VU.fromList [-0.20, 0.30, -0.10, 0.05], VU.fromList [0.10, -0.05, 0.20, -0.10])
                  , (VU.fromList [0.40, -0.10, 0.20, -0.30], VU.fromList [-0.20, 0.15, -0.05, 0.10])
                  ]
            reference <-
              either (assertFailure . Text.unpack) pure $ do
                gradients <-
                  traverse
                    (\(input, target) -> snd <$> LayerGraph.layerGraphSquaredErrorGradient graph input target)
                    batch
                case gradients of
                  [] -> Left "empty batch"
                  firstGradient : remaining ->
                    Right (foldl addLayerGraphGradient firstGradient remaining)
            run <-
              LayerGraphDevice.layerGraphSquaredErrorGradientBatchDevice
                Substrate.AppleSilicon
                env
                graph
                batch
                >>= expectRight "batched Metal LayerGraph gradient failed"
            assertLayerGraphGradientClose
              5.0e-3
              (LayerGraphDevice.layerGraphDeviceGradient run)
              reference
            length (LayerGraphDevice.layerGraphDeviceEvidence run)
              @?= length deviceSupportedLayerKinds
      , testCase
          "apple-silicon Metal runtime absence fails before product-row evidence is accepted (Phase 30.2)"
          $ do
            env <- buildEnv defaultGlobalFlags
            let unavailable =
                  MetalRuntime.MetalRuntimeProbe
                    { MetalRuntime.metalRuntimeSwiftVersion = Nothing
                    , MetalRuntime.metalRuntimeMetalCompilerPath = Nothing
                    , MetalRuntime.metalRuntimeSwiftCompilerPath = Nothing
                    , MetalRuntime.metalRuntimeDeviceVisible = False
                    , MetalRuntime.metalRuntimeProbeLog = ["unit-test unavailable runtime"]
                    }
            plain <-
              Metal.runMetalFamilyKernelWithProbe
                (pure unavailable)
                env
                Identity
                [1.0]
            plain @?= Left "apple-silicon Metal device not visible: device_visible=no"
            weighted <-
              Metal.runMetalWeightedFamilyKernelWithProbe
                (pure unavailable)
                env
                Dense2D
                [1.0]
                [1.0]
            weighted @?= Left "apple-silicon Metal device not visible: device_visible=no"
      , testCase
          "linux-cpu MLP forward kernel matches the pure-Haskell network (Phase 2 rebalance)"
          $ do
            -- Phase 2 parity: the oneDNN-lane MLP forward kernel
            -- (JitML.Codegen.MlpOneDnn) must reproduce the pure-Haskell
            -- forward pass within single precision — the same depth the
            -- linux-cuda lane already has. CPU runs float32 vs the Double
            -- reference, so agreement is close, not bit-equal (run-to-run
            -- bit-equality is the determinism case below).
            env <- buildEnv defaultGlobalFlags
            let shape = MlpShape {mlpInputs = 4, mlpHidden = 6, mlpOutputs = 3}
                params = mlpInit shape 5
                input = VU.fromList [0.5, -0.25, 1.0, -0.75]
                refForward = mlpForward params input
            result <- mlpForwardOneDnn env params input
            case result of
              Left message ->
                assertBool ("MLP forward oneDNN run failed: " <> Text.unpack message) False
              Right fwd -> do
                assertBool
                  "oneDNN hidden_pre within tolerance of reference"
                  (approxEqualVec 1.0e-3 (forwardHiddenPre fwd) (forwardHiddenPre refForward))
                assertBool
                  "oneDNN hidden_act within tolerance of reference"
                  (approxEqualVec 1.0e-3 (forwardHiddenAct fwd) (forwardHiddenAct refForward))
                assertBool
                  ( "oneDNN output within tolerance of reference: got="
                      <> show (VU.toList (forwardOutput fwd))
                      <> " ref="
                      <> show (VU.toList (forwardOutput refForward))
                  )
                  (approxEqualVec 1.0e-3 (forwardOutput fwd) (forwardOutput refForward))
      , testCase
          "linux-cpu MLP backward kernel matches the pure-Haskell gradient (Phase 2 rebalance)"
          $ do
            env <- buildEnv defaultGlobalFlags
            let shape = MlpShape {mlpInputs = 4, mlpHidden = 6, mlpOutputs = 3}
                params = mlpInit shape 5
                input = VU.fromList [0.5, -0.25, 1.0, -0.75]
                refForward = mlpForward params input
                dLdy = VU.fromList [0.2, -0.4, 0.6]
                refGrad = mlpBackward params refForward dLdy
            result <- mlpBackwardOneDnn env params refForward dLdy
            case result of
              Left message ->
                assertBool ("MLP backward oneDNN run failed: " <> Text.unpack message) False
              Right grad -> do
                assertBool
                  "oneDNN gradW1 within tolerance of reference"
                  (approxEqualVec 1.0e-3 (gradW1 grad) (gradW1 refGrad))
                assertBool
                  "oneDNN gradB1 within tolerance of reference"
                  (approxEqualVec 1.0e-3 (gradB1 grad) (gradB1 refGrad))
                assertBool
                  "oneDNN gradW2 within tolerance of reference"
                  (approxEqualVec 1.0e-3 (gradW2 grad) (gradW2 refGrad))
                assertBool
                  "oneDNN gradB2 within tolerance of reference"
                  (approxEqualVec 1.0e-3 (gradB2 grad) (gradB2 refGrad))
      , testCase
          "linux-cpu LayerGraph oneDNN training kernels match the pure oracle and record device evidence (Sprint 23.2)"
          $ do
            env <- buildEnv defaultGlobalFlags
            graph <- either (assertFailure . Text.unpack) pure layerGraphDeviceFixture
            let input = VU.fromList [0.15, -0.25, 0.35, -0.45]
                target = VU.fromList [-0.05, 0.10, -0.15, 0.20]
            (_pureTape, pureGradient) <-
              either
                (assertFailure . Text.unpack)
                pure
                (LayerGraph.layerGraphSquaredErrorGradient graph input target)
            run <-
              LayerGraphDevice.layerGraphSquaredErrorGradientDevice Substrate.LinuxCPU env graph input target
                >>= expectRight "LayerGraph oneDNN training run failed"
            assertLayerGraphGradientClose
              1.0e-3
              (LayerGraphDevice.layerGraphDeviceGradient run)
              pureGradient
            let evidence = LayerGraphDevice.layerGraphDeviceEvidence run
                -- Phase 241: the lowering is total, so every node executes a
                -- device kernel and every node reports evidence — including the
                -- parameterless ones, whose input gradient now comes back from
                -- the device rather than from the host oracle.
                expectedEvidence = length deviceSupportedLayerKinds
            length evidence @?= expectedEvidence
            assertBool
              "all LayerGraph device evidence entries report the oneDNN backend"
              ( all
                  ((== "linux-cpu-onednn") . LayerGraphDevice.layerEvidenceBackend)
                  evidence
              )
            assertBool
              "Conv2D node executed oneDNN convolution_backward_data"
              ( any
                  ( (== "onednn_convolution_backward_data_2d")
                      . LayerGraphDevice.layerEvidenceBackwardDataPrimitive
                  )
                  evidence
              )
            assertBool
              "non-convolution nodes executed oneDNN matmul backward weights"
              ( any
                  ( (== "onednn_matmul_backward_weights")
                      . LayerGraphDevice.layerEvidenceBackwardWeightsPrimitive
                  )
                  evidence
              )
            -- Phase 241: the parameterless operators are executed, not skipped.
            -- Pooling routes its output gradient back through the oneDNN
            -- pooling primitive, and identity/dropout run the scale kernel; both
            -- report the primitive the artifact says it ran.
            assertBool
              "pooling nodes executed the oneDNN pooling primitive"
              ( any
                  ( (== "onednn_pooling_backward_data")
                      . LayerGraphDevice.layerEvidenceBackwardDataPrimitive
                  )
                  evidence
              )
            assertBool
              "identity/dropout nodes executed the device scale kernel"
              ( any
                  ( (== "onednn_scale_backward_data")
                      . LayerGraphDevice.layerEvidenceBackwardDataPrimitive
                  )
                  evidence
              )
      , testCase
          "linux-cpu real 3-D convolution executes its own oneDNN device kernel (Phase 241)"
          $ do
            -- Before Phase 241 this graph failed closed: `runDeviceSpatialConv`
            -- accepted 2-D geometry only, so the one operator with three spatial
            -- axes had no device lowering at all. It now runs the ncdhw/oidhw
            -- convolution triple, and the gradient it returns is checked against
            -- the pure oracle rather than against itself.
            env <- buildEnv defaultGlobalFlags
            graph <- either (assertFailure . Text.unpack) pure layerGraphConv3DFixture
            let input = VU.fromList [0.15, -0.25, 0.35, -0.45]
                target = VU.fromList [-0.05, 0.10, -0.15, 0.20]
            (_pureTape, pureGradient) <-
              either
                (assertFailure . Text.unpack)
                pure
                (LayerGraph.layerGraphSquaredErrorGradient graph input target)
            run <-
              LayerGraphDevice.layerGraphSquaredErrorGradientDevice Substrate.LinuxCPU env graph input target
                >>= expectRight "3-D convolution oneDNN training run failed"
            assertLayerGraphGradientClose
              1.0e-3
              (LayerGraphDevice.layerGraphDeviceGradient run)
              pureGradient
            let evidence = LayerGraphDevice.layerGraphDeviceEvidence run
            assertBool
              "the 3-D convolution node reports the 3-D oneDNN convolution primitives"
              ( any
                  ( \entry ->
                      LayerGraphDevice.layerEvidenceForwardPrimitive entry
                        == "onednn_convolution_forward_training_3d"
                        && LayerGraphDevice.layerEvidenceBackwardDataPrimitive entry
                          == "onednn_convolution_backward_data_3d"
                        && LayerGraphDevice.layerEvidenceBackwardWeightsPrimitive entry
                          == "onednn_convolution_backward_weights_3d"
                  )
                  evidence
              )
      , testCase
          "linux-cpu batched LayerGraph oneDNN gradient matches the per-example summed oracle (Phase 234)"
          $ do
            env <- buildEnv defaultGlobalFlags
            graph <- either (assertFailure . Text.unpack) pure layerGraphDeviceFixture
            let batch =
                  [ (VU.fromList [0.15, -0.25, 0.35, -0.45], VU.fromList [-0.05, 0.10, -0.15, 0.20])
                  , (VU.fromList [-0.20, 0.30, -0.10, 0.05], VU.fromList [0.10, -0.05, 0.20, -0.10])
                  , (VU.fromList [0.40, -0.10, 0.20, -0.30], VU.fromList [-0.20, 0.15, -0.05, 0.10])
                  ]
            refGrad <-
              either (assertFailure . Text.unpack) pure $ do
                grads <-
                  traverse
                    (\(i, t) -> snd <$> LayerGraph.layerGraphSquaredErrorGradient graph i t)
                    batch
                case grads of
                  [] -> Left "empty batch"
                  (g : gs) -> Right (foldl addLayerGraphGradient g gs)
            run <-
              LayerGraphDevice.layerGraphSquaredErrorGradientBatchDevice Substrate.LinuxCPU env graph batch
                >>= expectRight "batched LayerGraph oneDNN run failed"
            -- (a) one batched device call per layer over N=3 reproduces the
            -- per-example summed oracle within float32 tolerance.
            assertLayerGraphGradientClose
              1.0e-3
              (LayerGraphDevice.layerGraphDeviceGradient run)
              refGrad
            -- (b) evidence is one entry per parameterized node, NOT per example,
            -- proving a single batched device round-trip per layer.
            let evidence = LayerGraphDevice.layerGraphDeviceEvidence run
            length evidence @?= length deviceSupportedLayerKinds
            assertBool
              "batched LayerGraph device evidence reports the oneDNN backend"
              ( all
                  ((== "linux-cpu-onednn") . LayerGraphDevice.layerEvidenceBackend)
                  evidence
              )
      , testCase
          "linux-cpu LayerGraph classification training reduces cross-entropy loss (Sprint 235.1)"
          $ do
            env <- buildEnv defaultGlobalFlags
            node <-
              either
                (assertFailure . Text.unpack)
                pure
                ( LayerGraph.mkAffineLayer
                    "toy-dense"
                    2
                    2
                    LayerGraph.LinearActivation
                    LayerGraph.TrainingMode
                    (LayerGraph.deterministicParameters 3 2 2)
                )
            let graph0 =
                  LayerGraph.LayerGraph
                    { LayerGraph.layerGraphName = "toy-classifier"
                    , LayerGraph.layerGraphInputShape = LayerGraph.TensorShape [2]
                    , LayerGraph.layerGraphOutputShape = LayerGraph.TensorShape [2]
                    , LayerGraph.layerGraphNodes = [node]
                    }
                dataset =
                  [ (VU.fromList [1.0, 0.0], 0)
                  , (VU.fromList [0.9, 0.1], 0)
                  , (VU.fromList [0.0, 1.0], 1)
                  , (VU.fromList [0.1, 0.9], 1)
                  ]
                totalLoss g =
                  fmap
                    sum
                    (traverse (uncurry (LayerGraph.layerGraphCrossEntropyLoss g)) dataset)
            loss0 <- either (assertFailure . Text.unpack) pure (totalLoss graph0)
            trained <-
              LayerGraphDevice.trainLayerGraphClassifierDevice Substrate.LinuxCPU env 2 50 2 0.1 graph0 dataset
                >>= expectRight "LayerGraph classification training failed"
            loss1 <- either (assertFailure . Text.unpack) pure (totalLoss trained)
            assertBool
              ( "training must reduce cross-entropy loss: before="
                  <> show loss0
                  <> " after="
                  <> show loss1
              )
              (loss1 < loss0)
      , testCase
          "linux-cpu Phase 241 oneDNN spatial Conv2D device kernel matches the pure oracle"
          $ do
            env <- buildEnv defaultGlobalFlags
            -- 2->3 channels, 4x4 input, 3x3 kernel, stride 1, pad 1 -> 4x4 out.
            let convSpec = LayerGraph.ConvSpec 2 3 [4, 4] [3, 3] [1, 1] [1, 1]
                params = LayerGraph.deterministicOpParameters 91 (LayerGraph.ConvOp convSpec)
                input = VU.generate 32 (\i -> sin (0.3 * fromIntegral i))
                dY = VU.generate 48 (\i -> cos (0.2 * fromIntegral (i + 1)))
            convNode <-
              either (assertFailure . Text.unpack) pure $
                LayerGraph.mkConvLayer
                  "conv-spatial"
                  convSpec
                  LayerGraph.LinearActivation
                  LayerGraph.TrainingMode
                  params
            let graph =
                  LayerGraph.LayerGraph
                    { LayerGraph.layerGraphName = "conv-spatial"
                    , LayerGraph.layerGraphInputShape = LayerGraph.TensorShape [2, 4, 4]
                    , LayerGraph.layerGraphOutputShape = LayerGraph.TensorShape [3, 4, 4]
                    , LayerGraph.layerGraphNodes = [convNode]
                    }
            -- Pure oracle: linear activation => tape output is the raw conv, and
            -- d_pre == dY, so backwardLayerGraph yields the conv gradients.
            tape <-
              either (assertFailure . Text.unpack) pure (LayerGraph.runLayerGraph graph input)
            grad <-
              either (assertFailure . Text.unpack) pure (LayerGraph.backwardLayerGraph graph tape dY)
            let pureOut = LayerGraph.layerTapeOutput tape
                pureDx = LayerGraph.layerGraphInputGradient grad
            (pureDw, pureDb) <-
              case LayerGraph.layerGraphLayerGradients grad of
                [lg]
                  | Just pg <- LayerGraph.layerGradientParameters lg ->
                      pure (LayerGraph.layerGradWeights pg, LayerGraph.layerGradBias pg)
                _ -> assertFailure "expected exactly one parameterized conv gradient"
            deviceResult <-
              LayerGraphDevice.withCompiledLayerGraphDevice Substrate.LinuxCPU env $ \functions _ _ _ ->
                LayerGraphDevice.runDeviceSpatialConv functions convSpec params input dY
            (devOut, devDx, devDw, devDb) <-
              either (assertFailure . Text.unpack) pure deviceResult
            let close label a b =
                  assertBool
                    (label <> ": device/oracle mismatch\n device=" <> show a <> "\n oracle=" <> show b)
                    ( VU.length a == VU.length b
                        && VU.and (VU.zipWith (\x y -> abs (x - y) <= 1.0e-3) a b)
                    )
            close "conv forward output" devOut pureOut
            close "conv input gradient" devDx pureDx
            close "conv weight gradient" devDw pureDw
            close "conv bias gradient" devDb pureDb
            -- Phase 242: strided downsampling stem (stride 2) — the compact literal
            -- ResNet/LeNet stems use a stride>1 conv, so validate the device kernel
            -- against the pure oracle at stride 2 (3->4 ch, 8x8 in -> 4x4 out).
            let stridedSpec = LayerGraph.ConvSpec 3 4 [8, 8] [3, 3] [2, 2] [1, 1]
                stridedParams = LayerGraph.deterministicOpParameters 92 (LayerGraph.ConvOp stridedSpec)
                stridedInput = VU.generate 192 (\i -> sin (0.21 * fromIntegral i))
                stridedDy = VU.generate 64 (\i -> cos (0.17 * fromIntegral (i + 1)))
            stridedNode <-
              either (assertFailure . Text.unpack) pure $
                LayerGraph.mkConvLayer
                  "conv-strided"
                  stridedSpec
                  LayerGraph.LinearActivation
                  LayerGraph.TrainingMode
                  stridedParams
            let stridedGraph =
                  LayerGraph.LayerGraph
                    { LayerGraph.layerGraphName = "conv-strided"
                    , LayerGraph.layerGraphInputShape = LayerGraph.TensorShape [3, 8, 8]
                    , LayerGraph.layerGraphOutputShape = LayerGraph.TensorShape [4, 4, 4]
                    , LayerGraph.layerGraphNodes = [stridedNode]
                    }
            stridedTape <-
              either (assertFailure . Text.unpack) pure (LayerGraph.runLayerGraph stridedGraph stridedInput)
            stridedGrad <-
              either
                (assertFailure . Text.unpack)
                pure
                (LayerGraph.backwardLayerGraph stridedGraph stridedTape stridedDy)
            (stridedPureDw, stridedPureDb) <-
              case LayerGraph.layerGraphLayerGradients stridedGrad of
                [lg]
                  | Just pg <- LayerGraph.layerGradientParameters lg ->
                      pure (LayerGraph.layerGradWeights pg, LayerGraph.layerGradBias pg)
                _ -> assertFailure "expected exactly one parameterized strided-conv gradient"
            stridedDeviceResult <-
              LayerGraphDevice.withCompiledLayerGraphDevice Substrate.LinuxCPU env $ \functions _ _ _ ->
                LayerGraphDevice.runDeviceSpatialConv functions stridedSpec stridedParams stridedInput stridedDy
            (stridedDevOut, stridedDevDx, stridedDevDw, stridedDevDb) <-
              either (assertFailure . Text.unpack) pure stridedDeviceResult
            close "strided conv forward output" stridedDevOut (LayerGraph.layerTapeOutput stridedTape)
            close "strided conv input gradient" stridedDevDx (LayerGraph.layerGraphInputGradient stridedGrad)
            close "strided conv weight gradient" stridedDevDw stridedPureDw
            close "strided conv bias gradient" stridedDevDb stridedPureDb
      , testCase
          "linux-cpu Phase 241 oneDNN Norm (LayerNorm) device kernel matches the pure oracle"
          $ do
            env <- buildEnv defaultGlobalFlags
            let normSpec = LayerGraph.NormSpec LayerGraph.NormLayerWise 4 1 1.0e-5
                gamma = VU.fromList [1.3, 0.7, 1.1, 0.9]
                beta = VU.fromList [0.05, -0.1, 0.2, -0.15]
                params = LayerGraph.LayerParameters gamma beta
                input = VU.fromList [0.4, -0.9, 1.3, -0.2]
                dY = VU.fromList [0.5, -0.3, 0.7, 0.1]
            node <-
              either (assertFailure . Text.unpack) pure $
                LayerGraph.mkNormLayer "norm-layer" normSpec LayerGraph.TrainingMode params
            assertDeviceOpOracle env "layernorm" node input dY
      , testCase
          "linux-cpu Phase 241 oneDNN Norm (GroupNorm) device kernel matches the pure oracle"
          $ do
            env <- buildEnv defaultGlobalFlags
            let normSpec = LayerGraph.NormSpec (LayerGraph.NormGroup 2) 4 2 1.0e-5
                gamma = VU.fromList [1.2, 0.8, 1.05, 0.95]
                beta = VU.fromList [0.1, -0.05, 0.15, -0.2]
                params = LayerGraph.LayerParameters gamma beta
                input = VU.generate 8 (\i -> sin (0.35 * fromIntegral i + 0.2))
                dY = VU.generate 8 (\i -> cos (0.25 * fromIntegral (i + 1)))
            node <-
              either (assertFailure . Text.unpack) pure $
                LayerGraph.mkNormLayer "groupnorm" normSpec LayerGraph.TrainingMode params
            assertDeviceOpOracle env "groupnorm" node input dY
      , testCase
          "linux-cpu Phase 241 oneDNN GeGLU device kernel matches the pure oracle"
          $ do
            env <- buildEnv defaultGlobalFlags
            let ggSpec = LayerGraph.GeGLUSpec 3 4 3
                params = LayerGraph.deterministicOpParameters 23 (LayerGraph.GeGLUOp ggSpec)
                input = VU.generate 3 (\i -> sin (0.4 * fromIntegral i + 0.1))
                dY = VU.generate 3 (\i -> cos (0.3 * fromIntegral (i + 1)))
            node <-
              either (assertFailure . Text.unpack) pure $
                LayerGraph.mkGeGLULayer "geglu" ggSpec LayerGraph.TrainingMode params
            assertDeviceOpOracle env "geglu" node input dY
      , testCase
          "linux-cpu Phase 241 oneDNN multi-head Attention device kernel matches the pure oracle"
          $ do
            env <- buildEnv defaultGlobalFlags
            let input = VU.generate 8 (\i -> sin (0.2 * fromIntegral (i + 1)))
                dY = VU.generate 8 (\i -> cos (0.15 * fromIntegral i))
                mkNode causal =
                  either (assertFailure . Text.unpack) pure $
                    LayerGraph.mkAttentionLayer
                      "attn"
                      (LayerGraph.AttentionSpec 2 4 2 causal)
                      LayerGraph.TrainingMode
                      ( LayerGraph.deterministicOpParameters
                          31
                          (LayerGraph.AttentionOp (LayerGraph.AttentionSpec 2 4 2 causal))
                      )
            nodeFull <- mkNode False
            assertDeviceOpOracle env "attention-full" nodeFull input dY
            nodeCausal <- mkNode True
            assertDeviceOpOracle env "attention-causal" nodeCausal input dY
      , testCase
          "linux-cpu Phase 241 oneDNN Patch-embed device kernel matches the pure oracle"
          $ do
            env <- buildEnv defaultGlobalFlags
            let patchSpec = LayerGraph.PatchSpec 1 4 4 2 2 3
                params = LayerGraph.deterministicOpParameters 41 (LayerGraph.PatchOp patchSpec)
                input = VU.generate 16 (\i -> sin (0.25 * fromIntegral i))
                dY = VU.generate 12 (\i -> cos (0.2 * fromIntegral (i + 1)))
            node <-
              either (assertFailure . Text.unpack) pure $
                LayerGraph.mkPatchEmbedLayer "patch" patchSpec LayerGraph.TrainingMode params
            assertDeviceOpOracle env "patch" node input dY
      , testCase
          "linux-cpu Phase 241 oneDNN Residual device kernel matches the pure oracle"
          $ do
            env <- buildEnv defaultGlobalFlags
            let inner = LayerGraph.AffineSpec 4 4
                residOp = LayerGraph.ResidualOp inner LayerGraph.IdentityShortcut 0.5 LayerGraph.ReluActivation
                residParams = LayerGraph.deterministicOpParameters 51 residOp
                inputR = VU.fromList [0.6, -0.4, 0.9, -0.2]
                dYR = VU.fromList [0.3, 0.5, -0.2, 0.4]
            residNode <-
              either (assertFailure . Text.unpack) pure $
                LayerGraph.mkResidualNode
                  "resid-id"
                  inner
                  LayerGraph.IdentityShortcut
                  0.5
                  LayerGraph.ReluActivation
                  LayerGraph.LinearActivation
                  LayerGraph.TrainingMode
                  residParams
            assertDeviceOpOracle env "residual-identity" residNode inputR dYR
            let innerP = LayerGraph.AffineSpec 3 4
                projSpec = LayerGraph.AffineSpec 3 4
                residOpP =
                  LayerGraph.ResidualOp innerP (LayerGraph.ProjectionShortcut projSpec) 0.5 LayerGraph.TanhActivation
                residParamsP = LayerGraph.deterministicOpParameters 53 residOpP
                inputRP = VU.fromList [0.5, -0.7, 0.3]
                dYRP = VU.fromList [0.2, -0.4, 0.6, 0.1]
            residNodeP <-
              either (assertFailure . Text.unpack) pure $
                LayerGraph.mkResidualNode
                  "resid-proj"
                  innerP
                  (LayerGraph.ProjectionShortcut projSpec)
                  0.5
                  LayerGraph.TanhActivation
                  LayerGraph.LinearActivation
                  LayerGraph.TrainingMode
                  residParamsP
            assertDeviceOpOracle env "residual-projection" residNodeP inputRP dYRP
      , testCase
          "linux-cpu Phase 241/242 oneDNN BlockOp device backward matches the pure blockBackward oracle"
          $ do
            env <- buildEnv defaultGlobalFlags
            -- (1) BasicBlock, identity shortcut: two affine->LayerNorm->ReLU stages
            -- with a final ReLU, composed on device from the dense-affine + norm
            -- sub-kernels. dW/dB come back in the block's packed segment order.
            let normSpec4 = LayerGraph.NormSpec LayerGraph.NormLayerWise 4 1 1.0e-5
                basicStage = LayerGraph.BlockStage (LayerGraph.AffineSpec 4 4) (Just normSpec4) LayerGraph.ReluActivation
                basicSpec =
                  LayerGraph.BlockSpec
                    [basicStage, basicStage]
                    LayerGraph.IdentityShortcut
                    0.5
                    LayerGraph.ReluActivation
                basicParams = LayerGraph.deterministicOpParameters 61 (LayerGraph.BlockOp basicSpec)
                inputB = VU.fromList [0.6, -0.4, 0.9, -0.2]
                dYB = VU.fromList [0.3, 0.5, -0.2, 0.4]
            basicNode <-
              either (assertFailure . Text.unpack) pure $
                LayerGraph.mkBasicBlock "block-basic-id" basicSpec LayerGraph.TrainingMode basicParams
            assertDeviceBlockOracle env "block-basic-id" basicNode inputB dYB
            -- (2) BasicBlock, projection shortcut (3 -> 4): the shortcut runs the
            -- final-activation gradient (not the scaled branch gradient) through a
            -- device dense affine, exercising the projection segment order.
            let normStage0 = LayerGraph.NormSpec LayerGraph.NormLayerWise 4 1 1.0e-5
                projStage0 = LayerGraph.BlockStage (LayerGraph.AffineSpec 3 4) (Just normStage0) LayerGraph.TanhActivation
                projStage1 = LayerGraph.BlockStage (LayerGraph.AffineSpec 4 4) (Just normStage0) LayerGraph.TanhActivation
                projSpec =
                  LayerGraph.BlockSpec
                    [projStage0, projStage1]
                    (LayerGraph.ProjectionShortcut (LayerGraph.AffineSpec 3 4))
                    0.5
                    LayerGraph.LinearActivation
                projParams = LayerGraph.deterministicOpParameters 67 (LayerGraph.BlockOp projSpec)
                inputP = VU.fromList [0.5, -0.7, 0.3]
                dYP = VU.fromList [0.2, -0.4, 0.6, 0.1]
            projNode <-
              either (assertFailure . Text.unpack) pure $
                LayerGraph.mkBasicBlock "block-basic-proj" projSpec LayerGraph.TrainingMode projParams
            assertDeviceBlockOracle env "block-basic-proj" projNode inputP dYP
            -- (3) Bottleneck, identity shortcut: three stages (4->2->2->4) with a
            -- reduced middle width, exercising the distinct bottleneck topology.
            let normMid = LayerGraph.NormSpec LayerGraph.NormLayerWise 2 1 1.0e-5
                normOut = LayerGraph.NormSpec LayerGraph.NormLayerWise 4 1 1.0e-5
                bnStage0 = LayerGraph.BlockStage (LayerGraph.AffineSpec 4 2) (Just normMid) LayerGraph.ReluActivation
                bnStage1 = LayerGraph.BlockStage (LayerGraph.AffineSpec 2 2) (Just normMid) LayerGraph.ReluActivation
                bnStage2 = LayerGraph.BlockStage (LayerGraph.AffineSpec 2 4) (Just normOut) LayerGraph.ReluActivation
                bnSpec =
                  LayerGraph.BlockSpec
                    [bnStage0, bnStage1, bnStage2]
                    LayerGraph.IdentityShortcut
                    1.0
                    LayerGraph.LinearActivation
                bnParams = LayerGraph.deterministicOpParameters 83 (LayerGraph.BlockOp bnSpec)
                inputBn = VU.fromList [0.4, -0.9, 1.3, -0.2]
                dYBn = VU.fromList [0.5, -0.3, 0.7, 0.1]
            bottleneckNode <-
              either (assertFailure . Text.unpack) pure $
                LayerGraph.mkBottleneck "block-bottleneck-id" bnSpec LayerGraph.TrainingMode bnParams
            assertDeviceBlockOracle env "block-bottleneck-id" bottleneckNode inputBn dYBn
            -- (4) End-to-end: a BlockOp node in the trained graph reduces
            -- cross-entropy through the device training loop.
            let ceStage = LayerGraph.BlockStage (LayerGraph.AffineSpec 4 4) (Just normSpec4) LayerGraph.ReluActivation
                ceBlockSpec =
                  LayerGraph.BlockSpec
                    [ceStage, ceStage]
                    LayerGraph.IdentityShortcut
                    0.5
                    LayerGraph.LinearActivation
                ceBlockParams = LayerGraph.deterministicOpParameters 89 (LayerGraph.BlockOp ceBlockSpec)
                ceHeadParams = LayerGraph.deterministicParameters 97 4 2
            ceBlockNode <-
              either (assertFailure . Text.unpack) pure $
                LayerGraph.mkBasicBlock "ce-block" ceBlockSpec LayerGraph.TrainingMode ceBlockParams
            ceHeadNode <-
              either (assertFailure . Text.unpack) pure $
                LayerGraph.mkAffineLayer
                  "ce-head"
                  4
                  2
                  LayerGraph.LinearActivation
                  LayerGraph.TrainingMode
                  ceHeadParams
            let ceGraph =
                  LayerGraph.LayerGraph
                    { LayerGraph.layerGraphName = "block-classifier"
                    , LayerGraph.layerGraphInputShape = LayerGraph.TensorShape [4]
                    , LayerGraph.layerGraphOutputShape = LayerGraph.TensorShape [2]
                    , LayerGraph.layerGraphNodes = [ceBlockNode, ceHeadNode]
                    }
                ceDataset =
                  [ (VU.fromList [1.0, 0.5, -0.5, -1.0], 0)
                  , (VU.fromList [0.8, 0.6, -0.4, -0.9], 0)
                  , (VU.fromList [-1.0, -0.5, 0.5, 1.0], 1)
                  , (VU.fromList [-0.9, -0.4, 0.6, 0.8], 1)
                  ]
                totalLoss g =
                  fmap sum (traverse (uncurry (LayerGraph.layerGraphCrossEntropyLoss g)) ceDataset)
            -- (4a) batched device gradient matches the per-example summed oracle.
            refGrad <-
              either (assertFailure . Text.unpack) pure $ do
                grads <-
                  traverse
                    (\(i, l) -> snd <$> LayerGraph.layerGraphClassifierCrossEntropyGradient ceGraph 2 i l)
                    ceDataset
                case grads of
                  [] -> Left "empty batch"
                  (g : gs) -> Right (foldl addLayerGraphGradient g gs)
            run <-
              LayerGraphDevice.layerGraphCrossEntropyGradientBatchDevice
                Substrate.LinuxCPU
                env
                2
                ceGraph
                ceDataset
                >>= expectRight "block batched device gradient failed"
            assertLayerGraphGradientClose
              2.0e-3
              (LayerGraphDevice.layerGraphDeviceGradient run)
              refGrad
            -- (4b) training the block graph on device reduces cross-entropy.
            loss0 <- either (assertFailure . Text.unpack) pure (totalLoss ceGraph)
            trained <-
              LayerGraphDevice.trainLayerGraphClassifierDevice
                Substrate.LinuxCPU
                env
                2
                60
                2
                0.05
                ceGraph
                ceDataset
                >>= expectRight "block device training failed"
            loss1 <- either (assertFailure . Text.unpack) pure (totalLoss trained)
            assertBool
              ( "BlockOp device training must reduce cross-entropy: before="
                  <> show loss0
                  <> " after="
                  <> show loss1
              )
              (loss1 < loss0)
      , testCase
          "linux-cpu Phase 241 mixed correct-operator graph trains on device and matches the oracle"
          $ do
            env <- buildEnv defaultGlobalFlags
            let classes = 2
                normSpec = LayerGraph.NormSpec LayerGraph.NormLayerWise 4 1 1.0e-5
                normParams =
                  LayerGraph.LayerParameters
                    (VU.fromList [1.1, 0.9, 1.05, 0.95])
                    (VU.fromList [0.05, -0.05, 0.1, -0.1])
                ggSpec = LayerGraph.GeGLUSpec 4 6 4
                ggParams = LayerGraph.deterministicOpParameters 71 (LayerGraph.GeGLUOp ggSpec)
                headParams = LayerGraph.deterministicParameters 73 4 2
            normNode <-
              either (assertFailure . Text.unpack) pure $
                LayerGraph.mkNormLayer "mix-norm" normSpec LayerGraph.TrainingMode normParams
            ggNode <-
              either (assertFailure . Text.unpack) pure $
                LayerGraph.mkGeGLULayer "mix-geglu" ggSpec LayerGraph.TrainingMode ggParams
            headNode <-
              either (assertFailure . Text.unpack) pure $
                LayerGraph.mkAffineLayer
                  "mix-head"
                  4
                  2
                  LayerGraph.LinearActivation
                  LayerGraph.TrainingMode
                  headParams
            let graph =
                  LayerGraph.LayerGraph
                    { LayerGraph.layerGraphName = "mixed-correct-op"
                    , LayerGraph.layerGraphInputShape = LayerGraph.TensorShape [4]
                    , LayerGraph.layerGraphOutputShape = LayerGraph.TensorShape [2]
                    , LayerGraph.layerGraphNodes = [normNode, ggNode, headNode]
                    }
                dataset =
                  [ (VU.fromList [1.0, 0.5, -0.5, -1.0], 0)
                  , (VU.fromList [0.8, 0.6, -0.4, -0.9], 0)
                  , (VU.fromList [-1.0, -0.5, 0.5, 1.0], 1)
                  , (VU.fromList [-0.9, -0.4, 0.6, 0.8], 1)
                  ]
            -- (a) batched device gradient matches the per-example summed oracle.
            refGrad <-
              either (assertFailure . Text.unpack) pure $ do
                grads <-
                  traverse
                    (\(i, l) -> snd <$> LayerGraph.layerGraphClassifierCrossEntropyGradient graph classes i l)
                    dataset
                case grads of
                  [] -> Left "empty batch"
                  (g : gs) -> Right (foldl addLayerGraphGradient g gs)
            run <-
              LayerGraphDevice.layerGraphCrossEntropyGradientBatchDevice
                Substrate.LinuxCPU
                env
                classes
                graph
                dataset
                >>= expectRight "mixed-op batched device gradient failed"
            assertLayerGraphGradientClose
              1.0e-3
              (LayerGraphDevice.layerGraphDeviceGradient run)
              refGrad
            -- (b) training the mixed graph on device reduces cross-entropy.
            let totalLoss g =
                  fmap sum (traverse (uncurry (LayerGraph.layerGraphCrossEntropyLoss g)) dataset)
            loss0 <- either (assertFailure . Text.unpack) pure (totalLoss graph)
            trained <-
              LayerGraphDevice.trainLayerGraphClassifierDevice
                Substrate.LinuxCPU
                env
                classes
                40
                2
                0.05
                graph
                dataset
                >>= expectRight "mixed-op device training failed"
            loss1 <- either (assertFailure . Text.unpack) pure (totalLoss trained)
            assertBool
              ( "mixed correct-operator device training must reduce cross-entropy: before="
                  <> show loss0
                  <> " after="
                  <> show loss1
              )
              (loss1 < loss0)
      , testCase
          "linux-cpu MLP kernels are bit-deterministic across repeated runs (Phase 2 rebalance)"
          $ do
            env <- buildEnv defaultGlobalFlags
            let shape = MlpShape {mlpInputs = 4, mlpHidden = 6, mlpOutputs = 3}
                params = mlpInit shape 5
                input = VU.fromList [0.5, -0.25, 1.0, -0.75]
                dLdy = VU.fromList [0.2, -0.4, 0.6]
            first <- mlpForwardOneDnn env params input
            second <- mlpForwardOneDnn env params input
            case (first, second) of
              (Right a, Right b) -> do
                forwardOutput a @?= forwardOutput b
                forwardHiddenAct a @?= forwardHiddenAct b
                gradA <- mlpBackwardOneDnn env params a dLdy
                gradB <- mlpBackwardOneDnn env params b dLdy
                case (gradA, gradB) of
                  (Right ga, Right gb) -> do
                    gradW1 ga @?= gradW1 gb
                    gradW2 ga @?= gradW2 gb
                  _ -> assertBool "both MLP backward oneDNN runs succeed" False
              _ -> assertBool "both MLP forward oneDNN runs succeed" False
      , testCase
          "linux-cpu batched MLP gradient matches the pure summed gradient (Phase 2 rebalance)"
          $ do
            env <- buildEnv defaultGlobalFlags
            let shape = MlpShape {mlpInputs = 4, mlpHidden = 6, mlpOutputs = 3}
                params = mlpInit shape 5
                batch =
                  [ (VU.fromList [0.5, -0.25, 1.0, -0.75], VU.fromList [0.2, -0.4, 0.6])
                  , (VU.fromList [-0.1, 0.3, -0.5, 0.2], VU.fromList [-0.3, 0.5, 0.1])
                  , (VU.fromList [0.9, 0.1, -0.2, 0.4], VU.fromList [0.05, -0.15, 0.25])
                  ]
                perSample (i, dy) = mlpBackward params (mlpForward params i) dy
                sumGrad a b =
                  MlpGradient
                    { gradW1 = VU.zipWith (+) (gradW1 a) (gradW1 b)
                    , gradB1 = VU.zipWith (+) (gradB1 a) (gradB1 b)
                    , gradW2 = VU.zipWith (+) (gradW2 a) (gradW2 b)
                    , gradB2 = VU.zipWith (+) (gradB2 a) (gradB2 b)
                    }
                refGrad = foldl1 sumGrad (map perSample batch)
            first <- mlpBatchGradientOneDnn env params batch
            second <- mlpBatchGradientOneDnn env params batch
            case (first, second) of
              (Right g, Right g2) -> do
                assertBool
                  "batched oneDNN gradW1 within tolerance of the pure summed gradient"
                  (approxEqualVec 1.0e-3 (gradW1 g) (gradW1 refGrad))
                assertBool
                  "batched oneDNN gradB1 within tolerance"
                  (approxEqualVec 1.0e-3 (gradB1 g) (gradB1 refGrad))
                assertBool
                  "batched oneDNN gradW2 within tolerance"
                  (approxEqualVec 1.0e-3 (gradW2 g) (gradW2 refGrad))
                assertBool
                  "batched oneDNN gradB2 within tolerance"
                  (approxEqualVec 1.0e-3 (gradB2 g) (gradB2 refGrad))
                gradW1 g @?= gradW1 g2
                gradW2 g @?= gradW2 g2
              _ -> assertBool "both batched MLP gradient oneDNN runs succeed" False
      , testCase
          "linux-cpu batched MLP forward matches the pure per-sample forward (Phase 2 rebalance)"
          $ do
            env <- buildEnv defaultGlobalFlags
            let shape = MlpShape {mlpInputs = 4, mlpHidden = 6, mlpOutputs = 3}
                params = mlpInit shape 5
                inputs =
                  [ VU.fromList [0.5, -0.25, 1.0, -0.75]
                  , VU.fromList [-0.1, 0.3, -0.5, 0.2]
                  , VU.fromList [0.9, 0.1, -0.2, 0.4]
                  ]
                refOutputs = map (forwardOutput . mlpForward params) inputs
            first <- mlpForwardBatchOneDnn env params inputs
            second <- mlpForwardBatchOneDnn env params inputs
            case (first, second) of
              (Right outs, Right outs2) -> do
                assertBool
                  ("batched oneDNN forward returns " <> show (length inputs) <> " outputs")
                  (length outs == length inputs)
                assertBool
                  "each batched oneDNN forward output is within tolerance of the pure forward"
                  (and (zipWith (approxEqualVec 1.0e-3) outs refOutputs))
                outs @?= outs2
              _ -> assertBool "both batched MLP forward oneDNN runs succeed" False
      , testCase
          "linux-cpu batched MLP input-gradient matches the pure mlpInputGradient (Phase 2 rebalance)"
          $ do
            env <- buildEnv defaultGlobalFlags
            let shape = MlpShape {mlpInputs = 4, mlpHidden = 6, mlpOutputs = 3}
                params = mlpInit shape 5
                batch =
                  [ (VU.fromList [0.5, -0.25, 1.0, -0.75], VU.fromList [0.2, -0.4, 0.6])
                  , (VU.fromList [-0.1, 0.3, -0.5, 0.2], VU.fromList [-0.3, 0.5, 0.1])
                  , (VU.fromList [0.9, 0.1, -0.2, 0.4], VU.fromList [0.05, -0.15, 0.25])
                  ]
                refDx (i, dy) = mlpInputGradient params (mlpForward params i) dy
                refs = map refDx batch
            first <- mlpInputGradientBatchOneDnn env params batch
            second <- mlpInputGradientBatchOneDnn env params batch
            case (first, second) of
              (Right dxs, Right dxs2) -> do
                assertBool
                  ("batched oneDNN input-gradient returns " <> show (length batch) <> " vectors")
                  (length dxs == length batch)
                assertBool
                  "each batched oneDNN dL/dx is within tolerance of the pure mlpInputGradient"
                  (and (zipWith (approxEqualVec 1.0e-3) dxs refs))
                dxs @?= dxs2
              _ -> assertBool "both batched MLP input-gradient oneDNN runs succeed" False
      , testCase
          "linux-cuda LayerGraph training kernels match the pure oracle and record device evidence (Phase 264)"
          $ do
            -- The linux-cuda mirror of the linux-cpu oracle case above, over the
            -- same fixture graph and the same pure `backwardLayerGraph` oracle.
            -- Before Phase 264 this lane had no layer-graph kernel at all: it
            -- served the typed graph through the pure executor, which the
            -- hardware-native determinism contract forbids on the execution path.
            env <- buildEnv defaultGlobalFlags
            graph <- either (assertFailure . Text.unpack) pure layerGraphDeviceFixture
            let input = VU.fromList [0.15, -0.25, 0.35, -0.45]
                target = VU.fromList [-0.05, 0.10, -0.15, 0.20]
            (_pureTape, pureGradient) <-
              either
                (assertFailure . Text.unpack)
                pure
                (LayerGraph.layerGraphSquaredErrorGradient graph input target)
            run <-
              LayerGraphDevice.layerGraphSquaredErrorGradientDevice Substrate.LinuxCUDA env graph input target
                >>= expectRight "LayerGraph CUDA training run failed"
            assertLayerGraphGradientClose
              1.0e-3
              (LayerGraphDevice.layerGraphDeviceGradient run)
              pureGradient
            let evidence = LayerGraphDevice.layerGraphDeviceEvidence run
            length evidence @?= length deviceSupportedLayerKinds
            assertBool
              "all LayerGraph device evidence entries report the cuDNN backend"
              ( all
                  ((== "linux-cuda-cudnn") . LayerGraphDevice.layerEvidenceBackend)
                  evidence
              )
            assertBool
              "Conv2D node executed cuDNN convolution backward data"
              ( any
                  ( (== "cudnn_convolution_backward_data_2d")
                      . LayerGraphDevice.layerEvidenceBackwardDataPrimitive
                  )
                  evidence
              )
            assertBool
              "non-convolution nodes executed cuBLAS sgemm backward weights"
              ( any
                  ( (== "cublas_sgemm_backward_weights")
                      . LayerGraphDevice.layerEvidenceBackwardWeightsPrimitive
                  )
                  evidence
              )
            assertBool
              "pooling nodes executed the cuDNN pooling primitive"
              ( any
                  ( (== "cudnn_pooling_backward_data")
                      . LayerGraphDevice.layerEvidenceBackwardDataPrimitive
                  )
                  evidence
              )
            assertBool
              "identity/dropout nodes executed the CUDA scale kernel"
              ( any
                  ( (== "cuda_scale_backward_data")
                      . LayerGraphDevice.layerEvidenceBackwardDataPrimitive
                  )
                  evidence
              )
      , testCase
          "linux-cuda real 3-D convolution executes its own cuDNN device kernel (Phase 264)"
          $ do
            env <- buildEnv defaultGlobalFlags
            graph <- either (assertFailure . Text.unpack) pure layerGraphConv3DFixture
            let input = VU.fromList [0.15, -0.25, 0.35, -0.45]
                target = VU.fromList [-0.05, 0.10, -0.15, 0.20]
            (_pureTape, pureGradient) <-
              either
                (assertFailure . Text.unpack)
                pure
                (LayerGraph.layerGraphSquaredErrorGradient graph input target)
            run <-
              LayerGraphDevice.layerGraphSquaredErrorGradientDevice Substrate.LinuxCUDA env graph input target
                >>= expectRight "3-D convolution CUDA training run failed"
            assertLayerGraphGradientClose
              1.0e-3
              (LayerGraphDevice.layerGraphDeviceGradient run)
              pureGradient
            assertBool
              "the 3-D convolution node reports the cuDNN 3-D convolution primitive"
              ( any
                  ( (== "cudnn_convolution_forward_3d")
                      . LayerGraphDevice.layerEvidenceForwardPrimitive
                  )
                  (LayerGraphDevice.layerGraphDeviceEvidence run)
              )
      , testCase
          "linux-cuda LayerGraph classification training reduces cross-entropy loss (Phase 264)"
          $ do
            -- The linux-cuda mirror of the linux-cpu mixed-correct-op training
            -- case above: same graph, same dataset, same hyperparameters, so a
            -- lane that trains and a lane that does not are directly
            -- comparable.
            --
            -- It deliberately does NOT reuse `layerGraphDeviceFixture`. That
            -- fixture carries one node per declared kind, including a
            -- `PoolGlobal` that collapses the width-4 activation to a single
            -- value, so its output is uniform and its parameter gradient
            -- vanishes: both lanes leave the loss at exactly 4 * ln 4 =
            -- 5.545177444479562. Asserting "training reduces the loss" over it
            -- is unsatisfiable on any backend and would report a correct CUDA
            -- arm as broken. It is a gradient-versus-oracle fixture, and the
            -- case above uses it for exactly that.
            env <- buildEnv defaultGlobalFlags
            let classes = 2
                normSpec = LayerGraph.NormSpec LayerGraph.NormLayerWise 4 1 1.0e-5
                normParams =
                  LayerGraph.LayerParameters
                    (VU.fromList [1.1, 0.9, 1.05, 0.95])
                    (VU.fromList [0.05, -0.05, 0.1, -0.1])
                ggSpec = LayerGraph.GeGLUSpec 4 6 4
                ggParams = LayerGraph.deterministicOpParameters 71 (LayerGraph.GeGLUOp ggSpec)
                headParams = LayerGraph.deterministicParameters 73 4 2
            normNode <-
              either (assertFailure . Text.unpack) pure $
                LayerGraph.mkNormLayer "mix-norm" normSpec LayerGraph.TrainingMode normParams
            ggNode <-
              either (assertFailure . Text.unpack) pure $
                LayerGraph.mkGeGLULayer "mix-geglu" ggSpec LayerGraph.TrainingMode ggParams
            headNode <-
              either (assertFailure . Text.unpack) pure $
                LayerGraph.mkAffineLayer
                  "mix-head"
                  4
                  2
                  LayerGraph.LinearActivation
                  LayerGraph.TrainingMode
                  headParams
            let graph =
                  LayerGraph.LayerGraph
                    { LayerGraph.layerGraphName = "mixed-correct-op"
                    , LayerGraph.layerGraphInputShape = LayerGraph.TensorShape [4]
                    , LayerGraph.layerGraphOutputShape = LayerGraph.TensorShape [2]
                    , LayerGraph.layerGraphNodes = [normNode, ggNode, headNode]
                    }
                dataset =
                  [ (VU.fromList [1.0, 0.5, -0.5, -1.0], 0)
                  , (VU.fromList [0.8, 0.6, -0.4, -0.9], 0)
                  , (VU.fromList [-1.0, -0.5, 0.5, 1.0], 1)
                  , (VU.fromList [-0.9, -0.4, 0.6, 0.8], 1)
                  ]
                totalLoss g =
                  fmap sum (traverse (uncurry (LayerGraph.layerGraphCrossEntropyLoss g)) dataset)
            loss0 <- either (assertFailure . Text.unpack) pure (totalLoss graph)
            trained <-
              LayerGraphDevice.trainLayerGraphClassifierDevice
                Substrate.LinuxCUDA
                env
                classes
                40
                2
                0.05
                graph
                dataset
                >>= expectRight "CUDA layer-graph classifier training failed"
            loss1 <- either (assertFailure . Text.unpack) pure (totalLoss trained)
            assertBool
              ( "CUDA layer-graph training must reduce cross-entropy: before="
                  <> show loss0
                  <> " after="
                  <> show loss1
              )
              (loss1 < loss0)
      , testCase "linux-cuda generated kernel compiles and runs through nvcc + FFI (Sprint 7.4)" $ do
          -- Live CUDA validation: Sprint 7.4 closure. When the host
          -- has nvcc + libcublas + libcudnn visible and an NVIDIA GPU
          -- attached, compile the generated `kernel.cu` through nvcc,
          -- dlopen the resulting `.so`, launch the identity kernel,
          -- and verify the copied-back output matches the input
          -- bit-equally. On hosts without a positive CUDA runtime
          -- probe the selected lane fails by design.
          env <- buildEnv defaultGlobalFlags
          let payload = [1.25, -2.5, 0.0, 3.5]
          result <- runCudaFamilyKernel env Identity payload
          case result of
            Left message ->
              assertBool ("linux-cuda Identity JIT run failed: " <> show message) False
            Right kernelRun -> do
              cudaKernelReportedFamily kernelRun @?= "identity"
              cudaKernelOutput kernelRun @?= payload
      , testCase "linux-cuda reduction kernel sums through warp-shuffle path (Sprint 7.4)" $ do
          env <- buildEnv defaultGlobalFlags
          let payload = [4.0, -2.0, 1.0, 3.0]
          result <- runCudaFamilyKernel env Reduction payload
          case result of
            Left message ->
              assertBool ("linux-cuda Reduction JIT run failed: " <> show message) False
            Right kernelRun -> do
              cudaKernelReportedFamily kernelRun @?= "reduction"
              -- Reduction emits one partial per warp; sum of all
              -- partials must equal the host-canonical sum.
              case CudaRuntime.finalizeCudaReductionPartials
                (length payload)
                (cudaKernelOutput kernelRun) of
                Left message ->
                  assertBool ("reduction finalize failed: " <> show message) False
                Right total ->
                  total @?= 6.0
      , testCase "linux-cuda kernel output is bit-equal across repeated runs (Sprint 7.4)" $ do
          -- Same-host bit-equality test for the CUDA path. Mirrors the
          -- linux-cpu sibling that lives next to this case. Three
          -- successive invocations of the generated identity kernel
          -- through the live FFI boundary must produce bit-identical
          -- output. Validates the determinism contract for linux-cuda
          -- per documents/engineering/determinism_contract.md.
          env <- buildEnv defaultGlobalFlags
          let payload = [0.0, 1.5, -2.25, 3.875, -4.125]
          first <- runCudaFamilyKernel env Identity payload
          second <- runCudaFamilyKernel env Identity payload
          third <- runCudaFamilyKernel env Identity payload
          case (first, second, third) of
            (Right a, Right b, Right c) -> do
              cudaKernelOutput a @?= cudaKernelOutput b
              cudaKernelOutput b @?= cudaKernelOutput c
              cudaKernelOutput a @?= payload
            _ ->
              assertBool "all three linux-cuda kernel runs succeed" False
      , testCase
          "linux-cuda weighted Dense2D kernel runs real device GEMM bit-deterministically (Sprint 13.11)"
          $ do
            -- Sprint 13.11 CUDA half — same-host bit-equality for the
            -- weighted CUDA ABI. Three runs of the device GEMM kernel
            -- against the same input + weights buffer must produce
            -- bit-identical output, and the math must match the
            -- diagonal-scaling expectation from the Linux CPU sibling.
            env <- buildEnv defaultGlobalFlags
            let input = [1.0, 2.0, 3.0]
                -- Same 3×3 diagonal matrix as the Linux CPU sibling
                -- test. Expected output: input × diag(1,2,3) = [1,4,9].
                weights = [1, 0, 0, 0, 2, 0, 0, 0, 3]
            first <- Cuda.runCudaWeightedFamilyKernel env Dense2D input weights
            second <- Cuda.runCudaWeightedFamilyKernel env Dense2D input weights
            third <- Cuda.runCudaWeightedFamilyKernel env Dense2D input weights
            case (first, second, third) of
              (Right a, Right b, Right c) -> do
                Cuda.cudaWeightedKernelReportedFamily a @?= "dense"
                Cuda.cudaWeightedKernelOutput a @?= Cuda.cudaWeightedKernelOutput b
                Cuda.cudaWeightedKernelOutput b @?= Cuda.cudaWeightedKernelOutput c
                Cuda.cudaWeightedKernelOutput a @?= [1.0, 4.0, 9.0]
              _ ->
                assertBool "all three linux-cuda weighted kernel runs succeed" False
      , testCase "apple-silicon kernel output is bit-equal across repeated runs (Sprint 14.2)" $ do
          -- Same-host bit-equality test for the Metal path. Mirrors the
          -- linux-cpu / linux-cuda siblings: three successive invocations of
          -- the generated identity kernel through the fixed Metal bridge must
          -- produce bit-identical output. The lane runs for real on Apple
          -- hardware with a visible Metal device and an installed bridge; a
          -- missing device or bridge fails (the Sprint 14.6 skip guards are gone).
          env <- buildEnv defaultGlobalFlags
          let payload = [0.0, 1.5, -2.25, 3.875, -4.125]
          first <- Metal.runMetalFamilyKernel env Identity payload
          second <- Metal.runMetalFamilyKernel env Identity payload
          third <- Metal.runMetalFamilyKernel env Identity payload
          case (first, second, third) of
            (Right a, Right b, Right c) -> do
              Metal.metalKernelOutput a @?= Metal.metalKernelOutput b
              Metal.metalKernelOutput b @?= Metal.metalKernelOutput c
              Metal.metalKernelOutput a @?= payload
            _ ->
              assertBool "all three apple-silicon kernel runs succeed" False
      , testCase
          "apple-silicon weighted Dense2D kernel runs bit-deterministically (Sprint 14.5)"
          $ do
            -- Sprint 14.5 — same-host bit-equality for the weighted Metal ABI.
            -- Three runs of the Dense2D GEMM against the same input + weights
            -- must be bit-identical and match the diagonal-scaling expectation
            -- shared with the linux-cpu / linux-cuda weighted siblings.
            env <- buildEnv defaultGlobalFlags
            let input = [1.0, 2.0, 3.0]
                -- 3×3 diagonal matrix: input × diag(1,2,3) = [1,4,9].
                weights = [1, 0, 0, 0, 2, 0, 0, 0, 3]
            first <- Metal.runMetalWeightedFamilyKernel env Dense2D input weights
            second <- Metal.runMetalWeightedFamilyKernel env Dense2D input weights
            third <- Metal.runMetalWeightedFamilyKernel env Dense2D input weights
            case (first, second, third) of
              (Right a, Right b, Right c) -> do
                Metal.metalWeightedKernelOutput a @?= Metal.metalWeightedKernelOutput b
                Metal.metalWeightedKernelOutput b @?= Metal.metalWeightedKernelOutput c
                Metal.metalWeightedKernelOutput a @?= [1.0, 4.0, 9.0]
              _ ->
                assertBool "all three apple-silicon weighted kernel runs succeed" False
      , testCase "apple-silicon live Metal benchmark candidate runner produces a measurement (Sprint 14.3)" $ do
          -- Sprint 14.3 — the de-stubbed metalBenchmarkCandidateRunner drives the
          -- fixed bridge -> runtime makeLibrary -> Metal launch path, times the
          -- round-trip, and digests the float output. One candidate keeps this
          -- fast; the full sweep is the gated test below.
          env <- buildEnv defaultGlobalFlags
          let input = [0.0, 1.0, 2.0, 3.0]
          measured <-
            TuningBenchmark.metalBenchmarkCandidateRunner
              env
              (Cache.KernelSpec "jitml-apple:benchmark")
              Cache.Inference
              input
              (Tuning.selectDeterministic Tuning.appleSiliconKnobs)
          case measured of
            Left err -> assertBool ("apple-silicon benchmark runner failed: " <> show err) False
            Right observation -> do
              TuningBenchmark.benchmarkObservationOutputDigest observation
                @?= TuningBenchmark.digestFloatOutput input
              assertBool
                "benchmark latency is non-negative"
                (TuningBenchmark.benchmarkObservationLatencyMicros observation >= 0)
          wrongSubstrate <-
            TuningBenchmark.metalBenchmarkCandidateRunner
              env
              (Cache.KernelSpec "jitml-apple:benchmark")
              Cache.Inference
              input
              (Tuning.selectDeterministic Tuning.linuxCpuKnobs)
          wrongSubstrate
            @?= Left "apple-silicon benchmark runner cannot execute linux-cpu candidate"
      , testCase
          "apple-silicon first cache-miss persists and reuses a TuningChoice via the live runner (Sprint 14.3)"
          $ do
            -- Full benchmark-tuning round-trip through the live Metal runner. The
            -- Apple knob space is a 4x3x2x1 cross-product (24 bridge-dispatched
            -- candidates), so this is gated behind the
            -- explicit JITML_TUNING_LIVE opt-in to keep the routine apple-silicon
            -- lane fast. When opted in, a missing Metal device or bridge fails —
            -- there is no hardware skip guard.
            liveTuning <- lookupEnv "JITML_TUNING_LIVE"
            case liveTuning of
              Just _ -> do
                env <- buildEnv defaultGlobalFlags
                let buildRoot = toFilePath (envCacheDir env)
                    tuningDir = buildRoot </> "jit" </> "tuning" </> "apple-silicon"
                    fingerprint = Cache.ToolchainFingerprint "14.3-fingerprint"
                uniqueSuffix <- pickRandomSuffix
                let kernelSpec = Cache.KernelSpec ("jitml-apple:14.3-cache-miss-" <> uniqueSuffix)
                preExisting <-
                  listDirectory tuningDir
                    `Control.Exception.catch` \(_ :: Control.Exception.IOException) -> pure []
                firstResult <-
                  TuningBenchmark.ensureKernelArtifactWithBenchmarkTuning
                    env
                    Substrate.AppleSilicon
                    kernelSpec
                    Cache.Inference
                    fingerprint
                    [0.0]
                assertBool
                  ("first benchmark-tuning build succeeds: " <> show firstResult)
                  (isRight firstResult)
                afterFirst <- listDirectory tuningDir
                let newFiles = filter (`notElem` preExisting) afterFirst
                assertBool
                  ("a new TuningChoice JSON is persisted under " <> tuningDir)
                  (not (null newFiles))
                -- The second build reads the persisted choice (no re-sweep).
                secondResult <-
                  TuningBenchmark.ensureKernelArtifactWithBenchmarkTuning
                    env
                    Substrate.AppleSilicon
                    kernelSpec
                    Cache.Inference
                    fingerprint
                    [0.0]
                assertBool
                  ("second benchmark-tuning build reuses the persisted choice: " <> show secondResult)
                  (isRight secondResult)
              Nothing ->
                assertBool
                  "JITML_TUNING_LIVE not set; slow apple-silicon tuning round-trip not requested"
                  True
      , testCase "linux-cuda cuBLAS bindings initialize and report a version (Sprint 7.4)" $ do
          versionResult <- Cublas.verifyCublasRuntime
          case versionResult of
            Left status ->
              assertBool
                ( "cuBLAS verifyCublasRuntime failed: "
                    <> show (Cublas.cublasStatusCode status)
                )
                False
            Right version -> do
              assertBool
                ( "cuBLAS major version is positive: "
                    <> show (Cublas.cublasVersionMajor version)
                )
                (Cublas.cublasVersionMajor version > 0)
              assertBool
                ( "cuBLAS raw version is positive: "
                    <> show (Cublas.cublasVersionRaw version)
                )
                (Cublas.cublasVersionRaw version > 0)
      , testCase "linux-cuda cuDNN bindings initialize and report a version (Sprint 7.4)" $ do
          versionResult <- Cudnn.verifyCudnnRuntime
          case versionResult of
            Left status ->
              assertBool
                ( "cuDNN verifyCudnnRuntime failed: "
                    <> show (Cudnn.cudnnStatusCode status)
                )
                False
            Right version -> do
              assertBool
                ( "cuDNN major version is positive: "
                    <> show (Cudnn.cudnnVersionMajor version)
                )
                (Cudnn.cudnnVersionMajor version > 0)
              assertBool
                ( "cuDNN raw version is positive: "
                    <> show (Cudnn.cudnnVersionRaw version)
                )
                (Cudnn.cudnnVersionRaw version > 0)
      , testCase "linux-cuda benchmark candidate runner measures generated FFI output (Sprint 7.6)" $ do
          -- Sprint 7.6 live CUDA candidate runner: mirrors the linux-cpu
          -- sibling. In the linux-cuda lane the runner renders the tuned CUDA
          -- source, compiles via real nvcc, loads through the FFI, and reports
          -- a measured latency plus content-sensitive float digest. A missing
          -- CUDA toolchain fails the lane (no skip guard).
          env <- buildEnv defaultGlobalFlags
          let cudaCandidate = Tuning.selectDeterministic Tuning.linuxCudaKnobs
              input = [1.0, 2.0, -3.5]
          observation <-
            TuningBenchmark.cudaBenchmarkCandidateRunner
              env
              (Cache.KernelSpec "jitml-linux-cuda:benchmark")
              Cache.Inference
              input
              cudaCandidate
          case observation of
            Left message ->
              assertBool ("linux-cuda benchmark candidate failed: " <> show message) False
            Right measured -> do
              TuningBenchmark.benchmarkObservationOutputDigest measured
                @?= TuningBenchmark.digestFloatOutput input
              assertBool
                "linux-cuda benchmark latency is non-negative"
                (TuningBenchmark.benchmarkObservationLatencyMicros measured >= 0)
          rejected <-
            TuningBenchmark.cudaBenchmarkCandidateRunner
              env
              (Cache.KernelSpec "jitml-linux-cuda:benchmark")
              Cache.Inference
              input
              (Tuning.selectDeterministic Tuning.linuxCpuKnobs)
          rejected @?= Left "linux-cuda benchmark runner cannot execute linux-cpu candidate"
      , testCase "linux-cpu benchmark candidate runner measures generated FFI output (Sprint 7.6)" $ do
          env <- buildEnv defaultGlobalFlags
          let candidate = Tuning.selectDeterministic Tuning.linuxCpuKnobs
              input = [1.0, 2.0, -3.5]
          observation <-
            TuningBenchmark.linuxCpuBenchmarkCandidateRunner
              env
              (Cache.KernelSpec "jitml-linux-cpu:benchmark")
              Cache.Inference
              input
              candidate
          case observation of
            Left message ->
              assertBool ("linux-cpu benchmark candidate failed: " <> show message) False
            Right measured -> do
              TuningBenchmark.benchmarkObservationOutputDigest measured
                @?= TuningBenchmark.digestFloatOutput input
              assertBool
                "benchmark latency is non-negative"
                (TuningBenchmark.benchmarkObservationLatencyMicros measured >= 0)
          rejected <-
            TuningBenchmark.linuxCpuBenchmarkCandidateRunner
              env
              (Cache.KernelSpec "jitml-linux-cpu:benchmark")
              Cache.Inference
              input
              (Tuning.selectDeterministic Tuning.linuxCudaKnobs)
          rejected @?= Left "linux-cpu benchmark runner cannot execute linux-cuda candidate"
      , testCase
          "linux-cpu first cache-miss persists a TuningChoice JSON in the tuning store (Sprint 13.15)"
          $ do
            env <- buildEnv defaultGlobalFlags
            let buildRoot = toFilePath (envCacheDir env)
                tuningDir = buildRoot </> "jit" </> "tuning" </> "linux-cpu"
            -- Pick a uniquely-named kernel spec so the cache-miss path
            -- triggers regardless of any prior tuning selections.
            uniqueSuffix <- pickRandomSuffix
            let kernelSpec = Cache.KernelSpec ("jitml-linux-cpu:13.15-cache-miss-" <> uniqueSuffix)
            -- Snapshot the existing selection files so the assertion
            -- below counts only files newly written by this run.
            preExisting <-
              listDirectory tuningDir
                `Control.Exception.catch` \(_ :: Control.Exception.IOException) -> pure []
            -- Drive the cache-miss path. The deterministic fixture runner
            -- returns a constant observation; the typed
            -- ensureKernelArtifactWithBenchmarkTuningWithRunner closure
            -- writes the selection to disk via TuningStore.
            let fixtureRunner _env _spec _kind _input _candidate =
                  pure
                    ( Right
                        ( TuningBenchmark.BenchmarkObservation
                            { TuningBenchmark.benchmarkObservationLatencyMicros = 1
                            , TuningBenchmark.benchmarkObservationOutputDigest = "fixture-digest"
                            }
                        )
                    )
            _ <-
              TuningBenchmark.ensureKernelArtifactWithBenchmarkTuningWithRunner
                env
                Substrate.LinuxCPU
                fixtureRunner
                kernelSpec
                Cache.Inference
                (Cache.ToolchainFingerprint "13.15-fingerprint")
                [0.0]
            -- A fresh kernel spec hashes to a previously-unseen base
            -- hash; the cache-miss path must persist exactly one new
            -- JSON selection under the tuning store directory.
            afterFirst <- listDirectory tuningDir
            let newFiles = filter (`notElem` preExisting) afterFirst
            assertBool
              ( "expected at least one new TuningChoice JSON under "
                  <> tuningDir
                  <> "; pre="
                  <> show preExisting
                  <> " post="
                  <> show afterFirst
              )
              (not (null newFiles))
      , testCase
          "linux-cuda MLP forward kernel matches the pure-Haskell network (Sprint 13.8/13.9)"
          $ do
            -- Sprint 13.8/13.9 — the nvcc-emitted MLP forward kernel
            -- (JitML.Codegen.MlpCuda) must reproduce the pure-Haskell
            -- forward pass within a single-precision tolerance. CUDA runs
            -- float32 while the reference runs Double, so the contract is
            -- close-agreement, not bit-equality (the determinism contract's
            -- bit-equality requirement is the run-to-run check below).
            env <- buildEnv defaultGlobalFlags
            let shape = MlpShape {mlpInputs = 4, mlpHidden = 6, mlpOutputs = 3}
                params = mlpInit shape 5
                input = VU.fromList [0.5, -0.25, 1.0, -0.75]
                refForward = mlpForward params input
            cudaResult <- mlpForwardCuda env params input
            case cudaResult of
              Left message ->
                assertBool ("MLP forward CUDA run failed: " <> Text.unpack message) False
              Right cudaForward -> do
                assertBool
                  ( "CUDA hidden_pre within tolerance of reference: cuda="
                      <> show (VU.toList (forwardHiddenPre cudaForward))
                      <> " ref="
                      <> show (VU.toList (forwardHiddenPre refForward))
                  )
                  (approxEqualVec 1.0e-3 (forwardHiddenPre cudaForward) (forwardHiddenPre refForward))
                assertBool
                  "CUDA hidden_act within tolerance of reference"
                  (approxEqualVec 1.0e-3 (forwardHiddenAct cudaForward) (forwardHiddenAct refForward))
                assertBool
                  ( "CUDA output within tolerance of reference: cuda="
                      <> show (VU.toList (forwardOutput cudaForward))
                      <> " ref="
                      <> show (VU.toList (forwardOutput refForward))
                  )
                  (approxEqualVec 1.0e-3 (forwardOutput cudaForward) (forwardOutput refForward))
      , testCase
          "linux-cuda MLP backward kernel matches the pure-Haskell gradient (Sprint 13.8/13.9)"
          $ do
            env <- buildEnv defaultGlobalFlags
            let shape = MlpShape {mlpInputs = 4, mlpHidden = 6, mlpOutputs = 3}
                params = mlpInit shape 5
                input = VU.fromList [0.5, -0.25, 1.0, -0.75]
                -- Feed both backward passes the same (pure) forward cache
                -- so the comparison isolates the backward kernel.
                refForward = mlpForward params input
                dLdy = VU.fromList [0.2, -0.4, 0.6]
                refGrad = mlpBackward params refForward dLdy
            cudaResult <- mlpBackwardCuda env params refForward dLdy
            case cudaResult of
              Left message ->
                assertBool ("MLP backward CUDA run failed: " <> Text.unpack message) False
              Right cudaGrad -> do
                assertBool
                  "CUDA gradW1 within tolerance of reference"
                  (approxEqualVec 1.0e-3 (gradW1 cudaGrad) (gradW1 refGrad))
                assertBool
                  "CUDA gradB1 within tolerance of reference"
                  (approxEqualVec 1.0e-3 (gradB1 cudaGrad) (gradB1 refGrad))
                assertBool
                  "CUDA gradW2 within tolerance of reference"
                  (approxEqualVec 1.0e-3 (gradW2 cudaGrad) (gradW2 refGrad))
                assertBool
                  "CUDA gradB2 within tolerance of reference"
                  (approxEqualVec 1.0e-3 (gradB2 cudaGrad) (gradB2 refGrad))
      , testCase
          "linux-cuda MLP kernels are bit-deterministic across repeated runs (Sprint 13.8/13.9)"
          $ do
            -- The determinism contract requires bit-equal output run-to-run
            -- on the same substrate. Per-thread sequential reductions in the
            -- generated kernel guarantee this.
            env <- buildEnv defaultGlobalFlags
            let shape = MlpShape {mlpInputs = 4, mlpHidden = 6, mlpOutputs = 3}
                params = mlpInit shape 5
                input = VU.fromList [0.5, -0.25, 1.0, -0.75]
                dLdy = VU.fromList [0.2, -0.4, 0.6]
            first <- mlpForwardCuda env params input
            second <- mlpForwardCuda env params input
            case (first, second) of
              (Right a, Right b) -> do
                forwardOutput a @?= forwardOutput b
                forwardHiddenAct a @?= forwardHiddenAct b
                gradA <- mlpBackwardCuda env params a dLdy
                gradB <- mlpBackwardCuda env params b dLdy
                case (gradA, gradB) of
                  (Right ga, Right gb) -> do
                    gradW1 ga @?= gradW1 gb
                    gradW2 ga @?= gradW2 gb
                  _ -> assertBool "both MLP backward CUDA runs succeed" False
              _ -> assertBool "both MLP forward CUDA runs succeed" False
      , testCase
          "linux-cuda batched MLP gradient matches the pure summed gradient (Sprint 13.8)"
          $ do
            -- Sprint 13.8 — the batched device gradient (one device call for
            -- the whole minibatch) must equal the pure per-sample summed
            -- gradient within a single-precision tolerance, and be
            -- bit-deterministic run-to-run. This is the amortised-copy
            -- primitive the RL trainers' minibatch hot path adopts.
            env <- buildEnv defaultGlobalFlags
            let shape = MlpShape {mlpInputs = 4, mlpHidden = 6, mlpOutputs = 3}
                params = mlpInit shape 5
                batch =
                  [ (VU.fromList [0.5, -0.25, 1.0, -0.75], VU.fromList [0.2, -0.4, 0.6])
                  , (VU.fromList [-0.1, 0.3, -0.5, 0.2], VU.fromList [-0.3, 0.5, 0.1])
                  , (VU.fromList [0.9, 0.1, -0.2, 0.4], VU.fromList [0.05, -0.15, 0.25])
                  ]
                perSample (i, dy) = mlpBackward params (mlpForward params i) dy
                sumGrad a b =
                  MlpGradient
                    { gradW1 = VU.zipWith (+) (gradW1 a) (gradW1 b)
                    , gradB1 = VU.zipWith (+) (gradB1 a) (gradB1 b)
                    , gradW2 = VU.zipWith (+) (gradW2 a) (gradW2 b)
                    , gradB2 = VU.zipWith (+) (gradB2 a) (gradB2 b)
                    }
                refGrad = foldl1 sumGrad (map perSample batch)
            first <- mlpBatchGradientCuda env params batch
            second <- mlpBatchGradientCuda env params batch
            case (first, second) of
              (Right g, Right g2) -> do
                assertBool
                  "batched gradW1 within tolerance of the pure summed gradient"
                  (approxEqualVec 1.0e-3 (gradW1 g) (gradW1 refGrad))
                assertBool
                  "batched gradB1 within tolerance"
                  (approxEqualVec 1.0e-3 (gradB1 g) (gradB1 refGrad))
                assertBool
                  "batched gradW2 within tolerance"
                  (approxEqualVec 1.0e-3 (gradW2 g) (gradW2 refGrad))
                assertBool
                  "batched gradB2 within tolerance"
                  (approxEqualVec 1.0e-3 (gradB2 g) (gradB2 refGrad))
                -- bit-deterministic across the two device runs
                gradW1 g @?= gradW1 g2
                gradW2 g @?= gradW2 g2
              _ -> assertBool "both batched MLP gradient runs succeed" False
      , testCase
          "linux-cuda layer-training artifact is byte-identical across two independent compiles (Phase 78)"
          $ do
            -- nvcc embeds its own process id (via `tmpxft_<pid>_…` intermediate
            -- names) and a random anonymous-namespace id unless both are pinned.
            -- Either one makes the artifact digest a per-compile nonce, which
            -- makes a committed lane attestation unsatisfiable by construction.
            outcome <- compileArtifactTwice Substrate.LinuxCUDA
            case outcome of
              Left message ->
                assertFailure ("linux-cuda double compile failed: " <> Text.unpack message)
              Right (first, second) ->
                assertBool
                  ( "linux-cuda artifact is not reproducible: "
                      <> show (ByteString.length first)
                      <> " vs "
                      <> show (ByteString.length second)
                      <> " bytes"
                  )
                  (first == second)
      , testCase
          "linux-cpu layer-training artifact is byte-identical across two independent compiles (Phase 78)"
          $ do
            -- g++ was measured to inject nothing, so this lane's pin set is
            -- empty. That is a claim, and this is what discharges it — it also
            -- guards the 55 attested `linux-cpu` cells against a future flag or
            -- renderer change that would quietly make them unreproducible.
            outcome <- compileArtifactTwice Substrate.LinuxCPU
            case outcome of
              Left message ->
                assertFailure ("linux-cpu double compile failed: " <> Text.unpack message)
              Right (first, second) ->
                assertBool "linux-cpu artifact is not reproducible" (first == second)
      , testCase
          "linux-cuda batched MLP gradient is bit-identical to the oneDNN lane (Phase 265)"
          $ do
            -- Phase 265 — cross-lane bit-identity, not tolerance. The name
            -- deliberately says "oneDNN lane" rather than naming both lanes:
            -- `jitml test jitml-backends --<substrate>` selects cases by tasty
            -- substring, so a name carrying both tokens is pulled into the
            -- GPU-less `linux-cpu` lane as well and dies in `cudaMalloc`.
            --
            -- The two Linux
            -- lanes are the one place jitML claims numeric agreement *between*
            -- substrates: `MlpOneDnn` declares its parameter-gradient loop
            -- "matches the CUDA batch-grad reduction order" and `Engine` passes
            -- `--fmad=false` solely so a device multiply-add rounds twice the
            -- way the oneDNN lane's separate multiply-then-add does. Agreement
            -- is therefore the stated design and divergence is a defect.
            --
            -- It was a defect: every accumulation order already matched, but
            -- the lanes evaluated two implementations of one function —
            -- `std::tanh` (glibc flt-32) against CUDA's libdevice `tanhf` —
            -- which disagree on 3.03% of all floats and drove the batched
            -- gradient apart by 9.54e-7 absolute. Sprint 265.1 renders glibc's
            -- own algorithm on this lane so the activation agrees exactly.
            --
            -- The per-lane oracle cases above compare against the pure
            -- reference at 1.0e-3, four orders too loose to observe this, so it
            -- needs its own standing assertion. The shape is deliberately wider
            -- than those fixtures: 32 x 64 = 2048 hidden activations, enough
            -- that the ~3% divergence rate would light up dozens of elements
            -- rather than getting lucky on six.
            env <- buildEnv defaultGlobalFlags
            let shape = MlpShape {mlpInputs = 16, mlpHidden = 64, mlpOutputs = 8}
                params = mlpInit shape 11
                sample b =
                  ( VU.generate 16 $ \j ->
                      sin (fromIntegral (b * 16 + j) * 0.37) * 1.5
                  , VU.generate 8 $ \k ->
                      cos (fromIntegral (b * 8 + k) * 0.21) * 0.5
                  )
                batch = [sample b | b <- [0 .. 31 :: Int]]
            cpu <- mlpBatchGradientOneDnn env params batch
            cuda <- mlpBatchGradientCuda env params batch
            case (cpu, cuda) of
              (Right c, Right g) -> do
                gradW1 g @?= gradW1 c
                gradB1 g @?= gradB1 c
                gradW2 g @?= gradW2 c
                gradB2 g @?= gradB2 c
              (Left message, _) ->
                assertFailure ("linux-cpu batched gradient failed: " <> Text.unpack message)
              (_, Left message) ->
                assertFailure ("linux-cuda batched gradient failed: " <> Text.unpack message)
      , testCase
          "linux-cuda MLP source renders the lane-aligned activation (Phase 265)"
          $ do
            -- The source guard for the case above: the rendered kernels must
            -- call the aligned activation, and CUDA's own `tanhf` must not
            -- survive at a call site. A regression here is a one-line edit that
            -- would otherwise only surface as a drifting gradient.
            let rendered =
                  Text.concat
                    [ contents
                    | SourceFile _ contents <- MlpCudaCodegen.renderMlpCudaSource
                    ]
            assertBool
              "the MLP CUDA source defines the aligned activation"
              ( ("__device__ __forceinline__ float " <> MlpCudaCodegen.mlpCudaActivation)
                  `Text.isInfixOf` rendered
              )
            assertBool
              "the MLP CUDA source calls the aligned activation"
              ((MlpCudaCodegen.mlpCudaActivation <> "(acc)") `Text.isInfixOf` rendered)
            assertBool
              "no MLP CUDA call site uses CUDA's own tanhf"
              (not ("= tanhf(" `Text.isInfixOf` rendered))
      , testCase
          "linux-cuda batched MLP forward matches the pure per-sample forward (Sprint 13.8)"
          $ do
            -- Sprint 13.8 — the batched forward (one device call for the whole
            -- minibatch) must reproduce the pure per-sample forward outputs
            -- within single precision, and be bit-deterministic. Together with
            -- the batched gradient this is the full device minibatch primitive
            -- set a CUDA trainer drives.
            env <- buildEnv defaultGlobalFlags
            let shape = MlpShape {mlpInputs = 4, mlpHidden = 6, mlpOutputs = 3}
                params = mlpInit shape 5
                inputs =
                  [ VU.fromList [0.5, -0.25, 1.0, -0.75]
                  , VU.fromList [-0.1, 0.3, -0.5, 0.2]
                  , VU.fromList [0.9, 0.1, -0.2, 0.4]
                  ]
                refOutputs = map (forwardOutput . mlpForward params) inputs
            first <- mlpForwardBatchCuda env params inputs
            second <- mlpForwardBatchCuda env params inputs
            case (first, second) of
              (Right outs, Right outs2) -> do
                assertBool
                  ("batched forward returns " <> show (length inputs) <> " outputs")
                  (length outs == length inputs)
                assertBool
                  "each batched forward output is within tolerance of the pure forward"
                  (and (zipWith (approxEqualVec 1.0e-3) outs refOutputs))
                -- bit-deterministic across the two device runs
                outs @?= outs2
              _ -> assertBool "both batched MLP forward runs succeed" False
      , testCase
          "linux-cuda batched MLP input-gradient matches the pure mlpInputGradient (Sprint 13.8)"
          $ do
            -- Sprint 13.8 — the batched device input-gradient (one device
            -- call → per-sample dL/dx) must match the pure
            -- `mlpInputGradient` within single precision and be
            -- bit-deterministic. This is the deterministic-policy gradient
            -- primitive the continuous actor-critic family needs.
            env <- buildEnv defaultGlobalFlags
            let shape = MlpShape {mlpInputs = 4, mlpHidden = 6, mlpOutputs = 3}
                params = mlpInit shape 5
                batch =
                  [ (VU.fromList [0.5, -0.25, 1.0, -0.75], VU.fromList [0.2, -0.4, 0.6])
                  , (VU.fromList [-0.1, 0.3, -0.5, 0.2], VU.fromList [-0.3, 0.5, 0.1])
                  , (VU.fromList [0.9, 0.1, -0.2, 0.4], VU.fromList [0.05, -0.15, 0.25])
                  ]
                refDx (i, dy) = mlpInputGradient params (mlpForward params i) dy
                refs = map refDx batch
            first <- mlpInputGradientBatchCuda env params batch
            second <- mlpInputGradientBatchCuda env params batch
            case (first, second) of
              (Right dxs, Right dxs2) -> do
                assertBool
                  ("batched input-gradient returns " <> show (length batch) <> " vectors")
                  (length dxs == length batch)
                assertBool
                  "each batched dL/dx is within tolerance of the pure mlpInputGradient"
                  (and (zipWith (approxEqualVec 1.0e-3) dxs refs))
                dxs @?= dxs2
              _ -> assertBool "both batched input-gradient runs succeed" False
      , testCase
          "linux-cuda on-policy PPO trainer trains through the batched device path (Sprint 13.8)"
          $ do
            -- Sprint 13.8 — the shared on-policy trainer
            -- (`trainOnPolicyOnCartpoleCuda`, covering PPO/A2C/TRPO/
            -- MaskablePPO/RecurrentPPO) runs its minibatch forward + backward
            -- on the GPU through the batched device primitives. Assert it
            -- completes the configured iterations with finite rewards and is
            -- run-to-run deterministic on the device (same seed → identical
            -- per-iteration means). Float32 means it does not match the pure
            -- Double trainer's numbers — determinism on CUDA is the contract.
            env <- buildEnv defaultGlobalFlags
            let config =
                  defaultPpoTrainConfig
                    { ppoNumIterations = 3
                    , ppoRolloutSteps = 128
                    , ppoEpochsPerUpdate = 2
                    , ppoMiniBatchSize = 32
                    , ppoHiddenUnits = 16
                    }
                finite x = not (isNaN x) && not (isInfinite x)
            r1 <- trainOnPolicyOnCartpoleCuda env VariantPPO config
            r2 <- trainOnPolicyOnCartpoleCuda env VariantPPO config
            case (r1, r2) of
              (Right res1, Right res2) -> do
                length (resultIterations res1) @?= 3
                assertBool
                  "per-iteration mean rewards are finite"
                  (all (finite . iterMeanReward) (resultIterations res1))
                -- run-to-run determinism on the device
                map iterMeanReward (resultIterations res1)
                  @?= map iterMeanReward (resultIterations res2)
              (Left e, _) ->
                assertBool ("CUDA on-policy trainer failed: " <> Text.unpack e) False
              _ -> assertBool "both CUDA on-policy trainer runs succeed" False
      , testCase
          "linux-cuda DQN trainer trains through the batched device path (Sprint 13.8)"
          $ do
            -- Sprint 13.8 — the DQN trainer (the discrete off-policy
            -- template) runs its minibatch Q-network forward + backward on
            -- the GPU through the batched primitives. Assert it produces
            -- finite per-interval mean rewards and is run-to-run
            -- deterministic on the device.
            env <- buildEnv defaultGlobalFlags
            let config =
                  defaultDqnTrainConfig
                    { dqnNumSteps = 600
                    , dqnTrainStart = 100
                    , dqnBatchSize = 16
                    , dqnHiddenUnits = 16
                    , dqnStatInterval = 200
                    , dqnTargetUpdateInterval = 200
                    }
                finite x = not (isNaN x) && not (isInfinite x)
            r1 <- trainDqnOnCartpoleCuda env config >>= expectRight "CUDA DQN trainer failed"
            r2 <- trainDqnOnCartpoleCuda env config >>= expectRight "CUDA DQN trainer failed"
            assertBool
              "DQN run produced at least one interval stat"
              (not (null (dqnResultStats r1)))
            assertBool
              "per-interval mean rewards are finite"
              (all (finite . dqnIterMeanReward) (dqnResultStats r1))
            map dqnIterMeanReward (dqnResultStats r1)
              @?= map dqnIterMeanReward (dqnResultStats r2)
      , testCase
          "linux-cuda QR-DQN trainer trains through the batched device path (Sprint 13.8)"
          $ do
            -- Sprint 13.8 — the QR-DQN distributional off-policy trainer runs
            -- its minibatch quantile-network forward + backward on the GPU
            -- through the batched primitives. Finite + run-to-run
            -- deterministic on the device.
            env <- buildEnv defaultGlobalFlags
            let config =
                  defaultQrDqnTrainConfig
                    { qrNumSteps = 600
                    , qrTrainStart = 100
                    , qrBatchSize = 16
                    , qrHiddenUnits = 16
                    , qrNumQuantiles = 4
                    , qrStatInterval = 200
                    , qrTargetUpdateInterval = 200
                    }
                finite x = not (isNaN x) && not (isInfinite x)
            r1 <- trainQrDqnOnCartpoleCuda env config >>= expectRight "CUDA QR-DQN trainer failed"
            r2 <- trainQrDqnOnCartpoleCuda env config >>= expectRight "CUDA QR-DQN trainer failed"
            assertBool
              "QR-DQN run produced at least one interval stat"
              (not (null (qrResultStats r1)))
            assertBool
              "per-interval mean rewards are finite"
              (all (finite . qrIterMeanReward) (qrResultStats r1))
            map qrIterMeanReward (qrResultStats r1)
              @?= map qrIterMeanReward (qrResultStats r2)
      , testCase
          "linux-cuda HER trainer trains through the batched device path (Sprint 13.8)"
          $ do
            -- Sprint 13.8 — the HER goal-conditioned trainer (DQN-shaped Q
            -- network on the bit-flip env) runs its minibatch forward +
            -- backward on the GPU through the batched primitives. Finite
            -- success rates + run-to-run deterministic on the device.
            env <- buildEnv defaultGlobalFlags
            let config =
                  defaultHerTrainConfig
                    { herNumBits = 4
                    , herEpisodes = 60
                    , herHiddenUnits = 16
                    , herBatchSize = 16
                    , herStatInterval = 20
                    , herTargetUpdateInterval = 20
                    }
                finite x = not (isNaN x) && not (isInfinite x)
            r1 <- trainHerOnBitFlipCuda env config >>= expectRight "CUDA HER trainer failed"
            r2 <- trainHerOnBitFlipCuda env config >>= expectRight "CUDA HER trainer failed"
            assertBool
              "HER run produced at least one interval stat"
              (not (null (herResultStats r1)))
            assertBool
              "per-interval success rates are finite in [0,1]"
              ( all
                  (\s -> finite (herIterSuccessRate s) && herIterSuccessRate s >= 0 && herIterSuccessRate s <= 1)
                  (herResultStats r1)
              )
            map herIterSuccessRate (herResultStats r1)
              @?= map herIterSuccessRate (herResultStats r2)
      , testCase
          "linux-cuda continuous actor-critic (DDPG) trains through the batched device path (Sprint 13.8)"
          $ do
            -- Sprint 13.8 — the continuous actor-critic trainer
            -- (`trainContinuousOnPendulumCuda`, covering DDPG/TD3/SAC/CrossQ/
            -- TQC) runs its critic param-gradient, the actor's dQ/da
            -- (critic input-gradient), and the actor param-gradient on the
            -- GPU through the batched primitives. DDPG exercises the full
            -- device actor-critic path; the other variants differ only in
            -- the shared pure `bellmanTarget`. Finite + run-to-run
            -- deterministic on the device.
            env <- buildEnv defaultGlobalFlags
            let config =
                  (defaultContinuousTrainConfig VariantDDPG)
                    { ctNumSteps = 400
                    , ctTrainStart = 100
                    , ctStartSteps = 100
                    , ctBatchSize = 16
                    , ctHidden = 16
                    , ctStatInterval = 200
                    }
                finite x = not (isNaN x) && not (isInfinite x)
            r1 <- trainContinuousOnPendulumCuda env config >>= expectRight "CUDA continuous trainer failed"
            r2 <- trainContinuousOnPendulumCuda env config >>= expectRight "CUDA continuous trainer failed"
            assertBool
              "continuous run produced at least one interval stat"
              (not (null (contResultStats r1)))
            assertBool
              "per-interval mean rewards are finite"
              (all (finite . contIterMeanReward) (contResultStats r1))
            map contIterMeanReward (contResultStats r1)
              @?= map contIterMeanReward (contResultStats r2)
      , testCase
          "linux-cuda AlphaZero PolicyValueNet trains on the device and reduces loss (Sprint 13.9)"
          $ do
            -- Sprint 13.9 — the CUDA-backed AlphaZero training step
            -- (`trainPolicyValueNetOnSamplesCuda`) runs the network
            -- forward + backward on the GPU through the generated nvcc MLP
            -- kernels. Mirror of the pure `rl-canonicals` loss-reduction
            -- assertion: 80 device gradient passes on a synthetic sample
            -- must drive the policy+value loss below its starting value.
            env <- buildEnv defaultGlobalFlags
            let net0 = PVN.initPolicyValueNet 43 7 16 22
                adam0 = PVN.initAdamFor net0
                target = VU.fromList [0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0]
                sample =
                  PVN.PolicyValueTrainingSample
                    { PVN.sampleState = initialConnect4
                    , PVN.sampleVisitDist = target
                    , PVN.sampleOutcome = 0.5
                    }
                logSafe x = if x <= 0 then -1.0e9 else log x
                lossOf net =
                  let pv = PVN.networkPolicyValue net (PVN.sampleState sample)
                      policy = PVN.pvPolicy pv
                      policyLoss =
                        negate
                          ( sum
                              [ (PVN.sampleVisitDist sample VU.! i) * logSafe (policy VU.! i)
                              | i <- [0 .. VU.length policy - 1]
                              ]
                          )
                      valueLoss = 0.5 * (PVN.pvValue pv - PVN.sampleOutcome sample) ^ (2 :: Int)
                   in policyLoss + valueLoss
            trained <- PVN.trainPolicyValueNetOnSamplesCuda env net0 adam0 1.0e-2 80 [sample]
            case trained of
              Left message ->
                assertBool ("PolicyValueNet CUDA training failed: " <> Text.unpack message) False
              Right (netN, _) -> do
                let before = lossOf net0
                    after = lossOf netN
                assertBool
                  ( "device-trained policy/value loss should decrease; before="
                      <> show before
                      <> " after="
                      <> show after
                  )
                  (after < before)
      , -- ════ Phase 4 rebalance: linux-cpu (oneDNN) RL trainers ════
        testCase
          "linux-cpu on-policy PPO trainer trains through the batched device path (Phase 4 rebalance)"
          $ do
            env <- buildEnv defaultGlobalFlags
            let config =
                  defaultPpoTrainConfig
                    { ppoNumIterations = 3
                    , ppoRolloutSteps = 128
                    , ppoEpochsPerUpdate = 2
                    , ppoMiniBatchSize = 32
                    , ppoHiddenUnits = 16
                    }
                finite x = not (isNaN x) && not (isInfinite x)
            r1 <- trainOnPolicyOnCartpoleOneDnn env VariantPPO config
            r2 <- trainOnPolicyOnCartpoleOneDnn env VariantPPO config
            case (r1, r2) of
              (Right res1, Right res2) -> do
                length (resultIterations res1) @?= 3
                assertBool
                  "per-iteration mean rewards are finite"
                  (all (finite . iterMeanReward) (resultIterations res1))
                map iterMeanReward (resultIterations res1)
                  @?= map iterMeanReward (resultIterations res2)
              (Left e, _) ->
                assertBool ("oneDNN on-policy trainer failed: " <> Text.unpack e) False
              _ -> assertBool "both oneDNN on-policy trainer runs succeed" False
      , testCase
          "linux-cpu DQN trainer trains through the batched device path (Phase 4 rebalance)"
          $ do
            env <- buildEnv defaultGlobalFlags
            let config =
                  defaultDqnTrainConfig
                    { dqnNumSteps = 600
                    , dqnTrainStart = 100
                    , dqnBatchSize = 16
                    , dqnHiddenUnits = 16
                    , dqnStatInterval = 200
                    , dqnTargetUpdateInterval = 200
                    }
                finite x = not (isNaN x) && not (isInfinite x)
            r1 <- trainDqnOnCartpoleOneDnn env config >>= expectRight "oneDNN DQN trainer failed"
            r2 <- trainDqnOnCartpoleOneDnn env config >>= expectRight "oneDNN DQN trainer failed"
            assertBool
              "DQN run produced at least one interval stat"
              (not (null (dqnResultStats r1)))
            assertBool
              "per-interval mean rewards are finite"
              (all (finite . dqnIterMeanReward) (dqnResultStats r1))
            map dqnIterMeanReward (dqnResultStats r1)
              @?= map dqnIterMeanReward (dqnResultStats r2)
      , testCase
          "linux-cpu QR-DQN trainer trains through the batched device path (Phase 4 rebalance)"
          $ do
            env <- buildEnv defaultGlobalFlags
            let config =
                  defaultQrDqnTrainConfig
                    { qrNumSteps = 600
                    , qrTrainStart = 100
                    , qrBatchSize = 16
                    , qrHiddenUnits = 16
                    , qrNumQuantiles = 4
                    , qrStatInterval = 200
                    , qrTargetUpdateInterval = 200
                    }
                finite x = not (isNaN x) && not (isInfinite x)
            r1 <- trainQrDqnOnCartpoleOneDnn env config >>= expectRight "oneDNN QR-DQN trainer failed"
            r2 <- trainQrDqnOnCartpoleOneDnn env config >>= expectRight "oneDNN QR-DQN trainer failed"
            assertBool
              "QR-DQN run produced at least one interval stat"
              (not (null (qrResultStats r1)))
            assertBool
              "per-interval mean rewards are finite"
              (all (finite . qrIterMeanReward) (qrResultStats r1))
            map qrIterMeanReward (qrResultStats r1)
              @?= map qrIterMeanReward (qrResultStats r2)
      , testCase
          "linux-cpu HER trainer trains through the batched device path (Phase 4 rebalance)"
          $ do
            env <- buildEnv defaultGlobalFlags
            let config =
                  defaultHerTrainConfig
                    { herNumBits = 4
                    , herEpisodes = 60
                    , herHiddenUnits = 16
                    , herBatchSize = 16
                    , herStatInterval = 20
                    , herTargetUpdateInterval = 20
                    }
                finite x = not (isNaN x) && not (isInfinite x)
            r1 <- trainHerOnBitFlipOneDnn env config >>= expectRight "oneDNN HER trainer failed"
            r2 <- trainHerOnBitFlipOneDnn env config >>= expectRight "oneDNN HER trainer failed"
            assertBool
              "HER run produced at least one interval stat"
              (not (null (herResultStats r1)))
            assertBool
              "per-interval success rates are finite in [0,1]"
              ( all
                  (\s -> finite (herIterSuccessRate s) && herIterSuccessRate s >= 0 && herIterSuccessRate s <= 1)
                  (herResultStats r1)
              )
            map herIterSuccessRate (herResultStats r1)
              @?= map herIterSuccessRate (herResultStats r2)
      , testCase
          "linux-cpu continuous actor-critic (DDPG) trains through the batched device path (Phase 4 rebalance)"
          $ do
            env <- buildEnv defaultGlobalFlags
            let config =
                  (defaultContinuousTrainConfig VariantDDPG)
                    { ctNumSteps = 400
                    , ctTrainStart = 100
                    , ctStartSteps = 100
                    , ctBatchSize = 16
                    , ctHidden = 16
                    , ctStatInterval = 200
                    }
                finite x = not (isNaN x) && not (isInfinite x)
            r1 <- trainContinuousOnPendulumOneDnn env config >>= expectRight "oneDNN continuous trainer failed"
            r2 <- trainContinuousOnPendulumOneDnn env config >>= expectRight "oneDNN continuous trainer failed"
            assertBool
              "continuous run produced at least one interval stat"
              (not (null (contResultStats r1)))
            assertBool
              "per-interval mean rewards are finite"
              (all (finite . contIterMeanReward) (contResultStats r1))
            map contIterMeanReward (contResultStats r1)
              @?= map contIterMeanReward (contResultStats r2)
      , testCase
          "linux-cpu AlphaZero PolicyValueNet trains on the device and reduces loss (Phase 4 rebalance)"
          $ do
            env <- buildEnv defaultGlobalFlags
            let net0 = PVN.initPolicyValueNet 43 7 16 22
                adam0 = PVN.initAdamFor net0
                target = VU.fromList [0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0]
                sample =
                  PVN.PolicyValueTrainingSample
                    { PVN.sampleState = initialConnect4
                    , PVN.sampleVisitDist = target
                    , PVN.sampleOutcome = 0.5
                    }
                logSafe x = if x <= 0 then -1.0e9 else log x
                lossOf net =
                  let pv = PVN.networkPolicyValue net (PVN.sampleState sample)
                      policy = PVN.pvPolicy pv
                      policyLoss =
                        negate
                          ( sum
                              [ (PVN.sampleVisitDist sample VU.! i) * logSafe (policy VU.! i)
                              | i <- [0 .. VU.length policy - 1]
                              ]
                          )
                      valueLoss = 0.5 * (PVN.pvValue pv - PVN.sampleOutcome sample) ^ (2 :: Int)
                   in policyLoss + valueLoss
            trained <- PVN.trainPolicyValueNetOnSamplesOneDnn env net0 adam0 1.0e-2 80 [sample]
            case trained of
              Left message ->
                assertBool ("PolicyValueNet oneDNN training failed: " <> Text.unpack message) False
              Right (netN, _) ->
                assertBool
                  "device-trained policy/value loss should decrease"
                  (lossOf netN < lossOf net0)
      , -- Metal MLP: validated in the host-native apple-silicon lane.
        testCase
          "apple-silicon batched MLP gradient is bit-identical to the aligned float32 oracle (Phase 271)"
          $ do
            env <- buildEnv defaultGlobalFlags
            let shape = MlpShape {mlpInputs = 16, mlpHidden = 64, mlpOutputs = 8}
                params = mlpInit shape 11
                sample b =
                  ( VU.generate 16 $ \j ->
                      sin (fromIntegral (b * 16 + j) * 0.37) * 1.5
                  , VU.generate 8 $ \k ->
                      cos (fromIntegral (b * 8 + k) * 0.21) * 0.5
                  )
                batch = [sample b | b <- [0 .. 31 :: Int]]
                oracle = mlpBatchGradientAlignedFloat params batch
            metal <- mlpBatchGradientMetal env params batch
            case metal of
              Right gradient -> do
                gradW1 gradient @?= gradW1 oracle
                gradB1 gradient @?= gradB1 oracle
                gradW2 gradient @?= gradW2 oracle
                gradB2 gradient @?= gradB2 oracle
              Left message ->
                assertFailure ("apple-silicon batched gradient failed: " <> Text.unpack message)
      , testCase
          "apple-silicon MLP source renders the lane-aligned activation (Phase 271)"
          $ do
            let rendered =
                  Text.concat
                    [ contents
                    | SourceFile _ contents <- MlpMetalCodegen.renderMlpMetalSource
                    ]
            assertBool
              "the MLP Metal source defines the aligned activation"
              (("inline float " <> MlpMetalCodegen.mlpMetalActivation) `Text.isInfixOf` rendered)
            assertBool
              "the MLP Metal source calls the aligned activation"
              ((MlpMetalCodegen.mlpMetalActivation <> "(acc)") `Text.isInfixOf` rendered)
            assertBool
              "the MLP Metal source disables floating-point contraction"
              ("#pragma clang fp contract(off)" `Text.isInfixOf` rendered)
            assertBool
              "no MLP Metal call site uses MSL's native tanh"
              (not ("= tanh(" `Text.isInfixOf` rendered))
      , testCase
          "apple-silicon MLP forward kernel matches the pure-Haskell network (Phase 4 rebalance)"
          $ do
            env <- buildEnv defaultGlobalFlags
            let shape = MlpShape {mlpInputs = 4, mlpHidden = 6, mlpOutputs = 3}
                params = mlpInit shape 5
                input = VU.fromList [0.5, -0.25, 1.0, -0.75]
                refForward = mlpForward params input
            result <- mlpForwardMetal env params input
            case result of
              Left message ->
                assertBool ("MLP forward Metal run failed: " <> Text.unpack message) False
              Right fwd -> do
                assertBool
                  "Metal hidden_act within tolerance of reference"
                  (approxEqualVec 1.0e-3 (forwardHiddenAct fwd) (forwardHiddenAct refForward))
                assertBool
                  "Metal output within tolerance of reference"
                  (approxEqualVec 1.0e-3 (forwardOutput fwd) (forwardOutput refForward))
      , testCase
          "apple-silicon MLP backward kernel matches the pure-Haskell gradient (Phase 4 rebalance)"
          $ do
            env <- buildEnv defaultGlobalFlags
            let shape = MlpShape {mlpInputs = 4, mlpHidden = 6, mlpOutputs = 3}
                params = mlpInit shape 5
                input = VU.fromList [0.5, -0.25, 1.0, -0.75]
                refForward = mlpForward params input
                dLdy = VU.fromList [0.2, -0.4, 0.6]
                refGrad = mlpBackward params refForward dLdy
            result <- mlpBackwardMetal env params refForward dLdy
            case result of
              Left message ->
                assertBool ("MLP backward Metal run failed: " <> Text.unpack message) False
              Right grad -> do
                assertBool
                  "Metal gradW1 within tolerance of reference"
                  (approxEqualVec 1.0e-3 (gradW1 grad) (gradW1 refGrad))
                assertBool
                  "Metal gradW2 within tolerance of reference"
                  (approxEqualVec 1.0e-3 (gradW2 grad) (gradW2 refGrad))
      , testCase
          "apple-silicon MLP kernels are bit-deterministic across repeated runs (Phase 4 rebalance)"
          $ do
            env <- buildEnv defaultGlobalFlags
            let shape = MlpShape {mlpInputs = 4, mlpHidden = 6, mlpOutputs = 3}
                params = mlpInit shape 5
                input = VU.fromList [0.5, -0.25, 1.0, -0.75]
            first <- mlpForwardMetal env params input
            second <- mlpForwardMetal env params input
            case (first, second) of
              (Right a, Right b) -> do
                forwardOutput a @?= forwardOutput b
                forwardHiddenAct a @?= forwardHiddenAct b
              _ -> assertBool "both MLP forward Metal runs succeed" False
      , testCase
          "apple-silicon batched MLP gradient matches the pure summed gradient (Phase 4 rebalance)"
          $ do
            env <- buildEnv defaultGlobalFlags
            let shape = MlpShape {mlpInputs = 4, mlpHidden = 6, mlpOutputs = 3}
                params = mlpInit shape 5
                batch =
                  [ (VU.fromList [0.5, -0.25, 1.0, -0.75], VU.fromList [0.2, -0.4, 0.6])
                  , (VU.fromList [-0.1, 0.3, -0.5, 0.2], VU.fromList [-0.3, 0.5, 0.1])
                  , (VU.fromList [0.9, 0.1, -0.2, 0.4], VU.fromList [0.05, -0.15, 0.25])
                  ]
                perSample (i, dy) = mlpBackward params (mlpForward params i) dy
                sumGrad a b =
                  MlpGradient
                    { gradW1 = VU.zipWith (+) (gradW1 a) (gradW1 b)
                    , gradB1 = VU.zipWith (+) (gradB1 a) (gradB1 b)
                    , gradW2 = VU.zipWith (+) (gradW2 a) (gradW2 b)
                    , gradB2 = VU.zipWith (+) (gradB2 a) (gradB2 b)
                    }
                refGrad = foldl1 sumGrad (map perSample batch)
            result <- mlpBatchGradientMetal env params batch
            case result of
              Right g ->
                assertBool
                  "batched Metal gradW1 within tolerance of the pure summed gradient"
                  (approxEqualVec 1.0e-3 (gradW1 g) (gradW1 refGrad))
              Left e -> assertBool ("Metal batched gradient failed: " <> Text.unpack e) False
      , testCase
          "apple-silicon batched MLP forward matches the pure per-sample forward (Phase 4 rebalance)"
          $ do
            env <- buildEnv defaultGlobalFlags
            let shape = MlpShape {mlpInputs = 4, mlpHidden = 6, mlpOutputs = 3}
                params = mlpInit shape 5
                inputs =
                  [ VU.fromList [0.5, -0.25, 1.0, -0.75]
                  , VU.fromList [-0.1, 0.3, -0.5, 0.2]
                  ]
                refOutputs = map (forwardOutput . mlpForward params) inputs
            result <- mlpForwardBatchMetal env params inputs
            case result of
              Right outs ->
                assertBool
                  "each batched Metal forward output is within tolerance of the pure forward"
                  (length outs == length inputs && and (zipWith (approxEqualVec 1.0e-3) outs refOutputs))
              Left e -> assertBool ("Metal batched forward failed: " <> Text.unpack e) False
      , testCase
          "apple-silicon batched MLP input-gradient matches the pure mlpInputGradient (Phase 4 rebalance)"
          $ do
            env <- buildEnv defaultGlobalFlags
            let shape = MlpShape {mlpInputs = 4, mlpHidden = 6, mlpOutputs = 3}
                params = mlpInit shape 5
                batch =
                  [ (VU.fromList [0.5, -0.25, 1.0, -0.75], VU.fromList [0.2, -0.4, 0.6])
                  , (VU.fromList [-0.1, 0.3, -0.5, 0.2], VU.fromList [-0.3, 0.5, 0.1])
                  ]
                refDx (i, dy) = mlpInputGradient params (mlpForward params i) dy
                refs = map refDx batch
            result <- mlpInputGradientBatchMetal env params batch
            case result of
              Right dxs ->
                assertBool
                  "each batched Metal dL/dx is within tolerance of the pure mlpInputGradient"
                  (length dxs == length batch && and (zipWith (approxEqualVec 1.0e-3) dxs refs))
              Left e -> assertBool ("Metal batched input-gradient failed: " <> Text.unpack e) False
      , -- Metal RL trainers: validated through the batched fixed-bridge MLP path.
        testCase
          "apple-silicon on-policy PPO trainer trains through the batched device path (Phase 4 rebalance)"
          $ do
            env <- buildEnv defaultGlobalFlags
            let config =
                  defaultPpoTrainConfig
                    { ppoNumIterations = 3
                    , ppoRolloutSteps = 128
                    , ppoEpochsPerUpdate = 2
                    , ppoMiniBatchSize = 32
                    , ppoHiddenUnits = 16
                    }
                finite x = not (isNaN x) && not (isInfinite x)
            r1 <- trainOnPolicyOnCartpoleMetal env VariantPPO config
            r2 <- trainOnPolicyOnCartpoleMetal env VariantPPO config
            case (r1, r2) of
              (Right res1, Right res2) -> do
                length (resultIterations res1) @?= 3
                assertBool
                  "per-iteration mean rewards are finite"
                  (all (finite . iterMeanReward) (resultIterations res1))
                map iterMeanReward (resultIterations res1)
                  @?= map iterMeanReward (resultIterations res2)
              (Left e, _) ->
                assertBool ("Metal on-policy trainer failed: " <> Text.unpack e) False
              _ -> assertBool "both Metal on-policy trainer runs succeed" False
      , testCase
          "apple-silicon DQN trainer trains through the batched device path (Phase 4 rebalance)"
          $ do
            env <- buildEnv defaultGlobalFlags
            let config =
                  defaultDqnTrainConfig
                    { dqnNumSteps = 600
                    , dqnTrainStart = 100
                    , dqnBatchSize = 16
                    , dqnHiddenUnits = 16
                    , dqnStatInterval = 200
                    , dqnTargetUpdateInterval = 200
                    }
                finite x = not (isNaN x) && not (isInfinite x)
            r1 <- trainDqnOnCartpoleMetal env config >>= expectRight "Metal DQN trainer failed"
            r2 <- trainDqnOnCartpoleMetal env config >>= expectRight "Metal DQN trainer failed"
            assertBool
              "DQN run produced at least one interval stat"
              (not (null (dqnResultStats r1)))
            assertBool
              "per-interval mean rewards are finite"
              (all (finite . dqnIterMeanReward) (dqnResultStats r1))
            map dqnIterMeanReward (dqnResultStats r1)
              @?= map dqnIterMeanReward (dqnResultStats r2)
      , testCase
          "apple-silicon QR-DQN trainer trains through the batched device path (Phase 4 rebalance)"
          $ do
            env <- buildEnv defaultGlobalFlags
            let config =
                  defaultQrDqnTrainConfig
                    { qrNumSteps = 600
                    , qrTrainStart = 100
                    , qrBatchSize = 16
                    , qrHiddenUnits = 16
                    , qrNumQuantiles = 4
                    , qrStatInterval = 200
                    , qrTargetUpdateInterval = 200
                    }
                finite x = not (isNaN x) && not (isInfinite x)
            r1 <- trainQrDqnOnCartpoleMetal env config >>= expectRight "Metal QR-DQN trainer failed"
            r2 <- trainQrDqnOnCartpoleMetal env config >>= expectRight "Metal QR-DQN trainer failed"
            assertBool
              "QR-DQN run produced at least one interval stat"
              (not (null (qrResultStats r1)))
            assertBool
              "per-interval mean rewards are finite"
              (all (finite . qrIterMeanReward) (qrResultStats r1))
            map qrIterMeanReward (qrResultStats r1)
              @?= map qrIterMeanReward (qrResultStats r2)
      , testCase
          "apple-silicon HER trainer trains through the batched device path (Phase 4 rebalance)"
          $ do
            env <- buildEnv defaultGlobalFlags
            let config =
                  defaultHerTrainConfig
                    { herNumBits = 4
                    , herEpisodes = 60
                    , herHiddenUnits = 16
                    , herBatchSize = 16
                    , herStatInterval = 20
                    , herTargetUpdateInterval = 20
                    }
                finite x = not (isNaN x) && not (isInfinite x)
            r1 <- trainHerOnBitFlipMetal env config >>= expectRight "Metal HER trainer failed"
            r2 <- trainHerOnBitFlipMetal env config >>= expectRight "Metal HER trainer failed"
            assertBool
              "HER run produced at least one interval stat"
              (not (null (herResultStats r1)))
            assertBool
              "per-interval success rates are finite in [0,1]"
              ( all
                  (\s -> finite (herIterSuccessRate s) && herIterSuccessRate s >= 0 && herIterSuccessRate s <= 1)
                  (herResultStats r1)
              )
            map herIterSuccessRate (herResultStats r1)
              @?= map herIterSuccessRate (herResultStats r2)
      , testCase
          "apple-silicon continuous actor-critic (DDPG) trains through the batched device path (Phase 4 rebalance)"
          $ do
            env <- buildEnv defaultGlobalFlags
            let config =
                  (defaultContinuousTrainConfig VariantDDPG)
                    { ctNumSteps = 400
                    , ctTrainStart = 100
                    , ctStartSteps = 100
                    , ctBatchSize = 16
                    , ctHidden = 16
                    , ctStatInterval = 200
                    }
                finite x = not (isNaN x) && not (isInfinite x)
            r1 <- trainContinuousOnPendulumMetal env config >>= expectRight "Metal continuous trainer failed"
            r2 <- trainContinuousOnPendulumMetal env config >>= expectRight "Metal continuous trainer failed"
            assertBool
              "continuous run produced at least one interval stat"
              (not (null (contResultStats r1)))
            assertBool
              "per-interval mean rewards are finite"
              (all (finite . contIterMeanReward) (contResultStats r1))
            map contIterMeanReward (contResultStats r1)
              @?= map contIterMeanReward (contResultStats r2)
      , testCase
          "apple-silicon AlphaZero PolicyValueNet trains on the device and reduces loss (Phase 4 rebalance)"
          $ do
            env <- buildEnv defaultGlobalFlags
            let net0 = PVN.initPolicyValueNet 43 7 16 22
                adam0 = PVN.initAdamFor net0
                target = VU.fromList [0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0]
                sample =
                  PVN.PolicyValueTrainingSample
                    { PVN.sampleState = initialConnect4
                    , PVN.sampleVisitDist = target
                    , PVN.sampleOutcome = 0.5
                    }
                logSafe x = if x <= 0 then -1.0e9 else log x
                lossOf net =
                  let pv = PVN.networkPolicyValue net (PVN.sampleState sample)
                      policy = PVN.pvPolicy pv
                      policyLoss =
                        negate
                          ( sum
                              [ (PVN.sampleVisitDist sample VU.! i) * logSafe (policy VU.! i)
                              | i <- [0 .. VU.length policy - 1]
                              ]
                          )
                      valueLoss = 0.5 * (PVN.pvValue pv - PVN.sampleOutcome sample) ^ (2 :: Int)
                   in policyLoss + valueLoss
            trained <- PVN.trainPolicyValueNetOnSamplesMetal env net0 adam0 1.0e-2 80 [sample]
            case trained of
              Left message ->
                assertBool ("PolicyValueNet Metal training failed: " <> Text.unpack message) False
              Right (netN, _) ->
                assertBool
                  "device-trained policy/value loss should decrease"
                  (lossOf netN < lossOf net0)
      ]

-- | Elementwise approximate equality for two unboxed Double vectors.
approxEqualVec :: Double -> VU.Vector Double -> VU.Vector Double -> Bool
approxEqualVec tol a b =
  VU.length a == VU.length b
    && VU.and (VU.zipWith (\x y -> abs (x - y) <= tol) a b)

assertLayerGraphGradientClose
  :: Double -> LayerGraph.LayerGraphGradient -> LayerGraph.LayerGraphGradient -> IO ()
assertLayerGraphGradientClose tol actual expected = do
  assertBool
    "LayerGraph input gradient within tolerance"
    ( approxEqualVec
        tol
        (LayerGraph.layerGraphInputGradient actual)
        (LayerGraph.layerGraphInputGradient expected)
    )
  let actualLayers = LayerGraph.layerGraphLayerGradients actual
      expectedLayers = LayerGraph.layerGraphLayerGradients expected
  length actualLayers @?= length expectedLayers
  for_ (zip [0 :: Int ..] (zip actualLayers expectedLayers)) $ \(idx, (actualLayer, expectedLayer)) -> do
    LayerGraph.layerGradientName actualLayer @?= LayerGraph.layerGradientName expectedLayer
    assertBool
      ("LayerGraph layer " <> show idx <> " input gradient within tolerance")
      ( approxEqualVec
          tol
          (LayerGraph.layerGradientInput actualLayer)
          (LayerGraph.layerGradientInput expectedLayer)
      )
    case ( LayerGraph.layerGradientParameters actualLayer
         , LayerGraph.layerGradientParameters expectedLayer
         ) of
      (Nothing, Nothing) -> pure ()
      (Just actualParams, Just expectedParams) -> do
        assertBool
          ("LayerGraph layer " <> show idx <> " weight gradient within tolerance")
          ( approxEqualVec
              tol
              (LayerGraph.layerGradWeights actualParams)
              (LayerGraph.layerGradWeights expectedParams)
          )
        assertBool
          ("LayerGraph layer " <> show idx <> " bias gradient within tolerance")
          ( approxEqualVec
              tol
              (LayerGraph.layerGradBias actualParams)
              (LayerGraph.layerGradBias expectedParams)
          )
      _ -> assertFailure ("LayerGraph layer " <> show idx <> " parameter-gradient shape mismatch")

-- | Component-wise sum of two structurally-identical layer-graph gradients (the
-- per-example summed oracle the batched device gradient must reproduce).
addLayerGraphGradient
  :: LayerGraph.LayerGraphGradient -> LayerGraph.LayerGraphGradient -> LayerGraph.LayerGraphGradient
addLayerGraphGradient a b =
  a
    { LayerGraph.layerGraphInputGradient =
        VU.zipWith (+) (LayerGraph.layerGraphInputGradient a) (LayerGraph.layerGraphInputGradient b)
    , LayerGraph.layerGraphLayerGradients =
        zipWith
          addLayerGradient
          (LayerGraph.layerGraphLayerGradients a)
          (LayerGraph.layerGraphLayerGradients b)
    }

addLayerGradient
  :: LayerGraph.LayerGradient -> LayerGraph.LayerGradient -> LayerGraph.LayerGradient
addLayerGradient a b =
  a
    { LayerGraph.layerGradientInput =
        VU.zipWith (+) (LayerGraph.layerGradientInput a) (LayerGraph.layerGradientInput b)
    , LayerGraph.layerGradientParameters =
        case ( LayerGraph.layerGradientParameters a
             , LayerGraph.layerGradientParameters b
             ) of
          (Just pa, Just pb) ->
            Just
              LayerGraph.LayerParameterGradient
                { LayerGraph.layerGradWeights =
                    VU.zipWith (+) (LayerGraph.layerGradWeights pa) (LayerGraph.layerGradWeights pb)
                , LayerGraph.layerGradBias =
                    VU.zipWith (+) (LayerGraph.layerGradBias pa) (LayerGraph.layerGradBias pb)
                }
          _ -> LayerGraph.layerGradientParameters a
    }

-- | Phase 241 per-operator device-vs-oracle check: build a single-node graph
-- from a correct-operator node, take the pure oracle forward + backward
-- (@runLayerGraph@ + @backwardLayerGraph@), run the operator's device training
-- kernel via @runDeviceOp@, and assert @out / dInput / dWeights / dBias@ all
-- agree within float32 tolerance (1e-3).
assertDeviceOpOracle
  :: Env -> String -> LayerGraph.LayerNode -> VU.Vector Double -> VU.Vector Double -> IO ()
assertDeviceOpOracle env =
  assertDeviceNodeOracle
    1.0e-3
    ( \node input dY -> LayerGraphDevice.withCompiledLayerGraphDevice Substrate.LinuxCPU env $ \functions _ _ _ -> LayerGraphDevice.runDeviceOp functions node input dY
    )

-- | Phase 241/242 per-block device-vs-oracle check: the same single-node
-- device-vs-oracle contract as 'assertDeviceOpOracle' but driven through
-- 'LayerGraphDevice.runDeviceBlock' (the on-device composition of the block's
-- affine + norm sub-kernels). Slightly looser tolerance to absorb the float32
-- error accumulated across the composed sub-kernels.
assertDeviceBlockOracle
  :: Env -> String -> LayerGraph.LayerNode -> VU.Vector Double -> VU.Vector Double -> IO ()
assertDeviceBlockOracle env =
  assertDeviceNodeOracle
    2.0e-3
    ( \node input dY -> LayerGraphDevice.withCompiledLayerGraphDevice Substrate.LinuxCPU env $ \functions _ _ _ -> LayerGraphDevice.runDeviceBlock functions node input dY
    )

-- | Build a single-node graph from a correct-operator node, take the pure oracle
-- forward + backward (@runLayerGraph@ + @backwardLayerGraph@), run the operator's
-- device training path via @deviceRun@, and assert @out / dInput / dWeights /
-- dBias@ all agree within @tol@.
assertDeviceNodeOracle
  :: Double
  -> ( LayerGraph.LayerNode
       -> VU.Vector Double
       -> VU.Vector Double
       -> IO (Either Text.Text (VU.Vector Double, VU.Vector Double, VU.Vector Double, VU.Vector Double))
     )
  -> String
  -> LayerGraph.LayerNode
  -> VU.Vector Double
  -> VU.Vector Double
  -> IO ()
assertDeviceNodeOracle tol deviceRun label node input dY = do
  let graph =
        LayerGraph.LayerGraph
          { LayerGraph.layerGraphName = Text.pack label
          , LayerGraph.layerGraphInputShape = LayerGraph.layerInputShape node
          , LayerGraph.layerGraphOutputShape = LayerGraph.layerOutputShape node
          , LayerGraph.layerGraphNodes = [node]
          }
  tape <-
    either (assertFailure . Text.unpack) pure (LayerGraph.runLayerGraph graph input)
  grad <-
    either (assertFailure . Text.unpack) pure (LayerGraph.backwardLayerGraph graph tape dY)
  let pureOut = LayerGraph.layerTapeOutput tape
      pureDx = LayerGraph.layerGraphInputGradient grad
  (pureDw, pureDb) <-
    case LayerGraph.layerGraphLayerGradients grad of
      [lg]
        | Just pg <- LayerGraph.layerGradientParameters lg ->
            pure (LayerGraph.layerGradWeights pg, LayerGraph.layerGradBias pg)
      _ -> assertFailure (label <> ": expected exactly one parameterized gradient")
  deviceResult <- deviceRun node input dY
  (devOut, devDx, devDw, devDb) <-
    either (assertFailure . Text.unpack) pure deviceResult
  let close what a b =
        assertBool
          ( label
              <> " "
              <> what
              <> ": device/oracle mismatch\n device="
              <> show (VU.toList a)
              <> "\n oracle="
              <> show (VU.toList b)
          )
          ( VU.length a == VU.length b
              && VU.and (VU.zipWith (\x y -> abs (x - y) <= tol) a b)
          )
  close "forward output" devOut pureOut
  close "input gradient" devDx pureDx
  close "weight gradient" devDw pureDw
  close "bias gradient" devDb pureDb

-- | One width-4-preserving node per declared 'LayerGraph.LayerKind', each built
-- from the operator that actually executes that kind. Sprint `72.1` derives a
-- node's kind from its operator, so a fixture can no longer tag a dense affine
-- as a convolution and then assert that a convolution primitive ran: every kind
-- here is backed by its real operator.
layerGraphDeviceFixture :: Either Text.Text LayerGraph.LayerGraph
layerGraphDeviceFixture = do
  nodes <- traverse fixtureNode (zip [1 :: Int ..] deviceSupportedLayerKinds)
  pure
    LayerGraph.LayerGraph
      { LayerGraph.layerGraphName = "backend-layergraph-all-kinds"
      , LayerGraph.layerGraphInputShape = LayerGraph.TensorShape [4]
      , LayerGraph.layerGraphOutputShape = LayerGraph.TensorShape [4]
      , LayerGraph.layerGraphNodes = nodes
      }

-- | Build the fixture node for one declared kind at the fixture width.
fixtureNode :: (Int, LayerGraph.LayerKind) -> Either Text.Text LayerGraph.LayerNode
fixtureNode (idx, kind) =
  case kind of
    LayerGraph.DenseLayer ->
      LayerGraph.mkAffineLayer name 4 4 activation mode (LayerGraph.deterministicParameters seed 4 4)
    LayerGraph.IdentityLayer -> LayerGraph.mkIdentityLayer name 4 mode
    LayerGraph.DropoutLayer rate -> LayerGraph.mkDropoutLayer name rate 4 mode
    LayerGraph.Conv2DLayer -> conv LayerGraph.mkConvLayer [2, 2]
    LayerGraph.Conv3DLayer -> conv LayerGraph.mkConv3DLayer [1, 2, 2]
    LayerGraph.PoolLayer LayerGraph.MaxPool ->
      LayerGraph.mkPoolLayer name (LayerGraph.SpatialShape 1 2 2) (LayerGraph.PoolMax window) mode
    LayerGraph.PoolLayer LayerGraph.AvgPool ->
      LayerGraph.mkPoolLayer name (LayerGraph.SpatialShape 1 2 2) (LayerGraph.PoolAvg window) mode
    LayerGraph.PoolLayer LayerGraph.GlobalAvgPool ->
      LayerGraph.mkPoolLayer name (LayerGraph.SpatialShape 4 1 1) LayerGraph.PoolGlobal mode
    LayerGraph.NormLayer LayerGraph.BatchNorm -> norm LayerGraph.NormBatch
    LayerGraph.NormLayer LayerGraph.LayerNorm -> norm LayerGraph.NormLayerWise
    LayerGraph.NormLayer (LayerGraph.GroupNorm groups) -> norm (LayerGraph.NormGroup groups)
    LayerGraph.MultiHeadAttentionLayer heads ->
      let spec = LayerGraph.AttentionSpec 2 2 (max 1 (min 2 heads)) False
       in LayerGraph.mkAttentionLayer name spec mode (opParams (LayerGraph.AttentionOp spec))
    LayerGraph.GeGLULayer ->
      let spec = LayerGraph.GeGLUSpec 4 4 4
       in LayerGraph.mkGeGLULayer name spec mode (opParams (LayerGraph.GeGLUOp spec))
    LayerGraph.PatchEmbedLayer ->
      let spec = LayerGraph.PatchSpec 1 2 2 1 1 1
       in LayerGraph.mkPatchEmbedLayer name spec mode (opParams (LayerGraph.PatchOp spec))
    LayerGraph.ResidualLayer scale ->
      let inner = LayerGraph.AffineSpec 4 4
          op =
            LayerGraph.ResidualOp
              inner
              LayerGraph.IdentityShortcut
              scale
              LayerGraph.TanhActivation
       in LayerGraph.mkResidualNode
            name
            inner
            LayerGraph.IdentityShortcut
            scale
            LayerGraph.TanhActivation
            activation
            mode
            (opParams op)
    LayerGraph.BasicBlockLayer scale -> block LayerGraph.mkBasicBlock False scale
    LayerGraph.BottleneckBlockLayer scale -> block LayerGraph.mkBottleneck True scale
 where
  seed = 100 + idx
  mode = LayerGraph.TrainingMode
  activation = layerGraphDeviceActivation kind
  name = "backend-layer-" <> Text.pack (show idx) <> "-" <> LayerGraph.layerKindName kind
  window = LayerGraph.PoolWindow 1 1 1 1 0 0 False
  opParams = LayerGraph.deterministicOpParameters seed
  conv build dims =
    let spec = fixtureConvSpec dims
     in build name spec activation mode (opParams (LayerGraph.ConvOp spec))
  norm flavor =
    let spec = LayerGraph.NormSpec flavor 4 1 1.0e-5
     in LayerGraph.mkNormLayer name spec mode (opParams (LayerGraph.NormOp spec))
  block build bottleneck scale =
    let spec = fixtureBlockSpec bottleneck scale
     in build name spec mode (opParams (LayerGraph.BlockOp spec))

fixtureConvSpec :: [Int] -> LayerGraph.ConvSpec
fixtureConvSpec dims =
  LayerGraph.ConvSpec
    { LayerGraph.convIn = 1
    , LayerGraph.convOut = 1
    , LayerGraph.convInputDims = dims
    , LayerGraph.convKernelDims = fmap (const 1) dims
    , LayerGraph.convStride = fmap (const 1) dims
    , LayerGraph.convPadding = fmap (const 0) dims
    }

fixtureBlockSpec :: Bool -> Double -> LayerGraph.BlockSpec
fixtureBlockSpec bottleneck scale =
  LayerGraph.BlockSpec
    ( if bottleneck
        then
          [ LayerGraph.BlockStage (LayerGraph.AffineSpec 4 2) Nothing LayerGraph.ReluActivation
          , LayerGraph.BlockStage (LayerGraph.AffineSpec 2 4) Nothing LayerGraph.ReluActivation
          ]
        else
          [ LayerGraph.BlockStage (LayerGraph.AffineSpec 4 4) Nothing LayerGraph.ReluActivation
          , LayerGraph.BlockStage (LayerGraph.AffineSpec 4 4) Nothing LayerGraph.ReluActivation
          ]
    )
    LayerGraph.IdentityShortcut
    scale
    LayerGraph.ReluActivation

layerGraphDeviceActivation :: LayerGraph.LayerKind -> LayerGraph.LayerActivation
layerGraphDeviceActivation kind =
  case kind of
    LayerGraph.DenseLayer -> LayerGraph.TanhActivation
    LayerGraph.Conv2DLayer -> LayerGraph.TanhActivation
    LayerGraph.Conv3DLayer -> LayerGraph.TanhActivation
    _ -> LayerGraph.LinearActivation

-- | The declared kinds the layer-graph oneDNN path has a real device kernel
-- for. Phase `241` made the lowering total, so this is the whole declared
-- vocabulary: 3-D convolution gained its own oneDNN primitive triple, and the
-- parameterless operators (pooling, dropout, identity) execute on the device
-- instead of falling back to the pure executor that is supposed to be their
-- oracle.
deviceSupportedLayerKinds :: [LayerGraph.LayerKind]
deviceSupportedLayerKinds = LayerGraph.allLayerKinds

-- | A single-node graph holding a real 3-D convolution, used to prove the
-- device path rejects it instead of silently running another primitive.
layerGraphConv3DFixture :: Either Text.Text LayerGraph.LayerGraph
layerGraphConv3DFixture = do
  node <- fixtureNode (1, LayerGraph.Conv3DLayer)
  pure
    LayerGraph.LayerGraph
      { LayerGraph.layerGraphName = "backend-layergraph-conv3d"
      , LayerGraph.layerGraphInputShape = LayerGraph.TensorShape [4]
      , LayerGraph.layerGraphOutputShape = LayerGraph.TensorShape [4]
      , LayerGraph.layerGraphNodes = [node]
      }

assertFamilySmoke :: Env -> KernelFamily -> IO ()
assertFamilySmoke env family = do
  result <- runLinuxCpuFamilyKernel env family [4.0, -2.0, 1.0, 3.0]
  case result of
    Left message ->
      assertBool
        ("linux-cpu family JIT run failed for " <> show (familyName family) <> ": " <> show message)
        False
    Right kernelRun -> do
      linuxCpuKernelReportedFamily kernelRun @?= familyName family
      assertBool
        ("linux-cpu family output is nonempty for " <> show (familyName family))
        (not (null (linuxCpuKernelOutput kernelRun)))
      assertBool
        ("linux-cpu family output is finite for " <> show (familyName family))
        (all finiteFloat (linuxCpuKernelOutput kernelRun))
      -- Sprint 80.1 — the unweighted ABI is checked against the semantics
      -- contract (the weighted reference at the family's canonical no-op
      -- weights), not merely smoke-asserted. The absence of this check is why
      -- the linux-cpu attention body was able to disagree with the other two
      -- lanes for as long as it did.
      assertUnweightedMatchesContract
        "linux-cpu unweighted"
        family
        [4.0, -2.0, 1.0, 3.0]
        (linuxCpuKernelOutput kernelRun)

finiteFloat :: Float -> Bool
finiteFloat value =
  not (isNaN value) && not (isInfinite value)

assertOneDnnOutput :: Env -> KernelFamily -> [Float] -> [Float] -> IO ()
assertOneDnnOutput env family input expected = do
  result <- runLinuxCpuFamilyKernel env family input
  case result of
    Left message ->
      assertBool
        ("oneDNN primitive run failed for " <> show (familyName family) <> ": " <> show message)
        False
    Right kernelRun -> do
      linuxCpuKernelReportedFamily kernelRun @?= familyName family
      linuxCpuKernelOutput kernelRun @?= expected

-- | Representative weighted-family fixtures whose inputs/weights exercise
-- non-trivial values per family. Shared across every substrate lane so all
-- three backends are checked for the same numeric correctness, not merely
-- run-to-run determinism. Weight buffers follow each family's ABI:
-- Dense2D row-major n*n; Conv2D 3x3; Conv3D 3x3x3;
-- BatchNorm [scale,shift,mean,var];
-- LayerNorm [scale,shift]; Embedding row-major rows*n table; MHA [Wq,Wk,Wv].
weightedFamilyFixtures :: [(KernelFamily, [Float], [Float])]
weightedFamilyFixtures =
  [ (Dense2D, [1.0, 2.0, 3.0], [1, 0, 0, 0, 2, 0, 0, 0, 3])
  , (Conv2DKernel, [1.0 .. 9.0], [0, 1, 0, 1, 2, 1, 0, 1, 0])
  , (Conv3DKernel, [1.0 .. 8.0], [if i == 13 then 2.0 else 1.0 | i <- [0 :: Int .. 26]])
  ,
    ( BatchNormKernel
    , [0.5, 1.5, 2.5, 3.5]
    , [1, 1, 1, 1, 0.1, 0.1, 0.1, 0.1, 0.0, 1.0, 2.0, 3.0, 1, 1, 1, 1]
    )
  , (LayerNormKernel, [0.5, 1.5, 2.5, 3.5], [1, 1, 1, 1, 0, 0, 0, 0])
  ,
    ( EmbeddingKernel
    , [0, 1, 2, 3]
    , [10, 11, 12, 13, 20, 21, 22, 23, 30, 31, 32, 33, 40, 41, 42, 43]
    )
  , (MultiHeadAttentionKernel, [1.0, 2.0], [1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1])
  ]

-- | Assert a backend kernel's weighted-family output matches the pure
-- 'familyReference' oracle within single-precision tolerance. The reference is
-- computed in Double; the kernel runs in Float, so agreement is asserted within
-- 1e-3 (the same band the MLP device tests use). This is a within-lane
-- backend-vs-oracle correctness check — not a cross-substrate parity assertion.
-- | The unweighted ABI's oracle: a lane's unweighted kernel must equal the
-- weighted reference evaluated at the family's canonical no-op weights.
assertUnweightedMatchesContract :: Text.Text -> KernelFamily -> [Float] -> [Float] -> IO ()
assertUnweightedMatchesContract label family input actual =
  assertBool
    ( Text.unpack label
        <> ": "
        <> show family
        <> " unweighted output "
        <> show actual
        <> " must match the semantics contract "
        <> show expected
        <> " within 1e-3"
    )
    ( length actual == length expected
        && approxEqualVec
          1.0e-3
          (VU.fromList (map realToFrac actual))
          (VU.fromList (map realToFrac expected))
    )
 where
  expected = unweightedFamilyReference family input

assertWeightedMatchesReference
  :: Text.Text -> KernelFamily -> [Float] -> [Float] -> [Float] -> IO ()
assertWeightedMatchesReference label family input weights actual =
  assertBool
    ( Text.unpack label
        <> ": "
        <> show family
        <> " kernel output "
        <> show actual
        <> " must match the pure reference "
        <> show expected
        <> " within 1e-3"
    )
    ( length actual == length expected
        && approxEqualVec
          1.0e-3
          (VU.fromList (map realToFrac actual))
          (VU.fromList (map realToFrac expected))
    )
 where
  expected = familyReference family input weights

-- | Exact Float oracle for the batched MLP parameter-gradient ABI. The loop
-- nesting and accumulation order mirror MlpOneDnn/MlpCuda/MlpMetal, while the
-- activation below mirrors the glibc flt-32 operation sequence rendered by the
-- two GPU lanes. Keeping this oracle host-local lets the Apple lane make the
-- bit-identity assertion without installing oneDNN on the Mac host.
mlpBatchGradientAlignedFloat
  :: MlpParams -> [(VU.Vector Double, VU.Vector Double)] -> MlpGradient
mlpBatchGradientAlignedFloat params batch =
  MlpGradient
    { gradW1 = toDouble gradW1Float
    , gradB1 = toDouble gradB1Float
    , gradW2 = toDouble gradW2Float
    , gradB2 = toDouble gradB2Float
    }
 where
  shape = paramShape params
  inputCount = mlpInputs shape
  hiddenCount = mlpHidden shape
  outputCount = mlpOutputs shape
  batchCount = length batch
  w1 = VU.map realToFrac (paramW1 params) :: VU.Vector Float
  b1 = VU.map realToFrac (paramB1 params) :: VU.Vector Float
  w2 = VU.map realToFrac (paramW2 params) :: VU.Vector Float
  samples =
    [ (VU.map realToFrac input, VU.map realToFrac dLdy)
    | (input, dLdy) <- batch
    ]
  hiddenActs =
    [ VU.generate hiddenCount $ \i ->
        glibcTanhFloat $
          List.foldl'
            (\acc j -> acc + (w1 VU.! (i * inputCount + j)) * (input VU.! j))
            (b1 VU.! i)
            [0 .. inputCount - 1]
    | (input, _) <- samples
    ]
  inputAt b = fst (samples !! b)
  dLdyAt b = snd (samples !! b)
  hiddenAt b = hiddenActs !! b
  dPre b i =
    let dAct =
          List.foldl'
            (\acc k -> acc + (w2 VU.! (k * hiddenCount + i)) * (dLdyAt b VU.! k))
            0.0
            [0 .. outputCount - 1]
        hidden = hiddenAt b VU.! i
     in dAct * (1.0 - hidden * hidden)
  gradB2Float =
    VU.generate outputCount $ \k ->
      List.foldl'
        (\acc b -> acc + (dLdyAt b VU.! k))
        0.0
        [0 .. batchCount - 1]
  gradW2Float =
    VU.generate (outputCount * hiddenCount) $ \idx ->
      let (k, i) = idx `divMod` hiddenCount
       in List.foldl'
            (\acc b -> acc + (dLdyAt b VU.! k) * (hiddenAt b VU.! i))
            0.0
            [0 .. batchCount - 1]
  gradB1Float =
    VU.generate hiddenCount $ \i ->
      List.foldl'
        (\acc b -> acc + dPre b i)
        0.0
        [0 .. batchCount - 1]
  gradW1Float =
    VU.generate (hiddenCount * inputCount) $ \idx ->
      let (i, j) = idx `divMod` inputCount
       in List.foldl'
            (\acc b -> acc + dPre b i * (inputAt b VU.! j))
            0.0
            [0 .. batchCount - 1]
  toDouble = VU.map realToFrac

-- | glibc's flt-32 tanhf for the finite activation range exercised by the
-- wide parity fixture. Every binding is Float, so each operation rounds at the
-- same point as the rendered MSL/CUDA helper. The expm1 reduction below rejects
-- only the large-magnitude arm that the fixture cannot reach.
glibcTanhFloat :: Float -> Float
glibcTanhFloat x
  | ix < 0x24000000 = x * (one + x)
  | ix < 0x41b00000 =
      signed $
        if ix >= 0x3f800000
          then
            let t = glibcExpm1Float (2.0 * abs x)
             in one - 2.0 / (t + 2.0)
          else
            let t = glibcExpm1Float (-(2.0 * abs x))
             in negate t / (t + 2.0)
  | otherwise = signed (one - tiny)
 where
  bits = GHC.Float.castFloatToWord32 x
  ix = bits Bits..&. 0x7fffffff
  negative = Bits.testBit bits 31
  signed value = if negative then negate value else value
  one = 1.0 :: Float
  tiny = 1.0e-30 :: Float

glibcExpm1Float :: Float -> Float
glibcExpm1Float x0
  | hx >= 0x4195b844 =
      error "glibcExpm1Float: parity fixture exceeded the supported activation range"
  | hx < 0x33000000 =
      let t = huge + x0
       in x0 - (t - (huge + x0))
  | otherwise = finish reducedX correction reductionK
 where
  bits = GHC.Float.castFloatToWord32 x0
  signBit = bits Bits..&. 0x80000000
  hx = bits Bits..&. 0x7fffffff
  one = 1.0 :: Float
  huge = 1.0e30 :: Float
  ln2Hi = 6.9313812256e-1 :: Float
  ln2Lo = 9.0580006145e-6 :: Float
  invLn2 = 1.4426950216 :: Float
  q1 = -3.3333335072e-2 :: Float
  q2 = 1.5873016091e-3 :: Float
  q3 = -7.9365076090e-5 :: Float
  q4 = 4.0082177293e-6 :: Float
  q5 = -2.0109921195e-7 :: Float
  (reducedX, correction, reductionK)
    | hx > 0x3eb17218 =
        let (hi, lo, k)
              | hx < 0x3f851592 =
                  if signBit == 0
                    then (x0 - ln2Hi, ln2Lo, 1)
                    else (x0 + ln2Hi, negate ln2Lo, -1)
              | otherwise =
                  let rounded = if signBit == 0 then 0.5 else -0.5
                      k' = truncate (invLn2 * x0 + rounded)
                      t = fromIntegral k'
                   in (x0 - t * ln2Hi, t * ln2Lo, k')
            x = hi - lo
         in (x, (hi - x) - lo, k)
    | otherwise = (x0, 0.0, 0)
  finish x corr k =
    let hfx = 0.5 * x
        hxs = x * hfx
        r1 = one + hxs * (q1 + hxs * (q2 + hxs * (q3 + hxs * (q4 + hxs * q5))))
        t0 = 3.0 - r1 * hfx
        e0 = hxs * ((r1 - t0) / (6.0 - x * t0))
     in if k == 0
          then x - (x * e0 - hxs)
          else scaleReduced x corr hxs e0 k
  scaleReduced x corr hxs e0 k =
    let twoPk =
          GHC.Float.castWord32ToFloat $
            fromIntegral ((0x7f + k) `Bits.shiftL` 23)
        e = x * (e0 - corr) - corr - hxs
     in case k of
          -1 -> 0.5 * (x - e) - 0.5
          1
            | x < -0.25 -> -(2.0 * (e - (x + 0.5)))
            | otherwise -> one + 2.0 * (x - e)
          _
            | k <= -2 || k > 56 ->
                let y0 = one - (e - x)
                    y =
                      if k == 128
                        then y0 * 2.0 * GHC.Float.castWord32ToFloat 0x7f000000
                        else y0 * twoPk
                 in y - one
            | k < 23 ->
                let t =
                      GHC.Float.castWord32ToFloat $
                        0x3f800000 - (0x01000000 `Bits.shiftR` k)
                 in (t - (e - x)) * twoPk
            | otherwise ->
                let t =
                      GHC.Float.castWord32ToFloat $
                        fromIntegral ((0x7f - k) `Bits.shiftL` 23)
                 in (x - (e + t) + one) * twoPk

assertListClose :: String -> [Float] -> [Float] -> IO ()
assertListClose label expected actual =
  assertBool
    (label <> ": expected=" <> show expected <> " actual=" <> show actual)
    (approxEqualFloatList 1.0e-3 expected actual)

approxEqualFloatList :: Float -> [Float] -> [Float] -> Bool
approxEqualFloatList tol expected actual =
  length expected == length actual
    && and (zipWith (\x y -> abs (x - y) <= tol) expected actual)

metalWindowedConv2DReference :: [Float] -> [Float] -> [Float]
metalWindowedConv2DReference input weights =
  [ outputAt idx
  | idx <- [0 .. n - 1]
  ]
 where
  n = length input
  width = ceilSqrt n
  height = (n + width - 1) `div` width
  valueAt idx = input !! idx
  weightAt k
    | k < length weights = weights !! k
    | k == 4 = 1.0
    | otherwise = 0.0
  outputAt idx =
    let x0 = idx `mod` width
        y0 = idx `div` width
     in sum
          [ valueAt sample * weightAt ((dy + 1) * 3 + (dx + 1))
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

metalWindowedConv3DReference :: [Float] -> [Float] -> [Float]
metalWindowedConv3DReference input weights =
  [ outputAt idx
  | idx <- [0 .. n - 1]
  ]
 where
  n = length input
  side = ceilCubeRoot n
  plane = side * side
  valueAt idx = input !! idx
  weightAt k
    | k < length weights = weights !! k
    | k == 13 = 1.0
    | otherwise = 0.0
  outputAt idx =
    let z0 = idx `div` plane
        rem0 = idx `mod` plane
        y0 = rem0 `div` side
        x0 = rem0 `mod` side
     in sum
          [ valueAt sample * weightAt ((dz + 1) * 9 + (dy + 1) * 3 + (dx + 1))
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

ceilSqrt :: Int -> Int
ceilSqrt n =
  go 1
 where
  go side
    | side * side >= n = side
    | otherwise = go (side + 1)

ceilCubeRoot :: Int -> Int
ceilCubeRoot n =
  go 1
 where
  go side
    | side * side * side >= n = side
    | otherwise = go (side + 1)

-- | Sprint 13.15 — unique per-run suffix so the first-cache-miss test
-- starts from a guaranteed-cold cache key on every invocation.
pickRandomSuffix :: IO Text.Text
pickRandomSuffix = do
  micros <- round . (* 1_000_000) <$> getPOSIXTime :: IO Integer
  pure (Text.pack (show micros))
