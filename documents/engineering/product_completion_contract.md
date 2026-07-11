# Product Completion Contract

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: ../../README.md, ../documentation_standards.md, README.md, training_workloads.md, purescript_frontend.md, unit_testing_policy.md, ../../DEVELOPMENT_PLAN/README.md, ../../DEVELOPMENT_PLAN/phase-19-product-truth-gates.md, ../../DEVELOPMENT_PLAN/phase-22-canonical-matrix-and-dataset-integrity.md, ../../DEVELOPMENT_PLAN/phase-24-real-supervised-architectures.md, ../../DEVELOPMENT_PLAN/phase-25-real-rl-algorithms-and-environments.md, ../../DEVELOPMENT_PLAN/phase-21-type-state-dsl-and-inference-eligibility.md, ../../DEVELOPMENT_PLAN/phase-27-demo-all-model-rendering.md, ../../DEVELOPMENT_PLAN/phase-28-per-model-integration-and-e2e.md, ../../DEVELOPMENT_PLAN/phase-29-linux-cuda-product-lane.md, ../../DEVELOPMENT_PLAN/phase-30-apple-silicon-product-lane.md, ../../DEVELOPMENT_PLAN/phase-31-no-caveat-product-aggregation.md, ../../DEVELOPMENT_PLAN/phase-32-external-truth-realness-harness.md, ../../DEVELOPMENT_PLAN/phase-33-per-model-convergence-and-inference-tests.md, ../../DEVELOPMENT_PLAN/phase-34-plan-truth-governance.md
**Generated sections**: none

> **Purpose**: Define the non-negotiable completion proof for jitML's documented
> model surface so documentation, implementation, demo rendering, and tests cannot
> treat catalog rows, fake scaffolds, or representative smoke checks as product
> completion.

## Current Product State

The current product chain is closed after Phase `31` aggregation in
[../../DEVELOPMENT_PLAN/README.md](../../DEVELOPMENT_PLAN/README.md). The
55-row product matrix, standing external-truth gates added by Phases `32`–`34`,
and refreshed `linux-cpu`/`linux-cuda`/`apple-silicon` evidence are the required
inputs. Phase `31` joined those committed fragments on `linux-cpu`: **55**
ProductRows per lane and **165** lane-row evidence records across the three
report artifacts under
[../../DEVELOPMENT_PLAN/attestations/](../../DEVELOPMENT_PLAN/attestations/).
Historical green runs remain dated evidence for the surfaces they actually
exercised. The 2026-07-05 realness audit, below, explains why those standing
gates are required.

> **2026-07-05 realness-audit reopen.** The audit found the Phase `19`–`31`
> closure was **satisfiable by fabrication**: every gate that graded a product
> row was authored and tuned by the same process it graded, so a row could pass
> with no real learning. A `convergenceBar` could be set equal to the measured
> value it checked; an `InferenceEligible` reference could be minted from a
> fabricated `CompletedTraining` witness; the "scaffold lint" was only a denylist
> of the previous iteration's fossil names; and an RL row's "measured" reward was
> a scripted expert controller rather than a rollout of the trained policy.
> Because these gates were **self-referential** — the grader and the graded were
> the same process — more internal validation could not close the gap. The
> no-caveat product claim was therefore reopened until each row was graded
> against external ground truth the implementer cannot author or tune, by the
> harness in
> [../../DEVELOPMENT_PLAN/phase-32-external-truth-realness-harness.md](../../DEVELOPMENT_PLAN/phase-32-external-truth-realness-harness.md),
> [../../DEVELOPMENT_PLAN/phase-33-per-model-convergence-and-inference-tests.md](../../DEVELOPMENT_PLAN/phase-33-per-model-convergence-and-inference-tests.md),
> and [../../DEVELOPMENT_PLAN/phase-34-plan-truth-governance.md](../../DEVELOPMENT_PLAN/phase-34-plan-truth-governance.md).
> Those phases own the harness; this contract states the bar, not its
> implementation.

The completion bar is intentionally stricter than "a command exists" or "a row
appears in a generated matrix". A row is complete only when the same canonical
product row is implemented, trainable, checkpointed, rendered, covered by
integration tests, covered by e2e tests, and validated on the selected real
substrate lane. As of the 2026-07-05 realness audit that bar is additionally
gated by the four external-truth conditions in
[Realness Completion Bar](#realness-completion-bar-2026-07-05); a row that clears
every earlier field but fails any one of them is **not** complete.

## Realness Completion Bar (2026-07-05)

Superseding the self-referential gates called out in the reopen note above, a
product row is `complete` **only when all four external-truth conditions below
hold**, in addition to every field in [Canonical Product Matrix](#canonical-product-matrix)
and every rule in [Real-ML Rules](#real-ml-rules). These conditions are graded by
the Phase `32`–`34` harness against ground truth the implementer cannot author or
tune; this section names the obligation and the plan owns the implementation.

1. **The committed negative control is rejected by the gate.** Each row ships a
   committed known-fake artifact — an untrained random-init checkpoint, a
   below-bar trained model, a scripted-controller RL trace, or a dense layer
   mislabelled as convolution — paired with the gate that must *reject* it. The
   row is not complete until the `jitml-negative-controls` stanza
   ([../../DEVELOPMENT_PLAN/phase-32-external-truth-realness-harness.md](../../DEVELOPMENT_PLAN/phase-32-external-truth-realness-harness.md))
   fails the build on acceptance. A gate that cannot reject its own known-fake is
   a failure, not a pass.
2. **The convergence bar is a frozen external literature constant.** The row's
   `convergenceBar` is an external, checked-in literature target that is **never**
   derived from, tuned to, or set equal to the measured value it checks. No
   threshold may be a function of the value it grades.
3. **The reported metric is recomputed at read time from the served artifact
   (provenance binding).** Every convergence or inference number shown for the row
   is recomputed at read time from the served checkpoint bytes, not read back from
   a declared field. A stand-in is typed `Declared` and can never be surfaced as
   `Measured`/`Real`.
4. **RL reward is a rollout of the trained policy.** An RL row's reward is a
   rollout evaluation of the *trained policy* through the production device seam
   (`rleSyntheticTransitionEvidence = False`, median over `k` seeds at or above
   the external bar), validated by the `jitml-model-convergence` stanza
   ([../../DEVELOPMENT_PLAN/phase-33-per-model-convergence-and-inference-tests.md](../../DEVELOPMENT_PLAN/phase-33-per-model-convergence-and-inference-tests.md)).
   A scripted or expert controller reward can never close an RL row.

The `Measured`/`Declared` split, the frozen external bars, the
recompute-at-read-time provenance binding, and the evidence-derived closure guard
that stops status drifting from reality live in Phases `32`–`34`; this contract
does not duplicate them.

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
render `*-demo-weights`; Phase `28` converts that browser proof into one
integration/e2e evidence row per ProductRow and keeps the active work on the
per-row `linux-cpu` report card.

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
identity is not enough to close a phase. As of the 2026-07-05 realness audit, the
`Negative` cell is closed only by a committed known-fake that the row's gate
*rejects* under the `jitml-negative-controls` stanza, and the `Integration` cell
is closed only when the row's measured metric clears its frozen external bar under
the `jitml-model-convergence` stanza; both stanzas are owned by
[../../DEVELOPMENT_PLAN/phase-32-external-truth-realness-harness.md](../../DEVELOPMENT_PLAN/phase-32-external-truth-realness-harness.md)
and [../../DEVELOPMENT_PLAN/phase-33-per-model-convergence-and-inference-tests.md](../../DEVELOPMENT_PLAN/phase-33-per-model-convergence-and-inference-tests.md).

## Phase Validation Boundary

Phases `19` through `31` implement this contract in order. Phases `19` through
`28` close on `linux-cpu` only. Phase `29` closes on `linux-cpu` plus
`linux-cuda`. Phase `30` closes on `linux-cpu` plus `apple-silicon`. Phase `31`
is a `linux-cpu`-only aggregation phase that consumes committed lane artifacts
and does not rerun accelerator lanes. The Phase `31` join requires all three
committed report-card fragments to carry every current `ProductRow.rowId`, the
row's catalog/integration/e2e/negative evidence, and the lane-specific
`DeviceEvidence` cell.

Phases `32` through `34`, added by the 2026-07-05 realness audit, extend this
boundary on `linux-cpu` only and introduce no accelerator gate. Phase `32`
installs the `jitml-negative-controls` stanza, the frozen external bars, and the
provenance binding; Phase `33` installs the per-model `jitml-model-convergence`
suite; Phase `34` makes closure status evidence-derived and installs the
standing adversarial realness audit. Those phases reclosed on 2026-07-06 after
`jitml-negative-controls` passed **3 / 3** and `jitml-model-convergence` passed
**111 / 111** on `linux-cpu`. The plan in
[../../DEVELOPMENT_PLAN/README.md](../../DEVELOPMENT_PLAN/README.md) owns their
sprint status; this contract does not duplicate it.
