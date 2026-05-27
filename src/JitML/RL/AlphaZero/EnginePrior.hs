{-# LANGUAGE OverloadedStrings #-}

-- | Sprint 13.9 — JIT-engine-backed 'PriorOracle' bridge.
--
-- The pure MCTS search loop in "JitML.RL.AlphaZero.Mcts" takes a
-- 'PriorOracle' (a @(seed, action) -> prior@ function). Production AlphaZero
-- wraps the policy-head forward pass of a JIT-compiled network behind that
-- callable. This module materialises that bridge for the substrates jitML
-- supports:
--
--   1. Pre-compute a deterministic prior table by compiling and running a
--      'Dense2D'-family JIT kernel (the smallest neural-net-shaped
--      primitive jitML's codegen currently exposes).
--   2. Wrap the resulting @[Float]@ output in a pure closure that the
--      MCTS loop consumes as a 'PriorOracle'.
--
-- The output table is finite, so the closure stride-indexes by
-- @seed * stride + action@ with a large coprime stride to avoid action-bias
-- patterns. The resulting oracle is bit-deterministic on the same substrate
-- (per the [determinism contract](../documents/engineering/determinism_contract.md))
-- and replaces the deterministic 'priorFor' stub the legacy ledger row
-- tracks.
--
-- This bridge is intentionally simpler than a full policy/value network
-- (per-position observation tensors, head splitting, value backup). A real
-- AlphaZero loop with policy/value network codegen plus checkpoint surface
-- is multi-day work tracked in the Sprint 13.9 'Remaining Work' block.
-- What this module gives the plan is: the MCTS prior input is no longer
-- the synthetic 'priorFor' constant — it now comes from a real JIT kernel.
module JitML.RL.AlphaZero.EnginePrior
  ( buildLinuxCpuPriorOracle
  , linuxCpuPriorTable
  )
where

import Data.Text (Text)

import JitML.Codegen.KernelFamily (KernelFamily (..))
import JitML.Engines.Local
  ( LinuxCpuKernelRun (..)
  , runLinuxCpuFamilyKernel
  )
import JitML.Env.Env (Env)
import JitML.RL.AlphaZero.Mcts (PriorOracle)

-- | Compile and run the canonical 'Dense2D' kernel on a deterministic
-- input vector and return the kernel's output as a flat prior table. The
-- output is bit-deterministic on the same substrate per the determinism
-- contract.
linuxCpuPriorTable :: Env -> Int -> IO (Either Text [Float])
linuxCpuPriorTable env actionSpace = do
  let probeSize = max 4 actionSpace
      input =
        [ fromIntegral (i + 1) / fromIntegral probeSize
        | i <- [0 .. probeSize - 1]
        ]
  result <- runLinuxCpuFamilyKernel env Dense2D input
  pure $ case result of
    Left err -> Left ("engine prior kernel failed: " <> err)
    Right run ->
      let output = linuxCpuKernelOutput run
       in if null output
            then Left "engine prior kernel returned empty output"
            else Right output

-- | Build the JIT-engine-backed 'PriorOracle' for AlphaZero on Linux CPU.
-- The closure pre-computes a finite prior table from a real JIT-compiled
-- Dense2D kernel, then indexes into it with @(seed * stride + action)@.
-- Outputs are mapped through @abs (x) + 1e-3@ so the MCTS prior is strictly
-- positive (the search loop normalises by their sum).
buildLinuxCpuPriorOracle :: Env -> Int -> IO (Either Text PriorOracle)
buildLinuxCpuPriorOracle env actionSpace = do
  table <- linuxCpuPriorTable env actionSpace
  pure $ case table of
    Left err -> Left err
    Right values ->
      let tableArray = values
          tableSize = length tableArray
          stride = 257
          lookupAt seed action =
            let idx = ((seed * stride + action) `mod` tableSize + tableSize) `mod` tableSize
                v = realToFrac (tableArray !! idx) :: Double
             in abs v + 1.0e-3
       in Right lookupAt
