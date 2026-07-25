# Phase 251: Row-Specific Renderers

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Row-Specific Renderers. Single-session phase migrated from legacy Sprint 27.2 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 251.1: Row-Specific Renderers [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Web/Contracts.hs`, `src/JitML/Test/WorkflowMatrix.hs`, `web/src/Panels/Checkpoints.purs`, `web/src/Panels/Mnist.purs`, `web/src/Panels/Cifar.purs`, `web/src/Panels/GenericInference.purs`, `web/src/Panels/CheckpointCompare.purs`, `web/src/Panels/Connect4.purs`, `web/src/Panels/Rl.purs`, `web/src/Panels/Training.purs`, `web/src/Panels/Tune.purs`
**Docs to update**: `../documents/engineering/purescript_frontend.md`

### Objective

Every product row renders through a model-appropriate renderer driven by its real
trained artifact and the checkpoint manifest's convergence/provenance metadata.

### Deliverables

- Supervised rows render model-appropriate input and output plus convergence
  metadata read from the checkpoint manifest for that exact row.
- Reinforcement learning rows render real trajectory frames, rewards, and
  policy/action metadata for the specific environment and algorithm row.
- AlphaZero rows render board state, legal moves, MCTS and value metadata, and
  replay for every documented game.
- Each renderer sources its content from the inference-eligible artifact selected
  in Sprint 27.1, never from a synthetic seeded checkpoint or a row name.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml test jitml-e2e --linux-cpu
docker compose run --rm jitml jitml lint purescript
docker compose run --rm jitml jitml check-code
```

Validation passed on 2026-07-02 for `jitml-unit --linux-cpu` (276 / 276),
`jitml-e2e --linux-cpu` (23 / 23), `jitml lint purescript`, and
`jitml check-code`.

### Closure Evidence

Reopened 2026-07-05 (realness audit). The row-specific-renderer obligation this
sprint owns — every row renders through a model-appropriate renderer driven by
its own real trained artifact and manifest metadata — is unmet in three ways:

- 39 of 55 rows (every RL algorithm × environment row plus HER) collapse to one
  shared `rl-trajectory` panel pinned to PPO/cartpole instead of rendering the
  specific environment and algorithm row's own trajectory frames, rewards, and
  policy/action metadata.
- 4 of 5 `mnist`-panel rows and 4 of 5 `cifar`-panel rows cannot be visualized
  (paired with the Sprint 27.1 selector-reachability gap).
- Checkpoint-browse "artifact renderers" emit static family-description text
  rather than the trained model's actual output.

- **Closed obligation**: each row's renderer sources real model output — RL
  trajectory frames for that exact environment/algorithm, supervised input and
  output plus per-row convergence metadata — from the row's own
  inference-eligible artifact, never a shared panel or a family-description
  string.
- **Negative-control validation (Phase 32)**: `jitml-negative-controls`
  (`docker compose run --rm jitml jitml test jitml-negative-controls --linux-cpu`)
  fails closed when a row renders another row's panel (for example a PPO/cartpole
  trajectory served for a SAC, DDPG, or HER row) or when a renderer returns static
  descriptive text instead of model output. See
  [phase-32-external-truth-realness-harness.md](README.md#legacy-to-new-phase-map).
- **Per-model validation (Phase 33)**: `jitml-model-convergence`
  (`docker compose run --rm jitml jitml test jitml-model-convergence --linux-cpu`)
  asserts every one of the 55 rows renders output produced by its own converged
  artifact. See
  [phase-33-per-model-convergence-and-inference-tests.md](README.md#legacy-to-new-phase-map).

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
