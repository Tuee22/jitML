# Phase 72: Layer Catalog

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Layer Catalog. Single-session phase migrated from legacy Sprint 6.1 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done** (closed 2026-08-13). `LayerOp` is the single layer vocabulary. The node
identity tag, the catalog, and the Dhall surface are all total projections of it:
`opKind` derives the kind (the stored `layerNodeKind` field is gone), `opLayer` /
`layerOpTemplate` relate the executed operator and `Catalog.Layer` in both
directions, `layerKindWitnessOp` proves every declared kind is executable, and
`layerCatalog` is `[minBound .. maxBound]` over the catalog type. The dead
`familyForLayer` bridge is deleted.

## Sprint 72.1: Layer Catalog [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Numerics/Catalog.hs`,
`src/JitML/Numerics/LayerGraph.hs`, `src/JitML/Numerics/LayerGraphMetadata.hs`,
`src/JitML/Codegen/KernelFamily.hs`, `src/JitML/SL/Architecture.hs`,
`dhall/numerics/Layer.dhall`, `test/unit/Main.hs`
**Docs to update**: `../documents/engineering/numerical_core.md`

### Objective

Stand up the layer catalog as the one operator vocabulary: a closed Haskell sum
type that the executed `LayerGraph` IR, the documentation table, and the Dhall
surface all derive from, so a constructor cannot exist in one and not the others.

### Deliverables

- `Catalog.Layer` enumerates the executed operator set — `Dense`, `Identity`,
  `Dropout`, `Convolution`, `Pooling`, `Normalization`, `MultiHeadAttention`,
  `GeGLU`, `PatchEmbedding`, `Residual`, `ResidualBlock` — one constructor per
  `LayerGraph.LayerOp` constructor.
- `layerCatalog` is `[minBound .. maxBound]` over that type, so the list cannot
  drift from the vocabulary it enumerates.
- `LayerGraph.opLayer :: LayerOp -> Catalog.Layer` and
  `LayerGraph.layerOpTemplate :: Catalog.Layer -> LayerOp` are total in both
  directions, so `-Werror=incomplete-patterns` (Sprint `7.1`) fails the build
  when either vocabulary gains a constructor the other lacks.
- `LayerGraph.opKind :: LayerOp -> LayerKind` derives the node identity tag.
  `LayerNode` no longer stores a kind beside its operator: `layerNodeKind` is
  that projection, so the oneDNN switch key is the executed operator by
  construction and a node cannot claim an operator it did not run. Kinds that
  refine one operator by its spec are read off the spec —
  `blockIsBottleneck` decides basic vs bottleneck from the block's internal
  narrowing, and `mkBasicBlock` / `mkBottleneck` reject a spec of the other
  topology rather than tagging it.
- `LayerGraph.layerKindWitnessOp :: LayerKind -> LayerOp` is total over
  `LayerKind`, and `opKind . layerKindWitnessOp` is the identity over
  `allLayerKinds`, so a declared kind cannot exist without an operator that
  executes it.
- `LayerGraphMetadata.layerGraphFromMetadata` recomputes the node kind from the
  persisted operator and rejects a persisted kind that disagrees, so the
  checkpoint DTO's kind field is a checksum on the one vocabulary rather than a
  second vocabulary.
- `renderNumericalCatalog` and the generated `numerics.layers` documentation
  table render from `layerCatalog`; `dhall/numerics/Layer.dhall` mirrors it
  under the cross-type audit.
- The dead `familyForLayer` bridge is deleted from
  `src/JitML/Codegen/KernelFamily.hs`; the removal is recorded in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

### Validation

1. `jitml test jitml-unit --linux-cpu` passes, including the seven-case
   "One operator vocabulary (Phase 72)" group and the two catalog/Dhall
   cross-type audit cases.
2. `jitml test jitml-backends --linux-cpu` passes: the oneDNN layer-graph
   kernels still dispatch on the derived kind for every declared layer kind.
3. `jitml test jitml-sl-canonicals --linux-cpu` passes: the literal
   architectures still declare exactly the features their graphs implement.
4. `jitml docs check` reports `ok` for the regenerated `numerics.layers` table.
5. `jitml check-code` exits `0` inside `jitml:local`.

### Completed in this sprint

- `src/JitML/Numerics/Catalog.hs`: `Layer` reduced to the eleven executed
  operators with `Bounded`/`Enum`; `layerCatalog` derived from the type.
- `src/JitML/Numerics/LayerGraph.hs`: `opKind`, `opLayer`, `layerOpTemplate`,
  `layerKindWitnessOp`, `poolKindOf`, `blockIsBottleneck`; the `layerNodeKind`
  record field replaced by the derived projection; every smart constructor
  stopped taking a kind argument; `IdentityLayer` added so the parameterless
  passthrough names itself instead of borrowing another node's tag.
- `src/JitML/Numerics/LayerGraphMetadata.hs`: derived-on-write,
  verified-on-read kind; `LayerGraphIdentityLayer` appended to the wire enum
  (existing constructor indices unchanged, so persisted checkpoints still
  decode).
- `src/JitML/SL/Architecture.hs`: `GraphLayerPlan` no longer carries a kind, so
  a plan cannot decorate a dense affine with a convolution or block tag.
- `src/JitML/Codegen/KernelFamily.hs`: `familyForLayer` deleted.
- `test/backends/Main.hs`: `layerGraphOneDnnFixture` now builds each declared
  kind from the operator that actually executes it, instead of building a dense
  affine for every kind and naming it after the kind. That rewrite surfaced a
  real gap the decorative fixture had been masking: the layer-graph oneDNN path
  has **no 3-D convolution primitive**, and the old fixture's dense-affine
  "Conv3D" node was reporting `onednn_convolution_backward_weights_3d` evidence
  for a dense kernel. The fixture now covers `deviceSupportedLayerKinds`, and a
  new case asserts that a real 3-D `ConvOp` **fails closed** naming the
  operator. Providing the missing device kernel is Phase `241`'s total-lowering
  obligation, recorded in its `### Remaining Work`.

### Historical Validation

Evidence for the surface this sprint exercised before the 2026-08-12 reopen:

> ✅ **Done**.

## Documentation Requirements

**Engineering docs to create/update:**

- `../documents/engineering/numerical_core.md` — the `One operator vocabulary`
  section and the regenerated `numerics.layers` table.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
