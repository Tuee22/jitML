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

✅ **Done**. The phase contributes the stateful-platform-services half of
[Exit Definition](README.md#exit-definition) item 3 (Harbor up first;
MinIO, Pulsar, Postgres, observability, TensorBoard, NVIDIA RuntimeClass
all installed and routable through the single Envoy Gateway socket), and the
phase-owned live service and CUDA RuntimeClass checks are validated.
**Met today**: typed chart-values, manual-PV templates, route templates,
deployment templates, the MinIO bucket registry, the Pulsar topic
registry/command renderer, the Grafana dashboard renderer, the TensorBoard
deployment/shard-key renderer, the NVIDIA RuntimeClass manifest, and the Linux
CUDA Kind worker containerd `nvidia` runtime-handler wiring are in place; MinIO
subchart values live under `minio:` in `chart/values.yaml`;
`jitml lint chart` rejects values files under `chart/templates/`. The
typed service-Postgres registry (`JitML.Cluster.PostgresRegistry`) and
its `validateRegisteredPostgres` lint helper are checked in;
`JitML.Cluster.PulsarBootstrap.pulsarTopicCreateSubprocess` is the
typed `pulsar-admin topics create` subprocess. The capability classes
(`HasMinIO`, `HasPulsar`, `HasHarbor`, `HasKubectl`) now expose the
full doctrine-required method set, and `JitML.Service.HarborSubprocess`
provides the explicit Docker/curl-backed Harbor client settings and command
surface for push, pull, promote, existence, and repository listing, while
`JitML.Service.MinIOSubprocess` provides the subprocess-backed HTTP S3
`HasMinIO` instance for write-once puts, pointer CAS, reads, listings, and
deletes. The route registry now targets the actual live Helm service names and
includes Harbor's Docker registry/token paths (`/v2`, `/service`) alongside
`/harbor` and `/harbor/api`. Harbor's direct subchart values are now checked in at
`chart/values/harbor.yaml`; both the umbrella values and live direct install
set `database.type=external` against
`harbor-pg-pgbouncer.platform.svc`, with credentials sourced from
`harbor-pg-secrets`; they also set Harbor registry storage to the MinIO
`harbor-registry` S3 backend with redirects disabled and 128 MiB chunks. The
live rollout waits for MinIO bucket readiness and `harbor-pg` readiness, grants
the `harbor` role ownership of schema `public`, and then installs Harbor. Live
Linux CPU validation on 2026-05-19 confirms that Harbor starts against the
external `harbor-pg-pgbouncer.platform.svc` database and stores registry objects
in the MinIO S3 backend: an OCI artifact pushed through the registry HTTP API to
`library/jitml-phase4-validate:phase4-20260519120542` returned manifest digest
`sha256:e763d768dd2fdee99d168ba9a7b0dfe6f6f0ceaabaa417241b6d79e27a7aee4c` from
both the registry and Harbor API, and MinIO contained the repository layer,
manifest, and tag-link objects under bucket `harbor-registry`. Live Linux CPU
validation on 2026-05-18 also exercises
`JitML.Cluster.Readiness.platformReadinessSubprocesses` against the installed
Harbor, MinIO, Pulsar, Envoy Gateway, observability, TensorBoard,
`jitml-service`, and `jitml-demo` rollouts, plus MinIO bucket existence through
the typed in-pod `mc` readiness subprocess. Live Linux CPU validation on
2026-05-19 confirms the Pulsar broker-embedded WebSocket service is enabled,
`/pulsar/ws` resolves to `pulsar-broker:8080`, the full typed topic family
exists, and `JitML.Service.PulsarWebSocketSubprocess` publishes and consumes
through the routed edge. Live Linux CPU validation on 2026-05-19 also confirms
the Haskell TensorBoard writer serializes TensorFlow-compatible scalar events,
writes a TFRecord shard through routed `JitML.Service.MinIOSubprocess`, and
TensorBoard reports the scalar through the routed `/tensorboard` scalars API.
Live Linux CUDA validation on 2026-05-20 cleanly recreates the
`jitml-linux-cuda` Kind cluster from the checked-in
`kind/cluster-linux-cuda.yaml`, confirms the worker has the
`jitml.runtime/gpu=true` label, the node-local containerd `nvidia` runtime
handler, the read-only host driver root at `/run/nvidia/driver`, and the
repo-owned NVIDIA runtime config, applies `RuntimeClass/nvidia`, and runs
`pod/nvidia-smi-probe` to `Succeeded` with log
`GPU 0: NVIDIA GeForce RTX 5090`.
Live Linux CPU validation on 2026-05-18 confirms Harbor push/promote, pull,
repository listing, and artifact existence through
`JitML.Service.HarborSubprocess` after routing Harbor public paths through the
chart's `harbor` nginx service, and confirms all seven typed MinIO buckets
exist through `JitML.Cluster.Readiness.minioBucketReadinessSubprocess`. Live
Linux CPU validation on 2026-05-19 confirms
`JitML.Service.MinIOSubprocess` against the routed
`http://127.0.0.1:9091/minio/s3` surface: duplicate `If-None-Match: *` writes
and stale `If-Match` pointer CAS both return `SEConflict`, while read, list,
and delete succeed. The same live run family now confirms the registered `harbor-pg`
`PerconaPGCluster` reaches `ready` with three Postgres instances, PgBouncer,
and the pgBackRest repo backed by explicit manual PV `volumeName` bindings.
No sprint-owned Phase `4` Remaining Work remains.

## Phase Summary

This phase populates the umbrella Helm chart's subchart bodies, the MinIO bucket
provisioning block, the Pulsar topic / namespace bootstrap, the Percona PG
operator and Patroni-managed Postgres clusters for packaged services that need
Postgres (jitML itself never writes to a relational DB on its data path), the
kube-prometheus-stack with Grafana datasources and
provisioned dashboards, the jitML-owned TensorBoard chart with MinIO event-
storage backing, and the NVIDIA `RuntimeClass` that binds to nodes labelled
`jitml.runtime/gpu=true`.

## Sprint 4.1: Harbor Subchart and Bootstrap-Phase Install ✅

**Status**: Done
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
- Current direct Harbor values configure the registry storage backend as S3
  against MinIO bucket `harbor-registry` with 128 MiB chunks and redirects
  disabled for MinIO compatibility. The live rollout now installs MinIO and
  checks the bucket before installing Harbor.
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
3. Live Linux CPU validation on 2026-05-19 confirms Harbor core, portal,
   registry, jobservice, redis, and trivy rollouts reach Ready against the
   external Percona `harbor-pg` database and the MinIO-backed S3 registry
   storage values.
4. `cabal test jitml-integration` covers the typed `HarborSubprocess` login,
   artifact-existence, manifest-inspect, and repository-list command surface,
   including explicit optional Docker host flag, repo-local Docker config path,
   stdin-piped Docker credentials, and the routed `/harbor/api` base.
5. Live Linux CPU validation on 2026-05-18 pushes/promotes
   `jitml:local` to `127.0.0.1:9091/library/jitml:phase4`, pulls it back
   with digest `sha256:ab610bc0672453ee42c1d4f6b052c36208c614ec7ff198eccf3f46ccf0e5710d`,
   lists `library/jitml` through `harborListImages`, and confirms
   `harborImageExists` via Harbor's artifact API.
6. `cabal test jitml-integration` confirms the live rollout installs MinIO
   and verifies bucket `harbor-registry` before installing Harbor, and that
   Harbor uses `chart/values/harbor.yaml`.
7. Live Linux CPU validation on 2026-05-19 pushes a tiny OCI artifact through
   Harbor's registry HTTP API to
   `library/jitml-phase4-validate:phase4-20260519120542`, reads it back from
   `/v2`, confirms Harbor's artifact API reports manifest digest
   `sha256:e763d768dd2fdee99d168ba9a7b0dfe6f6f0ceaabaa417241b6d79e27a7aee4c`,
   and confirms MinIO contains the repository's layer, manifest, and tag-link
   objects under `harbor-registry/docker/registry/v2/repositories/...`.
8. Live Linux CPU validation on 2026-05-19 through the rebuilt
   `jitml:local` validation container with host networking completes
   `jitml bootstrap --linux-cpu` with 100 live rollout steps, writes a ready
   publication on edge port `9091`, logs into
   `127.0.0.1:9091` with repo-local Docker config, pushes
   `ubuntu:24.04` as
   `127.0.0.1:9091/library/jitml-phase4-docker:phase4-docker-20260519195137`,
   pulls it back with digest
   `sha256:cdb5fd928fced577cfecf12c8966e830fcdf42ee481fb0b91904eeddc2fe5eff`,
   lists `library/jitml-phase4-docker` through `/harbor/api`, and confirms
   the tag's Harbor artifact API returns HTTP `200`.

## Sprint 4.2: Percona PG Operator and Patroni-Managed Service Postgres ✅

**Status**: Done
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
5. `cabal test jitml-integration` confirms the live rollout installs the
   Percona operator, applies the registered `harbor-pg` CR, waits for
   `perconapgcluster/harbor-pg` readiness, grants the `harbor` role schema
   ownership on the current primary, and only then installs Harbor with
   `--values chart/values/harbor.yaml`.
6. `cabal run jitml -- lint chart` rejects any `PerconaPGCluster` outside
   the typed service-Postgres registry.
7. Live Linux CPU validation on 2026-05-19 confirms Harbor starts successfully
   against the external `harbor-pg-pgbouncer.platform.svc` database endpoint
   after the pre-Harbor schema ownership grant.

### Closure State

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
- `chart/values/harbor.yaml` is the direct Harbor subchart values file, and
  `chart/values.yaml` carries the matching umbrella-chart values. Both set
  `database.type=external`, point at
  `harbor-pg-pgbouncer.platform.svc:5432`, use database/user `harbor`, and
  consume `harbor-pg-secrets` for the password with `sslmode=require`
  because PgBouncer requires TLS. The live rollout installs the Percona
  operator, applies the registered CR, waits for readiness, runs a typed
  `kubectl exec ... psql` schema grant on the current primary so Harbor's
  migration can create tables under `public`, and then installs Harbor with
  that values file.

## Sprint 4.3: MinIO Subchart, Bucket Provisioning, Conditional-Write Server ✅

**Status**: Done
**Implementation**: `chart/values.yaml`,
`src/JitML/Storage/Buckets.hs`,
`src/JitML/Cluster/Readiness.hs`,
`src/JitML/Service/MinIOSubprocess.hs`
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
- `JitML.Service.MinIOSubprocess` is the live HTTP-backed `HasMinIO`
  interpreter. It uses `curl --aws-sigv4`, signs the canonical path-style S3
  object URL, sends routed edge requests with `--request-target /minio/s3/...`
  so Envoy can rewrite to MinIO's upstream path, and maps MinIO `412` responses
  to the doctrine's `SEConflict`.

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
7. `cabal test jitml-integration` covers the rendered
   `JitML.Service.MinIOSubprocess` command surface: explicit local demo
   credentials, `curl --aws-sigv4`, `If-None-Match: *`, canonical signed S3
   URLs, routed Envoy `--request-target /minio/s3/...`, and list-response XML
   parsing.
8. Live Linux CPU validation on 2026-05-19 exercises the `HasMinIO`
   capability class against the running MinIO service, both through a direct
   service port-forward and through the routed
   `http://127.0.0.1:9091/minio/s3` edge surface: first write returns an
   `ETag`, duplicate `If-None-Match: *` write returns `SEConflict`, pointer
   CAS from the current ETag succeeds, stale-Etag CAS returns `SEConflict`,
   `minioReadObject` returns the updated pointer body, `listObjects` returns
   the written keys, and `deleteObject` removes them.

### Closure State

- The typed `HasMinIO` capability class exposes the full conditional-write
  surface (`putBlobIfAbsent`, `casPointer`, `listObjects`,
  `deleteObject`) with `ETag` newtype. `JitML.Service.FilesystemMinIO`
  honours the same conditional semantics in local tests, and
  `JitML.Service.MinIOSubprocess` is the subprocess-backed live HTTP S3
  implementation for running MinIO.
- `JitML.Service.MinIOSubprocess.minioSettingsForLocalEdge` models the routed
  Envoy surface by signing the upstream path-style S3 URL and passing
  `--request-target /minio/s3/...` to curl. This keeps SigV4 canonical paths
  aligned with the path that MinIO sees after the HTTPRoute rewrite.
- `JitML.Cluster.Readiness.minioBucketReadinessSubprocess` is wired into
  `platformReadinessSubprocesses` after the MinIO rollout check and before
  Pulsar topic bootstrap. It executes the Bitnami in-pod `mc` binary from
  `deploy/minio`, aliases `http://minio.platform.svc.cluster.local:9000` with
  the chart's explicit local demo credentials, and checks every bucket from
  `JitML.Storage.Buckets.bucketNames` with a bounded retry loop so the command
  survives MinIO's setup-server to final-server transition. Live Linux CPU
  validation confirmed the seven buckets on 2026-05-18, and the retry-hardened
  command passed against the 2026-05-19 live cluster after an initial transient
  `connection refused` during that transition.

## Sprint 4.4: Apache Pulsar HA and Topic Bootstrap ✅

**Status**: Done
**Implementation**: `chart/values.yaml`,
`chart/values/pulsar.yaml`, `chart/templates/httproute-pulsar-ws.yaml`,
`src/JitML/Cluster/PulsarBootstrap.hs`,
`src/JitML/Service/PulsarWebSocketSubprocess.hs`, `src/JitML/Routes.hs`
**Docs to update**: `documents/engineering/daemon_architecture.md`

### Objective

Install Apache Pulsar in HA shape (3× ZooKeeper, 3× BookKeeper, 3× Broker, 3×
Proxy, WebSocket enabled) and bootstrap the substrate-scoped topic family.

### Deliverables

- `pulsar` subchart at a pinned HA release.
- 3 ZooKeepers, 3 BookKeepers, 3 Brokers, 3 Proxies, WebSocket enabled through
  broker config `webSocketServiceEnabled=true`.
- The direct local values file `chart/values/pulsar.yaml` sets
  `proxy.service.type=ClusterIP` so Helm `--wait` is valid in Kind without a
  cloud load balancer.
- `src/JitML/Cluster/PulsarBootstrap.hs` declares the typed topic family from
  [system-components.md → Pulsar Topic
  Family](system-components.md#pulsar-topic-family) and renders the
  idempotent `/pulsar/bin/pulsar-admin topics list` / `topics create`
  commands executed from `pulsar-toolset-0` after the phased bootstrap rollout.
  The registered family is the eight command/event topics for each substrate
  plus the Apple-only `inference.command.apple-silicon` /
  `inference.event.apple-silicon` internal RPC pair.
- HTTPRoutes for `/pulsar/admin` and `/pulsar/ws` (Sprint `3.4`).
  `/pulsar/ws` rewrites to `/ws` and now targets `pulsar-broker:8080`, the
  broker HTTP service that owns the embedded WebSocket endpoint.
- `JitML.Service.PulsarWebSocketSubprocess` is the live one-shot WebSocket
  `HasPulsar` interpreter for the routed local edge. It publishes with Node's
  WebSocket constructor, with an `undici.WebSocket` fallback for older Node
  runtimes. The current `jitml:local` image carries Node.js `22.16.0`,
  opens consumers at the broker
  WebSocket endpoint, consumes one payload, and acknowledges on that same
  WebSocket session before closing.

### Validation

1. `src/JitML/Cluster/PulsarBootstrap.hs` renders the typed topic-command
   surface; `jitml-integration` asserts the 26-topic substrate-scoped family
   and rejects the retired `*.cluster` / `*.host` topics.
2. The route registry includes `/pulsar/admin` and `/pulsar/ws`.
3. Live Linux CPU validation on 2026-05-18 reaches Ready Pulsar components and
   creates every topic in
   [system-components.md → Pulsar Topic Family](system-components.md#pulsar-topic-family).
4. Live Linux CPU validation on 2026-05-19 confirms
   `pulsar-broker-0` carries `webSocketServiceEnabled=true`, HTTPRoute
   `pulsar-ws` is `Accepted=True` / `ResolvedRefs=True` against
   `pulsar-broker:8080`, and Gateway `jitml-edge` is `Programmed=True`.
5. Live Linux CPU validation on 2026-05-19 confirms every registered topic in
   [system-components.md → Pulsar Topic Family](system-components.md#pulsar-topic-family)
   exists in `public/default`.
6. Live Linux CPU validation on 2026-05-20 reconciles the current
   26-topic substrate-scoped family into `jitml-linux-cpu` through
   `pulsar-toolset-0` and verifies all 26 current names are listed by the live
   broker.
7. Live Linux CPU validation on 2026-05-19 opens a routed WebSocket consumer at
   `ws://127.0.0.1:9091/pulsar/ws/v2/consumer/...`, publishes through the
   matching routed producer endpoint, receives the same payload, and sends the
   WebSocket ack.
8. Live Linux CPU validation on 2026-05-19 exercises
   `JitML.Service.PulsarWebSocketSubprocess` through the same route:
   `pulsarPublish` returns broker message id `CBQQAjAA`, and concurrent
   `pulsarConsume` returns
   `("persistent://public/default/training.command.linux-cpu",
   "phase4-haskell-pulsar-1779216327")`.
9. Live Linux CPU validation on 2026-05-20 exercises the current routed topic
   `persistent://public/default/training.command.linux-cpu` from
   `jitml:local` through the WebSocket subprocess path;
   publish/consume succeeds through `/pulsar/ws`, returning broker message id
   `CDEQADAA`.
10. `cabal test jitml-integration` covers the rendered
   `JitML.Service.PulsarWebSocketSubprocess` command surface and asserts the
   producer and consumer target `/pulsar/ws/v2/...` on the routed local edge.
11. Live Linux CPU validation on 2026-05-19 confirms the direct Pulsar values
   upgrade the release to `deployed` in Kind with `proxy.service.type=ClusterIP`;
   leaving the upstream `LoadBalancer` default caused Helm `--wait` to fail
   despite Ready pods.

### Closure State

- `JitML.Cluster.PulsarBootstrap.pulsarTopicCreateSubprocesses` is appended to
  the typed `liveExecutePhasedRollout` step list in `JitML.Bootstrap`, so
  `jitml bootstrap --<substrate>` invokes `kubectl --kubeconfig
  ./.build/jitml.kubeconfig exec -n platform pulsar-toolset-0 -- sh -c
  '<list namespace>; <create if absent>' <topic>` for every registered topic
  after the phased Helm rollout completes. The script uses the chart's explicit
  `/pulsar/bin/pulsar-admin` path and treats an already-created topic as
  reconciled. The registered set matches the substrate-scoped Pulsar topic
  family: training, tune, RL, and inference request/result command/event topics
  for `apple-silicon`, `linux-cpu`, and `linux-cuda`, plus the Apple-only
  internal inference RPC pair.
- `chart/values.yaml` and `chart/values/pulsar.yaml` set
  `broker.configData.webSocketServiceEnabled: "true"`, enabling Pulsar's
  broker-embedded WebSocket service on port `8080`.
- `chart/values/pulsar.yaml` also sets `proxy.service.type: ClusterIP`,
  matching the single Envoy Gateway edge model instead of waiting for a
  cloud load balancer that Kind does not provide.
- The `/pulsar/ws` route no longer points at `pulsar-proxy`; it rewrites to
  `/ws` and targets `pulsar-broker:8080`, which serves `/ws/v2/producer/...`
  and `/ws/v2/consumer/...`.
- `JitML.Service.PulsarWebSocketSubprocess` validates the routed
  publish/consume path through the `HasPulsar` class. It is a one-shot
  subprocess interpreter: `pulsarConsume` opens a consumer, reads one message,
  acknowledges it on that same WebSocket session, and closes. Its Node script
  uses `globalThis.WebSocket` when present and `require('undici').WebSocket`
  otherwise, so the path remains compatible with older Node runtimes while
  current `jitml:local` carries Node.js `22.16.0`. The daemon's long-lived
  at-least-once cursor, explicit
  post-dispatch ack/redelivery, and seek behavior remain Sprint `5.5` /
  Sprint `12.7` work.

## Sprint 4.5: kube-prometheus-stack and Provisioned Dashboards ✅

**Status**: Done
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
  list for the `jitml-service` daemon's `/metrics` endpoint, renders
  `chart/templates/prometheus-scrapeconfig-jitml.yaml` with the
  `release=kube-prometheus-stack` selector label, and protects it through
  `trackingGeneratedPaths`.
- `chart/local/jitml-service/templates/service.yaml` exposes the daemon on
  ClusterIP port `8080` so Prometheus has a stable in-cluster scrape target.
- HTTPRoutes for `/grafana` and `/prometheus` (Sprint `3.4`).

### Validation

1. `src/JitML/Observability/Grafana.hs` renders the dashboard surface.
2. `src/JitML/Observability/Prometheus.hs` renders the scrape-target
   surface.
3. Live Linux CPU validation on 2026-05-18 confirms the kube-prometheus-stack
   operator, Grafana, kube-state-metrics, and Prometheus rollouts reach Ready.
4. Live Linux CPU validation on 2026-05-19 confirms Grafana serves all seven
   generated jitML dashboards behind `/grafana` (`training-throughput`,
   `rl-episode-reward`, `alphazero-arena`, `jit-cache`,
   `pulsar-consumer-lag`, `minio-put-latency`, `daemon-health`), and
   Prometheus reports
   `http://jitml-service.platform.svc.cluster.local:8080/metrics` as `up`
   through the routed `/prometheus` API.

### Closure State

- The live rollout applies the generated Grafana dashboard ConfigMaps and the
  generated Prometheus `ScrapeConfig` after the kube-prometheus-stack and
  `jitml-service` local charts are installed. The dashboard ConfigMaps use
  unique data keys (`<dashboard-name>.json`) so the Grafana sidecar writes
  every dashboard to a distinct file under `/tmp/dashboards`.
- The generated `ScrapeConfig` carries label
  `release: kube-prometheus-stack`, matching the Prometheus CR's
  `scrapeConfigSelector`, and targets only
  `jitml-service.platform.svc.cluster.local:8080` because that daemon service
  exposes the implemented `/metrics` endpoint.

## Sprint 4.6: TensorBoard with MinIO Event Storage and Checkpoint Sidecar ✅

**Status**: Done
**Implementation**: `src/JitML/Observability/TensorBoard.hs`,
`src/JitML/Proto/TensorBoard.hs`, `src/JitML/Observability/TbSidecar.hs`,
`src/JitML/Service/Runtime.hs`, `proto/tensorboard/event.proto`
**Docs to update**: `documents/engineering/daemon_architecture.md`,
`documents/engineering/checkpoint_format.md`

### Objective

Stand up the local TensorBoard shard-key/projection/deployment renderer that the
target TensorBoard chart will consume. The target chart points at MinIO bucket
`jitml-tensorboard`, adds a typed event-file writer with shard rotation, and
writes the CBOR checkpoint sidecar at
`jitml-tensorboard/<experiment-hash>/checkpoints/<step>-<manifest-sha>.cbor`.

### Deliverables

- Current `src/JitML/Observability/TensorBoard.hs` implements deterministic
  event projection, shard-key rendering under
  `jitml-tensorboard/<experiment-hash>/shards/<writer-id>-<shard-seq>.tfevents`,
  TensorBoard Deployment/Service renderers, the in-memory writer state, and
  write-once shard flushing through `HasMinIO.putBlobBytesIfAbsent`.
- `proto/tensorboard/event.proto` carries the TensorFlow-compatible minimal
  `Event` / `Summary.Value.simple_value` schema used by
  `JitML.Proto.TensorBoard.encodeTensorBoardEventProto`; the writer prepends
  the `brain.Event:2` file-version event to the first shard.
- TFRecord framing follows [../README.md → TensorBoard event storage →
  Format](../README.md#format) (uint64 LE length + masked-CRC32C + payload +
  masked-CRC32C). CRC32C is Castagnoli; the mask is TF's standard rotation
  `((crc >> 15) | (crc << 17)) + 0xa282ead8`.
- Bucket layout follows [system-components.md → MinIO Bucket
  Layout](system-components.md#minio-bucket-layout) and [../README.md →
  Bucket layout](../README.md#bucket-layout): overlay mode default, isolated
  mode per Dhall knob, HPO trials always isolated by trial-hash.
- Shard rotation flushes at 4 MiB, 10 s, or explicit `flush` (e.g.
  `CheckpointDone`, graceful shutdown, SIGTERM drain). PUTs use `If-None-
  Match: *`; the same `(writer-id, shard-seq)` is idempotent.
- `TbCheckpointMarker` CBOR sidecar (`tcmStep`, `tcmEpoch`, `tcmManifestSha`,
  `tcmExperimentSha`, `tcmTrialSha`, `tcmRunUuid`, `tcmMetricsAtStep`)
  written on every `CheckpointDone`.
- `JitML.Observability.TbSidecar.dispatchCheckpointPayload` parses rendered
  `CheckpointDone` envelopes, converts them to `TbCheckpointMarker`, and
  `JitML.Service.Runtime.daemonTensorBoardDispatcher` wires the side effect
  into the daemon dispatcher contract before Pulsar ack.
- HTTPRoute for `/tensorboard` routes the TensorBoard Service through the
  single Envoy Gateway listener (Sprint `3.4`).

### Validation

1. `src/JitML/Observability/TensorBoard.hs` renders deterministic shard
   keys and the TensorBoard deployment surface.
2. `proto/tensorboard/event.proto` exists and is exercised by
   `JitML.Proto.TensorBoard.encodeTensorBoardEventProto`.
3. Live Linux CPU validation on 2026-05-18 confirms the TensorBoard rollout
   reaches Ready.
4. Live Linux CPU validation on 2026-05-19 confirms the TensorBoard chart uses
   a native `python:3.11-slim` TensorBoard container with
   `tensorboard==2.16.2`, `setuptools==69.5.1`, and `numpy<2`, plus a
   Bitnami MinIO client sidecar that mirrors bucket `jitml-tensorboard` into an
   `emptyDir` mounted at `/tensorboard/logs`.
5. Live Linux CPU validation on 2026-05-19 writes a valid TensorBoard event
   file to MinIO at
   `jitml-tensorboard/phase4-live/events/events.out.tfevents.phase4`; the
   sidecar mirrors it into the pod, `/tensorboard/` returns HTML through Envoy,
   and `/tensorboard/data/plugin/scalars/tags` reports
   `phase4-live/events -> phase4/live_scalar`.
6. Live Linux CPU validation on 2026-05-19 invokes
   `JitML.Observability.TbSidecar.dispatchCheckpointDone` through
   `JitML.Service.MinIOSubprocess` against the routed MinIO edge; the write
   returns ETag `caf7dcd34a56656da5effd135ca931eb`, and MinIO reports the CBOR
   sidecar object under
   `jitml-tensorboard/jitml-tensorboard/phase4-live/checkpoints/7-manifest-phase4-live.cbor`.
7. `jitml-unit` validates the Castagnoli CRC32C vectors, TFRecord frame layout,
   TensorBoard shard keys, and the TensorFlow-compatible scalar `Event` protobuf
   encoder against `proto/tensorboard/event.proto`.
8. `jitml-integration` validates the filesystem-backed `HasMinIO` shard writer:
   the writer prepends `brain.Event:2`, flushes a TFRecord shard through
   `putBlobBytesIfAbsent`, increments `tbwsShardSeq`, and treats duplicate
   `(writer-id, shard-seq)` writes as idempotent success.
9. `jitml-integration` validates `Runtime.daemonTensorBoardDispatcher` from a
   rendered `Training.CheckpointDone` payload through `TbSidecar` into the
   canonical CBOR sidecar key before ack.
10. Live Linux CPU validation on 2026-05-19 writes a Haskell-encoded scalar
    shard through routed `JitML.Service.MinIOSubprocess` at
    `http://127.0.0.1:9091/minio/s3`; TensorBoard's routed scalars API reports
    `jitml-tensorboard/phase4-haskell-routed-20260519-1555/shards ->
    phase4/haskell_routed`.

## Sprint 4.7: NVIDIA `RuntimeClass` for Linux CUDA ✅

**Status**: Done
**Implementation**: `chart/templates/runtimeclass-nvidia.yaml`,
`src/JitML/Cluster/Kind.hs`, `kind/cluster-linux-cuda.yaml`,
`kind/nvidia-container-runtime/config.toml`,
`src/JitML/Service/ConfigMap.hs`,
`chart/local/jitml-service/templates/deployment.yaml`
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
- The Linux CUDA Kind config registers containerd runtime handler `nvidia` with
  `BinaryName = "/usr/bin/nvidia-container-runtime"`, mounts the repo-owned
  NVIDIA runtime config into the worker, mounts the host driver root read-only
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
2. The Linux CUDA Kind config carries the GPU worker label.
3. Live Linux CPU validation on 2026-05-18 confirms the RuntimeClass manifest
   applies and `kubectl get runtimeclass nvidia` succeeds.
4. `jitml-integration` confirms the Linux CUDA Kind config includes the
   containerd `nvidia` runtime handler, the driver-root mount, toolkit mounts,
   and the GPU worker label, while non-CUDA configs do not include NVIDIA
   runtime wiring.
5. Live Linux CUDA validation on 2026-05-19, after raising the host inotify
   limits for the two-cluster validation session, creates the
   `jitml-linux-cuda` Kind cluster, applies `RuntimeClass/nvidia`, and
   schedules `pod/nvidia-smi-probe` onto `jitml-linux-cuda-worker` with
   `jitml.runtime/gpu=true`. Kubelet then rejects the sandbox with
   `no runtime for "nvidia" is configured`, proving the then-current blocker
   was Kind worker containerd runtime wiring rather than node labels or
   scheduler selection.
6. Clean live Linux CUDA validation on 2026-05-20 recreates
   `jitml-linux-cuda` from the checked-in `kind/cluster-linux-cuda.yaml`,
   confirms the worker has `jitml.runtime/gpu=true`, containerd runtime handler
   `nvidia`, the read-only `/run/nvidia/driver` mount, and the repo-owned
   runtime config, applies `RuntimeClass/nvidia`, and runs
   `pod/nvidia-smi-probe` to `Succeeded`; `kubectl logs nvidia-smi-probe`
   reports `GPU 0: NVIDIA GeForce RTX 5090`.
7. `jitml-integration` confirms the `jitml-service` Deployment renderer emits
   `runtimeClassName: nvidia`, `NVIDIA_VISIBLE_DEVICES=all`, and
   `NVIDIA_DRIVER_CAPABILITIES=compute,utility` only when substrate is
   `linux-cuda`.

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
