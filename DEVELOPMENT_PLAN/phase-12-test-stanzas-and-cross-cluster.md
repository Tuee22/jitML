# Phase 12: Test Stanzas, Lint Matrix, Cross-Cluster Parity

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md),
[development_plan_standards.md](development_plan_standards.md),
[system-components.md](system-components.md),
[phase-0-planning-documentation.md](phase-0-planning-documentation.md),
[phase-1-haskell-cli-surface.md](phase-1-haskell-cli-surface.md),
[phase-11-purescript-frontend-and-demo.md](phase-11-purescript-frontend-and-demo.md),
[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
**Generated sections**: none

> **Purpose**: Fill out the ten Cabal test-suite surface (`jitml-unit`,
> `jitml-integration`, `jitml-sl-canonicals`, `jitml-rl-canonicals`,
> `jitml-hyperparameter`, `jitml-cross-backend`, `jitml-daemon-lifecycle`,
> `jitml-e2e`, `jitml-haskell-style`, `jitml-purescript-style`), the
> `jitml test all` Plan/Apply orchestrator, the report-card knob plumbing,
> the current Pulumi metadata scaffold at `infra/pulumi/` for the target
> ephemeral-Kind orchestrator, and the cross-substrate parity gate that closes
> the final handoff. Phase 12 owns the
> integration / canonicals / cross-backend / daemon-lifecycle / e2e stanzas
> and the orchestrator; `jitml-haskell-style` is owned by Sprint `1.4`;
> `jitml-purescript-style` is owned by Sprint `11.3`.

## Phase Status

🔄 **Active**. The phase owns
[Exit Definition](README.md#exit-definition) item 9 (`jitml test all`
runs every Cabal test-suite stanza with the report-card knobs pinned in
`cabal.project`; the `jitml-e2e` stanza orchestrates an ephemeral Kind
stack via the `infra/pulumi/` TypeScript program) and item 18 (empty
legacy ledger after items 1–9 close). **Met today**: Sprint `12.1`
(`jitml-unit` body) and Sprint `12.7` (`jitml-daemon-lifecycle` body)
close their owned obligations because their entire body is pure-logic /
parser / property / golden / lifecycle / signal coverage.
`infra/pulumi/index.ts` now contains the typed ephemeral-Kind
orchestrator that runs `kind create cluster` → `helm dependency
build` → `jitml bootstrap --<substrate>` → publication-check, with
the symmetric `kind delete cluster` rollback on destroy.
`JitML.Test.LivePlan.livePhasedClusterPlan` enumerates the typed
phased Helm rollout per substrate so the e2e body can verify the
ordering before invoking the live path. **Unmet today**: Sprint
`12.2` owes real-binary subprocess integration; Sprints `12.3`–`12.6`
owe live SL convergence, live RL trajectory, live hyperparameter
reproducibility, and live cross-substrate parity against committed
fixtures; Sprint `12.8` owes the live `JITML_LIVE_E2E=1` Pulumi + Helm
+ Playwright path actually executed against a real Kind cluster;
Sprint `12.9` owes the report card consuming live results from Sprint
`12.8`. Detailed remaining work lives in each sprint's
`### Remaining Work` block below.

### Current Implementation Scope

All ten Cabal test stanzas are declared and each has a deterministic
`tasty` body. These tests exercise parser/docs/cache/bootstrap helpers,
renderers, catalogs, checkpoint summaries, route/bucket registries,
daemon lifecycle data, and frontend contract scaffolds. The
`jitml-cross-backend` body also compiles, loads, and runs the generated
Linux CPU identity kernel through `dlopen`; the `jitml-e2e` body
verifies the typed live Helm/Pulumi/Playwright plan without executing
it. `jitml test all` invokes Cabal through the typed `Subprocess`
boundary after the Plan/Apply dry-run surface. Live execution paths live
in the sprints' `### Remaining Work` blocks below.

## Phase Summary

All ten Cabal stanza declarations already exist from Sprint `1.1`. The current
tree uses dedicated local deterministic bodies for every stanza:
`jitml-unit`, `jitml-integration`, `jitml-sl-canonicals`,
`jitml-rl-canonicals`, `jitml-hyperparameter`, `jitml-cross-backend`,
`jitml-daemon-lifecycle`, `jitml-e2e`, `jitml-haskell-style`, and
`jitml-purescript-style`. This phase expands the original minimal bodies
with Phase-12-owned workloads per doctrine `Test Organization` (each
`type: exitcode-stdio-1.0` with `tasty` as the in-stanza runner; a single `tasty`
tree spanning all tiers is forbidden). It also lands the current `jitml test
all` Plan/Apply report-card surface and the Pulumi TypeScript metadata scaffold
at `infra/pulumi/`; the live ephemeral-Kind orchestration remains target e2e
work. The two style stanzas — `jitml-haskell-style` (owned by Sprint `1.4`) and
`jitml-purescript-style` (owned by Sprint `11.3`) — are declared and have local
bodies, but their ownership remains with their source phases. Current
`jitml test all` delegates to Cabal for those stanzas and then renders the
report-card summary. The ten-stanza coverage
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
  and AlphaZero Connect 4 transcript golden fixtures are present under
  `test/golden/`. Richer transcript codecs and AlphaZero MCTS golden
  fixtures grow alongside Sprints `9.5` / `9.6` / `10.x` real bodies. The
  numerical and RL Dhall catalog mirrors are audited by the unit/lint
  body.

### Validation

1. `cabal test jitml-unit` exits `0` for the body.
2. Existing golden fixtures are deterministic and contain no timestamps or
   random identifiers.

## Sprint 12.2: `jitml-integration` Stanza (Subprocess Boundary + Determinism) 🔄

**Status**: Active
**Implementation**: `test/integration/`,
`jitml.cabal` (the `jitml-integration` stanza)
**Docs to update**: `documents/engineering/unit_testing_policy.md`

### Objective

Keep `jitml-integration` as the integration workload for the typed
subprocess boundary and renderer surfaces; grow real-binary subprocess
integration and same-substrate training determinism per `### Remaining
Work` below.

### Deliverables

- `test/integration/Main.hs` runs the current `tasty` tree.
- The current body exercises `runStreaming` against `/bin/echo`.
- It verifies the local bootstrap plan includes the Harbor-first publication
  ordering.
- It verifies Kind config rendering is deterministic and route registry
  rendering covers the registered routes.
- It compares the rendered route table against
  `test/golden/cluster/route-table.md`.
- Real `jitml` binary spawning, checkpoint round-trip, resume semantics, and
  training transcript determinism are not present yet. Current numerical and RL
  Dhall catalog mirrors are decoded and drift-checked by `jitml-unit`.

### Validation

1. `cabal test jitml-integration` exits `0` for the body.
2. Live validation (target): the stanza spawns the real `jitml` binary
   through the typed `Subprocess` boundary, exercises a real checkpoint
   round-trip via MinIO, validates resume-from-checkpoint semantics, and
   round-trips a Dhall experiment through the typed decoder against the
   actual numerical-core catalog.

### Remaining Work

- Add subprocess integration tests that spawn `./.build/jitml` against a
  real workdir and assert end-to-end behaviour for `bootstrap` /
  `cluster up` / `service` / `train --dry-run`.
- Add real checkpoint round-trip coverage against the live `HasMinIO`
  capability class from Sprint `5.4`.
- Add Dhall-to-typed-record decode coverage that exercises the full
  numerical-core catalog from Phase `6`.
- Add the per-substrate determinism assertion against a real generated
  kernel.

## Sprint 12.3: `jitml-sl-canonicals` Stanza 🔄

**Status**: Active
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
- It does not run live training or consume `SL_EPOCHS` / `SL_BATCH` yet.

### Validation

1. `cabal test jitml-sl-canonicals` exits `0` for the body.
2. Live validation (target): the stanza runs real training against every
   canonical SL problem with the `SL_EPOCHS` / `SL_BATCH` knobs from
   `cabal.project`, asserts the final loss meets the committed
   convergence threshold per problem, and bit-matches committed goldens
   under `test/golden/sl/<problem-key>/`.

### Remaining Work

- Drive `jitml train` against every canonical SL cell with real datasets
  fetched from MinIO bucket `jitml-datasets`.
- Consume the `SL_EPOCHS` / `SL_BATCH` report-card knobs from
  `cabal.project`.
- Commit per-problem convergence goldens under `test/golden/sl/`.

## Sprint 12.4: `jitml-rl-canonicals` Stanza 🔄

**Status**: Active
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
- It compares the local Connect 4 transcript shape against
  `test/golden/alphazero/connect4-transcript.txt`.
- It does not run RL environments, train policies, or consume
  `RL_STEPS`, `RL_EVAL_EPISODES`, `AZ_GAMES`, or `AZ_SIMS` yet.

### Validation

1. `cabal test jitml-rl-canonicals` exits `0` for the body.
2. Live validation (target): the stanza runs real RL training against
   every algorithm × canonical environment cohort with the `RL_STEPS`,
   `RL_EVAL_EPISODES`, `AZ_GAMES`, `AZ_SIMS` knobs from `cabal.project`,
   asserts trajectory determinism (target matrix form 2) and per-seed
   final-reward distribution (form 3) against committed fixtures, and
   bit-matches committed AlphaZero arena summaries.

### Remaining Work

- Drive `jitml rl train` against every algorithm × environment cohort
  with real env simulators from Sprint `8.3`.
- Consume the `RL_STEPS` / `RL_EVAL_EPISODES` / `AZ_GAMES` / `AZ_SIMS`
  report-card knobs from `cabal.project`.
- Commit per-cohort goldens (`test/golden/rl/<algo>/<env>/`) and per-game
  AlphaZero arena fixtures.
- Add per-seed final-reward distribution assertion (RL target matrix
  form 3).

## Sprint 12.5: `jitml-hyperparameter` Stanza 🔄

**Status**: Active
**Implementation**: `test/hyperparameter/`,
`jitml.cabal` (the `jitml-hyperparameter` stanza)
**Docs to update**: `documents/engineering/unit_testing_policy.md`,
`documents/engineering/training_workloads.md`

### Objective

Use `jitml-hyperparameter` for the sampler, scheduler, pruner,
and deterministic trial-value checks.

### Deliverables

- `test/hyperparameter/Main.hs` verifies the current axes are populated:
  four samplers, four schedulers, and three pruners.
- It asserts `deterministicTrials sampler 8` is stable for every current
  sampler.
- It asserts generated trial values are normalized into `[0, 1)`.
- It compares Sobol and GeneticAlgorithm trial streams against the current
  fixtures under `test/golden/tune/`.
- Full sampler set, scheduler/pruner event semantics, and resume
  equality are owned by `### Remaining Work` below. Report-card knob
  parsing is covered through `src/JitML/Test/Report.hs` and
  `jitml-e2e`.

### Validation

1. `cabal test jitml-hyperparameter` exits `0` for the body.
2. Live validation (target): the stanza runs real tuning sweeps with the
   `TUNE_TRIALS` / `TUNE_BUDGET_PER_TRIAL` knobs, asserts per-sampler /
   per-scheduler / per-pruner reproducibility, and asserts
   resume-from-partial-sweep equality against trial transcripts persisted
   to MinIO bucket `jitml-trials/`.

### Remaining Work

- Drive `jitml tune` against the full canonical sampler × scheduler ×
  pruner grid through the live tuner from Sprint `9.7`.
- Consume the `TUNE_TRIALS` / `TUNE_BUDGET_PER_TRIAL` report-card knobs.
- Assert per-sampler / per-scheduler / per-pruner reproducibility
  against committed golden trial-key streams.
- Implement resume-from-partial-sweep equality test that reads cached
  trial transcripts from live MinIO.

## Sprint 12.6: `jitml-cross-backend` Stanza 🔄

**Status**: Active
**Implementation**: `test/cross-backend/`,
`jitml.cabal` (the `jitml-cross-backend` stanza),
`src/JitML/Test/Report.hs`
**Docs to update**: `documents/engineering/unit_testing_policy.md`,
`documents/engineering/determinism_contract.md`

### Objective

Use `jitml-cross-backend` for the engine-flag, checkpoint
inference summary, and Linux CPU generated-kernel execution checks. Live
cross-substrate tolerance testing remains the overall handoff gate.

### Deliverables

- `test/cross-backend/Main.hs` verifies every substrate has non-empty
  deterministic engine flags.
- It verifies `inferFromManifest` returns the same deterministic summary for
  each substrate in the local substrate list.
- It compiles the generated Linux CPU identity kernel, loads `jitml_kernel`
  with `dlopen`, and asserts deterministic fixture output.
- It does not train SL canon cohorts or read `test/golden/cross-backend/`
  tolerance fixtures yet.

### Validation

1. `cabal test jitml-cross-backend` exits `0` for the body.
2. `cabal test jitml-cross-backend` validates the generated Linux CPU
   identity kernel compile/load/run path.
3. Live validation (target): the stanza runs the canonical SL cohorts
   on the `(linux-cpu, linux-cuda)` and `(linux-cpu, apple-silicon)`
   substrate pairs, asserts per-tensor drift fits the committed
   tolerance band per
   [../documents/engineering/determinism_contract.md](../documents/engineering/determinism_contract.md),
   and bit-matches committed cross-substrate fixtures.

### Remaining Work

- Drive the cross-substrate cohorts through real per-substrate engines
  from Sprints `7.3` / `7.4` / `7.5`.
- Commit `test/golden/cross-backend/` tolerance fixtures per cohort.
- Add the per-tensor drift assertion against the committed ULP
  tolerance band.

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
- Live Pulsar idempotency remains target runtime validation.

### Validation

1. `cabal test jitml-daemon-lifecycle` exits `0`.
2. The lifecycle plan remains `load → prereq → acquire → ready → serve →
   drain → exit`.
3. Retry helpers map synthetic service errors to the expected `AppError`.
4. The one-shot daemon HTTP listener returns `200 OK` for `/healthz`.

## Sprint 12.8: `jitml-e2e` Stanza and Pulumi Orchestrator 🔄

**Status**: Active
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
  contract endpoint count, demo deployment command, one-shot demo HTTP server,
  report-card rendering, report-card knob parsing, typed live plan rendering,
  and the explicit `JITML_LIVE_E2E` live gate.
- `JitML.Test.LivePlan` sequences `helm dependency build chart`, `pulumi up`,
  `npx playwright test`, `pulumi destroy`, and `pulumi stack rm` through typed
  `Subprocess` values.
- The target Pulumi stack is the only path that touches Pulumi; it is gated by
  the `pulumi` prerequisite node from Sprint `2.2`.
- The target live path runs typed `helm dependency build chart` before apply and
  records whether `Chart.lock` is part of the reproducible dependency surface.
- Default `cabal test jitml-e2e` remains local; the live path is enabled only
  by `JITML_LIVE_E2E=1`.
- Playwright runs only after the demo panels read fixture-backed or live-backed
  state rather than static scaffold output.

### Validation

1. `cabal test jitml-e2e` exits `0` for the scaffold body.
2. `cabal test jitml-e2e` verifies the rendered live plan contains the
   Helm dependency-build and Playwright steps.
3. Live validation (target): under `JITML_LIVE_E2E=1`, `cabal test
   jitml-e2e` runs the full live sequence: `helm dependency build chart`
   → `pulumi up` (ephemeral Kind) → demo cohorts reach Ready behind the
   real Envoy listener → `npx playwright test` against every canonical
   panel → `pulumi destroy` → `pulumi stack rm`. Teardown leaves no
   orphan `jitml-e2e` Kind clusters, Harbor projects, PVs, or Docker
   volumes.

### Remaining Work

- The ephemeral-Kind orchestrator (`infra/pulumi/index.ts`) and the
  typed phased rollout (`JitML.Test.LivePlan.livePhasedClusterPlan`)
  are in place. **Open**: actually executing the typed live plan
  under `JITML_LIVE_E2E=1` from the test body, which requires real
  Docker + Kind on the test host plus enough memory for the heavy
  subcharts (Harbor, Pulsar HA, Postgres, MinIO, Prometheus).
- Add the post-teardown assertion that no `jitml-e2e` Kind cluster,
  Harbor project, MinIO bucket, or Docker volume survives. The
  Pulumi `delete` commands clean up the Kind cluster; the
  post-teardown grep against `docker volume ls`, `kind get clusters`,
  and `mc ls jitml-e2e/` remains to be wired.

## Sprint 12.9: `jitml test all` Orchestrator and Report Card 🔄

**Status**: Active
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
     `jitml-cross-backend`, `jitml-daemon-lifecycle`, `jitml-e2e`,
     `jitml-haskell-style`, `jitml-purescript-style`) under `cabal test`
     through the typed `Subprocess` boundary.
  3. Aggregate results into the report card.
- Current `jitml test all --dry-run` renders the aggregate plan from
  `src/JitML/Plan/Plan.hs`; current non-dry-run `jitml test all` invokes
  `cabal test all` through `JitML.Sub.Stream.runStreaming` and then renders
  a typed `ReportCard` with `ReportCardKnobs` after Cabal succeeds.
- The report-card knob block in `cabal.project` carries `SL_EPOCHS`,
  `SL_BATCH`, `RL_STEPS`, `RL_EVAL_EPISODES`, `AZ_GAMES`, `AZ_SIMS`,
  `TUNE_TRIALS`, `TUNE_BUDGET_PER_TRIAL`, `XCLUSTER_KIND_NODES` (see
  [system-components.md → POC Report-Card
  Knobs](system-components.md#poc-report-card-knobs)).
- `ReportCard.hs` renders the tidy summary block on stdout and consumes
  environment overrides for the report-card knobs.
- `jitml test <stanza>` invokes that single Cabal stanza through the same typed
  `Subprocess` boundary.

### Validation

1. `jitml test all --dry-run` emits the typed plan enumerating all ten
   stanzas.
2. `jitml test all` invokes `cabal test all`, exits `0` on the current
   tree, and prints the report card.
3. `cabal test jitml-e2e` verifies report-card knob override parsing.
4. Live validation (target): under `JITML_LIVE_E2E=1`, `jitml test all`
   schedules the live `jitml-e2e` body too; the rendered report card
   answers every canonical question (SL convergence, RL reward,
   AlphaZero arena win rate, JIT cache hit rate, daemon health,
   cross-substrate parity tolerance) from real measurements rather than
   placeholder summaries.

### Remaining Work

- Drive the live `jitml-e2e` body from `jitml test all` when
  `JITML_LIVE_E2E=1` is set, threading the resulting live measurements
  back into the report card.
- Populate every canonical report-card question with real data once
  Sprints `8.x`, `9.x`, `10.x`, and `12.x` start emitting live results.
- Add the live integration test that confirms the report card
  surfaces real SL/RL/AlphaZero/tuning/cross-substrate numbers and not
  placeholder text.

## Doctrine Sections Cited

- [../HASKELL_CLI_TOOL.md → Testing Doctrine](../HASKELL_CLI_TOOL.md) (every sprint)
- [../HASKELL_CLI_TOOL.md → Standard Testing Stack](../HASKELL_CLI_TOOL.md) (every sprint)
- [../HASKELL_CLI_TOOL.md → Test Categories](../HASKELL_CLI_TOOL.md) (every sprint — ten stanzas cover all seven doctrine categories plus the project-specific Integration / Lint extensions)
- [../HASKELL_CLI_TOOL.md → Test Organization](../HASKELL_CLI_TOOL.md) (every sprint — `type: exitcode-stdio-1.0`, `tasty` per stanza, no spanning tree; project-specific stanzas under §Test Organization → project-specific stanzas)
- [../HASKELL_CLI_TOOL.md → Plan / Apply](../HASKELL_CLI_TOOL.md) (Sprint 12.9)
- [../HASKELL_CLI_TOOL.md → Architecture → Subprocesses as Typed Values](../HASKELL_CLI_TOOL.md) (every sprint)
- [../HASKELL_CLI_TOOL.md → Long-Running Daemons in the Same Binary](../HASKELL_CLI_TOOL.md) (Sprint 12.7)
- [../HASKELL_CLI_TOOL.md → At-Least-Once Event Processing](../HASKELL_CLI_TOOL.md) (Sprint 12.7)

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/unit_testing_policy.md` — populate the ten-stanza
  surface, the doctrine-category mapping (including the project-specific
  Integration extensions and the split style stanzas), the
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
  `POC Report-Card Knobs` rows remain aligned with the ten Cabal stanzas and
  `src/JitML/Test/Report.hs`.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [development_plan_standards.md](development_plan_standards.md)
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
