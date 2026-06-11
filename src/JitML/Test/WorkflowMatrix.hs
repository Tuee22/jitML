{-# LANGUAGE OverloadedStrings #-}

-- | Sprint 12.11 — the single DRY enumeration of the reopened real workflows
-- crossed with every substrate. The integration / e2e Live tests iterate this
-- matrix instead of re-deriving per-workflow asserts, so coverage is uniform
-- and a workflow can never silently drop out of the live exercise.
--
-- Each cell carries the canonical `jitml` command (argv) that drives the
-- workflow on its substrate. The live runner that executes each cell against a
-- live cluster and asserts the real measured output **fails closed** without a
-- `cluster-publication.json` (no vacuous pass); that live runner is owned by
-- Phases `13`/`14`/`15` and needs the cluster + per-substrate hardware. This
-- module is the host-validatable structure those tests share.
module JitML.Test.WorkflowMatrix
  ( Workflow (..)
  , WorkflowCell (..)
  , allWorkflows
  , workflowCommand
  , workflowMatrix
  )
where

import Data.Text (Text)

import JitML.Substrate (Substrate, allSubstrates, renderSubstrate)

-- | The reopened real workflows (Phases `8`–`11`) the matrix exercises per
-- substrate.
data Workflow
  = SlTrain
  | SlEval
  | RlTrain
  | RlEval
  | RlRollout
  | Tune
  | Inference
  | AlphaZeroSelfPlay
  deriving stock (Eq, Show, Enum, Bounded)

allWorkflows :: [Workflow]
allWorkflows = [minBound .. maxBound]

-- | The canonical `jitml` command (argv) that drives a workflow on a substrate.
-- Substrate-scoped workflows carry the resolved `--substrate` flag; the
-- checkpoint-read workflows (`eval`, `rl eval`, `inference run`) resolve the
-- substrate from the live publication.
workflowCommand :: Workflow -> Substrate -> [Text]
workflowCommand workflow substrate =
  let sub = ["--substrate", renderSubstrate substrate]
   in case workflow of
        SlTrain -> ["train", "experiments/mnist.dhall"] <> sub
        SlEval -> ["eval", "--checkpoint", "latest"]
        RlTrain -> ["rl", "train", "experiments/cartpole.dhall"] <> sub
        RlEval -> ["rl", "eval", "--checkpoint", "latest"]
        RlRollout -> ["rl", "rollout", "--seed", "42"]
        Tune -> ["tune", "experiments/mnist-tune.dhall"] <> sub
        Inference -> ["inference", "run", "--experiment-hash", "default"]
        AlphaZeroSelfPlay -> ["rl", "train", "experiments/key-door-grid.dhall"] <> sub

-- | One @(workflow, substrate)@ cell with its canonical command.
data WorkflowCell = WorkflowCell
  { cellWorkflow :: Workflow
  , cellSubstrate :: Substrate
  , cellCommand :: [Text]
  }
  deriving stock (Eq, Show)

-- | The full DRY matrix: every workflow × every substrate, in deterministic
-- order. The live runner iterates this; a fail-closed cell passes only when its
-- real workflow produced real measured output on the resolved substrate.
workflowMatrix :: [WorkflowCell]
workflowMatrix =
  [ WorkflowCell workflow substrate (workflowCommand workflow substrate)
  | workflow <- allWorkflows
  , substrate <- allSubstrates
  ]
