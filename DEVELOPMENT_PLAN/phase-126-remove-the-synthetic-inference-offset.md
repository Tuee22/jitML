# Phase 126: Remove the Synthetic Inference Offset

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Remove the Synthetic Inference Offset. Single-session phase migrated from legacy Sprint 10.5 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 126.1: Remove the Synthetic Inference Offset [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Checkpoint/Format.hs`,
`src/JitML/Checkpoint/Store.hs`, `src/JitML/Service/Workload.hs`,
`src/JitML/Engines/{Local,CudaLocal,MetalLocal}.hs` (checkpoint runners),
`src/JitML/App.hs` (`runInference`)
**Docs to update**: `../documents/engineering/checkpoint_format.md`, `system-components.md`

### Objective

Remove the fabricated `+ nTensors/100` inference offset that stood in for the
real substrate weighted kernel, so no read path emits a synthetic number. Owns
the inference-read slice of [Exit Definition](README.md#exit-definition) item 7.

### Deliverables

- The three engine checkpoint runners (`runLinuxCpuCheckpointInference` and
  peers) return the faithful kernel output with no added bias.
- `inferFromManifest` is deleted, together with the default Store wrappers that
  turned a manifest read into an inference result. Real inference is the
  substrate weighted kernel via `loadInferenceCheckpointWithWeights` →
  `run*WeightedCheckpointInference`.
- `Service.Workload` default inference fails closed with `weighted inference
  runner required`; runtime self-inference supplies the weighted runner.
- `jitml inference run` fails closed (`InferenceCheckpointMissing`) when no live
  publication is present, instead of the `emptyManifest` + synthetic summary,
  and reports real checkpoint metadata rather than a synthetic inference value.

### Validation

- `docker compose run --rm jitml jitml test jitml-unit --linux-cpu` — 196 / 196.
- `docker compose run --rm jitml jitml test jitml-daemon-lifecycle --linux-cpu`
  — 31 / 31.
- `docker compose run --rm jitml cabal test jitml-integration
  --test-options='-p loadInferenceCheckpointWithWeights'` — focused offline case
  passed.
- `docker compose run --rm jitml cabal test jitml-integration
  --test-options='-p boundaries'` — focused offline HasMinIO checkpoint-write
  case passed.

### Current Validation State

Closed on 2026-06-11 in the container with the validation commands above. A
broader `jitml-integration -p conditional` run also exercised the changed offline
checkpoint snapshot case successfully before matching the intentionally
fail-closed `Live` conditional test; without
`.build/runtime/cluster-publication.json`, live integration tests fail by design.

### Remaining Work

- No Sprint 10.5 code-surface Remaining Work remains. Live per-lane exercise of
  the weighted read path remains owned by Phase 15 / Phase 14.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
