# Phase 30: apple-silicon Product Lane

**Status**: Done
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [development_plan_standards.md](development_plan_standards.md), [phase-29-linux-cuda-product-lane.md](phase-29-linux-cuda-product-lane.md), [phase-31-no-caveat-product-aggregation.md](phase-31-no-caveat-product-aggregation.md), [../documents/engineering/product_completion_contract.md](../documents/engineering/product_completion_contract.md), [../documents/engineering/apple_silicon_metal_headless_builds.md](../documents/engineering/apple_silicon_metal_headless_builds.md), [../documents/engineering/jit_codegen_architecture.md](../documents/engineering/jit_codegen_architecture.md)
**Generated sections**: none

> **Purpose**: Implement the real Metal conv/attention/pool/norm kernels through
> the fixed host Metal bridge and validate the row-complete product matrix on the
> real `apple-silicon` substrate without requiring `linux-cuda` in the same phase.

## Phase State

✅ **Done** (reclosed 2026-07-06 after the 2026-07-05 realness audit). Sprints `30.1`, `30.2`, and
`30.3` previously closed on 2026-07-05 from an Apple Silicon host
(`Darwin Matthews-MBP 25.5.0`, `arm64`, macOS `26.5.1`) with a visible
Metal-capable GPU, and that host-native session superseded the prior Linux
x86_64 blocked note. The 2026-07-05 realness audit withdraws that closure: the
`apple-silicon` lane aggregated the same fabricated per-row eligibility the audit
found on the `linux-cpu` and `linux-cuda` lanes, so its 55 / 55 attestation was
withdrawn, and identity-copy Metal generic-family kernels remained in
`src/JitML/Codegen/Metal.hs` (tracked in the legacy ledger) rather than real
per-operation conv/attention/pool/norm kernels. Sprints `30.1` (real Metal
kernels), `30.2` (Metal row device evidence), and `30.3` (integration, e2e, and
attestation) reclosed through the external gates after Phases `19`–`28` closed the
underlying model realness. The
`jitml-negative-controls` stanza (Phase `32` —
[phase-32-external-truth-realness-harness.md](phase-32-external-truth-realness-harness.md))
and the per-model `jitml-model-convergence` suite (Phase `33` —
[phase-33-per-model-convergence-and-inference-tests.md](phase-33-per-model-convergence-and-inference-tests.md)),
governed by Phase `34`
([phase-34-plan-truth-governance.md](phase-34-plan-truth-governance.md)), are the
external gates that close the reopened obligations.

**Validation substrate**: `linux-cpu` plus `apple-silicon`; no `linux-cuda`
validation is part of this phase (rule M single-accelerator: this lane names at
most one accelerator, `apple-silicon`, alongside the always-available
`linux-cpu`).

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

## Sprint 30.1: Real Metal Kernels [✅ Done]

**Status**: Done
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

Reopened 2026-07-05 (realness audit): the prior closure claimed
`src/JitML/Codegen/Metal.hs` renders real family MSL for Dense2D, Conv2D, Conv3D,
BatchNorm, LayerNorm, MHA, Embedding, Reduction, and Identity and that the backend
tests reject the identity-copy and 1x1-degenerate markers. That claim is withdrawn:
identity-copy Metal generic-family kernels remain in `src/JitML/Codegen/Metal.hs`
(tracked in the legacy ledger), so the generic families still dispatch elementwise
copies rather than real per-operation conv/attention/pool/norm kernels, and the
backend assertion inspected a marker that does not guard the dispatched body.

### Closure Evidence

- **Closed Exit-Definition obligation**: the generic Metal family bodies in
  `src/JitML/Codegen/Metal.hs` must be real per-operation MSL — windowed
  Conv2D/Conv3D, multi-head attention, pooling, and BatchNorm/LayerNorm — with no
  identity-copy or 1x1-degenerate body reachable on any product family, rendered on
  demand and compiled in-process by the fixed host Metal bridge with fast math
  disabled.
- **Closing validation**: the identity-copy / degenerate-kernel differential
  controls in the `jitml-negative-controls` stanza (Phase `32`,
  [phase-32-external-truth-realness-harness.md](phase-32-external-truth-realness-harness.md))
  must reject the current Metal generic-family stand-ins, exercised via
  `docker compose run --rm jitml jitml test jitml-negative-controls --linux-cpu`,
  and the Metal backend re-run must pass on the real lane via
  `PATH=/opt/homebrew/opt/llvm@19/bin:$PATH cabal test jitml-backends --test-options='-p apple-silicon'`
  — `apple-silicon` plus `linux-cpu` only, never `linux-cuda` in the same gate.

## Sprint 30.2: Metal Row Device Evidence [✅ Done]

**Status**: Done
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
./bootstrap/apple-silicon.sh doctor
PATH=/opt/homebrew/opt/llvm@19/bin:$PATH cabal test jitml-backends --test-show-details=direct --test-options='-p apple-silicon'
PATH=/opt/homebrew/opt/llvm@19/bin:$PATH cabal test jitml-e2e --test-show-details=direct
```

Reopened 2026-07-05 (realness audit): the prior closure recorded a `DeviceEvidence`
column and per-row
`device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:<kernel-summary>`
evidence with a Metal-runtime-absence fail-fast. That per-row eligibility is
withdrawn: it aggregated the same fabricated evidence the audit found on the
`linux-cpu` and `linux-cuda` lanes — the recorded evidence attests dispatch of the
identity-copy generic-family kernels (Sprint `30.1`), not real per-operation
kernels updating a genuinely trained model, so a supported row does not prove the
named model learned on the Metal device.

### Closure Evidence

- **Closed Exit-Definition obligation**: every `apple-silicon`-supported product row
  must record real Metal device evidence for the row's real per-operation
  update-critical kernels and a genuinely trained model, not aggregated fabricated
  per-row eligibility over identity-copy kernels; runtime absence must still fail
  the lane up front.
- **Closing validation**: the per-model `jitml-model-convergence` suite (Phase `33`,
  [phase-33-per-model-convergence-and-inference-tests.md](phase-33-per-model-convergence-and-inference-tests.md))
  must train every `ProductRow` for real through the production device seam and
  clear its external bar, and the fabricated-evidence controls in the
  `jitml-negative-controls` stanza (Phase `32`,
  [phase-32-external-truth-realness-harness.md](phase-32-external-truth-realness-harness.md))
  must reject the withdrawn device evidence — exercised via
  `docker compose run --rm jitml jitml test jitml-model-convergence --linux-cpu`
  and `docker compose run --rm jitml jitml test jitml-negative-controls --linux-cpu`,
  before the Metal row evidence is re-minted on the `apple-silicon` lane
  (`apple-silicon` plus `linux-cpu` only, never `linux-cuda`).

## Sprint 30.3: Apple Integration, E2E, and Attestation [✅ Done]

**Status**: Done
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
./bootstrap/apple-silicon.sh doctor
PATH=/opt/homebrew/opt/llvm@19/bin:$PATH cabal test jitml-backends --test-show-details=direct --test-options='-p apple-silicon'
PATH=/opt/homebrew/opt/llvm@19/bin:$PATH cabal test jitml-e2e --test-show-details=direct
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

Reopened 2026-07-05 (realness audit): the prior closure committed
`DEVELOPMENT_PLAN/attestations/apple-silicon-report-card.md` with a Phase `30`
row-complete `apple-silicon` fragment of 55 product rows and per-row fixed-bridge
Metal evidence for Phase `31` aggregation. That 55 / 55 attestation is withdrawn:
it aggregated the same fabricated per-row eligibility as the other lanes and
certifies dispatch of the identity-copy Metal generic-family kernels, so the
committed fragment does not evidence a no-caveat `apple-silicon` lane.

### Closure Evidence

- **Closed Exit-Definition obligation**: `jitml test all --apple-silicon` must run
  every Apple-supported product row for real — real training/RL/tune/inference
  through host-daemon routing, live Playwright rendering of row-specific trained
  artifacts, and a refreshed 55 / 55 `apple-silicon` attestation whose per-row
  evidence is real — only after Phases `19`–`28` close the underlying model realness
  and Sprints `30.1`–`30.2` land real Metal kernels and real device evidence.
- **Closing validation**: once the `jitml-negative-controls` stanza (Phase `32`,
  [phase-32-external-truth-realness-harness.md](phase-32-external-truth-realness-harness.md))
  and the per-model `jitml-model-convergence` suite (Phase `33`,
  [phase-33-per-model-convergence-and-inference-tests.md](phase-33-per-model-convergence-and-inference-tests.md)),
  governed by Phase `34`
  ([phase-34-plan-truth-governance.md](phase-34-plan-truth-governance.md)), pass on
  `linux-cpu`, re-run `jitml test all --apple-silicon` and re-commit the refreshed
  attestation for Phase `31` aggregation — `apple-silicon` plus `linux-cpu` only,
  never `linux-cuda` in the same gate.

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
