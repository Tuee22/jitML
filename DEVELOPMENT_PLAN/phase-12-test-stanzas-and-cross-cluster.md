# Phase 12: Test Stanzas, Lint Matrix, Live Workflow Matrix

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md),
[development_plan_standards.md](development_plan_standards.md),
[system-components.md](system-components.md),
[phase-0-planning-documentation.md](phase-0-planning-documentation.md),
[phase-1-haskell-cli-surface.md](phase-1-haskell-cli-surface.md),
[phase-11-purescript-frontend-and-demo.md](phase-11-purescript-frontend-and-demo.md),
[phase-14-interactive-demo-and-playwright-closure.md](phase-14-interactive-demo-and-playwright-closure.md),
[../README.md](../README.md)
**Generated sections**: none

> **Purpose**: Govern the ten Cabal test-suite surface (`jitml-unit`,
> `jitml-integration`, `jitml-sl-canonicals`, `jitml-rl-canonicals`,
> `jitml-hyperparameter`, `jitml-backends`, `jitml-daemon-lifecycle`,
> `jitml-e2e`, `jitml-negative-controls`, `jitml-model-convergence`), the
> `jitml test all` Plan/Apply orchestrator, the
> report-card knob plumbing,
> the typed `JitML.Test.LivePlan` live-plan surface for the
> ephemeral-Kind e2e orchestration, and the fail-closed live workflow matrix used
> by later closure phases. Phase 12 owns the
> integration / canonicals / backends / daemon-lifecycle / e2e stanzas and the
> orchestrator; Phases `32` and `33` own the negative-control and
> model-convergence stanzas. Lint and code-quality targets are owned outside
> this phase and are not Cabal test stanzas.

## Phase Status

✅ **Done** (Sprint `12.16`; re-closed 2026-07-15 after Sprint `3.7`). The
scoped live interpreter, exact reducers, closed Job observation, role-indexed
daemon clients, keyed host-workload lifecycle, and journal-derived
invocation/suite outcomes are implemented and validated. Immutable descriptor
`sha256:6e0d57971bf8e6a7c996530a4b434a575237a570c745710f2a150a501da42aa0`
passed the complete retained-cluster `linux-cpu` gate: unit **544 / 544**,
integration **155 / 155** including **18 / 18** Live scenarios, Playwright **72
/ 72**, Haskell e2e **29 / 29**, and the full aggregate's **11 / 11** reporter
invocations with zero Failed or NotRun. Docs and code quality passed. Every
post-command verifier retained **5 / 5** Ready application pods with zero
restarts, three brokers, **34 / 34** topics, zero workload residue, and the
healthy edge. The three Sprint `12.16` replacement-landed ledger rows are
Completed. Sprints `12.1`–`12.15` remain Done on their retained stanza and
matrix surfaces.

**Historical retained closure.** ✅ **Done** (reopened and re-closed 2026-06-26 for Sprint `12.15` —
per-model fixed-budget integration/e2e matrix). The common-shape reopen remains
historically closed on its owned surface (Sprint `12.14`, re-closed 2026-06-18). The common-shape coverage
landed: the `Work*` workflow envelopes (training + inference correlated by
`callId`) + the composite Engine commands (compare/move round-trip + MCTS
legality) in `jitml-unit`, the derived **topic algebra** (the coordinator's
reconciled topic set equals the validated routing graph) and the `.ready`
readiness gate from Sprints `5.13`/`10.7`, and the websocket snapshot/patch frames
(`parseDecodedInference` / `parseCompareFrame` / `parseMoveFrame`) in `web/test`.
Validated `linux-cpu` offline lane: `jitml-unit` 208, `jitml-e2e` 23,
`jitml-daemon-lifecycle` 35, `spago test` 17/17, `lint purescript`/`docs
check`/`check-code` ok; the `-p Live` integration lane is the standard runtime
gate (rule M(b)). See [README.md](README.md) → Closure Status, the shared
[../documents/engineering/pulsar_ml_workflow.md](../documents/engineering/pulsar_ml_workflow.md)
contract, and [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).
Sprint `12.15` is now closed; the prior closure narrative below is retained as
dated history.

✅ **Done** (Sprint `12.13` re-closed 2026-06-16 on its owned host-validatable
e2e/matrix/report structure; the live Playwright product-matrix execution was
deduped to Sprints `14.2` / `15.20` / `16.11` per standards rule E). The
2026-06-14 reopen had expanded this phase from route/panel/value checks and
workflow-matrix command execution toward product-level browser validation; the
owned `JitML.Test.WorkflowMatrix.browserProductMatrix` enumeration and the
`browser_product_matrix` report-card field landed and are validated
(`jitml-e2e --linux-cpu` 23 / 23; `check-code`), and the live Playwright product
matrix is owned by Sprint `14.2`.

✅ **Historical closure** (reopened and re-closed 2026-06-13 for Sprint `12.12`). The Apple
Silicon full test run found a failed `jitml-rl-*` Kubernetes Job but the
integration convergence collector kept polling Pulsar rewards instead of failing
immediately with the Job condition and pod logs. Sprint `12.12` adds fail-fast
live Job observation, bounded host-command polling, and placement assertions so
illegal Apple Metal Jobs are caught at dispatch time. The focused Linux CPU live
dispatch selectors still create in-cluster Jobs, while the focused Apple live
selectors now observe host-command forwarding and no `jitml-train-*`,
`jitml-rl-*`, or `jitml-tune-*` workload Jobs.

Prior closure history follows.

✅ **Done** (re-closed 2026-06-12 — Sprint `12.11`). The stanza suite, lint
matrix, and substrate-partitioned lanes shipped, then the real-workflow refactor
reopened the phase because the test surface did not run every reopened real
workflow per substrate behind one DRY, fail-closed matrix. Sprint `12.11` adds
`JitML.Test.WorkflowMatrix`, replaces the vacuous `-p Live` assertions with a
matrix-driven integration `Live` runner, and keeps `jitml-e2e` responsible for
structural coverage plus the typed live e2e plan. The integration runner fails
closed without a live publication, filters to the current live substrate, stages
the required datasets/checkpoints, and executes every matrix cell through the
canonical `jitml` command. The AlphaZero cell executes
`jitml rl alphazero self-play` through the CLI instead of a direct in-test
helper. On 2026-06-12 the local `linux-cpu` bootstrap was repaired by moving
the Percona Postgres PVs to node-local storage on Docker Desktop, granting
database ownership before Harbor migrations, removing stale publications before
rollout, and right-sizing the Envoy data-plane request; the edge returned
`HTTP/1.1 200 OK` from `/healthz`, and the live `WorkflowMatrix` case passed
against the clean `linux-cpu` cluster. The Apple live lane then closed in
Phase `16`, and the final handoff closed in Phase `17`, both on 2026-06-12.

✅ **Done** (re-closed 2026-06-09 on the NVIDIA GeForce RTX 5090 host after
Sprint `12.10`'s live `linux-cuda` lane re-validation). The phase reopened
2026-06-08 for Sprint `12.10`. The reproducibility contract is clarified to
"within a substrate: bit-for-bit reproducible; across substrates: NO
guarantee", so the cross-substrate numeric parity surface is removed. Sprint
`12.10` realigns `jitml-cross-backend` to within-substrate cases only,
relocates the two substrate-agnostic cross-backend cases into `jitml-unit`,
deletes the cross-substrate tolerance-band test group from `jitml-unit`,
removes the report-card `cross_substrate_parity` field, wires
substrate-partitioned `jitml test` lanes (each substrate's cases run for real
in its own `--test-options='-p <substrate>'` lane; the six pure-logic stanzas
run in every lane; NO skipped tests — a missing toolchain fails by design), and
removes the skip-antipattern guards from the cross-backend / integration test
bodies. ALL linux-cuda within-substrate cases STAY (CUDA is NOT being removed).
**The Sprint `12.10` test/report code edits all landed 2026-06-09** and were
validated on every lane: the `apple-silicon` lane (4 / 4 host-native Metal
cases) and the `linux-cpu` lane (10 / 10 oneDNN cases in the `jitml` container)
each selected exactly their substrate's cases with no skip-sentinels,
`jitml-unit` passes 193 / 193 (including the relocated backend-agnostic group),
the container `jitml check-code` + `jitml docs check` are green, and on
**2026-06-09 the `linux-cuda` lane was re-validated for real on the RTX 5090**
(`docker compose run --rm jitml-cuda cabal test -fcuda jitml-cross-backend
--test-options '-p linux-cuda'` → 19 / 19, 12.26s, no skip-sentinels). The
historical 2026-05-25 closure record is preserved below.

✅ **Done** (2026-05-25). Every owned code-surface obligation closed:
eight Cabal test-suite stanzas with deterministic bodies, real-binary
spawn matrix through the typed `Subprocess` boundary, report-card
knob parsing from `cabal.project`, plan/apply rendering for
`jitml test all`, statistical and run-to-run replacements for all
former numerical-golden assertions per
[../README.md → Snapshot targets → Numerical-fixture
prohibition](../README.md#snapshot-targets), and the typed
`JitML.Test.LivePlan` live-plan surface. Live execution
of the `jitml-e2e` ephemeral-Kind rollout + Playwright on
the edge route is owned by
[phase-15-linux-cuda-and-cluster-closure.md](phase-15-linux-cuda-and-cluster-closure.md)
Sprints `15.1` and `15.14`. Cross-substrate cohort runs against
in-code tolerance bands + populated live report card are owned by
[phase-17-cross-substrate-and-handoff.md](phase-17-cross-substrate-and-handoff.md)
Sprints `17.1` and `17.2`.

The phase owns
[Exit Definition](README.md#exit-definition) item 9 (`jitml test all`
runs every test-only Cabal test-suite stanza with the report-card knobs pinned in
`cabal.project`; the `jitml-e2e` stanza orchestrates an ephemeral Kind
stack via `jitml bootstrap` + the typed `JitML.Test.LivePlan` live plan)
and item 18 (empty
legacy ledger after the open Exit-Definition items, including item `17`, close).
**Met today**: Sprint `12.1`
(`jitml-unit` body) and Sprint `12.7` (`jitml-daemon-lifecycle` body)
close their owned obligations because their entire body is pure-logic /
parser / property / snapshot / lifecycle / signal coverage (snapshot
restricted to pure-renderer output per
[../README.md → Snapshot targets → Numerical-fixture
prohibition](../README.md#snapshot-targets)).
The 2026-05-19 container validation also proves `jitml test all --dry-run`
renders the aggregate Plan/Apply surface and non-dry-run `jitml test all`
invokes the eight test-only Cabal stanzas inside `jitml:local`, parses the
`cabal.project` report-card knob block, and prints the current target-stanza
report card after Cabal succeeds. `renderReportCardForTargets` renders the
actual Cabal stanza targets that were run instead of fixed placeholder
workload PASS rows.
`JitML.Test.LivePlan.liveE2EPlan` contains the typed ephemeral-Kind
orchestration that runs `helm dependency build chart` → `jitml
bootstrap` → substrate-bound
the pinned `mcr.microsoft.com/playwright:v1.49.1-noble` browser-image run
against `playwright/playwright.config.ts`
→ `jitml cluster down`.
`JitML.Test.LivePlan.livePhasedClusterPlan` enumerates the typed
phased Helm rollout per substrate so the e2e body can verify the
ordering before invoking the live path. 2026-05-21 local validation re-ran
`jitml test all --dry-run` and non-dry-run `jitml test all`; all eight test
stanzas passed and the report card rendered `passed: 8`, `failed: 0`.
**Migrated live obligations**: Sprint `12.2`'s live checkpoint /
Pulsar / cluster capability effects and real per-substrate run-to-run
determinism are owned by Phase `15` Sprint `15.7` and Phase `17`
Sprint `17.1`. Sprints `12.3`–`12.6`'s live statistical SL
convergence, live RL trajectory determinism, live hyperparameter
reproducibility, and the historical cross-substrate comparison work are owned by
Phase `15` Sprints `15.4` / `15.6` / `15.10` and Phase `17`
Sprint `17.1` / `17.4` history. Sprint `12.8`'s live Helm + Playwright path
is owned by Phase `15` Sprints `15.1` / `15.14`. Sprint `12.9`'s live
report-card consumption is owned by Phase `17` Sprint `17.2`. No
code-surface Remaining Work survives in this phase.

### Current Implementation Scope

All ten Cabal test stanzas are declared and each has a `tasty` body. These tests
exercise parser/docs/cache/bootstrap helpers,
renderers, catalogs, checkpoint summaries, route/bucket registries,
daemon lifecycle data, and frontend contract scaffolds. The
`jitml-backends` body also compiles, loads, and runs the generated
Linux CPU oneDNN primitive kernels through
`dlopen` and checks the exported family and output-count symbols. The non-Live
`jitml-e2e` body verifies the typed Helm/Playwright plan and deterministic demo
stream routes; `jitml test jitml-e2e --live --<substrate>` additionally runs
the live Playwright matrix against the published substrate edge. The Live
integration cohort executes supervised, RL, tuning, GC, and inference commands
through `runLiveWorkflow`, real event subscriptions, and journal-derived
completion evidence. Its local
post-teardown check asserts no `jitml-e2e-*` Kind clusters survive when `kind`
is present and the active Docker context answers `docker info`; when Docker is
unreachable, the check fails closed instead of passing vacuously. `jitml test all`
invokes Cabal through the typed `Subprocess` boundary after the Plan/Apply
dry-run surface. Lint and code-quality commands run separately inside
`jitml:local`. Sprint `12.16` validated those implemented live paths on the
binding immutable image; it did not construct a separate structural-only
executor.

## Phase Summary

Ten Cabal stanza declarations now exist. The original eight came from Sprint
`1.1`; Phases `32` and `33` added `jitml-negative-controls` and
`jitml-model-convergence`. The current tree uses dedicated bodies for every stanza:
`jitml-unit`, `jitml-integration`, `jitml-sl-canonicals`,
`jitml-rl-canonicals`, `jitml-hyperparameter`, `jitml-backends`,
`jitml-daemon-lifecycle`, `jitml-e2e`, `jitml-negative-controls`, and
`jitml-model-convergence`. This phase expands the original minimal bodies
with Phase-12-owned workloads per doctrine `Test Organization` (each
`type: exitcode-stdio-1.0` with `tasty` as the in-stanza runner; a single `tasty`
tree spanning all tiers is forbidden). It also lands the current `jitml test
all` Plan/Apply report-card surface and the typed `JitML.Test.LivePlan`
live-plan surface; live ephemeral-Kind orchestration is exercised by the
later live matrix and product-handoff closure phases. Current `jitml test all`
delegates to Cabal for the ten test-only stanzas and then renders the
target-stanza report-card summary. The ten-stanza coverage
maps every doctrine test category
to the stanzas per [system-components.md → Test Categories Mapping (Doctrine
→ Stanza)](system-components.md#test-categories-mapping-doctrine--stanza).

## Sprint 12.1: `jitml-unit` Stanza ✅

**Status**: Done
**Implementation**: `test/unit/`, `jitml.cabal` (the `jitml-unit` stanza)
**Docs to update**: `documents/engineering/unit_testing_policy.md`

### Objective

Keep `jitml-unit` as the unit workload covering parser, generated
docs, prerequisite, environment, AppError, Plan/Subprocess, bootstrap-script,
runtime-source, and cache surfaces. Broader per-domain snapshot suites
(restricted to pure-renderer output per [../README.md → Snapshot
targets → Numerical-fixture
prohibition](../README.md#snapshot-targets)) are owned by the relevant
domain-specific stanzas rather than this unit-stanza sprint.

### Deliverables

- `test/unit/Main.hs` runs the current `tasty` tree.
- The current body covers command registry/parser/help/json, generated-doc
  checks, env resolution, plan rendering, subprocess rendering and fixture
  execution, prerequisite topology/remediation, bootstrap script diagnostics,
  cache-key/layout/manifest/symlink behavior, runtime-source determinism, and
  AppError rendering.
- Current pure-renderer snapshot fixtures live under `test/snapshots/cache/`,
  `test/snapshots/cli/`, and `test/snapshots/prerequisite/`. The legacy
  `test/golden/` tree is scheduled for deletion per
  [legacy-tracking-for-deletion.md → Pending Removal](legacy-tracking-for-deletion.md#pending-removal)
  and a `jitml lint files` rule (added in this sprint) fails any new
  file under that path.
- Route-table and Grafana daemon-health renderer snapshots are present
  under `test/snapshots/`. RL and AlphaZero per-game correctness is
  asserted through run-to-run determinism plus rule-conformance
  property tests; no per-substrate trajectory or transcript files are
  committed per [../README.md → Snapshot targets → Numerical-fixture
  prohibition](../README.md#snapshot-targets). The numerical and RL
  Dhall catalog mirrors are audited by the unit/lint body.

### Validation

1. `cabal test jitml-unit` exits `0` for the body.
2. Existing snapshot fixtures (pure-renderer output only) are
   deterministic and contain no timestamps or random identifiers.
3. `jitml lint files` fails if any file is committed under
   `test/golden/`, per [../README.md → Snapshot targets →
   Numerical-fixture prohibition](../README.md#snapshot-targets).

## Sprint 12.2: `jitml-integration` Stanza (Subprocess Boundary + Determinism) ✅

**Status**: Done
**Owned obligations after refactor**: code-surface only. Live HTTP MinIO
checkpoint round-trip migrated to Phase `15` Sprint `15.7`. The
per-substrate determinism assertion against real CUDA and Metal
production kernels migrated to Phase `17` Sprint `17.1`.
**Implementation**: `test/integration/`,
`jitml.cabal` (the `jitml-integration` stanza)
**Docs to update**: `documents/engineering/unit_testing_policy.md`

### Objective

Keep `jitml-integration` as the integration workload for the typed
subprocess boundary, renderer surfaces, real-binary spawn matrix, and
filesystem-backed capability coverage; grow live service effects and
same-substrate training determinism per `### Remaining Work` below.

### Deliverables

- `test/integration/Main.hs` runs the current `tasty` tree.
- The current body exercises `runStreaming` against `/bin/echo`.
- It verifies the local bootstrap plan includes the Harbor-first publication
  ordering.
- It verifies Kind config rendering is deterministic and route registry
  rendering covers the registered routes.
- It compares the rendered route table against
  `test/snapshots/cluster/route-table.md` (pure-renderer snapshot per
  [../README.md → Snapshot targets](../README.md#snapshot-targets)).
- Real `jitml` binary spawning is now exercised by the
  `spawned ./.build/jitml binary matrix against a real workdir` test —
  it locates the dist-newstyle binary, spawns it through the typed
  `Subprocess` boundary in a temporary workdir, and asserts the
  expected dry-run / help / no-op behaviours for `--help`, `bootstrap`,
  `cluster up`, `internal gc`, `service --help`, `train --dry-run`, and
  the Sprint `9.7` TPE `jitml tune` render path.
- CpuFeatures CPUID detection, filesystem-backed `HasMinIO` checkpoint /
  inference / resume round-trips, the local Linux CPU checkpoint inference
  runner through a generated FFI kernel, decoded `.jmw1` weights passed into
  the weighted local inference runner, Dhall numerics decode coverage, and
  `KubectlSubprocess` command-shape coverage against the repo-local kubeconfig
  all run here.
- Real checkpoint round-trip against live HTTP MinIO and training transcript
  determinism are not present yet.

### Validation

1. `cabal test jitml-integration` exits `0` for the body.
2. Transferred live validation: the stanza spawns the real `jitml` binary
   through the typed `Subprocess` boundary, exercises a real checkpoint
   round-trip via MinIO, validates resume-from-checkpoint semantics, and
   round-trips a Dhall experiment through the typed decoder against the
   actual numerical-core catalog.

### Remaining Work

- No sprint-owned code-surface Remaining Work remains. Real checkpoint
  round-trip against `JitML.Service.MinIOSubprocess` and the live
  `HasMinIO` capability class is owned by
  [phase-15-linux-cuda-and-cluster-closure.md](phase-15-linux-cuda-and-cluster-closure.md)
  Sprint `15.7`. The per-substrate determinism assertion against real
  CUDA and Metal production kernels is owned by
  [phase-17-cross-substrate-and-handoff.md](phase-17-cross-substrate-and-handoff.md)
  Sprint `17.1`.

## Sprint 12.3: `jitml-sl-canonicals` Stanza ✅

**Status**: Done
**Owned obligations after refactor**: code-surface only. The
`sl_epochs` / `sl_batch` report-card knob consumption closed on
2026-05-24 — `test/sl-canonicals/Main.hs` reads the `cabal.project`
report-card knob block via `JitML.Test.Report.loadReportCardKnobs`
and asserts the SL epoch/batch knobs are positive for the device-backed
training surface.
Live `jitml train` against canonical SL cells with real MinIO
datasets and live statistical convergence assertions against in-code
literature-target thresholds (no per-substrate fixtures per
[../README.md → Snapshot targets → Numerical-fixture
prohibition](../README.md#snapshot-targets)) migrated to Phase `15`
Sprint `15.4`.
**Implementation**: `test/sl-canonicals/`,
`jitml.cabal` (the `jitml-sl-canonicals` stanza)
**Docs to update**: `documents/engineering/unit_testing_policy.md`,
`documents/engineering/training_workloads.md`

### Objective

Use `jitml-sl-canonicals` for the current eleven-cell local supervised-learning
canonical workload exercised as property tests (finite-and-monotone
loss, run-to-run determinism, median over k seeds clears an in-code
literature-derived threshold). Live training thresholds remain target
runtime work; no per-substrate committed convergence fixtures will be
created per [../README.md → Snapshot targets → Numerical-fixture
prohibition](../README.md#snapshot-targets).

### Deliverables

- `test/sl-canonicals/Main.hs` verifies the eleven canonical
  cells from `src/JitML/SL/Canonicals.hs`.
- It asserts convergence curves are deterministic across two in-process
  invocations (run-to-run equality) and contain `sl_epochs` points.
- It asserts each final synthetic loss is lower than the initial loss
  by a per-problem-class margin (a property test, not a stored value).
- It does not compare against any `test/golden/sl/...` file per
  [../README.md → Snapshot targets → Numerical-fixture
  prohibition](../README.md#snapshot-targets).
- It covers `TrainingCommand` text render/parse round-trips plus
  `TrainingCommand` / `TrainingEvent` proto3-compatible byte round-trips.
- It does not run live training or consume `sl_epochs` / `sl_batch` yet.

### Validation

1. `cabal test jitml-sl-canonicals` exits `0` for the body.
2. Transferred live validation: the stanza runs real training against every
   canonical SL problem with the `sl_epochs` / `sl_batch` knobs from
   `cabal.project`, asserts the median test accuracy over a fixed-seed
   pool clears the in-code literature-derived threshold per problem, and
   asserts run-to-run determinism (two fresh same-substrate / same-seed
   runs produce bit-identical `sha256(weights.bin)`). No `test/golden/sl/`
   fixtures are created per [../README.md → Snapshot targets →
   Numerical-fixture prohibition](../README.md#snapshot-targets).

### Remaining Work

- The `sl-canonicals consumes cabal.project sl_epochs and sl_batch
  knobs` case in `test/sl-canonicals/Main.hs` reads the
  `cabal.project` report-card knob block via
  `JitML.Test.Report.loadReportCardKnobs` and asserts the deterministic
  curve length is bounded by `sl_epochs` (closed 2026-05-24).
- Driving `jitml train` against every canonical SL cell with real
  datasets and asserting median accuracy clears the in-code
  literature-derived threshold (rather than against a per-substrate
  committed fixture) are owned by
  [phase-15-linux-cuda-and-cluster-closure.md](phase-15-linux-cuda-and-cluster-closure.md)
  Sprint `15.4`.

## Sprint 12.4: `jitml-rl-canonicals` Stanza ✅

**Status**: Done
**Owned obligations after refactor**: code-surface only. The
`rl_steps` / `rl_eval_episodes` / `az_games` / `az_sims` knob
consumption closed on 2026-05-24 and the deterministic-stub per-cohort
run-to-run determinism closed on the same date — the stanza invokes
each cohort's rollout helper twice in-process and asserts bit-identity
plus rule-conformance properties (no `test/golden/rl/` fixtures per
[../README.md → Snapshot targets → Numerical-fixture
prohibition](../README.md#snapshot-targets)). Live `jitml rl train`
against algorithm × environment cohorts with real env simulators and
live statistical convergence + run-to-run determinism migrated to
Phase `15` Sprint `15.6`.
**Implementation**: `test/rl-canonicals/`,
`jitml.cabal` (the `jitml-rl-canonicals` stanza)
**Docs to update**: `documents/engineering/unit_testing_policy.md`,
`documents/engineering/training_workloads.md`

### Objective

Use `jitml-rl-canonicals` for the RL algorithm catalog, registered rollout
determinism over real environment dynamics, and Connect 4 transcript checks.

### Deliverables

- `test/rl-canonicals/Main.hs` verifies representative entries in
  `algorithmCatalog`: `PPO`, `SAC`, `HER`, and `AlphaZero`.
- It asserts a registered PPO/CartPole module rollout is deterministic for a
  fixed seed across two in-process invocations (run-to-run equality; no
  committed PPO/CartPole trajectory fixture per
  [../README.md → Snapshot targets → Numerical-fixture
  prohibition](../README.md#snapshot-targets)).
- It asserts `selfPlayTranscript` emits legal Connect 4 columns.
- It asserts each per-game `selfPlayTranscriptFor` helper for Connect 4,
  Othello, Hex, and Gomoku is run-to-run bit-identical and that every
  emitted move satisfies the per-game `gameLegalMoves` invariant; no
  per-game transcript fixtures are committed.
- It covers `RlCommand` text render/parse round-trips plus `RlCommand` /
  `RlEvent` proto3-compatible byte round-trips.
- It does not run RL environments, train policies, or consume
  `rl_steps`, `rl_eval_episodes`, `az_games`, or `az_sims` yet.

### Validation

1. `cabal test jitml-rl-canonicals` exits `0` for the body.
2. Transferred live validation: the stanza runs real RL training against
   every algorithm × canonical environment cohort with the `rl_steps`,
   `rl_eval_episodes`, `az_games`, `az_sims` knobs from `cabal.project`,
   asserts run-to-run trajectory determinism (target matrix form 2)
   and per-seed final-reward distribution clears an in-code statistical
   threshold (form 3 — `median ≥ literature_target − slack`, no
   committed fixtures per [../README.md → Snapshot targets →
   Numerical-fixture prohibition](../README.md#snapshot-targets)), and
   asserts AlphaZero arena promotion thresholds against the in-code
   gating policy.

### Remaining Work

- The `rl-canonicals consumes cabal.project rl_steps and
  rl_eval_episodes knobs` case asserts `rl_steps`, `rl_eval_episodes`,
  `az_games`, and `az_sims` are populated from the `cabal.project`
  report-card knob block (closed 2026-05-24).
- Deterministic-stub per-cohort run-to-run determinism closed on
  2026-05-24 for every traditional RL algorithm cohort; the stanza
  invokes the rollout helper twice in-process and asserts bit-identity
  plus rule-conformance properties. No `test/golden/rl/` fixtures are
  committed per [../README.md → Snapshot targets → Numerical-fixture
  prohibition](../README.md#snapshot-targets).
- Driving `jitml rl train` against every cohort with real env
  simulators, the AlphaZero arena-promotion gating assertion against
  the in-code threshold, and the per-seed final-reward statistical
  assertion are owned by
  [phase-15-linux-cuda-and-cluster-closure.md](phase-15-linux-cuda-and-cluster-closure.md)
  Sprint `15.6`.

## Sprint 12.5: `jitml-hyperparameter` Stanza ✅

**Status**: Done
**Owned obligations after refactor**: code-surface only. The
per-sampler run-to-run bit-identity assertion plus the per-scheduler /
per-pruner cohort resume-equality assertions closed on 2026-05-24 —
`test/hyperparameter/Main.hs` invokes each sampler twice in-process
over the same seed, asserts bit-identity between the two trial-value
streams, and walks every scheduler/pruner catalog entry plus the
per-sampler `resumeMatchesFullRun` (no `test/golden/tune/` fixtures
per [../README.md → Snapshot targets → Numerical-fixture
prohibition](../README.md#snapshot-targets)). Live `jitml tune`
against the full canonical sampler × scheduler × pruner grid through
the live tuner and resume-from-partial-sweep equality test against
live MinIO migrated to Phase `15` Sprint `15.10`.
**Implementation**: `test/hyperparameter/`,
`jitml.cabal` (the `jitml-hyperparameter` stanza)
**Docs to update**: `documents/engineering/unit_testing_policy.md`,
`documents/engineering/training_workloads.md`

### Objective

Use `jitml-hyperparameter` for the sampler, scheduler, pruner,
and deterministic trial-value checks.

### Deliverables

- `test/hyperparameter/Main.hs` verifies the current axes are populated:
  eleven samplers, four schedulers, and three pruners.
- It asserts `deterministicTrials sampler 8` is bit-identical across
  two in-process invocations for every current sampler (run-to-run
  equality).
- It asserts generated trial values are normalized into `[0, 1)`.
- It does **not** compare against any `test/golden/tune/...` file per
  [../README.md → Snapshot targets → Numerical-fixture
  prohibition](../README.md#snapshot-targets); sampler reproducibility
  is asserted as run-to-run equality plus sampler-state-purity
  property tests.
- It decodes `experiments/mnist-tune.dhall` and asserts the local tuning ADT
  carries the TPE / ASHA / MedianPruner worked-example axes.
- It consumes `tune_trials` and `tune_budget_per_trial` from the
  `cabal.project` report-card knob block for the local TPE trial-budget
  assertion.
- It covers `TuneCommand` text render/parse round-trips plus `TuneCommand` /
  `TuneEvent` proto3-compatible byte round-trips.
- Scheduler/pruner event semantics and resume equality are owned by
  `### Remaining Work` below. Report-card knob parsing is also covered through
  `src/JitML/Test/Report.hs` and `jitml-e2e`.

### Validation

1. `cabal test jitml-hyperparameter` exits `0` for the body.
2. Transferred live validation: the stanza runs real tuning sweeps with the
   `tune_trials` / `tune_budget_per_trial` knobs, asserts per-sampler /
   per-scheduler / per-pruner reproducibility, and asserts
   resume-from-partial-sweep equality against trial transcripts persisted
   to MinIO bucket `jitml-trials/`.

### Remaining Work

- The `every sampler is run-to-run bit-identical (Sprint 12.5)` case in
  `test/hyperparameter/Main.hs` walks the full sampler catalog (Grid,
  Sobol, Random, TPE, GPBO, GeneticAlgorithm, NSGA2, MuLambdaES, CMAES,
  EvolutionStrategies, and PBT), invokes each sampler twice in-process
  over the same seed, and asserts bit-identity between the two
  trial-value streams; the `every scheduler / pruner cohort reproduces
  under resume (Sprint 12.5)` case asserts every scheduler and pruner
  catalog entry plus the per-sampler resume equality from
  `resumeMatchesFullRun` (closed 2026-05-24). No `test/golden/tune/`
  fixtures are committed per [../README.md → Snapshot targets →
  Numerical-fixture prohibition](../README.md#snapshot-targets).
- Driving `jitml tune` against the full canonical sampler × scheduler ×
  pruner grid through the live tuner, extending knob consumption to the
  full grid, and the resume-from-partial-sweep equality test against
  live MinIO are owned by
  [phase-15-linux-cuda-and-cluster-closure.md](phase-15-linux-cuda-and-cluster-closure.md)
  Sprint `15.10`.

## Sprint 12.6: `jitml-cross-backend` Stanza ✅

**Status**: Done
**Owned obligations after refactor**: code-surface only. Cross-substrate
cohort runs and per-tensor drift assertion against the **in-code**
per-layer-family tolerance band at `src/JitML/Engines/Tolerance.hs`
(no per-tensor stored fixtures per
[../README.md → Snapshot targets → Numerical-fixture
prohibition](../README.md#snapshot-targets)) migrated to Phase `17`
Sprint `17.1`.
**Implementation**: `test/cross-backend/`,
`jitml.cabal` (the `jitml-cross-backend` stanza),
`src/JitML/Test/Report.hs`
**Docs to update**: `documents/engineering/unit_testing_policy.md`,
`documents/engineering/determinism_contract.md`

### Objective

Use `jitml-cross-backend` for the engine-flag, checkpoint
manifest/weight-selection invariant, Linux CPU generated-kernel execution
checks, and local Linux CPU `HasEngine` smoke dispatch. Live
cross-substrate tolerance testing remains the overall handoff gate.

### Deliverables

- `test/cross-backend/Main.hs` verifies every substrate has non-empty
  deterministic engine flags.
- It verifies checkpoint weight-only tensor selection is substrate-independent.
- It compiles generated Linux CPU oneDNN primitive kernels, loads `jitml_kernel` and
  `jitml_kernel_family_name` / `jitml_kernel_output_count` with `dlopen`,
  verifies the reported family and output length, and asserts three successive
  FFI invocations produce bit-identical fixture output.
- It dispatches a generated family kernel through the local Linux CPU
  `HasEngine` interpreter and verifies the loaded family metadata.
- It does not train SL canon cohorts yet (the canon-cohort run lives
  in Phase `17` Sprint `17.1`). The in-code per-layer-family tolerance
  band at `src/JitML/Engines/Tolerance.hs` will be the **only** drift
  reference; no `test/golden/cross-backend/` fixtures will be created
  per [../README.md → Snapshot targets → Numerical-fixture
  prohibition](../README.md#snapshot-targets).

### Validation

1. `cabal test jitml-cross-backend` exits `0` for the body.
2. `cabal test jitml-cross-backend` validates the generated Linux CPU oneDNN
   primitive compile/load/run paths plus exported family/output-count symbol
   metadata.
3. `docker compose run --rm jitml cabal test jitml-cross-backend` on
   2026-05-24 validates the local Linux CPU `HasEngine` dispatch over the
   generated oneDNN family FFI path in `jitml:local`.
4. Transferred live validation: the stanza runs the canonical SL cohorts
   on the `(linux-cpu, linux-cuda)` and `(linux-cpu, apple-silicon)`
   substrate pairs and asserts per-tensor drift fits the in-code
   per-layer-family tolerance band at
   `src/JitML/Engines/Tolerance.hs` per
   [../documents/engineering/determinism_contract.md](../documents/engineering/determinism_contract.md).
   No `test/golden/cross-backend/` fixtures are created.

### Remaining Work

- No sprint-owned code-surface Remaining Work remains. The
  cross-substrate cohort runs and the per-tensor drift assertion
  against the in-code per-layer-family tolerance band are owned by
  [phase-17-cross-substrate-and-handoff.md](phase-17-cross-substrate-and-handoff.md)
  Sprint `17.1`.

## Sprint 12.7: `jitml-daemon-lifecycle` Stanza ✅

**Status**: Done
**Implementation**: `test/daemon-lifecycle/`,
`jitml.cabal` (the `jitml-daemon-lifecycle` stanza)
**Docs to update**: `documents/engineering/unit_testing_policy.md`,
`documents/engineering/daemon_architecture.md`

### Objective

Use `jitml-daemon-lifecycle` for the doctrine's Daemon Lifecycle test category
through the lifecycle, retry, endpoint, and signal-control
surfaces. The target live test adds real Pulsar consumer idempotency on top of
the current boot → ready → serve → SIGHUP reload → drain → exit control model.

### Deliverables

- `test/daemon-lifecycle/Main.hs` verifies the current lifecycle phase plan.
- The test exercises endpoint response helpers and retry behaviour against
  synthetic service errors.
- The test exercises signal mapping (`SIGHUP` reload generation and
  `SIGINT`/`SIGTERM` graceful drain) and asserts readiness drops during drain.
- The test exercises the one-shot daemon HTTP listener against `/healthz`.
- The test covers proto3-compatible byte round-trips for the current
  `JitML.Proto.Inference` request/result envelopes.
- Live Pulsar idempotency is validated by the later live daemon/runtime
  closure phases.

### Validation

1. `cabal test jitml-daemon-lifecycle` exits `0`.
2. The lifecycle plan remains `load → prereq → acquire → ready → serve →
   drain → exit`.
3. Retry helpers map synthetic service errors to the expected `AppError`.
4. The one-shot daemon HTTP listener returns `200 OK` for `/healthz`.
5. Inference request/result protobuf envelopes round-trip through the local
   codec.

## Sprint 12.8: `jitml-e2e` Stanza and Live-Plan Orchestrator ✅

**Status**: Done
**Owned obligations after refactor**: code-surface only. Live phased
Helm + Pulsar rollout against a real Kind cluster, live Playwright
against the edge route, and full live teardown leak-detection migrated
to Phase `15` Sprints `15.1` and `15.14`.
**Implementation**: `src/JitML/Test/LivePlan.hs`,
`test/e2e/`,
`jitml.cabal` (the `jitml-e2e` stanza)
**Docs to update**: `documents/engineering/unit_testing_policy.md`

### Objective

Use `jitml-e2e` for the e2e scaffold and the typed live-plan
orchestration. The current body checks route, bucket, publication,
contract, report-card, and typed live-plan surfaces; the live body
brings up an ephemeral Kind stack via `jitml bootstrap`, runs the demo
cohorts against the real Envoy listener with Playwright, and tears the
stack down deterministically via `jitml cluster down`. This is the
doctrine's Ephemeral-Cluster Infrastructure test category. The live body
is an explicit opt-in gate, not part of default `cabal test all`,
because it creates Kind clusters, builds Helm dependencies, mutates
external container/runtime state, and validates teardown.

### Deliverables

- `JitML.Test.LivePlan.liveE2EPlan` declares the typed live-plan
  sequence — `helm dependency build chart` → `jitml bootstrap`
  (ephemeral Kind + phased Helm rollout) → substrate-bound
  pinned `mcr.microsoft.com/playwright:v1.49.1-noble` browser-image Playwright run →
  `jitml cluster down` — through typed `Subprocess` values, and
  `livePhasedClusterPlan` records the bootstrap rollout's typed
  subprocess list for the explicit live driver.
- `test/e2e/Main.hs` currently validates the route registry, bucket registry,
  `chart/values.yaml` MinIO bucket coverage, publication defaults, browser
  contract endpoint count, demo deployment command, demo HTTP route table
  coverage for generated stream endpoints, one-shot demo HTTP server,
  report-card rendering, typed report-card defaults, typed live plan rendering,
  and, when the `kind` binary is present and the active Docker context answers
  `docker info`, the absence of leaked `jitml-e2e-*` Kind clusters. When Docker
  is unreachable, the no-leak query fails closed instead of passing vacuously.
- The target live path runs typed `helm dependency build chart` before apply and
  records whether `Chart.lock` is part of the reproducible dependency surface.
- Default `cabal test jitml-e2e` remains local. The full live path is a separate
  explicit orchestration command, not a process-environment gate.
- Playwright invocation is represented in the typed live plan and is validated
  live against the demo edge route (Phase `15` Sprint `15.14`, 7/7 panel
  matrix).

### Validation

1. `cabal test jitml-e2e` exits `0` for the scaffold body.
2. `cabal test jitml-e2e` verifies the rendered live plan contains the
   Helm dependency-build and Playwright steps.
3. Transferred live validation: the explicit live e2e orchestration runs the full
   sequence: `helm dependency build chart`
   → `jitml bootstrap` (ephemeral Kind) → demo cohorts reach Ready behind the
   real Envoy listener →
   pinned `mcr.microsoft.com/playwright:v1.49.1-noble` browser-image Playwright run
   against every canonical panel → `jitml cluster down`. Teardown leaves no
   orphan Kind clusters, Harbor projects, PVs, or Docker
   volumes.

### Remaining Work

- No sprint-owned code-surface Remaining Work remains. Live phased Helm
  + Pulsar topic creation rollout against a real Kind cluster is owned
  by
  [phase-15-linux-cuda-and-cluster-closure.md](phase-15-linux-cuda-and-cluster-closure.md)
  Sprint `15.1`; live Playwright against the edge route and full live
  teardown leak-detection are owned by Phase `15` Sprint `15.14`.

## Sprint 12.9: `jitml test all` Orchestrator and Report Card ✅

**Status**: Done
**Owned obligations after refactor**: code-surface only. Live `jitml
test all` mode threading live measurements into the report card and the
live integration test that surfaces real metrics migrated to Phase `17`
Sprint `17.2`.
**Implementation**: `src/JitML/App.hs`,
`src/JitML/Test/Report.hs`,
`cabal.project` (report-card knob block)
**Docs to update**: `documents/engineering/unit_testing_policy.md`

### Objective

Land `jitml test all` (Plan/Apply with `--dry-run` and `--plan-file`) as the
current operator-facing report-card surface, plus the report-card emitter that
prints the tidy summary block answering the canonical questions (SL
convergence, RL reward, AlphaZero arena win rate, JIT cache hit rate, daemon
health, and the then-planned cross-substrate comparison summary).

### Deliverables

- Target `jitml test all` plan steps:
  1. Resolve prerequisites.
  2. Schedule each stanza (`jitml-unit`, `jitml-integration`,
     `jitml-sl-canonicals`, `jitml-rl-canonicals`, `jitml-hyperparameter`,
     `jitml-cross-backend`, `jitml-daemon-lifecycle`, `jitml-e2e`) under `cabal test`
     through the typed `Subprocess` boundary.
  3. Aggregate results into the report card.
- Current `jitml test all --dry-run` renders the aggregate plan from
  `src/JitML/Plan/Plan.hs`; current non-dry-run `jitml test all` invokes
  Cabal through `JitML.Sub.Stream.runStreaming` and then renders a typed
  `ReportCard` with `ReportCardKnobs` and the actual target stanza list after
  Cabal succeeds. Without a substrate selector it keeps the legacy single
  `cabal test` invocation over the explicit test-only stanza names; with a
  substrate selector it serializes stanzas as separate Cabal subprocesses so
  live tests do not contend over one cluster/device.
- The report-card knob block in `cabal.project` carries `sl_epochs`,
  `sl_batch`, `rl_steps`, `rl_eval_episodes`, `az_games`, `az_sims`,
  `tune_trials`, `tune_budget_per_trial`, `xcluster_kind_nodes` (see
  [system-components.md → POC Report-Card
  Knobs](system-components.md#poc-report-card-knobs)).
- `src/JitML/Test/Report.hs` renders the tidy summary block on stdout, exposes
  `parseReportCardKnobs`, and `jitml test all` now reads the `cabal.project`
  knob block before rendering the report card instead of relying only on the
  in-code defaults. `renderReportCardForTargets` renders the expanded
  eight-stanza list for `jitml test all` and the selected stanza for
  `jitml test <stanza>`.
- `jitml test <stanza>` invokes that single Cabal stanza through the same typed
  `Subprocess` boundary.
- 2026-05-19 container validation ran `jitml test all --dry-run` and
  non-dry-run `jitml test all` inside `jitml:local`; the non-dry-run path
  passed all eight test stanzas and printed the report card with the
  `cabal.project` knob values.
- 2026-05-21 local validation re-ran `jitml test all --dry-run` and
  non-dry-run `jitml test all`; all eight test stanzas passed and the
  report-card summary printed the current knob block plus target stanza list.

### Validation

1. `jitml test all --dry-run` emits the typed plan enumerating all eight
   test stanzas.
2. `jitml test all` invokes Cabal over the explicit eight test-only stanza
   names (serializing by stanza under a substrate selector), exits `0` on the
   current tree, parses the `cabal.project` report-card knob block, and prints
   the target-stanza report card.
3. `cabal test jitml-e2e` verifies report-card default rendering and that the
   `cabal.project` knob block matches the typed defaults.
4. Transferred live validation: the explicit live `jitml test all` path schedules
   the live `jitml-e2e` body too; the rendered report card adds live
   measurements (SL convergence, RL reward, AlphaZero arena win rate,
   JIT cache hit rate, daemon health, and final handoff fields)
   on top of the target-stanza summary.

### Remaining Work

- No sprint-owned code-surface Remaining Work remains. The live `jitml
  test all` mode threading live measurements into the report card, the
  population of canonical report-card metrics with real data, and the
  live integration test that confirms the populated report card are
  owned by
  [phase-17-cross-substrate-and-handoff.md](phase-17-cross-substrate-and-handoff.md)
  Sprint `17.2`.

## Sprint 12.10: Substrate-partitioned test lanes; remove the cross-substrate parity test surface ✅

**Status**: Done (closed 2026-06-09 on the NVIDIA GeForce RTX 5090 host after the live `linux-cuda` lane re-validation)
**Implementation**: `test/cross-backend/Main.hs`, `test/unit/Main.hs`,
`test/integration/Main.hs`, `src/JitML/Test/Report.hs`, `src/JitML/App.hs`,
`jitml.cabal` (the `jitml-cross-backend` / `jitml-unit` / `jitml-integration`
stanzas), `cabal.project` (report-card knob block)
**Docs to update**: `documents/engineering/unit_testing_policy.md`

### Objective

Realign the test surface to the clarified reproducibility contract —
within a substrate: bit-for-bit reproducible; across substrates: NO
guarantee. The cross-substrate numeric parity surface is therefore removed
in full, the cross-backend / canonicals / integration stanzas are
partitioned into per-substrate lanes selected with the
`--test-options='-p <substrate>'` switch (added by Phase 1 Sprint `1.13`),
and every selected case runs for real in its lane with NO skip sentinels — a
missing toolchain fails by design. Within-substrate bit-for-bit
reproducibility coverage stays, including ALL `linux-cuda` within-substrate
cases (CUDA is NOT being removed). This keeps each stanza inside its
doctrine [Test Organization](../README.md#test-suite-stanzas) shape
(`type: exitcode-stdio-1.0`, `tasty` per stanza, no spanning tree) and the
doctrine [Test Categories](../README.md#test-suite-stanzas) mapping while
dropping the cross-substrate parity category that the contract no longer
supports.

### Deliverables

- `jitml-cross-backend` (`test/cross-backend/Main.hs`) realigned to
  within-substrate cases only: the `CrossSubstrate weighted drift
  assertions` test group is deleted.
- The two substrate-agnostic cross-backend cases — "each substrate has
  deterministic engine flags" and "checkpoint inference is backend
  independent for manifest reads" — are relocated into `jitml-unit`
  (`test/unit/Main.hs`).
- The cross-substrate tolerance-band test group is deleted from
  `test/unit/Main.hs`.
- The report-card `cross_substrate_parity` field is removed:
  `ReportMeasurements` in `src/JitML/Test/Report.hs` loses the field, and
  `measureCrossSubstrateParity` plus its call site are removed from
  `src/JitML/App.hs`.
- Substrate-partitioned `jitml test` lanes are wired: each substrate's
  cases run for real in its own lane selected via
  `jitml test ... --test-options='-p <substrate>'` (the `-p` switch is
  added by Phase 1 Sprint `1.13`); the six pure-logic stanzas
  (`jitml-unit`, `jitml-sl-canonicals`, `jitml-rl-canonicals`,
  `jitml-hyperparameter`, `jitml-daemon-lifecycle`, `jitml-e2e`) run in
  every lane; NO tests are skipped — a missing toolchain fails by design.
- The skip-antipattern guards are removed from the cross-backend and
  integration test bodies: the `probeCudaRuntime` / `cudaRuntimeAvailable`,
  `appleLiveReady`, and `cublasBindingsCompiledIn` /
  `cudnnBindingsCompiledIn` skip branches, and the oneDNN-availability
  assertion in the integration probe test. Within-substrate bit-for-bit
  reproducibility tests STAY — including ALL `linux-cuda` within-substrate
  cases.

### Historical Validation

Each lane is green with every selected case actually executing (no
skip-sentinels):

1. Apple host (`apple-silicon` lane): `bootstrap/apple-silicon.sh test`.
2. linux-cpu lane:
   `docker compose run --rm jitml jitml test ... -p linux-cpu`.
3. linux-cuda lane:
   `docker compose run --rm jitml-cuda jitml test ... -p linux-cuda -fcuda`.
4. Container code-quality gate: `jitml check-code`.

### Remaining Work

- **The test/report code edits have landed** (2026-06-08): the `CrossSubstrate
  weighted drift assertions` group and every skip-guard branch
  (`probeCudaRuntime` / `cudaRuntimeAvailable`, `appleLiveReady`,
  `cublasBindingsCompiledIn` / `cudnnBindingsCompiledIn`) are removed from
  `test/cross-backend/Main.hs`; the two substrate-agnostic cases
  (`each substrate has deterministic engine flags`, `checkpoint inference is
  backend independent for manifest reads`) are relocated into
  `test/unit/Main.hs` and the cross-substrate tolerance-band group there is
  deleted; the `cross_substrate_parity` field is removed from
  `ReportMeasurements` (`src/JitML/Test/Report.hs`) and
  `measureCrossSubstrateParity` plus its call site are removed from
  `src/JitML/App.hs`; the oneDNN-availability assertion is removed from the
  integration probe test; and the per-substrate `--test-options='-p
  <substrate>'` lanes are wired (the passthrough landed in Sprint `1.13`). The
  cuBLAS / cuDNN cases are renamed with the `linux-cuda` prefix so
  `-p linux-cuda` selects them, and every remaining cross-backend case carries
  its substrate id so `-p <substrate>` partitions cleanly.
- **Validated lanes (2026-06-08):** the `apple-silicon` lane ran for real
  host-native — `jitml test jitml-cross-backend --test-options='-p
  apple-silicon'` selected exactly the four Metal cases and passed **4 / 4
  (88.90s, no skip-sentinels)**; `jitml-unit` passed **193 / 193** host-native
  (covering the relocated backend-agnostic group and the new
  `--test-options` parse case); the whole edited suite compiles + links clean
  host-native; `jitml docs check` is green. The `linux-cpu` lane and the
  container `jitml check-code` gate run in the `jitml` container.
- **linux-cuda lane re-validated (2026-06-09, RTX 5090):** on the NVIDIA
  GeForce RTX 5090 host (UUID `GPU-e764ef97-32d7-4981-c348-029983c64073`) the
  GPU-attached `jitml-cuda` compose service ran the lane for real —
  `docker compose run --rm jitml-cuda cabal test -fcuda jitml-cross-backend
  --test-options '-p linux-cuda'` passed **19 / 19 (12.26s, no skip-sentinels)**,
  selecting exactly the within-substrate CUDA cases (the `-fcuda` cabal build
  flag compiles the real cuBLAS / cuDNN bindings, and the GPU lane is driven
  through the GPU container's `cabal test -fcuda` form per the `jitml-cuda`
  compose-service contract and every historical CUDA evidence line; the
  flag-free `jitml test` orchestrator owns the apple-silicon / linux-cpu lanes).
  This closes the sprint's one remaining obligation — owned jointly with Sprint
  `15.16`, whose [GPU Re-validation Evidence](phase-15-linux-cuda-and-cluster-closure.md#gpu-re-validation-evidence-2026-06-09-rtx-5090)
  records the full case list. Sprint `12.10` is `✅ Done`.

## Sprint 12.11: DRY Real-Workflow Matrix, Fail-Closed ✅

**Status**: Done
**Implementation**: a new `JitML.Test.WorkflowMatrix` enumeration consumed by
`test/integration/Main.hs` and `test/e2e/Main.hs`
**Docs to update**: `../documents/engineering/unit_testing_policy.md`,
`system-components.md`

### Objective

Run every reopened real workflow (SL train, SL eval, RL train, RL eval, RL
rollout, tune, inference, AlphaZero self-play) per substrate behind one DRY
matrix that **fails closed** without a live cluster, replacing the vacuous-pass
`-p Live` asserts (which called the pure trainer and asserted stdout prefixes,
passing even offline) and the model-less e2e asserts. Owns the test-surface
slice of [Exit Definition](README.md#exit-definition) item 17.

### Deliverables

- `JitML.Test.WorkflowMatrix` is the single typed enumeration of
  `(workflow, substrate)` cells with the canonical command + the expected
  real-output assertion for each; the integration `Live` runner iterates it
  rather than re-deriving per-workflow asserts, and `jitml-e2e` asserts the
  full matrix shape alongside the typed live e2e plan.
- Each cell **fails closed** without a live `cluster-publication.json` (no
  vacuous pass); a cell passes only when the real workflow produced real
  measured output on the resolved substrate.

### Validation

- Offline: the matrix fails closed (no live cluster → typed failure, not a
  vacuous pass); host-validatable.
- Structural e2e: `jitml-e2e` verifies complete workflow × substrate matrix
  coverage and the typed live e2e plan.
- Live workflow executor: `jitml-integration -p WorkflowMatrix` runs every
  current-substrate matrix cell against a live cluster.

### Current Validation State

Landed: `JitML.Test.WorkflowMatrix` enumerates the 8 reopened workflows × every
substrate (`workflowMatrix`), each cell carrying its canonical `jitml` command
(`workflowCommand`) with real positional experiment arguments and stable
checkpoint / experiment hashes for eval and inference. `test/e2e/Main.hs`
asserts the matrix covers every workflow × substrate and that each cell carries
a command (host-validatable coverage).

`test/integration/Main.hs` now adds the matrix-driven `Live` case. It loads the
current live publication, filters `WorkflowMatrix.workflowMatrix` to the current
substrate, asserts exactly one cell per workflow, stages minimal MNIST IDX
training data when missing, stages stable eval / inference checkpoints in
MinIO, and runs the canonical CLI command for every cell with real-output
snippets. The AlphaZero cell executes `jitml rl alphazero self-play`, which
probes the selected substrate `MlpDevice`, generates MCTS self-play samples
through device-backed leaf policy/value evaluation, trains the policy/value
head on-device, and reports sample count plus arena win rate.

Current local validation (2026-06-11 / 2026-06-12):

- `docker compose run --rm jitml cabal run jitml -- rl alphazero self-play
  --substrate linux-cpu --seed 31` passed and printed
  `rl alphazero self-play: substrate=linux-cpu`, `samples: 12`, and
  `arena-win-rate: 0.5`.
- `docker compose run --rm jitml jitml test jitml-unit --linux-cpu` passed
  **196 / 196** after the CLI parser / canonical leaf update.
- `docker compose run --rm jitml jitml test jitml-rl-canonicals --linux-cpu`
  passed **28 / 28** after the device-backed AlphaZero sample-generation path
  landed.
- `docker compose run --rm jitml cabal test jitml-e2e` passed **20 / 20**.
- `docker compose run --rm jitml cabal test jitml-integration
  --test-show-details=direct --test-options='-p !/Live/'` passed **49 / 49**,
  compiling the new
  integration code while excluding the live group.
- `docker compose run --rm jitml cabal test jitml-integration
  --test-show-details=direct --test-options='-p WorkflowMatrix'` failed closed
  with no publication, as expected, with a `cluster-publication.json not found
  at .build/runtime/cluster-publication.json` failure that instructs the
  operator to run `jitml bootstrap --<substrate>` before `-p Live` tests.
- `docker compose run --rm jitml cabal run jitml -- docs check` passed after
  regenerating the CLI command docs / man page / completions for
  `jitml rl alphazero self-play`.
- `docker compose run --rm jitml cabal run jitml -- check-code` passed
  (`check-code: ok`) after the final HLint cleanup in the live binary locator.

Resolved live-validation failures on this host (2026-06-11 / 2026-06-12):

- `docker compose run --rm jitml cabal run jitml -- bootstrap --linux-cpu`
  failed at the Harbor Helm wait after **23** rollout steps on the preserved
  `.data` tree. Harbor core logged `Dirty database version 15. Fix and force
  version.`
- The failed cluster was torn down through `jitml cluster down`, the dirty
  `.data` tree was preserved as `.data-preserved-phase12-20260611-204433`, and
  `docker compose run --rm jitml cabal run jitml -- bootstrap --linux-cpu` was
  retried against a clean `.data` tree. The clean retry failed at the same
  Harbor Helm wait after **22** rollout steps; Harbor core logged
  `Dirty database version 1. Fix and force version.`
- While that failed cluster was up, the live `WorkflowMatrix` selector reached
  the published edge but failed during dataset staging because `/healthz` and
  `/minio/s3` returned `curl: (52) Empty reply from server`; this matches the
  incomplete Harbor/Gateway rollout rather than an AlphaZero matrix-code
  failure.
- The failed retry was torn down through `jitml cluster down`; `kind get
  clusters` then reported no Kind clusters.
- The bootstrap path was then fixed so `linux-cpu` uses the same node-local
  Percona Postgres PV overlay as Apple Silicon on Docker Desktop, while
  `linux-cuda` keeps direct `.data` ownership normalization on real Linux GPU
  hosts.
- The Harbor schema grant now makes the Harbor database owned by the `harbor`
  role before granting privileges on `public`, preventing migration writes from
  inheriting the wrong owner on fresh local clusters.
- `liveExecutePhasedRollout` removes stale
  `.build/runtime/cluster-publication.json` before selecting and publishing a
  fresh live coordinate, so a failed or cross-substrate publication cannot send
  validation traffic to the wrong edge.
- `EnvoyProxy/jitml-edge` now pins the managed Envoy data-plane request to
  `cpu: 50m` / `memory: 512Mi` with a `1Gi` memory limit, allowing the local
  Kind stack to schedule the proxy while keeping large dataset/archive uploads
  inside a bounded data-plane envelope.
- The live WorkflowMatrix runner now prefers the freshly built
  `dist-newstyle/.../jitml` executable over the container image's installed
  fallback, so newly added CLI leaves are exercised by the test binary that was
  just built.

Linux live validation is no longer blocked on this machine:

- `docker compose run --rm jitml cabal run jitml -- bootstrap --linux-cpu`
  passed **83** live rollout steps against a clean `linux-cpu` cluster on
  2026-06-12.
- `curl -i --max-time 10 http://127.0.0.1:9091/healthz` returned
  `HTTP/1.1 200 OK`, and `Gateway/jitml-edge` reported `Programmed=True`.
- `docker compose run --rm jitml cabal test jitml-integration
  --test-show-details=direct --test-options='-p WorkflowMatrix'` passed
  **1 / 1** against that live `linux-cpu` cluster on 2026-06-12, and passed
  again after the binary-locator HLint cleanup.
- `docker compose run --rm jitml cabal test jitml-integration
  --test-show-details=direct` passed **67 / 67** against a clean
  `linux-cpu` cluster on 2026-06-11.
- `docker compose run --rm jitml jitml test jitml-e2e --linux-cpu` passed
  **20 / 20** on 2026-06-11.
- `docker compose run --rm jitml-cuda cabal test -fcuda jitml-integration
  --test-show-details=direct` passed **67 / 67** against a fresh
  `linux-cuda` cluster on 2026-06-11.
- `docker compose run --rm jitml-cuda jitml test jitml-e2e --linux-cuda`
  passed **20 / 20** on 2026-06-11.

### Remaining Work

None. The integration `Live` group is the sprint-owned real-workflow matrix
executor; `jitml-e2e` remains the structural/browser/live-plan stanza. The
Apple matrix execution belongs to Phase `16`, and final handoff belongs to
Phase `17`. The later failed-Job observation gap is owned by Sprint `12.12`.

## Sprint 12.12: Live Job Failure Observation and Apple Placement Assertions ✅

**Status**: Done
**Implementation**: `test/integration/Main.hs`,
`src/JitML/Test/WorkflowMatrix.hs`, `src/JitML/Service/Workload.hs`
**Docs to update**: `../README.md`,
`../documents/engineering/unit_testing_policy.md`,
`../documents/engineering/daemon_architecture.md`,
`system-components.md`

### Objective

Make live integration tests observe workload placement failures directly. A
failed Kubernetes Job must fail the test promptly with status and pod logs, and
Apple Metal-backed workloads must assert host-resident placement rather than
waiting for domain events that can never arrive.

### Deliverables

- Add a live Job watcher used by integration convergence collectors. When a
  daemon-dispatched Job reaches `Failed` / `BackoffLimitExceeded`, collect the
  owning Job, pod names, container states, and logs, then fail the test.
- Add Apple placement assertions for `training.command.apple-silicon`,
  `rl.command.apple-silicon`, and `tune.command.apple-silicon`: Metal-backed
  cells must produce host workload commands and must not create `jitml-train-*`,
  `jitml-rl-*`, or `jitml-tune-*` Kubernetes Jobs.
- Keep Linux CPU/CUDA tests asserting that their command envelopes still create
  valid in-cluster Jobs.
- Preserve the no-skips lane rule: a missing device/runtime fails the owning lane
  up front instead of silently passing or polling until timeout.

### Validation

- `docker compose run --rm jitml cabal build all` passed after the failed-Job
  watcher and WorkflowMatrix placement expectation edits.
- `docker compose run --rm jitml cabal test jitml-integration
  --test-show-details=direct --test-options='-p !/Live/'` passed **51 / 51**,
  including the synthetic failed-Job renderer and Apple-vs-Linux placement unit
  assertions.
- `docker compose run --rm jitml cabal test jitml-e2e
  --test-show-details=direct` passed **20 / 20**, including complete
  WorkflowMatrix placement-expectation coverage.
- `docker compose run --rm jitml jitml check-code` passed after the HLint
  eta-reduction fix.
- `./bootstrap/linux-cpu.sh up` completed **83** live rollout steps, and the
  focused `linux-cpu` live selectors for `StartTraining`, duplicate
  `StartTraining`, `StartSweep`, `StartRLRun`, and PPO convergence all passed.
  The Linux selectors still observe legal in-cluster Jobs and the RL/PPO
  collectors now watch those Jobs for failure while consuming Pulsar events.
- `./bootstrap/apple-silicon.sh up` completed **83** live rollout steps after
  the host Cabal package registration was repaired. A stale `jitml:local` image
  had left the Apple service pod running old placement code, so
  `src/JitML/Bootstrap.hs` now rebuilds repo-owned local images during bootstrap;
  after `docker compose build jitml`, `kind load docker-image jitml:local
  --name jitml-apple-silicon`, and `kubectl rollout restart
  deployment/jitml-service -n platform`, the focused Apple live selectors for
  `StartTraining`, duplicate `StartTraining`, `StartSweep`, `StartRLRun`, and
  PPO convergence all passed. A final `kubectl get jobs -n platform` showed only
  platform init/backup Jobs, with no `jitml-train-*`, `jitml-rl-*`, or
  `jitml-tune-*` workload Jobs.
- `docker compose run --rm jitml jitml docs check`, `docker compose run --rm
  jitml jitml check-code`, and `git diff --check` are the final documentation
  alignment gates for the reopened Phase `12` closure.

### Remaining Work

None. Phase `16` owns the full Apple lifecycle lane and Phase `17` owns the
final ledger walk-down.

## Sprint 12.13: Playwright No-Caveat E2E Matrix ✅

**Status**: Done (closed 2026-06-16 on the owned host-validatable e2e/matrix/report
structure; the live Playwright product-matrix execution was deduped to its owning
downstream sprints per standards rule E — see "Owned Surface Closed; Live
Obligations Deferred" below)
**Implementation**: `playwright/jitml-demo.spec.ts`, `test/e2e/Main.hs`,
`src/JitML/Test/LivePlan.hs`, `src/JitML/Test/WorkflowMatrix.hs`
**Docs to update**: `documents/engineering/unit_testing_policy.md`,
`documents/engineering/purescript_frontend.md`, `system-components.md`,
`legacy-tracking-for-deletion.md`

### Objective

Make `jitml-e2e` and Playwright validate the full no-caveat app/product matrix
instead of structural reachability plus a few REST assertions.

### Deliverables

- `jitml-e2e` brings up an ephemeral cluster, runs the compiled browser bundle
  through the routed Envoy edge, executes the Playwright product matrix, and
  tears the cluster down with `bracket` even on failure.
- Playwright starts every canonical SL workflow, observes live training events,
  verifies checkpoint creation, opens model-specific interaction panels, and
  asserts real inference output from the produced checkpoint.
- Playwright starts RL workflows for each algorithm family, observes live
  episode/trajectory frames, verifies canvas animation, records a trajectory,
  and replays/scrubs it in the browser.
- Playwright drives Connect 4, Othello, Hex, and Gomoku against AlphaZero
  checkpoints, verifies legal moves, MCTS visit distributions, value estimates,
  and interactive replay controls.
- Playwright launches and controls a bounded tuning sweep, verifies live
  frontier/heatmap/trial updates, kills a trial, promotes a trial, and verifies
  the promoted checkpoint is usable.
- The report card includes a no-caveat browser/product section; unavailable,
  placeholder, skipped, or synthetic rows fail the e2e lane when hardware and
  cluster prerequisites are present.

### Historical Validation

- `docker compose run --rm jitml jitml test jitml-e2e --linux-cpu`
- `docker compose run --rm jitml-cuda jitml test jitml-e2e --linux-cuda`
- `jitml test jitml-e2e --apple-silicon`
- `docker compose run --rm jitml jitml docs check`
- `docker compose run --rm jitml jitml check-code`

### Current Validation State

The 2026-06-15 Sprint `12.13` slice lands the host-validatable Haskell structure
for the no-caveat browser/product matrix:

- `JitML.Test.WorkflowMatrix` now enumerates the no-caveat browser/product cells
  alongside the existing per-substrate workflow matrix: a `BrowserProductInteraction`
  type (training launch, checkpoint open, MNIST/image/generic inference,
  checkpoint compare, RL animation, RL trajectory replay, adversarial play,
  adversarial replay, tuning sweep control, tuning trial promote), the
  `browserAdversarialGames` list (Connect 4, Othello, Hex, Gomoku), per-cell
  `browserProductInteractionLabel` descriptions, and `browserProductMatrix`
  crossing every interaction with every substrate — the DRY structure the live
  Playwright lane iterates.
- `JitML.Test.Report.ReportMeasurements` gains a `measuredBrowserProductMatrix`
  field; the live collector (`collectLiveReportMeasurements`) reports it
  `MeasurementUnavailable` until Phase `14` exercises the matrix live, so a live
  report card that has not proven the browser product surface keeps the
  no-caveat handoff honestly open (Sprint `18.1`) instead of omitting the row.
- Validated: `docker compose run --rm jitml jitml test jitml-e2e --linux-cpu`
  (23 / 23, including the new "browser product matrix enumerates every no-caveat
  interaction on every substrate" case and the `browser_product_matrix: unavailable`
  report-card assertion); `docker compose run --rm jitml jitml check-code`.

### Owned Surface Closed; Live Obligations Deferred (rule E)

Every remaining obligation is **live-runtime** and is already owned by a
downstream sprint, so it lives there per standards rule E (one obligation, one
place) and the live-obligation consolidation doctrine:

- Replacing the panel-visibility Playwright assertions with the no-caveat
  workflow-launch/event/checkpoint/inference/animation/replay/control product
  matrix, and populating `measuredBrowserProductMatrix` with a real measured
  value → **Sprint `14.2` (Playwright No-Caveat Product Matrix)**, which already
  owns exactly this expansion.
- Executing that matrix live and failing closed on any missing
  `browserProductMatrix` cell artifact → the per-lane live runs in
  **Sprint `15.20` (linux-cpu / linux-cuda)** and **Sprint `16.11`
  (apple-silicon)**.

The host-validatable structure Sprint `12.13` owns — the
`JitML.Test.WorkflowMatrix` `browserProductMatrix` enumeration, the
`browser_product_matrix` report-card field, and the `jitml-e2e` structural
assertions — is in place and validated (`jitml-e2e --linux-cpu` 23 / 23,
`check-code` ok; see Current Validation State above).

## Doctrine Sections Cited

- [../README.md → Test-suite stanzas](../README.md#test-suite-stanzas) (every sprint)
- [../README.md → Standard Testing Stack](../README.md#doctrine-scope) (every sprint)
- [../README.md → Test Categories](../README.md#test-suite-stanzas) (every sprint — eight stanzas cover all seven doctrine categories plus the project-specific Integration extensions)
- [../README.md → Test Organization](../README.md#test-suite-stanzas) (every sprint — `type: exitcode-stdio-1.0`, `tasty` per stanza, no spanning tree; project-specific stanzas under the Integration category)
- [../README.md → Plan / Apply](../README.md#doctrine-scope) (Sprint 12.9)
- [../README.md → Subprocesses as Typed Values](../README.md#doctrine-scope) (every sprint)
- [../README.md → Long-Running Daemons in the Same Binary](../README.md#doctrine-scope) (Sprint 12.7)
- [../README.md → At-Least-Once Event Processing](../README.md#doctrine-scope) (Sprint 12.7)
- [../README.md → Test Categories](../README.md#test-suite-stanzas) (Sprint 12.10 — drops the cross-substrate parity category; the within-substrate categories per lane stay)
- [../README.md → Test Organization](../README.md#test-suite-stanzas) (Sprint 12.10 — substrate-partitioned lanes via `--test-options='-p <substrate>'` keep each stanza's `exitcode-stdio-1.0` + `tasty` shape with no spanning tree)

## Sprint 12.14: Common-Shape Workflow, Topic-Algebra, and Websocket Coverage ✅

**Status**: Done
**Validation State**: Coverage landed + validated. The `Work*`/topic-algebra/
`.ready` unit coverage landed with Sprints `5.13`/`5.14`/`10.7`; this sprint
added the remaining websocket snapshot/patch + composite-command coverage now
that `11.10` is Done:
- **`test/unit/Main.hs`** — `DecodedInference` decode + the composite Engine
  commands (`CheckpointCompareCommand`/`AdversarialMoveCommand` render→parse
  round-trip) + MCTS move-legality.
- **`web/test/Main.purs`** — `parseDecodedInference` + `parseCompareFrame` +
  `parseMoveFrame`: the Engine-computed websocket snapshot frames apply
  mechanically in the browser, with no panel compute.

Validated (offline closure gate): `jitml-unit` **208/208**,
`jitml-daemon-lifecycle` **35/35**, `jitml-e2e` **23/23**, `spago test`
**17/17**, `jitml lint purescript: ok`, `jitml docs check: ok`, `jitml
check-code: ok`. The `jitml-integration` `-p Live` lane (live `linux-cpu`
cluster) is the runtime gate per rule M(b); offline integration is green
(52/52), the Live subset re-validates against a freshly bootstrapped cluster.
**Implementation**: `test/unit/Main.hs`, `test/daemon-lifecycle/Main.hs`,
`test/integration/Main.hs`, `test/e2e/Main.hs`, `web/test/Main.purs`
**Docs to update**: `../documents/engineering/unit_testing_policy.md`,
`../documents/engineering/pulsar_ml_workflow.md`, `system-components.md`

### Objective

Add the test coverage for the common Pulsar ML-workflow shape so the convergence
deltas are gated, per the
[../documents/engineering/pulsar_ml_workflow.md](../documents/engineering/pulsar_ml_workflow.md)
`Conformance checklist`. Adopts `Test Organization` and `At-Least-Once Event
Processing` from [../README.md](../README.md).

### Deliverables

- `Work*` envelope coverage: training and inference share `WorkCommand →
  WorkEvent* → WorkResult` correlated by `callId`; producer-side dedup keyed by
  `callId` is a pure fold over the work log (offline, no broker).
- Topic-algebra coverage: the coordinator's reconciled topic set **equals** the
  validated routing graph's derived set; the validator rejects an unroutable
  descriptor and one-sided command↔event links.
- `.ready` readiness-gate coverage: infer-before-ready yields a typed rejection;
  a serveable `ArtifactRef` is mintable only from a completed training derivation.
- Websocket coverage: snapshot/patch frames apply mechanically in the browser
  (`web/test`), and inference is asynchronous to the browser (no synchronous
  compute-and-return).

### Validation

- `docker compose run --rm jitml jitml test jitml-unit --linux-cpu`,
  `jitml-daemon-lifecycle --linux-cpu`, `jitml-integration --linux-cpu`,
  `jitml-e2e --linux-cpu` (per standards rule M(b), the `linux-cpu` lane is the
  closure gate; accelerator lanes are attested in Phases `15`/`16`).
- `jitml lint purescript` for the `web/test` snapshot/patch spec.
- `docker compose run --rm jitml jitml docs check` and `jitml check-code`.

### Remaining Work

- None. The `Work*`, topic-algebra, `.ready`, and websocket snapshot/patch test
  groups have landed (unit + `web/test`); the live `linux-cpu` integration lane is
  the standard runtime gate (rule M(b)), exercised on a bootstrapped cluster.

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/run_contract.md` — the functional-core live workflow
  interpreter, exact reducer, scoped lifecycle, and scenario journal.
- `documents/engineering/unit_testing_policy.md` — populate the ten-stanza
  surface, the doctrine-category mapping (including the project-specific
  Integration extensions), the
  Ephemeral-Cluster Infrastructure test pattern, the report-card
  narrative, and the per-stanza notes for canonicals / hyperparameter /
  cross-backend / daemon-lifecycle / e2e. **Sprint 12.10**: record the
  substrate-partitioned lane model (`--test-options='-p <substrate>'`; nine
  non-backend stanzas in every lane; no skip sentinels — a missing toolchain
  fails by design), the within-substrate-only realignment of
  `jitml-cross-backend`, and the removal of the cross-substrate parity test
  surface and report-card field per the clarified reproducibility contract
  (within a substrate: bit-for-bit; across substrates: no guarantee).
  **Sprint 12.12**: record failed Kubernetes Job fail-fast observation and
  Apple host-resident placement assertions.
- `documents/engineering/training_workloads.md` — SL canonicals threshold
  methodology, RL canonicals reward distribution methodology, hyperparameter
  sampler / scheduler / pruner reproducibility expectations.
- `documents/engineering/determinism_contract.md` — **Sprint 12.10**
  supersedes the prior cross-substrate per-tensor tolerance methodology
  with the clarified contract (within a substrate: bit-for-bit
  reproducible; across substrates: NO guarantee). `jitml-cross-backend`
  now enforces only within-substrate bit-for-bit reproducibility per lane;
  the cross-substrate tolerance-band enforcement is removed.
- `documents/engineering/daemon_architecture.md` — daemon lifecycle test
  surface, SIGHUP reload, at-least-once consumer idempotency, and placement-test
  expectations for Apple host-resident work.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- `system-components.md → Test Stanzas`, `Test Categories Mapping`, and
  `POC Report-Card Knobs` rows remain aligned with the ten Cabal stanzas and
  `src/JitML/Test/Report.hs`.
- [legacy-tracking-for-deletion.md → Pending Removal](legacy-tracking-for-deletion.md#pending-removal) —
  Sprint `12.10` owns the Pending Removal rows for the report-card
  `cross_substrate_parity` field
  (`src/JitML/Test/Report.hs` `ReportMeasurements` + `src/JitML/App.hs`
  `measureCrossSubstrateParity` and its call site), the `CrossSubstrate
  weighted drift assertions` group in `test/cross-backend/Main.hs`, the
  cross-substrate tolerance-band group in `test/unit/Main.hs`, and the
  skip-guard antipattern branches (`probeCudaRuntime` /
  `cudaRuntimeAvailable`, `appleLiveReady`, `cublasBindingsCompiledIn` /
  `cudnnBindingsCompiledIn`, and the oneDNN-availability assertion in the
  integration probe test). Each row resolves when the Sprint `12.10` code
  edits land.
- [legacy-tracking-for-deletion.md → Pending Removal](legacy-tracking-for-deletion.md#pending-removal) —
  Sprint `12.12` verifies the Sprint `5.11` removal row by asserting Apple
  Metal-backed commands do not create Kubernetes Jobs.

## Sprint 12.15: Per-Model Integration and E2E Matrix [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Test/WorkflowMatrix.hs`,
`test/integration/Main.hs`, `test/e2e/Main.hs`,
`playwright/jitml-demo.spec.ts`
**Docs to update**: `../documents/engineering/unit_testing_policy.md`,
`../documents/engineering/training_workloads.md`,
`../documents/engineering/purescript_frontend.md`, `system-components.md`

### Objective

Replace workflow-category coverage with per-model coverage. Every supported
SL, RL, and AlphaZero row must have integration/e2e proof that its fixed budget
can complete, its convergence statistics enter the checkpoint, and inference is
rejected before completion.

### Deliverables

- Expand `WorkflowMatrix` from coarse workflow cells to model cells for all 11
  SL rows, all RL algorithm rows, HER, and every AlphaZero game.
- Remove hardcoded transport-smoke checkpoints from live inference proof and
  replace them with trained-artifact fixtures produced by the workflow matrix.
- Add infer-before-complete and untrained-demo-checkpoint negative tests.
- Ensure `jitml-e2e` local fake-runtime tests are clearly structural only and
  cannot satisfy the live no-caveat model matrix.

### Validation

- `docker compose run --rm jitml jitml test jitml-integration --linux-cpu`
- `docker compose run --rm jitml jitml test jitml-e2e --linux-cpu`
- `docker compose run --rm jitml jitml docs check`

### Current Validation State

- `docker compose run --rm jitml cabal test jitml-e2e --test-show-details=direct`
  passed **23 / 23**.
- `docker compose run --rm jitml cabal run jitml -- test jitml-e2e --linux-cpu`
  passed through the project wrapper with **23 / 23** tests.
- `docker compose run --rm jitml cabal test jitml-integration --test-show-details=direct`
  passed all non-live integration cases, including the partial-checkpoint
  negative loader test. The live group failed fast because no bootstrapped
  cluster publication exists at `.build/runtime/cluster-publication.json`.
- `docker compose run --rm jitml cabal test jitml-integration --test-show-details=direct`
  later passed **53** non-live integration cases after adding a
  checkpoint-browser selector negative test that omits incomplete manifests from
  the `CheckpointList` summary. The **19** live cases still fail fast without a
  bootstrapped cluster publication.
- `./bootstrap/linux-cpu.sh up` completed the live `linux-cpu` rollout
  (**111** steps), and
  `docker compose run --rm jitml cabal test jitml-integration --test-show-details=direct`
  passed **72 / 72** against the bootstrapped cluster. The live matrix now
  observes the new RL completion metric/checkpoint events through a single
  Pulsar subscription pass without losing completion frames while collecting
  episode frames.
- `docker compose run --rm jitml cabal run jitml -- docs check` passed
  (`docs check: ok`).
- `docker compose run --rm jitml cabal run jitml -- check-code` passed
  (`check-code: ok`).
- Rule-M deterministic scans over `DEVELOPMENT_PLAN/phase-*.md` report:
  **0** backward `Blocked by` edges, **0** dual-accelerator validation gates,
  and **0** accelerator reruns in aggregation-phase validation.
- `docker compose run --rm jitml cabal test jitml-daemon-lifecycle --test-show-details=direct`
  passed **32 / 32** after the synthetic daemon inference fixture gained a
  completed-training manifest.
- `docker compose run --rm jitml jitml test all --live --linux-cpu` passed the
  aggregate lane with **8 / 8** stanzas green, including `jitml-integration`
  **72 / 72**, `jitml-e2e` **23 / 23**, `jitml-daemon-lifecycle` **32 / 32**,
  and `jitml-backends` **23 / 23**.
- Live Playwright passed **15 / 15** against the rebuilt `linux-cpu` edge from a
  temporary repo copy with Playwright pinned to `@playwright/test` `1.49.1`.

### Remaining Work

- None.

## Sprint 12.16: Functional-Core Live Workflow Interpreter [✅ Done]

**Status**: Done (implementation started 2026-07-14; unblocked and validated
2026-07-15 after Sprint `3.7` re-closed)
**Implementation**: `src/JitML/Test/WorkflowMatrix.hs`,
`src/JitML/Test/LivePlan.hs`, `src/JitML/Test/Report.hs`,
`src/JitML/Test/{RunContract,LiveWorkflow,LiveEvidence,PulsarTransport}.hs`,
`test/integration/Main.hs`, `test/e2e/Main.hs`, `src/JitML/App.hs`,
`src/JitML/Service/{Clients,Consumer,HostWorkloadRegistry,RoleLifecycle}.hs`,
`src/JitML/Service/{Runtime,RuntimeState,Workload}.hs`,
`src/JitML/Service/{InferenceBatch,LiveConfig,Logger,Retry}.hs`,
`src/JitML/Test/InferenceBatch.hs`, `src/JitML/Tune/Catalog.hs`,
`src/JitML/Bootstrap.hs`,
`src/JitML/Cluster/{Publication,PulsarBootstrap,Readiness}.hs`,
`src/JitML/Service/ConfigMap.hs`,
`src/JitML/Service/Http.hs`, `jitml.cabal`,
`test/daemon-lifecycle/{Main,SigtermRegression}.hs`,
`web/src/Panels/Stream.{purs,js}`, `playwright/jitml-demo.spec.ts`,
`chart/local/jitml-{service,demo}/templates/*.yaml`
**Docs to update**: `../README.md`,
`../documents/engineering/daemon_architecture.md`,
`../documents/engineering/unit_testing_policy.md`,
`../documents/engineering/pulsar_ml_workflow.md`,
`../documents/engineering/training_workloads.md`,
`../documents/engineering/run_contract.md`, `system-components.md`,
`legacy-tracking-for-deletion.md`

### Objective

Interpret every live workflow that claims protocol completion through one
resource-safe IO shell around the pure contract reducer, and report only the
invocation and evidence states that actually occurred. Public-CLI matrix cells
remain typed executable-outcome coverage when no outer correlated subscription
exists; transport/placement smokes cannot masquerade as completion. This sprint
owns the harness portions of
[Exit Definition](README.md#exit-definition) items `31`, `32`, and `33`.
The binding design is
[README.md → Typed run contracts](../README.md#typed-run-contracts).

### Deliverables

- Add one `runLiveWorkflow` interpreter that subscribes before publication,
  renders commands/topics through typed protocol and topology surfaces, and
  consumes receipt-bound decoded events into the pure reducer.
- Complete the live one-binary role interpreter: Coordinator reconciles the
  exact typed topic family at acquire, gates readiness on that evidence, serves
  without Engine compute subscriptions, owns the cluster-orchestration
  Harbor/kubectl effects currently retained by the Engine compatibility path,
  and drains its scoped loops; Engine and Webapp retain only their disjoint
  compute/browser capabilities.
- Supervise Apple host-resident Training/Tune/RL work under validated keyed
  handles so Stop cancels or drains the matching action exactly once; replace
  the Phase `5` safe Nack with successful terminal evidence only after the real
  handle is observed.
- Add dynamic LiveConfig fields only with their operational consumers:
  structured-log filtering, service retry scheduling, inference batching, and
  latency-SLO enforcement all read the atomic live snapshot and have reload
  behavior tests; no accepted field is inert.
- Require both terminal workload success and complete evidence, accepting either
  arrival order; delete no Job until both conditions are resolved.
- Replace reward lists and boolean tuples with exact key-indexed evidence that
  rejects gaps, conflicting duplicates, wrong `PlanId`, malformed values, and
  missing terminal events.
- Represent placement and job observation as closed sums (`Missing`, `Pending`,
  `Running`, `Succeeded`, `Failed`, `ProbeFailed`) with diagnostics attached.
- Scope owned subscriptions, Jobs and their per-run ConfigMaps, and ephemeral clusters with
  `bracket`/`generalBracket`; gather diagnostics before cleanup and preserve
  cleanup failures without hiding the primary failure.
- Replace hand-rendered topic names, subscription encodings, commands, hashes,
  and per-workflow collectors in `test/integration/Main.hs`.
- Model each test invocation as `Passed`, `Failed`, or `NotRun`, derive suite
  counts from those values, and retain the complete subprocess/scenario journal.

### Current Implementation State

- `runLiveWorkflow` is the single evidence-bearing live IO shell. It acquires
  correlated subscriptions before publication, folds decoded events through
  the pure contract, observes typed placement/Job state, and scopes cleanup and
  diagnostics without allowing transport smokes to mint completion evidence.
  Its journal orders diagnostics before the owned subscription and placement
  releases; independent primary, completion, and cleanup facts survive every
  release outcome.
- Exact supervised, RL, Tune, AlphaZero, GC, and inference adapters are landed;
  the former reward-list/boolean collectors and zero fallback are absent. Job
  observation is a closed diagnostic sum, and terminal success plus complete
  evidence is order-independent.
- The production role boundary is landed but not yet through the full sprint
  gate. `DaemonRuntime` retains a closed role-projected client value: Engine runs
  an opaque MinIO/Pulsar-only interpreter, Coordinator alone retains
  Harbor/kubectl settings and namespace RBAC for per-run ConfigMap/Job
  reconciliation, and Webapp retains no daemon clients, GPU runtime, device
  environment, or Kubernetes API token. The platform readiness
  gate waits for both `deployment/jitml-coordinator` and the Engine
  `deployment/jitml-service` before bootstrap may publish the cluster. The
  existing Engine Deployment selector remains app-only so Helm upgrades do not
  mutate Kubernetes' immutable selector; `jitml.role: engine` remains on the pod
  template for role-indexed diagnostics and policy.
- Engine and Coordinator have bounded five-minute startup probes, so their
  liveness probes cannot restart a healthy process while topic reconciliation,
  persistent consumer connection, and client probes are still completing.
  After applying Gateway and HTTPRoute manifests, bootstrap runs one typed,
  bounded, retrying public `/readyz` request through the Coordinator-only
  Service. Linux publication re-measures both role Deployments; Apple publication
  requires the clustered Coordinator and public edge but deliberately records no
  Engine row because its clustered Engine has zero replicas and the separately
  launched host daemon is not bootstrap evidence. Every substrate requires
  exactly one ready row for its registered components and returns a typed
  invariant failure without writing live evidence when any row is missing,
  duplicated, unexpected, or not ready.
- Apple host Starts are supervised in a keyed process-local registry. Stops
  select exact cancel or natural-drain semantics, join the matching handle, and
  retain the successful receipt for same-`EventId` redelivery when required
  terminal status publication fails. Bounded consume-once joins all registered
  handles and surfaces retained worker failures.
- Structured log filtering, retry scheduling, inference batching/latency SLO,
  dedup resize/TTL, and positive drain-deadline validation consume the atomic
  LiveConfig snapshot. Invocation and scenario journals now derive
  `Passed`/`Failed`/`NotRun`, counts, duration, and failure status from observed
  outcomes rather than declared pass rows. The live e2e scope derives diagnostic
  collection from `generalBracket`'s `ExitCase`, so exceptional, cancelled, and
  aborted exits cannot cross a mutable clean-body flag and skip pre-release
  diagnostics.
- Phase-owned temporary MinIO fixtures and every Linux workload Job/derived
  `runconfig-<jobName>` ConfigMap pair are held by exception-safe scopes.
  Cleanup attempts every resource, retains each typed deletion failure beside
  assertion or workflow failures, and never labels failed cleanup as release.
- Production Linux Training, Tune, and RL Stop programs retain the same paired
  ownership as Start: each emits ordered, indexed deletion effects for the Job
  and its derived `runconfig-<jobName>` ConfigMap. The Workload interpreter
  attempts both effects and preserves each typed outcome; exact CPU/CUDA
  builder and daemon-dispatch regressions pin the resource names and order and
  prove that a typed failure at either deletion does not skip the other.
- The warning-clean combined library/test build passes. Current source pre-gate
  suites are green: `jitml-unit` **544 / 544**,
  `jitml-daemon-lifecycle` **51 / 51**, and `jitml-e2e` **29 / 29**, including
  the actual production-binary threaded-RTS probe, repeated quiet-WebSocket
  handler release, real daemon-process signal/drain cases, role-projection
  regressions, and scoped exceptional-exit diagnostics. `jitml lint
  purescript` also passes the **611**-module frontend compile, **18** specs, and
  tidy check with the cleanup-bearing stream emitter. These checks do not
  replace the repaired-image canonical validation below.
- The first unfiltered non-Live `jitml-integration` pre-gate passed **68 / 123**
  cases and failed **55 / 123**, all in the ProductRow checkpoint matrix: **46**
  retained manifests recorded more units than their now-exact declared budget,
  and **9** retained manifests predated the refined content encoding and no
  longer matched their pointer SHA. That first gate remained failed until the
  artifacts were regenerated through the reconciled real producers; stale or
  over-budget evidence was not accepted as completion. The
  test enumeration at that checkpoint was **124** non-Live plus **20** Live
  cases. Later regressions bring the current enumeration to **125** non-Live
  plus **20** Live; final validation records the reporter's newly observed
  counts rather than reusing either historical value.
- ProductRow budget reconciliation is present for the regeneration: supervised
  rows consume their registered `5`- or `10`-epoch execution schedule, while
  traditional RL rows obtain the aggregate transition count from
  `JitML.RL.ProductBudget`, including vector-environment and indivisible
  rollout/episode granularity. The `sl_epochs=5` and `rl_steps=100_000`
  report-card knobs remain separate canonical-measurement inputs and cannot
  mint ProductRow completion. At that checkpoint the implementation state was
  not validation evidence and the retained artifacts plus unfiltered
  integration gate remained red; the later regeneration evidence below
  supersedes the retained artifacts.
- The internal ProductRow publisher and wall-clock benchmark now share one
  fail-closed filter parser. A mixed valid/invalid request reports every unknown
  row, duplicate identifiers are rejected, and neither internal command begins
  producer work or runtime probes until the complete requested set is valid.
  The focused ProductRow unit scope passes **16 / 16**; live CLI probes reported
  both unknown dotted identifiers and the repeated `PPO/cartpole` identifier
  before any producer row began.
- The first full exact-budget regeneration traversed all **55** rows and
  reported **53** eligible, **0** unsupported, and **2** errors. Every
  supervised, non-TRPO RL, AlphaZero, and tuning row published. The two red rows
  were real deterministic convergence failures: `TRPO/cartpole` produced median
  final reward **126** against its **185** bar at **1,228,800** transitions, and
  `TRPO/lunar-lander` produced **-179.21215200130655** against **155** at
  **2,400,000** transitions. That result did not satisfy the **55 / 55** gate;
  the thresholds and exact budgets remained binding while the real TRPO path
  was corrected and selectively regenerated as recorded below.
- The first independent 55-case artifact slice passed **49 / 55** and failed
  exactly those two TRPO rows plus all four AlphaZero rows. The TRPO rows then
  retained their old local over-budget pointers and had no live object. The new
  AlphaZero pointers were byte-identical locally and live, but their manifests
  were inference-ineligible because checkpoint step recorded sample count while
  `CompletedTraining` recorded generation count: connect4 **2,370 / 64**,
  othello **23,037 / 96**, hex **23,727 / 128**, and gomoku **17,475 / 128**.
  Producer `eligible` status therefore cannot substitute for the checkpoint
  refinement gate.
- The actor-side TRPO audit corrected trust-region contract violations without
  changing either product bar. The current implementation runs exactly one
  natural-gradient actor trust-region step per rollout, followed by
  **10** separate value-head-only critic passes over the configured rollout
  minibatches in both the pure and device paths. Each critic minibatch
  recomputes its gradient at the current critic parameters and threads critic
  Adam at the TRPO-specific **0.001** learning rate. Both counts are independent
  of PPO epochs, and critic gradients plus stale Adam moments cannot change
  actor parameters. The actor line search requires a strict surrogate
  improvement under exact full categorical KL and otherwise rolls back; its
  Fisher-vector product is policy curvature rather than squared
  objective-gradient entries, and the acceptance and actor objectives agree on
  zero TRPO entropy. Malformed configurations, batches, device outputs,
  gradients, and optimizer state fail closed. The current focused TRPO scope
  passes **17 / 17**, the full `jitml-unit` stanza passes **517 / 517**,
  Fourmolu is clean for the changed scope, and focused HLint reports no hints.
  The container `jitml-rl-canonicals` lane with
  `JITML_SUBSTRATE=linux-cpu` passes **40 / 40** in **225.43s**. The exact
  runtime diagnostics and selective regeneration/artifact gates now pass as
  recorded below. Thresholds and exact transition budgets remain intact; the
  unfiltered producer now passes and the full **55 / 55** artifact-refinement
  gate is still required. The first
  pre-multi-pass selective
  runtime attempt on 2026-07-15 traversed both rows but produced **0** eligible,
  **0** unsupported, and **2** errors.
  CartPole failed closed with `TRPO conjugate-gradient curvature is not finite
  and positive`. Lunar Lander completed **2,400,000** transitions and improved
  its median final reward from **-179.21215200130655** to
  **13.372352820002362**, but still failed the unchanged **155** criterion.
  Two further exact-budget controls also stayed red before the multi-pass
  change: increased update density at `max-kl = 0.002` produced
  **-39.564210179995044**, and the denser schedule at `max-kl = 0.01` produced
  **-428.10478983664495**. These diagnostics reject schedule/KL-only
  workarounds; they are not closure evidence for the current implementation.
- On 2026-07-15 the corrected immutable image passed its clean-room build and is
  live as
  `jitml:local@sha256:30eb596380d9e939ae5bd5e0a87757d557576ef7a32614e156953057eba8b813`
  with platform manifest
  `sha256:e37527306af6173e4195a291f4e20b053454b0484de0d47c5ab71268ef6bc0a0`
  and config image ID
  `sha256:560d1b72153a6d8acdf232facc986089c3a0a7f178cfb85627c2e25b34a0253a`.
  Its embedded `jitml check-code` passed, and the frontend compiled **611 /
  611** modules with **0** warnings and **0** errors. `jitml:local` and
  `jitml-demo:local` resolve to that config ID on each of the four retained Kind
  nodes. Sequential rollouts converged for all three application Deployments;
  the three Engines, Coordinator, and Webapp are Ready with zero restarts and
  the same config image ID. Public `/healthz` and `/readyz` pass, the retained
  publication still has exactly nine ready rows, and all four MinIO PVCs retain
  their prior UIDs in `Bound` state. This closes the immutable-image and rollout
  prerequisite without claiming ProductRow convergence.
- The exact no-publish CartPole diagnostic against that corrected runtime
  completed **1,228,800** transitions under the resolved **150 × 512 × 16**
  schedule. All **20** deterministic evaluation episodes reached the **500**
  step limit with reward **500.0**, so the final-tail median **500.0** passes
  the unchanged **185** bar. This is runtime convergence evidence only: it did
  not write a checkpoint or live object and therefore could not itself satisfy
  publication; the subsequent selective publisher evidence follows below. The
  corresponding Lunar Lander diagnostic completed
  **2,400,000** transitions under the resolved **150 × 1,000 × 16** schedule.
  All **20** deterministic evaluation episodes ended after **85** steps with
  reward **271.16021982**, so the final-tail median **271.16021982** passes the
  unchanged **155** bar. It likewise did not publish an artifact.
- The installed immutable publisher then ran the exact two-row filter once and
  reported **2** rows, **2** eligible, **0** unsupported, and **0** errors.
  `TRPO/cartpole` published manifest
  `57b3f858714b8777781720736e43d571adde6ad82932da5b5183d61f78a8c78b`;
  `TRPO/lunar-lander` published
  `0ae8d6a23f15dfcc0ced16ecb4fea27f60dff15f69500ea0e48ee08b86db28e6`.
  The focused artifact-refinement slice then passed **2 / 2**. For both rows,
  the local pointer equals the local manifest content SHA, the live pointer
  equals the live manifest content SHA, and all four values agree. This closes
  the selective artifact/hash gate without substituting it for the unfiltered
  producer traversal.
- The AlphaZero artifact-unit correction is landed in all three production
  writers: Apple host execution, the resolved cluster worker, and ProductRow
  publication now derive checkpoint step from completed self-play generations,
  the same unit carried by `CompletedTraining`; generated sample count remains
  diagnostic evidence only. A focused unit regression with **64** generations
  and **2,370** samples passed. On 2026-07-15 the corrected immutable image
  `sha256:c085148fcaf8c17bba1166ae0c58a175b5d81d03db84ceca6562a32b941dd5c9`
  regenerated connect4, othello, hex, and gomoku with **4** eligible, **0**
  unsupported, and **0** errors. The focused artifact-refinement slice executed
  and passed **4 / 4**. Their new manifest SHAs are respectively
  `53e8390394bd5682d53daf6f45da6d119e9d2beb9cf3e9681f158ac42cd1d1a1`,
  `bfa64783fe610ea56a21a7aa6bf88643f1f167d6c03af80648ef05bc135d0cc1`,
  `3bfd546e9061bdb986114d9cf0ee5c35b9d3643a7ddf95132f7462c912b22587`,
  and `58afa9fd0f3e8ae9e5b45e29cf444dc16fc11a37bed459831b4eef268ac1fa44`;
  each local pointer, live pointer, local manifest hash, and live manifest hash
  agrees. Checkpoint steps and completed self-play generations are exactly
  **64 / 64**, **96 / 96**, **128 / 128**, and **128 / 128**. Their observed
  arena win rates are **0.7777777777777778**, **0.8888888888888888**,
  **0.5555555555555556**, and **0.7777777777777778**, each passing the binding
  `>= 0.4` criterion.
- The installed immutable unfiltered `linux-cpu` producer then exited **0**
  after traversing all **55** ProductRows and reported **55** rows, **55**
  eligible, **0** unsupported, and **0** errors. The traversal reproduced the
  corrected TRPO and AlphaZero manifests alongside every other registered row.
  This closes the producer gate; the independent artifact evidence follows.
- The exact `integration.product` selection then exited **0** and passed
  **55 / 55** in **0.01s**. The independent four-way verifier also exited **0**
  with `canonical_rows=55`, `local_namespaces=55`, `live_namespaces=55`,
  `local_pointers=55`, `live_pointers=55`, `local_manifests=55`,
  `live_manifests=55`, `four_way_matches=55`, `missing=0`, `extra=0`,
  `duplicates=0`, and `mismatches=0`. Every canonical ProductRow therefore has
  one local namespace and one live namespace whose pointer and manifest
  content SHA agree across all four values. This closes the full artifact and
  content-SHA gate independently of producer eligibility.
- The first unfiltered integration rerun exposed a stale live supervised test
  request: **5** epochs × **4,096** training examples with **1,024** evaluation
  examples produced `test_accuracy = 0.8935546875`, below the unchanged
  **0.90** bar. The run correctly could not mint `CompletedTraining` and timed
  out with incomplete evidence. The test request now uses the existing
  registered/ProductRow-publisher MNIST schedule of **10** epochs × **7,000**
  training examples with **1,000** evaluation examples; no convergence bar was
  changed. The focused live `StartTraining` case then exited **0** and passed
  **1 / 1** in **32.54s**, including cleanup.
- The next unfiltered integration pre-gate exited **1** after **140 / 144**
  cases passed in **1,776.55s**. The corrected supervised case passed in
  **31.44s**, and the unchanged real PPO case passed in **725.51s**. The four
  failures were scoped and retained: the WorkflowMatrix inference cell and the
  exact inference workflow timed out without a result; duplicate-Start
  diagnostics selected a still-creating workload pod; and the stale two-trial,
  one-update Tune request produced two objectives of **0.5** and no
  `SweepCompleted`, below the unchanged **1.0** target with **0.05** slack.
- Broker evidence for both inference failures showed three accepted request
  messages, thousands of redeliveries, zero acknowledgements, and no result
  publication. An under-capacity batch waited through its captured **25ms**
  handler/publication-entry deadline, then skipped its handler and Nacked
  forever. The first admission now captures one immutable monotonic
  deadline, and collection closes after the smaller of **1ms** or one tenth of
  the captured latency budget. If no decision has returned by expiry, the
  transport cancels the handler and Nacks every admitted receipt; immediately
  before publication the Engine also refuses to begin a new publish at or after
  that deadline. A decision returned before timeout is settled as returned,
  without retroactive deadline reclassification, because publication may
  already be visible. The shared deadline/policy scope passes **6 / 6** and the
  complete Pulsar transport scope passes **31 / 31**, including single and
  batched cancellation during a slow failing DELETE, typed settlement failure
  during handler/policy cancellation, the under-capacity regression, and the
  real Node batch-drain race. The batch bridge flushes the private Nack for
  every raced receipt before `Drained`, the single bridge rejects unsolicited
  deliveries, and Haskell lint is clean.
- The first exact inference rerun against the rolled-out repair failed **1 / 1**
  after **120.27s**. The reply subscription released correctly, but the exact
  request remained as the sole `jitml-engine` backlog entry and no result topic
  existed. A broker peek tied message `128:2` to call
  `live-inference-call-1784179856971664-1`; through the retained evidence window
  Pulsar emitted exactly **355** negative-ack redeliveries and **355** matching
  cursor rewinds, with no acknowledgement, no unacked delivery, three connected
  Engine consumers, and no worker reconnect or completed outcome log. The new
  one-millisecond cutoff therefore reached the handler, but the inherited
  **25ms** captured handler/publication-entry fence still cancelled the real
  cold MinIO/checkpoint, oneDNN/JIT, and result-publication path. After
  capturing that evidence, only this expired subscription backlog was cleared.
- All three Engines then hot-reloaded a diagnostic **1,000ms** window through
  SIGHUP at generation **1** with zero restarts. The unchanged exact live test
  exited **0** and passed **1 / 1** in **1.17s**. Broker timestamps measured
  approximately **996ms** from request delivery to acknowledgement, and the
  Engine emitted its completed dispatch outcome at roughly **963ms**, so one
  second is not a stable production margin. The operational default and all
  checked-in Engine, Coordinator, and Webapp `LiveConfig` materializations are
  now **5,000ms**. This retains the monotonic handler-completion and
  Engine-publication-entry deadline, one-millisecond sparse-collection cap,
  complete-batch Nack when no decision returns by expiry, and unchanged CLI
  **30s** reply timeout. A returned decision is settled without a retroactive
  Nack, and no broker-ack completion deadline is claimed. It provides room for
  the observed cold path plus the configured exponential retry schedule. The
  focused source gate now passes: `jitml-unit` **535 / 535**, complete
  `jitml-daemon-lifecycle` **50 / 50**, chart/materialization integration **2 /
  2**, container Haskell lint, docs check, and `git diff --check`. The current
  non-Live integration enumeration is **125**; the unfiltered pre-gate remains
  open. All three Engines then hot-reloaded the durable **5,000ms** value at
  generation **2** with zero restarts. Two unchanged unique-checkpoint exact
  live runs exited
  **0**, passing **1 / 1** in **1.20s** and **1 / 1** in **1.14s**. The first
  request was acknowledged in approximately **982ms** and the warm repeat in
  approximately **205ms**; request backlog and unacked counts are both zero,
  the result topic records **2** publications and **2** deliveries, and its
  subscription map is empty after joined cleanup. These hot-reload results
  validate the value and lifecycle, but the final claim still requires the new
  immutable image and the complete focused/canonical rerun against it.
- The timed-out public CLI calls also exposed two stale `jitml-infer-*`
  subscriptions. The caller had delivered cancellation with `killThread` but
  neither joined the consumer nor observed the transport's typed DELETE
  result. It now supervises the worker with `Async`, cancels and joins on every
  primary exit, bounds the uninterruptible owned DELETE, de-duplicates natural
  consumer failure, preserves secondary cleanup failure beside a normal
  primary, and reports it before rethrowing the identical exceptional primary.
  Four bounded lifecycle regressions pass **4 / 4**. The live WorkflowMatrix
  now snapshots the inference-result subscription inventory before and after
  execution and rejects every newly leaked `jitml-infer-*` cursor. Rebuilt live
  proof remains pending.
- Inference reply correlation now requires both the request `callId` and
  experiment hash. A live reply startup, publication, transport, cleanup, or
  timeout failure is reported as `PulsarFailed`, not as evidence that the
  checkpoint is missing. Batched daemon dispatch commits each completed
  command's semantic event ID independently; if a later command is cancelled,
  every earlier commit survives while the interrupted command remains eligible
  for redelivery. This is bounded idempotency on an at-least-once broker, not
  exactly-once delivery. Settlement, drain, child-process, and owned-cleanup
  failures retain their typed identity.
- Duplicate-Start diagnostics now select only daemon pods with the conjunctive
  `app in (jitml-service,jitml-coordinator),jitml.role in
  (engine,coordinator)` selector, excluding workload Jobs that also carry the
  Engine role label without hiding genuine daemon-log failures. Its structural
  regression passes **1 / 1**, the exact live selector exits **0**, and Haskell
  lint is clean. The hot-reloaded full duplicate workflow now passes **1 / 1**
  in **1.37s**; exact post-immutable-rollout repetition remains pending.
- The live Tune completion fixture now derives the registered
  `hyperparameter-tuning` ProductRow and `JitML.Tune.Catalog` schedule rather
  than a test-local miniature: TPE, ASHA, MedianPruner, seed **1729**, **128**
  trials, a **1000**-optimizer-update ceiling allocated through measured
  eta-derived rungs, parallelism **1**, and exactly one promotion.
  The unchanged **1.0** target and **0.05** slack remain binding. Its non-Live
  schedule/convergence regression passes **1 / 1**. The hot-reloaded registered
  live workflow now passes **1 / 1** in **21.10s**; exact post-immutable-rollout
  repetition remains pending.
- The hot-reloaded public WorkflowMatrix passes **1 / 1** in **418.56s**,
  including the formerly timed-out inference cell and the broker-inventory
  assertion that no `jitml-infer-*` cursor leaked. Together with the duplicate,
  Tune, and two inference results above, all four repaired paths are provisionally
  green with no workload Job or `runconfig-*` ConfigMap residue. The new
  immutable image and identical post-rollout selection remain the binding gate.
- The first supported immutable-image build containing all four repairs reached
  `[251 of 261] Compiling JitML.App` and then failed closed before
  `jitml check-code`: GHC 9.12.4 reported `heap overflow` under the binding
  `+RTS -M2G -RTS` compiler limit. The host retained ample memory, so the limit
  was not weakened. The newly added higher-order reply supervisor is now
  isolated in `JitML.Service.InferenceReplyScope`; both exported entrypoints are
  `NOINLINE` so `-fexpose-all-unfoldings` cannot pull that Core back into the
  already-large CLI composition module. The ordinary container build compiles
  both modules, the direct lifecycle scope still passes **4 / 4** in **0.21s**,
  `git diff --check` is clean, and container Haskell lint passes. The supported
  retry then completed all **17 / 17** BuildKit steps in **31m37s**. Both the
  primary CUDA-enabled compile and `check-code`'s `-Werror` compile emitted
  `JitML.App.o` under the unchanged heap cap; embedded `jitml check-code`
  passed; and the frontend compiled **611 / 611** PureScript modules with **0**
  warnings and **0** errors. The resulting immutable image index is
  `sha256:0d86d6dbf1fa1f1133eacb0e9c930a5190d8f1c52bc907f86ca67906c32228d4`
  with linux/amd64 manifest
  `sha256:135a19c752e9ba0bb354804d62c2b68d563296dda91badeb5577caaea8a2563b`.
  Both shared tags were loaded into all four retained Kind nodes and resolve to
  config image
  `sha256:33fe6dd03a7d38b8e6b748bd202e63f2f52ebb10973749d25c143a3fe0b79ce5`.
  Sequential Engine, Coordinator, and Webapp rollouts converged **3 / 3**, **1 /
  1**, and **1 / 1** with zero jitML app restarts. All **16** Deployments and
  **14** StatefulSets have no readiness mismatch; public `/healthz` and
  `/readyz` return HTTP **200**; publication remains exactly **9 / 9**; and all
  **20** PVC names, UIDs, and `Bound` phases exactly match the pre-rollout
  baseline. The three expired inference commands were cleared only from the
  retained `jitml-engine` subscription, which still has three consumers and
  zero backlog. Exactly the two stale zero-consumer `jitml-infer-*` result
  subscriptions were removed. No jitML workload Job or `runconfig-*` ConfigMap
  remains. Rebuilt focused live proof remains required.
- The same audit confirmed a distinct, later-owned evaluation-contract debt:
  current ProductRow traditional-RL training uses one derived seed and its
  deterministic evaluator repeats the same standard-start greedy episode,
  whereas the binding convergence doctrine requires a fixed five-seed cohort.
  This does not authorize a Phase `12` workaround or a weaker bar; Sprint
  `25.4` remains responsible for the typed seed-cohort/evaluation correction.
  Phase `12` closes only when the honest current producer meets its existing
  fixed budget and thresholds with the corrected trust-region implementation.
- The audit also confirmed that `TrainingEvidence.updateCount` still projects
  configured or rollout counts rather than an exact count of applied optimizer
  steps, including accepted versus rolled-back TRPO actor steps. Phase `12`
  does not redefine that evidence field: the singular ProductRow-to-evidence
  projection remains open under Sprint `21.4`, after Sprint `19.4` installs the
  required ProductRow plan projection in the mandated phase order.
- The immutable-ALE replacement image is built and attested as
  `jitml:local@sha256:43d550a4b7d2353e2942e9aadba586413a3387c94f34962e9de7eb0221b9cf45`.
  Its embedded `jitml check-code` gate passed, and the frontend rebuilt all
  **611** PureScript modules with **0** warnings and **0** errors. This closes
  the image prerequisite only; no cluster or ProductRow evidence is inferred
  from a successful image build.
- The supported clean `linux-cpu` bootstrap from that image completed **133**
  rollout steps. Its publication has `evidence: live-readiness`, exactly the
  nine registered ready components, and the canonical loopback Pulsar/MinIO
  URLs; the public `/readyz` body is `ready`. Three zero-restart Engines and one
  zero-restart Coordinator are ready on `linux-cpu`, and the public Service
  selector names only the Coordinator. Harbor jobservice made two immediate
  dependency-startup attempts while `harbor-core` still refused connections,
  then remained ready; the jitML role processes did not restart.
- The fresh `jitml-datasets` bucket was empty by signed S3 inventory. All **12**
  locally pinned canonical files then passed the internal uploader's SHA-256
  check and were written under the exact typed keys: eight MNIST/Fashion-MNIST
  image/label objects plus the CIFAR-10, CIFAR-100, Tiny ImageNet, and California
  Housing archives. A second signed inventory reports all **12** keys.
- A real representative producer selection closed **4 / 4** rows with **4**
  eligible, **0** unsupported, and **0** errors: `mnist-shallow-mlp` processed
  its exact **70,000** example schedule and reached **0.915** test accuracy,
  while `PPO/cartpole`, `DQN/cartpole`, and `HER/goal-reaching` completed their
  exact registered transition schedules and published current artifacts.
- The binding immutable-image focused proof before the final Sprint `3.7`
  rebuild was green: exact inference passed twice in **1.20s** and **1.17s**,
  WorkflowMatrix passed in **432.19s**, duplicate-Start passed in **1.38s**,
  resolved Tune passed in **20.10s**, and Tune persistence/replay passed in
  **0.09s**, with no new reply cursor, workload Job, or `runconfig-*` ConfigMap.
  The final Phase `3` image superseded that image. Current-image preflight then
  exposed Pulsar's valid HTTP `307` owner redirect during owned-subscription
  deletion. Cleanup now follows at most five HTTP(S)-only redirects while
  preserving `DELETE`; the real socket regression and the complete
  `PulsarTransport` group pass **1 / 1** and **32 / 32**.
- On 2026-07-15 the redirect-safe supported build completed with embedded
  `jitml check-code: ok`; the frontend compiled **611 / 611** PureScript
  modules with **0** warnings and **0** errors. The resulting immutable image
  index is
  `sha256:0da77629209333a22f500e54cb2554da7e199b9aec9024b3f7a7384aa35dc361`,
  with linux/amd64 manifest
  `sha256:521674e7a949389752e584dc2656a73b43ecc14cde3fb68240d71d0055254e43`
  and config image ID
  `sha256:f9a63c53fea29cdfa76fce390bf246742a5a9adef2f9f3f1b54b397e117e326c`.
  The supported retained-cluster reconcile, skipping only the duplicate nested
  image build, exited **0** after **156** live rollout steps. Both application
  tags resolve to the same index, manifest, and config on all four Kind nodes;
  the three Engines, Coordinator, and Webapp are Ready with zero restarts and
  that exact config ID. The three Pulsar broker UIDs, zero-restart states, and
  StatefulSet revision are byte-identical to the Phase `3` durable baseline;
  inactive-topic deletion remains disabled in desired and runtime config; all
  **34** exact topic stats calls return objects. Publication remains exactly
  **9 / 9**, `/healthz` and `/readyz` pass on edge `:9091`, the Engine request
  subscription has zero backlog/unacked messages and three consumers, the
  result topic has no subscription, and no workload Job, workload pod, or
  `runconfig-*` ConfigMap remains. The formerly failing live
  `POST /api/checkpoints` now returns HTTP **200** with all **55** ProductRow
  selectors, then removes its owned result subscription without leaking a
  cursor. `git diff --check` is clean.
- The exact current-image focused block then passed: live inference **1 / 1** in
  **1.34s**, public WorkflowMatrix **1 / 1** in **432.83s**, duplicate-Start
  **1 / 1** in **0.34s**, resolved Tune **1 / 1** in **23.19s**, and Tune
  persistence/replay **1 / 1** in **0.09s**. A complete post-focused proof
  retained the same image/index/config tuple on every node, five Ready
  zero-restart application pods, the unchanged three-broker durable baseline,
  **34 / 34** exact topics, zero request backlog/unacked messages with three
  Engine consumers, an empty result subscription map, and no workload Job,
  workload pod, or `runconfig-*` ConfigMap. The unfiltered pre-gate is now the
  next binding command.
- The unfiltered `jitml test jitml-integration --linux-cpu` pre-gate then exited
  **0** and passed **155 / 155** in **1,658.82s**. Its live timings include
  WorkflowMatrix **424.47s**, StartTraining **32.52s**, duplicate-Start
  **0.32s**, StartRLRun **183.56s**, PPO CartPole convergence **737.15s**,
  inference **1.13s**, Tune persistence **0.09s**, resolved Tune **21.06s**,
  and AlphaZero dispatch **4.57s**. The journal-derived stanza report records
  one Passed invocation, zero Failed, and zero NotRun. A complete post-gate
  proof again retained the exact image tuple, five Ready zero-restart app pods,
  unchanged durable broker lineage, **34 / 34** topics, zero cursors/backlog,
  and no workload or ConfigMap residue. The six-command canonical block is now
  the only validation work before ledger and status closure.
- Canonical command **1 / 6**, `jitml test jitml-unit --linux-cpu`, exited **0**
  and passed **544 / 544** in **41.17s**. Its invocation journal records one
  Passed stanza, zero Failed, and zero NotRun; the redirect-following owned
  cleanup regression is included in the complete `PulsarTransport` group. The
  canonical integration rerun is next.
- Canonical command **2 / 6**, `jitml test jitml-integration --linux-cpu`,
  exited **0** and passed **155 / 155** in **1,658.23s**. The second independent
  live run remained stable: WorkflowMatrix **417.47s**, StartTraining
  **32.54s**, StartRLRun **185.64s**, PPO convergence **739.19s**, inference
  **1.13s**, resolved Tune **20.06s**, and AlphaZero dispatch **4.57s**. Its
  post-command cluster proof again records the exact image tuple, five Ready
  zero-restart app pods, unchanged durable brokers, **34 / 34** topics, and
  zero cursor/workload residue. Live e2e is next.
- The first attempt at canonical command **3 / 6**, `jitml test jitml-e2e
  --live --linux-cpu`, exited **0** after **286.10s**: the journal report
  recorded **2** Passed invocations, zero Failed, and zero NotRun; the Haskell
  body passed **28 / 28**; and the browser matrix completed all **71** cases,
  with one case succeeding on retry. That command is not accepted as Sprint
  closure evidence because the mandatory post-command cluster proof found the
  Webapp pod had restarted. Previous-container logs reported file descriptor
  **1032** outside the non-threaded `select()` range; the restarted process then
  retained **182** quiet `jitml-demo-bridge-inference` consumers and **917**
  descriptors before a second `OOMKilled` restart. Pulsar retained **380**
  inactive `jitml-demo-bridge-*` subscriptions. The exact leak was one accepted
  socket, two pipes, and two transcript files per browser bridge: the server
  observed peer loss only during writes, so a quiet handler remained blocked in
  Pulsar consumption after the page closed.
- The repair is implemented but not yet validation evidence. The production
  executable is linked with `-threaded` and the daemon-lifecycle suite now runs
  the actual built binary with `+RTS -N1`. The HTTP listener races every
  server-push handler against a read-side peer-close/EOF watcher, cancels and
  joins the scoped handler before closing the connection, and masks the
  accepted-socket handoff into its fork. A repeated quiet-close regression
  requires every handler finalizer to run and the active count to return to
  zero. On the browser side `Panels.Stream` now constructs a cleanup-bearing
  Halogen emitter; component disposal detaches callbacks and closes its
  WebSocket, with a live hash-navigation Playwright regression. The **380**
  orphaned cursors must be removed explicitly, then a new immutable image must
  be built and rolled out. Because the source/image changed, canonical commands
  **1 / 6** and **2 / 6** above remain diagnostic history and the binding block
  restarts at **1 / 6** on the repaired image.
- The first quiet-WebSocket repair image completed the supported build with
  embedded `jitml check-code: ok`; its frontend compiled **611 / 611** modules
  with zero warnings and zero errors. The immutable index is
  `sha256:5060ce86a25bb1f5869dd366e0960cd16e9f55f2fc4e187c6cd2e462120a418f`,
  with linux/amd64 manifest
  `sha256:15094c97303dba3ebf46788a24c622943b28b06378913ab5700b8781e02dbf82`
  and config image ID
  `sha256:554ecbf9f2ff0f8809441f396c3d91aa65cd679ffd168c46fb62dc5815b1fc45`.
  The installed binary accepted `+RTS -N1`; the supported retained-cluster
  rollout again completed **156** steps. Independent proof recorded the exact
  image tuple, **5 / 5** Ready application pods with zero restarts, three
  brokers, **34 / 34** topics, and zero workload residue. The fresh Webapp pod
  `c51c19bc-889d-44f4-8b68-b6094bd02795` stabilized at **14** PID-1 file
  descriptors with zero direct children, Node processes, piped-process temp
  directories, or `jitml-demo-bridge-*` cursors across all topics. The focused
  hash-navigation browser cleanup regression passed **1 / 1** in **0.077s**
  and the exact resource baseline then held for three consecutive samples.
- On that image canonical command **1 / 6** passed **544 / 544** unit tests in
  **93.715s**, followed by an exact zero-restart/zero-residue cluster proof.
  Canonical command **2 / 6** then ran every integration case for
  **1,698.420s**: **154 / 155** passed, including WorkflowMatrix **443.31s**,
  StartRLRun **200.04s**, PPO convergence **733.96s**, inference **1.13s**,
  resolved Tune **18.03s**, and AlphaZero dispatch **4.59s**. The sole failure
  sampled `jitml-coordinator` on `rl.command.linux-cpu` with `consumers: []`.
  Broker logs prove the healthy three-command consumer set hit the configured
  `webSocketSessionIdleTimeoutMillis=300000` at `20:55:00.887Z`; the failing
  stats response landed at `20:55:01.542Z`, and the bridge resubscribed at
  `20:55:01.896Z` with cursor position unchanged. Coordinator and broker UIDs
  and restart counts remained stable, later daemon dispatches succeeded, and
  the complete failed-run post-state proof again reported the exact image,
  **5 / 5** Ready apps, zero restarts, **34 / 34** topics, and zero residue.
- The role-subscription live gate now polls the entire expected route set as one
  sweep, requires two consecutive all-present sweeps, resets the streak on any
  missing subscription, empty consumer array, command failure, malformed JSON,
  or unexpected shape, and retains the last three complete sweep diagnostics on
  exhaustion. Container Haskell lint passes and the focused live assertion
  passes **1 / 1** in **12.71s**. Because this changes the test source, the
  `5060ce86…` image and its command **1 / 6** result remain diagnostic history;
  the binding image must be rebuilt and the canonical sequence restarted from
  **1 / 6**.
- The final repaired image completed the supported build with embedded
  `jitml check-code: ok`, a **611 / 611** zero-warning PureScript build, and an
  installed binary that accepts `+RTS -N1`. Its immutable index/descriptor is
  `sha256:0c94a15d1c49a6ab13e91133c2e6d16a78029be3c7d873e4397f654260bb1e0d`,
  with linux/amd64 manifest
  `sha256:0b923416bb711b02b32e6cd82f4239d57fe3ba55597db7462b0f088960d5a57e`
  and config image ID
  `sha256:2f43386ea36737c9ed87a29134c1e93e1515b6ae771b302820d0f9d1a0fb7e2b`.
  The supported retained-cluster rollout completed **156** steps. Independent
  proof records that exact tuple on every node, **5 / 5** Ready application
  pods with zero restarts, three unchanged brokers, **34 / 34** topics, and
  zero workload residue. The fresh Webapp pod
  `f89d9fc1-b3be-4e6a-8cff-e23a3befefb4` held **14** PID-1 file descriptors
  with zero direct children, Node processes, piped-process temp directories,
  or `jitml-demo-bridge-*` cursors for three consecutive samples. The focused
  role-subscription gate passed **1 / 1** in **12.77s**, the hash-navigation
  browser cleanup regression passed **1 / 1**, and the exact Webapp resource
  baseline recovered for three further consecutive samples.
- On that binding image, canonical command **1 / 6** passed **544 / 544** unit
  tests in **40.70s** (**1** Passed, zero Failed, zero NotRun), and command
  **2 / 6** passed **155 / 155** integration tests in **1,669.09s** (**1**
  Passed, zero Failed, zero NotRun). Command **3 / 6** passed all **72 / 72**
  Playwright cases and **29 / 29** Haskell e2e cases (**2** Passed, zero
  Failed, zero NotRun). Immediate before/after resource proofs retained the
  same Webapp UID, restart count zero, FD baseline **14**, zero child/Node/temp
  residue, and zero bridge cursors on all **34** topics. The immutable-image
  cluster verifier passed after each command.
- The first binding-image attempt at canonical command **4 / 6**, `jitml test
  all --live --linux-cpu`, is diagnostic history rather than closure evidence.
  The Playwright, unit, integration, supervised-learning canonicals,
  reinforcement-learning canonicals, and hyperparameter stanzas passed, but
  `jitml-backends` failed **1 / 24** at the linux-cpu LayerGraph oneDNN
  training assertion for layer-1 input-gradient tolerance. The fail-fast
  report card therefore recorded **6** Passed invocations, **1** Failed, and
  **4** NotRun. The post-failure immutable-image verifier passed with the exact
  image tuple, **5 / 5** Ready application pods, zero restarts, three unchanged
  brokers, **34 / 34** governed topics, zero workload residue, and a healthy
  edge on port `9091`. The next bullet records the resulting repair; this
  failed aggregate remains diagnostic history.
- Root-cause isolation showed that the oneDNN affine ABI received the raw layer
  input while the pure LayerGraph contract first applies the layer-kind input
  transform. Conv2D is fixture layer index `1`, so its raw `WᵀdPre` first
  exposed the missing backward transform. The oneDNN adapter now applies the
  shared LayerGraph transform before device forward/weight-gradient work and
  maps the device input gradient back through the shared inverse transform.
  The focused assertion passed **1 / 1** three consecutive times, and the full
  linux-cpu backend lane passed **24 / 24** (**1** Passed, zero Failed, zero
  NotRun). Because this is production-source change, image `0c94a15d…` and its
  canonical commands **1 / 6** through **3 / 6** remain diagnostic history. A
  new immutable image, retained-cluster rollout, resource proof, and canonical
  restart from command **1 / 6** are required.
- The post-LayerGraph-fix supported build exited **0** with embedded
  `jitml check-code: ok`, a **611 / 611** PureScript build with zero warnings
  and zero errors, and an installed binary that accepts `+RTS -N1`. The new
  immutable index/descriptor is
  `sha256:6e0d57971bf8e6a7c996530a4b434a575237a570c745710f2a150a501da42aa0`,
  with linux/amd64 manifest
  `sha256:8c3c2bb3319b18e1b927cb5e73c88e8ffc55ff756806d7a8a795844975135899`
  and config image ID
  `sha256:d647ab711f7ff277121ac82390a6b4406cedd93c80422d86b3bf360d9bead432`.
  The supported retained-cluster rollout then exited **0** after **156** steps.
  Independent proof recorded that exact tuple on all four nodes, **5 / 5**
  Ready application pods with zero restarts, three unchanged brokers, **34 /
  34** topics, zero workload residue, and healthy edge `:9091`. New Webapp UID
  `185969ce-92f2-4bed-a61d-6e91ee3129b9` stabilized at **14** PID-1 file
  descriptors with zero children, Node processes, piped-process temp
  directories, or bridge cursors for three consecutive samples. The canonical
  block restarted at command **1 / 6** on this binding image.
- On the post-LayerGraph-fix binding image, canonical command **1 / 6** passed
  **544 / 544** unit tests in **40.62s** (whole invocation
  **92.410180923s**) with a journal summary of **1** Passed, zero Failed, and
  zero NotRun. Canonical command **2 / 6** passed **155 / 155** integration
  tests in **1,660.76s** (whole invocation **1,729.499980288s**) with the same
  **1 / 0 / 0** journal outcome. Its **18 / 18** live cases included the real
  workflow matrix, supervised and reinforcement-learning launches, PPO
  convergence, checkpoint, garbage-collection, inference, tuning, AlphaZero,
  and self-play paths. The independent verifier passed after both commands,
  retaining the exact immutable image tuple, **5 / 5** Ready application pods,
  zero restarts, three brokers, **34 / 34** topics, zero workload residue, and
  the healthy edge on port `9091`.
- Canonical command **3 / 6** on that same binding image passed all **72 / 72**
  Playwright cases in **27.8s** and all **29 / 29** Haskell e2e cases in
  **0.12s**. The journal recorded **2** Passed, zero Failed, and zero NotRun in
  **32.957148353s**, with per-stanza invocations of **29.800086445s** and
  **3.157061908s**. Immediate before/after resource proofs retained Webapp UID
  `185969ce-92f2-4bed-a61d-6e91ee3129b9`, restart count zero, FD baseline
  **14**, and zero child processes, Node processes, piped-process temporary
  directories, or bridge cursors for three consecutive samples. The
  post-command immutable-image verifier again passed the exact image tuple,
  **5 / 5** Ready applications, zero restarts, three brokers, **34 / 34**
  topics, zero workload residue, and healthy edge `:9091`. Canonical command
  **4 / 6** followed on the same retained cluster.
- Canonical command **4 / 6**, `jitml test all --live --linux-cpu`, passed all
  **11 / 11** reporter invocations with **11** Passed, zero Failed, and zero
  NotRun in a whole container invocation of **2,487.430443021s**. Its executed
  cases were Playwright **72 / 72**, unit **544 / 544**, integration **155 /
  155**, supervised-learning canonicals **31 / 31**, reinforcement-learning
  canonicals **40 / 40**, hyperparameter **21 / 21**, backends **24 / 24**,
  daemon lifecycle **51 / 51**, Haskell e2e **29 / 29**, negative controls **3
  / 3**, and model convergence **111 / 111**. The integration journal again
  included all **18 / 18** Live scenarios; in particular, the repaired
  LayerGraph oneDNN case passed inside the full backend stanza rather than only
  in the focused gate. The independent post-aggregate verifier retained the
  exact immutable image tuple, **5 / 5** Ready applications, zero restarts,
  three brokers, **34 / 34** topics, zero workload residue, and healthy edge
  `:9091`. Canonical command **5 / 6**, `jitml docs check`, then exited **0**
  with `docs check: ok`; its independent verifier retained the same exact image
  and healthy zero-residue cluster state. Canonical command **6 / 6**, `jitml
  check-code`, then exited **0** with `check-code: ok`; the final independent
  verifier again retained the exact image tuple, **5 / 5** Ready applications,
  zero restarts, three brokers, **34 / 34** topics, zero workload residue, and
  healthy edge `:9091`. The complete six-command binding-image gate is green.
- Closure alignment moved exactly the three Sprint `12.16` rows to Completed,
  leaving **12** later-owned Pending Removal rows, and activated Sprint `19.4`
  in both its phase document and the Haskell status registry. Standards rule M
  then reported **0 / 44** backward edges, **0 / 284** dual-accelerator gates,
  and **0 / 20** accelerator invocations in aggregation validation. The
  post-edit parity gate passed unit **544 / 544** with **1** Passed, zero
  Failed, and zero NotRun in **178.538679068s**; docs and code quality again
  passed, and the verifier retained the same exact zero-residue cluster state.
- Phase `12` requires no Apple hardware under standards rule M. Its keyed
  registry, forwarding shape, and real daemon-process semantics are
  Linux-host-validatable; the real Metal lane and Apple journal/attestation
  refresh remain owned by Sprint `30.4`.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml test jitml-integration --linux-cpu
docker compose run --rm jitml jitml test jitml-e2e --live --linux-cpu
docker compose run --rm jitml jitml test all --live --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Remaining Work

- None.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [development_plan_standards.md](development_plan_standards.md)
- [../README.md](../README.md)
