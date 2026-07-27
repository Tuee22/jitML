# Phase 238: Supervised Training on the Layer-Graph IR

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Train the supervised rows through the typed `LayerGraph` IR and retire the parallel `[LayerSpec]` / `[LayerState]` program entirely.

## Phase State

⏸️ **Blocked**. Blocked by Phase 237 (Sprint 237.1). With serving on the IR, the
training drivers move onto the IR and the parallel executable program is deleted;
see the old→new map in [README.md](README.md).

## Sprint 238.1: Supervised Training on the Layer-Graph IR [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Sprint `237.1`
**Implementation**: `src/JitML/SL/Architecture.hs`, `src/JitML/Numerics/LayerGraphOneDnn.hs`, `src/JitML/SL/TrainingExecution.hs`, `test/unit/SupervisedRuntimeArtifact.hs`
**Docs to update**: `../documents/engineering/numerical_core.md`, `../documents/engineering/jit_codegen_architecture.md`

### Objective

Train the supervised rows through the typed `LayerGraph` IR and **retire the
parallel `[LayerSpec]` / `[LayerState]` program**. The `trainArchitectureWithDevice*`
drivers thread `Env` (required by the device IR path, which the `MlpDevice` record
does not carry) and train `archLayerGraph` with the batched
`trainLayerGraphClassifierOneDnn` loop over the graph's flat parameter vector,
using the device cross-entropy gradient. After this sprint the IR is the single
owner of supervised training, inference, and graph-ordered parameter identity.

### Deliverables

- The `trainArchitectureWithDevice*` driver chain takes `Env` and trains the
  architecture's `LayerGraph` via the batched
  `trainLayerGraphClassifierOneDnn` (mini-batch Adam over
  `graphParameterVector` using the batched device cross-entropy gradient from
  Phase `234`).
- The `[LayerSpec]` / `[LayerState]` executable program and its supporting
  projection are deleted; `archLayerGraph` is the trained object (recorded in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) under this
  sprint, repointing the pre-existing decorative-graph ledger row here).
- A backends/unit test trains a small classifier `LayerGraph` end to end through
  the batched oneDNN loop and asserts cross-entropy decreases, with device
  evidence recorded.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-backends --linux-cpu
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml check-code
```

## Documentation Requirements

**Engineering docs to create/update:**

- `../documents/engineering/numerical_core.md` — record the IR as the sole
  training representation and the removal of the parallel program (prose only).
- `../documents/engineering/jit_codegen_architecture.md` — the supervised training
  path is the batched oneDNN IR loop.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
