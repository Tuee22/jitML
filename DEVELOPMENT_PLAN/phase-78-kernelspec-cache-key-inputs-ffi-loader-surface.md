# Phase 78: `KernelSpec`, Cache Key Inputs, FFI Loader Surface

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: KernelSpec, Cache Key Inputs, FFI Loader Surface. Single-session phase migrated from legacy Sprint 7.1 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done** (re-closed 2026-08-17). Every toolchain fingerprint input is derived
from the surface it describes, including the last one that was not. The
`linux-cuda` determinism facts are read off the compile arguments themselves:
`Engine.engineCompileFlagSpecs` tags each argument with the role it plays, so
`engineCompileFlags` — what nvcc is given — and `Engine.compileLineDeterminism` —
what the cache key advertises about that invocation — are two projections of one
list, and the `fast-math=absent` entry is derived from the absence of a fast-math
argument in it rather than restating `--use_fast_math=false`, which no compile
line passes. `cudnn-explicit-algorithm-id` and `warp-shuffle-deterministic` were
substrate-wide claims about two specific kernels, so the trainer MLP artifact
keyed on both while reducing per thread with neither; they are gone, because a
kernel body already reaches the cache key through the rendered-source payload.
The one library-level choice that must also be keyed —  the layer-training
artifact's pinned cuBLAS math mode and three deterministic cuDNN convolution
algorithms — is `CudaLayerTraining.cudaLayerTrainingDeterminismChoices`, named
once, spliced into the generated source, and read from there by that artifact's
own fingerprint knobs.

Retained from the 2026-08-14 closure: every toolchain fingerprint is __derived__
from the surface it describes. `JitML.Engines.Fingerprint` renders one
`ToolchainFacts` record per artifact: the compiler, its hash-free compile flags,
and its link line come from `Engine.engineCompiler` / `engineCompileFlags` /
`engineLinkFlags` — the same lists `compileSubprocess` passes; the determinism
knobs from `deterministicFlags`; the ABI from a typed `AbiKind` that carries
`metalBridgeAbiVersion`, so the token cannot be hardcoded at one site and
interpolated at another; the numeric knobs from the renderers' own constants;
and the emitter set from the vocabulary the artifact covers.
`buildToolchainFingerprint` is total over `Substrate` with no shared literal and
equals the per-substrate family fingerprint, so `jitml build` can no longer
install at a different cache key than the one the benchmark candidate runners
measure at.

## Sprint 78.1: `KernelSpec`, Cache Key Inputs, FFI Loader Surface [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Engines/Fingerprint.hs`,
`src/JitML/Engines/Engine.hs`, `src/JitML/Cache/Key.hs`, `src/JitML/Substrate.hs`,
`src/JitML/Codegen/{OneDnn,Cuda,MlpCuda,CudaLayerTraining}.hs`, `src/JitML/Engines/{Local,CudaLocal,MetalLocal,TuningBenchmark,TuningCache}.hs`,
`src/JitML/Numerics/{MlpOneDnn,MlpCuda,MlpMetal,LayerGraphOneDnn}.hs`,
`src/JitML/App.hs`, `test/unit/Main.hs`
**Docs to update**: `documents/engineering/jit_codegen_architecture.md`,
`documents/engineering/determinism_contract.md`

### Objective

Populate the local cache-key input surface and kernel-handle/cache-decision
surface, and lock the cache key derivation over `KernelSpec`, `Kind`,
`Substrate`, `ToolchainFingerprint`, `RuntimeSourcePayload`, and
`TuningChoice`. Downstream runtime phases consume the generic FFI loading
surface; the local Linux CPU identity runner is owned by Sprint `7.3`.

### Deliverables

- `KernelSpec` is the cache-key payload wrapper.
- `Kind` distinguishes `Training` from `Inference`.
- `ToolchainFingerprint`, `RuntimeSourcePayload`, and `TuningChoice` are typed
  cache-key inputs.
- `cacheKey` hashes the serialized kernel spec, kind, substrate, fingerprint,
  rendered-source payload, and tuning choice into a SHA-256 digest.
- `KernelHandle` names the engine, content hash, and canonical artifact path.
- `resolveKernelCache` returns a typed `JitCacheHit` or `JitCacheMiss` with the
  compile `Subprocess` needed to fill the cache.
- `JitML.Engines.Loader.ensureKernelArtifact` is the generic cache-hit/cache-miss
  artifact boundary: it materializes generated source, detects existing cache
  artifacts, runs the typed compile `Subprocess` on misses, and returns a
  `KernelArtifact` with the chosen `KernelHandle`.
- `JitML.Engines.Loader.withKernelSymbol` owns the reusable `dlopen`/`dlsym`
  helper used by the local Linux CPU FFI fixture.
- The production `HasEngine` graph-launch capability is consumed and
  validated by the later runtime and per-lane closure phases.
- `JitML.Engines.Fingerprint` is the single owner of every toolchain
  fingerprint. `ToolchainFacts` names the compiler, compile flags, link flags,
  determinism knobs, renderer knobs, ABI, entry points, and emitter set; each is
  read off the surface it describes rather than restated beside it.
- `Engine.engineCompiler`, `engineCompileFlags`, `engineLinkFlags`, and
  `engineSourceFileName` are the hash-free halves of `compileSubprocess`, which
  is rewritten in terms of them. The rendered compile command is unchanged.
- `AbiKind` is typed, with `FixedMetalBridge` carrying `metalBridgeAbiVersion`,
  so the bridge token cannot be written as a literal at a call site.
- `buildToolchainFingerprint` is total over `Substrate` — three explicit arms,
  no wildcard — and equals `engineFamilyToolchainFingerprint` for that
  substrate.
- `JitML.Substrate` owns the one `Substrate` type, its `Serialise` instance, and
  its JSON codec; `JitML.Cache.Key` re-exports it and defines
  `substrateText = renderSubstrate`. The duplicate ADT and the
  `TuningCache.cacheSubstrateFor` bridge are deleted.
- `JitML.Codegen.OneDnn.oneDnnFixedReductionBlock` is the one reduction-block
  constant: the renderer emits it into the generated source and the fingerprint
  reads it.
- `Engine.engineCompileFlagSpecs` is the one compile-argument list, each argument
  tagged `BuildFlag` or `DeterminismFlag`. `engineCompileFlags` and
  `Engine.compileLineDeterminism` are projections of it, so the arguments the
  compiler is given and the determinism facts the cache key advertises cannot
  drift apart, and the `fast-math=absent` fact is derived from that list rather
  than naming a flag no compile line passes.
- `JitML.Substrate.profileDeterminism` holds only the runtime determinism
  properties no compile line establishes. Kernel-body properties are not stated
  there: a body reaches the cache key through the rendered-source payload.
- `JitML.Codegen.CudaLayerTraining.cudaLayerTrainingDeterminismChoices` is the
  one place the CUDA layer-training artifact's pinned cuBLAS math mode and its
  three deterministic cuDNN convolution algorithms are written; the generated
  `kernel.cu` splices them and `layerTrainingKnobs` reads them.
- The generated CUDA `// determinism:` comments state what their own bodies
  establish. They no longer restate `--use_fast_math=false`.

### Validation

1. `jitml-unit` verifies the cache-key snapshot under `test/snapshots/cache/`
   (pure-renderer output; see [../README.md → Snapshot
   targets](../README.md#snapshot-targets)).
2. `jitml-unit` verifies changing the rendered runtime-source payload changes
   the cache key.
3. `jitml-unit` verifies the typed cache-hit/cache-miss decision surface.
4. `jitml test jitml-unit --linux-cpu` passes, including the nine-case
   "Derived toolchain fingerprints (Phase 78)" group.
5. `jitml docs check` reports `ok`.
6. `jitml check-code` exits `0` inside `jitml:local`.

### Remaining Work

- None.

### Closure Evidence

Re-closed 2026-08-17 from one source state, inside `jitml:local`:

- `jitml lint haskell` → `ok`.
- `jitml docs check` → `ok`.
- `jitml test jitml-unit --linux-cpu` → **896 / 896 passed**, including the
  fourteen-case "Derived toolchain fingerprints (Phase 78)" group. Four cases
  are new and each fails on the reopened defect: *no advertised determinism
  argument is absent from the compile line* rejects any fact shaped like a
  compiler argument that `engineCompileFlags` does not contain; *every
  determinism-roled compile argument is advertised* closes the other direction;
  *the fast-math fact is read off the compile line* pins the derivation to the
  argument list; and *no CUDA determinism fact describes a kernel the artifact
  does not run* pins the removal of the cuDNN and warp-shuffle claims against
  the rendered MLP source. A fifth, *the CUDA layer-training knobs are the
  choices its source makes*, holds the layer-training knobs to the tokens the
  generated `kernel.cu` splices.
- `jitml check-code` → `ok`.

Every `linux-cuda` and `linux-cpu` JIT cache key changes with this landing, by
design: the determinism facts are inputs to `buildToolchainFingerprint`, so the
first run on each Linux lane recompiles its kernels once. No compiled artifact's
bytes change on `linux-cpu` — the rendered `kernel.cc` text is untouched — so the
`linux-cpu` lane fragment's `DeviceEvidence` digests, which pin the bytes that
ran rather than the address they were cached at, are unmoved. The two generated
CUDA sources do change, so the `linux-cuda` MLP and family artifact digests move;
that lane's fragment is reissued by Sprint `268.1`.

### Historical Closure Evidence

Closed 2026-08-14 from one source state, inside `jitml:local`:

- `jitml lint haskell` → `ok`.
- `jitml docs check` → `ok`.
- `jitml test jitml-unit --linux-cpu` → **864 / 864 passed**, including the
  nine-case "Derived toolchain fingerprints (Phase 78)" group. The cache-key
  snapshot under `test/snapshots/cache/` is unmoved: it keys on a synthetic
  fingerprint, and the substrate rendering is unchanged.
- `jitml check-code` → `ok`.

### Completed in this sprint

- `src/JitML/Engines/Fingerprint.hs` (new): `ToolchainFacts`, `AbiKind`,
  `toolchainFingerprint`, and the four derived fingerprints
  (`buildToolchainFingerprint`, `engineFamilyToolchainFingerprint`,
  `mlpToolchainFingerprint`, `layerTrainingToolchainFingerprint`). All eight
  hand-written fingerprints are deleted.
- `src/JitML/Engines/Engine.hs`: the compile facts split out of
  `compileSubprocess`, which is rewritten in terms of them, byte-identically.
- Two ABI misstatements corrected, both found by the new standing test that
  every named entry point must appear in the source its lane renders:
  - the Apple MLP fingerprint claimed `abi=cdecl-host-buffers` plus five
    `extern "C"` prototypes for an artifact that exports no C symbols at all,
    and one of those names (`jitml_mlp_forward`) is defined in no rendered
    source. It now names the ten MSL kernels the artifact defines.
  - the Apple *family* fingerprint named `jitml_kernel_family_name` and
    `jitml_kernel_output_count`, which on Apple are `.metal.json` metadata
    fields rather than callable kernels. It now names the two MSL kernels.
- `src/JitML/Substrate.hs` / `src/JitML/Cache/Key.hs` /
  `src/JitML/Engines/TuningCache.hs`: the duplicate `Substrate` ADT, its
  parallel renderer, its parallel JSON codec, and the `cacheSubstrateFor` bridge
  are deleted; one closed set now has one renderer.
- Both Sprint `78.1` rows in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) moved to
  `Completed`.

Every JIT cache key changes with this landing, by design: the first run on each
substrate recompiles its kernels once.

### Historical Validation

Evidence for the surface this sprint actually exercised before the 2026-08-12 reopen:

> ✅ **Done**.

## Documentation Requirements

**Engineering docs to create/update:**

- `../documents/engineering/jit_codegen_architecture.md` — the derived
  `toolchain-fingerprint` cache-key input and the `reduction-block` derivation.
- `../documents/engineering/determinism_contract.md` — the same, plus the
  Apple fingerprint's MSL entry points.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
