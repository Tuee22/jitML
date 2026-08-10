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

Validate the then-current typed checkpoint snapshot + pointer-CAS path against
the live MinIO cluster: blobs and manifests land under
`jitml-checkpoints/<experiment-hash>/`, latest-pointer CAS honours
`If-Match`, retry harness backs off per `RetryPolicy`. The
`jitml internal gc` reconciler runs against the live store, deletes
unreferenced checkpoint objects, emits `GcReapedEvent` Pulsar events, and exits
`3` on steady state. Phase `262` owns the remaining hardening of the retained
reconciler but is currently Blocked by Phase `69`; its target contract is
recorded below and in
[checkpoint_format.md](../documents/engineering/checkpoint_format.md#retention-and-gc).

### Deliverables

- A live checkpoint round-trip test in `jitml-integration` writes a
  manifest + blobs through `writeCheckpointSnapshotWithMinIO`, advances
  the latest pointer, then asserts that a subsequent identical write
  surfaces `SEConflict` for the blob and that the latest-pointer CAS
  honours `If-Match`.
- `jitml internal gc <experiment-hash>` against the live store lists the
  experiment's candidate manifests, applies `LastN` retention, reaps
  unreferenced physical objects from MinIO via `HasMinIO.deleteObject`,
  publishes `GcReapedEvent` records, and exits `3` on a steady-state run. The
  original Phase `174` live evidence below remains historical; Phase `262`
  owns the current intrinsic/append-only roots and durable retry protocol.

### Validation

1. `jitml-integration --test-options='-p Live'` covers the live
   checkpoint round-trip + CAS retry against the running cluster.
2. `jitml internal gc <experiment-hash>` on a live tree produces
   non-zero reap events on the first run and exits `3` (no-op) on the
   second.

### Phase 262 Hardened Target Contract (Blocked)

- `jitml internal gc` is an explicit operator/external-scheduler reconciler;
  trainers do not invoke it.
- New writers derive
  `snapshot-id = sha256(canonical-CBOR("jitml-snapshot-v1", logical manifest,
  sorted(original-key,payload-sha)))`, persist an exact
  per-attempt `snapshots/<snapshot-id>/reservations/<attempt-id>.cbor` before
  payload-object writes, and store every payload object at the exact scoped address
  derived from its canonical original key. Reservation and commit records bind
  the sorted canonical-original → exact-scoped → payload-SHA descriptor; Store
  reverses it to reconstruct the logical manifest and re-derive the snapshot
  id. Only the exact attempt-independent `committed.cbor` makes that snapshot
  eligible for admission, retention, or GC. Attempt ids are fixed-width
  lowercase-hex counters allocated by absent-only marker create; every conflict,
  including identical bytes, increments the counter, so attempts never share a
  marker and need no RNG/lease.
- The canonical experiment-scoped `ExperimentGcFence` at
  `jitml-checkpoints/<experiment-hash>/gc/coordination-fence.txt` carries a
  version, bound experiment hash, monotonic CAS revision, separate monotonic
  writer/root-activity epoch, canonical full active reservation set, and
  canonical `GcFenceDecision` histories. Every reservation registration and
  unregister increments the epoch; GC-only decision revisions do not. Per-event absence
  is `Open`; generations are contiguous and use `Planned`, `Cancelling`,
  complete `Cancelled`, `Executing`, or permanent `Reaped`; every prior
  generation is complete `Cancelled`, and only the latest may be nonterminal or
  destructive.
  Experiment scope preserves a child reservation's cross-snapshot
  `parentManifestSha` overlap. A writer CAS-registers its full reservation before
  marker creation, atomically moving every overlapping planned event to
  `Cancelling` and rejecting overlap with executing or reaped state before
  mutation. The writer helps persist the immutable cancellation artifact and
  complete `Cancelled` before marker creation or payload mutation. The semantic
  intent and cancellation artifact may remain physically present across
  generations; the latest exact fence phase determines their logical activity,
  and delayed helpers only repeat the same byte-identical PUT. The marker
  still precedes every payload write. Candidate writes commit after manifest;
  completed writes CAS latest before commit. Success deletes only its own marker
  and then CAS-unregisters only its own entry. Exact retry acquires a fresh
  marker. Every crashed entry or marker remains a permanent root even after a
  matching commit; commit never overrides it. A marker conflict also leaves the
  attempt's entry as conservative protection because marker ownership cannot be
  proved, and advances through a freshly registered attempt. Atomic MinIO byte-plus-ETag read
  and CAS provide this exclusion. GC brackets its complete fresh root view with
  matching epoch observations and may move `Open` or complete `Cancelled` to
  `Planned` only at that exact epoch, while GC-only sibling revisions leave the
  witness valid. The current Phase `262` reconciler converges this view in a
  bounded loop: epoch churn restarts it, and an epoch-stable plan that persists
  an absent exact durable intent restarts the entire view before authorization.
  A local lock or pair of scans does not provide this proof.
- For a zero-payload-object logical manifest, Phase `262` Store derives
  `snapshot-id = sha256(canonical-CBOR("jitml-snapshot-v1", exact logical
  manifest, []))`. Its exact derived `committed.cbor` is the sole GC-owned key
  and enables admission, retention, and GC. Without that commit, a legacy empty
  manifest remains decode/inspection-only, protected, and ineligible; Phase
  `262` still owns the focused and aligned-image validation of this rule.
- Every MinIO manifest, commit/reservation-marker, browser-catalogue-root,
  durable-intent/cancelled, and ready/published scan consumes all ListObjectsV2
  pages. Page one omits the continuation-token echo, every later page echoes
  exactly the requested token, and keys remain globally strictly ascending.
  Malformed state, token mismatch/cycles, duplicate or reordered keys, response
  mismatch, decode errors, or any page transport failure fail closed.
- Retention rank is canonical `(step descending, manifest SHA ascending)`.
  Completed canonical ProductRow manifests are intrinsic roots, and immutable
  `pointers/browser-catalogues/<catalogue-sha>` objects are append-only archival
  roots. Both override `LastN` and retain their immediate manifest parent.
- One plan covers the full snapshot-owned deletion graph: the exact
  `committed.cbor` plus tensor, optimizer, RNG, replay/transcript companion, and
  substrate-artifact payload-object keys. Each event contains keys from exactly
  one snapshot and exactly one commit. The exact commit descriptor reconstructs
  and re-derives that ownership identity and scopes the deletion keys; the
  experiment CAS fence provides the stale-executor exclusion proof.
- Before deletion the exact initial plan is persisted at
  `jitml-checkpoints/<experiment>/gc/intents/<event-id>.cbor`. The executor then
  converges a fresh complete view of manifests, pointer bodies, catalogue and intrinsic roots,
  marker reservations, the experiment fence's full reservations and event
  generations, ready records, and published tombstones, bracketed by matching
  observations of the fence's writer/root-activity epoch. The loop is bounded
  and restarts the entire view on epoch churn. An epoch-stable fresh plan that
  discovers an exact event absent from durable intent state first persists its
  canonical intent and then restarts the entire view. Only the converged plan
  supplies `kept` and no-op, and creating an exact initial-plan or fresh-plan
  intent counts as work. Exact work moves
  `Open` → `Planned(g,event)` at that exact epoch and then to
  `Executing(g,event)` only while no active entry overlaps it. A writer insertion
  atomically changes overlapping planned events to `Cancelling(g,event)`.
  Writers, coordinators, or helpers durably write the byte-identical cancellation
  artifact and CAS to complete `Cancelled(g,event)` before writer mutation or
  re-arm. Neither cancellation nor authorization deletes the semantic intent or
  physically retires that artifact; the stable objects may span generations and
  only the latest exact fence phase makes either logically active. Delayed helpers
  therefore have only an idempotent PUT to repeat. Only after cancellation
  completes may the event re-arm as generation `g+1`, after roots/markers
  disappear and at an exact newly witnessed epoch;
  executors and helpers re-read exact executing state
  and consume opaque Store authorization through `executeAuthorizedGcIntents`,
  the sole destructive execution API. No plan or raw-intent compatibility
  execution export remains. Completion CASes to permanent
  `Reaped`. Any changed protection records whole-intent
  `gc/cancelled/<event-id>.cbor` and deletes none of it. Semantic-intent cleanup
  occurs only after `Reaped` during ready/published terminal handling. A global manifest barrier
  requires every reap-target manifest DELETE to acknowledge before
  snapshot-owned DELETE; already-absent DELETE is retry success.
- Exact fully completed intents whose fence decision is permanent `Reaped` are promoted to
  `jitml-checkpoints/<experiment>/gc/ready/<event-id>.cbor` only after checks for
  a permanent `gc/published/<event-id>.cbor` both before and after ready PUT.
  `event_id` binds the experiment, manifest SHA, step, and sorted unique
  `reaped_object_keys`, including the exact commit; substrate and completion
  timestamp are fixed once. The
  stored substrate selects the topic through the current edge. Broker success
  is followed by absent-or-identical published-tombstone persistence and only
  then post-`Reaped` ready/intent cleanup, so recovery never recreates an acknowledged event.
- Broker text is `jitml-gc-reaped-event-protobuf-hex-v1:` plus lowercase hex of
  canonical protobuf bytes. Decode requires canonical re-encoding, full safe
  snapshot keys, one snapshot namespace, exactly one `committed.cbor`, sorted
  uniqueness, and exact manifest/event identity.
- The live summary is `kept=<n> reaped=<n> reaped-objects=<n>`.
  `reaped` counts exact completed manifest intents; `reaped-objects` counts the
  corresponding snapshot-owned delete acknowledgements, including the commit
  and confirmed-already-absent retry targets. A zero-payload-object snapshot
  therefore contributes `reaped-objects=1`. Exit `3` is reserved for a
  converged-plan no-op with no reconciliation or recovered-outbox work.

The dated sections below are retained historical landing/validation evidence.
Names such as `writeCheckpointSnapshotWithMinIO`, count-only GC result fields,
`reaped-blobs`, and direct post-delete publication describe those snapshots,
not the current API or durability contract.

### Historical Code Surface Landed (2026-05-25)

- New `Live` case `live checkpoint snapshot round-trip through
  MinIOSubprocess (Sprint 15.7)` in `test/integration/Main.hs` writes
  a `CheckpointManifest` plus a single `TensorBlob` payload to live
  MinIO through `JitML.Service.MinIOSubprocess`, asserts the first
  write produces `PointerWritten`, asserts the second identical write
  surfaces `PointerConflict` (latest-pointer CAS guard), then cleans
  up the three written objects (`blob-weights`, manifest, latest
  pointer) via `deleteObject`. The validation runs against the leased
  edge port read from `cluster-publication.json`.

### Historical Live Validation Note (2026-05-25)

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

### Historical Code Surface Landed (2026-05-25, GC half)

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

### Historical Live Validation Note (2026-05-25, GC half)

`cabal test jitml-integration --test-options='-p Live'` cohort on the
Sprint 15.1 cluster:

```
    live GC: listCheckpointManifestsMinIO + executeGcPlan reap (Sprint 15.7):  OK (0.25s)
```

All 7 Live cases pass (`1.31s` total).

### Historical Live Validation Note (2026-05-26, CLI wiring)

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

### Historical Code Surface Landed (2026-05-26, CLI wiring)

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

### Historical Code Surface Landed (2026-05-26, gc_reaped Pulsar envelope)

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
- At that historical checkpoint, `JitML.App.runInternalGc` invoked
  `publishGcReapedEvents publication executed plan` after the live
  `executeGcPlan` returns: for each reaped manifest the helper
  constructs a `GcReapedEvent` (timestamp via `getPOSIXTime`,
  substrate from the live publication), and publishes it through
  `JitML.Service.PulsarWebSocketSubprocess.runPulsarWebSocketSubprocess` +
  `Capabilities.pulsarPublish`. Publication failures surfaced as a stderr line
  after the MinIO delete. That count-based direct-publish path did not durably
  retain a missed event; Phase `262` owns its replacement with
  intent/cancelled/ready/published records and the byte-stable at-least-once
  retry contract, and remains Active until the replacement's gates pass.
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

### Historical Live Validation Note (2026-05-26, gc.event publish stream)

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

- None.

## Documentation Requirements

**Engineering docs to create/update:**

- `../documents/engineering/checkpoint_format.md`
- `../documents/engineering/determinism_contract.md`

**Product docs to create/update:**

- None.

**Cross-references to add:**

- Link the active hardened GC target contract to
  [Phase 262](phase-262-contract-driven-live-execution-browser-and-playwright.md).
