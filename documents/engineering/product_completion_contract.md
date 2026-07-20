# Product Completion Contract

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: ../../README.md, ../documentation_standards.md, README.md, checkpoint_format.md, training_workloads.md, purescript_frontend.md, unit_testing_policy.md, numerical_core.md, run_contract.md, ../../DEVELOPMENT_PLAN/README.md, ../../DEVELOPMENT_PLAN/phase-19-product-truth-gates.md, ../../DEVELOPMENT_PLAN/phase-22-canonical-matrix-and-dataset-integrity.md, ../../DEVELOPMENT_PLAN/phase-24-real-supervised-architectures.md, ../../DEVELOPMENT_PLAN/phase-25-real-rl-algorithms-and-environments.md, ../../DEVELOPMENT_PLAN/phase-21-type-state-dsl-and-inference-eligibility.md, ../../DEVELOPMENT_PLAN/phase-27-demo-all-model-rendering.md, ../../DEVELOPMENT_PLAN/phase-28-per-model-integration-and-e2e.md, ../../DEVELOPMENT_PLAN/phase-29-linux-cuda-product-lane.md, ../../DEVELOPMENT_PLAN/phase-30-apple-silicon-product-lane.md, ../../DEVELOPMENT_PLAN/phase-31-no-caveat-product-aggregation.md, ../../DEVELOPMENT_PLAN/phase-32-external-truth-realness-harness.md, ../../DEVELOPMENT_PLAN/phase-33-per-model-convergence-and-inference-tests.md, ../../DEVELOPMENT_PLAN/phase-34-plan-truth-governance.md
**Generated sections**: none

> **Purpose**: Define the non-negotiable completion proof for jitML's documented
> model surface so documentation, implementation, demo rendering, and tests cannot
> treat catalog rows, fake scaffolds, or representative smoke checks as product
> completion.

## Status Ownership

Current phase state, remaining work, blockers, and validation evidence live only
in [Development Plan → Closure Status](../../DEVELOPMENT_PLAN/README.md#closure-status).
This document states the product bar and does not infer closure from historical
pass counts or committed report artifacts.

The 2026-07-05 realness audit established a lasting design constraint: a product
gate must not be satisfiable by a self-authored measured value, fabricated
completion witness, scripted-controller reward, or name-based scaffold denylist.
That finding motivates the external-truth conditions below. The run mechanism
that prevents raw or partial evidence from manufacturing completion is
[Typed Run Contract](run_contract.md).

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
| `productCapability` | Closed executable capability carrying a kind-indexed plan descriptor and same-kind evidence requirements. An unsupported declaration carries only its reason and cannot project into an executable scenario. |
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

`projectProductRow` is the one refinement boundary from a raw registry row to
an opaque, kind-indexed `ProductProjection`. It validates the declaration,
budget kind, convergence bar, descriptor/row-class agreement, and complete
resolved workload plan, then retains the semantic `PlanId`, exact execution
descriptor, evidence requirements, substrate, and internal executor command.
`projectProductRows` additionally rejects duplicate identities and returns an
opaque, order-preserving `ProductProjectionBatch`. Workflow cells, execution,
and completed-report joins consume that batch; none may reinterpret `rowClass`
or copy plan inputs from registry labels. The transitional optional evidence
handle fields on the raw row side are rejected when populated and are removed
by Sprint `21.4`; they are not completion evidence.

`trainingBudget` is the row's real execution schedule, not a report-card
default. Supervised ProductRows use the `5`- or `10`-epoch schedule registered
for that row. Traditional RL ProductRows use the aggregate environment
transition count derived by `JitML.RL.ProductBudget`; that count includes
vector-environment multiplicity and each trainer's indivisible rollout,
episode, ARS-direction, or HER-episode granularity. The smaller RL requested
step floor is only an input to that planner. The report-card knobs
`sl_epochs=5` and `rl_steps=100_000` parameterize canonical measurement
stanzas; neither value is ProductRow completion evidence, and neither can mint
`CompletedTraining`.

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
own transcript/game id. The checkpoint manifest carries a `CompletedTraining`
witness with the initial/final policy-value network hashes, positive generation
count, passing per-game arena win-rate observation, and an opaque
`AdmittedCompletedCheckpoint` from the Store loader boundary.

## Type-State DSL Contract

It must be impossible to represent "run inference on an untrained model" in the
DSL accepted by product commands. The generic transition from raw request to
opaque completed evidence is owned by
[Typed Run Contract](run_contract.md). The product pipeline is its model-facing
projection: declared, running, completed-training, and inference-eligible phases
have phase-specific payloads rather than one record whose independent `Maybe`
fields can disagree.

`CompletedTraining` is refined from the exact observed unit-indexed budget,
initial/final learned-state hashes, measured positive update counters,
dataset-read provenance where applicable, finite criterion-evaluated
measurements, TensorBoard metadata, and matching `PlanId`. Product reporting
does not admit that caller-held value directly. Store first re-reads the exact
persisted manifest and physical payload graph and returns opaque
`AdmittedCompletedCheckpoint`. A private kind-indexed
`ProductScenarioCompletion` accepts only that value when its manifest
experiment, canonical `rowId`, manifest/completion `PlanId`, full completion
identity, budget/evidence kind, criterion, every dimensionally defined
update-count relation, and family-specific runtime provenance exactly match the
row projection. Traditional RL retains its admitted positive measured trainer
count without equating it to the current descriptor that mixes iterations,
transitions, and optimizer epochs; Sprint `25.4` owns that typed exact
comparison. Only a successful opaque
`CompletedRunEvidence` carrying that completion can mint reportable scenario
evidence; the evidence retains the admitted manifest SHA. The final report is
an opaque batch join that rejects missing, duplicate, orphan, wrong-plan, and
wrong-lane scenarios. A freely constructible `passed` boolean, declared
metric, checkpoint pointer, caller-held completion, generic evidence payload,
or direct CBOR/Dhall decode cannot cross either boundary.

Supervised V2 makes that provenance distinction nominal. The ProductRow
publisher writes `RawProductRowProjectionOrigin`, which must resolve the row and
`PlanId` to exactly one supported-substrate projection and use the row's
authoritative experiment hash. Public/daemon supervised commands write
`RawGenericSupervisedExecutionOrigin(rowId, canonicalPlanTransport)` with their
canonical row identity, exact plan transport, and a non-product experiment
identity. In both cases the addressed row/origin composite binds canonical row
semantics; `PlanId` alone does not. A passing generic-origin V2 can satisfy its
own inference-eligibility checks, but it cannot be admitted as ProductRow
scenario/report evidence. A finite below-bar generic run is successful training
with no eligible checkpoint or completed-checkpoint event; absence of optional
legacy weight-list projections does not change that miss. It is not a failed
metric disguised as product completion. The exact wire rules are owned by
[Checkpoint Format](checkpoint_format.md#frozen-v1-and-exact-supervised-v2).

Product-origin admission also checks observations rather than declarations. The
publisher requires exact processed examples and constructs the canonical four
finite metric rows (`train_loss`, `validation_loss`, `examples_processed`, and
the row's named held-out convergence metric). V2 refinement then binds every
completed convergence observation to one unique equal-valued manifest row,
binds TensorBoard run/prefix/tags to the manifest experiment and completed
metric names, and requires runtime, manifest, and completion dataset digests to
equal the canonical pinned training/evaluation read digest for that row.
Completed-checkpoint publication additionally requires the current-pointer CAS
to return `PointerWritten` for that exact manifest before the event is emitted;
a retained immutable snapshot with a pointer conflict is not product adoption.

Publisher eligibility requires a second read boundary after that write. The
exact stored address is re-admitted through Store; the stored/admitted manifest
SHA, projected `rowId` and `PlanId`, complete `CompletedTraining`, canonical
row lookup, and family runtime provenance must all agree before the row counts
as eligible. Supervised ProductRows require Product-origin V2. RL, AlphaZero,
and tuning retain canonical non-supervised Product V1, but their exact
trajectory, self-play transcript, or tuning-v2 transcript is written first and
its content-addressed receipt is bound into the manifest. The full publisher
batch and independent integration inventory require all 55 projections in
registry order, 55 unique admitted manifest addresses, canonical unique
companion keys, no missing/orphan/substituted pointer, and exactly one
tuning-v2 transcript.

That tuning transcript binds `row-id`, `plan-id`, experiment hash,
dataset-at-read SHA, best-final-JMW1 SHA, and the exact ordered contiguous trial
executions. It is valid only when exactly one execution is promoted and equals
the selected best trial, all persisted numerical values are finite, observed
trial/update counts match completion, and completion contains exactly one
equal-valued `best_objective` measurement.

Dhall selectors and checkpoint manifests are raw persisted DTOs. Store loaders
start from an opaque persisted address, verify the exact manifest and physical
blob bytes, re-run semantic refinement, and return opaque
`AdmittedCompletedCheckpoint` only when artifact identity and completed evidence
agree. Missing, partial, synthetic, seeded-demo, failed-training, wrong-plan, or
non-finite provenance remains a typed rejection before any substrate runner
receives weights.

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

The all-row form above is orchestration shorthand. Each projected row's exact
executor argv is
`jitml internal train-and-publish-product-rows --<substrate> --row <rowId>`.
The authoritative row selector rejects repeated/multi-row values
and conflicts with `JITML_PRODUCT_ROW_FILTER`; execution uses direct
`InProcessRun` placement and consumes the projection's seed, budget, dimensions,
RL vector-environment count, and kind-indexed descriptor. The semantic
`JITML_PRODUCT_SL_*`, `JITML_PRODUCT_RL_*`, `JITML_PRODUCT_AZ_*`, and
`JITML_PRODUCT_TUNE_*` override families do not alter this path. When a live
report requests product evidence, absence of an opaque completed-scenario
journal is a failure, not an omitted report section.

## Test Contract

Every product row owns all of the following test evidence:

| Evidence | Required behavior |
|----------|-------------------|
| Catalog parity | Generated docs/browser matrix exactly matches the typed product matrix. |
| Integration | The row trains through the real command path and common run interpreter, verifies data, updates learned state, reaches terminal success, satisfies its exact event/evidence contract, writes a completed checkpoint, rejects inference before completion, and records the resulting `CompletedRunEvidence` journal rather than reconstructing evidence from declarations or synthetic row-local hashes/curves. |
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

The product proof follows the project's single-accelerator phase rule and joins
lane evidence only through the plan's designated aggregation phase. Exact phase
order, lane assignment, reopen status, blockers, and current validation evidence
live in [Development Plan → Closure Status](../../DEVELOPMENT_PLAN/README.md#closure-status).

## Cross-References

- [Typed Run Contract](run_contract.md)
- [Training Metrics and Data Splits](training_metrics_and_splits.md)
- [Checkpoint Format](checkpoint_format.md)
- [Unit Testing Policy](unit_testing_policy.md)
- [Development Plan](../../DEVELOPMENT_PLAN/README.md)
