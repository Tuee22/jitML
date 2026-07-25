# Phase 125: Inference-Only Read Path

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Inference-Only Read Path. Single-session phase migrated from legacy Sprint 10.4 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 125.1: Inference-Only Read Path [✅ Done]

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
  [phase-15-linux-cuda-and-cluster-closure.md](README.md#legacy-to-new-phase-map)
  Sprint `15.12`.
- Per-substrate production weight loading: Linux CPU oneDNN and Linux
  CUDA are owned by Phase `15` Sprint `15.11`; Apple Metal is owned by
  [phase-16-apple-silicon-closure.md](README.md#legacy-to-new-phase-map)
  Sprint `16.5`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
