# Phase 64: Workload Placement Planner and Apple Host Workload Dispatch

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Workload Placement Planner and Apple Host Workload Dispatch. Single-session phase migrated from legacy Sprint 5.11 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

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

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
