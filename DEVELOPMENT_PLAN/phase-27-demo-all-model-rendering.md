# Phase 27: Demo All-Model Rendering

**Status**: Blocked
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [development_plan_standards.md](development_plan_standards.md), [phase-26-alphazero-real-self-play.md](phase-26-alphazero-real-self-play.md), [phase-28-per-model-integration-and-e2e.md](phase-28-per-model-integration-and-e2e.md), [../documents/engineering/product_completion_contract.md](../documents/engineering/product_completion_contract.md), [../documents/engineering/purescript_frontend.md](../documents/engineering/purescript_frontend.md), [../documents/engineering/cli_command_surface.md](../documents/engineering/cli_command_surface.md)
**Generated sections**: none

> **Purpose**: The browser demo renders every product row from a real
> inference-eligible trained artifact with a model-appropriate renderer, and
> fails closed when no eligible artifact exists.

## Phase State

⏸️ **Blocked by** Phase `26`.

**Validation substrate**: `linux-cpu` only.

## Objective

The browser product matrix proves actual model rendering from real trained
weights. Every `ProductRow` is served from an inference-eligible checkpoint that
`jitml internal train-and-publish-product-rows` produced by training the row for
real; no seed-demo checkpoint, synthetic seeded artifact, or static generated
row name reaches a product panel. Each row exposes a live selector whose state
is one of eligible, training-required, unsupported, or error; each row renders
with a model-appropriate renderer that displays the trained artifact's inputs,
outputs, and convergence/provenance metadata; and the browser fails closed with
a `503 checkpoint-required` response whenever no eligible artifact exists for the
requested row. A unit guard plus a live Playwright guard prove the browser can
never serve a `*-demo-weights` artifact for a product row.

## Sprint 27.1: Train-and-Publish + Artifact Selectors [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Phase `26`
**Implementation**: `src/JitML/App.hs`, `src/JitML/Web/Contracts.hs`, `src/JitML/Web/Server.hs`, `web/src/Panels/Checkpoints.purs`
**Docs to update**: `../documents/engineering/cli_command_surface.md`, `../documents/engineering/purescript_frontend.md`

### Objective

`jitml internal train-and-publish-product-rows --linux-cpu` trains each product
row for real and publishes an inference-eligible checkpoint, retiring
seed-demo-checkpoints from the product path. Checkpoint browse groups the
published artifacts by `ProductRow` and exposes per-row selector state.

### Deliverables

- `jitml internal train-and-publish-product-rows --<substrate>` enumerates the
  typed product matrix, runs each row through the real training and checkpoint
  path for its declared fixed budget, and publishes an `InferenceEligible`
  checkpoint per supported row.
- Seed-demo checkpoints and synthetic seeded artifacts are removed from the
  product publish path; the command is the sole producer of product-row demo
  artifacts.
- Checkpoint browse in the server contract groups eligible artifacts by
  `ProductRow`, and each row carries a selector state of `eligible`,
  `training-required`, `unsupported`, or `error`.
- A static generated row list cannot be counted as demo proof; only an
  artifact-backed selector satisfies a row's `demoEvidence` field.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml test jitml-e2e --linux-cpu
docker compose run --rm jitml jitml docs check
```

### Remaining Work

- Implement `train-and-publish-product-rows` and wire it into `src/JitML/App.hs`.
- Replace static product-matrix proof with `ProductRow`-grouped artifact-backed
  selectors and assert every selector state.
- Move retired seed-demo-checkpoint helpers into the pending-removal ledger.

## Sprint 27.2: Row-Specific Renderers [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Sprint `27.1`
**Implementation**: `web/src/Panels/Mnist.purs`, `web/src/Panels/Cifar.purs`, `web/src/Panels/Rl.purs`, `web/src/Panels/Replay.purs`, `web/src/Panels/Connect4.purs`, `src/JitML/Web/Contracts.hs`
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
docker compose run --rm jitml jitml test jitml-e2e --linux-cpu
docker compose run --rm jitml jitml lint purescript
docker compose run --rm jitml jitml check-code
```

### Remaining Work

- Add the missing row-specific panels and per-family metadata contracts.
- Remove any remaining seeded synthetic demo checkpoints from product evidence.

## Sprint 27.3: Browser Fail-Closed [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Sprint `27.2`
**Implementation**: `src/JitML/Web/Server.hs`, `playwright/jitml-demo.spec.ts`, `test/e2e/Main.hs`
**Docs to update**: `../documents/engineering/purescript_frontend.md`, `../documents/engineering/product_completion_contract.md`

### Objective

The browser never substitutes a fake response when a trained artifact is missing.
A product row with no inference-eligible checkpoint returns
`503 checkpoint-required`, and no product row is ever served from a
`*-demo-weights` artifact.

### Deliverables

- The server returns `503 checkpoint-required` for a product row that has no
  inference-eligible artifact, and the panel renders the fail-closed state.
- E2E covers missing artifact, untrained artifact, partial checkpoint, missing
  cluster, and unsupported substrate states.
- A unit guard and a live Playwright guard prove the browser can never serve a
  `*-demo-weights` artifact for a product row.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-e2e --linux-cpu
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml check-code
```

### Remaining Work

- Add the fail-closed server responses and matching UI states.
- Add the unit and Playwright `*-demo-weights` guards and the negative-state e2e
  cases.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/purescript_frontend.md` — row-complete artifact-backed
  rendering and fail-closed browser states.
- `documents/engineering/cli_command_surface.md` — `train-and-publish-product-rows`
  command surface.
- `documents/engineering/product_completion_contract.md` — demo-contract closure
  with fail-closed `503 checkpoint-required` semantics.

**Product docs to create/update:**
- `README.md` — demo section describing artifact-backed all-model rendering.

**Cross-references to add:**
- Link the demo rendering requirements from the runtime and service control docs.
