# Phase 188: Linux-CUDA All-Model Trained-Artifact Lane

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Linux-CUDA All-Model Trained-Artifact Lane. Single-session phase migrated from legacy Sprint 15.21 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 188.1: Linux-CUDA All-Model Trained-Artifact Lane [✅ Done]

**Status**: Done (closed 2026-06-26 on the NVIDIA GeForce RTX 5090 host)
**Implementation**: `test/integration/Main.hs`, `test/e2e/Main.hs`,
`playwright/jitml-demo.spec.ts`, `src/JitML/Test/WorkflowMatrix.hs`
**Docs to update**: `../documents/engineering/training_workloads.md`,
`../documents/engineering/unit_testing_policy.md`, `system-components.md`

### Objective

Re-run the expanded all-model trained-artifact runtime and browser matrix on the
real `linux-cuda` lane after the `linux-cpu` baseline closes.

### Deliverables

- Execute every fixed-budget SL/RL/AlphaZero model row on the CUDA substrate.
- Prove convergence-statistics checkpointing, TensorBoard emission, and
  inference eligibility on CUDA.
- Run the expanded Playwright matrix against the CUDA edge.

### Validation

- `docker compose build jitml` — passed, including embedded `check-code: ok`
  and the PureScript bundle build.
- `./bootstrap/linux-cuda.sh up` — live Kind/Helm rollout executed 110 steps;
  publication substrate `linux-cuda`, edge `9092`, all seven components Ready.
- Canonical SL dataset staging through `jitml internal upload-dataset` —
  MNIST, Fashion-MNIST, CIFAR-10, CIFAR-100, Tiny ImageNet, and California
  Housing artifacts uploaded to live MinIO with pinned SHA-256 verification.
- `docker compose run --rm jitml-cuda cabal test -fcuda jitml-sl-canonicals
  --test-show-details=direct` — 24/24 PASS, including live MNIST threshold
  clearance and all canonical row materialization.
- `docker compose run --rm jitml-cuda jitml test all --linux-cuda` — 8/8
  stanzas PASS, including `jitml-backends` 20/20 on the attached RTX 5090 and
  the live WorkflowMatrix/integration cells.
- `docker compose run --rm jitml-cuda jitml internal seed-demo-checkpoints` —
  seeded eight demo checkpoints for the browser product matrix.
- Live `linux-cuda` Playwright product matrix — 15/15 PASS against
  `http://127.0.0.1:9092/`.

### Remaining Work

None. The expanded `linux-cuda` all-model lane is closed; Phase `16` remains
blocked on a separate Apple Silicon/Metal host.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
