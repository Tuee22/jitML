# Cluster Topology

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: README.md, ../documentation_standards.md, [legacy-to-new phase map](../../DEVELOPMENT_PLAN/README.md#legacy-to-new-phase-map), [Phase 37](../../DEVELOPMENT_PLAN/phase-37-per-substrate-kind-configs-and-extramounts.md), [Phase 41](../../DEVELOPMENT_PLAN/phase-41-cluster-lifecycle-reconciler-and-phased-deploy.md), [Phase 42](../../DEVELOPMENT_PLAN/phase-42-ha-kind-node-and-manual-pv-topology.md), [Phase 53](../../DEVELOPMENT_PLAN/phase-53-ha-platform-service-topology.md), [Phase 69](../../DEVELOPMENT_PLAN/phase-69-one-numerical-worker-per-kubernetes-node.md), code_quality.md, daemon_architecture.md, durable_state_dsl.md, run_contract.md
**Generated sections**: cluster.routes

> **Purpose**: Project-specific cluster topology for jitML — Kind cluster
> shapes per substrate, the umbrella Helm chart, the storage discipline, the
> Envoy Gateway listener, the typed route registry, the `jitml bootstrap
> --<substrate>` rollout contract, and the no-kubeconfig-pollution invariant.

## Current Status

**Refactor boundary.** The campaign/resource contracts below are targets. Current
implementation does not acquire their safety or qualification authority from
this documentation change; execution order and pending work live in the
[validation foundation refactor](../../DEVELOPMENT_PLAN/README.md#validation-foundation-refactor).


The checked-in topology renders one control-plane plus one worker, with manual
PV cardinality and replica counts derived from the selected typed profile.
Durable node-local PV startup projection and retained consumer-origin checks are
implemented in `JitML.Cluster.StatefulPV`; their live preservation and whole-host
resource proof remain separate obligations of the reopened lifecycle owners.
The [plan](../../DEVELOPMENT_PLAN/README.md#validation-foundation-refactor) owns
current statuses and dated validation evidence.

The target is one control-plane, one worker, one instance of each local
platform role, and one Linux Engine replica. The renderer continues to accept
positive operator-selected worker counts and to enforce at most one numerical
worker of each compute scope per node. Pulsar's at-least-once semantics remain
in force for those deployments, but jitML does not require explicit
multi-worker, platform-HA, or node-failover acceptance evidence.

**Durable-state source of truth (Sprint 4.9):** the MinIO bucket set and the logical
Pulsar topic family are now projected from the durable-state registry
(`JitML.Project.Config.defaultProjectConfig`) — `JitML.Storage.Buckets.bucketNames` is
the `ObjectBucket` projection, and the topic logical names are anti-drift-checked
against `JitML.Coordinator.Topology`. See [durable_state_dsl.md](durable_state_dsl.md).

**Local topology source of truth:** this document defines one control-plane node
plus one worker per substrate, one localhost Envoy edge socket,
single-instance stateful services, and scoped placement that permits at most one
numerical ML compute worker of each scope per Kubernetes node. Current
implementation and lane-validation status live only in the development plan.

**Reconciliation contract:** cluster health and edge coordinates
come only from a successful live Kind/Helm reconcile. A locally materialized
publication, a missing publication, or a corrupt publication is not a ready
cluster: `jitml cluster status` fails closed unless
`./.build/runtime/cluster-publication.json` decodes and carries
`evidence: live-readiness` plus exactly one ready row for every required
component. `jitml cluster up --substrate <s>` performs the live Kind
create/export, dependency build, Docker image build/load, Helm/local apply,
substrate-required role-rollout readiness, public Coordinator `/readyz`,
Pulsar-topic, and measured-publication write promised by the CLI and plan
surfaces. Linux requires clustered Engine and Coordinator rows; Apple requires
only the clustered Coordinator and edge, never inferring its separately launched
host Engine from the zero-replica cluster Deployment.

## Whole-Host Resource Boundary

**Target; resource admission is not established by the topology renderer.**
[Execution resources](execution_resources.md) owns combined host/VM/container/
native/observer accounting, measurement semantics and stop policy. Reopened
Phases 29, 43, 51 and 64 own the effective implementation and live proof.

A single typed selected profile generates node, pod, caller and lifecycle-helper
limits and the expectations checked against actual runtime objects before start.
Declared requests, a Compose dry run or a node cap alone do not prove the combined
stack fits. Image builders/imports and native host commands receive their own
accounting. Helpers reserve space inside the client's existing slot; overlapping
helpers cannot each claim the whole slot. Compiler scratch and archives use
bounded disk-backed homes with separate disk-reserve checks.

The named VM is started and stopped as explicit operator steps. No implicit
bootstrap/test/build VM start, boot/login activation or default-VM fallback is
permitted. CPU quotas remain enforced; host idle percentage is diagnostic and
cannot independently refuse, pause or stop a workload. Unknown measurement is
not a healthy reserve. Actual host/native and VM/guest limits are separate facts.
Original-data readback and retained-node identity proofs accompany lifecycle
seals; later healthy observations cannot replace missing original closing roles.


## Substrates and Cluster Shapes

| Substrate | Kind shape | Node labels | Daemon residency |
|-----------|-------------------|-------------|------------------|
| `apple-silicon` | one control-plane plus one worker from `dhall/cluster/resources.dhall` | the worker carries `jitml.node-role/compute=true`; host Metal compute remains host-resident | one clustered Coordinator (`Cluster + ForwardToHost`) + one host-native Engine (`Host + SelfInference`) |
| `linux-cpu` | one control-plane plus one worker from `dhall/cluster/resources.dhall` | the worker carries `jitml.node-role/compute=true` for numerical compute placement | one clustered Engine plus one Coordinator (`Cluster + SelfInference`) |
| `linux-cuda` | one control-plane plus one worker from `dhall/cluster/resources.dhall` | the CUDA worker carries `jitml.node-role/compute=true` and `jitml.runtime/gpu=true` | one clustered Engine plus one Coordinator (`Cluster + SelfInference`) |

This table owns where computation may reside. A validated workload consumes it
as the closed `ClusterJob | HostRun` placement choice defined by
[Typed Run Contract → Lifecycle State Machine](run_contract.md#lifecycle-state-machine).
Missing/probe-failed placement, terminal success, evidence completion, and
resource cleanup are run-protocol states rather than topology strings.

Per-substrate Kind configs live at `kind/cluster-<substrate>.yaml`. The
`kindest/node` pin is the single source of toolchain truth; it is mirrored as a
comment in `cabal.project`. `jitml lint chart` rejects drift between the two.
`JitML.Cluster.Kind.renderKindConfig` renders the checked-in control-plane plus
worker topology for every substrate while keeping a single host-port mapping on
the control-plane.

The host `./.build/` directory is bind-mounted into Kind via the `extraMounts`
block in the Kind config. This is what lets in-cluster Linux workloads see the
repo-local build/cache tree. The resource profile mounts every materialized Kind
node that may run jitML workloads. It is **not**
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
node at `/jitml/.data`. `.data` owns these registered manual PV bind mounts and the reserved `.jitml-pv-snapshots/<substrate>/` lifecycle snapshot namespace.
Kind metadata, runtime coordinates, kubeconfig, generated Dhall, and JIT
artifacts live under `./.build/`.

Apple Silicon and Docker-backed `linux-cpu` use a node-local bind overlay for
every registered stateful PV. The authoritative backing directories are
`/var/local/jitml-stateful-pv/...` inside each Kind node; the projection binds
them over the corresponding `/jitml/.data/...` paths. Fresh bootstrap restores
the selected generation first, then installs the source-rendered startup bundle
before kubelet resource calibration or any manual PV/Helm apply. Explicit fresh
initialization creates only genuinely absent backing leaves: registered Percona
Postgres roots receive uid/gid `26:26`, and other stateful roots receive
`chmod 0777`. Existing roots, including empty or restored roots, retain their
owner, permissions, ACLs, xattrs and mtime.

[`JitML.Cluster.StatefulPV`](../../src/JitML/Cluster/StatefulPV.hs) owns the
projection script, `jitml-stateful-pv.service` and dependency drop-ins for both
`containerd.service` and `kubelet.service`. Both daemons require the projection
oneshot and start after it; each also verifies the projection before starting.
The bounded startup path requires existing physical backing directories and
exact backing/target device-and-inode equality. Missing backing, symlinks, files
or a wrong existing bind fail closed. Startup does not initialize missing data,
replace a wrong bind, or copy bytes from the host fallback directory.

A correct node path alone is insufficient after a late bind: an existing Pod
volume can retain the old directory inode. Retained bootstrap refreshes its
derived `./.build/jitml.kubeconfig` before the read-only consumer guard, then
verifies the installed bundle and effective daemon dependencies before
convergence or calibration. The guard matches PVC namespace/name to the closed
manual-PV registry, resolves each running consumer's node, Pod UID, container ID
and actual CRI PID, and compares the backing inode with the mount visible through
that PID's root. It checks stable PID start identity and repeats the consumer
inventory. A safe static directory `subPath` selects the physical child under
the backing root; dynamic `subPathExpr`, traversal and symlink children are
refused. Final readiness publication also requires this origin check.

An unproved projection or stale consumer bind requires an explicit cold repair.
Stop the retained Kind nodes, install the exact source-rendered bundle into the
same stopped CIDs, and explicitly restart those whole nodes before verifying
their consumers. `statefulPVBundleFiles` exports the complete bundle; its script
is root-owned mode `0755`, and its unit/drop-ins are root-owned mode `0644`, all
single-link files. Verify that the retained nodes cannot restart automatically
when the Docker daemon returns before installing the bundle; a stopped state
alone does not guarantee this. This maintenance requirement does not change
Kind's generated restart policy. The repair preserves original backing bytes,
Pod node assignments, and PV/PVC, Pod and Job objects; it performs no reseeding,
repeat restoration or deletion of those objects.

The checked-in PV identity and chart paths remain the repo-local `.data`
layout, but the live MinIO, Pulsar, and Postgres write paths use node-local
storage on macOS/Colima to avoid host bind-mount ownership and I/O stalls.
`linux-cuda` retains its existing real Linux/NVIDIA `.data` path and Postgres
ownership normalization. Startup ordering does not add per-PV node ownership:
the manual PV affinity still uses `kubernetes.io/hostname` with `Exists`, so this
repair does not establish safe relocation of node-local state.

The real Linux regressions in
[`test/shared/StatefulPvProjection.hs`](../../test/shared/StatefulPvProjection.hs)
exercise restored metadata, new-leaf defaults, invalid backing/binds, stale
consumer mounts, static directory subpaths and the exact systemd dependencies
with isolated marker services. The component fixture does not substitute for
the retained Kind rollout or original-data readback.

The node-local trees live inside each Kind node's anonymous `/var` volume;
preserving the hidden host `.data` directories alone does not preserve these
writes. `cluster down --substrate <name>` holds an exclusive lifecycle lease,
clears readiness before quiescence, drains actual registered writers, archives
every node's complete closed PV registry and verifies content and restorable
metadata through an isolated Linux scratch restore. Only a durably selected,
verified generation permits Kind deletion. Source CIDs and complete before/after
manifests remain exact; cross-filesystem comparison permits only filesystem
identity and directory-allocation differences. Snapshot archives and selectors
are private, purge-owned files under `.data/.jitml-pv-snapshots/<substrate>/`.

Extraction first preserves payload no-overwrite protection with GNU tar's
`--keep-old-files`. A second `--no-recursion --overwrite-dir` pass selects only
the first unique literal root-directory entry through the same held archive and
destination descriptors. Root PAX metadata is validated before either pass,
including exact decimal nanosecond times. This restores the root's numeric
owner/group, permission and SGID bits, ACLs, xattrs and mtime. Complete archive
hash/identity checks follow both passes, and the unchanged whole-tree comparison
must include the root. A successful tar exit alone does not admit restoration.

Fresh Kind creation restores the selected generation before overlays or Helm
releases. Every destination must be empty, every archive exact, and all restored
node manifests must match before a completed restore marker is written. Failed
or cancelled restoration leaves a durable pending marker; reuse and normal down
refuse those partial roots. Existing admitted roots are not restored again.
Snapshot verification does not publish live readiness: the normal bootstrap
readiness gates remain authoritative.

The permanent `.jitml-pv-lifecycle.lock` and exclusive
`.jitml-pv-lifecycle.claim.lock/` live at the repository root, outside `.data`
and `.build`, and are ignored by both Git and Docker. The shared claim is needed
because the host and guest can each acquire `flock` on the same bridged file.
Lease scope covers the complete bootstrap/down/reset operation. Claim creation
is exclusive and fsynced; release requires the same held owner identity/token.
An interrupted claim is not automatically reclaimed from a PID observation.

Metadata-sensitive snapshot work also requires external permission writers to
be inactive. Colima's optional inotify bridge can forward host writes by applying
the existing permission mode in the guest, which changes ctime; see the
[Colima 0.10.3 implementation](https://raw.githubusercontent.com/abiosoft/colima/v0.10.3/daemon/process/inotify/events.go).
Use that environment with inotify forwarding disabled during this work. The
snapshot reader retains its complete identity checks and refuses a changed file;
an external same-mode permission update does not justify omitting ctime.

Destructive `cluster reset --yes` invalidates all snapshot selections durably
before deletion, refuses another extant substrate cluster that shares `.data`,
and clears retained readiness. Data is detached into an exclusive ignored
`.data-preserved-purge-<token>-data/` quarantine before descriptor-relative cleanup.
A cleanup failure retains detached bytes and cannot reselect them. `--full`
removes `.build` only after data cleanup; both lifecycle guards survive it.


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
    ├── minio/pv_0                      -- standalone MinIO
    ├── pulsar-bookie-journal/pv_0      -- one bookie journal
    ├── pulsar-bookie-ledgers/pv_0      -- one bookie ledger store
    └── pulsar-zookeeper-data/pv_0      -- one ZooKeeper data store
```

Changing an existing local installation from distributed MinIO to standalone
MinIO requires `./bootstrap/<substrate>.sh purge` before the first target-shape
`up`. A normal `down` preserves `.data`; `purge` removes the local cluster and
its retained state and is intentionally destructive. The legacy replica paths,
values, and assertions remain listed in
[legacy-tracking-for-deletion.md](../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md)
until their owning phases remove them.

`jitml lint files` excludes runtime `.data` trees. The typed lifecycle API
validates the reserved snapshot paths and closed `manualPVsFor` registry with
no-follow traversal; it rejects unregistered payload paths. `jitml lint chart`
rejects any StorageClass with a provisioner other than
`kubernetes.io/no-provisioner`, any freestanding PVC, and any PV without either
an explicit `claimRef` or a registered Percona `volumeName` binding.

## Helm Chart Layout

Single umbrella chart at `chart/`. `Chart.yaml` declares subchart
dependencies:

| Third-party dependency | Purpose | Owning sprint |
|------------------------|---------|---------------|
| `pulsar` | Apache Pulsar (1× ZooKeeper, 1× BookKeeper, 1× Broker, 1× Proxy, single-node ledger quorums; broker-embedded WebSocket routed through `/pulsar/ws`) | Sprint 4.4, revised by Phase 53 |
| `minio` | Standalone-mode object store (1 replica) | Sprint 4.3, revised by Phase 53 |
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
local live footprints for MinIO, Pulsar, and kube-prometheus-stack.

The image registry is not a dependency subchart at all — it is
`chart/templates/deployment-registry.yaml`, one `registry:2` Deployment plus its
Service, configured from the `registry:` block in `chart/values.yaml`. It stores
layers in the MinIO `harbor-registry` S3 bucket with redirects disabled, so a
client is never handed a presigned URL naming an in-cluster host it cannot
resolve. The bucket name is deliberately the one Harbor used: reusing it meant
replacing the registry required no blob migration. The registry runs
unauthenticated, which is why there is no token endpoint and no credential in
any chart value. These inputs keep the
generated dependency archives installable when the live rollout installs a
subchart `.tgz` directly instead of installing the umbrella chart.

## Resource Budgets and the Kind-Node Cap

The local topology is bounded by a typed Dhall resource profile (`dhall/cluster/`,
decoded by `JitML.Cluster.Resources`) rather than running unbounded. The profile
is the source of truth for node caps, per-pod requests/limits, service replica
counts, and worker placement budgets. It also preserves single-host phase
closeability under the project's
[Substrate-affinity phasing](../../README.md#substrate-affinity-phasing)
doctrine: each development phase brings its lane up on one host with at most one
accelerator plus `linux-cpu` (bound by
[`DEVELOPMENT_PLAN/development_plan_standards.md` rule M](../../DEVELOPMENT_PLAN/development_plan_standards.md)).
- **Runtime admission** — the `cluster.host-memory` prerequisite and live
  bootstrap read CPU count and `MemTotal` from the selected running Docker
  runtime. Every Kind node, the client job and VM system reserve must fit
  together. Linux callers also prove their own finite CPU/RAM cgroup limits
  and zero swap allowance. The check does not start a VM. Native host jobs
  require separate CPU, heap and host-pressure supervision.
- **Kind-node caps** — after `kind create`, the bootstrap reconciler applies
  `docker update --memory/--memory-swap/--cpus` caps to materialized Kind nodes
  from the profile. An over-budget cluster then OOM-kills pods inside node
  cgroups. Before Helm installs workloads, the observed Node allocatable
  CPU/RAM must not exceed the profile's per-node application budget. An outer
  VM capacity advertised by a nested kubelet fails this check. System reserves
  and optional control-plane scheduling are explicit; numerical compute labels
  remain worker-only.
  Kind can expose outer-runtime capacity despite Docker caps. Live materialization
  excludes capacity outside each node and adds the declared node-system reserve
  when rendering kubelet reservations. Retained nodes reconcile those resource flags
  atomically and restart kubelet only when the record changes; live checks verify
  both running Docker state and actual Allocatable before workloads proceed.
- **Per-pod budgets and local replicas** — the registry, MinIO, Pulsar,
  observability, TensorBoard, and jitML roles carry CPU/memory requests+limits
  and target replica counts from the same profile. Eight generated resource
  overlays follow authored Helm values. A platform-namespace LimitRange supplies
  defaults for newly admitted containers, including init/helper containers with
  missing resource fields. Effective manifests and Pods still require inspection:
  defaults do not replace explicit upstream values or retrofit existing Pods.
  Before publication or convergence acceptance, all-namespace admitted Pods must
  account for their actual per-node requests, regular and restartable sidecars,
  sequential init work and overhead. Pending/terminating infrastructure and missing
  platform caps prevent acceptance. System containers with missing inner limits are
  reported as relying on the hard node parent; extended resources remain outside
  this CPU/RAM proof and retain their substrate checks.
  Manual PV layout follows the counts.
- **Numerical worker cardinality** — regardless of service replica counts, the
  Engine/numerical ML compute role is capped at one worker per Kubernetes node.
  Coordinator, Webapp, observability, and platform-service replicas may scale
  independently without creating extra numerical workers on the same node.

The explicit Mac-local profile is `dhall/cluster/mac16.dhall`: two 5 GiB /
1.5 CPU nodes, a 4 GiB / 1 CPU client, and 1,536 MiB for VM system overhead.
Each node reserves 1 GiB / 250m for its own system services. Pod memory limits
may collectively exceed their enclosing node cap; the hard parent contains
that use, but readiness and OOM observations decide whether the stack can run
successfully. A passing arithmetic check is not a live rollout pass.

Fresh Kind creation applies and observes the selected node hard caps before
node-local PV restoration. A failed cap or inspection prevents restoration.
Partial Kind creation failures may leave nodes without their individual caps;
the explicitly bounded outer VM remains the containment boundary in that case.
Snapshot helpers run serially with fixed 0.5 CPU, 512 MiB RAM, zero swap, 64 PIDs
and a 64 MiB `/tmp` tmpfs. Their actual Docker limits are verified before start.
These are failure boundaries, not a guarantee that every manifest fits. Lifecycle
admission reserves the helper within the existing 4 GiB / 1 CPU client slot;
it requires the actual caller to fit the remaining allowance. The
`compose.lifecycle-bounded.yaml` override gives the caller 3 GiB / 0.5 CPU with
zero swap. Apply it last for bootstrap, cluster shutdown and snapshot restoration.
Normal training may use the full 4 GiB / 1 CPU client slot only after all helpers
have ended. Application readiness and data readback are separate full-stack
lifecycle checks after filesystem restoration.

Pulsar's pinned 3.6.0 chart is authenticated against Apache's published archive
digest before bootstrap prepares a separate copy under
`.build/conf/cluster/charts/`. Preparation corrects the broker ZooKeeper startup
check's memory variable to `PULSAR_MEM`, so its existing `-Xmx128M` setting reaches
the invoked launcher. Every other inflated chart byte stays unchanged, including
both readiness guards, deadlines and TLS/metadata helpers. The original dependency
cache stays intact; unsupported version or digest drift fails before Helm.
Preparation alone does not establish live readiness.

Select it with `JITML_CLUSTER_RESOURCES`; a missing explicitly selected file
fails instead of falling back. On this Mac the named Colima profile `jitml`
has 4 CPUs, 16 GiB RAM and a 288 GiB disk. Disk capacity accommodates retained
images and both nodes' imported layers; it does not increase the RAM allowance.
Cache the canonical `jitml:local` image
explicitly before lifecycle work: reuse its verified cached copy, or build/load
it while the cluster is stopped. Lifecycle operations fail if it is absent and
do not build an image implicitly. Bootstrap's separate application-image stage
rebuilds by default; verify the cached image matches the intended source and
pass `JITML_BOOTSTRAP_SKIP_IMAGE_BUILD=1` in the bootstrap client's environment
to reuse it. VM startup and shutdown are explicit; the lifecycle override comes
last:

```sh
colima --profile jitml start
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml -f compose.cluster-bounded.yaml -f compose.lifecycle-bounded.yaml run --rm -e JITML_BOOTSTRAP_SKIP_IMAGE_BUILD=1 jitml jitml bootstrap --linux-cpu
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml -f compose.cluster-bounded.yaml -f compose.lifecycle-bounded.yaml run --rm jitml jitml cluster down --substrate linux-cpu
colima --profile jitml stop
```

Use `compose.vm-bounded.yaml` for the 2 CPU / 6 GiB build/test runtime-container
ceiling while the cluster is stopped. A separate image builder remains bounded
by the VM rather than this container override. `compose.cluster-bounded.yaml`
selects the Mac profile and lowers the normal full-stack client to 4 GiB / 1 CPU;
the lifecycle override makes room for its sibling helper within that same slot.
None of these overrides starts a VM. The generic `default` VM and its automatic
startup entries are retired. Its separate Docker data disk remains offline,
with a private OS/settings recovery copy under ignored `.build/`; retain both
until complete image/volume/host-state migration is verified. Current bounded
normal/cold application-data readbacks pass; full workflow qualification remains
a separate obligation.

The compact single-node guardrails introduced by Phase `2` Sprint `2.8`, Phase
`4` Sprint `4.8`, and Phase `3` Sprint `3.2` remain historical evidence. The
later replicated profile is the current implementation being retired by Phases
42, 53, and 69; neither historical shape is closure evidence for the target.

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

The target `jitml bootstrap --<substrate>` runs the phased rollout. The lower
level `jitml cluster up --substrate <s>` contract is the same live cluster
reconcile without the stage-0 substrate script wrapper; a file-only
materialization is insufficient for a command documented as bringing the cluster
up.

0. **Dependency phase**: `JitML.Cluster.Helm` renders
   `helm dependency build chart` before any live apply. `Chart.lock` is adopted
   only if reproducible dependency locking becomes part of the release surface;
   `chart/charts/` is not vendored by default.
1. **Registry phase**: MinIO starts first and the `harbor-registry` bucket is
   checked, then the `registry:2` Deployment rolls out against that bucket. The
   registry cannot serve before the bucket exists, which is the whole reason
   this is a distinct phase. There is no database step: Harbor's Postgres was
   the only service-managed database, so the Percona Operator, its cluster, and
   the schema-ownership grant left with it. `JitML.Cluster.PostgresRegistry`
   keeps the type, an empty registry, and its lint guard, so the grant machinery
   is a no-op over an empty list rather than a deleted step.
2. **Image build/load phase**: the `jitml:local` image is built locally and
   retagged as `jitml-demo:local`, then both tags are loaded explicitly into the
   selected Kind cluster with `kind load docker-image`. The `jitml:local` build
   is also the exclusive Haskell style/code-quality gate: it uses the same
   pinned GHC `9.12.4` to build pinned Fourmolu / HLint binaries and fails the
   image build on Haskell style or warning-clean build drift. The third-party
   chart images (`docker.io/*` — MinIO, Pulsar, the registry, etc.) are **pre-pulled
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

This makes local bootstrap explicit: the registry is installed and routed as the
stateful platform registry, but Phase `3` does not require the host Docker
daemon or Kind node container runtime to resolve an in-cluster registry DNS name
before the cluster itself is stable. The route registry exposes exactly one
public path for it, `/v2`, routed straight at the registry Service — there is no
portal, no project API, and no `/service` token endpoint, because `registry:2`
serves the Docker Registry v2 API and nothing else and runs unauthenticated
here. Live push/pull is validated through `JitML.Service.RegistrySubprocess`,
whose settings name the registry endpoint, base URL, repo-local Docker config
directory, optional Docker host socket, Docker binary, and curl binary
explicitly. Live
Linux CPU validation on 2026-05-19 also pushed a tiny OCI artifact through the
registry HTTP API, confirmed the registry's manifest API reported the same digest,
and confirmed MinIO stored the repository layer, manifest, and tag-link objects
under bucket `harbor-registry`, proving the registry's S3 values use the
external Postgres and S3 backend path. The same live-validation family runs the
cluster toolchain from `jitml:local` with host networking and a repo-local
Docker config, logs Docker into `127.0.0.1:9091`, pushes and pulls
`library/jitml-phase4-docker`, lists the repository through `/v2/_catalog`, and
confirms the pushed tag's artifact API returns HTTP `200`.

For Apple Silicon, the edge publication is also the host daemon's service
discovery contract. `jitml bootstrap --apple-silicon` writes
`./.build/runtime/cluster-publication.json` and patches
`./.build/conf/host/apple-silicon.dhall` with routed Pulsar and MinIO URLs. The
host daemon converts `pulsar://127.0.0.1:<edge>/pulsar` to the routed WebSocket
path and sends S3 requests through `/minio/s3`. It does not use the Kubernetes API
to discover work, and the cluster must not schedule Apple Metal execution into
Linux pods.

The accepted lifecycle contract is that any command documented as bringing the
cluster up executes the live reconcile. `jitml bootstrap --<substrate>` and the
lower-level `jitml cluster up --substrate <s>` materialize local Kind, chart, and
Dhall inputs and then call `JitML.Bootstrap.liveExecutePhasedRollout` directly;
there is no process-environment safety gate for local Kind/Helm work. The live
path runs the typed `kind`, Helm, Docker build / Kind image-load,
repo-owned manifest apply, platform readiness, and Pulsar-topic subprocesses
through the `Subprocess` boundary and stops at the first failed subprocess so a
failed image build or image load cannot be masked by later Helm rollout
failures. The topic subprocesses register the exact 34-topic family derived by
`JitML.Coordinator.Topology`: nine command/event/request/result topics per
substrate plus one workflow-status topic per substrate, together with the
Apple-only `inference.command.apple-silicon` forward topic and the Apple
host-command topics `training.host-command.apple-silicon`,
`tune.host-command.apple-silicon`, and `rl.host-command.apple-silicon`. Topic
convergence probes every fully qualified topic with an exact read-only HTTP
stats request. The Coordinator and bootstrap create each nonpartitioned topic
with a JSON-properties `PUT`, accepting only HTTP `204` or `409`, then require
HTTP `200` with a decoded JSON object from that topic's `/stats` address before
acquiring family evidence. A partitioned-name conflict or a namespace topic list
cannot replace that exact observation. Calls run serially with bounded retries.
The remote curl client keeps the shared `flock`, a **17-second** watchdog plus
**3-second** forced retirement, and a **5-second** HTTP budget; the local client
has a separate **25-second** deadline. This transport serves the repository's
pinned internal Pulsar chart, whose authentication and TLS are disabled. It uses
the chart's explicit HTTP admin endpoint; it does not import arbitrary
`pulsar-admin` client authentication or TLS configuration. Actual current-image
startup and data preservation remain tracked in Phase278's Remaining Work.
The in-cluster Apple daemon forwards each raw inference command onto
`inference.command.apple-silicon`, and the host Engine publishes the
`InferenceResult` to the request's reply-topic directly (the converged values
model). The Apple placement path forwards Metal-backed starts to the
host-command topics rather than rendering Linux worker Jobs; Phase `12` owns the
live no-Job assertion. The live path selects the fresh lease or recovers the
retained cluster's fixed edge coordinate before it materializes the
Kind/Gateway/EnvoyProxy inputs. For a retained cluster it compares a versioned
desired-state stamp with a deterministic workspace fingerprint and repo-app
top-level OCI descriptor identities; these are distinct from both the selected
platform manifest and the runtime config digest. Read-only observations require
the exact Helm release,
publication-readiness, Pulsar-topic, per-node loaded-image, and app-pod image
families: every node's containerd target digest must match the desired host OCI
identity, all expected nodes must resolve one uniform non-empty config ID for
the tag, and every app pod's config image ID must match that uniform live ID. An
exact match returns reconciler exit `3` without rewriting the
publication or applying Helm; drift atomically replaces any stale live claim
with an evidence-free recovery publication before cluster mutation. A mutating
rollout must pass the same complete evidence gate before it can publish live
state or persist the reconcile stamp. A
successful apply writes
`./.build/runtime/cluster-publication.json` with that lease, measured Helm
release status, substrate-required role rollout rows, public-edge readiness, and
`evidence: live-readiness`, and patches the Apple host Dhall from the publication.
Linux records Engine and Coordinator; Apple records Coordinator but no Engine
until the separate host-daemon lifecycle supplies its own evidence outside
cluster publication. The edge request is a bounded typed curl subprocess issued
only after all HTTPRoutes are applied; incomplete, duplicate, unexpected, or
not-ready component evidence returns a typed bootstrap invariant failure and
writes no live publication. Only after that publication is live does the
reconciler write `./.build/runtime/cluster-reconcile-stamp.json`, binding schema
version, substrate, edge port, desired-input fingerprint, and each repo-app
tag's top-level host OCI descriptor for the next no-op decision. The stamp's
legacy `repo_app_image_ids` field name does not change that identity level: it
does not store a selected-platform manifest or image config digest.
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
`chart/local/`. Direct Pulsar values and the umbrella-chart projection both set
`brokerDeleteInactiveTopicsEnabled=false`; broker StatefulSets restart when
that ConfigMap changes, so a retained broker fleet cannot keep a stale
topic-deletion policy.

The final Sprint `3.7` Linux CPU acceptance on 2026-07-15 ran the exact command
`docker compose run -T --rm jitml jitml cluster up --substrate linux-cpu`
twice against the retained cluster. The first invocation took the mutating path,
exited `0` after 157 steps in 2,692 seconds, and retained all 34
coordinator-derived topics as independently probeable JSON objects for more
than 60 seconds. The identical second invocation exited `3` in 58 seconds and
preserved publication, reconcile stamp, edge authority, four node identities,
20 PVCs, nine Helm revisions, five application Pods, three broker identities,
and all eight node/tag image rows. Host and node target identity was the
top-level OCI descriptor
`sha256:87b478abc5aade79b613386a9ad7c4a77a145b7cf3d54391ca4f1fa8d11013b0`;
the uniform node CRI and application runtime config digest was
`sha256:43238c272a7d54ac2c2212d211f209d1b991385c21e8badd4283710580d6f227`.

Historical live Linux CPU validation on 2026-05-23 completed
the compact 110-step phased rollout plus readiness checks, built and loaded
`jitml:local`, retagged it as `jitml-demo:local`, loaded both tags into Kind, served
`http://127.0.0.1:9091/api` through Envoy, published the expected Pulsar topic
family, wrote ready publication health, and validated `jitml cluster down`
teardown plus the second-run no-op exit `3`. The 2026-05-19 live run confirms
`/pulsar/admin` works through the
edge, `/pulsar/ws` resolves to `pulsar-broker:8080`, the broker config carries
`webSocketServiceEnabled=true`, and routed WebSocket publish/consume succeeds
through `JitML.Service.PulsarWebSocketSubprocess`. The 2026-05-20 live run
reconciled the then-current 26 substrate-scoped Pulsar topics and
published/consumed
on `persistent://public/default/training.command.linux-cpu` through the
`jitml:local` WebSocket subprocess path. The 2026-05-19 live run
revalidated the registry's preconditions and
backend wiring with MinIO bucket readiness, registry rollout readiness, and a
Registry v2 artifact write
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
wrong shape. The target enforces scoped **at most one numerical ML compute
worker per Kubernetes node** placement. Required anti-affinity/topology-spread
belongs to compute scopes; Coordinator, Webapp, observability, and platform
services may use their own replica counts without placing additional numerical
workers on a node. The default Linux profile renders one Engine replica, pins it
to a `jitml.node-role/compute=true` worker, and labels it `jitml.compute="true"` plus
`jitml.compute-scope="service"`. Daemon-spawned Linux Training/RL/Tune Jobs use
`jitml.compute="true"` plus `jitml.compute-scope="workload"`. Each scope matches
only itself for required hostname anti-affinity and hard topology spread, so Jobs
cannot bypass their one-per-node invariant and also cannot be blocked by an
operator-selected expanded service profile. Apple Silicon keeps the clustered service as a single
non-compute forwarder (`jitml.compute="false"`); Metal work remains on the host
daemon.

Positive worker counts remain a supported deployment input. Engine consumers
use Pulsar `Failover` subscriptions, so an expanded replica set is active/standby
rather than shared-throughput load balancing. Pulsar still provides
at-least-once redelivery, application deduplication, and total settlement. That
semantic support is not a claim that the single-instance local platform is
highly available, and multi-worker or node-failover behavior is not an explicit
jitML acceptance lane.

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
`jitml bootstrap --<substrate>` from the finite candidate set `9090`, `9091`,
and `9092`. With no matching persisted publication, fresh `apple-silicon`,
`linux-cpu`, and `linux-cuda` clusters prefer `9090`, `9091`, and `9092`,
respectively, then probe the remaining candidates. A valid same-substrate
publication is tried first for a fresh cluster, while a retained cluster must
recover that publication's exact coordinate without probing. Bootstrap does not
scan beyond `9092`; an exhausted candidate set fails closed during the Kind
host-port bind. The selected coordinate is recorded as the `edge_port` field of
`./.build/runtime/cluster-publication.json` alongside `pulsar_url`,
`minio_url`, and component health. `jitml cluster status` reads this file, and
the Apple host `BootConfig` turns those publication fields into
`pulsarServiceUrl`, `pulsarAdminUrl`, `minioEndpoint`, and `imageRegistry`
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
  schedule the edge proxy after the registry, MinIO, Pulsar, observability, and the
  demo/service workloads are ready; Phase `53` owns target resource-profile
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
| `/v2` | `registry` | 5000 | `-` | no |
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
The root `compose.yaml` runs the live cluster toolchain from the `jitml:local`
image with the repository mounted at the same absolute host path and pins the
headless `jitml` service to host networking so
Kind kubeconfig loopback endpoints are reachable from the outer container. The
GPU-enabled `jitml-cuda` companion service uses the same image and mount shape,
adding only `gpus: all` for direct live CUDA tests that need device exposure in
the outer container. The target renderer preserves the CUDA RuntimeClass contract on the one GPU
worker node: its labels include `jitml.runtime/gpu=true`,
`RuntimeClass/nvidia` applies, and `Deployment/jitml-service` plus daemon-spawned
CUDA worker Jobs render `runtimeClassName: nvidia`,
`NVIDIA_VISIBLE_DEVICES=all`, and
`NVIDIA_DRIVER_CAPABILITIES=compute,utility`. The prior live replicated CUDA
evidence owned by Phase `15` Sprint `15.22` is historical and is not target
topology closure evidence.

2026-05-23 Apple Silicon live validation completed `./bootstrap/apple-silicon.sh
up` on the same compact topology, published all seven components ready on
edge port `9090`, patches `./.build/conf/host/apple-silicon.dhall` with routed
edge coordinates, and runs the host-native
`jitml service --consume-once 0` acquisition check. The host daemon derives
`/pulsar/ws`, `/minio/s3`, the registry, and repo-local kubeconfig settings from that
Dhall and acquires `inference.command.apple-silicon` as `jitml-host`.

## Validation

Topology closure requires the rendered and live local profile to prove all of
the following:

- exactly one control-plane and one worker, with the worker carrying the
  substrate-required compute/GPU labels, node caps, and `.build`/manual-PV
  mounts;
- exactly one MinIO, ZooKeeper, BookKeeper, Broker, Proxy, Postgres, pgBouncer,
  registry, observability component, TensorBoard, Webapp,
  Coordinator, and default Linux Engine as applicable to the substrate;
- standalone MinIO and single-node Pulsar ledger quorum values, with every
  manual PV/PVC binding converged and no stale higher-index PV manifest;
- one Engine per compute node at most, Apple cluster Engine count zero and host
  Engine count one; and
- routed MinIO/Pulsar operations, at-least-once redelivery/dedup/settlement,
  retained-cluster no-op reconciliation, teardown, and publication readiness.

The focused and standing container gates are:

```bash
docker compose build jitml
docker compose run --rm jitml jitml test jitml-integration --linux-cpu \
  --test-options='-p local-topology'
docker compose run --rm jitml jitml test jitml-daemon-lifecycle --linux-cpu
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml lint chart
docker compose run --rm jitml jitml check-code
```

The first live validation after applying the replica-shape change starts from a
clean local state:

```bash
./bootstrap/linux-cpu.sh purge
JITML_BOOTSTRAP_SKIP_IMAGE_BUILD=1 ./bootstrap/linux-cpu.sh up
```

`purge` is deliberately destructive; it is required here because `down`
preserves the distributed MinIO `.data` layout. No closure criterion requires
more than one worker or validates platform/node failover.

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
- [run_contract.md](run_contract.md)
- [../../DEVELOPMENT_PLAN/phase-3-cluster-substrate-and-routing.md](../../DEVELOPMENT_PLAN/README.md#legacy-to-new-phase-map)
- [../../DEVELOPMENT_PLAN/phase-4-stateful-platform-services.md](../../DEVELOPMENT_PLAN/README.md#legacy-to-new-phase-map)
