# Phase 12: Test Stanzas, Lint Matrix, Cross-Cluster Parity

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md),
[development_plan_standards.md](development_plan_standards.md),
[system-components.md](system-components.md),
[phase-0-planning-documentation.md](phase-0-planning-documentation.md),
[phase-1-haskell-cli-surface.md](phase-1-haskell-cli-surface.md),
[phase-11-purescript-frontend-and-demo.md](phase-11-purescript-frontend-and-demo.md),
[../README.md](../README.md)
**Generated sections**: none

> **Purpose**: Fill out the eight Cabal test-suite surface (`jitml-unit`,
> `jitml-integration`, `jitml-sl-canonicals`, `jitml-rl-canonicals`,
> `jitml-hyperparameter`, `jitml-cross-backend`, `jitml-daemon-lifecycle`,
> `jitml-e2e`), the `jitml test all` Plan/Apply orchestrator, the
> report-card knob plumbing,
> the typed `JitML.Test.LivePlan` live-plan surface for the
> ephemeral-Kind e2e orchestration, and the cross-substrate parity gate that
> closes the final handoff. Phase 12 owns the
> integration / canonicals / cross-backend / daemon-lifecycle / e2e stanzas
> and the orchestrator. Lint and code-quality targets are owned outside this
> phase and are not Cabal test stanzas.

## Phase Status

🔄 **Active** (reopened 2026-06-08 for Sprint `12.10`). The reproducibility
contract is clarified to "within a substrate: bit-for-bit reproducible;
across substrates: NO guarantee", so the cross-substrate numeric parity
surface is removed. Sprint `12.10` realigns `jitml-cross-backend` to
within-substrate cases only, relocates the two substrate-agnostic
cross-backend cases into `jitml-unit`, deletes the cross-substrate
tolerance-band test group from `jitml-unit`, removes the report-card
`cross_substrate_parity` field, wires substrate-partitioned `jitml test`
lanes (each substrate's cases run for real in its own
`--test-options='-p <substrate>'` lane; the six pure-logic stanzas run in
every lane; NO skipped tests — a missing toolchain fails by design), and
removes the skip-antipattern guards from the cross-backend / integration
test bodies. ALL linux-cuda within-substrate cases STAY (CUDA is NOT being
removed). The phase stays Active until the Sprint `12.10` test/report code
edits land (separate approved code plan). The historical 2026-05-25 closure
record is preserved below.

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
[phase-13-linux-cuda-and-cluster-closure.md](phase-13-linux-cuda-and-cluster-closure.md)
Sprints `13.1` and `13.14`. Cross-substrate cohort runs against
in-code tolerance bands + populated live report card are owned by
[phase-15-cross-substrate-and-handoff.md](phase-15-cross-substrate-and-handoff.md)
Sprints `15.1` and `15.2`.

The phase owns
[Exit Definition](README.md#exit-definition) item 9 (`jitml test all`
runs every test-only Cabal test-suite stanza with the report-card knobs pinned in
`cabal.project`; the `jitml-e2e` stanza orchestrates an ephemeral Kind
stack via `jitml bootstrap` + the typed `JitML.Test.LivePlan` live plan)
and item 18 (empty
legacy ledger after the open Exit-Definition items, including item `15`, close).
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
bootstrap` → `npx playwright test` → `jitml cluster down`.
`JitML.Test.LivePlan.livePhasedClusterPlan` enumerates the typed
phased Helm rollout per substrate so the e2e body can verify the
ordering before invoking the live path. 2026-05-21 local validation re-ran
`jitml test all --dry-run` and non-dry-run `jitml test all`; all eight test
stanzas passed and the report card rendered `passed: 8`, `failed: 0`.
**Migrated live obligations**: Sprint `12.2`'s live checkpoint /
Pulsar / cluster capability effects and real per-substrate run-to-run
determinism are owned by Phase `13` Sprint `13.7` and Phase `15`
Sprint `15.1`. Sprints `12.3`–`12.6`'s live statistical SL
convergence, live RL trajectory determinism, live hyperparameter
reproducibility, and live cross-substrate parity are owned by
Phase `13` Sprints `13.4` / `13.6` / `13.10` and Phase `15`
Sprint `15.1`. Sprint `12.8`'s live Helm + Playwright path
is owned by Phase `13` Sprints `13.1` / `13.14`. Sprint `12.9`'s live
report-card consumption is owned by Phase `15` Sprint `15.2`. No
code-surface Remaining Work survives in this phase.

### Current Implementation Scope

All eight Cabal test stanzas are declared and each has a deterministic
`tasty` body. These tests exercise parser/docs/cache/bootstrap helpers,
renderers, catalogs, checkpoint summaries, route/bucket registries,
daemon lifecycle data, and frontend contract scaffolds. The
`jitml-cross-backend` body also compiles, loads, and runs the generated
Linux CPU oneDNN primitive kernels through
`dlopen` and checks the exported family and output-count symbols; the `jitml-e2e` body
verifies the typed live Helm/Playwright plan and the deterministic
demo stream routes without executing the live stack. Its local
post-teardown check asserts no `jitml-e2e-*` Kind clusters survive when both
`kind` and `/var/run/docker.sock` are available, and skips only the Docker
query when the container cannot reach the Docker daemon. `jitml test all`
invokes Cabal through the typed `Subprocess` boundary after the Plan/Apply
dry-run surface. Lint and code-quality commands run separately inside
`jitml:local`.
Live execution paths live in the sprints' `### Remaining Work` blocks below.

## Phase Summary

All eight Cabal stanza declarations already exist from Sprint `1.1`. The current
tree uses dedicated local deterministic bodies for every stanza:
`jitml-unit`, `jitml-integration`, `jitml-sl-canonicals`,
`jitml-rl-canonicals`, `jitml-hyperparameter`, `jitml-cross-backend`,
`jitml-daemon-lifecycle`, and `jitml-e2e`. This phase expands the original minimal bodies
with Phase-12-owned workloads per doctrine `Test Organization` (each
`type: exitcode-stdio-1.0` with `tasty` as the in-stanza runner; a single `tasty`
tree spanning all tiers is forbidden). It also lands the current `jitml test
all` Plan/Apply report-card surface and the typed `JitML.Test.LivePlan`
live-plan surface; the live ephemeral-Kind orchestration remains target e2e
work. Current `jitml test all` delegates to Cabal for the eight test-only
stanzas and then renders the target-stanza report-card summary. The eight-stanza coverage
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
prohibition](../README.md#snapshot-targets)) remain target work.

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
checkpoint round-trip migrated to Phase `13` Sprint `13.7`. The
per-substrate determinism assertion against real CUDA and Metal
production kernels migrated to Phase `15` Sprint `15.1`.
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
2. Live validation (target): the stanza spawns the real `jitml` binary
   through the typed `Subprocess` boundary, exercises a real checkpoint
   round-trip via MinIO, validates resume-from-checkpoint semantics, and
   round-trips a Dhall experiment through the typed decoder against the
   actual numerical-core catalog.

### Remaining Work

- No sprint-owned code-surface Remaining Work remains. Real checkpoint
  round-trip against `JitML.Service.MinIOSubprocess` and the live
  `HasMinIO` capability class is owned by
  [phase-13-linux-cuda-and-cluster-closure.md](phase-13-linux-cuda-and-cluster-closure.md)
  Sprint `13.7`. The per-substrate determinism assertion against real
  CUDA and Metal production kernels is owned by
  [phase-15-cross-substrate-and-handoff.md](phase-15-cross-substrate-and-handoff.md)
  Sprint `15.1`.

## Sprint 12.3: `jitml-sl-canonicals` Stanza ✅

**Status**: Done
**Owned obligations after refactor**: code-surface only. The
`sl_epochs` / `sl_batch` report-card knob consumption closed on
2026-05-24 — `test/sl-canonicals/Main.hs` reads the `cabal.project`
report-card knob block via `JitML.Test.Report.loadReportCardKnobs`
and asserts the deterministic curve length is bounded by `sl_epochs`.
Live `jitml train` against canonical SL cells with real MinIO
datasets and live statistical convergence assertions against in-code
literature-target thresholds (no per-substrate fixtures per
[../README.md → Snapshot targets → Numerical-fixture
prohibition](../README.md#snapshot-targets)) migrated to Phase `13`
Sprint `13.4`.
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
2. Live validation (target): the stanza runs real training against every
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
  [phase-13-linux-cuda-and-cluster-closure.md](phase-13-linux-cuda-and-cluster-closure.md)
  Sprint `13.4`.

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
Phase `13` Sprint `13.6`.
**Implementation**: `test/rl-canonicals/`,
`jitml.cabal` (the `jitml-rl-canonicals` stanza)
**Docs to update**: `documents/engineering/unit_testing_policy.md`,
`documents/engineering/training_workloads.md`

### Objective

Use `jitml-rl-canonicals` for the RL algorithm catalog,
deterministic trajectory helper, and Connect 4 transcript checks.

### Deliverables

- `test/rl-canonicals/Main.hs` verifies representative entries in
  `algorithmCatalog`: `PPO`, `SAC`, `HER`, and `AlphaZero`.
- It asserts `deterministicTrajectory` is deterministic for a fixed
  algorithm and seed across two in-process invocations (run-to-run
  equality; no committed PPO/CartPole trajectory fixture per
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
2. Live validation (target): the stanza runs real RL training against
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
  [phase-13-linux-cuda-and-cluster-closure.md](phase-13-linux-cuda-and-cluster-closure.md)
  Sprint `13.6`.

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
live MinIO migrated to Phase `13` Sprint `13.10`.
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
2. Live validation (target): the stanza runs real tuning sweeps with the
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
  [phase-13-linux-cuda-and-cluster-closure.md](phase-13-linux-cuda-and-cluster-closure.md)
  Sprint `13.10`.

## Sprint 12.6: `jitml-cross-backend` Stanza ✅

**Status**: Done
**Owned obligations after refactor**: code-surface only. Cross-substrate
cohort runs and per-tensor drift assertion against the **in-code**
per-layer-family tolerance band at `src/JitML/Engines/Tolerance.hs`
(no per-tensor stored fixtures per
[../README.md → Snapshot targets → Numerical-fixture
prohibition](../README.md#snapshot-targets)) migrated to Phase `15`
Sprint `15.1`.
**Implementation**: `test/cross-backend/`,
`jitml.cabal` (the `jitml-cross-backend` stanza),
`src/JitML/Test/Report.hs`
**Docs to update**: `documents/engineering/unit_testing_policy.md`,
`documents/engineering/determinism_contract.md`

### Objective

Use `jitml-cross-backend` for the engine-flag, checkpoint
inference summary, Linux CPU generated-kernel execution checks, and local Linux
CPU `HasEngine` smoke dispatch. Live
cross-substrate tolerance testing remains the overall handoff gate.

### Deliverables

- `test/cross-backend/Main.hs` verifies every substrate has non-empty
  deterministic engine flags.
- It verifies `inferFromManifest` returns the same deterministic summary for
  each substrate in the local substrate list.
- It compiles generated Linux CPU oneDNN primitive kernels, loads `jitml_kernel` and
  `jitml_kernel_family_name` / `jitml_kernel_output_count` with `dlopen`,
  verifies the reported family and output length, and asserts three successive
  FFI invocations produce bit-identical fixture output.
- It dispatches a generated family kernel through the local Linux CPU
  `HasEngine` interpreter and verifies the loaded family metadata.
- It does not train SL canon cohorts yet (the canon-cohort run lives
  in Phase `15` Sprint `15.1`). The in-code per-layer-family tolerance
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
4. Live validation (target): the stanza runs the canonical SL cohorts
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
  [phase-15-cross-substrate-and-handoff.md](phase-15-cross-substrate-and-handoff.md)
  Sprint `15.1`.

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
- Live Pulsar idempotency remains target runtime validation.

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
to Phase `13` Sprints `13.1` and `13.14`.
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
  (ephemeral Kind + phased Helm rollout) → `npx playwright test` →
  `jitml cluster down` — through typed `Subprocess` values, and
  `livePhasedClusterPlan` records the bootstrap rollout's typed
  subprocess list for the explicit live driver.
- `test/e2e/Main.hs` currently validates the route registry, bucket registry,
  `chart/values.yaml` MinIO bucket coverage, publication defaults, browser
  contract endpoint count, demo deployment command, demo HTTP route table
  coverage for generated stream endpoints, one-shot demo HTTP server,
  report-card rendering, typed report-card defaults, typed live plan rendering,
  and, when the `kind` binary and `/var/run/docker.sock` are both available,
  the absence of leaked `jitml-e2e-*` Kind clusters. When `kind` or the
  Docker socket is absent, the no-leak query is skipped in the local scaffold
  because live Kind orchestration is an explicit target gate.
- The target live path runs typed `helm dependency build chart` before apply and
  records whether `Chart.lock` is part of the reproducible dependency surface.
- Default `cabal test jitml-e2e` remains local. The full live path is a separate
  explicit orchestration command, not a process-environment gate.
- Playwright invocation is represented in the typed live plan and is validated
  live against the demo edge route (Phase `13` Sprint `13.14`, 7/7 panel
  matrix).

### Validation

1. `cabal test jitml-e2e` exits `0` for the scaffold body.
2. `cabal test jitml-e2e` verifies the rendered live plan contains the
   Helm dependency-build and Playwright steps.
3. Live validation (target): the explicit live e2e orchestration runs the full
   sequence: `helm dependency build chart`
   → `jitml bootstrap` (ephemeral Kind) → demo cohorts reach Ready behind the
   real Envoy listener → `npx playwright test` against every canonical
   panel → `jitml cluster down`. Teardown leaves no
   orphan Kind clusters, Harbor projects, PVs, or Docker
   volumes.

### Remaining Work

- No sprint-owned code-surface Remaining Work remains. Live phased Helm
  + Pulsar topic creation rollout against a real Kind cluster is owned
  by
  [phase-13-linux-cuda-and-cluster-closure.md](phase-13-linux-cuda-and-cluster-closure.md)
  Sprint `13.1`; live Playwright against the edge route and full live
  teardown leak-detection are owned by Phase `13` Sprint `13.14`.

## Sprint 12.9: `jitml test all` Orchestrator and Report Card ✅

**Status**: Done
**Owned obligations after refactor**: code-surface only. Live `jitml
test all` mode threading live measurements into the report card and the
live integration test that surfaces real metrics migrated to Phase `15`
Sprint `15.2`.
**Implementation**: `src/JitML/App.hs`,
`src/JitML/Test/Report.hs`,
`cabal.project` (report-card knob block)
**Docs to update**: `documents/engineering/unit_testing_policy.md`

### Objective

Land `jitml test all` (Plan/Apply with `--dry-run` and `--plan-file`) as the
current operator-facing report-card surface, plus the report-card emitter that
prints the tidy summary block answering the canonical questions (SL
convergence, RL reward, AlphaZero arena win rate, JIT cache hit rate, daemon
health, cross-substrate parity tolerance).

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
  `cabal test` with the explicit eight test-only stanza names through
  `JitML.Sub.Stream.runStreaming` and then renders a typed `ReportCard`
  with `ReportCardKnobs` and the actual target stanza list after Cabal
  succeeds.
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
2. `jitml test all` invokes `cabal test` with the explicit eight test-only
   stanza names, exits `0` on the current tree, parses the `cabal.project`
   report-card knob block, and prints the target-stanza report card.
3. `cabal test jitml-e2e` verifies report-card default rendering and that the
   `cabal.project` knob block matches the typed defaults.
4. Live validation (target): the explicit live `jitml test all` path schedules
   the live `jitml-e2e` body too; the rendered report card adds live
   measurements (SL convergence, RL reward, AlphaZero arena win rate,
   JIT cache hit rate, daemon health, cross-substrate parity tolerance)
   on top of the target-stanza summary.

### Remaining Work

- No sprint-owned code-surface Remaining Work remains. The live `jitml
  test all` mode threading live measurements into the report card, the
  population of canonical report-card metrics with real data, and the
  live integration test that confirms the populated report card are
  owned by
  [phase-15-cross-substrate-and-handoff.md](phase-15-cross-substrate-and-handoff.md)
  Sprint `15.2`.

## Sprint 12.10: Substrate-partitioned test lanes; remove the cross-substrate parity test surface [🔄 Active]

**Status**: Active
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

### Validation

Each lane is green with every selected case actually executing (no
skip-sentinels):

1. Apple host (`apple-silicon` lane): `bootstrap/apple-silicon.sh test`.
2. linux-cpu lane:
   `docker compose run --rm jitml jitml test ... -p linux-cpu`.
3. linux-cuda lane:
   `docker compose run --rm jitml-cuda jitml test ... -p linux-cuda -fcuda`.
4. Container code-quality gate: `jitml check-code`.

### Remaining Work

- The test/report code edits above are not yet landed — they are owned by a
  separate approved code plan. Specifically: deleting the `CrossSubstrate
  weighted drift assertions` group and the skip-guard branches from
  `test/cross-backend/Main.hs`; relocating the two substrate-agnostic cases
  into `test/unit/Main.hs` and deleting the cross-substrate tolerance-band
  group there; removing the `cross_substrate_parity` field from
  `ReportMeasurements` and `measureCrossSubstrateParity` (plus its call
  site); removing the oneDNN-availability assertion from the integration
  probe test; and wiring the per-substrate `--test-options='-p <substrate>'`
  lanes. The sprint stays Active until these land and all four validation
  lanes are green.

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

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/unit_testing_policy.md` — populate the eight-stanza
  surface, the doctrine-category mapping (including the project-specific
  Integration extensions), the
  Ephemeral-Cluster Infrastructure test pattern, the report-card
  narrative, and the per-stanza notes for canonicals / hyperparameter /
  cross-backend / daemon-lifecycle / e2e. **Sprint 12.10**: record the
  substrate-partitioned lane model (`--test-options='-p <substrate>'`; six
  pure-logic stanzas in every lane; no skip sentinels — a missing toolchain
  fails by design), the within-substrate-only realignment of
  `jitml-cross-backend`, and the removal of the cross-substrate parity test
  surface and report-card field per the clarified reproducibility contract
  (within a substrate: bit-for-bit; across substrates: no guarantee).
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
  surface, SIGHUP reload, at-least-once consumer idempotency.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- `system-components.md → Test Stanzas`, `Test Categories Mapping`, and
  `POC Report-Card Knobs` rows remain aligned with the eight Cabal stanzas and
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

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [development_plan_standards.md](development_plan_standards.md)
- [../README.md](../README.md)
