# Phase 78: `KernelSpec`, Cache Key Inputs, FFI Loader Surface

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: KernelSpec, Cache Key Inputs, FFI Loader Surface. Single-session phase migrated from legacy Sprint 7.1 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done** (re-closed 2026-08-19). A compiled artifact's bytes are a function of
its cache-key inputs on every substrate. The 2026-08-17 closure held one
direction — every fingerprint input is derived from the surface it describes —
and this closes the converse: an input that reaches the **artifact** without
reaching the **cache key**.

`nvcc` was injecting two such inputs. It embedded its own process id through its
`tmpxft_<pid>_…` intermediate file names, and `cudafe` mangled the CUDA
layer-training kernel's anonymous namespace as `_GLOBAL__N__<random>`; three
full-lane runs on identical source had produced three different artifact digests
(`d84ca76fda631347`, `a4964bef7e7ceb32`, `ef912228254d6960` for the layer-graph
artifact). Both are pinned — intermediates are directed at a caller-chosen
scratch directory whose path is not itself embedded, and file-scope helpers are
rendered `static` — and the pins are declared per substrate in
`JitML.Substrate.profileFor` as a closed `PinnedNonDeterminism` set with no
unpinned constructor. `g++` was measured already reproducible, so `linux-cpu`
carries the empty set as a positive claim rather than an omission.

A type cannot prove that set is complete, so a double-compile gate discharges it
on **every** lane, including the two whose set is empty: each compiles one
rendered source twice at two distinct cache addresses — two source directories,
two staging paths, two scratch directories — and asserts the artifacts are
byte-identical. Both lanes pass. The contract is stated in
[determinism_contract.md → Artifact Reproducibility](../documents/engineering/determinism_contract.md#artifact-reproducibility).

This is what makes a `DeviceEvidence` cell's `Text.take 16` of an artifact's
SHA-256 an identity rather than a per-compile nonce, so the committed
`linux-cuda` lane fragment is satisfiable and
[Phase 266](phase-266-cuda-integration-e2e-and-attestation.md) is the next
executable owner. Two further defects the same audit surfaced are closed with
it: publication is now atomic on every substrate (a fill stages to a
per-invocation path and is renamed into the content-addressed slot, so a killed
compile cannot leave a truncated artifact that the next run reports as a hit),
and a toolchain sidecar beside each artifact makes a compiler upgrade a cache
miss instead of serving stale machine code at an unchanged address.

### Historical Phase State

> 🔄 **Active** (reopened 2026-08-19 under standards rule `C`) — the reopen this
closure discharges. `nvcc` output was not byte-reproducible, which made the
committed `linux-cuda` lane fragment unsatisfiable by construction and
fail-fast-blocked Phase `266` at `jitml-integration` `1 / 197`.

> ✅ **Done** (re-closed 2026-08-17). Every toolchain fingerprint input is derived
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
`src/JitML/Engines/{Loader,CudaRuntime}.hs`, `src/JitML/App.hs`,
`test/unit/Main.hs`, `test/backends/Main.hs`
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
- Every substrate's artifact bytes are a function of its cache-key inputs. The
  invariant is stated in
  [determinism_contract.md → Artifact Reproducibility](../documents/engineering/determinism_contract.md#artifact-reproducibility).
  `JitML.Substrate.profileFor` declares, per substrate, the closed set of
  non-determinism sources its producer has, each already paired with its pin;
  `PinnedNonDeterminism` has no unpinned constructor, so a known source cannot be
  carried without its remedy. An empty set — `linux-cpu`, `apple-silicon` — is a
  positive claim discharged by the gate, not an omission.
- `Engine.CompileArgument` splits a literal argument from one that carries a
  caller-supplied value, so `--keep-dir <scratch>` cannot be passed without its
  prefix and the invocation-scoped path never enters the cache key.
  `ReproducibilityFlag` is a distinct role from `DeterminismFlag`, because an
  argument that pins a compiler's embedded identifiers pins nothing numerical and
  the determinism contract must not claim otherwise.
- The converse direction of this sprint's own invariant is closed.
  `compileSubprocess` is a total fold over `engineCompileFlagSpecs`, so no
  argument reaches a compiler that the cache key never saw. The original closure
  tested only that no advertised fact lacked a real argument; both directions are
  now tested, which is what stops a third reopen.
- Artifacts publish atomically on every substrate. A fill stages to a
  per-invocation path and `Loader` renames into the content-addressed slot, so a
  killed compile cannot leave a truncated artifact that the next run reports as a
  cache hit. This replaces the fixed `.tmp` suffix the Apple arm used, which was
  shared by every concurrent writer of one artifact.
- A cache hit produced by a different toolchain is rejected. A sidecar beside each
  artifact records the compiler version that produced it; a mismatch is a miss.
  This is a cache-*validity* rule, not a cache-*key* change — the published
  six-tuple is untouched.

### Validation

1. `jitml-unit` verifies the cache-key snapshot under `test/snapshots/cache/`
   (pure-renderer output; see [../README.md → Snapshot
   targets](../README.md#snapshot-targets)).
2. `jitml-unit` verifies changing the rendered runtime-source payload changes
   the cache key.
3. `jitml-unit` verifies the typed cache-hit/cache-miss decision surface.
4. `jitml test jitml-unit --linux-cpu` passes, including the eighteen-case
   "Derived toolchain fingerprints (Phase 78)" group.
5. `jitml test jitml-backends --linux-cpu` and
   `jitml test jitml-backends --linux-cuda` each compile one rendered source
   twice, at two distinct cache addresses, and assert the two artifacts are
   byte-identical. Nothing is compared against a stored digest — per
   [unit_testing_policy.md → Snapshot Tests](../documents/engineering/unit_testing_policy.md#snapshot-tests-and-the-prohibition-on-numerical-fixtures),
   run-to-run equality is asserted between two fresh runs. The two lanes are
   separate single-accelerator gates, never one must-pass-together gate
   (standards rule `M(b)`).
6. `jitml docs check` reports `ok`.
7. `jitml check-code` exits `0` inside `jitml:local`.

### Closure Evidence

Re-closed 2026-08-19 from one source state, inside `jitml:local`:

- `jitml lint haskell` → `ok`.
- `jitml docs check` → `ok`.
- `jitml test jitml-unit --linux-cpu` → **900 / 900 passed**, including the
  three new cases that hold this landing: *every argument the compiler receives
  is one the cache key saw* (the mirror image of the defect that reopened this
  phase — an argument added straight into `compileSubprocess` would reach the
  compiler while the fingerprint stayed blind to it); *each substrate pins every
  non-determinism source its producer has*; and *every rendered native source
  uses its substrate's linkage style*, which fails if a CUDA renderer
  reintroduces an anonymous namespace or the `linux-cpu` renderer loses the one
  its attested bytes were produced with.
- `jitml test jitml-backends --linux-cpu` → **37 / 37 passed**, including
  *linux-cpu layer-training artifact is byte-identical across two independent
  compiles (Phase 78)*.
- `jitml test jitml-backends --linux-cuda` → **28 / 28 passed** on the attached
  RTX 5090, including *linux-cuda layer-training artifact is byte-identical
  across two independent compiles (Phase 78)* — the gate that discharges the
  reopen.
- `jitml check-code` → `ok`.

Validation commands:

```bash
docker compose run --rm jitml-cuda jitml test jitml-backends --linux-cuda
docker compose run --rm jitml jitml test jitml-backends --linux-cpu
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

The `linux-cpu` arm is the tripwire: this lane's rendered text and artifact bytes
must not move, because Sprint `263.1` pins that artifact's SHA-256 in 45 of the
55 committed rows. Measured before and after the landing, the rendered
layer-training text is unchanged at
`42f20f9acfe24021a1298a299b09fa43c1344bc9deb837b54b45b7dcd163c407`.

The `linux-cuda` artifact digests do move with this landing, by design: the two
generated CUDA sources change (`static` file-scope helpers) and the
`reproducibility=` fact enters the toolchain fingerprint, so that lane's kernels
recompile once at a new address. That lane's fragment is issued by Sprint
`268.1`, which is what this sprint unblocks.

### Historical Closure Evidence

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

Added by the 2026-08-19 artifact-reproducibility landing:

- `src/JitML/Substrate.hs`: `PinnedNonDeterminism`, `ArtifactProducer`, and
  `InternalLinkageStyle`, with `profileFor` declaring each substrate's closed pin
  set and linkage style. There is no unpinned constructor, so a producer cannot
  carry a known non-determinism source without its remedy.
- `src/JitML/Engines/Engine.hs`: `CompileArgument` splits literal arguments from
  value-carrying ones so `--keep-dir <scratch>` cannot be passed without its
  prefix and the invocation-scoped path never enters the cache key;
  `ReproducibilityFlag` is a role distinct from `DeterminismFlag`;
  `compileSubprocess` became a total fold over `engineCompileFlagSpecs`.
- `src/JitML/Engines/Loader.hs`: `withStagedArtifact` is the one publish path for
  every substrate, and a toolchain sidecar makes a compiler upgrade a cache miss.
- `src/JitML/Codegen/CudaLayerTraining.hs`: file-scope helpers render `static`
  rather than in an anonymous namespace.
- `test/backends/Main.hs`: the per-lane double-compile gate.
- Six further Sprint `78.1` rows moved to `Completed`, including the
  `JitToolchainDrift` constructor — deleted rather than raised, because the
  delivered design makes toolchain drift a recoverable miss and leaves no
  unrecoverable state for an `AppError` to name.

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
