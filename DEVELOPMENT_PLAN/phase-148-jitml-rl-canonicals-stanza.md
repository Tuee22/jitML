# Phase 148: `jitml-rl-canonicals` Stanza

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: jitml-rl-canonicals Stanza. Single-session phase migrated from legacy Sprint 12.4 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 148.1: `jitml-rl-canonicals` Stanza [✅ Done]

**Status**: Done
**Owned obligations after refactor**: code-surface only. The
`rl_steps` / `rl_eval_episodes` / `az_games` / `az_sims` knob
consumption closed on 2026-05-24 and the deterministic-stub per-cohort
run-to-run determinism closed on the same date — the stanza invokes
each cohort's rollout helper twice in-process and asserts bit-identity
plus rule-conformance properties (no `test/golden/rl/` fixtures per
[../README.md → Snapshot targets → Numerical-fixture
prohibition](../README.md#snapshot-targets)). Live `jitml rl train`
against algorithm × environment cohorts with real env simulators and
live statistical convergence + run-to-run determinism migrated to
Phase `15` Sprint `15.6`.
**Implementation**: `test/rl-canonicals/`,
`jitml.cabal` (the `jitml-rl-canonicals` stanza)
**Docs to update**: `documents/engineering/unit_testing_policy.md`,
`documents/engineering/training_workloads.md`

### Objective

Use `jitml-rl-canonicals` for the RL algorithm catalog, registered rollout
determinism over real environment dynamics, and Connect 4 transcript checks.

### Deliverables

- `test/rl-canonicals/Main.hs` verifies representative entries in
  `algorithmCatalog`: `PPO`, `SAC`, `HER`, and `AlphaZero`.
- It asserts a registered PPO/CartPole module rollout is deterministic for a
  fixed seed across two in-process invocations (run-to-run equality; no
  committed PPO/CartPole trajectory fixture per
  [../README.md → Snapshot targets → Numerical-fixture
  prohibition](../README.md#snapshot-targets)).
- It asserts `selfPlayTranscript` emits legal Connect 4 columns.
- It asserts each per-game `selfPlayTranscriptFor` helper for Connect 4,
  Othello, Hex, and Gomoku is run-to-run bit-identical and that every
  emitted move satisfies the per-game `gameLegalMoves` invariant; no
  per-game transcript fixtures are committed.
- It covers `RlCommand` text render/parse round-trips plus `RlCommand` /
  `RlEvent` proto3-compatible byte round-trips.
- It does not run RL environments, train policies, or consume
  `rl_steps`, `rl_eval_episodes`, `az_games`, or `az_sims` yet.

### Validation

1. `cabal test jitml-rl-canonicals` exits `0` for the body.
2. Transferred live validation: the stanza runs real RL training against
   every algorithm × canonical environment cohort with the `rl_steps`,
   `rl_eval_episodes`, `az_games`, `az_sims` knobs from `cabal.project`,
   asserts run-to-run trajectory determinism (target matrix form 2)
   and per-seed final-reward distribution clears an in-code statistical
   threshold (form 3 — `median ≥ literature_target − slack`, no
   committed fixtures per [../README.md → Snapshot targets →
   Numerical-fixture prohibition](../README.md#snapshot-targets)), and
   asserts AlphaZero arena promotion thresholds against the in-code
   gating policy.

### Remaining Work

- The `rl-canonicals consumes cabal.project rl_steps and
  rl_eval_episodes knobs` case asserts `rl_steps`, `rl_eval_episodes`,
  `az_games`, and `az_sims` are populated from the `cabal.project`
  report-card knob block (closed 2026-05-24).
- Deterministic-stub per-cohort run-to-run determinism closed on
  2026-05-24 for every traditional RL algorithm cohort; the stanza
  invokes the rollout helper twice in-process and asserts bit-identity
  plus rule-conformance properties. No `test/golden/rl/` fixtures are
  committed per [../README.md → Snapshot targets → Numerical-fixture
  prohibition](../README.md#snapshot-targets).
- Driving `jitml rl train` against every cohort with real env
  simulators, the AlphaZero arena-promotion gating assertion against
  the in-code threshold, and the per-seed final-reward statistical
  assertion are owned by
  [phase-15-linux-cuda-and-cluster-closure.md](README.md#legacy-to-new-phase-map)
  Sprint `15.6`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
