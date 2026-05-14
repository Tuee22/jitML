# Phase 7: JIT Codegen and Per-Substrate Execution

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md),
[development_plan_standards.md](development_plan_standards.md),
[system-components.md](system-components.md),
[phase-0-planning-documentation.md](phase-0-planning-documentation.md),
[phase-2-bootstrap-reconciler-and-jit-cache.md](phase-2-bootstrap-reconciler-and-jit-cache.md),
[phase-6-numerical-core.md](phase-6-numerical-core.md),
[phase-8-supervised-and-rl-framework.md](phase-8-supervised-and-rl-framework.md),
[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
**Generated sections**: none

> **Purpose**: Stand up the per-substrate JIT codegen drivers (Metal, oneDNN,
> CUDA), the engine ABI between the Haskell daemon and the substrate-specific
> kernels, the content-addressed cache key inputs from the numerical core, the
> Apple Silicon hybrid pattern (host daemon + lazy tart spin-up + cluster RPC
> envelope), and the hardware auto-tuning surface that preserves the per-
> substrate determinism contract.

## Phase Status

⏸️ **Blocked** on Phase `6` closure. The codegen drivers consume the typed
numerical core from Phase `6` and write into the cache layout from Phase `2`.
The Apple Silicon hybrid pattern consumes the daemon shape from Phase `5` and
the bootstrap tart contract from Phase `2`.

## Phase Summary

This phase delivers the three substrate engines under `src/JitML/Engines/`, the
codegen driver homes (`codegen-cuda/`, `codegen-metal/`, `codegen-onednn/`),
the content-addressed cache key derivation from `KernelSpec`, the FFI boundary
that consumes cached `.dylib` / `.so` artefacts, the per-substrate determinism
contract enforcement (Metal single-stream, oneDNN blocked reduction, CUDA
warp-shuffle + `--use_fast_math=false` + cuDNN explicit algorithm-id pinning),
and the hardware auto-tuning surface.

## Sprint 7.1: `KernelSpec`, Cache Key Inputs, FFI Loader Surface ⏸️

**Status**: Blocked
**Blocked by**: phase-6, 2.3
**Implementation**: `src/JitML/Codegen/KernelSpec.hs`,
`src/JitML/Codegen/CacheKey.hs`, `src/JitML/FFI/Loader.hs`
**Docs to update**: `documents/engineering/jit_codegen_architecture.md`,
`documents/engineering/determinism_contract.md`

### Objective

Populate `KernelSpec` from the numerical core (Phase `6`) and lock the four-
tuple cache key derivation `(canonical-cbor(KernelSpec), kind, substrate,
toolchain-fingerprint)`. Stand up the FFI loader that resolves cached
artefacts (Apple via the stable-named symlink at
`./.build/host/apple-silicon/<model-id>.dylib`; Linux directly out of
`./.build/jit/<substrate>/`).

### Deliverables

- `KernelSpec` ADT carrying:
  - `ksLayers :: [Layer]` (layer topology),
  - `ksDtypes :: [Dtype]` (per-tensor dtype layout),
  - `ksActivations :: [Activation]` per applicable layer,
  - `ksOptimizer :: Maybe Optimizer` (present when `kind = Training`),
  - `ksLoss :: Maybe Loss` (present when `kind = Training`),
  - `ksFreezeMask :: [Bool]` (per-layer trainable flag).
- `canonicalCborKernelSpec :: KernelSpec -> ByteString` is deterministic and
  golden-tested.
- `ToolchainFingerprint` is the hash of every codegen-toolchain pin from
  `cabal.project` plus the substrate kernel-compiler version captured at
  daemon startup.
- `cacheKey` (Sprint `2.3` placeholder) is now fully populated.
- `loadKernel :: HasJitCache env => ModelId -> Kind -> Substrate -> IO
  (Either AppError KernelHandle)` returns either a cached handle or `AppError
  JitCacheMiss`. The `JitCacheMiss` triggers a per-substrate compile path
  (Sprints `7.3`–`7.5`).
- Apple Silicon FFI loader uses `dlopen` against the stable-named symlink;
  Linux loaders use `dlopen` directly against the cache file.

### Validation

1. `canonicalCborKernelSpec` produces byte-identical output across two runs
   for the same `KernelSpec`.
2. `cacheKey` golden tests pass.
3. A `JitCacheMiss` against an empty cache fails with the typed error;
   populating the cache and retrying succeeds.

## Sprint 7.2: Engine ABI and `Engines` Module Skeleton ⏸️

**Status**: Blocked
**Blocked by**: 7.1
**Implementation**: `src/JitML/Engines/Engines.hs`,
`src/JitML/Engines/AppleSilicon.hs`,
`src/JitML/Engines/LinuxCPU.hs`,
`src/JitML/Engines/LinuxCUDA.hs`,
`src/JitML/FFI/EngineAbi.hs`
**Docs to update**: `documents/engineering/jit_codegen_architecture.md`

### Objective

Define the engine ABI shared by every substrate: typed entrypoints for kernel
launch, parameter binding, output retrieval, and per-substrate envelope
capture. Stand up empty per-substrate engine modules that later sprints
populate.

### Deliverables

- `class HasEngine env where` exposes `launchKernel :: KernelHandle ->
  KernelInputs -> IO KernelOutputs`, `paramsCommit :: KernelHandle ->
  ParamSnapshot -> IO ()`, `engineEnvelope :: KernelHandle -> IO
  EngineEnvelope`.
- `EngineEnvelope` carries the substrate-specific reproducibility witnesses
  named in [../documents/engineering/determinism_contract.md → Engine
  Envelope](../documents/engineering/determinism_contract.md): for Metal,
  the GPU device id and Metal version; for CUDA, the cuDNN version, cuBLAS
  version, CUDA driver version, GPU compute capability; for oneDNN, the
  detected ISA (AVX2 / AVX-512), oneDNN version, glibc version.
- The three per-substrate engine modules expose stub `instance HasEngine
  env` skeletons that Sprints `7.3`–`7.5` populate.

### Validation

1. `cabal build all` succeeds with the engine ABI.
2. `jitml-unit` exercises the engine envelope golden under a synthetic
   per-substrate fingerprint.

## Sprint 7.3: Linux CPU Engine and oneDNN Codegen Driver ⏸️

**Status**: Blocked
**Blocked by**: 7.2
**Implementation**: `src/JitML/Engines/LinuxCPU.hs`, `codegen-onednn/`,
`src/JitML/Codegen/OneDnn.hs`
**Docs to update**: `documents/engineering/jit_codegen_architecture.md`,
`documents/engineering/determinism_contract.md`

### Objective

Land the `linux-cpu` engine: oneDNN graph wrappers, AVX2 baseline with
AVX-512 detected at JIT time, blocked reduction with fixed block size for
deterministic float-accumulation order.

### Deliverables

- `codegen-onednn/` carries oneDNN graph templates and the JIT driver that
  emits a `.so` artefact per `KernelSpec`.
- `src/JitML/Codegen/OneDnn.hs` invokes the codegen driver through the typed
  `Subprocess` boundary; the produced `.so` is written atomically to
  `./.build/jit/linux-cpu/<hash>.so`.
- Block size is pinned per layer family so reductions are host-independent;
  the value is part of `ToolchainFingerprint`.
- `LinuxCPU.HasEngine` instance loads the `.so` via the FFI loader and binds
  the engine ABI from Sprint `7.2`.

### Validation

1. Two same-host runs produce bit-identical reduction outputs (matches the
   per-substrate determinism contract).
2. `jitml-cross-backend` exercises the AVX2 baseline behaviour on hosts
   without AVX-512.

## Sprint 7.4: Linux CUDA Engine and CUDA Codegen Driver ⏸️

**Status**: Blocked
**Blocked by**: 7.2
**Implementation**: `src/JitML/Engines/LinuxCUDA.hs`, `codegen-cuda/`,
`src/JitML/Codegen/Cuda.hs`
**Docs to update**: `documents/engineering/jit_codegen_architecture.md`,
`documents/engineering/determinism_contract.md`

### Objective

Land the `linux-cuda` engine: CUDA C codegen, cuBLAS / cuDNN bindings, with
`--use_fast_math=false`, deterministic warp-shuffle reductions, cuDNN
`cudnnSetConvolutionMathType` plus explicit algorithm-id pinning, and
splitmix RNG (never the GPU's curand).

### Deliverables

- `codegen-cuda/` carries CUDA kernel templates and the JIT driver that
  emits a `.so` per `KernelSpec`. NVCC is invoked through the typed
  `Subprocess` boundary with the doctrine-pinned `--use_fast_math=false`
  and baseline `sm_70`.
- `src/JitML/Codegen/Cuda.hs` writes the produced `.so` atomically to
  `./.build/jit/linux-cuda/<hash>.so`.
- cuBLAS / cuDNN are pinned to deterministic algorithm selections.
- `LinuxCUDA.HasEngine` instance loads the `.so` via the FFI loader, binds
  the engine ABI, captures the engine envelope (cuDNN version, cuBLAS
  version, driver, GPU compute capability).

### Validation

1. Two same-host same-GPU runs produce bit-identical training transcripts
   for the canonical SL workload.
2. `jitml-cross-backend` asserts cross-substrate drift versus the
   `linux-cpu` engine fits inside the per-tensor tolerance band per
   [../documents/engineering/determinism_contract.md](../documents/engineering/determinism_contract.md).

## Sprint 7.5: Apple Silicon Engine, Metal Codegen, Hybrid Host↔Cluster RPC ⏸️

**Status**: Blocked
**Blocked by**: 7.2, 2.5, 5.5
**Implementation**: `src/JitML/Engines/AppleSilicon.hs`, `codegen-metal/`,
`src/JitML/Codegen/Metal.hs`, `src/JitML/Service/InferenceProxy.hs`
**Docs to update**: `documents/engineering/jit_codegen_architecture.md`,
`documents/engineering/determinism_contract.md`,
`documents/engineering/daemon_architecture.md`

### Objective

Land the `apple-silicon` engine: Swift + Metal codegen running inside the
`jitml-build` tart VM, single-stream kernel launch for deterministic
accumulation order, the host daemon FFI surface, and the cluster↔host RPC
envelope on `inference.command.apple-silicon` /
`inference.event.apple-silicon`.

### Deliverables

- `codegen-metal/` carries Swift / Metal kernel templates plus the JIT
  driver. The driver runs inside the `jitml-build` tart VM via `tart ssh`
  (Sprint `2.5`); the produced `.dylib` is copied atomically to
  `./.build/jit/apple-silicon/<hash>.dylib` and the stable-FFI symlink at
  `./.build/host/apple-silicon/<model-id>.dylib` is repointed.
- `AppleSilicon.HasEngine` instance loads the `.dylib` via the FFI loader.
- Metal kernels launch in a single MTLCommandQueue with FIFO ordering
  (single-stream); explicit barriers prevent kernel reordering.
- The clustered daemon (Dhall: `Cluster + ForwardToHost`) runs the
  `InferenceProxy`, which:
  - On `inference.request.apple-silicon`, reads the model snapshot from
    MinIO, publishes an `inference.command.apple-silicon` envelope per
    [system-components.md → Pulsar Topic
    Family](system-components.md#pulsar-topic-family),
  - Awaits the `inference.event.apple-silicon` ACK from the host daemon,
  - Republishes on `inference.result.apple-silicon` to the demo frontend.
- The host daemon (Dhall: `Host + SelfInference`) subscribes to
  `inference.command.apple-silicon`, executes the kernel via Metal, writes
  large outputs directly to MinIO, and ACKs on
  `inference.event.apple-silicon` with the small envelope (call-id, kind
  tag, MinIO refs).
- Direct k8s API access from the host daemon is hlint-forbidden.

### Validation

1. From a clean state, the first host-side cache miss spins tart up;
   subsequent misses reuse the running VM.
2. The host↔cluster RPC roundtrip on a synthetic inference request
   completes within the `LiveConfig.inferenceMaxLatencyMillis` budget.
3. `purge` destroys the VM but preserves `./.build/jit/apple-silicon/`; a
   subsequent inference command resolves from cache without spinning tart
   up.

## Sprint 7.6: Hardware Auto-Tuning Within the Determinism Contract ⏸️

**Status**: Blocked
**Blocked by**: 7.3, 7.4, 7.5
**Implementation**: `src/JitML/Codegen/AutoTune.hs`,
`src/JitML/Codegen/AutoTune/Strategy.hs`
**Docs to update**: `documents/engineering/jit_codegen_architecture.md`,
`documents/engineering/determinism_contract.md`

### Objective

Choose among reduction strategies, tile sizes, and prefetch widths per
substrate while preserving the determinism contract. Auto-tuning produces a
typed `TuningChoice` baked into `ToolchainFingerprint` so cache invalidation
is automatic.

### Deliverables

- `TuningChoice` ADT enumerating per-substrate knob spaces (Metal: workgroup
  size, threadgroup memory; oneDNN: block size variants under the fixed
  block-reduction discipline; CUDA: tile size, warp-shuffle pattern, cuDNN
  algorithm id from the deterministic-only set).
- `AutoTune` runs at JIT time on a cache miss, picks a `TuningChoice` per
  `KernelSpec` based on a per-substrate strategy (latency-vs-throughput
  trade-off, with a default that prioritises bit-determinism).
- The chosen `TuningChoice` is folded into `ToolchainFingerprint`; a knob
  change invalidates the cache key.
- The cuDNN algorithm-id selection is restricted to the deterministic-only
  set; the `--use_fast_math=false` invariant is preserved.

### Validation

1. A `TuningChoice` change produces a different `cacheKey` (golden test).
2. The same `(KernelSpec, kind, substrate, ToolchainFingerprint)` tuple
   produces bit-identical kernel output across two same-host runs.

## Doctrine Sections Cited

- [../HASKELL_CLI_TOOL.md → Architecture → Subprocesses as Typed Values](../HASKELL_CLI_TOOL.md) (Sprints 7.3, 7.4, 7.5)
- [../HASKELL_CLI_TOOL.md → Capability Classes and Service Errors](../HASKELL_CLI_TOOL.md) (Sprint 7.5 — `HasMinIO`/`HasPulsar` consumers)
- [../HASKELL_CLI_TOOL.md → Long-Running Daemons in the Same Binary](../HASKELL_CLI_TOOL.md) (Sprint 7.5 — host/cluster split)
- [../HASKELL_CLI_TOOL.md → At-Least-Once Event Processing](../HASKELL_CLI_TOOL.md) (Sprint 7.5 — host↔cluster RPC envelope)
- [../HASKELL_CLI_TOOL.md → Toolchain pinning](../HASKELL_CLI_TOOL.md) (Sprints 7.3, 7.4, 7.5)

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/jit_codegen_architecture.md` — populate with
  `KernelSpec`, the cache key derivation, the per-substrate codegen
  drivers, the FFI loader, the Apple hybrid pattern, the host↔cluster RPC
  envelope, and the auto-tuning surface.
- `documents/engineering/determinism_contract.md` — populate with the per-
  substrate floating-point semantics (Metal single-stream, oneDNN blocked
  reduction, CUDA warp-shuffle + `--use_fast_math=false` + cuDNN explicit
  algorithm-id pinning), the engine envelope shape, the cross-substrate
  tolerance methodology.
- `documents/engineering/daemon_architecture.md` — link to the
  `InferenceProxy` Apple-only surface.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- `system-components.md → JIT Codegen Components` and `Substrates` rows
  move from `⏸️ Blocked` through `🔄 Active` to `✅ Done`.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [development_plan_standards.md](development_plan_standards.md)
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
