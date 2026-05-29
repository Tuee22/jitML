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
        { replicas = 1
        , cpuRequest = "50m"
        , cpuLimit = "250m"
        , memoryRequest = "128Mi"
        , memoryLimit = "256Mi"
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
