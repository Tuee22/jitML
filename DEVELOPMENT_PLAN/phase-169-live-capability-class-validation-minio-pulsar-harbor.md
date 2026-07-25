# Phase 169: Live Capability Class Validation (MinIO + Pulsar + Harbor)

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Live Capability Class Validation (MinIO + Pulsar + Harbor). Single-session phase migrated from legacy Sprint 15.2 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 169.1: Live Capability Class Validation (MinIO + Pulsar + Harbor) [✅ Done]

**Status**: Done (re-validated 2026-06-06 on RTX 5090; previously Done on RTX 3090) (closed 2026-05-26)
**Blocked by**: Sprint `168.1`
**Implementation**: `src/JitML/Service/MinIOSubprocess.hs`,
`src/JitML/Service/PulsarWebSocketSubprocess.hs`,
`src/JitML/Service/HarborSubprocess.hs`,
`src/JitML/Checkpoint/Store.hs`, `test/integration/Main.hs`
**Docs to update**: `documents/engineering/daemon_architecture.md`,
`documents/engineering/checkpoint_format.md`

### Objective

Exercise every `HasMinIO` / `HasPulsar` / `HasHarbor` method through the
running cluster: `putBlobIfAbsent` with `If-None-Match: *` returns ETag
on first write and `SEConflict` on subsequent identical PUTs;
`applyPointerWrite` honours `If-Match` and surfaces `412` as
`SEConflict`; `pulsarPublish` / `pulsarConsume` round-trip a payload on
a substrate-scoped topic; `harborPromoteImage` promotes a tag through
the live registry. Closes Exit Definition item 2's live capability slice
and the live MinIO halves of items 7 and 5.

### Deliverables

- A live MinIO conditional-write test asserts both first-write success
  and subsequent-conflict for `putBlobIfAbsent` plus `casPointer`
  through `JitML.Service.MinIOSubprocess`.
- A live Pulsar WebSocket publish/consume test on a substrate-scoped
  topic round-trips a payload and asserts subscription acquisition as
  `jitml-service`.
- A live Harbor tag-promotion test round-trips an image through the
  same-repository promotion path.
- The bucket layout for `jitml-checkpoints/<experiment-hash>/` holds
  blobs/manifests after a controlled write under the live capability
  classes.

### Validation

1. On Linux+Docker+NVIDIA, with the cluster from Sprint `15.1` up: a
   targeted `jitml-integration --test-options='-p Live'` (or equivalent
   bespoke driver) exercises the three capability classes and exits `0`.

### Live Validation Note (2026-05-25)

Validation host: same Linux+NVIDIA host as Sprint 15.1 (RTX 3090, CUDA
12.8 driver, Ubuntu 24.04, Docker 29.5.0). Driver:
`docker compose run --rm jitml cabal test --builddir=/root/dist-jitml
jitml-integration --test-options='-p Live'` against the Sprint 15.1
cluster at `127.0.0.1:9092`.

```
jitml-integration
  Live
    live HasMinIO conditional writes round-trip on jitml-checkpoints:        OK (0.09s)
    live HasMinIO listObjects sees a freshly written object:                 OK (0.04s)
    live HasPulsar publish/subscribe/consume round-trip on training.command: OK (0.36s)

All 50 tests passed (2.81s)
Test suite jitml-integration: PASS
```

Covered: the three new `Live` cases drive `HasMinIO.putBlobIfAbsent`
(first-PUT success + SEConflict on duplicate), `HasMinIO.casPointer`
(stale `If-Match` → SEConflict, fresh `If-Match` → ETag),
`HasMinIO.listObjects` (sees a freshly written prefix entry),
`HasMinIO.deleteObject` (best-effort post-test cleanup), and the
`HasPulsar` full round-trip
(`pulsarSubscribe` → `pulsarPublish` → `pulsarConsume` →
`pulsarAcknowledge`) through `/pulsar/ws` against
`persistent://public/default/training.command.linux-cuda`. Every
assertion runs through `JitML.Service.MinIOSubprocess` /
`JitML.Service.PulsarWebSocketSubprocess` — the same instances the
daemon uses — and reads the leased edge port from
`./.build/runtime/cluster-publication.json` via
`requireLivePublication`.

### Live Validation Note (2026-05-26, Harbor tag promotion)

Closes the live Harbor capability slice. New `Live` case `live
HasHarbor same-repository tag promotion round-trip (Sprint 15.2
Harbor)` in `test/integration/Main.hs`:
(a) calls `ensureLocalImage "alpine:3.20"` so the host docker daemon
has a ~5MB source image, (b) `docker tag alpine:3.20
127.0.0.1:9092/library/jitml-harbor-test-<suffix>:initial` via the
typed `Subprocess` boundary, (c) drives `harborPushImage initialRef`
through `HarborSubprocess` (typed `docker login` + `docker push`), (d)
asserts `harborImageExists initialRef == Right True`, (e) drives
`harborPromoteImage initialRef currentRef` (same-repo path, uses
Harbor's `/v2.0/.../tags` API directly, no docker push), and (f)
asserts `harborImageExists currentRef == Right True`. Post-test
cleanup deletes the test repository through the Harbor REST API.

```
jitml-integration
  Live
    live HasHarbor same-repository tag promotion round-trip (Sprint 15.2 Harbor): OK (0.97s)
```

Validated against the same RTX 3090 cluster from the 2026-05-26
bring-up (edge port 9092, Harbor admin password from
`secret/harbor-core`). Full Live cohort: 11/11 in 5.47s.

### Live Validation Note (2026-05-26, subscription acquisition)

Closes the last remaining 15.2 obligation. New `Live` case `live
jitml-service holds subscriptions on all four daemon command topics
(Sprint 15.2 acquisition)`: iterates the four daemon-side command
topics
(`training.command.<substrate>`, `tune.command.<substrate>`,
`rl.command.<substrate>`, `inference.request.<substrate>`), runs
`kubectl exec -n platform pulsar-toolset-0 -- /pulsar/bin/pulsar-admin
topics stats <topic>` via the typed `Subprocess` boundary, decodes
the JSON, and asserts `subscriptions["jitml-service"].consumers` is a
non-empty array on every topic.

```
jitml-integration
  Live
    live jitml-service holds subscriptions on all four daemon command topics (Sprint 15.2 acquisition): OK (7.73s)
```

Full Live cohort: 12/12 in 12.53s.

### Remaining Work

- None remaining for Sprint 13.2. Sprint closed 2026-05-26.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
