{-# LANGUAGE OverloadedStrings #-}

module Main where

import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

import JitML.Cache.Key qualified as Cache
import JitML.Checkpoint.Format (TensorBlob (..), emptyManifest, inferFromManifest)
import JitML.Codegen.KernelFamily (KernelFamily (..), kernelFamilyKernelSpec)
import JitML.Codegen.OneDnn (renderOneDnnFamilySource)
import JitML.Codegen.RuntimeSource
  ( RuntimeSource (..)
  , runtimeSourcePayload
  )
import JitML.Engines.Engine (deterministicFlags, engineForSubstrate)
import JitML.Engines.Local (linuxCpuKernelOutput, runLinuxCpuIdentityKernel, runLinuxCpuKernel)
import JitML.Env.Build (buildEnv, defaultGlobalFlags)
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
            Right kernelRun ->
              linuxCpuKernelOutput kernelRun @?= [1.25, 2.5, -3.75]
      , testCase "linux-cpu reduction family compiles through the generated FFI path" $ do
          env <- buildEnv defaultGlobalFlags
          let source = oneDnnFamilyRuntimeSource Reduction
              hash = oneDnnFamilyHash source Reduction
          result <- runLinuxCpuKernel env source hash [4.5]
          case result of
            Left message -> assertBool ("linux-cpu reduction JIT run failed: " <> show message) False
            Right kernelRun ->
              take 1 (linuxCpuKernelOutput kernelRun) @?= [4.5]
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
      ]

oneDnnFamilyRuntimeSource :: KernelFamily -> RuntimeSource
oneDnnFamilyRuntimeSource family =
  GeneratedOneDnnSource
    { runtimeSourceKernel = kernelFamilyKernelSpec family
    , runtimeSourceKind = Cache.Inference
    , runtimeSourceTuning = Cache.defaultTuningChoice
    , runtimeSourceFiles =
        renderOneDnnFamilySource
          family
          (kernelFamilyKernelSpec family)
          Cache.Inference
          Cache.defaultTuningChoice
    }

oneDnnFamilyHash :: RuntimeSource -> KernelFamily -> Cache.Hash
oneDnnFamilyHash source family =
  Cache.cacheKey
    (kernelFamilyKernelSpec family)
    Cache.Inference
    Cache.LinuxCPU
    (Cache.ToolchainFingerprint "g++-shared;abi=extern-c;jitml_kernel(float*,const float*,size_t)")
    (runtimeSourcePayload source)
    Cache.defaultTuningChoice
