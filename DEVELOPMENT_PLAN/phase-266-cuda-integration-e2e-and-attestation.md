# Phase 266: CUDA Integration, E2E, and Attestation

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: CUDA Integration, E2E, and Attestation. Single-session phase migrated from legacy Sprint 29.3 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done** (2026-08-22). `jitml test all --linux-cuda` runs every CUDA-supported
product row for real through the training, checkpoint, integration, and e2e
paths, and the refreshed `linux-cuda` attestation records that run rather than
the withdrawn 2026-07-10 counts. The gate is green end to end: **10 / 10**
stanzas, `jitml-integration` **197 / 197**, and the live Playwright product
matrix **PASS** with **77** browser tests covering **55** distinct
`e2e.product.*` row selectors.

What blocked this phase was not row coverage but a defect in the device path.
`JitML.Engines.Loader.ensureKernelArtifact` runs on **every** device operation,
not only on a cache miss, so the Sprint `78.1` toolchain-validity check forked
`nvcc --version` once per kernel launch — measured at **20,692** spawns in 60 s
of `linux-cuda` PPO rollout, none of them a compile. That put the live RL
workflow past its 600 s placement budget and made `jitml-integration` a 21.2-hour
stanza. The probe is now resolved once per substrate per process; the per-artifact
sidecar comparison that actually enforces the upgrade gate is unchanged, and a
`jitml-unit` case drives 32 cache hits through a PATH-shimmed `nvcc` and fails if
it runs more than once.

The effect is measured, not inferred: `live daemon places StartRLRun by substrate`
went from a hard 600 s timeout to **96.33 s**, `live PPO cartpole convergence`
from **2766.89 s** to **339.11 s**, and the `jitml-integration` stanza from
**21.2 h** to **7.9 h**.

### Historical Phase State

> 📋 **Planned** (2026-08-19). Every upstream dependency is `Done` and this phase
is the first executable owner of the open chain. Its own obligation — a
row-complete `linux-cuda` lane attested from real evidence — is not yet met: the
`55 / 55` and `71 / 71` counts in `### Historical Validation` remain
**withdrawn**, and the 2026-07-10 evidence stands only for the surface it
exercised.

> ⏸️ **Blocked** (reopened 2026-08-16 under standards rule `C`). This phase attests
a row-complete `linux-cuda` lane, and its own `### Historical Validation` already
records the `55 / 55` and `71 / 71` counts as **withdrawn**. The 2026-08-16
measured lane run reported `rows: 55`, `eligible: 50`, `unsupported: 0`,
`errors: 5`, so the lane is not row-complete and this phase cannot hold `Done`
on that obligation.

## Sprint 266.1: CUDA Integration, E2E, and Attestation [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Engines/Loader.hs`, `test/unit/Main.hs`, `test/integration/Main.hs`, `test/e2e/Main.hs`, `playwright/jitml-demo.spec.ts`, `DEVELOPMENT_PLAN/attestations/`
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
- Live Playwright renders every generated ProductRow artifact selector as
  eligible: **77** browser tests pass, covering **55** distinct row-specific
  `e2e.product.*` selectors.
- The device path resolves the artifact-toolchain probe once per substrate per
  process. `ensureKernelArtifact` runs per device operation rather than per
  compile, so an unmemoised probe forked `nvcc --version` once per kernel launch;
  a `jitml-unit` case drives 32 cache hits through a PATH-shimmed `nvcc` and
  fails if it is invoked more than once.
- The refreshed CUDA report card in
  `DEVELOPMENT_PLAN/attestations/linux-cuda-report-card.md` records the
  2026-08-22 measured lane run.

### Validation

```bash
docker compose run --rm jitml-cuda jitml test all --linux-cuda
docker compose run --rm jitml-cuda jitml test jitml-e2e --linux-cuda
docker compose run --rm jitml-cuda jitml test jitml-e2e --live --linux-cuda
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

2026-08-22 validation passed on the current source.

| Gate | Result |
|---|---|
| `jitml internal train-and-publish-product-rows --linux-cuda` | `rows: 55`, `eligible: 55`, `unsupported: 0`, `errors: 0` |
| `jitml test all --linux-cuda` | exit `0` — **10 / 10** stanzas: `jitml-unit` **902 / 902**, `jitml-integration` **197 / 197**, `jitml-sl-canonicals` **36 / 36**, `jitml-rl-canonicals` **47 / 47**, `jitml-hyperparameter` **26 / 26**, `jitml-backends` **28 / 28**, `jitml-daemon-lifecycle` **54 / 54**, `jitml-e2e` **30 / 30**, `jitml-negative-controls` **3 / 3**, `jitml-model-convergence` **111 / 111** |
| `jitml test jitml-e2e --linux-cuda` | exit `0` |
| `jitml test jitml-e2e --live --linux-cuda` | exit `0` — `jitml-integration` **197 / 197**, Haskell e2e **30 / 30**, `jitml-e2e-playwright` **PASS** (**77** browser tests, **55** `e2e.product.*` selectors) |
| `jitml docs check` | PASS |
| `jitml check-code` | PASS |

Measured effect of the loader fix on the live path, same commands and same
cluster before and after: `live daemon places StartRLRun by substrate` **FAIL
(600 s timeout) → OK (96.33 s)**; `live PPO cartpole convergence` **2766.89 s →
339.11 s**; `jitml-integration` stanza **21.2 h → 7.9 h**; `nvcc` spawns per 60 s
of CUDA PPO rollout **20,692 → 1**.

### Historical Validation (2026-07-10, withdrawn counts)

2026-07-10 validation passed on the then-current source: `jitml test all
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
