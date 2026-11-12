# Phase 64: Workload Placement Planner and Apple Host Workload Dispatch

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Workload Placement Planner and Apple Host Workload Dispatch. Originally migrated from legacy Sprint 5.11 in the 2026-07-24 phase renumber; see the old→new map in [README.md](README.md).

## Current execution ownership

**Historical record; no current execution gate.** Phases 1–289 retain their
original contracts, statuses and receipts below. Their former order, dependencies
and current-sounding statements are historical. They do not gate the new
[numerical execution sequence](ordered-execution-plan.md). No historical failure
is erased and no historical Done is promoted to current qualification.

Unfinished scope is **transferred, not completed**:

- Former sprint `64.2` → [298](phase-298-portable-workload-placement.md), [318](phase-318-cuda-runtime-engineering.md), [319](phase-319-apple-runtime-engineering.md).

The [transfer register](ordered-plan-transfers.md) assigns implementation and
real-input acceptance separately. The complete retained contract is inherited;
examples or wrappers do not replace its detailed unmet requirements.

## Historical plan and evidence

## Phase State

⏸️ **Blocked** for the expanded validation foundation in Sprint `64.2`.
The earlier Sprint `64.1` record below is retained on its original source and
scope; it does not validate this target or a current hardware lane. The execution
order and transition authority are [the validation-foundation refactor](README.md#validation-foundation-refactor).

The new source/catalogue, runner and hardware controls remain unimplemented.
Sprint `221.2` owns reconciliation of the existing checker with these documented
targets; this documentation-only change supplies no machine-validation receipt.

## Sprint 64.2: Admitted native workload placement and cancellation [⏸️ Blocked]

**Status**: Blocked
**Implementation**: Target changes to `src/JitML/Service/Workload.hs`, `src/JitML/Service/Runtime.hs`, `src/JitML/Service/HostWorkloadRegistry.hs`.
**Blocked by**: Sprint `9.2`, Sprint `21.2`, Sprint `29.2`.
**Docs to update**: `../documents/engineering/execution_resources.md`, `../documents/engineering/validation_execution.md`, `../documents/engineering/daemon_architecture.md`, `../documents/engineering/apple_silicon_metal_headless_builds.md`, `README.md`, `system-components.md`, `legacy-tracking-for-deletion.md`.

### Objective

Native workload dispatch admits and owns the actual host process family, while preserving Apple host placement and exact cancellation identity.

The target contracts are [execution resources](../documents/engineering/execution_resources.md)
and [validation execution](../documents/engineering/validation_execution.md).
Their acceptance requirements below are planned work, not implemented behavior.

### Deliverables

- Carry the validated native resource policy and owned process identity across host dispatch; a Kubernetes client limit never stands in for native enforcement.
- Bind cancellation and observation to the exact workload handle and invocation, not a command name or arbitrary PID; cancel/drain exactly the matching work.
- Budget native heap, footprint, CPU quota, output and finite deadlines together with the VM and observers. Bound Metal/native allocations through actual host accounting and measured retirement headroom.
- Keep real Metal execution in the Apple lane. CPU fixture closure here proves ownership/placement logic, not GPU availability or an Apple scientific pass.

### Validation

1. Run finite native dispatch fixtures and verify correct process identity, wrong/stale handle refusal, observer loss, duplicate requests and owned-family cancellation.
2. Confirm Apple plans emit host commands and no Linux training Job; actual Metal runtime proof remains required by `273.2`.
3. Exercise cap/reader failure and stop escalation under small fixture bounds, retaining terminal and cleanup results without touching unrelated workloads.

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

- Implement the admitted native process boundary and propagate its outcome through daemon dispatch.
- Prove fixture ownership and cancellation; require genuine Apple hardware/resource evidence separately before native scientific qualification.

## Retained Historical Scope

The following state, commands, measurements and closure statements describe the
original Sprint `64.1` surface only. New execution rules and acceptance
above supersede any conflicting operational instruction; old receipts are not
reinterpreted as current readiness.

### Historical Phase State

✅ **Done**.

## Sprint 64.1: Workload Placement Planner and Apple Host Workload Dispatch [✅ Done]

**Status**: Done (2026-06-13)
**Implementation**: `src/JitML/Service/Workload.hs`,
`src/JitML/Service/Consumer.hs`, `src/JitML/Service/Runtime.hs`,
`src/JitML/App.hs`, `src/JitML/Cluster/PulsarBootstrap.hs`,
`test/daemon-lifecycle/Main.hs`, `test/integration/Main.hs`
**Docs to update**: `../README.md`,
`../documents/engineering/daemon_architecture.md`,
`../documents/engineering/training_workloads.md`,
`system-components.md`,
`legacy-tracking-for-deletion.md`

### Objective

Separate substrate semantics from execution residency in the daemon. The
dispatcher uses a single placement planner so Linux device work can still render
Kubernetes Jobs, while Apple Metal-backed Training/RL/Tune/AlphaZero work is
forwarded to the host daemon over Pulsar and never scheduled into a Linux pod.
Adopts `Long-Running Daemons in the Same Binary`, `At-Least-Once Event
Processing`, `Capability Classes and Service Errors`, and `Application
Environment` from [../README.md](../README.md).

### Deliverables

- Add a `WorkloadKind` / `WorkloadPlacement` layer that plans from residency,
  requested `Substrate`, and workload kind to either `WorkloadClusterJob` or
  `WorkloadHostCommand`.
- Extend the Apple host daemon subscription plan beyond inference so
  `BootConfig { substrate = apple-silicon, residency = Host }` acquires the typed
  host workload topic for Metal-backed non-inference commands.
- Replace Apple Training/RL/Tune Job rendering with host command publication.
  Linux CPU/CUDA Job rendering remains unchanged, including CUDA
  `runtimeClassName: nvidia`.
- Preserve the public topic family (`training.command.apple-silicon`,
  `rl.command.apple-silicon`, `tune.command.apple-silicon`) as orchestration
  entrypoints. The cluster daemon consumes those public commands, plans placement,
  and publishes host work when Metal execution is required.
- Publish ordinary domain events (`training.event.apple-silicon`,
  `rl.event.apple-silicon`, `tune.event.apple-silicon`) after host completion so
  clients and tests do not gain a second result surface.
- Record the stale Apple Kubernetes-Job placement row in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md#completed)
  for Sprint `17.7`'s final audit after the live Apple lane validates; that row
  has since moved to `Completed`.

### Validation

- `jitml-daemon-lifecycle` covers the planner table:
  Apple Metal-backed Training/RL/Tune/AlphaZero -> host-resident command; Linux
  CPU -> in-cluster Job; Linux CUDA -> in-cluster Job with NVIDIA RuntimeClass.
- The Apple host daemon dry/acquire summary includes the new host workload
  subscription when `residency = Host`.
- Dispatching `StartRLRun apple-silicon` from the clustered Apple daemon
  publishes a host workload command and creates no `jitml-rl-*` Kubernetes Job.
- Linux CPU and Linux CUDA command dispatch still render their existing Jobs.
- `docker compose run --rm jitml jitml docs check` and
  `docker compose run --rm jitml jitml check-code` pass after the code/doc change.

### Validation State (2026-06-13)

- `docker compose run --rm jitml cabal build all` passed.
- `docker compose run --rm jitml cabal test jitml-daemon-lifecycle --test-show-details=direct`
  passed 34 / 34. The Sprint `5.11` case asserts that `StartRLRun
  apple-silicon` publishes to
  `persistent://public/default/rl.host-command.apple-silicon`, while
  `StartRLRun linux-cpu` still applies `job/jitml-rl-*`.
- The daemon subscription test now records the Apple host subscriptions:
  `inference.command.apple-silicon`, `training.host-command.apple-silicon`,
  `tune.host-command.apple-silicon`, and `rl.host-command.apple-silicon`, all as
  `jitml-host`.
- The Pulsar bootstrap registry now contains the three host-command topics.
- `docker compose run --rm jitml jitml docs check`, `docker compose run --rm
  jitml jitml check-code`, and `git diff --check` passed.

### Remaining Work

- None. Phase `12` completed the failed-Job/no-Apple-Job integration assertions,
  Phase `16` completed the live Apple full-lane validation, and Phase `17`
  completed the final legacy-ledger move to `Completed`.

## Documentation Requirements

**Engineering docs to create/update:**

- `../documents/engineering/execution_resources.md`.
- `../documents/engineering/validation_execution.md`.
- `../documents/engineering/daemon_architecture.md`.
- `../documents/engineering/apple_silicon_metal_headless_builds.md`.

**Product docs to create/update:**

- [Development-plan entry](README.md#validation-foundation-refactor), [component inventory](system-components.md), and [deletion ledger](legacy-tracking-for-deletion.md).

**Cross-references to add:**

- Link the target contracts, exact sprint dependencies and evidence pointers together when source implementation lands; update root summaries only in an authorized root-file change.
