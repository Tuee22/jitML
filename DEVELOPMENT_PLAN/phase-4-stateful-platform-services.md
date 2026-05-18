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

🔄 **Active**. The phase contributes the stateful-platform-services half of
[Exit Definition](README.md#exit-definition) item 3 (Harbor up first;
MinIO, Pulsar, Postgres, observability, TensorBoard, NVIDIA RuntimeClass
all installed and routable through the single Envoy Gateway socket).
**Met today**: typed chart-values, manual-PV templates, route templates,
deployment templates, the MinIO bucket registry, the Pulsar topic
registry/command renderer, the Grafana dashboard renderer, the TensorBoard
deployment/event-key renderer, and the NVIDIA RuntimeClass manifest are in
place; MinIO subchart values live under `minio:` in `chart/values.yaml`;
`jitml lint chart` rejects values files under `chart/templates/`. The
typed service-Postgres registry (`JitML.Cluster.PostgresRegistry`) and
its `validateRegisteredPostgres` lint helper are checked in;
`JitML.Cluster.PulsarBootstrap.pulsarTopicCreateSubprocess` is the
typed `pulsar-admin topics create` subprocess. The capability classes
(`HasMinIO`, `HasPulsar`, `HasHarbor`, `HasKubectl`) now expose the
full doctrine-required method set. **Unmet today**: every Sprint `4.x`
owes live readiness against a real Kind + Helm rollout. Detailed
remaining work lives in each sprint's `### Remaining Work` block below.

## Phase Summary

This phase populates the umbrella Helm chart's subchart bodies, the MinIO bucket
provisioning block, the Pulsar topic / namespace bootstrap, the Percona PG
operator and Patroni-managed Postgres clusters for packaged services that need
Postgres (jitML itself never writes to a relational DB on its data path), the
kube-prometheus-stack with Grafana datasources and
provisioned dashboards, the jitML-owned TensorBoard chart with MinIO event-
storage backing, and the NVIDIA `RuntimeClass` that binds to nodes labelled
`jitml.runtime/gpu=true`.

## Sprint 4.1: Harbor Subchart and Bootstrap-Phase Install 🔄

**Status**: Active
**Implementation**: `chart/Chart.yaml`, `chart/values.yaml`,
`src/JitML/Cluster/Publication.hs`, `src/JitML/Bootstrap.hs`
**Docs to update**: `documents/engineering/cluster_topology.md`

### Objective

Install Harbor as the in-cluster image registry, with MinIO as its S3 backend
and Percona PG (Sprint `4.2`) as its database. Routed at `/harbor` (portal) and
`/harbor/api` (API).

### Deliverables

- `chart/Chart.yaml` declares the `harbor` subchart dependency at a pinned
  version.
- Current `chart/values.yaml` provides the local Harbor values scaffold and uses
  the `jitml-manual` StorageClass for registry persistence.
- Target live bootstrap deploys Harbor's portal, core, registry, and notary in
  the bootstrap phase, then configures its S3 backend against MinIO bucket
  `harbor-registry` (Sprint `4.3`).
- Current `jitml bootstrap --<substrate>` materializes bootstrap files only. The
  target live apply path builds the `jitml` image, pushes it to
  `harbor.platform.svc.cluster.local/jitml/jitml:<sha>`, and uses that image for
  the cluster daemon rollout.
- HTTPRoute manifests for `/harbor` and `/harbor/api` are generated from the
  route registry (Sprint `3.4`).

### Validation

1. `chart/Chart.yaml` declares the Harbor subchart dependency.
2. The local route registry renders `/harbor` and `/harbor/api` routes.
3. Live validation (target): Harbor portal/core/registry/notary all reach
   Ready in the bootstrap phase, S3 backend is configured against MinIO
   bucket `harbor-registry`, and the `jitml` image pushes successfully to
   `harbor.platform.svc.cluster.local/jitml/jitml:<sha>`.

### Remaining Work

- The typed `helm install` subprocess for Harbor lives in
  `JitML.Cluster.Helm.helmInstallSubprocess` and is sequenced first
  in `JitML.Cluster.Helm.phasedReleases` (HarborPhase). The
  pending work is invoking it from `JitML.Bootstrap` against a live
  cluster.
- Implement the readiness check that waits for Harbor portal / core /
  registry / notary to all report Ready.
- Implement the live image-build → tag → push flow against local Harbor
  via `HasHarbor.{harborPushImage,harborPullImage,harborListImages}`.
- Integration coverage exercising a real push and subsequent pull from
  Harbor through the `HasHarbor` capability class.

## Sprint 4.2: Percona PG Operator and Patroni-Managed Service Postgres 🔄

**Status**: Active
**Implementation**: `chart/Chart.yaml`, `chart/values.yaml`,
`chart/templates/pv-platform-harbor-pg-*.yaml`
**Docs to update**: `documents/engineering/cluster_topology.md`

### Objective

Install the Percona Kubernetes Operator and Patroni-managed HA Postgres clusters
for packaged services that require Postgres. Harbor is the first consumer.
jitML itself never writes to a relational DB on its data path — durable state
lives in MinIO and Pulsar exclusively.

### Deliverables

- `pg-operator` subchart pinned in `chart/Chart.yaml`.
- Current local storage includes manual PV templates for `platform/harbor-pg`.
- Target `PerconaPGCluster` resources are rendered from a typed service-Postgres
  registry; the first entry is `harbor-pg` in namespace `platform`, using the
  `jitml-manual` StorageClass and manual PVs from Sprint `3.2`.
- Target Harbor database values point at `harbor-pg`.
- Target `jitml lint chart` rejects any `PerconaPGCluster` outside the typed
  service-Postgres registry.

### Validation

1. `chart/Chart.yaml` declares the `pg-operator` subchart dependency.
2. `chart/templates/pv-platform-harbor-pg-*.yaml` provides the manual PV
   surface for service Postgres storage.
3. Live validation (target): `PerconaPGCluster` `harbor-pg` reaches Ready
   in namespace `platform`, Harbor's database values point at the live
   service, and `jitml lint chart` rejects any `PerconaPGCluster` outside
   the typed service-Postgres registry.

### Remaining Work

- `JitML.Cluster.PostgresRegistry.postgresRegistry` is the typed
  service-Postgres registry with `harbor-pg` in namespace `platform` as
  the first entry. `renderPerconaPGCluster` emits the `PerconaPGCluster`
  YAML; `validateRegisteredPostgres` is the lint helper that rejects
  unknown cluster names. **The lint rule is now wired into
  `JitML.Lint.Chart.checkPerconaCluster`** — `jitml lint chart` rejects
  any `PerconaPGCluster` in `chart/templates/*.yaml` whose name is not
  declared in `postgresRegistry`, with the remedy pointing at
  `src/JitML/Cluster/PostgresRegistry.hs`.
- The `helm install` of the Percona operator is sequenced in
  `JitML.Cluster.Helm.phasedReleases` (HarborPhase, `harbor-pg` row).
  The rendered `PerconaPGCluster` YAML now flows through
  `HasKubectl.kubectlApply` (stdin-piped) — validated via
  `jitml-integration` under `JITML_LIVE_E2E=1` against the live Kind
  cluster: `kubectl apply --dry-run=client -f -` accepts the YAML
  and reports `harbor-pg`. The live server-side apply requires the
  Percona operator CRD installed (gated by the heavy Helm rollout).
- Implement the readiness check that waits for the Patroni-managed Postgres
  cluster to reach Ready and exposes its DSN to Harbor.

## Sprint 4.3: MinIO Subchart, Bucket Provisioning, Conditional-Write Server 🔄

**Status**: Active
**Implementation**: `chart/values.yaml`,
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
  `chart/values.yaml` carries the Helm `minio.provisioning.buckets` block.
- Bootstrap materialization removes legacy standalone MinIO values fragments
  from `chart/templates/minio-values.yaml` and `chart/minio-values.yaml` so the
  chart has one values owner.
- HTTPRoutes for `/minio/console` and `/minio/s3` (Sprint `3.4`).

### Validation

1. `src/JitML/Storage/Buckets.hs` enumerates the seven current bucket names.
2. `chart/values.yaml` includes each typed bucket under
   `minio.provisioning.buckets`.
3. `materializeBootstrapFiles` removes legacy standalone MinIO values files
   and remains idempotent on the second pass.
4. The cleanup row in
   [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) is
   marked completed for the standalone values fragment.
5. Live validation (target): the four-replica MinIO StatefulSet reaches
   Ready, the seven buckets exist (verified through `mc ls`), and the
   `HasMinIO` capability class exercises `If-None-Match: *` PUT and
   `If-Match: <etag>` pointer CAS against the running cluster.

### Remaining Work

- The typed `HasMinIO` capability class exposes the full conditional-write
  surface (`putBlobIfAbsent`, `casPointer`, `listObjects`,
  `deleteObject`) with `ETag` newtype. A filesystem-backed instance
  (`JitML.Service.FilesystemMinIO`) honours the same conditional
  semantics — `putBlobIfAbsent` returns `Left (SEConflict ...)` on the
  second PUT (the 412 → `SEConflict` mapping doctrine prescribes), and
  `casPointer` returns `Left (SEConflict ...)` on a stale ETag.
  Validated by `jitml-integration` against a real on-disk temporary
  store. The pending work is the live HTTP-backed instance against a
  running MinIO StatefulSet issued via the typed `helm install` from
  `JitML.Cluster.Helm.helmInstallSubprocess`.
- Implement the `mc`-based or in-process readiness check that confirms the
  seven buckets exist.

## Sprint 4.4: Apache Pulsar HA and Topic Bootstrap 🔄

**Status**: Active
**Implementation**: `chart/values.yaml`,
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
  Family](system-components.md#pulsar-topic-family) and renders the
  `pulsar-admin topics create ...` commands. Executing those commands at
  bootstrap final-phase time remains target live apply behavior.
- HTTPRoutes for `/pulsar/admin` and `/pulsar/ws` (Sprint `3.4`).

### Validation

1. `src/JitML/Cluster/PulsarBootstrap.hs` renders the typed topic-command
   surface.
2. The route registry includes `/pulsar/admin` and `/pulsar/ws`.
3. Live validation (target): the 3× ZooKeeper / 3× BookKeeper / 3× Broker /
   3× Proxy Pulsar StatefulSets reach Ready, `pulsar-admin topics create`
   creates every substrate-scoped topic in
   [system-components.md → Pulsar Topic Family](system-components.md#pulsar-topic-family),
   and the `HasPulsar` capability class subscribes successfully via the
   WebSocket proxy.

### Remaining Work

- `JitML.Cluster.PulsarBootstrap.pulsarTopicCreateSubprocesses` is now
  appended to the typed `liveExecutePhasedRollout` step list in
  `JitML.Bootstrap`, so `jitml bootstrap --<substrate>` under
  `JITML_LIVE_E2E=1` invokes `kubectl exec pulsar-broker-0 -- pulsar-admin
  topics create <topic>` for every registered topic after the phased
  Helm rollout completes.
- The typed `HasPulsar` capability class now exposes
  `pulsarSubscribe`, `pulsarConsume`, `pulsarSeek`,
  `pulsarPublish`, `pulsarAcknowledge` with the `SubscriptionId`
  newtype naming the broker cursor. The pending work is the live
  instance against the running broker.
- Integration coverage exercising at-least-once redelivery + payload-hash
  dedup against a live broker.

## Sprint 4.5: kube-prometheus-stack and Provisioned Dashboards 🔄

**Status**: Active
**Implementation**: `chart/values.yaml`,
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
  Pulsar consumer lag, MinIO PUT latency, daemon health), writes provisioned
  ConfigMaps under `chart/templates/grafana-dashboard-*.yaml`, and protects
  those YAML files through `trackingGeneratedPaths`.
- `src/JitML/Observability/Prometheus.hs` declares the typed scrape-target
  list, renders `chart/templates/prometheus-scrapeconfig-jitml.yaml`, and
  protects it through `trackingGeneratedPaths`.
- HTTPRoutes for `/grafana` and `/prometheus` (Sprint `3.4`).

### Validation

1. `src/JitML/Observability/Grafana.hs` renders the dashboard surface.
2. `src/JitML/Observability/Prometheus.hs` renders the scrape-target
   surface.
3. Live validation (target): the kube-prometheus-stack reaches Ready,
   Grafana serves the provisioned dashboards behind `/grafana`, and
   Prometheus scrapes the `jitml service` `/metrics` endpoint at the
   declared interval.

### Remaining Work

- Bring up the kube-prometheus-stack via `helm install` against the
  cluster.
- Confirm Grafana dashboard ConfigMaps are picked up and rendered behind
  `/grafana`.
- Confirm Prometheus scrapes the daemon's `/metrics` endpoint successfully
  through the Envoy listener.

## Sprint 4.6: TensorBoard with MinIO Event Storage and Checkpoint Sidecar 🔄

**Status**: Active
**Implementation**: `src/JitML/Observability/TensorBoard.hs`,
`proto/tensorboard/event.proto`
**Docs to update**: `documents/engineering/daemon_architecture.md`,
`documents/engineering/checkpoint_format.md`

### Objective

Stand up the local TensorBoard event-key/projection/deployment renderer that the
target TensorBoard chart will consume. The target chart points at MinIO bucket
`jitml-tensorboard`, adds a typed event-file writer with shard rotation, and
writes the CBOR checkpoint sidecar at
`jitml-tensorboard/<experiment-hash>/checkpoints/<step>-<manifest-sha>.cbor`.

### Deliverables

- Current `src/JitML/Observability/TensorBoard.hs` implements deterministic
  event projection, shard-key rendering under `jitml-tensorboard/.../events/`,
  and a TensorBoard Deployment renderer.
- `proto/tensorboard/event.proto` is vendored from TensorFlow for the target
  binding/codegen path; generated Haskell proto bindings are not present yet.
- Target TFRecord framing follows [../README.md → TensorBoard event storage →
  Format](../README.md#format) (uint64 LE length + masked-CRC32C + payload +
  masked-CRC32C). CRC32C is Castagnoli; the mask is TF's standard rotation
  `((crc >> 15) | (crc << 17)) + 0xa282ead8`.
- Target bucket layout per [system-components.md → MinIO Bucket
  Layout](system-components.md#minio-bucket-layout) and [../README.md →
  Bucket layout](../README.md#bucket-layout): overlay mode default, isolated
  mode per Dhall knob, HPO trials always isolated by trial-hash.
- Target shard rotation: flush at 4 MiB, 10 s, or explicit `flush` (e.g.
  `CheckpointDone`, graceful shutdown, SIGTERM drain). PUTs use `If-None-
  Match: *`; the same `(writer-id, shard-seq)` is idempotent.
- Target `TbCheckpointMarker` CBOR sidecar (`tcmStep`, `tcmEpoch`, `tcmManifestSha`,
  `tcmExperimentSha`, `tcmTrialSha`, `tcmRunUuid`, `tcmMetricsAtStep`)
  written on every `CheckpointDone`.
- HTTPRoute for `/tensorboard` (Sprint `3.4`).

### Validation

1. `src/JitML/Observability/TensorBoard.hs` renders deterministic event
   keys and the TensorBoard deployment surface.
2. `proto/tensorboard/event.proto` exists for the target binding path.
3. Live validation (target): TensorBoard pod reaches Ready behind
   `/tensorboard`, reads TFRecord shards from MinIO bucket
   `jitml-tensorboard`, and a `CheckpointDone` event causes the
   `TbCheckpointMarker` CBOR sidecar to land under
   `jitml-tensorboard/<experiment-hash>/checkpoints/`.

### Remaining Work

- The TFRecord framing writer is implemented as
  `JitML.Observability.TensorBoard.encodeTfRecord` (with batch helper
  `encodeTfRecordBatch`); the Castagnoli `crc32cCastagnoli` and TF's
  `maskedCrc32c` mask `((crc >> 15) | (crc << 17)) + 0xa282ead8` are
  exposed and validated by `jitml-unit` against canonical CRC32C
  vectors (empty / single byte / 32 zeros / "123456789") and against a
  TFRecord round-trip that confirms the length / payload byte
  positions.
- Generate Haskell proto bindings from `proto/tensorboard/event.proto`
  via `proto-lens-protoc` once the dep lands.
- Shard rotation is implemented as the pure predicate
  `JitML.Observability.TensorBoard.shouldRotateShard` with knobs
  carried in `ShardRotationLimits` (4 MiB default byte cap, 10 s
  default elapsed cap, `shardExplicitFlush` override). Validated by
  `jitml-unit` against the four-branch decision matrix
  (keep-open / byte-cap / elapsed-cap / explicit-flush). The pending
  wiring is the live IO loop that maintains the running byte/elapsed
  counters and issues `HasMinIO.putBlobBytesIfAbsent` writes keyed by
  `(writer-id, shard-seq)`.
- The typed `TbCheckpointMarker` CBOR sidecar
  (`JitML.Observability.TensorBoard.TbCheckpointMarker` +
  `encodeTbCheckpointMarker` via `Codec.Serialise`) is in place;
  validated for deterministic encoding by `jitml-unit`. The pending
  wiring is plugging `CheckpointDone` events into a writer that calls
  `encodeTbCheckpointMarker` + writes the bytes at
  `checkpointSidecarKey` through `HasMinIO.putBlobBytesIfAbsent`.
- Deploy a TensorBoard `Service` template alongside the Deployment.

## Sprint 4.7: NVIDIA `RuntimeClass` for Linux CUDA 🔄

**Status**: Active
**Implementation**: `chart/templates/runtimeclass-nvidia.yaml`
**Docs to update**: `documents/engineering/cluster_topology.md`

### Objective

Add the `RuntimeClass nvidia` and bind it to the Linux CUDA worker label
`jitml.runtime/gpu=true`. The substrate image (`jitml:local`) is unchanged —
target CUDA image hardening bakes NVCC + cuBLAS + cuDNN unconditionally and
activates them at runtime when the pod is scheduled with
`runtimeClassName: nvidia`.

### Deliverables

- `chart/templates/runtimeclass-nvidia.yaml` declares the `RuntimeClass` with
  `handler: nvidia` and node-selector label `jitml.runtime/gpu=true`.
- The `jitml-service` Deployment renderer sets
  `spec.template.spec.runtimeClassName: nvidia` when substrate is `linux-cuda`.
- The Linux CUDA Kind worker (Sprint `3.1`) is labelled
  `jitml.runtime/gpu=true`.

### Validation

1. `chart/templates/runtimeclass-nvidia.yaml` declares the RuntimeClass.
2. The Linux CUDA Kind config carries the GPU worker label.
3. Live validation (target): a pod with `runtimeClassName: nvidia` lands on
   the labelled Kind worker and successfully runs an `nvidia-smi` probe.

### Remaining Work

- Validate the live pod scheduling against the labelled Kind worker with
  the `nvidia` runtime installed.
- Confirm the `jitml-service` Deployment renders
  `runtimeClassName: nvidia` only when substrate is `linux-cuda` and that
  the resulting pod actually sees the GPU.

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
  rows remain aligned with the implemented chart, bucket, Pulsar, PostgreSQL,
  and observability surfaces.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [development_plan_standards.md](development_plan_standards.md)
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
