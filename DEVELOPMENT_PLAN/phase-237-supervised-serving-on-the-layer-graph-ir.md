# Phase 237: Supervised Serving on the Layer-Graph IR

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Make the typed `LayerGraph` IR the sole supervised serving representation — accuracy, cross-entropy, projection, and weight identity all run through `runLayerGraph`.

## Phase State

✅ **Done** (closed 2026-07-28). `runLayerGraph` over the typed `LayerGraph` IR is
the single supervised **serving** executor: accuracy, cross-entropy, prediction,
and graph-ordered weight identity all run through `runLayerGraph` /
`graphParameterVector` over `TrainedArchitecture.trainedArchGraph`, and the
engine/Store read path (`run{LinuxCpu,Cuda,Metal}WeightedCheckpointInference`)
reconstructs the served `LayerGraph` from the checkpoint's architecture metadata
and executes it via `runSupervisedGraphCheckpointInference`, so the frozen V2
`SupervisedRuntime` `executeLayer` read operators are off the read path (the
retired serving arm fails closed). Every family serves the **dense-trainable**
`archLayerGraph`; the literal correct-operator architectures (multi-head attention
with `W_O`, real spatial conv) train on the Phase-`241` kernels in Phases
`242`–`244`, and end-to-end convergence is Phase `245`. Final operator-ABI removal
completes in Phase `239`; see the old→new map in [README.md](README.md).

## Sprint 237.1: Supervised Serving on the Layer-Graph IR [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/SL/Architecture.hs`, `src/JitML/Numerics/LayerGraph.hs`, `src/JitML/Numerics/LayerGraphMetadata.hs`, `src/JitML/Engines/Local.hs`, `src/JitML/Engines/CudaLocal.hs`, `src/JitML/Engines/MetalLocal.hs`, `test/unit/SupervisedRuntimeArtifact.hs`
**Docs to update**: `../documents/engineering/numerical_core.md`, `../documents/engineering/determinism_contract.md`

### Objective

Make `runLayerGraph` over the typed `LayerGraph` IR the single supervised
**serving** executor over the architecture's `LayerGraph`; `TrainedArchitecture`
carries the trained graph; and accuracy, cross-entropy, runtime projection, and
graph-ordered weight identity are computed by pure `runLayerGraph` +
`graphParameterVector` instead of the parallel `[LayerSpec]`/`[LayerState]`
executor and the frozen V2 `SupervisedRuntime` `executeLayer` read operators.
`runLayerGraph` executes every correct Phase-233 operator (multi-head attention
with `W_O`, `GeGLU`, conv, patch, norm, residual), so the spurious
single-head/no-residual/outer-`tanh` executeLayer read operators are no longer on
the path. The graph the architecture trains and serves in Phases `237`/`238` is
the **dense-trainable** graph (the current oneDNN loop is dense-only); rebuilding
`architectureLayerGraphForFamily` onto the literal correct-operator nodes and
training them on the Phase-`241` device kernels is Phases `242`–`244`. The trained
parameters that populate the served graph are produced by Phase `238`'s
graph-training loop — the two phases land the migration together (see
[Phase State](#phase-state)) — so this phase's validation asserts the serving
executor is oracle-consistent (the engine/Store read path reproduces
`runLayerGraph`) and that graph-ordered weight identity holds. End-to-end
trained-model convergence is Phase `245`.

### Deliverables

- `TrainedArchitecture` holds the trained `LayerGraph`;
  `accuracyArchitectureWithDevice` / `crossEntropyArchitectureWithDevice` /
  `projectTrainedArchitectureRuntime` / `trainedArchitectureWeights` are rewritten
  onto `runLayerGraph` and `graphParameterVector`, preserving the semantic-prefix
  argmax/softmax over the first `classes` of the `classes + 1` logits.
- Serving flows through the typed IR executor (`runLayerGraph`), so the frozen V2
  `SupervisedRuntime` `executeLayer` read operators (single-head / no-residual /
  outer-`tanh`) are off the read path. The literal correct-operator served math
  (multi-head attention with `W_O`, affine-LayerNorm, GeGLU) is realized once the
  correct-operator architectures train on the Phase-`241` kernels (Phases
  `242`–`244`).
- The V2 `SupervisedRuntime` served representation is superseded on the read side:
  `loadSupervisedRuntimeFromCheckpoint` serving (the load path transferred from
  Phase `236`) and the Local/CUDA/Metal engines move onto a reloaded `LayerGraph`
  served via `runLayerGraph` (input/output transforms remain outside the graph),
  recorded in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) under this
  sprint; final operator-ABI removal completes in Phase `239`.
- Serving unit tests assert the engine/Store read path reproduces the pure
  `runLayerGraph` oracle within tolerance and that
  `graphParameterVector (trained graph) == trainedArchitectureWeights`, for a
  representative row.

### Closure Evidence

All [Deliverables](#deliverables) are met. `TrainedArchitecture` carries
`trainedArchGraph :: !LayerGraph`; `accuracyArchitectureWithDevice` /
`crossEntropyArchitectureWithDevice` / `predictArchitectureWithDevice` /
`trainedArchitectureWeights` compute through `runLayerGraph` /
`graphParameterVector`, and the parallel `[LayerSpec]`/`[LayerState]` serving fork
is deleted. The write path populates the checkpoint architecture metadata with the
trained graph (`architectureLayerGraph = Just (layerGraphMetadataFromGraph
trainedArchGraph)`), so the engine/Store read path
(`run{LinuxCpu,Cuda,Metal}WeightedCheckpointInference`) reconstructs the served
`LayerGraph` via `reconstructSupervisedGraphFromCheckpoint` and executes it with
`runSupervisedGraphCheckpointInference`; the former V2 `executeLoadedRuntime`
serving arm is retired to a fail-closed error (`loadSupervisedRuntimeFromCheckpoint`
stays compiled for admission until the Phase `239` ABI removal). A write-path
liveness test in `test/unit/SupervisedRuntimeArtifact.hs` drives the real
production write plumbing, asserts the produced manifest carries the trained graph,
reloads it, and asserts the engine/Store read path reproduces the pure
`runLayerGraph` oracle. Validated by the `### Validation` gate below (`jitml test
jitml-unit --linux-cpu` **777 / 777**, `jitml test jitml-backends --linux-cpu`
**27 / 27**, `jitml check-code` **ok**).

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
