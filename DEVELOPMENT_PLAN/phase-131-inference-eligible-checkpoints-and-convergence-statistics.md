# Phase 131: Inference-Eligible Checkpoints and Convergence Statistics

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Inference-Eligible Checkpoints and Convergence Statistics. Single-session phase migrated from legacy Sprint 10.10 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 131.1: Inference-Eligible Checkpoints and Convergence Statistics [✅ Done]

**Status**: Done on its retained convergence-statistics and structural-completion surface
**Implementation**: `src/JitML/Checkpoint/Format.hs`,
`src/JitML/Checkpoint/Store.hs`, `src/JitML/App.hs`,
`src/JitML/Observability/TensorBoard.hs`,
`src/JitML/Observability/TbSidecar.hs`
**Docs to update**: `../documents/engineering/checkpoint_format.md`,
`../documents/engineering/training_metrics_and_splits.md`,
`../documents/engineering/purescript_frontend.md`, `system-components.md`

### Objective

Record fixed-budget completion and convergence statistics in the checkpoint
model and introduce the structural distinction between inspectable candidates
and completed manifests. That in-memory refinement is necessary but not
sufficient for eligibility: Store alone admits the opaque consumer value from
exact persisted reads, and Sprint `10.6` makes supervised V1 inspection only.

### Deliverables

- Add completed-budget fields, convergence-statistics records, TensorBoard
  scalar run metadata, and readiness witness data to the manifest contract.
- Introduce the hidden structural completion refinement and the
  completion/convergence predicates consumed by persisted Store admission.
- Refactor `eval`, `inference run`, demo handlers, `rl eval`, `rl rollout`, and
  AlphaZero game endpoints to accept Store's opaque admitted-completed value,
  not raw weights or a caller-built manifest.
- Preserve raw manifest loading for inspection/resume without allowing it to
  flow into inference.

### Historical Validation

- `docker compose run --rm jitml jitml test jitml-unit --linux-cpu`
- `docker compose run --rm jitml jitml test jitml-integration --linux-cpu`
- `docker compose run --rm jitml jitml test jitml-e2e --linux-cpu`
- `docker compose run --rm jitml jitml docs check`

### Current Validation State

- `docker compose run --rm jitml cabal test jitml-unit --test-show-details=direct`
  passed **224 / 224**.
- `docker compose run --rm jitml cabal test jitml-e2e --test-show-details=direct`
  passed **23 / 23**.
- `docker compose run --rm jitml cabal run jitml -- test jitml-e2e --linux-cpu`
  passed through the project wrapper with **23 / 23** tests.
- `docker compose run --rm jitml cabal test jitml-integration --test-show-details=direct`
  passed the non-live checkpoint loader cases, including an
  infer-before-complete rejection for a manifest without
  `CompletedTraining`. The remaining integration failures were the expected live
  cluster failures from missing `.build/runtime/cluster-publication.json`.
- `docker compose run --rm jitml cabal test jitml-integration --test-show-details=direct`
  later passed **53** non-live cases after the checkpoint-browser selector
  gained a negative test that omits manifests without `CompletedTraining`; the
  **19** live cases still fail fast without a bootstrapped cluster publication.
- `./bootstrap/linux-cpu.sh up` completed the live `linux-cpu` rollout
  (**111** steps), and
  `docker compose run --rm jitml cabal test jitml-integration --test-show-details=direct`
  passed **72 / 72** against the bootstrapped cluster, including live checkpoint
  snapshot, GC, inference, TensorBoard sidecar, tune, RL, and AlphaZero
  checkpoint paths.
- `docker compose run --rm jitml cabal run jitml -- docs check` passed
  (`docs check: ok`).
- `docker compose run --rm jitml cabal run jitml -- check-code` passed
  (`check-code: ok`).
- `docker compose run --rm jitml jitml test all --live --linux-cpu` passed the
  aggregate lane with **8 / 8** stanzas green. The run includes live checkpoint
  snapshot, GC, inference, TensorBoard sidecar, tuning, RL, AlphaZero
  checkpoint paths, and `jitml-backends` **23 / 23** through the
  `InferenceEligibleCheckpoint` gate.
- Historical Live Playwright passed **15 / 15** against the rebuilt
  `linux-cpu` edge after reseeding eight pre-V2 demo manifests. That result does
  not establish current supervised eligibility.

### Remaining Work

- None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
