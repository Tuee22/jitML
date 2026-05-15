# Phase 3: Cluster Substrate and Routing

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md),
[development_plan_standards.md](development_plan_standards.md),
[system-components.md](system-components.md),
[phase-0-planning-documentation.md](phase-0-planning-documentation.md),
[phase-2-bootstrap-reconciler-and-jit-cache.md](phase-2-bootstrap-reconciler-and-jit-cache.md),
[phase-4-stateful-platform-services.md](phase-4-stateful-platform-services.md),
[phase-5-jitml-service-daemon.md](phase-5-jitml-service-daemon.md),
[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
**Generated sections**: none

> **Purpose**: Stand up the per-substrate Kind cluster shape, the umbrella Helm
> chart skeleton, the `kubernetes.io/no-provisioner` storage discipline, the
> single `127.0.0.1:<edge-port>` Envoy Gateway listener, the typed route registry
> that drives every `HTTPRoute` resource, and the cluster lifecycle reconciler
> consumed by `jitml bootstrap --<substrate>`.

## Phase Status

✅ **Done** for the local renderer and materialization surface. The cluster
substrate consumes the typed prerequisite DAG, the JIT cache mount via
`extraMounts`, and the substrate image machinery from Phase `2`. Live
Kind/Helm rollout against running dependencies remains part of later
cross-cluster validation.

## Phase Summary

This phase delivers the per-substrate Kind cluster configurations, the umbrella
Helm chart skeleton (subchart dependencies pinned but not yet exercised — Phase
`4` adds bodies), the manual-PV storage layout, the Envoy Gateway listener, the
`src/JitML/Routes.hs` route registry as the single source of truth for every
`HTTPRoute`, and the cluster lifecycle reconciler that `jitml bootstrap
--<substrate>` uses to run the phased deploy (Harbor bootstrap → mirror/build →
final rollout) and write `./.build/runtime/cluster-publication.json`.

## Sprint 3.1: Per-Substrate Kind Configs and `extraMounts` ✅

**Status**: Done
**Implementation**: `kind/cluster-apple-silicon.yaml`, `kind/cluster-linux-cpu.yaml`,
`kind/cluster-linux-cuda.yaml`, `src/JitML/Cluster/Kind.hs`
**Docs to update**: `documents/engineering/cluster_topology.md`

### Objective

Lay down the per-substrate Kind configs (single control-plane + one worker), the
`kindest/node` pin (mirrored into a `cabal.project` comment), the `extraMounts`
binding host `./.build/` into the worker, and the Linux CUDA worker label
`jitml.runtime/gpu=true`.

### Deliverables

- Each Kind config carries `name: jitml-<substrate>`, one control-plane node,
  one worker node, the pinned `kindest/node` image, and `extraMounts:
  - hostPath: ./.build, containerPath: /jitml/.build`.
- Linux CUDA worker carries `kubeadmConfigPatches` adding the
  `node-labels: jitml.runtime/gpu=true` line so the NVIDIA `RuntimeClass`
  binds.
- The edge port mapping (`extraPortMappings`) maps host
  `127.0.0.1:<edge-port>` → worker `30090` (NodePort).
- `src/JitML/Cluster/Kind.hs` renders the Kind config from the typed
  `KindConfig` ADT (substrate, kindest pin, edge-port lease, GPU label flag);
  this sprint promotes the `kind/cluster-*.yaml` generated files into active
  tracking so `jitml docs generate` owns them.
- `kindest/node` mirror-pin comment in `cabal.project` is enforced by
  `jitml lint chart`.

### Validation

1. `kind create cluster --config kind/cluster-apple-silicon.yaml` succeeds and
   the worker mounts `./.build/` at `/jitml/.build`.
2. The CUDA worker's `kubectl get nodes --show-labels` includes
   `jitml.runtime/gpu=true`.
3. Drift between `kind/cluster-<substrate>.yaml`'s `kindest/node` pin and the
   `cabal.project` comment fails `jitml lint chart`.

## Sprint 3.2: `kubernetes.io/no-provisioner` Storage and Manual PVs ✅

**Status**: Done
**Implementation**: `chart/templates/storageclass-jitml-manual.yaml`,
`chart/templates/pv-platform-minio.yaml`,
`chart/templates/pv-platform-pulsar-bookkeeper.yaml`,
`chart/templates/pv-platform-pulsar-zookeeper.yaml`,
`src/JitML/Cluster/Storage.hs`, `src/JitML/Lint/Chart.hs`
**Docs to update**: `documents/engineering/cluster_topology.md`

### Objective

Lay down the `jitml-manual` StorageClass (no provisioner), the manual PV
templates per StatefulSet replica, the on-disk layout
`./.data/<namespace>/<StatefulSet>/pv_<replica-int>/`, and the chart-shape lint
that enforces the discipline.

### Deliverables

- `jitml-manual` StorageClass with `provisioner:
  kubernetes.io/no-provisioner`, `volumeBindingMode: WaitForFirstConsumer`, and
  no other provisioner anywhere in the chart.
- Manual PV templates per StatefulSet (MinIO 4 replicas, Pulsar BookKeeper 3
  replicas, Pulsar ZooKeeper 3 replicas) with explicit `claimRef.namespace` and
  `claimRef.name`. Each `hostPath` is
  `./.data/<namespace>/<StatefulSet>/pv_<replica-int>/`.
- DNS-1123-compatible PV resource names:
  `<namespace>-<statefulset>-pv-<int>`.
- `src/JitML/Cluster/Storage.hs` is the typed source for the PV layout; the
  templates are generated and tracked by `trackingGeneratedPaths`.
- `jitml lint chart` (the Sprint `1.4` scaffold plus this sprint's real chart
  checks) enforces every invariant: the only
  StorageClass is `jitml-manual`, every PV has explicit `claimRef`, every PVC
  is created only by a StatefulSet's `volumeClaimTemplates`, every hostPath
  matches the regex.

### Validation

1. `jitml lint chart` exits `0` on a freshly-generated chart.
2. Hand-introducing a freestanding PVC, a `kubernetes.io/aws-ebs`
   StorageClass, or a non-conformant hostPath surfaces a typed `AppError
   ChartLintFailed`.
3. `jitml bootstrap --<substrate>` against an empty `./.data/` creates the
   hostPath directories with the expected layout.

## Sprint 3.3: Envoy Gateway and Single `127.0.0.1:<edge-port>` Listener ✅

**Status**: Done
**Implementation**: `chart/templates/gatewayclass-jitml.yaml`,
`chart/templates/gateway-jitml-edge.yaml`,
`chart/templates/envoyproxy-jitml-edge.yaml`, `src/JitML/Cluster/Gateway.hs`
**Docs to update**: `documents/engineering/cluster_topology.md`

### Objective

Stand up the Envoy Gateway controller deployment and the single edge listener
at `127.0.0.1:<edge-port>` backed by the in-cluster NodePort `30090`.

### Deliverables

- `GatewayClass/jitml-gateway` declares the Envoy Gateway controller as the
  controller name.
- `Gateway/jitml-edge` listens on port `<edge-port>` (templated; the actual port
  is selected by `jitml bootstrap --<substrate>` starting at `9090` and incremented until
  available).
- `EnvoyProxy/jitml-edge` is a NodePort service with `externalTrafficPolicy:
  Cluster`, port `30090` in-cluster.
- The `gateway-helm` subchart in `chart/Chart.yaml` provides the Envoy Gateway
  controller.
- `src/JitML/Cluster/Gateway.hs` is the typed source for the Gateway shape;
  templates are generated and tracked.

### Validation

1. After `jitml bootstrap --<substrate>`, `kubectl get gateway -n platform` lists
   `jitml-edge` with the chosen port.
2. `curl http://127.0.0.1:<edge-port>/` returns the demo backend response once
   Phase `11` is present; otherwise the bootstrap-phase chart serves an
   intentional not-found `404`.

## Sprint 3.4: Typed Route Registry and Generated `HTTPRoute` Manifests ✅

**Status**: Done
**Implementation**: `src/JitML/Routes.hs`, `chart/templates/httproute-*.yaml`,
`src/JitML/Lint/Chart.hs`
**Docs to update**: `documents/engineering/cluster_topology.md`

### Objective

Stand up the typed route registry as the source of truth for every `HTTPRoute`
resource. Hand-edited HTTPRoute YAML in the chart is hlint-forbidden.

### Deliverables

- `src/JitML/Routes.hs` enumerates every routed surface from
  [system-components.md → CLI Doctrine
  Components](system-components.md#cli-doctrine-components) and the README's
  edge route table:
  - `/` → `jitml-demo:80`
  - `/api` → `jitml-demo:80`
  - `/api/ws` → `jitml-demo:80` (WebSocket)
  - `/tensorboard` → `tensorboard:6006` (rewrite to `/`)
  - `/grafana` → `grafana:3000` (rewrite to `/`)
  - `/prometheus` → `prometheus:9090` (rewrite to `/`)
  - `/harbor` → `jitml-harbor-portal:80` (rewrite to `/`)
  - `/harbor/api` → `jitml-harbor-core:80` (rewrite to `/api`)
  - `/minio/console` → `jitml-minio-console:9090` (rewrite to `/`)
  - `/minio/s3` → `jitml-minio:9000` (rewrite to `/`)
  - `/pulsar/admin` → `jitml-pulsar-proxy:80` (rewrite to `/admin`)
  - `/pulsar/ws` → `jitml-pulsar-proxy:80` (WebSocket; rewrite to `/ws`)
- `chart/templates/httproute-*.yaml` is generated from the registry and tracked
  by `trackingGeneratedPaths`. Hand edits fail `jitml lint files`.
- `documents/engineering/cluster_topology.md` carries the route table inside a
  `<!-- jitml:cluster.routes:start -->` / `<!-- jitml:cluster.routes:end -->`
  block, regenerated from the registry.
- `src/JitML/Lint/Chart.hs` enforces route/manifest shape against
  `src/JitML/Routes.hs` so generated HTTPRoute YAML stays aligned.

### Validation

1. `jitml docs check` exits `0` after `jitml docs generate`.
2. Hand-editing any `httproute-*.yaml` surfaces `AppError RouteRegistryDrift`
   on the next `jitml lint files`.
3. After `jitml bootstrap --<substrate>`, `curl http://127.0.0.1:<edge-port>/grafana`
   reaches the Grafana service (Phase `4` populates the upstream).

## Sprint 3.5: Cluster Lifecycle Reconciler and Phased Deploy ✅

**Status**: Done
**Implementation**: `src/JitML/Cluster/Publication.hs`,
`src/JitML/Cluster/{Kind,Storage,Gateway,PulsarBootstrap}.hs`,
`src/JitML/App.hs`, `src/JitML/Bootstrap.hs`
**Docs to update**: `documents/engineering/cluster_topology.md`,
`documents/engineering/daemon_architecture.md`

### Objective

Land the cluster lifecycle reconciler used by `jitml bootstrap --<substrate>`.
`jitml cluster up` may remain as a lower-level lifecycle command, but the
canonical full-stack rollout starts at `jitml bootstrap --<substrate>` so image
build/upload, Dhall rendering, cluster daemon deployment, and Apple host-daemon
handoff are sequenced together. Reconciler discipline: re-running on a
steady-state cluster is a no-op (exit code `3`).

### Deliverables

- Cluster lifecycle plan steps:
  1. Reconcile `cluster` prerequisite subgraph (Sprint `2.2`).
  2. Write `kind/cluster-<substrate>.yaml` from the typed config (Sprint `3.1`).
  3. `kind create cluster --config kind/cluster-<substrate>.yaml --kubeconfig
     ./.build/jitml.kubeconfig` (the CLI never touches `~/.kube/config`).
  4. Write the `jitml-manual` StorageClass and the manual PVs.
  5. Run the phased Helm rollout (Sprint `3.5`).
  6. Lease the edge port starting at `9090` and write
     `./.build/runtime/cluster-publication.json`.
- Phased deploy:
  1. **Harbor phase**: bring up Harbor plus the Percona operator and
     Patroni-managed Postgres required by packaged services, using only the
     public pulls needed to make Harbor available.
  2. **Mirror/build phase**: mirror third-party images into Harbor; build the
     `jitml` container and `jitml-demo` container; push both to Harbor.
  3. **Final phase**: MinIO, Pulsar, Envoy Gateway, kube-prometheus-stack,
     TensorBoard, the `jitml-service` workload, and the `jitml-demo` workload
     all pull exclusively from local Harbor.
- `jitml bootstrap --apple-silicon` renders both host Dhall and cluster ConfigMap
  Dhall; after the edge port is known it patches the host Dhall so the host
  daemon can reach Pulsar and MinIO.
- `jitml bootstrap --linux-cpu|--linux-cuda` renders only the cluster ConfigMap
  Dhall; Linux JIT operations happen entirely in the cluster.
- `jitml cluster down`, `jitml cluster status` round out the lifecycle surface.
- Subsequent `jitml cluster up` invocations on a steady-state cluster exit
  `3` (`AppError ReconcilerNoop`).

### Validation

1. `jitml bootstrap --<substrate> --dry-run` emits the typed plan (every Helm release,
   every Kind operation, every PV write) without side effects.
2. `jitml bootstrap --<substrate>` followed by the same bootstrap exits `0`
   then `3`.
3. After `up`, `./.build/runtime/cluster-publication.json` carries
   `edge_port`, `pulsar_ws_url`, `pulsar_admin_url`, `minio_s3_url`.
4. `jitml cluster status` parses the publication and reports a
   per-component health summary.

## Doctrine Sections Cited

- [../HASKELL_CLI_TOOL.md → Plan / Apply](../HASKELL_CLI_TOOL.md) (Sprint 3.5)
- [../HASKELL_CLI_TOOL.md → Reconcilers: Idempotent Mutation as a Single Command](../HASKELL_CLI_TOOL.md) (Sprint 3.5)
- [../HASKELL_CLI_TOOL.md → Architecture → Subprocesses as Typed Values](../HASKELL_CLI_TOOL.md) (every sprint)
- [../HASKELL_CLI_TOOL.md → Generated Artifacts](../HASKELL_CLI_TOOL.md) (Sprints 3.1, 3.2, 3.3, 3.4)
- [../HASKELL_CLI_TOOL.md → Lint, Format, and Code-Quality Stack](../HASKELL_CLI_TOOL.md) (Sprints 3.2, 3.4)

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/cluster_topology.md` — populate with the per-substrate
  Kind shapes, storage discipline, Envoy Gateway listener, route registry
  contract, and the phased deploy narrative. Add the
  `<!-- jitml:cluster.routes:start -->` block consumed by Sprint `3.4`.
- `documents/engineering/daemon_architecture.md` — link to the publication file
  contract that bootstrap writes on Apple Silicon
  (`./.build/runtime/cluster-publication.json`).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- `system-components.md → Cluster Substrate Components` rows remain aligned
  with the implemented Kind, chart, route, and publication surfaces.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [development_plan_standards.md](development_plan_standards.md)
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
