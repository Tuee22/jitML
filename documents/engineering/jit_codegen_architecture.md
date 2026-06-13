# JIT Codegen Architecture

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: README.md, ../documentation_standards.md, ../../DEVELOPMENT_PLAN/phase-0-planning-documentation.md, ../../DEVELOPMENT_PLAN/phase-2-bootstrap-reconciler-and-jit-cache.md, ../../DEVELOPMENT_PLAN/phase-7-jit-codegen-and-substrates.md, determinism_contract.md, numerical_core.md
**Generated sections**: none

> **Purpose**: Project-specific JIT codegen architecture for jitML — the
> content-addressed cache, the per-substrate compilers (Metal, oneDNN,
> CUDA), the typed engine handle/envelope surface, the FFI boundary, the
> Apple Silicon fixed-bridge Metal JIT (Haskell writes cached MSL source metadata,
> a fixed host bridge compiles that MSL through runtime
> `MTLDevice.makeLibrary(source:)`, and the host executes it on the Metal GPU),
> and the hardware auto-tuning surface.

## Cache Layout

```
.build/
├── jitml                                    -- the binary
├── jitml.kubeconfig                         -- repo-local kubeconfig
├── conf/                                    -- generated host and cluster Dhall
├── runtime/cluster-publication.json          -- routed cluster coordinates
├── kind/<substrate>/                         -- Kind metadata/config for later compose-run commands
├── host/apple-silicon/                      -- Apple-only fixed Metal bridge and host runtime metadata
├── jit-src/<substrate>/<hash>/               -- generated compiler inputs emitted by Haskell renderers
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

The generated-source rule applies to every source file that participates in a
JIT cache miss. Checked-in CUDA `.cu`, C/C++ `.cc` / `.cpp`, per-kernel MSL,
Swift package sources, native adapter shims, and per-substrate build scripts are
forbidden as JIT compiler inputs; Haskell renderers must emit them under
`./.build/jit-src/` or `./.build/jit/` instead. A fixed, non-kernel Apple Metal
bridge is allowed because it is process infrastructure, not model-specific JIT
source; `jitml internal install-metal-bridge` source-builds that bridge under
`./.build/host/apple-silicon/`.

`./.build/` is the host root for compiled artefacts, generated Dhall,
kubeconfig, cluster publication, Kind metadata, and JIT-compiled kernels.
`./.data/` is strictly for manual PV bind mounts. Both `./.build/` and
`./.data/` are in `.gitignore` and `.dockerignore`.

The Sprint `2.3` cache support lives in `src/JitML/Cache/`: `Key` owns the
typed cache-key ADTs and SHA-256 derivation, `Layout` owns typed path
resolution under `./.build/`, and `Manifest` owns `manifest.json` round-trip and
atomic writes. Sprint `7.11` removed the Apple stable-dylib symlink layer; Apple
cache entries are source metadata consumed by the fixed bridge. Sprint `7.1`
keeps `KernelSpec` as the current cache-key payload wrapper.
Future model-schema work grows that payload from local text fixtures into the
numerical core's full kernel shape.

`jit/<substrate>/<hash>.<ext>` is the canonical content-addressed cache —
every cached kernel lives there, on every substrate.

`host/apple-silicon/` is *only* on Apple, and holds the process-stable Metal
bridge dylib plus host-side runtime metadata. The Apple JIT cache entry is
`jit/apple-silicon/<hash>.metal.json`, not a per-kernel dylib. The Haskell side
loads/probes the fixed bridge and passes canonical MSL source plus launch
metadata to it on cache hits and misses.

Linux substrates load generated shared objects directly out of
`jit/<substrate>/`.

The first executable path is local `linux-cpu`. `JitML.Engines.Loader`
materializes generated libdnnl-linked oneDNN kernels and fills cache misses
with `g++ ... -ldnnl`; `JitML.Engines.Local` loads the shared objects through
`dlopen`, resolves `jitml_kernel` plus `jitml_kernel_family_name` plus
`jitml_kernel_output_count`, and validates deterministic fixture output,
loaded family metadata, and artifact-reported output length through the Haskell
FFI. `JitML.Engines.HasEngine` exposes that generated-family path through the
current local `HasEngine` interpreter, and `jitml service` uses
`runLinuxCpuCheckpointInference` for `linux-cpu` + `SelfInference` routed
checkpoint inference after MinIO manifest loading. `JitML.Engines.CudaLocal`
and `LocalCudaEngine` extend the same cache and kernel-handle contracts behind
a positive CUDA runtime probe. `JitML.Engines.MetalLocal` and
`JitML.Engines.MetalBridge` extend the Apple side with source-metadata cache
entries and fixed-bridge dispatch.

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
  `cabal.project` (LLVM, NVCC, the host OS Metal runtime plus fixed bridge ABI,
  oneDNN) plus loader-relevant ABI facts for local FFI paths.
- `rendered-source-payload` is the canonical payload emitted by
  `renderRuntimeSource`.
- `tuning-choice` is the selected `TuningChoice`.

The cache-key snapshot fixtures use the same rendered `RuntimeSourcePayload`
that runtime compilation consumes; there is no separate default placeholder
payload for tests. The cache key is a SHA-256 over the canonical rendered
source bundle — a pure text artefact — so the snapshot is deterministic by
construction and falls under [unit_testing_policy.md → Snapshot Tests](unit_testing_policy.md#snapshot-tests-and-the-prohibition-on-numerical-fixtures)
rather than the numerical-fixture prohibition.

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

`src/JitML/Engines/Loader.hs` is the shared artifact boundary. It materializes
generated runtime source, detects whether the content-addressed cache artifact
already exists, fills Linux cache misses through the typed compile `Subprocess`,
and fills Apple cache misses by atomically writing the rendered
`<hash>.metal.json` source metadata. It returns a `KernelArtifact` that records
the `KernelHandle`, cache status, compile command text or metadata-write plan,
and whether the cache artifact was created in this call. The same module owns
the reusable `dlopen`/`dlsym` helper used by local Linux FFI runners and fixed
bridge probing.

`src/JitML/Engines/Local.hs` is the local execution interpreter for the Linux
CPU oneDNN primitive kernels on top of that loader. It records the family name
reported by the loaded shared object's `jitml_kernel_family_name` symbol and
sizes the output buffer from the loaded `jitml_kernel_output_count` symbol.

`src/JitML/Engines/HasEngine.hs` defines the current engine capability:
`EngineRequest` carries the requested `KernelFamily` and input vector,
`EngineRun` carries the loaded `KernelHandle`, output vector, reported family,
compile command, and cache-miss flag, and `LocalLinuxCpuEngine` dispatches the
request through the generated-family Linux CPU FFI path. It rejects artifacts
whose exported family metadata does not match the requested family. The target
live daemon extends that capability with real graph-kernel launch and
parameter-commit effects. `EngineEnvelope` is already the local
reproducibility witness surface; see
[determinism_contract.md → Engine Envelope](determinism_contract.md#engine-envelope).

## Per-Substrate Codegen Drivers

### `linux-cpu` — oneDNN

- `src/JitML/Codegen/OneDnn.hs` renders the generated C++ compiler input under
  `./.build/jit-src/linux-cpu/<hash>/`.
- `docker/Dockerfile` installs `libdnnl-dev`. The build plan invokes the
  oneDNN C++ compiler path through the typed `Subprocess` boundary against the
  generated directory as `g++ ... -ldnnl`; the produced `.so` is written
  atomically to `./.build/jit/linux-cpu/<hash>.so`.
- `src/JitML/Engines/Local.hs` routes the generated identity source,
  reduction source, and all generated oneDNN family kernels through
  `JitML.Engines.Loader`, `dlopen`s the produced `.so`, resolves
  `jitml_kernel`, `jitml_kernel_family_name`, and
  `jitml_kernel_output_count`, and executes local oneDNN reorder, reduction,
  matmul, convolution, normalization, attention, and embedding primitives
  through the Haskell FFI while checking that the loaded artifact reports the
  expected family and output length. Its local toolchain fingerprint includes
  `artifact-abi=<os>-<arch>` and `reduction-block=256` so host-native Darwin
  builds, Linux container builds, and fixed reduction-block changes do not
  collide in the shared `.build/jit/linux-cpu/` cache.
- `src/JitML/Engines/HasEngine.hs` wraps the generated-family Linux CPU runner
  in the local `HasEngine` capability, preserving the family metadata check at
  the engine boundary.
- `src/JitML/Service/Runtime.hs` exposes
  `daemonWorkloadDispatcherWithInference`; the `jitml service` entrypoint
  selects the Linux CPU generated-kernel checkpoint runner for
  `linux-cpu` + `SelfInference` configs.
- `src/JitML/Engines/CpuFeatures.hs` detects AVX2 / AVX-512 through typed
  subprocess probes (`sysctl -a` on Darwin, `cat /proc/cpuinfo` on Linux) and
  maps the result to the `linuxCpuKnobs` `micro-kernel` axis.
- `src/JitML/Engines/OneDnnRuntime.hs` probes the production oneDNN link/runtime
  surface through typed subprocesses: `pkg-config --modversion dnnl`,
  `pkg-config --modversion onednn`, readable oneDNN headers under
  `/usr/include/oneapi/dnnl/dnnl.hpp` / `/usr/include/dnnl.hpp`, and
  `ldconfig -p`. The rendered probe reports the selected package/header path
  and whether `libdnnl` is visible to the dynamic linker.
- AVX2 is the baseline; AVX-512 is detected at JIT time.
- Block size for reductions is pinned per layer family so reductions are
  host-independent. The block size is part of `ToolchainFingerprint`.
- The local Linux CPU `ToolchainFingerprint` includes the host artifact ABI
  (`artifact-abi=<os>-<arch>`) and fixed reduction block
  (`reduction-block=256`) because the same repository `.build/` tree can be
  mounted by both the host and `jitml:local`, and reduction-block changes alter
  deterministic kernel semantics.
- The current local engine envelope names the `.so` artifact path and compile
  command. The local Linux CPU ABI includes
  `jitml_kernel(float*, const float*, size_t)` and
  `jitml_kernel_family_name(void)` plus
  `jitml_kernel_output_count(size_t)`. Current Linux CPU service loading routes
  checkpoint inference through this oneDNN-backed FFI path.

### `linux-cuda` — CUDA + cuBLAS / cuDNN

- `src/JitML/Codegen/Cuda.hs` renders the generated CUDA compiler input under
  `./.build/jit-src/linux-cuda/<hash>/`.
- NVCC is invoked through the typed `Subprocess` boundary against the generated
  directory with the doctrine-pinned `--use_fast_math=false` and baseline
  `sm_70`.
- The produced `.so` is written atomically to
  `./.build/jit/linux-cuda/<hash>.so`.
- The generated reduction kernel uses warp-shuffle reduction and writes one
  deterministic partial per warp; it does not use device-side `atomicAdd`.
  `src/JitML/Engines/CudaRuntime.hs` mirrors the generated block/warp geometry,
  computes the expected partial count, validates the partial vector length, and
  folds those partials in canonical index order.
- cuBLAS / cuDNN are pinned to deterministic algorithm selections via
  `cudnnSetConvolutionMathType` plus explicit algorithm-id pinning.
- `src/JitML/Engines/Rng.hs` implements the host SplitMix64 stream. Generated
  CUDA source records `host-splitmix64-no-curand`, so the no-curand RNG policy
  is part of the rendered source payload and cache key.
- `src/JitML/Engines/CudaRuntime.hs` also owns the typed CUDA runtime probe:
  it checks `nvcc --version`, `nvidia-smi -L`, and `ldconfig -p` through the
  typed subprocess boundary, parses the compiler version and visible GPU
  devices, and reports `libcuda` / `libcublas` / `libcudnn` dynamic-linker
  visibility for the future production launcher.
- Generated CUDA source exports `jitml_kernel(float*, const float*, size_t)`,
  `jitml_kernel_family_name`, and `jitml_kernel_output_count`. The
  host-callable wrapper owns CUDA device allocation, host-to-device input copy,
  deterministic device-kernel launch, `cudaDeviceSynchronize`, and
  device-to-host output copyback.
- `src/JitML/Engines/CudaLocal.hs` is the guarded CUDA local runner. It
  consumes a positive `probeCudaRuntime` before materializing and compiling the
  generated source, then loads the `.so` through the shared
  `JitML.Engines.Loader` / `dlopen` boundary and resolves the same
  family/output-count symbols as the Linux CPU local runner. It fails closed
  before compile when the CUDA runtime probe is unavailable.
- The CUDA compile plan renders the typed
  `nvcc --shared --compiler-options=-fPIC --use_fast_math=false -arch=sm_70
  -DJITML_USE_CUBLAS=1 -DJITML_USE_CUDNN=1 -o <artifact> <generated>/kernel.cu
  -lcudart -lcublas -lcudnn` command so the produced `.so` carries DT_NEEDED
  entries for the CUDA runtime, cuBLAS, and cuDNN; the dynamic linker
  resolves the three libraries at `dlopen` time and the CUDA toolchain
  fingerprint records the new link line so the JIT cache key reflects the
  artifact ABI change.
- `src/JitML/Engines/CublasBindings.hs` and
  `src/JitML/Engines/CudnnBindings.hs` are the typed Haskell binding surface
  for libcublas / libcudnn. They expose `withCublasHandle`,
  `verifyCublasRuntime`, `withCudnnHandle`, `verifyCudnnRuntime`, and the
  `cublasBindingsCompiledIn` / `cudnnBindingsCompiledIn` switches behind the
  `cuda` cabal flag. With `-fcuda` enabled (the canonical
  `jitml:local` build), `verifyCublasRuntime` / `verifyCudnnRuntime` create
  a handle, query the runtime version, and destroy the handle. With
  `-f-cuda`, every entrypoint returns a typed
  `CublasStatus (-2)` / `CudnnStatus (-2)` so non-CUDA hosts cannot silently
  no-op the cuBLAS / cuDNN path.
- The current local engine envelope names the `.so` artifact path and compile
  command. `JitML.Engines.HasEngine.LocalCudaEngine` wraps the guarded runner
  and rejects loaded-family metadata mismatches. The 2026-05-23 live single-node CUDA
  `RuntimeClass/nvidia` and pod-visible GPU probe closed on a Linux CUDA host
  (NVIDIA GeForce RTX 5090, CUDA 12.8) — Phase `4` Sprint `4.7` complete, and
  Phase `5` Sprint `5.6`'s CUDA service-pod portion complete on the same date.
- `jitml:local` (`docker/Dockerfile`) installs the CUDA 12.8 toolkit
  (`cuda-toolkit-12-8`) and matching cuDNN 9 dev headers
  (`libcudnn9-dev-cuda-12`), exposes `/usr/local/cuda/bin` on `PATH` and
  `/usr/local/cuda/lib64` on `LD_LIBRARY_PATH`, and runs
  `cabal build -fcuda exe:jitml exe:jitml-demo` so the installed
  `/usr/local/bin/jitml` binary links against libcublas / libcudnn.
  `compose.yaml` keeps the default `jitml` service headless for bootstrap and
  code-quality runs, and exposes every host NVIDIA GPU only through the
  `jitml-cuda` companion service via the modern `gpus: all` shorthand for live
  in-container CUDA validation.
- **MLP forward/backward network kernels (Sprint 13.8 / 13.9).**
  `src/JitML/Codegen/MlpCuda.hs` renders a `kernel.cu` for the
  `JitML.Numerics.Mlp` feed-forward network: `jitml_mlp_forward`
  (`hidden_pre`, `hidden_act = tanh hidden_pre`, `output = W2 hidden_act +
  b2`) and `jitml_mlp_backward` (parameter gradients `gW1 / gB1 / gW2 /
  gB2` from `dL/dy`, the forward `hidden_act`, the input, and `W2`). Each
  device thread accumulates its own reduction sequentially (no atomics, no
  warp-shuffle) so the result is bit-deterministic run-to-run on the same
  device. `src/JitML/Numerics/MlpCuda.hs` is the host runner — it compiles
  the kernel through the same `ensureKernelArtifact` JIT-cache path,
  `dlopen`s the `.so`, marshals the flat row-major parameter buffers across
  the FFI, and returns the same `MlpForward` / `MlpGradient` the pure
  network produces (CUDA `float` vs host `Double`, so agreement is within a
  single-precision tolerance). `jitml-backends` validates this on the
  RTX 3090: forward + backward match the pure network within `1e-3` and are
  bit-equal across repeated runs. Routing the RL trainers and the AlphaZero
  `PolicyValueNet` through these device kernels (batched) plus the cuDNN
  deterministic-pin are validated (Sprints 13.8 / 13.9 closed). Re-validated 2026-06-06 on an RTX 5090 / Blackwell `sm_120` — `nvcc -arch=sm_70` PTX forward-JITs at launch, `jitml-backends -fcuda` 38 / 38.

### `apple-silicon` — fixed Metal bridge

- `src/JitML/Codegen/Metal.hs` renders canonical MSL source plus
  `kernel.metal.json` metadata under
  `./.build/jit/apple-silicon/<hash>.metal.json`. The metadata records
  `bridge_abi=jitml-metal-bridge-v1`, family name, function names,
  output-count policy, threadgroup size, safe math mode, single-stream launch
  policy, source hash, and embedded source.
- `src/JitML/Engines/Loader.ensureKernelArtifact` fills an Apple cache miss by
  atomically writing that `.metal.json` file. There is no per-kernel Swift
  package, SwiftPM invocation, Tart VM build, copied dylib, stable symlink, or
  Apple per-kernel `dlopen` path.
- `src/JitML/Engines/MetalBridge.hs` owns the fixed bridge dylib. The install
  command writes the bridge source under `./.build/host/apple-silicon/` and
  builds `libJitMLMetalBridge.dylib` with `/usr/bin/clang -dynamiclib -fobjc-arc
  -ObjC ... -framework Foundation -framework Metal`. The bridge exports probe,
  generic source dispatch, and MLP forward/backward/batch entrypoints; stale
  bridge builds fail the probe because required symbols are checked.
- `src/JitML/Engines/MetalLocal.hs` loads/probes the fixed bridge, passes the
  Haskell-rendered MSL source to it, and dispatches unweighted and weighted
  family kernels on the host GPU. The bridge compiles MSL in-process through
  `MTLDevice.makeLibrary(source:options:)` with fast math disabled, creates
  deterministic pipeline state, uses one command queue, dispatches full
  simd-aligned threadgroups with bounds checks, and blocks for completion before
  returning output to Haskell.
- `src/JitML/Numerics/MlpDevice.hs` routes Apple MLP forward, backward,
  batched-gradient, batched-forward, and input-gradient batches through the same
  fixed bridge ABI using MSL from `src/JitML/Codegen/MlpMetal.hs`.
- `src/JitML/Engines/MetalRuntime.hs` probes host Metal device visibility
  (`system_profiler SPDisplaysDataType`); device visibility plus a loadable fixed
  bridge gates host execution. The core cache-miss path does not require
  `swiftc`, `xcrun metal`, SwiftPM, full Xcode, Tart, or login-keychain state.
- Metal kernels launch in a single `MTLCommandQueue` with FIFO ordering;
  explicit barriers prevent kernel reordering.

The bridge is host-only process infrastructure. A Linux container cannot execute
this path by mounting `./.build/host/apple-silicon/`, because the dylib targets
macOS frameworks and the dispatch requires a host `MTLDevice`. Any workload that
selects the Apple `MlpDevice` must therefore be placed on the host daemon before
it reaches the bridge.

## Apple Silicon Fixed-Bridge Metal JIT

The Apple Silicon JIT is source-metadata-first. On a cache miss, jitML writes
the canonical `.metal.json` artifact and immediately uses the fixed bridge to
compile the embedded MSL through the OS Metal runtime. On a cache hit, jitML
reuses the cached metadata and the process-local bridge/pipeline cache; no
external compiler, VM lifecycle, or user-session secret is part of the critical
path.

`jitml internal install-metal-bridge` is the headless bridge remediation command.
It is safe to run from source-built jitML because it needs only the system clang,
Foundation, Metal, and the Haskell-rendered bridge source. Optional generated
Swift modules may later use separate `apple.swiftc` / `apple.macos-sdk` probes,
but they are not the training/inference cache-miss path.

The retired Tart/SwiftPM path remains only as dated plan history and as rationale
in [apple_silicon_metal_headless_builds.md](apple_silicon_metal_headless_builds.md).

## Cache Survives Purge

`./bootstrap/apple-silicon.sh purge` clears runtime state but **preserves**
`./.build/`. After `purge`, every previously rendered Apple kernel metadata
artifact remains under `./.build/jit/apple-silicon/` and the fixed bridge remains
under `./.build/host/apple-silicon/`, so the next bootstrap plus any inference
command resolves from cache without regenerating source metadata or rebuilding
the bridge.

`purge --full` is `purge` plus `rm -rf ./.build/` (and on Linux,
`docker compose down --rmi local --volumes` to drop the substrate image).
Use only for fresh-start debugging.

## Linux Substrates Share the Cache via Kind `extraMounts`

The Kind cluster config bind-mounts host `./.build/` into the single Kind node,
and the `jitml-service` Deployment mounts that path into the pod at
`/opt/build`. Linux cache hits / misses share the same content-addressed layout:
on a Linux miss the compile runs in-process inside the pod because the substrate
image carries the full JIT toolchain. Later `docker compose run --rm jitml jitml <command>` invocations
reuse the Kind metadata under `./.build/`; the outer container exits after the
cluster daemon is in charge. This is the **one** exception to the "no
freestanding host paths in pod specs" discipline; the chart lint permits
exactly this hostPath and rejects any other.

## Hardware Auto-Tuning

`JitML.Engines.Tuning` defines the current per-substrate knob spaces (Metal:
threadgroup size, matmul tile, reduction strategy, single-stream queue
discipline; oneDNN: micro-kernel, reduction block, thread count, fastmath off;
CUDA: matmul tile, block dim, deterministic cuDNN algorithm id, reduction
strategy, TF32 off, fast-math off). `selectDeterministic` picks the deterministic
default for each axis and `tuningChoiceForResult` emits the cache-key payload.
`benchmarkPlan` enumerates the deterministic-only candidate `TuningResult`s for
each knob space in stable order, and `renderBenchmarkPlan` prints the
corresponding cache-key `TuningChoice` payloads. The current local test asserts
the CUDA plan has 72 deterministic candidates and includes the deterministic
default.

The pure measured-result boundary is also implemented:
`BenchmarkMeasurement` records a candidate, latency in microseconds, and output
digest; `selectMeasuredTuning` rejects measurements outside the benchmark plan
or with negative latency, then selects the lowest-latency candidate with stable
plan-order tie-breaking. `renderBenchmarkMeasurement` prints the cache-key
tuning choice, latency, and digest for audit logs.

`JitML.Engines.TuningStore` persists a supplied selected measurement under
`jit/tuning/<substrate>/<base-hash>.json`. The JSON record stores the substrate,
base hash, selected `TuningChoice`, measured latency, and output digest, and the
reader rejects records whose substrate or hash do not match the requested cache
base.

`JitML.Engines.TuningBenchmark` is the measurement collection boundary. It runs
candidates in benchmark-plan order through a typed candidate runner, records
latency and output digest as `BenchmarkMeasurement`s, provides SHA-256 digest
helpers for float and double output vectors, and can persist the selected
lowest-latency measurement by base hash through `TuningStore`.

`JitML.Engines.TuningCache` is the cache-key selection boundary. It derives the
default-tuning base hash, reads the persisted selection for that base hash when
present, renders the runtime source with the selected `TuningChoice`, and derives
the final cache key from that selected runtime-source payload and tuning choice.
`jitml build --dry-run` reports the base hash, selected tuning choice, and
whether the selection came from the default or persisted path before the compile
plan.
`JitML.Engines.TuningBenchmark.linuxCpuBenchmarkCandidateRunner` is the first
concrete candidate runner: it renders the tuned Linux CPU source, computes the
candidate cache key, compiles/loads through the existing generated-kernel FFI
path, measures elapsed time, and records the output digest.
`cudaBenchmarkCandidateRunner` and `metalBenchmarkCandidateRunner` are guarded
live runners for the non-local substrates: they reject wrong-substrate
candidates, summarize CUDA/Metal runtime availability from the typed runtime
probes, fail closed before compilation when the runtime is unavailable, and run
the visible-device candidate through the same CUDA local FFI or Apple fixed
bridge path used by normal kernel execution.

Target auto-tuning runs at JIT time on a cache miss, benchmarks only
deterministic choices, and records the selected `TuningChoice` per `KernelSpec`.
The chosen `TuningChoice` is a cache-key input; a knob change invalidates the
cache key. The remaining growth is broadening benchmark payloads beyond the
current primitive fixtures and wiring measured-choice selection more deeply into
first-cache-miss execution.

The cuDNN algorithm-id selection is restricted to the deterministic-only set.
The `--use_fast_math=false` invariant is preserved.

## FFI Boundary

The current worktree has typed cache decisions and `KernelHandle` construction
in `src/JitML/Engines/Engine.hs`, a shared cache artifact loader in
`src/JitML/Engines/Loader.hs`, local Linux CPU oneDNN primitive `dlopen`
runners in `src/JitML/Engines/Local.hs`, guarded CUDA `dlopen` runners in
`src/JitML/Engines/CudaLocal.hs`, and Apple fixed-bridge dispatch in
`src/JitML/Engines/MetalLocal.hs` / `src/JitML/Engines/MetalBridge.hs`.
`JitML.Engines.HasEngine` wraps generated-family runners in the local engine
capability and checks the requested family against loaded or rendered metadata.
Linux runners resolve the executable `jitml_kernel` symbol, the
`jitml_kernel_family_name` metadata symbol, and the
`jitml_kernel_output_count` shape symbol. Apple supplies equivalent metadata in
the `.metal.json` cache artifact and bridge ABI.
`ensureKernelArtifact` now owns the cache-on-miss path:

- On cache hit, returns a `KernelArtifact` with the existing `KernelHandle` and
  `kernelArtifactCompiled = False`.
- On Linux cache miss, materializes generated source, runs the typed substrate
  compile subprocess, and returns the new `KernelArtifact` with
  `kernelArtifactCompiled = True`.
- On Apple cache miss, writes the rendered `.metal.json` metadata artifact and
  returns a `KernelArtifact` whose command text describes the metadata-write
  plan.
- `withKernelSymbol` wraps `dlopen` / `dlsym` for Linux FFI runners that need a
  symbol from the cached artifact. Apple loads only the fixed bridge dylib; the
  bridge receives MSL source and function names at runtime.

## Cross-References

- [../../README.md → Built-artifact and JIT-cache discipline](../../README.md#built-artifact-and-jit-cache-discipline)
- [../../README.md → JIT compilation architecture](../../README.md#jit-compilation-architecture)
- [determinism_contract.md](determinism_contract.md)
- [daemon_architecture.md](daemon_architecture.md)
- [../../DEVELOPMENT_PLAN/phase-2-bootstrap-reconciler-and-jit-cache.md](../../DEVELOPMENT_PLAN/phase-2-bootstrap-reconciler-and-jit-cache.md)
- [../../DEVELOPMENT_PLAN/phase-7-jit-codegen-and-substrates.md](../../DEVELOPMENT_PLAN/phase-7-jit-codegen-and-substrates.md)
