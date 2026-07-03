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
| `rowClass` | Typed row dimension: supervised dataset/model, RL algorithm/environment, HER goal-conditioned row, AlphaZero game, or tuning family. |
| `implementation` | Owning Haskell module and constructor/function that implements the documented dataset/env/model/algorithm pair. |
| `experimentConfig` | Checked-in Dhall config or generated reflected config that can run the row through `jitml`. |
| `trainingBudget` | Fixed terminating budget used by the row's training or tuning run. |
| `convergenceBar` | Per-row metric, direction, literature target, slack, and threshold; representative category thresholds cannot satisfy another row. |
| `deviceClaim` | The substrate-backed execution claim the row must prove before product closure. |
| `trainingEvidence` | Proof that training ran for the declared fixed budget and parameters changed from initialization. |
| `deviceEvidence` | Proof that the selected substrate device executed the forward/backward/update-critical kernels, or an explicit non-product classification if no device-backed model is claimed. |
| `checkpointEvidence` | `CompletedTraining` witness plus convergence metrics in the checkpoint manifest. |
| `demoEvidence` | Browser contract and panel path that renders the trained artifact, not only the row name. |
| `integrationTest` | Test identifier that executes the row through the real training/checkpoint path. |
| `e2eTest` | Test identifier that renders or interacts with the row through the live demo app. |
| `demoPanel` | Browser panel that must render the row from an inference-eligible trained artifact. |

The source of truth is the typed registry in
`src/JitML/Product/Matrix.hs`, with convergence-bar helpers in
`src/JitML/Product/Convergence.hs`. The `MatrixFloor` pins the current product
minimum: eleven supervised rows, seven canonical RL environments, the
stable-baselines3 algorithm family plus HER, four AlphaZero games, and the
hyperparameter-tuning row. Unit tests reject duplicate rows, rows outside that
documented floor, documented floor members missing from the registry, and rows
without integration/e2e ids. Browser contracts and workflow-matrix projections
are generated from the registry; hand-maintained duplicate row lists are not
closure evidence.

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

RL product rows additionally require per-row convergence evidence from
`JitML.RL.ConvergenceThresholds`: the row's `(algorithm, environment)` cohort
must have a concrete threshold, the measured median or HER goal metric must pass
that threshold, policy-or-Q hashes must change across a positive update count,
and the manifest must carry `linux-cpu` device evidence. Synthetic transition
traces, missing thresholds, initialized-only checkpoints, and generic
self-thresholded metric fallbacks cannot mint `CompletedTraining` for RL rows.

AlphaZero product rows are game-specific, not a single Connect 4 proxy. Connect
4, Othello, Hex, and Gomoku each resolve their own initial state, observation
shape, action count, self-play command (`--game <id>`), MCTS visit distribution
targets, outcome labels, and policy/value checkpoint tensor name. Self-play
evidence must show network-backed priors and leaf values, persistent per-game
MCTS cache state across moves, deterministic root-noise seeding, and the row's
own transcript/game id. Each row carries training, device, and checkpoint
evidence handles; its checkpoint manifest carries a `CompletedTraining` witness
with the initial/final policy-value network hashes, positive generation count,
passing per-game arena win-rate observation, and an
`InferenceEligibleCheckpoint` proof from the checkpoint loader boundary.

## Type-State DSL Contract

It must be impossible to represent "run inference on an untrained model" in the
DSL accepted by product commands. The Haskell boundary is the opaque
`JitML.Product.Pipeline.ModelRef (state :: ModelState)` pipeline:

```haskell
data ModelState = Declared | TrainingStarted | TrainingCompleted | InferenceEligible

declareExperiment :: Text -> Experiment Declared
declareModel :: Experiment Declared -> ModelRef Declared
startTraining :: ModelRef Declared -> ModelRef TrainingStarted

train
  :: ModelRef TrainingStarted
  -> CompletedTraining
  -> m (ModelRef TrainingCompleted)

markInferenceEligible
  :: Text
  -> ModelRef TrainingCompleted
  -> CompletedTraining
  -> Either Text (ModelRef InferenceEligible)

infer
  :: InferenceEligibleRef
  -> CheckpointManifest
  -> InputBatch
  -> m OutputBatch
```

`CompletedTraining` can only be built with the Sprint `21.1` training evidence:
initial weight hash, final weight hash, positive update count, dataset SHA at
read time, fixed-budget completion, TensorBoard metadata, and passing numeric
convergence observations. `markInferenceEligible` promotes only a
`TrainingCompleted` reference carrying that exact witness and rejects mismatches
or failed convergence. `InferenceEligibleRef` is minted from a validated
`InferenceEligibleCheckpoint` at the checkpoint loader boundary before any
substrate runner receives weights.

Dhall mirrors the same state boundary with separate records for declared
experiments, completed-training witnesses, and inference selectors in
`dhall/project/Schema.dhall` and `dhall/run/Schema.dhall`.
`tryLoadInferenceSelectorConfig` validates the selector/witness hash match,
completed-training provenance, passing convergence, changed weight hashes,
positive update count, and dataset-read SHA. A manifest or selector with
missing, partial, synthetic, seeded-demo, or failed-training provenance cannot
decode as an inference target.

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
The product-row artifact publisher is
`jitml internal train-and-publish-product-rows --<substrate>`; it trains rows
through the real family-specific path and writes artifacts under stable
`product-row-*` experiment hashes. The browser checkpoint-list frame carries one
`row-selector` per `ProductRow` with a selector state of `eligible`,
`training-required`, `unsupported`, or `error`, and carries global
`selector-state: fail-closed:no-inference-eligible-artifact` when the daemon
finds no eligible summary rows. The checkpoint panel renders those states
directly instead of substituting a seeded or synthetic artifact. Generated
`ModelMatrixRow` values carry the same `product-row-*` experiment hashes and
demo panel names, the default panel requests use those hashes, and the checkpoint
panel renders supervised, RL, AlphaZero, and tuning artifact cards from the
matching `CheckpointSummary.rowId` metadata rather than from static row names.
Browser REST handlers validate product requests against the ProductRow registry
before any runtime or publisher path runs; non-product hashes, panel/row
mismatches, stale seeded hashes, `*-demo-weights`, missing artifacts, untrained or
partial manifests, and unsupported substrate states return a `503
checkpoint-required` fail-closed envelope instead of a fake result. The
Playwright guard asserts the browser posts `product-row-*` hashes and does not
render `*-demo-weights`; Phase `28` owns converting that browser proof into one
integration/e2e evidence row per ProductRow.

## Test Contract

Every product row owns all of the following test evidence:

| Evidence | Required behavior |
|----------|-------------------|
| Catalog parity | Generated docs/browser matrix exactly matches the typed product matrix. |
| Integration | The row trains through the real command path, verifies data, updates learned state, writes a completed checkpoint, rejects inference before completion, and records evidence from the product-row publisher manifest rather than from synthetic row-local hashes or loss curves. |
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
