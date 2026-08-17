# Typed Run Contract

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: ../../README.md, ../documentation_standards.md, README.md, haskell_code_guide.md, daemon_architecture.md, training_workloads.md, training_metrics_and_splits.md, product_completion_contract.md, checkpoint_format.md, numerical_core.md, unit_testing_policy.md, purescript_frontend.md, pulsar_ml_workflow.md, cluster_topology.md, determinism_contract.md, ../../DEVELOPMENT_PLAN/README.md, ../../DEVELOPMENT_PLAN/00-overview.md, ../../DEVELOPMENT_PLAN/system-components.md, ../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md, ../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md, ../../DEVELOPMENT_PLAN/phase-5-jitml-service-daemon.md, ../../DEVELOPMENT_PLAN/phase-8-supervised-and-rl-framework.md, ../../DEVELOPMENT_PLAN/phase-9-rl-catalog-alphazero-and-tuning.md, ../../DEVELOPMENT_PLAN/phase-10-checkpointing-and-inference.md, ../../DEVELOPMENT_PLAN/phase-12-test-stanzas-and-cross-cluster.md, ../../DEVELOPMENT_PLAN/phase-19-product-truth-gates.md, ../../DEVELOPMENT_PLAN/phase-21-type-state-dsl-and-inference-eligibility.md, ../../DEVELOPMENT_PLAN/phase-25-real-rl-algorithms-and-environments.md, ../../DEVELOPMENT_PLAN/phase-28-per-model-integration-and-e2e.md, ../../DEVELOPMENT_PLAN/phase-29-linux-cuda-product-lane.md, ../../DEVELOPMENT_PLAN/phase-30-apple-silicon-product-lane.md, ../../DEVELOPMENT_PLAN/phase-31-no-caveat-product-aggregation.md, ../../DEVELOPMENT_PLAN/phase-32-external-truth-realness-harness.md, ../../DEVELOPMENT_PLAN/phase-33-per-model-convergence-and-inference-tests.md, ../../DEVELOPMENT_PLAN/phase-34-plan-truth-governance.md, ../../DEVELOPMENT_PLAN/phase-261-contract-driven-live-execution-integration-journal.md, ../../DEVELOPMENT_PLAN/phase-262-contract-driven-live-execution-browser-and-playwright.md
**Generated sections**: none

> **Purpose**: Define jitML's typed run-planning, workflow-protocol, evidence,
> delivery-settlement, lifecycle, and reporting contract so invalid workflow
> states cannot cross the raw input boundary.

## Current Status

**Implemented today.** Provenance is bound to one self-describing checkpoint
envelope distinguished by payload variant: weight-only for RL, AlphaZero, and
tuning, or supervised-graph for the exact trained `LayerGraph`. Store admission
binds the persisted envelope payload, exact snapshot commit/descriptor and
scoped payload objects, closed execution origin, plan, measured completion, and
manifest before inference or report eligibility. The former Product V1/V2
served-byte split is historical and has no current parallel wire. Current phase
status and validation evidence live in the development plan.

## Scope and Ownership

This document is the single source of truth for the common contract followed by
supervised training, reinforcement learning, AlphaZero self-play, tuning,
inference, GC, and their live tests. The binding flow is:

```text
Raw input -> validated plan -> running protocol -> completed evidence
```

Only raw configuration, wire payloads, persisted bytes, and process output may
contain invalid state. The functional core accepts only refined values. Opaque
constructors ensure that a caller cannot manufacture a validated plan, settled
delivery, terminal workload observation, or completed-evidence witness.

This document does not own:

- role separation, the common `Work*` envelope family, or topic algebra; see
  [Pulsar ML-Workflow Contract](pulsar_ml_workflow.md);
- metric definitions or data-split rules; see
  [Training Metrics and Data Splits](training_metrics_and_splits.md);
- checkpoint encoding, object layout, and pointer CAS; see
  [Checkpoint Format](checkpoint_format.md);
- model-row completion bars; see
  [Product Completion Contract](product_completion_contract.md);
- test stanza organization; see [Unit Testing Policy](unit_testing_policy.md);
- phase order, implementation status, blockers, validation evidence, or cleanup
  ownership; see [Development Plan](../../DEVELOPMENT_PLAN/README.md).

## Raw and Validated Boundaries

Configuration and wire codecs decode into versioned raw DTOs. A single pure
refinement step accumulates all independent errors before effects begin:

```haskell
-- Example: Run-plan refinement boundary
resolveRun
  :: RawRunRequest kind
  -> Validation (NonEmpty PlanError) (RunPlan kind)
```

`RunPlan` constructors are hidden. Refinement proves at least:

- non-empty, canonical run, experiment, subject, topic, and artifact identities;
- positive counts and finite measurements;
- a real substrate and a placement permitted for that substrate;
- a compatible workflow, algorithm, environment, action domain, and trainer;
- dimensionally valid training, evaluation, checkpoint, and publication budgets;
- a non-empty deterministic seed cohort where cohort evidence is required; and
- protocol/version compatibility for every command and event codec.

Dhall type-checking and protobuf/CBOR decoding are necessary raw-boundary checks,
not semantic completion. A mounted config that decodes but fails refinement is a
typed failure; execution may not clamp it, reinterpret it, or substitute a
default. Persisted plans and evidence decode into raw versioned representations
and pass through the same refinement boundary. Generic deserialization must
never mint a proof-bearing domain value directly.

The resolved plan has a stable `PlanId` derived from its canonical encoding.
Commands, events, journals, manifests, and report rows carry that identity so
evidence from another run cannot satisfy the plan.

## Typed Plans and Dimensional Budgets

Counts that participate in arithmetic use opaque positive quantities indexed by
their units:

```haskell
-- Example: Dimensionally checked workflow quantities
data Unit
  = Epoch
  | EnvTransition
  | RolloutTickPerEnv
  | VectorEnvironment
  | EpisodeStep
  | EvaluationEpisode
  | OptimizerUpdate
  | Trial
  | Generation
  | ParallelTrial
  | Promotion
  | PerTrialOptimizerUpdate
  | SelfPlayGame
  | MctsSimulationPerMove
  | AlphaZeroPly
  | AlphaZeroOptimizerUpdate
  | ArenaGame

newtype Quantity (unit :: Unit) = Quantity PositiveInt
```

Training and evaluation are separate plans. An evaluation episode count cannot
be used as a training iteration count; an episode horizon cannot be used as a
rollout length; and evaluation episode steps cannot satisfy an environment-
transition budget. One pure plan compiler owns dimensional arithmetic such as
vector-environment multiplication and ceiling division for rollout iterations.
Callers never reconstruct completed work from configuration values.

The traditional-RL `RunBudget` contains environment transitions, rollout ticks
per environment, vector environments, episode steps, and evaluation episodes.
It deliberately has no optimizer-update quantity. The removed field denoted
different outer-loop concepts for different trainers and therefore could not be
compared dimensionally with actual optimizer applications. Optimizer work is an
opaque trainer measurement described below, not a declared RL plan axis.

Closed sums and GADTs model mutually exclusive choices such as cluster, host,
or direct in-process plan placement and discrete versus continuous action
domains. Opaque smart
constructors handle relational or runtime invariants such as unique seed
cohorts and exact keyed event coverage. Arbitrary text and runtime facts are not
promoted to the type level merely for novelty; the goal is a small, reviewable
set of types that prevents meaningful illegal states.

A runtime fact that is expensive to observe and catastrophic to assume qualifies
on that test. The correlated request/reply channel is one: an opaque
`ReplyCursor` is minted only from an acknowledged broker subscription creation,
and the correlated publish accepts nothing else, so a request cannot be
published before the cursor that must receive its reply exists. The token is
minted by the effect that establishes the fact, in the same shape as
`ArtifactRef` from a completed admission — a lifecycle event observed along the
way is a diagnostic, never the proof.

### Resolved Worker Plan Transports

`JitML.Plan.Workload` supplies hidden `SupervisedPlan`, `TuningPlan`, and
`AlphaZeroPlan` values. A supervised plan carries positive epoch,
training-example, evaluation-example, batch-example, and optimizer-update
quantities. Its optimizer-update budget is not an independent knob: refinement
requires it to equal `epochs * ceil(trainingExamples / batchExamples)`. The
tuning plan combines its common `RunPlan` with validated closed
sampler/scheduler/pruner axes and positive trial, parallel-trial, promotion,
and per-trial-update quantities. The AlphaZero plan combines its common
`RunPlan` with a closed canonical game and positive generation, self-play-game,
simulation-per-move, maximum-ply, optimizer-update, and arena-game quantities.

`JitML.RL.ProductBudget.compileRlPlan` separately refines a traditional-RL
`TrainingPlan` and `EvaluationPlan` into one content-addressed
`CompiledRlPlan`. Only the training half reaches schedule arithmetic; the
evaluation episode count cannot determine rollout iterations, transition
budgets, or any other training dimension. The compiled training schedule binds
the exact physical environment-transition target, rollout ticks, vector width,
and episode horizon, while the evaluation plan binds the exact final-policy
episode count.

`JitML.Plan.Command` is the only adapter between raw `StartTraining`,
`StartSweep`, and `StartAlphaZeroRun` records and those plans. A producer
refines the raw command, then attaches the canonical version-`1` plan encoding
and content-derived `PlanId`. A consumer re-refines both the command fields and
transported plan, requires semantic equality, exact canonical encoding, and
identity equality, and only then returns the hidden plan.

`TrainingRunConfig`, `TuneRunConfig`, and `AlphaZeroRunConfig` contain only the
canonical plan transport, its `PlanId`, and the operational Pulsar WebSocket
endpoint. They contain no second set of primitive execution axes or budgets.
`RlRunConfig` likewise carries the canonical compiled RL transport and its
content-derived id; its experiment, optional ROM path, and Pulsar endpoint are
operational fields, not alternate budget inputs. The worker parses and
re-refines the mounted transport before dataset reads,
training, trial/game execution, checkpointing, Job/host effects, or event
publication. A missing, malformed, non-canonical, version-incompatible, or
identity-mismatched plan is a typed failure; workers do not clamp quantities or
recover semantic defaults from environment variables. The same transport
drives local execution and Linux Jobs. A mounted RL worker rejects semantic CLI
`--seed`/`--algorithm` overrides rather than recompiling a second plan after
validation; those flags remain available only to explicit no-mount developer
runs. Apple host RL execution and daemon RunConfig construction share the same
pure raw-start adapter with an explicit absent vector override, so host process
environment cannot move the schedule or content-derived plan identity.

The supervised-graph payload persists that identity through a closed origin sum. ProductRow
publication uses `RawProductRowProjectionOrigin` and binds the addressed payload
row plus `PlanId` to one exact supported-substrate projection. A generic
public/daemon supervised command instead uses
`RawGenericSupervisedExecutionOrigin(rowId, canonicalPlanTransport)`. Loading
requires the origin row, payload row, and authoritative canonical
problem/ProductRow to agree, reparses and re-refines the complete exact plan,
requires canonical rendering and `PlanId` equality, binds the selected substrate
and manifest experiment to that plan, and rejects collision with a ProductRow
experiment hash. The addressed composite origin, not `PlanId` alone, binds the
canonical row semantics. See
[Checkpoint Format → The Self-Describing Checkpoint Envelope](checkpoint_format.md#the-self-describing-checkpoint-envelope)
for the byte contract and migration rule.

Generic execution also consumes that plan's seed: the supervised boundary
requires exactly one refined seed, rejects device-trainer `Int` overflow, and
uses it for model initialization and deterministic epoch ordering. Local generic
experiment identity hashes the Dhall path plus canonical row/dataset/model,
substrate, seed, epoch/training/evaluation/batch budgets, and therefore the
derived optimizer-update budget. These are execution inputs, not metadata that
may be replaced by canonical-row defaults after plan refinement.

## Protocol and Evidence Contracts

Each workload supplies associated command, event, progress, and evidence types
to one common protocol shape:

```haskell
-- Example: Pure workflow evidence contract
data Contract event progress result = Contract
  { initial :: progress
  , ingest  :: progress -> event -> Either ContractViolation progress
  , finish  :: progress -> Validation (NonEmpty MissingEvidence) result
  }
```

The reducer is pure and total. It accepts decoded events only after plan/run
identity validation and returns a new progress value or a typed violation. The
completion function returns opaque evidence only when the complete contract is
satisfied.

Reusable contract combinators include:

- `exactlyOne` for terminal metrics, completed checkpoints, and unique results;
- `atLeastOne` for explicitly non-exact telemetry streams;
- `exactKeyedRange` for episode, iteration, trial, generation, and shard
  coverage; and
- `refineContract` for semantic agreement between already-complete evidence
  requirements; and
- product composition so independent requirements accumulate missing-evidence
  diagnostics rather than failing at the first absent field.

Exact collections are keyed maps, not arrival-ordered lists. Identical
redeliveries with the same semantic event ID are idempotent. Conflicting
duplicates, gaps, out-of-range keys, malformed finite values, wrong-plan events,
and contradictory terminal events are contract violations. Aggregates such as a
median consume `NonEmpty` finite measurements, so missing evidence cannot become
a plausible zero.

Completion and checkpoint bytes cross a second explicit raw boundary.
`RawTrainingBudget`, `RawConvergenceObservation`, and
`RawCompletedTraining` are forgeable persistence/wire DTOs; the completion DTO
is versioned and carries the `PlanId`, budget kind and target, observed kind,
observed count, canonical unit label, training evidence, measurements, and
TensorBoard metadata. The current encoder emits V2 with an optional exact
ProductScenario invocation. The exact V1 tuple decodes and re-refines as a
completion with no invocation, preserving checkpoint inspection and nested
protocol compatibility; it cannot close a Phase `261` scenario because that
boundary requires the admitted completion to carry the exact current
invocation. Decoding always re-runs refinement.

`TrainingEvidence` additionally carries the `DeviceExecutionWitness` the run's
device call left behind, as a forgeable `RawDeviceExecutionWitness` on the wire
that `refineRawDeviceExecutionWitness` re-checks on the way back in — known
substrate, non-blank backend and executed identity, hex cache key, and a
64-character SHA-256 artifact digest. Revalidation carries the bound witness
across rather than dropping it, and a stored witness that no longer refines
fails the revalidation instead of degrading to an unwitnessed completion.
Product-row checkpoint admission requires the witness to be present, so the
lane fragment's `DeviceEvidence` column is a measurement of the artifact that
executed rather than a rendering of the row's declared substrate and claim. `TrainingBudget`,
`MetricCriterion`, `FiniteMeasurement`, `PassedMeasurement`, and
`CompletedTraining` hide their constructors. Criterion rules are typed as
at-least, at-most, or at-least-with-an-excluded-value; every threshold,
exclusion value, tolerance, and observation must be finite. The pass verdict is
derived rather than stored.

`CompletedTraining` requires exact observed-budget equality, revalidated
weight-delta and dataset-read evidence, the originating `PlanId`, and a
`NonEmpty` collection of opaque `PassedMeasurement` values. Zero criteria, one
failed criterion, a unit/kind mismatch, an underrun, or an overrun therefore
cannot construct completion. Generic CBOR decoding cannot bypass those checks.

For traditional RL, every successful trainer result owns opaque positive
`MeasuredEnvironmentTransitions` and `MeasuredOptimizerUpdates` counters. The
trainer increments them at the actual environment-step and learned-tensor update
sites; adapters and publishers cannot reconstruct success from a schedule or
configuration. The trained-artifact constructor exact-checks measured
transitions against the compiled plan and measured updates against
`TrainingEvidence`. The measured training-transition count is then used
unchanged as the checkpoint step and `CompletedTraining` observed units.
Evaluation episode steps never participate in that comparison.

For the supervised-graph payload, persisted metadata must re-bind that witness rather than
merely repeat its `PlanId`. Every completed convergence observation has one
unique equal-valued manifest metric row. TensorBoard run id equals the manifest
experiment, its log prefix is `jitml-tensorboard/<experiment>`, and its ordered
scalar tags equal the completed convergence metric names. The runtime,
manifest, and completed witness also carry the canonical pinned
training/evaluation dataset-read digest for the origin row; synchronized forged
digest fields remain invalid.

Protocol terminals preserve the distinction between persistence and proof:

- `TrainingCheckpoint CheckpointDone` is a candidate; only
  `TrainingCompletedCheckpoint CompletedCheckpointDone` carries mandatory,
  re-refined `CompletedTraining`.
- `RlCheckpoint CheckpointDoneRL` is a candidate; only
  `RlCompletedCheckpoint CompletedCheckpointDoneRL` carries mandatory,
  re-refined `CompletedTraining`.
- `TuneSweepFinished SweepFinished` reports the finite terminal counts and
  objective but is proof-free; only `TuneSweepCompleted SweepCompleted`
  carries mandatory, re-refined `CompletedTraining`.

The completed wrappers have hidden constructors and smart constructors. Their
text and protobuf codecs encode completion as a nested versioned raw payload;
there is no `Maybe CompletedTraining` field whose presence can be mistaken for
proof.

The current supervised worker publishes one final `TrainingEpoch` summary after
the run.  Its live adapter therefore requires the exact terminal epoch key plus
the proof-bearing completed checkpoint.  That singleton terminal snapshot is
named and tested as such; it is not presented as a complete iteration curve.
Any later learning-curve contract must be backed by per-epoch publication and a
separate ordered evidence type.

For a generic supervised command, exact finite completion of the plan and
passing the canonical row's convergence criterion are separate outcomes.
Structural or identity mismatches are hard failures. A finite below-bar result
is successful training but returns a typed completion miss, writes no eligible
supervised-graph checkpoint, and emits no completed-checkpoint event. Consequently a public
process-outcome check may pass while a live contract that explicitly requires
proof-bearing checkpoint evidence remains incomplete. A passing generic result
may write a generic-origin supervised-graph checkpoint, but it is not relabelled as ProductRow evidence.
Absent legacy initial/final weight-list projections do not gate that miss; exact
initial/final JMW1 bytes remain the required evidence, and any supplied legacy
projection must equal them.

A completed supervised-checkpoint event is publication after commit, not a
promise to commit. Before payload mutation the writer CAS-registers its full
reservation in the experiment-scoped `ExperimentGcFence` at
`gc/coordination-fence.txt` and advances its monotonic writer/root-activity
epoch. Registration moves overlapping `Planned` events to `Cancelling`; the
writer helps persist the byte-identical immutable cancellation artifact and
complete `Cancelled`, without deleting the semantic intent, before creating its
separate attempt marker or mutating a payload. The stable artifacts may span
generations and only the latest exact fence phase is logically active. It then reads the current latest-pointer expectation (the
current MinIO ETag when live), performs the pointer CAS, installs the exact
attempt-independent `committed.cbor`, deletes its owned marker, CAS-unregisters
its owned reservation entry (advancing the epoch again), and requires Store's exact completed result before
event publication. An overlapping executing/reaped GC event rejects the writer
before marker creation. A marker conflict leaves that attempt's fence entry as
conservative protection because marker ownership cannot be proved and advances
through a freshly registered attempt. A pointer conflict or
wrong-manifest acknowledgement is a typed failure, and the completed-checkpoint
event is not published. Candidate
and completed persistence are separate Store operations: candidates return
opaque `StoredCandidateCheckpoint` without writing `latest`; completed writers
take mandatory `CompletedTraining` and return opaque
`StoredCompletedCheckpoint` only after exact CAS adoption and commit.

Persistence proof is stronger than structural completion refinement. Latest
admission reads exact pointer body `P1`, fetches the exact addressed canonical
outer envelope, verifies the embedded-body identity for a supervised-graph
payload, reads exact pointer body `P2`, and requires `P1 == P2`. Store then
derives the required snapshot id, validates the exact commit's sorted canonical-
original → exact-scoped → payload-SHA descriptor, reconstructs the logical
manifest, and re-derives the same snapshot id before fetching scoped payload
objects. It independently verifies every scoped key, exact bytes, payload SHA, JMW1
encoding/shape, and graph-derived slice binding. A known manifest address
performs the same commit/descriptor/payload-object admission without pointer reads. Only
after that process may `requireAdmittedCompletedCheckpoint` produce Store's opaque
`AdmittedCompletedCheckpoint`; `JitML.Product.Pipeline` consumes that value and
Store does not import Pipeline. Immutable create conflicts are idempotent only
after an exact read proves byte equality, while pointer changes/CAS conflicts
remain typed rejection outcomes. Local persistence's `CheckpointWriteError`
separates invalid input, immutable-object conflict, pointer-CAS conflict, and
filesystem failure; MinIO conflicts remain typed `ServiceError`. A pure
structural completion precheck may reject an impossible addressed manifest
before payload-object I/O, but it cannot construct an admitted value.
Generic `JitML.Service.Workload` object effects reject the Store-owned
`manifests/`, `pointers/`, `snapshots/`, and `gc/` checkpoint prefixes before
`HasMinIO`; decoded workload input cannot manufacture this proof outside Store.
Supervised completion requires the supervised-graph payload. Completed
weight-only refinement is restricted to canonical non-supervised ProductRows
and additionally binds each companion pointer to its exact fetched bytes;
generic/non-product and supervised weight-only payloads cannot cross that
Product completion boundary.

RL has distinct evidence types for training and final quality. `LearningCurve`
is a non-empty sequence of finite trainer-produced `IterationSummary` values
whose iteration ids are strictly increasing in trainer order. `EvaluationSet`
is an exact map containing every planned zero-based evaluation episode id once,
with a finite reward and positive actual step count. Plan-bound
`IterationSummary` and `EvaluationOutcome` protocol events preserve that
distinction across Linux and Apple publication. Strict summary order is a local
`LearningCurve` construction invariant: the current live reducer treats
`IterationSummary` as telemetry and reduces the exact keyed
`EvaluationOutcome` cohort with metric/checkpoint evidence. Event arrival order,
a partial set, or the tail of final evaluation episodes can never be interpreted
as a learning curve; the final median consumes the complete finite
`EvaluationSet`. Contract refinement rejects a separately reported median that
does not equal that derived cohort median; that terminal metric event and the
completed checkpoint witness must both carry the same plan identity derived
from the compiled RL plan.

## Lifecycle State Machine

Placement is a closed sum, never a `Maybe` handle:

```haskell
-- Example: Placement and observation states
data Placement
  = ClusterJob JobHandle
  | HostRun HostRunHandle
  | RequestReply RequestHandle

data WorkloadObservation
  = Missing
  | Pending
  | Running
  | Succeeded TerminalEvidence
  | Failed WorkloadFailure
  | ProbeFailed ProbeFailure
```

The run lifecycle distinguishes awaiting placement, running work, terminal work
awaiting evidence, completed evidence, and failure. A successful workload and a
complete evidence contract are independent facts and may arrive in either
order. Neither alone is completion. Probe errors remain errors rather than
being collapsed into absence, and host placement cannot accidentally execute
cluster-only cleanup.

Only the final state exposes `CompletedRunEvidence kind`. Failure retains the
latest progress, workload observation, protocol violations, process transcripts,
and cleanup outcome. Cleanup failure is attached to the primary outcome instead
of overwriting or hiding it.

Apple host-resident Training, Tune, and RL/AlphaZero actions additionally use a
process-local keyed handle registry. The key is the refined pair of closed
workload family and canonical experiment hash. A Start registers its masked
`Async` handle before workload code can run; duplicate Starts and reuse of a
terminal key fail closed. Stop claims one exact transition, cancels and joins
that handle, and returns success only for an observed cancellation tombstone.
Unknown, already-stopping, naturally terminal, and cancellation-lost-race cases
remain distinct failures. Daemon drain closes admission, cancels all active
families concurrently, and joins them under the active bounded drain deadline.

## Delivery and Settlement

Logical event identity and broker delivery identity are distinct:

- a semantic `EventId` provides reducer idempotency and is derived from the
  plan, event kind, and event key;
- an opaque broker `DeliveryReceipt` identifies exactly the delivery being
  settled; payload text is never a receipt.

A typed subscription yields a decoded `Delivery event`. The handler returns a
`ConsumerDecision result`: `Continue disposition` or `Done disposition result`.
Both variants carry exactly one `Disposition` (`Ack` or `Nack reason`), and the
interpreter performs settlement on the same persistent consumer session before
continuing or draining. The handler has no separate acknowledge API, so
acknowledging the wrong payload, acknowledging twice, or forgetting to settle
cannot be represented in normal workflow code.

The interpreter owns subscription acquisition and cleanup through a scoped
resource combinator. `Owned` ephemeral subscriptions are deleted idempotently;
`Borrowed` daemon subscriptions survive interpreter cleanup. Durable test
subscriptions therefore cannot leak after a run, while shutdown cannot delete a
shared daemon cursor. Decode, dispatch, reducer, acknowledgement,
negative-acknowledgement, settlement, drain/protocol, bridge-process, and
subscription-cleanup failures are all typed run failures; a generic consume
error is not silently treated as another timeout.

Short-lived CLI reply consumers are supervised `Async` resources rather than
detached threads. An acknowledged admin CREATE first mints the opaque
`ReplyCursor`; the consumer then borrows that established subscription while
publication obtains both topics only from the token. Release cancels and joins
the consumer before issuing the bounded, cancellation-safe `DELETE` for the
cursor's `Owned` subscription. A cleanup
failure is retained as secondary detail when a timeout, publication error, or
other primary failure already exists; it becomes the failure when the primary
action succeeded. Expected cancellation after successful cleanup is not an
error. A settlement, drain/protocol, bridge-process, or cleanup failure observed
during cancellation remains the typed result and is not hidden by the
cancellation; only a completely successful drain and cleanup rethrows the
original asynchronous-exception identity.

Inference subscriptions use the same receipt boundary in a multi-delivery
form. The transport reads the current positive batch-size and latency policy
when the first request is admitted and captures two monotonic boundaries. The
handler/publication-entry deadline is admission plus the configured latency.
Sparse collection closes earlier at admission plus
`min(1 ms, latency / 10)`, allowing an under-capacity batch to reach its handler
with most of the SLO reserved for execution and result publication. The
operational default is 5,000 ms so a cold checkpoint load, generated-kernel
execution, configured retries, and result publication have a viable window;
this does not change the captured deadline or the one-millisecond collection
cap. Compatible `RunInference` requests group by checkpoint/experiment identity
plus input width; other inference-domain commands are isolated. Size,
collection cutoff, or compatibility change closes a batch, and the
incompatible/late request is carried into a fresh admission using a new policy
snapshot.

The handler receives an opaque receipt-free `DeliveryBatch`, while the transport
retains every broker receipt. Daemon dispatch commits semantic dedup state one
command at a time. Cancelling a later command restores only that command's
in-progress transition; earlier successful commands remain committed and do
not replay when the complete admitted receipt set is Nacked and redelivered. If
the handler has not returned when the transport timeout expires, the timeout
cancels it and Nacks that receipt set with a typed retry reason. Engine checks
the same captured deadline immediately before each Pulsar publication and
returns a typed timeout instead of entering the publication side effect after
expiry.

Once a handler returns a decision, the transport settles that decision without
a later clock sample that could retroactively turn it into a Nack. A publication
started before the deadline may already be externally visible and may finish,
fail, or receive its broker acknowledgement after the deadline. The boundary is
therefore a handler/publication-entry deadline, not an atomic publication or
broker-acknowledgement guarantee. Pulsar remains at-least-once. Every commanded
settlement, including a delivery racing an outstanding permit during drain,
must flush and be confirmed before the bridge reports `Drained`.

The public inference CLI does no model computation. It opens an `Owned`,
`FromLatest` reply cursor before publishing the typed request to the Engine's
derived request topic, then accepts exactly the Engine result whose `callId` and
experiment hash both match the request. A same-call result for another
experiment is unrelated evidence. The cursor is per invocation so historical
replies cannot satisfy the request and the joined release above cannot leave a
durable CLI subscription behind. With a live cluster publication,
request/reply startup, transport, publication, and timeout failures remain
Pulsar-path failures rather than being misclassified as checkpoint absence.

## Functional Core, Imperative Shell

One resource-safe interpreter executes every evidence-bearing live workflow
that owns a typed event or reply subscription:

```haskell
-- Example: Common live-workflow interpreter
runLiveWorkflow
  :: (Eq terminal, Eq evidence)
  => LiveWorkflow command event progress evidence violation missing
  -> LiveTransport command event
  -> LiveBackend terminal
  -> IO
       (Either
          (LiveRunFailure terminal evidence violation missing)
          (CompletedRunEvidence terminal evidence violation missing))
```

The interpreter:

1. acquires the validated, plan-bound Job, host-run, or request/reply
   placement;
2. opens the scoped typed subscription and waits for its persistent session to
   report connected before publishing the command;
3. renders commands and topics only through their protocol/topology owners;
4. consumes receipt-bearing deliveries through that session and feeds the pure
   reducer;
5. observes terminal workload state and complete protocol evidence without
   assuming which arrives first;
6. captures diagnostics while the event subscription and placement are both
   still owned;
7. settles each delivery exactly once; and
8. releases the subscription, then the Job, host-run, or request/reply
   placement, then any outer temporary-object fixtures under
   `bracket`/supervised-`Async` semantics.

The Sprint `12.11` `WorkflowMatrix` is a different boundary: it executes every
public CLI leaf as a typed `Subprocess` and validates the real process outcome
and documented output. Those cells do not expose an outer correlated event
subscription, so the matrix uses the canonical executable renderer without
fabricating protocol evidence or a workload terminal witness. Apple
host-command forwarding and duplicate-delivery checks are likewise explicitly
scoped transport/placement smokes; exact decoded command equality or a dedup
observation is not presented as completed-run evidence.

Resource ownership is explicit (`Borrowed` or `Owned`). An interpreter never
deletes a developer-owned cluster or another run's Job/RunConfig pair. Assertions live outside
the resource scope so an exception cannot bypass cleanup. The journal fixes the
successful release order as `DiagnosticsGathered` → `SubscriptionReleased` →
`PlacementReleased`; a failed release records its typed cleanup issue at the
same position instead of falsely recording release. Integration-only MinIO
fixtures and raw smoke-test Jobs plus their derived `runconfig-<jobName>`
ConfigMaps use an outer `generalBracket` owner that tries every deletion. A
synchronous assertion and its deletion failures are retained
together, and a deletion-only failure cannot be discarded as best effort.
Asynchronous cancellation is rethrown with its original identity after cleanup;
any simultaneous fixture-cleanup issues are emitted through the cleanup
diagnostic observer rather than replacing or wrapping cancellation.

## Evidence Journals and Reporting

Every interpreted live run produces an append-only typed journal containing
placement acquisition, consumer-session state, subscribe-before-publish
ordering, command publication, receipt fingerprints and redelivery counts,
reducer decisions, delivery dispositions, workload observations, diagnostics,
placement release, and cleanup issues. Sequence numbers are assigned only by
the interpreter. Successful completion is constructible only after terminal
workload success, complete protocol evidence, and successful cleanup; failures
retain the journal plus any primary, completion, diagnostic, and cleanup facts
that were observed. The journal is the input to live assertions and failure
rendering.

Test reporting represents what actually happened:

```haskell
-- Example: Suite invocation result
data InvocationResult
  = Passed ProcessTranscript
  | Failed ObservedProcessFailure
  | NotRun BlockedBy
  | NotRunAfterRefinement RefinementBlocker
```

`ProcessTranscript` retains the rendered command, stdout, stderr, working
directory, and monotonic duration; it does not own an exit status.
`ProcessOutcome` distinguishes success, while opaque `ProcessFailure` adds the
genuinely non-zero exit status to the transcript. Neither `ExitSuccess` nor the
malformed `ExitFailure 0` representation can inhabit `ProcessFailure`. Suite
orchestration observes that unchanged boundary through additive
`ObservedProcessOutcome`. `ObservedProcessFailure` is either the original
non-zero `ProcessFailure` or a structured `ProcessAttemptFailure` for a
synchronous runner exception that occurred before an exit status was observed.
The latter retains command, working directory, monotonic attempt duration,
exception detail, and explicit available/unavailable stream state. It has no
exit-code field, so a launch or capture exception cannot be rewritten as a fake
non-zero exit. Asynchronous exceptions are not converted to data: they retain
their identity and reach the enclosing resource bracket.

`NotRunAfterRefinement` is the honest result for a planned invocation whose
preceding process may have exited successfully but whose output did not refine
into the proof that invocation requires. Its `RefinementBlocker` retains the
source stanza, refinement name, and rejection detail. Because refinement is not
a process, this state must not be rendered as either `Failed` process evidence
or a synthetic `Passed` transcript.

Process-launch environment is a separate opaque `SubprocessEnv` value with no
`Show` instance. It is applied through the process API and is never folded into
argv, command rendering, `ProcessTranscript`, or failure diagnostics. For a
ProductScenario acquisition, the parent command creates the journal path,
current run id, exclusive `0600` HMAC key-file path, canonical executable path,
and executable SHA-256. Only the `jitml-integration` Cabal child receives those
values, as `JITML_PRODUCT_SCENARIO_JOURNAL_PATH`,
`JITML_PRODUCT_SCENARIO_RUN_ID`, `JITML_PRODUCT_SCENARIO_JOURNAL_KEY_FILE`,
`JITML_PRODUCT_SCENARIO_EXECUTABLE`, and
`JITML_PRODUCT_SCENARIO_EXECUTABLE_SHA256`, through that opaque environment.
Playwright, unrelated Cabal stanzas, lifecycle commands, and nested scenario
children scrub every ProductScenario capability instead of inheriting it.

The integration boundary requires the executable path to be canonical and the
expected SHA-256 to be canonical lowercase hexadecimal, independently rehashes
the executable, and rejects either mismatch before workspace creation or row
execution. Each ProductScenario runner then rechecks and pins that same
path-and-SHA identity while issuing its fresh invocation challenge. For a
complete command-owned startup bundle, the child parses the key once, validates
the remaining run, journal, and executable identities, rehashes the executable,
then bracket cleanup unlinks the key file and clears every ProductScenario
environment variable before Tasty constructs or runs the test tree. The parent
retains only its in-memory key for authenticated journal verification and
attempts failure-safe cleanup after the integration outcome.

After its precondition succeeds, each ProductScenario has a finite four-hour
wall-clock safety envelope covering exact command execution, terminal evidence,
and Store-backed resolution. This is operational scheduling policy, not a `TrainingBudget` or
`PlanId` input: it changes no epochs, examples, batch size, derived optimizer
updates, seed, or completion equality. Expiry remains fail-closed, contributes
no completed row, and cannot authorize reuse or resumption of a partial
command-owned scope.

Suite counts, status, duration, and per-stanza rows are derived from an append-only
invocation journal; fail-fast work is `NotRun`, never rendered as a pass. Every
selected stanza has one planned Cabal invocation, so an outcome cannot be
attributed to a different target. The complete journal is rendered before the
first retained failure is propagated.

The Phase `262` browser lane is a staged producer/consumer refinement inside one
command-owned scope:

1. Exactly one fresh `jitml-integration` producer receives the Phase `261`
   ProductScenario capability. A zero exit is necessary but insufficient.
2. The parent authenticates the completed 55-row journal, independently
   re-admits every immutable checkpoint through Store, and publishes an exact
   browser catalogue. Failure at this non-process boundary records Playwright
   and every later Cabal invocation as `NotRunAfterRefinement`.
3. In a parent-only temporary directory, the parent first writes and signs an
   all-`NotRun` fallback result. The browser result path remains absent. Only
   after the fallback succeeds does the parent create the distinct browser-only
   `0600` key file in the browser's writable scope.
4. Playwright receives only the repository, exact catalogue, and exact cluster
   publication as read-only mounts plus its isolated browser-evidence directory
   as the sole read-write mount. It consumes and unlinks its key, runs one
   catalogue-named test per row with retries, and atomically publishes an exact
   result without replacing an existing path.
5. The final parent refinement removes any surviving browser key before reading
   untrusted output. It chooses the exact browser result when present and the
   inaccessible parent fallback otherwise, verifies the HMAC, and exact-joins
   all 55 ordered rows against the published expectation.
6. An unauthenticatable or structurally invalid result is
   `LiveE2ERefinementRejected`. An authenticated result containing `Failed` or
   `NotRun`, or a later measurement-collection issue, is
   `LiveE2ERefinedWithIssue`: its exact row measurements remain renderable, but
   every post-refinement invocation is `NotRunAfterRefinement`. Only an
   all-`Passed` result is `LiveE2ERefined` and permits the Haskell e2e stanza and,
   for `jitml test all`, the remaining Cabal stanzas to run.

The live browser/Cabal runner keeps owned cluster acquisition, the producer,
selected Playwright invocation, every later selected Cabal stanza, report
measurements, diagnostics, and authoritative release in one `generalBracket`
scope.
Synchronous diagnostic runner exceptions become secondary scenario failures,
so later diagnostics and release still run. A body failure remains primary;
diagnostic and cleanup failures are retained without replacing it. The release
path records accepted idempotent no-ops without rewriting their original
non-zero process evidence. Diagnostic collection is decided from the bracket's
authoritative `ExitCase`: only a clean normal body return may skip it, while a
synchronous exception, asynchronous cancellation, or aborted branch always
collects diagnostics before release. No mutable success flag exists between the
body's last action and its return.

The binding measurement boundary is likewise a projection of evidence already
gathered by the scenario that ran: reporting must not launch a second probe,
invent a declaration row, or collapse not-requested and unavailable-with-reason
states. The invocation-journal half of this boundary is implemented. The
surviving post-test global measurement probes are a separately owned legacy row;
see [Legacy Tracking → Pending Removal](../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md#pending-removal).

### Product registry projection and report admission

Every `ProductRow` crosses one total refinement in
`JitML.Product.Matrix.projectProductRow`. The row's closed capability refines to
an opaque `ProductProjection kind` containing its validated convergence bar,
exact `TrainingBudget`, kind-indexed descriptor and evidence requirement,
resolved workload plan, semantic `PlanId`, substrate, and canonical internal
executor argv. `projectProductRows` accumulates row errors, rejects duplicate
identities, preserves input order, and returns an opaque
`ProductProjectionBatch`. Workflow matrix cells and the internal product-row
publisher consume this projection rather than dispatching or defaulting from a
raw `RowClass`.

The publisher executes the descriptor and resolved plan exactly. Its command is
`jitml internal train-and-publish-product-rows --<substrate> --row <rowId>`;
the row selector is authoritative and conflicts with the compatibility
`JITML_PRODUCT_ROW_FILTER` fail closed. Product execution does not accept the
historical `JITML_PRODUCT_SL_*`, `JITML_PRODUCT_RL_*`,
`JITML_PRODUCT_AZ_*`, or `JITML_PRODUCT_TUNE_*` semantic overrides. Dataset or
experiment configuration is loaded only after projection and must agree with
the projected descriptor. The direct publisher uses the explicit
`InProcessRun` plan placement on every substrate, and every semantic axis,
including RL vector-environment multiplicity and the seed cohort, participates
in the resolved plan identity.

For supervised ProductRows, the publisher accepts the trainer's processed
examples only when they equal `epochs * trainingExamples`, then constructs the
canonical four-row finite metric vector in order: `train_loss`,
`validation_loss`, `examples_processed`, and the row's named held-out
convergence metric. Missing, extra, duplicate, renamed, reordered, or non-finite
rows cannot enter Product-origin completion.

For every family, a successful write is only a receipt. The publisher
known-address re-admits that exact stored manifest through Store and marks the
row eligible only after the stored/admitted address, projected `rowId`,
`PlanId`, full `CompletedTraining`, canonical row lookup, and family-specific
runtime provenance agree. Supervised rows require a Product-origin
supervised-graph payload. RL, AlphaZero, and tuning retain canonical Product
weight-only payloads; their exact trajectory,
self-play transcript, or tuning-v2 transcript is written first, and its
content-addressed pointer is supplied to the checkpoint writer so Store
admission physically binds it. The opaque publisher batch audit requires the
projected order and denominator, unique row/experiment/manifest identities,
canonical artifact receipts, exact manifest-pointer/receipt equality, one
companion pointer for every non-supervised row, no companion pointer for
supervised rows, and exactly one tuning-v2 transcript for the tuning row.

Reporting is a second nominal boundary, not a text-table join. A private
`ProductScenarioCompletion kind` can be created only from Store's opaque
`AdmittedCompletedCheckpoint`. Its persisted manifest and admitted completion
must exactly match the projection's experiment, canonical ProductRow `rowId`,
`PlanId`, complete budget, budget/evidence kind, criterion, every dimensionally
defined update-count relation, and family-specific runtime provenance.
Traditional RL has no planned optimizer-update descriptor field. Its positive
measured optimizer count is exact-checked against `TrainingEvidence` before
completion, while its measured physical transition count is exact-checked
against the plan and carried as both checkpoint step and completed observed
budget. Supervised rows require a matching Product-origin supervised-graph
payload; non-supervised rows reject an unexpected supervised payload. A
reportable row can then be minted only from a successful opaque
`CompletedRunEvidence` carrying that same kind-indexed completion, and it
retains the admitted manifest SHA. Joining those values against the common
`ProductProjectionBatch` yields an opaque `CompletedProductScenarioReport` and
rejects missing, duplicate, orphaned, wrong-plan, or wrong-lane evidence.
Registry ids, declared test ids, generic payloads, and the legacy seven-column
lane table cannot populate `ReportMeasurements`.
`measuredProductRowEvidence = Nothing` means product evidence was not requested;
when the selected live targets request product evidence and no opaque
cross-process completed-scenario journal is available, collection fails closed
before launching measurement effects. Phase `261` supplies the authenticated
current-run journal writer, reader, executable-identity checks, and report
re-admission boundary.

The version-`3` journal writer accepts only the opaque, projection-ordered
`CompletedProductScenarioReport`, covers the complete aggregate and every
ordered row field with one current-run HMAC-SHA-256 receipt, and publishes by a
same-directory temporary file plus atomic rename. The parent authenticates that
receipt with its in-memory key before trusting any row semantics, requires the
exact current run, substrate, projection batch, canonical checkpoint scope,
executable identity, command, invocation, contract, inference receipt, and
successful chronology, and re-admits every recorded immutable manifest address
through Store. A valid HMAC or green integration exit alone cannot mint report
evidence.

The browser-safe catalogue derived from that opaque report has one frozen
version-`1` transport schema. Its top level is exactly `format`, `version`,
`run_id`, `substrate`, `catalogue_sha256`, `source_journal_sha256`, and `rows`.
It contains exactly 55 projection-ordered rows, each with exactly `ordinal`,
`row_id`, `plan_id`, `experiment_hash`, `manifest_sha256`, `contract_sha256`,
`journal_sha256`, `measured_sha256`, `e2e_test`, `demo_panel`,
`measured_result`, and `status`. Every source status is `Passed`; duplicate,
missing, orphaned, reordered, wrong-substrate, wrong-plan, wrong-address, or
non-canonical input is rejected before Playwright starts.

Publication orders effects as live re-admission, immutable catalogue write,
append-only per-row GC-root writes, then selector CAS. Every authenticated and
live-admitted attempt is archival: its roots intentionally override `LastN` and
survive both later selector changes and a failed CAS attempt. Inline root moves
or deletion are forbidden because they can expose a selected catalogue without
roots or race concurrent publishers. A future bounded-retention mechanism must
be an independently synchronized external lifecycle policy; the selector owns
only the current UI view.

The independent browser result journal is also frozen at version `1`. Its top
level is exactly `format`, `version`, `run_id`, `substrate`,
`catalogue_sha256`, `source_journal_sha256`,
`run_receipt_hmac_sha256`, and `rows`. Each of its 55 ordered rows is exactly
`ordinal`, `row_id`, `plan_id`, `experiment_hash`, `manifest_sha256`,
`e2e_test`, `status`, and `detail`. `Passed` requires an empty detail;
`Failed` and `NotRun` require a non-empty, trimmed, control-free detail of at
most 4096 Unicode code points. The HMAC material begins with the domain
`jitml-browser-result-journal-hmac-v1` and length-delimits every top-level and
row value as `<label>=<UTF-8-byte-length>:<value>\n` in schema order. The key is
exactly 32 bytes encoded as 64 lowercase hexadecimal characters. Browser and
parent implementations share cross-language ASCII and multibyte golden vectors;
neither JSON serialization nor platform newline conventions define the receipt.

A passing generic-origin supervised-graph payload remains outside this admission boundary.
Its embedded exact plan may make it inference eligible, but its non-product
experiment identity and generic origin cannot be substituted for the projected
row's ProductRow-origin artifact or completed scenario journal. Matching a
`PlanId` without the addressed Product composite origin is insufficient.

## Workload Instances

- **Supervised learning** requires the exact training budget, observed update
  counters, dataset-read provenance, finite split metrics, terminal checkpoint,
  and passing completion measurements.
- **Reinforcement learning** requires typed training-transition budgets, ordered
  iteration evidence when curve properties are claimed, an exact keyed final-
  policy evaluation cohort, finite rewards, terminal metric, and completed
  checkpoint.
- **Tuning** separates trial count, parallelism, promotion count, and per-trial
  optimizer updates. `TrialFinished` events must cover the exact zero-based
  trial range, every tuning event must match the plan and experiment, and
  exactly one proof-bearing `SweepCompleted` must wrap a `SweepFinished` with
  the plan-prescribed completed-trial and promoted-trial counts and a finite
  objective. A proof-free `SweepFinished` remains terminal candidate evidence,
  not run completion. The executor bounds concurrent cohorts by the plan
  parallelism, retains pruned outcomes instead of dropping trial keys, persists
  every transcript, and checkpoints exactly the promoted frontier. Replayable
  sampler state and promoted-checkpoint evidence compose with that completion
  contract. Product publication renders one `tune-trials-v2` transcript that
  binds the projected row, `PlanId`, experiment, dataset-at-read SHA, best
  final JMW1 SHA, and exact ordered contiguous trial executions; exactly one
  execution is promoted and it must equal the selected best trial. Product
  evidence for the registered hyperparameter-tuning
  `ProductRow` uses the Catalog's TPE/ASHA/`MedianPruner` schedule: `128` trials,
  seed `1729`, a `1000`-optimizer-update ceiling allocated through eta-derived
  measured rungs with real early stopping, parallelism `1`, and a best-
  objective target of `1.0` with slack `0.05`. A reduced smoke plan may validate
  transport or lifecycle mechanics but cannot mint completion for that row.
- **AlphaZero** separates generations, self-play games, simulations per move,
  maximum plies, optimizer updates, and arena games. `GenerationCompleted`
  events must cover the exact zero-based generation range and report the
  plan-prescribed game count; exactly one `ArenaCompleted` must report the
  plan-prescribed arena count and a finite win rate. Game-specific transcript,
  update, and checkpoint evidence compose with that completion contract.
- **Inference** consumes only an inference-eligible artifact refined from
  completed evidence and produces exactly one result for the plan/call identity.
- **GC** requires an exact deletion decision journal and acknowledgement of each
  published audit event; a steady-state no-op is a distinct successful outcome.

Field-level metrics, bars, artifact formats, and retention semantics remain in
their owning documents linked from [Scope and Ownership](#scope-and-ownership).

## Verification Contract

The pure reducer is property-tested independently of brokers, Kubernetes, and
devices. Required properties cover:

- permutations of valid event arrival order;
- identical redelivery idempotency and conflicting-duplicate rejection;
- missing, extra, out-of-range, malformed, non-finite, and wrong-plan events;
- exact keyed coverage and non-empty aggregate construction;
- workload-failure, probe-failure, timeout, settlement-failure, drain/process-
  failure, and cleanup-failure preservation; and
- both terminal-before-evidence and evidence-before-terminal sequences.

Integration tests fault-inject the effect boundary and validate resource
ownership, receipt settlement, diagnostics, and journal projection. Live tests
then exercise the same interpreter against the real broker, placement runtime,
toolchain, and device. No live lane may pass by skipping its protocol or
hardware obligations.

## Migration and Legacy Deletion

The execution order and current reopen status live only in the
[Development Plan](../../DEVELOPMENT_PLAN/README.md). Concrete compatibility
helpers and doctrine deviations awaiting deletion live only in
[Legacy Tracking](../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md).
Engineering documents describe the target contract and verification boundary;
they do not maintain a competing implementation-status ledger.

## Cross-References

- [README project doctrine](../../README.md)
- [Engineering docs index](README.md)
- [Pulsar ML-Workflow Contract](pulsar_ml_workflow.md)
- [Haskell Code Guide](haskell_code_guide.md)
- [Cluster Topology](cluster_topology.md)
- [Determinism Contract](determinism_contract.md)
- [Training Workloads](training_workloads.md)
- [Training Metrics and Data Splits](training_metrics_and_splits.md)
- [Product Completion Contract](product_completion_contract.md)
- [Checkpoint Format](checkpoint_format.md)
- [Unit Testing Policy](unit_testing_policy.md)
- [Daemon Architecture](daemon_architecture.md)
- [PureScript Frontend](purescript_frontend.md)
- [Development Plan](../../DEVELOPMENT_PLAN/README.md)
- [Legacy Tracking](../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md)
