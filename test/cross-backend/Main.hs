{-# LANGUAGE OverloadedStrings #-}

module Main where

import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

import JitML.Cache.Key qualified as Cache
import JitML.Checkpoint.Format (TensorBlob (..), emptyManifest, inferFromManifest)
import JitML.Codegen.KernelFamily (KernelFamily (..), familyName, kernelFamilies)
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
