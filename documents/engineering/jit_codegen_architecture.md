# JIT Codegen Architecture

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: README.md, ../documentation_standards.md, ../../DEVELOPMENT_PLAN/phase-0-planning-documentation.md, ../../DEVELOPMENT_PLAN/phase-2-bootstrap-reconciler-and-jit-cache.md, ../../DEVELOPMENT_PLAN/phase-7-jit-codegen-and-substrates.md, determinism_contract.md, numerical_core.md
**Generated sections**: none

> **Purpose**: Project-specific JIT codegen architecture for jitML — the
> content-addressed cache, the per-substrate compilers (Metal, oneDNN,
> CUDA), the current typed engine handle/envelope surface, the target FFI
> boundary, the Apple Silicon hybrid pattern with lazy tart spin-up, and the
> hardware auto-tuning surface — where routing every Apple Silicon Swift/Metal
> build through the `jitml-build` Tart VM (Xcode 16 pre-installed and
> pre-licensed) is a hard requirement, the only way jitML can truly JIT on
> Apple Silicon; the host keeps only the Metal framework to load the VM-produced
> `.dylib` and never installs or runs Xcode.

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
typed cache-key ADTs and SHA-256 derivation, `Layout` owns typed path
resolution under `./.build/`, `Manifest` owns `manifest.json` round-trip and
atomic writes, and `Symlink` owns atomic Apple stable-FFI symlink repointing.
Sprint `7.1` keeps `KernelSpec` as the current cache-key payload wrapper.
Future model-schema work grows that payload from local text fixtures into the
numerical core's full kernel shape.

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
a positive CUDA runtime probe; live CUDA GPU-host execution and Apple Metal
loading remain the open runtime validations.

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
  `cabal.project` (LLVM, NVCC, Xcode/Metal, oneDNN) plus loader-relevant ABI
  facts for local FFI paths.
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
already exists, fills cache misses through the typed compile `Subprocess`, and
returns a `KernelArtifact` that records the `KernelHandle`, cache status, compile
command, and whether compilation happened in this call. The same module owns the
reusable `dlopen`/`dlsym` helper used by local FFI runners.

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
  `compose.yaml` exposes every host NVIDIA GPU to the `jitml` service via
  the modern `gpus: all` shorthand for live in-container validation.
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
  single-precision tolerance). `jitml-cross-backend` validates this on the
  RTX 3090: forward + backward match the pure network within `1e-3` and are
  bit-equal across repeated runs. Routing the RL trainers and the AlphaZero
  `PolicyValueNet` through these device kernels (batched) plus the cuDNN
  deterministic-pin validation is the open Sprint 13.8 / 13.9 integration.

### `apple-silicon` — Swift + Metal

- `src/JitML/Codegen/Metal.hs` renders the generated Swift package and Metal
  kernel input under `./.build/jit-src/apple-silicon/<hash>/`.
- Generated Swift source exports `jitml_kernel_family_name` and
  `jitml_kernel_output_count` metadata symbols for the future Metal FFI
  loader. The generated reduction metadata reports `ceil(n / 32)` outputs,
  matching the current `simd_sum` simdgroup partial-output kernel shape.
- The build plan runs `swift build` inside the `jitml-build` tart VM via
  `tart exec`, against the generated package directory. The VM ships Xcode 16
  pre-installed and pre-licensed, so compiling the generated `Kernels.metal`
  resource through Xcode's `metal` shader compiler runs fully non-interactively
  under `tart exec` — no first-launch or license UI can break the headless
  workflow. ALL Apple Silicon Swift and Metal builds run in this VM regardless
  of VM image size or download cost; full Xcode is never installed on the host.
- The produced `.dylib` is copied atomically to
  `./.build/jit/apple-silicon/<hash>.dylib` and the stable-FFI symlink at
  `./.build/host/apple-silicon/<model-id>.dylib` is repointed.
- `src/JitML/Engines/MetalRuntime.hs` owns the typed host Metal runtime probe:
  it checks `swift --version`, `xcrun -find metal`, `xcrun -find swiftc`, and
  `system_profiler SPDisplaysDataType` through the typed subprocess boundary,
  parses Swift version/tool paths and Metal device visibility, and renders the
  availability summary for the future host FFI launcher. A failing
  `xcrun -find metal` on the host is never remediated by installing Xcode on the
  host — the `metal` shader compiler exists only inside the `jitml-build` VM.
  The host probe is informational; the host keeps solely the Metal framework to
  load and execute the VM-produced `.dylib` and never compiles shaders.
- The current local engine envelope names the `.dylib` artifact path and Tart
  `swift build` command through `tart exec`. `JitML.Engines.Loader` now routes
  Apple cache misses through the concrete `JitML.Tart.Build`
  first-cache-miss executor.
- `JitML.Engines.MetalLocal` (Sprint `14.2` / `14.5`, code landed 2026-05-30)
  implements the host-side runner: `runMetalKernel` / `runMetalWeightedKernel`
  `dlopen` the cached `<hash>.dylib`, resolve the host-callable
  `jitml_kernel` / `jitml_weighted_kernel` / `jitml_kernel_family_name` /
  `jitml_kernel_output_count` C ABI emitted by `JitML.Codegen.Metal`, and
  marshal buffers across the FFI to the generated `MTLDevice` launcher.
  `JitML.Engines.HasEngine` dispatches `apple-silicon` through
  `LocalAppleSiliconEngine`. The generated Swift launcher loads its
  `MTLLibrary` from the content-addressed `<hash>.metallib` that
  `JitML.Tart.Build` publishes beside the relocated dylib
  (`JITML_METALLIB_PATH`). Live exercise of the build-in-VM → `dlopen` →
  Metal launch path requires booting the `jitml-build` VM from an
  interactive GUI session (the macOS guest cannot boot headless — Secure
  Enclave / Aqua-session requirement) and is the remaining Phase `14`
  closure gate.
- `JitML.Tart.Build` renders the current first-cache-miss plan for Apple:
  ensure `jitml-build`, validate `swift --version` inside the VM, run
  `swift build` against the generated package, copy
  `libJitMLMetal.dylib` into `./.build/jit/apple-silicon/<hash>.dylib`, and
  repoint the stable host FFI symlink through
  `JitML.Cache.Symlink.repointSymlink`. The same module exposes
  `executeTartCacheMissBuildPlan`, which performs real `tart list`,
  `tart run --no-graphics`, readiness probing through `tart exec <vm> true`,
  Swift validation/build commands, cache publication, and symlink repointing.
  `executeTartCacheMissBuildPlanWith` remains the typed host-action/subprocess
  boundary that unit tests validate with synthetic ordered-success and
  failure-short-circuit executors.
- Metal kernels launch in a single `MTLCommandQueue` with FIFO ordering;
  explicit barriers prevent kernel reordering.

## Apple Silicon Hybrid Pattern

Routing every Apple Silicon Swift and Metal kernel build through the
`jitml-build` Tart VM is a hard architectural requirement, not an optimization.
It is the only way jitML can truly JIT on Apple Silicon: the VM ships Xcode 16
pre-installed and pre-licensed, so `swift build` compiles the generated
`Kernels.metal` resource through Xcode's `metal` shader compiler
non-interactively via `tart exec` — no first-launch or license UI can break the
headless workflow. Full Xcode is **never** installed on the host: its
first-launch license/UI prompts break the required headless workflow, and host
Xcode is never an acceptable remediation for a missing `metal` compiler or an
`xcrun -find metal` failure. The host retains only the Metal framework, used
solely to load and execute the VM-produced `.dylib`; the host never compiles
shaders and never runs Xcode. This holds irrespective of the VM image size or
download cost.

Bootstrap and the host daemon's startup path never touch tart. On a JIT cache
miss, the host daemon first validates or installs the `tart` Homebrew package
through typed lazy prerequisite remediation, then calls
`JitML.Tart.ensureVmUpLive jitml-build`:

- If the VM is up, no-op.
- If down, start `tart run --no-graphics jitml-build` through the typed
  detached subprocess boundary and poll until reachable.

The daemon then dispatches the Swift build inside the VM via `tart exec`,
writes the artifact into `./.build/jit/apple-silicon/<hash>.dylib`
atomically (`tmp + rename`), repoints the stable-named symlink under
`./.build/host/apple-silicon/`, and loads via FFI. The checked-in
`JitML.Tart.Build` executor now performs the real Tart status/run/readiness
steps and cache publication. The user-facing lifecycle commands call the same
Tart boundary: `jitml internal vm bootstrap` clones the default source image
into `jitml-build` when missing, `status` reports the parsed Tart state, and
`down` stops a running VM through `tart stop`. Provisioning/bootstrapping the
`jitml-build` VM on Apple hardware and performing the Metal FFI launch remain
target runtime work.

The VM stays up for the daemon's lifetime once spun up; an idle timeout
(default `30 min`, configurable in `LiveConfig.tartIdleTimeout`) brings it
down again. Subsequent cache hits skip the spin-up entirely.

Manual VM access is available via `jitml internal vm bootstrap|up|down|status`
and `jitml internal vm exec -- <cmd>` (Apple-only Tart operations).

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

The Kind cluster config bind-mounts host `./.build/` into the single Kind node,
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
preflight boundaries for the non-local substrates: they reject wrong-substrate
candidates, summarize CUDA/Metal runtime availability from the typed runtime
probes, and fail closed until the live FFI candidate execution paths are
implemented.

Target auto-tuning runs at JIT time on a cache miss, benchmarks only
deterministic choices, and records the selected `TuningChoice` per `KernelSpec`.
The chosen `TuningChoice` is a cache-key input; a knob change invalidates the
cache key. The live hardware work that remains is adding actual CUDA/Metal
measurement behind those preflight runners, wiring benchmark selection into
first-cache-miss execution, expanding the Linux CPU benchmark payloads beyond
the current flat oneDNN primitive fixtures, and validating those runners on
real hardware.

The cuDNN algorithm-id selection is restricted to the deterministic-only set.
The `--use_fast_math=false` invariant is preserved.

## FFI Boundary

The current worktree has typed cache decisions and `KernelHandle` construction
in `src/JitML/Engines/Engine.hs`, a shared cache artifact loader in
`src/JitML/Engines/Loader.hs`, and local Linux CPU oneDNN primitive `dlopen`
runners in `src/JitML/Engines/Local.hs`. `JitML.Engines.HasEngine`
wraps the generated-family Linux CPU runner in the local engine capability and
checks the requested family against the loaded artifact metadata. The local
runner resolves
the executable `jitml_kernel` symbol, the `jitml_kernel_family_name` metadata
symbol, and the `jitml_kernel_output_count` shape symbol.
`ensureKernelArtifact` now owns the local
compile-on-miss path:

- On cache hit, returns a `KernelArtifact` with the existing `KernelHandle` and
  `kernelArtifactCompiled = False`.
- On cache miss, materializes generated source, runs the typed substrate compile
  subprocess, and returns the new `KernelArtifact` with
  `kernelArtifactCompiled = True`.
- `withKernelSymbol` wraps `dlopen` / `dlsym` for FFI runners that need a symbol
  from the cached artifact.

The production engine interpreters still need to grow real graph-kernel launch.
Apple Silicon FFI uses `dlopen` against the stable-named symlink; generated
Swift already exposes the family/output-count metadata symbols for that loader,
but the `MTLDevice`/pipeline/command-buffer launch path is still target runtime
work. Linux loaders use `dlopen` directly against the cache file.

## Cross-References

- [../../README.md → Built-artifact and JIT-cache discipline](../../README.md#built-artifact-and-jit-cache-discipline)
- [../../README.md → JIT compilation architecture](../../README.md#jit-compilation-architecture)
- [determinism_contract.md](determinism_contract.md)
- [daemon_architecture.md](daemon_architecture.md)
- [../../DEVELOPMENT_PLAN/phase-2-bootstrap-reconciler-and-jit-cache.md](../../DEVELOPMENT_PLAN/phase-2-bootstrap-reconciler-and-jit-cache.md)
- [../../DEVELOPMENT_PLAN/phase-7-jit-codegen-and-substrates.md](../../DEVELOPMENT_PLAN/phase-7-jit-codegen-and-substrates.md)
