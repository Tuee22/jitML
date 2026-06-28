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
[phase-13-no-caveat-model-runtime.md](phase-13-no-caveat-model-runtime.md),
[../README.md](../README.md)
**Generated sections**: none

> **Purpose**: Stand up the checkpoint and inference surface:
> split-blob object-key renderers, a small typed manifest, pure pointer-CAS
> decisions, a local deterministic CBOR manifest codec/content hash, a
> binary `.jmw1` encoder/decoder, a filesystem-backed local checkpoint store,
> `jitml internal gc` summary output, deterministic inference summaries,
> and the inference request/result protobuf byte contract. Sprint `10.6`
> reopens this surface for architecture-aware model-family manifests,
> preprocessing/output decoders, replay pointers, and no-caveat checkpoint
> reload across every runtime family.

## Phase Status

✅ **Done** (reopened and re-closed 2026-06-26 for Sprint `10.10` —
checkpoint manifests, readiness, TensorBoard metadata, and inference
eligibility for fixed-budget trained artifacts). Sprint `10.9` remains historically closed: `runInternalSeedDemoCheckpoints`' hardcoded `demoWeights` ramp
(byte-identical across all five seeds) is replaced with `seededDemoCheckpoints`:
distinct, provenance-tagged, **self-describing seeded fixture** weights per family (four
softmax MLP classifiers + one AlphaZero policy/value-shaped net), each
carrying per-layer tensor shapes + a class-count output spec so Sprint `14.3` can reshape
them. Validation is complete: grep-clean for the ramp, the `jitml-unit` "demo checkpoints
(Sprint 10.9)" distinctness/self-describing case, `jitml-e2e` 23/23, `check-code` from
the rebuilt `jitml:local` image, and this phase's own self-contained `linux-cpu` live
family-distinct `jitml inference run` proof after a 109-step bootstrap and live MinIO
seeding. Sprint `13.2` re-exercises the path in its full-runtime re-attest but no longer
gates Phase 10. All prior Sprints `10.1`–`10.9` remain historical `✅ Done`;
Sprint `10.10` is now closed.

✅ **Done** (reopened 2026-06-23 for Sprint `10.8`; unblocked by Phase 2's 2026-06-24
close, **re-closed 2026-06-24**) — the checkpoint GC retention is now sourced from the
durable-state registry's `checkpoints` store (`JitML.Project.Config`'s typed
`RetentionPolicy`), retiring the hardcoded `LastN 5` literal in `runInternalGc`.
Validated: `jitml-unit` 219/219 (incl. "checkpoint GC retention is registry-sourced
(LastN 5)"). All prior Sprints `10.1`–`10.7` remain `✅ Done`; the prior closure
history follows.

✅ **Done — common-shape reopen (Pulsar ML-Workflow convergence) closed on its
retained surface (Sprint `10.7`).** The `Work*` envelope family
(`JitML.Work.Envelope`: `WorkCommand`/`WorkEvent`/`WorkResult` correlated by
`callId`, parse-don't-validate wire boundary, `callId` dedup fold), the **`.ready`
readiness gate** (opaque `ArtifactRef` mintable only from a completed training
derivation — checkpoint manifest `step ≥ 1` — so "infer on an untrained model" is
unrepresentable), and the **single-Engine compute collapse** (`engineWeightedInference`
replaces the triplicated demo/CLI/daemon dispatch) are landed and validated
**statically in-container** (`check-code`, `docs check`, `jitml-unit` 206/206) and
**live on `linux-cpu`** (`jitml-integration` 71/71, inference round-trip). The
remaining **publish-only async behavior** (CLI/demo publish a `WorkCommand` instead
of computing) is an ownership-transfer to Phase `11` Sprint `11.10` (shared
websocket/publish infrastructure) per standards rules E/M. See
[README.md](README.md) → Closure Status, the shared
[../documents/engineering/pulsar_ml_workflow.md](../documents/engineering/pulsar_ml_workflow.md)
contract, and [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md). The
prior closure narrative below is retained as dated history.

✅ **Done** (reopened 2026-06-14; re-closed 2026-06-15). Sprint `10.6`
expands this phase from weighted
Dense-MLP checkpoint inference to architecture-aware checkpoint,
preprocessing, output decoding, and inference reload for every model family the
no-caveat runtime trains. The manifest/load-path/demo-endpoint code is in the
worktree and the live linux-cpu, linux-cuda, and apple-silicon integration
lanes all passed. The final Apple Silicon closure run used a live
`apple-silicon` publication with all seven components ready and
`./.build/jitml test jitml-integration --apple-silicon`, which passed 71 / 71
including the 19-test `Live` group.

✅ **Historical closure** (re-closed 2026-06-11 after Sprint `10.5`). The checkpoint format,
MinIO-backed latest-pointer reads, and weighted inference read path are the
supported surface. The synthetic manifest-only helper `inferFromManifest` and
the default Store wrappers around it are deleted; `Service.Workload`'s default
inference callback now fails closed with `weighted inference runner required`.
Production inference uses `loadInferenceCheckpointWithWeights` plus the selected
substrate's weighted checkpoint runner, while `loadInferenceCheckpointWith`
remains only an explicit injected-runner hook.

✅ **Done** (2026-05-25). Every owned code-surface obligation closed:
split-blob object-key renderers, manifest CBOR codec with canonical
ordering, `.jmw1` wire format, local pointer-CAS decision surface,
filesystem-backed checkpoint write/read helpers, retention reconciler surface
(`RetentionPolicy`, `walkLiveSet`, `buildGcPlan`), inference proto
envelope codec, and the proto-lens cross-language bindings for
`inference.proto`. Live MinIO conditional writes + checkpoint
round-trip + GC publish are owned by
[phase-15-linux-cuda-and-cluster-closure.md](phase-15-linux-cuda-and-cluster-closure.md)
Sprint `15.7`. Production weight loading (CUDA + Linux CPU) is owned by
Phase `15` Sprint `15.11`; Apple Metal weight loading is owned by
[phase-16-apple-silicon-closure.md](phase-16-apple-silicon-closure.md)
Sprint `16.5`. Per-substrate ULP tolerance documentation is owned by
[phase-17-cross-substrate-and-handoff.md](phase-17-cross-substrate-and-handoff.md)
Sprint `17.1`.

The phase owns
[Exit Definition](README.md#exit-definition) item 7 (split-blob `.jmw1`
format with the typed manifest, inference-only read path, bit-determinism
contract holding within the per-substrate ULP tolerance methodology).
**Met today**: the typed `CheckpointManifest` now carries the full
split-blob shape (weights, optimizer state, RNG streams, monotonic
`manifestStep`, per-metric values, parent-manifest lineage SHA) plus Sprint
`10.6` model-family metadata: architecture metadata, preprocessing metadata,
output decoders, weight-layout descriptors, replay/transcript pointers, and
per-substrate artifact identity. `emptyManifest` is the convenience builder.
The split-blob object-key renderers, deterministic manifest CBOR codec (with
canonical ordering across tensors / optimizer parts / RNG parts / metrics /
architecture inputs and outputs / preprocessing inputs / output decoders /
artifact pointers),
`manifestContentSha`, `.jmw1` encoder, pointer-CAS decision surface,
and the filesystem-backed local checkpoint store with explicit injected-runner
and weighted inference loaders (`loadInferenceCheckpointWith`,
`loadInferenceCheckpointWithWeights`) are all in place.
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
coverage. Live checkpoint-store validation against the HTTP MinIO interpreter,
the user-facing live `jitml inference run` path, live `gc_reaped` publish, and
per-substrate runtime exercise are owned by the live-runtime closure phases
rather than Phase `10`'s local format/read-path surface.
The local Linux CPU inference runner hook
(`loadInferenceCheckpointWith` + `JitML.Engines.Local.runLinuxCpuCheckpointInference`)
validates the latest-pointer → manifest → generated-kernel FFI path against the
filesystem-backed `HasMinIO` instance. The weighted hook
(`loadInferenceCheckpointWithWeights` +
`JitML.Engines.Local.runLinuxCpuWeightedCheckpointInference`) decodes weight-only
`.jmw1` blobs through `HasMinIO` before running the generated weighted kernel.
Detailed live-runtime obligations remain owned by Phases `15` / `16`.
`loadInferenceCheckpointWith` and `loadInferenceCheckpointWithWeights` validate
the addressed manifest's experiment hash and content SHA before invoking a
runner, and `loadWeightTensors` rejects `.jmw1` payloads whose decoded element
count does not match the manifest tensor shape. `Web.Server` no longer creates
inline policy/value demo networks for `/api/inference`, `/api/images`, or
`/api/connect4/move`; Sprint `11.9` later supplies the injected checkpoint
runtime handler for the current browser panel routes, including generic tensor
inference and checkpoint comparison.

### Current Implementation Scope

The worktree implements a `CheckpointManifest`, `TensorBlob`, optimizer/RNG
blob metadata, split-blob object-key renderers, pointer-CAS decisions,
`manifestPointer`, deterministic `encodeManifestCbor` / `decodeManifestCbor`
/ `manifestContentSha`, and binary `encodeJmw1` encoder with `JMW1` magic, CBOR
header length, and little-endian `F64` payload bytes. `src/JitML/Proto/Inference.hs` mirrors
`proto/jitml/inference.proto` with text render/parse helpers plus
proto3-compatible byte codecs for `InferenceRequest` and `InferenceResult`.
`src/JitML/Checkpoint/Store.hs` adds a local
object-store interpreter for write-once payloads, manifest writes/reads,
latest pointer CAS, retention planning,
local manifest discovery for `jitml internal gc`, `HasMinIO`-backed GC
execution, `HasMinIO`-backed weighted inference checkpoint loading, and
`loadInferenceCheckpointWith`, which lets a caller run the loaded weight-only
manifest through an explicit injected engine, and `loadInferenceCheckpointWithWeights`,
which loads decoded `.jmw1` weights before invoking the weighted runner. The same module also provides
`writeCheckpointSnapshotWithMinIO` for the checkpoint write path over the
`HasMinIO` conditional-write/CAS boundary. The filesystem-backed instance
validates the local Linux CPU generated-kernel FFI runner and the weighted local
runner that consumes decoded `.jmw1` values. Live checkpoint writes after a real
training step, live `gc_reaped` Pulsar publishing, and live per-substrate
runtime exercise remain in Phases `15` / `16`.
The Sprint `10.6` worktree also includes model-family manifest metadata,
content-SHA/experiment validation before inference, tensor payload shape checks
for decoded weights, and fail-closed demo REST routes that no longer instantiate
inline demo networks.

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
  [phase-15-linux-cuda-and-cluster-closure.md](phase-15-linux-cuda-and-cluster-closure.md)
  Sprint `15.7`.

## Sprint 10.2: `.jmw1` Wire Format and Manifest CBOR ✅

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
- `JitML.Checkpoint.Store.writeCheckpointSnapshotWithMinIO` writes tensor
  blobs and manifest CBOR through `HasMinIO.putBlobBytesIfAbsent` and advances
  the latest pointer through `HasMinIO.casPointer`; existing identical objects
  are treated idempotently before the pointer CAS decision.
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
  [phase-15-linux-cuda-and-cluster-closure.md](phase-15-linux-cuda-and-cluster-closure.md)
  Sprint `15.7`.

## Sprint 10.3: Bit-Determinism Contract and Retention Reconciler ✅

**Status**: Done
**Owned obligations after refactor**: code-surface only. Live MinIO blob
deletion plus `gc_reaped` Pulsar event publication migrated to Phase `15`
Sprint `15.7`. The per-substrate ULP tolerance measurement migrated to
Phase `17` Sprint `17.1`.
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
  MinIO + Pulsar `gc_reaped` publish is owned by the checkpoint-GC closure
  path.

### Validation

1. `jitml internal gc <experiment-hash> --dry-run` emits the typed plan.
2. `jitml internal gc <experiment-hash>` prints the reconciliation
   summary.
3. Transferred live validation: the bit-determinism contract is verified by
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
  [phase-15-linux-cuda-and-cluster-closure.md](phase-15-linux-cuda-and-cluster-closure.md)
  Sprint `15.7`. The per-substrate ULP tolerance measurement is owned by
  [phase-17-cross-substrate-and-handoff.md](phase-17-cross-substrate-and-handoff.md)
  Sprint `17.1`.

## Sprint 10.4: Inference-Only Read Path ✅

**Status**: Done
**Owned obligations after refactor**: code-surface only. Cross-language
proto-lens bindings for `inference.proto` closed on 2026-05-24
(`gen/Proto/Jitml/Inference.hs` + `gen/Proto/Jitml/Inference_Fields.hs`
re-exported by the cabal library; `jitml-daemon-lifecycle` validates
the local proto3 bytes decode through
`Proto.Jitml.Inference.InferenceRequest` round-trip). The
user-facing live `jitml inference run` MinIO path and per-substrate production
weight loading (Linux CPU + CUDA) migrated to Phase `15`
Sprints `15.11` / `15.12`. Apple Metal production weight loading
migrated to Phase `16` Sprint `16.5`.
**Implementation**: `src/JitML/Checkpoint/Format.hs`,
`src/JitML/Checkpoint/Store.hs`,
`src/JitML/App.hs`
**Docs to update**: `documents/engineering/checkpoint_format.md`,
`documents/engineering/daemon_architecture.md`

### Objective

Land the inference-only read path: latest pointer → manifest → explicit runner,
plus the weighted latest-pointer → manifest → `.jmw1` weight loading path used
by substrate checkpoint inference. Live MinIO pointer reads, live manifest
fetches, and production runtime exercise are closed by Phase `10` Sprint
`10.9` and the later per-lane closure phases.

### Deliverables

- `loadInferenceCheckpointWith` reads the latest pointer and manifest through
  `HasMinIO`, reduces the manifest to weight-only parts, and delegates execution
  to an explicit caller-provided runner.
- `loadInferenceCheckpointWithWeights` extends that hook by loading and
  decoding weight-only `.jmw1` tensor blobs through `HasMinIO` before invoking
  the caller-provided runner.
- `JitML.Engines.Local.runLinuxCpuCheckpointInference` validates the local
  Linux CPU generated-kernel FFI path from a loaded checkpoint manifest.
  `runLinuxCpuWeightedCheckpointInference` validates the same generated-kernel
  path while consuming decoded weight values from `loadInferenceCheckpointWithWeights`;
  Sprint `10.6` / Phase `13` expand production per-substrate live exercise to
  every no-caveat model-family checkpoint and inference path.
- `jitml inference run` fails closed without a live publication and uses the
  selected substrate's weighted checkpoint runner when live MinIO is available.
- Checkpoint/inference loaders validate manifest identity and report real
  manifest metadata instead of a synthetic inference summary. The old public
  `inspect replay` command was retired by Phase `1` Sprint `1.16`.
- `proto/jitml/inference.proto` declares `InferenceRequest` and
  `InferenceResult`, and `JitML.Proto.Inference` round-trips both through
  proto3-compatible bytes using packed repeated doubles for input/output.

### Validation

1. `jitml-unit` exercises checkpoint manifests, pointer reads, and
   backend-independent weight-only tensor selection.
2. `jitml-integration` exercises `loadInferenceCheckpointWith` and
   `loadInferenceCheckpointWithWeights` against the filesystem-backed
   `HasMinIO` instance, then runs the loaded manifest through the local Linux
   CPU generated-kernel FFI path.
3. `jitml-daemon-lifecycle` verifies inference request/result protobuf byte
   round-trips.
4. Transferred live validation: `jitml inference run` reads the latest
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
- The user-facing `jitml inference run` live MinIO path is owned by
  [phase-15-linux-cuda-and-cluster-closure.md](phase-15-linux-cuda-and-cluster-closure.md)
  Sprint `15.12`.
- Per-substrate production weight loading: Linux CPU oneDNN and Linux
  CUDA are owned by Phase `15` Sprint `15.11`; Apple Metal is owned by
  [phase-16-apple-silicon-closure.md](phase-16-apple-silicon-closure.md)
  Sprint `16.5`.

## Sprint 10.5: Remove the Synthetic Inference Offset ✅

**Status**: Done
**Implementation**: `src/JitML/Checkpoint/Format.hs`,
`src/JitML/Checkpoint/Store.hs`, `src/JitML/Service/Workload.hs`,
`src/JitML/Engines/{Local,CudaLocal,MetalLocal}.hs` (checkpoint runners),
`src/JitML/App.hs` (`runInference`)
**Docs to update**: `../documents/engineering/checkpoint_format.md`, `system-components.md`

### Objective

Remove the fabricated `+ nTensors/100` inference offset that stood in for the
real substrate weighted kernel, so no read path emits a synthetic number. Owns
the inference-read slice of [Exit Definition](README.md#exit-definition) item 7.

### Deliverables

- The three engine checkpoint runners (`runLinuxCpuCheckpointInference` and
  peers) return the faithful kernel output with no added bias.
- `inferFromManifest` is deleted, together with the default Store wrappers that
  turned a manifest read into an inference result. Real inference is the
  substrate weighted kernel via `loadInferenceCheckpointWithWeights` →
  `run*WeightedCheckpointInference`.
- `Service.Workload` default inference fails closed with `weighted inference
  runner required`; runtime self-inference supplies the weighted runner.
- `jitml inference run` fails closed (`InferenceCheckpointMissing`) when no live
  publication is present, instead of the `emptyManifest` + synthetic summary,
  and reports real checkpoint metadata rather than a synthetic inference value.

### Validation

- `docker compose run --rm jitml jitml test jitml-unit --linux-cpu` — 196 / 196.
- `docker compose run --rm jitml jitml test jitml-daemon-lifecycle --linux-cpu`
  — 31 / 31.
- `docker compose run --rm jitml cabal test jitml-integration
  --test-options='-p loadInferenceCheckpointWithWeights'` — focused offline case
  passed.
- `docker compose run --rm jitml cabal test jitml-integration
  --test-options='-p boundaries'` — focused offline HasMinIO checkpoint-write
  case passed.

### Current Validation State

Closed on 2026-06-11 in the container with the validation commands above. A
broader `jitml-integration -p conditional` run also exercised the changed offline
checkpoint snapshot case successfully before matching the intentionally
fail-closed `Live` conditional test; without
`.build/runtime/cluster-publication.json`, live integration tests fail by design.

### Remaining Work

- No Sprint 10.5 code-surface Remaining Work remains. Live per-lane exercise of
  the weighted read path remains owned by Phase 15 / Phase 14.

## Sprint 10.6: No-Caveat Checkpoint and Inference Matrix ✅

**Status**: Done
**Implementation**: `src/JitML/Checkpoint/{Format,Store}.hs`,
`src/JitML/Engines/{Local,CudaLocal,MetalLocal}.hs`,
`src/JitML/Proto/Inference.hs`, `src/JitML/App.hs`,
`src/JitML/Web/Server.hs`
**Docs to update**: `documents/engineering/checkpoint_format.md`,
`documents/engineering/training_workloads.md`, `system-components.md`,
`legacy-tracking-for-deletion.md`

### Objective

Make checkpoint reload and inference complete for every model family the
runtime can train, so browser interactions and CLI evaluation use real
checkpoint-backed models rather than demo-only or Dense-only readers.

### Deliverables

- ✅ `CheckpointManifest` records architecture metadata, preprocessing metadata,
  output decoding metadata, model-family identifiers, replay/transcript pointers
  where applicable, and per-substrate artifact identity for every SL/RL/
  AlphaZero/tuning workflow.
- ✅ `.jmw1` blobs remain the shared F64 weight payload, while the manifest now
  records the model-family weight layout needed to interpret those blobs beyond
  Dense-only readers.
- ✅ `jitml eval`, `jitml rl eval`, and `jitml inference run` use the same
  checkpoint loaders, and those loaders fail closed when the latest pointer,
  manifest body, manifest experiment/content SHA, or tensor payload shape is
  absent or incompatible.
- ✅ Image, handwriting, tensor, RL policy, AlphaZero game, and generic
  inference metadata share the same manifest output-decoder contract.
- ✅ Demo-only inline networks in `Web.Server` are removed from the active HTTP
  route implementation; Sprint `11.9` later replaces the fail-closed browser
  route shape with an injected checkpoint runtime handler for current REST
  panels.

### Historical Validation

- ✅ `docker compose run --rm jitml jitml test jitml-unit --linux-cpu` passed
  197 / 197 on 2026-06-15.
- ✅ `docker compose run --rm jitml jitml test jitml-integration --linux-cpu`
  passed 71 / 71 on 2026-06-15 against the live
  `.build/runtime/cluster-publication.json`, including the 19-test `Live`
  group. The earlier non-live subset
  `cabal test jitml-integration --test-options='-p !/Live/'` passed 51 / 51.
- ✅ `docker compose run --rm jitml docker build -t jitml:local -f
  ./docker/Dockerfile .` passed on 2026-06-15 after changing the Dockerfile's
  Cabal repository URL to `https://hackage.haskell.org/`. This reproduced the
  exact bootstrap-owned legacy-builder child path, reached `check-code: ok`,
  built the PureScript bundle, and tagged `jitml:local`.
- ✅ `./bootstrap/linux-cpu.sh up` passed on 2026-06-15 after the image-build
  fix, printing `bootstrap: linux-cpu reconciled` and `bootstrap: live phased
  rollout executed 84 steps`. It wrote
  `.build/runtime/cluster-publication.json` for `linux-cpu` on edge port `9091`
  with `harbor`, `minio`, `pulsar`, `postgres`, `observability`,
  `jitml-service`, and `jitml-demo` all `ready`.
- ✅ `./bootstrap/linux-cuda.sh up` passed on 2026-06-15 after the same
  image-build fix, printing `bootstrap: linux-cuda reconciled` and
  `bootstrap: live phased rollout executed 84 steps`. It wrote
  `.build/runtime/cluster-publication.json` for `linux-cuda` on edge port
  `9092` with `harbor`, `minio`, `pulsar`, `postgres`, `observability`,
  `jitml-service`, and `jitml-demo` all `ready`.
- ✅ `docker compose run --rm jitml jitml test jitml-daemon-lifecycle --linux-cpu`
  passed 34 / 34 on 2026-06-15.
- ✅ `docker compose run --rm jitml-cuda jitml test jitml-integration --linux-cuda`
  passed 71 / 71 on 2026-06-15 against the live `linux-cuda`
  `.build/runtime/cluster-publication.json`, including the 19-test `Live`
  group. The long `WorkflowMatrix` live case completed in 899.12s, the live PPO
  cartpole convergence case completed in 117.47s, and the full stanza passed in
  1039.19s. The earlier no-publication attempt failed the 19 live cases by
  design, while the non-live cases passed 52 / 52 under
  `cabal test -fcuda jitml-integration --test-show-details=direct`.
- ✅ `./bootstrap/apple-silicon.sh up` passed on 2026-06-15 after the
  image-build fix and fixed-bridge installation, printing
  `bootstrap: live phased rollout executed 84 steps`. It wrote
  `.build/runtime/cluster-publication.json` for `apple-silicon` on edge port
  `9090` with `harbor`, `minio`, `pulsar`, `postgres`, `observability`,
  `jitml-service`, and `jitml-demo` all `ready`; routed `/healthz` returned
  `HTTP/1.1 200 OK`.
- ✅ `./.build/jitml test jitml-integration --apple-silicon` passed 71 / 71 on
  2026-06-15 against the live `apple-silicon`
  `.build/runtime/cluster-publication.json`, including the 19-test `Live`
  group.
- ✅ `docker compose run --rm jitml jitml check-code` passed on 2026-06-15.
- ✅ `docker compose run --rm jitml jitml docs check` passed on 2026-06-15.
- ✅ `git diff --check` passed on 2026-06-15.

### Remaining Work

- No Sprint 10.6 Remaining Work remains. The broader all-model
  train/checkpoint/reload/evaluate matrix is owned by Phase `13`.

## Doctrine Sections Cited

- [../README.md → Plan / Apply commands](../README.md#doctrine-scope) (Sprints 10.3, 10.4)
- [../README.md → Test-suite stanzas](../README.md#test-suite-stanzas) (Sprint 10.4 — unit / integration bodies consume explicit checkpoint runner hooks and the weighted checkpoint loader)
- [../README.md → Reconcilers and No-Op Exit](../README.md#doctrine-scope) (Sprint 10.3 — `jitml internal gc` command summary and local no-op exit `3`; live MinIO deletion / Pulsar `gc_reaped` events remain Sprint 10.3 Remaining Work)

## Sprint 10.7: Async `Work*` Inference Workflow and `.ready` Readiness Gate ✅

**Status**: Done on its retained surface (Work* envelope family + `.ready`/
`ArtifactRef` readiness gate + single-Engine compute collapse — static + live
validated). The remaining **publish-only async behavior** (the CLI/demo publish a
`WorkCommand` and render the streamed `WorkResult` instead of computing locally)
is an ownership-transfer to Phase `11` Sprint `11.10`, which owns the
websocket/publish-only infrastructure that both the demo panels and the CLI share
(standards rule E — one obligation in one place; rule M — forward transfer to a
later phase).
**Depends-On**: Sprint `5.13` (Coordinator topic algebra), Sprint `5.14`
(one-binary role model — Engine is the sole compute role)
**Implementation**: `src/JitML/Work/Envelope.hs` (new), `src/JitML/App.hs`,
`src/JitML/Service/Workload.hs`, `src/JitML/Service/Runtime.hs`,
`src/JitML/Checkpoint/Format.hs`, `test/integration/Main.hs`,
`test/daemon-lifecycle/Main.hs`
**Docs to update**: `../documents/engineering/checkpoint_format.md`,
`../documents/engineering/training_workloads.md`,
`../documents/engineering/pulsar_ml_workflow.md`, `system-components.md`,
`legacy-tracking-for-deletion.md`

### Objective

Recast inference as an **asynchronous `Work*` workflow** owned by the single
**Engine**, and make a serveable artifact **unrepresentable** unless it comes from
a completed derivation. Implements the `Work*` envelope family and the `Artifact +
readiness contract` of
[../documents/engineering/pulsar_ml_workflow.md](../documents/engineering/pulsar_ml_workflow.md),
and retires the "Triplicated inference path" ledger row. Adopts `At-Least-Once
Event Processing`, `Capability Classes and Service Errors`, and `Parse, don't
validate` from [../README.md](../README.md).

### Deliverables

- Add `JitML.Work.Envelope` with `WorkCommand { callId, workflow, lane,
  subjectRef, artifactRef?, payload, replyTopic }`, `WorkEvent { callId, workflow,
  progress }`, `WorkResult { callId, status, outputRefs }`, correlated by
  `callId`; training and inference share this shape.
- Collapse the triplicated load→pick-runner→run-kernel logic (demo
  `weightedInferenceForBrowser`, CLI `inferenceForSubstrate`/`runInference`, daemon
  `daemonWorkloadDispatcherWithWeightedInference`) into the single Engine consumer
  path; the CLI/demo publish a `WorkCommand` and render the streamed `WorkResult`.
- Make a serveable `ArtifactRef` obtainable **only** from a training `WorkResult`
  whose checkpoint manifest has `step ≥ 1` and a resolvable `latest` pointer; the
  coordinator writes a `.ready` sentinel **last**. A malformed wire command parses
  into a typed rejection event, never a silent bad state.
- Move the "Triplicated inference path" ledger row to `Completed`.

### Validation

- `docker compose run --rm jitml jitml test jitml-daemon-lifecycle --linux-cpu`
  covers the `Work*` correlation, the `.ready` gate (infer-before-ready →
  typed rejection), and single-Engine dispatch.
- `docker compose run --rm jitml jitml test jitml-integration --linux-cpu`
  (live `Work*` inference round-trip through the Engine; per standards rule M(b)
  this `linux-cpu` lane is the closure gate, with the accelerator lanes attested
  in Phases `15`/`16`).
- `docker compose run --rm jitml jitml docs check` and `jitml check-code`.

### Validation State (host-native, apple-silicon lane)

- **Landed and validated host-native.** `JitML.Work.Envelope` defines the
  `Work*` family (`WorkCommand`/`WorkEvent`/`WorkResult`/`WorkStatus`) correlated
  by `CallId`, the **parse-don't-validate** wire boundary (`parseWorkCommand` →
  typed `WorkRejection`), and the producer-side `dedupByCallId` pure fold
  (effectively-once). The **readiness gate** is enforced in the types: `ArtifactRef`
  is opaque and obtainable only via `mintArtifactRef` (`Just` iff checkpoint
  manifest `step ≥ 1`), with `readinessSentinelKey` naming the `.ready` witness —
  so "infer over an untrained model" is unrepresentable (`parseWorkCommand Infer`
  with no ready artifact → `ArtifactNotReady`).
- **Triplicated compute collapsed.** The per-substrate weighted-runner dispatch is
  single-sourced in `engineWeightedInference`; the demo handler, the `jitml
  inference run` CLI (`inferenceForSubstrate`), and the daemon consumer all route
  through it. The "Triplicated inference path" ledger row moved to `Completed`.
- `cabal build lib:jitml` warning-clean (`-Wall`); `jitml-unit` **206 / 206**
  (three new `Work*` cases: readiness gate, typed-rejection parse, effectively-once
  dedup), `jitml-daemon-lifecycle` **35 / 35** (behavior-preserving).
- **Container gates pass authoritatively.** `docker compose build jitml` exits `0`
  with the baked `jitml check-code` layer clean (fourmolu + hlint + warning-clean
  `-fcuda` build) on the full Phase `5`+`10` change set; and against the built
  `jitml:local` image: `jitml docs check` → `docs check: ok`, `jitml test
  jitml-unit --linux-cpu` → **206 / 206**, `jitml test jitml-daemon-lifecycle
  --linux-cpu` → **35 / 35**.
- **Live `linux-cpu` validation.** Against a freshly bootstrapped cluster
  (`jitml bootstrap --linux-cpu`, 84 steps), `jitml test jitml-integration
  --linux-cpu` passes **71 / 71** including the `Live` inference round-trip, which
  exercises the single-sourced `engineWeightedInference` through the daemon —
  confirming the compute collapse is behavior-preserving and live-correct.

### Remaining Work

- None on the retained surface. The **publish-only async behavior** (`jitml
  inference run` and the demo publish a `WorkCommand` and render the streamed
  `WorkResult` instead of computing locally) is transferred to Phase `11` Sprint
  `11.10` (it shares that sprint's websocket/publish-only infrastructure; both the
  demo panels and the CLI become thin publishers). Wiring the live
  coordinator-written `.ready` sentinel into the Engine readiness path (the pure
  gate + `ArtifactRef` minting are landed and tested) likewise lands with the
  Coordinator-role serve path in Phase `15`.

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

## Sprint 10.8: Typed `RetentionPolicy` Replaces the `LastN 5` Literal [✅ Done]

**Status**: Done (reopened 2026-06-23; re-closed 2026-06-24) — unblocked by Phase 2
Sprint `2.15`.

Replace the hardcoded checkpoint-GC retention literal with the typed `RetentionPolicy`
declared per `StoreEntry` in the durable-state registry, so retention is a validated
config value (`LastN 0` etc. rejected at typecheck) rather than a magic constant:

- New `JitML.Project.Config.lookupStoreRetention` reads the `checkpoints` store's typed
  `RetentionPolicy` from the registry; `App.hs` `checkpointsGcRetention` maps it onto
  the GC-supported subset and feeds `runInternalGc`'s `buildGcPlan`.
- The hardcoded `retention = CheckpointStore.LastN 5` literal is gone; the GC retention
  is now registry-sourced (the registry declares `checkpoints` retention `LastN 5`).

### Exit Definition

- The checkpoint GC reads its retention from the registry-sourced `RetentionPolicy`;
  no hardcoded `LastN 5` retention value remains in `App.hs`.

### Validation State (2026-06-24)

- `cabal build exe:jitml` links; no `LastN 5` retention literal remains in `App.hs`
  (only doc-comment references).
- `jitml-unit` **219/219**, incl. "checkpoint GC retention is registry-sourced (LastN 5)".

### Remaining Work

- None on the retention source-of-truth surface. (Mapping the age/bytes
  `RetentionPolicy` variants onto an object-store ILM policy is a follow-on; the
  manifest-chain GC uses the `KeepAll`/`LastN` subset, registry-sourced.)
- Documentation Requirements: **met (2026-06-24)** — `checkpoint_format.md` notes the GC
  retention is a typed, registry-sourced `RetentionPolicy` (not the former `LastN 5`
  literal), cross-linking `durable_state_dsl.md`; the README durable-state registry note
  covers the retention prose.

## Sprint 10.9: Real Trained Demo Checkpoints (Delete the Synthetic Weight Ramp) [✅ Done]

**Status**: Done — reopened 2026-06-24, re-closed 2026-06-25 on the `linux-cpu` lane.
The code landed and validated host-native (grep-clean + the `jitml-unit` "demo
checkpoints (Sprint 10.9)" distinctness/self-describing case + `jitml-e2e` 23/23), then
this phase's own live proof ran after a 109-step `linux-cpu` bootstrap: seeding all five
checkpoints into live MinIO and `jitml inference run` returning family-distinct outputs
for every seeded family. Phase 8 Sprint `8.13` and Phase 9 Sprint `9.13` (the real
training surfaces this reuses) have landed.

**Implementation**: `src/JitML/App.hs` (`seededDemoCheckpoints` + `SeededDemoCheckpoint`,
`demoClassifierDataset`, `mlpLayerTensorSpecs`, `buildShapedWeightCheckpointSnapshot` /
`writeMinIOWeightCheckpointShaped`, the rewritten `runInternalSeedDemoCheckpoints`),
`test/unit/Main.hs` (the distinctness test).

The hardcoded `demoWeights = [0.05 + ((i*7+3) mod 11)/20 | i in 0..255]` ramp
(byte-identical across all five seeded "models") is **removed**.
`runInternalSeedDemoCheckpoints` now seeds `seededDemoCheckpoints`: one **distinct,
provenance-tagged, self-describing fixture** checkpoint per demo family — the four classifier
families (`mnist-deep-mlp` 784→24→10, `cifar-imagenet` 3072→24→10, `generic-tensor-demo`
and `generic-tensor-demo-candidate` 4→8→3, distinct seeds) train a real softmax MLP
(`Classifier.trainClassifier`) on a small in-code separable task and flatten the trained
`MlpParams`; `connect4-alphazero` trains a real policy/value network through self-play
(`runOneGenerationOfSelfPlay`) and flattens it (`policyValueNetToFlat`). Each checkpoint's
manifest metric map records the run's provenance (training loss/accuracy or arena
win-rate, plus the seed).

**Self-describing checkpoints — the 10.9 → 14.3 shape contract.** `writeMinIOWeightCheckpointShaped`
records each model's **per-layer tensor shapes** (`W1/b1/W2/b2` in the `mlpParamsToFlat`
flatten order) plus an input `TensorSpec` and an output `TensorSpec` whose width is the
**class count** (`logits` `[10]`/`[3]`; AlphaZero `policy_value` `[8]`), so the checkpoint
satisfies "correct per-tensor shapes" and the downstream multi-layer-forward consumer
(Sprint `14.3`, "output width = class count") can reshape the flat `.jmw1` blob into its
layers without a hardcoded per-family lookup. (The classifier MLP carries one extra raw
value-head output, `classes + 1`, from the shared policy/value structure; the output spec
records the semantic class count and the layer specs keep the raw tensor shapes.)

### Exit Definition

- No synthetic/hardcoded weight ramp remains in `App.hs`; each demo family's checkpoint
  is distinct, provenance-tagged, and self-describing (per-layer shapes +
  class-count output spec). The legacy ledger row for the ramp moves to `Completed`. ✅
  (code; grep-clean + the distinctness/self-describing unit test confirm the worktree.)

### Validation

- Grep clean for the ramp — **confirmed** (`demoWeights` removed; no ramp remains).
- `jitml-unit` "demo checkpoints (Sprint 10.9)" — the five families are distinct,
  non-constant, self-describing (per-layer shapes sum to the flat length),
  and the output spec width equals the class count. **Host-native, no cluster.**
- `jitml-e2e` chart/bucket guards green — **23/23**; the five demo experiment hashes are
  preserved.
- **Live (this phase owns it, `linux-cpu`):** `jitml bootstrap --linux-cpu` →
  `jitml internal seed-demo-checkpoints` → `jitml inference run` over the five seeded
  checkpoints returns family-distinct outputs. Self-contained on the `linux-cpu` host (no
  accelerator), so Phase 10 closes in numerical order. Sprint `13.2`'s `jitml test all
  --live --linux-cpu` re-exercises this path as part of the full-runtime re-attest, but
  does **not** gate Phase 10.
- **Live validation completed 2026-06-25 (`linux-cpu`):** `docker compose build jitml`
  rebuilt `jitml:local` and ran `jitml check-code: ok`; the direct compose bootstrap
  (`docker compose run --rm -e JITML_BOOTSTRAP_SKIP_IMAGE_BUILD=1 jitml jitml bootstrap
  --linux-cpu`) completed **109 steps** after reusing that fresh image; `jitml internal
  seed-demo-checkpoints` seeded all five checkpoints (MNIST 19,115 weights, generic 76
  weights each, CIFAR 74,027 weights, Connect 4 1,672 weights); sequential live
  `jitml inference run --experiment-hash ...` returned family-distinct outputs:
  `mnist-deep-mlp` `[-0.14406323432922363,-5.201629549264908e-2]`,
  `generic-tensor-demo` `[0.10279107093811035,-0.7217661738395691]`,
  `generic-tensor-demo-candidate` `[-1.4564321041107178,0.761154294013977]`,
  `cifar-imagenet` `[0.19340509176254272,3.598484769463539e-2]`, and
  `connect4-alphazero` `[0.2905381917953491,0.38741081953048706]`.

## Sprint 10.10: Inference-Eligible Checkpoints and Convergence Statistics [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Checkpoint/Format.hs`,
`src/JitML/Checkpoint/Store.hs`, `src/JitML/App.hs`,
`src/JitML/Observability/TensorBoard.hs`,
`src/JitML/Observability/TbSidecar.hs`
**Docs to update**: `../documents/engineering/checkpoint_format.md`,
`../documents/engineering/training_metrics_and_splits.md`,
`../documents/engineering/purescript_frontend.md`, `system-components.md`

### Objective

Make the checkpoint manifest the enforcement point for trained-artifact
eligibility. A manifest may be inspectable or resumable before completion, but
only a completed fixed-budget manifest with convergence statistics can be used
for inference, evaluation, RL rollout, or browser interaction.

### Deliverables

- Add completed-budget fields, convergence-statistics records, TensorBoard
  scalar run metadata, and readiness witness data to the manifest contract.
- Introduce an opaque `InferenceEligibleCheckpoint` value minted only after the
  manifest's completed budget and convergence-statistics predicate pass.
- Refactor `eval`, `inference run`, demo handlers, `rl eval`, `rl rollout`, and
  AlphaZero game endpoints to accept the eligibility value, not raw weights.
- Preserve raw manifest loading for inspection/resume without allowing it to
  flow into inference.

### Validation

- `docker compose run --rm jitml jitml test jitml-unit --linux-cpu`
- `docker compose run --rm jitml jitml test jitml-integration --linux-cpu`
- `docker compose run --rm jitml jitml test jitml-e2e --linux-cpu`
- `docker compose run --rm jitml jitml docs check`

### Current Validation State

- `docker compose run --rm jitml cabal test jitml-unit --test-show-details=direct`
  passed **224 / 224**.
- `docker compose run --rm jitml cabal test jitml-e2e --test-show-details=direct`
  passed **23 / 23**.
- `docker compose run --rm jitml cabal run jitml -- test jitml-e2e --linux-cpu`
  passed through the project wrapper with **23 / 23** tests.
- `docker compose run --rm jitml cabal test jitml-integration --test-show-details=direct`
  passed the non-live checkpoint loader cases, including an
  infer-before-complete rejection for a manifest without
  `CompletedTraining`. The remaining integration failures were the expected live
  cluster failures from missing `.build/runtime/cluster-publication.json`.
- `docker compose run --rm jitml cabal test jitml-integration --test-show-details=direct`
  later passed **53** non-live cases after the checkpoint-browser selector
  gained a negative test that omits manifests without `CompletedTraining`; the
  **19** live cases still fail fast without a bootstrapped cluster publication.
- `./bootstrap/linux-cpu.sh up` completed the live `linux-cpu` rollout
  (**111** steps), and
  `docker compose run --rm jitml cabal test jitml-integration --test-show-details=direct`
  passed **72 / 72** against the bootstrapped cluster, including live checkpoint
  snapshot, GC, inference, TensorBoard sidecar, tune, RL, and AlphaZero
  checkpoint paths.
- `docker compose run --rm jitml cabal run jitml -- docs check` passed
  (`docs check: ok`).
- `docker compose run --rm jitml cabal run jitml -- check-code` passed
  (`check-code: ok`).
- `docker compose run --rm jitml jitml test all --live --linux-cpu` passed the
  aggregate lane with **8 / 8** stanzas green. The run includes live checkpoint
  snapshot, GC, inference, TensorBoard sidecar, tuning, RL, AlphaZero
  checkpoint paths, and `jitml-backends` **23 / 23** through the
  `InferenceEligibleCheckpoint` gate.
- Live Playwright passed **15 / 15** against the rebuilt `linux-cpu` edge after
  reseeding all eight demo checkpoints as completed, inference-eligible
  manifests.

### Remaining Work

- None.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [development_plan_standards.md](development_plan_standards.md)
- [../README.md](../README.md)
