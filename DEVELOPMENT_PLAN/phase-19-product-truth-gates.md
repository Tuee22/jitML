# Phase 19: Product Truth Gates & Registry

**Status**: Active
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [development_plan_standards.md](development_plan_standards.md), [phase-20-de-fossilization-and-scaffold-lint.md](phase-20-de-fossilization-and-scaffold-lint.md), [../README.md](../README.md), [../documents/engineering/product_completion_contract.md](../documents/engineering/product_completion_contract.md), [../documents/engineering/unit_testing_policy.md](../documents/engineering/unit_testing_policy.md)
**Generated sections**: none

> **Purpose**: Install one typed product-truth registry and machine-checkable
> gates so no fake, deterministic, static, seeded, or representative evidence can
> satisfy the documented model product contract, and so the ambitious model
> surface cannot be narrowed away by a later agent.

## Phase State

🔄 **Active**. The 2026-07-01 model-runtime audit reopened product closure and
chose to implement the documented surface for real — real deep architectures,
real per-substrate conv/attention kernels, real cuBLAS/cuDNN invocation — rather
than narrow the docs. Phases `0`–`18` remain historical evidence for their owned
surfaces, but the no-caveat product claim is not restored until Phases `19`–`31`
close in numerical order. This phase builds the enforcement spine every later
product phase is validated against.

**Validation substrate**: `linux-cpu` only.

## Objective

The repository owns one typed product-truth registry. Every documented model
row, every generated browser contract line, every README canonical table, and
every report-card row is generated from or parity-tested against that single
registry, and each row pins its own convergence obligation. A `MatrixFloor`
holds the ambitious surface — all eleven supervised rows, seven reinforcement
learning environments, the full stable-baselines3 algorithm family plus
AlphaZero, four AlphaZero games, and hyperparameter tuning — so a future agent
cannot delete rows to make closure cheaper. A separate typed phase-status
registry is the single source of Phase `19`–`31` sprint status, and `jitml docs
check` rejects any product-closure claim in governed docs while that registry
reports an unfinished product phase.

The forbidden-scaffold import lint is *not* owned here: the worktree must first
de-fossilize its scaffold helpers, so that enforcement is owned by Phase `20`.
This phase establishes the matrix floor, the per-row convergence bars (closing
gaps G3/G4 of the approved plan), and the status-truth gate that the rest of the
chain depends on.

## Sprint 19.1: Product Matrix Authority [🔄 Active]

**Status**: Active
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
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Remaining Work

- Implement the typed registry, `ConvergenceBar`, and `MatrixFloor`.
- Invert the dependency so `modelMatrixLines`, `WorkflowMatrix.hs`, the README
  tables, and the report card are generated from or parity-tested against the
  registry.
- Add the drift tests for duplicate, undocumented, unregistered, test-id-missing,
  and floor-violation rows.

## Sprint 19.2: Phase Status Registry [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Sprint `19.1`
**Implementation**: `src/JitML/Product/PhaseStatus.hs`, `test/unit/Main.hs`
**Docs to update**: `development_plan_standards.md`, `00-overview.md`, `system-components.md`

### Objective

`src/JitML/Product/PhaseStatus.hs` is the single typed source of Phase `19`–`31`
sprint status. A parity test asserts the typed registry agrees with the `Status`
headers declared in each `phase-*.md`.

### Deliverables

- A typed `PhaseStatus` registry enumerates every product phase (Phases `19`–`31`)
  and each of its sprints with a `Done | Active | Planned | Blocked` value.
- A parity test parses the `**Status**` header of every `phase-*.md` sprint block
  and asserts it equals the typed registry entry; any drift is a failure.
- The registry exposes a total `allProductPhasesDone` predicate that later gates
  consume, defined only over Phases `19`–`31`.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Remaining Work

- Implement the typed phase-status registry.
- Add the parity test against the `phase-*.md` status headers.

## Sprint 19.3: Status Truth Enforcement [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Sprint `19.2`
**Implementation**: `src/JitML/Lint/Docs.hs`, `src/JitML/Docs/Check.hs`, `test/unit/Main.hs`
**Docs to update**: `README.md`, `00-overview.md`, `system-components.md`, `../documents/engineering/unit_testing_policy.md`

### Objective

Governed documentation cannot claim product closure while any product phase is
unfinished. `src/JitML/Lint/Docs.hs` scans governed docs for closure language and
`src/JitML/Docs/Check.hs` rejects it through `jitml docs check` unless the typed
`PhaseStatus` registry reports every product phase (Phases `19`–`31`) Done.

### Deliverables

- `jitml docs check` scans governed docs for closure claims — for example "all
  phases done", "no-caveat product complete", and "production ready" — and
  rejects them unless `allProductPhasesDone` is true for Phases `19`–`31`.
- Dated historical-evidence blocks that explicitly describe themselves as
  historical are exempt from the closure-claim rejection.
- A unit test asserts the scanner flags closure language while a product phase is
  Active or Blocked and passes only when the registry reports full closure.

### Validation

```bash
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml check-code
```

### Remaining Work

- Add the closure-claim scanner and the historical-evidence exemption.
- Wire the docs-check predicate to the typed `PhaseStatus` registry.
- Re-run the docs check after every later product phase changes status.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/product_completion_contract.md` — record the matrix
  floor and the per-row convergence bars as the binding closure surface.
- `documents/engineering/unit_testing_policy.md` — ownership of the matrix parity,
  phase-status parity, and closure-claim tests.
- `documents/engineering/system-components.md` (the `DEVELOPMENT_PLAN`
  `system-components.md` inventory) — add the new `src/JitML/Product/*` registry
  modules and the `src/JitML/Lint/Docs.hs` closure-claim scanner.

**Product docs to create/update:**
- `README.md` — reopened product status and the registry-backed canonical tables.

**Cross-references to add:**
- Add this phase to `README.md`, `00-overview.md`, `system-components.md`, and
  `development_plan_standards.md`.
</content>
</invoke>
