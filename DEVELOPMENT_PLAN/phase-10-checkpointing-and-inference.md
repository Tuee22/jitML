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

🔄 **Active**. The phase owns
[Exit Definition](README.md#exit-definition) item 7 (split-blob `.jmw1`
format with the typed manifest, inference-only read path, bit-determinism
contract holding within the per-substrate ULP tolerance methodology).
**Met today**: the typed `CheckpointManifest`, split-blob object-key
renderers, deterministic manifest CBOR codec, `manifestContentSha`,
`.jmw1` encoder, pointer-CAS decision surface, and the filesystem-backed
local checkpoint store with `inferFromManifest` /
`inferFromLatestCheckpoint`. **Unmet today**: Sprints `10.1`–`10.4` owe
optimizer/RNG split-blob parts, experiment-hash derivation from the
resolved Dhall, live MinIO `If-None-Match` / `If-Match` effects,
retention reconciler graph traversal and blob reaping, real
kernel-handle loading, and the per-substrate ULP tolerance measured from
real cross-substrate runs. Detailed remaining work lives in each sprint's
`### Remaining Work` block below.

### Current Implementation Scope

The worktree implements a `CheckpointManifest`, `TensorBlob`, split-blob
object-key renderers, pointer-CAS decisions, `manifestPointer`,
deterministic `encodeManifestCbor` / `decodeManifestCbor` /
`manifestContentSha`, binary `encodeJmw1` encoder with `JMW1` magic, CBOR
header length, and little-endian `F64` payload bytes, plus
`inferFromManifest`. `src/JitML/Checkpoint/Store.hs` adds a local
object-store interpreter for write-once payloads, manifest writes/reads,
latest pointer CAS, and inference from the latest checkpoint. Live MinIO
conditional-write effects, retention graph traversal, kernel-handle
loading, and real demo/frontend checkpoint reads live in the sprints'
`### Remaining Work` blocks below.

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

## Sprint 10.1: Storage Layout and Split-Blob Schema 🔄

**Status**: Active
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

1. `src/JitML/Checkpoint/Format.hs` exposes the `TensorBlob`,
   `CheckpointManifest`, and `manifestPointer` helpers.
2. `cabal test jitml-cross-backend` exercises the manifest-based inference
   helper.
3. `jitml-unit` verifies the split-key renderers.
4. Live validation (target): a real MinIO bucket holds blobs and
   manifests under the addressed split-blob paths after a real training
   step; `experiment-hash` is derived from the resolved Dhall and
   referenced by both the bucket prefix and the pointer key.

### Remaining Work

- Grow `CheckpointManifest` to carry optimizer state and RNG split-blob
  parts beyond the weight tensors.
- Implement experiment-hash derivation
  `sha256(resolved-dhall || substrate-fingerprint)` and thread it through
  the manifest, blob, and pointer renderers.
- Validate the bucket layout against a live MinIO instance once Sprint
  `4.3` brings up the conditional-write server.

## Sprint 10.2: `.jmw1` Wire Format and Manifest CBOR 🔄

**Status**: Active
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
   little-endian `Double` payload bytes.
2. `jitml-unit` verifies deterministic manifest CBOR encoding/decoding and
   content hashing.
3. `jitml-unit` verifies successful and conflicting pointer-CAS decisions.
4. `jitml-unit` verifies the checkpoint store writes objects/manifests
   and reads the latest inference path.
5. Live validation (target): `putBlobIfAbsent` against MinIO returns the
   blob's ETag on first write and `SEConflict` on subsequent identical
   PUTs through `If-None-Match: *`; `applyPointerWrite` against MinIO
   honours `If-Match: <etag>` and surfaces `412` as `SEConflict`; the
   retry harness backs off per the typed `RetryPolicy`.

### Remaining Work

- Implement the live MinIO put-blob-if-absent and pointer-CAS effects
  through the `HasMinIO` capability class from Sprint `5.4`.
- Add integration coverage in `jitml-integration` (Sprint `12.2`) that
  exercises the CAS retry against a live MinIO instance.
- Grow the typed advance predicates beyond simple
  `pointerWriteExpectedETag` matching (e.g. monotonic step number, best
  metric).

## Sprint 10.3: Bit-Determinism Contract and Retention Reconciler 🔄

**Status**: Active
**Implementation**: `src/JitML/App.hs`, `src/JitML/Plan/Plan.hs`
**Docs to update**: `documents/engineering/determinism_contract.md`,
`documents/engineering/checkpoint_format.md`

### Objective

Land the determinism documentation tie-in and `jitml internal gc`
summary surface; grow real retention graph traversal and MinIO deletion
per `### Remaining Work` below.

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
2. `jitml internal gc <experiment-hash>` prints the reconciliation
   summary.
3. Live validation (target): the bit-determinism contract is verified by
   `jitml-cross-backend` running real cross-substrate cohorts and the
   resulting per-tensor drift fitting the committed ULP tolerance band;
   `jitml internal gc` traverses the pointer live set, applies a `LastN`
   retention policy, reaps unreferenced blobs from MinIO, emits
   `gc_reaped` events, and exits `3` when the cluster is already at the
   target retention state.

### Remaining Work

- Implement the pointer-live-set traversal (root: `latest` and every
  `best/<metric>` and `trial/<...>` pointer) and the `LastN` retention
  policy application.
- Wire the blob-reaping path through the live `HasMinIO` capability
  class.
- Emit `gc_reaped` events on the platform metrics surface (Prometheus
  counter + Pulsar event) for each reaped blob/manifest.
- Make a steady-state second invocation exit `3`
  (`AppError ReconcilerNoop`).
- Add the per-substrate ULP tolerance measurement to
  `documents/engineering/determinism_contract.md` based on real
  cross-substrate runs from Sprint `12.6`.

## Sprint 10.4: Inference-Only Read Path 🔄

**Status**: Active
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

1. `cabal test jitml-cross-backend` exercises `inferFromManifest` across
   the substrate list.
2. `jitml-unit` exercises `inferFromLatestCheckpoint` against the
   checkpoint store.
3. `jitml inference run experiments/mnist.dhall` prints the deterministic
   inference summary.
4. Live validation (target): `jitml inference run` reads the latest
   pointer from MinIO bucket `jitml-checkpoints/<experiment-hash>/`,
   fetches the addressed manifest, loads weight-only blobs (no optimizer
   parts), loads the substrate-bound `KernelHandle` from the JIT cache,
   and runs real inference against the loaded weights.

### Remaining Work

- Implement live `loadInferenceCheckpoint` against MinIO through the
  `HasMinIO` capability class.
- Implement weight-only blob loading (skip optimizer/RNG parts the
  inference path does not need).
- Wire FFI `KernelHandle` loading through `JitML.Engines.Local` (and
  the future per-substrate engines) so inference actually executes the
  generated kernel.
- Implement `jitml inspect replay <manifest-sha>` to walk a real
  manifest by content SHA and replay through the deterministic inference
  helper.

## Doctrine Sections Cited

- [../HASKELL_CLI_TOOL.md → Plan / Apply](../HASKELL_CLI_TOOL.md) (Sprints 10.3, 10.4)
- [../HASKELL_CLI_TOOL.md → Test Organization](../HASKELL_CLI_TOOL.md) (Sprint 10.4 — local `jitml-cross-backend` body consumes `inferFromManifest`)
- [../HASKELL_CLI_TOOL.md → Reconcilers: Idempotent Mutation as a Single Command](../HASKELL_CLI_TOOL.md) (Sprint 10.3 — `jitml internal gc` command summary; full no-op exit `3` owned by Sprint 10.3's Remaining Work)

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
