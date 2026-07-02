# Phase 28: Per-Model Integration & Row-Complete E2E

**Status**: Blocked
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [development_plan_standards.md](development_plan_standards.md), [phase-27-demo-all-model-rendering.md](phase-27-demo-all-model-rendering.md), [phase-29-linux-cuda-product-lane.md](phase-29-linux-cuda-product-lane.md), [../documents/engineering/product_completion_contract.md](../documents/engineering/product_completion_contract.md), [../documents/engineering/unit_testing_policy.md](../documents/engineering/unit_testing_policy.md), [../documents/engineering/purescript_frontend.md](../documents/engineering/purescript_frontend.md)
**Generated sections**: none

> **Purpose**: Every product row owns a named integration test and e2e test that
> exercises real training, checkpointing, and demo rendering on `linux-cpu`, and
> the coverage report fails naming any missing row/test pair.

## Phase State

⏸️ **Blocked by** Phase `27`.

**Validation substrate**: `linux-cpu` only.

## Objective

Every `ProductRow` in the canonical registry is bound to one integration test id
and one e2e test id, both keyed by `rowId`, and both drive the real
training/checkpoint/inference and live-demo paths rather than a representative
smoke check. The integration matrix folds `allProductRows`, dispatches per
family (`Supervised`, `ReinforcementLearning`, `AlphaZero`, `Tuning`) to real
training-then-checkpoint-then-inference-before-completion-rejection assertions,
and the Playwright suite generates one live test per row from the same generated
registry. A green pass count without row identity does not close this phase: the
report card enumerates every row and fails on any uncovered `rowId`/`testId`
pair.

## Sprint 28.1: Row-Keyed Integration Matrix [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Phase `27`
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

### Remaining Work

- Implement `RowAssertions.hs` (`paramHash`, `assertLearnedStateChanged`,
  `assertRealLoss`) and the per-family dispatch in `test/integration/Main.hs`.
- Add the uncovered-pair report and remove any representative-only workflow
  closure from the integration stanza.

## Sprint 28.2: Row-Complete Playwright [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Sprint `28.1`
**Implementation**: `playwright/jitml-demo.spec.ts`, `src/JitML/Test/LivePlan.hs`, `src/JitML/App.hs`
**Docs to update**: `../documents/engineering/purescript_frontend.md`, `../documents/engineering/unit_testing_policy.md`

### Objective

The live demo has one Playwright test per product row, generated from the same
generated registry the integration matrix uses, and each test renders the row's
trained artifact against a live edge with fail-closed negative coverage.

### Deliverables

- `playwright/jitml-demo.spec.ts` loads the product rows from the generated
  contract registry and generates one test per row, titled by the row's
  `prowE2eTest` id, with family-specific renderer assertions (supervised
  prediction panel, RL rollout/return panel, AlphaZero board/policy panel,
  tuning trial-table panel).
- Each generated test asserts fail-closed negatives: missing artifact, untrained
  checkpoint, partial/failed-provenance checkpoint, missing cluster, and
  unsupported substrate each render the fail-closed state instead of a stale or
  synthetic panel.
- `src/JitML/Test/LivePlan.hs` exposes a substrate-parametrized `LivePlan` and
  `src/JitML/App.hs` wires the live Playwright run into
  `jitml test jitml-e2e --live --linux-cpu`, launching or selecting the live
  cluster and binding the run to `linux-cpu`.
- A fake browser-runtime route test remains a structural test only and cannot
  satisfy a row's `e2eTest` evidence.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-e2e --live --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Remaining Work

- Generate the per-row Playwright suite from the registry and add the
  fail-closed negative cases.
- Land the substrate-parametrized `LivePlan` and the `jitml test jitml-e2e
  --live --linux-cpu` wiring in `src/JitML/App.hs`.

## Sprint 28.3: linux-cpu Report Card [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Sprint `28.2`
**Implementation**: `src/JitML/Test/Report.hs`, `DEVELOPMENT_PLAN/attestations/linux-cpu-report-card.md`
**Docs to update**: `system-components.md`, `README.md`

### Objective

The `linux-cpu` report card is a per-row evidence table that fails on any missing
cell, and the committed attestation reflects a real, row-complete `linux-cpu`
run.

### Deliverables

- `src/JitML/Test/Report.hs` renders one row per `ProductRow` with the columns
  `Catalog` (generated matrix parity), `Integration` (real learned-state-changed
  test), `E2E` (live per-row Playwright test), `Negative` (fail-closed cases),
  and `Lane` (`linux-cpu` validated), and **fails on any missing cell**.
- The report distinguishes an explicitly non-product row from a missing-evidence
  row so a black-box/non-ANN row is never silently counted as complete.
- `DEVELOPMENT_PLAN/attestations/linux-cpu-report-card.md` is committed only
  after the phase validation passes, and it carries dated, row-keyed evidence for
  the full matrix.

### Validation

```bash
docker compose run --rm jitml jitml test all --live --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Remaining Work

- Extend the report schema to the five-column per-row evidence table and the
  non-product classification.
- Regenerate and commit the `linux-cpu` attestation after the row-complete
  integration and e2e stanzas pass.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/unit_testing_policy.md` — row-keyed integration/e2e
  coverage ownership and the uncovered-pair failure rule.
- `documents/engineering/purescript_frontend.md` — per-row generated Playwright
  suite and fail-closed negative rendering.
- `documents/engineering/product_completion_contract.md` — integration/e2e
  evidence fields satisfied per row on `linux-cpu`.

**Product docs to create/update:**
- `README.md` — test-stanza descriptions for the row-keyed `jitml-integration`
  and `jitml-e2e` matrices.

**Cross-references to add:**
- Link the committed `linux-cpu` attestation from Phase `31`.
