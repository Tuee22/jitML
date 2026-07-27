# Phase 257: Row-Keyed Integration Matrix

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Row-Keyed Integration Matrix. Single-session phase migrated from legacy Sprint 28.1 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 257.1: Row-Keyed Integration Matrix [✅ Done]

**Status**: Done
**Implementation**: `test/integration/Main.hs`, `src/JitML/Test/RowAssertions.hs`, `src/JitML/Test/Report.hs`
**Docs to update**: `../documents/engineering/unit_testing_policy.md`, `../documents/engineering/product_completion_contract.md`

### Objective

The integration stanza is a row-keyed matrix generated from the typed product
registry, not a hand-listed set of representative workflows. Each product row
runs the real command path for its family and asserts that learned state
actually changed.

### Deliverables

- `src/JitML/Test/RowAssertions.hs` exposes real-ML assertion primitives:
  `paramHash` (deterministic initial/final parameter hash), `assertLearnedStateChanged`
  (final hash differs from initial hash with a non-zero update count), and
  `assertRealLoss` (a real, finite, decreasing loss trajectory over the declared
  budget — no hardcoded or deterministic-scaffold summary satisfies it).
- `test/integration/Main.hs` folds `allProductRows` and dispatches per `family`:
  `Supervised`, `ReinforcementLearning`, and `AlphaZero` rows train for their
  fixed budget, write a `CompletedTraining` checkpoint, and reject inference
  before completion; `Tuning` rows drive the real hyperparameter search path and
  record the selected configuration's learned-state delta.
- Each row's `integrationTest` id is exercised by exactly the test the registry
  names; the matrix binds `rowId` → `testId` with no duplicate or orphan ids.
- `src/JitML/Test/Report.hs` collects per-row integration evidence and **fails
  naming any uncovered `rowId`/`testId` pair** — a row without a real,
  learned-state-changing integration test cannot pass.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-integration --linux-cpu
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml check-code
```

### Closure Evidence

Reopened 2026-07-05. The obligation this sprint owns — every product row bound to
an integration test that drives the **real** training/checkpoint/inference path
and asserts learned-state change — is unmet in substance:

- The `integration.product.<row>` cases **read** published checkpoint manifests
  from `.build/checkpoints` and assert over recorded fields; they do not drive a
  training run, so `assertLearnedStateChanged` / `assertRealLoss` are checked
  against a manifest rather than a live-computed trajectory
  (`test/integration/Main.hs`, `src/JitML/Test/RowAssertions.hs`).
- The RL rows' `median_final_reward` is the **expert-controller heuristic**, not
  a trained-policy rollout, so the reward evidence certifies the scripted
  controller, not the learned policy.
- `assertRlRowEvidence` is sound but is only exercised on **synthetic** good/bad
  fixtures, never on real RL training output.

Closed by: the per-model *measurement* obligation (train from a real random init;
assert measured convergence + inference performance) transfers to new
[Phase 33](README.md#legacy-to-new-phase-map)'s
`jitml-model-convergence` stanza, and the negative-control that must reject the
artifact-read shortcut, the expert-controller reward, and any `assertRlRowEvidence`
case never run on real output is the
[Phase 32](README.md#legacy-to-new-phase-map) `jitml-negative-controls`
suite. This sprint returned to Done after its rows drive real training and both
suites are green on `linux-cpu`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
