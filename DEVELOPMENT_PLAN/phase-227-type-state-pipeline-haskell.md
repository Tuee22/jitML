# Phase 227: Type-State Pipeline (Haskell)

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Type-State Pipeline (Haskell). Single-session phase migrated from legacy Sprint 21.2 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 227.1: Type-State Pipeline (Haskell) [✅ Done]

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
  `markInferenceEligible :: AdmittedCompletedCheckpoint -> ModelRef TrainingCompleted -> Either Text InferenceEligibleRef`,
  where promotion requires Store's exact persisted-byte admission and the same
  `CompletedTraining` witness already carried by the completed model reference.
- `JitML.Product.Pipeline` mints `InferenceEligibleRef` only from Store's opaque
  `AdmittedCompletedCheckpoint`, and `src/JitML/App.hs`,
  `src/JitML/Service/Runtime.hs`, and `src/JitML/Service/Workload.hs` thread
  that typed reference into inference, demo, checkpoint-compare, and adversarial
  move runners.
- Unit tests compile the legal `Declared -> TrainingStarted ->
  TrainingCompleted -> InferenceEligible` path, reject a mismatched
  completed-training witness, and prove that only an admitted completed
  checkpoint mints an `InferenceEligibleRef`.

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
  [Phase 32](README.md#legacy-to-new-phase-map) Sprint `32.2`.
- **Real weight-delta witness.** The `checkpointTrainingEvidenceWithDatasetSha`
  construction in `src/JitML/App.hs` (~line 3578) that feeds the all-zeros
  initial-weight hash into the promoted witness is corrected alongside Sprint
  `21.1`.

Closed by the [Phase 32](README.md#legacy-to-new-phase-map)
negative-control suite (`jitml-negative-controls`, Sprint `32.1`) that an untrained
random-init checkpoint fails `InferenceEligible`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
