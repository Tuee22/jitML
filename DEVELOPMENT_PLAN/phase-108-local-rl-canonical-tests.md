# Phase 108: Local RL Canonical Tests

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Local RL Canonical Tests. Single-session phase migrated from legacy Sprint 9.4 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 108.1: Local RL Canonical Tests [✅ Done]

**Status**: Done
**Owned obligations after refactor**: code-surface only. Per-algorithm
run-to-run determinism coverage closed on 2026-05-24 for every
traditional algorithm × canonical environment pairing via
`checkRolloutDeterminism`, and the `rl-canonicals consumes
cabal.project rl_steps and rl_eval_episodes knobs` case closed on the
same date. Per-seed final-reward distribution check consuming live
training output migrated to Phase `15` Sprint `15.6`.
**Implementation**: `test/unit/Main.hs`, `test/integration/Main.hs`,
`test/rl-canonicals/Main.hs`
**Docs to update**: `documents/engineering/training_workloads.md`

### Objective

Stitch the current RL metadata and registered real-environment rollout surface
into the dedicated local RL canonical stanza.

### Deliverables

- `test/rl-canonicals/Main.hs` verifies representative algorithm names across
  the local metadata catalog.
- The stanza asserts a registered PPO/CartPole rollout is stable across two
  in-process invocations (run-to-run equality, no committed trajectory fixture
  per [../README.md → Snapshot targets → Numerical-fixture prohibition](../README.md#snapshot-targets)).
- The stanza also checks the current Connect 4 transcript helper keeps moves
  within legal column bounds.
- PPO/CartPole determinism is asserted by re-running the rollout
  in-process and comparing bit-for-bit; per-algorithm coverage is
  owned by `### Remaining Work` below.

### Validation

1. `cabal test jitml-rl-canonicals` exits `0` for the body.
2. Transferred live validation: the stanza exercises the RL target matrix
   forms (2) same-substrate run-to-run trajectory determinism and (3)
   per-seed final-reward distribution against an in-code statistical
   threshold (median over k seeds ≥ literature_target − slack; no
   per-substrate committed reward fixture per [../README.md → Snapshot
   targets → Numerical-fixture prohibition](../README.md#snapshot-targets))
   for every algorithm in the catalog.

### Remaining Work

- The per-algorithm run-to-run determinism coverage closed on
  2026-05-24 for every traditional algorithm × canonical environment
  pairing (cartpole or mountain-car); the rl-canonicals stanza
  enforces each through `checkRolloutDeterminism`, which invokes
  `AlgorithmModule.moduleRolloutGenerator` twice in-process and
  asserts bit-identity between the two outputs. No `test/golden/rl/`
  files are committed.
- The `rl-canonicals consumes cabal.project rl_steps and
  rl_eval_episodes knobs` case in `test/rl-canonicals/Main.hs` now loads
  the `cabal.project` report-card knob block and asserts the RL knobs
  are populated (closed 2026-05-24).
- The per-seed final-reward distribution check (form 3) consuming live
  training output is owned by
  [phase-15-linux-cuda-and-cluster-closure.md](README.md#legacy-to-new-phase-map)
  Sprint `15.6`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
