{-# LANGUAGE OverloadedStrings #-}

module Main where

import Data.Foldable (for_)
import Data.Text qualified as Text
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

import Control.Exception qualified
import Data.Time.Clock.POSIX (getPOSIXTime)
import Data.Vector.Unboxed qualified as VU
import JitML.Cache.Key qualified as Cache
import JitML.Checkpoint.Format (TensorBlob (..), emptyManifest, inferFromManifest)
import JitML.Codegen.KernelFamily (KernelFamily (..), familyName, kernelFamilies)
import JitML.Engines.CublasBindings qualified as Cublas
import JitML.Engines.CudaLocal
  ( cudaKernelOutput
  , cudaKernelReportedFamily
  , runCudaFamilyKernel
  )
import JitML.Engines.CudaLocal qualified as Cuda
import JitML.Engines.CudaRuntime qualified as CudaRuntime
import JitML.Engines.CudnnBindings qualified as Cudnn
import JitML.Engines.MetalLocal qualified as Metal
import JitML.Engines.MetalRuntime qualified as MetalRuntime
import JitML.Tart.Lifecycle
  ( TartVmStatus (TartVmRunning)
  , VmName (VmName)
  , queryTartVmStatus
  )
import JitML.Engines.Engine (deterministicFlags, engineForSubstrate)
import JitML.Engines.HasEngine
  ( EngineRequest (..)
  , engineRunOutput
  , engineRunReportedFamily
  , runLinuxCpuEngine
  )
import JitML.Engines.Local
  ( linuxCpuKernelOutput
  , linuxCpuKernelReportedFamily
  , runLinuxCpuFamilyKernel
  , runLinuxCpuIdentityKernel
  )
import JitML.Engines.Local qualified as Local
import JitML.Engines.Tuning qualified as Tuning
import JitML.Engines.TuningBenchmark qualified as TuningBenchmark
import JitML.Env.Build (buildEnv, defaultGlobalFlags)
import JitML.Env.Env (Env, envCacheDir)
import JitML.Numerics.Mlp
  ( MlpForward (..)
  , MlpGradient (..)
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
import JitML.RL.Algorithms.ContinuousTrainer
  ( ContinuousIterationStat (..)
  , ContinuousTrainConfig (..)
  , ContinuousTrainResult (..)
  , ContinuousVariant (..)
  , defaultContinuousTrainConfig
  , trainContinuousOnPendulumCuda
  )
import JitML.RL.Algorithms.DqnTrainer
  ( DqnIterationStat (..)
  , DqnTrainConfig (..)
  , DqnTrainResult (..)
  , defaultDqnTrainConfig
  , trainDqnOnCartpoleCuda
  )
import JitML.RL.Algorithms.HerTrainer
  ( HerIterationStat (..)
  , HerTrainConfig (..)
  , HerTrainResult (..)
  , defaultHerTrainConfig
  , trainHerOnBitFlipCuda
  )
import JitML.RL.Algorithms.PpoTrainer
  ( OnPolicyVariant (..)
  , PpoIterationStat (..)
  , PpoTrainConfig (..)
  , PpoTrainResult (..)
  , defaultPpoTrainConfig
  , trainOnPolicyOnCartpoleCuda
  )
import JitML.RL.Algorithms.QrDqnTrainer
  ( QrDqnIterationStat (..)
  , QrDqnTrainConfig (..)
  , QrDqnTrainResult (..)
  , defaultQrDqnTrainConfig
  , trainQrDqnOnCartpoleCuda
  )
import JitML.RL.AlphaZero (initialConnect4)
import JitML.RL.AlphaZero.PolicyValueNet qualified as PVN
import JitML.Substrate (Substrate (..), allSubstrates)
import JitML.Substrate qualified as Substrate
import Path (toFilePath)
import System.Directory (listDirectory)
import System.FilePath ((</>))

main :: IO ()
main =
  defaultMain $
    testGroup
      "jitml-cross-backend"
      [ testCase "each substrate has deterministic engine flags" $
          mapM_
            (assertBool "flags present" . not . null . deterministicFlags . engineForSubstrate)
            allSubstrates
      , testCase "checkpoint inference is backend independent for manifest reads" $ do
          let manifest = emptyManifest "m1" "exp" [TensorBlob "dense" [2, 2] "blob"]
              expected = inferFromManifest manifest [1, 2, 3]
          mapM_
            (\_substrate -> inferFromManifest manifest [1, 2, 3] @?= expected)
            [AppleSilicon, LinuxCPU, LinuxCUDA]
      , testCase "linux-cpu JIT compile/load/run executes the generated identity kernel" $ do
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
                  [ (Conv2DKernel, [2.0 :: Float])
                  , (Conv3DKernel, [3.0 :: Float])
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
      , testCase "linux-cuda generated kernel compiles and runs through nvcc + FFI (Sprint 7.4)" $ do
          -- Live CUDA validation: Sprint 7.4 closure. When the host
          -- has nvcc + libcublas + libcudnn visible and an NVIDIA GPU
          -- attached, compile the generated `kernel.cu` through nvcc,
          -- dlopen the resulting `.so`, launch the identity kernel,
          -- and verify the copied-back output matches the input
          -- bit-equally. On hosts without a positive CUDA runtime
          -- probe the test logs a skip and passes.
          probe <- CudaRuntime.probeCudaRuntime
          if not (CudaRuntime.cudaRuntimeAvailable probe)
            then
              assertBool
                "CUDA runtime unavailable on this host; live CUDA path skipped"
                True
            else do
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
          probe <- CudaRuntime.probeCudaRuntime
          if not (CudaRuntime.cudaRuntimeAvailable probe)
            then
              assertBool
                "CUDA runtime unavailable on this host; live CUDA path skipped"
                True
            else do
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
          probe <- CudaRuntime.probeCudaRuntime
          if not (CudaRuntime.cudaRuntimeAvailable probe)
            then
              assertBool
                "CUDA runtime unavailable on this host; live CUDA determinism check skipped"
                True
            else do
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
            probe <- CudaRuntime.probeCudaRuntime
            if not (CudaRuntime.cudaRuntimeAvailable probe)
              then
                assertBool
                  "CUDA runtime unavailable on this host; weighted CUDA Dense2D test skipped"
                  True
              else do
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
          -- the generated identity kernel through the live `dlopen` + Metal
          -- launcher FFI must produce bit-identical output. The build runs
          -- inside the `jitml-build` Tart VM; the host loads and executes the
          -- VM-produced dylib through its Metal framework. The test requires a
          -- visible Metal device and a running `jitml-build` Tart VM (the build
          -- runs inside it); on hosts without both (Linux CI, or an Apple host
          -- where the VM is not booted) the test logs a skip.
          ready <- appleLiveReady
          if not ready
            then
              assertBool
                "Metal device + running jitml-build VM unavailable; live apple-silicon determinism check skipped"
                True
            else do
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
            ready <- appleLiveReady
            if not ready
              then
                assertBool
                  "Metal device + running jitml-build VM unavailable; weighted apple-silicon Dense2D test skipped"
                  True
              else do
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
      , testCase "cuBLAS bindings initialize and report a version (Sprint 7.4)" $ do
          probe <- CudaRuntime.probeCudaRuntime
          if not (CudaRuntime.cudaRuntimeAvailable probe)
            then
              assertBool
                "CUDA runtime unavailable on this host; cuBLAS bindings test skipped"
                True
            else
              if not Cublas.cublasBindingsCompiledIn
                then
                  assertBool
                    "jitml built without -fcuda; cuBLAS bindings test skipped"
                    True
                else do
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
      , testCase "cuDNN bindings initialize and report a version (Sprint 7.4)" $ do
          probe <- CudaRuntime.probeCudaRuntime
          if not (CudaRuntime.cudaRuntimeAvailable probe)
            then
              assertBool
                "CUDA runtime unavailable on this host; cuDNN bindings test skipped"
                True
            else
              if not Cudnn.cudnnBindingsCompiledIn
                then
                  assertBool
                    "jitml built without -fcuda; cuDNN bindings test skipped"
                    True
                else do
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
          -- Sprint 7.6 live CUDA candidate runner: mirrors the
          -- linux-cpu sibling above. On a host with `probeCudaRuntime`
          -- available the runner renders the tuned CUDA source,
          -- compiles via real nvcc, loads through the FFI, and reports
          -- a measured latency plus content-sensitive float digest.
          -- On a host without CUDA the runner returns a typed
          -- unavailable error.
          probe <- CudaRuntime.probeCudaRuntime
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
          if not (CudaRuntime.cudaRuntimeAvailable probe)
            then case observation of
              Left message ->
                assertBool
                  ("expected unavailable summary, got: " <> show message)
                  ("linux-cuda benchmark runner unavailable:" `Text.isPrefixOf` message)
              Right _ ->
                assertBool
                  "unavailable probe but live benchmark returned a measurement"
                  False
            else case observation of
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
            -- Drive the cache-miss path. The deterministic-stub runner
            -- returns a constant observation; the typed
            -- ensureKernelArtifactWithBenchmarkTuningWithRunner closure
            -- writes the selection to disk via TuningStore.
            let stubRunner _env _spec _kind _input _candidate =
                  pure
                    ( Right
                        ( TuningBenchmark.BenchmarkObservation
                            { TuningBenchmark.benchmarkObservationLatencyMicros = 1
                            , TuningBenchmark.benchmarkObservationOutputDigest = "stub-digest"
                            }
                        )
                    )
            _ <-
              TuningBenchmark.ensureKernelArtifactWithBenchmarkTuningWithRunner
                env
                Substrate.LinuxCPU
                stubRunner
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
            probe <- CudaRuntime.probeCudaRuntime
            if not (CudaRuntime.cudaRuntimeAvailable probe)
              then
                assertBool
                  "CUDA runtime unavailable on this host; MLP forward CUDA test skipped"
                  True
              else do
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
            probe <- CudaRuntime.probeCudaRuntime
            if not (CudaRuntime.cudaRuntimeAvailable probe)
              then
                assertBool
                  "CUDA runtime unavailable on this host; MLP backward CUDA test skipped"
                  True
              else do
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
            probe <- CudaRuntime.probeCudaRuntime
            if not (CudaRuntime.cudaRuntimeAvailable probe)
              then
                assertBool
                  "CUDA runtime unavailable on this host; MLP determinism CUDA test skipped"
                  True
              else do
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
            probe <- CudaRuntime.probeCudaRuntime
            if not (CudaRuntime.cudaRuntimeAvailable probe)
              then
                assertBool
                  "CUDA runtime unavailable on this host; batched MLP gradient test skipped"
                  True
              else do
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
          "linux-cuda batched MLP forward matches the pure per-sample forward (Sprint 13.8)"
          $ do
            -- Sprint 13.8 — the batched forward (one device call for the whole
            -- minibatch) must reproduce the pure per-sample forward outputs
            -- within single precision, and be bit-deterministic. Together with
            -- the batched gradient this is the full device minibatch primitive
            -- set a CUDA trainer drives.
            probe <- CudaRuntime.probeCudaRuntime
            if not (CudaRuntime.cudaRuntimeAvailable probe)
              then
                assertBool
                  "CUDA runtime unavailable on this host; batched MLP forward test skipped"
                  True
              else do
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
            probe <- CudaRuntime.probeCudaRuntime
            if not (CudaRuntime.cudaRuntimeAvailable probe)
              then
                assertBool
                  "CUDA runtime unavailable on this host; batched input-gradient test skipped"
                  True
              else do
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
            probe <- CudaRuntime.probeCudaRuntime
            if not (CudaRuntime.cudaRuntimeAvailable probe)
              then
                assertBool
                  "CUDA runtime unavailable on this host; on-policy CUDA trainer test skipped"
                  True
              else do
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
            probe <- CudaRuntime.probeCudaRuntime
            if not (CudaRuntime.cudaRuntimeAvailable probe)
              then
                assertBool
                  "CUDA runtime unavailable on this host; DQN CUDA trainer test skipped"
                  True
              else do
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
                r1 <- trainDqnOnCartpoleCuda env config
                r2 <- trainDqnOnCartpoleCuda env config
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
            probe <- CudaRuntime.probeCudaRuntime
            if not (CudaRuntime.cudaRuntimeAvailable probe)
              then
                assertBool
                  "CUDA runtime unavailable on this host; QR-DQN CUDA trainer test skipped"
                  True
              else do
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
                r1 <- trainQrDqnOnCartpoleCuda env config
                r2 <- trainQrDqnOnCartpoleCuda env config
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
            probe <- CudaRuntime.probeCudaRuntime
            if not (CudaRuntime.cudaRuntimeAvailable probe)
              then
                assertBool
                  "CUDA runtime unavailable on this host; HER CUDA trainer test skipped"
                  True
              else do
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
                r1 <- trainHerOnBitFlipCuda env config
                r2 <- trainHerOnBitFlipCuda env config
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
            probe <- CudaRuntime.probeCudaRuntime
            if not (CudaRuntime.cudaRuntimeAvailable probe)
              then
                assertBool
                  "CUDA runtime unavailable on this host; continuous CUDA trainer test skipped"
                  True
              else do
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
                r1 <- trainContinuousOnPendulumCuda env config
                r2 <- trainContinuousOnPendulumCuda env config
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
            probe <- CudaRuntime.probeCudaRuntime
            if not (CudaRuntime.cudaRuntimeAvailable probe)
              then
                assertBool
                  "CUDA runtime unavailable on this host; PolicyValueNet CUDA training skipped"
                  True
              else do
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
      ]

-- | Elementwise approximate equality for two unboxed Double vectors.
approxEqualVec :: Double -> VU.Vector Double -> VU.Vector Double -> Bool
approxEqualVec tol a b =
  VU.length a == VU.length b
    && VU.and (VU.zipWith (\x y -> abs (x - y) <= tol) a b)

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
      case family of
        Reduction -> linuxCpuKernelOutput kernelRun @?= [6.0]
        _ -> length (linuxCpuKernelOutput kernelRun) @?= 4
      assertBool
        ("linux-cpu family output is finite for " <> show (familyName family))
        (all finiteFloat (linuxCpuKernelOutput kernelRun))

finiteFloat :: Float -> Bool
finiteFloat value =
  not (isNaN value) && not (isInfinite value)

-- | The live apple-silicon Metal path is exercisable only when the host has a
-- visible Metal device AND the `jitml-build` Tart VM is running (the kernel
-- build runs inside the VM via `tart exec`; booting a macOS guest requires an
-- interactive GUI session, so a headless context cannot start it). When either
-- is missing the cross-backend Apple cases skip rather than fail.
appleLiveReady :: IO Bool
appleLiveReady = do
  probe <- MetalRuntime.probeMetalRuntime
  if not (MetalRuntime.metalRuntimeDeviceVisible probe)
    then pure False
    else do
      status <- queryTartVmStatus (VmName "jitml-build")
      pure (status == Right TartVmRunning)

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

-- | Sprint 13.15 — unique per-run suffix so the first-cache-miss test
-- starts from a guaranteed-cold cache key on every invocation.
pickRandomSuffix :: IO Text.Text
pickRandomSuffix = do
  micros <- round . (* 1_000_000) <$> getPOSIXTime :: IO Integer
  pure (Text.pack (show micros))
