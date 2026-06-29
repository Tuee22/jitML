# Cluster Topology

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: README.md, ../documentation_standards.md, ../../DEVELOPMENT_PLAN/phase-0-planning-documentation.md, ../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md, ../../DEVELOPMENT_PLAN/phase-2-bootstrap-reconciler-and-jit-cache.md, ../../DEVELOPMENT_PLAN/phase-3-cluster-substrate-and-routing.md, ../../DEVELOPMENT_PLAN/phase-4-stateful-platform-services.md, ../../DEVELOPMENT_PLAN/phase-5-jitml-service-daemon.md, code_quality.md, daemon_architecture.md, durable_state_dsl.md
**Generated sections**: cluster.routes

> **Purpose**: Project-specific cluster topology for jitML — Kind cluster
> shapes per substrate, the umbrella Helm chart, the storage discipline, the
> Envoy Gateway listener, the typed route registry, the `jitml bootstrap
> --<substrate>` rollout contract, and the no-kubeconfig-pollution invariant.

**Durable-state source of truth (Sprint 4.9):** the MinIO bucket set and the logical
Pulsar topic family are now projected from the durable-state registry
(`JitML.Project.Config.defaultProjectConfig`) — `JitML.Storage.Buckets.bucketNames` is
the `ObjectBucket` projection, and the topic logical names are anti-drift-checked
against `JitML.Coordinator.Topology`. See [durable_state_dsl.md](durable_state_dsl.md).

**HA topology source of truth (2026-06-27):** this document describes the
implemented HA topology: one control-plane node plus three workers per
substrate, one localhost Envoy edge socket, distributed stateful services, and
scoped placement that permits at most one numerical ML compute worker of each
scope per Kubernetes node. Phase `3` Sprint `3.6`, Phase `4` Sprint `4.10`, and
Phase `5` Sprint `5.16` implemented the local materialization; Phase `15`
Sprint `15.22` revalidated the Linux CUDA live lane, and Phase `16` Sprint
`16.14` owns the remaining Apple Silicon live lane revalidation.

## Substrates and Cluster Shapes

| Substrate | Kind shape | Node labels | Daemon residency |
|-----------|-------------------|-------------|------------------|
| `apple-silicon` | one control-plane plus three workers from `dhall/cluster/resources.dhall` | workers carry `jitml.node-role/compute=true`; host Metal compute remains host-resident | clustered (`Cluster + ForwardToHost`) + host-native (`Host + SelfInference`) |
| `linux-cpu` | one control-plane plus three workers from `dhall/cluster/resources.dhall` | workers carry `jitml.node-role/compute=true` for numerical compute placement | clustered only (`Cluster + SelfInference`) |
| `linux-cuda` | one control-plane plus three workers from `dhall/cluster/resources.dhall` | CUDA workers carry `jitml.node-role/compute=true` and `jitml.runtime/gpu=true` | clustered only (`Cluster + SelfInference`) |

Per-substrate Kind configs live at `kind/cluster-<substrate>.yaml`. The
`kindest/node` pin is the single source of toolchain truth; it is mirrored as a
comment in `cabal.project`. `jitml lint chart` rejects drift between the two.
`JitML.Cluster.Kind.renderKindConfig` renders the checked-in control-plane plus
worker topology for every substrate while keeping a single host-port mapping on
the control-plane.

The host `./.build/` directory is bind-mounted into Kind via the `extraMounts`
block in the Kind config. This is what lets in-cluster Linux workloads see the
repo-local build/cache tree. The HA profile mounts every materialized Kind node
that may run jitML workloads. It is **not**
an Apple Metal execution bridge: Apple Metal work is macOS-host-resident and
reaches the cluster only through Pulsar and MinIO. This is the **one** exception
to the "no freestanding host paths in pod specs" discipline; the chart lint
permits exactly this hostPath and rejects any other.

## Storage Discipline: `kubernetes.io/no-provisioner` Only

Every StorageClass uses the `kubernetes.io/no-provisioner` provisioner — no
dynamic provisioning anywhere in the chart. Every PV is **manually defined**
in `chart/templates/pv-<statefulset>.yaml` against the `jitml-manual`
StorageClass and backed by a `hostPath` under
`/jitml/.data/<namespace>/<StatefulSet-name>/pv_<replica-int>/` inside the
Kind node. The host directory is repo-local
`./.data/<namespace>/<StatefulSet-name>/pv_<replica-int>/`, mounted into the
node at `/jitml/.data`; `.data` is strictly for these manual PV bind mounts.
Kind metadata, runtime coordinates, kubeconfig, generated Dhall, and JIT
artifacts live under `./.build/`.

Apple Silicon and Docker Desktop `linux-cpu` use a node-local bind overlay for
the registered Percona Postgres PVs before the `harbor-pg` cluster starts:
bootstrap creates `/var/local/jitml-postgres-pv/...` inside the Kind node,
bind-mounts those directories over the corresponding
`/jitml/.data/.../harbor-pg*` paths, and normalizes the node-local directories
to uid/gid `26:26`. The checked-in PV identity and chart paths remain the
repo-local `.data` layout, but the live Postgres relation files are written to
node-local storage on macOS/Docker Desktop to avoid host bind-mount ownership and
relation-file permission drift. `linux-cuda` runs on a real Linux/NVIDIA host
and uses the `.data` hostPath directly with ownership normalization.

Every PVC is created **only** by a StatefulSet's `volumeClaimTemplates`;
freestanding PVCs are a chart-lint failure. StatefulSet PVs carry
`claimRef.namespace` and `claimRef.name` to bind each PV to one PVC so a
teardown / spinup yields the exact same binding. Registered Percona
`PerconaPGCluster` volumes bind from the generated PVC side through explicit
`volumeName` fields because the Percona operator appends controller suffixes to
PVC names. Dynamic provisioning would erode reproducibility.

Naming convention is uniform:

- on disk: `<k8s-namespace>/<StatefulSet-name>/pv_<replica-int>`
- as a PV resource: `<namespace>-<statefulset>-pv-<int>` (DNS-1123 compatible)

Example layout for the `platform` namespace:

```
.data/
└── platform/
    ├── minio/{pv_0, pv_1, pv_2, pv_3}                  -- 4 distributed replicas
    ├── pulsar-bookie-journal/{pv_0, pv_1, pv_2}        -- bookie journals
    ├── pulsar-bookie-ledgers/{pv_0, pv_1, pv_2}        -- bookie ledgers
    ├── pulsar-zookeeper-data/{pv_0, pv_1, pv_2}        -- ZK data
    ├── harbor-pg/{pv_0, pv_1, pv_2}                    -- 3 Postgres instances
    └── harbor-pg-repo1/pv_0                            -- pgBackRest repo
```

`jitml lint files` rejects any path under `.data/` that does not match the
`<namespace>/<StatefulSet>/pv_<int>` regex. `jitml lint chart`
rejects any StorageClass with a provisioner other than
`kubernetes.io/no-provisioner`, any freestanding PVC, and any PV without either
an explicit `claimRef` or a registered Percona `volumeName` binding.

## Helm Chart Layout

Single umbrella chart at `chart/`. `Chart.yaml` declares subchart
dependencies:

| Third-party dependency | Purpose | Owning sprint |
|------------------------|---------|---------------|
| `harbor` | Image registry | Sprint 4.1 |
| `pg-operator` | Percona Operator; HA Postgres clusters are jitML-rendered `PerconaPGCluster` CRs, not a `pg-db` subchart | Sprint 4.2 |
| `pulsar` | Apache Pulsar HA (3× ZooKeeper, 3× BookKeeper, 3× Broker, 3× Proxy; broker-embedded WebSocket enabled and routed through `/pulsar/ws`) | Sprint 4.4 |
| `minio` | Distributed-mode object store (4 replicas) | Sprint 4.3 |
| `gateway-helm` | Envoy Gateway controller | Sprint 3.3 |
| `kube-prometheus-stack` | Prometheus operator + Grafana | Sprint 4.5 |

Templates in `chart/templates/`: GatewayClass, Gateway, HTTPRoutes rendered
from the route registry, EnvoyProxy, manual PVs, the materialized
`jitml-service` Deployment, NVIDIA RuntimeClass for the CUDA substrate, service
ConfigMaps, generated Grafana dashboard ConfigMaps, and the generated
Prometheus scrape config. The `jitml-demo` Webapp workload lives in the local
chart under `chart/local/jitml-demo`. The current typed renderers live under
`src/JitML/Observability/`.

Checked-in jitML-owned local charts live under `chart/local/`:
`tensorboard`, `jitml-service`, and `jitml-demo`. The `jitml-service` local
chart includes a ClusterIP Service on port `8080` for the Prometheus scrape
target. The typed live rollout installs those paths directly and leaves
`chart/charts/` as Helm's generated dependency cache for third-party archives
only. `jitml lint chart` treats that cache as binary Helm output and limits
text manifest checks to YAML files.

Typed direct-install values live under `chart/values/` and are passed only by
the corresponding `JitML.Cluster.Helm` subprocess. Current files cover the
local live footprints for Harbor, MinIO, Pulsar, and kube-prometheus-stack.
Harbor's direct file, `chart/values/harbor.yaml`, disables local TLS, keeps the
ClusterIP exposure, and points `database.type=external` at
`harbor-pg-pgbouncer.platform.svc:5432` with credentials from
`harbor-pg-secrets` and `sslmode=require`; it also sets registry storage to the MinIO
`harbor-registry` S3 backend with redirects disabled and a 128 MiB chunk size.
The live install still receives a typed
`externalURL=http://127.0.0.1:<edge-port>` override. These inputs keep the
generated dependency archives installable when the live rollout installs a
subchart `.tgz` directly instead of installing the umbrella chart.

## Resource Budgets and the Kind-Node Cap

The HA topology is bounded by a typed Dhall resource profile (`dhall/cluster/`,
decoded by `JitML.Cluster.Resources`) rather than running unbounded. The profile
is the source of truth for node caps, per-pod requests/limits, HA service
replica counts, and worker placement budgets. It also preserves single-host phase
closeability under the project's
[Substrate-affinity phasing](../../README.md#substrate-affinity-phasing)
doctrine: each development phase brings its lane up on one host with at most one
accelerator plus `linux-cpu` (bound by
[`DEVELOPMENT_PLAN/development_plan_standards.md` rule M](../../DEVELOPMENT_PLAN/development_plan_standards.md)).
- **Kind-node caps** — after `kind create`, the bootstrap reconciler applies
  `docker update --memory/--memory-swap/--cpus` caps to materialized Kind nodes
  from the profile. An over-budget cluster then OOM-kills pods inside node
  cgroups instead of exhausting the host. A `cluster.host-memory` preflight
  (`jitml doctor --scope cluster`) fails fast when host RAM is below the cap +
  reserve.
- **Per-pod budgets and HA replicas** — Harbor, MinIO, Pulsar, service Postgres,
  observability, TensorBoard, and jitML roles carry CPU/memory requests+limits
  and HA replica counts from the same profile. Manual PV layout follows the HA
  counts.
- **Numerical worker cardinality** — regardless of service replica counts, the
  Engine/numerical ML compute role is capped at one worker per Kubernetes node.
  Coordinator, Webapp, observability, and platform-service replicas may scale
  independently without creating extra numerical workers on the same node.

The compact single-node guardrails introduced by Phase `2` Sprint `2.8`, Phase
`4` Sprint `4.8`, and Phase `3` Sprint `3.2` are historical evidence only; the
current materialized profile is the HA profile above.

## Helm Values Ownership

`chart/templates/` contains only Kubernetes manifests rendered by Helm. It must
not contain Helm values files, subchart values files, or auxiliary YAML that is
not itself a Kubernetes object; Helm lint parses every file under
`chart/templates/` as a manifest.

Umbrella-chart configuration belongs in `chart/values.yaml` under the subchart
key that consumes it, for example `minio:`, `pulsar:`, or
`kube-prometheus-stack:`. A separate values file under `chart/` is valid only
when a typed `helm` subprocess explicitly passes it with `-f` / `--values`, and
the owning plan/doc section names that invocation. Otherwise, standalone files
such as `chart/<subchart>-values.yaml` are cleanup candidates: fold their
content into `chart/values.yaml` and remove the extra materialization path.

This keeps the umbrella chart self-contained, makes `helm lint chart` reflect
the actual install input, and avoids checked-in values fragments that are
materialized but never consumed by Helm. `jitml lint chart` rejects values files
under `chart/templates/`; the former standalone MinIO values fragment now lives
under `minio:` in `chart/values.yaml`.

## Phased Deploy

The target `jitml bootstrap --<substrate>` runs the phased rollout:

0. **Dependency phase**: `JitML.Cluster.Helm` renders
   `helm dependency build chart` before any live apply. `Chart.lock` is adopted
   only if reproducible dependency locking becomes part of the release surface;
   `chart/charts/` is not vendored by default.
1. **Harbor phase**: MinIO starts first and the `harbor-registry` bucket is
   checked, the Percona Operator is installed next, the registered `harbor-pg`
   cluster is applied and waited ready, a typed `kubectl exec ... psql` grant
   gives the `harbor` role ownership of schema `public`, and Harbor then starts
   against `harbor-pg-pgbouncer.platform.svc` and the MinIO S3 backend using
   the direct subchart values file.
2. **Image build/load phase**: the `jitml:local` image is built locally and
   retagged as `jitml-demo:local`, then both tags are loaded explicitly into the
   selected Kind cluster with `kind load docker-image`. The `jitml:local` build
   is also the exclusive Haskell style/code-quality gate: it uses the same
   pinned GHC `9.12.4` to build pinned Fourmolu / HLint binaries and fails the
   image build on Haskell style or warning-clean build drift. The third-party
   chart images (`docker.io/*` — MinIO, Pulsar, Harbor, etc.) are **pre-pulled
   authenticated on the host and `kind load`ed** (Sprint `2.13`) so the Kind
   node's containerd never pulls them anonymously from Docker Hub during the
   final-phase Helm waits — anonymous pulls on a cold host hit the Docker Hub
   **429** rate limit. The pre-pull **reads** the host's existing `docker login`
   (the in-container bootstrap's client is not logged in, so `linux-cpu` /
   `linux-cuda` pre-pull in the stage-0 host script before delegating; the
   host-native `apple-silicon` bootstrap pre-pulls directly) and **never writes**
   `~/.docker/config.json`, honoring the bootstrap no-touch invariant
   ([../../README.md → Bootstrap scripts](../../README.md#bootstrap-scripts)). This
   is jitML's own self-contained Docker Hub credential path: host `config.json`
   discovery → authenticated host `docker pull` → `kind load` into the Kind node,
   plus the in-cluster `imagePullSecret` projected from the host Docker Hub
   credential (Sprint `2.14`). It is owned by the project, not a transitional
   stand-in.
3. **Final phase**: Pulsar, Envoy Gateway, kube-prometheus-stack,
TensorBoard, the `jitml-service` workload (all substrates: Linux
   self-inference plus Apple forward-to-host), and the `jitml-demo` workload
   roll out after the local image tags are present in Kind.

This makes local bootstrap explicit: Harbor is installed and routed as the
stateful platform registry, but Phase `3` does not require the host Docker
daemon or Kind node container runtime to resolve an in-cluster Harbor DNS name
before the cluster itself is stable. The route registry exposes Harbor's portal
and API under `/harbor`, and exposes Docker registry auth surfaces at `/v2` and
`/service`. Those public paths route through the chart's `harbor` nginx service
rather than directly to the internal registry service, so Docker receives the
Bearer-token challenge from Harbor's public auth flow. Live Harbor push/pull is
validated through `JitML.Service.HarborSubprocess`, whose settings name the
registry, API base URL, credentials, repo-local Docker config directory,
optional Docker host socket, Docker binary, and curl binary explicitly. Live
Linux CPU validation on 2026-05-19 also pushed a tiny OCI artifact through the
registry HTTP API, confirmed Harbor's artifact API reported the same digest,
and confirmed MinIO stored the repository layer, manifest, and tag-link objects
under bucket `harbor-registry`, proving the direct Harbor values use the
external Postgres and S3 backend path. The same live-validation family runs the
cluster toolchain from `jitml:local` with host networking and a repo-local
Docker config, logs Docker into `127.0.0.1:9091`, pushes and pulls
`library/jitml-phase4-docker`, lists the repository through `/harbor/api`, and
confirms the pushed tag's artifact API returns HTTP `200`.

For Apple Silicon, the edge publication is also the host daemon's service
discovery contract. `jitml bootstrap --apple-silicon` writes
`./.build/runtime/cluster-publication.json` and patches
`./.build/conf/host/apple-silicon.dhall` with routed Pulsar and MinIO URLs. The
host daemon converts `pulsar://127.0.0.1:<edge>/pulsar` to the routed WebSocket
path and sends S3 requests through `/minio/s3`. It does not use the Kubernetes API
to discover work, and the cluster must not schedule Apple Metal execution into
Linux pods.

`jitml cluster up` materializes local Kind, chart, Dhall, and publication inputs
without mutating a live cluster. `jitml bootstrap --<substrate>` materializes
those inputs and then calls `JitML.Bootstrap.liveExecutePhasedRollout` directly;
there is no process-environment safety gate for local Kind/Helm work. The live
path runs the typed `kind`, Helm, Docker build / Kind image-load, repo-owned
manifest apply, platform readiness, and Pulsar-topic subprocesses through the
`Subprocess` boundary and stops at the first failed subprocess so a failed image
build or image load cannot be masked by later Helm rollout failures. The topic
subprocesses register the substrate-scoped
family consumed by `jitml service`: eight command/event topics for each
substrate plus the Apple-only `inference.command.apple-silicon` forward topic
and the Apple host-command topics `training.host-command.apple-silicon`,
`tune.host-command.apple-silicon`, and `rl.host-command.apple-silicon`. The
in-cluster Apple daemon forwards each raw inference command onto
`inference.command.apple-silicon`, and the host Engine publishes the
`InferenceResult` to the request's reply-topic directly (the converged values
model). The Apple placement path forwards Metal-backed starts to the
host-command topics rather than rendering Linux worker Jobs; Phase `12` owns the
live no-Job assertion. The live path rewrites the
Kind/Gateway/EnvoyProxy inputs from the selected edge-port lease, writes
`./.build/runtime/cluster-publication.json` with that lease and measured Helm
release status, and patches the Apple host Dhall from the publication.
Platform readiness includes rollout checks and a
retry-hardened in-pod MinIO bucket check that aliases
`http://minio.platform.svc.cluster.local:9000` through the Bitnami `mc` client
and lists every bucket from `JitML.Storage.Buckets`.
The live HTTP S3 client is `JitML.Service.MinIOSubprocess`; for the routed
edge it signs the canonical path-style S3 URL and passes
`--request-target /minio/s3/...` to curl so Envoy can rewrite the request to
MinIO's upstream path while SigV4 verification still uses the path MinIO sees.
External Helm dependencies install from the `.tgz` archives produced by
`helm dependency build`, using typed values files from `chart/values/` when
direct subchart installs need values; jitML-owned workloads install from
`chart/local/`. Historical live Linux CPU validation on 2026-05-23 completed
the compact 110-step phased rollout plus readiness checks, built and loaded
`jitml:local`, retagged it as `jitml-demo:local`, loaded both tags into Kind, served
`http://127.0.0.1:9091/api` through Envoy, published the expected Pulsar topic
family, wrote ready publication health, and validated `jitml cluster down`
teardown plus the second-run no-op exit `3`. The 2026-05-19 live run confirms
`/pulsar/admin` works through the
edge, `/pulsar/ws` resolves to `pulsar-broker:8080`, the broker config carries
`webSocketServiceEnabled=true`, and routed WebSocket publish/consume succeeds
through `JitML.Service.PulsarWebSocketSubprocess`. The 2026-05-20 live run
reconciles all 26 current substrate-scoped Pulsar topics and publishes/consumes
on `persistent://public/default/training.command.linux-cpu` through the
`jitml:local` WebSocket subprocess path. The 2026-05-19 live run
revalidated Harbor's preconditions and
backend wiring with MinIO bucket readiness, `harbor-pg` readiness, schema
ownership grant, Harbor rollout readiness, and a registry-API artifact write
that appeared in MinIO. The same 2026-05-19 validation confirms the generated
Grafana dashboard ConfigMaps are served behind `/grafana` and Prometheus
reports `jitml-service.platform.svc.cluster.local:8080/metrics` as an `up`
target behind `/prometheus`. The same 2026-05-19 validation confirms routed
MinIO `HasMinIO` operations through `http://127.0.0.1:9091/minio/s3`: duplicate
`If-None-Match: *` writes and stale `If-Match` pointer CAS return `SEConflict`,
and read, list, and delete succeed. The same 2026-05-19 validation confirms
TensorBoard serves behind `/tensorboard`, reads a mirrored event shard from the
`jitml-tensorboard` MinIO bucket via the scalars API, and the CBOR checkpoint
sidecar writer can write to live routed MinIO. A second 2026-05-19 validation
writes a Haskell-encoded TensorBoard scalar shard through routed
`JitML.Service.MinIOSubprocess`; TensorBoard reports
`phase4/haskell_routed` from the routed scalars API.

## `jitml-service` Deployment, Not StatefulSet

The Engine/numerical compute role is stateless and owns no PVC of its own —
durable state lives entirely in MinIO and Pulsar — so a StatefulSet would be the
wrong shape. The HA target enforces scoped **at most one numerical ML compute
worker per Kubernetes node** placement. Required anti-affinity/topology-spread
belongs to compute scopes; Coordinator, Webapp, observability, and platform
services may use their own replica counts without placing additional numerical
workers on a node. Linux substrates render three Engine replicas, pin them to
`jitml.node-role/compute=true` workers, and label them `jitml.compute="true"` plus
`jitml.compute-scope="service"`. Daemon-spawned Linux Training/RL/Tune Jobs use
`jitml.compute="true"` plus `jitml.compute-scope="workload"`. Each scope matches
only itself for required hostname anti-affinity and hard topology spread, so Jobs
cannot bypass their one-per-node invariant and also cannot be blocked by the HA
service replicas. Apple Silicon keeps the clustered service as a single
non-compute forwarder (`jitml.compute="false"`); Metal work remains on the host
daemon.

The Kind node maintains its JIT cache under the mounted
`./.build/jit/<substrate>/` hostPath. JIT artifacts are deterministic functions
of `(model-shape, kind, substrate, toolchain)`.

Namespace: `platform` (fixed). The live local chart rollout creates or reuses
that namespace, mounts the current typed Dhall ConfigMap, and exposes the
daemon HTTP surface on a ClusterIP Service at port `8080`; 2026-05-19 live
validation port-forwarded that Service and verified `/healthz`, `/readyz`, and
`/metrics`. 2026-05-23 single-node validation covers the replacement update
strategy, service-account kubectl access from inside the pod, the Linux CUDA
service pod under `runtimeClassName: nvidia`, and the Apple Silicon host-Dhall
subscription path.

## Envoy Gateway: A Single Localhost Socket

There is **one user-facing socket**: `127.0.0.1:<edge-port>`. Selected by
`jitml bootstrap --<substrate>` starting at `9090` and incremented until
available. Recorded as the `edge_port` field of
`./.build/runtime/cluster-publication.json` alongside `pulsar_url`,
`minio_url`, and component health. `jitml cluster status` reads this file, and
the Apple host `BootConfig` turns those publication fields into
`pulsarServiceUrl`, `pulsarAdminUrl`, `minioEndpoint`, and `harborRegistry`
before `JitML.Service.Clients` derives the concrete subprocess endpoints. Live
Apple Silicon validation on 2026-05-21 runs the patched
`./.build/conf/host/apple-silicon.dhall` against the leased
`127.0.0.1:9090` edge route with
`jitml service --config ./.build/conf/host/apple-silicon.dhall --consume-once 0`;
that host-native run passes routed client probes and acquires
`persistent://public/default/inference.command.apple-silicon` as `jitml-host`.

The shape:

- `GatewayClass/jitml-gateway` declares the Envoy Gateway controller and
  references `EnvoyProxy/jitml-edge` via `parametersRef`.
- `Gateway/jitml-edge` listens at `127.0.0.1:<edge-port>`.
- `EnvoyProxy/jitml-edge` is a NodePort service, `externalTrafficPolicy:
  Cluster`, with the Gateway listener port pinned to NodePort `30090` for the
  Kind host-port mapping. Its managed Envoy data-plane request is pinned to
  `cpu: 50m` / `memory: 64Mi` in the compact local profile so the platform can
  schedule the edge proxy after Harbor, MinIO, Pulsar, observability, and the
  demo/service workloads are ready; Sprint `3.6` owns any HA resource-profile
  adjustment.

Routes are rendered from the typed route registry in `src/JitML/Routes.hs`.
Hand-written HTTPRoute YAML is hlint-forbidden.

## Routes Published at the Edge

<!-- jitml:cluster.routes:start -->
| Prefix | Service | Port | Rewrite | WebSocket |
|--------|---------|------|---------|-----------|
| `/` | `jitml-demo` | 80 | `-` | no |
| `/api` | `jitml-demo` | 80 | `-` | no |
| `/api/ws` | `jitml-demo` | 80 | `-` | yes |
| `/healthz` | `jitml-service` | 8080 | `-` | no |
| `/readyz` | `jitml-service` | 8080 | `-` | no |
| `/metrics` | `jitml-service` | 8080 | `-` | no |
| `/tensorboard` | `tensorboard` | 80 | `/` | no |
| `/grafana` | `kube-prometheus-stack-grafana` | 80 | `/` | no |
| `/prometheus` | `kube-prometheus-stack-prometheus` | 9090 | `/` | no |
| `/harbor` | `harbor` | 80 | `/` | no |
| `/harbor/api` | `harbor` | 80 | `/api` | no |
| `/v2` | `harbor` | 80 | `-` | no |
| `/service` | `harbor` | 80 | `-` | no |
| `/minio/console` | `minio` | 9001 | `/` | no |
| `/minio/s3` | `minio` | 9000 | `/` | no |
| `/pulsar/admin` | `pulsar-proxy` | 80 | `/admin` | no |
| `/pulsar/ws` | `pulsar-broker` | 8080 | `/ws` | yes |
<!-- jitml:cluster.routes:end -->

This table is regenerated from the route registry (Sprint `3.4`) by
`jitml docs generate`. Hand edits fail `jitml docs check`.

TLS is off for the local demo. The production-deployment posture is
intentionally not specified.

## Bootstrap Script Surface

Sprint `2.1` owns and has closed the stage-0 bootstrap scripts under
`bootstrap/{apple-silicon,linux-cpu,linux-cuda}.sh` plus shared helpers in
`bootstrap/_lib.sh`. The scripts do only enough work to reach Haskell:

- `apple-silicon.sh` verifies macOS on Apple Silicon, the source-build
  prerequisites for `./.build/jitml`, and Homebrew when typed remediation may
  need it; then it builds `./.build/jitml` and calls
  `./.build/jitml bootstrap --apple-silicon`. The delegated bootstrap still
  builds `jitml:local` for the in-cluster daemon, so Apple Silicon receives the
  same container-exclusive Haskell style gate as Linux. Full Xcode is **never**
  installed on the host. Core Apple Silicon Metal cache misses write
  `<hash>.metal.json` source metadata and dispatch through the fixed host Metal
  bridge, which JIT-compiles MSL at runtime via
  `MTLDevice.makeLibrary(source:)` and dispatches on the host GPU. See
  [jit_codegen_architecture.md → Apple Silicon Fixed-Bridge Metal JIT](jit_codegen_architecture.md#apple-silicon-fixed-bridge-metal-jit).
- `linux-cpu.sh` verifies Docker is usable without `sudo`; then it calls
  `docker compose run --rm jitml jitml bootstrap --linux-cpu`.
- `linux-cuda.sh` adds NVIDIA container-runtime and `nvidia-smi` compute
  capability checks; then it calls
  `docker compose run --rm jitml jitml bootstrap --linux-cuda`. The Linux CUDA
  Kind config registers the CUDA workers' containerd `nvidia` runtime handler,
  mounts the repo-owned NVIDIA runtime config, mounts the host driver root
  read-only at `/run/nvidia/driver`, and mounts the node-local NVIDIA toolkit
  support needed by the runtime hook.

Missing stage-0 gates return exit code `2` with installation instructions. All
broader package validation/remediation belongs to the Haskell typed
prerequisite DAG. Homebrew packages may be installed lazily by `jitml` through
Plan/Apply prerequisite remediation; shell scripts never install them.
Current validation on 2026-05-23 runs the live cluster toolchain from the
`jitml:local` image with the repository mounted at the same absolute host path;
the root `compose.yaml` pins the headless `jitml` service to host networking so
Kind kubeconfig loopback endpoints are reachable from the outer container. The
GPU-enabled `jitml-cuda` companion service uses the same image and mount shape,
adding only `gpus: all` for direct live CUDA tests that need device exposure in
the outer container. The Linux CPU bootstrap completes the 110-step live
rollout and publishes all platform components as ready on edge port `9091`.

2026-05-23 Linux CUDA live validation on a GPU host (NVIDIA GeForce RTX 5090,
CUDA 12.8) historically closed both Phase `4` Sprint `4.7` and the CUDA portion
of Phase `5` Sprint `5.6` against the compact `jitml-linux-cuda` shape. The
current HA renderer preserves that CUDA RuntimeClass contract on the three GPU
worker nodes: worker labels include `jitml.runtime/gpu=true`,
`RuntimeClass/nvidia` applies, and `Deployment/jitml-service` plus daemon-spawned
CUDA worker Jobs render `runtimeClassName: nvidia`,
`NVIDIA_VISIBLE_DEVICES=all`, and
`NVIDIA_DRIVER_CAPABILITIES=compute,utility`. Live HA CUDA revalidation is owned
by Phase `15` Sprint `15.22`.

2026-05-23 Apple Silicon live validation completed `./bootstrap/apple-silicon.sh
up` on the same compact topology, published all seven components ready on
edge port `9090`, patches `./.build/conf/host/apple-silicon.dhall` with routed
edge coordinates, and runs the host-native
`jitml service --consume-once 0` acquisition check. The host daemon derives
`/pulsar/ws`, `/minio/s3`, Harbor, and repo-local kubeconfig settings from that
Dhall and acquires `inference.command.apple-silicon` as `jitml-host`.

## No Kubeconfig Pollution

The CLI never touches `~/.kube/config`. Cluster kubeconfig lives at
`./.build/jitml.kubeconfig`; the live Kind subprocess may write/export to an
in-container temporary kubeconfig first, then copy the completed file to that
repo-local path so Kind's lock file never lives on the Docker bind mount.
Stage-0 scripts forbid touches to
`~/.kube/config`, `~/.docker/config.json`, the user's Homebrew prefix, or any
global state outside the repo. Haskell `jitml` may install Homebrew packages
only through typed lazy prerequisite remediation. `./.build/` holds build
outputs, generated Dhall, runtime coordinates, kubeconfig, Kind metadata, and
JIT artifacts; `./.data/` holds only manual PV bind mounts.

## Cross-References

- [../../README.md → Cluster topology and Kind](../../README.md#cluster-topology-and-kind)
- [../../README.md → Envoy Gateway API](../../README.md#envoy-gateway-api-a-single-localhost-socket)
- [../../README.md → Helm chart layout](../../README.md#helm-chart-layout)
- [daemon_architecture.md](daemon_architecture.md)
- [../../DEVELOPMENT_PLAN/phase-3-cluster-substrate-and-routing.md](../../DEVELOPMENT_PLAN/phase-3-cluster-substrate-and-routing.md)
- [../../DEVELOPMENT_PLAN/phase-4-stateful-platform-services.md](../../DEVELOPMENT_PLAN/phase-4-stateful-platform-services.md)
