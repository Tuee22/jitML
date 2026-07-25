# Phase 156: Live Job Failure Observation and Apple Placement Assertions

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Live Job Failure Observation and Apple Placement Assertions. Single-session phase migrated from legacy Sprint 12.12 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 156.1: Live Job Failure Observation and Apple Placement Assertions [✅ Done]

**Status**: Done
**Implementation**: `test/integration/Main.hs`,
`src/JitML/Test/WorkflowMatrix.hs`, `src/JitML/Service/Workload.hs`
**Docs to update**: `../README.md`,
`../documents/engineering/unit_testing_policy.md`,
`../documents/engineering/daemon_architecture.md`,
`system-components.md`

### Objective

Make live integration tests observe workload placement failures directly. A
failed Kubernetes Job must fail the test promptly with status and pod logs, and
Apple Metal-backed workloads must assert host-resident placement rather than
waiting for domain events that can never arrive.

### Deliverables

- Add a live Job watcher used by integration convergence collectors. When a
  daemon-dispatched Job reaches `Failed` / `BackoffLimitExceeded`, collect the
  owning Job, pod names, container states, and logs, then fail the test.
- Add Apple placement assertions for `training.command.apple-silicon`,
  `rl.command.apple-silicon`, and `tune.command.apple-silicon`: Metal-backed
  cells must produce host workload commands and must not create `jitml-train-*`,
  `jitml-rl-*`, or `jitml-tune-*` Kubernetes Jobs.
- Keep Linux CPU/CUDA tests asserting that their command envelopes still create
  valid in-cluster Jobs.
- Preserve the no-skips lane rule: a missing device/runtime fails the owning lane
  up front instead of silently passing or polling until timeout.

### Validation

- `docker compose run --rm jitml cabal build all` passed after the failed-Job
  watcher and WorkflowMatrix placement expectation edits.
- `docker compose run --rm jitml cabal test jitml-integration
  --test-show-details=direct --test-options='-p !/Live/'` passed **51 / 51**,
  including the synthetic failed-Job renderer and Apple-vs-Linux placement unit
  assertions.
- `docker compose run --rm jitml cabal test jitml-e2e
  --test-show-details=direct` passed **20 / 20**, including complete
  WorkflowMatrix placement-expectation coverage.
- `docker compose run --rm jitml jitml check-code` passed after the HLint
  eta-reduction fix.
- `./bootstrap/linux-cpu.sh up` completed **83** live rollout steps, and the
  focused `linux-cpu` live selectors for `StartTraining`, duplicate
  `StartTraining`, `StartSweep`, `StartRLRun`, and PPO convergence all passed.
  The Linux selectors still observe legal in-cluster Jobs and the RL/PPO
  collectors now watch those Jobs for failure while consuming Pulsar events.
- `./bootstrap/apple-silicon.sh up` completed **83** live rollout steps after
  the host Cabal package registration was repaired. A stale `jitml:local` image
  had left the Apple service pod running old placement code, so
  `src/JitML/Bootstrap.hs` now rebuilds repo-owned local images during bootstrap;
  after `docker compose build jitml`, `kind load docker-image jitml:local
  --name jitml-apple-silicon`, and `kubectl rollout restart
  deployment/jitml-service -n platform`, the focused Apple live selectors for
  `StartTraining`, duplicate `StartTraining`, `StartSweep`, `StartRLRun`, and
  PPO convergence all passed. A final `kubectl get jobs -n platform` showed only
  platform init/backup Jobs, with no `jitml-train-*`, `jitml-rl-*`, or
  `jitml-tune-*` workload Jobs.
- `docker compose run --rm jitml jitml docs check`, `docker compose run --rm
  jitml jitml check-code`, and `git diff --check` are the final documentation
  alignment gates for the reopened Phase `12` closure.

### Remaining Work

None. Phase `16` owns the full Apple lifecycle lane and Phase `17` owns the
final ledger walk-down.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
