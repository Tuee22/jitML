# Phase 30: apple-silicon Product Lane

**Status**: Blocked
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [development_plan_standards.md](development_plan_standards.md), [phase-29-linux-cuda-product-lane.md](phase-29-linux-cuda-product-lane.md), [phase-31-no-caveat-product-aggregation.md](phase-31-no-caveat-product-aggregation.md), [../documents/engineering/product_completion_contract.md](../documents/engineering/product_completion_contract.md), [../documents/engineering/apple_silicon_metal_headless_builds.md](../documents/engineering/apple_silicon_metal_headless_builds.md), [../documents/engineering/jit_codegen_architecture.md](../documents/engineering/jit_codegen_architecture.md)
**Generated sections**: none

> **Purpose**: Implement the real Metal conv/attention/pool/norm kernels through
> the fixed host Metal bridge and validate the row-complete product matrix on the
> real `apple-silicon` substrate without requiring `linux-cuda` in the same phase.

## Phase State

⏸️ **Blocked by** Phase `29`.

**Validation substrate**: `linux-cpu` plus `apple-silicon`; no `linux-cuda`
validation is part of this phase.

## Objective

Every product row validated on `linux-cpu` also runs on the real Apple Metal lane
where `apple-silicon` is supported, and the Metal kernels it dispatches are the
real per-operation kernels rather than stand-ins. The unweighted family kernels
are true per-operation Metal Shading Language (conv, attention, pool, norm)
instead of the current identity-class elementwise copies, and Conv2D/Conv3D are
their real windowed convolutions instead of the current degenerate 1x1 weighted
compute. Every kernel is rendered on demand and compiled in-process by the fixed
host Metal bridge through `MTLDevice.makeLibrary(source:options:)` with fast math
disabled; no Metal source is checked in as a ready-to-run kernel file. Apple
validation proves host-daemon routing, Metal runtime probes, on-demand
compile/load/dispatch, trained-state updates, completed checkpoints, demo
rendering, integration coverage, and e2e coverage for the same product matrix,
and the committed `apple-silicon` attestation records that evidence per row.

## Sprint 30.1: Real Metal Kernels [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Phase `29`
**Implementation**: `src/JitML/Codegen/Metal.hs`, `src/JitML/Engines/MetalLocal.hs`, `src/JitML/Engines/MetalBridge.hs`, `test/backends/Main.hs`
**Docs to update**: `../documents/engineering/jit_codegen_architecture.md`, `../documents/engineering/apple_silicon_metal_headless_builds.md`

### Objective

`src/JitML/Codegen/Metal.hs` renders real per-operation Metal Shading Language
for every kernel family, replacing the identity-class elementwise copy in the
unweighted body and the degenerate 1x1 weighted compute for Conv2D/Conv3D. The
`src/JitML/Engines/MetalLocal.hs` launch path dispatches these kernels through the
fixed host bridge `src/JitML/Engines/MetalBridge.hs`, which compiles the rendered
source in-process via `MTLDevice.makeLibrary(source:options:)` with fast math
disabled and runs on the host GPU.

### Deliverables

- The unweighted family bodies in `src/JitML/Codegen/Metal.hs` render real
  per-operation MSL — windowed Conv2D/Conv3D, multi-head attention, pooling, and
  BatchNorm/LayerNorm normalization — mirroring the CUDA `weightedFamilyImpl`
  math, so no product-family kernel is an identity elementwise copy.
- `conv1x1WeightedCompute` is replaced by real windowed convolution over the
  input's spatial neighbourhood and filter bank for Conv2D and Conv3D; the 1x1
  degenerate path is removed from the product families (or dispatched to MPS where
  a hardware primitive is the appropriate real implementation).
- The rendered kernels carry correct launch metadata (threadgroup sizing, grid
  extents, weight/bias layout) into `<hash>.metal.json`, and
  `src/JitML/Engines/MetalBridge.hs` compiles them in-process with fast math
  disabled; no Metal kernel is checked in as a ready-to-run source file.
- Misleading comments in `src/JitML/Codegen/Metal.hs` that describe the copy-only
  or 1x1 stand-ins (for example the "Identity-class elementwise copy" and 1x1
  convolution notes) are corrected to describe the real kernels.
- `test/backends/Main.hs` asserts each family produces the numerically correct
  output versus a host reference and fails if a family regresses to an
  identity-copy or 1x1-degenerate result.

### Validation

```bash
jitml test jitml-backends --apple-silicon
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml check-code
```

### Remaining Work

- Render real conv/attention/pool/norm MSL for every product family and remove the
  identity-copy and 1x1-degenerate paths.
- Add the numeric-correctness and no-identity-regression backend assertions.
- Correct the stale copy-only and 1x1 comments in the Metal renderer.

## Sprint 30.2: Metal Row Device Evidence [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Sprint `30.1`
**Implementation**: `src/JitML/Product/Matrix.hs`, `test/backends/Main.hs`
**Docs to update**: `../documents/engineering/apple_silicon_metal_headless_builds.md`, `../documents/engineering/jit_codegen_architecture.md`

### Objective

Every `apple-silicon`-supported product row records real Metal device evidence
that the row's update-critical kernels compiled and dispatched on the host GPU
through the fixed bridge. Runtime absence fails up front, and no Apple row is
scheduled into a Linux pod as fake evidence.

### Deliverables

- Every `apple-silicon`-supported `ProductRow` records Metal `deviceEvidence`
  naming the Metal device and the compiled-and-dispatched update-critical kernels
  for that row.
- Absence of a Metal-capable GPU or the host Metal runtime fails the lane up front
  with a named error; no Apple row passes vacuously and no row is marked supported
  without real device evidence.
- No Apple product row is scheduled onto a Linux pod or `linux-cpu` engine as a
  substitute for Metal device evidence; the matrix classifies such a row as
  unsupported on this lane rather than counting host-only execution as proof.
- The report distinguishes unsupported rows from failed supported rows and pins
  each supported row's device evidence to the real bridge compile/dispatch.

### Validation

```bash
jitml test jitml-backends --apple-silicon
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml check-code
```

### Remaining Work

- Add Metal per-row device-evidence collection to `src/JitML/Product/Matrix.hs`.
- Add the runtime-absence fail-fast and the Linux-pod-substitution rejection
  tests to `test/backends/Main.hs`.

## Sprint 30.3: Apple Integration, E2E, and Attestation [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Sprint `30.2`
**Implementation**: `test/integration/Main.hs`, `test/e2e/Main.hs`, `playwright/jitml-demo.spec.ts`, `DEVELOPMENT_PLAN/attestations/`
**Docs to update**: `../documents/engineering/unit_testing_policy.md`, `../documents/engineering/purescript_frontend.md`

### Objective

`jitml test all --apple-silicon` runs every Apple-supported product row for real
on the Mac host, live Playwright hits the Apple edge and renders row-specific
trained artifacts, and the committed `apple-silicon` attestation records the
row-complete evidence for the lane.

### Deliverables

- `jitml test all --apple-silicon` runs every Apple-supported product row for real
  on the Mac host: real training/RL/tune/inference through host-daemon routing
  that fails closed if the host daemon or Metal runtime is absent.
- Live Playwright (`playwright/jitml-demo.spec.ts`) hits the Apple edge and
  renders row-specific trained artifacts, never a fake browser runtime or static
  generated row-name list.
- The `apple-silicon` report card includes row ids, Metal device evidence,
  integration evidence, and e2e evidence, distinguishing unsupported rows from
  failed supported rows.
- The refreshed `apple-silicon` attestation is committed under
  `DEVELOPMENT_PLAN/attestations/` for the aggregation phase to consume.

### Validation

```bash
jitml test all --apple-silicon
jitml test jitml-e2e --apple-silicon
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Remaining Work

- Run and fix the Apple product matrix across integration and e2e.
- Add the host-routing fail-closed negative cases for a missing daemon or Metal
  runtime.
- Commit the refreshed `apple-silicon` attestation after validation.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/apple_silicon_metal_headless_builds.md` — real per-operation
  Metal kernels rendered on demand and compiled in-process by the fixed host
  bridge, replacing the identity-copy and 1x1-degenerate stand-ins.
- `documents/engineering/jit_codegen_architecture.md` — the real Metal
  conv/attention/pool/norm renderers and their launch metadata.
- `documents/engineering/unit_testing_policy.md` — ownership of the Apple
  per-row device-evidence, integration, and e2e tests.
- `documents/engineering/purescript_frontend.md` — live Apple-edge rendering of
  row-specific trained artifacts.

**Product docs to create/update:**
- `README.md` — current product status after the `apple-silicon` lane validates.

**Cross-references to add:**
- Link the committed `apple-silicon` attestation from Phase `31`.
