# Phase 255: Train-and-Publish + Artifact Selectors

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Train-and-Publish + Artifact Selectors. Single-session phase migrated from legacy Sprint 27.1 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 255.1: Train-and-Publish + Artifact Selectors [✅ Done]

**Status**: Done
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

Validation passed on 2026-07-02 for `jitml-unit --linux-cpu` (276 / 276),
`jitml-e2e --linux-cpu` (23 / 23), and `jitml docs check`.

### Closure Evidence

Reopened 2026-07-05 (realness audit). The selector obligation this sprint owns —
"Checkpoint browse in the server contract groups eligible artifacts by
`ProductRow`, and each row carries a selector state" backed by that row's own
inference-eligible artifact — is unmet: 4 of 5 `mnist`-panel rows and 4 of 5
`cifar`-panel rows cannot be selected, so only one row per panel is reachable and
the other eight rows resolve to no selectable artifact.

- **Closed obligation**: every `ProductRow` the browse groups — in particular all
  five rows of the `mnist` panel and all five of the `cifar` panel — must expose
  its own inference-eligible selector, and row selection must reach every row,
  not one aliased representative.
- **Negative-control validation (Phase 32)**: `jitml-negative-controls`
  (`docker compose run --rm jitml jitml test jitml-negative-controls --linux-cpu`)
  fails closed when two distinct rows resolve to the same selector or artifact, or
  when a row Phase 32 tags Declared is served as Real, proving no row is silently
  aliased to a shared checkpoint. See
  [phase-32-external-truth-realness-harness.md](README.md#legacy-to-new-phase-map).
- **Per-model validation (Phase 33)**: `jitml-model-convergence`
  (`docker compose run --rm jitml jitml test jitml-model-convergence --linux-cpu`)
  asserts each `mnist` and `cifar` row selects the checkpoint its own training
  produced. See
  [phase-33-per-model-convergence-and-inference-tests.md](README.md#legacy-to-new-phase-map).

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
