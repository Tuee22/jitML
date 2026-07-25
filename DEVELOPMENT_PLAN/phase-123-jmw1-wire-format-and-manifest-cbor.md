# Phase 123: `.jmw1` Wire Format and Manifest CBOR

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: .jmw1 Wire Format and Manifest CBOR. Single-session phase migrated from legacy Sprint 10.2 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 123.1: `.jmw1` Wire Format and Manifest CBOR [✅ Done]

**Status**: Done
**Owned obligations after refactor**: code-surface only. Live MinIO
conditional-write validation and CAS retry coverage migrated to Phase
`15` Sprint `15.7`.
**Implementation**: `src/JitML/Checkpoint/Format.hs`,
`src/JitML/Checkpoint/Store.hs`
**Docs to update**: `documents/engineering/checkpoint_format.md`

### Objective

Land the current `.jmw1` encoder, local deterministic manifest CBOR codec,
manifest-content SHA helper, local pointer-CAS decision surface, and local
write-once object-store interpreter. Live MinIO conditional-write effects are
validated by Phase `15` Sprint `15.7`.

### Deliverables

- `encodeJmw1` emits a lazy bytestring beginning with `JMW1`, followed by a
  little-endian 32-bit CBOR header length, a CBOR header, and little-endian
  `Double` payload bytes. `decodeJmw1` validates the same local payload shape
  and returns the decoded `Double` values.
- `encodeManifestCbor` canonicalizes tensor order by name and serializes the
  current `CheckpointManifest`.
- `decodeManifestCbor` round-trips the manifest representation.
- `manifestContentSha` hashes the deterministic manifest CBOR bytes.
- `PointerWrite`, `PointerWriteResult`, and `applyPointerWrite` model the local
  CAS decision used by the eventual MinIO pointer writer.
- `JitML.Checkpoint.Store` writes blob and manifest objects if absent, advances
  the latest pointer through `applyPointerWrite`, and reads manifests by content
  SHA from a local filesystem root.
- `JitML.Checkpoint.Store.checkpointObjectRef` adapts the checked-in
  bucket-prefixed split-key renderers to the live `HasMinIO` boundary by
  carrying bucket `jitml-checkpoints` separately and stripping that prefix from
  the object key.
- Store's internal MinIO snapshot primitive writes tensor blobs and manifest
  CBOR through `HasMinIO.putBlobBytesIfAbsent` and advances a completed
  transaction through `HasMinIO.casPointer`; the public candidate/completed
  writers enforce exact identity and adoption semantics around that primitive.
- The typed `AdvancePredicate` ADT (`AdvanceLatest`,
  `AdvanceBestMaximised "<metric>"`, `AdvanceBestMinimised
  "<metric>"`) plus `applyAdvancePredicate` evaluate the typed CAS
  predicates from README → Concurrency model. Live MinIO conditional-write
  effects are validated by Phase `15` Sprint `15.7`.

### Validation

1. `encodeJmw1` emits the expected `JMW1` marker, CBOR header length, and
   little-endian `Double` payload bytes; `decodeJmw1` round-trips that local
   `F64` payload.
2. `jitml-unit` verifies deterministic manifest CBOR encoding/decoding and
   content hashing.
3. `jitml-unit` verifies successful and conflicting pointer-CAS decisions.
4. `jitml-unit` verifies the checkpoint store writes objects/manifests
   and reads the latest inference path.
5. `jitml-integration` verifies the `HasMinIO` snapshot writer against the
   filesystem-backed MinIO instance, including latest-pointer CAS conflict.
6. Transferred live validation: `putBlobIfAbsent` against MinIO returns the
   blob's ETag on first write and `SEConflict` on subsequent identical
   PUTs through `If-None-Match: *`; `applyPointerWrite` against MinIO
   honours `If-Match: <etag>` and surfaces `412` as `SEConflict`; the
   retry harness backs off per the typed `RetryPolicy`.

### Remaining Work

- No sprint-owned code-surface Remaining Work remains. Live MinIO
  conditional-write validation and CAS retry integration coverage are
  owned by
  [phase-15-linux-cuda-and-cluster-closure.md](README.md#legacy-to-new-phase-map)
  Sprint `15.7`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
