# Phase 179: Live `jitml inference run` and Legacy Replay Helper

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Live jitml inference run and Legacy Replay Helper. Single-session phase migrated from legacy Sprint 15.12 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 179.1: Live `jitml inference run` and Legacy Replay Helper [✅ Done]

**Status**: Done (re-validated 2026-06-06 on RTX 5090; previously Done on RTX 3090) (closed 2026-05-27)
**Blocked by**: Sprint `178.1`
**Implementation**: `src/JitML/App.hs`,
`src/JitML/Checkpoint/Store.hs`,
`src/JitML/Service/MinIOSubprocess.hs`
**Docs to update**: `documents/engineering/daemon_architecture.md`,
`documents/engineering/checkpoint_format.md`

### Objective

Extend the user-facing inference path from the current local-store path to the
live MinIO + JIT cache path: `jitml inference run` reads the latest pointer from
MinIO bucket
`jitml-checkpoints/<experiment-hash>/`, fetches the addressed manifest,
loads weight-only blobs, loads the substrate-bound `KernelHandle` from
the JIT cache, and runs real inference. The historical companion replay helper
fetched the named manifest from live MinIO; Sprint `1.16` later removed that
public `inspect` command surface.

### Deliverables

- `jitml inference run experiments/mnist.dhall`
  reads through live MinIO and produces an inference result through
  the loaded JIT kernel.
- The checkpoint manifest read path validates addressed manifests and reports
  real metadata; the old public replay CLI was retired by Sprint `1.16`.
- The Sprint `15.11` weighted runners execute the actual inference; the
  command exits non-zero with `AppError` on missing pointers or
  manifest SHA mismatches.

### Validation

1. End-to-end: `jitml inference run experiments/mnist.dhall` against the live
   cluster reads the latest pointer and outputs the expected deterministic
   inference summary.
2. Historical replay-helper validation against a manifest written by Sprint
   `15.4` succeeded; the public helper was later removed by Sprint `1.16`.

### Live Validation Note (2026-05-25)

```
    live jitml inference run reads checkpoint from live MinIO (Sprint 15.12):  OK (0.29s)
```

`cabal test jitml-integration --test-options='-p Live'` cohort on the
Sprint 15.1 cluster (edge port `127.0.0.1:9092`) — 8/8 pass in
`1.43s`. The new case (a) writes a manifest + blob + latest pointer
to live MinIO via `writeCheckpointSnapshotWithMinIO`, (b) spawns
`./.build/jitml inference run --experiment-hash <hash>` via the typed
`Subprocess` boundary and asserts the stdout contains
`inference: experiment=<hash>`. The same historical case also exercised the now
retired replay CLI before cleanup.

### Code Surface Landed (2026-05-25)

- `JitML.App.runInference` detects the live cluster publication
  (`./.build/runtime/cluster-publication.json`) and drives
  `JitML.Checkpoint.Store.loadInferenceCheckpointWithWeights` through
  `JitML.Service.MinIOSubprocess` against the leased edge port. The command
  reads the latest pointer from
  `jitml-checkpoints/<experiment-hash>/pointers/latest`, fetches the addressed
  manifest, decodes weight-only `.jmw1` blobs, and runs the selected substrate's
  weighted checkpoint runner. Without a live publication the command fails
  closed with `InferenceCheckpointMissing`.
- The historical `JitML.App.runInspectReplay` branch routed through MinIO when a
  publication was present, fetched
  `jitml-checkpoints/<experiment-hash>/manifests/<sha>.cbor` via
  `Capabilities.minioReadBytes`, decoded it via `Checkpoint.decodeManifestCbor`,
  and printed the replay summary. Sprint `1.16` removed that public branch.
- `JitML.Bootstrap.readExistingLivePublication` is exported from
  `JitML.Bootstrap` so the CLI commands (and any future tests) share
  one publication-detection surface.
- A new `Live` case
  `live jitml inference run reads checkpoint from live MinIO (Sprint
  15.12)` in `test/integration/Main.hs` (a) writes a manifest + blob +
  latest pointer to live MinIO via `writeCheckpointSnapshotWithMinIO`,
  (b) spawns `./.build/jitml inference run --experiment-hash
  <hash>` via the typed `Subprocess` boundary, asserting the output
  contains `inference: experiment=<hash>`. The original historical version also
  spawned the now-retired replay CLI before cleaning up the three written
  objects.

### Remaining Work

- **Live cluster validation deferred to the final pass.** The
  JIT-kernel path is now in place (see the 2026-05-26 landing below);
  end-to-end bit-determinism validation in the cluster is owned by
  the final live validation pass.
### Code Surface Landed (2026-05-26, typed inference AppError variants)

- `JitML.AppError.AppError` now carries
  `InferenceCheckpointMissing :: Text -> AppError` (exit code `1`)
  and `InferenceManifestShaMismatch :: Text -> Text -> AppError`
  (exit code `1`). The `JitML.AppError.Render.renderError` boundary
  surfaces both as single-line typed diagnostics
  (`inference checkpoint missing: <experiment-hash>` and
  `inference manifest sha mismatch: <experiment-hash>: requested
  <sha>`); the canonical render golden at
  `test/snapshots/cli/app-error-render.txt` is updated to include them.
- `JitML.App.runInference` now routes weighted checkpoint-load failures through
  `classifyCheckpointLoadError` which maps the
  underlying `pointer read failed` / `manifest read failed` cases to
  `InferenceCheckpointMissing experimentHash`. Decode failures retain
  `InvalidConfig` since they indicate format drift, not absence.
- The historical replay branch mapped "read failed" outcomes to
  `InferenceCheckpointMissing experimentHash` and added an explicit post-decode
  manifest-SHA check. Sprint `1.16` removed that public replay branch with the
  rest of the placeholder `inspect` group.
- `system-components.md → CLI Doctrine Components` enumerates the new
  variants in the canonical `AppError` row.
- `jitml-unit`'s "AppError render golden covers canonical variants"
  test consumes the extended `canonicalErrors` list with both new
  variants; 103/103 pass.

### Code Surface Landed (2026-05-26, JIT-kernel-backed inference path)

- `JitML.App.runInference` (and the new helper
  `inferenceForSubstrate`) now route through
  `loadInferenceCheckpointWithWeights` with the substrate-bound
  weighted runner:
  - `LinuxCPU` → `runLinuxCpuWeightedCheckpointInference`
  - `LinuxCUDA` → `runCudaWeightedCheckpointInference`
  - `AppleSilicon` → `runMetalWeightedCheckpointInference`
- The historical replay helper had already been routed through the live MinIO
  path in the prior session; Sprint `1.16` later removed the public command.

### Live Validation Note (2026-05-27)

On the same RTX 3090 host as the 2026-05-26 cluster bring-up, with a
freshly rebuilt `jitml:local` image (Sprint 15.12 JIT-kernel-backed
inference path baked into `/usr/local/bin/jitml` via the binary mount
override during testing), the Sprint 15.12 Live case ran
end-to-end:

```
    live jitml inference run reads checkpoint from live MinIO (Sprint 15.12): OK (0.54s)
```

The test now exercises the real JIT-kernel-backed CUDA path:
`./.build/jitml inference run --experiment-hash <hash>` spawns the
binary, `runInference` detects the live publication, routes through
`loadInferenceCheckpointWithWeights` with `runCudaWeightedCheckpointInference`,
nvcc compiles the weighted `kernel.cu` (with `-L/usr/local/cuda/lib64/stubs`
and without the now-corrected `--use_fast_math=false` arg), dlopen
loads the `.so`, `jitml_weighted_kernel` runs on the RTX 3090, and the
real device-computed result is returned. The pre-existing
`--use_fast_math=false` nvcc syntax was exposed by this live wiring and
corrected (default behaviour is fast-math-off, matching the
[determinism contract](../documents/engineering/determinism_contract.md)).
The historical replay-helper half was exercised by its earlier Live case
against a Sprint 15.4-written manifest; Sprint `1.16` later removed the public
command.

### Remaining Work

- None remaining for Sprint 13.12. Sprint closed 2026-05-27.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
