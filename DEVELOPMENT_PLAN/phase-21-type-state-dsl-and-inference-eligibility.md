# Phase 21: Type-State DSL & Inference Eligibility

**Status**: Done
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [development_plan_standards.md](development_plan_standards.md), [phase-20-de-fossilization-and-scaffold-lint.md](phase-20-de-fossilization-and-scaffold-lint.md), [phase-22-canonical-matrix-and-dataset-integrity.md](phase-22-canonical-matrix-and-dataset-integrity.md), [../documents/engineering/product_completion_contract.md](../documents/engineering/product_completion_contract.md), [../documents/engineering/checkpoint_format.md](../documents/engineering/checkpoint_format.md), [../documents/engineering/training_metrics_and_splits.md](../documents/engineering/training_metrics_and_splits.md), [../documents/engineering/durable_state_dsl.md](../documents/engineering/durable_state_dsl.md)
**Generated sections**: none

> **Purpose**: Make "run inference on an untrained model" unrepresentable and
> make training evidence non-fabricable by binding weight-delta witnesses to a
> real type-state pipeline across the Haskell and Dhall product surfaces.

## Phase State

✅ **Done** (reclosed 2026-07-06 after the 2026-07-05 realness audit). The
self-referential inference-eligibility defects are removed: product convergence
bars now come from frozen external constants in `JitML.Product.ExternalBars`,
`InferenceEligible` decode re-checks completed metrics against those bars, the
all-zero initial-weight fallback is deleted, and the internal seed-demo
checkpoint writer is retired. Validation: `jitml-unit` passed **277 / 277** and
`jitml-negative-controls` passed **3 / 3** on `linux-cpu`.

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

## Sprint 21.1: Non-Fabricable Training Evidence [✅ Done]

**Status**: Done
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
  fields, populated only via smart constructors that reject empty hashes,
  `initialWeightHash == finalWeightHash`, `updateCount <= 0`, and missing
  dataset-read provenance; `attachCompletedTraining` mirrors the witness fields
  into the manifest and inference eligibility rejects missing or mismatched
  manifest evidence.
- The `coPassed = True` fabrication in `completedTrainingFromMetrics`
  (`src/JitML/Training/Budget.hs`) is deleted; the pass flag is replaced by
  `evaluateConvergence :: ConvergenceBar -> MeasuredMetrics -> Either Text ConvergenceObservation`,
  which compares measured metrics against a numeric bar and sets `coPassed` from
  the threshold result.
- `src/JitML/SL/ConvergenceThresholds.hs` carries a per-row numeric bar table
  mirroring the RL threshold table (`src/JitML/RL/ConvergenceThresholds.hs`), so
  every supervised row resolves to an explicit numeric `ConvergenceBar`.
- A unit test fails when evidence is constructed with equal init/final hashes,
  with a zero update count, or with a hardcoded pass flag; and fails when any
  product row lacks a numeric convergence bar.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-unit --linux-cpu # passed, 253/253 tests
docker compose run --rm jitml jitml docs check                  # passed
docker compose run --rm jitml jitml check-code                  # passed
```

The 2026-07-05 realness audit found this validation graded the surface against
self-authored gates: the per-row bar was slack-0 and the initial-weight hash was
taken over an all-zeros placeholder, so the unit test never exercised an untrained
checkpoint.

### Closure Evidence

closed obligation (Exit Definition — non-fabricable training evidence): the
weight-movement witness and the convergence outcome are self-referential, so an
untrained random-init model constructs valid evidence.

- **Hash the real random-init weights.** `initialWeightHash` must be taken over the
  actual randomly-initialized weight tensor, not the all-zeros placeholder in
  `src/JitML/App.hs` `checkpointTrainingEvidenceWithDatasetSha` (~line 3578); until
  then `initialWeightHash /= finalWeightHash` is satisfied by any nonzero final
  weights.
- **`updateCount` equals the real optimizer-step count.** The witness must carry the
  number of optimizer steps actually applied, not a positive constant.
- **Non-tautological convergence bar.** Replace the slack-0 per-row bar in
  `src/JitML/SL/ConvergenceThresholds.hs` (which makes `evaluateConvergence` compare
  a value against itself) with the frozen external constants from
  [phase-32-external-truth-realness-harness.md](phase-32-external-truth-realness-harness.md)
  Sprint `32.2` (`src/JitML/Product/ExternalBars.hs`).

Closed by the [Phase 32](phase-32-external-truth-realness-harness.md)
negative-control suite (`jitml-negative-controls`, Sprint `32.1`) that an untrained
random-init checkpoint is **rejected**, plus the no-self-referential-gate lint
(Sprint `32.2`).

## Sprint 21.2: Type-State Pipeline (Haskell) [✅ Done]

**Status**: Done
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
- `train :: ModelRef TrainingStarted -> CompletedTraining -> m (ModelRef TrainingCompleted)`
  and
  `markInferenceEligible :: Text -> ModelRef TrainingCompleted -> CompletedTraining -> Either Text InferenceEligibleRef`,
  where promotion requires the exact Sprint `21.1` weight-delta witness already
  carried by the completed model reference and passing convergence.
- `JitML.Checkpoint.Store` mints `InferenceEligibleRef` only from a validated
  `InferenceEligibleCheckpoint`, and `src/JitML/App.hs`,
  `src/JitML/Service/Runtime.hs`, and `src/JitML/Service/Workload.hs` thread
  that typed reference into inference, demo, checkpoint-compare, and adversarial
  move runners.
- Unit tests compile the legal `Declared -> TrainingStarted ->
  TrainingCompleted -> InferenceEligible` path, reject a mismatched
  completed-training witness, and prove that `InferenceEligibleCheckpoint`
  mints only an `InferenceEligibleRef`.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-unit --linux-cpu       # passed, 256/256 tests
docker compose run --rm jitml jitml test jitml-integration --linux-cpu # passed, 77/77 tests after `jitml bootstrap --linux-cpu`
docker compose run --rm jitml jitml check-code                        # passed
docker compose run --rm jitml jitml docs check                        # passed
```

The 2026-07-05 realness audit found the promotion test only exercised the legal
state path against a witness whose convergence was the tautological slack-0 gate,
so it never proved an untrained model is refused promotion.

### Closure Evidence

closed obligation (Exit Definition — inference eligibility is earned): promotion via
`markInferenceEligible` requires "passing convergence," but that convergence is the
tautological slack-0 gate from Sprint `21.1`, so promotion is unconditional in
practice.

- **Promotion must consume a real convergence outcome.** `markInferenceEligible`
  must reject a witness whose `coPassed` was derived from a value-equals-threshold
  bar; the promotion path is re-pointed at the frozen external bars from
  [Phase 32](phase-32-external-truth-realness-harness.md) Sprint `32.2`.
- **Real weight-delta witness.** The `checkpointTrainingEvidenceWithDatasetSha`
  construction in `src/JitML/App.hs` (~line 3578) that feeds the all-zeros
  initial-weight hash into the promoted witness is corrected alongside Sprint
  `21.1`.

Closed by the [Phase 32](phase-32-external-truth-realness-harness.md)
negative-control suite (`jitml-negative-controls`, Sprint `32.1`) that an untrained
random-init checkpoint fails `InferenceEligible`.

## Sprint 21.3: Dhall Boundary & Fail-Closed Decode [✅ Done]

**Status**: Done
**Implementation**: `dhall/project/Schema.dhall`, `dhall/run/Schema.dhall`, `src/JitML/Service/RunConfig.hs`, `src/JitML/Service/DhallSchema.hs`, `src/JitML/Project/Config.hs`, `src/JitML/Checkpoint/Format.hs`, `src/JitML/Checkpoint/Store.hs`, `src/JitML/Service/Workload.hs`, `src/JitML/Web/Contracts.hs`, `web/src/Generated/Contracts.purs`, `web/src/Panels/Checkpoints.purs`, `test/unit/Main.hs`, `test/integration/Main.hs`
**Docs to update**: `../documents/engineering/durable_state_dsl.md`, `../documents/engineering/product_completion_contract.md`

### Objective

The Dhall configuration surface mirrors the Haskell state boundary. A manifest
with missing, partial, synthetic, seeded, or failed-training provenance cannot
decode as an inference target, and the browser renders a fail-closed state
instead of substituting a fabricated artifact.

### Deliverables

- Dhall schemas under `dhall/project/Schema.dhall` and `dhall/run/Schema.dhall`
  distinguish declared experiments, completed-training witnesses, and inference
  selectors, mirroring the `ModelState` boundary from Sprint `21.2`.
  `JitML.Service.RunConfig.tryLoadInferenceSelectorConfig` decodes and validates
  selector facts at the Dhall boundary.
- `src/JitML/Checkpoint/Format.hs` exposes
  `decodeInferenceEligibleManifestCbor`, and `src/JitML/Checkpoint/Store.hs`
  rejects any manifest missing the weight-delta evidence fields, carrying
  synthetic/seeded provenance, or carrying a failing convergence outcome before
  weight blobs are read or an inference runner is invoked.
- `JitML.Service.Workload.renderCheckpointListResult`, the generated browser
  contracts, and `web/src/Panels/Checkpoints.purs` carry
  `selector-state: fail-closed:no-inference-eligible-artifact` when no row has
  an inference-eligible artifact, so the browser shows an explicit fail-closed
  state rather than falling back to seeded or synthetic data.
- Unit and integration tests assert that declared, partial, synthetic, seeded,
  zero-update, unchanged-weight, and failed-training selectors/manifests fail
  closed with typed errors, that invalid manifests are rejected before blob or
  runner IO, and that a valid completed manifest decodes as an inference target.

### Validation

```bash
docker compose build jitml                                                        # passed; refreshed image, embedded check-code: ok
docker compose run --rm -e JITML_BOOTSTRAP_SKIP_IMAGE_BUILD=1 jitml jitml bootstrap --linux-cpu # passed, 105 rollout steps
docker compose run --rm jitml jitml docs check                                    # passed
docker compose run --rm jitml jitml check-code                                    # passed
docker compose run --rm jitml jitml test jitml-unit --linux-cpu                   # passed, 258/258 tests
docker compose run --rm jitml jitml test jitml-integration --linux-cpu            # passed, 78/78 tests
```

The 2026-07-05 realness audit found decode trusted the stored `coPassed` boolean
and the stored weight hashes, so the "unchanged-weight / failed-training" rejections
above never fired for an untrained random-init manifest whose all-zeros init hash
differs from its nonzero final hash.

### Closure Evidence

closed obligation (Exit Definition — fail-closed decode): the decode surface trusts
the stored `coPassed` boolean and the stored weight hashes, so an untrained
random-init manifest decodes as an inference target instead of failing closed.

- **Re-derive `coPassed` at decode against the external bar.**
  `decodeInferenceEligibleManifestCbor` (`src/JitML/Checkpoint/Format.hs`) and the
  `src/JitML/Checkpoint/Store.hs` rejection path must recompute the convergence
  verdict from the served metrics against the frozen external constants
  ([Phase 32](phase-32-external-truth-realness-harness.md) Sprint `32.2` decode
  change), not accept the boolean the manifest carries, and must assert the
  served-weights hash equals the checkpoint hash.

Closed by the [Phase 32](phase-32-external-truth-realness-harness.md)
negative-control suite (`jitml-negative-controls`, Sprint `32.1`) that an untrained
random-init checkpoint is rejected at decode.

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
