# Checkpoint Format

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: README.md, ../documentation_standards.md, ../../DEVELOPMENT_PLAN/phase-0-planning-documentation.md, ../../DEVELOPMENT_PLAN/phase-4-stateful-platform-services.md, ../../DEVELOPMENT_PLAN/phase-10-checkpointing-and-inference.md, determinism_contract.md, training_workloads.md
**Generated sections**: none

> **Purpose**: Project-specific checkpoint format for jitML — split-blob
> layout, `.jmw1` dense weight blob wire format, typed CBOR manifest, write-
> once + If-Match CAS protocol, retention reconciler, inference-only read
> path, and inference request/result protobuf envelopes.

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
`loadInferenceCheckpoint`. The live rollout proceeds storage-outward: validate
those checkpoint writes/reads through the live MinIO capability, then inference
from checkpoint, then training persistence, then tuning/resume. Later workload
layers should not invent parallel persistence paths around the checkpoint store.

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
inference loader. The richer target header shape above remains the durable
contract for full runtime checkpoints.

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

The Haskell `CheckpointManifest` in `src/JitML/Checkpoint/Format.hs` carries
the implemented local shape: manifest id, experiment hash, tensor blobs,
optimizer blobs, RNG blobs, monotonic step, metrics, and optional parent
manifest SHA. `encodeManifestCbor` canonicalizes tensor order by `tensorName`,
optimizer order by `optimizerKind`, RNG order by `rngStreamId`, and metrics by
name; `decodeManifestCbor` round-trips that representation, and
`manifestContentSha` hashes the deterministic CBOR bytes. The richer target
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
`applyRetentionPolicy`, `buildGcPlan`, `listCheckpointManifests`, and
`executeGcPlan` over the typed `HasMinIO` boundary, with filesystem-backed
coverage in tests. The current `jitml internal gc <experiment-hash>` scans
`<cache-dir>/checkpoints/jitml-checkpoints/<experiment-hash>/manifests/`,
prints `gc: <experiment-hash> kept=<n> reaped=<n>`, and exits `3` when the
local plan is a no-op. Live GC traversal and deletion through
`JitML.Service.MinIOSubprocess`, plus live `gc_reaped` Pulsar publication,
remain target runtime work.

## Inference-Only Read Path

Target `loadInferenceCheckpoint :: PointerKey -> ReaderT Env IO (KernelHandle,
CheckpointManifest)` reads `pointers/<>`, fetches `manifests/<sha>`, fetches **only**
the `Weights` part's blob (skipping optimizer state, RNG state, replay
buffer, and exploration cache), and instantiates a `KernelHandle` in
`Inference` kind.

Concurrent training advances are invisible to the reader because the
snapshot the reader operates against is immutable.

The current local read paths are `inferFromManifest`, a deterministic summary
helper used by `jitml inference run` and the local cross-backend stanza,
`JitML.Checkpoint.Store.inferFromLatestCheckpoint`, which reads a local latest
pointer, fetches the addressed manifest, and applies the same deterministic
inference helper, and `inferWeightsOnlyFromLatestCheckpoint`, which clears
optimizer/RNG parts before inference. `loadInferenceCheckpoint` already reads
the latest pointer and manifest through `HasMinIO` and is covered by the
filesystem-backed instance. `loadInferenceCheckpointWith` exposes the
weight-only manifest to a caller-provided runner, and
`JitML.Engines.Local.runLinuxCpuCheckpointInference` validates that the local
Linux CPU path can compile, load, and execute a generated FFI kernel from that
checkpoint read. `JitML.Service.Runtime.daemonWorkloadDispatcherWithInference`
threads the same runner hook through daemon `RunInference` dispatch, and
`jitml service` selects the Linux CPU generated-kernel checkpoint runner for
`linux-cpu` + `SelfInference` configs. `loadInferenceCheckpointWithWeights`
additionally loads the
weight-only `.jmw1` blobs through `HasMinIO`, decodes them, and passes them to
`JitML.Engines.Local.runLinuxCpuWeightedCheckpointInference`, which validates a
local generated-kernel inference smoke path that consumes decoded weight
values. Validating the same weighted path through `JitML.Service.MinIOSubprocess`
and loading real weight blobs into non-local production `KernelHandle`s remain
target work. The inference-only read path is the supported entrypoint for
`jitml-demo` and the PureScript panels.

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
drift is bounded by the per-tensor tolerance band per
[determinism_contract.md → Cross-Substrate Tolerance
Methodology](determinism_contract.md#cross-substrate-tolerance-methodology).

## Cross-References

- [../../README.md → Checkpointing](../../README.md#checkpointing)
- [../../README.md → Concurrency model](../../README.md#concurrency-model)
- [determinism_contract.md](determinism_contract.md)
- [training_workloads.md](training_workloads.md)
- [../../DEVELOPMENT_PLAN/phase-10-checkpointing-and-inference.md](../../DEVELOPMENT_PLAN/phase-10-checkpointing-and-inference.md)
