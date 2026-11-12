# Phase 51: Per-Pod Resource Limits and Right-Sized Replicas from the `dhall/cluster/` Profile

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Per-Pod Resource Limits and Right-Sized Replicas from the dhall/cluster/ Profile. Originally migrated from legacy Sprint 4.8 in the 2026-07-24 phase renumber; see the old→new map in [README.md](README.md).

## Current execution ownership

**Historical record; no current execution gate.** Phases 1–289 retain their
original contracts, statuses and receipts below. Their former order, dependencies
and current-sounding statements are historical. They do not gate the new
[numerical execution sequence](ordered-execution-plan.md). No historical failure
is erased and no historical Done is promoted to current qualification.

Unfinished scope is **transferred, not completed**:

- Former sprint `51.2` → [297](phase-297-node-pod-fit.md), [318](phase-318-cuda-runtime-engineering.md), [319](phase-319-apple-runtime-engineering.md).

The [transfer register](ordered-plan-transfers.md) assigns implementation and
real-input acceptance separately. The complete retained contract is inherited;
examples or wrappers do not replace its detailed unmet requirements.

## Historical plan and evidence

## Phase State

⏸️ **Blocked** for the expanded validation foundation in Sprint `51.2`.
The earlier Sprint `51.1` record below is retained on its original source and
scope; it does not validate this target or a current hardware lane. The execution
order and transition authority are [the validation-foundation refactor](README.md#validation-foundation-refactor).

The new source/catalogue, runner and hardware controls remain unimplemented.
Sprint `221.2` owns reconciliation of the existing checker with these documented
targets; this documentation-only change supplies no machine-validation receipt.

## Sprint 51.2: Effective node and pod resource fit [⏸️ Blocked]

**Status**: Blocked
**Implementation**: Target changes to `src/JitML/Cluster/Resources.hs`, `src/JitML/Cluster/Helm.hs`, `chart/values.yaml`.
**Blocked by**: Sprint `29.2`.
**Docs to update**: `../documents/engineering/execution_resources.md`, `../documents/engineering/validation_execution.md`, `../documents/engineering/cluster_topology.md`, `README.md`, `system-components.md`, `legacy-tracking-for-deletion.md`.

### Objective

Rendered and effective pod, node and helper limits agree with the admitted whole-host profile and leave a measured client slot for numerical work.

The target contracts are [execution resources](../documents/engineering/execution_resources.md)
and [validation execution](../documents/engineering/validation_execution.md).
Their acceptance requirements below are planned work, not implemented behavior.

### Deliverables

- Keep requests, limits, replicas and node caps sourced from the typed profile; reject profiles whose combined allocation cannot fit the VM or that reserve the same capacity twice.
- Compare effective cgroup ancestry, pod limits and node limits with planned values; inherited no-swap enforcement is observed explicitly instead of inferred from one redundant literal.
- Include platform startup, steady-state services, lifecycle helpers and client peaks in profile validation. A historical multi-node count does not validate the present bounded topology.
- Keep resource shortage an explicit operational refusal, separate from numerical quality and scientific completion.

### Validation

1. Test rendered/effective mismatches, missing limits, excessive replicas, inherited limits and helper overlap against independent bounded fixtures.
2. On the selected real cluster, observe actual caps and readiness under the admitted profile, retain OOM/limit counters and check client/helper coexistence.
3. Close the finite observation window, retire helpers and explicitly stop the named VM; CPU-idle variation alone must not refuse or stop the run.

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

- Implement the profile/effective-limit checks and verify them before scientific runtime admission.
- Reprove real profile fit and bounded lifecycle-helper coexistence; old replica measurements remain historical only.

## Retained Historical Scope

The following state, commands, measurements and closure statements describe the
original Sprint `51.1` surface only. New execution rules and acceptance
above supersede any conflicting operational instruction; old receipts are not
reinterpreted as current readiness.

### Historical Phase State

✅ **Done**.

**Current topology note (2026-08-09):** typed CPU/memory budgets, readiness
loops, and profile decoding remain Done. Phases `42`, `53`, and `69` closed the
one-worker default, single-instance platform counts, and profile-driven
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

- `../documents/engineering/execution_resources.md`.
- `../documents/engineering/validation_execution.md`.
- `../documents/engineering/cluster_topology.md`.

**Product docs to create/update:**

- [Development-plan entry](README.md#validation-foundation-refactor), [component inventory](system-components.md), and [deletion ledger](legacy-tracking-for-deletion.md).

**Cross-references to add:**

- Link the target contracts, exact sprint dependencies and evidence pointers together when source implementation lands; update root summaries only in an authorized root-file change.
