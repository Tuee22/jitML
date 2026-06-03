# Cluster Topology

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: README.md, ../documentation_standards.md, ../../DEVELOPMENT_PLAN/phase-0-planning-documentation.md, ../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md, ../../DEVELOPMENT_PLAN/phase-2-bootstrap-reconciler-and-jit-cache.md, ../../DEVELOPMENT_PLAN/phase-3-cluster-substrate-and-routing.md, ../../DEVELOPMENT_PLAN/phase-4-stateful-platform-services.md, ../../DEVELOPMENT_PLAN/phase-5-jitml-service-daemon.md, code_quality.md, daemon_architecture.md
**Generated sections**: cluster.routes

> **Purpose**: Project-specific cluster topology for jitML — Kind cluster
> shapes per substrate, the umbrella Helm chart, the storage discipline, the
> Envoy Gateway listener, the typed route registry, the `jitml bootstrap
> --<substrate>` rollout contract, and the no-kubeconfig-pollution invariant.

## Substrates and Cluster Shapes

| Substrate | Kind shape | Node labels | Daemon residency |
|-----------|------------|---------------|------------------|
| `apple-silicon` | 1 control-plane node, no worker node | none | clustered (`Cluster + ForwardToHost`) + host-native (`Host + SelfInference`) |
| `linux-cpu` | 1 control-plane node, no worker node | none | clustered only (`Cluster + SelfInference`) |
| `linux-cuda` | 1 control-plane node, no worker node | `jitml.runtime/gpu=true` | clustered only (`Cluster + SelfInference`) |

Per-substrate Kind configs at `kind/cluster-<substrate>.yaml`. The `kindest/
node` pin is the single source of toolchain truth; it is mirrored as a
comment in `cabal.project`. `jitml lint chart` rejects drift between the two.
The checked-in configs and `JitML.Cluster.Kind.renderKindConfig` use one Kind
node for every substrate. There is no local control-plane/worker split.

The host `./.build/` directory is bind-mounted into the single Kind node via the
`extraMounts` block in the Kind config. This is what lets the in-cluster
`jitml-service` pod see the same JIT artefacts the host built. This is the
**one** exception to the "no freestanding host paths in pod specs"
discipline; the chart lint permits exactly this hostPath and rejects any
other.

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
    ├── pulsar-bookkeeper/{pv_0, pv_1, pv_2}            -- 3 bookies
    ├── pulsar-zookeeper/{pv_0, pv_1, pv_2}             -- 3 ZK nodes
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

| Subchart | Purpose | Owning sprint |
|----------|---------|---------------|
| `harbor` | Image registry | Sprint 4.1 |
| `pg-operator` + `pg-db` | Percona Operator HA Postgres for packaged services that require Postgres (jitML itself never writes to it) | Sprint 4.2 |
| `pulsar` | Apache Pulsar HA (3× ZooKeeper, 3× BookKeeper, 3× Broker, 3× Proxy; broker-embedded WebSocket enabled and routed through `/pulsar/ws`) | Sprint 4.4 |
| `minio` | Distributed-mode object store (4 replicas) | Sprint 4.3 |
| `gateway-helm` | Envoy Gateway controller | Sprint 3.3 |
| `kube-prometheus-stack` | Prometheus operator + Grafana | Sprint 4.5 |
| `tensorboard` | jitML-owned local chart with MinIO event-storage backing through a MinIO-client mirror sidecar | Sprint 4.6 |

Templates in `chart/templates/`: GatewayClass, Gateway, HTTPRoutes rendered
from the route registry, EnvoyProxy, manual PVs, `jitml-service` Deployment,
`jitml-demo` Deployment, NVIDIA RuntimeClass for the CUDA substrate, service
ConfigMaps, generated Grafana dashboard ConfigMaps, and the generated
Prometheus scrape config. The current typed renderers live under
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

The single Kind node hosts the entire platform stack on one host, so the cluster
is bounded by a typed Dhall resource profile (`dhall/cluster/`, decoded by
`JitML.Cluster.Resources`) rather than running unbounded. The profile is the
single source of truth for two guardrails introduced after the 2026-05-29 host
OOM-storm incident:

- **Kind-node cap** — after `kind create`, the bootstrap reconciler applies a
  `docker update --memory/--memory-swap/--cpus` cap to
  `jitml-<substrate>-control-plane` from the profile's `nodeMemoryMiB` / `nodeCpus`.
  An over-budget cluster then OOM-kills its own pods inside the node cgroup instead
  of exhausting the host. A `cluster.host-memory` preflight (`jitml doctor --scope
  cluster`) fails fast when host RAM is below the cap + reserve.
- **Per-pod budgets and right-sized replicas** — Harbor, MinIO, Pulsar, service
  Postgres, and observability carry CPU/memory requests+limits and reduced replica
  counts (MinIO `4→1–2`, Pulsar zk/bookkeeper/broker/proxy `3→1`, Postgres `3→1`)
  from the same profile, applied through the typed `helm` `--set` seam and the
  `chart/values/*.yaml` files; the manual-PV layout (Storage Discipline above)
  follows the reduced counts. They are sized so the sum of pod limits plus node
  overhead stays under the kind-node cap.

These guardrails are owned by Phase `2` Sprint `2.8` (profile + cap + preflight),
Phase `4` Sprint `4.8` (per-pod budgets + replicas), and Phase `3` Sprint `3.2`
(PV layout); see
[Development Plan → Reopened phases](../../DEVELOPMENT_PLAN/README.md#reopened-phases-2026-05-29).

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
2. **Image build/load phase**: the `jitml:local` image and the
   `jitml-demo:local` image are built locally, then loaded explicitly into the
   selected Kind cluster with `kind load docker-image`. The `jitml:local` build
   is also the exclusive Haskell style/code-quality gate: it installs the
   separate style-tools GHC plus pinned Fourmolu / HLint binaries and fails the
   image build on Haskell style or warning-clean build drift.
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
substrate plus the Apple-only inference RPC pair. The live path rewrites the
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
`chart/local/`. Live Linux CPU validation on 2026-05-23 completed the
single-node 110-step phased rollout plus readiness checks, built and loaded
`jitml:local` and `jitml-demo:local` into Kind, served
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

The orchestrator is a stateless **Deployment** with `replicas: 1` by default
and required pod **anti-affinity** at `topologyKey:
kubernetes.io/hostname`. The local Kind topology has one node, so the supported
local `jitml-service` replica count is one. The anti-affinity remains in the
chart to keep the one-service-pod-per-node rule when the chart is applied to a
non-local multi-node environment. Rolling updates use `maxSurge: 0` and
`maxUnavailable: 1` so replacement works on the single-node Kind cluster.
The daemon owns no PVC of its own — durable state lives entirely in MinIO and
Pulsar — so a StatefulSet would be the wrong shape.

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
  Kind host-port mapping.

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

- `apple-silicon.sh` verifies macOS on Apple Silicon, Xcode Command Line Tools,
  and Homebrew; then it builds `./.build/jitml` and calls
  `./.build/jitml bootstrap --apple-silicon`. The delegated bootstrap still
  builds `jitml:local` for the in-cluster daemon, so Apple Silicon receives the
  same container-exclusive Haskell style gate as Linux. Only the Xcode Command
  Line Tools are required on the host; full Xcode is **never** installed,
  because its first-launch/license UI prompts break the headless bootstrap.
  Apple Silicon Metal kernels build **on the host** with the CommandLineTools
  `swift build` and JIT-compile at runtime via `MTLDevice.makeLibrary(source:)`
  — no Tart VM. See
  [jit_codegen_architecture.md → Apple Silicon Headless JIT](jit_codegen_architecture.md#apple-silicon-headless-jit).
- `linux-cpu.sh` verifies Docker is usable without `sudo`; then it calls
  `docker compose run --rm jitml jitml bootstrap --linux-cpu`.
- `linux-cuda.sh` adds NVIDIA container-runtime and `nvidia-smi` compute
  capability checks; then it calls
  `docker compose run --rm jitml jitml bootstrap --linux-cuda`. The Linux CUDA
  Kind config registers the single node's containerd `nvidia` runtime handler, mounts
  the repo-owned NVIDIA runtime config, mounts the host driver root read-only at
  `/run/nvidia/driver`, and mounts the node-local NVIDIA toolkit support needed
  by the runtime hook.

Missing stage-0 gates return exit code `2` with installation instructions. All
broader package validation/remediation belongs to the Haskell typed
prerequisite DAG. Homebrew packages may be installed lazily by `jitml` through
Plan/Apply prerequisite remediation; shell scripts never install them.
Current validation on 2026-05-23 runs the live cluster toolchain from the
`jitml:local` image with the repository mounted at the same absolute host path;
the root `compose.yaml` pins the `jitml` service to host networking so Kind
kubeconfig loopback endpoints are reachable from the outer container. The Linux
CPU bootstrap completes the 110-step live rollout and publishes all platform
components as ready on edge port `9091`.

2026-05-23 Linux CUDA live validation on a GPU host (NVIDIA GeForce RTX 5090,
CUDA 12.8) closes both Phase `4` Sprint `4.7` and the CUDA portion of Phase
`5` Sprint `5.6` against the single-node `jitml-linux-cuda` shape: the lone
Kind node carries `jitml.runtime/gpu=true`, registers the containerd `nvidia`
handler, exposes the read-only `/run/nvidia/driver` mount, mounts the
repo-owned `/etc/nvidia-container-runtime/config.toml`; `RuntimeClass/nvidia`
applies; the `nvidia-smi-probe` pod reaches `Succeeded` and reports the RTX
5090; and the actual `Deployment/jitml-service` rendered with
`substrate=linux-cuda` runs with `runtimeClassName: nvidia`,
`NVIDIA_VISIBLE_DEVICES=all`, `NVIDIA_DRIVER_CAPABILITIES=compute,utility`,
and required pod anti-affinity, with `nvidia-smi -L` inside the service
container reporting the RTX 5090.

2026-05-23 Apple Silicon live validation completes `./bootstrap/apple-silicon.sh
up` on the same single-node topology, publishes all seven components ready on
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
