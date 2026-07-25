# Phase 80: Linux CPU Engine and oneDNN Codegen Driver

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Linux CPU Engine and oneDNN Codegen Driver. Single-session phase migrated from legacy Sprint 7.3 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 80.1: Linux CPU Engine and oneDNN Codegen Driver [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Engines/Engine.hs`,
`src/JitML/Engines/HasEngine.hs`, `src/JitML/Engines/Loader.hs`,
`src/JitML/Engines/Local.hs`, `src/JitML/Engines/OneDnnRuntime.hs`,
`src/JitML/Codegen/OneDnn.hs`, `docker/Dockerfile`
**Docs to update**: `documents/engineering/jit_codegen_architecture.md`,
`documents/engineering/determinism_contract.md`

### Objective

Land the `linux-cpu` engine metadata, generated oneDNN-style C++ source
renderer, and first same-host compile/load/run path for the generated
identity kernel; grow the path into libdnnl-linked oneDNN primitive launches
behind the local production `HasEngine` execution surface.

### Deliverables

- `engineForSubstrate LinuxCPU` records backend `onednn` and artifact
  extension `.so`.
- `renderOneDnnSource` emits generated `kernel.cc` source with oneDNN C++
  headers, a fixed local reduction-block constant, and the exported
  `jitml_kernel_family_name` metadata symbol plus `jitml_kernel_output_count`
  for family-specific output length reporting.
- `docker/Dockerfile` installs `libdnnl-dev`, and `compileSubprocess` renders
  the `g++ -std=c++20 -O2 -fPIC -shared ... -ldnnl` command against the
  generated source directory.
- `JitML.Engines.Local` routes generated Linux CPU source through
  `JitML.Engines.Loader.ensureKernelArtifact`, loads `jitml_kernel` with the
  shared `withKernelSymbol` helper, loads `jitml_kernel_family_name` and
  `jitml_kernel_output_count`, and executes a deterministic identity fixture
  through the Haskell FFI while recording the family reported by the artifact
  and reading exactly the output count reported by the artifact.
- `JitML.Engines.Local.linuxCpuToolchainFingerprint` includes the local
  `artifact-abi=<os>-<arch>` plus `reduction-block=256` in the cache-key
  input so host/container loader ABIs and fixed reduction-block changes do not
  share a Linux CPU artifact path. `jitml build` uses that fingerprint for
  `--substrate linux-cpu` cache-key selection.
- `renderOneDnnFamilySource` extends the local renderer to emit
  `identity`, `reduction`, `dense`, `conv2d`, `conv3d`, `batchnorm`,
  `layernorm`, `mha`, and `embedding` family kernels backed by oneDNN C++
  primitive launches under the current flat fixture ABI: reorder for
  identity/embedding, reduction for reduction, matmul for dense and MHA,
  unit 2D/3D convolution for convolution families, and oneDNN
  batch/layer-normalization primitives for normalization families. The kernel
  family and tuning metadata remain embedded in the generated source payload.
- `JitML.Engines.Local.runLinuxCpuFamilyKernel` materializes, compiles, loads,
  and executes each generated oneDNN family kernel through the same
  cache-artifact loader and FFI symbol boundary, validating the reported family
  name and family-specific output length against the requested `KernelFamily`
  in `jitml-cross-backend`.
- `JitML.Engines.HasEngine` defines `EngineRequest`, `EngineRun`, and the
  `HasEngine` class plus a `LocalLinuxCpuEngine` interpreter. `runLinuxCpuEngine`
  dispatches requested `KernelFamily` values through the generated-family FFI
  path and rejects any loaded artifact whose exported
  `jitml_kernel_family_name` differs from the request.
- `JitML.Engines.OneDnnRuntime.probeOneDnnRuntime` establishes the typed
  `libdnnl` runtime/link availability boundary: it probes
  `pkg-config --modversion dnnl`, `pkg-config --modversion onednn`, readable
  oneDNN headers at `/usr/include/oneapi/dnnl/dnnl.hpp` /
  `/usr/include/dnnl.hpp`, and `ldconfig -p` through typed subprocesses,
  renders the selected package/header/library visibility, and reports
  availability when either package metadata or headers plus dynamic-linker
  `libdnnl` visibility are present.
- `JitML.Service.Workload` exposes an injectable checkpoint inference runner,
  `JitML.Service.Runtime.daemonWorkloadDispatcherWithInference` threads that
  runner through parsed `RunInference` workload effects and inference-domain
  command envelopes, and `jitml service` selects
  `JitML.Engines.Local.runLinuxCpuCheckpointInference` for
  `linux-cpu` + `SelfInference` daemon configs. This wires the Linux CPU
  service path to the generated-kernel FFI runner after the latest pointer and
  manifest are loaded from MinIO.
- The local Linux CPU path is the first production engine interpreter. Future
  model-specific tensor ABI growth can pass real weight/table/QKV payloads into
  the same generated oneDNN primitive-launch boundary without changing the
  stable FFI metadata contract.

### Validation

1. `jitml build --dry-run --substrate linux-cpu` renders a
   generated-source directory and `g++ ... -ldnnl` compile plan.
2. `jitml-unit` verifies `JitML.Engines.Loader.ensureKernelArtifact`
   recognizes an existing content-addressed artifact as a cache hit and does
   not recompile it.
3. `jitml-unit` verifies the Linux CPU local toolchain fingerprint includes
   the host artifact ABI used to separate host/container cache artifacts and
   the fixed `reduction-block=256` value; revalidated on 2026-05-22 in
   `jitml:local`.
4. `cabal test jitml-cross-backend` compiles, loads, and executes the
   generated Linux CPU identity kernel through a oneDNN reorder primitive;
   revalidated on 2026-05-24 with linkable `libdnnl`.
5. `cabal test jitml-cross-backend` compiles, loads, and executes the
   generated Linux CPU reduction kernel through a oneDNN reduction primitive;
   revalidated on 2026-05-24 with linkable `libdnnl`.
6. `cabal test jitml-cross-backend` compiles, loads, and executes every
   generated Linux CPU oneDNN family kernel through
   `runLinuxCpuFamilyKernel` and checks the exported
   `jitml_kernel_family_name` and `jitml_kernel_output_count` metadata;
   revalidated on 2026-05-24 with linkable `libdnnl`.
7. `docker compose run --rm jitml cabal test jitml-cross-backend` on
   2026-05-24 validates the local Linux CPU `HasEngine` boundary dispatching
   a generated oneDNN family kernel through the same artifact loader and FFI
   metadata checks.
8. `jitml-unit` validates deterministic `JitML.Engines.CpuFeatures` parser
   fixtures for Linux AVX-512, Linux AVX2, reference fallback, Apple Silicon,
   and Intel Darwin text. `jitml-integration -p CpuFeatures` validates the
   live host probe through typed subprocesses in `jitml:local`; revalidated on
   2026-05-22.
9. `jitml-unit` validates deterministic `JitML.Engines.OneDnnRuntime`
   parser/rendering fixtures for `pkg-config` version output, readable oneDNN
   headers, and dynamic-linker `libdnnl` visibility. `docker compose run --rm
   jitml cabal test jitml-integration --test-options='-p oneDNN'` on
   2026-05-24 validates the live typed subprocess probe for CPU features plus
   linkable oneDNN runtime availability.
10. `docker compose run --rm jitml cabal test jitml-daemon-lifecycle` on
    2026-05-22 validates that the daemon workload dispatcher can inject an
    engine-backed checkpoint inference runner between MinIO manifest loading
    and Pulsar `InferenceResult` publication.
11. `docker compose run --rm jitml cabal test jitml-cross-backend` on
    2026-05-24 validates representative oneDNN reduction, matmul, and
    convolution primitive launches, plus repeated same-host bit equality under
    the local Linux CPU `HasEngine` path.

### Remaining Work

- No sprint-owned Phase `7.3` Remaining Work remains. Linux CPU tensor-parameter
  payload growth for real model weights, embedding tables, and QKV tensors can
  extend the same oneDNN primitive-launch ABI from later checkpoint/inference
  work without reopening the Linux CPU engine/codegen closure.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
