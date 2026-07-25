# Phase 174: Live MinIO Checkpoint Round-Trip and Retention

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Live MinIO Checkpoint Round-Trip and Retention. Single-session phase migrated from legacy Sprint 15.7 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 174.1: Live MinIO Checkpoint Round-Trip and Retention [✅ Done]

**Status**: Done (re-validated 2026-06-06 on RTX 5090; previously Done on RTX 3090) (closed 2026-05-26)
**Blocked by**: Sprint `169.1`
**Implementation**: `src/JitML/Checkpoint/Store.hs`,
`src/JitML/App.hs`, `test/integration/Main.hs`
**Docs to update**: `documents/engineering/checkpoint_format.md`,
`documents/engineering/determinism_contract.md`

### Objective

Validate the typed `writeCheckpointSnapshotWithMinIO` + `applyPointerWrite`
path against the live MinIO cluster: blobs and manifests land under
`jitml-checkpoints/<experiment-hash>/`, latest-pointer CAS honours
`If-Match`, retry harness backs off per `RetryPolicy`. The
`jitml internal gc` reconciler runs against the live store, deletes
unreferenced blobs, emits `gc_reaped` Pulsar events, and exits `3` on
steady state.

### Deliverables

- A live checkpoint round-trip test in `jitml-integration` writes a
  manifest + blobs through `writeCheckpointSnapshotWithMinIO`, advances
  the latest pointer, then asserts that a subsequent identical write
  surfaces `SEConflict` for the blob and that the latest-pointer CAS
  honours `If-Match`.
- `jitml internal gc <experiment-hash>` against the live store traverses
  the pointer live set, applies `LastN` retention, reaps unreferenced
  blobs from MinIO via `HasMinIO.deleteObject`, publishes `gc_reaped`
  Pulsar events for each delete, and exits `3` on a steady-state run.

### Validation

1. `jitml-integration --test-options='-p Live'` covers the live
   checkpoint round-trip + CAS retry against the running cluster.
2. `jitml internal gc <experiment-hash>` on a live tree produces
   non-zero reap events on the first run and exits `3` (no-op) on the
   second.

### Code Surface Landed (2026-05-25)

- New `Live` case `live checkpoint snapshot round-trip through
  MinIOSubprocess (Sprint 15.7)` in `test/integration/Main.hs` writes
  a `CheckpointManifest` plus a single `TensorBlob` payload to live
  MinIO through `JitML.Service.MinIOSubprocess`, asserts the first
  write produces `PointerWritten`, asserts the second identical write
  surfaces `PointerConflict` (latest-pointer CAS guard), then cleans
  up the three written objects (`blob-weights`, manifest, latest
  pointer) via `deleteObject`. The validation runs against the leased
  edge port read from `cluster-publication.json`.

### Live Validation Note (2026-05-25)

Validation host: same Linux+NVIDIA host as Sprints 15.1 / 15.2 / 13.3.
The 15.7 Live case ran inside the
`docker compose run --rm jitml cabal test --builddir=/root/dist-jitml
jitml-integration --test-options='-p Live'` cohort against the
running cluster (edge port `127.0.0.1:9092`) and exited `OK (0.13s)`,
with all 53 jitml-integration tests passing overall. The first write
populated `jitml-checkpoints/live-ckpt-<suffix>/blobs/blob-weights.bin`,
the manifest at
`jitml-checkpoints/live-ckpt-<suffix>/manifests/<sha>.cbor`, and the
latest pointer at `jitml-checkpoints/live-ckpt-<suffix>/pointers/latest`;
the second write was rejected at the latest-pointer CAS with
`PointerConflict`, confirming the `If-Match` guard is enforced through
the routed S3 SigV4 path.

### Code Surface Landed (2026-05-25, GC half)

- `JitML.Checkpoint.Store.listCheckpointManifestsMinIO :: (HasMinIO m)
  => Text -> m (Either ServiceError [CheckpointManifest])` walks the
  `jitml-checkpoints/<experiment-hash>/manifests/` prefix through
  `HasMinIO.listObjects` and decodes each manifest via
  `decodeManifestCbor`. The existing `JitML.Checkpoint.Store.executeGcPlan`
  function already calls `HasMinIO.deleteObject` for each reaped
  manifest + blob, so combining `listCheckpointManifestsMinIO →
  buildGcPlan → executeGcPlan` is a complete live-MinIO GC pipeline.
- A new `Live` case `live GC: listCheckpointManifestsMinIO +
  executeGcPlan reap (Sprint 15.7)` in `test/integration/Main.hs`
  stages 3 manifests + per-step blobs under a unique
  `live-gc-<suffix>` experiment hash via `putBlobBytesIfAbsent`,
  asserts `listCheckpointManifestsMinIO` returns the expected 3
  manifests, builds a `LastN 2` `GcPlan` (1 reap target — the
  lowest-step manifest), executes the plan, and asserts the
  `gcExecutedReapedManifests = 1` / `gcExecutedReapedBlobs = 1` /
  empty `gcExecutedDeleteFailures` shape. A post-GC re-list confirms
  only 2 manifests remain. Cleanup removes the residual objects.

### Live Validation Note (2026-05-25, GC half)

`cabal test jitml-integration --test-options='-p Live'` cohort on the
Sprint 15.1 cluster:

```
    live GC: listCheckpointManifestsMinIO + executeGcPlan reap (Sprint 15.7):  OK (0.25s)
```

All 7 Live cases pass (`1.31s` total).

### Live Validation Note (2026-05-26, CLI wiring)

```
    live jitml internal gc reaps from live MinIO (Sprint 15.7 CLI):            OK (0.64s)
```

`cabal test jitml-integration --test-options='-p Live'` cohort on a
fresh `jitml bootstrap --linux-cuda` cluster — 9/9 Live pass in
`2.09s`. The new case stages six manifests + blobs under
`live-cli-gc-<suffix>`, spawns `./.build/jitml internal gc <hash>` via
the typed `Subprocess` boundary, asserts the stdout reports
`reaped=1 reaped-blobs=1`, re-runs the same command and asserts exit
`3` (`ReconcilerNoop`), then cleans up.

### Code Surface Landed (2026-05-26, CLI wiring)

- `JitML.App.runInternalGc` now detects the live cluster publication
  (`./.build/runtime/cluster-publication.json`) and routes through
  `JitML.Checkpoint.Store.listCheckpointManifestsMinIO` +
  `executeGcPlan` via `JitML.Service.MinIOSubprocess.runMinIOSubprocess`
  against the leased edge port. Without a live publication the
  reconciler still walks the local on-disk cache root, preserving the
  prior behaviour for offline use. The stdout line now reports
  `kept=<N> reaped=<M> reaped-blobs=<K>` so the live test can assert
  the reap counts.
- A new `Live` case `live jitml internal gc reaps from live MinIO
  (Sprint 15.7 CLI)` in `test/integration/Main.hs` (a) stages six
  manifests + blobs under a unique
  `live-cli-gc-<suffix>` experiment hash, (b) spawns
  `./.build/jitml internal gc --experiment-hash <hash>` via the typed
  `Subprocess` boundary, asserts the stdout contains `reaped=1` and
  `reaped-blobs=1` (the hardcoded `LastN 5` reaps the lowest of 6),
  (c) re-runs the same command and asserts exit code `3`
  (`ReconcilerNoop`), then (d) cleans up.

### Code Surface Landed (2026-05-26, gc_reaped Pulsar envelope)

- `JitML.Proto.Gc` defines the `GcReapedEvent` envelope
  (`experiment_hash` / `manifest_sha` / repeated `reaped_blob_shas` /
  `step_at_reap` / `substrate` / `timestamp_ns`) with `renderGcReapedEvent`
  / `parseGcReapedEvent` text codecs and
  `encodeGcReapedEventProto` / `decodeGcReapedEventProto`
  proto3-compatible byte codecs sharing `JitML.Proto.Wire`.
- `JitML.Proto.Gc.gcEventTopic Substrate` returns
  `persistent://public/default/gc.event.<substrate>`; the matching
  topic is registered in the derived `JitML.Cluster.PulsarBootstrap.pulsarTopics`
  family. At that checkpoint the topic family size grew from 26 to 29
  (`gc.event.<substrate>` added); later Apple host-command additions brought the
  then-current topology to 31; Sprint `5.18` subsequently brings the current
  family to 34 with `workflow.status.<substrate>`.
- `proto/jitml/gc.proto` describes the same envelope for cross-binding
  use through `proto-lens`.
- `JitML.App.runInternalGc` now invokes
  `publishGcReapedEvents publication executed plan` after the live
  `executeGcPlan` returns: for each reaped manifest the helper
  constructs a `GcReapedEvent` (timestamp via `getPOSIXTime`,
  substrate from the live publication), and publishes it through
  `JitML.Service.PulsarWebSocketSubprocess.runPulsarWebSocketSubprocess` +
  `Capabilities.pulsarPublish`. Publication failures are surfaced as
  a stderr line but do not roll back the MinIO delete and do not
  short-circuit the reconciler (at-least-once handles the missed
  event on a subsequent run).
- `jitml-unit` adds 4 new tests under the "GC reaped event envelope
  (Sprint 15.7)" group covering the substrate-scoped topic name, the
  proto3 byte round-trip, the text render/parse round-trip, and the
  empty-blobs degenerate case (107/107 unit tests pass).
- `jitml-integration` updated the "Pulsar bootstrap registers the
  substrate-scoped topic family" assertion to the then-current 29 topics with
  the three new `gc.event.<substrate>` entries (47/47 non-Live integration
  tests passed). The assertion later became 31 topics after the host-command
  additions and is now 34 after Sprint `5.18` adds the three
  `workflow.status.<substrate>` routes.

### Live Validation Note (2026-05-26, gc.event publish stream)

Closes Sprint 15.7's last open Remaining Work item. New `Live` case
`live jitml internal gc publishes GcReapedEvent on
gc.event.<substrate> (Sprint 15.7 events)` in
`test/integration/Main.hs`: (a) subscribes to
`ProtoGc.gcEventTopic substrate` with a unique-suffix subscription
through `PulsarWebSocketSubprocess`, (b) stages 6 manifests + blobs
under a unique `live-gce-<suffix>` experiment hash so the CLI's
`LastN 5` retention reaps exactly the lowest-step manifest, (c) runs
`./.build/jitml internal gc <hash>` via the typed `Subprocess`
boundary and asserts `reaped=1` in stdout, (d) consumes one payload
from the gc-event subscription, parses it through
`ProtoGc.parseGcReapedEvent`, and asserts
`gcEventExperimentHash`, `gcEventManifestSha`, `gcEventStepAtReap = 1`,
and `gcEventSubstrate` all match the expected values. The
post-validation cleanup removes the remaining 5 manifests + 6 blobs.

```
jitml-integration
  Live
    live jitml internal gc publishes GcReapedEvent on gc.event.<substrate> (Sprint 15.7 events): OK (0.69s)
```

Run via `cabal test jitml-integration --test-options='-p Live'` against
the fresh `jitml bootstrap --linux-cuda` cluster (edge port 9092 on
the same RTX 3090 / CUDA 12.8 host as the 2026-05-26 cluster
bring-up). The full Live cohort is 10/10 in ~2.92s.

### Remaining Work

- None remaining for Sprint 13.7. Sprint closed 2026-05-26.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
