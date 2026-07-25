# Phase 105: On-Policy Algorithm Metadata

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: On-Policy Algorithm Metadata. Single-session phase migrated from legacy Sprint 9.1 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 105.1: On-Policy Algorithm Metadata [✅ Done]

**Status**: Done
**Owned obligations after refactor**: code-surface only. The
per-algorithm per-environment run-to-run determinism plus
rule-conformance properties for the deterministic-stub rollout closed
on 2026-05-24 for PPO, A2C, TRPO, MaskablePPO, RecurrentPPO via
`AlgorithmModule.moduleRolloutGenerator` (no committed rollout-value
files per [../README.md → Snapshot targets → Numerical-fixture
prohibition](../README.md#snapshot-targets)). Real
clipped-surrogate-loss / GAE / KL-trigger update code through the live
CUDA JIT engine migrated to Phase `15` Sprint `15.8`.
**Implementation**: `src/JitML/RL/Algorithms.hs`,
`src/JitML/RL/Algorithms/{Ppo,A2c,Trpo,MaskablePpo,RecurrentPpo}.hs`,
`test/rl-canonicals/Main.hs`
**Docs to update**: `documents/engineering/training_workloads.md`

### Objective

Land the on-policy algorithm metadata rows; grow real algorithm modules
and full per-algorithm run-to-run trajectory determinism plus
rule-conformance property coverage per `### Remaining Work` below. No
committed trajectory `.txt` fixtures per [../README.md → Snapshot
targets → Numerical-fixture prohibition](../README.md#snapshot-targets).

### Deliverables

- `algorithmCatalog` includes on-policy rows for `PPO`, `A2C`, `TRPO`,
  `MaskablePPO`, and `RecurrentPPO`.
- Each row records the `OnPolicy` family and `algorithmReplayBased = False`.
- `renderAlgorithmCatalog` renders the table from the local metadata list.
- The five on-policy modules expose typed deterministic hyperparameter rows
  and per-seed trajectory transcripts through `AlgorithmModule`.

### Historical Validation

1. `cabal test jitml-rl-canonicals` verifies representative catalog
   entries.
2. Transferred live validation: each on-policy algorithm has a dedicated
   module with real loss / policy / rollout-buffer code, reaches the
   in-code reward threshold for its canonical environment (`median
   over k seeds ≥ literature_target − slack`, no committed
   per-substrate reward fixture), and two fresh same-substrate /
   same-seed runs produce bit-identical per-seed trajectories
   compared against each other.

### Remaining Work

- Per-algorithm + per-environment run-to-run determinism closed on
  2026-05-24 for each of the five on-policy modules (PPO, A2C, TRPO,
  MaskablePPO, RecurrentPPO) keyed to cartpole through
  `AlgorithmModule.moduleRolloutGenerator`; the rl-canonicals stanza
  enforces each by running the rollout twice in-process and asserting
  bit-identity between the two run outputs plus rule-conformance
  properties (every step legal under the env transition, terminal
  condition canonical). Per
  [../README.md → Snapshot targets → Numerical-fixture
  prohibition](../README.md#snapshot-targets), no `test/golden/rl/...`
  rollout-value files are committed; the legacy `test/golden/rl/`
  scaffolding is scheduled for deletion per
  [legacy-tracking-for-deletion.md → Pending Removal](legacy-tracking-for-deletion.md#pending-removal).
  Live measured cross-substrate runs from real CUDA training are owned
  by Phase `15` Sprint `15.8`.
- Replacement of the deterministic-fixture rollout with real
  clipped-surrogate-loss / GAE / KL-trigger update code through the live
  CUDA JIT engine is owned by
  [phase-15-linux-cuda-and-cluster-closure.md](README.md#legacy-to-new-phase-map)
  Sprint `15.8`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
