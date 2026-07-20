# Phase 32: External-Truth Realness Harness & Negative-Control Gate

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [development_plan_standards.md](development_plan_standards.md), [phase-33-per-model-convergence-and-inference-tests.md](phase-33-per-model-convergence-and-inference-tests.md), [phase-34-plan-truth-governance.md](phase-34-plan-truth-governance.md), [../README.md](../README.md), [../documents/engineering/product_completion_contract.md](../documents/engineering/product_completion_contract.md), [../documents/engineering/unit_testing_policy.md](../documents/engineering/unit_testing_policy.md)
**Generated sections**: none

> **Purpose**: Grade "Done" against external ground truth the implementer cannot
> author or tune. Install a standing negative-control suite (known fakes must be
> rejected), frozen external convergence bars, provenance-binding controls, and a typed
> `Measured`/`Declared` split, so no future fabrication can pass a self-authored
> gate — the recurring failure mode this whole reopen exists to end.

## Phase State

⏸️ **Blocked** (reopened 2026-07-18 at Sprint `32.2`). The retained
external-bar predicate is independent, but it is not yet bound to the exact
Store-admitted manifest and exact served blob bytes. Sprint `32.2` is blocked
by Sprint `31.3`; Sprint `32.4` is then blocked by Sprint `32.2`. Sprints
`32.1` and `32.3` remain Done on their retained negative-control and
Measured/Declared surfaces.

Sprint `31.3` is downstream of the reopened exact-artifact chain beginning at
Sprints `10.6` and `10.12`. Phase `32` tests that the admitted boundary rejects
known fakes; it does not own the V2 representation, blob/hash binding, stable
read, or proof constructor. Those primary obligations are Sprints `10.6` and
`10.12`.

**Historical retained closure.** ✅ **Done**. This phase exists because the 2026-07-05 realness audit found that
every prior product closure was graded by self-authored, self-referential gates
(convergence bar set equal to the measured value; `InferenceEligible` minted from a
fabricated witness; scaffold lint a denylist of the previous iteration's fossil
names). Adding more internal validation cannot fix this — the only exit is to grade
against external ground truth plus negative controls that must fail. This phase owns
that grader as a permanent gate; Phases `19`/`20`/`21`/`23` own wiring their
individual gates onto it. It depends on Phases `19`–`31`.

**Validation substrate**: `linux-cpu` only.

## Objective

The repository owns a `jitml-negative-controls` test stanza and a set of harness
primitives that make items `1`–`24` of the [Exit Definition](README.md#exit-definition)
non-gameable, enforcing new items `25`–`28`. A gate that cannot reject a committed
known-fake artifact fails the build. No convergence or eligibility threshold may
be a function of the value it checks. Every reported metric is recomputed from
the opaque admitted artifact and compared with its journal evidence. A stand-in
is typed `Declared` and cannot be reported as `Measured`/`Real`.

## Sprint 32.1: Negative-Control Suite [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Test/NegativeControls.hs`, `test/negative-controls/Main.hs`, `jitml.cabal`
**Docs to update**: `../documents/engineering/unit_testing_policy.md`, `../documents/engineering/product_completion_contract.md`, `system-components.md`

### Objective

A committed set of known-fake artifacts, each paired with the gate that must reject
it. The `jitml-negative-controls` stanza (wired into `jitml test all`) fails the
build if any known-fake is accepted.

### Deliverables

- Known-fake fixtures and their required verdict: an untrained random-init checkpoint
  (must fail `InferenceEligible`); a below-threshold trained model (must fail the
  convergence bar); an RL reward trace produced by a scripted controller (must fail RL
  row evidence); a dense layer labelled as convolution (must fail the differential
  conv≠dense assertion).
- The stanza asserts each gate returns *reject* for its known-fake; a gate that cannot
  reject its known-fake is a failure, not a pass.
- The suite is enumerated from the `ProductRow` registry so a new row cannot ship
  without its negative control.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-negative-controls --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Closure Evidence

- Implemented `NegativeControls.hs` and the stanza; the committed known-fakes are rejected by the standing gate; `docker compose run --rm jitml env JITML_SUBSTRATE=linux-cpu cabal test jitml-negative-controls --test-options='--hide-successes --color=never'` passed 3/3 on 2026-07-06.

## Sprint 32.2: External Bars, No-Self-Referential-Gate Lint, and Exact Served-Byte Provenance [⏸️ Blocked]

**Status**: Blocked
**Implementation**: `src/JitML/Product/ExternalBars.hs`, `src/JitML/Lint/ProductTruth.hs`, `src/JitML/Checkpoint/Format.hs`, `test/unit/Main.hs`
**Blocked by**: Sprint `31.3`
**Docs to update**: `../documents/engineering/product_completion_contract.md`, `../documents/engineering/determinism_contract.md`, `system-components.md`

### Objective

Convergence bars are frozen external literature constants and a lint bans any
threshold derived from the value it checks. Persisted artifact binding is
implemented by Sprints `10.6`/`10.12`; this sprint owns the independent
external-truth predicates used to grade that boundary and, after aggregation,
the proof that a reported measurement was recomputed from the exact admitted
bytes subsequently served.

### Deliverables

- `src/JitML/Product/ExternalBars.hs` holds the literature convergence targets,
  dataset SHAs, and arena baselines as immutable constants with a "do not derive from
  measurements" invariant.
- A lint (`ProductTruth.hs`) statically rejects the `mkConvergenceBar … measuredValue 0.0`
  / `threshold = measured` pattern anywhere on a product path.
- The external-bar predicate re-derives `coPassed` from finite measurements
  rather than trusting a stored boolean. Current served-weight, manifest, blob,
  and dataset binding is not minted here; Sprint `10.12` exposes only an opaque
  admitted artifact for this harness to challenge.
- Bind the aggregated ProductRow claim to that opaque admitted manifest address
  and its exact served `supervised.weights` bytes, recompute the reported metric
  through the admitted runtime, and reject metadata-consistent byte
  substitution.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Historical Closure Evidence

- Implemented the module and lint and exercised the former decode-time check.
  That old re-encoded-manifest/served-weight assertion is historical and does
  not close exact V2 persistence or admission; the retained closure here is the
  external-bar and no-self-reference grader.

### Remaining Work

- Blocked until Sprint `31.3` produces the versioned aggregate evidence bound to
  Sprint `10.12`'s opaque admitted artifact.
- Recompute the external-bar measurement from the exact admitted manifest and
  served weight bytes, then add substitution controls that retain matching
  metadata while changing either byte object.

## Sprint 32.3: Measured/Declared Type Split & Behavioral Scaffold Lint [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Product/Matrix.hs`, `src/JitML/Lint/ProductTruth.hs`, `src/JitML/Test/Report.hs`, `src/JitML/Web/Contracts.hs`, `test/unit/Main.hs`
**Docs to update**: `../documents/engineering/product_completion_contract.md`, `../documents/engineering/purescript_frontend.md`, `system-components.md`

### Objective

A stand-in is typed `Declared` and cannot be reported as real; the scaffold lint is a
behavioral detector, not a name denylist.

### Deliverables

- A `Measured` vs `Declared` metric type and a `RealArchitecture` vs `MlpApproximation`
  distinction carried on `ProductRow`, surfaced in the report card and demo so an
  approximate row is visibly marked.
- The scaffold lint asks "does this product function's output depend on the trained
  weights?" rather than matching fossil names; the `FutureOwner` exemption is deleted.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Closure Evidence

- Implemented the type split and behavioral lint.

## Sprint 32.4: `RunContract` Negative Controls and Properties [⏸️ Blocked]

**Status**: Blocked
**Implementation**: `src/JitML/Test/NegativeControls.hs`,
`src/JitML/Test/RunContract.hs`, `test/negative-controls/Main.hs`,
`test/unit/Main.hs`
**Blocked by**: Sprint `32.2`
**Docs to update**: `../README.md`,
`../documents/engineering/product_completion_contract.md`,
`../documents/engineering/unit_testing_policy.md`,
`../documents/engineering/run_contract.md`, `system-components.md`

### Objective

Prove that the validated-plan and evidence contract rejects every known illegal
state and remains total under event reordering and redelivery. This sprint owns
the adversarial portions of
[Exit Definition](README.md#exit-definition) items `31` and `32`.
The binding design is
[README.md → Typed run contracts](../README.md#typed-run-contracts).

### Deliverables

- Add known-invalid raw requests for zero/negative quantities, empty identities,
  incompatible algorithm/environment pairs, dimension mismatches, and invalid
  resolved-plan versions.
- Add event fixtures for gaps, conflicting duplicates, wrong `PlanId`, malformed
  payloads, non-finite measurements, missing terminal events, and completion
  before the declared budget.
- Add journal fixtures that report storage success or caller-held completion but
  omit, substitute, or mismatch the opaque Store-admitted artifact identity;
  each must be rejected as ineligible without recreating admission logic in the
  harness.
- Property-test permutation invariance for independent events, idempotence for
  identical redelivery, deterministic rejection of conflicting duplicates, and
  exact missing-evidence diagnostics.
- Exercise successful and failed settlement, timeout, cleanup failure, workload-
  terminal-before-evidence, and evidence-before-workload-terminal orderings.
- Require every product workflow contract to register at least one negative
  control; accepting any known-invalid fixture fails the standing stanza.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-negative-controls --linux-cpu
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Remaining Work

- Blocked until Sprint `32.2` binds the versioned aggregate evidence to the
  exact admitted bytes graded by these controls.
- Add the invalid-plan, invalid-evidence, settlement, lifecycle-order, and
  reducer property suites, including storage-success-without-admission cases.
- Make contract-negative coverage mandatory for every product row/workflow.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/run_contract.md` — invalid-plan/evidence controls and
  reducer/lifecycle properties.
- `documents/engineering/product_completion_contract.md` — negative controls,
  external bars, and provenance binding become the binding definition of "complete".
- `documents/engineering/unit_testing_policy.md` — ownership of the
  `jitml-negative-controls` stanza and the metamorphic/differential test discipline.

**Product docs to create/update:**
- `README.md` — the `Real`/`Declared` row tagging and the negative-control gate.

**Cross-references to add:**
- Add this phase to `README.md`, `00-overview.md`, `system-components.md`, and
  `development_plan_standards.md §E`.
