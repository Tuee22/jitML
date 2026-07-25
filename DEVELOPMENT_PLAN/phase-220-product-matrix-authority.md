# Phase 220: Product Matrix Authority

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Product Matrix Authority. Single-session phase migrated from legacy Sprint 19.1 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 220.1: Product Matrix Authority [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Product/Matrix.hs`, `src/JitML/Product/Convergence.hs`, `src/JitML/Web/Contracts.hs`, `web/src/Generated/Contracts.purs`, `test/unit/Main.hs`
**Docs to update**: `../README.md`, `../documents/engineering/product_completion_contract.md`, `system-components.md`

### Objective

`src/JitML/Product/Matrix.hs` holds the single `ProductRow` ADT and the
`MatrixFloor` that pins the ambitious surface. `src/JitML/Web/Contracts.hs`
(`modelMatrixLines`), `src/JitML/Test/WorkflowMatrix.hs`, the README canonical
tables, and the report card are generated from or parity-tested against this one
registry rather than hand-maintained model-name lists.

### Deliverables

- A `ProductRow` ADT whose fields are `rowId`, `family`, `rowClass`,
  `implementation`, `experimentConfig`, a per-row `ConvergenceBar`, `deviceClaim`,
  phantom-tagged evidence handles (training, device, checkpoint, demo evidence
  parameterised by model state so a `Declared` row cannot carry a
  completed-training witness), `integrationTest`, `e2eTest`, and `demoPanel`.
- `src/JitML/Product/Convergence.hs` defines `ConvergenceBar` so every row pins
  its own metric and literature target minus slack — accuracy for the image and
  MLP rows, RMSE for California Housing regression, median evaluation return per
  `(env, algo)` for RL, and arena win-rate per AlphaZero game — instead of one
  shared representative threshold (closes gaps G3/G4).
- A `MatrixFloor` pins the ambitious surface and fails any registry that drops a
  member: the eleven supervised rows (MNIST shallow MLP, MNIST deep MLP with
  BatchNorm and Dropout, MNIST LeNet-5-variant CNN, Fashion-MNIST shallow MLP,
  Fashion-MNIST small ResNet, CIFAR-10 ResNet-20, CIFAR-10 ResNet-56, CIFAR-100
  Wide ResNet-28-10, CIFAR-10 small ViT, Tiny ImageNet ResNet-50, California
  Housing tabular-regression MLP); the seven RL environments (CartPole-v1,
  MountainCar-v0, Acrobot-v1, Pendulum-v1, LunarLander-v2 discrete,
  KeyDoorGrid-v0, GridWorld-Deterministic-v0); the stable-baselines3 algorithm
  family (PPO, A2C, TRPO, MaskablePPO, RecurrentPPO, DQN, QR-DQN, DDPG, TD3, SAC,
  CrossQ, TQC, ARS, HER) plus AlphaZero self-play; the four AlphaZero games
  (Connect 4, Othello, Hex, Gomoku); and hyperparameter tuning.
- Generated browser contracts (`web/src/Generated/Contracts.purs` via
  `modelMatrixLines`) and report-card rows read from this registry.
- A unit test fails on duplicate row ids, undocumented rows, documented-but-
  unregistered rows, rows missing an integration or e2e test id, and any
  `MatrixFloor` violation.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-unit --linux-cpu  # passed, 241/241 tests
docker compose run --rm jitml jitml docs check                  # passed
docker compose run --rm jitml jitml check-code                  # passed
```

### Closure Evidence

- The `ProductRow` ADT, the single registry, and the `MatrixFloor` are real and
  met; the caveat is confined to the per-row **convergence-bar deliverable**. The
  bar is not derived from any external target at runtime: the checkpoint writer
  constructs each bar with `mkConvergenceBar name Maximise value 0.0`
  (`src/JitML/App.hs` `convergenceObservationsForMetrics` ~line 3597), so the
  threshold equals the measured value and `evaluateConvergence` evaluates
  `value >= value` (`src/JitML/Product/Convergence.hs:104`) — a slack-0 tautology
  that passes every row. Closed by Phase `32`, which moves the literature target
  into a frozen `src/JitML/Product/ExternalBars.hs` constant never derived from
  the measured value; the negative-control validation that shuts this gap is the
  `jitml-negative-controls` suite rejecting a bar set equal to its own measured
  value, and the per-row check is exercised by the `jitml-model-convergence`
  suite (Phase `33`).

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
