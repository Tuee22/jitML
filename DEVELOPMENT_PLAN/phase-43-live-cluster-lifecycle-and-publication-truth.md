# Phase 43: Live Cluster Lifecycle and Publication Truth

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Live Cluster Lifecycle and Publication Truth. Originally migrated from legacy Sprint 3.7 in the 2026-07-24 phase renumber; see the old→new map in [README.md](README.md).

## Current execution ownership

**Historical record; no current execution gate.** Phases 1–289 retain their
original contracts, statuses and receipts below. Their former order, dependencies
and current-sounding statements are historical. They do not gate the new
[numerical execution sequence](ordered-execution-plan.md). No historical failure
is erased and no historical Done is promoted to current qualification.

Unfinished scope is **transferred, not completed**:

- Former sprint `43.2` → [296](phase-296-lifecycle-preservation.md), [318](phase-318-cuda-runtime-engineering.md), [319](phase-319-apple-runtime-engineering.md).

The [transfer register](ordered-plan-transfers.md) assigns implementation and
real-input acceptance separately. The complete retained contract is inherited;
examples or wrappers do not replace its detailed unmet requirements.

## Historical plan and evidence

## Phase State

⏸️ **Blocked** for the expanded validation foundation in Sprint `43.2`.
The earlier Sprint `43.1` record below is retained on its original source and
scope; it does not validate this target or a current hardware lane. The execution
order and transition authority are [the validation-foundation refactor](README.md#validation-foundation-refactor).

The new source/catalogue, runner and hardware controls remain unimplemented.
Sprint `221.2` owns reconciliation of the existing checker with these documented
targets; this documentation-only change supplies no machine-validation receipt.

## Sprint 43.2: Bounded lifecycle preservation and explicit VM retirement [⏸️ Blocked]

**Status**: Blocked
**Implementation**: Target changes to `src/JitML/Bootstrap.hs`, `src/JitML/Cluster/Publication.hs`, `src/JitML/Cluster/ReconcileStamp.hs`.
**Blocked by**: Sprint `29.2`, Sprint `21.2`.
**Docs to update**: `../documents/engineering/execution_resources.md`, `../documents/engineering/validation_execution.md`, `../documents/engineering/cluster_topology.md`, `../documents/engineering/durable_state_dsl.md`, `README.md`, `system-components.md`, `legacy-tracking-for-deletion.md`.

### Objective

Lifecycle operations preserve application data and publish live readiness under the admitted resource envelope, with explicit VM management and attributable retirement.

The target contracts are [execution resources](../documents/engineering/execution_resources.md)
and [validation execution](../documents/engineering/validation_execution.md).
Their acceptance requirements below are planned work, not implemented behavior.

### Deliverables

- Own the state-preserving lifecycle correction formerly accumulated in Phase `278`: original-data readback, snapshot retention, fresh restore, real readiness and truthful publication after teardown.
- Keep VM start and stop explicit operator steps. No test, build, login item, default profile fallback or observer reconnection starts a VM implicitly.
- Bound lifecycle caller plus one serial helper within the declared client slot, verify helper limits before start, and require cached verified application images rather than implicit image builds during constrained lifecycle work.
- Preserve original before/after data summaries and helper retirement. Missing original after-state proof remains missing; later readback does not retroactively complete a failed operation.

### Validation

1. Use lifecycle fixtures for helper collision, absent image, wrong resource limit, failed snapshot/readback and incomplete publication; each refuses before unsafe work.
2. Run a separately admitted finite real lifecycle/readback sequence with known original data, verify retained identities after restoration, then verify publication invalidation and explicit named-VM stop.
3. Confirm failure paths retain exact command errors, helper stop results, preserved recovery data and absence of stray owned processes.

Closure requires the owned targeted/hermetic controls listed above, with a
nonempty independently enumerated test inventory and exact scoped transcripts.
The implementation publishes actual selectable groups in the existing stanzas
and uses the supported `--test-options` passthrough; no invented selector or
unfiltered full-matrix acquisition is an acceptable substitute. A scoped result
is recorded as scoped, never as a passing full stanza. Resource/live controls
also require the actual owned runtime observations named above.

Complete evidence-dependent unit/integration/negative-control transcripts belong
to Sprints `277.2` and `280.2`; cross-family convergence belongs to `283.2` and
`285.2`. Those downstream records are not prerequisites for this foundation or
readiness closure. Every original case remains registered with an explicit owner.
The existing documentation/code-quality commands below run after source parity
is implemented, inside the admitted profile; they do not execute these controls.

```bash
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml docs check
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml check-code
```

Cluster-running jobs use the separately admitted cluster/lifecycle overlays
instead of the stopped-cluster build profile. A real hardware lane is never
claimed by CPU fixtures; absent required runtime capability fails that lane.

### Remaining Work

- Implement and validate the bounded lifecycle and preservation contract without deleting retained recovery data.
- Reprove live readback/restore and publication truth under the current resource policy before campaign ownership depends on them.

## Retained Historical Scope

The following state, commands, measurements and closure statements describe the
original Sprint `43.1` surface only. New execution rules and acceptance
above supersede any conflicting operational instruction; old receipts are not
reinterpreted as current readiness.

### Historical Phase State

✅ **Done**.

The retained closure covers the original measured reconcile/publication
surface. Phase `278` owns the later node-local PV preservation and fresh-restore
handoff across cluster deletion, including readiness after restoration. This
explicit [ownership transfer](phase-278-external-bars-no-self-referential-gate-lint-and-exact-served.md#remaining-work)
adds no backward dependency and does not make the current failed runtime ready.

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

- `../documents/engineering/execution_resources.md`.
- `../documents/engineering/validation_execution.md`.
- `../documents/engineering/cluster_topology.md`.
- `../documents/engineering/durable_state_dsl.md`.

**Product docs to create/update:**

- [Development-plan entry](README.md#validation-foundation-refactor), [component inventory](system-components.md), and [deletion ledger](legacy-tracking-for-deletion.md).

**Cross-references to add:**

- Link the target contracts, exact sprint dependencies and evidence pointers together when source implementation lands; update root summaries only in an authorized root-file change.
