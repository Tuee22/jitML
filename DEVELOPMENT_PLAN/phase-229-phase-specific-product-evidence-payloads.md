# Phase 229: Phase-Specific Product Evidence Payloads

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Phase-Specific Product Evidence Payloads. Single-session phase migrated from legacy Sprint 21.4 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

🔄 **Active** (2026-08-12). Reopened: this sprint's own deliverable states that no decoder
constructs a proof-bearing value directly, but `deviceEvidenceForClaim` is a total
pure function from a declared substrate and a declared `DeviceClaim` to the device
evidence string. It performs no execution, consults no journal, and cannot fail, so
a row attests an engine that need never have run.

## Sprint 229.1: Phase-Specific Product Evidence Payloads [🔄 Active]

**Status**: Active
**Implementation**: `src/JitML/Product/Matrix.hs`,
`src/JitML/Product/Pipeline.hs`, `src/JitML/Product/Evidence.hs`,
`src/JitML/Training/Budget.hs`, `src/JitML/Checkpoint/Format.hs`,
`test/unit/Main.hs`
**Docs to update**: `../README.md`,
`../documents/engineering/product_completion_contract.md`,
`../documents/engineering/checkpoint_format.md`,
`../documents/engineering/durable_state_dsl.md`,
`../documents/engineering/run_contract.md`, `system-components.md`,
`legacy-tracking-for-deletion.md`

### Objective

Store only the payload legal for each product lifecycle state, so contradictory
optional evidence cannot be constructed even inside the module. This sprint
owns the product type-state portions of
[Exit Definition](README.md#exit-definition) items `30` and `31`.
The binding design is
[README.md → Typed run contracts](../README.md#typed-run-contracts).

### Deliverables

- Replace phase-independent records containing `Maybe` evidence with GADT or
  data-family constructors whose payload is specific to `Declared`, `Running`,
  `Completed`, and `InferenceEligible` states.
- Hide constructors for product rows, model references, training evidence,
  passing measurements, and eligibility proofs; expose total smart constructors
  and legal state transitions only.
- Remove redundant fields whose values are derivable from the state witness,
  including stored completion/pass booleans and optional manifests in completed
  states.
- Decode raw Haskell/Dhall/browser DTOs into validation errors or a legal state;
  no decoder constructs a proof-bearing value directly.
- Add compile-time legal-path fixtures and runtime negative tests for every
  invalid transition and mismatched plan/evidence pair.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml test jitml-negative-controls --linux-cpu
docker compose run --rm jitml jitml test jitml-integration --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Historical Validation

Validated on `linux-cpu` on 2026-07-22 (the refactor is pure type-level with no
runtime-path change, so it was validated from source without a cluster reload):

- **`Pipeline.ModelRef` is a hidden-constructor GADT.** `DeclaredModelRef` /
  `TrainingStartedModelRef` carry only the experiment hash;
  `TrainingCompletedModelRef` adds the completed-training witness;
  `InferenceEligibleModelRef` adds the admitted manifest SHA. The module exports
  only `ModelRef` (opaque), the smart transitions (`declareModel`,
  `startTraining`, `train`, `completeTraining`, `markInferenceEligible`), and
  total accessors — a contradictory state payload is unconstructible.
- **`Matrix.ProductRow` dropped its optional evidence.** The four
  `Maybe (EvidenceHandle state kind)` fields, the `EvidenceHandle`/`EvidenceKind`
  types, the `validateDeclaredEvidenceBoundary` projection guard, and the
  `DeclaredProductCarriesEvidence` error are removed. The former runtime
  fabrication negative control is now a compile-time impossibility (documented in
  `test/unit/Main.hs`).
- **Suites** (new code): `jitml-unit` **739 / 739**, `jitml-negative-controls`
  **3 / 3**, `jitml-model-convergence` **111 / 111**, `jitml-integration`
  **156 / 156** (runtime unchanged; live `-p Live` cases pass on the current
  cluster image). `jitml docs check` and `jitml check-code` both exited `0`
  (the `-Werror` build is clean with the retained `ProductRow` phantom), and the
  phase-status parity test agrees with the typed registry.

### Remaining Work

- Make device evidence mintable only from an execution witness returned by the
  interpreter: a hidden-constructor value carrying the engine, kernel hash, and
  artifact path recorded after a successful call.
- Remove every path that constructs device evidence from `(Substrate, DeviceClaim)`
  alone.
- Read the executed identity back from the artifact rather than asserting it; one
  substrate currently fabricates the executed family name host-side.

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
