# Product Completion Contract

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: ../../README.md, ../documentation_standards.md, README.md, checkpoint_format.md, training_workloads.md, purescript_frontend.md, unit_testing_policy.md, numerical_core.md, run_contract.md, ../../DEVELOPMENT_PLAN/README.md, [legacy-to-new phase map](../../DEVELOPMENT_PLAN/README.md#legacy-to-new-phase-map), [Phase 223](../../DEVELOPMENT_PLAN/phase-223-product-registry-plan-and-admitted-evidence-projection.md), [Phase 229](../../DEVELOPMENT_PLAN/phase-229-phase-specific-product-evidence-payloads.md), [Phase 236](../../DEVELOPMENT_PLAN/phase-236-checkpoint-admission-single-path.md), [Phase 246](../../DEVELOPMENT_PLAN/phase-246-completedtraining-sl-manifests.md), [Phase 249](../../DEVELOPMENT_PLAN/phase-249-per-row-convergence-and-evidence.md), [Phase 278](../../DEVELOPMENT_PLAN/phase-278-external-bars-no-self-referential-gate-lint-and-exact-served.md), [Phase 285](../../DEVELOPMENT_PLAN/phase-285-contract-driven-per-model-evidence.md), [Phase 286](../../DEVELOPMENT_PLAN/phase-286-evidence-derived-closure-guard.md), ../../DEVELOPMENT_PLAN/phase-261-contract-driven-live-execution-integration-journal.md, ../../DEVELOPMENT_PLAN/phase-262-contract-driven-live-execution-browser-and-playwright.md
**Generated sections**: none

> **Purpose**: Define the non-negotiable completion proof for jitML's documented
> model surface so documentation, implementation, demo rendering, and tests cannot
> treat catalog rows, fake scaffolds, or representative smoke checks as product
> completion.

## Current Status

**Refactor boundary.** The campaign/resource contracts below are targets. Current
implementation does not acquire their safety or qualification authority from
this documentation change; execution order and pending work live in the
[validation foundation refactor](../../DEVELOPMENT_PLAN/README.md#validation-foundation-refactor).


**Implemented today.** Every ProductRow uses one self-describing checkpoint
envelope with a typed payload variant: supervised-graph for the exact trained
`LayerGraph`, or weight-only for RL, AlphaZero, and tuning. Store admission binds
the persisted envelope payload, exact snapshot commit/descriptor and scoped
payload objects, closed execution origin, exact plan, measured completion, and
manifest before inference, browser rendering, or report eligibility. The former V2-
versus-V1 distinction is historical and has no current parallel wire.

## Complete Campaign Qualification Target

**Target; requires the reopened campaign and lane implementation.** A complete
lane is exact coverage of every required ProductRow under one immutable source,
criterion and execution epoch, admitted through production APIs. It is not
inferred from a process exit, a row count or a set of unrelated readiness passes.
The authority and recovery rules are owned by
[typed run contracts](run_contract.md#qualification-campaign-target) and
[validation execution](validation_execution.md).

Only whole prescribed cohorts with authentic initial/final artifacts, fixed
seeds, fixed served index, measured work, real selected-device evidence,
Store/replay and completed preservation seals qualify. Every attempt is retained;
interruption neither certifies unfinished work nor permits seed replacement or
hidden scientific retries. The final exact join and required browser/integration/
standing checks remain mandatory. The new protocol does not retrospectively
admit old interrupted command scopes.

CPU, CUDA and Apple qualification have separate execution owners and real host
prerequisites. Aggregation consumes their admitted portable objects without
rerunning accelerator training. A missing device blocks its own lane; no
unrelated Mac qualification is a prerequisite for CPU behavioral assurance.
Learned-weight dependence is a required behavioral control, not proof that an
arbitrary algorithm implements correct learning.

Learning and realness predicates are independent of operational scheduling.
Prospectively revised recipes or criteria require independent justification and
a new epoch. A floor fitted to a failing qualifying result is not independence;
a repeatedly inspected evaluation is not unseen evidence. Fixed numeric constants
are not intrinsically correct, and naming one literatureTarget proves no origin.
See [metric and split discipline](training_metrics_and_splits.md).


## Status Ownership

Current phase state, remaining work, blockers, and validation evidence live only
in [Development Plan → Closure Status](../../DEVELOPMENT_PLAN/README.md#closure-status).
This document states the product bar and does not infer closure from historical
pass counts or committed report artifacts. That state is projected from committed
validation evidence rather than typed: `jitml docs status` derives each sprint's
status, the open chain, and every unmet obligation, and a sprint is Done only when
its obligations are proven by evidence (see
[Typed Run Contract → validation records](run_contract.md)).

The product contract carries a lasting realness constraint: a product
gate must not be satisfiable by a self-authored measured value, fabricated
completion witness, scripted-controller reward, or name-based scaffold denylist.
That finding motivates the external-truth conditions below. The run mechanism
that prevents raw or partial evidence from manufacturing completion is
[Typed Run Contract](run_contract.md).

The current product-truth source scanner detects registered fossil names and
forbidden reachable imports. It does not establish generic output dependence on
trained weights; the stronger behavioral detector remains an unmet contract in
[Phase 225](../../DEVELOPMENT_PLAN/phase-225-scaffold-lint-reachability.md#remaining-work).

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

1. **The committed negative control is rejected by the gate.** Completion
   requires each row to own a committed known-fake artifact — an untrained
   random-init checkpoint, a below-bar trained model, a scripted-controller RL
   trace, or a dense layer mislabelled as convolution — paired with the gate that
   must *reject* it. The current `jitml-negative-controls` stanza commits
   hand-built pure gate-soundness controls together with known-invalid
   requests, event streams, and Store-admission journals (missing, zeroed,
   foreign, or mismatched manifest identity, caller-held completion, storage
   without admission), each rejected for the specific reason it names, plus
   the live interpreter's lifecycle (settlement, timeout, cleanup, terminal
   ordering) and, for every `ProductRow`, an invalid request, a wrong-plan
   event, and a foreign admission, with a guard that fails the stanza when a
   row has no registered controls. A gate that cannot reject its own
   known-fake, or rejects it for the wrong reason, is a failure, not a pass.
2. **Acceptance rules are independently fixed before qualifying execution.**
   Compact SL uses the five-run paired predictive-learning contract in
   [the CLI doctrine](../../README.md#threshold-methodology): canonical base
   plus `0..4`, original served index `0`, at least three joint learning successes,
   full-cohort median against unchanged floors, and independent served-model
   eligibility. Exact initial/final serving replay, authentic complete outcomes
   and source-bound cohort admission are required; a singleton checkpoint or
   stored pass flag does not supply them. Historical SL floors retain their
   true measured-calibrated/unproven origins as additional restrictions; they
   are not published-model anchors. Phase `278` owns validation of the
   implementation and actual five-run evidence for this contract. Its opaque
   qualification/publication and current journal boundaries are specified in
   [Checkpoint Format](checkpoint_format.md#compact-supervised-qualification). The SL rule does not justify
   RL's separate target/slack criteria. Existing numeric bar representation is
   `literatureTarget − slack`; its field names alone prove no external origin.
   New rules or constants may not be fitted to the qualifying final values. See
   [training_metrics_and_splits.md](training_metrics_and_splits.md#current-status)
   for the enforcement boundary. Three existing checks enforce structural bar
   consistency; none proves independent provenance or the new cohort qualification:
   - *Source lint.* `JitML.Lint.ProductTruth` (run by `jitml check-code`) reads
     each `src/` file that mentions a bar constructor or target field as a token
     stream, so a field split over lines, an argument on its own line, or a value
     bound in a `let` or `where` block cannot hide a violation. Outside
     test-support code (`src/JitML/Test/`, which builds known-fake bars on
     purpose), no bar target, slack, or threshold may mention a measured value,
     directly or through any chain of bindings in its declaration. A measured
     value is recognised by name: an identifier containing `measured`, or one of
     the observation accessors `coMetricValue`, `metricValue`, and
     `observedValue`. Every numeric argument of `mkConvergenceBar`,
     `regressionRmseBar`, the positional `ConvergenceBar` constructor, or a bar
     record must be a numeric literal or a projection of the canonical threshold
     tables, a selector applied as the whole argument; the cohort-threshold
     constructors accept literals only. A helper-wrapped or renamed value, or a
     table value with a helper's value added to it, has no provenance the lint
     can see, so it is rejected rather than trusted. The lint is lexical. It
     checks every numeric position a constructor names, saturated or not, and
     reads what follows a `$` as the last argument, but it does not follow a
     partially applied or aliased constructor through `uncurry`, an operator
     section, an applicative chain, or a local alias. It excuses a constructor or record pattern whose `=`,
     `->`, or `<-` is on the line where the pattern ends, and reads a pattern
     whose arrow or guard is on a later line as an application. It reads a
     binding only when its `=` or `<-` shares the binder's line (the layout
     fourmolu produces), and cannot tell a literal calibrated to a measurement
     from one that was not. It walks `src/` only, the file set of
     `checkProductTruth`.
   - *Registry cross-check.* A unit test rebuilds all 55 ProductRow bars from the
     canonical tables without calling the code that builds them (the regression
     and tuning rows have no table, so their constants are pinned in the test) and
     requires the metric name, goal, literature target, slack, and threshold to be
     equal, so a registry constant that is not a table constant fails. It does not
     pin the table values themselves.
   - *Completion gate.* `assertConvergenceObservationsAgainstBar` is called by
     `validateCheckpointCompletion`, which Store runs on every completed
     checkpoint it writes or admits, whenever the manifest resolves to a
     ProductRow. It admits a completed run only when the run carries exactly one
     observation of the row's metric, whose goal, threshold, value, and
     re-derived verdict agree with the row's own bar. (With a single observation
     the value comparison holds by construction; it bites when the metric is
     observed twice, where it names the second value.) The retained `linux-cuda`
     lane journal is admitted through the production reader in a permanent unit
     test that requires all 55 of its rows to pass this gate.
3. **The reported metric has exact served-artifact provenance.** For a
   supervised ProductRow, the publisher carries the verified held-out inputs
   until Store re-admits the persisted checkpoint. It then prepares the same
   serving graph from the admitted manifest and physical `supervised.weights`
   tensor, recomputes accuracy or RMSE across the exact evaluation budget, and
   blocks eligibility if the completed metric disagrees. A byte replacement at
   an existing address fails Store admission; coherently readdressed manifest
   or weight replacements with a stale metric fail the independent served
   evaluation. The comparison allows `min 0.01 (1/n + 1e-9)` for classification
   accuracy over `n` held-out examples and `0.005 × max(1, |reported|)` for
   standardized regression RMSE (the raw served-versus-target error divided by
   the positive target scale). Every supervised row evaluates exactly 1,000
   examples, where the accuracy allowance is one flipped decision; for fewer than
   100 examples one decision exceeds the cap, so even a single flip is rejected,
   which is intentional. The full statement of the bounds, and of what they do
   not claim across substrates, is in
   [determinism_contract.md](determinism_contract.md#the-contract). A non-finite
   reported metric or regression target, a non-positive scale, an empty example
   set, a class label outside the runtime output, and a metric name that does not
   fit the evidence kind are typed rejections, not measurements. The check runs
   after the checkpoint is written and admitted, because only an admitted
   checkpoint can be served: a rejected checkpoint remains in Store, the row is
   denied eligibility, and the supervised publisher never reuses a prior
   checkpoint because a persisted manifest carries no held-out example set. Only
   the 11 supervised rows are recomputed from served bytes; RL, HER, AlphaZero,
   and tuning metrics are not. The portable aggregate admits authenticated lane
   journals and their manifest/measurement digests after that live check; it
   cannot re-fetch a released lane's physical checkpoint scope. The broader
   read-time recomputation of every displayed product number in the Exit
   Definition is not claimed by this supervised gate. A stand-in remains typed
   `Declared` and cannot be surfaced as `Measured`/`Real`.
   Supervised ProductRow publication eligibility also checks the exact served outputs against the
   label-only majority and exact-binomial classification rules, or strict
   positive held-out R² for regression. These additive learning-signal checks
   use integer counts and actual prediction vectors independently of the
   provenance tolerances. A constant model can have perfect metric provenance
   and still be rejected. The policy is versioned in supervised scenario
   contract digests, making earlier journals stale for those rows. The precise
   rules and their statistical scope live in
   [Training Metrics and Splits](training_metrics_and_splits.md#additional-held-out-learning-signal-policy).
   They supplement the historical floor. The independently reviewed compact
   qualification additionally requires exact paired improvement, all-five median
   and original index-zero eligibility. Phase `278` owns its final validation
   and actual qualification evidence.
   The approved generic regression `reg-ord1` recipe additionally binds the full
   epoch-order contract into regression ProductRow/cohort PlanIds and regression
   report digests. Its finite quality criteria remain unchanged. Earlier failed
   attempts remain evidence of their original recipe; new qualification requires
   fresh complete five-seed runs under the changed identity. The already-seen
   held-out results informed this approved revision, so the successor is not an
   independent hold-out confirmation. Exact ordering semantics are specified in
   [Determinism Contract](determinism_contract.md#the-contract).
   The scalar gate does not add a checkpoint companion or rerun on general
   weighted inference. Compact qualification is a separate detached object,
   bound to the index-zero Store admission through its publication reference;
   it is not a Store-owned learning-eligibility refinement. Current optional
   remote publication is mandatory for parsed scenario binary attempt records;
   every new or already-identical remote write requires exact-byte readback.
   Direct local publication remains explicitly offline-capable.
   A post-check rejected artifact can
   remain structurally completed and physically admitted while its ProductRow
   publication is denied. The authenticated product browser catalogue requires
   the current scenario digest and live admitted row evidence separately.
4. **RL reward is a rollout of the trained policy.** An RL row's reward is a
   rollout evaluation of the *trained policy* through the production device seam
   (`rleSyntheticTransitionEvidence = False`, median over `k` seeds at or above
   the external bar). The `jitml-model-convergence` stanza
   ([Phase 285](../../DEVELOPMENT_PLAN/phase-285-contract-driven-per-model-evidence.md))
   grades each row's opaque completed-run evidence, minted only from the
   validated projection and the admitted retained lane-journal row, against a
   criterion re-derived independently from the canonical tables. The compact row
   metric records the median final reward; current native qualification also
   requires complete original evaluation graphs and raw parent capture,
   physically re-audited through the authenticated lane reader (see
   [training_metrics_and_splits.md](training_metrics_and_splits.md#per-model-completed-run-evidence)).
   A scripted or expert controller reward can never close an RL row.
   These requirements retain current evidence limits: singleton completed models
   and repeated episodes do not supply five training runs. QR-DQN, continuous,
   HER and arena neural scoring use their selected device. Raw numerical returns
   do not establish process/source origin or learning. ARS's non-MLP path uses
   checked host provenance instead of a neural witness. Durable prepared capture, independent comparison
   inputs, authenticated five-run qualification and exact physical policy replay
   remain distinct obligations; see
   [Training Metrics and Splits](training_metrics_and_splits.md#current-final-policy-runtime-scope).

The `Measured`/`Declared` split, external bars, served-byte provenance binding,
and evidence-derived closure guard are owned by Phases `278`–`289`; this
contract records the current implementation and its limits.

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
or copy plan inputs from registry labels. Raw `ProductRow` values contain no
optional evidence-handle fields: Sprint `21.4` removed them, so
phase-specific evidence can enter only through its nominal validated boundary.

`trainingBudget` is the row's real execution schedule, not a report-card
default. Supervised ProductRows use the `10`-, `15`-, or `40`-epoch schedule
registered for that row. Traditional RL ProductRows use the aggregate environment
transition count derived by `JitML.RL.ProductBudget`; that count includes
vector-environment multiplicity and each trainer's indivisible rollout,
episode, ARS-direction, or HER-episode granularity. The smaller RL requested
step floor is only an input to that planner. The RL plan carries no declared
optimizer-update quantity: the removed field combined PPO iterations, fixed
environment steps, ARS iterations, and HER episodes under one misleading name.
Optimizer applications are instead an opaque positive measurement returned by
the trainer that performed them. The report-card knobs
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

   For neural execution, the recorded device cell is minted from a `DeviceExecutionWitness`
   (`JitML.Product.DeviceWitness`). That type has no exported constructor and no
   pure smart constructor: `witnessDeviceExecution` runs in `IO`, requires the
   compiled artifact the engine reported to be present at the path the engine
   reported, resolves that path in the caller's working directory to an absolute
   canonical coordinate, digests its bytes, and records the execution-family backend
   and executed identity. Parent/child comparisons retain all six witness fields;
   different working directories do not change the coordinate of one shared artifact.
   Loadable layer-graph kernels expose `jitml_layer_training_backend`;
   the Apple layer graph uses its fixed-bridge identity. MLP execution keeps the
   selected engine backend and reads the executed family through
   `jitml_kernel_family_name`, or the `family` field of its Metal source metadata.
   The [supervised family binding](checkpoint_format.md#compact-supervised-qualification)
   selects the exact expected identity from the typed projection. The
   witness is recorded after the training loop returns successfully, bound to
   the run's `TrainingEvidence`, and carried into the completion; checkpoint
   admission (`requireAdmittedCompletedCheckpoint`) rejects a completion that
   carries none, so `AdmittedCompletedCheckpoint` exposes the witness totally
   and the lane fragment renders it with no no-evidence branch. There is no
   remaining path that composes the cell from a declared substrate and a
   declared claim.
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
must have a concrete threshold, and the measured median is computed over the
complete finite `EvaluationSet` keyed by the exact planned episode ids. The
median or HER goal metric must pass that threshold, policy-or-Q hashes must
change across the trainer-returned positive update count, the measured physical
transition count must exactly exhaust the RL budget, and that same transition
count must be the checkpoint/completion step. Synthetic or reconstructed
transition counters, partial or tail-only evaluation cohorts, missing
thresholds, initialized-only checkpoints, and generic self-thresholded metric
fallbacks cannot mint `CompletedTraining` for RL rows.

Generic RL checkpoints carry the actual compiled plan in their completion,
including the algorithm and environment. `bindCompletedTrainingToRlPlan`
recompiles its canonical transport and binds its derived `PlanId` and exact
environment-transition count to the completion, rejecting a contradictory
budget seed when one is present. Raw completion decoding repeats
those checks. Structural checkpoint admission then requires exactly the
cohort's own convergence criteria, rejects another cohort's threshold and
unrelated or duplicated observations, and re-evaluates each measurement. HER
requires both goal success and achieved-goal distance. A generic RL completion
without this plan cannot be admitted as completed. Canonical ProductRows retain
their independent row-bound bar checks; unbound canonical RL completions also
require the exact projected `PlanId` and budget for their measured device
substrate. Renaming an experiment cannot substitute a generic run's cohort or
authorize canonical row evidence. A manifest that claims an RL policy requires
an environment-transition completion budget.

The target generic ARS path retains a separate actual host origin over the same
prepared numerical loop and full compiled plan. Its generic experiment,
`generic-compiled-plan-attempt-v1` context, applied work, initial/final JMW1 and
physically fetched trace bind that singleton completion; no MLP execution
witness or canonical row identity is invented. Actual unchanged quality checks
still apply. A positive generic evaluation count describes episodes of one
training run, not independent training seeds. The canonical native requirement
remains all five fixed training runs, strict effective-initial gain, the
independent reference rules, full-five old-quality medians, three joint
successes and independently eligible served index `0`. Generic host publication
cannot satisfy those acquisition or authentication obligations.

The additional plan is carried by the nested `RawCompletedTraining` V3 DTO;
unbound completions retain their exact V2 encoding, including the completions
in retained ProductRow lane journals. This completion DTO version does not
change the single checkpoint envelope or its payload variants.

AlphaZero product rows are game-specific, not a single Connect 4 proxy. Connect
4, Othello, Hex, and Gomoku each resolve their own initial state, observation
shape, action count, self-play command (`--game <id>`), MCTS visit distribution
targets, outcome labels, and policy/value checkpoint tensor name. Self-play
evidence must show network-backed priors and leaf values, persistent per-game
MCTS cache state across moves, deterministic root-noise seeding, and the row's
own transcript/game id. The checkpoint manifest carries a `CompletedTraining`
witness with the initial/final policy-value network hashes, positive generation
count and passing per-game arena win-rate observation. Store's neural loader
then supplies an opaque `AdmittedCompletedCheckpoint` after physical admission;
the manifest itself carries no admission capability.

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
persisted manifest, snapshot commit/descriptor, and scoped payload-object graph,
then supplies physical admission to the addressed report boundary. That boundary
carries opaque `AdmittedExecutionCheckpoint`: its neural arm retains
`AdmittedCompletedCheckpoint`, while its host arm retains the admitted ARS trace.
A private kind-indexed `ProductScenarioCompletion` accepts only that total
value when its manifest
experiment, canonical `rowId`, manifest/completion `PlanId`, full completion
identity, budget/evidence kind, criterion, every dimensionally defined
update-count relation, and family-specific runtime provenance exactly match the
row projection. Traditional RL has no heterogeneous planned optimizer field to
compare against. Its opaque trained artifact instead requires the measured
transition count to equal the exact plan target and the measured optimizer count
to equal `TrainingEvidence`; completion and manifest persistence carry those
same observations without caller reconstruction. Only a successful opaque
`CompletedRunEvidence` carrying that completion can mint reportable scenario
evidence; the evidence retains the admitted manifest SHA. The final report is
an opaque batch join that rejects missing, duplicate, orphan, wrong-plan, and
wrong-lane scenarios. A freely constructible `passed` boolean, declared
metric, checkpoint pointer, caller-held completion, generic evidence payload,
or direct CBOR/Dhall decode cannot cross either boundary.

The cross-process integration boundary preserves those nominal values instead
of flattening them into a successful child exit. The parent command creates one
current run id, journal path, exclusive `0600` HMAC key file, and canonical
executable path/SHA identity and passes them only to the `jitml-integration`
child through an opaque process environment. Child startup validates the whole
bundle, consumes the key once, and unlinks and clears the capability before
Tasty or any ProductRow work. The child can persist only an opaque,
projection-ordered `CompletedProductScenarioReport`; current journal version `5`
authenticates the complete aggregate and all ordered row fields. The parent
authenticates that current-run receipt before semantic admission, then requires
the current projection, the exact ProductScenario invocation carried by the
canonical completion's `RawCompletedTraining` V2 DTO, checkpoint scope,
executable identity, execution/inference chronology, and fresh Store admission
of every recorded manifest address. A missing, partial, stale, reordered, or
wrong-HMAC journal fails closed even when the Cabal process exits successfully.
Each row's finite four-hour command-and-evidence-resolution envelope begins
after its precondition and is operational policy only: expiry cannot mint
completion, contribute a row, or weaken exact observed-budget equality, and a
subsequent attempt starts a fresh scope rather than resuming or reusing partial
roots.

The command allocates each fresh private ProductScenario scope below ignored
`.build/runtime/product-scenario-attempts/`. Original workspaces, issued slots,
reports and available raw attempt payloads remain after success, failure or
managed cancellation; a new command always allocates a new namespace. Scope
cleanup removes only its exact signing-key file, including a setup failure
after partial key creation. Retaining attempt DATA supplies no completion or
admission authority. The browser's repository mount overlays `.build/` with an
empty read-only filesystem; only its separately mounted catalogue, publication
and writable browser scope are available there.

The authenticated parent additionally issues a canonical version-`3` portable lane journal
and its exact detached qualification objects after successful admission.
It retains the complete refined `CompletedTraining` DTO together with the row,
plan, substrate, admitted manifest, inference manifest, execution provenance,
executable, invocation, contract and completion-journal identities. Native
neural rows retain their selected-device witness; ARS rows retain their honest
host reference and cannot satisfy a neural-only witness accessor.

Native row admission requires the original owned parent to verify the full
five-child physical allocation, exact policy-specific data and eleven actual
replays, including the Store-selected index-zero checkpoint. The source journal
binds the resulting native receipt and its complete identity in both row and
aggregate authentication. Re-reading that journal in its live scope rechecks
the retained physical evidence; parsed receipt data cannot construct an owned
execution certificate.

Native child refusal messages preserve bounded typed Candidate findings before
captured outer diagnostics. Parent refusals preserve the nested evaluation stage
and bounded nested diagnostic or refusal before the parent fallback. Missing or
oversized detail supplies no reconstructed cause; error classification and
qualification checks remain unchanged. Rendering follows no retained object
references and does not dump producer, physical or evaluation payloads.

Portable native admission requires a separate IO audit of the pinned lane and
its complete content-addressed bundle. This checks retained bytes and recorded
associations without rerunning training, selecting a device or restoring the
deleted live Store or HMAC authority. It is suitable for later CPU aggregation;
the pure lane reader cannot admit native rows. The wire and sidecar bounds are
specified in [Checkpoint Format](checkpoint_format.md#compact-supervised-qualification).
These implementation boundaries do not establish that any required real lane
journal or qualifying execution has passed; current evidence and remaining
validation are tracked in Phase `278`.

The supervised-graph payload makes that provenance distinction nominal. The ProductRow
publisher writes `RawProductRowProjectionOrigin`, which must resolve the row and
`PlanId` to exactly one supported-substrate projection and use the row's
authoritative experiment hash. Public/daemon supervised commands write
`RawGenericSupervisedExecutionOrigin(rowId, canonicalPlanTransport)` with their
canonical row identity, exact plan transport, and a non-product experiment
identity. In both cases the addressed row/origin composite binds canonical row
semantics; `PlanId` alone does not. A passing generic-origin supervised-graph payload can satisfy its
own inference-eligibility checks, but it cannot be admitted as ProductRow
scenario/report evidence. A finite below-bar generic run is successful training
with no eligible checkpoint or completed-checkpoint event; absence of optional
legacy weight-list projections does not change that miss. It is not a failed
metric disguised as product completion. The exact wire rules are owned by
[Checkpoint Format](checkpoint_format.md#the-self-describing-checkpoint-envelope).

Product-origin admission also checks observations rather than declarations. The
publisher requires exact processed examples and constructs the canonical four
finite metric rows (`train_loss`, `validation_loss`, `examples_processed`, and
the row's named held-out convergence metric). Supervised-graph refinement then binds every
completed convergence observation to one unique equal-valued manifest row,
binds TensorBoard run/prefix/tags to the manifest experiment and completed
metric names, and requires runtime, manifest, and completion dataset digests to
equal the canonical pinned training/evaluation read digest for that row.
Completed-checkpoint publication additionally requires the current-pointer CAS
to return `PointerWritten` for that exact manifest before the event is emitted;
a retained immutable snapshot with a pointer conflict is not product adoption.

Publisher eligibility requires a second read boundary after that write. The
exact stored address is re-admitted through Store. Store validates the one
required `committed.cbor` before final completion refinement: its sorted
canonical-original → exact-scoped → payload-SHA descriptor must reconstruct
the logical manifest, re-derive the snapshot id, and bind every fetched scoped
payload object. A zero-payload-object manifest uses the empty descriptor and is
admissible only with its exact derived commit, although it cannot refine into a
weighted completed product merely because it has no payload objects. Only after
that persisted proof may the stored/admitted manifest SHA, projected `rowId` and
`PlanId`, complete `CompletedTraining`, canonical row lookup, and family runtime
provenance establish eligibility. Supervised ProductRows require a Product-
origin supervised-graph envelope payload. RL, AlphaZero, and tuning retain
canonical non-supervised Product weight-only envelope payloads, but their exact
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
start from an opaque persisted address, verify the exact manifest, commit,
descriptor, and scoped payload-object bytes, re-run semantic refinement, and
return a Store-issued completed admission only when artifact identity and
completed evidence agree. Neural-only admission returns the narrower opaque
`AdmittedCompletedCheckpoint`; total neural-or-closed-host admission returns
`AdmittedExecutionCheckpoint` with the corresponding actual admission fields.
Decoded manifest or host-reference DATA cannot mint either value. Missing, partial, synthetic, seeded-demo,
failed-training, wrong-plan, or
non-finite provenance remains a typed rejection before any substrate runner
receives weights.

Generic `JitML.Service.Workload` object effects cannot create an alternate
product proof: they reject the Store-owned checkpoint `manifests/`, `pointers/`,
`snapshots/`, and `gc/` prefixes before reaching `HasMinIO`.

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
`product-row-*` experiment hashes.

Phase `262` replaces the former best-effort selector list with one
publication-bound, all-or-nothing `CheckpointList`. The daemon reads the
selected substrate catalogue, independently re-admits all 55 exact manifest
addresses, and emits the following identity without partial success:

- the unique `kind`, `call-id`, `panel`, publication `status`, `run-id`,
  `substrate`, catalogue SHA, source-journal SHA, canonical `count: 55`, and
  `selector-state: ready` header;
- one projection-ordered `row-selector` for every row containing ordinal,
  `rowId`, `PlanId`, experiment, manifest SHA, family, explicit `Passed`
  status, empty reason, and demo panel; and
- one projection-ordered `checkpoint-summary` for every selector, repeating
  ordinal and the full row/plan/experiment/manifest identity before step,
  family, positive tensor count, `eligible`, complete budget, measured result,
  and TensorBoard prefix.

The generated PureScript parser is an `Either` boundary, not a permissive UI
decoder. It selects the generated 55-row matrix for the response substrate and
rejects unknown or duplicate header fields, partial/duplicate/orphan/reordered
rows, wrong-lane `PlanId`s, any selector/summary identity or family mismatch,
malformed digests or identities, non-positive tensor counts, non-`Passed`
source evidence, non-empty pass reasons, and any global state other than
`ready`. The panel renders aggregate `Passed`/`Failed`/`NotRun` counts, explicit
status/reason cells, exact identity metadata, and family-specific supervised,
RL, AlphaZero, or tuning cards only after that complete refinement. Static
registry rows remain declaration-only `NotRun` fallback content and display no
substrate-specific `PlanId`; they cannot become live evidence.

Catalogue retention is deliberately archival. Every authenticated,
live-re-admitted immutable catalogue publication attempt writes one append-only
GC root per row before selector CAS, and those roots intentionally override the
ordinary `LastN` checkpoint policy. They survive selector changes and failed CAS
attempts because the selected pointer controls only the current UI view, not the
historical evidence set. Moving or deleting roots inline is forbidden: doing so
can expose a selected catalogue before its roots exist or race a concurrent
publisher. If bounded retention is adopted, an independently synchronized
external lifecycle policy must own it.

Browser REST handlers validate product requests against the ProductRow registry
before any runtime or publisher path runs; non-product hashes, panel/row
mismatches, stale seeded hashes, `*-demo-weights`, missing artifacts, untrained or
partial manifests, and unsupported substrate states return a `503
checkpoint-required` fail-closed envelope instead of a fake result. The
Playwright positive cases are created only from the exact parent-published
catalogue. One authenticated real API/UI load refines the complete publication;
the 55 catalogue `e2e_test` cases then assert their exact row, plan, experiment,
manifest, measured result, status/reason, and family renderer against that same
DOM. Route fixtures exist only in a separate negative suite for malformed,
mismatched, explicit `Failed`, explicit `NotRun`, and unavailable responses. A
retry-aware custom reporter then publishes every
planned row as `Passed`, `Failed`, or reasoned `NotRun` in a separately keyed,
HMAC-authenticated browser journal; this browser result can refine the parent
report but cannot mint integration evidence. The integration journal boundary
does not stand in for its downstream consumers: Phase `262` / legacy Sprint
`28.5` owns browser and Playwright consumption, and Phase `263` / legacy Sprint
`28.6` owns fragment issuance. Their current execution state and dated
validation evidence remain canonical only in
[the development-plan Closure Status](../../DEVELOPMENT_PLAN/README.md#closure-status).

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
| E2E | The exact catalogue-named Playwright case drives the live checkpoint API and panel for that row, asserts its full `rowId`/`PlanId`/experiment/manifest/measured-result/family identity, and contributes one authenticated explicit `Passed`, `Failed`, or reasoned `NotRun` result. |
| Negative | Missing dataset, missing cluster, malformed checkpoint, untrained checkpoint, and unsupported substrate fail closed. |
| Lane | The same row is validated on `linux-cpu`; accelerator phases separately validate `linux-cuda` and `apple-silicon` without requiring both accelerators in one phase. |

Coverage reports must name missing row/test pairs. A pass count without row
identity is not enough to close a phase. The current ProductScenario journal
supplies row-identified integration evidence. Of the two standing realness
stanzas, `jitml-negative-controls` grades known-invalid fixture rejection for the
reason each fixture names (request, event, journal-identity, and lifecycle
controls, and three controls for every `ProductRow` registered from the
registry), while `jitml-model-convergence` grades each row's
completed-run evidence from the selected lane's retained journal (convergence
against an independent criterion, learning telemetry, committed deterministic
performance bounds, and plan/artifact binding, with typed
missing/duplicate/cross-plan failures). The convergence stanza is exactly as
current as the retained journals: it fails closed for a lane whose journal is
stale, and it executes no inference. Neither stanza substitutes for the live
lanes' production obligations.

## Journal Aggregation

`JitML.Test.ProductAggregation` joins the retained, externally pinned portable
journals after production-reader admission against each current lane projection.
Only the registered source paths and digest pins can mint an aggregate; callers
cannot replace that authority with a digest computed from supplied bytes.
The opaque result contains one completed cell per substrate for every ProductRow.
The merged report's counts, checkpoint and plan identities, device witnesses,
counters, and convergence observations come from these typed cells. Reading the
retained report requires exact regeneration from the pinned journals; prose
attestations and declared test IDs cannot manufacture completion. This boundary
retains the original Store-admitted checkpoint identity and does not claim a
fresh live admission or independent metric recomputation after teardown.

Current production loaders select each lane through its separately governed
append-only registration in `DEVELOPMENT_PLAN/attestations/product-lane-registrations/`.
An immutable snapshot records the independently selected journal path, byte count
and SHA-256, complete ordered 55-row PlanIds/contracts, original qualifying code
source and supervised/native review identities. Expected output pins are selected
after actual whole-lane acquisition and independent review. Reading a journal
never makes its observed digest the expected pin. The safe default readers use
full registered-lane admission; explicit historical readers retain older pins.

The independent criterion selection is frozen before training. Its bounded
original review files and artifact references bind the source, lane, scope and
complete 55-row contract set. Actual supervised/native execution retains that
same prelaunch identity in its authenticated qualification chain. Current
registration requires original source/review bindings for all 54 training rows.
The tuning row has no recorded original code source; its full current contract
and original lane admission remain required. CPU and Apple judgments are
independent; the later aggregate still requires all three actual admitted lanes.
Parsing review or registration DATA establishes no reviewer independence or
execution, device, Store or parent capability. Phase 278 owns the remaining
actual acquisition and validation.

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

## Validation

The following existing commands are run inside the explicitly admitted, bounded
project container with real linux-cpu prerequisites. Target-specific cases are
implemented by the owning reopened sprints before these commands can prove the
new contract. No result from this documentation change is a passing execution.

```bash
# Example: Existing validation entrypoints inside the bounded project container
jitml test jitml-unit --linux-cpu
jitml test jitml-negative-controls --linux-cpu
jitml docs check
jitml check-code
```

Real backend, integration, browser and cohort evidence is additionally required
where the owning sprint names it; pure controls cannot replace selected hardware.
