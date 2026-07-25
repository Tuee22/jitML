# Phase 93: RL CLI Summaries and Report Hooks

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: RL CLI Summaries and Report Hooks. Single-session phase migrated from legacy Sprint 8.5 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 93.1: RL CLI Summaries and Report Hooks [✅ Done]

**Status**: Done
**Owned obligations after refactor**: code-surface only. The
`proto-lens` Haskell wire bindings for `rl.proto` closed on
2026-05-24 (`gen/Proto/Jitml/Rl.hs` + `gen/Proto/Jitml/Rl_Fields.hs`
re-exported by the cabal library; `parseRlCommand` remains the
deterministic local text-envelope parser). Daemon-side `RlHandler`
against live broker and the live `StartRLRun → EpisodeDone`
integration test migrated to Phase `15` Sprints `15.3` / `15.6`.
**Implementation**: `src/JitML/RL/Algorithms.hs`,
`src/JitML/RL/Framework.hs`, `src/JitML/Proto/Rl.hs`,
`src/JitML/Test/Report.hs`, `src/JitML/App.hs`
**Docs to update**: `documents/engineering/training_workloads.md`

### Objective

Wire the current RL CLI summaries, framework metadata, and report-card hooks.

### Deliverables

- `jitml rl train <rl-experiment-dhall>` is registered as a Plan/Apply-capable
  command and prints the selected experiment plus the local algorithm count
  during normal execution.
- `jitml rl eval --checkpoint <id>` loads the named checkpoint through the
  substrate inference path.
- `jitml rl rollout --seed <n>` runs a measured on-device PPO rollout and fails
  closed when the substrate device is unavailable.
- `src/JitML/Test/Report.hs` carries the report-card stanza list used by the
  current test summary.
- `src/JitML/RL/Framework.hs` declares schedules, action distributions, action
  noise, target networks, GAE, callbacks, and evaluator metadata.
- `proto/jitml/rl.proto` declares `StartRLRun`, `StopRLRun`,
  `EpisodeDone`, `EvalDone`, `CheckpointDoneRL`, `MetricUpdate` plus
  the discriminated `RlCommand` / `RlEvent` unions for the
  substrate-scoped topics. `src/JitML/Proto/Rl.hs` mirrors the proto
  into typed envelopes, including `parseRlCommand` for the current text
  command envelope; `rlCommandTopic` / `rlEventTopic` resolve the topic
  names per substrate.
- `encodeRlCommandProto` / `decodeRlCommandProto` and
  `encodeRlEventProto` / `decodeRlEventProto` round-trip the current
  `RlCommand` and `RlEvent` oneofs through strict proto3-compatible bytes.
  Generated proto-lens Haskell bindings are checked in under
  `gen/Proto/Jitml/Rl.hs` and `gen/Proto/Jitml/Rl_Fields.hs`.

### Validation

1. `jitml rl train --dry-run experiments/cartpole.dhall` emits the typed
   plan.
2. `jitml rl rollout --seed 42` prints a measured same-seed rollout from the
   registered real-environment generator.
3. `jitml-unit` verifies the framework catalog and run-plan surface.
4. `cabal test jitml-rl-canonicals` covers render/parse round-trips for
   `StartRLRun` and `StopRLRun` text command envelopes and
   proto3-compatible binary command/event envelopes.
5. Transferred live validation: `jitml rl train` publishes `StartRLRun` on
   `rl.command.<mode>`; the daemon's `RlHandler` consumes it, runs the
   real RL loop, and publishes `rl.event.<mode>` envelopes
   (`EpisodeDone`, `EvalDone`, `CheckpointDone`, `MetricUpdate`) that
   round-trip into the report card.

### Remaining Work

- `proto-lens` Haskell wire bindings for `rl.proto` closed on
  2026-05-24: `gen/Proto/Jitml/Rl.hs` and
  `gen/Proto/Jitml/Rl_Fields.hs` are exposed by the cabal library.
  `parseRlCommand` remains the deterministic local text-envelope
  parser; the new `Proto.Jitml.Rl.*` modules are the cross-language
  byte-equivalent binding for other-language proto3 clients.
- The daemon-side `RlHandler` against live broker and the live
  `StartRLRun → EpisodeDone` round-trip are owned by
  [phase-15-linux-cuda-and-cluster-closure.md](README.md#legacy-to-new-phase-map)
  Sprints `15.3` and `15.6`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
