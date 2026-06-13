{-# LANGUAGE OverloadedStrings #-}

-- | Sprint 12.11 — the single DRY enumeration of the reopened real workflows
-- crossed with every substrate. The integration / e2e Live tests iterate this
-- matrix instead of re-deriving per-workflow asserts, so coverage is uniform
-- and a workflow can never silently drop out of the live exercise.
--
-- Each cell carries the canonical `jitml` command (argv) that drives the
-- workflow on its substrate. The live runner that executes each cell against a
-- live cluster and asserts the real measured output **fails closed** without a
-- `cluster-publication.json` (no vacuous pass); substrate selection is explicit
-- where the command surface owns a `--substrate` flag and otherwise resolves
-- through the live publication / run config. This module is the
-- host-validatable structure those tests share.
module JitML.Test.WorkflowMatrix
  ( Workflow (..)
  , WorkflowCell (..)
  , WorkflowPlacementExpectation (..)
  , allWorkflows
  , workflowCommand
  , workflowMatrix
  , workflowPlacementExpectation
  )
where

import Data.Text (Text)

import JitML.Substrate (Substrate (..), allSubstrates, renderSubstrate)

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
-- checkpoint-read and publication-scoped workflows (`eval`, `rl eval`,
-- `tune`, `inference run`) resolve the substrate from the live publication.
workflowCommand :: Workflow -> Substrate -> [Text]
workflowCommand workflow substrate =
  let sub = ["--substrate", renderSubstrate substrate]
   in case workflow of
        SlTrain -> ["train", "experiments/mnist.dhall"] <> sub
        SlEval -> ["eval", "experiments/mnist.dhall", "--checkpoint", "workflow-matrix-eval"]
        RlTrain -> ["rl", "train", "experiments/cartpole.dhall"] <> sub
        RlEval -> ["rl", "eval", "experiments/cartpole.dhall", "--checkpoint", "workflow-matrix-eval"]
        RlRollout -> ["rl", "rollout", "experiments/cartpole.dhall", "--seed", "42"]
        Tune -> ["tune", "experiments/mnist-tune.dhall"]
        Inference ->
          ["inference", "run", "experiments/mnist.dhall", "--experiment-hash", "workflow-matrix-inference"]
        AlphaZeroSelfPlay -> ["rl", "alphazero", "self-play"] <> sub

-- | One @(workflow, substrate)@ cell with its canonical command.
data WorkflowCell = WorkflowCell
  { cellWorkflow :: Workflow
  , cellSubstrate :: Substrate
  , cellCommand :: [Text]
  }
  deriving stock (Eq, Show)

data WorkflowPlacementExpectation
  = WorkflowRunsInProcess
  | WorkflowClusterJobExpected
  | WorkflowHostCommandExpected Text
  deriving stock (Eq, Show)

-- | Daemon-dispatched placement expected for workflows that have a service
-- command-envelope path. The matrix commands themselves still run through the
-- CLI; this expectation is used by live daemon tests to keep placement rules
-- DRY across substrates.
workflowPlacementExpectation :: Workflow -> Substrate -> WorkflowPlacementExpectation
workflowPlacementExpectation workflow substrate =
  case (workflow, substrate) of
    (SlTrain, AppleSilicon) ->
      WorkflowHostCommandExpected "persistent://public/default/training.host-command.apple-silicon"
    (RlTrain, AppleSilicon) ->
      WorkflowHostCommandExpected "persistent://public/default/rl.host-command.apple-silicon"
    (Tune, AppleSilicon) ->
      WorkflowHostCommandExpected "persistent://public/default/tune.host-command.apple-silicon"
    (SlTrain, _) -> WorkflowClusterJobExpected
    (RlTrain, _) -> WorkflowClusterJobExpected
    (Tune, _) -> WorkflowClusterJobExpected
    _ -> WorkflowRunsInProcess

-- | The full DRY matrix: every workflow × every substrate, in deterministic
-- order. The live runner iterates this; a fail-closed cell passes only when its
-- real workflow produced real measured output on the resolved substrate.
workflowMatrix :: [WorkflowCell]
workflowMatrix =
  [ WorkflowCell workflow substrate (workflowCommand workflow substrate)
  | workflow <- allWorkflows
  , substrate <- allSubstrates
  ]
