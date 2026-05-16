# Phase 10: Checkpointing and Inference-Only Read Path

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md),
[development_plan_standards.md](development_plan_standards.md),
[system-components.md](system-components.md),
[phase-0-planning-documentation.md](phase-0-planning-documentation.md),
[phase-4-stateful-platform-services.md](phase-4-stateful-platform-services.md),
[phase-9-rl-catalog-alphazero-and-tuning.md](phase-9-rl-catalog-alphazero-and-tuning.md),
[phase-11-purescript-frontend-and-demo.md](phase-11-purescript-frontend-and-demo.md),
[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
**Generated sections**: none

> **Purpose**: Stand up the current local checkpoint and inference surface:
> split-blob object-key renderers, a small typed manifest, pure pointer-CAS
> decisions, a local deterministic CBOR manifest codec/content hash, a
> binary `.jmw1` encoder, a filesystem-backed local checkpoint store,
> `jitml internal gc` summary output, and deterministic inference summaries.
> Live MinIO effects, retention traversal, and
> kernel-handle loading remain target runtime work.

## Phase Status

✅ **Done** for the local checkpoint manifest, split-blob object-key helpers,
pointer-CAS decision surface, deterministic manifest CBOR codec/content hash,
`.jmw1` blob header, filesystem-backed local checkpoint store, and
inference-only read surfaces. Target checkpointing serialises models trained in
Phases `8`/`9`; target Phase `11` demo/frontend surfaces consume the real
inference-only read path once those runtime pieces land.

### Current Implementation Scope

The current worktree implements a small `CheckpointManifest`, `TensorBlob`,
split-blob object-key renderers, pointer-CAS decisions, `manifestPointer`,
deterministic `encodeManifestCbor` / `decodeManifestCbor` /
`manifestContentSha`, binary `encodeJmw1` encoder with `JMW1` magic, CBOR
header length, and little-endian `F64` payload bytes, and deterministic
`inferFromManifest` helper in `src/JitML/Checkpoint/Format.hs`.
`src/JitML/Checkpoint/Store.hs` adds a local object-store interpreter for
write-once payloads, manifest writes/reads, latest pointer CAS, and inference
from the latest checkpoint. It does not yet implement live MinIO
conditional-write effects, retention graph traversal, kernel-handle loading, or
real demo/frontend checkpoint reads.

## Phase Summary

This phase currently delivers the local checkpoint manifest, split-blob key,
pointer-CAS, deterministic manifest CBOR, local write-once object store, latest
pointer read path, and inference summary helpers. The target persistence layer
still uses MinIO bucket `jitml-checkpoints`, write-once blobs, If-Match CAS
pointers, and the split-blob `.jmw1` binary format; live MinIO effects are not
implemented in the present codebase. The live implementation proceeds
storage-outward: MinIO conditional checkpoint writes/reads first, then
inference from checkpoint, then training persistence, then tuning/resume
semantics.

## Sprint 10.1: Storage Layout and Split-Blob Schema ✅

**Status**: Done
**Implementation**: `src/JitML/Checkpoint/Format.hs`,
`src/JitML/Storage/Buckets.hs`
**Docs to update**: `documents/engineering/checkpoint_format.md`

### Objective

Establish the current local manifest shape, bucket pointer string, and
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
- Optimizer/RNG parts and experiment-hash derivation remain target runtime
  validation.

### Validation

1. `src/JitML/Checkpoint/Format.hs` exposes the current `TensorBlob`,
   `CheckpointManifest`, and `manifestPointer` helpers.
2. `cabal test jitml-cross-backend` exercises the local manifest-based
   inference helper.
3. `jitml-unit` verifies the split-key renderers.

## Sprint 10.2: `.jmw1` Wire Format and Manifest CBOR ✅

**Status**: Done
**Implementation**: `src/JitML/Checkpoint/Format.hs`,
`src/JitML/Checkpoint/Store.hs`
**Docs to update**: `documents/engineering/checkpoint_format.md`

### Objective

Land the current `.jmw1` encoder, local deterministic manifest CBOR codec,
manifest-content SHA helper, local pointer-CAS decision surface, and local
write-once object-store interpreter. Live MinIO conditional-write effects
remain target runtime validation.

### Deliverables

- `encodeJmw1` emits a lazy bytestring beginning with `JMW1`, followed by a
  little-endian 32-bit CBOR header length, a CBOR header, and little-endian
  `Double` payload bytes.
- `encodeManifestCbor` canonicalizes tensor order by name and serializes the
  current `CheckpointManifest`.
- `decodeManifestCbor` round-trips the current local manifest representation.
- `manifestContentSha` hashes the deterministic manifest CBOR bytes.
- `PointerWrite`, `PointerWriteResult`, and `applyPointerWrite` model the local
  CAS decision used by the eventual MinIO pointer writer.
- `JitML.Checkpoint.Store` writes blob and manifest objects if absent, advances
  the latest pointer through `applyPointerWrite`, and reads manifests by content
  SHA from a local filesystem root.
- Live MinIO conditional-write effects and richer typed advance predicates
  remain target runtime validation.

### Validation

1. `encodeJmw1` emits the expected `JMW1` marker, CBOR header length, and
   little-endian `Double` payload bytes for local callers.
2. `jitml-unit` verifies deterministic manifest CBOR encoding/decoding and
   content hashing.
3. `jitml-unit` verifies successful and conflicting pointer-CAS decisions.
4. `jitml-unit` verifies the local checkpoint store writes objects/manifests and
   reads the latest inference path.

## Sprint 10.3: Bit-Determinism Contract and Retention Reconciler ✅

**Status**: Done
**Implementation**: `src/JitML/App.hs`, `src/JitML/Plan/Plan.hs`
**Docs to update**: `documents/engineering/determinism_contract.md`,
`documents/engineering/checkpoint_format.md`

### Objective

Land the local determinism documentation tie-in and `jitml internal gc` summary
surface. Real retention graph traversal and MinIO deletion remain target work.

### Deliverables

- `documents/engineering/determinism_contract.md` records the target
  same-substrate and cross-substrate tolerance methodology.
- `jitml internal gc <experiment-hash> --dry-run` renders a generic
  Plan/Apply retention plan.
- Normal `jitml internal gc <experiment-hash>` currently prints
  `gc: checkpoint retention policy reconciled`.
- Pointer live-set traversal, `LastN` policy application, blob reaping,
  `gc_reaped` events, and no-op exit `3` are not implemented yet.

### Validation

1. `jitml internal gc <experiment-hash> --dry-run` emits the typed plan.
2. `jitml internal gc <experiment-hash>` prints the local reconciliation
   summary.
3. Live retention and MinIO deletion validation remain target work.

## Sprint 10.4: Inference-Only Read Path ✅

**Status**: Done
**Implementation**: `src/JitML/Checkpoint/Format.hs`,
`src/JitML/Checkpoint/Store.hs`,
`src/JitML/App.hs`
**Docs to update**: `documents/engineering/checkpoint_format.md`,
`documents/engineering/daemon_architecture.md`

### Objective

Land the current inference-only summary helper consumed by local command and
test bodies, plus the local latest-pointer → manifest → inference read path.
Live MinIO pointer reads, live manifest fetches, and kernel-handle loading
remain target runtime work.

### Deliverables

- `inferFromManifest` adds a deterministic bias derived from the number of
  manifest tensors to each input value.
- `inferFromLatestCheckpoint` reads the latest pointer from the local checkpoint
  store, fetches the addressed manifest, and runs the deterministic inference
  helper.
- `jitml inference run` constructs a small local manifest and prints the
  deterministic inference summary.
- `jitml inspect replay <manifest-sha>` is registered and currently prints a
  command summary from `src/JitML/App.hs`.
- Live `loadInferenceCheckpoint`, live MinIO pointer reads, weight-only blob
  loading, and FFI kernel handles are not implemented yet.

### Validation

1. `cabal test jitml-cross-backend` exercises `inferFromManifest` across the
   local substrate list.
2. `jitml-unit` exercises `inferFromLatestCheckpoint` against the local
   checkpoint store.
3. `jitml inference run experiments/mnist.dhall` prints the deterministic
   local inference summary.
4. Weight-only GET traces and FFI loading remain target validation.

## Doctrine Sections Cited

- [../HASKELL_CLI_TOOL.md → Plan / Apply](../HASKELL_CLI_TOOL.md) (Sprints 10.3, 10.4)
- [../HASKELL_CLI_TOOL.md → Test Organization](../HASKELL_CLI_TOOL.md) (Sprint 10.4 — local `jitml-cross-backend` body consumes `inferFromManifest`)
- [../HASKELL_CLI_TOOL.md → Reconcilers: Idempotent Mutation as a Single Command](../HASKELL_CLI_TOOL.md) (Sprint 10.3 — current local `jitml internal gc` command summary; full no-op exit `3` remains target work)

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/checkpoint_format.md` — current local
  `CheckpointManifest`, manifest CBOR codec/content hash, binary `.jmw1`
  encoder, manifest pointer, local checkpoint object store, latest-pointer
  inference helper, and inference summary helper; target split-blob layout,
  live MinIO write protocols, typed advance predicates, retention reconciler,
  and real inference-only read path.
- `documents/engineering/determinism_contract.md` — same-substrate bit-
  equality contract, cross-substrate tolerance methodology, GC determinism.
- `documents/engineering/daemon_architecture.md` — `InferenceHandler`
  lifecycle.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- `system-components.md → Checkpoint and Inference Components` rows remain
  aligned with `src/JitML/Checkpoint/Format.hs` and the command surfaces in
  `src/JitML/App.hs`.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [development_plan_standards.md](development_plan_standards.md)
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
