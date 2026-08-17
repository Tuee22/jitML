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

## Current Status

**Implemented today.** The supervised served path reconstructs the reloaded typed
`LayerGraph` from checkpoint metadata and executes it directly through
`LayerGraph.runLayerGraph` (Phases `237`–`239`); the V2 structural-operation ABI
has been removed. The `LayerGraphDevice` device path evaluates one example at a
time.

**`LayerGraphDevice` is the one layer-graph device path, with a per-lane arm
behind it.** Sprint `264.1` parameterised it on `Substrate`: a narrower
`LayerTrainingBackend` (`OneDnnLayerTraining` / `CudaLayerTraining`) makes every
function behind it total, and `layerTrainingBackendFor` is the single boundary
where a substrate becomes a backend. `linux-cpu` renders oneDNN primitives and
`linux-cuda` renders cuBLAS/cuDNN primitives, both splicing the same shared
operator layer, so the two lanes cannot drift in operator semantics.
`apple-silicon` has no layer-graph training kernel and therefore fails closed
naming Sprint `269.1`, rather than silently executing the `linux-cpu` artifact
and attributing the run to hardware that did not execute it. The per-substrate
lowering is owned by
Phase `79` (the substrate-generic seam),
[Phase 264](../../DEVELOPMENT_PLAN/phase-264-real-cudnn-cublas-kernels.md), and
[Phase 269](../../DEVELOPMENT_PLAN/phase-269-real-metal-kernels.md).

**Target (Phase `234`, see [DEVELOPMENT_PLAN](../../DEVELOPMENT_PLAN/README.md)).**
The oneDNN layer kernels gain a **batched** forward/backward path (Phase `234`).

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
general per-substrate source bundles. (Phase `239` removed the supervised V2
structural-runtime `RuntimeOperations{Cpu,Cuda,Metal}` renderers; supervised
serving now runs the reloaded typed `LayerGraph` directly.) The repository does
not keep checked-in substrate-source directories for generated compiler inputs.

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
- `toolchain-fingerprint` is a rendering of `ToolchainFacts`
  (`src/JitML/Engines/Fingerprint.hs`), and every field of it is *derived* from
  the surface it describes rather than restated beside it: the compiler name,
  its hash-free compile flags, and its link line come from
  `Engine.engineCompiler` / `engineCompileFlags` / `engineLinkFlags` — the same
  lists `compileSubprocess` passes, so a flag or link-line edit moves the
  command and the fingerprint together; the determinism knobs come from
  `deterministicFlags`; the ABI is a typed `AbiKind`, so the Metal bridge token
  is interpolated from `metalBridgeAbiVersion` at every site by construction;
  the numeric knobs come from the renderers' own constants
  (`oneDnnFixedReductionBlock`, `threadgroupSizeFor`); the entry points come
  from one shared list per ABI; and the emitter set comes from the vocabulary
  the artifact covers (`kernelFamilies` for family kernels,
  `allLayerKinds` for the layer-graph training kernel), so widening either
  vocabulary invalidates the artifacts that execute it. `buildToolchainFingerprint`
  is total over `Substrate` and equals the per-substrate family fingerprint, so
  the build path and the benchmark-tuning candidate runners cannot key one
  artifact two ways. Rendered kernel bodies are deliberately not restated here —
  they already reach the key through `rendered-source-payload`.
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
the reusable `loadKernelLibrary` plus `dlopen`/`dlsym` helpers used by local
Linux FFI runners and fixed bridge probing.

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

### One substrate profile

Every fact that varies by substrate lives in one `SubstrateProfile` record with
a single total `profileFor` (`src/JitML/Substrate.hs`) — backend name, artifact
extension, determinism knobs, `KernelLaunch`, `ArtifactFill`, cluster-compute,
edge port, and runtime class. `Engine.engineForSubstrate` and
`deterministicFlags` are projections of it, so the engine record cannot
disagree with the profile, and `profileFor` has one equation per constructor
with no wildcard, so a fourth substrate is a build failure rather than a silent
default.

Two of those fields replace branches that used to sit inside otherwise-generic
code. `ArtifactFill` decides whether a cache miss runs the typed compile
`Subprocess` or writes `<hash>.metal.json` in-process, so
`Loader.ensureKernelArtifact` dispatches on a value instead of a wildcard over
`Substrate`. `KernelLaunch` decides whether a kernel is entered by `dlopen` /
`dlsym` or through the fixed Metal bridge; `MlpBackendSpec` carries it, and
`Loader.executedArtifactIdentity` uses it to ask an artifact what it actually
implements — reading `jitml_kernel_family_name` out of a loaded object, or the
`family` field out of the written Metal source metadata. That read is what makes
the engine-boundary family check evidence rather than a tautology: the Apple
family driver previously reported the family the host had *requested*, so the
comparison could never reject anything.

The `dlopen`/`dlsym` half of the ABI — the FFI type aliases, the dynamic
imports, and the `loadAndRun` / `loadAndRunWeighted` helpers — is owned once by
`JitML.Engines.LoadableKernel` and shared by every substrate whose profile
carries `LoadableSymbolLaunch`.

### Supervised serving through the trained graph

Phase `239` retired the V2 structural-operation ABI. A supervised checkpoint's
sole served representation is its trained typed `LayerGraph` (persisted as
`architectureLayerGraph` metadata); there is no persisted or executed layer-op
program, no per-substrate `RuntimeBackendExecutor`, and no generated
`RuntimeOperations{Cpu,Cuda,Metal}` structural bundle. The
`JitML.Codegen.RuntimeOperations*`, `JitML.Engines.RuntimeOperations*`, and the
`RuntimeArtifact` `executeLoadedRuntime` / `RuntimeBackendExecutor` /
`RuntimeLayerOperation` surfaces are deleted.

`JitML.Engines.{Local,CudaLocal,MetalLocal}` serve a supervised checkpoint
through `runSupervisedGraphCheckpointInference`: reconstruct the trained
`LayerGraph` from its metadata, inject the one physical graph-ordered
`supervised.weights` blob as the parameter vector, run
`LayerGraph.runLayerGraph`, and apply the exact input/output transforms (which
ride OUTSIDE the graph) as pure functions
(`RuntimeArtifact.executeSupervisedGraphRuntime`). The transforms — feature
standardisation / unit-image ingress and the semantic-prefix / destandardize
egress — are the only supervised-runtime state that survives alongside the
graph.

## Product Scaffold Boundary

Sprint `20.1` removed the legacy fake-RL helpers from `src/`: the deleted
`JitML.RL.VecEnv` was a dead, zero-caller fake with no product reach, so it was
removed rather than the vectorized-env capability as such. The current
product-reachable, learning `JitML.RL.VecEnv` batches ~16 parallel environment
instances through the network in a single device call per step; this module is
exercised on the trainer device seam and is categorically distinct from the
removed fossil. The scaffold-lint now
distinguishes the real vectorized-env module (a genuine caller-backed
device-batched env) from that dead zero-caller fake, so reintroducing the real
`VecEnv` does not re-trip the fake-scaffold gate. `runRLLoop` / `runOneEpisode`
and the deterministic step helper live only under `test/rl-canonicals/Support/`,
and the old simulator-loop runners are test-support only. Product RL dispatch reaches
real trainers through `JitML.RL.TrainerExecution`; `EpisodeEnvelope` remains a
trajectory/animation projection, while broker publication uses distinct
plan-bound `IterationSummary` learning telemetry and keyed
`EvaluationOutcome` final-policy evidence. No product cache-miss path,
JIT source renderer, engine loader, or trainer device seam imports the relocated
scaffolding modules.

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
  matmul, convolution, and normalization primitives through the Haskell FFI. The
  attention and embedding families are **fixtures rather than primitives** on this
  renderer — they render an identity matmul and a reorder respectively, pending the
  QKV tensor and table-index ABIs, as their generated source states while checking that the loaded artifact reports the
  expected family and output length. Its local toolchain fingerprint includes
  `artifact-abi=<os>-<arch>` and the `reduction-block=` knob read off
  `oneDnnFixedReductionBlock` so host-native Darwin builds, Linux container
  builds, and fixed reduction-block changes do not collide in the shared
  `.build/jit/linux-cpu/` cache.
- `src/JitML/Engines/HasEngine.hs` wraps the generated-family Linux CPU runner
  in the local `HasEngine` capability, preserving the family metadata check at
  the engine boundary.
- Sprint `23.2` adds a generated layer-graph training shared object through the
  same cache and loader path. `renderOneDnnLayerTrainingSource` emits
  `jitml_layer_forward`, `jitml_layer_backward_data`, and
  `jitml_layer_backward_weights` plus primitive-name evidence functions.
  `JitML.Numerics.LayerGraphDevice` resolves those symbols with
  `withKernelSymbol`, dispatches parameterized `LayerGraph` nodes to oneDNN, and
  returns per-node evidence naming the backend, artifact, and primitive. Dense
  and other affine graph nodes execute oneDNN matmul; `Conv2D` and `Conv3D`
  execute oneDNN `convolution_forward` in `forward_training` mode plus
  `convolution_backward_data` and `convolution_backward_weights` over the
  graph's flat 1x1 channel projection.
- Phase `241` replaces that flat 1×1 projection with a **real `dnnl` primitive
  per operator kind**. `renderOneDnnLayerTrainingSource` renders spatial `ConvOp`
  (`convolution_{forward,backward_data,backward_weights}` over the true
  `[C_in,H,W]` / kernel / stride / padding geometry), `NormOp` (batch / layer /
  group norm), `GeGLUOp` (three-projection gated GELU), multi-head `AttentionOp`
  including the `W_O` output projection, `PatchOp`, `ResidualOp`, and the
  BasicBlock/Bottleneck `BlockOp` composed from dense + norm device sub-kernels.
  The FFI carries each operator's true geometry and packed-parameter layout, and
  `deviceLayerGradient` dispatches on the node's `LayerOp` to the matching kernel.
  Each kernel is validated against the pure `backwardLayerGraph` oracle within
  float32 tolerance in the backends lane; on this lane the pure gradient is never a
  runtime fallback. The determinism contract forbids such a fallback on the
  execution path, which is why the absence of a layer-graph device path on
  `linux-cuda` and `apple-silicon` is a tracked defect rather than a design choice
  (see [Current Status](#current-status)).
- That per-operator dispatch is a **total lowering**. `LayerGraphDevice.lowerLayerOp`
  maps every declared `LayerOp` onto the closed primitive set
  `LowerDenseAffine | LowerSpatialConv | LowerBlockComposition | LowerOpTrain`,
  with no wildcard arm: a twelfth operator is a compile error under
  `-Werror=incomplete-patterns` rather than a silent host fallback. Three
  consequences of totality are visible on the lane. A real three-dimensional
  `ConvOp` executes `jitml_conv3d_spatial_{forward,backward_data,backward_weights}`
  (`ncdhw`/`oidhw`) instead of failing closed. `PoolOp` runs the `dnnl` pooling
  primitive whose algorithm is its own `PoolSpec` — max,
  average-excluding-padding, or average-including-padding, with global average
  pooling the exclude-padding case over the full spatial extent — so its
  gradient routing is device work rather than oracle work. `IdentityOp` and
  `DropoutOp` lower to one scale kernel (identity is the unit scale, dropout's
  scale is the shared `dropoutScale`), so "no trainable parameters" no longer
  means "not executed": every node emits device evidence naming the primitive
  the artifact reports.
- `jitml_op_train` returns an executed-opcode status rather than `void`. An
  unrecognised opcode previously fell through a `default: break`, leaving the
  caller's output and gradient buffers untouched — indistinguishable from a
  kernel that ran and produced zeros. The host now reads the status and fails
  closed with a typed error naming the opcode.
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
  (`artifact-abi=<os>-<arch>`) and the fixed reduction block read off
  `JitML.Codegen.OneDnn.oneDnnFixedReductionBlock` — the same constant the
  renderer emits into the generated source — because the same repository
  `.build/` tree can be mounted by both the host and `jitml:local`, and
  reduction-block changes alter deterministic kernel semantics.
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
  directory with the doctrine-pinned determinism flags and baseline `sm_70`.
  Fast math is disabled by **omission** — `--use_fast_math` is never passed,
  because modern nvcc rejects the `=false` spelling — and `--fmad=false` is
  passed explicitly to suppress FMA contraction.
- The produced `.so` is written atomically to
  `./.build/jit/linux-cuda/<hash>.so`.
- The generated **family** reduction kernel uses warp-shuffle reduction and
  writes one deterministic partial per warp; it does not use device-side
  `atomicAdd`. The trainer MLP kernel does not use this pattern — see the MLP
  seam below.
  `src/JitML/Engines/CudaRuntime.hs` mirrors the generated block/warp geometry,
  computes the expected partial count, validates the partial vector length, and
  folds those partials in canonical index order.
- Where cuBLAS / cuDNN are called — the family kernels and the Sprint `264.1`
  layer-graph arm — they are pinned to deterministic algorithm selections via
  `cudnnSetConvolutionMathType` plus explicit algorithm-id pinning. The trainer
  MLP kernel calls neither.
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
  device-to-host output copyback. Sprint `29.4` hoists the weight upload out of
  this per-batch path with persistent CUDA device weight buffers: within a
  fixed-parameter phase the weights are uploaded to the device once and reused
  across batches, so the per-call `cudaMalloc` + host-to-device weight copy no
  longer sit on the per-batch kernel path (see
  `src/JitML/Codegen/MlpCuda.hs`).
- Phase `29` extends the generated CUDA family surface so Dense2D and MHA invoke
  `cublasSgemm`, Conv2D/Conv3D invoke `cudnnConvolutionForward` through
  deterministic tensor/filter/convolution descriptors, and BatchNorm/LayerNorm
  invoke cuDNN normalization descriptors. The generated artifact owns the native
  cuBLAS/cuDNN handles inside the compiled CUDA source; the Haskell binding
  modules remain the typed compile/runtime probe surface. This cuBLAS/cuDNN
  routing applies **only** to the generated family-kernel surface
  (Conv2D/Conv3D/MHA/BatchNorm/LayerNorm/Dense2D); it is a separate seam from the
  executed RL/SL trainer MLP device path, which uses the hand-written elementwise
  kernels in `src/JitML/Codegen/MlpCuda.hs` (`jitml_mlp_forward` /
  `jitml_mlp_forward_batch` / `jitml_mlp_grad`) and does **not** call
  `cublasSgemm` (see "MLP forward/backward network kernels" below). The two
  surfaces therefore do not overlap and are not in conflict.
- *(Dated historical, 2026-07-05 — since WITHDRAWN.)* On 2026-07-05 the
  `jitml-backends --linux-cuda` lane was recorded as passing **21 / 21** on the
  RTX 5090, asserting those generated source entry points before executing the
  kernels. That evidence is withdrawn and must be cited only as dated historical
  record. Current 2026-07-10 backend validation passes **22 / 22** on the RTX
  5090, and the full `linux-cuda` product lane is **Done** after the fresh
  55-row publisher, integration/e2e/live gates, and Phase `29.4` performance
  table passed. The lane's assertion structure (checking the generated source
  entry points before kernel execution) is unchanged.
- `src/JitML/Engines/CudaLocal.hs` is the guarded CUDA local runner. It
  consumes a positive `probeCudaRuntime` before materializing and compiling the
  generated source, then loads the `.so` through the shared
  `JitML.Engines.Loader` / `dlopen` boundary and resolves the same
  family/output-count symbols as the Linux CPU local runner. It fails closed
  before compile when the CUDA runtime probe is unavailable.
- The CUDA compile plan renders the typed
  `nvcc --shared --compiler-options=-fPIC --fmad=false -arch=sm_70
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
  `/usr/local/cuda/lib64` on `LD_LIBRARY_PATH`, and runs a CUDA-enabled build
  of `exe:jitml` so the installed `/usr/local/bin/jitml` binary links against
  libcublas / libcudnn.
  `compose.yaml` keeps the default `jitml` service headless for bootstrap and
  code-quality runs, and exposes every host NVIDIA GPU only through the
  `jitml-cuda` companion service via the modern `gpus: all` shorthand for live
  in-container CUDA validation.
- *(Dated historical, 2026-07-05 — since WITHDRAWN.)* A Phase `29` product-lane
  validation recorded on 2026-07-05 staged all 12 canonical datasets, published
  all **55 / 55** ProductRow checkpoints on `linux-cuda`, passed
  `jitml test all --linux-cuda` **8 / 8**, and passed live Playwright **71 / 71**
  at the CUDA edge `:9092`. This evidence is withdrawn and must be presented only
  as dated historical record, never as current closure. It was superseded on
  2026-07-10 by the fresh **55 / 55** publisher, integration/e2e/live gates, and
  **55 / 55** CUDA-faster-than-CPU table that retain closure for Sprints
  `29.1`–`29.4`. Phase `29` as a whole is now **Blocked**, not Active: reopened
  Sprint `29.5` waits on Phase `263` / legacy Sprint `28.6` before it can
  produce the new contract-journal-bound CUDA lane attestation.
- **MLP forward/backward network kernels (Sprint 15.8 / 15.9).**
  `src/JitML/Codegen/MlpCuda.hs` renders a `kernel.cu` for the
  `JitML.Numerics.Mlp` feed-forward network: `jitml_mlp_forward`
  (`hidden_pre`, `hidden_act = tanh hidden_pre`, `output = W2 hidden_act +
  b2`) and `jitml_mlp_backward` (parameter gradients `gW1 / gB1 / gW2 /
  gB2` from `dL/dy`, the forward `hidden_act`, the input, and `W2`). Each
  device thread accumulates its own reduction sequentially (no atomics, no
  warp-shuffle) so the result is bit-deterministic run-to-run on the same
  device. These `jitml_mlp_forward` / `jitml_mlp_forward_batch` / `jitml_mlp_grad`
  entry points are **hand-written elementwise CUDA kernels**, not `cublasSgemm`
  calls; the cuBLAS/cuDNN routing described above applies to the separate
  generated family-kernel surface, not to this trainer MLP device seam.
  `src/JitML/Numerics/MlpCuda.hs` is the host runner — it compiles
  the kernel through the same `ensureKernelArtifact` JIT-cache path,
  `dlopen`s the `.so`, marshals the flat row-major parameter buffers across
  the FFI, and returns the same `MlpForward` / `MlpGradient` the pure
  network produces (CUDA `float` vs host `Double`, so agreement is within a
  single-precision tolerance). Under Sprint `29.4` the flat weight buffers are
  uploaded once per fixed-parameter phase into persistent device buffers and
  reused across batches, rather than re-marshalled on every per-batch launch.
  The CUDA batch-gradient path also uses one thread per `gW1`/`gW2` weight
  element plus separate bias kernels, preserving deterministic per-thread batch
  reductions while keeping tiny-output rows fast enough for the strict
  ProductRow speedup gate. `jitml-backends --linux-cuda` validates this on the
  RTX 5090: forward + backward match the pure network within `1e-3`, batched
  forward/gradient/input-gradient match the pure MLP oracle, trainer paths run
  through the batched device kernels, and the Phase `29.4` source guard covers
  persistent buffers and per-weight gradient kernels (**22 / 22**).

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
- Phase `30` makes most of the product-family Metal renderer real rather than
  copy-shaped: Dense2D, Conv2D, Conv3D, BatchNorm, LayerNorm, Embedding,
  Reduction, and Identity render explicit MSL bodies. **MultiHeadAttention is not
  yet real on the unweighted path**: it renders an elementwise square, which also
  disagrees with the oneDNN renderer for the same family. Phase `269` owns it. Conv2D and Conv3D weighted kernels use windowed multi-tap
  neighbourhoods and the backend tests reject the old identity-copy and
  1x1-degenerate source markers before executing Metal output checks against
  host references.
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
- The per-row `device:<substrate>:<runtime>:<kernel-summary>` cell is currently
  composed from the declared substrate and the declared device claim, so it is not
  a record of what executed. Phase `229` owns making it mintable only from an
  execution witness. Dated per-lane counts are owned by the sprint whose gate
  produced them and live in
  [../../DEVELOPMENT_PLAN/](../../DEVELOPMENT_PLAN/README.md).

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

The Kind cluster config bind-mounts host `./.build/` into every materialized Kind
node, and the `jitml-service` Deployment mounts that path into the pod at
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
The no-fast-math invariant is preserved by omitting `--use_fast_math`, and
`--fmad=false` is passed explicitly.

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
