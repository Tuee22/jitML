# Phase 32: External-Truth Realness Harness & Negative-Control Gate

**Status**: Planned
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [development_plan_standards.md](development_plan_standards.md), [phase-33-per-model-convergence-and-inference-tests.md](phase-33-per-model-convergence-and-inference-tests.md), [phase-34-plan-truth-governance.md](phase-34-plan-truth-governance.md), [../README.md](../README.md), [../documents/engineering/product_completion_contract.md](../documents/engineering/product_completion_contract.md), [../documents/engineering/unit_testing_policy.md](../documents/engineering/unit_testing_policy.md)
**Generated sections**: none

> **Purpose**: Grade "Done" against external ground truth the implementer cannot
> author or tune. Install a standing negative-control suite (known fakes must be
> rejected), frozen external convergence bars, provenance binding, and a typed
> `Measured`/`Declared` split, so no future fabrication can pass a self-authored
> gate — the recurring failure mode this whole reopen exists to end.

## Phase State

📋 **Planned**. This phase exists because the 2026-07-05 realness audit found that
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
known-fake artifact fails the build. No convergence or eligibility threshold may be a
function of the value it checks. Every reported metric is recomputed at read time
from the served artifact. A stand-in is typed `Declared` and cannot be reported as
`Measured`/`Real`.

## Sprint 32.1: Negative-Control Suite [📋 Planned]

**Status**: Planned
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

### Remaining Work

- Implement `NegativeControls.hs` and the stanza; against the current worktree the
  known-fakes are *accepted* (the controls fail), which is the correct red baseline
  until Phases `19`–`28` land.

## Sprint 32.2: External Bars, No-Self-Referential-Gate Lint, Provenance Binding [📋 Planned]

**Status**: Planned
**Implementation**: `src/JitML/Product/ExternalBars.hs`, `src/JitML/Lint/ProductTruth.hs`, `src/JitML/Checkpoint/Format.hs`, `test/unit/Main.hs`
**Docs to update**: `../documents/engineering/product_completion_contract.md`, `../documents/engineering/determinism_contract.md`, `system-components.md`

### Objective

Convergence bars are frozen external literature constants; a lint bans any threshold
derived from the value it checks; reported metrics are recomputed from the served
artifact.

### Deliverables

- `src/JitML/Product/ExternalBars.hs` holds the literature convergence targets,
  dataset SHAs, and arena baselines as immutable constants with a "do not derive from
  measurements" invariant.
- A lint (`ProductTruth.hs`) statically rejects the `mkConvergenceBar … measuredValue 0.0`
  / `threshold = measured` pattern anywhere on a product path.
- `Checkpoint/Format.hs` re-derives `coPassed` at decode against the external bar (not
  the stored boolean) and asserts the served-weights hash equals the checkpoint hash.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Remaining Work

- Implement the module, lint, and decode change; migrate the reopened gate phases
  (`19`/`21`) onto `ExternalBars`.

## Sprint 32.3: Measured/Declared Type Split & Behavioral Scaffold Lint [📋 Planned]

**Status**: Planned
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

### Remaining Work

- Implement the type split and behavioral lint.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/product_completion_contract.md` — negative controls,
  external bars, and provenance binding become the binding definition of "complete".
- `documents/engineering/unit_testing_policy.md` — ownership of the
  `jitml-negative-controls` stanza and the metamorphic/differential test discipline.

**Product docs to create/update:**
- `README.md` — the `Real`/`Declared` row tagging and the negative-control gate.

**Cross-references to add:**
- Add this phase to `README.md`, `00-overview.md`, `system-components.md`, and
  `development_plan_standards.md §E`.
