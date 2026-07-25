# Phase 122: Storage Layout and Split-Blob Schema

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Storage Layout and Split-Blob Schema. Single-session phase migrated from legacy Sprint 10.1 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 122.1: Storage Layout and Split-Blob Schema [✅ Done]

**Status**: Done
**Owned obligations after refactor**: code-surface only. Live MinIO
bucket layout validation migrated to Phase `15` Sprint `15.7`.
**Implementation**: `src/JitML/Checkpoint/Format.hs`,
`src/JitML/Storage/Buckets.hs`
**Docs to update**: `documents/engineering/checkpoint_format.md`

### Objective

Establish the manifest shape, bucket pointer string, and
split-blob object-key renderers used by the inference summary surface.

### Deliverables

- `TensorBlob` carries `tensorName`, `tensorShape`, and `tensorBlobKey`.
- `CheckpointManifest` carries `manifestId`, `manifestExperiment`, and a list
  of `TensorBlob` values.
- `manifestPointer` renders the current simplified pointer path
  `jitml-checkpoints/<experiment>/<manifest>.manifest.cbor`.
- `blobKey`, `manifestKey`, `latestPointerKey`, `bestPointerKey`, and
  `trialPointerKey` render the split-blob object layout under
  `jitml-checkpoints/<experiment-hash>/`.
- `src/JitML/Storage/Buckets.hs` enumerates the `jitml-checkpoints` bucket
  among the local MinIO bucket names.
- `CheckpointManifest` carries `manifestOptimizer :: [OptimizerBlob]`,
  `manifestRng :: [RngBlob]`, `manifestStep :: Word64`,
  `manifestMetrics :: [(Text, Double)]`, and `manifestParentManifestSha`.
- `deriveExperimentHash resolvedDhall substrateFingerprint` computes
  the canonical `sha256(resolved-dhall || substrate-fingerprint)`
  used as the bucket prefix and pointer-key key.
- Live MinIO bucket-layout validation is closed by Phase 4 Sprint `4.3`
  and Phase 15 Sprint `15.7`; the current live checkpoint snapshot path
  round-trips through `JitML.Service.MinIOSubprocess`.

### Historical Validation

1. `src/JitML/Checkpoint/Format.hs` exposes the `TensorBlob`,
   `CheckpointManifest`, and `manifestPointer` helpers.
2. `cabal test jitml-cross-backend` exercises the manifest-based inference
   helper.
3. `jitml-unit` verifies the split-key renderers.
4. Live validation: Phase 15 Sprint `15.7` validates that a real MinIO
   bucket holds blobs and manifests under the addressed split-blob paths
   after a real training step; `experiment-hash` is derived from the
   resolved Dhall and referenced by both the bucket prefix and the
   pointer key.

### Remaining Work

- No sprint-owned code-surface Remaining Work remains. Live MinIO bucket
  layout validation through `JitML.Service.MinIOSubprocess` after a real
  training step is closed by
  [phase-15-linux-cuda-and-cluster-closure.md](README.md#legacy-to-new-phase-map)
  Sprint `15.7`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
