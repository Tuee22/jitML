# Phase 60: Typed Dhall `RunConfig` and BootConfig-Mounted Worker Dispatch

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Typed Dhall RunConfig and BootConfig-Mounted Worker Dispatch. Single-session phase migrated from legacy Sprint 5.7 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 60.1: Typed Dhall `RunConfig` and BootConfig-Mounted Worker Dispatch [✅ Done]

**Status**: Done (code-surface closed 2026-05-29; live re-validation owned by Phase 15 Sprints `15.3`/`15.4`/`15.8`/`15.10`)
**Implementation**: `dhall/run/Schema.dhall`, `src/JitML/Service/RunConfig.hs`, `src/JitML/Service/Workload.hs`, `src/JitML/App.hs`
**Docs to update**: `documents/engineering/training_workloads.md`, `documents/engineering/daemon_architecture.md`, `system-components.md`, `legacy-tracking-for-deletion.md`

### Objective

Replace the ~20 `JITML_*` run-parameter environment variables the daemon sets on
worker Jobs (and the worker re-parses with silent defaulting) with a typed Dhall
`RunConfig`, and have the worker read `BootConfig.dhall` from a mounted ConfigMap
instead of duplicate `JITML_SUBSTRATE` / `JITML_PULSAR_WS` env vars. Implements
doctrine `Application Environment`; the removed env IPC is tracked in the legacy
ledger.

### Deliverables

- A typed `RunConfig` Dhall schema (`dhall/run/Schema.dhall`) covering the train /
  tune / rl run parameters (seed, epochs, batch size, max steps, eval episodes,
  sampler/scheduler/pruner, trial budgets, SL caps), with `src/JitML/Service/
  RunConfig.hs` = record + decoder + render + load (mirrors
  `JitML.Service.BootConfig`).
- `JitML.Service.Workload.renderJob` writes the `RunConfig` Dhall the same way the
  experiment Dhall already travels by hash (`stDhallObjectKey` / `ssDhallObjectKey`)
  and mounts the `jitml-service-config` ConfigMap into the Job; it no longer sets
  the `JITML_*` run-parameter env vars.
- `JitML.App` (`runRl` / `runTune` / SL `attemptRealMnistTraining`) decodes the
  `RunConfig` via `Dhall.inputFile` and reads `BootConfig` via `loadBootConfig`
  instead of `envWithDefault`; the experiment hash travels in the typed
  `RunConfig` record (`workerExperimentHash` reads it from the mounted
  `RunConfig.dhall` first, with the legacy `JITML_EXPERIMENT_HASH` env retained
  only as a developer-side fallback for non-Job invocations).

### Validation

- `jitml rl train` / `jitml train` / `jitml tune` decode their parameters from the
  typed Dhall with no `JITML_*` run-parameter or wiring env on the Job. Sprint
  `5.17` reopens the bad-field case because a present mounted file that fails
  Dhall decoding is currently treated like an absent mount; the close condition
  is a typed failure instead of silent defaulting.
- Live (owned by Phase `15`): a dispatched train/rl/tune run produces the same
  results with the env IPC removed.

### Current Validation State

- New `dhall/run/Schema.dhall` declares the typed @TrainingRunConfig@ /
  @TuneRunConfig@ / @RlRunConfig@ records; `JitML.Service.RunConfig` provides
  the records, decoders, loaders, renderers, and try-load helpers (mirrors
  `JitML.Service.BootConfig`).
- `JitML.Service.Workload.renderTrainingJob` / `renderTuneJob` / `renderRlJob`
  emit two YAML documents: a per-run @ConfigMap@ holding the rendered
  @RunConfig.dhall@ and a Job whose pod mounts that ConfigMap at
  `/etc/jitml/run/` plus the shared @jitml-service-config@ ConfigMap at
  `/etc/jitml/service/`. The Job's container takes no `JITML_*` environment
  variables.
- `JitML.App` worker paths read typed Dhall:
  - `runRl ["rl","train"]` loads `RlRunConfig` and uses its
    `environment`/`seed`/`maxSteps`/`evalEpisodes`/`trainerKind`.
  - `lookupTrialBudget` / `lookupSweepSeed` (in `runTune`) load
    `TuneRunConfig` first.
  - `attemptRealMnistTraining` loads `TrainingRunConfig` for the SL caps.
  - `workerBrokerTarget` loads `BootConfig.dhall` (substrate) + any
    @RunConfig@ variant (Pulsar WebSocket URL).
- Each path falls back to the former `JITML_*` env vars when the mount is
  absent (e.g., developer-side CLI invocations outside a Job pod), preserving
  backward compatibility.
- `docker compose run --rm jitml cabal build all` (2026-05-29) succeeds.
- `cabal test jitml-unit` — all 185 tests pass.
- `cabal test jitml-daemon-lifecycle` — all 30 tests pass.
- `cabal test jitml-integration` — only pre-existing live-cluster tests fail
  (Pulsar/MinIO/Harbor timeouts, no cluster up); renderer assertions pass.
- `jitml docs check` and `jitml check-code` exit `0`.

### Remaining Work

- The live daemon→worker dispatch validation with the env IPC removed is owned by
  Phase `15` Sprints `15.3` / `15.4` / `15.8` / `15.10`'s Remaining Work.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
