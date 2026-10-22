# Phase 279: Measured/Declared Type Split & Behavioral Scaffold Lint

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Measured/Declared Type Split & Behavioral Scaffold Lint. Single-session phase migrated from legacy Sprint 32.3 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

⏸️ **Blocked**. Blocked by Phase 278 (Sprint 278.1).

Reopened under standards rule `C` on 2026-10-15. The current opaque metric,
completion and projection types retain meaningful declaration/evidence
boundaries, and realized graphs enforce architecture claims. The promised
behavioral scaffold detector remains unmet: `ProductTruth.hs` scans a finite
registry of names and substrings. It does not establish that a newly named
product function's output depends on trained weights. Phase `225` explicitly
transfers that obligation here; no equivalent supersession is identified.
Phase `278` remains the first executable owner. This status correction starts
no Phase `279` feature work. The forward allocation below additionally assigns
the fresh CUDA lane to this phase and the aggregate/unchanged full CPU unit and
integration gates to Phase `280`; the status correction itself supplied no
execution evidence.

## Sprint 279.1: Measured/Declared Type Split & Behavioral Scaffold Lint [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Sprint `278.1`
**Implementation**: `src/JitML/Product/Matrix.hs`, `src/JitML/Lint/ProductTruth.hs`, `src/JitML/Test/Report.hs`, `src/JitML/Web/Contracts.hs`, `test/unit/Main.hs`
**Docs to update**: `../documents/engineering/product_completion_contract.md`, `../documents/engineering/purescript_frontend.md`, `system-components.md`

### Objective

A stand-in is typed `Declared` and cannot be reported as real; the scaffold lint is a
behavioral detector, not a name denylist. This phase also owns the complete
current CUDA lane under Phase `278`'s independently validated qualification
contracts. It closes on one real NVIDIA host with Docker CPU.

### Deliverables

- A `Measured` vs `Declared` metric type and a `RealArchitecture` vs `MlpApproximation`
  distinction carried on `ProductRow`, surfaced in the report card and demo so an
  approximate row is visibly marked.
- The scaffold lint asks "does this product function's output depend on the trained
  weights?" rather than matching fossil names; the `FutureOwner` exemption is deleted.

- Issue and admit the complete current 55-row CUDA journal with authenticated
  qualification objects, actual prescribed training runs, exact served-index-zero
  admission, unchanged per-run budgets and exhaustive all-attempt retention.
- Validate the genuine CUDA backend gate and complete CPU local-control gate,
  preserving the separate behavioral output-dependence detector obligation.

### Lane Acquisition Commands

This complete 55-row acquisition satisfies the owned CUDA lane-journal
requirement using the exact ProductScenario subtree. It requires the real CUDA
cluster and all twelve staged datasets. It is not an unfiltered integration
standing pass; that unchanged full CPU gate remains owned by Phase `280`.

```bash
docker compose run --rm jitml-cuda jitml test jitml-integration --linux-cuda --test-options='-p "Phase 261 ProductRow contract-driven integration matrix"'
```

### Validation

```bash
docker compose run --rm jitml-cuda jitml test jitml-backends --linux-cuda
docker compose run --rm jitml jitml test jitml-negative-controls --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Closure Evidence

The historical closure claimed both the type split and behavioral lint without
retaining a renamed-fake behavioral proof. Current opaque completion, measured
metric and graph-claim controls support their own typed surfaces; the fossil
scanner and its passing tests cannot establish the stronger behavioral claim.
The former Done assertion remains historical and does not close this reopened
obligation.

### Remaining Work

- Close Sprint `278.1` before implementing this phase's remaining detector.
- Implement product-reachable output-dependence analysis that rejects a newly
  named function which ignores its trained-weight input. Validate the precise
  rejection and a corresponding weight-dependent positive, including helper,
  alias and import indirection, without rejecting unrelated utilities. The
  deleted `FutureOwner` exemption stays absent; renaming a fake cannot bypass
  the detector.
- Preserve the existing opaque metric/completion and graph-claim boundaries,
  with positive and adversarial controls for their modern representations.
  Historical constructor names alone do not decide whether those protections
  remain equivalent.
- After Sprint `278.1` validates, prospectively bind the actual CUDA allocation,
  current source/executable and immutable artifact publication, retaining all
  previous inspected attempts and complete finite failures. Execute and admit
  the entire current lane; a filtered acquisition is not a full integration pass.
- Run the complete Validation commands on the finished implementation. Replace
  the explicit unproven behavioral-detector context with machine-observable
  validation only alongside the actual implementation and controls. Phase `280`
  owns the unchanged full CPU unit and integration passes after admitting the
  three earlier lanes. Global standing requirements remain unchanged; no old
  record is repinned or upgraded to current execution.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
