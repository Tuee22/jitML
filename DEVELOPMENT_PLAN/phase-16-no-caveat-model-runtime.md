# Phase 16: No-Caveat Model Runtime Closure

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md),
[development_plan_standards.md](development_plan_standards.md),
[system-components.md](system-components.md),
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md),
[phase-8-supervised-and-rl-framework.md](phase-8-supervised-and-rl-framework.md),
[phase-9-rl-catalog-alphazero-and-tuning.md](phase-9-rl-catalog-alphazero-and-tuning.md),
[phase-10-checkpointing-and-inference.md](phase-10-checkpointing-and-inference.md),
[phase-17-interactive-demo-and-playwright-closure.md](phase-17-interactive-demo-and-playwright-closure.md),
[phase-18-no-caveat-product-handoff.md](phase-18-no-caveat-product-handoff.md),
[../README.md](../README.md)
**Generated sections**: none

> **Purpose**: Own the no-caveat model-runtime closure that spans multiple
> earlier phases: every canonical SL model trains, checkpoints, evaluates, and
> infers through a substrate device; every RL algorithm and AlphaZero game runs
> through the production runtime; and tuning objectives measure real model
> outcomes without synthetic projections.

## Phase Status

🔄 **Active** (opened 2026-06-14; unblocked 2026-06-15). The no-caveat product target expands the
original Dense-MLP / current-RL closure into the full advertised model matrix.
Phase `8` Sprint `8.12` has landed the all-row SL trainable architecture and
typed RL event-payload surface consumed here. Phase `9` Sprint `9.12` provides
the RL/AlphaZero/tuning runtime surface, and Phase `10` Sprint `10.6` provides
checkpoint/inference support across every model family. Phase `16` now owns the
remaining cross-model runtime proof across those surfaces.

## Phase Summary

This phase is the cross-model runtime gate. It does not replace Phase `8`,
Phase `9`, or Phase `10`; it consumes their reopened deliverables and proves the
whole model matrix operates as one product surface. A model or algorithm is not
closed here until it can be started through the public `jitml` command or daemon
command envelope, run on the selected substrate, write a checkpoint, reload that
checkpoint, serve inference/evaluation, and produce deterministic same-substrate
results without an offline, echo, synthetic, or demo-only substitute.

## Sprint 16.1: Full Canonical Model Matrix Runtime 🔄

**Status**: Active
**Implementation**: `src/JitML/SL/`, `src/JitML/RL/`, `src/JitML/Tune/`,
`src/JitML/Checkpoint/`, `src/JitML/App.hs`
**Docs to update**: `documents/engineering/training_workloads.md`,
`documents/engineering/checkpoint_format.md`,
`documents/engineering/numerical_core.md`, `system-components.md`

### Objective

Close the end-to-end runtime matrix for every canonical model, not just the
currently narrowed Dense-MLP / selected-RL subset.

### Deliverables

- Every row in [../README.md → Canonical supervised learning problems](../README.md#canonical-supervised-learning-problems)
  is device-trainable on `apple-silicon`, `linux-cpu`, and `linux-cuda`, including
  Dense, DeepDense, Conv2D, residual, wide-residual, ResNet-50, and
  VisionTransformer rows.
- Every RL algorithm in the catalog trains/evaluates/rolls out through its
  production policy/runtime path. Algorithm-level synthetic reward projections
  and deterministic-stub loss fixtures no longer stand in for trained policy
  execution.
- AlphaZero uses real terminal evaluators, legal-game replay state, persistent
  MCTS state, device-backed policy/value leaf evaluation, and checkpoint-loaded
  policy/value nets for Connect 4, Othello, Hex, and Gomoku.
- Hyperparameter sweeps measure objectives from real trained SL/RL workloads,
  persist trial artifacts, and replay/resume from MinIO without LCG-derived or
  structurally tautological values.
- Checkpoints and inference support every model family the runtime trains,
  including architecture metadata, weight layouts, preprocessing metadata, and
  output decoding.
- The legacy ledger rows owned by reopened Phases `8`, `9`, and `10` move to
  `Completed` only after their replacements are validated through this matrix.

### Validation

- `docker compose run --rm jitml jitml test jitml-sl-canonicals --linux-cpu`
- `docker compose run --rm jitml jitml test jitml-rl-canonicals --linux-cpu`
- `docker compose run --rm jitml jitml test jitml-hyperparameter --linux-cpu`
- `docker compose run --rm jitml jitml test jitml-integration --linux-cpu`
- `docker compose run --rm jitml-cuda jitml test all --linux-cuda`
- `jitml test all --apple-silicon`
- `docker compose run --rm jitml jitml check-code`
- `docker compose run --rm jitml jitml docs check`

### Remaining Work

- Phase `8` provides the all-row trainable SL architecture runtime, live
  linux-cpu staged-byte smoke, and typed RL animation/replay event payloads.
  Phase `16` must consume that surface to run the full canonical SL catalog
  through median convergence, checkpoint reload, evaluation, and inference.
- Phase `9` provides the real RL/AlphaZero/tuning runtime surface. Phase `16`
  consumes that surface to retire the remaining catalog rollout compatibility
  helper and close the full checkpoint-backed train/evaluate/rollout matrix.
- Phase `10` provides checkpoint/inference metadata, weight layouts, and
  preprocessing/output decoders for every model family. Phase `16` consumes
  that surface across the full runtime matrix.

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/training_workloads.md` — no-caveat model matrix,
  per-family train/eval/rollout closure, AlphaZero game/runtime closure, and
  tuning objective semantics.
- `documents/engineering/checkpoint_format.md` — architecture-aware model
  metadata, weight layouts, preprocessing metadata, replay artifacts, and
  inference reload contracts for every model family.
- `documents/engineering/numerical_core.md` — trainable layer-family coverage
  and per-substrate forward/backward kernel requirements.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- Update `system-components.md` training, checkpoint, and test rows to mark this
  phase as the owner of no-caveat runtime closure.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
- [../README.md](../README.md)
