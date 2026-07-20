{-# LANGUAGE GADTs #-}
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
  , ModelCell (..)
  , ModelKind (..)
  , WorkflowPlacementExpectation (..)
  , BrowserProductInteraction (..)
  , allWorkflows
  , allModelCells
  , allBrowserProductInteractions
  , browserAdversarialGames
  , browserProductInteractionLabel
  , browserProductMatrix
  , modelCellMatrix
  , modelCellsForRows
  , workflowCommand
  , workflowMatrix
  , workflowPlacementExpectation
  )
where

import Data.List.NonEmpty (NonEmpty)
import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Plan.Plan (Validation (..), planIdText)
import JitML.Product.Matrix qualified as Product
import JitML.Substrate (Substrate (..), allSubstrates, renderSubstrate)
import JitML.Training.Budget qualified as TrainingBudget

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

data ModelKind
  = SupervisedModelCell
  | RlAlgorithmModelCell
  | HerModelCell
  | AlphaZeroGameModelCell
  | TuningModelCell
  deriving stock (Eq, Show, Enum, Bounded)

data ModelCell = ModelCell
  { modelCellKind :: ModelKind
  , modelCellName :: Text
  , modelCellPlanId :: Text
  , modelCellSubstrate :: Substrate
  , modelCellExperimentHash :: Text
  , modelCellE2eTest :: Text
  , modelCellDemoPanel :: Text
  , modelCellBudget :: Text
  , modelCellCommand :: [Text]
  , modelCellRequiresTrainedArtifact :: Bool
  }
  deriving stock (Eq, Show)

allModelCells :: [ModelCell]
allModelCells = canonicalModelCells LinuxCPU

-- | Refine arbitrary registry rows into workflow cells through the same total
-- product projection used by reports and execution.  Invalid rows stay typed
-- failures; callers cannot obtain a cell by reinterpreting raw RowClass data.
modelCellsForRows
  :: Substrate
  -> [Product.ProductRow state]
  -> Validation
       (NonEmpty Product.ProductMatrixError)
       [ModelCell]
modelCellsForRows substrate rows =
  fmap
    (fmap productModelCell . Product.productProjectionBatchProjections)
    (Product.projectProductRows substrate rows)

productModelCell :: Product.SomeProductProjection -> ModelCell
productModelCell (Product.SomeProductProjection _ projection) =
  ModelCell
    { modelCellKind = productModelKind projection
    , modelCellName = Product.productProjectionRowId projection
    , modelCellPlanId = planIdText (Product.productProjectionPlanId projection)
    , modelCellSubstrate = Product.productProjectionSubstrate projection
    , modelCellExperimentHash = Product.productProjectionExperimentHash projection
    , modelCellE2eTest = Product.productProjectionE2ETest projection
    , modelCellDemoPanel = Product.productProjectionDemoPanel projection
    , modelCellBudget =
        TrainingBudget.renderTrainingBudget
          (Product.productProjectionTrainingBudget projection)
    , modelCellCommand = Product.productProjectionCommand projection
    , modelCellRequiresTrainedArtifact = True
    }

productModelKind :: Product.ProductProjection kind -> ModelKind
productModelKind projection =
  case Product.productProjectionFamily projection of
    Product.Supervised -> SupervisedModelCell
    Product.ReinforcementLearning ->
      case Product.productProjectionRowClass projection of
        Product.RlGoalConditioned _ -> HerModelCell
        _ -> RlAlgorithmModelCell
    Product.AlphaZero -> AlphaZeroGameModelCell
    Product.Tuning -> TuningModelCell

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

modelCellMatrix :: [(ModelCell, Substrate)]
modelCellMatrix =
  [ (modelCell, substrate)
  | substrate <- allSubstrates
  , modelCell <- canonicalModelCells substrate
  ]

canonicalModelCells :: Substrate -> [ModelCell]
canonicalModelCells substrate =
  case modelCellsForRows substrate Product.allProductRows of
    Success cells -> cells
    Failure errors ->
      error
        ( "canonical ProductRow registry is not projectable for "
            <> Text.unpack (renderSubstrate substrate)
            <> ": "
            <> show errors
        )

-- | The no-caveat browser/product interactions (Sprint 12.13 / Phase `17`) the
-- live Playwright product matrix must exercise: every model/product cell the
-- demo app exposes, from training launch and checkpoint inspection through
-- model-family inference, RL animation/replay, adversarial play/replay, and
-- tuning control/promotion. The live e2e runner iterates this crossed with
-- every substrate ('browserProductMatrix') and fails closed on any cell whose
-- real browser interaction is missing; this enumeration is the host-validatable
-- structure those tests share, mirroring 'Workflow' / 'workflowMatrix'.
data BrowserProductInteraction
  = BrowserTrainingLaunch
  | BrowserTrainingCheckpointOpen
  | BrowserMnistInference
  | BrowserImageUploadInference
  | BrowserGenericInference
  | BrowserCheckpointCompare
  | BrowserRlAnimation
  | BrowserRlTrajectoryReplay
  | BrowserAdversarialPlay
  | BrowserAdversarialReplay
  | BrowserTuningSweepControl
  | BrowserTuningTrialPromote
  deriving stock (Eq, Show, Enum, Bounded)

allBrowserProductInteractions :: [BrowserProductInteraction]
allBrowserProductInteractions = [minBound .. maxBound]

-- | The canonical adversarial games whose boards, legal moves, MCTS visit
-- distributions, and interactive replay the adversarial product cells cover.
browserAdversarialGames :: [Text]
browserAdversarialGames = ["connect4", "othello", "hex", "gomoku"]

-- | Human-readable description of each browser/product interaction, used by the
-- live report card / e2e assertions; never empty.
browserProductInteractionLabel :: BrowserProductInteraction -> Text
browserProductInteractionLabel interaction = case interaction of
  BrowserTrainingLaunch -> "launch every canonical SL training workflow and observe live events"
  BrowserTrainingCheckpointOpen -> "open the produced checkpoint and inspect its metadata"
  BrowserMnistInference -> "run MNIST stroke inference through the checkpoint"
  BrowserImageUploadInference -> "upload CIFAR / Tiny ImageNet images and classify them"
  BrowserGenericInference -> "run generic tensor inference through a checkpoint"
  BrowserCheckpointCompare -> "swap and compare two checkpoints' outputs"
  BrowserRlAnimation -> "animate live RL environment frames and reward distributions"
  BrowserRlTrajectoryReplay -> "record an RL trajectory and scrub/replay it"
  BrowserAdversarialPlay -> "play every canonical game against a checkpointed AlphaZero policy"
  BrowserAdversarialReplay -> "replay a completed game from its persisted transcript"
  BrowserTuningSweepControl -> "launch and control a bounded tuning sweep with live frontier/heatmap"
  BrowserTuningTrialPromote -> "promote a trial to a checkpointed run and verify it is usable"

-- | Every browser/product interaction crossed with every substrate, in
-- deterministic order — the per-substrate product matrix the live Playwright
-- lane iterates.
browserProductMatrix :: [(BrowserProductInteraction, Substrate)]
browserProductMatrix =
  [ (interaction, substrate)
  | interaction <- allBrowserProductInteractions
  , substrate <- allSubstrates
  ]
