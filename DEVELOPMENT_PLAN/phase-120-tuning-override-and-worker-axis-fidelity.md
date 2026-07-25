# Phase 120: Tuning Override and Worker Axis Fidelity

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Tuning Override and Worker Axis Fidelity. Single-session phase migrated from legacy Sprint 9.16 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 120.1: Tuning Override and Worker Axis Fidelity [✅ Done]

**Status**: Done (closed 2026-06-30)
**Implementation**: `src/JitML/App.hs`, `src/JitML/Tune/Catalog.hs`,
`src/JitML/Service/Workload.hs`, `src/JitML/Service/RunConfig.hs`,
`test/hyperparameter/Main.hs`, `test/integration/Main.hs`
**Docs to update**: `README.md`, `documents/engineering/training_workloads.md`,
`system-components.md`, `legacy-tracking-for-deletion.md`

### Objective

Make tuning control values real. A sampler/scheduler/pruner/trial count selected
by CLI override must be the value used by validation, plan refinement, trial
selection, local artifact writing, checkpoint promotion, and report-card
measurement. The current worker transport captures those resolved values in
the versioned `TuningPlan`, not in parallel primitive fields.

### Deliverables

- Apply `JitML.Experiment.Overrides.applyOverrides` to the decoded tuning
  experiment before rendering the plan, validating the axes, computing local
  trials, writing `tune-trials`, or writing the best-trial checkpoint.
- Ensure `writeLocalTuneArtifacts` consumes the resolved/overridden experiment,
  not the original Dhall value.
- Preserve daemon-dispatched worker axis fidelity: workers consume the
  sampler/scheduler/pruner selected by the resolved plan and must not enumerate
  the whole catalog product unless that plan explicitly requests it. Sprint
  `9.17` supersedes the primitive `turcSampler` / `turcScheduler` /
  `turcPruner` transport used when this sprint originally closed.
- Add tests that `jitml tune experiments/mnist-tune.dhall --sampler Sobol
  --trials 2` changes both rendered output and local artifact/trial selection,
  and that a daemon `StartSweep` with a non-default axis runs that axis in the
  worker event path.

### Validation

- `docker compose run --rm jitml jitml test jitml-hyperparameter --linux-cpu`
  passed **17 / 17**.
- `docker compose run --rm jitml jitml test jitml-integration --linux-cpu`
  passed **77 / 77**, including **19 / 19** `Live` cases and the live daemon
  `StartSweep` placement path.
- `docker compose run --rm jitml jitml docs check` is rerun after the Sprint
  `9.16` documentation updates.
- `docker compose run --rm jitml jitml check-code` is rerun after the Sprint
  `9.16` documentation updates.

### Remaining Work

- None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
