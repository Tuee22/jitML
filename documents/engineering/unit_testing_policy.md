# Unit Testing Policy

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [engineering index](README.md), [documentation standards](../documentation_standards.md), [root README](../../README.md), [determinism contract](determinism_contract.md), [training workloads](training_workloads.md), [product completion contract](product_completion_contract.md), [JIT code-generation architecture](jit_codegen_architecture.md), [typed run contract](run_contract.md), [legacy-to-new phase map](../../DEVELOPMENT_PLAN/README.md#legacy-to-new-phase-map), [Phase 261](../../DEVELOPMENT_PLAN/phase-261-contract-driven-live-execution-integration-journal.md), [Phase 262](../../DEVELOPMENT_PLAN/phase-262-contract-driven-live-execution-browser-and-playwright.md), [Phase 276](../../DEVELOPMENT_PLAN/phase-276-negative-control-suite.md), [Phase 279](../../DEVELOPMENT_PLAN/phase-279-runcontract-negative-controls-request-and-event-fixtures.md), [Phase 280](../../DEVELOPMENT_PLAN/phase-280-runcontract-negative-controls-journal-fixtures-and-reducer-p.md), [Phase 281](../../DEVELOPMENT_PLAN/phase-281-runcontract-negative-controls-lifecycle-and-per-row-registra.md), [Phase 284](../../DEVELOPMENT_PLAN/phase-284-contract-driven-per-model-evidence.md)
**Generated sections**: none

> **Purpose**: Project-specific testing policy for jitML. Defers to the
> doctrine for the per-tier stanza model, the standard testing stack, the
> seven test categories, and the test-organization invariants; names the
> jitML test stanzas — the ten declared in `jitml.cabal`, including the
> realness stanzas whose retained and successor scopes are owned by Phases
> `276`, `279`–`281`, and `284` — the doctrine-category mapping,
> and the integration/e2e verification boundary for typed run contracts.

## Current Status

**Implemented today.** `jitml-sl-canonicals` asserts the current literal trained
`LayerGraph`, its graph-derived parameter count, the single supervised-graph
checkpoint envelope, Store reload parity, and row convergence/evidence.
`jitml-backends` covers batched device gradients and correct-operator execution
against the finite-difference-validated pure oracle. The obsolete byte-frozen V1
fixture and the `cifar10-vit` frozen-Mixer 123,595-parameter layout are retired.

## Doctrine Deferrals

This doc defers to [../../README.md](../../README.md) for:

- **Testing Doctrine** — every behavioural surface gated by a stanza; no
  spanning `tasty` tree.
- **Standard Testing Stack** — Cabal + `exitcode-stdio-1.0` + `tasty` +
  `tasty-hunit` + `tasty-quickcheck` + `typed-process` + `temporary`.
  Snapshot comparisons for renderer output are spelled with
  plain `tasty-hunit` equality assertions over `Text` / `ByteString`
  values; jitML does not depend on `tasty-golden`.
- **Test Categories** — Pure Logic, Parser, Property, Snapshot (pure-renderer
  output only), Integration, Daemon Lifecycle, Ephemeral-Cluster
  Infrastructure. Snapshot tests are restricted to deterministic,
  non-numerical renderer output — CLI help text, `CommandSpec` JSON, route
  tables, dashboard JSON, prerequisite renderings, cache keys, and other
  pure `Text` / `ByteString` artefacts — per [Snapshot Tests and the
  Prohibition on Numerical Fixtures](#snapshot-tests-and-the-prohibition-on-numerical-fixtures).
- **Test Organization** — one `test-suite` stanza per tier with `type:
  exitcode-stdio-1.0` and `tasty` as the in-stanza runner; project-specific
  stanzas under §Test Organization → project-specific stanzas.

## jitML Stanzas

The ten Cabal test-suite stanzas are declared in `jitml.cabal`. This document
owns their category and verification boundaries. Current phase state, remaining
work, blockers, and validation evidence live only in
[Development Plan → Closure Status](../../DEVELOPMENT_PLAN/README.md#closure-status).
A representative workflow, static browser matrix, declared evidence handle, or
fake browser runtime does not satisfy product-row evidence.

Live workload cases share the plan, pure reducer, receipt settlement,
placement/terminal lifecycle, append-only journal, and resource-safe interpreter
defined by [Typed Run Contract](run_contract.md). The common interpreter is the
only collector for the evidence-bearing Linux cluster supervised,
traditional-RL, Tune, AlphaZero, GC, and inference scenarios. The Sprint
`12.11` workflow matrix separately executes typed public-CLI subprocesses; it
does not invent an outer subscription for commands that own their reply or
produce no correlated event. Direct Apple forwarding and daemon-dedup cases are
explicitly scoped transport/placement smokes and are not treated as completion
evidence. Stanza-specific sections below state the required verification
boundary and identify current stand-ins where relevant.

The supervised live adapter tests the protocol the worker actually emits: one
exact terminal-epoch snapshot plus the proof-bearing completed checkpoint.  It
rejects earlier/out-of-range epochs, wrong-plan completion, non-finite values,
and a missing checkpoint.  This terminal snapshot is not counted as a complete
training iteration curve.

Sprint `19.4` keeps the product registry boundary in `jitml-unit`. Tests project
all 55 rows across all three substrates, pin representative semantic PlanIds,
exercise exact budget, seed, dimension, RL vector-environment, and
`InProcessRun` identity, reject duplicate and unprojectable batches, and require
WorkflowMatrix commands to use the projected
`internal train-and-publish-product-rows --<substrate> --row <rowId>` argv.
`JitML.Test.RunContract` owns report-admission tests: only a successful opaque
`CompletedRunEvidence ... (ProductScenarioCompletion kind)` carrying a matching
Store-admitted checkpoint is accepted. The admitted manifest must preserve its
exact SHA and match the projection's experiment, canonical row, `PlanId`, full
completion, budget/kind/criterion, every dimensionally defined update-count
relation, and Product runtime provenance. Traditional RL has no projected
optimizer-update plan axis: its admitted completion retains the trainer-measured
positive update count without comparing it to the removed heterogeneous
descriptor. The typed trainer boundary separately rejects zero counters and a
measured transition count that differs from the compiled plan, then binds the
measured update count unchanged into `TrainingEvidence`. Cross-experiment,
cross-plan, generic-origin supervised, missing completion, projection mismatch,
duplicate, orphan, and wrong-lane joins fail. E2E report
rendering tests may consume the opaque report, but cannot manufacture a generic
completion fixture.

At the historical Sprint `19.4` boundary, the unit suite proved that the
then-canonical non-supervised Product V1 form could be Store-admitted only with
exact transcript bytes, while then-non-product V1 and supervised V1 remained
outside completed admission. Phase `235` subsequently migrated the current
tests and writes to one self-describing checkpoint envelope with weight-only
and supervised-graph body variants. Publisher tests exercise stored/admitted
address equality, Product projection substitution rejection, and the separate
versioned tuning-transcript (`tuning-v2`) semantics rather than treating a
successful write receipt as eligibility.

| Stanza | Verification boundary | Final Tier | Owning Sprint |
|--------|--------------|------------|---------------|
| `jitml-unit` | `test/unit/Main.hs` covers current CLI, docs, prerequisite, env, app-error, plan, subprocess, bootstrap-script, cache, hot-reload, capability, RL framework, AlphaZero, tuning resume, checkpoint key/CAS/store, deterministic snapshot preparation, canonical original/scoped/payload-SHA descriptor reconstruction and tamper rejection, zero-payload-object commit admission/GC, unique reservation attempts plus marker-conflict/leaked-entry/marker roots, the canonical versioned `ExperimentGcFence` path and experiment/revision/writer-root-epoch/reservation/history validation, contiguous generation histories, experiment-scoped writer/GC CAS transitions including cross-snapshot parent overlap, epoch increments on reservation register/unregister, complete-root-view epoch bracketing, exact fresh-plan missing-intent discovery/persistence and whole-view restart before no-op, late ready/published-transient recovery classification and cleanup, absent-target rejection without exact `Executing`/`Reaped` history, exact-epoch `Open`/`Cancelled` → `Planned` despite sibling GC-only revisions, `Planned` → `Cancelling` writer insertion, durable byte-identical immutable cancellation-artifact settlement without semantic-intent deletion to complete `Cancelled`, delayed-helper idempotence, no premature re-arm, executing/reaped writer rejection, post-`Reaped` intent cleanup, and helpable exact-executing authorization through Store's sole destructive `executeAuthorizedGcIntents` export without cancellation-artifact retirement, whole-intent cancellation and terminal-state contradictions, commit-inclusive one-snapshot GC events, strict protobuf-hex decoding, `.jmw1` encode/decode, TensorBoard scalar-event codec / TFRecord writer / sidecar, Grafana fixture, frontend bundle/panel/demo-route surfaces, the structural `ValidatedCheckpointCompletion` boundary plus Store-admitted completed-checkpoint gate, total ProductRow projection/batch identity, opaque completed-product report admission, pure all-model workflow-matrix enumeration, and inference-reply matching by both `callId` and experiment hash. It also checks all eleven canonical supervised learning rates (`3e-3` for `fashion-mnist-resnet`, `1.1e-3` for `cifar10-resnet20`, `1.5e-3` for `cifar10-vit`, and `1e-3` for the other eight rows), rejects zero/negative/NaN/infinite values, proves rate-sensitive `PlanId` identity, and observes exact Publisher callback propagation. | Pure Logic + Parser + Property + Snapshot | Sprint 10.6 / Sprint 12.1 / Sprint 19.4 / Phase 262 |
| `jitml-integration` | `test/integration/Main.hs` covers typed process results, bootstrap/live-rollout renderers, route-table snapshots, real-binary spawn, filesystem-backed MinIO checkpoint/inference/resume, local Linux CPU weighted checkpoint inference, partial-manifest rejection, routed MinIO/Pulsar behavior, exact 34-topic bootstrap evidence, daemon settings, Kind/RBAC rendering, Dhall numerics, oneDNN probing, and typed service command shapes. Its checkpoint/GC boundary covers scoped candidate conflicts, complete fail-closed ListObjectsV2 pagination and token echo/global ordering, atomic MinIO byte-plus-ETag coordination reads and CAS, canonical `ExperimentGcFence` path/identity/revision/writer-root-epoch/reservation/history validation, cross-snapshot writer/GC authorization and recovery, marker-conflict retained-entry protection, epoch increments on reservation register/unregister, complete-root-view epoch bracketing, exact-epoch planning with sibling GC-only revision tolerance, `Planned` → `Cancelling` crash recovery through byte-identical immutable cancellation persistence without intent removal, complete `Cancelled`, delayed-helper idempotence, exact-executing help without cancellation-artifact retirement, post-`Reaped` ready/published intent cleanup, durable cancelled/ready/published recovery, commit-inclusive exact deletion outcomes, idempotent already-absent DELETE, stored-substrate ready replay, and pre-capability weighted/unweighted Workload rejection of noncanonical bucket/key aliases and Store-owned control prefixes. The independent Product inventory uses one self-describing envelope: supervised rows carry supervised-graph bodies with no companion pointer; RL, AlphaZero, and tuning rows carry weight-only bodies with exactly one family-appropriate content-addressed companion pointer. The independently versioned `tuning-v2` transcript payload is re-read and header-bound separately; it is not a checkpoint-envelope version. Missing, duplicate, orphaned, and substituted pointer mutations fail. Its evidence-bearing live workflow cases execute `runLiveWorkflow` over typed topics/subscriptions, exact reducers, closed workload observations, a terminal/evidence join, diagnostics-before-cleanup, and retained journals. The command-owned startup capability, complete projection-batch ProductScenario resource, invocation-bound version-2 `RawCompletedTraining` completion DTO (not a checkpoint-envelope version), version-`3` authenticated journal, and parent-side exact Store re-admission bind every ordered ProductRow record. The uniform WorkflowMatrix remains public-CLI executable-outcome coverage, while exact Apple forwarding and duplicate-delivery cases are explicitly non-completion transport/placement smokes. Dated counts and current gate evidence live in the owning phase files. | Integration | Sprint 12.2 / Sprint 12.11 / Sprint 12.12 / Sprint 12.13 / Sprint 5.18 / Sprint 12.16 / Sprint 19.4 / Phases 261–262 |
| `jitml-sl-canonicals` | `test/sl-canonicals/Main.hs` covers the canonical SL `(dataset, model)` matrix, dataset parsing, Training command/event envelope round-trips, exact canonical epoch-permutation replay, and every row's read-time SHA verification, literal trained-`LayerGraph` feature/block parity, fixed `TrainingBudget`, measured update proof, completed-training witness, convergence statistics, single-envelope checkpoint write/reload, trained-versus-Store-loaded inference parity, and infer-before-complete rejection. The current `cifar10-vit` assertion derives its 8×8-patch/16-token graph parameter count and one physical graph-ordered `supervised.weights` shape from the literal graph; the obsolete Sprint `10.6` 123,595-parameter frozen-Mixer slices are not used as current truth. No per-substrate numerical fixtures are committed. | Integration (project-specific) | Sprint 10.6 / Sprint 12.3 / Phases 24, 235–246, and 28 |
| `jitml-rl-canonicals` | `test/rl-canonicals/Main.hs` covers the RL algorithm catalog, canonical-game surface, RL command/event envelope round-trips, representative measured convergence, and AlphaZero metrics. Sprint `20.1` relocated the deterministic `runRLLoop`, simulator-loop runners, and `deterministicStep` into `test/rl-canonicals/Support/`; tests that exercise them carry a `scaffolding:` title prefix and are not product evidence. Phase `25`/`28` make this row-complete: every documented algorithm/env row dispatches to its named environment, updates learned state where applicable, writes completed artifacts, and has named integration/e2e evidence. No per-substrate trajectory or reward-distribution fixtures are committed. | Integration (project-specific) | Sprint 12.4 / Sprint 20.1 / Phase 25 / Phase 28 |
| `jitml-hyperparameter` | `test/hyperparameter/Main.hs` covers sampler / scheduler / pruner axes including TPE, the TPE worked-example Dhall decode, sampler resume equality (replay an event log → next-batch matches first-pass), checkpointable trained weights for measured trial objectives, fixed trial-budget completion, promoted-checkpoint eligibility, and Tune command/event envelope round-trips. Sampler trial values are checked as properties rather than committed numerical sequences. | Integration (project-specific) | Sprint 12.5 |
| `jitml-backends` | `test/backends/Main.hs` covers per-substrate JIT backend validation, **symmetric across all three backends**: generated kernel compile/load/run + family/output-count symbols, weighted-family numeric correctness vs the pure `JitML.Numerics.FamilyReference` oracle, MLP forward/backward/batched-gradient/input-gradient vs the pure `JitML.Numerics.Mlp` network, the PPO/DQN/QR-DQN/HER/DDPG/AlphaZero device trainers (via the injected `JitML.Numerics.MlpDevice` backend), run-to-run bit-determinism, benchmark-candidate measurement, and tuning-cache persistence — each substrate's cases run **for real** in their own lane (Apple host-native Metal; linux-cpu oneDNN in the `jitml` container; linux-cuda CUDA in the `jitml-cuda` GPU container), selected with `jitml test jitml-backends --<substrate>`; the orchestrator synthesizes the backend stanza's `-p <substrate>` filter and `-fcuda` on `linux-cuda`, with **no skipped tests**. Correctness is asserted within-lane against the in-process pure-Haskell oracle within `1e-3`; no cross-substrate cohort | Integration (project-specific) | Sprint 12.6 |
| `jitml-daemon-lifecycle` | `test/daemon-lifecycle/{Main,SigtermRegression}.hs` covers lifecycle ordering, endpoints, opaque role-derived borrowed subscriptions, receipt-bound equal-payload delivery, strict decode failure, handler and settlement failure, owned cleanup, bounded persistent consumption, exact Coordinator topic/readiness state, role/domain dispatch separation, per-command dedup commits that survive later batch cancellation, Engine publication-entry refusal after the captured deadline, and actual compiled Engine/Webapp processes. Its companion unit groups cover dynamic log/retry/batch/SLO policy and the keyed Apple host workload registry, including duplicate/unknown/terminal Stops and bounded drain. Process cases exercise adjacent LiveConfig fail-closed loading; unchanged, valid changed, malformed-live, and immutable-Boot SIGHUP decisions; dynamically resized/expired dedup state; SIGTERM readiness loss; configured drain deadlines; forced-cleanup joins; and clean Webapp reload/termination. | Daemon Lifecycle | Sprint 12.7 / Sprint 5.18 / Sprint 12.16 |
| `jitml-e2e` | `test/e2e/Main.hs` covers route, bucket, publication, browser-contract, demo HTTP including generated stream routes, deployment, report-card, no leaked `jitml-e2e-*` clusters when `kind` is present and the active Docker context answers `docker info`, typed live-plan surfaces, browser-evidence mount/capability isolation, reporter wiring, and structural workflow assertions. Live execution borrows an existing publication without deletion or owns an auto-bootstrapped cluster and always releases it; primary failure is preserved when cleanup also fails. Phase `262` creates exactly 55 positive tests from the command-owned catalogue, binds their exact row/PlanId/artifact/measured identities through the real API/UI path, and returns a separately authenticated browser journal. | Ephemeral-Cluster Infrastructure | Sprint 12.8 / Sprint 12.11 / Sprint 12.13 / Sprint 12.16 / Phase 27 / Phase 28 / Phase 262 |
| `jitml-negative-controls` | **Owned by [Phase 276](../../DEVELOPMENT_PLAN/phase-276-negative-control-suite.md) and wired into `jitml test all`.** The current `test/negative-controls/Main.hs` (backed by `src/JitML/Test/NegativeControls.hs`) rejects hand-built known fakes with pure gate logic and requires the remaining production-path controls to stay explicitly enumerated. That pure gate-soundness scope does not mutate contract-driven production journals or require one negative case per `ProductRow`; Phases `279`–`281` own those production boundaries. Current status and validation evidence live in the development plan. | Integration (project-specific) | Phase 276 (legacy Sprint 32.1) / Phases 279–281 (legacy Sprints 32.4–32.6) |
| `jitml-model-convergence` | **Established under [legacy Phase 33](../../DEVELOPMENT_PLAN/README.md#legacy-to-new-phase-map); declared and wired into `jitml test all`.** The current lightweight guard enumerates one case per `ProductRow` from `JitML.Product.Matrix.allProductRows` and validates row identity, named integration/e2e handles, external bars, and positive non-wall-clock performance floors. It does not train, reload, recompute served metrics, or infer; [Phase 284](../../DEVELOPMENT_PLAN/phase-284-contract-driven-per-model-evidence.md) owns migration to opaque completed-run evidence. | Integration (project-specific) | Sprint 33.1 / Sprint 33.2 / Phase 284 |

Sprint `10.6` records historical pre-IR execution counts and diagnostics. The
current policy requires the complete unit run to include the graph-runtime,
permuted-training/fitted-transform, typed-rate recipe/refinement, `PlanId`
sensitivity, and Publisher propagation checks; structural passes cannot replace
the phase-owned live/integration, standing, docs, and code-quality gates.

The table states the current verification boundary, not phase status. The
standing realness stanzas are green lightweight guards, not substitutes for the
contract-driven production evidence still owned by Phases `279`–`284`. Current
closure evidence lives only in the Development Plan.

Each stanza is `type: exitcode-stdio-1.0` with `tasty` as the in-stanza
runner. A single `tasty` tree spanning all tiers is forbidden per doctrine
`Test Organization`.

## Doctrine Category → Stanza Mapping

| Doctrine Test Category | Owning Stanza |
|------------------------|---------------|
| Pure Logic | `jitml-unit` |
| Parser | `jitml-unit` |
| Property | `jitml-unit` |
| Snapshot (pure-renderer output only) | `jitml-unit` |
| Integration | `jitml-integration`, `jitml-sl-canonicals`, `jitml-rl-canonicals`, `jitml-hyperparameter`, `jitml-backends`, `jitml-negative-controls`, `jitml-model-convergence` |
| Daemon Lifecycle | `jitml-daemon-lifecycle` |
| Ephemeral-Cluster Infrastructure | `jitml-e2e` |

The four `*-canonicals`/HPO/backends rows, plus the two 2026-07-05 realness
rows (`jitml-negative-controls`, retained by Phase `276` from legacy Phase
`32`; `jitml-model-convergence`, legacy Phase `33`), are **project-specific Integration** stanzas under doctrine §Test
Organization's project-specific stanzas allowance — extensions of the
Integration category, not parallel test systems.

`jitml test all` fans out to every test stanza above through structured process
results. Each target becomes `Passed transcript`, `Failed failure`, or
`NotRun blockedBy`; a fail-fast invocation therefore cannot fabricate passes
for work that never ran. Failures retain the command, stdout, stderr, non-zero
exit, and duration. Suite status, counts, and duration are a pure projection of
the append-only invocation journal. Live workflow journals remain inside their
own test cases; the current `--live` measurement layer still launches
post-test probes and is tracked for replacement by Sprint `34.3`. See
[Evidence Journals and Reporting](run_contract.md#evidence-journals-and-reporting).

Substrate-selected runs serialize stanzas so live tests do not contend over one
cluster/device. `jitml test <stanza>` uses the same result shape for one target.
Style and code-quality commands remain separate; use `docker compose run --rm
jitml jitml lint *` and `docker compose run --rm jitml jitml check-code` inside
the headless `jitml:local` service.

## Project-Specific Stanza Notes

### `jitml-sl-canonicals` — SL canon coverage

The current body exercises the eleven canonical cells from
`src/JitML/SL/Canonicals.hs`, verifies dataset fetch and SHA validation through
`HasMinIO`, round-trips Training command/event envelopes, and asserts the
fixed-budget trained-artifact contract for every SL row: complete budget,
convergence-statistics payload, checkpoint reload, inference eligibility, and
infer-before-complete rejection. No `.txt` / `.json` files of hardcoded
per-epoch loss values are committed — see [Snapshot Tests and the Prohibition
on Numerical Fixtures](#snapshot-tests-and-the-prohibition-on-numerical-fixtures).

The retained Sprint `10.6` compact-Mixer counts are historical diagnostics, not
the current graph contract. Current cases derive the literal ViT parameter
count from its 8×8-patch/16-token trained `LayerGraph`, require one physical
`supervised.weights` object of that exact graph-ordered length, and prove
trained-versus-Store-reloaded inference parity. The ProductRow plan supplies
**2,000** training examples, forty epochs, batch size 128, **80,000** processed
examples, **640** successful optimizer updates, and the typed `1.5e-3` rate.
Phases `245`–`246` own the literal-graph convergence and completion closure;
Phase `262` separately owns the browser/e2e consumption of authenticated live
evidence.

### `jitml-rl-canonicals` — RL canon coverage

The current body checks entries in `algorithmCatalog`, verifies same-substrate,
same-seed run-to-run trajectory equality
(two fresh runs compared bit-for-bit against each other — no stored
trajectory file), property-tests the canonical environments (legal-move
generation, terminal detection, draw conditions for Connect 4, Othello,
Hex, and Gomoku), and round-trips RL command/event envelopes. Sprint `12.15`
requires and now validates that every RL algorithm row and every AlphaZero game
has a fixed budget, completed-training witness, stand-alone
convergence-statistics payload, checkpoint reload, inference/rollout
eligibility, and infer-before-complete rejection for the `linux-cpu` baseline.
No per-substrate trajectory, reward-distribution, or AlphaZero transcript files
are committed.

`KeyDoorGrid-v0` is the required visual discrete-control canonical demo target
introduced by the Phase `8` / Phase `9` replacement work. Its tests assert
same-seed map generation, legal-action masks, key pickup, locked-door
transition behavior, goal termination, render-frame determinism, and run-to-run
trajectory equality without committed trajectory fixtures.

Sprint `20.1` keeps the historical deterministic loop and simulator-runner
checks only as test scaffolding under `test/rl-canonicals/Support/`. Those test
titles begin with `scaffolding:` so the relocated `deterministicStep`,
`runRLLoop`, and `runSimulatedEpisode*` helpers cannot be mistaken for product
runtime evidence.

The ALE-backed `atari-subset` path is optional runtime support only, not a
required canonical demo dependency. Mandatory tests may assert the no-ROM
fail-closed diagnostic without possessing ROM bytes. Any real ALE smoke run is
manual/opportunistic and requires an explicit ignored user-provided ROM
path/object plus a generated or externally supplied runtime shim; commercial
ROM bytes and C/C++ adapter sources are never committed or baked into images.
JIT compiler inputs and project-owned native adapter sources remain generated
only by Haskell renderers.

### `jitml-hyperparameter` — sampler / scheduler / pruner reproducibility

The current body checks the local `Grid`, `Sobol`, `Random`, `TPE`, `GPBO`,
`GeneticAlgorithm`, `NSGA2`, `MuLambdaES`, `CMAES`, `EvolutionStrategies`,
and `PBT` samplers; `Fifo`, `SuccessiveHalving`, `Hyperband`, and `ASHA`
schedulers; and `NoPruner`, `MedianPruner`, and `PercentilePruner` pruners.
Sampler behaviour is exercised as properties — sampler state is a pure
function of its seed and event log, two runs produce bit-identical
trial-spec sequences, and `replaySweep` over a recorded event log yields
the same next-batch as the first-pass dispatcher. The stanza also covers
sampler-label parsing, the `experiments/mnist-tune.dhall` TPE
worked-example decode, and Tune command/event envelope round-trips. No
committed numerical trial-value fixtures.

### `jitml-backends` — per-substrate within-substrate determinism

The current body checks that every local substrate has deterministic engine
flags and that checkpoint weight-only tensor selection is substrate-independent.
It also routes the generated oneDNN/CUDA/Metal primitive
kernels through the shared cache artifact loader, loads `jitml_kernel` and
`jitml_kernel_family_name` / `jitml_kernel_output_count` with `dlopen`,
verifies the reported family and output length, and asserts three successive
FFI runs return bit-identical output (run-to-run determinism only — no
stored output bytes). It also dispatches a generated family kernel through
the local `HasEngine` interpreter and checks the loaded family metadata at
that boundary. There is **no cross-substrate cohort, no tolerance band, and
no `jitml verify cross-backend` command**: cross-substrate equivalence is not
asserted (RNG draws + float reduction order differ across substrates per
[determinism_contract.md → The Contract](determinism_contract.md#the-contract)).

Each substrate's cases run **for real** in their own lane and **none are
skipped**: Apple Metal writes cached MSL metadata and executes through the fixed
host Metal bridge on the host GPU, `linux-cpu` oneDNN runs in the `jitml`
container, and `linux-cuda` runs in the `jitml-cuda` GPU container.
A lane is selected with the public substrate flags, for example
`jitml test jitml-backends --linux-cpu` or `jitml test jitml-backends
--linux-cuda`; the orchestrator synthesizes the backend stanza's
`-p <substrate>` filter and adds `-fcuda` for `linux-cuda`. The lower-level
`--test-options='-p <substrate>'` tasty passthrough remains available for
ad-hoc runs. Within-substrate bit-for-bit reproducibility is the only equality
asserted here.

This one-real-lane-per-substrate model is the test-stanza instance of the
project's [Substrate-affinity phasing](../../README.md#substrate-affinity-phasing)
doctrine: each accelerator lane is exercised on its own host with no
cross-substrate cohort. The development plan generalizes it to whole phases —
each closure phase validates at most one of `{linux-cuda, apple-silicon}` plus
`linux-cpu`, and cross-lane evidence is aggregated on `linux-cpu` — bound, with
deterministic enforcement, by
[`DEVELOPMENT_PLAN/development_plan_standards.md` rule M](../../DEVELOPMENT_PLAN/development_plan_standards.md).
Phase order, blockers, and closure status live in the development plan, not here.
The unit suite owns the executable product-truth guardrails for that plan:
`test/unit/Main.hs` checks the `ProductRow` matrix floor, the Phase `19`–`34`
typed status registry against the sprint `**Status**` headers, and the
docs-check closure-claim scanner. The unit suite demotes a synthetic sprint to
prove the scanner rejects product-closure language for an unfinished registry.
It also covers the Sprint `20.2` ProductTruth lint boundary: direct product
source mentions of enforced fossils are rejected, product-reachable imports of
relocated scaffold modules fail, and no `ProductRow` implementation names an
entry from `nonProductScaffolding`.
Current lane evidence and any withdrawn historical evidence live in the
development plan and its attestations, not in this policy.

`jitml-unit` owns the CUDA runtime-probe parser snapshots for `nvcc`,
`nvidia-smi`, and `ldconfig`, plus the guarded CUDA benchmark-runner preflight
checks for wrong-substrate rejection, unavailable runtime summaries, and
available-runtime fail-closed behavior; `jitml-integration` owns the live probe
attempt through typed subprocesses. The same split covers the Metal runtime
probe snapshots and the guarded Metal benchmark-runner preflight checks. On
`apple-silicon` the live Metal path writes `<hash>.metal.json`, calls the fixed
bridge, and JIT-compiles the Metal shader via
`MTLDevice.makeLibrary(source:)` on the host GPU. The Apple `jitml-backends`
lane therefore needs a visible host Metal device plus a loadable fixed bridge;
each substrate's lane runs its own cases for real with no skipped tests. See
[../engineering/jit_codegen_architecture.md → Apple Silicon Fixed-Bridge Metal JIT](../engineering/jit_codegen_architecture.md#apple-silicon-fixed-bridge-metal-jit).
Only within-substrate bit-for-bit reproducibility is asserted; there is no
cross-substrate drift check and no tolerance band. See
[determinism_contract.md → The Contract](determinism_contract.md#the-contract).

### `jitml-negative-controls` — committed known-fakes must be rejected

**The retained pure gate-soundness scope is owned by
[Phase 276](../../DEVELOPMENT_PLAN/phase-276-negative-control-suite.md)
(legacy Sprint `32.1`; declared in `jitml.cabal` and exposed through
`jitml test all`).** The realness contract requires a gate that is not
self-authored or self-referential. The current
`test/negative-controls/Main.hs` (backed by
`src/JitML/Test/NegativeControls.hs`) commits hand-built gate-soundness fakes,
pairs each with pure gate logic that must reject it, and **fails the build if
any fake is accepted**. It also asserts that `pendingProductionControls` is
non-empty, so blocked production-path coverage cannot disappear silently. It
does not yet mutate the contract's real request/event journals, cover the full
lifecycle, or require a negative control per `ProductRow`. Phases `279`–`281`
own those production boundaries: request
and event fixtures in Phase `279`, journal/reducer coverage in Phase `280`, and
lifecycle plus mandatory per-row registration in Phase `281`.

### `jitml-model-convergence` — per-model case-registry guard

**Established under [legacy Phase 33](../../DEVELOPMENT_PLAN/README.md#legacy-to-new-phase-map)
and currently owned for production evidence by
[Phase 284](../../DEVELOPMENT_PLAN/phase-284-contract-driven-per-model-evidence.md)
(declared in `jitml.cabal` and exposed through `jitml test all`).** The realness
audit found that artifact readers and declared evidence handles are not training
drivers. The current `test/model-convergence/Main.hs` (backed by
`src/JitML/Test/ModelConvergence.hs`) is a lightweight registry guard: it owns
one case per `ProductRow`, enumerated from
`JitML.Product.Matrix.allProductRows`, and validates coverage, row identity,
named integration/e2e handles, externally anchored bar metadata, and positive
non-wall-clock performance floors. No current case trains, reloads a completed
artifact, recomputes its served metric, or performs inference. Phase `284`
owns that completed-run-evidence migration and its validation record.

### `jitml-daemon-lifecycle`

The current body exercises lifecycle ordering, endpoint responses, strict typed
decode followed by plan/kind/key semantic identity (including encoding
independence), strict protocol byte round-trips, opaque subscription planning,
receipt-bound settlement, scoped
owned/borrowed cleanup, derived readiness, exact Coordinator topic/readiness
evidence, and role/domain-separated workload dispatch. Synthetic broker cases prove
equal payloads with distinct receipts, Nack redelivery, decode failure before
dispatch, settlement failure, bounded drain, cleanup ownership, and lossless
dedup-cache resizing/expiry under a valid reload. `SigtermRegression` first
proves the actual production executable accepts `+RTS -N1`, enforcing its
threaded RTS link, then launches compiled Engine and Webapp `jitml service`
processes. Its Engine cases prove adjacent LiveConfig fail-closed loading;
unchanged, valid changed,
malformed-live, and restart-required immutable-Boot SIGHUP decisions; readiness
loss during SIGTERM drain; one confirmed settlement per receipt; enforcement of
the active handler/publication-entry deadline; and joined forced cleanup with no
orphan child. The daemon cases additionally prove that each completed command
commits its semantic dedup transition independently, so cancellation of a later
command cannot roll back the successful prefix, and that Engine refuses to enter
Pulsar publication after the captured deadline. The Webapp case proves the
shared reload decisions while HTTP serving remains live,
followed by clean SIGTERM exit. Companion unit groups prove operational dynamic
log/retry/batch/SLO policy, multi-receipt inference settlement, and the keyed
Apple host workload registry: duplicate, unknown, and already-terminal Stops
fail closed, while a live Stop cancels and joins exactly the selected workload
before success and bounded drain joins all remaining work. These surfaces are
exercised by the Sprint `12.16` daemon-lifecycle and canonical Linux CPU
validation.

The sparse-inference regression boundary is explicit and focused:
the `InferenceBatch` unit group covers the distinct early collection cutoff and
exact shared deadline predicate; the `PulsarTransport` group covers redirect-safe owned cleanup,
under-capacity dispatch, cancellation
settlement/drain/process/cleanup failure precedence, and an actual Node bridge
drain race whose hidden Nack flushes before `Drained`. The four `inference reply
scope` branches prove the CLI cancels and
joins its `Async` reply worker, treats the expected joined `AsyncCancelled` as a
clean release, preserves a typed DELETE failure beside a normal primary failure,
avoids duplicating a natural consumer failure, and observes cleanup before
rethrowing an exceptional primary with its identity unchanged. Unit coverage
also rejects a same-`callId` reply carrying the wrong experiment hash and maps
live request/reply transport failure to `PulsarFailed`, not checkpoint absence.
They import the isolated `JitML.Service.InferenceReplyScope` boundary directly,
while `JitML.App` only composes it into the public command.
The live WorkflowMatrix additionally snapshots `jitml-infer-*` subscriptions on
the result topic before and after its CLI cells and rejects any newly leaked
`Owned` cursor.

### `jitml-e2e` and the ephemeral-cluster live driver

The current `jitml-e2e` body validates local route, bucket, `chart/values.yaml`
MinIO coverage, publication, browser-contract, demo HTTP routes including the
generated stream endpoints, deployment, report-card rendering plus the
`cabal.project` knob-block parser, typed live-plan surfaces, no leaked
`jitml-e2e-*` Kind clusters when `kind` is present and the active Docker
context answers `docker info`, the bundle-serving fallback, and repeated quiet
WebSocket peer closure returning the active handler count to zero. When either
binary is absent or Docker is unreachable, the local Docker-backed Kind query
fails closed. The typed
`JitML.Test.LivePlan.liveE2EPlan` records the live orchestration as `Subprocess`
values: `helm dependency build chart` → `jitml bootstrap` (ephemeral Kind +
phased Helm rollout) → substrate-bound Playwright in the pinned browser image
with the repository read-only, the exact catalogue and publication mounted as
individual read-only files, and one command-owned browser-evidence directory
read-write → cluster release. The browser subprocess receives no Phase 261
journal, executable challenge, checkpoint root, or ProductScenario/integration
signing capability. Its only signing key is the independent browser-result key
created after the parent-only fallback is durable.
The live driver is an explicit command path, not a
process-environment gate or part of default `cabal test all`, because it selects
or bootstraps Kind, builds Helm dependencies, mutates image/runtime state, and
polls live routes.
Live test driver:

1. A typed `helm dependency build chart` step prepares subchart dependencies
   before any apply. `Chart.lock` becomes part of the reproducible surface only
   if the project adopts committed chart dependency locking.
2. `jitml bootstrap --<substrate>` brings up the stack (ephemeral Kind cluster,
   Helm chart in its `final` phase, plus the `jitml-demo` Deployment) and writes
   `cluster-publication.json`.
3. Exactly one fresh `jitml-integration` producer runs inside the command-owned
   ProductScenario scope and is the only child that receives the Phase `261`
   capability. Its zero exit is not proof: before Playwright starts, the parent
   authenticates the resulting 55-row journal, re-admits every exact immutable
   checkpoint through Store, and publishes the projection-ordered browser
   catalogue. After precondition success, every row retains its exact typed
   plan under the same bounded four-hour command-and-evidence-resolution
   envelope; that wall-clock safety limit is not a
   training-budget axis, and expiry cannot contribute or authorize reuse of a
   partial row.
4. The parent writes an authenticated all-`NotRun` fallback in a separate
   parent-only temporary directory while the browser result path is absent.
   Only after that succeeds does it create the fresh `0600` browser-only key in
   the isolated writable browser scope. The exact catalogue and matching
   cluster publication are individual read-only mounts; the browser scope is
   the only read-write mount.
5. The suite validates the exact live publication and catalogue and performs one
   authenticated real checkpoint API/panel load in a serial setup. It then runs
   one exact-title test per catalogue `e2e_test`; each case asserts its row id,
   PlanId, experiment, manifest, measured result, explicit status/reason, and
   family renderer against the shared refined DOM. Route mocks occur only in
   separate negative contract cases.
6. The custom reporter retains the final retry outcome for every exact planned
   title, maps missing/skipped work to reasoned `NotRun`, consumes and unlinks
   its fresh key, HMAC-signs a strict ordered 55-row result, and publishes it
   atomically without replacing stale output.
7. Final parent refinement first removes any surviving key, then authenticates
   the exact result when present or the inaccessible parent fallback otherwise
   and joins all 55 ordered identities to the catalogue. Structural or
   authentication rejection records every later stanza as
   `NotRunAfterRefinement`. An authenticated report with a `Failed`/`NotRun`
   row, or with a later measurement issue, is `LiveE2ERefinedWithIssue`: its
   measurements remain reportable, but it still blocks later stanzas. Only an
   all-`Passed` refinement permits the Haskell e2e and remaining `test all`
   stanzas. The browser never receives authority to mint integration evidence.
8. Release follows the acquisition ownership: a borrowed publication is never
   deleted; an auto-bootstrapped Kind cluster is always deleted on success or
   failure. If primary execution and cleanup both fail, the primary exception
   is preserved and the cleanup failure is emitted as additional diagnostics.
   The teardown audit then rejects orphan PVs, MinIO buckets, Harbor projects,
   or Docker volumes.

Cluster acquisition and release use one outer resource scope; every seeded
workflow owns its subscription, placement, evidence journal, diagnostics, and
cleanup through the nested scope in
[Functional Core, Imperative Shell](run_contract.md#functional-core-imperative-shell).
Assertions cannot bypass teardown. Evidence-bearing workflows journal
diagnostics before subscription release and placement release. Live integration
fixtures created directly in MinIO, plus the duplicate-Start smoke's raw Job and
derived `runconfig-<jobName>` ConfigMap, use exception-safe outer ownership;
every typed deletion failure remains visible beside an assertion failure rather
than being treated as best-effort cleanup.
Cancellation keeps its exact asynchronous exception identity, with simultaneous
fixture-cleanup failures sent to the deterministic cleanup diagnostic channel.

### Live Report Card

`jitml test all` remains local by default: it runs the ten declared test-only
Cabal stanzas and derives the report card from actual `Passed`, `Failed`, and
`NotRun` invocation results. Every planned stanza has one journal row, including
the exact command that a fail-fast suffix would have run; aggregate status,
counts, and duration are derived from that journal.

The current `--live` layer is deliberately documented as legacy: after all
selected stanza invocations pass, it launches separate probes for SL held-out
loss, RL return, AlphaZero arena win rate, tuning objective, JIT cache, daemon
health, and the browser matrix. Those seven generic probes remain Sprint `34.3`
legacy: an absent optional field means the measurement was not requested,
`MeasurementUnavailable` carries no reason, and `MeasurementAvailable Text` is
not yet tied to the scenario journal. Product-row evidence is stricter: it can
only be an opaque `CompletedProductScenarioReport`, and when selected targets
request it without the exact authenticated cross-process journal, collection
fails closed instead of silently omitting rows. The command-owned writer/reader
boundary gives only the integration
child receives the current run, `0600` key-file capability, journal path, and
canonical executable identity; startup consumes and clears that capability
before Tasty; and the parent authenticates the returned aggregate before exact
Store re-admission. Phase `262` owns
the separate browser/Playwright consumption boundary described above; it cannot
mint or replace the integration journal. Sprint `34.3` replaces the remaining generic probes with
`NotRequested`, reasoned `Unavailable`, and journal-bound `Available` evidence. Failed invocations
already retain their complete subprocess transcript/failure and block post-test
measurement. See
[Evidence Journals and Reporting](run_contract.md#evidence-journals-and-reporting).

### Playwright

Playwright belongs to the doctrine's Ephemeral-Cluster Infrastructure test
category. The checked-in `playwright/jitml-demo.spec.ts` is a live-only product
matrix. It reads `JITML_BROWSER_CATALOGUE_PATH` plus the individually mounted
`JITML_BROWSER_PUBLICATION_PATH`, validates exact live-readiness and substrate,
and drives the published edge route. The positive 55-row group contains no
route mocks and does not parse `Generated.Contracts` for evidence identities.
Its separate negative suite supplies complete frozen frames with intentional
identity/status faults and proves the panel rejects them without a Passed
fallback. The default `jitml-e2e` body validates the typed Playwright plan,
capability isolation, reporter wiring, and server-side route/concurrency
invariants without invoking the live stack; live edge-route execution stays on
the explicit live orchestration path. Static route/API scaffold checks stay in
the local Haskell e2e and the `purescript-spec` smoke suite run by `spago test`
through the Node `spec-node` runner.

The list reporter remains available for ordinary tooling. The evidence reporter
is enabled only when all four browser-evidence path variables are present; a
partial environment fails configuration. In evidence mode it rejects malformed
catalogues, stale output, non-exact key files, missing or duplicate planned test
titles, and publishes all 55 final retry outcomes as `Passed`, `Failed`, or
reasoned `NotRun` under a canonical UTF-8 byte-length HMAC-SHA256 receipt.
Failure detail is normalized by Unicode code point, removes every Unicode `Cc`
control, and is bounded to 4096 code points to match Haskell `Text`; an
independent multibyte golden fixes the cross-language receipt bytes.

The live Playwright expansion starts real
SL/RL/AlphaZero/tuning workflows, waits for live events and checkpoint evidence,
invokes model-specific interactions, observes non-identical RL animation
frames, drives legal moves on every canonical adversarial game, replays
persisted transcripts, and exercises tuning controls.
User-interaction fixtures such as drawn strokes, uploaded image files, or fixed
human move sequences are allowed as inputs; numerical curves, reward
distributions, policy outputs, and replay transcripts remain runtime-produced
and are never committed as golden numerical fixtures.

### Real-Workflow Matrix

`JitML.Test.WorkflowMatrix` is the source of truth for workflow coverage. Its
public-workflow cells enumerate SL train/eval, RL train/eval/rollout, tune,
inference, and AlphaZero self-play for each canonical substrate, with the
canonical `jitml` command and typed protocol instance for each cell. Its
ProductRow model cells instead derive from the common opaque projection batch
and carry the exact internal per-row executor argv. The completed Phase `261` integration
group executes the complete projection-ordered ProductRow batch, admits each
row only from its exact completed local-workflow evidence, and atomically writes
the authenticated aggregate for the parent command; declared ids, artifact-only
reads, and process outcomes cannot substitute for that journal. The separate
public WorkflowMatrix cells retain executable-outcome coverage. Phase `262`
owns the downstream browser/Playwright consumer of this boundary. The integration
`Live` group filters the matrix to the current publication
substrate, stages required input state, resolves each plan, and runs it through
the real binary plus common live interpreter. The
AlphaZero cell uses `jitml rl alphazero self-play`, so it follows the same CLI
boundary as the other cells. Without a live publication the selector fails
closed with the missing `cluster-publication.json` diagnostic; it does not pass
offline.

Workload observation distinguishes missing, pending, running, succeeded,
failed, and probe-failed states. A failed or unobservable producer captures Job
or host diagnostics and terminates the run rather than leaving an evidence
collector polling. Metal-backed Apple starts must resolve to host placement and
must not create workload Jobs; Linux CPU/CUDA cells resolve to the expected Job
placement. Terminal success alone is insufficient until the exact evidence
contract is complete, and complete events alone are insufficient until the
producer succeeds.

Daemon log diagnostics use the exact conjunctive selector
`app in (jitml-service,jitml-coordinator),jitml.role in (engine,coordinator)`.
The integration renderer regression requires both clauses: the application
clause excludes workload Jobs, which also carry `jitml.role=engine`, while the
role clause retains both daemon command roles. The WorkflowMatrix inference
cell also compares the result-topic broker subscription inventory before and
after execution and fails if the CLI leaves a new `jitml-infer-*` subscription.

### Property Invariants

Per doctrine `Test Categories → Property Tests`, every codec exposes the
canonical invariants:

- `decode . encode == id`
- `render is deterministic`
- `parser roundtrips`

Every run-contract reducer additionally property-tests valid event
permutations, identical and conflicting duplicates, gaps, extra/out-of-range
events, non-finite values, wrong-plan events, both terminal/evidence arrival
orders, settlement failure, and cleanup failure. See
[Verification Contract](run_contract.md#verification-contract).

Current checked coverage applies these invariants to the local parser, renderers,
route registry, cache helpers, checkpoint key/CAS/store helpers, runtime-source
renderers, numerical/RL Dhall catalog mirrors, local catalog helpers, and the
current route/Grafana renderer snapshots.
Transcript codecs, manifest CBOR, protobuf schemas, generated Grafana
fixtures, and richer numerical-core Dhall round-trips remain target validation.

### Snapshot Tests and the Prohibition on Numerical Fixtures

Snapshot fixtures live under `test/snapshots/`. They are restricted to
**pure, deterministic, non-numerical renderer output** — CLI help text,
`CommandSpec` JSON, route tables, Grafana dashboard JSON, Prometheus
scrape configs, Helm route templates, the report-card summary block,
cache keys (SHA-256 over rendered runtime source), and prerequisite
renderings. Non-deterministic content (wall-clock readings, hostnames,
timestamps) is replaced with sentinel placeholders.

Snapshot tests are **forbidden** for numerical content. jitML is a
numerical-methods repository; floating-point reduction order, transcendental
implementations, RNG host word size, and BLAS/DNN dispatch all vary across
substrates and toolchain pins. Committing `.txt` / `.json` / `.bin` files
of hardcoded SL training curves, RL trajectories, RL reward distributions,
AlphaZero transcripts, sampler trial values, or per-tensor cross-substrate
deltas would harden the producing host's floating-point behavior into the
repository, giving a false sense of authority that whichever host wrote
the fixture first defines correctness. Numerical correctness is asserted
through:

- **Run-to-run determinism** — two fresh runs on the same substrate / same
  seed produce bit-identical outputs, compared against each other, never
  against a stored file.
- **Statistical convergence assertions** — the median over a fixed-seed pool
  clears a sanity threshold derived from the literature reference at test
  time; the threshold is not committed as a per-substrate fixture.
- **Property tests** — finite gradients, monotonically-decreasing training
  loss, monotone evaluator reward over a sliding window, codec round-trips,
  legal-move generation, terminal detection.

Cross-substrate equivalence is **not** asserted at all — neither by fixtures
nor by a tolerance band. RNG draws and float reduction order differ across
substrates, so each substrate is validated for real within its own lane.

## Cross-References

- [../../README.md](../../README.md)
- [Development Plan legacy-to-new phase map](../../DEVELOPMENT_PLAN/README.md#legacy-to-new-phase-map)
- [determinism_contract.md](determinism_contract.md)
- [run_contract.md](run_contract.md)
- [../documentation_standards.md](../documentation_standards.md)
