-- Sprint 2.8 / Phase 42 — concrete local cluster resource budget (single source
-- of truth). One control-plane plus one worker, with each Kind node capped by
-- the values below. Platform services use the supported one-instance local
-- topology; numerical compute cardinality remains separately
-- constrained by the jitml-service Engine worker placement rules.
-- Edit here to retune; the bootstrap reconciler reads this file at apply time.
let S = ./Schema.dhall

in    { nodeMemoryMiB = 12288
      , nodeCpus = "4"
      , workerCount = 1
      , harbor =
        { replicas = 1
        , cpuRequest = "100m"
        , cpuLimit = "500m"
        , memoryRequest = "256Mi"
        , memoryLimit = "512Mi"
        }
      , minio =
        { replicas = 1
        , cpuRequest = "100m"
        , cpuLimit = "500m"
        , memoryRequest = "512Mi"
        , memoryLimit = "1Gi"
        }
      , pulsar =
        { replicas = 1
        , cpuRequest = "100m"
        , cpuLimit = "500m"
        , memoryRequest = "512Mi"
        , memoryLimit = "1Gi"
        }
      , postgres =
        { replicas = 1
        , cpuRequest = "200m"
        , cpuLimit = "500m"
        , memoryRequest = "512Mi"
        , memoryLimit = "1Gi"
        }
      , prometheus =
        { replicas = 1
        , cpuRequest = "100m"
        , cpuLimit = "500m"
        , memoryRequest = "512Mi"
        , memoryLimit = "1Gi"
        }
      , grafana =
        { replicas = 1
        , cpuRequest = "50m"
        , cpuLimit = "250m"
        , memoryRequest = "256Mi"
        , memoryLimit = "512Mi"
        }
      , jitmlService =
        { replicas = 1
        , cpuRequest = "500m"
        , cpuLimit = "2"
        , memoryRequest = "1Gi"
        , memoryLimit = "2Gi"
        }
      , jitmlDemo =
        -- Sprint 14.1 — the demo serves checkpoint-backed inference by
        -- JIT-compiling the Dense2D weighted kernel in-pod on first use; the
        -- g++/oneDNN compile OOM-kills a 256Mi pod, so the budget is raised to
        -- 3Gi/2cpu (validated 2026-06-17: live linux-cpu Playwright 11/11).
        { replicas = 1
        , cpuRequest = "250m"
        , cpuLimit = "2"
        , memoryRequest = "512Mi"
        , memoryLimit = "3Gi"
        }
      , tensorboard =
        { replicas = 1
        , cpuRequest = "50m"
        , cpuLimit = "250m"
        , memoryRequest = "256Mi"
        , memoryLimit = "512Mi"
        }
      }
    : S.ClusterResources
