# Phase 271: Metal Row Device Evidence

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Metal Row Device Evidence. Single-session phase migrated from legacy Sprint 30.2 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

🔄 **Active** (2026-08-12). Reopened under standards rule `C`, for the same reason as
Sprint `265.1`: the recorded Metal device evidence is composed from the declared
substrate and claim, and supervised rows on this lane execute oneDNN kernels rather
than the fixed bridge. Prior evidence stays historical for the surface it
exercised.

## Sprint 271.1: Metal Row Device Evidence [🔄 Active]

**Status**: Active
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

### 2026-08-24 Pause Checkpoint

The Phase `270` fixed-bridge layer-training implementation is now available to
mint the execution witnesses this phase requires. Validation completed before
this session paused:

- `./bootstrap/apple-silicon.sh doctor` passed.
- `jitml-backends` passed **21 / 21** on `apple-silicon`, including the
  all-operator fixed-bridge layer-training oracle.
- `jitml-e2e` passed **30 / 30**.
- `./bootstrap/apple-silicon.sh up` completed its **111-step** live rollout.
  The image build passed the container-only `jitml check-code` gate, and the
  live status reported registry, MinIO, Pulsar, observability, coordinator,
  demo, and edge all Ready.
- Ten of the twelve canonical dataset objects were SHA-verified and staged:
  MNIST and Fashion-MNIST train/test images and labels, Tiny ImageNet, and
  California Housing. The canonical CIFAR-100 archive was also downloaded and
  verified locally as
  `58a81ae192c23a4be8b1804d68e518ed807d710a4eb253b1f2a199162a40d8ec`,
  but was not staged before the pause. The CIFAR-10 transfer is incomplete and
  its partial file is not evidence.

No product-row publisher run was started, so this phase remains **Active** and
no row-complete claim is made. At the user's pause request all active transfers
were stopped and `./bootstrap/apple-silicon.sh down` deleted the two-node Kind
cluster. A continuation must recreate the publication and re-stage all twelve
objects before running the 55-row publisher.

2026-07-06 closing validation: the `apple-silicon` backend lane proves Metal
runtime absence fails before product-row evidence is accepted, and the real
windowed kernels compile and dispatch through the fixed bridge on the host GPU.
The row-complete attestation is preserved as the Phase `30` lane fragment, but
final product aggregation remains blocked by Phase `29`.

### Historical Validation

- **Closed Exit-Definition obligation**: every `apple-silicon`-supported product row
  must record real Metal device evidence for the row's real per-operation
  update-critical kernels and a genuinely trained model, not aggregated fabricated
  per-row eligibility over identity-copy kernels; runtime absence must still fail
  the lane up front.
- **Closing validation**: the per-model `jitml-model-convergence` suite (Phase `33`,
  [phase-33-per-model-convergence-and-inference-tests.md](README.md#legacy-to-new-phase-map))
  must train every `ProductRow` for real through the production device seam and
  clear its external bar, and the fabricated-evidence controls in the
  `jitml-negative-controls` stanza (Phase `32`,
  [phase-32-external-truth-realness-harness.md](README.md#legacy-to-new-phase-map))
  must reject the withdrawn device evidence — exercised via
  `docker compose run --rm jitml jitml test jitml-model-convergence --linux-cpu`
  and `docker compose run --rm jitml jitml test jitml-negative-controls --linux-cpu`,
  before the Metal row evidence is re-minted on the `apple-silicon` lane
  (`apple-silicon` plus `linux-cpu` only, never `linux-cuda`).

### Remaining Work

- Finish and SHA-verify the canonical CIFAR-10 archive download.
- Recreate the Apple publication and re-stage all twelve canonical dataset
  objects; the paused cluster was deliberately deleted.
- Run `jitml internal train-and-publish-product-rows --apple-silicon` and require
  `rows: 55`, `eligible: 55`, `unsupported: 0`, and `errors: 0`, with each
  supported row's admitted manifest carrying its execution-derived Metal
  witness.
- Re-run the validation block on the final source and record the measured
  result before changing this phase to `Done`.

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
