module PanelRegistry where

import Prelude

import Data.Array as Array
import Data.Maybe (Maybe)
import Effect.Aff (Aff)
import Panels.CheckpointCompare as CheckpointCompare
import Panels.Checkpoints as Checkpoints
import Panels.Cifar as Cifar
import Panels.Connect4 as Connect4
import Panels.GenericInference as GenericInference
import Panels.Mnist as Mnist
import Panels.Replay as Replay
import Panels.Rl as Rl
import Panels.Training as Training
import Panels.Tune as Tune
import Panels.Workflow as Workflow

-- | SPA-side registry of demo panels. Each entry's `hash` matches the
-- | `panelName` constant exported by the corresponding `Panels.X`
-- | module; the router in `Main.purs` and the portals home page in
-- | `Panels.Portals` both read from this single list.

type PanelEntry = { hash :: String, label :: String, mount :: Aff (Aff Unit) }

panels :: Array PanelEntry
panels =
  [ { hash: Mnist.panelName, label: "MNIST", mount: Mnist.mount }
  , { hash: GenericInference.panelName, label: "Generic inference", mount: GenericInference.mount }
  , { hash: CheckpointCompare.panelName, label: "Checkpoint compare", mount: CheckpointCompare.mount }
  , { hash: Cifar.panelName, label: "CIFAR", mount: Cifar.mount }
  , { hash: Training.panelName, label: "Training", mount: Training.mount }
  , { hash: Tune.panelName, label: "Tune", mount: Tune.mount }
  , { hash: Rl.panelName, label: "RL", mount: Rl.mount }
  , { hash: Connect4.panelName, label: "Connect4", mount: Connect4.mount }
  , { hash: Checkpoints.panelName, label: "Checkpoint browse", mount: Checkpoints.mount }
  , { hash: Workflow.panelName, label: "Workflow status", mount: Workflow.mount }
  , { hash: Replay.panelName, label: "Transcript replay", mount: Replay.mount }
  ]

mountForHash :: String -> Maybe (Aff (Aff Unit))
mountForHash hash =
  _.mount <$> Array.find (\entry -> entry.hash == hash) panels
