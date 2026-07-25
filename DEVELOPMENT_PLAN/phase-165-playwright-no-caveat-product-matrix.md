# Phase 165: Playwright No-Caveat Product Matrix

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Playwright No-Caveat Product Matrix. Single-session phase migrated from legacy Sprint 14.2 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 165.1: Playwright No-Caveat Product Matrix [✅ Done]

**Status**: Done (`linux-cpu` scope; re-validated 2026-06-26 — live Playwright 15/15)
**Implementation**: `playwright/jitml-demo.spec.ts`, `test/e2e/Main.hs`,
`src/JitML/Test/LivePlan.hs`
**Previously blocked by**: Sprint `14.1`; Phase `13` Sprint `13.1`
**Docs to update**: `documents/engineering/purescript_frontend.md`,
`documents/engineering/unit_testing_policy.md`, `system-components.md`

### Objective

Make Playwright the product proof that every supported model trains and exposes
its expected browser interaction.

### Deliverables

- Playwright starts every canonical SL training workflow, waits for live events,
  verifies convergence/status, opens the resulting checkpoint, and exercises the
  model-specific interaction.
- Playwright starts every RL algorithm family, observes live reward/trajectory
  frames, verifies animation updates, records a trajectory, and scrubs/replays it.
- Playwright launches AlphaZero self-play for every canonical adversarial game,
  plays against a checkpointed policy, verifies legal moves and visit
  distributions, and replays the completed game interactively.
- Playwright launches a bounded tuning sweep, verifies trial/final-frontier
  visualization updates, stops or kills a trial, promotes a trial, and verifies
  the promoted checkpoint is usable.
- The e2e driver owns an ephemeral Kind lifecycle and tears it down even on
  failure; tests fail fast if the live publication, bundle, route, or workload
  event stream is absent.

### Validation

This sprint closes the Playwright product matrix on `linux-cpu` (single host) per
standards rule M(b)/(d); the same matrix is re-run per-accelerator by Sprint
`15.20` (`linux-cuda`) and Sprint `16.11` (`apple-silicon`).

- `docker compose run --rm jitml jitml test jitml-e2e --linux-cpu`

### Remaining Work

None for the `linux-cpu` scope owned by Sprint `14.2`. The live Playwright matrix
now covers the portals/header surfaces, MNIST, generic inference, CIFAR/ImageNet,
checkpoint compare, Connect 4, Othello/Hex/Gomoku adversarial selectors,
checkpoint browse, workflow status, persisted transcript replay, RL, training,
and tuning panels against the live edge, and it passes **15/15**.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
