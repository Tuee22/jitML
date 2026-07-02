# Product Completion Contract

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: ../../README.md, ../documentation_standards.md, README.md, training_workloads.md, purescript_frontend.md, unit_testing_policy.md, ../../DEVELOPMENT_PLAN/README.md, ../../DEVELOPMENT_PLAN/phase-19-product-truth-gates.md, ../../DEVELOPMENT_PLAN/phase-22-canonical-matrix-and-dataset-integrity.md, ../../DEVELOPMENT_PLAN/phase-24-real-supervised-architectures.md, ../../DEVELOPMENT_PLAN/phase-25-real-rl-algorithms-and-environments.md, ../../DEVELOPMENT_PLAN/phase-21-type-state-dsl-and-inference-eligibility.md, ../../DEVELOPMENT_PLAN/phase-27-demo-all-model-rendering.md, ../../DEVELOPMENT_PLAN/phase-28-per-model-integration-and-e2e.md, ../../DEVELOPMENT_PLAN/phase-29-linux-cuda-product-lane.md, ../../DEVELOPMENT_PLAN/phase-30-apple-silicon-product-lane.md, ../../DEVELOPMENT_PLAN/phase-31-no-caveat-product-aggregation.md
**Generated sections**: none

> **Purpose**: Define the non-negotiable completion proof for jitML's documented
> model surface so documentation, implementation, demo rendering, and tests cannot
> treat catalog rows, fake scaffolds, or representative smoke checks as product
> completion.

## Current Product State

As of 2026-07-01 the no-caveat product claim is reopened. Historical green runs
remain dated evidence for the surfaces they actually exercised, but they do not
prove the stronger product contract below. The active remediation chain lives in
[../../DEVELOPMENT_PLAN/README.md](../../DEVELOPMENT_PLAN/README.md) and starts
at Phase `19`.

The completion bar is intentionally stricter than "a command exists" or "a row
appears in a generated matrix". A row is complete only when the same canonical
product row is implemented, trainable, checkpointed, rendered, covered by
integration tests, covered by e2e tests, and validated on the selected real
substrate lane.

## Canonical Product Matrix

The canonical product matrix is the union of:

- every row in [../../README.md → Canonical supervised learning problems](../../README.md#canonical-supervised-learning-problems);
- every environment in [../../README.md → Canonical reinforcement learning environments](../../README.md#canonical-reinforcement-learning-environments);
- every required algorithm/environment row in [../../README.md → Convergence and determinism checks for RL](../../README.md#convergence-and-determinism-checks-for-rl);
- every AlphaZero game documented in [../../README.md → AlphaZero-style self-play and persistent MCTS state](../../README.md#alphazero-style-self-play-and-persistent-mcts-state);
- every product demo panel that claims to render one of those model families.

Each row carries these machine-checkable fields:

| Field | Required meaning |
|-------|------------------|
| `rowId` | Stable identifier used by docs, CLI experiment files, checkpoint metadata, demo contracts, integration tests, and e2e tests. |
| `family` | `Supervised`, `ReinforcementLearning`, `AlphaZero`, or `Tuning`. |
| `implementation` | Owning Haskell module and constructor/function that implements the documented dataset/env/model/algorithm pair. |
| `experimentConfig` | Checked-in Dhall config or generated reflected config that can run the row through `jitml`. |
| `trainingEvidence` | Proof that training ran for the declared fixed budget and parameters changed from initialization. |
| `deviceEvidence` | Proof that the selected substrate device executed the forward/backward/update-critical kernels, or an explicit non-product classification if no device-backed model is claimed. |
| `checkpointEvidence` | `CompletedTraining` witness plus convergence metrics in the checkpoint manifest. |
| `demoEvidence` | Browser contract and panel path that renders the trained artifact, not only the row name. |
| `integrationTest` | Test identifier that executes the row through the real training/checkpoint path. |
| `e2eTest` | Test identifier that renders or interacts with the row through the live demo app. |

A matrix generator may render this table into README/browser contracts, but the
source of truth must be one typed registry. Hand-maintained duplicate row lists
are not closure evidence.

## Real-ML Rules

Production ML paths must satisfy all rules below:

1. **No fake or deterministic substitute may satisfy a product row.**
   Deterministic fixtures are permitted only in tests that explicitly assert
   scaffolding behavior; they must be excluded from product completion scans.
2. **Training changes learned state.** A completed row records a deterministic
   initial-parameter hash, final-parameter hash, and update count. A no-op update,
   hardcoded final tensor, or initialized-only checkpoint is incomplete.
3. **Device selection changes execution.** A row that claims substrate-backed ML
   records which `MlpDevice` or equivalent substrate engine executed the
   update-critical operations. Host-only rollout helpers may exist, but they do
   not prove the substrate training claim.
4. **Dataset bytes are verified at the product boundary.** Every product fetch
   from MinIO or a local mirror verifies the pinned SHA before decoding. Upload
   time verification alone is insufficient.
5. **Representative smoke tests do not close product rows.** A single MNIST,
   PPO/cartpole, or static browser matrix test proves only that row and only the
   behavior it actually exercised.

Algorithms that do not have neural weights, such as a black-box policy search
row, may stay in the research catalog only if they are typed as non-product rows
or carry their own learned-policy artifact and do not claim substrate-backed ANN
training. The product matrix must make that state explicit.

## Type-State DSL Contract

It must be impossible to represent "run inference on an untrained model" in the
DSL accepted by product commands. The target shape is a type-state pipeline:

```haskell
-- Example: target type-state shape, not a checked-in API promise.
data ModelState = Declared | TrainingStarted | TrainingCompleted | InferenceEligible

newtype ModelRef (state :: ModelState) = ModelRef ArtifactRef

train
  :: Experiment Declared
  -> TrainingBudget
  -> m (ModelRef TrainingCompleted)

markInferenceEligible
  :: ModelRef TrainingCompleted
  -> CompletedTraining
  -> ConvergenceMetrics
  -> m (ModelRef InferenceEligible)

infer
  :: ModelRef InferenceEligible
  -> InputBatch
  -> m OutputBatch
```

Dhall mirrors the same state boundary with separate constructors or records for
declared experiments, completed training witnesses, and inference-eligible
artifacts. A manifest with missing, partial, synthetic, seeded-demo, or
failed-training provenance cannot decode as an inference target.

## Demo Contract

The demo app is complete only when every product matrix row has:

- a live artifact selector that can choose an inference-eligible checkpoint for
  that exact row;
- a model-appropriate renderer or interaction surface;
- displayed convergence/provenance metadata from the checkpoint manifest;
- a fail-closed state when no eligible artifact exists;
- a Playwright assertion that exercises the row against a live edge, not a fake
  browser runtime or static generated name list.

Static model names, seeded synthetic checkpoints, route-shape tests, and demo
fixtures may support development, but they cannot count as product completion.

## Test Contract

Every product row owns all of the following test evidence:

| Evidence | Required behavior |
|----------|-------------------|
| Catalog parity | Generated docs/browser matrix exactly matches the typed product matrix. |
| Integration | The row trains through the real command path, verifies data, updates learned state, writes a completed checkpoint, and rejects inference before completion. |
| E2E | The live demo renders or interacts with that row through an inference-eligible artifact. |
| Negative | Missing dataset, missing cluster, malformed checkpoint, untrained checkpoint, and unsupported substrate fail closed. |
| Lane | The same row is validated on `linux-cpu`; accelerator phases separately validate `linux-cuda` and `apple-silicon` without requiring both accelerators in one phase. |

Coverage reports must name missing row/test pairs. A pass count without row
identity is not enough to close a phase.

## Phase Validation Boundary

Phases `19` through `31` implement this contract in order. Phases `19` through
`28` close on `linux-cpu` only. Phase `29` closes on `linux-cpu` plus
`linux-cuda`. Phase `30` closes on `linux-cpu` plus `apple-silicon`. Phase `31`
is a `linux-cpu`-only aggregation phase that consumes committed lane artifacts
and does not rerun accelerator lanes.
