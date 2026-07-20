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
> and the inference request/result protobuf byte contract. Completed Sprints
> `10.6` and `10.12` own the retained exact V2 supervised runtime artifact,
> strict loaded-model execution, and proof admission from a stable,
> byte-verified persisted snapshot. The canonical supervised worker plan and
> raw-to-refined completion values remain retained prerequisites of that
> persisted boundary.

## Phase Status

✅ **Done**. Sprint `10.6` is Done on immutable descriptor
`sha256:0147b37fafd53c01669705a5723ce91482d0fd545da4b9da523df8dacc3e9ba8`:
the byte-exact V2 supervised representation, complete persisted inference
program, strict Store-to-engine execution, and trained-versus-loaded parity all
passed for the eleven supervised ProductRows. Sprint `10.12` is Done on stable
persisted-checkpoint admission rather than proof construction from caller-held
values. Sprints `10.1`–`10.12` are Done on their retained surfaces. The
canonical `SupervisedPlan`, `PlanId`, and refined `CompletedTraining` work
remains a structural prerequisite of the exact persisted boundary; Store alone
mints opaque admitted artifacts after address, manifest, pointer, and blob
verification. Phase `19` Sprint `19.4` is now Active and consumes that admitted
boundary.

**Historical retained closure.** ✅ **Done** (reopened 2026-06-29; re-closed 2026-06-30 for Sprint `10.11`).
Checkpoint manifests, readiness, TensorBoard metadata, and inference
eligibility for fixed-budget trained artifacts remain historically validated,
and local checkpoint object-key validation now returns typed failures before
filesystem path construction. `objectPathForKey` / `safeRelativePath` reject
empty, absolute, and parent-traversing keys as `Left Text`; local
write/read/list helpers propagate those values; app call sites render them as
`InvalidConfig`; and local `jitml internal gc --experiment-hash ...` rejects
unsafe hashes without process termination. Validation passed:
`docker compose run --rm jitml jitml test jitml-unit --linux-cpu`
(**237 / 237**), `docker compose run --rm jitml jitml test
jitml-integration --linux-cpu` (**77 / 77**), and `docker compose run --rm
jitml jitml check-code` (`check-code: ok`). At that historical checkpoint no
Phase `10` blocker was recorded; this evidence does not address the reopened V2
artifact or admission scope.

Historical Sprint `10.10` closure:
checkpoint manifests, readiness, TensorBoard metadata, and inference
eligibility for fixed-budget trained artifacts. Sprint `10.9` remains historically closed: `runInternalSeedDemoCheckpoints`' hardcoded `demoWeights` ramp
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
Sprint `15.7`. Historical production weight-loading validation (CUDA + Linux
CPU) was owned by Phase `15` Sprint `15.11`; historical Apple Metal weight
loading was owned by
[phase-16-apple-silicon-closure.md](phase-16-apple-silicon-closure.md)
Sprint `16.5`. Reopened Sprint `10.6` now owns strict V2 reconstruction and
dispatch for all three engines; refreshed accelerator lane evidence remains in
Phases `29` and `30`. Per-substrate ULP tolerance documentation is owned by
[phase-17-cross-substrate-and-handoff.md](phase-17-cross-substrate-and-handoff.md)
Sprint `17.1`.

The phase owns
[Exit Definition](README.md#exit-definition) item 7 (split-blob `.jmw1`
format with the typed manifest, inference-only read path, bit-determinism
contract holding within the per-substrate ULP tolerance methodology).
**Retained pre-V2 implementation**: the typed `CheckpointManifest` carries the
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
detection. The distinct candidate/completed Store writers publish checkpoint
blobs and manifests through exact absent-or-byte-identical operations;
candidate writes never advance `latest`, while completed writes require
`CompletedTraining` and exact pointer CAS. The older live checkpoint-store,
user-facing inference, `gc_reaped`,
and per-substrate runs remain historical validation. They do not validate V2;
the current strict reconstructed execution contract is Sprint `10.6`, followed
by refreshed single-accelerator product lanes.
The local Linux CPU inference runner hook
(`loadInferenceCheckpointWith` + `JitML.Engines.Local.runLinuxCpuCheckpointInference`)
validates the latest-pointer → manifest → generated-kernel FFI path against the
filesystem-backed `HasMinIO` instance. The weighted hook
(`loadInferenceCheckpointWithWeights` +
`JitML.Engines.Local.runLinuxCpuWeightedCheckpointInference`) decodes weight-only
`.jmw1` blobs through `HasMinIO` before running the generated weighted kernel.
Those Phase `15` / `16` results remain historical runtime evidence.
`loadInferenceCheckpointWith` and `loadInferenceCheckpointWithWeights` validate
the addressed manifest's experiment hash and content SHA before invoking a
runner, and `loadWeightTensors` rejects `.jmw1` payloads whose decoded element
count does not match the manifest tensor shape. `Web.Server` no longer creates
inline policy/value demo networks for `/api/inference`, `/api/images`, or
`/api/connect4/move`; Sprint `11.9` later supplies the injected checkpoint
runtime handler for the current browser panel routes, including generic tensor
inference and checkpoint comparison.

### Current Gap and Retained Implementation Scope

The worktree implements the hidden, versioned `SupervisedPlan` boundary with
positive epoch, training-example, evaluation-example, batch-example, and
derived optimizer-update quantities. `TrainingRunConfig` carries only the
canonical resolved transport, its `PlanId`, and the operational Pulsar
endpoint; worker load re-refines the transport and rejects identity or
canonicalization drift before effects. `TrainingBudget`, finite convergence
measurements, passed criteria, and `CompletedTraining` hide their proof
constructors. Versioned completion DTOs are re-refined on
decode and completed Training/RL/Tune protocol variants carry mandatory proof
rather than `Maybe CompletedTraining`. Those retained in-memory types do not
establish persisted admission.

The worktree also implements a `CheckpointManifest`, `TensorBlob`, optimizer/RNG
blob metadata, split-blob object-key renderers, pointer-CAS decisions,
`manifestPointer`, deterministic `encodeManifestCbor` / `decodeManifestCbor`
/ `manifestContentSha`, and binary `encodeJmw1` encoder with `JMW1` magic, CBOR
header length, and little-endian `F64` payload bytes. `src/JitML/Proto/Inference.hs` mirrors
`proto/jitml/inference.proto` with text render/parse helpers plus
proto3-compatible byte codecs for `InferenceRequest` and `InferenceResult`.
`src/JitML/Checkpoint/Store.hs` adds local and `HasMinIO` interpreters for
exact absent-or-byte-identical payload/manifest writes, latest pointer CAS,
retention planning,
local manifest discovery for `jitml internal gc`, `HasMinIO`-backed GC
execution, opaque stable admission, and weighted inference checkpoint loading.
`loadInferenceCheckpointWith` and `loadInferenceCheckpointWithWeights` consume
Store-admitted completed values before invoking their explicit runners. The
same module provides distinct candidate/completed local and `HasMinIO` write
transactions over the conditional-write/CAS boundary. The filesystem-backed instance
validates the local Linux CPU generated-kernel FFI runner and the weighted local
runner that consumes decoded `.jmw1` values. The prior live checkpoint-write,
`gc_reaped`, and per-substrate runtime results from Phases `15` / `16` remain
historical retained evidence; they do not validate the reopened V2 boundary.

**Historical audit finding (2026-07-18).** The reopened supervised write/read
boundary used to let ProductRow tensor names fall through to
`GenericModelFamily`, write a topology-free architecture, verify a manifest by
decode-and-re-encode equivalence, and load physical weights without binding
their exact fetched bytes to a graph-ordered virtual layout. Store also read the
latest pointer only once, so a successful storage write/read was not a persisted
admission proof.

**Current landed V2 state.** Product supervised writes now require the exact
training-returned runtime, canonical ProductRow and `PlanId`, trainer-owned
successful mini-batch update count, exact dataset-at-read identity, completion,
and exact initial/final JMW1 bytes. They persist the exact V2 outer/body bytes,
one physical `supervised.weights` object, and checked graph-derived virtual
`Flat` slices. Every V2 payload has one closed origin: either the authoritative
ProductRow projection or the exact canonical generic `SupervisedPlan`
transport. Generic completion binds that exact plan and cannot masquerade as a
ProductRow artifact; a generic run below the external convergence bar completes
successfully without minting a checkpoint. Mounted workers write successful
generic completions directly through the in-cluster MinIO boundary. Strict
reload reconstructs and executes the persisted graph through the selected
engine, and supervised V1 remains inspection/resume only. Sprint `10.6` is Done
after the immutable-image, live publication, exact parity, full-suite, docs,
code-quality, whitespace, and Rule-M gates passed. Sprint `10.12`'s Store
boundary now reads exact `P1`, verifies the addressed outer/body bytes, reads
exact `P2`, and only then binds every physical payload before returning its
opaque admitted value. Sprint `10.12` is Done after its API hardening,
owned-document alignment, and complete validation gate passed. Sprint `19.4`
applies that same Store boundary to canonical non-supervised Product V1:
companion evidence is bound by exact manifest pointer and physically verified
before completed admission; this does not make supervised V1 eligible.

## Phase Summary

The retained phase surface includes local and `HasMinIO` object-key/CAS
primitives, `.jmw1`, weighted loader seams, canonical supervised plans, and
refined training completion. The phase uses one exact V2 supervised runtime
artifact and a non-forgeable persisted admission boundary.
Candidate checkpoints remain proof-free. Supervised V1 remains inspectable and
resumable but cannot be admitted for inference; V2 eligibility requires the
exact stable Store read and physical binding owned by Sprint `10.12`.
Canonical non-supervised ProductRows retain their frozen V1 wire form and may
become Store-admitted completed evidence only after exact manifest, final
weight, completion, and companion-transcript binding. Generic/non-product V1
does not gain that refinement.

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

## Sprint 10.6: Exact V2 Supervised Runtime Artifact [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Checkpoint/{Format,WeightCodec,Writer,Store}.hs`,
`src/JitML/Codegen/RuntimeOperations{Cpu,Cuda,Metal}.hs`,
`src/JitML/Engines/{Local,CudaLocal,MetalLocal,Loader,RuntimeOperations,RuntimeOperationsDevice,RuntimeOperationsCuda,RuntimeOperationsMetal}.hs`,
`src/JitML/Engines/Rng.hs`,
`src/JitML/SL/{Architecture,Classifier,Regression,RuntimeArtifact,TrainingExecution}.hs`,
`src/JitML/Product/{Completion,Matrix,Publisher}.hs`,
`src/JitML/{App,Service/Command}.hs`,
`test/unit/{Main,RegressionStandardization,RuntimeOperationsAccelerators,SupervisedCheckpointV2,SupervisedRuntimeArtifact}.hs`,
`test/integration/Main.hs`, `test/sl-canonicals/Main.hs`
**Docs to update**: `../documents/engineering/checkpoint_format.md`,
`../documents/engineering/training_workloads.md`,
`../documents/engineering/training_metrics_and_splits.md`,
`../documents/engineering/determinism_contract.md`,
`../documents/engineering/jit_codegen_architecture.md`,
`../documents/engineering/apple_silicon_metal_headless_builds.md`,
`../documents/engineering/haskell_code_guide.md`,
`system-components.md`, `legacy-tracking-for-deletion.md`

### Objective

The supervised runtime persists and reloads one byte-exact, topology-complete
V2 inference artifact before any completion or inference proof is admitted.
New supervised runtime writes use V2. A V2 artifact retains exact identities
for its final outer bytes and embedded canonical body bytes, stores exactly one
physical `supervised.weights` `.jmw1` payload, and describes node parameters as
graph-ordered virtual `Flat` slices into that payload. It is the complete
inference program actually executed by training, including preprocessing and
output decoding, not a generic-family or topology-free approximation.
Supervised V1 manifests remain decodable and inspectable but cannot be
inference eligible.

### Deliverables

- The V1 encoder and its golden bytes remain frozen for compatibility. Decode
  structurally dispatches V2, then V1, then the retained legacy form; after a
  form is structurally recognized, any validation failure is final and cannot
  fall through to another decoder.
- A V2 outer envelope carries the V2 version, the SHA-256 identity of the exact
  canonical embedded body bytes, and those body bytes. The checkpoint address
  is the SHA-256 identity of the exact final outer-envelope bytes. Address
  calculation and validation retain the fetched bytes and never substitute
  decode-and-re-encode equivalence.
- New supervised runtime writes persist the exact addressed V2 bytes and expose
  both exact identities without exporting a forgeable addressed-manifest
  constructor. Every supervised V2 manifest names exactly one physical tensor,
  `supervised.weights`, encoded as one `.jmw1`; no per-node physical weight
  object is emitted.
- The supervised V2 checkpoint is the complete runtime inference artifact. It
  records the exact graph actually executed during training; every node kind,
  attribute, shape, edge, parameter identity, and graph-ordered virtual `Flat`
  slice; the exact preprocessing and output-decoder program; canonical row and
  `PlanId` identity; dataset provenance; completion evidence; and the physical
  weights. A generic-family, topology-free, descriptive-only, or
  reconstructed-from-row-name representation is invalid.
- For the current compact `cifar10-vit` executable, that exact program records
  RGB means and positive scales fitted from the training partition only and
  repeated in pixel-major order, patch size/stride `4/4` over `32×32×3`,
  **64** non-overlapping patch tokens, and token-mixing count `64`, followed by
  the executed LayerNorm, token-mixing MLP, attention, mean-pool, and classifier
  operations. This is exact persistence of the current `[LayerSpec]` /
  `[LayerState]` Mixer executable. It does not satisfy Sprint `23.1`'s
  single-typed-graph obligation or Sprint `24.1`'s literal small-ViT obligation,
  both of which remain Blocked in their numerical order.
- Virtual `Flat` slices carry graph-ordered node/parameter identities, shapes,
  and dtype. Refinement derives each offset and element length from those
  ordered shapes with checked arithmetic; redundant offsets/lengths are not
  persisted. The derived slices are non-overlapping, in bounds, and exactly
  cover the single physical flat vector.
- California Housing is split into its exact raw training and held-out
  partitions before any statistic is fitted. Feature means/scales and target
  mean/scale are fitted from the training partition only, applied unchanged to
  training and held-out examples, and persisted exactly. Loaded inference
  applies those feature transforms and inverse-transforms predictions into the
  declared target units; held-out and inference values never influence the
  fitted statistics.
- Canonical classification training permutes only the complete materialized
  training partition once per one-based epoch. For epoch `e`, it draws exactly
  `length trainSet` words using
  `splitMixWords (length trainSet) (deriveSplitMixSeed (SplitMixSeed
  (fromIntegral clfSeed)) (fromIntegral e))`, zips each whole example with its
  word and original zero-based index, and stable-sorts ascending exactly on
  `(word, originalIndex)` before forming mini-batches. Validation and test stay
  in fixed decoded order. The permutation changes no authoritative example or
  batch quantity, batch size/count, examples-processed total, or actual
  optimizer-update count. The tuning exact-update path retains its fixed-order
  cyclic batches.
- The validated supervised ProductRow descriptor owns the exact finite,
  positive learning rate and includes it in descriptor equality, rendering,
  semantic fields, and `PlanId`. The canonical recipe is `3e-3` for
  `fashion-mnist-resnet`, `1.1e-3` for `cifar10-resnet20`, `1.5e-3` for
  `cifar10-vit`, and `1e-3` for the other eight rows. Publisher passes that
  refined value unchanged to the
  selected trainer; both classification and California Housing regression
  consume it, and no environment override or executor default may reinterpret
  it.
- V2 construction binds completion evidence to the persisted artifact. The
  completed and manifest final-weight hashes equal SHA-256 of the exact
  `supervised.weights` `.jmw1` bytes; the initial-weight hash identifies the
  exact canonical `.jmw1` encoding consumed at initialization; and the
  completion/manifest dataset digest identifies the exact canonical dataset
  artifact bytes read for the bound row, split, and plan. A missing or unequal
  hash, dataset identity, `PlanId`, observed budget, or update count is a typed
  construction failure.
- Every V2 runtime carries exactly one refined origin. Product Publisher writes
  bind the authoritative ProductRow projection and retain the strict row,
  experiment, substrate, budget, and `PlanId` checks. Generic supervised
  commands bind the exact canonical `SupervisedPlan` transport, re-refine it on
  load, reject canonicalization or identity drift, and cannot occupy a
  ProductRow experiment identity. A generic run that completes its declared
  budget below the external convergence bar returns a typed successful miss and
  publishes no checkpoint; a passing generic run persists its exact-plan V2
  artifact. Mounted service workers perform that write through in-cluster
  MinIO rather than a host publication mirror.
- The Store V2 decode/reconstruction path produces an executable only from the
  persisted graph, transforms, decoder, slices, and physical bytes. Once V2 is
  recognized, an unsupported operation, absent field, invalid slice, transform
  mismatch, decoder mismatch, or backend incompatibility fails with a typed
  error; it never falls back to V1/legacy decoding, a generic or Dense model, a
  demo network, caller-supplied topology, the pure/reference engine, or another
  substrate.
- The reconstructed artifact executes its complete graph through the selected
  real CPU, CUDA, or Metal engine. Every operation required by the eleven
  authoritative supervised ProductRows has a strict engine implementation; an
  unavailable operation fails rather than being skipped or replaced. Linux CPU
  and Linux CUDA generate content-addressed `kernel.cc` / `kernel.cu` sources
  implementing a status-returning version-`1` `double` ABI with the complete
  `0xff` capability mask. Apple Silicon generates MSL inside content-addressed
  `.metal.json`, validates the same logical ABI/capability/symbol contract, and
  dispatches through the fast-math-off fixed bridge with explicit
  `Double`↔fp32 transport. All compile, load, symbol, ABI, capability,
  contract, native-status, execution, and nested selected-backend MLP failures
  are typed; the production engine adapters install no
  `RuntimeOperations.host*` callbacks.
- For all eleven rows in `matrixFloor.floorSupervisedRows`, validation compares
  the training-returned model with the Store-loaded V2 artifact on the same
  held-out/inference inputs. Weight bytes/hashes, preprocessing, slice-to-node
  assignment, decoded output, row identity, and `PlanId` agree exactly;
  `sameSubstrateV2Tolerance` bounds maximum absolute floating-output difference
  by `1e-9` for the `double` `linux-cpu` / `linux-cuda` structural ABIs and
  `1e-5` for the fixed-bridge Metal fp32 path. These are same-substrate bounds,
  not cross-substrate equivalence. Codec-only round trips and fixture networks
  cannot satisfy the parity matrix. The successful training return carries a
  mandatory finite, dimension-checked held-out
  input/output probe produced immediately by that model, plus the observed
  optimizer-update count recorded only after all epoch/batch loops complete.
  Writer and Product Publisher consume that count and require exact equality
  with the authoritative `SupervisedPlan`, completion, and manifest rather than
  reconstructing it after training.
- Supervised V1 manifests remain available to inspection/resume code and are
  explicitly inference-ineligible. New supervised runtime writers cannot emit
  V1.

### Validation

Current Sprint `10.6` validation is `linux-cpu` only. CUDA and Metal
reattestation remains downstream in the single-accelerator product lanes; the
older accelerator results below are historical and do not validate V2.

```bash
docker compose --progress plain build jitml
```

The live portion uses the freshly built `jitml:local` image, reconciles the
retained `linux-cpu` publication onto that image, verifies both routed health
endpoints, and publishes each authoritative supervised row explicitly:

```bash
docker compose run --rm -e JITML_BOOTSTRAP_SKIP_IMAGE_BUILD=1 jitml jitml bootstrap --linux-cpu
docker compose run --rm jitml jitml cluster status
curl --fail http://127.0.0.1:9091/healthz
curl --fail http://127.0.0.1:9091/readyz
docker compose run --rm jitml jitml internal train-and-publish-product-rows --linux-cpu --row cifar10-vit
docker compose run --rm jitml jitml internal train-and-publish-product-rows --linux-cpu --row mnist-shallow-mlp
docker compose run --rm jitml jitml internal train-and-publish-product-rows --linux-cpu --row mnist-deep-mlp
docker compose run --rm jitml jitml internal train-and-publish-product-rows --linux-cpu --row mnist-lenet
docker compose run --rm jitml jitml internal train-and-publish-product-rows --linux-cpu --row fashion-mnist-mlp
docker compose run --rm jitml jitml internal train-and-publish-product-rows --linux-cpu --row fashion-mnist-resnet
docker compose run --rm jitml jitml internal train-and-publish-product-rows --linux-cpu --row cifar10-resnet20
docker compose run --rm jitml jitml internal train-and-publish-product-rows --linux-cpu --row cifar10-resnet56
docker compose run --rm jitml jitml internal train-and-publish-product-rows --linux-cpu --row cifar100-wide-resnet
docker compose run --rm jitml jitml internal train-and-publish-product-rows --linux-cpu --row tiny-imagenet-resnet50
docker compose run --rm jitml jitml internal train-and-publish-product-rows --linux-cpu --row california-housing-mlp
```

Every publisher invocation must train from its exact verified staged bytes,
consume the authoritative plan's complete successful mini-batch count, write a
V2 latest target, and reload the same held-out probe through Store and the real
Linux CPU engine within `1e-9`. The eleven commands must finish with **11 / 11**
V2 rows, zero V1 supervised latest targets, zero unsupported rows, and zero
errors. `cifar10-vit` runs first. Four diagnostics missed the unchanged
**0.25** bar: the fresh-image 16×16/four-token run measured
`test_accuracy=0.173`, the deterministically permuted 16×16 rerun measured
`0.181`, the permuted 8×8/16-token rerun measured `0.227`, and the permuted
4×4/64-token rerun measured `0.237`. The then-current-source train-only
RGB-normalized rerun measured `0.266` and published one eligible V2 row before
the phase-order algebra error was discovered. That artifact is diagnostic only;
the final fresh immutable-image run must reproduce the corrected typed recipe
before any row can contribute closure evidence.

After live reconciliation and all eleven publications succeed, the canonical
test and code-quality gates run against that same image/publication:

```bash
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml test jitml-sl-canonicals --linux-cpu
docker compose run --rm jitml jitml test jitml-integration --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

Rule-M plan enforcement was re-scanned against the current phase corpus on
2026-07-19: **0** backward edges across **47** formal sprint edges, **0**
dual-accelerator gates across **282** validation sections, and **0** accelerator
invocations across the **20** validation sections in aggregation phases `17`,
`18`, and `31`. This Sprint `10.6` validation block contains **15**
Linux CPU lane invocations and **0** accelerator invocations. These are
current plan-maintenance denominators; they do not relabel or replace Sprint
`10.12`'s separately dated 2026-07-14 historical evidence. The same closure
audit passed `git diff --check` with no whitespace errors.

### Closure Validation Evidence

- ❌ On 2026-07-18, the fresh current-image
  `train-and-publish-product-rows --linux-cpu --row cifar10-vit` run completed
  its authoritative 16×16/four-token, pre-permutation schedule over **1,000**
  training examples for five epochs, batch size 128, **5,000** examples
  processed, and **40** successful optimizer updates. It measured
  `train_acc=0.199` and `test_accuracy=0.173`, below the unchanged **0.25** bar,
  and correctly published no artifact.
- ❌ The current-source rerun then retained the same 16×16/four-token
  executable and every authoritative plan quantity while applying the exact
  seed-and-one-based-epoch SplitMix permutation. It measured
  `train_acc=0.227` and `test_accuracy=0.181`; the honest failure showed that
  deterministic epoch order alone did not clear the bar.
- ❌ The next current-source diagnostic retained the exact verified bytes,
  permutation, **1,000** training examples, five epochs, batch size 128,
  **5,000** examples processed, **40** successful updates, and **0.25** bar
  while reducing the patch to 8×8. Its 16-token runtime improved to
  `train_acc=0.321` and `test_accuracy=0.227`, but still failed convergence and
  correctly published no artifact.
- ❌ The next current-source diagnostic used non-overlapping 4×4 patches over
  `32×32×3`, producing **64** tokens and reducing each patch projection to
  48 image values plus two positional values. It leaves the exact dataset,
  split membership, five epochs, batch size 128, **5,000** examples processed,
  **40** updates, seed-derived epoch order, and **0.25** bar unchanged. The
  optimized run completed with `train_acc=0.308` and
  `test_accuracy=0.237`, still below the frozen bar, and correctly published
  no artifact. The focused raw-runtime contract asserts patch size/stride
  `4/4`, token count `64`, **123,595** parameters, and contiguous full virtual
  slice coverage.
- ✅ On 2026-07-19, the pre-algebra-correction train-only RGB-normalized
  4×4/64-token diagnostic retained the exact **1,000-example**, five-epoch, batch-128,
  **5,000-example**, **40-successful-update** schedule and unchanged **0.25**
  bar. It measured `train_loss=1.7352672695605809`,
  `val_loss=2.024846793637071`, `train_acc=0.392`, and
  `test_accuracy=0.266`. RGB means and positive scales came from the training
  partition only; the same transform was applied to train, validation, and test
  model inputs, the raw `[0,1]` held-out probe was retained, and V2 persisted
  the repeated elementwise transform. The then-current production command returned **1**
  row, **1** eligible, **0** unsupported, and **0** errors and wrote manifest
  SHA-256
  `8622315fa0bcf3ea969f8f8da065f09ec75948e2d415bd091aee171d8fdf4663`.
  The later phase-order correction changed the meaning of its token-mix and
  attention operations, so this artifact is historical diagnostic evidence,
  not the current canonical Mixer artifact.
- ✅ Pre-rate-binding current-source partial gates passed: container
  `jitml-unit` **678 / 678**;
  the focused exact CIFAR ViT V2 contract **1 / 1**; and the focused canonical
  permuted-training plus fitted-transform bind→project check **1 / 1**. The
  same implementation uses boxed-vector constant-time attention indexing and
  discards each `forwardOnly` tape after projecting that layer's output. These
  focused results and the one-row publication do not close Sprint `10.6` before
  the fresh immutable-image all-row and full-suite gates pass.
- ✅ After the exact rate became descriptor-semantic, container `jitml-unit`
  passed **681 / 681**, including all eleven canonical values,
  zero/negative/NaN/infinite rejection, `PlanId` sensitivity, exact Publisher
  callback propagation, and California Housing consumption. Current-source
  `jitml check-code` also passed (`check-code: ok`). These gates validate the
  landed recipe but do not replace the pending fresh-image row publications.
- ❌ The first immutable-image `cifar10-resnet20` continuation exposed a
  phase-order regression and correctly published no artifact:
  `train_acc=0.227`, `test_accuracy=0.209`. The in-progress V2 work had changed
  token mixing and attention into residual variants even though Sprint `23.1`
  explicitly owns those still-Blocked equation corrections. Sprint `10.6` now
  freezes and executes the pre-`23.1` algebra instead: token mixing replaces its
  input with the mixed result, attention returns attended values, and only an
  explicit residual layer adds a skip. Strict shape/error checks, boxed
  indexing, native selected-engine dispatch, and ABI/capability enforcement
  remain unchanged.
- ❌ After that scope correction, the exact canonical permutation at the
  retained `1e-3` rate measured `train_acc=0.277` and
  `test_accuracy=0.249`, one of 1,000 test examples below the unchanged **0.25**
  bar, and again published no artifact. A temporary environment-override
  diagnostic at `1.1e-3` then retained the same dataset, seed, five epochs,
  batch-128 geometry, **5,000** examples, **40** updates, topology, and bar; it
  measured `train_loss=1.8407929741047941`,
  `val_loss=1.897399248354522`, `train_acc=0.319`, and
  `test_accuracy=0.293`, publishing one eligible current-source V2 artifact
  with SHA-256
  `d5c123d6f08d3891e0db6fe5def29b3769f964bc0a5778bd007f002b01692984`.
  That artifact predates descriptor/`PlanId` binding of the rate and is not
  final evidence. The measured result justified the typed canonical recipe;
  adding that recipe changes every supervised `PlanId`. The fresh-image
  reconciliation and all-eleven sequence must therefore restart from
  `cifar10-vit` after the corrected operation algebra and typed rate recipe pass
  their unit/code-quality gates.
- ✅ The corrected current-source `cifar10-resnet56` prebuild diagnostic used
  its typed `1e-3` rate, five epochs, **1,000** training examples, batch size
  128, **5,000** processed examples, and **40** successful updates. It measured
  `train_loss=1.7652791500005947`, `val_loss=1.9516668964460984`,
  `train_acc=0.368`, and `test_accuracy=0.28`, clearing the unchanged **0.20**
  bar and publishing V2 manifest SHA-256
  `cf9d3ea54c33decf317137539cd95506664f39269af79e4076375afedd2dc2b5`.
  This removes the remaining known convergence risk before image freeze but is
  still current-source diagnostic evidence, not final immutable-image evidence.
- ❌ On 2026-07-19, fresh immutable image descriptor
  `sha256:aeb82655aed67e81b30feb0c2c0c6932c0f89b01496cab70b23e03137127906a`
  passed its embedded `jitml check-code` gate and the 611-module PureScript
  build with zero warnings and zero errors. A non-no-op `linux-cpu` reconcile
  then executed **156** live steps; both repository image identities in the
  reconcile stamp matched that descriptor, all nine published components were
  Ready, and `/healthz` plus `/readyz` returned `ok` and `ready`. The mandatory
  all-eleven sequence nevertheless stopped at its first row, as required:
  corrected-algebra `cifar10-vit` retained the canonical **1,000-example**,
  five-epoch, batch-128, **5,000-example**, **40-update**, typed-`1e-3` recipe
  and unchanged **0.25** bar but measured
  `train_loss=1.9099182707321072`, `val_loss=2.1013915602250837`,
  `train_acc=0.313`, and `test_accuracy=0.226`. The publisher returned **1**
  row, **0** eligible, **0** unsupported, and **1** error and correctly minted
  no artifact. No later row ran. Sprint `10.6` remained Active at that
  diagnostic point while the typed, `PlanId`-bound ViT recipe was corrected;
  the next immutable-image sequence
  must restart at `cifar10-vit` without weakening the bar.
- ❌ A current-source one-axis diagnostic then changed only the ViT epoch
  budget from five to ten while retaining its exact **1,000-example**,
  batch-128, typed-`1e-3`, corrected-algebra, and **0.25** contracts. It
  executed the declared **10,000** examples and **80** optimizer updates, but
  validation selection retained the exact same snapshot as the five-epoch run:
  `train_loss=1.9099182707321072`, `val_loss=2.1013915602250837`,
  `train_acc=0.313`, and `test_accuracy=0.226`. The publisher again returned
  **0** eligible / **1** error and minted no artifact. The ineffective epoch
  change was reverted; the next bounded diagnostic retains five epochs and
  tests the smallest source-declared, `PlanId`-bound rate change (`1.1e-3`).
- ❌ That five-epoch `1.1e-3` current-source probe executed the same **5,000**
  examples and **40** updates and improved modestly to
  `train_loss=1.9025646335053257`, `val_loss=2.1035817069984653`,
  `train_acc=0.318`, and `test_accuracy=0.232`, but remained below **0.25**.
  The publisher returned **0** eligible / **1** error and minted no artifact.
  The next one-axis probe uses a source-declared, `PlanId`-bound `1.5e-3` rate;
  the epoch budget, data, seed, topology, preprocessing, and bar remain fixed.
- ❌ The five-epoch `1.5e-3` current-source probe again executed **5,000**
  examples / **40** updates and improved to
  `train_loss=1.8802370382416158`, `val_loss=2.1103454293014035`,
  `train_acc=0.329`, and `test_accuracy=0.242`, but still failed **0.25**.
  It returned **0** eligible / **1** error and minted no artifact. The next
  single-axis diagnostic uses the conventional typed `2e-3` Adam rate, with
  every non-rate contract unchanged.
- ❌ At `2e-3`, the same five-epoch **5,000-example** / **40-update** run
  measured `train_loss=1.853951751572561`,
  `val_loss=2.105241314216369`, `train_acc=0.346`, and
  `test_accuracy=0.239`. The higher training accuracy but lower held-out result
  shows that rate-only tuning is exhausted; the publisher returned **0**
  eligible / **1** error and minted no artifact. The next typed recipe retains
  the best observed `1.5e-3` rate and expands only the bounded training
  partition to **2,000** examples. Five epochs therefore execute **10,000**
  examples and **80** updates over twice the data while keeping the seed,
  batch size, topology, preprocessing discipline, evaluation size, and
  external **0.25** bar unchanged.
- ✅ The resulting current-source `cifar10-vit` publisher run used that exact
  **2,000-example**, five-epoch, batch-128, **10,000-example**, **80-update**,
  typed-`1.5e-3` recipe. It measured
  `train_loss=1.7761211625600088`, `val_loss=1.9528016967824382`,
  `train_acc=0.352`, and `test_accuracy=0.275`, clearing the unchanged
  **0.25** bar by 0.025. The full publisher/Store path returned **1** row,
  **1** eligible, **0** unsupported, and **0** errors and published exact
  supervised V2 manifest SHA-256
  `a05f1e235f18cfc7aa1b3baebeff8bfc1e1825e77139ccd877f9106f17001d05`.
  This locks the source-declared ViT recipe and removes the observed
  convergence blocker, but remains current-source diagnostic evidence: final
  closure still requires a new immutable image, reconcile, and the complete
  all-eleven sequence restarted at `cifar10-vit`.
- ✅ The final source-declared recipe then passed the full current-source
  `jitml-unit` stanza **682 / 682** in **39.03s**. The count includes the exact
  ViT projection assertion (**2,000** train / **1,000** evaluation / batch 128 /
  five epochs / **80** updates / `1.5e-3`) and proves both learning-rate and
  training-example-count sensitivity in semantic `PlanId` identity.
- ✅ Final current-source `jitml docs check` and `jitml check-code` both passed
  (`docs check: ok`; `check-code: ok`) after the recipe, tests, and current
  contract documentation were synchronized.
- ✅ Fresh immutable image descriptor
  `sha256:fbd0c55e8f13e82450df1f6b46c14b3d174735d2c007a6de67481a524a0a2a72`
  passed its embedded `jitml check-code` gate and the **611-module**
  PureScript build with zero warnings and zero errors. A non-no-op
  `linux-cpu` reconcile executed **156** steps. Both `jitml:local` and
  `jitml-demo:local`, both repository identities in the version-1 reconcile
  stamp, and all five Ready application Pods resolved to that image; every Pod
  had zero restarts. All nine publication components were Ready and the edge
  `/healthz` / `/readyz` probes returned `ok` / `ready`.
- ✅ That exact image then published the mandated eleven supervised rows in
  order, with every command reporting **1** eligible, **0** unsupported, and
  **0** errors. The held-out metric and exact V2 manifest identities were:

  | Row | Held-out metric | V2 manifest SHA-256 |
  | --- | ---: | --- |
  | `cifar10-vit` | accuracy `0.275` | `a05f1e235f18cfc7aa1b3baebeff8bfc1e1825e77139ccd877f9106f17001d05` |
  | `mnist-shallow-mlp` | accuracy `0.907` | `eb1b3c6e5571449f86283bd90a2cf0c14831c8140d55fd004391a0cc0685e6fb` |
  | `mnist-deep-mlp` | accuracy `0.913` | `618c471531bdc6ea60b9fab2093abf0a496e99291d52d31fab5824a99eb621a9` |
  | `mnist-lenet` | accuracy `0.332` | `39c1b5be2dae2958230401a46b9c699a7fc076d2beed70aacd4be66f31bcf903` |
  | `fashion-mnist-mlp` | accuracy `0.856` | `7f9a5fba559b43f45e3709c8051d0600bcc09d4ffb4d585a78d67b2ec1a88ca5` |
  | `fashion-mnist-resnet` | accuracy `0.835` | `e4a57492ac89aeca8c5a546f3078ee0a1208f5ff7a4eaedf50b07cde7bcd55b0` |
  | `cifar10-resnet20` | accuracy `0.293` | `01d9a88d2309266be5b6d5b227df8940f6ae0795a614220d329278959a8a08b9` |
  | `cifar10-resnet56` | accuracy `0.28` | `cf9d3ea54c33decf317137539cd95506664f39269af79e4076375afedd2dc2b5` |
  | `cifar100-wide-resnet` | accuracy `0.12` | `1a26570b5d7726a2a544e033cc268ba7ac92de998a950150d2ecd14997c9f187` |
  | `tiny-imagenet-resnet50` | accuracy `0.002` | `30f82e70138d8df31d579f398bd20bd33410639f70b0bddaf34d562c0d1d8853` |
  | `california-housing-mlp` | validation MSE `0.21983530961436884` | `d22681a4f2562469c9cfe375d60ee59fb902459796128cc8bde27460ac754665` |

  The focused live latest-pointer gate then loaded all eleven exact V2 runtime
  identities and passed **1 / 1** in **6.99s**. The full immutable-image unit
  lane also passed **682 / 682** in **39.03s**.
- ❌ The subsequent full `jitml-sl-canonicals --linux-cpu` gate exposed a
  parity-test recipe propagation defect and failed **1 / 36** after
  **1,765.22s**. Publisher had correctly trained `cifar10-resnet20` at its
  descriptor-owned `1.1e-3` rate and measured `test_accuracy=0.293`; the exact
  parity test projected the row but called the generic plan-only runner, which
  supplied `Nothing` and therefore retrained at the executor default `1e-3`.
  Its deterministic `test_accuracy=0.249` matched the earlier default-rate
  diagnostic and failed the unchanged `0.25` bar before Store parity. The
  corrected test now extracts the refined descriptor rate and calls the same
  mandatory-rate execution boundary as Publisher. It compiles, HLint and the
  supported Fourmolu check are clean, and the focused Publisher rate
  propagation regression passes **1 / 1**. Because this changes the test
  source included in the immutable image, descriptor `fbd0c55e…` is retained
  as diagnostic evidence only; the next validation attempt must build a new
  image and restart reconcile plus all eleven publications from row one.
- ✅ Corrected immutable image descriptor
  `sha256:29d5d744b86b53cf51a92447708ca4d86466bf3b364a766cc7477bd3e2ccdc3d`
  then passed its embedded `jitml check-code` and 611-module PureScript gates.
  A **156-step** non-no-op `linux-cpu` reconcile left all five application Pods
  Ready with zero restarts, all nine publication components Ready, and both
  routed probes healthy. The mandated row-one restart published all eleven
  supervised ProductRows as exact V2 artifacts; the live latest-pointer
  identity proof passed **1 / 1**, the full unit lane passed **682 / 682**, and
  the corrected all-eleven Store parity lane passed **36 / 36**.
- ❌ The mandatory integration gate against that exact image passed
  **152 / 155**. Its two generic supervised failures completed real training
  before checkpoint construction rejected their generic `PlanId` against the
  ProductRow-only V2 projection: the public workflow measured
  `test_accuracy=0.838`, and the live daemon `StartTraining` schedule completed
  its declared **10 × 7,000** training budget. The third failure was a
  spawned-binary tune test that deliberately corrupted its cluster publication
  and then retained the stale expectation that real tune execution would
  succeed. The **682 / 682** unit result, **36 / 36** SL result, eleven
  publications, and descriptor `29d5d744…` therefore remain diagnostic evidence
  only; mandatory integration did not close the sprint.
- ✅ On 2026-07-19, the corrected source passed a warning-as-error build of
  the library, executable, unit, integration, and SL-canonical targets and the
  complete unit lane passed **711 / 711** in **39.01s**. The closed generic V2
  origin is now the composite of its canonical row identity and canonical
  `SupervisedPlan` transport; admission re-refines both and binds the exact
  executed seed, canonical dataset-at-read digest, runtime bytes, completion
  observations, TensorBoard identity/tags, and current-ETag pointer CAS result.
  Product-origin publication separately binds the authoritative ProductRow and
  exact four-row metric vector. A completed generic run below its external bar
  returns a typed successful miss without consulting optional legacy weight
  projections; a passing run writes its exact-plan V2 artifact. The spawned
  tune test now treats its deliberately corrupted publication as an execution
  failure while retaining `--dry-run` render coverage. Supported Fourmolu and
  `git diff --check` are clean; the focused spawned-binary integration case
  passed **1 / 1**, and `jitml docs check` plus `jitml check-code` both exited
  `0`. Because this source differs from descriptor `29d5d744…`, the immutable
  build, reconcile, publication, and remaining full-suite gates must still run
  again.
- ✅ `docker compose build jitml` then built that exact corrected source as OCI
  descriptor
  `sha256:0147b37fafd53c01669705a5723ce91482d0fd545da4b9da523df8dacc3e9ba8`,
  with Linux/amd64 manifest
  `sha256:a8d35d46393552afb7d4616fc8af6ee6d7f976da96fc4ab678ff18a79371fa92`
  and runtime config
  `sha256:799fa6856bb3d0b81f11d761595d35ce273c969af63bffb4cb084bc6787b2805`.
  The tag identities matched the corresponding Buildx-history attachments.
  The image build's embedded `jitml check-code` passed, and its 611-module
  PureScript build completed with zero warnings and zero errors. This is the
  sole image used for Sprint 10.6 closure evidence.
- ✅ The supported `JITML_BOOTSTRAP_SKIP_IMAGE_BUILD=1` Linux CPU bootstrap
  reconciled that exact descriptor in a non-no-op **156-step** rollout.
  `jitml cluster status` reported all nine publication components Ready;
  routed `/healthz` and `/readyz` returned HTTP `200` with `ok` and `ready`.
  The reconcile stamp names descriptor `0147b37f…` for both repository app
  tags; all four kind nodes resolve both tags to that descriptor and runtime
  config `799fa685…`. The coordinator, demo, and three service Pods are all
  Running and Ready on that config with zero restarts. That identity chain
  remained unchanged through the eleven publications and focused pointer gate.
- ✅ The mandatory publication restart on descriptor `0147b37f…` is **11 / 11**
  rows complete. Every completed invocation has reported `rows: 1`,
  `eligible: 1`, `unsupported: 0`, and `errors: 0`:

  | ProductRow | held-out metric | manifest SHA-256 |
  | --- | --- | --- |
  | `cifar10-vit` | `test_accuracy=0.275` | `c54d62f618782fd9dcc06860a47b97f15fcce2ec3f0ce25d1caaa6abae1b654c` |
  | `mnist-shallow-mlp` | `test_accuracy=0.907` | `3bd862e5e2e14c173d196536ad8ddac4aeb3197cce12c5686536390e96402360` |
  | `mnist-deep-mlp` | `test_accuracy=0.913` | `7b7028344b834fa92997936c5a1d88613b561632ad2d63e6aba93b519a026ea4` |
  | `mnist-lenet` | `test_accuracy=0.332` | `7cfdeda777280c3db5e07730182fd1a38c4a195b480d148dba6d30adf3725ac0` |
  | `fashion-mnist-mlp` | `test_accuracy=0.856` | `a841e95e5ed8c57ed8fef0271a83a234d2a2c5729183ee2192d3cdf741a541eb` |
  | `fashion-mnist-resnet` | `test_accuracy=0.835` | `ae1329b859a729877b752a1fe572d3972ecf9dff31fdf5440132b722147c1531` |
  | `cifar10-resnet20` | `test_accuracy=0.293` | `e7ca913a0269ff9a8b3f0ffe801135eaaa3c30e9ced09b051ee6bf36187b8160` |
  | `cifar10-resnet56` | `test_accuracy=0.28` | `85d16ee6bad2a61c0b2f791aba4b46d2e5379f68ba74c5352e423ff6df5c7154` |
  | `cifar100-wide-resnet` | `test_accuracy=0.12` | `6a4e6017040d12364b1a2d016e1d57e5143a655bf7db7b25672f92bf3153daa8` |
  | `tiny-imagenet-resnet50` | `test_accuracy=2.0e-3` | `290f8ac63ff93e792ee4236b86c3d892cd6c2e0ab7a8854fcd8ed0b1ce8edde4` |
  | `california-housing-mlp` | `validation_mse=0.21983530961436884` | `a742554d18dc1e75f54229fac6370132af45f72b770e8627a34cd278b388a09f` |

  All eleven ordered invocations completed at `1` eligible and zero
  unsupported/errors. The focused live latest-pointer gate then passed
  **1 / 1** in **6.97s**, loading all eleven exact ProductRow-origin V2 runtime
  identities from their latest targets with no supervised V1 target. The full
  Store-parity matrix remains pending against exactly this set.
- ✅ The complete immutable-image `jitml-unit --linux-cpu` lane then passed
  **711 / 711** in **38.85s** (**44.16s** including orchestration), against the
  same descriptor and live publication.
- ✅ The complete immutable-image `jitml-sl-canonicals --linux-cpu` lane passed
  **36 / 36** in **7,164.60s** (**7,166.18s** including orchestration). Its
  production all-eleven trained-program versus Store-loaded V2 parity case
  passed in **6,871.87s** with the exact published metrics above; the embedded
  live latest-pointer proof passed again in **7.04s**, the live staged-row
  runtime case in **21.98s**, and live MNIST convergence in **263.53s**.
- ✅ The complete immutable-image `jitml-integration --linux-cpu` lane passed
  **155 / 155** in **7,082.12s** (**7,086.39s** including orchestration). The
  full live typed-executable WorkflowMatrix passed in **6,081.96s**, live PPO
  convergence in **719.40s**, live daemon training placement in **33.53s**, and
  the corrected spawned-binary matrix case passed in **0.18s**. The three
  failures that kept descriptor `29d5d744…` diagnostic are therefore closed on
  the final image and publication.
- ✅ `jitml-negative-controls --linux-cpu` passed **3 / 3** in **0.50s**
  (**3.63s** including orchestration) on that same immutable image.
- ✅ `jitml-model-convergence --linux-cpu` passed **111 / 111** in **0.50s**
  (**4.28s** including orchestration), covering every ProductRow's external
  convergence bar and non-wall-clock inference-performance floor.
- ✅ `jitml docs check` and `jitml check-code` both exited `0` in the project
  container after the final evidence updates.

### Historical Validation (retained; does not close the reopened scope)

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

- None.

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

The retained `.ready`/`ArtifactRef` gate is transport readiness only. A
`step >= 1` manifest and resolvable pointer do not mint current inference
eligibility; Engine execution additionally requires Sprint `10.12`'s opaque
Store-admitted artifact.

### Objective

Recast inference as an **asynchronous `Work*` workflow** owned by the single
**Engine**, and make transport readiness unrepresentable unless it comes from a
completed derivation. Implements the `Work*` envelope family and the `Artifact +
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
- Make a transport-ready `ArtifactRef` obtainable **only** from a training `WorkResult`
  whose checkpoint manifest has `step ≥ 1` and a resolvable `latest` pointer; the
  coordinator writes a `.ready` sentinel **last**. A malformed wire command parses
  into a typed rejection event, never a silent bad state. Current serving still
  requires the admitted artifact owned by Sprint `10.12`.
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

### Historical Validation State (host-native, apple-silicon lane)

- **Landed and validated host-native.** `JitML.Work.Envelope` defines the
  `Work*` family (`WorkCommand`/`WorkEvent`/`WorkResult`/`WorkStatus`) correlated
  by `CallId`, the **parse-don't-validate** wire boundary (`parseWorkCommand` →
  typed `WorkRejection`), and the producer-side `dedupByCallId` pure fold, which
  suppresses duplicate semantic results without changing the broker's
  at-least-once guarantee. The **readiness gate** is enforced in the types: `ArtifactRef`
  is opaque and obtainable only via `mintArtifactRef` (`Just` iff checkpoint
  manifest `step ≥ 1`), with `readinessSentinelKey` naming the `.ready` witness —
  so the historical transport gate rejects `parseWorkCommand Infer` with no
  ready artifact as `ArtifactNotReady`. It is not current persisted admission.
- **Triplicated compute collapsed.** The per-substrate weighted-runner dispatch is
  single-sourced in `engineWeightedInference`; the demo handler, the `jitml
  inference run` CLI (`inferenceForSubstrate`), and the daemon consumer all route
  through it. The "Triplicated inference path" ledger row moved to `Completed`.
- `cabal build lib:jitml` warning-clean (`-Wall`); `jitml-unit` **206 / 206**
  (three new `Work*` cases: readiness gate, typed-rejection parse, and
  call-ID semantic dedup), `jitml-daemon-lifecycle` **35 / 35**
  (behavior-preserving).
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
  Coordinator-role serve path in Sprint `12.16`.

## Documentation Requirements

**Engineering docs to create/update:**

- `../documents/engineering/run_contract.md` — refined completion evidence and
  completed-checkpoint contract.
- `../documents/engineering/checkpoint_format.md` — current local
  `CheckpointManifest`, manifest CBOR codec/content hash, binary `.jmw1`
  encoder, manifest pointer, local checkpoint object store, `HasMinIO`
  snapshot writer, latest-pointer inference helper, and inference summary
  helper; target split-blob layout, live MinIO write protocols, typed advance
  predicates, retention reconciler, inference protobuf byte contract, and real
  inference-only read path.
- `../documents/engineering/training_metrics_and_splits.md` — supervised-plan
  budget units, finite completion criteria, and measured-pass requirements.
- `../documents/engineering/training_workloads.md` — canonical resolved-plan
  transport and candidate-versus-completed workload events.
- `../documents/engineering/determinism_contract.md` — same-substrate bit-
  equality contract, same-substrate trained-versus-Store V2 path-comparison
  bounds, explicit rejection of cross-substrate equivalence, and GC
  determinism.
- `../documents/engineering/jit_codegen_architecture.md` — generated CPU,
  CUDA, and Metal supervised-V2 structural-operation source, ABI/capability
  checks, and selected-engine fail-closed execution.
- `../documents/engineering/apple_silicon_metal_headless_builds.md` — generated
  supervised-V2 MSL metadata, fixed-bridge execution, explicit fp32 transport,
  and the downstream real-device reattestation boundary.
- `../documents/engineering/haskell_code_guide.md` — exact supervised runtime,
  training-returned evidence, V2 writer/reload, and selected structural-engine
  module/type ownership.
- `../documents/engineering/daemon_architecture.md` — `InferenceHandler`
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

**Status**: Done on its retained convergence-statistics and structural-completion surface
**Implementation**: `src/JitML/Checkpoint/Format.hs`,
`src/JitML/Checkpoint/Store.hs`, `src/JitML/App.hs`,
`src/JitML/Observability/TensorBoard.hs`,
`src/JitML/Observability/TbSidecar.hs`
**Docs to update**: `../documents/engineering/checkpoint_format.md`,
`../documents/engineering/training_metrics_and_splits.md`,
`../documents/engineering/purescript_frontend.md`, `system-components.md`

### Objective

Record fixed-budget completion and convergence statistics in the checkpoint
model and introduce the structural distinction between inspectable candidates
and completed manifests. That in-memory refinement is necessary but not
sufficient for eligibility: Store alone admits the opaque consumer value from
exact persisted reads, and Sprint `10.6` makes supervised V1 inspection only.

### Deliverables

- Add completed-budget fields, convergence-statistics records, TensorBoard
  scalar run metadata, and readiness witness data to the manifest contract.
- Introduce the hidden structural completion refinement and the
  completion/convergence predicates consumed by persisted Store admission.
- Refactor `eval`, `inference run`, demo handlers, `rl eval`, `rl rollout`, and
  AlphaZero game endpoints to accept Store's opaque admitted-completed value,
  not raw weights or a caller-built manifest.
- Preserve raw manifest loading for inspection/resume without allowing it to
  flow into inference.

### Historical Validation

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
- Historical Live Playwright passed **15 / 15** against the rebuilt
  `linux-cpu` edge after reseeding eight pre-V2 demo manifests. That result does
  not establish current supervised eligibility.

### Remaining Work

- None.

## Sprint 10.11: Typed Checkpoint Object-Key Validation [✅ Done]

**Status**: Done (reopened 2026-06-29; re-closed 2026-06-30)
**Implementation**: `src/JitML/Checkpoint/Store.hs`,
`src/JitML/Checkpoint/Format.hs`, `src/JitML/App.hs`,
`test/unit/Main.hs`, `test/integration/Main.hs`
**Docs to update**: `documents/engineering/checkpoint_format.md`,
`documents/engineering/haskell_code_guide.md`,
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`, `system-components.md`

### Objective

Keep the local filesystem-backed checkpoint store traversal-safe while returning
validation failures through typed command paths instead of `error`.

### Deliverables

- Change local object-key-to-path conversion to return `Either Text FilePath`
  for empty, absolute, or parent-traversing keys.
- Thread the typed validation result through local checkpoint read/write/list
  operations.
- Make local `jitml internal gc --experiment-hash ...` reject unsafe hashes with
  `InvalidConfig`, not process termination.
- Add tests for unsafe local keys and valid checkpoint prefixes.

### Validation

- `docker compose run --rm jitml jitml test jitml-unit --linux-cpu` passed
  **237 / 237**, including typed unsafe-key local store regressions.
- `docker compose run --rm jitml jitml test jitml-integration --linux-cpu`
  passed **77 / 77**, including the spawned-binary `jitml internal gc
  ../escape` `InvalidConfig` regression and **19 / 19** `Live` cases.
- `docker compose run --rm jitml jitml check-code` passed (`check-code: ok`).

### Remaining Work

- None.

## Sprint 10.12: Persisted Checkpoint Proof Admission [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Checkpoint/{Store,Writer}.hs`,
`src/JitML/Product/Pipeline.hs`, completed/candidate checkpoint call sites,
`test/unit/{Main,ProtocolCodec}.hs`, `test/integration/Main.hs`
**Docs to update**: `README.md`, `00-overview.md`, `../README.md`,
`../documents/engineering/checkpoint_format.md`,
`../documents/engineering/training_metrics_and_splits.md`,
`../documents/engineering/training_workloads.md`,
`../documents/engineering/run_contract.md`, `system-components.md`,
`legacy-tracking-for-deletion.md`

### Objective

Completion and inference eligibility are admitted only from an exact, stable
persisted checkpoint snapshot. `Store` owns reading and verifying the pointer,
exact manifest envelope/body, and physical payloads, then returns an opaque
admitted artifact. `Pipeline` consumes that value and cannot mint eligibility
from caller-supplied or merely in-memory values. Candidate persistence and
completed persistence are distinct APIs, and completed persistence cannot omit
`CompletedTraining`. This sprint owns the persisted-checkpoint portion of
[Exit Definition](README.md#exit-definition) item `31`; its previously closed
canonical supervised-plan and measured-completion refinements remain retained.

### Deliverables

- `Store` performs manifest-body stability reads: read latest pointer `P1`,
  fetch and verify the exact addressed outer bytes and embedded body, read
  latest pointer `P2`, and proceed only when `P1 == P2`. A changed pointer
  produces a typed retry/conflict result and never admits the body read between
  two different pointers. Physical blob verification is an independent
  content-addressed binding step, not part of the `P1`/`P2` body-stability
  interval.
- Admission verifies the outer address against the exact fetched outer bytes,
  canonical V1 structure or the V2 body address/exact embedded body bytes, and
  all manifest/refinement invariants before Store can construct its opaque
  admitted-completed artifact. Completed V1 refinement is restricted to
  canonical non-supervised ProductRows; supervised V1 remains inspection/resume
  only. Pure manifest completion validation is explicitly structural and cannot
  stand in for persisted admission.
- Blob binding verifies the exact object key, fetched bytes, byte length/content
  SHA, `.jmw1` decoding, `supervised.weights` identity, flat-vector length,
  virtual-slice bounds/coverage/shapes, and completed run's final-weight and
  plan identity. Manifest metadata alone cannot stand in for fetched payload
  evidence.
- Candidate and completed writer APIs are separate. Candidate writers carry no
  completion proof and cannot publish an inference-eligible latest pointer.
  Completed writers require a non-optional `CompletedTraining`; no completed
  boundary accepts `Maybe CompletedTraining` or a caller-asserted eligible flag.
- A content-addressed object write succeeds only when the object is absent or
  its existing bytes are exactly identical. Existing different bytes at the
  same key produce a typed conflict. Latest-pointer updates use exact
  compare-and-swap and cannot overwrite a concurrently changed value.
- Dependency direction is `Pipeline -> Store admission`: `Pipeline` requests
  admission and consumes the opaque artifact returned by `Store`. It cannot
  construct, alter, or relabel a manifest/proof before or after admission, and
  `Store` never accepts an eligibility value minted by `Pipeline`.
- Candidate/completed, pointer-race, object-conflict, byte-tamper,
  body/blob-substitution, malformed-`.jmw1`, slice-mismatch,
  plan/final-weight-mismatch, and successful stable-admission regressions cover
  local and MinIO-backed behavior.

### Retained Completed Surface

- The resolved supervised plan has positive unit-indexed training/evaluation
  budgets, canonical versioned transport, and a derived `PlanId`; local, Linux
  worker, and Apple host paths consume that same plan without primitive budget
  reinterpretation.
- Raw completion values re-run hidden smart constructors, require finite passing
  measurements plus exact budget completion, and cannot mint
  `CompletedTraining` through generic deserialization.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml test jitml-sl-canonicals --linux-cpu
docker compose run --rm jitml jitml test jitml-rl-canonicals --linux-cpu
docker compose run --rm jitml jitml test jitml-hyperparameter --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Closure Validation Evidence (2026-07-20)

- `jitml-unit --linux-cpu` passed **719 / 719** in **39.18s** on the
  post-transition worktree.
- `jitml-sl-canonicals --linux-cpu` passed **36 / 36**; the container exited
  `0` after **7,209.943s** wall time.
- `jitml-rl-canonicals --linux-cpu` passed **40 / 40** in **162.30s**, including
  the real AlphaZero completed-checkpoint path.
- `jitml-hyperparameter --linux-cpu` passed **26 / 26** in **0.38s**.
- Focused Store admission passed **8 / 8**; candidate persistence passed
  **1 / 1**; typed unsafe/unreadable write conflicts passed **1 / 1**.
- The library, unit, integration, and RL target compile sweep exited `0`;
  `jitml docs check`, `jitml check-code`, and `git diff --check` passed.
- Rule-M deterministic scans found **0** backward dependency edges across 45
  formal references, **0** dual-accelerator gates across 282 validation
  sections, and **0** accelerator invocations across the 20 validation
  sections in aggregation phases `17`, `18`, and `31`.

### Historical Validation Evidence (2026-07-14; retained surface only)

- `jitml-unit --linux-cpu` passed **411 / 411** in **37.11s**; its focused
  `ProtocolCodec` group passed **12 / 12**.
- `jitml-sl-canonicals --linux-cpu` passed **31 / 31** in **286.64s**.
- `jitml-rl-canonicals --linux-cpu` passed **40 / 40** in **224.50s**.
- `jitml-hyperparameter --linux-cpu` passed **21 / 21** in **0.23s**.
- The rebuilt `jitml:local` image passed its embedded strict build and
  `check-code`; the public container gates then passed with `docs check: ok`
  and `check-code: ok`.
- Rule-M deterministic scans found **0** backward dependency edges across 45
  formal references, **0** dual-accelerator gates across 284 validation
  sections, and **0** accelerator invocations across the 20 validation
  sections in aggregation phases `17`, `18`, and `31`.

### Remaining Work

- None.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [development_plan_standards.md](development_plan_standards.md)
- [../README.md](../README.md)
