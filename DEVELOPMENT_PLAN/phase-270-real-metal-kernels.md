# Phase 270: Real Metal Kernels

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Real Metal Kernels. Single-session phase migrated from legacy Sprint 30.1 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

🔄 **Active** (2026-08-12). Reopened: this sprint's deliverable requires the unweighted
family bodies to render real per-operation MSL with no identity-class elementwise
copy, and requires misleading comments to be corrected. The shipped unweighted
multi-head-attention body renders an elementwise square, and comments still describe
an explicit identity GEMM and a unit-centre filter.

## Sprint 270.1: Real Metal Kernels [🔄 Active]

**Status**: Active
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
./bootstrap/apple-silicon.sh doctor
PATH=/opt/homebrew/opt/llvm@19/bin:$PATH cabal build test:jitml-backends test:jitml-e2e test:jitml-unit
PATH=/opt/homebrew/opt/llvm@19/bin:$PATH cabal test jitml-backends --test-show-details=direct --test-options='-p apple-silicon'
```

2026-07-06 closing validation: `./bootstrap/apple-silicon.sh doctor` passed;
`PATH=/opt/homebrew/opt/llvm@19/bin:$PATH cabal run exe:jitml -- internal
install-metal-bridge` built the fixed bridge and reported `metal_bridge_probe:
ok`; the focused rendered-source guard passed **1 / 1**; the multi-tap Metal
Conv2D/Conv3D runtime test passed **1 / 1**; and the full
`apple-silicon` backend lane passed **20 / 20**.

### Historical Validation

- **Closed Exit-Definition obligation**: the generic Metal family bodies in
  `src/JitML/Codegen/Metal.hs` must be real per-operation MSL — windowed
  Conv2D/Conv3D, multi-head attention, pooling, and BatchNorm/LayerNorm — with no
  identity-copy or 1x1-degenerate body reachable on any product family, rendered on
  demand and compiled in-process by the fixed host Metal bridge with fast math
  disabled.
- **Closing validation**: the identity-copy / degenerate-kernel differential
  controls in the `jitml-negative-controls` stanza (Phase `32`,
  [phase-32-external-truth-realness-harness.md](README.md#legacy-to-new-phase-map))
  must reject the current Metal generic-family stand-ins, exercised via
  `docker compose run --rm jitml jitml test jitml-negative-controls --linux-cpu`,
  and the Metal backend re-run must pass on the real lane via
  `PATH=/opt/homebrew/opt/llvm@19/bin:$PATH cabal test jitml-backends --test-options='-p apple-silicon'`
  — `apple-silicon` plus `linux-cpu` only, never `linux-cuda` in the same gate.

### Remaining Work

- Render the unweighted attention family against the shared semantics contract from
  Sprint `84.1`; close the weighted-family wildcard.
- Correct the remaining identity-class comments.
- Implement the Metal arm of the total lowering so the typed layer graph executes on
  the host GPU rather than through the pure executor.

### Historical Phase State

> ✅ **Done**.

*(Retained as historical evidence for the surface it exercised; superseded by the 2026-08-12 reopen above.)*

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
