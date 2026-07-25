# Phase 49: TensorBoard with MinIO Event Storage and Checkpoint Sidecar

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: TensorBoard with MinIO Event Storage and Checkpoint Sidecar. Single-session phase migrated from legacy Sprint 4.6 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 49.1: TensorBoard with MinIO Event Storage and Checkpoint Sidecar [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Observability/TensorBoard.hs`,
`src/JitML/Proto/TensorBoard.hs`, `src/JitML/Observability/TbSidecar.hs`,
`src/JitML/Service/Runtime.hs`, `proto/tensorboard/event.proto`
**Docs to update**: `documents/engineering/daemon_architecture.md`,
`documents/engineering/checkpoint_format.md`

### Objective

Stand up the local TensorBoard shard-key/projection/deployment renderer that the
target TensorBoard chart will consume. The target chart points at MinIO bucket
`jitml-tensorboard`, adds a typed event-file writer with shard rotation, and
writes the CBOR checkpoint sidecar at
`jitml-tensorboard/<experiment-hash>/checkpoints/<step>-<manifest-sha>.cbor`.

### Deliverables

- Current `src/JitML/Observability/TensorBoard.hs` implements deterministic
  event projection, shard-key rendering under
  `jitml-tensorboard/<experiment-hash>/shards/<writer-id>-<shard-seq>.tfevents`,
  TensorBoard Deployment/Service renderers, the in-memory writer state, and
  write-once shard flushing through `HasMinIO.putBlobBytesIfAbsent`.
- `proto/tensorboard/event.proto` carries the TensorFlow-compatible minimal
  `Event` / `Summary.Value.simple_value` schema used by
  `JitML.Proto.TensorBoard.encodeTensorBoardEventProto`; the writer prepends
  the `brain.Event:2` file-version event to the first shard.
- TFRecord framing follows [../README.md → TensorBoard event storage →
  Format](../README.md#format) (uint64 LE length + masked-CRC32C + payload +
  masked-CRC32C). CRC32C is Castagnoli; the mask is TF's standard rotation
  `((crc >> 15) | (crc << 17)) + 0xa282ead8`.
- Bucket layout follows [system-components.md → MinIO Bucket
  Layout](system-components.md#minio-bucket-layout) and [../README.md →
  Bucket layout](../README.md#bucket-layout): overlay mode default, isolated
  mode per Dhall knob, HPO trials always isolated by trial-hash.
- Shard rotation flushes at 4 MiB, 10 s, or explicit `flush` (e.g.
  `CheckpointDone`, graceful shutdown, SIGTERM drain). PUTs use `If-None-
  Match: *`; the same `(writer-id, shard-seq)` is idempotent.
- `TbCheckpointMarker` CBOR sidecar (`tcmStep`, `tcmEpoch`, `tcmManifestSha`,
  `tcmExperimentSha`, `tcmTrialSha`, `tcmRunUuid`, `tcmMetricsAtStep`)
  written on every `CheckpointDone`.
- `JitML.Observability.TbSidecar.checkpointDoneToMarker` converts an already
  decoded typed `CheckpointDone` event to `TbCheckpointMarker`, and
  `dispatchCheckpointDone` writes that typed marker. There is no parallel raw
  payload parser or raw daemon dispatcher.
- HTTPRoute for `/tensorboard` routes the TensorBoard Service through the
  single Envoy Gateway listener (Sprint `3.4`).

### Validation

1. `src/JitML/Observability/TensorBoard.hs` renders deterministic shard
   keys and the TensorBoard deployment surface.
2. `proto/tensorboard/event.proto` exists and is exercised by
   `JitML.Proto.TensorBoard.encodeTensorBoardEventProto`.
3. Live Linux CPU validation on 2026-05-18 confirms the TensorBoard rollout
   reaches Ready.
4. Live Linux CPU validation on 2026-05-19 confirms the TensorBoard chart uses
   a native `python:3.11-slim` TensorBoard container with
   `tensorboard==2.16.2`, `setuptools==69.5.1`, and `numpy<2`, plus a
   Bitnami MinIO client sidecar that mirrors bucket `jitml-tensorboard` into an
   `emptyDir` mounted at `/tensorboard/logs`.
5. Live Linux CPU validation on 2026-05-19 writes a valid TensorBoard event
   file to MinIO at
   `jitml-tensorboard/phase4-live/events/events.out.tfevents.phase4`; the
   sidecar mirrors it into the pod, `/tensorboard/` returns HTML through Envoy,
   and `/tensorboard/data/plugin/scalars/tags` reports
   `phase4-live/events -> phase4/live_scalar`.
6. Live Linux CPU validation on 2026-05-19 invokes
   `JitML.Observability.TbSidecar.dispatchCheckpointDone` through
   `JitML.Service.MinIOSubprocess` against the routed MinIO edge; the write
   returns ETag `caf7dcd34a56656da5effd135ca931eb`, and MinIO reports the CBOR
   sidecar object under
   `jitml-tensorboard/jitml-tensorboard/phase4-live/checkpoints/7-manifest-phase4-live.cbor`.
7. `jitml-unit` validates the Castagnoli CRC32C vectors, TFRecord frame layout,
   TensorBoard shard keys, and the TensorFlow-compatible scalar `Event` protobuf
   encoder against `proto/tensorboard/event.proto`.
8. `jitml-integration` validates the filesystem-backed `HasMinIO` shard writer:
   the writer prepends `brain.Event:2`, flushes a TFRecord shard through
   `putBlobBytesIfAbsent`, increments `tbwsShardSeq`, and treats duplicate
   `(writer-id, shard-seq)` writes as idempotent success.
9. `jitml-integration` validates typed `Training.CheckpointDone` →
   `checkpointDoneToMarker` → `dispatchCheckpointDone` through `TbSidecar`
   into the canonical CBOR sidecar key with no raw-payload reparse.
10. Live Linux CPU validation on 2026-05-19 writes a Haskell-encoded scalar
    shard through routed `JitML.Service.MinIOSubprocess` at
    `http://127.0.0.1:9091/minio/s3`; TensorBoard's routed scalars API reports
    `jitml-tensorboard/phase4-haskell-routed-20260519-1555/shards ->
    phase4/haskell_routed`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
