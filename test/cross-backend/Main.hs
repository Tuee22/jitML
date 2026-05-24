{-# LANGUAGE OverloadedStrings #-}

module Main where

import Data.Text qualified as Text
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

import JitML.Cache.Key qualified as Cache
import JitML.Checkpoint.Format (TensorBlob (..), emptyManifest, inferFromManifest)
import JitML.Codegen.KernelFamily (KernelFamily (..), familyName, kernelFamilies)
import JitML.Engines.CublasBindings qualified as Cublas
import JitML.Engines.CudaLocal
  ( cudaKernelOutput
  , cudaKernelReportedFamily
  , runCudaFamilyKernel
  )
import JitML.Engines.CudaRuntime qualified as CudaRuntime
import JitML.Engines.CudnnBindings qualified as Cudnn
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
import JitML.Engines.Tuning qualified as Tuning
import JitML.Engines.TuningBenchmark qualified as TuningBenchmark
import JitML.Env.Build (buildEnv, defaultGlobalFlags)
import JitML.Env.Env (Env)
import JitML.Substrate (Substrate (..), allSubstrates)

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
      ]

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
