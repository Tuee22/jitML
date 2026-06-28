-- Sprint 2.8 / 3.6 — typed cluster resource profile schema.
-- Decoded in Haskell by JitML.Cluster.Resources; the concrete budget lives in
-- ./resources.dhall. `workerCount` sets the HA Kind worker count, and
-- `nodeMemoryMiB` / `nodeCpus` bound each materialized Kind node container
-- (applied via `docker update` after `kind create`).
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
      , workerCount : Natural
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
