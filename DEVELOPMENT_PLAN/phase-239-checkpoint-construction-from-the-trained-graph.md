# Phase 239: Checkpoint Construction from the Trained Graph

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Build the supervised-graph checkpoint envelope directly from the trained `LayerGraph`, removing the V2 `SupervisedRuntime` projection and its served-operator ABI.

## Phase State

✅ **Done** (closed 2026-07-28). The supervised checkpoint payload is constructed
directly from the trained typed `LayerGraph`: the write path carries the graph
metadata in the manifest architecture, the envelope selects the supervised-graph
body on `architectureLayerGraph == Just`, and admission validates the weight blob
against the graph parameter count. The V2 `SupervisedRuntime` layer-operation
projection (`projectTrainedArchitectureRuntime`, `exactRuntimeWeightBytes`) and its
nine-operation served ABI (`executeLoadedRuntime`, `Codegen/RuntimeOperationsCpu`,
`Engines/RuntimeOperationsDevice`, and the per-substrate operators) are deleted;
the reloaded graph is executed directly by `runLayerGraph`. See the old→new map in
[README.md](README.md).

## Sprint 239.1: Checkpoint Construction from the Trained Graph [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/SL/TrainingExecution.hs`, `src/JitML/Checkpoint/Writer.hs`, `src/JitML/Checkpoint/Format.hs`, `src/JitML/Tune/Catalog.hs`, `src/JitML/SL/RuntimeArtifact.hs`
**Docs to update**: `../documents/engineering/checkpoint_format.md`, `../documents/engineering/jit_codegen_architecture.md`, `../documents/engineering/determinism_contract.md`

### Objective

Construct the supervised-graph checkpoint payload directly from the trained
`LayerGraph`, replacing the
`projectTrainedArchitectureRuntime` → V2 `SupervisedRuntime` →
`exactRuntimeWeightBytes` chain. The V2 served-operator ABI
(`RuntimeOperationsCpu`/`Cuda`/`Metal`, the nine-operation set) is removed because
the reloaded graph is executed directly, and the supervised writer emits the
single supervised-graph envelope from Phase `235`.

### Deliverables

- `src/JitML/SL/TrainingExecution.hs` and `src/JitML/Checkpoint/Writer.hs` build
  the supervised-graph envelope from the trained `LayerGraph`; the V2
  `SupervisedRuntime` projection and `exactRuntimeWeightBytes` are removed, and
  `src/JitML/Tune/Catalog.hs` consumers follow.
- The V2 served-operator ABI (`RuntimeArtifact.hs`,
  `Codegen/RuntimeOperationsCpu.hs`, the per-substrate device operators, the
  nine-operation set) is deleted (recorded in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) under this
  sprint).
- A unit test builds a supervised checkpoint from a trained graph and reloads it,
  asserting the reloaded graph is byte-identical to the trained graph and serves
  the same predictions.

### Closure Evidence

All [Deliverables](#deliverables) are met. `src/JitML/SL/TrainingExecution.hs` and
`src/JitML/Checkpoint/Writer.hs` construct the supervised checkpoint from the
trained `LayerGraph` (the graph metadata rides in the manifest architecture);
`encodeManifestCbor` selects the supervised-graph body on `architectureLayerGraph
== Just`, and admission (`loadSupervisedRuntimeFromCheckpoint`,
`validateBoundRuntimeAndCompletion`) validates the one `supervised.weights` blob
against `layerGraphMetadataParameterCount`. The V2 `SupervisedRuntime` projection
(`projectTrainedArchitectureRuntime`, `exactRuntimeWeightBytes`) and the
nine-operation served ABI (`executeLoadedRuntime` + the structural executors,
`Codegen/RuntimeOperationsCpu.hs`, `Engines/RuntimeOperations*.hs`,
`RuntimeLayerOperation`/`LoadedRuntime`/the token layer DTOs) are deleted (~4600
lines of whole files plus net reductions; recorded in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) under this
sprint), and the reloaded graph is executed directly by `runLayerGraph`. The
`SupervisedCheckpointV2` fixtures are re-anchored onto the graph parameter count,
and the checkpoint/engineering docs are rewritten to the graph-only served
representation. Token-family end-to-end convergence is validated on the
`jitml-sl-canonicals` lane in Phase `245`. Validated by the `### Validation` gate
below (`jitml test jitml-unit --linux-cpu` **743 / 743**, `jitml test
jitml-backends --linux-cpu` **27 / 27**, `jitml check-code` **ok**, `jitml docs
check` **ok**).

### Validation

```bash
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml test jitml-backends --linux-cpu
docker compose run --rm jitml jitml check-code
docker compose run --rm jitml jitml docs check
```

## Documentation Requirements

**Engineering docs to create/update:**

- `../documents/engineering/checkpoint_format.md` — the supervised payload is the
  trained graph; finish the CBOR-DTO rewrite.
- `../documents/engineering/jit_codegen_architecture.md` — remove the Supervised
  V2 structural-operation ABI section.
- `../documents/engineering/determinism_contract.md` — remove the Exact V2
  Structural Runtime section; the reloaded-graph reconstruction is the contract.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
