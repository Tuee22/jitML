# Phase 237: Supervised Serving on the Layer-Graph IR

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Make the typed `LayerGraph` IR the sole supervised serving representation — accuracy, cross-entropy, projection, and weight identity all run through `runLayerGraph`.

## Phase State

🔄 **Active** (frontier; promoted 2026-07-27 after Phase `236` closed the
admission single-path).

**Code reality this phase corrects (2026-07-27 audit).** `runLayerGraph`'s
`forwardOp` already executes the FD-validated Phase-233 operators — multi-head
`AttentionOp` (four `d×d` projections including `W_O`), `GeGLUOp`, `ConvOp`,
`PatchOp`, `ResidualOp`/`BlockOp`, `NormOp`. But `architectureLayerGraphForFamily`
does **not** emit them: it builds every node with `mkAffineLayer` (hard-coded
`DenseOp`) / `mkIdentityLayer`, so `archLayerGraph` is a decorative
single-affine/identity placeholder that is never consumed for serving. A trained
`[LayerState]` (2-layer `tanh` MLPs, single-`MlpParams` QKV) is structurally
incompatible with a correct-operators graph — the parameter counts diverge per
family, so `replaceGraphParameterVector` hard-errors and there is **no valid
weight transfer**. The correct-operators graph only becomes a *trained* object
once training runs through it.

**Coupling with Phase `238` (honest boundary).** Because a trained graph cannot
be served here before Phase `238`'s graph-training loop produces it, Phases `237`
and `238` jointly migrate the supervised path onto the typed `LayerGraph` IR and
are **implemented together**. This phase owns and validates the
**serving/measurement** surface (the executor is `runLayerGraph`, the engine/Store
read path reproduces it, graph-ordered weight identity holds, and the frozen V2
`SupervisedRuntime` read operators are retired). Phase `238` owns training on the
graph via the oneDNN loop, deletion of the parallel `[LayerSpec]`/`[LayerState]`
program, and cross-entropy-decrease evidence.

**Correct-operator scope (2026-07-28 audit).** The IR training loop
(`trainLayerGraphClassifierOneDnn` → `runDeviceLayer`) is currently **dense-only**
— it can train an all-`DenseOp` graph but not the correct-operator nodes
(`ConvOp`/`NormOp`/`GeGLUOp`/`AttentionOp`/`PatchOp`/`ResidualOp`/`BlockOp`), whose
device training kernels do not yet exist. `runLayerGraph` **serves** all of them,
but they cannot be **trained** until Phase `241` (oneDNN Device Training Kernels
for Correct Operators). Therefore Phases `237`/`238` migrate serving and training
onto the **dense-trainable** `LayerGraph`; the literal correct-operator
architectures (multi-head attention with `W_O`, real spatial conv) are trained on
the Phase-`241` kernels in Phases `242`–`244`, and end-to-end convergence is Phase
`245`. This phase also inherits, by ownership transfer from Phase `236` (rule
M(a)), removal of the live V2 `SupervisedRuntime` read/serving path
(`loadSupervisedRuntimeFromCheckpoint`). The unmet obligations are in
[Remaining Work](#remaining-work); see the old→new map in [README.md](README.md).

## Sprint 237.1: Supervised Serving on the Layer-Graph IR [🔄 Active]

**Status**: Active
**Implementation**: `src/JitML/SL/Architecture.hs`, `src/JitML/Numerics/LayerGraph.hs`, `test/unit/SupervisedRuntimeArtifact.hs`
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

### Remaining Work

- **In-process serving migration DONE and validated** (`jitml-unit` **775/775**,
  `jitml-backends` **27/27**, `check-code` **ok** on `linux-cpu`). Every family —
  flat and token — now carries the trained `LayerGraph` in `TrainedArchitecture`
  (`trainedArchGraph`) and computes accuracy, cross-entropy, prediction, and
  graph-ordered weights through `runLayerGraph` / `graphParameterVector`; the
  parallel `[LayerState]` serving fork (`flatFamilyServingGraph` / `forwardOnly`)
  is retired, and the trained-graph parameters are produced by Phase `238`'s
  device loop (implemented together). `trainedArchitectureWeights` is
  `graphParameterVector`; `projectTrainedArchitectureRuntime` is bridged to the
  canonical contract.
- **Unmet (coupled with Phase `239`):** the engine/Store read path
  (`runLinuxCpuWeightedCheckpointInference` / `runCudaWeightedCheckpointInference`
  / `runMetalWeightedCheckpointInference`) still reloads the V2
  `SupervisedRuntime` (`loadSupervisedRuntimeFromCheckpoint` →
  `executeLoadedRuntime`) instead of reconstructing the served `LayerGraph` and
  running `runLayerGraph`, and the token-family checkpoint parameter count
  (`canonicalClassificationRuntimeContract` → `supervisedRuntimeParameterCount`,
  e.g. `cifar10-vit` `123595`) does not yet match the dense-trainable graph's
  `graphParameterVector` count. Because the served graph is a *reconstruction*
  from the checkpoint, the engine move is coupled to Phase `239`'s
  checkpoint-construction-from-the-trained-graph re-anchor (`loadSupervisedRuntimeFromCheckpoint`
  stays compiled for admission until then). Close with the `### Validation` gate
  below plus a serving test asserting the engine/Store read path reproduces the
  `runLayerGraph` oracle.

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
