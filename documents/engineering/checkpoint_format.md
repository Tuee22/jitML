# Checkpoint Format

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: README.md, ../documentation_standards.md, ../../DEVELOPMENT_PLAN/phase-0-planning-documentation.md, ../../DEVELOPMENT_PLAN/phase-4-stateful-platform-services.md, ../../DEVELOPMENT_PLAN/phase-10-checkpointing-and-inference.md, ../../DEVELOPMENT_PLAN/phase-16-no-caveat-model-runtime.md, ../../DEVELOPMENT_PLAN/phase-18-no-caveat-product-handoff.md, determinism_contract.md, training_workloads.md
**Generated sections**: none

> **Purpose**: Project-specific checkpoint format for jitML — split-blob
> layout, `.jmw1` dense weight blob wire format, typed CBOR manifest, write-
> once + If-Match CAS protocol, retention reconciler, inference-only read
> path, inference request/result protobuf envelopes, and the reopened
> architecture-aware checkpoint target for every no-caveat model family.

## No-Caveat Checkpoint Target

The current weighted checkpoint path is real for the implemented MLP-family
payloads. Sprint `10.6` adds the typed manifest metadata needed by every model
family that the runtime trains: Dense, DeepDense, Conv2D, residual,
wide-residual, ResNet-50, VisionTransformer, RL policies, AlphaZero
policy/value nets, and tuning trial checkpoints. The manifest carries
architecture metadata, preprocessing metadata, output-decoding metadata, replay
/ transcript pointers, per-substrate artifact identity, and weight-layout
information so `jitml eval`, `jitml rl eval`, `jitml inference run`, and the
demo app can reject missing or incompatible checkpoints instead of using an
inline demo-only model. Sprint `10.6` remains blocked on the live Linux
CPU/CUDA and Apple Silicon integration validation lanes.

## Storage Layout

The `jitml-checkpoints` MinIO bucket uses a fixed prefix schema. The current
local key renderers live in `src/JitML/Checkpoint/Format.hs` so paths are typed
values rather than stringly-typed call sites:

```
jitml-checkpoints/
  <experiment-hash>/                      -- sha256(resolved-dhall || substrate-fingerprint)
    blobs/<sha256>                        -- write-once, content-addressed, opaque bytes
    manifests/<sha256>                    -- write-once, content-addressed, CBOR manifest objects
    pointers/
      latest                              -- mutable, ETag-CAS; body = 32-byte manifest sha
      best/<metric>                       -- mutable, ETag-CAS; body = 32-byte manifest sha
      trial/<trial-hash>/latest           -- per-HPO-trial latest pointer
      trial/<trial-hash>/best/<metric>    -- per-HPO-trial best pointer
```

`experiment-hash = sha256(resolved-dhall || substrate-fingerprint)`.
`manifest-sha = sha256(canonical-cbor(CheckpointManifest))`.

Current local helpers cover `deriveExperimentHash`, `blobKey`, `manifestKey`,
`latestPointerKey`, `bestPointerKey`, `trialPointerKey`, deterministic
`encodeManifestCbor` / `decodeManifestCbor` / `manifestContentSha`, typed
`AdvancePredicate`, and pure `applyPointerWrite` CAS decisions.
`JitML.Checkpoint.Store` provides the local filesystem-backed interpreter for
write-once object writes, manifest writes/reads, latest-pointer CAS, retention
planning, local manifest discovery for `jitml internal gc`, GC execution
through `HasMinIO`, checkpoint snapshot writes through `HasMinIO`, and
inference from the latest checkpoint. Store-level
`checkpointObjectRef` adapts the bucket-prefixed key renderers to live
`HasMinIO` calls by carrying bucket `jitml-checkpoints` separately and using
keys relative to that bucket.
`JitML.Service.MinIOSubprocess` provides the live HTTP MinIO
`HasMinIO` interpreter; 2026-05-19 live Linux CPU validation confirms
`If-None-Match: *` duplicate writes and stale `If-Match` pointer CAS surface as
`SEConflict` through the routed `/minio/s3` edge.

The local checkpoint write/read paths now both cross the `HasMinIO` capability
boundary through `writeCheckpointSnapshotWithMinIO` and
`loadInferenceCheckpointWithWeights`. The live rollout proceeds storage-outward:
validate those checkpoint writes/reads through the live MinIO capability, then
inference from checkpoint, then training persistence, then tuning/resume. Later
workload layers should not invent parallel persistence paths around the
checkpoint store.

## Three Object Classes, Two Write Protocols

### `blobs/<sha256>` — Write-Once Content-Addressed Payloads

Each blob's key *is* `sha256(its bytes)`. PUTs use `If-None-Match: *` and
treat `412 Precondition Failed` as success (the bytes already exist by
definition).

One checkpoint produces one blob per checkpoint part: weights, optimizer
state, RNG state, and, for RL workloads, replay buffer and exploration
cache. Part-level content addressing makes unchanged state deduplicate
automatically across consecutive checkpoints.

### `manifests/<sha256>` — Write-Once Content-Addressed CBOR Manifests

Each manifest names the blob SHAs that constitute one logical checkpoint
plus the metadata needed to interpret them: experiment hash, optional trial
hash, step / epoch, telemetry wall-clock, substrate, schema version,
canonical-ordered checkpoint parts, metrics, and parent manifest SHA for
linear history. Same `If-None-Match: *` write protocol.

The manifest's SHA is the canonical *checkpoint id* used by Pulsar
`CheckpointDone` events, RPC envelopes, and `--resume <checkpoint-id>`.

### `pointers/*` — The Only Mutable Objects

Each pointer's body is a 32-byte manifest SHA. Updates use S3 conditional
PUT with `If-Match: <etag>` — textbook compare-and-swap. The
`pointers/latest` update is the **single atomic commit point** for a
checkpoint: part-level blob writes can happen in any order and may even
leave orphans on failure, but the manifest is only adopted as HEAD when its
pointer update succeeds.

## `.jmw1` Dense Weight Blob Format

Target blob format starts with magic bytes, a canonical-CBOR header length, the
canonical-CBOR header, then packed little-endian tensor bytes:

```
offset   field         type             notes
0        magic         4 bytes          "JMW1"
4        header_len    uint32 LE        size of CBOR header in bytes
8        header_cbor   bytes            CBOR canonical form
8+H      payload       bytes            packed dense tensors, no padding
```

The CBOR header decodes into:

```haskell
type Hash32 = ByteString

data JmwHeader = JmwHeader
  { jmwExperimentHash :: !Hash32
  , jmwGraphShapeHash :: !Hash32
  , jmwStep           :: !Word64
  , jmwEpoch          :: !Word64
  , jmwSubstrate      :: !Substrate
  , jmwDtypeMap       :: !DtypeMap
  , jmwTensors        :: ![TensorEntry]
  }

data Dtype = F32 | F64 | C32 | C64 | I32 | I64 | U8 | BF16
```

`jmwTensors` is canonical-ordered by tensor path ascending bytewise. Each
entry carries path, dtype, shape, payload offset, byte length, and SHA-256.
Payload bytes are contiguous, little-endian, dtype-native, and unpadded.

The current local `encodeJmw1` helper in `src/JitML/Checkpoint/Format.hs`
emits the `JMW1` magic, a little-endian 32-bit CBOR header length, a compact
CBOR header, and little-endian `F64` payload bytes. `decodeJmw1` validates the
same local `F64` payload shape and returns decoded weight values for the local
inference loader. The richer header shape above is the Sprint `10.6` / Phase
`16` durable contract for full runtime checkpoints across every no-caveat model
family.

## CBOR Manifest

```haskell
data CheckpointManifest = CheckpointManifest
  { cmExperimentHash :: !Hash32
  , cmTrialHash      :: !(Maybe Hash32)
  , cmStep           :: !Word64
  , cmEpoch          :: !Word64
  , cmWallClockNs    :: !Word64
  , cmSubstrate      :: !Substrate
  , cmSchemaVersion  :: !Word32
  , cmParts          :: ![CheckpointPart]
  , cmMetrics        :: ![(Text, Double)]
  , cmParentManifest :: !(Maybe Hash32)
  }

data CheckpointPart = CheckpointPart
  { cpRole    :: !PartRole
  , cpBlobSha :: !Hash32
  , cpBytes   :: !Word64
  , cpFormat  :: !PartFormat
  }
```

The Haskell `CheckpointManifest` in `src/JitML/Checkpoint/Format.hs` carries the
implemented local shape: manifest id, experiment hash, model-family identifier,
architecture metadata, preprocessing metadata, output decoders, weight layout,
replay/transcript pointers, per-substrate artifact identities, tensor blobs,
optimizer blobs, RNG blobs, monotonic step, metrics, and optional parent
manifest SHA. `TensorSpec`, `ArchitectureMetadata`,
`PreprocessingMetadata`, `OutputDecoder`, `WeightLayout`, `ArtifactPointer`,
and `SubstrateArtifact` are part of the serialized manifest contract.
`encodeManifestCbor` canonicalizes tensor order by `tensorName`, optimizer
order by `optimizerKind`, RNG order by `rngStreamId`, metrics by name,
architecture input/output specs by name, preprocessing inputs by name,
weight-layout tensors by name, output decoders by name, and artifact pointers
by their identity fields; `decodeManifestCbor` round-trips that representation,
and `manifestContentSha` hashes the deterministic CBOR bytes. The richer target
shape above still documents the full runtime contract for wall-clock telemetry,
epoch, substrate, schema version, and generalized part roles. `cmWallClockNs`
is telemetry only and is never an input to any content hash.

## Concurrency Model

Target live race conditions between trainers, hyperparameter-trial workers, and
inference clients are eliminated at the protocol layer; nothing relies on
advisory locks, leases, or a separate lock service.

| Hazard | Resolution |
|--------|------------|
| Write/write on `blobs/*` and `manifests/*` | Impossible by construction — keys are derived from `sha256(payload)`. Two writers with the same logical payload write the same key with the same bytes; `If-None-Match: *` `412` is success. |
| Write/read on `blobs/*` and `manifests/*` | Impossible — S3 object PUT is atomic at the object level. |
| Write/write on `pointers/*` | `If-Match: <etag>` CAS. Loser receives `412` → `MinIOPreconditionFailed` → `SEConflict` (retryable). The retry harness re-reads the pointer, applies the caller's resolution policy, and retries. |
| Write/read on `pointers/*` | A reader observes either the old ETag's bytes or the new ETag's bytes. Both name valid immutable manifests. No torn state because the only mutation is a single object PUT (atomic) of a 32-byte body. |

## Typed Advance Predicates

The pointer-CAS retry harness applies the typed `AdvancePredicate` ADT in
`src/JitML/Checkpoint/Format.hs` through `applyAdvancePredicate`:

| Predicate | Meaning |
|-----------|---------|
| `advanceLatest` | `cmStep new > cmStep cur` |
| `advanceBestMaximised` | `lookupMetric m new > lookupMetric m cur` |
| `advanceBestMinimised` | `lookupMetric m new < lookupMetric m cur` |

Trainers pick `Maximised` vs `Minimised` from the experiment Dhall's
`metrics[i].direction` field. The direction is part of the resolved-Dhall
hash, so flipping a metric's direction defines a *different experiment*.
The current worktree has `AdvanceLatest`, `AdvanceBestMaximised`, and
`AdvanceBestMinimised` constructors, pure `applyAdvancePredicate`, a pure
`PointerWrite` / `applyPointerWrite` decision surface, and a local
filesystem-backed checkpoint store. `writeCheckpointSnapshotWithMinIO` applies
the same protocol through `HasMinIO.putBlobBytesIfAbsent` and
`HasMinIO.casPointer`, treating existing identical blob/manifest payloads as
idempotent before the pointer CAS decision. The live HTTP MinIO capability path
for the same conditional-write protocol is `JitML.Service.MinIOSubprocess`.

## Sketch

```haskell
writeCheckpoint :: HasCheckpointStore m => CheckpointPayload -> m CheckpointId
writeCheckpoint payload = do
  parts    <- traverse (putBlobIfAbsent . encodePart) (payloadParts payload)
                                                  -- If-None-Match: *  (412 = success)
  manifest <- putBlobIfAbsent (encodeManifestCanonical (mkManifest parts payload))
  retryServiceAction defaultRetryPolicy $
    casPointer (pointerKeyLatest (experimentHash payload))
               advanceLatest
                                                  -- If-Match: <etag>  (412 = SEConflict, retry)
                                                  -- advanceLatest :: CurrentManifest -> ProposedManifest -> Bool
  pure (CheckpointId manifest)
```

## Retention and GC

Target retention (`retain = Checkpoint.Retention.LastN k` in the experiment
Dhall) is enforced by a reconciler — `jitml internal gc <experiment-hash>` —
invoked by the trainer at training-end. Per doctrine `Reconcilers`,
re-running `gc` on a steady-state experiment is a no-op (exit code `3`).

- **Live set.** The reconciler reads `pointers/latest`, every
  `pointers/best/<metric>` for the metrics declared in the experiment Dhall,
  every `pointers/trial/<trial-hash>/*` reachable from the experiment, and
  follows `cmParentManifest` along the lineage chain from those tips. The
  transitive closure is the live set.
- **`LastN k` semantics.** `LastN k` keeps the `k` most-recent manifests on
  the `latest` chain (by `cmStep`). `pointers/best/<m>` target manifests are
  always live regardless of `LastN`.
- **Blob GC.** A blob is reapable iff no live manifest references it.
- **Audit trail.** GC emits a structured `gc_reaped` event per doctrine
  `At-Least-Once Event Processing`, naming every reaped manifest and blob
  SHA so the audit trail survives the deletion.

The current store exposes `RetentionPolicy{KeepAll,LastN}`, `walkLiveSet`,
`applyRetentionPolicy`, `buildGcPlan`, `listCheckpointManifests`,
`listCheckpointManifestsMinIO`, and `executeGcPlan` over the typed
`HasMinIO` boundary. The current `jitml internal gc <experiment-hash>`
detects the live cluster publication
(`./.build/runtime/cluster-publication.json`) and routes the live half
through `listCheckpointManifestsMinIO + buildGcPlan + executeGcPlan` via
`JitML.Service.MinIOSubprocess`; the offline half scans
`<cache-dir>/checkpoints/jitml-checkpoints/<experiment-hash>/manifests/`.
The stdout reports
`gc: <experiment-hash> kept=<n> reaped=<n> reaped-blobs=<n>` (live) or
`gc: <experiment-hash> kept=<n> reaped=<n>` (offline) and exits `3`
when the plan is a no-op.

After the live reaper completes, `JitML.App.publishGcReapedEvents`
publishes a `GcReapedEvent` envelope on
`persistent://public/default/gc.event.<substrate>` for each successfully
reaped manifest. The envelope carries `experiment_hash`, `manifest_sha`,
the addressed `reaped_blob_shas`, the reaped manifest's `step_at_reap`,
the live `substrate`, and the reap `timestamp_ns`; text + proto3 codecs
live in `JitML.Proto.Gc`. Publication failures surface a stderr line
but do not roll back the MinIO delete and do not short-circuit the
reconciler — at-least-once handles the missed event on a subsequent
run.

## Inference-Only Read Path

Final `loadInferenceCheckpointWithWeights` reads `pointers/latest`, fetches
`manifests/<sha>`, fetches **only** the `Weights` part's blobs (skipping
optimizer state, RNG state, replay buffer, and exploration cache), decodes the
`.jmw1` payloads, and hands the manifest plus decoded weights to the
substrate-specific weighted inference runner. Sprint `10.6` extends this from
the current MLP weight payloads to all no-caveat model-family weight layouts and
output decoders.

Concurrent training advances are invisible to the reader because the
snapshot the reader operates against is immutable.

The current read paths are explicit-runner APIs. `loadInferenceCheckpointWith`
loads the latest pointer and weight-only manifest through `HasMinIO` for callers
that provide an injected manifest runner. `loadInferenceCheckpointWithWeights`
also loads and decodes the `.jmw1` weight blobs before invoking the weighted
runner; both loaders validate that the loaded manifest records the requested
experiment hash and that the manifest body's content SHA matches the pointer.
`loadInferenceCheckpointWithWeights` also rejects a decoded `.jmw1` payload when
its element count disagrees with the manifest tensor shape. `jitml inference
run` and daemon self-inference use this weighted path.
`JitML.Engines.Local.runLinuxCpuCheckpointInference` validates that the local
Linux CPU path can compile, load, and execute a generated FFI kernel from that
checkpoint read. `JitML.Service.Runtime.daemonWorkloadDispatcherWithInference`
keeps that explicit injected-runner hook available for tests. Production
`jitml service` self-inference selects
`daemonWorkloadDispatcherWithWeightedInference`, which uses
`loadInferenceCheckpointWithWeights` to load the weight-only `.jmw1` blobs
through `HasMinIO`, decode them, and pass them to the selected substrate's
weighted checkpoint runner. The `jitml-demo` REST inference/generic/image/
checkpoint-compare/Connect 4 routes now accept generated browser request
envelopes and call an injected checkpoint runtime handler when a live
publication is available; without that handler they fail closed with
`503 checkpoint-required`.

The inference topic contract is declared in `proto/jitml/inference.proto`.
`JitML.Proto.Inference` mirrors the `InferenceRequest` and `InferenceResult`
messages with text render/parse helpers plus proto3-compatible byte codecs;
the input/output vectors are encoded as packed repeated doubles.

## TensorBoard Sidecar

Target `CheckpointDone` events also write a CBOR sidecar at
`jitml-tensorboard/<experiment-hash>/checkpoints/<step>-<manifest-sha>.cbor`:

```haskell
data TbCheckpointMarker = TbCheckpointMarker
  { tcmStep          :: !Word64
  , tcmEpoch         :: !Word64
  , tcmManifestSha   :: !Hash32     -- references the checkpoint manifest in jitml-checkpoints
  , tcmExperimentSha :: !Hash32
  , tcmTrialSha      :: !(Maybe Hash32)
  , tcmRunUuid       :: !Uuid
  , tcmMetricsAtStep :: ![(Text, Double)]   -- mirror of the manifest's metric snapshot
  }
```

CBOR canonical-form, content-addressed-style, written with `If-None-Match:
*`. The PureScript frontend lists the `checkpoints/` prefix once at panel-
load and overlays clickable markers on the TB iframe's loss curve — clicking
opens the inference panel pre-loaded with that manifest SHA.

The current local sidecar surface includes
`JitML.Observability.TensorBoard.checkpointSidecarKey`,
`TbCheckpointMarker`, `encodeTbCheckpointMarker`, and
`JitML.Observability.TbSidecar.{writeCheckpointSidecar,dispatchCheckpointDone,dispatchCheckpointPayload}`
over `HasMinIO`, with filesystem-backed integration coverage.
`JitML.Service.Runtime.daemonTensorBoardDispatcher` wires rendered
`CheckpointDone` payloads into that sidecar writer before ack. Live Linux CPU
validation on 2026-05-19 also writes a marker through
`JitML.Service.MinIOSubprocess` and confirms MinIO stores the CBOR object.

## Bit-Determinism

Target same-substrate same-toolchain reproduction of a checkpoint produces a
byte-identical `.jmw1` payload and a byte-identical manifest SHA. Cross-substrate
bit-equality is **not** guaranteed and not asserted (RNG draws + float reduction
order differ across substrates) per
[determinism_contract.md → The Contract](determinism_contract.md#the-contract).

## Cross-References

- [../../README.md → Checkpointing](../../README.md#checkpointing)
- [../../README.md → Concurrency model](../../README.md#concurrency-model)
- [determinism_contract.md](determinism_contract.md)
- [training_workloads.md](training_workloads.md)
- [../../DEVELOPMENT_PLAN/phase-10-checkpointing-and-inference.md](../../DEVELOPMENT_PLAN/phase-10-checkpointing-and-inference.md)
- [../../DEVELOPMENT_PLAN/phase-16-no-caveat-model-runtime.md](../../DEVELOPMENT_PLAN/phase-16-no-caveat-model-runtime.md)
- [../../DEVELOPMENT_PLAN/phase-18-no-caveat-product-handoff.md](../../DEVELOPMENT_PLAN/phase-18-no-caveat-product-handoff.md)
