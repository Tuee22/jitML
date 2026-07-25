# Phase 50: NVIDIA `RuntimeClass` for Linux CUDA

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: NVIDIA RuntimeClass for Linux CUDA. Single-session phase migrated from legacy Sprint 4.7 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 50.1: NVIDIA `RuntimeClass` for Linux CUDA [✅ Done]

**Status**: Done
**Implementation**: `chart/templates/runtimeclass-nvidia.yaml`,
`src/JitML/Cluster/Kind.hs`, `kind/cluster-linux-cuda.yaml`,
`kind/nvidia-container-runtime/config.toml`,
`src/JitML/Service/ConfigMap.hs`,
`chart/local/jitml-service/templates/deployment.yaml`
**Docs to update**: `documents/engineering/cluster_topology.md`

### Objective

Add the `RuntimeClass nvidia` and bind it to the Linux CUDA node label
`jitml.runtime/gpu=true`. The substrate image (`jitml:local`) is unchanged —
target CUDA image hardening bakes NVCC + cuBLAS + cuDNN unconditionally and
activates them at runtime when the pod is scheduled with
`runtimeClassName: nvidia`.

### Deliverables

- `chart/templates/runtimeclass-nvidia.yaml` declares the `RuntimeClass` with
  `handler: nvidia` and node-selector label `jitml.runtime/gpu=true`.
- The `jitml-service` Deployment renderer sets
  `spec.template.spec.runtimeClassName: nvidia` when substrate is `linux-cuda`.
- The Linux CUDA Kind node (Sprint `3.1`) is labelled
  `jitml.runtime/gpu=true`.
- The Linux CUDA Kind config registers containerd runtime handler `nvidia` with
  `BinaryName = "/usr/bin/nvidia-container-runtime"`, mounts the repo-owned
  NVIDIA runtime config into the single node, mounts the host driver root read-only
  at `/run/nvidia/driver`, and mounts the toolkit binaries plus
  `libnvidia-container` / NVML support libraries needed by the node-local
  NVIDIA runtime.
- The repo-owned `kind/nvidia-container-runtime/config.toml` pins
  `mode = "legacy"`, `path = "/usr/bin/nvidia-container-cli"`, and
  `root = "/run/nvidia/driver"` so the hook uses the node-mounted toolkit
  binary while discovering driver files under the read-only host driver root.
- The Linux CUDA `jitml-service` pod sets `NVIDIA_VISIBLE_DEVICES=all` and
  `NVIDIA_DRIVER_CAPABILITIES=compute,utility` alongside
  `runtimeClassName: nvidia`; non-CUDA substrates do not set those fields.

### Validation

1. `chart/templates/runtimeclass-nvidia.yaml` declares the RuntimeClass.
2. The Linux CUDA Kind config carries the GPU node label.
3. Live Linux CPU validation on 2026-05-18 confirms the RuntimeClass manifest
   applies and `kubectl get runtimeclass nvidia` succeeds.
4. `jitml-integration` confirms the Linux CUDA Kind config includes the
   containerd `nvidia` runtime handler, the driver-root mount, toolkit mounts,
   and the GPU node label, while non-CUDA configs do not include NVIDIA
   runtime wiring.
5. 2026-05-23 live validation on a Linux CUDA host (NVIDIA GeForce RTX 5090,
   CUDA 12.8, compute capability `12.0`, Docker `nvidia` runtime registered):
   `bootstrap/linux-cuda.sh doctor` passes; `kind create cluster --config
   kind/cluster-linux-cuda.yaml` produces a single control-plane node
   `jitml-linux-cuda-control-plane` labelled `jitml.runtime/gpu=true` and
   `jitml.substrate/linux-cuda=true`. The node carries containerd runtime
   handler `nvidia` with `BinaryName = /usr/bin/nvidia-container-runtime` and
   `SystemdCgroup = true`, the read-only `/run/nvidia/driver` host driver-root
   mount, and the repo-owned `/etc/nvidia-container-runtime/config.toml` with
   `mode = "legacy"`, `path = /usr/bin/nvidia-container-cli`, and
   `root = /run/nvidia/driver`.
6. 2026-05-23 live validation: `kubectl apply -f
   chart/templates/runtimeclass-nvidia.yaml` creates `RuntimeClass/nvidia`;
   the probe pod with `runtimeClassName: nvidia`,
   `NVIDIA_VISIBLE_DEVICES=all`, and `NVIDIA_DRIVER_CAPABILITIES=compute,utility`
   running `nvidia-smi -L` lands on `jitml-linux-cuda-control-plane`, reaches
   phase `Succeeded`, and `kubectl logs nvidia-smi-probe` reports
   `GPU 0: NVIDIA GeForce RTX 5090 (UUID: GPU-e764ef97-32d7-4981-c348-029983c64073)`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
