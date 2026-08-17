# Phase 80: Linux CPU Engine and oneDNN Codegen Driver

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Linux CPU Engine and oneDNN Codegen Driver. Single-session phase migrated from legacy Sprint 7.3 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done** (closed 2026-08-14). The weighted-family renderer is total: a tenth
`KernelFamily` fails the build rather than rendering a weights-discarding
passthrough, and `Identity` / `Reduction` are named explicitly because their
canonical no-op weight buffer is genuinely empty. The unweighted multi-head
attention divergence is resolved in favour of the algebra the contract implies:
`JitML.Numerics.FamilyReference.defaultFamilyWeights` defines each family's
canonical no-op weights, the unweighted reference is the weighted reference
evaluated at them, and at `Wq = Wk = Wv = I` the attention algebra degenerates
to `out[i] = input[i]^2` — which is what `linux-cuda` and `apple-silicon`
already rendered and what `linux-cpu` did not. The backends lane now checks the
unweighted ABI against that contract for every family instead of smoke-asserting
it, which is the gap that let the divergence survive.

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

### Closure Evidence

Closed 2026-08-14 from one source state, inside `jitml:local`:

- `jitml lint haskell` → `ok`.
- `jitml docs check` → `ok`.
- `jitml test jitml-unit --linux-cpu` → **873 / 873 passed**, including the
  three-case "Kernel-family semantics contract (Phase 80)" group.
- `jitml test jitml-backends --linux-cpu` → the unweighted ABI checked against
  the contract for all nine families through the real oneDNN kernels.
- `jitml check-code` → `ok`.

### Completed in this sprint

- `src/JitML/Numerics/FamilyReference.hs`: `defaultFamilyWeights` — the
  canonical no-op weights per family, total over `KernelFamily` — plus
  `unweightedFamilyReference`, which is *defined* as the weighted reference at
  those defaults. The unweighted ABI therefore has no independent definition to
  drift from. This is the shared semantics contract Sprint `84.1` enforces
  across all three renderers; it lands here because Sprint `80.1` cannot fix its
  own arm without it.
- `src/JitML/Codegen/OneDnn.hs`: `familyImpl MultiHeadAttentionKernel` rendered
  `jitml_onednn_dense_identity` — the input unchanged. It now calls a new
  `jitml_onednn_mha_unit`, which builds identity `Wq`/`Wk`/`Wv` and delegates to
  `jitml_onednn_mha_weighted`, so the generated source expresses the same
  "unweighted is weighted at no-op weights" law the oracle does and cannot drift
  from it either.
- `weightedFamilyCall`'s `_` wildcard and `kernelOutputCountFunction`'s `_`
  wildcard are both replaced by explicit per-family arms.
- `test/backends/Main.hs`: `assertFamilySmoke`'s length/finiteness check is
  replaced by `assertUnweightedMatchesContract` against the contract, for every
  family on the real device.

The matching wildcards on the CUDA and Metal renderers, and the second
divergence the contract exposes — the unweighted `Reduction` output shape, one
scalar on oneDNN versus unsummed partials on CUDA and Metal — are Sprint
`84.1`'s to close across all three lanes.

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
