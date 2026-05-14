# Phase 4: Stateful Platform Services

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md),
[development_plan_standards.md](development_plan_standards.md),
[system-components.md](system-components.md),
[phase-0-planning-documentation.md](phase-0-planning-documentation.md),
[phase-3-cluster-substrate-and-routing.md](phase-3-cluster-substrate-and-routing.md),
[phase-5-jitml-service-daemon.md](phase-5-jitml-service-daemon.md),
[phase-10-checkpointing-and-inference.md](phase-10-checkpointing-and-inference.md),
[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
**Generated sections**: none

> **Purpose**: Install and configure the in-cluster stateful platform services —
> Harbor, MinIO, Apache Pulsar, Percona PostgreSQL for packaged services, the
> kube-prometheus-stack, and TensorBoard with MinIO event-storage backing — plus
> the NVIDIA `RuntimeClass` for the Linux CUDA substrate.

## Phase Status

⏸️ **Blocked** on Phase `3` closure. Every service installs through the umbrella
chart and routes through the Envoy Gateway listener established in Phase `3`.

## Phase Summary

This phase populates the umbrella Helm chart's subchart bodies, the MinIO bucket
provisioning block, the Pulsar topic / namespace bootstrap, the Percona PG
operator and Patroni-managed Postgres clusters for packaged services that need
Postgres (jitML itself never writes to a relational DB on its data path), the
kube-prometheus-stack with Grafana datasources and
provisioned dashboards, the jitML-owned TensorBoard chart with MinIO event-
storage backing, and the NVIDIA `RuntimeClass` that binds to nodes labelled
`jitml.runtime/gpu=true`.

## Sprint 4.1: Harbor Subchart and Bootstrap-Phase Install ⏸️

**Status**: Blocked
**Blocked by**: phase-3
**Implementation**: `chart/Chart.yaml`, `chart/values.yaml`,
`chart/templates/harbor-values.yaml`, `src/JitML/Cluster/Phased.hs`
**Docs to update**: `documents/engineering/cluster_topology.md`

### Objective

Install Harbor as the in-cluster image registry, with MinIO as its S3 backend
and Percona PG (Sprint `4.2`) as its database. Routed at `/harbor` (portal) and
`/harbor/api` (API).

### Deliverables

- `chart/Chart.yaml` declares the `harbor` subchart dependency at a pinned
  version.
- Harbor's portal, core, registry, and notary are deployed in the bootstrap
  phase (image-pull from public registries).
- Harbor's S3 backend points at MinIO bucket `harbor-registry` (Sprint `4.3`).
- `jitml bootstrap --<substrate>` builds the `jitml` image, pushes it to
  `harbor.platform.svc.cluster.local/jitml/jitml:<sha>`, and uses that image for
  the cluster daemon rollout.
- HTTPRoute manifests for `/harbor` and `/harbor/api` are generated from the
  route registry (Sprint `3.4`).

### Validation

1. `jitml bootstrap --<substrate>` succeeds; `kubectl get pods -n platform` shows the
   Harbor stack ready.
2. `jitml bootstrap --linux-cpu` lands an image visible in the Harbor portal
   at `127.0.0.1:<edge-port>/harbor`.

## Sprint 4.2: Percona PG Operator and Patroni-Managed Service Postgres ⏸️

**Status**: Blocked
**Blocked by**: 4.1
**Implementation**: `chart/templates/pg-operator-values.yaml`,
`chart/templates/pg-db-harbor.yaml`
**Docs to update**: `documents/engineering/cluster_topology.md`

### Objective

Install the Percona Kubernetes Operator and Patroni-managed HA Postgres clusters
for packaged services that require Postgres. Harbor is the first consumer.
jitML itself never writes to a relational DB on its data path — durable state
lives in MinIO and Pulsar exclusively.

### Deliverables

- `pg-operator` subchart pinned in `chart/Chart.yaml`.
- `PerconaPGCluster` resources are rendered from a typed service-Postgres
  registry; the first entry is `harbor-pg` in namespace `platform`.
- The PG cluster's storage uses the `jitml-manual` StorageClass and the
  manual PVs from Sprint `3.2`.
- Harbor's `database` config block in `chart/templates/harbor-values.yaml`
  points at `harbor-pg`.
- `jitml lint chart` rejects any `PerconaPGCluster` outside the typed
  service-Postgres registry.

### Validation

1. `kubectl get perconapgcluster -n platform` shows `harbor-pg` ready after
   `jitml bootstrap --<substrate>`.
2. Harbor's portal authenticates against the PG cluster.

## Sprint 4.3: MinIO Subchart, Bucket Provisioning, Conditional-Write Server ⏸️

**Status**: Blocked
**Blocked by**: 4.1
**Implementation**: `chart/templates/minio-values.yaml`,
`src/JitML/Storage/Buckets.hs`
**Docs to update**: `documents/engineering/cluster_topology.md`,
`documents/engineering/checkpoint_format.md`

### Objective

Install MinIO in distributed mode (4 replicas), provision the seven jitML
buckets, and pin the server to a release with S3 conditional-write support
(`If-None-Match`, `If-Match`) — `RELEASE.2024-08-26T15-33-07Z` or later.

### Deliverables

- `minio` subchart at the conditional-write-supporting pin in
  `chart/Chart.yaml`.
- Distributed mode with 4 replicas, each backed by a manual PV under
  `./.data/platform/minio/pv_<i>/` (Sprint `3.2`).
- `provisioning.buckets` block creates the seven buckets enumerated in
  [system-components.md → MinIO Bucket
  Layout](system-components.md#minio-bucket-layout): `harbor-registry`,
  `jitml-checkpoints`, `jitml-datasets`, `jitml-transcripts`, `jitml-trials`,
  `jitml-tensorboard`, `jitml-artifacts`.
- `src/JitML/Storage/Buckets.hs` is the typed source for the bucket layout;
  the values file is generated and tracked.
- HTTPRoutes for `/minio/console` and `/minio/s3` (Sprint `3.4`).

### Validation

1. `mc ls minio/` after `jitml bootstrap --<substrate>` lists the seven buckets.
2. `mc admin info minio/` confirms the conditional-write-supporting release.
3. `jitml-integration` exercises `If-None-Match: *` and `If-Match: <etag>`
   against MinIO and asserts the typed `MinIOPreconditionFailed` →
   `SEConflict` translation works.

## Sprint 4.4: Apache Pulsar HA and Topic Bootstrap ⏸️

**Status**: Blocked
**Blocked by**: 4.1
**Implementation**: `chart/templates/pulsar-values.yaml`,
`src/JitML/Cluster/PulsarBootstrap.hs`
**Docs to update**: `documents/engineering/daemon_architecture.md`

### Objective

Install Apache Pulsar in HA shape (3× ZooKeeper, 3× BookKeeper, 3× Broker, 3×
Proxy, WebSocket enabled) and bootstrap the substrate-scoped topic family.

### Deliverables

- `pulsar` subchart at a pinned HA release.
- 3 ZooKeepers, 3 BookKeepers, 3 Brokers, 3 Proxies, WebSocket enabled.
- `src/JitML/Cluster/PulsarBootstrap.hs` declares the typed topic family from
  [system-components.md → Pulsar Topic
  Family](system-components.md#pulsar-topic-family) and reconciles them at
  bootstrap final-phase time via `pulsar-admin` through the typed
  `Subprocess` boundary.
- HTTPRoutes for `/pulsar/admin` and `/pulsar/ws` (Sprint `3.4`).

### Validation

1. `pulsar-admin topics list public/default` after `jitml bootstrap --<substrate>` lists
   the substrate-scoped topics.
2. WebSocket subscribe from `127.0.0.1:<edge-port>/pulsar/ws/v2/consumer/...`
   succeeds.

## Sprint 4.5: kube-prometheus-stack and Provisioned Dashboards ⏸️

**Status**: Blocked
**Blocked by**: 4.1
**Implementation**: `chart/templates/kube-prometheus-stack-values.yaml`,
`chart/templates/grafana-dashboard-*.yaml`,
`chart/templates/prometheus-scrapeconfig-jitml.yaml`,
`src/JitML/Observability/Grafana.hs`,
`src/JitML/Observability/Prometheus.hs`
**Docs to update**: `documents/engineering/daemon_architecture.md`

### Objective

Install the kube-prometheus-stack (Prometheus operator + Grafana) and provision
Grafana dashboards from typed Haskell renderers. Prometheus scrape configs name
the daemon's `/metrics` endpoint.

### Deliverables

- `kube-prometheus-stack` subchart pinned.
- `src/JitML/Observability/Grafana.hs` renders typed dashboards (training
  throughput, RL episode reward, AlphaZero arena win rate, JIT cache hit rate,
  Pulsar consumer lag, MinIO PUT latency, daemon health) into provisioned
  ConfigMaps. Dashboards are generated and tracked by
  `trackingGeneratedPaths`.
- `src/JitML/Observability/Prometheus.hs` declares the typed scrape-target
  list and renders the scrape config.
- HTTPRoutes for `/grafana` and `/prometheus` (Sprint `3.4`).

### Validation

1. `127.0.0.1:<edge-port>/grafana` lists every provisioned dashboard.
2. Hand-editing a dashboard ConfigMap surfaces `AppError DocsCheckDrift` on
   the next `jitml lint files`.

## Sprint 4.6: TensorBoard with MinIO Event Storage and Checkpoint Sidecar ⏸️

**Status**: Blocked
**Blocked by**: 4.3
**Implementation**: `chart/templates/tensorboard-deployment.yaml`,
`chart/templates/tensorboard-service.yaml`,
`src/JitML/Observability/TensorBoard.hs`,
`proto/tensorboard/event.proto`
**Docs to update**: `documents/engineering/daemon_architecture.md`,
`documents/engineering/checkpoint_format.md`

### Objective

Stand up the jitML-owned TensorBoard chart pointed at MinIO bucket
`jitml-tensorboard`, plus the typed event-file writer with shard rotation and
the CBOR checkpoint sidecar at
`jitml-tensorboard/<experiment-hash>/checkpoints/<step>-<manifest-sha>.cbor`.

### Deliverables

- TB pod is stateless; reads MinIO at panel-load time; reschedules freely.
- `proto/tensorboard/event.proto` is vendored from TensorFlow at a pinned
  commit; `proto-lens` generates Haskell bindings.
- `src/JitML/Observability/TensorBoard.hs` implements the TFRecord framing
  per [../README.md → TensorBoard event storage →
  Format](../README.md#format) (uint64 LE length + masked-CRC32C +
  payload + masked-CRC32C). CRC32C is Castagnoli; the mask is TF's standard
  rotation `((crc >> 15) | (crc << 17)) + 0xa282ead8`.
- Bucket layout per [system-components.md → MinIO Bucket
  Layout](system-components.md#minio-bucket-layout) and [../README.md →
  Bucket layout](../README.md#bucket-layout): overlay mode default, isolated
  mode per Dhall knob, HPO trials always isolated by trial-hash.
- Shard rotation: flush at 4 MiB, 10 s, or explicit `flush` (e.g.
  `CheckpointDone`, graceful shutdown, SIGTERM drain). PUTs use `If-None-
  Match: *`; the same `(writer-id, shard-seq)` is idempotent.
- `TbCheckpointMarker` CBOR sidecar (`tcmStep`, `tcmEpoch`, `tcmManifestSha`,
  `tcmExperimentSha`, `tcmTrialSha`, `tcmRunUuid`, `tcmMetricsAtStep`)
  written on every `CheckpointDone`.
- HTTPRoute for `/tensorboard` (Sprint `3.4`).

### Validation

1. After a synthetic training run, the TB UI lists `(tag, step, value)`
   triples sorted canonically.
2. The bit-determinism test from [../README.md → Determinism
   caveat](../README.md#determinism-caveat): two same-substrate same-seed
   runs project to identical `[(tag, step, value)]` lists after canonical
   sort.
3. The CBOR sidecar is present alongside every `CheckpointDone` event.

## Sprint 4.7: NVIDIA `RuntimeClass` for Linux CUDA ⏸️

**Status**: Blocked
**Blocked by**: 3.1, 4.1
**Implementation**: `chart/templates/runtimeclass-nvidia.yaml`
**Docs to update**: `documents/engineering/cluster_topology.md`

### Objective

Add the `RuntimeClass nvidia` and bind it to the Linux CUDA worker label
`jitml.runtime/gpu=true`. The substrate image (`jitml:local`) is unchanged —
NVCC + cuBLAS + cuDNN are baked unconditionally and activate at runtime when
the pod is scheduled with `runtimeClassName: nvidia`.

### Deliverables

- `chart/templates/runtimeclass-nvidia.yaml` declares the `RuntimeClass` with
  `handler: nvidia` and node-selector label `jitml.runtime/gpu=true`.
- The `jitml-service` Deployment template (Sprint `5.6`) sets
  `spec.template.spec.runtimeClassName: nvidia` only when substrate is
  `linux-cuda`.
- The Linux CUDA Kind worker (Sprint `3.1`) is labelled
  `jitml.runtime/gpu=true`.

### Validation

1. After `bootstrap/linux-cuda.sh up`, `kubectl get runtimeclass` lists
   `nvidia`.
2. The `jitml-service` pod on the CUDA substrate scheduler-binds to the
   GPU-labelled worker.

## Doctrine Sections Cited

- [../HASKELL_CLI_TOOL.md → Reconcilers: Idempotent Mutation as a Single Command](../HASKELL_CLI_TOOL.md) (every sprint)
- [../HASKELL_CLI_TOOL.md → Architecture → Subprocesses as Typed Values](../HASKELL_CLI_TOOL.md) (every sprint)
- [../HASKELL_CLI_TOOL.md → Generated Artifacts](../HASKELL_CLI_TOOL.md) (Sprints 4.4, 4.5, 4.6)
- [../HASKELL_CLI_TOOL.md → Capability Classes and Service Errors](../HASKELL_CLI_TOOL.md) (Sprint 4.3 — `If-None-Match` / `If-Match` translation to `SEConflict`)

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/cluster_topology.md` — Harbor / Postgres / MinIO /
  Pulsar / Prometheus / TensorBoard / NVIDIA RuntimeClass narrative.
- `documents/engineering/daemon_architecture.md` — observability surface, the
  typed scrape-target list, the Grafana dashboard renderer.
- `documents/engineering/checkpoint_format.md` — MinIO conditional-write
  protocol pointer; TensorBoard sidecar shape.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- `system-components.md → Stateful Platform Services` and `MinIO Bucket Layout`
  rows move from `⏸️ Blocked` through `🔄 Active` to `✅ Done`.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [development_plan_standards.md](development_plan_standards.md)
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
