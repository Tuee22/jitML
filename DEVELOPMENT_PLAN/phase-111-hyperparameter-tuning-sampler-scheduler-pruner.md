# Phase 111: Hyperparameter Tuning (Sampler × Scheduler × Pruner)

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Hyperparameter Tuning (Sampler × Scheduler × Pruner). Single-session phase migrated from legacy Sprint 9.7 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 111.1: Hyperparameter Tuning (Sampler × Scheduler × Pruner) [✅ Done]

**Status**: Done
**Owned obligations after refactor**: code-surface only.
`proto-lens`-driven Haskell bindings for `proto/jitml/tune.proto`
closed on 2026-05-24 (`gen/Proto/Jitml/Tune.hs` +
`gen/Proto/Jitml/Tune_Fields.hs` re-exported by the cabal library).
Daemon-side tune handler against live broker, live MinIO trial
persistence, and the full canonical sampler × scheduler × pruner grid
against live tuner execution migrated to Phase `15` Sprint `15.10`.
**Implementation**: `src/JitML/Tune/Catalog.hs`,
`src/JitML/App.hs`, `src/JitML/Proto/Tune.hs`,
`test/hyperparameter/Main.hs`
**Docs to update**: `documents/engineering/training_workloads.md`

### Objective

Land the current deterministic sampler × scheduler × pruner catalogs,
trial-storage key helpers, resume equality summary, and `jitml tune` local
summary.

### Deliverables

- `Sampler` enumerates `Grid`, `Sobol`, `Random`, `TPE`, `GPBO`,
  `GeneticAlgorithm`, `NSGA2`, `MuLambdaES`, `CMAES`, `EvolutionStrategies`,
  and `PBT`.
- `Scheduler` enumerates `Fifo`, `SuccessiveHalving`, `Hyperband`, and `ASHA`.
- `Pruner` enumerates `NoPruner`, `MedianPruner`, and `PercentilePruner`.
- `deterministicTrials` emits real measured train-accuracy trial values for
  the current sampler set; sampler outputs are exercised by run-to-run
  equality and sampler-state-purity property tests, not by committed
  trial-value files (per [../README.md → Snapshot targets →
  Numerical-fixture prohibition](../README.md#snapshot-targets)).
- `trialStorageKey`, `resumeMatchesFullRun`, and
  `renderTrialResumeSummary` provide the local trial persistence/resume
  surface.
- `JitML.Tune.Resume.persistTrialTranscript` and `replaySweep` round-trip
  `TrialTranscript` values through `HasMinIO.putBlobBytesIfAbsent` /
  `minioReadBytes`, validated against the filesystem-backed instance in
  `jitml-integration`.
- `jitml tune <tune-dhall>` is Plan/Apply-capable and prints the decoded
  sampler / scheduler / pruner axes plus four deterministic local trial values.
- `experiments/mnist-tune.dhall` is the checked-in `Some
  Tuning::{ … }` worked example from
  [../README.md → Concrete `Some Tuning::{ … }` example](../README.md)
  with the TPE sampler / ASHA scheduler / MedianPruner triple and the
  full search space. `JitML.Tune.Catalog.loadTuningExperiment` decodes it
  into the local Haskell tuning ADT, and the real-binary integration matrix
  asserts `jitml tune experiments/mnist-tune.dhall` renders `sampler: TPE`.
- `jitml-hyperparameter` consumes the `tune_trials` and
  `tune_budget_per_trial` report-card knobs from `cabal.project` for the
  local TPE trial-budget assertion.
- `proto/jitml/tune.proto` + `src/JitML/Proto/Tune.hs` declare the
  typed `TuneCommand` / `TuneEvent` surfaces for the substrate-scoped
  Pulsar topics. `parseTuneCommand` covers the current text
  `StartSweep` / `StopSweep` command envelopes, and
  `encodeTuneCommandProto` / `decodeTuneCommandProto` round-trip the current
  `TuneCommand` oneof through proto3-compatible bytes.
  `encodeTuneEventProto` / `decodeTuneEventProto` round-trip the current
  `TuneEvent` oneof through proto3-compatible bytes.
- Generated wire-format protobuf bindings (proto-lens) live under
  `gen/Proto/Jitml/`; live MinIO persistence is validated by later live
  closure sprints.

### Validation

1. `jitml tune --dry-run experiments/mnist-tune.dhall` emits the typed
   Plan/Apply command plan.
2. `cabal test jitml-hyperparameter` verifies the sampler, scheduler, and
   pruner axes are populated, deterministic, the TPE worked example
   decodes, and the local TPE trial budget consumes `cabal.project`
   report-card knobs. It also covers text render/parse round-trips for
   `StartSweep` and `StopSweep`, plus proto3-compatible byte round-trips for
   the current `TuneCommand` / `TuneEvent` oneofs.
3. `jitml-unit` verifies the trial key and resume-equality helpers.
4. `jitml-integration` spawns the real binary and verifies normal
   `jitml tune experiments/mnist-tune.dhall` execution renders `sampler: TPE`.
5. Transferred live validation: a real `Some Tuning::{ … }`-shaped Dhall
   drives `jitml tune` end-to-end through the daemon, trial transcripts
   persist to MinIO bucket `jitml-trials/`, and resume-from-partial-sweep
   reproduces the same trial outcome bit-for-bit.

### Remaining Work

- `proto-lens`-driven Haskell bindings for `proto/jitml/tune.proto`
  closed on 2026-05-24: `gen/Proto/Jitml/Tune.hs` and
  `gen/Proto/Jitml/Tune_Fields.hs` are exposed by the cabal library,
  giving the `TuneCommand` / `TuneEvent` envelopes a binary-equivalent
  cross-language Haskell wire surface.
- Daemon-side tune handler against live broker, `persistTrialTranscript`
  / `replaySweep` validation against live HTTP MinIO, and the full
  canonical sampler × scheduler × pruner grid against live tuner
  execution are owned by
  [phase-15-linux-cuda-and-cluster-closure.md](README.md#legacy-to-new-phase-map)
  Sprint `15.10`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
