# JIT Codegen Architecture

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: README.md, ../documentation_standards.md, ../../DEVELOPMENT_PLAN/phase-0-planning-documentation.md, ../../DEVELOPMENT_PLAN/phase-2-bootstrap-reconciler-and-jit-cache.md, ../../DEVELOPMENT_PLAN/phase-7-jit-codegen-and-substrates.md, determinism_contract.md, numerical_core.md
**Generated sections**: none

> **Purpose**: Project-specific JIT codegen architecture for jitML — the
> content-addressed cache, the per-substrate compilers (Metal, oneDNN,
> CUDA), the current typed engine handle/envelope surface, the target FFI
> boundary, the Apple Silicon hybrid pattern with lazy tart spin-up, and the
> hardware auto-tuning surface.

## Cache Layout

```
.build/
├── jitml                                    -- the binary
├── jitml.kubeconfig                         -- repo-local kubeconfig
├── conf/                                    -- generated host and cluster Dhall
├── runtime/cluster-publication.json          -- routed cluster coordinates
├── kind/<substrate>/                         -- Kind metadata/config for later compose-run commands
├── host/apple-silicon/                      -- Apple-only stable-named dlopen() targets
└── jit/
    ├── manifest.json                        -- index keyed on (model-id, kind, substrate, toolchain)
    └── <substrate>/<hash>.<ext>             -- one file per cached kernel
```

Generated compiler inputs live alongside the cache under:

```
.build/jit-src/<substrate>/<hash>/
```

`src/JitML/Codegen/RuntimeSource.hs` owns the generated-source ADT and
materialization discipline. `src/JitML/Codegen/{Cuda,OneDnn,Metal}.hs` render the
per-substrate source bundles. The repository does not keep checked-in
substrate-source directories for generated compiler inputs.

`./.build/` is the host root for compiled artefacts, generated Dhall,
kubeconfig, cluster publication, Kind metadata, and JIT-compiled kernels.
`./.data/` is strictly for manual PV bind mounts. Both `./.build/` and
`./.data/` are in `.gitignore` and `.dockerignore`.

The Sprint `2.3` cache support lives in `src/JitML/Cache/`: `Key` owns the
placeholder cache-key ADTs and SHA-256 derivation, `Layout` owns typed path
resolution under `./.build/`, `Manifest` owns `manifest.json` round-trip and
atomic writes, and `Symlink` owns atomic Apple stable-FFI symlink repointing.
Sprint `7.1` replaces the placeholder `KernelSpec` payload with the numerical
core's full kernel shape.

`jit/<substrate>/<hash>.<ext>` is the canonical content-addressed cache —
every cached kernel lives there, on every substrate.

`host/apple-silicon/` is *only* on Apple, and holds **stable-named symlinks**
into `jit/apple-silicon/`. The Haskell FFI `dlopen`s
`host/apple-silicon/<model-id>.dylib`, which resolves through the symlink to
`jit/apple-silicon/<hash>.dylib`. The indirection lets the FFI path stay
stable across re-JITs (a new hash repoints the symlink; the FFI key never
changes).

Linux substrates don't need this — the pod loads directly out of
`jit/<substrate>/` because there is no host↔VM artifact-copy step.

The first executable path is local `linux-cpu`. `JitML.Engines.Local`
materializes the generated identity kernel, compiles it with `g++`, loads the
shared object through `dlopen`, resolves `jitml_kernel`, and validates
deterministic fixture output through the Haskell FFI. Production oneDNN graph
kernels, Apple Metal loading, and Linux CUDA loading extend the same cache and
kernel-handle contracts later.

## Cache Key

```
sha256(canonical-cbor(KernelSpec) || kind || substrate || toolchain-fingerprint || rendered-source-payload || tuning-choice)
```

where:

- `KernelSpec` is model shape (layer topology, dtype layouts, activation
  choices) plus the optimizer + loss when `kind = Training`.
- `kind ∈ Training | Inference`.
- `substrate ∈ apple-silicon | linux-cpu | linux-cuda`.
- `toolchain-fingerprint` is the hash of every codegen-toolchain pin from
  `cabal.project` (LLVM, NVCC, Xcode/Metal, oneDNN).
- `rendered-source-payload` is the canonical payload emitted by
  `renderRuntimeSource`.
- `tuning-choice` is the selected `TuningChoice`.

Training and inference kernels are **separate artifacts** because they have
different compute graphs — training carries the backward pass and optimizer-
step kernel; inference is forward-only with frozen-weight constant folding
enabled. Sharing one artifact across both would force one of them to be
sub-optimal.

## Engine ABI

The current checked-in ABI surface lives in `src/JitML/Engines/Engine.hs`.
It provides:

- `KernelHandle`, naming the engine, content hash, and cache artifact path.
- `JitCacheStatus`, distinguishing `JitCacheHit` from `JitCacheMiss` with the
  typed compile `Subprocess` needed to fill the cache.
- `KernelInputs` / `KernelOutputs`, recording local launch shape and byte
  counts.
- `EngineEnvelope`, carrying the handle, input/output metadata, per-substrate
  determinism witnesses, and compile command text.

`src/JitML/Engines/Local.hs` is the narrow local execution interpreter for the
Linux CPU identity fixture. The target live daemon grows the general surface
into a `HasEngine` capability with real graph-kernel launch and parameter-commit
effects. `EngineEnvelope` is already the local reproducibility witness surface;
see [determinism_contract.md → Engine Envelope](determinism_contract.md#engine-envelope).

## Per-Substrate Codegen Drivers

### `linux-cpu` — oneDNN

- `src/JitML/Codegen/OneDnn.hs` renders the generated C++ compiler input under
  `./.build/jit-src/linux-cpu/<hash>/`.
- The build plan invokes the oneDNN C++ compiler path through the typed
  `Subprocess` boundary against the generated directory; the produced `.so` is
  written atomically to `./.build/jit/linux-cpu/<hash>.so`.
- `src/JitML/Engines/Local.hs` currently compiles the generated identity source,
  `dlopen`s the produced `.so`, resolves `jitml_kernel`, and executes a local
  fixture through the Haskell FFI.
- AVX2 is the baseline; AVX-512 is detected at JIT time.
- Block size for reductions is pinned per layer family so reductions are
  host-independent. The block size is part of `ToolchainFingerprint`.
- The current local engine envelope names the `.so` artifact path and compile
  command. A production `LinuxCPU.HasEngine` instance for real oneDNN graph
  kernels remains target runtime work.

### `linux-cuda` — CUDA + cuBLAS / cuDNN

- `src/JitML/Codegen/Cuda.hs` renders the generated CUDA compiler input under
  `./.build/jit-src/linux-cuda/<hash>/`.
- NVCC is invoked through the typed `Subprocess` boundary against the generated
  directory with the doctrine-pinned `--use_fast_math=false` and baseline
  `sm_70`.
- The produced `.so` is written atomically to
  `./.build/jit/linux-cuda/<hash>.so`.
- cuBLAS / cuDNN are pinned to deterministic algorithm selections via
  `cudnnSetConvolutionMathType` plus explicit algorithm-id pinning.
- The current local engine envelope names the `.so` artifact path and compile
  command. A `LinuxCUDA.HasEngine` instance that loads the `.so` via the FFI
  loader remains target runtime work.

### `apple-silicon` — Swift + Metal

- `src/JitML/Codegen/Metal.hs` renders the generated Swift package and Metal
  kernel input under `./.build/jit-src/apple-silicon/<hash>/`.
- The build plan runs `swift build` inside the `jitml-build` tart VM via
  `tart ssh`, against the generated package directory.
- The produced `.dylib` is copied atomically to
  `./.build/jit/apple-silicon/<hash>.dylib` and the stable-FFI symlink at
  `./.build/host/apple-silicon/<model-id>.dylib` is repointed.
- The current local engine envelope names the `.dylib` artifact path and Tart
  `swift build` command. An `AppleSilicon.HasEngine` instance that loads the
  `.dylib` via the FFI loader remains target runtime work.
- Metal kernels launch in a single `MTLCommandQueue` with FIFO ordering;
  explicit barriers prevent kernel reordering.

## Apple Silicon Hybrid Pattern

Bootstrap and the host daemon's startup path never touch tart. On a JIT cache
miss, the host daemon first validates or installs the `tart` Homebrew package
through typed lazy prerequisite remediation, then calls
`JitML.Tart.ensureVmUp jitml-build`:

- If the VM is up, no-op.
- If down, `tart run jitml-build --no-graphics &` and poll until reachable.

The daemon then dispatches the Swift build inside the VM via `tart ssh`,
writes the artifact into `./.build/jit/apple-silicon/<hash>.dylib`
atomically (`tmp + rename`), repoints the stable-named symlink under
`./.build/host/apple-silicon/`, and loads via FFI.

The VM stays up for the daemon's lifetime once spun up; an idle timeout
(default `30 min`, configurable in `LiveConfig.tartIdleTimeout`) brings it
down again. Subsequent cache hits skip the spin-up entirely.

Manual VM access is available via `jitml internal vm exec -- <cmd>` (Apple
only; rejected on Linux substrates with `AppError UnknownCommand`).

## Cache Survives VM Teardown

`./bootstrap/apple-silicon.sh purge` destroys the tart VM (along with the
Swift incremental build cache *inside* the VM) but **preserves** `./.build/`.
After `purge`, every previously compiled kernel is still on disk under
`./.build/jit/apple-silicon/`, so the next bootstrap plus any inference command
can resolve from cache without spinning tart up at all.

`purge --full` is `purge` plus `rm -rf ./.build/` (and on Linux,
`docker compose down --rmi local --volumes` to drop the substrate image).
Use only for fresh-start debugging.

## Linux Substrates Share the Cache via Kind `extraMounts`

The Kind cluster config bind-mounts host `./.build/` into the worker node,
and the `jitml-service` Deployment mounts that path into the pod at
`/opt/build`. Cache hits / misses behave identically to Apple Silicon — the
only difference is that on a Linux miss the compile runs in-process inside
the pod (the substrate image carries the full JIT toolchain), not in a
separate VM. Later `docker compose run --rm jitml jitml <command>` invocations
reuse the Kind metadata under `./.build/`; the outer container exits after the
cluster daemon is in charge. This is the **one** exception to the "no
freestanding host paths in pod specs" discipline; the chart lint permits
exactly this hostPath and rejects any other.

## Hardware Auto-Tuning

`TuningChoice` enumerates per-substrate knob spaces (Metal: workgroup size,
threadgroup memory; oneDNN: block size variants under the fixed block-
reduction discipline; CUDA: tile size, warp-shuffle pattern, cuDNN algorithm
id from the deterministic-only set).

`AutoTune` runs at JIT time on a cache miss, picks a `TuningChoice` per
`KernelSpec` based on a per-substrate strategy (latency-vs-throughput
trade-off, with a default that prioritises bit-determinism). The chosen
`TuningChoice` is a cache-key input; a knob change invalidates the cache key.

The cuDNN algorithm-id selection is restricted to the deterministic-only
set. The `--use_fast_math=false` invariant is preserved.

## FFI Boundary

The current worktree has typed cache decisions and `KernelHandle` construction
in `src/JitML/Engines/Engine.hs`, plus a local Linux CPU identity `dlopen`
runner in `src/JitML/Engines/Local.hs`. Target `src/JitML/FFI/Loader.hs`
exposes
`loadKernel :: HasJitCache env => ModelId -> Kind -> Substrate -> IO (Either
AppError KernelHandle)`:

- On cache hit, `dlopen`s the cached artefact and returns a typed
  `KernelHandle`.
- On cache miss, returns `AppError JitCacheMiss` — caught by the substrate-
  specific compile path which produces the artefact and retries.

Apple Silicon FFI loader uses `dlopen` against the stable-named symlink;
Linux loaders use `dlopen` directly against the cache file.

## Cross-References

- [../../README.md → Built-artifact and JIT-cache discipline](../../README.md#built-artifact-and-jit-cache-discipline)
- [../../README.md → JIT compilation architecture](../../README.md#jit-compilation-architecture)
- [determinism_contract.md](determinism_contract.md)
- [daemon_architecture.md](daemon_architecture.md)
- [../../DEVELOPMENT_PLAN/phase-2-bootstrap-reconciler-and-jit-cache.md](../../DEVELOPMENT_PLAN/phase-2-bootstrap-reconciler-and-jit-cache.md)
- [../../DEVELOPMENT_PLAN/phase-7-jit-codegen-and-substrates.md](../../DEVELOPMENT_PLAN/phase-7-jit-codegen-and-substrates.md)
