# Checkpoint Format

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: README.md, ../documentation_standards.md, ../../DEVELOPMENT_PLAN/phase-0-planning-documentation.md, ../../DEVELOPMENT_PLAN/phase-4-stateful-platform-services.md, ../../DEVELOPMENT_PLAN/phase-10-checkpointing-and-inference.md, determinism_contract.md, training_workloads.md
**Generated sections**: none

> **Purpose**: Project-specific checkpoint format for jitML — split-blob
> layout, `.jmw1` dense weight blob wire format, typed CBOR manifest, write-
> once + If-Match CAS protocol, retention reconciler, inference-only read
> path.

## Storage Layout

The `jitml-checkpoints` MinIO bucket uses a fixed prefix schema, owned by
`src/JitML/Storage/Layout.hs` so paths are typed values rather than stringly-
typed call sites:

```
jitml-checkpoints/
  <experiment-hash>/                      -- sha256(resolved-dhall || graph-shape-hash)
    blobs/<sha256>                        -- write-once, content-addressed, opaque bytes
    manifests/<sha256>                    -- write-once, content-addressed, CBOR manifest objects
    pointers/
      latest                              -- mutable, ETag-CAS; body = 32-byte manifest sha
      best/<metric>                       -- mutable, ETag-CAS; body = 32-byte manifest sha
      trial/<trial-hash>/latest           -- per-HPO-trial latest pointer
      trial/<trial-hash>/best/<metric>    -- per-HPO-trial best pointer
```

`experiment-hash = sha256(resolved-dhall || graph-shape-hash)`.
`manifest-sha = sha256(canonical-cbor(CheckpointManifest))`.

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

The blob starts with magic bytes, a canonical-CBOR header length, the
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

`cmWallClockNs` is telemetry only and is never an input to any content hash.
`cmParts` is canonical-ordered by role. CBOR canonical-form encoding makes
the manifest SHA deterministic.

## Concurrency Model

All race conditions between trainers, hyperparameter-trial workers, and
inference clients are eliminated at the protocol layer; nothing relies on
advisory locks, leases, or a separate lock service.

| Hazard | Resolution |
|--------|------------|
| Write/write on `blobs/*` and `manifests/*` | Impossible by construction — keys are derived from `sha256(payload)`. Two writers with the same logical payload write the same key with the same bytes; `If-None-Match: *` `412` is success. |
| Write/read on `blobs/*` and `manifests/*` | Impossible — S3 object PUT is atomic at the object level. |
| Write/write on `pointers/*` | `If-Match: <etag>` CAS. Loser receives `412` → `MinIOPreconditionFailed` → `SEConflict` (retryable). The retry harness re-reads the pointer, applies the caller's resolution policy, and retries. |
| Write/read on `pointers/*` | A reader observes either the old ETag's bytes or the new ETag's bytes. Both name valid immutable manifests. No torn state because the only mutation is a single object PUT (atomic) of a 32-byte body. |

## Typed Advance Predicates

The pointer-CAS retry harness applies a typed predicate `CurrentManifest →
ProposedManifest → Bool`:

| Predicate | Meaning |
|-----------|---------|
| `advanceLatest` | `cmStep new > cmStep cur` |
| `advanceBestMaximised` | `lookupMetric m new > lookupMetric m cur` |
| `advanceBestMinimised` | `lookupMetric m new < lookupMetric m cur` |

Trainers pick `Maximised` vs `Minimised` from the experiment Dhall's
`metrics[i].direction` field. The direction is part of the resolved-Dhall
hash, so flipping a metric's direction defines a *different experiment*.

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

Retention (`retain = Checkpoint.Retention.LastN k` in the experiment Dhall)
is enforced by a reconciler — `jitml internal gc <experiment-hash>` —
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

## Inference-Only Read Path

`loadInferenceCheckpoint :: PointerKey -> ReaderT Env IO (KernelHandle,
CheckpointManifest)` reads `pointers/<>`, fetches `manifests/<sha>`, fetches **only**
the `Weights` part's blob (skipping optimizer state, RNG state, replay
buffer, and exploration cache), and instantiates a `KernelHandle` in
`Inference` kind.

Concurrent training advances are invisible to the reader because the
snapshot the reader operates against is immutable.

The inference-only read path is the supported entrypoint for `jitml-demo`
and the PureScript panels.

## TensorBoard Sidecar

Every `CheckpointDone` event also writes a CBOR sidecar at
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

## Bit-Determinism

Same-substrate same-toolchain reproduction of a checkpoint produces a byte-
identical `.jmw1` payload and a byte-identical manifest SHA. Cross-substrate
drift is bounded by the per-tensor tolerance band per
[determinism_contract.md → Cross-Substrate Tolerance
Methodology](determinism_contract.md#cross-substrate-tolerance-methodology).

## Cross-References

- [../../README.md → Checkpointing](../../README.md#checkpointing)
- [../../README.md → Concurrency model](../../README.md#concurrency-model)
- [determinism_contract.md](determinism_contract.md)
- [training_workloads.md](training_workloads.md)
- [../../DEVELOPMENT_PLAN/phase-10-checkpointing-and-inference.md](../../DEVELOPMENT_PLAN/phase-10-checkpointing-and-inference.md)
