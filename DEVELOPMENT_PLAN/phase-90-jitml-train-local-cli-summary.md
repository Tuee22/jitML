# Phase 90: `jitml train` Local CLI Summary

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: jitml train Local CLI Summary. Single-session phase migrated from legacy Sprint 8.2 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 90.1: `jitml train` Local CLI Summary [✅ Done]

**Status**: Done
**Owned obligations after refactor**: code-surface only. The
`proto-lens-protoc` binding generation closed on 2026-05-24 (modules
`Proto.Jitml.Training` and `Proto.Jitml.Training_Fields` under `gen/`,
cabal library re-exports them, `cabal.project` resolves `lens-family` /
`lens-family-core` from plain Hackage under GHC `9.12.4`, and
`jitml-daemon-lifecycle` validates the cross-language wire-byte
equivalence). Daemon-side `TrainingHandler` against live broker and
the live publish/consume integration test migrated to Phase `15`
Sprints `15.3` / `15.4`.
**Implementation**: `src/JitML/App.hs`, `src/JitML/Plan/Plan.hs`,
`src/JitML/Proto/Training.hs`
**Docs to update**: `documents/engineering/training_workloads.md`,
`documents/engineering/daemon_architecture.md`

### Objective

Wire `jitml train` into the CLI as a Plan/Apply-capable command with a current
local summary body. Pulsar command/event publication is daemon-owned and later
validated by the workflow/runtime closure phases.

### Deliverables

- `jitml train <experiment-dhall>` is registered in `CommandSpec`.
- `jitml train --dry-run <experiment-dhall>` renders the generic training plan
  through `src/JitML/Plan/Plan.hs`.
- Normal `jitml train` execution prints the selected experiment path, the first
  local canonical problem, and its deterministic final loss.
- `src/JitML/Service/Consumer.hs` provides the local at-least-once
  deduplication helper used by later event-flow work.
- `proto/jitml/training.proto` declares `StartTraining`, `StopTraining`,
  `EpochCompleted`, `CheckpointDone`, `TrainingFailed` plus
  discriminated `TrainingCommand` / `TrainingEvent` unions for the
  substrate-scoped Pulsar topics. `src/JitML/Proto/Training.hs` mirrors
  the proto into typed Haskell envelopes with deterministic renderers and
  `parseTrainingCommand` for the current text command envelopes.
  `trainingCommandTopic` / `trainingEventTopic` resolve the
  substrate-scoped topic names.
- The GADT-indexed `TrainingLifecycle` already lives in
  `src/JitML/RL/Framework.hs` (Sprint 8.4 / 8.7); the pipeline in
  `src/JitML/SL/Loop.hs` walks the singleton lifecycle.
- `encodeTrainingCommandProto` / `decodeTrainingCommandProto` use
  `JitML.Proto.Wire` to round-trip the current `TrainingCommand`
  oneof envelope through strict proto3-compatible bytes.
- `encodeTrainingEventProto` / `decodeTrainingEventProto` round-trip the
  current `TrainingEvent` oneof envelope, including repeated checkpoint
  metrics, through strict proto3-compatible bytes.
- Generated cross-language `proto-lens` output lives under
  `gen/Proto/Jitml/Training.hs` (+ `Training_Fields`); the cabal library
  exposes `Proto.Jitml.Training` and `Proto.Jitml.Training_Fields` so
  callers can decode the same wire bytes through the proto-lens
  `Message` instance for cross-language interop with other-language
  proto3 clients.

### Validation

1. `jitml train --dry-run experiments/mnist.dhall` emits the typed plan
   and exits `0`.
2. `jitml train experiments/mnist.dhall` prints the deterministic
   canonical-problem summary.
3. `cabal test jitml-sl-canonicals` covers render/parse round-trips for
   `StartTraining` and `StopTraining` text command envelopes and
   proto3-compatible binary command/event envelopes.
4. Transferred live validation: `jitml train` resolves and SHA-hashes the
   experiment Dhall, reconciles prerequisites, materializes the dataset,
   publishes `StartTraining` on `training.command.<mode>`, the daemon's
   `TrainingHandler` consumes it, and the resulting
   `training.event.<mode>` envelopes drive the report card.

### Remaining Work

- The `proto-lens-protoc` bindings closed on 2026-05-24: generated
  modules `Proto.Jitml.Training` and `Proto.Jitml.Training_Fields`
  live under `gen/`, the cabal library exposes them, and the
  `proto-lens` / `proto-lens-runtime` deps resolve through plain Hackage
  under the GHC `9.12.4` / `base-4.21` baseline. The `gen/` tree is
  excluded from the whitespace lint so regeneration via
  `protoc --plugin=protoc-gen-haskell=$(which proto-lens-protoc)
  --haskell_out=../gen jitml/*.proto` from `proto/` produces a
  drift-free check-code path. Cross-language byte-equivalence is
  validated by the new `local proto3 bytes decode through the
  proto-lens generated InferenceRequest` case in
  `jitml-daemon-lifecycle` (extends the same pattern to Training
  envelopes as the daemon-side handler lands).
- The daemon-side `TrainingHandler` against live broker and the live
  publish/consume integration test are owned by
  [phase-15-linux-cuda-and-cluster-closure.md](README.md#legacy-to-new-phase-map)
  Sprints `15.3` / `15.4`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
