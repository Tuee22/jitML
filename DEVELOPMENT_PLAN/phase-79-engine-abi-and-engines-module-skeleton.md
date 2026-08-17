# Phase 79: Engine ABI and `Engines` Module Skeleton

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Engine ABI and Engines Module Skeleton. Single-session phase migrated from legacy Sprint 7.2 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done** (closed 2026-08-14). `SubstrateProfile` and a total `profileFor` —
one equation per constructor, no wildcard — own every substrate-varying fact,
and `engineForSubstrate` / `deterministicFlags` are projections of it. The
`dlopen`/`dlsym` versus fixed-Metal-bridge difference is a `KernelLaunch` value
carried by the profile and by `MlpBackendSpec`, so all six `isMetalSpec`
escapes are gone and the artifact-fill branch is a total two-arm `case` rather
than a wildcard over `Substrate`. Two fail-open defects the duplication had been
hiding are closed with it: the Apple family driver now reports the family read
back out of the artifact rather than the one the host requested (its mismatch
guard had been comparing a value with itself and could never fire), and
the `linux-cpu` **family-kernel** entries probe their oneDNN runtime before
launching instead of going straight to `dlopen`.

The generic `runLinuxCpuKernel` / `runLinuxCpuWeightedKernel` drivers remain
unprobed, and are still reached unprobed by the two tuning-benchmark candidate
runners (whose CUDA and Metal siblings do have `…WithProbe` variants) and by
`jitml build`. Those paths fail closed rather than fail open — a missing
`-ldnnl` fails the compile, and a post-compile `dlopen` failure throws rather
than returning a wrong value — but the CPU-versus-accelerator asymmetry this
sprint set out to remove is only partly closed. Extending the probe to the
benchmark lane is recorded in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

## Sprint 79.1: Engine ABI and `Engines` Module Skeleton [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Substrate.hs`, `src/JitML/Engines/Engine.hs`,
`src/JitML/Engines/Loader.hs`, `src/JitML/Engines/LoadableKernel.hs`,
`src/JitML/Engines/{Local,CudaLocal,MetalLocal}.hs`,
`src/JitML/Numerics/MlpDevice.hs`, `src/JitML/Numerics/{MlpOneDnn,MlpCuda,MlpMetal}.hs`,
`src/JitML/Sub/Render.hs`, `src/JitML/Service/{ConfigMap,Workload}.hs`,
`src/JitML/Plan/Command.hs`, `src/JitML/Cluster/Publication.hs`,
`src/JitML/Bootstrap.hs`, `test/unit/Main.hs`
**Docs to update**: `documents/engineering/jit_codegen_architecture.md`

### Objective

Define the engine metadata shared by every substrate: backend
name, artifact extension, deterministic flags, typed kernel input/output
shapes, deterministic launch envelope, and renderable build plan.

### Deliverables

- `Engine` records `engineSubstrate`, `engineBackend`, and
  `engineArtifactExtension`.
- `engineForSubstrate` maps `apple-silicon` to `metal` / `.dylib`,
  `linux-cpu` to `onednn` / `.so`, and `linux-cuda` to `cuda` / `.so`.
- `deterministicFlags` records the current per-substrate determinism summary.
- `renderEnginePlan` renders the local engine metadata.
- `KernelInputs`, `KernelOutputs`, and `EngineEnvelope` record the local launch
  ABI and reproducibility witness surface.
- `renderEngineEnvelope` renders the envelope for deterministic inspection.
- Full production non-CPU `HasEngine` graph execution is validated by the
  Linux-CUDA and Apple-Silicon closure phases; the local Linux CPU oneDNN
  primitive execution path is implemented in `JitML.Engines.Local` and exposed through
  `JitML.Engines.HasEngine.LocalLinuxCpuEngine`.

### Validation

1. `cabal test jitml-cross-backend` verifies every substrate has
   deterministic flags.
2. `jitml-unit` validates local engine envelope rendering.

### Closure Evidence

Closed 2026-08-14 from one source state, inside `jitml:local`:

- `jitml lint haskell` → `ok`.
- `jitml docs check` → `ok`.
- `jitml test jitml-unit --linux-cpu` → **870 / 870 passed**, including the
  six-case "One substrate profile (Phase 79)" group.
- `jitml test jitml-backends --linux-cpu` → **36 / 36 passed**, over the shared
  `dlopen`/`dlsym` driver the three engines now use.
- `jitml check-code` → `ok`.

### Completed in this sprint

- `src/JitML/Substrate.hs`: `SubstrateProfile`, `KernelLaunch`, `ArtifactFill`,
  and a total `profileFor`. It lives here rather than in `Engine.hs` because
  `Engine` imports `Substrate`, so the leaf module must own the profile for the
  edge-port and runtime-class projections to read off it.
- `substrateHasClusterCompute` collapsed from five shapes across four modules
  to one profile projection; `substrateRuntimeClass`'s `_ -> Nothing` wildcard
  deleted.
- `src/JitML/Engines/Loader.hs`: the artifact-fill wildcard replaced by a total
  `case` on `ArtifactFill`, plus `executedArtifactIdentity` — the one identity
  read for both launch kinds.
- `src/JitML/Numerics/MlpDevice.hs`: `MlpBackendSpec` gains `mbsLaunch`, and all
  **six** `isMetalSpec` guards (the phase doc said five) became total two-arm
  dispatches on it. The sixth was the execution-witness identity read, which now
  asks the launcher what ran instead of inferring it from the substrate.
- `src/JitML/Engines/LoadableKernel.hs` (new): the shared `dlopen`/`dlsym` ABI —
  four FFI type aliases, four dynamic imports, and both driver helpers, which
  were byte-identical between the CPU and CUDA drivers apart from one comment
  word.
- `renderBool` folded from six copies into `JitML.Sub.Render`;
  `Local.runSupervisedGraphDeviceInference` (a line-for-line re-implementation
  of the Store function) and `MetalLocal.familyNameText` (a byte-identical copy
  of `KernelFamily.familyName`) deleted. The three drivers fell from 1,162 lines
  to 938, plus 106 shared.
- Both Sprint `79.1` rows in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) moved to
  `Completed`.

The `-Werror=incomplete-patterns` precondition this sprint's Remaining Work
named is already satisfied — Phase `7` closed it on 2026-08-13, and it is
enabled in all twelve `jitml.cabal` stanzas. The reason the old
`buildToolchainFingerprint` arm slipped through was the wildcard itself, not a
missing flag.

**Live-execution scope.** The `linux-cpu` arm is exercised by this sprint's
validation. The `linux-cuda` and `apple-silicon` arms are compiled and
type-checked here; their live execution is owned by Phases `268` and `272` on
their own hardware, as it already was.

### Historical Validation

Evidence for the surface this sprint actually exercised before the 2026-08-12 reopen:

> ✅ **Done**.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
