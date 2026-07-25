# Phase 102: Fixed-Budget Training Witness and Inference-Ineligible Partial Models

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Fixed-Budget Training Witness and Inference-Ineligible Partial Models. Single-session phase migrated from legacy Sprint 8.14 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 102.1: Fixed-Budget Training Witness and Inference-Ineligible Partial Models [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Training/Budget.hs`,
`src/JitML/SL/Architecture.hs`, `src/JitML/RL/Framework.hs`,
`src/JitML/App.hs`, `src/JitML/Checkpoint/Format.hs`,
`src/JitML/Checkpoint/Store.hs`, `src/JitML/Work/Envelope.hs`
**Docs to update**: `../documents/engineering/training_metrics_and_splits.md`,
`../documents/engineering/training_workloads.md`,
`../documents/engineering/checkpoint_format.md`, `system-components.md`

### Objective

Represent learning completion as pure data. A model has a fixed, reproducible,
terminating `TrainingBudget`; completing that budget mints a `CompletedTraining`
witness. There is no pure value that can represent inference with random,
untrained, smoke-only, cancelled, skipped, or partially trained weights.

### Deliverables

- Define the shared `TrainingBudget` vocabulary for SL epochs, RL environment
  steps, AlphaZero self-play generations, and tuning trials.
- Define `CompletedTraining` as the only constructor path from a completed
  budget plus metric observations to checkpoint eligibility.
- Thread the witness through SL/RL/tuning event payloads without permitting
  inference surfaces to consume raw manifests or raw weights.
- Remove or quarantine existing direct inference paths that can bypass the
  completion witness.

### Validation

- `docker compose run --rm jitml jitml test jitml-unit --linux-cpu`
- `docker compose run --rm jitml jitml test jitml-sl-canonicals --linux-cpu`
- `docker compose run --rm jitml jitml test jitml-rl-canonicals --linux-cpu`
- `docker compose run --rm jitml jitml docs check`

### Current Validation State

- `docker compose run --rm jitml cabal test jitml-unit --test-show-details=direct`
  passed **224 / 224**.
- `docker compose run --rm jitml cabal test jitml-sl-canonicals jitml-rl-canonicals --test-show-details=direct`
  passed `jitml-sl-canonicals` **24 / 24** and `jitml-rl-canonicals`
  **31 / 31**.
- The wrapper form `docker compose run --rm jitml cabal run jitml -- test jitml-unit --linux-cpu`
  now passes and reports `jitml-unit: PASS` with **224 / 224** tests.
- `docker compose run --rm jitml cabal run jitml -- test jitml-sl-canonicals --linux-cpu`
  passed through the project wrapper with **24 / 24** tests.
- `docker compose run --rm jitml cabal run jitml -- test jitml-rl-canonicals --linux-cpu`
  passed through the project wrapper with **31 / 31** tests.
- `docker compose run --rm jitml cabal run jitml -- docs check` passed
  (`docs check: ok`).
- `docker compose run --rm jitml cabal run jitml -- check-code` passed
  (`check-code: ok`).
- `docker compose run --rm jitml cabal test jitml-sl-canonicals --test-show-details=direct`
  passed **24 / 24** after `CheckpointDone` gained the optional
  `CompletedTraining` witness in both text and proto event payloads.
- `docker compose run --rm jitml cabal test jitml-rl-canonicals --test-show-details=direct`
  passed **31 / 31** after `CheckpointDoneRL` gained the optional
  `CompletedTraining` witness in both text and proto event payloads.
- `docker compose run --rm jitml cabal test jitml-hyperparameter --test-show-details=direct`
  passed **16 / 16** after `SweepDone` gained the optional
  `CompletedTraining` witness and live tune sweep-done publishers populate it.
- `docker compose run --rm jitml cabal test jitml-rl-canonicals --test-show-details=direct`
  passed **31 / 31** after the worker RL runtime began writing final
  checkpoints under the daemon experiment hash, using RL environment-step budget
  units, publishing `MetricUpdate` convergence rows, and emitting
  `CheckpointDoneRL` with the same `CompletedTraining` witness.
- `docker compose run --rm jitml cabal test jitml-integration --test-show-details=direct`
  compiled the new live daemon assertion and passed all **52** non-live cases;
  the **19** live cases failed fast because no `.build/runtime/cluster-publication.json`
  is present.
- `docker compose run --rm jitml cabal test jitml-sl-canonicals --test-show-details=direct`
  passed **24 / 24** after successful SL training began carrying flattened
  trained weights, writing a supervised checkpoint, and emitting `CheckpointDone`
  with `CompletedTraining` from worker and host-Apple training paths.
- `docker compose run --rm jitml cabal test jitml-integration --test-show-details=direct`
  was rerun after the SL checkpoint producer change; it passed all **52**
  non-live cases and failed only the expected **19** no-cluster live cases.
- `docker compose run --rm jitml cabal test jitml-integration --test-show-details=direct`
  passed **53** non-live cases after adding the checkpoint-browser selector
  negative test: incomplete manifests are omitted from the `CheckpointList`
  summary while completed inference-eligible manifests remain visible. The
  **19** live cases still fail fast without `.build/runtime/cluster-publication.json`.
- `./bootstrap/linux-cpu.sh up` completed the live `linux-cpu` rollout
  (**111** steps) and wrote `.build/runtime/cluster-publication.json`.
- `docker compose run --rm jitml cabal test jitml-integration --test-show-details=direct`
  then passed **72 / 72** against the bootstrapped `linux-cpu` cluster. The
  live RL dispatch case observes `EpisodeDone`, `MetricUpdate
  median_final_reward`, and `CheckpointDoneRL completed-training` through
  Pulsar/MinIO; the broader live stanza also revalidated SL dispatch, live
  inference, tuning, GC, TensorBoard sidecars, and AlphaZero checkpoint
  round-trip.
- `docker compose run --rm jitml jitml test all --live --linux-cpu` passed the
  aggregate lane with **8 / 8** stanzas green, including `jitml-unit` **224 / 224**,
  `jitml-sl-canonicals` **24 / 24**, `jitml-rl-canonicals` **31 / 31**,
  `jitml-hyperparameter` **16 / 16**, `jitml-daemon-lifecycle` **32 / 32**,
  `jitml-e2e` **23 / 23**, `jitml-integration` **72 / 72**, and
  `jitml-backends` **23 / 23** on the real `linux-cpu` lane.

### Remaining Work

- None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
