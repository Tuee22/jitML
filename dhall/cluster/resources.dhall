-- Sprint 2.8 — concrete cluster resource budget (single source of truth).
-- Sized for a ~16 GiB single-node host: a ~10 GiB kind-node cap with the heavy
-- subcharts right-sized so the sum of pod memory limits stays under the cap.
-- Edit here to retune; the bootstrap reconciler reads this file at apply time.
let S = ./Schema.dhall

in    { nodeMemoryMiB = 10240
      , nodeCpus = "6"
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
