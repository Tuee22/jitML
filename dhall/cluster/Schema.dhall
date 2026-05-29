-- Sprint 2.8 — typed cluster resource profile schema.
-- Decoded in Haskell by JitML.Cluster.Resources; the concrete budget lives in
-- ./resources.dhall. `nodeMemoryMiB` / `nodeCpus` bound the single kind node
-- container (applied via `docker update` after `kind create`); the per-component
-- budgets size the platform pods so their sum stays under the node cap.
let ComponentBudget : Type =
      { replicas : Natural
      , cpuRequest : Text
      , cpuLimit : Text
      , memoryRequest : Text
      , memoryLimit : Text
      }

let ClusterResources : Type =
      { nodeMemoryMiB : Natural
      , nodeCpus : Text
      , harbor : ComponentBudget
      , minio : ComponentBudget
      , pulsar : ComponentBudget
      , postgres : ComponentBudget
      , prometheus : ComponentBudget
      , grafana : ComponentBudget
      , jitmlService : ComponentBudget
      , jitmlDemo : ComponentBudget
      , tensorboard : ComponentBudget
      }

in  { ComponentBudget = ComponentBudget, ClusterResources = ClusterResources }
