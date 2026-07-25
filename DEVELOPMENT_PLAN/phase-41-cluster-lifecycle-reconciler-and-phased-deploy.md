# Phase 41: Cluster Lifecycle Reconciler and Phased Deploy

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Cluster Lifecycle Reconciler and Phased Deploy. Single-session phase migrated from legacy Sprint 3.5 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 41.1: Cluster Lifecycle Reconciler and Phased Deploy [✅ Done]

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
3. Historical Sprint `3.5` target: `jitml cluster status` parsed
   `./.build/runtime/cluster-publication.json` when present or reported the
   default publication summary. Sprint `3.7` supersedes the default-ready
   fallback: missing, corrupt, or locally materialized publication state must
   report not-ready or fail through a typed path.
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

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
