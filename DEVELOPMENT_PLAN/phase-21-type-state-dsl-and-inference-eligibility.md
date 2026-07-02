# Phase 21: Type-State DSL & Inference Eligibility

**Status**: Blocked
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [development_plan_standards.md](development_plan_standards.md), [phase-20-de-fossilization-and-scaffold-lint.md](phase-20-de-fossilization-and-scaffold-lint.md), [phase-22-canonical-matrix-and-dataset-integrity.md](phase-22-canonical-matrix-and-dataset-integrity.md), [../documents/engineering/product_completion_contract.md](../documents/engineering/product_completion_contract.md), [../documents/engineering/checkpoint_format.md](../documents/engineering/checkpoint_format.md), [../documents/engineering/training_metrics_and_splits.md](../documents/engineering/training_metrics_and_splits.md), [../documents/engineering/durable_state_dsl.md](../documents/engineering/durable_state_dsl.md)
**Generated sections**: none

> **Purpose**: Make "run inference on an untrained model" unrepresentable and
> make training evidence non-fabricable by binding weight-delta witnesses to a
> real type-state pipeline across the Haskell and Dhall product surfaces.

## Phase State

⏸️ **Blocked by** Phase `20`.

**Validation substrate**: `linux-cpu` only.

## Objective

Training evidence is manufactured only from real weight movement, and inference
eligibility is a compile-time property. A `CompletedTraining` witness and a
`CheckpointManifest` carry a deterministic initial-weight hash, final-weight
hash, update count, and dataset SHA observed at read; those fields exist only
when the initial and final hashes differ and the update count is positive.
Convergence is decided against per-row numeric bars, not a hardcoded pass flag.
Inference commands, demo selectors, checkpoint compare, and report-card readers
accept only a `ModelRef InferenceEligible`, so declared experiments, partial
manifests, failed runs, seeded demo fixtures, and static matrix rows cannot
decode as inference targets in Haskell, in Dhall, or in the browser.

## Sprint 21.1: Non-Fabricable Training Evidence [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Phase `20`
**Implementation**: `src/JitML/Product/Evidence.hs`, `src/JitML/Training/Budget.hs`, `src/JitML/Checkpoint/Format.hs`, `src/JitML/SL/ConvergenceThresholds.hs`, `test/unit/Main.hs`
**Docs to update**: `../documents/engineering/checkpoint_format.md`, `../documents/engineering/training_metrics_and_splits.md`

### Objective

A `CompletedTraining` witness and a `CheckpointManifest` prove that learned
state moved. Evidence is constructible only through smart constructors that
require real weight movement, and convergence is evaluated against the same
per-row numeric bar table the RL rows already use.

### Deliverables

- `src/JitML/Product/Evidence.hs` owns the only constructors for training
  evidence. `CompletedTraining` (in `src/JitML/Training/Budget.hs`) and
  `CheckpointManifest` (in `src/JitML/Checkpoint/Format.hs`) gain
  `initialWeightHash`, `finalWeightHash`, `updateCount`, and `datasetShaAtRead`
  fields, populated only via non-exported smart constructors that reject
  `initialWeightHash == finalWeightHash` and `updateCount <= 0`.
- The `coPassed = True` fabrication in `completedTrainingFromMetrics`
  (`src/JitML/Training/Budget.hs`) is deleted; the pass flag is replaced by
  `evaluateConvergence :: ConvergenceBar -> MeasuredMetrics -> Outcome`, which
  compares measured metrics against a numeric bar and returns `Pass`/`Fail`.
- `src/JitML/SL/ConvergenceThresholds.hs` carries a per-row numeric bar table
  mirroring the RL threshold table (`src/JitML/RL/ConvergenceThresholds.hs`), so
  every supervised row resolves to an explicit numeric `ConvergenceBar`.
- A unit test fails when evidence is constructed with equal init/final hashes,
  with a zero update count, or with a hardcoded pass flag; and fails when any
  product row lacks a numeric convergence bar.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Remaining Work

- Add the smart-constructor module and thread the four evidence fields through
  the witness and manifest types.
- Delete the hardcoded `coPassed = True` path and route convergence through the
  numeric bar table for both SL and RL rows.
- Add the negative unit tests that reject fabricated evidence.

## Sprint 21.2: Type-State Pipeline (Haskell) [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Sprint `21.1`
**Implementation**: `src/JitML/Product/Pipeline.hs`, `src/JitML/Product/Evidence.hs`, `src/JitML/App.hs`, `test/unit/Main.hs`
**Docs to update**: `../documents/engineering/product_completion_contract.md`, `../documents/engineering/checkpoint_format.md`

### Objective

Inference eligibility is a phantom-typed property of a model reference. Only a
completed training run that carries valid weight-delta evidence and a passing
convergence outcome can be promoted to an inference-eligible reference, and only
inference-eligible references reach the inference, demo, and checkpoint-compare
commands.

### Deliverables

- `ModelRef (state :: ModelState)` with `Declared`, `TrainingStarted`,
  `TrainingCompleted`, and `InferenceEligible` states, so an untrained model
  cannot be passed where an inference-eligible one is required.
- `train :: Experiment Declared -> TrainingBudget -> m (ModelRef TrainingCompleted)`
  and `markInferenceEligible :: ModelRef TrainingCompleted -> CompletedTraining -> m (ModelRef InferenceEligible)`,
  where promotion requires valid weight-delta evidence from Sprint `21.1` and a
  `ConvergenceOutcome == Pass`.
- `infer`, demo inference, and checkpoint-compare entrypoints in
  `src/JitML/App.hs` accept only `ModelRef InferenceEligible`; call sites that
  previously accepted an untyped artifact ref no longer typecheck.
- A unit test proves the illegal transitions (infer from `Declared`,
  `TrainingStarted`, or a `TrainingCompleted` ref with failing/absent evidence)
  are rejected at the type boundary.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml test jitml-integration --linux-cpu
docker compose run --rm jitml jitml check-code
```

### Remaining Work

- Add the state-indexed `ModelRef` and the `train`/`markInferenceEligible`
  transitions gated on real evidence.
- Retype the inference, demo, and checkpoint-compare entrypoints and fix every
  broken call site.
- Add the negative unit tests for each illegal state transition.

## Sprint 21.3: Dhall Boundary & Fail-Closed Decode [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Sprint `21.2`
**Implementation**: `dhall/project`, `dhall/run`, `src/JitML/Checkpoint/Format.hs`, `src/JitML/Checkpoint/Store.hs`, `test/integration/Main.hs`
**Docs to update**: `../documents/engineering/durable_state_dsl.md`, `../documents/engineering/product_completion_contract.md`

### Objective

The Dhall configuration surface mirrors the Haskell state boundary. A manifest
with missing, partial, synthetic, seeded, or failed-training provenance cannot
decode as an inference target, and the browser renders a fail-closed state
instead of substituting a fabricated artifact.

### Deliverables

- Dhall schemas under `dhall/project` and `dhall/run` distinguish declared
  experiments, completed-training witnesses, and inference selectors, mirroring
  the `ModelState` boundary from Sprint `21.2`.
- Manifest decode in `src/JitML/Checkpoint/Format.hs` and
  `src/JitML/Checkpoint/Store.hs` rejects any manifest missing the weight-delta
  evidence fields or carrying a failing convergence outcome, before any inference
  IO runs.
- The demo selector shows an explicit fail-closed state for a row with no
  inference-eligible artifact rather than falling back to seeded or synthetic
  data.
- Integration tests assert that declared/partial/synthetic/seeded/failed-training
  manifests fail closed with a typed error, and that a valid completed manifest
  decodes as an inference target.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-integration --linux-cpu
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml docs check
```

### Remaining Work

- Add the state-indexed Dhall schema surface and negative Dhall fixtures for
  illegal inference states.
- Add fail-closed decode in the checkpoint reader and the demo selector.
- Add the end-to-end negative integration cases and remove any selector fallback
  to seeded demo data.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/checkpoint_format.md` — evidence manifest fields
  (`initialWeightHash`, `finalWeightHash`, `updateCount`, `datasetShaAtRead`).
- `documents/engineering/training_metrics_and_splits.md` — per-row numeric
  convergence bars and the weight-delta witness.
- `documents/engineering/product_completion_contract.md` — type-state pipeline
  and non-fabricable evidence contract.
- `documents/engineering/durable_state_dsl.md` — Dhall state boundary and
  fail-closed decode.

**Product docs to create/update:**
- `README.md` — inference-eligibility and non-fabricable-evidence product state.

**Cross-references to add:**
- Add this phase to `README.md`, `00-overview.md`, `system-components.md`, and
  `development_plan_standards.md`.
