# Phase 237: Supervised Serving on the Layer-Graph IR

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Make the typed `LayerGraph` IR the sole supervised serving representation — accuracy, cross-entropy, projection, and weight identity all run through `runLayerGraph`.

## Phase State

⏸️ **Blocked**. Blocked by Phase 236 (Sprint 236.1). The read side of the
supervised path moves onto the IR before the train side (Phase `238`) and
checkpoint construction (Phase `239`); see the old→new map in
[README.md](README.md).

## Sprint 237.1: Supervised Serving on the Layer-Graph IR [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Sprint `236.1`
**Implementation**: `src/JitML/SL/Architecture.hs`, `src/JitML/Numerics/LayerGraph.hs`, `test/unit/SupervisedRuntimeArtifact.hs`
**Docs to update**: `../documents/engineering/numerical_core.md`, `../documents/engineering/determinism_contract.md`

### Objective

Make the typed `LayerGraph` IR the single supervised serving representation.
`TrainedArchitecture` carries the trained `LayerGraph`; accuracy, cross-entropy,
runtime projection, and graph-ordered weight identity are computed by pure
`runLayerGraph` instead of the parallel `[LayerSpec]` / `[LayerState]` executor.
The correct multi-head + `W_O` + residual + affine-LayerNorm math (already
finite-difference-validated in Phase `233`) becomes the served math; the spurious
single-head/no-residual/outer-`tanh` served operators are no longer on the path.

### Deliverables

- `TrainedArchitecture` holds the trained `LayerGraph`;
  `accuracyArchitectureWithDevice` / `crossEntropyArchitectureWithDevice` /
  `projectTrainedArchitectureRuntime` / `trainedArchitectureWeights` are rewritten
  onto `runLayerGraph` and the graph parameter vector.
- The served attention adds the transformer residual `Y = X + O` and drops the
  outer `tanh`/`SiLU`; token-mix and normalization execute the Phase `233`
  forward semantics — all inherited from the IR executor, not re-implemented.
- The V2 `SupervisedRuntime` served representation is superseded on the read side
  (recorded in [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
  under this sprint; final operator-ABI removal completes in Phase `239`).
- Serving unit tests assert the IR-served accuracy/cross-entropy match the pure
  `runLayerGraph` oracle within tolerance for a representative attention row.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml test jitml-backends --linux-cpu
docker compose run --rm jitml jitml check-code
```

## Documentation Requirements

**Engineering docs to create/update:**

- `../documents/engineering/numerical_core.md` — update the Execution Boundary /
  Typed Layer Graph prose to "IR is the sole served representation" (prose only;
  the generated `numerics.*` catalog tables are regenerated via `jitml docs generate`).
- `../documents/engineering/determinism_contract.md` — begin retiring the Exact V2
  Structural Runtime section (served ABI removal completes in Phase `239`).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
