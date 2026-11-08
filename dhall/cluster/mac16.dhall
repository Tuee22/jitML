-- Explicit 4-vCPU/16-GiB Docker VM profile. The hard envelope is two5-GiB
-- Kind nodes, one4-GiB client job and1536MiB VM overhead. Each node has
-- 1.5 CPUs; the client has one CPU, leaving schedulable platform headroom.
-- Pod limits may
-- overcommit a node; hard parent cgroups protect the VM and readiness/OOM
-- observations still decide whether a rollout succeeds.
let base = ./resources.dhall

in  base
  with nodeMemoryMiB = 5120
  with nodeCpus = "1.5"
  with jobMemoryMiB = 4096
  with jobCpus = "1"
  -- Numerical Jobs live inside a capped Kind node; this is separate from
  -- the external client reservation above. Live fit still needs validation.
  with numericalWorkload.cpuRequest = "250m"
  with numericalWorkload.cpuLimit = "1"
  with numericalWorkload.memoryRequest = "1Gi"
  with numericalWorkload.memoryLimit = "1536Mi"
  -- Keep the frontend on the control plane so it cannot consume the single
  -- compute worker's numerical request headroom during a rollout.
  with scheduleOnControlPlane = True
  with registry.cpuRequest = "50m"
  with registry.memoryRequest = "128Mi"
  with minio.cpuRequest = "100m"
  with minio.memoryRequest = "256Mi"
  with pulsar.cpuRequest = "50m"
  with pulsar.memoryRequest = "128Mi"
  with prometheus.cpuRequest = "50m"
  with prometheus.memoryRequest = "256Mi"
  with grafana.cpuRequest = "25m"
  with grafana.memoryRequest = "128Mi"
  with jitmlService.cpuRequest = "200m"
  with jitmlService.memoryRequest = "512Mi"
  with jitmlDemo.cpuRequest = "100m"
  with jitmlDemo.memoryLimit = "3Gi"
  with tensorboard.cpuRequest = "25m"
  with tensorboard.memoryRequest = "128Mi"
  with gateway.cpuRequest = "25m"
