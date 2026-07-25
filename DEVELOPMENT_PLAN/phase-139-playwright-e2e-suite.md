# Phase 139: Playwright E2E Suite

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Playwright E2E Suite. Single-session phase migrated from legacy Sprint 11.6 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 139.1: Playwright E2E Suite [✅ Done]

**Status**: Done
**Owned obligations after refactor**: code-surface only. Live edge-route
Playwright execution against the running cluster migrated to Phase `15`
Sprint `15.14`; Phase `17` Sprint `17.3` removed the inline
`page.setContent` DOM fallback.
**Implementation**: `playwright/jitml-demo.spec.ts`
**Docs to update**: `documents/engineering/purescript_frontend.md`,
`documents/engineering/unit_testing_policy.md`

### Objective

Land the Playwright scaffold for the future interactive panel suite.

### Deliverables

- `playwright/jitml-demo.spec.ts` exists as the current E2E scaffold.
- The live suite covers MNIST, CIFAR/ImageNet, Connect 4, RL trajectory,
  training, and tuning panel flows through the routed Webapp.
- The current `jitml-e2e` stanza validates the typed Playwright plan; live
  Playwright execution is owned by the explicit e2e orchestration path and the
  later product-matrix closure phases.
- Historical scaffold note: Playwright execution originally stayed out of the
  default local Cabal matrix until panels consumed live-backed state through
  `jitml-demo`; Sprint `12.13` / Phase `14` supersede that with the explicit
  live no-caveat product matrix. Static scaffold assertions remain covered by
  the current Haskell e2e and PureScript lint targets.

### Validation

1. `playwright/jitml-demo.spec.ts` remains present for the E2E runner.
2. `jitml-e2e` validates route, bucket, publication, contract, and
   report-card surfaces.
3. Later live validation: the explicit live orchestration path invokes
   Playwright against the live `jitml-demo` HTTP listener, and the
   canonical panel matrix passed 7 / 7 against the Apple Silicon edge
   route on 2026-06-04 after the offline fallback was removed.

### Remaining Work

- None remaining for Sprint `11.6`. `playwright/jitml-demo.spec.ts` now
  reads the live edge port from `cluster-publication.json`, fails fast
  when no live publication exists, and stays out of the default
  `cabal test all` matrix unless the live invocation is explicit.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
