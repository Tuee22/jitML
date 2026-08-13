# Phase 268: Contract-Driven CUDA Lane Revalidation

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Contract-Driven CUDA Lane Revalidation. Single-session phase migrated from legacy Sprint 29.5 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

⏸️ **Blocked**. Blocked by Phase 263 (Sprint 263.1), which reopened on 2026-08-12
because the committed lane fragment's device-evidence column is derived from the
declared substrate and claim rather than from what executed. This lane's
revalidation cannot be meaningful while supervised rows on it execute oneDNN
kernels, so the CUDA lowering in Sprint `264.1` and the witness in Sprint `229.1`
land first.

## Sprint 268.1: Contract-Driven CUDA Lane Revalidation [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Sprint `263.1`
**Implementation**: `src/JitML/Test/RunContract.hs`,
`src/JitML/Test/Report.hs`, `test/integration/Main.hs`,
`DEVELOPMENT_PLAN/attestations/linux-cuda-report-card.md`
**Docs to update**: `../README.md`,
`../documents/engineering/product_completion_contract.md`,
`../documents/engineering/unit_testing_policy.md`,
`../documents/engineering/run_contract.md`, `system-components.md`

### Objective

Revalidate the full row-complete workflow contract on a real `linux-cuda` host
and replace the lane fragment with journal-derived evidence. This sprint owns
the CUDA-lane portions of [Exit Definition](README.md#exit-definition) items
`31`, `32`, and `34` while preserving the existing item `29` performance bar.
The binding design is
[README.md → Typed run contracts](../README.md#typed-run-contracts).

### Deliverables

- Run every supported CUDA product scenario through the same validated plan,
  receipt-bound consumer, exact evidence reducer, and scoped lifecycle used by
  the `linux-cpu` lane.
- Prove each completed row journal carries the CUDA substrate/device witness,
  exact terminal evidence, trained artifact hash, and measured inference result.
- Re-run the existing backend, publisher, integration, e2e, negative-control,
  model-convergence, and every-row CUDA-vs-CPU performance gates on the real GPU.
- Replace the committed `linux-cuda` fragment only after all scenarios complete;
  retain explicit failed/not-run entries rather than fabricating pass cells.
- Record cleanup and diagnostic evidence for the full bootstrap/test/down
  lifecycle without requiring Apple Silicon in this phase.

### Validation

```bash
./bootstrap/linux-cuda.sh up
./bootstrap/linux-cuda.sh test
./bootstrap/linux-cuda.sh down
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Remaining Work

- Blocked until Sprints `229.1`, `264.1`, and `265.1` land the CUDA lowering and the
  execution witness; a lane revalidation cannot attest kernels the lane does not run.
- [Exit Definition](README.md#exit-definition) item `29` — every one of the 55 rows
  strictly faster on `linux-cuda` than on `linux-cpu`, with no per-row exemptions —
  is **not met and is presently unreachable**: the non-dense rows have no CUDA
  layer-graph kernel and fall back to the pure host tape on this lane, so the GPU
  lane executes host Haskell for that cohort. Sprint `264.1` makes the item
  reachable; it is recorded here as unmet rather than weakened.
- The 2026-08-12 attempt failed closed at row `PPO/mountain-car`
  (`median_final_reward=-159.0` against `threshold=-155.0`). No `linux-cuda`
  `median_final_reward` was ever committed for that row, and the bar moved to `-155`
  on 2026-07-11, the day after the last CUDA lane run, so this is an unbaselined
  substrate difference rather than a regression. Measure and record the value, then
  use the existing per-substrate on-policy tuning knob if it reproduces; do not
  modify the shared `cohortThresholds` table, which is documented as
  substrate-invariant and is fenced by the frozen external-bar set.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
