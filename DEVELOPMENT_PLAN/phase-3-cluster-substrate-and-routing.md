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
[../README.md](../README.md)
**Generated sections**: none

> **Purpose**: Stand up the per-substrate Kind cluster shape, the umbrella Helm
> chart skeleton, the `kubernetes.io/no-provisioner` storage discipline, the
> single `127.0.0.1:<edge-port>` Envoy Gateway listener, the typed route registry
> that drives every `HTTPRoute` resource, and the cluster lifecycle reconciler
> consumed by `jitml bootstrap --<substrate>`.

## Phase Status

✅ **Done** (re-closed 2026-06-28 for Sprint `3.6`). `JitML.Cluster.Kind`,
materialized `kind/cluster-*.yaml`, `JitML.Cluster.Storage`, manual PV
templates, and bootstrap pre-grant resource-cap/mount preparation now implement
the HA topology: one control-plane plus three workers, repo mounts and resource
caps across all materialized Kind nodes, Linux CUDA GPU runtime material on
workers, HA manual PV counts, and one public localhost Envoy socket. Validation:
`cabal build exe:jitml --ghc-options=-fasm`; `jitml internal
materialize-substrate` for `apple-silicon`, `linux-cpu`, and `linux-cuda`;
`cabal test jitml-integration --ghc-options=-fasm --test-options='-p HA'`.
Live HA lane revalidation is owned by Phases `15` and `16`. Prior closure
history follows.

✅ **Done** (re-closed 2026-05-29; Sprint `3.2`'s right-sized PV layout
(MinIO `4→1`, Pulsar `3→1`, Postgres `3→1`) landed in `JitML.Cluster.Storage` and
validated against the container build + unit + integration renderer assertions;
live hostPath-backed rollout exercise owned by Phase 15 Sprint 15.1). The phase owns
[Exit Definition](README.md#exit-definition) items 3 (`jitml bootstrap
--<substrate>` deploys the umbrella Helm chart against the per-substrate
Kind cluster shape with no kubeconfig pollution, Harbor up before later
image rollouts, exactly one `127.0.0.1:<edge-port>` Envoy Gateway socket)
and 17 (`src/JitML/Routes.hs` is the source of truth for every HTTPRoute
resource). Item 17 is met: the Routes registry is the sole
HTTPRoute source, every chart-rendered HTTPRoute is generated from it,
hand edits fail `jitml lint chart` (Sprints `3.1`–`3.4`). Sprint `3.1` now
uses the single-node Kind shape for every substrate: one `control-plane` node,
no separate `worker`, repo `./.build/` and `./.data/` mounted into that single
node, and the Linux CUDA GPU label/runtime material on that node. The typed
`JitML.Cluster.Helm` module now exposes `kindCreateSubprocess` (the
typed Kind create/export command that uses an in-container temporary
kubeconfig and copies the finished file to `./.build/jitml.kubeconfig`),
`helmInstallSubprocess` (a per-release upgrade-install with `--wait`
and kubeconfig pinning), and `helmPhasedRolloutPlan` (the Helm-release
sequence backed by `phasedReleases`, with the non-Helm Docker build /
explicit Kind image-load phase inserted directly by
`JitML.Bootstrap.livePhasedRolloutSubprocesses`). Item 3's Phase `3`
substrate/routing slice is met: 2026-05-23 live Linux CPU bootstrap executed
the typed Kind create/export, Helm, Docker build / explicit Kind image-load,
repo-owned manifest apply, and Pulsar-topic subprocesses against the
single-node Kind topology through `./.build/jitml.kubeconfig`, wrote measured
ready component health to `cluster-publication.json`, served `/api` through
the single Envoy localhost socket, and tore the Kind cluster down through
`jitml cluster down` without touching `~/.kube/config`.

### Reopened (2026-05-29)

The phase reopened so **Sprint `3.2`** (manual PVs / storage) can carry the
right-sized manual-PV layout that follows the reduced platform replica counts
(MinIO `4→1–2`, Pulsar `3→1`) introduced by Phase `4` Sprint `4.8` as part of the
2026-05-29 cluster resource-guardrail work. Sprints `3.1`, `3.3`, `3.4`, and `3.5`
stay closed; the live exercise of the new PV layout is owned by Phase `15`.

### Current Implementation Scope

The worktree implements typed renderers for Kind config, manual PVs,
storage class, Gateway/GatewayClass/EnvoyProxy, HTTPRoutes, cluster
publication, and bootstrap file materialization. `jitml cluster up`
materializes those files without live cluster mutation. `jitml bootstrap
--<substrate>` materializes the files and then calls
`JitML.Bootstrap.liveExecutePhasedRollout` directly; there is no process
environment gate for local Kind/Helm work. The live rollout runs the typed
`kind`, Helm, Docker build / explicit Kind image-load, and Pulsar-topic
subprocesses, rewrites the live Kind/Gateway inputs from the selected edge-port
lease, patches the Apple host Dhall from the resulting publication, and writes
`./.build/runtime/cluster-publication.json` with that leased port plus component
status measured from live Helm release status. It applies the repo-owned
foundation and edge manifests through explicit `kubectl apply -f` subprocesses.
`jitml cluster down` deletes the Kind cluster named by the publication file and
marks the preserved publication components `stopped`; a second down run exits
through the reconciler no-op path. Live step failures surface as `AppError
SubprocessFailed`, and the live rollout stops at the first failed subprocess so
later Helm phases cannot mask an earlier image-build or image-load failure.

## Phase Summary

This phase delivers the per-substrate Kind cluster configurations, the umbrella
Helm chart skeleton (subchart dependencies pinned but not yet exercised — Phase
`4` adds bodies), the manual-PV storage layout, the Envoy Gateway listener, the
`src/JitML/Routes.hs` route registry as the single source of truth for every
`HTTPRoute`, and the cluster lifecycle reconciler that `jitml bootstrap
--<substrate>` uses to run the phased deploy (Harbor bootstrap → local image
build/load → final rollout) and write
`./.build/runtime/cluster-publication.json`.

## Sprint 3.1: Per-Substrate Kind Configs and `extraMounts` ✅

**Status**: Done
**Implementation**: `kind/cluster-apple-silicon.yaml`, `kind/cluster-linux-cpu.yaml`,
`kind/cluster-linux-cuda.yaml`, `src/JitML/Cluster/Kind.hs`
**Docs to update**: `documents/engineering/cluster_topology.md`

### Objective

Lay down the per-substrate Kind configs (single-node control-plane topology),
the `kindest/node` pin (mirrored into a `cabal.project` comment), the
`extraMounts` binding host `./.build/` and `./.data/` into the Kind node, and
the Linux CUDA node label `jitml.runtime/gpu=true`.

### Deliverables

- Each Kind config carries `name: jitml-<substrate>`, one control-plane node,
  no worker node, the pinned `kindest/node` image, and `extraMounts:
  - hostPath: ./.build, containerPath: /jitml/.build`.
- Linux CUDA's single Kind node carries `kubeadmConfigPatches` adding the
  `node-labels: jitml.runtime/gpu=true` line so the NVIDIA `RuntimeClass`
  binds.
- The edge port mapping (`extraPortMappings`) maps host
  `127.0.0.1:<edge-port>` → the single Kind node's `30090` NodePort.
- `src/JitML/Cluster/Kind.hs` renders the Kind config from the typed
  `KindConfig` ADT (substrate, kindest pin, edge-port lease, GPU label flag);
  the checked-in `kind/cluster-*.yaml` files are local materialized fixtures,
  not generated by the active docs/path registry.
- `kindest/node` mirror-pin comment in `cabal.project` is enforced by
  `jitml lint chart`.

### Validation

1. `src/JitML/Cluster/Kind.hs` renders deterministic Kind configs for all
   three substrates.
2. The checked-in Linux CUDA Kind config contains
   `jitml.runtime/gpu=true`.
3. Live `kind create cluster` / kubeconfig export execution is validated by
   Sprint `3.5`; this sprint owns the typed renderer.

## Sprint 3.2: `kubernetes.io/no-provisioner` Storage and Manual PVs ✅

**Status**: Done (re-closed 2026-05-29 after the right-sized PV layout landed; live hostPath-backed rollout owned by Phase 15 Sprint 15.1)
**Implementation**: `chart/templates/storageclass-jitml-manual.yaml`,
`chart/templates/pv-platform-minio-*.yaml`,
`chart/templates/pv-platform-pulsar-bookkeeper-*.yaml`,
`chart/templates/pv-platform-pulsar-zookeeper-*.yaml`,
`chart/templates/pv-platform-harbor-pg-*.yaml`,
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
  `claimRef.name`. Registered Percona PG PVs are the exception: their generated
  PVC names carry an operator suffix, so the typed `PerconaPGCluster` pins
  those PVs from the PVC side with explicit `volumeName` fields. Each host
  directory is `./.data/<namespace>/<StatefulSet>/pv_<replica-int>/`, mounted
  into the Kind node at `/jitml/.data/...`.
- DNS-1123-compatible PV resource names:
  `<namespace>-<statefulset>-pv-<int>`.
- `src/JitML/Cluster/Storage.hs` is the typed source for the PV layout; the
  templates are present in the chart and checked by chart lint.
- `jitml lint chart` (the Sprint `1.4` scaffold plus this sprint's real chart
  checks) enforces every invariant: the only
  StorageClass is `jitml-manual`, every PV has explicit `claimRef` or a
  registered Percona `volumeName` binding, every PVC is created only by a
  StatefulSet's `volumeClaimTemplates` or by the registered Percona operator
  resource, every hostPath matches the regex.

### Validation

1. `jitml lint chart` exits `0` on the current chart.
2. Hand-introducing a non-conformant StorageClass, PV claimRef, or hostPath
   surfaces `AppError ChartLintFailed`.
3. Live hostPath-backed cluster rollout is validated by Sprint `3.5`.
4. After the right-sized layout lands, `src/JitML/Cluster/Storage.hs` emits the
   reduced PV set (MinIO `1–2`, Pulsar BookKeeper / ZooKeeper `1`) matching the
   Phase `4` Sprint `4.8` replica counts, and `jitml lint chart` still exits `0`.

### Remaining Work

- The manual-PV set was reduced to the right-sized replica counts in
  `JitML.Cluster.Storage` (MinIO `4→1`, Pulsar BookKeeper / ZooKeeper `3→1`,
  Postgres `3→1`), and the orphan `chart/templates/pv-*.yaml` files left from
  the larger replica set were deleted from the worktree. A new
  `JitML.Bootstrap.sweepStalePvManifests` runs during materialization, deleting
  any `pv-*.yaml` that is not in the current `manualPVs` list so future
  replica re-tunes never leave stale PV manifests behind (caught live when
  `jitml check-code` inside the Dockerfile rejected the orphan PVs as missing
  `claimRef`).
- The live hostPath-backed rollout with the reduced PV set is owned by Phase
  `15` Sprint `15.1`'s Remaining Work.

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
  controller name and references `EnvoyProxy/jitml-edge` through
  `parametersRef`.
- `Gateway/jitml-edge` listens on port `<edge-port>` (templated; the actual port
  is selected by `jitml bootstrap --<substrate>` starting at `9090` and incremented until
  available).
- `EnvoyProxy/jitml-edge` is a NodePort service with `externalTrafficPolicy:
  Cluster`; the Gateway listener port is pinned to NodePort `30090` for the
  Kind host-port mapping.
- The `gateway-helm` subchart in `chart/Chart.yaml` provides the Envoy Gateway
  controller.
- `src/JitML/Cluster/Gateway.hs` is the typed source for the Gateway shape;
  templates are present in the chart and checked locally.

### Validation

1. `chart/templates/gatewayclass-jitml.yaml`,
   `chart/templates/gateway-jitml-edge.yaml`, and
   `chart/templates/envoyproxy-jitml-edge.yaml` exist in the chart.
2. `src/JitML/Cluster/Gateway.hs` renders the Gateway shape.
3. Live `kubectl get gateway` and `curl` validation against a real
   cluster is validated by Sprint `3.5`.

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
  - `/tensorboard` → `tensorboard:80` (rewrite to `/`)
  - `/grafana` → `kube-prometheus-stack-grafana:80` (rewrite to `/`)
  - `/prometheus` → `kube-prometheus-stack-prometheus:9090` (rewrite to `/`)
  - `/harbor` → `harbor:80` (rewrite to `/`)
  - `/harbor/api` → `harbor:80` (rewrite to `/api`)
  - `/v2` → `harbor:80`
  - `/service` → `harbor:80`
  - `/minio/console` → `minio:9001` (rewrite to `/`)
  - `/minio/s3` → `minio:9000` (rewrite to `/`)
  - `/pulsar/admin` → `pulsar-proxy:80` (rewrite to `/admin`)
  - `/pulsar/ws` → `pulsar-broker:8080` (WebSocket; rewrite to `/ws`)
- `chart/templates/httproute-*.yaml` is rendered from the registry, tracked by
  `trackingGeneratedPaths`, and checked by `jitml lint chart`.
- `documents/engineering/cluster_topology.md` carries the route table inside a
  `<!-- jitml:cluster.routes:start -->` / `<!-- jitml:cluster.routes:end -->`
  block, regenerated from the registry.
- `src/JitML/Lint/Chart.hs` enforces route/manifest shape against
  `src/JitML/Routes.hs` so generated HTTPRoute YAML stays aligned.

### Validation

1. `jitml lint chart` compares `chart/templates/httproute-*.yaml` against
   `src/JitML/Routes.hs`.
2. `test/integration/Main.hs` verifies route registry rendering covers
   the registered routes.
3. Live route reachability through the Envoy listener is validated by Sprint
   `3.5`.

## Sprint 3.5: Cluster Lifecycle Reconciler and Phased Deploy ✅

**Status**: Done
**Implementation**: `src/JitML/Cluster/Publication.hs`,
`src/JitML/Cluster/Helm.hs`,
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
  3. Render the typed Helm dependency-build subprocess before any live
     apply gate; live execution skips the build when every expected packaged
     dependency archive already exists under `chart/charts/`.
  4. Ensure the `jitml-<substrate>` Kind cluster exists, write/export Kind's
     kubeconfig to an in-container temporary file, then copy it to
     `./.build/jitml.kubeconfig` (the CLI never touches `~/.kube/config`).
  5. Write the `jitml-manual` StorageClass and the manual PVs.
  6. Run the typed phased rollout, including Helm releases and the non-Helm
     Docker build / explicit Kind image-load phase (Sprint `3.5`).
  7. Lease the edge port starting at `9090` and write
     `./.build/runtime/cluster-publication.json`.
- Phased deploy:
  0. **Dependency phase**: render the typed dependency-build step before any
     live apply. The live step is idempotent: if the `.tgz` archives expected by
     the phased rollout are already present, it exits without requiring global
     Helm repository definitions; otherwise it runs `helm dependency build
     chart`.
  1. **Harbor phase**: bring up MinIO for the `harbor-registry` bucket,
     then the Percona operator plus registered `harbor-pg` database, then
     Harbor against those live dependencies.
  2. **Image build/load phase**: build the `jitml:local` container once,
     `docker tag jitml:local jitml-demo:local` (the `jitml-demo` tag runs the
     same `jitml` binary in the Webapp role), then load both
     tags explicitly into the selected Kind cluster with `kind load
     docker-image`.
  3. **Final phase**: Pulsar, Envoy Gateway, kube-prometheus-stack,
     TensorBoard, the `jitml-service` workload, and the `jitml-demo` workload
     roll out after the local image tags are present in Kind. Live Harbor
     registry push/pull remains Phase `4` / Phase `5` platform-service and
     capability work, not a hidden dependency of the local Phase `3` cluster
     bootstrap.
- `jitml bootstrap --apple-silicon` renders both host Dhall and cluster ConfigMap
  Dhall; after the edge port is known it patches the host Dhall so the host
  daemon can reach Pulsar and MinIO.
- `jitml bootstrap --linux-cpu|--linux-cuda` renders only the cluster ConfigMap
  Dhall; Linux JIT operations happen entirely in the cluster.
- `jitml cluster down`, `jitml cluster status` round out the lifecycle surface.
- Subsequent `jitml cluster up` invocations on a steady-state cluster exit
  `3` (`AppError ReconcilerNoop`).

### Validation

1. `jitml bootstrap --<substrate> --dry-run` emits the typed plan without side
   effects.
2. `jitml bootstrap --<substrate>` materializes local Kind/chart/Dhall and
   publication files.
3. `jitml cluster status` parses
   `./.build/runtime/cluster-publication.json` when present or reports the
   default publication summary.
4. Local materialization no-op exit `3` is covered by `jitml-unit`.
5. `jitml-unit` covers `JitML.Cluster.Helm.renderHelmDependencyBuildPlan
   "chart" == "helm dependency build chart"` and the `cluster up` plan
   contains `build-helm-dependencies`.
6. `jitml-integration` covers the typed Docker build/load plan, idempotent
   Helm dependency-build wrapper, repo-local kubeconfig export, explicit
   manifest apply steps, the absence of the retired `jitml-mirror` Helm
   placeholder, idempotent Pulsar topic creation, and idempotent Kind delete
   subprocess.
7. Live validation on 2026-05-23: `docker compose run --rm jitml jitml
   bootstrap --linux-cpu` reconciled the single-node Kind cluster through
   `./.build/jitml.kubeconfig`, ran the 110-step phased rollout, built and
   loaded `jitml:local` and `jitml-demo:local` into Kind, published the
   substrate-scoped Pulsar topics, wrote ready component health to
   `./.build/runtime/cluster-publication.json`, and served
   `http://127.0.0.1:9091/api` through Envoy. The live Docker build also
   validated the Dockerfile fallback that derives `TARGETARCH` from the Debian
   architecture when the legacy Docker builder does not inject it.
8. Live teardown validation on 2026-05-23: `docker compose run --rm jitml jitml
   cluster down` deleted `jitml-linux-cpu`, `kind get clusters` reported no
   Kind clusters, and a second `jitml cluster down` exited through the
   reconciler no-op path with code `3` while preserving the publication with
   all components marked `stopped`.

## Doctrine Sections Cited

- [../README.md → Plan / Apply commands](../README.md#doctrine-scope) (Sprint 3.5)
- [../README.md → Reconcilers and No-Op Exit](../README.md#doctrine-scope) (Sprint 3.5)
- [../README.md → Subprocesses as Typed Values](../README.md#doctrine-scope) (every sprint)
- [../README.md → Generated Artifacts](../README.md#generated-documentation-flow) (Sprints 3.1, 3.2, 3.3, 3.4)
- [../README.md → Lint matrix](../README.md#lint-matrix) (Sprints 3.2, 3.4)

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/cluster_topology.md` — populate with the per-substrate
  Kind shapes, storage discipline, Envoy Gateway listener, route registry
  contract, and the phased deploy narrative. Add the
  `<!-- jitml:cluster.routes:start -->` block consumed by Sprint `3.4`. Update the
  storage-layout PV table for the Sprint `3.2` right-sized replica counts (MinIO
  `4→1–2`, Pulsar `3→1`).
- `documents/engineering/daemon_architecture.md` — link to the publication file
  contract that bootstrap writes on Apple Silicon
  (`./.build/runtime/cluster-publication.json`).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- `system-components.md → Cluster Substrate Components` rows remain aligned
  with the implemented Kind, chart, route, and publication surfaces.

## Sprint 3.6: HA Kind Node and Manual-PV Topology [✅ Done]

**Status**: Done (opened 2026-06-27; closed 2026-06-28)
**Implementation**: `kind/cluster-*.yaml`, `src/JitML/Cluster/Kind.hs`,
`src/JitML/Cluster/Storage.hs`, `chart/templates/pv-*.yaml`,
`src/JitML/Lint/Chart.hs`
**Docs to update**: `documents/engineering/cluster_topology.md`,
`system-components.md`, `legacy-tracking-for-deletion.md`

### Objective

Make the documented HA cluster shape the implemented Kind/materialization
surface: control-plane plus worker nodes from the HA profile, HA-sized manual
PVs, single localhost Envoy edge socket, and no hidden single-node/right-sized
assumptions.

### Deliverables

- Render a target HA Kind topology for every substrate, including worker nodes
  that can host platform services and Engine compute while preserving the
  `127.0.0.1:<edge-port>` Envoy listener.
- Apply `kindest/node` pins, `extraMounts`, GPU labels/runtime material, and
  resource caps to the correct node set rather than only the compact
  control-plane node.
- Expand manual PV rendering and chart templates for the HA storage topology:
  distributed MinIO, Pulsar ZooKeeper/BookKeeper/Broker/Proxy where persistent,
  Percona Postgres replicas, and pgBackRest.
- Keep the one-numerical-worker-per-node compute invariant coordinated with
  Phase `5` Sprint `5.16`; Phase `3` owns the node topology that makes that
  scheduling rule enforceable.

### Validation

- `cabal build exe:jitml --ghc-options=-fasm`
- `cabal test jitml-integration --ghc-options=-fasm --test-options='-p HA'`
  covers the HA Kind renderer and HA PV/service shape.
- `cabal run exe:jitml --ghc-options=-fasm -- internal materialize-substrate
  --substrate <apple-silicon|linux-cpu|linux-cuda>` regenerated the checked-in
  substrate fixtures from the HA renderer.
- Shared final gates: `jitml docs check`, `jitml lint chart`, and
  `docker compose run --rm jitml jitml check-code`.

### Remaining Work

- None. Live HA substrate revalidation is tracked by Phase `15` Sprint `15.22`
  and Phase `16` Sprint `16.14`.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [development_plan_standards.md](development_plan_standards.md)
- [../README.md](../README.md)
