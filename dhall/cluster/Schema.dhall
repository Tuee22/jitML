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
      , jobMemoryMiB : Natural
      , jobCpus : Text
      , systemReserveMiB : Natural
      , nodeSystemMemoryMiB : Natural
      , nodeSystemCpus : Text
      -- True permits ordinary control-plane Pods and pins the non-compute
      -- webapp there, preserving request headroom on the compute worker.
      , scheduleOnControlPlane : Bool
      , registry : ComponentBudget
      , minio : ComponentBudget
      , pulsar : ComponentBudget
      , postgres : ComponentBudget
      , prometheus : ComponentBudget
      , grafana : ComponentBudget
      , jitmlService : ComponentBudget
      , jitmlDemo : ComponentBudget
      , tensorboard : ComponentBudget
      , supporting : ComponentBudget
      , gateway : ComponentBudget
      , numericalWorkload : ComponentBudget
      }

in  { ComponentBudget = ComponentBudget, ClusterResources = ClusterResources }
