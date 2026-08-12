# Phase 59: Stateless `Deployment`, Pod Anti-Affinity, Per-Substrate Dhall

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Stateless Deployment, Pod Anti-Affinity, Per-Substrate Dhall. Single-session phase migrated from legacy Sprint 5.6 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

**Current topology note (2026-08-09):** the stateless Deployment, scoped
anti-affinity, substrate Dhall, and rolling-update constraints remain Done.
Phase `69` replaced the three-Engine Linux default with one profile-driven
Engine; no Phase `59` closure claim is used as evidence for that new count.

## Sprint 59.1: Stateless `Deployment`, Pod Anti-Affinity, Per-Substrate Dhall [✅ Done]

**Status**: Done
**Superseded for HA scheduling by**: Sprint `5.16`, which owns the current
one-numerical-worker-per-Kubernetes-node invariant.
**Implementation**: `chart/templates/deployment-jitml-service.yaml`,
`src/JitML/Service/ConfigMap.hs`, `src/JitML/Service/BootConfig.hs`,
`src/JitML/App.hs`
**Docs to update**: `documents/engineering/daemon_architecture.md`,
`documents/engineering/cluster_topology.md`

### Objective

Land the stateless `Deployment` shape with required pod anti-affinity at
`topologyKey: kubernetes.io/hostname`, plus bootstrap-rendered per-substrate
Dhall configs.

### Deliverables

- Historical compact `Deployment/jitml-service` with `replicas: 1` default and
  required pod anti-affinity at hostname topology. Sprint `5.16` replaces this
  as the current HA target by enforcing at most one numerical ML compute worker
  per Kubernetes node while other roles may scale separately. **Not** a
  `StatefulSet` — durable state lives entirely in MinIO and Pulsar.
- Rolling updates use `maxSurge: 0` and `maxUnavailable: 1` so the required
  anti-affinity does not deadlock a single-node development cluster during a
  replacement rollout.
- `runtimeClassName: nvidia` only when substrate is `linux-cuda`.
- `jitml bootstrap --<substrate>` renders
  `./.build/conf/cluster/<substrate>.dhall` and
  `chart/templates/configmap-jitml-service.yaml`; the checked-in
  `chart/local/jitml-service/templates/configmap.yaml` carries the same
  current Dhall surface for the live Helm chart.
- The cluster Dhall declares `residency = < Cluster | Host >.Cluster`,
  `inferenceMode = < SelfInference | ForwardToHost >.SelfInference` for
  Linux substrates, and
  `< SelfInference | ForwardToHost >.ForwardToHost` for Apple.
- `jitml bootstrap --apple-silicon` also renders
  `./.build/conf/host/apple-silicon.dhall`; live bootstrap patches the chosen
  edge port so the host daemon can reach Pulsar and MinIO. Generated
  host-resident Dhall renders `httpListener = None { host : Text, port : Natural }`
  so the standalone file loads without an out-of-scope type alias.
- Linux substrates do not render a host-level Dhall file; all JIT operations
  happen in the cluster and the daemon knows that from its ConfigMap Dhall.
- Deployment template mounts `./.build/` from the compact hostPath into the pod
  at `/opt/build/` so the JIT cache is shared; Sprint `3.6` owns extending the
  mount materialization to every HA node that can run jitML workloads.
- `chart/local/jitml-demo/templates/deployment.yaml` is the sibling Deployment
  for the Webapp role workload; Phase `11` owns the current frontend/demo
  scaffold and target HTTP server behavior.

### Validation

1. `chart/templates/deployment-jitml-service.yaml` renders the stateless
   Deployment surface.
2. `jitml bootstrap --<substrate>` materializes the service ConfigMap and
   Dhall files.
3. `jitml-integration` confirms the Deployment renderer uses
   `requiredDuringSchedulingIgnoredDuringExecution` with
   `topologyKey: kubernetes.io/hostname`, not advisory preferred
   anti-affinity.
4. Historical Linux CPU validation on 2026-05-19 completed
   `jitml bootstrap --linux-cpu`, upgraded the local Helm chart with the typed
   Dhall ConfigMap, rolled out a single `jitml-service` pod, and verified
   `/healthz`, `/readyz`, and `/metrics` through a port-forward.
5. 2026-05-23 live Linux CPU validation on the single-node topology: `jitml
   bootstrap --linux-cpu` completes a full live phased rollout (Postgres
   operator + `harbor-pg` ready, Harbor up against the external Postgres,
   MinIO, Pulsar with broker-embedded WebSocket, kube-prometheus-stack,
   TensorBoard, `jitml-service`, `jitml-demo`) and writes
   `./.build/runtime/cluster-publication.json` with all seven components
   `ready` on `edge_port: 9091`. The `jitml-service` Deployment renders with
   `strategy.rollingUpdate.maxSurge: 0` / `maxUnavailable: 1` and required
   `podAntiAffinity` at `topologyKey: kubernetes.io/hostname`. `kubectl
   rollout restart deployment/jitml-service` triggers a replacement rollout:
   the old `jitml-service-75969d8755-n8tnw` pod terminates before the new
   ReplicaSet's `jitml-service-68d5759bc6-z2vb6` pod schedules — the cluster
   never holds two pods concurrently (no surge pod), and the new pod reaches
   `Running` on `jitml-linux-cpu-control-plane`. `/healthz` returns `ok`,
   `/readyz` returns `ready`, `/metrics` serves the Prometheus surface, and
   the daemon logs `acquired persistent://public/default/training.command.linux-cpu`
   along with the rest of the substrate-scoped subscription plan.
6. 2026-05-23 live Linux CUDA validation on a GPU host (NVIDIA GeForce RTX
   5090, CUDA 12.8): `kind create cluster --config kind/cluster-linux-cuda.yaml`
   produces `jitml-linux-cuda-control-plane`; the repo-local kubeconfig lands
   at `./.build/jitml-linux-cuda.kubeconfig`; `kind load docker-image
   jitml:local` registers the substrate image on the node; `kubectl apply`
   materializes `RuntimeClass/nvidia`; `helm template chart/local/jitml-service
   --set substrate=linux-cuda` renders the service `Deployment`, ConfigMap,
   ServiceAccount/Role/RoleBinding, and Service; `kubectl apply` rolls them
   out into namespace `platform`; the `jitml-service-*` pod reaches `Running`
   on `jitml-linux-cuda-control-plane` with `runtimeClassName: nvidia`,
   `NVIDIA_VISIBLE_DEVICES=all`, `NVIDIA_DRIVER_CAPABILITIES=compute,utility`,
   and required pod anti-affinity at `topologyKey: kubernetes.io/hostname`;
   `kubectl exec` inside the service container reports
   `GPU 0: NVIDIA GeForce RTX 5090` via `nvidia-smi -L`; `/healthz` returns
   `ok` and `/metrics` serves the Prometheus surface (`/readyz` returns 503
   without Pulsar/MinIO behind the daemon, which is expected in this
   focused RuntimeClass-path validation).
7. `cabal test jitml-integration` verifies both cluster and Apple host rendered
   `BootConfig` files round-trip through the Dhall loader, including the
   host-resident `None { host : Text, port : Natural }` listener form.
8. `cabal test jitml-daemon-lifecycle` verifies a zero-budget bounded daemon
   batch exits without consuming broker messages, supporting
   `jitml service --consume-once 0` as an acquisition-only validation run.
9. 2026-05-23 live Apple Silicon validation runs
   `./bootstrap/apple-silicon.sh up` against the local single-node Kind
   topology. The stage-0 gates pass on macOS arm64, `./.build/jitml` is built
   host-native, Docker builds `jitml:local` with the in-container
   `jitml check-code` gate, it is retagged as `jitml-demo:local`, both tags
   are loaded into Kind, the live phased rollout executes 110 steps, and
   `./.build/runtime/cluster-publication.json` records all seven components
   `ready` on `edge_port: 9090`. The regenerated
   `./.build/conf/host/apple-silicon.dhall` contains routed edge coordinates
   on `127.0.0.1:9090` and the self-contained
   `httpListener = None { host : Text, port : Natural }` value.
10. 2026-05-23 live Apple Silicon host validation runs
    `./.build/jitml service --config ./.build/conf/host/apple-silicon.dhall --consume-once 0`
    host-native. The run derives `ws://127.0.0.1:9090/pulsar/ws`, `/minio/s3`,
    Harbor, and repo-local kubeconfig settings from the patched Dhall, passes
    MinIO / Harbor / kubectl read-only probes, subscribes to
    `persistent://public/default/inference.command.apple-silicon` as
    `jitml-host`, reports `/healthz`, `/readyz`, and `/metrics`, and exits after
    draining zero messages.

### Remaining Work

No sprint-owned Phase `5.6` Remaining Work remains.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
