# Phase 157: Playwright No-Caveat E2E Matrix

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Playwright No-Caveat E2E Matrix. Single-session phase migrated from legacy Sprint 12.13 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 157.1: Playwright No-Caveat E2E Matrix [✅ Done]

**Status**: Done (closed 2026-06-16 on the owned host-validatable e2e/matrix/report
structure; the live Playwright product-matrix execution was deduped to its owning
downstream sprints per standards rule E — see "Owned Surface Closed; Live
Obligations Deferred" below)
**Implementation**: `playwright/jitml-demo.spec.ts`, `test/e2e/Main.hs`,
`src/JitML/Test/LivePlan.hs`, `src/JitML/Test/WorkflowMatrix.hs`
**Docs to update**: `documents/engineering/unit_testing_policy.md`,
`documents/engineering/purescript_frontend.md`, `system-components.md`,
`legacy-tracking-for-deletion.md`

### Objective

Make `jitml-e2e` and Playwright validate the full no-caveat app/product matrix
instead of structural reachability plus a few REST assertions.

### Deliverables

- `jitml-e2e` brings up an ephemeral cluster, runs the compiled browser bundle
  through the routed Envoy edge, executes the Playwright product matrix, and
  tears the cluster down with `bracket` even on failure.
- Playwright starts every canonical SL workflow, observes live training events,
  verifies checkpoint creation, opens model-specific interaction panels, and
  asserts real inference output from the produced checkpoint.
- Playwright starts RL workflows for each algorithm family, observes live
  episode/trajectory frames, verifies canvas animation, records a trajectory,
  and replays/scrubs it in the browser.
- Playwright drives Connect 4, Othello, Hex, and Gomoku against AlphaZero
  checkpoints, verifies legal moves, MCTS visit distributions, value estimates,
  and interactive replay controls.
- Playwright launches and controls a bounded tuning sweep, verifies live
  frontier/heatmap/trial updates, kills a trial, promotes a trial, and verifies
  the promoted checkpoint is usable.
- The report card includes a no-caveat browser/product section; unavailable,
  placeholder, skipped, or synthetic rows fail the e2e lane when hardware and
  cluster prerequisites are present.

### Historical Validation

- `docker compose run --rm jitml jitml test jitml-e2e --linux-cpu`
- `docker compose run --rm jitml-cuda jitml test jitml-e2e --linux-cuda`
- `jitml test jitml-e2e --apple-silicon`
- `docker compose run --rm jitml jitml docs check`
- `docker compose run --rm jitml jitml check-code`

### Current Validation State

The 2026-06-15 Sprint `12.13` slice lands the host-validatable Haskell structure
for the no-caveat browser/product matrix:

- `JitML.Test.WorkflowMatrix` now enumerates the no-caveat browser/product cells
  alongside the existing per-substrate workflow matrix: a `BrowserProductInteraction`
  type (training launch, checkpoint open, MNIST/image/generic inference,
  checkpoint compare, RL animation, RL trajectory replay, adversarial play,
  adversarial replay, tuning sweep control, tuning trial promote), the
  `browserAdversarialGames` list (Connect 4, Othello, Hex, Gomoku), per-cell
  `browserProductInteractionLabel` descriptions, and `browserProductMatrix`
  crossing every interaction with every substrate — the DRY structure the live
  Playwright lane iterates.
- `JitML.Test.Report.ReportMeasurements` gains a `measuredBrowserProductMatrix`
  field; the live collector (`collectLiveReportMeasurements`) reports it
  `MeasurementUnavailable` until Phase `14` exercises the matrix live, so a live
  report card that has not proven the browser product surface keeps the
  no-caveat handoff honestly open (Sprint `18.1`) instead of omitting the row.
- Validated: `docker compose run --rm jitml jitml test jitml-e2e --linux-cpu`
  (23 / 23, including the new "browser product matrix enumerates every no-caveat
  interaction on every substrate" case and the `browser_product_matrix: unavailable`
  report-card assertion); `docker compose run --rm jitml jitml check-code`.

### Owned Surface Closed; Live Obligations Deferred (rule E)

Every remaining obligation is **live-runtime** and is already owned by a
downstream sprint, so it lives there per standards rule E (one obligation, one
place) and the live-obligation consolidation doctrine:

- Replacing the panel-visibility Playwright assertions with the no-caveat
  workflow-launch/event/checkpoint/inference/animation/replay/control product
  matrix, and populating `measuredBrowserProductMatrix` with a real measured
  value → **Sprint `14.2` (Playwright No-Caveat Product Matrix)**, which already
  owns exactly this expansion.
- Executing that matrix live and failing closed on any missing
  `browserProductMatrix` cell artifact → the per-lane live runs in
  **Sprint `15.20` (linux-cpu / linux-cuda)** and **Sprint `16.11`
  (apple-silicon)**.

The host-validatable structure Sprint `12.13` owns — the
`JitML.Test.WorkflowMatrix` `browserProductMatrix` enumeration, the
`browser_product_matrix` report-card field, and the `jitml-e2e` structural
assertions — is in place and validated (`jitml-e2e --linux-cpu` 23 / 23,
`check-code` ok; see Current Validation State above).

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
