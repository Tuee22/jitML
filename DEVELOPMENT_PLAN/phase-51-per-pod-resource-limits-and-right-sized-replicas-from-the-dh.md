# Phase 51: Per-Pod Resource Limits and Right-Sized Replicas from the `dhall/cluster/` Profile

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Per-Pod Resource Limits and Right-Sized Replicas from the dhall/cluster/ Profile. Single-session phase migrated from legacy Sprint 4.8 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

**Current topology note (2026-08-09):** typed CPU/memory budgets, readiness
loops, and profile decoding remain Done. Phase `42` owns the one-worker default,
Phase `53` owns the single-instance platform counts, and Phase `69` owns the
one-Engine Linux default. The counts this phase previously validated are
historical and do not reopen its retained resource-budget surface.

## Sprint 51.1: Per-Pod Resource Limits and Right-Sized Replicas from the `dhall/cluster/` Profile [✅ Done]

**Status**: Done (code-surface closed 2026-05-29; live re-validation owned by Phase 15 Sprint 15.1)
**Implementation**: `chart/values/{harbor,minio,pulsar,kube-prometheus-stack}.yaml`, `chart/local/{jitml-service,jitml-demo,tensorboard}/templates/deployment.yaml`, `src/JitML/Cluster/{Helm,PostgresRegistry,Readiness,PulsarBootstrap}.hs`, `src/JitML/Cluster/Resources.hs`
**Docs to update**: `documents/engineering/cluster_topology.md`, `system-components.md`, `legacy-tracking-for-deletion.md`

### Objective

Right-size the platform stack so it converges under the Phase `2` Sprint `2.8`
kind-node cap and no single pod can starve the others: per-pod CPU/memory
requests+limits and reduced replica counts driven by the typed `dhall/cluster/`
profile, plus the MinIO/Pulsar readiness retries moving from embedded `sh -c`
loops to typed Haskell with `RetryPolicy`. Implements doctrine `Application
Environment`, `Subprocesses as Typed Values`, and `Retry Policy as First-Class
Values`.

### Deliverables

- Harbor, MinIO, Pulsar, service Postgres, Prometheus, and Grafana carry
  `resources` requests+limits and reduced replica counts (MinIO `4→1–2`, Pulsar
  zk/bookkeeper/broker/proxy `3→1`, Postgres `3→1`) sourced from the
  `ClusterResources` profile (Sprint `2.8`), applied through the typed `helm`
  `--set` seam and generated `chart/values/*.yaml`; `chart/local/*` deployments
  gain `resources:` blocks; `JitML.Cluster.PostgresRegistry.renderPerconaPGCluster`
  emits the reduced replicas + a `resources` block.
- `JitML.Cluster.Readiness` (MinIO bucket readiness) and
  `JitML.Cluster.PulsarBootstrap` (topic create) replace their `sh -c` retry loops
  with bounded typed Haskell over leaf `subprocess` outcomes. The loops retain
  explicit attempt/delay constants; they do not use or claim the daemon
  `RetryPolicy` reader.

### Validation

- `jitml lint chart` exits `0`; rendered manifests carry the budgeted `resources`
  and replica counts.
- `jitml bootstrap --<substrate> --dry-run` renders the typed readiness retries.
- Live (owned by Phase `15`): a full `jitml bootstrap --linux-cpu` reaches all
  components Ready under the kind-node cap with no `OOMKilled` restart loops, and
  `free -h` stays within budget.

### Current Validation State

- Pod resource limits + right-sized replicas have landed: `chart/values/minio.yaml`,
  `chart/values/pulsar.yaml`, `chart/values/harbor.yaml`, and
  `chart/values/kube-prometheus-stack.yaml` now carry `resources` requests/limits
  matching the `dhall/cluster/` budgets; the local chart deployments
  (`chart/local/jitml-service`, `chart/local/jitml-demo`,
  `chart/local/tensorboard`) carry `resources` blocks; `JitML.Cluster.PostgresRegistry`
  generates the PerconaPGCluster CRD with `replicas: 1` and per-instance
  `resources` requests/limits.
- MinIO bucket readiness and Pulsar topic create migrated from `sh -c` to typed
  Haskell IO: `JitML.Cluster.Readiness.runMinioBucketReadinessIO` and
  `JitML.Cluster.PulsarBootstrap.runPulsarTopicCreatesIO` perform the retry
  loops in Haskell over typed leaf `kubectl exec ... mc` / `... pulsar-admin`
  subprocesses; the final-gate `minioBucketReadinessSubprocess` is now a typed
  single command using the `MC_HOST_jitml-minio` env hand-off (no in-pod shell).
  `JitML.Bootstrap.liveExecutePhasedRollout` runs the IO steps between the
  pre-grant / grant / post-grant subprocess phases.
- `docker compose run --rm jitml cabal build all` (2026-05-29) succeeds.
- `cabal test jitml-unit` — all 185 tests pass.
- `cabal test jitml-integration` — only pre-existing live-cluster tests fail
  (Pulsar/MinIO/Harbor timeouts, no cluster up); renderer assertions pass.
- `jitml lint chart` and `jitml check-code` exit `0`.
- **Live cluster (2026-05-29)** — `docker compose run --rm jitml cabal run -v0
  jitml -- bootstrap --linux-cpu` brought up MinIO, the Percona Postgres
  operator + cluster, and the full Harbor stack with the new resource budgets:
  `kubectl get pods -n platform` reports all Harbor + MinIO + Postgres pods
  `Running`, and `free -h` reports `4.5 Gi used / 10 Gi available` against the
  Sprint `2.8` 10 GiB node cap. The right-sized stack fits comfortably under
  the cap. `runMinioBucketReadinessIO` succeeded live (Harbor's registry bucket
  existed in MinIO before Harbor installed; Harbor reached Ready).

### Remaining Work

- The live convergence-under-cap run and the readiness-retry re-validation are
  owned by Phase `15` Sprint `15.1`'s Remaining Work.
- The matching manual-PV count reduction landed in Phase `3` Sprint `3.2`
  (closed 2026-05-29).

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
