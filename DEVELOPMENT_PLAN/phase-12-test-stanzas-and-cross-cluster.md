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

✅ **Done** for the local Cabal stanza expansion and report-card surface. The
ten stanzas exercise prior phases' local renderers, catalogs, command summaries,
and scaffolds; live
`jitml-cross-backend` infrastructure validation remains the closure gate that
bounds cross-substrate drift inside the per-tensor tolerance band.

### Current Implementation Scope

The current worktree declares all ten Cabal test stanzas and gives each a local
deterministic `tasty` body. These tests exercise parser/docs/cache/bootstrap
helpers, renderers, catalogs, checkpoint summaries, route/bucket registries,
daemon lifecycle data, and frontend contract scaffolds. They do not currently
spawn the real `jitml` binary for integration, run live training, run
Playwright, or bring up Kind through Pulumi. `jitml test all` invokes Cabal
through the typed `Subprocess` boundary after the Plan/Apply dry-run surface.

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

Keep `jitml-unit` as the current local unit workload covering parser, generated
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
- Route-table, Grafana daemon-health, Sobol, GA, PPO/CartPole trajectory, and
  AlphaZero Connect 4 transcript golden fixtures are present under
  `test/golden/`. Richer transcript codecs and AlphaZero MCTS golden fixtures
  remain target work. The numerical and RL Dhall catalog mirrors are audited by
  the current unit/lint body.

### Validation

1. `cabal test jitml-unit` exits `0` for the current local body.
2. Existing golden fixtures are deterministic and contain no timestamps or
   random identifiers.

## Sprint 12.2: `jitml-integration` Stanza (Subprocess Boundary + Determinism) ✅

**Status**: Done
**Implementation**: `test/integration/`,
`jitml.cabal` (the `jitml-integration` stanza)
**Docs to update**: `documents/engineering/unit_testing_policy.md`

### Objective

Keep `jitml-integration` as the current local integration workload for the
typed subprocess boundary and renderer surfaces. Real-binary subprocess
integration and same-substrate training determinism remain target work.

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

1. `cabal test jitml-integration` exits `0` for the current local body.
2. Live transcript determinism remains target validation.

## Sprint 12.3: `jitml-sl-canonicals` Stanza ✅

**Status**: Done
**Implementation**: `test/sl-canonicals/`,
`jitml.cabal` (the `jitml-sl-canonicals` stanza)
**Docs to update**: `documents/engineering/unit_testing_policy.md`,
`documents/engineering/training_workloads.md`

### Objective

Use `jitml-sl-canonicals` for the current eleven-cell local supervised-learning
canonical summary workload. Live training thresholds and committed convergence
fixtures remain future runtime work.

### Deliverables

- `test/sl-canonicals/Main.hs` verifies the eleven current local canonical
  cells from `src/JitML/SL/Canonicals.hs`.
- It asserts convergence curves are deterministic and contain five points.
- It asserts each final synthetic loss is lower than the initial loss.
- It does not run live training or consume `SL_EPOCHS` / `SL_BATCH` yet.

### Validation

1. `cabal test jitml-sl-canonicals` exits `0` for the current local body.
2. Live convergence fixtures remain target validation.

## Sprint 12.4: `jitml-rl-canonicals` Stanza ✅

**Status**: Done
**Implementation**: `test/rl-canonicals/`,
`jitml.cabal` (the `jitml-rl-canonicals` stanza)
**Docs to update**: `documents/engineering/unit_testing_policy.md`,
`documents/engineering/training_workloads.md`

### Objective

Use `jitml-rl-canonicals` for the current local RL algorithm catalog,
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

1. `cabal test jitml-rl-canonicals` exits `0` for the current local body.
2. Environment trajectory and reward-distribution fixtures remain target
   validation.

## Sprint 12.5: `jitml-hyperparameter` Stanza ✅

**Status**: Done
**Implementation**: `test/hyperparameter/`,
`jitml.cabal` (the `jitml-hyperparameter` stanza)
**Docs to update**: `documents/engineering/unit_testing_policy.md`,
`documents/engineering/training_workloads.md`

### Objective

Use `jitml-hyperparameter` for the current local sampler, scheduler, pruner,
and deterministic trial-value checks.

### Deliverables

- `test/hyperparameter/Main.hs` verifies the current axes are populated:
  four samplers, four schedulers, and three pruners.
- It asserts `deterministicTrials sampler 8` is stable for every current
  sampler.
- It asserts generated trial values are normalized into `[0, 1)`.
- It compares Sobol and GeneticAlgorithm trial streams against the current
  fixtures under `test/golden/tune/`.
- Full sampler set, scheduler/pruner event semantics, and resume equality
  remain target work. Report-card knob parsing is covered through
  `src/JitML/Test/Report.hs` and `jitml-e2e`.

### Validation

1. `cabal test jitml-hyperparameter` exits `0` for the current local body.
2. Resume equality remains target validation.

## Sprint 12.6: `jitml-cross-backend` Stanza ✅

**Status**: Done
**Implementation**: `test/cross-backend/`,
`jitml.cabal` (the `jitml-cross-backend` stanza),
`src/JitML/Test/Report.hs`
**Docs to update**: `documents/engineering/unit_testing_policy.md`,
`documents/engineering/determinism_contract.md`

### Objective

Use `jitml-cross-backend` for the current local engine-flag and checkpoint
inference summary checks. Live cross-substrate tolerance testing remains the
overall handoff gate.

### Deliverables

- `test/cross-backend/Main.hs` verifies every substrate has non-empty
  deterministic engine flags.
- It verifies `inferFromManifest` returns the same deterministic summary for
  each substrate in the local substrate list.
- It does not launch kernels, train SL canon cohorts, or read
  `test/golden/cross-backend/` tolerance fixtures yet.

### Validation

1. `cabal test jitml-cross-backend` exits `0` for the current local body.
2. Live kernel parity and tolerance-band fixture validation remain target work.

## Sprint 12.7: `jitml-daemon-lifecycle` Stanza ✅

**Status**: Done
**Implementation**: `test/daemon-lifecycle/`,
`jitml.cabal` (the `jitml-daemon-lifecycle` stanza)
**Docs to update**: `documents/engineering/unit_testing_policy.md`,
`documents/engineering/daemon_architecture.md`

### Objective

Use `jitml-daemon-lifecycle` for the
doctrine's Daemon
Lifecycle test category through the current local lifecycle and retry surfaces.
The target live test spawns the real `jitml service`, exercises boot → ready →
serve → SIGHUP reload → drain → exit, and asserts at-least-once Pulsar consumer
idempotency.

### Deliverables

- `test/daemon-lifecycle/Main.hs` verifies the current lifecycle phase plan.
- The test exercises endpoint response helpers and retry behaviour against
  synthetic service errors.
- The test exercises the one-shot daemon HTTP listener against `/healthz`.
- Live process spawning, SIGHUP reload, Pulsar idempotency, and SIGTERM drain
  remain target runtime validation.

### Validation

1. `cabal test jitml-daemon-lifecycle` exits `0`.
2. The lifecycle plan remains `load → prereq → acquire → ready → serve →
   drain → exit`.
3. Retry helpers map synthetic service errors to the expected `AppError`.
4. The one-shot daemon HTTP listener returns `200 OK` for `/healthz`.

## Sprint 12.8: `jitml-e2e` Stanza and Pulumi Orchestrator ✅

**Status**: Done
**Implementation**: `infra/pulumi/`,
`infra/pulumi/package.json`, `infra/pulumi/Pulumi.yaml`,
`infra/pulumi/index.ts`,
`test/e2e/`,
`jitml.cabal` (the `jitml-e2e` stanza)
**Docs to update**: `documents/engineering/unit_testing_policy.md`

### Objective

Use `jitml-e2e` for the current local e2e scaffold and target Pulumi/
Playwright stack. The current body checks route, bucket, publication, contract,
and report-card surfaces; the future body brings up an ephemeral Kind stack,
runs the demo cohorts against the real Envoy listener with Playwright, and tears
the stack down deterministically.
This is the doctrine's Pulumi-Orchestrated Infrastructure test category.

### Deliverables

- `infra/pulumi/index.ts` currently exports stack and cluster-name metadata.
- `test/e2e/Main.hs` currently validates the route registry, bucket registry,
  publication defaults, browser contract endpoint count, demo deployment
  command, one-shot demo HTTP server, report-card rendering, and report-card
  knob parsing.
- The target Pulumi stack is the only path that touches Pulumi; it is gated by
  the `pulumi` prerequisite node from Sprint `2.2`.

### Validation

1. `cabal test jitml-e2e` exits `0` for the current local scaffold body.
2. The future live body proves teardown leaves no `jitml-e2e` Kind cluster.

## Sprint 12.9: `jitml test all` Orchestrator and Report Card ✅

**Status**: Done
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
2. `jitml test all` invokes `cabal test all`, exits `0` on the current tree,
   and prints the report card.
3. `cabal test jitml-e2e` verifies report-card knob override parsing.

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
