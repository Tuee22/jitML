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
[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
**Generated sections**: none

> **Purpose**: Stand up the split-blob checkpoint format (`blobs/<sha256>`,
> `manifests/<sha256>`, `pointers/{latest,best/<metric>,trial/...}`), the
> `.jmw1` dense weight blob wire format, the typed CBOR manifest, the
> `If-None-Match: *` write-once protocol for blobs and manifests, the
> `If-Match: <etag>` CAS protocol for pointers with typed advance predicates,
> the bit-determinism contract scoped to same-substrate equality with the
> cross-substrate tolerance methodology, the retention reconciler
> (`jitml internal gc`), and the inference-only read path consumed by both
> `jitml-demo` and the PureScript panels.

## Phase Status

✅ **Done** for the local checkpoint manifest, `.jmw1` blob header, and
inference-only read surfaces. Checkpointing serialises models trained in Phases
`8`/`9`; the inference-only read path is consumed by Phase `11`'s demo HTTP
server and PureScript panels.

## Phase Summary

This phase delivers the persistence layer in MinIO bucket `jitml-checkpoints`,
the `.jmw1` dense weight blob format with a canonical-CBOR header, the
typed manifest, the concurrency model from
[../README.md → Concurrency model](../README.md#concurrency-model) (write-
once + If-Match CAS — no advisory locks), the typed retention reconciler with
exit code `3` on no-op, the bit-determinism contract scoped to same-substrate
equality, and the inference-only read path. There is no Postgres on jitML's
data path: manifests and blobs live in MinIO exclusively.

## Sprint 10.1: Storage Layout and Split-Blob Schema ✅

**Status**: Done
**Implementation**: `src/JitML/Checkpoint/Format.hs`,
`src/JitML/Storage/Buckets.hs`
**Docs to update**: `documents/engineering/checkpoint_format.md`

### Objective

Establish the typed prefix schema for the `jitml-checkpoints` bucket and the
split-blob layout (one immutable weight blob per uniquely shaped tensor group
plus a typed manifest enumerating the blob keys).

### Deliverables

- `src/JitML/Checkpoint/Format.hs` is the typed source of truth for every key
  pattern under `jitml-checkpoints/<experiment-hash>/`:
  - `blobs/<sha256>` — write-once content-addressed payloads.
  - `manifests/<sha256>` — write-once content-addressed CBOR manifests.
  - `pointers/latest` — mutable, ETag-CAS; body = 32-byte manifest sha.
  - `pointers/best/<metric>` — mutable, ETag-CAS.
  - `pointers/trial/<trial-hash>/latest` — per-HPO-trial latest.
  - `pointers/trial/<trial-hash>/best/<metric>` — per-HPO-trial best.
- `Checkpoint` ADT enumerates the blob roles: weights per layer (one per
  uniquely shaped tensor group), optimizer state, RNG state, replay buffer
  (RL only), exploration cache (RL only).
- `experiment-hash = sha256(resolved-dhall || graph-shape-hash)`.
- `manifest-sha = sha256(canonical-cbor(CheckpointManifest))`.
- The `pointers/latest` update is the **single atomic commit point** for a
  checkpoint per [../README.md → Concurrency
  model](../README.md#concurrency-model).

### Validation

1. `Layout` round-trips every key pattern through `parseKey . renderKey ==
   id`.
2. `jitml-unit` exercises the `experiment-hash` derivation against a
   resolved-Dhall fixture and asserts SHA-256 byte-equality.

## Sprint 10.2: `.jmw1` Wire Format and Manifest CBOR ✅

**Status**: Done
**Implementation**: `src/JitML/Checkpoint/Format.hs`
**Docs to update**: `documents/engineering/checkpoint_format.md`

### Objective

Land the `.jmw1` dense weight blob format (magic bytes, `header_len`,
canonical-CBOR `JmwHeader`, packed little-endian payload), the typed CBOR manifest, the `If-None-Match: *`
write-once protocol for blobs and manifests, and the `If-Match: <etag>` CAS
protocol for pointers with typed advance predicates.

### Deliverables

- `.jmw1` wire format documented in
  [`documents/engineering/checkpoint_format.md`](../documents/engineering/checkpoint_format.md):
  magic `JMW1`, `header_len :: Word32`, canonical-CBOR `JmwHeader`, then packed
  little-endian payload bytes.
- `CheckpointManifest` CBOR record carries: `experiment-hash :: Hash`,
  `trial-hash :: Maybe Hash`, `step :: Word64`, `epoch :: Word64`,
  `wall-clock-ns :: Word64` for telemetry only, `substrate :: Substrate`,
  `schema-version :: Word32`, canonical-ordered `parts :: [CheckpointPart]`,
  sorted metrics, and `parent-manifest :: Maybe Hash`.
- `Write.hs` exposes `putBlobIfAbsent :: Hash -> ByteString -> ReaderT Env
  IO ()` using `If-None-Match: *`; `412 Precondition Failed` is success.
- `Pointer.hs` exposes `casPointer :: PointerKey -> AdvancePredicate ->
  Manifest -> ReaderT Env IO ()` using `If-Match: <etag>`; `412` is
  `SEConflict` (retryable per Sprint `5.4`'s `RetryPolicy`).
- Typed advance predicates: `advanceLatest` (`step new > step cur`),
  `advanceBestMaximised` (`lookupMetric m new > lookupMetric m cur`),
  `advanceBestMinimised` (`lookupMetric m new < lookupMetric m cur`). The
  metric direction comes from the experiment Dhall's `metrics[i].direction`
  field per [../README.md → Concurrency
  model](../README.md#concurrency-model).

### Validation

1. `decodeJmw1 . encodeJmw1 == id` across a property-test grid.
2. `decodeManifest . encodeManifest == id`.
3. `putBlobIfAbsent` is idempotent (golden round trip; second write returns
   `412` and the harness translates to success).
4. `casPointer` under contention exercises the retry harness and converges
   to a single committed manifest.

## Sprint 10.3: Bit-Determinism Contract and Retention Reconciler ✅

**Status**: Done
**Implementation**: `src/JitML/App.hs`, `src/JitML/Plan/Plan.hs`
**Docs to update**: `documents/engineering/determinism_contract.md`,
`documents/engineering/checkpoint_format.md`

### Objective

Land the bit-determinism contract scoped to same-substrate equality, the
cross-substrate tolerance methodology, and the typed retention reconciler
`jitml internal gc <experiment-hash>` with exit code `3` on no-op.

### Deliverables

- The bit-determinism contract holds: a checkpoint produced on `<substrate>`
  is bit-identical when reproduced on the same `<substrate>` against the
  same toolchain pin (matches the per-substrate determinism contract from
  Phase `7`).
- Cross-substrate drift is bounded by the per-tensor tolerance band; the
  tolerance methodology is documented in
  [`documents/engineering/determinism_contract.md`](../documents/engineering/determinism_contract.md).
- `jitml internal gc <experiment-hash>` is a Plan/Apply reconciler:
  - Reads `pointers/latest`, every `pointers/best/<metric>` for the metrics
    declared in the experiment Dhall, every `pointers/trial/<trial-hash>/*`
    reachable from the experiment.
  - Follows `parent-manifest` along the lineage chain. The transitive
    closure is the **live set**.
  - Per the Dhall-declared `retain` policy (`Retention.LastN k` keeps the
    `k` most-recent manifests on the `latest` chain by `step`;
    `pointers/best/<m>` target manifests are always live),
    schedules the reapable manifests and blobs.
  - A blob is reapable iff no live manifest references it.
  - Emits a structured `gc_reaped` event per doctrine `At-Least-Once Event
    Processing`, naming every reaped manifest and blob SHA.
  - On a steady-state experiment the reconciler exits `3` (`AppError
    ReconcilerNoop`).

### Validation

1. `jitml internal gc <experiment-hash>` after a fresh training run is a
   no-op (exit `3`).
2. After producing `k+1` manifests under `Retention.LastN k`, GC reaps the
   oldest manifest and any blobs referenced only by it.
3. A `pointers/best/<metric>` target manifest is preserved regardless of
   `LastN`.
4. `gc_reaped` events are emitted on `training.event.<mode>` with the
   reaped SHAs.

## Sprint 10.4: Inference-Only Read Path ✅

**Status**: Done
**Implementation**: `src/JitML/Checkpoint/Format.hs`,
`src/JitML/App.hs`
**Docs to update**: `documents/engineering/checkpoint_format.md`,
`documents/engineering/daemon_architecture.md`

### Objective

Land the inference-only read path consumed by both the `jitml-demo` HTTP
server (Phase `11`) and the PureScript panels. Inference reads `pointers/<>`,
fetches the manifest, fetches **only** the `Weights` part's blob (skipping
optimizer state, RNG state, replay buffer, exploration cache).

### Deliverables

- `loadInferenceCheckpoint :: PointerKey -> ReaderT Env IO
  (KernelHandle, Manifest)` reads `pointers/<>`, fetches `manifests/<sha>`,
  fetches the weights blobs, instantiates a `KernelHandle` (Sprint `7.1`)
  in `Inference` kind.
- Concurrent training advances are invisible to the reader because the
  snapshot the reader operates against is immutable per
  [../README.md → Concurrency model](../README.md#concurrency-model).
- `jitml inspect replay <manifest-sha>` (Plan/Apply) replays an inference
  path against the manifest, asserts the bit-determinism contract holds.
- `src/JitML/Service/Consumer.hs` provides the local at-least-once consumer
  surface for inference command summaries.

### Validation

1. `loadInferenceCheckpoint` against a freshly-trained MNIST model produces
   a `KernelHandle` that runs against the FFI loader.
2. The inference-only path skips optimizer-state, RNG-state, and buffer
   blobs (asserted by the GET-trace property test).
3. `jitml inspect replay` is bit-identical against the same-substrate
   reproduction of a trained snapshot.

## Doctrine Sections Cited

- [../HASKELL_CLI_TOOL.md → Plan / Apply](../HASKELL_CLI_TOOL.md) (Sprints 10.3, 10.4)
- [../HASKELL_CLI_TOOL.md → Capability Classes and Service Errors](../HASKELL_CLI_TOOL.md) (Sprint 10.2 — `HasMinIO` consumers)
- [../HASKELL_CLI_TOOL.md → Retry Policy as First-Class Values](../HASKELL_CLI_TOOL.md) (Sprint 10.2 — `casPointer` retry harness)
- [../HASKELL_CLI_TOOL.md → At-Least-Once Event Processing](../HASKELL_CLI_TOOL.md) (Sprints 10.3, 10.4 — `gc_reaped`, inference handler)
- [../HASKELL_CLI_TOOL.md → Reconcilers: Idempotent Mutation as a Single Command](../HASKELL_CLI_TOOL.md) (Sprint 10.3 — exit `3` on no-op)
- [../HASKELL_CLI_TOOL.md → Generated Artifacts](../HASKELL_CLI_TOOL.md) (Sprint 10.2 — generated `.jmw1` format reference table)

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/checkpoint_format.md` — full split-blob layout,
  `.jmw1` wire format, manifest CBOR schema, write protocols (`If-None-
  Match: *` for blobs/manifests, `If-Match: <etag>` for pointers), typed
  advance predicates, retention reconciler narrative, inference-only read
  path.
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
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
