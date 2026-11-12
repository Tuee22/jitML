# Phase 29: Dhall Cluster-Resource Profile, Kind-Node Cap, and Host-RAM Preflight

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Dhall Cluster-Resource Profile, Kind-Node Cap, and Host-RAM Preflight. Originally migrated from legacy Sprint 2.8 in the 2026-07-24 phase renumber; see the old→new map in [README.md](README.md).

## Current execution ownership

**Historical record; no current execution gate.** Phases 1–289 retain their
original contracts, statuses and receipts below. Their former order, dependencies
and current-sounding statements are historical. They do not gate the new
[numerical execution sequence](ordered-execution-plan.md). No historical failure
is erased and no historical Done is promoted to current qualification.

Unfinished scope is **transferred, not completed**:

- Former sprint `29.2` → [292](phase-292-generated-output-portability.md), [295](phase-295-host-resource-admission.md), [318](phase-318-cuda-runtime-engineering.md), [319](phase-319-apple-runtime-engineering.md).

The [transfer register](ordered-plan-transfers.md) assigns implementation and
real-input acceptance separately. The complete retained contract is inherited;
examples or wrappers do not replace its detailed unmet requirements.

## Historical plan and evidence

## Phase State

⏸️ **Blocked** for the expanded validation foundation in Sprint `29.2`.
The earlier Sprint `29.1` record below is retained on its original source and
scope; it does not validate this target or a current hardware lane. The execution
order and transition authority are [the validation-foundation refactor](README.md#validation-foundation-refactor).

The new source/catalogue, runner and hardware controls remain unimplemented.
Sprint `221.2` owns reconciliation of the existing checker with these documented
targets; this documentation-only change supplies no machine-validation receipt.

## Sprint 29.2: Whole-host resource admission and measured limits [⏸️ Blocked]

**Status**: Blocked
**Implementation**: Target changes to `src/JitML/Cluster/Resources.hs`, `src/JitML/Prerequisite/Nodes/Cluster.hs`, `dhall/cluster/Schema.dhall`.
**Blocked by**: Sprint `221.2`.
**Docs to update**: `../documents/engineering/execution_resources.md`, `../documents/engineering/validation_execution.md`, `../documents/engineering/cluster_topology.md`, `README.md`, `system-components.md`, `legacy-tracking-for-deletion.md`.

### Objective

One resource contract accounts for host, VM, node, numerical family, helper, compiler and observer consumption before and during owned work. Missing native measurements refuse admission.

The target contracts are [execution resources](../documents/engineering/execution_resources.md)
and [validation execution](../documents/engineering/validation_execution.md).
Their acceptance requirements below are planned work, not implemented behavior.

### Deliverables

- Generate runtime launch arguments and guard expectations from one typed resource policy; verify actual limits before work. CPU idle is diagnostic only; retain explicit CPU quotas and memory, swap and disk safeguards.
- Account for the named VM and its node/pod/client allocations together, including lifecycle helpers and image-builder transients. Container ceilings do not cap native Metal or a separate builder.
- Use platform-correct metrics: macOS footprint includes compressed accounting, RSS is not total footprint, and Windows commit is distinct from resident memory. Record availability/pressure, swap and disk reserves separately.
- Enforce one exclusive heavy-workload admission per host, including diagnostic experiments and compilers. A personal process-name guard or a protected interactive client is not the campaign safety mechanism.
- On native hosts, admit only measured allocation growth, sample latency and bounded retirement that fit the emergency reserve; describe limitations of supervision honestly rather than promise that every kernel panic is impossible.

### Validation

1. Exercise missing/stale/malformed measurements, reserve breach, wrong observed limits, duplicate owners and helper overlap with small fixture thresholds. Retain the failed sample and retirement result.
2. Test macOS footprint/compression decoding without double counting and Linux cgroup aggregate/ancestor limits without summing shared RSS as unique memory.
3. Prove bounded retirement of owned work and no unrelated signal. Do not induce host OOM, swap exhaustion or a panic as a test.
4. After controlled cases pass, verify the selected named-VM/node/client/helper arithmetic and effective limits on real runtime metadata; absence of the substrate reader is a refusal, not a pass.

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

- Implement the exclusive resource admission, readers, policy-to-launch generation and failed-observation retention.
- Validate effective runtime limits and native reaction headroom before any larger diagnostic or campaign; the historical missing-`/proc/meminfo` pass is superseded for native admission.

## Retained Historical Scope

The following state, commands, measurements and closure statements describe the
original Sprint `29.1` surface only. New execution rules and acceptance
above supersede any conflicting operational instruction; old receipts are not
reinterpreted as current readiness.

### Historical Phase State

✅ **Done**.

## Sprint 29.1: Dhall Cluster-Resource Profile, Kind-Node Cap, and Host-RAM Preflight [✅ Done]

**Status**: Done (code-surface closed 2026-05-29; live node-cap exercise owned by Phase 15 Sprint 15.1)
**Implementation**: `dhall/cluster/Schema.dhall`, `dhall/cluster/resources.dhall`, `src/JitML/Cluster/Resources.hs`, `src/JitML/Bootstrap.hs`, `src/JitML/Prerequisite/Nodes/Cluster.hs`
**Docs to update**: `documents/engineering/cluster_topology.md`, `system-components.md`

### Objective

Bound the kind cluster's memory and CPU so an over-budget bootstrap can never
exhaust the host (the 2026-05-29 OOM-storm incident), with the budget expressed as
typed Dhall rather than environment variables or shell arithmetic. Implements
doctrine `Application Environment` (typed config) and `Prerequisites as Typed
Effects`.

### Deliverables

- A typed `ClusterResources` Dhall schema (`dhall/cluster/Schema.dhall`) plus a
  concrete profile (`dhall/cluster/resources.dhall`) carrying `nodeMemoryMiB`,
  `nodeCpus`, and per-component `{ replicas, cpuRequest, cpuLimit, memoryRequest,
  memoryLimit }`, decoded by `JitML.Cluster.Resources.loadClusterResourcesOrDefault`
  (mirrors `JitML.Service.BootConfig.loadBootConfig` and `JitML.Numerics.Schema`).
- The bootstrap reconciler applies a typed `docker update
  --memory/--memory-swap/--cpus` cap to `jitml-<substrate>-control-plane` after
  `kind create`, fail-closed if the cap cannot be applied; the resolved profile is
  materialized to `./.build/conf/cluster/Resources.dhall`.
- A `cluster.host-memory` prerequisite added to the Sprint `2.2` registry that fails
  when host `MemTotal` is below `nodeMemoryMiB` + reserve (returns pass when
  `/proc/meminfo` is absent).

### Validation

- `jitml doctor --scope cluster` reports the `cluster.host-memory` node and fails
  with a remedy hint when `nodeMemoryMiB` exceeds host RAM.
- `jitml bootstrap --<substrate> --dry-run` renders the plan including the node-cap
  step and exits `0`.
- Live (owned by Phase `15`): after `kind create`, `docker inspect -f
  '{{.HostConfig.Memory}}' jitml-<substrate>-control-plane` reports the cap, and a
  forced over-budget cluster OOM-kills pods inside the node cgroup while the host
  stays up.

### Current Validation State

- `docker compose run --rm jitml cabal build all` succeeds (2026-05-29) — the new
  `JitML.Cluster.Resources` module and the wiring changes in
  `JitML.Bootstrap` / `JitML.Prerequisite.Nodes.Cluster` compile clean.
- `docker compose run --rm jitml jitml doctor --scope cluster` reports the new
  `cluster.host-memory` node and exits `0` on this host (15 GiB ≥ 10 GiB node cap +
  4 GiB reserve).
- Historical Phase `2` validation:
  `docker compose run --rm jitml jitml cluster up --substrate linux-cpu`
  materialized `./.build/conf/cluster/Resources.dhall` from the
  `dhall/cluster/` source. Phase `3` Sprint `3.7` subsequently validated the
  stricter live lifecycle contract for that command.
- `cabal test jitml-unit` passes; `cabal test jitml-integration` failures are
  isolated to pre-existing live-cluster Sprint 13.x tests (Pulsar timeouts —
  no cluster up).
- `jitml docs check` exits `0`.

### Remaining Work

- The live node-cap exercise and the host-survives-over-budget validation are owned
  by Phase `15` Sprint `15.1`'s Remaining Work.
- The per-pod limits + right-sized replicas that make the stack converge under the
  cap are owned by Phase `4` Sprint `4.8` (and the PV-layout change by Phase `3`
  Sprint `3.2`).

## Documentation Requirements

**Engineering docs to create/update:**

- `../documents/engineering/execution_resources.md`.
- `../documents/engineering/validation_execution.md`.
- `../documents/engineering/cluster_topology.md`.

**Product docs to create/update:**

- [Development-plan entry](README.md#validation-foundation-refactor), [component inventory](system-components.md), and [deletion ledger](legacy-tracking-for-deletion.md).

**Cross-references to add:**

- Link the target contracts, exact sprint dependencies and evidence pointers together when source implementation lands; update root summaries only in an authorized root-file change.
