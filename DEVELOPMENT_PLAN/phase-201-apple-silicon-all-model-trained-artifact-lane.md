# Phase 201: Apple-Silicon All-Model Trained-Artifact Lane

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Apple-Silicon All-Model Trained-Artifact Lane. Single-session phase migrated from legacy Sprint 16.13 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 201.1: Apple-Silicon All-Model Trained-Artifact Lane [✅ Done]

**Status**: Done (closed 2026-06-26 on macOS `26.5` / Apple M1 Max / Metal 4)
**Implementation**: `test/integration/Main.hs`, `test/e2e/Main.hs`,
`playwright/jitml-demo.spec.ts`, `src/JitML/Test/WorkflowMatrix.hs`
**Docs to update**: `../documents/engineering/training_workloads.md`,
`../documents/engineering/unit_testing_policy.md`, `system-components.md`

### Objective

Re-run the expanded all-model trained-artifact runtime and browser matrix on a
real Apple Silicon host with the fixed Metal bridge.

### Deliverables

- Execute every fixed-budget SL/RL/AlphaZero model row on `apple-silicon`.
- Prove convergence-statistics checkpointing, TensorBoard emission, and
  inference eligibility through the host Metal daemon.
- Run the expanded Playwright matrix against the Apple edge.

### Validation

- `bootstrap/apple-silicon.sh up` — 109 live rollout steps reconciled; published
  `cluster-publication.json` with substrate `apple-silicon`, edge port `9091`,
  and all components `ready`.
- `bootstrap/apple-silicon.sh run-daemon` — host daemon acquired
  `inference.command.apple-silicon`, `training.host-command.apple-silicon`,
  `tune.host-command.apple-silicon`, and `rl.host-command.apple-silicon`;
  Metal acquisition reported `apple.metal-runtime=yes` and
  `apple.metal-bridge=yes`.
- `bootstrap/apple-silicon.sh test` — all **8/8** stanzas passed; live
  `jitml-integration` passed **72/72** and `jitml-backends --apple-silicon`
  passed **17/17**.
- `jitml internal seed-demo-checkpoints` — seeded MNIST, generic, CIFAR, and
  AlphaZero browser checkpoints for the live matrix.
- Live Playwright product matrix in the pinned Playwright browser container:
  **15/15** passed (`npx playwright test --config=playwright/playwright.config.ts`).

### Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
