# Phase 266: CUDA Integration, E2E, and Attestation

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: CUDA Integration, E2E, and Attestation. Single-session phase migrated from legacy Sprint 29.3 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 266.1: CUDA Integration, E2E, and Attestation [✅ Done]

**Status**: Done
**Implementation**: `test/integration/Main.hs`, `test/e2e/Main.hs`, `playwright/jitml-demo.spec.ts`, `DEVELOPMENT_PLAN/attestations/`
**Docs updated**: `../documents/engineering/unit_testing_policy.md`, `../documents/engineering/purescript_frontend.md`, `DEVELOPMENT_PLAN/attestations/linux-cuda-report-card.md`

### Objective

`jitml test all --linux-cuda` runs every CUDA-supported product row for real
through the training, checkpoint, integration, and e2e paths. Live Playwright
hits the CUDA edge and renders row-specific trained artifacts from the published
checkpoint list, and the refreshed `linux-cuda` attestation records the
row-complete lane evidence.

### Deliverables

- `jitml test all --linux-cuda` passed every CUDA-supported product row through
  integration/e2e evidence, including the live WorkflowMatrix and the row-keyed
  ProductRow integration cases.
- `jitml test jitml-e2e --live --linux-cuda` selected the existing CUDA
  publication at edge `:9092`, ran the Haskell e2e stanza, and then ran the live
  Playwright product matrix against that edge.
- Live Playwright rendered every generated ProductRow artifact selector as
  eligible: **71 / 71** browser tests passed, including **55 / 55** row-specific
  `e2e.product.*` cases.
- The refreshed CUDA report card in
  `DEVELOPMENT_PLAN/attestations/linux-cuda-report-card.md` records the 2026-07-10
  Phase `29` validation.

### Validation

```bash
docker compose run --rm jitml-cuda jitml test all --linux-cuda
docker compose run --rm jitml-cuda jitml test jitml-e2e --linux-cuda
docker compose run --rm jitml-cuda jitml test jitml-e2e --live --linux-cuda
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

2026-07-10 validation passed on the current source: `jitml test all
--linux-cuda` passed **10 / 10** stanzas (`jitml-unit` **278 / 278**,
`jitml-integration` **137 / 137**, `jitml-sl-canonicals` **31 / 31**,
`jitml-rl-canonicals` **39 / 39**, `jitml-hyperparameter` **19 / 19**,
`jitml-backends` **22 / 22**, `jitml-daemon-lifecycle` **32 / 32**,
`jitml-e2e` **27 / 27**, `jitml-negative-controls` **3 / 3**, and
`jitml-model-convergence` **111 / 111**). Standalone CUDA e2e then passed
**27 / 27**. The live CUDA e2e gate selected the existing CUDA publication at
edge `:9092`, ran the checkpoint-backed Playwright product matrix with
**71 / 71** browser tests, and passed the Haskell e2e stanza with **27 / 27**.

### Closure Evidence

- **Closed Exit-Definition obligation (row-complete CUDA integration/e2e/
  attestation).** `jitml test all --linux-cuda` and the live Playwright product
  matrix must pass for every CUDA-supported row against checkpoints whose per-row
  convergence is really measured, and the refreshed `linux-cuda` attestation must
  record that real evidence rather than the withdrawn `55 / 55` / `71 / 71`
  counts.
- **Negative-control validation that closes it.** After Phases `19`–`28` re-close
  and Sprint `29.2` re-validates, re-run
  `docker compose run --rm jitml-cuda jitml test all --linux-cuda` and
  `docker compose run --rm jitml-cuda jitml test jitml-e2e --live --linux-cuda`,
  gated by the
  [`jitml-negative-controls`](README.md#legacy-to-new-phase-map) and
  [`jitml-model-convergence`](README.md#legacy-to-new-phase-map)
  suites, and re-commit the attestation only after they pass. Validation stays
  single accelerator: `linux-cuda` plus `linux-cpu`, never `apple-silicon`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
