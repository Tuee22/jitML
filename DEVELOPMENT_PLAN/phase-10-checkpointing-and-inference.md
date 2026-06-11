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
[../README.md](../README.md)
**Generated sections**: none

> **Purpose**: Stand up the checkpoint and inference surface:
> split-blob object-key renderers, a small typed manifest, pure pointer-CAS
> decisions, a local deterministic CBOR manifest codec/content hash, a
> binary `.jmw1` encoder/decoder, a filesystem-backed local checkpoint store,
> `jitml internal gc` summary output, deterministic inference summaries,
> and the inference request/result protobuf byte contract.
> Live MinIO effects, retention traversal, and
> kernel-handle loading remain target runtime work.

## Phase Status

🔄 **Active** (reopened 2026-06-10 — real-workflow refactor). The checkpoint
format and the live weighted read path shipped, but the manifest-only read used
a synthetic `inferFromManifest` (`+ nTensors/100`) and the three engine
checkpoint runners added the same fabricated offset to the real kernel output.
Sprint `10.5` removes the fabricated value: the engines return faithful output,
`inferFromManifest` is a faithful identity read, and `jitml inference run` /
`jitml inspect replay` fail closed / report real manifest metadata. See
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md). The prior
closure narrative below is retained as dated record.

✅ **Done** (2026-05-25). Every owned code-surface obligation closed:
split-blob object-key renderers, manifest CBOR codec with canonical
ordering, `.jmw1` wire format, local pointer-CAS decision surface,
filesystem-backed `inferFromManifest` /
`inferWeightsOnlyFromLatestCheckpoint`, retention reconciler surface
(`RetentionPolicy`, `walkLiveSet`, `buildGcPlan`), inference proto
envelope codec, and the proto-lens cross-language bindings for
`inference.proto`. Live MinIO conditional writes + checkpoint
round-trip + GC publish are owned by
[phase-13-linux-cuda-and-cluster-closure.md](phase-13-linux-cuda-and-cluster-closure.md)
Sprint `13.7`. Production weight loading (CUDA + Linux CPU) is owned by
Phase `13` Sprint `13.11`; Apple Metal weight loading is owned by
[phase-14-apple-silicon-closure.md](phase-14-apple-silicon-closure.md)
Sprint `14.5`. Per-substrate ULP tolerance documentation is owned by
[phase-15-cross-substrate-and-handoff.md](phase-15-cross-substrate-and-handoff.md)
Sprint `15.1`.

The phase owns
[Exit Definition](README.md#exit-definition) item 7 (split-blob `.jmw1`
format with the typed manifest, inference-only read path, bit-determinism
contract holding within the per-substrate ULP tolerance methodology).
**Met today**: the typed `CheckpointManifest` now carries the full
split-blob shape (weights, optimizer state, RNG streams, monotonic
`manifestStep`, per-metric values, parent-manifest lineage SHA);
`emptyManifest` is the convenience builder. The split-blob object-key
renderers, deterministic manifest CBOR codec (with canonical
ordering across tensors / optimizer parts / RNG parts / metrics),
`manifestContentSha`, `.jmw1` encoder, pointer-CAS decision surface,
and the filesystem-backed local checkpoint store with
`inferFromManifest` / `inferFromLatestCheckpoint` /
`inferWeightsOnlyFromLatestCheckpoint` are all in place.
`proto/jitml/inference.proto` declares the current request/result envelope
schema, and `JitML.Proto.Inference` round-trips `InferenceRequest` /
`InferenceResult` through proto3-compatible bytes. The typed
`AdvancePredicate` ADT (`AdvanceLatest`, `AdvanceBestMaximised`,
`AdvanceBestMinimised`) and `applyAdvancePredicate` evaluate the
typed CAS predicates from README → Concurrency model.
`deriveExperimentHash resolvedDhall substrateFingerprint` computes
`sha256(resolved-dhall || substrate-fingerprint)`. The GC
reconciler surface (`RetentionPolicy`, `walkLiveSet`,
`applyRetentionPolicy`, `buildGcPlan`, `GcEvent`) implements
`LastN k` retention with always-live best/trial pointer targets,
`gc_reaped` event materialisation, local filesystem manifest discovery
through `listCheckpointManifests`, and a second-invocation no-op
detection. `writeCheckpointSnapshotWithMinIO` now writes checkpoint blobs and
manifests through `HasMinIO.putBlobBytesIfAbsent` and advances the latest
pointer through `HasMinIO.casPointer`, with filesystem-backed integration
coverage. **Unmet today**: Sprints `10.2`–`10.4` still owe checkpoint-store
validation against the live HTTP MinIO interpreter after a real training step,
the user-facing live `jitml inference run` path, the live `gc_reaped` Pulsar
publish, production weight-blob loading into the non-local substrate-bound
`KernelHandle`s, and the per-substrate ULP tolerance measured from real
cross-substrate runs.
The local Linux CPU inference runner hook
(`loadInferenceCheckpointWith` + `JitML.Engines.Local.runLinuxCpuCheckpointInference`)
now validates the latest-pointer → manifest → generated-kernel FFI path
against the filesystem-backed `HasMinIO` instance. The weighted local hook
(`loadInferenceCheckpointWithWeights` +
`JitML.Engines.Local.runLinuxCpuWeightedCheckpointInference`) also decodes
weight-only `.jmw1` blobs through `HasMinIO` before running the generated
Linux CPU identity kernel. 2026-05-21 Phase `5.4` live daemon validation
exercises the default `loadInferenceCheckpoint` path against in-cluster MinIO
through `JitML.Service.MinIOSubprocess`. Detailed remaining work lives in each
sprint's `### Remaining Work` block below.

### Current Implementation Scope

The worktree implements a `CheckpointManifest`, `TensorBlob`, optimizer/RNG
blob metadata, split-blob object-key renderers, pointer-CAS decisions,
`manifestPointer`, deterministic `encodeManifestCbor` / `decodeManifestCbor`
/ `manifestContentSha`, binary `encodeJmw1` encoder with `JMW1` magic, CBOR
header length, and little-endian `F64` payload bytes, plus
`inferFromManifest`. `src/JitML/Proto/Inference.hs` mirrors
`proto/jitml/inference.proto` with text render/parse helpers plus
proto3-compatible byte codecs for `InferenceRequest` and `InferenceResult`.
`src/JitML/Checkpoint/Store.hs` adds a local
object-store interpreter for write-once payloads, manifest writes/reads,
latest pointer CAS, inference from the latest checkpoint, retention planning,
local manifest discovery for `jitml internal gc`, `HasMinIO`-backed GC
execution, `HasMinIO`-backed inference checkpoint loading, and
`loadInferenceCheckpointWith`, which lets a caller run the loaded weight-only
manifest through a concrete engine, and `loadInferenceCheckpointWithWeights`,
which loads decoded `.jmw1` weights before invoking the runner. The same module also provides
`writeCheckpointSnapshotWithMinIO` for the checkpoint write path over the
`HasMinIO` conditional-write/CAS boundary. The filesystem-backed instance now
validates the deterministic fallback, the local Linux CPU generated-kernel FFI
runner, and the weighted local runner that consumes decoded `.jmw1` values.
The Phase `5.4` live daemon validation covers the default latest-checkpoint
read against in-cluster MinIO. Live checkpoint writes after a real training
step, live `gc_reaped` Pulsar publishing, production non-local weight-blob
loading, and real demo/frontend checkpoint reads live in the sprints'
`### Remaining Work` blocks below.

## Phase Summary

This phase currently delivers the local checkpoint manifest, split-blob key,
pointer-CAS, deterministic manifest CBOR, local write-once object store, latest
pointer read path, and inference summary helpers. The target persistence layer
still uses MinIO bucket `jitml-checkpoints`, write-once blobs, If-Match CAS
pointers, and the split-blob `.jmw1` binary format; the standalone live MinIO
capability path is available through `JitML.Service.MinIOSubprocess`, while the
checkpoint store still needs live wiring. The live implementation proceeds
storage-outward: conditional checkpoint writes/reads first, then
inference from checkpoint, then training persistence, then tuning/resume
semantics.

## Sprint 10.1: Storage Layout and Split-Blob Schema ✅

**Status**: Done
**Owned obligations after refactor**: code-surface only. Live MinIO
bucket layout validation migrated to Phase `13` Sprint `13.7`.
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
- Live MinIO bucket-layout validation remains target work owned by
  Sprint 4.3.

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

- No sprint-owned code-surface Remaining Work remains. Live MinIO bucket
  layout validation through `JitML.Service.MinIOSubprocess` after a real
  training step is owned by
  [phase-13-linux-cuda-and-cluster-closure.md](phase-13-linux-cuda-and-cluster-closure.md)
  Sprint `13.7`.

## Sprint 10.2: `.jmw1` Wire Format and Manifest CBOR ✅

**Status**: Done
**Owned obligations after refactor**: code-surface only. Live MinIO
conditional-write validation and CAS retry coverage migrated to Phase
`13` Sprint `13.7`.
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
- `JitML.Checkpoint.Store.writeCheckpointSnapshotWithMinIO` writes tensor
  blobs and manifest CBOR through `HasMinIO.putBlobBytesIfAbsent` and advances
  the latest pointer through `HasMinIO.casPointer`; existing identical objects
  are treated idempotently before the pointer CAS decision.
- The typed `AdvancePredicate` ADT (`AdvanceLatest`,
  `AdvanceBestMaximised "<metric>"`, `AdvanceBestMinimised
  "<metric>"`) plus `applyAdvancePredicate` evaluate the typed CAS
  predicates from README → Concurrency model. Live MinIO
  conditional-write effects remain target runtime validation.

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
6. Live validation (target): `putBlobIfAbsent` against MinIO returns the
   blob's ETag on first write and `SEConflict` on subsequent identical
   PUTs through `If-None-Match: *`; `applyPointerWrite` against MinIO
   honours `If-Match: <etag>` and surfaces `412` as `SEConflict`; the
   retry harness backs off per the typed `RetryPolicy`.

### Remaining Work

- No sprint-owned code-surface Remaining Work remains. Live MinIO
  conditional-write validation and CAS retry integration coverage are
  owned by
  [phase-13-linux-cuda-and-cluster-closure.md](phase-13-linux-cuda-and-cluster-closure.md)
  Sprint `13.7`.

## Sprint 10.3: Bit-Determinism Contract and Retention Reconciler ✅

**Status**: Done
**Owned obligations after refactor**: code-surface only. Live MinIO blob
deletion plus `gc_reaped` Pulsar event publication migrated to Phase `13`
Sprint `13.7`. The per-substrate ULP tolerance measurement migrated to
Phase `15` Sprint `15.1`.
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
- Normal `jitml internal gc <experiment-hash>` scans
  `<cache-dir>/checkpoints/jitml-checkpoints/<experiment-hash>/manifests/`,
  prints the local retention summary (`gc: <experiment-hash> kept=<n>
  reaped=<n>`), and exits `3` on a no-op plan through
  `AppError ReconcilerNoop`.
- `JitML.Checkpoint.Store.{walkLiveSet,applyRetentionPolicy,buildGcPlan}`
  implement the pointer live-set traversal across the `latest` chain
  and `best/<m>` / `trial/<...>` always-live pointer targets,
  `LastN k` retention application, blob-reap event materialisation
  (`GcEvent` records the manifest SHA, blob SHAs, experiment hash,
  and step), and the steady-state no-op detection
  (`gcNoOp` flag flips when there are no reap events).
- `JitML.Checkpoint.Store.listCheckpointManifests` is the local manifest
  discovery hook used by the CLI reconciler. Live blob deletion through
  MinIO + Pulsar `gc_reaped` publish remain target runtime work.

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

- No sprint-owned code-surface Remaining Work remains. `gc_reaped`
  Pulsar event publication and live HTTP MinIO deletion validation are
  owned by
  [phase-13-linux-cuda-and-cluster-closure.md](phase-13-linux-cuda-and-cluster-closure.md)
  Sprint `13.7`. The per-substrate ULP tolerance measurement is owned by
  [phase-15-cross-substrate-and-handoff.md](phase-15-cross-substrate-and-handoff.md)
  Sprint `15.1`.

## Sprint 10.4: Inference-Only Read Path ✅

**Status**: Done
**Owned obligations after refactor**: code-surface only. Cross-language
proto-lens bindings for `inference.proto` closed on 2026-05-24
(`gen/Proto/Jitml/Inference.hs` + `gen/Proto/Jitml/Inference_Fields.hs`
re-exported by the cabal library; `jitml-daemon-lifecycle` validates
the local proto3 bytes decode through
`Proto.Jitml.Inference.InferenceRequest` round-trip). The
user-facing live `jitml inference run` MinIO path, `jitml inspect
replay` live MinIO manifest read, and per-substrate production weight
loading (Linux CPU + CUDA) migrated to Phase `13`
Sprints `13.11` / `13.12`. Apple Metal production weight loading
migrated to Phase `14` Sprint `14.5`.
**Implementation**: `src/JitML/Checkpoint/Format.hs`,
`src/JitML/Checkpoint/Store.hs`,
`src/JitML/App.hs`
**Docs to update**: `documents/engineering/checkpoint_format.md`,
`documents/engineering/daemon_architecture.md`

### Objective

Land the current inference-only summary helper consumed by local command and
test bodies, plus the local latest-pointer → manifest → inference read path.
Live MinIO pointer reads, live manifest fetches, and production
weight-blob-to-kernel loading remain target runtime work.

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
- `inferWeightsOnlyFromLatestCheckpoint` reads the latest pointer,
  fetches the manifest, drops `manifestOptimizer` / `manifestRng`
  parts (the inference path doesn't need them), and runs
  `inferFromManifest`. The typed `weightOnlyTensors` predicate
  selects the inference subset of the manifest.
- `loadInferenceCheckpointWith` reads the latest pointer and manifest through
  `HasMinIO`, reduces the manifest to weight-only parts, and delegates
  execution to a caller-provided runner.
- `loadInferenceCheckpointWithWeights` extends that hook by loading and
  decoding weight-only `.jmw1` tensor blobs through `HasMinIO` before invoking
  the caller-provided runner.
- `JitML.Engines.Local.runLinuxCpuCheckpointInference` validates the local
  Linux CPU generated-kernel FFI path from a loaded checkpoint manifest.
  `runLinuxCpuWeightedCheckpointInference` validates the same generated-kernel
  path while consuming decoded weight values from `loadInferenceCheckpointWithWeights`;
  production non-local per-substrate weight-blob loading remains target runtime
  work.
- `proto/jitml/inference.proto` declares `InferenceRequest` and
  `InferenceResult`, and `JitML.Proto.Inference` round-trips both through
  proto3-compatible bytes using packed repeated doubles for input/output.

### Validation

1. `cabal test jitml-cross-backend` exercises `inferFromManifest` across
   the substrate list.
2. `jitml-unit` exercises `inferFromLatestCheckpoint` against the
   checkpoint store.
3. `jitml inference run experiments/mnist.dhall --checkpoint latest`
   prints the deterministic inference summary.
4. `jitml-integration` exercises `loadInferenceCheckpointWith` and
   `loadInferenceCheckpointWithWeights` against the filesystem-backed
   `HasMinIO` instance, then runs the loaded manifest through the local Linux
   CPU generated-kernel FFI path.
5. `jitml-daemon-lifecycle` verifies inference request/result protobuf byte
   round-trips.
6. Live validation (target): `jitml inference run` reads the latest
   pointer from MinIO bucket `jitml-checkpoints/<experiment-hash>/`,
   fetches the addressed manifest, loads weight-only blobs (no optimizer
   parts), loads the substrate-bound `KernelHandle` from the JIT cache,
   and runs real inference against the loaded weights.

### Remaining Work

- Cross-language bindings for `proto/jitml/inference.proto` closed on
  2026-05-24: `gen/Proto/Jitml/Inference.hs` and
  `gen/Proto/Jitml/Inference_Fields.hs` are exposed by the cabal
  library. The new `local proto3 bytes decode through the proto-lens
  generated InferenceRequest` case in `jitml-daemon-lifecycle`
  validates that the local `encodeInferenceRequestProto` output decodes
  cleanly through `Proto.Jitml.Inference.InferenceRequest` and
  re-encodes back to bytes the local codec decodes to the original
  value (wire-format byte-equivalence).
- The user-facing `jitml inference run` live MinIO path and `jitml
  inspect replay` live MinIO manifest read are owned by
  [phase-13-linux-cuda-and-cluster-closure.md](phase-13-linux-cuda-and-cluster-closure.md)
  Sprint `13.12`.
- Per-substrate production weight loading: Linux CPU oneDNN and Linux
  CUDA are owned by Phase `13` Sprint `13.11`; Apple Metal is owned by
  [phase-14-apple-silicon-closure.md](phase-14-apple-silicon-closure.md)
  Sprint `14.5`.

## Sprint 10.5: Remove the Synthetic Inference Offset [Active]

**Status**: Active
**Implementation**: `src/JitML/Checkpoint/Format.hs` (`inferFromManifest`),
`src/JitML/Engines/{Local,CudaLocal,MetalLocal}.hs` (checkpoint runners),
`src/JitML/App.hs` (`runInference`, `assertManifestShaMatches`)
**Docs to update**: `../documents/engineering/checkpoint_format.md`, `system-components.md`

### Objective

Remove the fabricated `+ nTensors/100` inference offset that stood in for the
real substrate weighted kernel, so no read path emits a synthetic number. Owns
the inference-read slice of [Exit Definition](README.md#exit-definition) item 7.

### Deliverables

- The three engine checkpoint runners (`runLinuxCpuCheckpointInference` and
  peers) return the faithful kernel output with no added bias.
- `inferFromManifest` is a faithful identity read (no fabricated value); real
  inference is the substrate weighted kernel via
  `loadInferenceCheckpointWithWeights` → `run*WeightedCheckpointInference`.
- `jitml inference run` fails closed (`InferenceCheckpointMissing`) when no live
  publication is present, instead of the `emptyManifest` + synthetic summary;
  `jitml inspect replay` reports the verified manifest's real metadata
  (content SHA + weight-tensor count), not a synthetic inference value.

### Validation

- `docker compose run --rm jitml cabal test jitml-unit` (the `inferFromManifest`
  round-trip cases hold under the identity read).
- `jitml check-code` + `jitml docs check` green inside `jitml:local`.

### Current Validation State

Landed; host lib type-checks. Container: `check-code` + `jitml-unit` validated at
the Phase 10 boundary.

### Remaining Work

- Route the remaining manifest-only read sites (`Checkpoint.Store` synthetic
  load variants, `Service.Workload`, and the `Web.Server` demo endpoint — the
  last owned by Sprint 11.8) through the substrate weighted kernel, then delete
  `inferFromManifest`. The live device-weighted read is Phase 13 (Sprint 13.11).

## Doctrine Sections Cited

- [../README.md → Plan / Apply commands](../README.md#doctrine-scope) (Sprints 10.3, 10.4)
- [../README.md → Test-suite stanzas](../README.md#test-suite-stanzas) (Sprint 10.4 — local `jitml-cross-backend` body consumes `inferFromManifest`)
- [../README.md → Reconcilers and No-Op Exit](../README.md#doctrine-scope) (Sprint 10.3 — `jitml internal gc` command summary and local no-op exit `3`; live MinIO deletion / Pulsar `gc_reaped` events remain Sprint 10.3 Remaining Work)

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/checkpoint_format.md` — current local
  `CheckpointManifest`, manifest CBOR codec/content hash, binary `.jmw1`
  encoder, manifest pointer, local checkpoint object store, `HasMinIO`
  snapshot writer, latest-pointer inference helper, and inference summary
  helper; target split-blob layout, live MinIO write protocols, typed advance
  predicates, retention reconciler, inference protobuf byte contract, and real
  inference-only read path.
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
- [../README.md](../README.md)
