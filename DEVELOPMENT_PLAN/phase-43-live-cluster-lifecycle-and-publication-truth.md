# Phase 43: Live Cluster Lifecycle and Publication Truth

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Live Cluster Lifecycle and Publication Truth. Single-session phase migrated from legacy Sprint 3.7 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 43.1: Live Cluster Lifecycle and Publication Truth [✅ Done]

**Status**: Done (reopened and re-closed 2026-07-15)
**Implementation**: `src/JitML/App.hs`, `src/JitML/Bootstrap.hs`,
`src/JitML/Cluster/Publication.hs`, `src/JitML/Cluster/ReconcileStamp.hs`,
`src/JitML/Cluster/PulsarBootstrap.hs`, `chart/values/pulsar.yaml`,
`chart/values.yaml`, `src/JitML/Plan/Plan.hs`,
`src/JitML/CLI/Spec.hs`, generated command docs after code changes
**Docs to update**: `README.md`, `documents/engineering/cluster_topology.md`,
`documents/engineering/daemon_architecture.md`, `system-components.md`,
`legacy-tracking-for-deletion.md`

### Objective

Make the cluster lifecycle command surface tell the truth and keep readiness
live-measured. A command documented as bringing the cluster up must perform the
live reconcile, and a status command must never manufacture a ready cluster from
missing, corrupt, or default-local publication data.

### Deliverables

- `jitml cluster up --substrate <s>` is the lower-level live Kind/Helm
  reconciler described by `CommandSpec` and `Plan.Plan`
  (`materialize-substrate` → dependency build → Kind create/export → image
  build/load → Helm/apply/readiness → measured publication); it is not a
  file-only lifecycle command.
- A ready `defaultPublication` is never written from file materialization
  alone. Publications that claim component readiness are written only after
  live readiness has been observed.
- `jitml cluster status` fails closed or reports `unknown/not-ready` when
  `./.build/runtime/cluster-publication.json` is missing, corrupt, or locally
  materialized without live evidence. It does not fall back to an Apple Silicon
  ready default.
- `jitml bootstrap --<substrate>` remains the canonical full-stack entrypoint
  and preserves staged image, Dhall, Apple host patching, and measured
  publication semantics.
- Kind/Gateway/Envoy inputs are materialized from the recovered retained-cluster
  port before convergence classification. A versioned desired-state stamp is
  persisted only after successful live publication; exact non-vacuous release,
  readiness, topic, node-image, and app-image evidence maps an exact match to
  exit `3` without mutating cluster or publication state.
- Each stamp binds its schema version, substrate, recovered edge port,
  deterministic desired-input fingerprint, and top-level host OCI descriptor
  for each repo-app tag. Every expected node/tag containerd target matches that
  descriptor, each tag has one uniform node config digest, and every ready app
  Pod reports that exact config digest.
- All 34 authoritative Pulsar topics are probed with exact read-only per-topic
  `stats` commands, and only JSON objects are accepted. Direct and umbrella Pulsar
  values set `brokerDeleteInactiveTopicsEnabled: "false"` and
  `restartPodsOnConfigMapChange: true`, preventing inactive deletion and
  rolling retained brokers when the rendered policy changes.
- `README.md`, `documents/cli/commands.md`, manpages, and completions remain
  generated from `CommandSpec`.

### Validation

- The first exact `docker compose run -T --rm jitml jitml cluster up
  --substrate linux-cpu` invocation exited `0` after 157 live steps in 2692
  seconds, retaining edge `127.0.0.1:9091`, all four Kind nodes, and all 20 PVCs
  while reconciling nine Helm releases, five repo-app Pods, and three Pulsar
  brokers.
- All 34 exact read-only `pulsar-admin topics stats <topic>` probes returned one
  JSON object after the reconcile and again after more than 60 seconds. The
  broker ConfigMap and all three live broker runtimes reported
  `brokerDeleteInactiveTopicsEnabled=false`; broker restart counts and
  expected-topic inactivity-deletion log matches were both zero.
- Host and all eight node/tag image rows agreed on top-level OCI descriptor
  `sha256:87b478abc5aade79b613386a9ad7c4a77a145b7cf3d54391ca4f1fa8d11013b0`.
  Every node/tag row and all five app Pods agreed on config digest
  `sha256:43238c272a7d54ac2c2212d211f209d1b991385c21e8badd4283710580d6f227`.
- The second identical command exited `3` in 58 seconds. Publication, stamp,
  edge, four-node set, 20-PVC set, nine Helm revisions, five app Pods, three
  brokers, and eight node-image rows were byte-stable across the two snapshots.
- Focused gates passed for reconcile stamp/classification **8 / 8**, Kind
  recovery/materialization **12 / 12**, app-image evidence **2 / 2**, Pulsar
  stats parsing/retry **1 / 1**, and direct/umbrella Pulsar values **1 / 1**.
  Haskell lint, `jitml check-code`, the warning-clean build, and the immutable
  container build all passed.

### Remaining Work

- None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
