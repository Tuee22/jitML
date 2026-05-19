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
full doctrine-required method set, and `JitML.Service.HarborSubprocess`
provides the explicit Docker/curl-backed Harbor client settings and command
surface for push, pull, promote, existence, and repository listing. The route
registry now targets the actual live Helm service names and includes Harbor's
Docker registry/token paths (`/v2`, `/service`) alongside `/harbor` and
`/harbor/api`. Live Linux CPU validation on 2026-05-18 also exercises
`JitML.Cluster.Readiness.platformReadinessSubprocesses` against the installed
Harbor, MinIO, Pulsar, Envoy Gateway, observability, TensorBoard,
`jitml-service`, and `jitml-demo` rollouts, plus MinIO bucket existence
through the typed in-pod `mc` readiness subprocess. **Unmet today**: Phase `4` still
owes the live service-client effects: Harbor S3-backend verification,
MinIO conditional-write checks,
`HasPulsar` subscription semantics, Grafana dashboard inspection, Prometheus
scrape verification, TensorBoard event reads, and CUDA RuntimeClass binding on
a real NVIDIA worker. Live Linux CPU validation on 2026-05-18 confirms Harbor
push/promote, pull, repository listing, and artifact existence through
`JitML.Service.HarborSubprocess` after routing Harbor public paths through the
chart's `harbor` nginx service, and confirms all seven typed MinIO buckets
exist through `JitML.Cluster.Readiness.minioBucketReadinessSubprocess`. The
same live run family now confirms the registered `harbor-pg`
`PerconaPGCluster` reaches `ready` with three Postgres instances, PgBouncer,
and the pgBackRest repo backed by explicit manual PV `volumeName` bindings.
Detailed remaining work lives in each sprint's `### Remaining Work` block
below.

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
`src/JitML/Cluster/Publication.hs`, `src/JitML/Bootstrap.hs`,
`src/JitML/Service/HarborSubprocess.hs`
**Docs to update**: `documents/engineering/cluster_topology.md`

### Objective

Install Harbor as the in-cluster image registry, with MinIO as its S3 backend
and Percona PG (Sprint `4.2`) as its database. Routed at `/harbor` (portal),
`/harbor/api` (API), `/v2` (Docker registry), and `/service` (token service).

### Deliverables

- `chart/Chart.yaml` declares the `harbor` subchart dependency at a pinned
  version.
- Current `chart/values.yaml` provides the local Harbor values scaffold and uses
  the `jitml-manual` StorageClass for registry persistence.
- Target live bootstrap deploys Harbor's portal, core, registry, and notary in
  the bootstrap phase, then configures its S3 backend against MinIO bucket
  `harbor-registry` (Sprint `4.3`).
- Current `jitml bootstrap --<substrate>` installs Harbor in the first live
  Helm phase, then uses explicit Kind-loaded `jitml:local` /
  `jitml-demo:local` tags for the Phase `3` local workload rollout. The Harbor
  phase target is live registry readiness plus a validated image push/pull path
  through the `HasHarbor` capability surface.
- HTTPRoute manifests for `/harbor`, `/harbor/api`, `/v2`, and `/service` are
  generated from the route registry (Sprint `3.4`).
- `JitML.Service.HarborSubprocess` is the explicit local Harbor client:
  callers pass `HarborSettings` with Docker binary, optional Docker host,
  curl binary, registry, API base URL, username, password, and repo-local
  Docker config directory; no process environment or global Docker config is
  consulted.

### Validation

1. `chart/Chart.yaml` declares the Harbor subchart dependency.
2. The local route registry renders `/harbor`, `/harbor/api`, `/v2`, and
   `/service` routes against the live Harbor service names.
3. Live Linux CPU validation on 2026-05-18 confirms Harbor core, portal,
   registry, jobservice, database, redis, and trivy rollouts reach Ready.
4. `cabal test jitml-integration` covers the typed `HarborSubprocess` login,
   artifact-existence, manifest-inspect, and repository-list command surface,
   including explicit optional Docker host flag, repo-local Docker config path,
   stdin-piped Docker credentials, and the routed `/harbor/api` base.
5. Live Linux CPU validation on 2026-05-18 pushes/promotes
   `jitml:local` to `127.0.0.1:9091/library/jitml:phase4`, pulls it back
   with digest `sha256:ab610bc0672453ee42c1d4f6b052c36208c614ec7ff198eccf3f46ccf0e5710d`,
   lists `library/jitml` through `harborListImages`, and confirms
   `harborImageExists` via Harbor's artifact API.
6. Live validation target: S3 backend is configured against MinIO bucket
   `harbor-registry`.

### Remaining Work

- The typed `helm install` subprocess for Harbor lives in
  `JitML.Cluster.Helm.helmInstallSubprocess` and is sequenced first
  in `JitML.Cluster.Helm.phasedReleases` (HarborPhase). The live rollout
  invokes it from `JitML.Bootstrap` against the repo-local kubeconfig and
  passes an explicit `externalURL=http://127.0.0.1:<edge-port>` so Harbor's
  registry auth challenge points at the selected localhost edge.
  `JitML.Cluster.Readiness.platformReadinessSubprocesses` waits for the
  Harbor rollouts before topic bootstrap.
- `JitML.Service.HarborSubprocess` implements
  `HasHarbor.{harborImageExists,harborPromoteImage,harborPushImage,
  harborPullImage,harborListImages}` through typed Docker/curl subprocesses.
  Existence checks use Harbor's `/api/v2.0/projects/.../artifacts/...`
  endpoint because Docker `manifest inspect` does not reliably report local
  HTTP Harbor registry artifacts. Live Linux CPU validation has exercised
  image tag/push through `harborPromoteImage`, pull through
  `harborPullImage`, project listing through `harborListImages`, and artifact
  lookup through `harborImageExists`.
- Verify Harbor's S3 backend against MinIO bucket `harbor-registry` once the
  MinIO bucket-readiness check from Sprint `4.3` is live.
- Codify the live Harbor push/pull/list sequence in the future live e2e
  harness once Sprint `12.8` owns always-live cross-cluster execution.

## Sprint 4.2: Percona PG Operator and Patroni-Managed Service Postgres 🔄

**Status**: Active
**Implementation**: `chart/Chart.yaml`, `chart/values.yaml`,
`chart/templates/pv-platform-harbor-pg-*.yaml`,
`chart/templates/pv-platform-harbor-pg-repo1-0.yaml`,
`src/JitML/Cluster/PostgresRegistry.hs`,
`src/JitML/Cluster/Readiness.hs`, `src/JitML/Bootstrap.hs`
**Docs to update**: `documents/engineering/cluster_topology.md`

### Objective

Install the Percona Kubernetes Operator and Patroni-managed HA Postgres clusters
for packaged services that require Postgres. Harbor is the first consumer.
jitML itself never writes to a relational DB on its data path — durable state
lives in MinIO and Pulsar exclusively.

### Deliverables

- `pg-operator` subchart pinned in `chart/Chart.yaml`.
- Current local storage includes manual PV templates for the `platform/harbor-pg`
  data volumes and `platform/harbor-pg-repo1` pgBackRest repo volume.
- `PerconaPGCluster` resources are rendered from a typed service-Postgres
  registry; the first entry is `harbor-pg` in namespace `platform`, using the
  `jitml-manual` StorageClass and manual PVs from Sprint `3.2`. Percona data
  and pgBackRest PVCs bind through explicit `volumeName` fields because the
  operator-generated PVC names carry controller suffixes.
- Target Harbor database values point at `harbor-pg`.
- Target `jitml lint chart` rejects any `PerconaPGCluster` outside the typed
  service-Postgres registry.

### Validation

1. `chart/Chart.yaml` declares the `pg-operator` subchart dependency.
2. `chart/templates/pv-platform-harbor-pg-*.yaml` and
   `chart/templates/pv-platform-harbor-pg-repo1-0.yaml` provide the manual PV
   surface for service Postgres data and pgBackRest storage.
3. `cabal test jitml-integration` covers the rendered `PerconaPGCluster`,
   pinned Percona component images, explicit `volumeName` PV bindings,
   stdin-piped apply command, and readiness wait command.
4. Live Linux CPU validation on 2026-05-19 confirms `PerconaPGCluster`
   `harbor-pg` reaches `ready` in namespace `platform`, with
   `postgres=3/3`, `pgbouncer=1/1`, host
   `harbor-pg-pgbouncer.platform.svc`, and all four manual PVs bound.
5. Live validation target: Harbor's database values point at the live
   `harbor-pg` service, and `jitml lint chart` rejects any
   `PerconaPGCluster` outside the typed service-Postgres registry.

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
  The rendered `PerconaPGCluster` YAML now flows through the live bootstrap as
  a stdin-piped `kubectl --kubeconfig ./.build/jitml.kubeconfig apply -n
  platform -f -` after the operator CRD is installed. The CR pins Postgres,
  PgBouncer, and pgBackRest images for Percona Operator `2.5.1`; renders three
  single-replica instance volumes plus one pgBackRest repo volume; and binds
  all four manual PVs through explicit `volumeName` fields. Live Linux CPU
  validation on 2026-05-19 confirmed `harbor-pg` reaches `ready` with
  `postgres=3/3` and `pgbouncer=1/1`.
- `JitML.Cluster.Readiness.postgresReadinessSubprocesses` waits for
  `perconapgcluster/harbor-pg` to report `.status.state=ready` before
  Pulsar topic bootstrap.
- Remaining work: wire Harbor's Helm values to use the live
  `harbor-pg-pgbouncer.platform.svc` database endpoint instead of Harbor's
  internal chart database, including the rollout ordering needed to make that
  external database available before Harbor switches to it.

## Sprint 4.3: MinIO Subchart, Bucket Provisioning, Conditional-Write Server 🔄

**Status**: Active
**Implementation**: `chart/values.yaml`,
`src/JitML/Storage/Buckets.hs`,
`src/JitML/Cluster/Readiness.hs`
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
5. Live Linux CPU validation on 2026-05-18 confirms the installed MinIO rollout
   reaches Ready.
6. Live Linux CPU validation on 2026-05-18 confirms all seven typed buckets
   exist through `JitML.Cluster.Readiness.minioBucketReadinessSubprocess`,
   which runs the Bitnami in-pod MinIO client (`mc`) against the local service
   endpoint and checks every bucket from `JitML.Storage.Buckets.bucketNames`.
7. Live validation target: the `HasMinIO` capability class exercises
   `If-None-Match: *` PUT and `If-Match: <etag>` pointer CAS against the
   running cluster.

### Remaining Work

- The typed `HasMinIO` capability class exposes the full conditional-write
  surface (`putBlobIfAbsent`, `casPointer`, `listObjects`,
  `deleteObject`) with `ETag` newtype. A filesystem-backed instance
  (`JitML.Service.FilesystemMinIO`) honours the same conditional
  semantics — `putBlobIfAbsent` returns `Left (SEConflict ...)` on the
  second PUT (the 412 → `SEConflict` mapping doctrine prescribes), and
  `casPointer` returns `Left (SEConflict ...)` on a stale ETag.
  Validated by `jitml-integration` against a real on-disk temporary
  store. The pending work is the live HTTP-backed instance against the
  running MinIO service.
- `JitML.Cluster.Readiness.minioBucketReadinessSubprocess` is wired into
  `platformReadinessSubprocesses` after the MinIO rollout check and before
  Pulsar topic bootstrap. It executes the Bitnami in-pod `mc` binary from
  `deploy/minio`, aliases `http://127.0.0.1:9000` with the chart's explicit
  local demo credentials, and checks every bucket from
  `JitML.Storage.Buckets.bucketNames`. Live Linux CPU validation confirmed the
  seven buckets on 2026-05-18.

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
  idempotent `/pulsar/bin/pulsar-admin topics list` / `topics create`
  commands executed from `pulsar-toolset-0` after the phased bootstrap rollout.
- HTTPRoutes for `/pulsar/admin` and `/pulsar/ws` (Sprint `3.4`).

### Validation

1. `src/JitML/Cluster/PulsarBootstrap.hs` renders the typed topic-command
   surface.
2. The route registry includes `/pulsar/admin` and `/pulsar/ws`.
3. Live Linux CPU validation on 2026-05-18 reaches Ready Pulsar components and
   creates every topic in
   [system-components.md → Pulsar Topic Family](system-components.md#pulsar-topic-family).
4. Live validation target: the `HasPulsar` capability class subscribes
   successfully via the WebSocket proxy.

### Remaining Work

- `JitML.Cluster.PulsarBootstrap.pulsarTopicCreateSubprocesses` is now
  appended to the typed `liveExecutePhasedRollout` step list in
  `JitML.Bootstrap`, so `jitml bootstrap --<substrate>` invokes
  `kubectl --kubeconfig
  ./.build/jitml.kubeconfig exec -n platform pulsar-toolset-0 -- sh -c
  '<list namespace>; <create if absent>' <topic>` for every registered topic after
  the phased Helm rollout completes. The script uses the chart's explicit
  `/pulsar/bin/pulsar-admin` path and treats an already-created topic as
  reconciled. Sprint `3.5` live validation confirmed the topic family exists
  in `public/default`.
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
3. Live Linux CPU validation on 2026-05-18 confirms the kube-prometheus-stack
   operator, Grafana, kube-state-metrics, and Prometheus rollouts reach Ready.
4. Live validation target: Grafana serves the provisioned dashboards behind
   `/grafana`, and Prometheus scrapes the `jitml service` `/metrics` endpoint
   at the declared interval.

### Remaining Work

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
3. Live Linux CPU validation on 2026-05-18 confirms the TensorBoard rollout
   reaches Ready.
4. Live validation target: TensorBoard serves behind `/tensorboard`, reads
   TFRecord shards from MinIO bucket
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
  validated for deterministic encoding by `jitml-unit`. The writer
  surface `JitML.Observability.TbSidecar.writeCheckpointSidecar`
  consumes a `TbCheckpointMarker` and writes the CBOR bytes at
  `checkpointSidecarKey` through `HasMinIO.putBlobBytesIfAbsent`,
  validated by `jitml-integration` against the filesystem-backed
  `HasMinIO` instance. The Consumer-domain entry point is
  `JitML.Observability.TbSidecar.dispatchCheckpointDone ::
  HasMinIO m => TbCheckpointMarker -> m (Either ServiceError ETag)`,
  which derives the sidecar key from the marker's own
  `tcmExperimentSha` / `tcmStep` / `tcmManifestSha` fields and writes
  through `writeCheckpointSidecar`. Validated by `jitml-integration`
  against the filesystem-backed instance: a marker round-trips
  through the dispatcher and the resulting bytes land at the
  canonical `checkpointSidecarKey` location. The pending wiring is
  plugging the `inference.event.<substrate>` payload deserialiser
  into the Consumer's per-domain dispatcher so it invokes
  `dispatchCheckpointDone` on each `CheckpointDone` envelope.
- `JitML.Observability.TensorBoard.renderTensorBoardService` now renders
  the TensorBoard `Service` manifest alongside the existing Deployment
  renderer. The checked-in `chart/local/tensorboard` chart now carries
  both the Deployment and the Service for the live Phase `3` rollout and
  uses `tensorflow/tensorflow:2.16.1` as a pullable TensorBoard image.
  Live Linux CPU bootstrap reaches a Running TensorBoard pod. Remaining gap:
  MinIO-backed event reads through the live rollout path.

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
3. Live Linux CPU validation on 2026-05-18 confirms the RuntimeClass manifest
   applies and `kubectl get runtimeclass nvidia` succeeds.
4. Live validation target: a pod with `runtimeClassName: nvidia` lands on
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
