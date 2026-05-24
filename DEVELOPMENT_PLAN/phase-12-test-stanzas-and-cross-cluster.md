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
> the current Pulumi metadata scaffold at `infra/pulumi/` for the target
> ephemeral-Kind orchestrator, and the cross-substrate parity gate that closes
> the final handoff. Phase 12 owns the
> integration / canonicals / cross-backend / daemon-lifecycle / e2e stanzas
> and the orchestrator. Lint and code-quality targets are owned outside this
> phase and are not Cabal test stanzas.

## Phase Status

🔄 **Active**. After the 2026-05-24 refactor, this phase carries only
its code-surface obligations (eight Cabal test-suite stanzas with
deterministic-stub bodies, real-binary spawn matrix through the typed
`Subprocess` boundary, report-card knob parsing, plan/apply rendering
for `jitml test all`). Live execution of the `jitml-e2e` Pulumi
orchestrator + Helm rollout + Playwright on the edge route migrated to
[phase-13-linux-cuda-and-cluster-closure.md](phase-13-linux-cuda-and-cluster-closure.md)
Sprints `13.1` and `13.14`. Cross-substrate cohort fixtures + ULP
tolerance + populated live report card migrated to
[phase-15-cross-substrate-and-handoff.md](phase-15-cross-substrate-and-handoff.md)
Sprints `15.1` and `15.2`.

The phase owns
[Exit Definition](README.md#exit-definition) item 9 (`jitml test all`
runs every test-only Cabal test-suite stanza with the report-card knobs pinned in
`cabal.project`; the `jitml-e2e` stanza orchestrates an ephemeral Kind
stack via the `infra/pulumi/` TypeScript program) and item 18 (empty
legacy ledger after the open Exit-Definition items, including item `15`, close).
**Met today**: Sprint `12.1`
(`jitml-unit` body) and Sprint `12.7` (`jitml-daemon-lifecycle` body)
close their owned obligations because their entire body is pure-logic /
parser / property / golden / lifecycle / signal coverage.
The 2026-05-19 container validation also proves `jitml test all --dry-run`
renders the aggregate Plan/Apply surface and non-dry-run `jitml test all`
invokes the eight test-only Cabal stanzas inside `jitml:local`, parses the
`cabal.project` report-card knob block, and prints the current target-stanza
report card after Cabal succeeds. `renderReportCardForTargets` renders the
actual Cabal stanza targets that were run instead of fixed placeholder
workload PASS rows.
`infra/pulumi/index.ts` now contains the typed ephemeral-Kind
orchestrator that runs `kind create cluster` → `helm dependency
build` → `jitml bootstrap --<substrate>` → publication-check, with
the symmetric `kind delete cluster` rollback on destroy.
`JitML.Test.LivePlan.livePhasedClusterPlan` enumerates the typed
phased Helm rollout per substrate so the e2e body can verify the
ordering before invoking the live path. 2026-05-21 local validation re-ran
`jitml test all --dry-run` and non-dry-run `jitml test all`; all eight test
stanzas passed and the report card rendered `passed: 8`, `failed: 0`.
**Unmet today**: Sprint
`12.2` still owes live checkpoint/Pulsar/cluster capability effects and
real per-substrate determinism; its real-binary spawn matrix, live routed
MinIO conditional-write validation, and Dhall
numerics decode coverage are in place. Sprints `12.3`–`12.6`
owe live SL convergence, live RL trajectory, live hyperparameter
reproducibility, and live cross-substrate parity against committed
fixtures; Sprint `12.8` owes the explicit live Pulumi + Helm + Playwright
path actually executed against a real Kind cluster;
Sprint `12.9` owes the report card consuming live results from Sprint
`12.8`. Detailed remaining work lives in each sprint's
`### Remaining Work` block below.

### Current Implementation Scope

All eight Cabal test stanzas are declared and each has a deterministic
`tasty` body. These tests exercise parser/docs/cache/bootstrap helpers,
renderers, catalogs, checkpoint summaries, route/bucket registries,
daemon lifecycle data, and frontend contract scaffolds. The
`jitml-cross-backend` body also compiles, loads, and runs the generated
Linux CPU oneDNN primitive kernels through
`dlopen` and checks the exported family and output-count symbols; the `jitml-e2e` body
verifies the typed live Helm/Pulumi/Playwright plan and the deterministic
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
all` Plan/Apply report-card surface and the Pulumi TypeScript metadata scaffold
at `infra/pulumi/`; the live ephemeral-Kind orchestration remains target e2e
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
runtime-source, and cache surfaces. Broader per-domain golden suites remain
target work.

### Deliverables

- `test/unit/Main.hs` runs the current `tasty` tree.
- The current body covers command registry/parser/help/json, generated-doc
  checks, env resolution, plan rendering, subprocess rendering and fixture
  execution, prerequisite topology/remediation, bootstrap script diagnostics,
  cache-key/layout/manifest/symlink behavior, runtime-source determinism, and
  AppError rendering.
- Current golden fixtures exist under `test/golden/cache/`,
  `test/golden/cli/`, and `test/golden/prerequisite/`.
- Route-table, Grafana daemon-health, Sobol, GA, PPO/CartPole trajectory,
  and AlphaZero Connect 4 / Othello / Hex / Gomoku transcript golden fixtures
  are present under
  `test/golden/`. Richer transcript codecs and AlphaZero MCTS golden
  fixtures grow alongside Sprints `9.5` / `9.6` / `10.x` real bodies. The
  numerical and RL Dhall catalog mirrors are audited by the unit/lint
  body.

### Validation

1. `cabal test jitml-unit` exits `0` for the body.
2. Existing golden fixtures are deterministic and contain no timestamps or
   random identifiers.

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
  `test/golden/cluster/route-table.md`.
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

## Sprint 12.3: `jitml-sl-canonicals` Stanza 🔄

**Status**: Active
**Owned obligations after refactor**: code-surface only. Live `jitml
train` against canonical SL cells with real MinIO datasets and live
measured convergence fixtures migrated to Phase `13` Sprint `13.4`. The
`sl_epochs` / `sl_batch` report-card knob consumption remains a
code-only deliverable here.
**Implementation**: `test/sl-canonicals/`,
`jitml.cabal` (the `jitml-sl-canonicals` stanza)
**Docs to update**: `documents/engineering/unit_testing_policy.md`,
`documents/engineering/training_workloads.md`

### Objective

Use `jitml-sl-canonicals` for the current eleven-cell local supervised-learning
canonical summary workload. Live training thresholds and committed convergence
fixtures remain future runtime work.

### Deliverables

- `test/sl-canonicals/Main.hs` verifies the eleven canonical
  cells from `src/JitML/SL/Canonicals.hs`.
- It asserts convergence curves are deterministic and contain five points.
- It asserts each final synthetic loss is lower than the initial loss.
- It compares every deterministic curve against the committed fixture under
  `test/golden/sl/<problem-key>/curve.txt`.
- It covers `TrainingCommand` text render/parse round-trips plus
  `TrainingCommand` / `TrainingEvent` proto3-compatible byte round-trips.
- It does not run live training or consume `sl_epochs` / `sl_batch` yet.

### Validation

1. `cabal test jitml-sl-canonicals` exits `0` for the body.
2. Live validation (target): the stanza runs real training against every
   canonical SL problem with the `sl_epochs` / `sl_batch` knobs from
   `cabal.project`, asserts the final loss meets the committed
   convergence threshold per problem, and bit-matches committed goldens
   under `test/golden/sl/<problem-key>/`.

### Remaining Work

- Consume the `sl_epochs` / `sl_batch` report-card knobs from
  `cabal.project` in the local convergence assertion. (Code-only.)
- Driving `jitml train` against every canonical SL cell with real
  datasets and supplementing deterministic synthetic fixtures with live
  measured convergence fixtures are owned by
  [phase-13-linux-cuda-and-cluster-closure.md](phase-13-linux-cuda-and-cluster-closure.md)
  Sprint `13.4`.

## Sprint 12.4: `jitml-rl-canonicals` Stanza 🔄

**Status**: Active
**Owned obligations after refactor**: code-surface only. Live `jitml
rl train` against algorithm × environment cohorts with real env
simulators and live measured fixtures migrated to Phase `13` Sprint
`13.6`. The `rl_steps` / `rl_eval_episodes` / `az_games` / `az_sims`
knob consumption remains a code-only deliverable here.
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
- It asserts `deterministicTrajectory` is deterministic for a fixed algorithm
  and seed and matches the current PPO/CartPole golden fixture.
- It asserts `selfPlayTranscript` emits legal Connect 4 columns.
- It compares the local Connect 4, Othello, Hex, and Gomoku transcript
  shapes against `test/golden/alphazero/<game>-transcript.txt`.
- It covers `RlCommand` text render/parse round-trips plus `RlCommand` /
  `RlEvent` proto3-compatible byte round-trips.
- It does not run RL environments, train policies, or consume
  `rl_steps`, `rl_eval_episodes`, `az_games`, or `az_sims` yet.

### Validation

1. `cabal test jitml-rl-canonicals` exits `0` for the body.
2. Live validation (target): the stanza runs real RL training against
   every algorithm × canonical environment cohort with the `rl_steps`,
   `rl_eval_episodes`, `az_games`, `az_sims` knobs from `cabal.project`,
   asserts trajectory determinism (target matrix form 2) and per-seed
   final-reward distribution (form 3) against committed fixtures, and
   bit-matches committed AlphaZero arena summaries.

### Remaining Work

- Consume the `rl_steps` / `rl_eval_episodes` / `az_games` / `az_sims`
  report-card knobs from `cabal.project`. (Code-only.)
- Commit deterministic-stub per-cohort goldens under
  `test/golden/rl/<algo>/<env>/`. (Code-only; live measured goldens
  replace these once Phase `13` Sprint `13.6` produces them.)
- Driving `jitml rl train` against every cohort with real env
  simulators, measured AlphaZero arena fixtures, and the per-seed
  final-reward distribution assertion are owned by
  [phase-13-linux-cuda-and-cluster-closure.md](phase-13-linux-cuda-and-cluster-closure.md)
  Sprint `13.6`.

## Sprint 12.5: `jitml-hyperparameter` Stanza 🔄

**Status**: Active
**Owned obligations after refactor**: code-surface only. Live `jitml
tune` against the full canonical sampler × scheduler × pruner grid
through the live tuner and resume-from-partial-sweep equality test
migrated to Phase `13` Sprint `13.10`. The per-sampler / per-scheduler /
per-pruner reproducibility assertion against committed deterministic
golden trial-key streams remains a code-only deliverable here.
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
- It asserts `deterministicTrials sampler 8` is stable for every current
  sampler.
- It asserts generated trial values are normalized into `[0, 1)`.
- It compares Sobol and GeneticAlgorithm trial streams against the current
  fixtures under `test/golden/tune/`.
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

- Assert per-sampler / per-scheduler / per-pruner reproducibility against
  committed deterministic golden trial-key streams under
  `test/golden/tune/`. (Code-only.)
- Driving `jitml tune` against the full canonical sampler × scheduler ×
  pruner grid through the live tuner, extending knob consumption to the
  full grid, and the resume-from-partial-sweep equality test against
  live MinIO are owned by
  [phase-13-linux-cuda-and-cluster-closure.md](phase-13-linux-cuda-and-cluster-closure.md)
  Sprint `13.10`.

## Sprint 12.6: `jitml-cross-backend` Stanza ✅

**Status**: Done
**Owned obligations after refactor**: code-surface only. Cross-substrate
cohort runs, per-cohort tolerance fixtures, and per-tensor drift
assertion migrated to Phase `15` Sprint `15.1`.
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
- It does not train SL canon cohorts or read `test/golden/cross-backend/`
  tolerance fixtures yet.

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
   substrate pairs, asserts per-tensor drift fits the committed
   tolerance band per
   [../documents/engineering/determinism_contract.md](../documents/engineering/determinism_contract.md),
   and bit-matches committed cross-substrate fixtures.

### Remaining Work

- No sprint-owned code-surface Remaining Work remains. The
  cross-substrate cohort runs, per-cohort tolerance fixtures, and the
  per-tensor drift assertion against the committed ULP tolerance band
  are owned by
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

## Sprint 12.8: `jitml-e2e` Stanza and Pulumi Orchestrator ✅

**Status**: Done
**Owned obligations after refactor**: code-surface only. Live phased
Helm + Pulsar rollout against a real Kind cluster, live Playwright
against the edge route, and full live teardown leak-detection migrated
to Phase `13` Sprints `13.1` and `13.14`.
**Implementation**: `infra/pulumi/`,
`infra/pulumi/package.json`, `infra/pulumi/Pulumi.yaml`,
`infra/pulumi/index.ts`,
`src/JitML/Test/LivePlan.hs`,
`test/e2e/`,
`jitml.cabal` (the `jitml-e2e` stanza)
**Docs to update**: `documents/engineering/unit_testing_policy.md`

### Objective

Use `jitml-e2e` for the e2e scaffold and target Pulumi/
Playwright stack. The current body checks route, bucket, publication, contract,
report-card, and typed live-plan surfaces; the future body brings up an
ephemeral Kind stack, runs the demo cohorts against the real Envoy listener with
Playwright, and tears the stack down deterministically.
This is the doctrine's Pulumi-Orchestrated Infrastructure test category.
The live body is an explicit opt-in gate, not part of default `cabal test all`,
because it creates Kind clusters, builds Helm dependencies, mutates external
container/runtime state, and validates teardown.

### Deliverables

- `infra/pulumi/index.ts` now declares the typed `kindCluster`,
  `helmDeps`, `jitmlBootstrap`, and `publicationCheck`
  `@pulumi/command` `local.Command` resources, in dependency order;
  destroy reverses the order via the typed `delete` commands. The
  `playwrightCommand` output exposes the typed `npx playwright
  test` invocation with the leased kubeconfig.
- `test/e2e/Main.hs` currently validates the route registry, bucket registry,
  `chart/values.yaml` MinIO bucket coverage, publication defaults, browser
  contract endpoint count, demo deployment command, demo HTTP route table
  coverage for generated stream endpoints, one-shot demo HTTP server,
  report-card rendering, typed report-card defaults, typed live plan rendering,
  and, when the `kind` binary and `/var/run/docker.sock` are both available,
  the absence of leaked `jitml-e2e-*` Kind clusters. When `kind` or the
  Docker socket is absent, the no-leak query is skipped in the local scaffold
  because live Kind orchestration is an explicit target gate.
- `JitML.Test.LivePlan` sequences `helm dependency build chart`, `pulumi up`,
  `npx playwright test`, `pulumi destroy`, and `pulumi stack rm` through typed
  `Subprocess` values.
- The target Pulumi stack is the only path that touches Pulumi; it is gated by
  the `pulumi` prerequisite node from Sprint `2.2`.
- The target live path runs typed `helm dependency build chart` before apply and
  records whether `Chart.lock` is part of the reproducible dependency surface.
- Default `cabal test jitml-e2e` remains local. The full live path is a separate
  explicit orchestration command, not a process-environment gate.
- Playwright invocation is represented in the typed live plan today; the
  checked-in spec still uses inline DOM stubs. Live edge-route Playwright remains
  target work after the demo panels read fixture-backed or live-backed state.

### Validation

1. `cabal test jitml-e2e` exits `0` for the scaffold body.
2. `cabal test jitml-e2e` verifies the rendered live plan contains the
   Helm dependency-build and Playwright steps.
3. Live validation (target): the explicit live e2e orchestration runs the full
   sequence: `helm dependency build chart`
   → `pulumi up` (ephemeral Kind) → demo cohorts reach Ready behind the
   real Envoy listener → `npx playwright test` against every canonical
   panel → `pulumi destroy` → `pulumi stack rm`. Teardown leaves no
   orphan `jitml-e2e` Kind clusters, Harbor projects, PVs, or Docker
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

## Doctrine Sections Cited

- [../README.md → Test-suite stanzas](../README.md#test-suite-stanzas) (every sprint)
- [../README.md → Standard Testing Stack](../README.md#doctrine-scope) (every sprint)
- [../README.md → Test Categories](../README.md#test-suite-stanzas) (every sprint — eight stanzas cover all seven doctrine categories plus the project-specific Integration extensions)
- [../README.md → Test Organization](../README.md#test-suite-stanzas) (every sprint — `type: exitcode-stdio-1.0`, `tasty` per stanza, no spanning tree; project-specific stanzas under the Integration category)
- [../README.md → Plan / Apply](../README.md#doctrine-scope) (Sprint 12.9)
- [../README.md → Subprocesses as Typed Values](../README.md#doctrine-scope) (every sprint)
- [../README.md → Long-Running Daemons in the Same Binary](../README.md#doctrine-scope) (Sprint 12.7)
- [../README.md → At-Least-Once Event Processing](../README.md#doctrine-scope) (Sprint 12.7)

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/unit_testing_policy.md` — populate the eight-stanza
  surface, the doctrine-category mapping (including the project-specific
  Integration extensions), the
  Pulumi-Orchestrated Infrastructure test pattern, the report-card
  narrative, and the per-stanza notes for canonicals / hyperparameter /
  cross-backend / daemon-lifecycle / e2e.
- `documents/engineering/training_workloads.md` — SL canonicals threshold
  methodology, RL canonicals reward distribution methodology, hyperparameter
  sampler / scheduler / pruner reproducibility expectations.
- `documents/engineering/determinism_contract.md` — cross-substrate
  tolerance methodology including how the per-tensor tolerance bands are
  set and how `jitml-cross-backend` enforces them.
- `documents/engineering/daemon_architecture.md` — daemon lifecycle test
  surface, SIGHUP reload, at-least-once consumer idempotency.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- `system-components.md → Test Stanzas`, `Test Categories Mapping`, and
  `POC Report-Card Knobs` rows remain aligned with the eight Cabal stanzas and
  `src/JitML/Test/Report.hs`.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [development_plan_standards.md](development_plan_standards.md)
- [../README.md](../README.md)
