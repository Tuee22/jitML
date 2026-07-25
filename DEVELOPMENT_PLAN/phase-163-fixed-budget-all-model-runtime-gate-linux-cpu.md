# Phase 163: Fixed-Budget All-Model Runtime Gate (`linux-cpu`)

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Fixed-Budget All-Model Runtime Gate (linux-cpu). Single-session phase migrated from legacy Sprint 13.3 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 163.1: Fixed-Budget All-Model Runtime Gate (`linux-cpu`) [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/SL/`, `src/JitML/RL/`,
`src/JitML/Tune/`, `src/JitML/Checkpoint/`, `src/JitML/App.hs`,
`test/integration/Main.hs`, `test/sl-canonicals/Main.hs`,
`test/rl-canonicals/Main.hs`
**Docs to update**: `../documents/engineering/training_workloads.md`,
`../documents/engineering/training_metrics_and_splits.md`,
`../documents/engineering/checkpoint_format.md`,
`../documents/engineering/numerical_core.md`, `system-components.md`

### Objective

Close the `linux-cpu` runtime only when every supported model trains to its
fixed budget, writes convergence statistics into a checkpoint, reloads that
checkpoint, and runs evaluation/inference through Store's opaque
`AdmittedCompletedCheckpoint` boundary.

### Deliverables

- Run every canonical SL row through fixed-budget convergence, checkpoint reload,
  evaluation, inference eligibility, and TensorBoard metric emission.
- Run every RL algorithm row through fixed-budget training/eval/rollout,
  checkpoint reload, and convergence-statistics emission.
- Run AlphaZero Connect 4, Othello, Hex, and Gomoku through fixed self-play and
  arena budgets with legal move and win-rate metrics.
- Replace transport-smoke hardcoded inference checkpoints with trained artifacts
  produced by the matrix.

### Validation

- `docker compose run --rm jitml jitml test jitml-sl-canonicals --linux-cpu`
- `docker compose run --rm jitml jitml test jitml-rl-canonicals --linux-cpu`
- `docker compose run --rm jitml jitml test jitml-integration --linux-cpu`
- `docker compose run --rm jitml jitml test all --live --linux-cpu`
- `docker compose run --rm jitml jitml docs check`

### Current Validation State

- `docker compose run --rm jitml cabal test jitml-sl-canonicals jitml-rl-canonicals --test-show-details=direct`
  passed `jitml-sl-canonicals` **24 / 24** and `jitml-rl-canonicals`
  **31 / 31** on `linux-cpu`.
- The project-wrapper forms also passed on `linux-cpu`:
  `jitml-sl-canonicals` **24 / 24** and `jitml-rl-canonicals` **31 / 31**.
- `docker compose run --rm jitml cabal test jitml-integration --test-show-details=direct`
  first passed non-live integration and failed only on live tests because no
  `linux-cpu` cluster publication existed.
- `./bootstrap/linux-cpu.sh up` then completed the live `linux-cpu` rollout
  (**111** steps), and
  `docker compose run --rm jitml cabal test jitml-integration --test-show-details=direct`
  passed **72 / 72** against that bootstrapped cluster. This proves the current
  representative live workflow gates, including the new RL completion
  `MetricUpdate`/`CheckpointDoneRL` witness path, but it is not yet the
  all-model fixed-budget matrix.
- After the cluster came up,
  `docker compose run --rm jitml cabal test jitml-sl-canonicals jitml-rl-canonicals --test-show-details=direct`
  started `jitml-sl-canonicals` and passed **23 / 24** before the live all-row
  staged-artifact case failed because none of the canonical MNIST,
  Fashion-MNIST, CIFAR-10, CIFAR-100, Tiny ImageNet, or California Housing
  dataset blobs were staged in live MinIO. That is the current blocking input
  for the all-model SL runtime gate; no local dataset archives are present in
  the checkout.
- The stale live MNIST train artifacts were repaired by deleting the bad MinIO
  objects and re-uploading the canonical train image/label gzip files with
  `jitml internal upload-dataset`; the staged hashes matched
  `JitML.SL.Dataset.canonicalArtifactSha256For`.
- `docker compose run --rm jitml cabal test jitml-sl-canonicals --test-show-details=direct`
  then passed **24 / 24** against the live `linux-cpu` MinIO dataset state.
- `docker compose run --rm jitml cabal test jitml-rl-canonicals --test-show-details=direct`
  passed **31 / 31** after the live integration run.
- `docker compose run --rm jitml cabal run jitml -- docs check` passed
  (`docs check: ok`).
- `docker compose run --rm jitml cabal run jitml -- check-code` passed
  (`check-code: ok`).
- `docker compose run --rm jitml jitml test all --live --linux-cpu` passed the
  full aggregate lane with **8 / 8** stanzas green and populated report-card
  measurements: `sl_final_loss`, `rl_final_reward`, `alphazero_arena_win_rate`,
  `tune_best_objective`, `jit_cache_hit_rate`, `daemon_healthz`, and
  `browser_product_matrix`.

### Remaining Work

- None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
