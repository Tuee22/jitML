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

> **Purpose**: Stand up the ten Cabal test-suite stanzas (`jitml-unit`,
> `jitml-integration`, `jitml-sl-canonicals`, `jitml-rl-canonicals`,
> `jitml-hyperparameter`, `jitml-cross-backend`, `jitml-daemon-lifecycle`,
> `jitml-e2e`, `jitml-haskell-style`, `jitml-purescript-style`), the
> `jitml test all` Plan/Apply orchestrator, the report-card knob plumbing,
> the Pulumi-orchestrated ephemeral-Kind stack at `infra/pulumi/`, and the
> cross-substrate parity gate that closes the plan. Phase 12 owns the
> integration / canonicals / cross-backend / daemon-lifecycle / e2e stanzas
> and the orchestrator; `jitml-haskell-style` is owned by Sprint `1.4`;
> `jitml-purescript-style` is owned by Sprint `11.3`.

## Phase Status

⏸️ **Blocked** on Phase `11` closure. The ten stanzas exercise every prior
phase's surface end-to-end; `jitml-cross-backend` is the closure gate that
bounds cross-substrate drift inside the per-tensor tolerance band.

## Phase Summary

This phase delivers the Phase-12-owned Cabal test-suite stanzas per doctrine
`Test Organization` (each `type: exitcode-stdio-1.0` with `tasty` as the
in-stanza runner; a single `tasty` tree spanning all tiers is forbidden):
`jitml-unit`, `jitml-integration`, `jitml-sl-canonicals`,
`jitml-rl-canonicals`, `jitml-hyperparameter`, `jitml-cross-backend`,
`jitml-daemon-lifecycle`, and `jitml-e2e`. It also lands `jitml test all` as
the Plan/Apply orchestrator and the Pulumi TypeScript program at
`infra/pulumi/` that brings up an ephemeral Kind stack for `jitml-e2e` (the
doctrine's Pulumi-Orchestrated Infrastructure test category). The two style
stanzas — `jitml-haskell-style` (owned by Sprint `1.4`) and
`jitml-purescript-style` (owned by Sprint `11.3`) — are not landed by Phase
12 but are listed as part of the ten-stanza inventory and consumed by
`jitml test all`. The ten-stanza coverage maps every doctrine test category
to the stanzas per [system-components.md → Test Categories Mapping (Doctrine
→ Stanza)](system-components.md#test-categories-mapping-doctrine--stanza).

## Sprint 12.1: `jitml-unit` Stanza ⏸️

**Status**: Blocked
**Blocked by**: phase-11
**Implementation**: `test/unit/`, `jitml.cabal` (the `jitml-unit` stanza)
**Docs to update**: `documents/engineering/unit_testing_policy.md`

### Objective

Land the `jitml-unit` stanza, exercising the doctrine's Pure Logic, Parser,
Property, and Golden test categories.

### Deliverables

- `test/unit/Main.hs` runs the `tasty` tree.
- Submodules per domain (CLI parser, Subprocess renderer, Plan renderer,
  AppError render, prerequisite-DAG topology, JIT cache key derivation,
  numerical-core round-trips, RL framework primitives, AlphaZero MCTS
  invariants, hyperparameter sampler determinism, checkpoint codec round-
  trips, route registry, Grafana renderer, transcript codecs, RNG mixers).
- Property invariants per doctrine `Test Categories → Property Tests`:
  `decode . encode == id`, `render is deterministic`, `parser roundtrips`.
- Golden tests under `test/golden/` for `CommandSpec` output, route-table
  render, Grafana dashboard JSON, Sobol sequences, GA traces, and the
  per-domain golden fixtures from prior phases.

### Validation

1. `cabal test jitml-unit` exits `0` on a freshly-built tree.
2. Sentinel placeholders for non-deterministic content (timestamps,
   wall-clock readings) are honoured per doctrine `Test Categories →
   Golden Tests`.

## Sprint 12.2: `jitml-integration` Stanza (Subprocess Boundary + Determinism) ⏸️

**Status**: Blocked
**Blocked by**: 12.1, phase-5
**Implementation**: `test/integration/`,
`jitml.cabal` (the `jitml-integration` stanza)
**Docs to update**: `documents/engineering/unit_testing_policy.md`

### Objective

Land the `jitml-integration` stanza covering the doctrine's Integration test
category — real-binary subprocess integration plus same-substrate
determinism. Daemon Lifecycle is owned separately by Sprint `12.7`.

### Deliverables

- `test/integration/Main.hs` runs the `tasty` tree.
- Subprocess integration: exercises the real `jitml` binary across the
  typed `Subprocess` boundary (`runStreaming`, `capture`) against fixture
  inputs; asserts exit codes, stdout schema, stderr structured logging.
- Checkpoint round-trip: split-blob encode/decode + manifest CBOR round-trip
  against the same `.jmw1` wire format the daemon writes.
- Resume semantics: stop a training run mid-epoch, resume from the latest
  pointer, assert the resumed run reaches the same transcript bytes as the
  uninterrupted reference run.
- Dhall→typed-record decode: every governed Dhall surface (`BootConfig`,
  `LiveConfig`, experiment files, sweep files, cluster topology) round-trips
  through `dhall`-driven decoders against committed fixtures.
- Same-experiment determinism: same Dhall + same seed ⇒ identical training
  transcript bytes per the per-substrate bit-equality contract.

### Validation

1. `cabal test jitml-integration` exits `0`.
2. Replaying the same `(experiment-Dhall, seed)` pair through `jitml train`
   twice produces byte-equal transcripts.
3. Mutating any Dhall field by one bit produces a different transcript SHA.

## Sprint 12.3: `jitml-sl-canonicals` Stanza ⏸️

**Status**: Blocked
**Blocked by**: 12.2, phase-8
**Implementation**: `test/sl-canonicals/`,
`jitml.cabal` (the `jitml-sl-canonicals` stanza)
**Docs to update**: `documents/engineering/unit_testing_policy.md`,
`documents/engineering/training_workloads.md`

### Objective

Land the `jitml-sl-canonicals` stanza — project-specific Integration per
doctrine §Test Organization's project-specific stanzas allowance — covering
the eleven canonical SL `(dataset, model)` pairs from [../README.md →
Canonical supervised learning problems](../README.md#canonical-supervised-learning-problems).

### Deliverables

- `test/sl-canonicals/Main.hs` enumerates the eleven canonical SL cells
  (MNIST shallow MLP, MNIST deep CNN, Fashion-MNIST, CIFAR-10 ResNet-20,
  CIFAR-100, Tiny ImageNet ResNet-50, plus the remaining variants enumerated
  in the README canonical list).
- For each `(dataset, model)` cell:
  - Same-substrate determinism: two runs with the same `(seed, knobs)`
    produce byte-equal transcripts.
  - Convergence golden: `median(final_metric) ≥ T` under the `k=5` replicate
    methodology per [../README.md → Threshold
    methodology](../README.md#threshold-methodology); the per-seed
    final-metric distribution is committed as a JSON fixture and regression
    detection is by Kolmogorov–Smirnov shift against the fixture.
- The stanza honours the report-card knobs (`SL_EPOCHS`, `SL_BATCH`).

### Validation

1. `cabal test jitml-sl-canonicals` exits `0` against the report-card knob
   settings.
2. Widening any committed final-metric fixture requires a written cause in
   the PR description; tightening is a free win.

## Sprint 12.4: `jitml-rl-canonicals` Stanza ⏸️

**Status**: Blocked
**Blocked by**: 12.2, phase-9
**Implementation**: `test/rl-canonicals/`,
`jitml.cabal` (the `jitml-rl-canonicals` stanza)
**Docs to update**: `documents/engineering/unit_testing_policy.md`,
`documents/engineering/training_workloads.md`

### Objective

Land the `jitml-rl-canonicals` stanza — project-specific Integration per
doctrine §Test Organization's project-specific stanzas allowance — covering
the RL target matrix forms (2) and (3): same-substrate trajectory
determinism plus per-seed final-reward distribution against committed
fixtures.

### Deliverables

- `test/rl-canonicals/Main.hs` enumerates the canonical RL `(env, algo)`
  cells (stable-baselines3 family: PPO, A2C, TRPO, MaskablePPO, RecurrentPPO,
  DQN, QR-DQN, DDPG, TD3, SAC, CrossQ, TQC, ARS, HER) plus the AlphaZero
  self-play targets on the canonical Connect 4 surface.
- Form (2): fix `(env, algo, seed, policy_init)`, run for a small fixed
  number of steps, SHA-256 the resulting `(obs, action, reward, done)`
  sequence, assert byte equality across runs.
- Form (3): fix `(env, algo, seed_pool of k=5 seeds, hyperparameters)`,
  train each seed to budget, golden assertion `median(final_reward) ≥ T`
  with `T = median(reward) − slack` per the same `k=5` replicate variance
  methodology used for SL; store the full per-seed final-reward distribution
  as a JSON fixture; regression detection by Kolmogorov–Smirnov shift.
- The stanza honours the report-card knobs (`RL_STEPS`, `RL_EVAL_EPISODES`,
  `AZ_GAMES`, `AZ_SIMS`).

### Validation

1. `cabal test jitml-rl-canonicals` exits `0` against the report-card knob
   settings.
2. Trajectory determinism failures point at the precise `(obs, action,
   reward, done)` step that diverged.

## Sprint 12.5: `jitml-hyperparameter` Stanza ⏸️

**Status**: Blocked
**Blocked by**: 12.2, phase-9
**Implementation**: `test/hyperparameter/`,
`jitml.cabal` (the `jitml-hyperparameter` stanza)
**Docs to update**: `documents/engineering/unit_testing_policy.md`,
`documents/engineering/training_workloads.md`

### Objective

Land the `jitml-hyperparameter` stanza — project-specific Integration per
doctrine §Test Organization's project-specific stanzas allowance — covering
per-sampler, per-scheduler, and per-pruner reproducibility plus resume
equality across the hyperparameter tuning surface.

### Deliverables

- Per-sampler reproducibility for: Grid, Random, Sobol, TPE, GP-BO, GA,
  NSGA-II, (μ,λ)-ES, CMA-ES, PBT — fixing `(sampler, seed, search-space)`
  produces a byte-equal trial proposal sequence.
- Per-scheduler reproducibility for: Fifo, SuccessiveHalving, Hyperband,
  ASHA — bracket-scheduling decisions are deterministic given the same
  trial-event stream.
- Per-pruner reproducibility for: none, median, percentile — pruning
  decisions are deterministic given the same trial telemetry.
- Resume-from-partial-sweep equality: stopping after `n < TUNE_TRIALS`
  trials and resuming produces the same final trial transcript as running
  the full sweep uninterrupted.
- The stanza honours the report-card knobs (`TUNE_TRIALS`,
  `TUNE_BUDGET_PER_TRIAL`).

### Validation

1. `cabal test jitml-hyperparameter` exits `0` against the report-card
   knob settings.
2. Trial proposals are byte-equal across resumes for every sampler.

## Sprint 12.6: `jitml-cross-backend` Stanza ⏸️

**Status**: Blocked
**Blocked by**: 12.3, phase-7
**Implementation**: `test/cross-backend/`,
`jitml.cabal` (the `jitml-cross-backend` stanza),
`src/JitML/Test/ParityTolerance.hs`
**Docs to update**: `documents/engineering/unit_testing_policy.md`,
`documents/engineering/determinism_contract.md`

### Objective

Land the `jitml-cross-backend` stanza — project-specific Integration per
doctrine §Test Organization's project-specific stanzas allowance — and the
closure gate for the plan: assert cross-substrate per-tensor drift fits
inside the committed per-tensor tolerance band on the SL canon cohorts
`(cpu, cuda)` and `(cpu, metal)` per
[../documents/engineering/determinism_contract.md](../documents/engineering/determinism_contract.md).

### Deliverables

- `test/cross-backend/Main.hs` enumerates the SL canon cohorts the host
  can exercise (e.g., `linux-cpu` + `linux-cuda` on a CUDA-capable Linux
  host; `apple-silicon` + `linux-cpu` via container on an Apple Silicon
  host with Colima).
- For each `(workload, substrate-pair)` cell:
  - Asserts same-substrate bit-equality across two runs per the per-
    substrate determinism contract.
  - Asserts cross-substrate per-tensor `max-abs(deltaᵢⱼ)` drift fits inside
    the per-tensor tolerance band fixture under
    `test/golden/cross-backend/<pair>/<tensor>.json`; the bands are pinned
    by the `k=5` replicate methodology per
    [../documents/engineering/determinism_contract.md](../documents/engineering/determinism_contract.md).
- The stanza emits a per-cell pass/fail row to stdout that the
  `jitml test all` report card aggregates.

### Validation

1. `cabal test jitml-cross-backend` against an Apple Silicon host
   exercising `apple-silicon` + `linux-cpu` exits `0`; the report card
   reflects the pairwise tolerance results.
2. A synthetic per-tensor drift exceeding the committed band fails the
   stanza with a structured diagnostic naming the offending tensor and
   layer family.
3. Widening any committed band requires a written cause in the PR
   description; tightening is a free win.

## Sprint 12.7: `jitml-daemon-lifecycle` Stanza ⏸️

**Status**: Blocked
**Blocked by**: 12.2, phase-5
**Implementation**: `test/daemon-lifecycle/`,
`jitml.cabal` (the `jitml-daemon-lifecycle` stanza)
**Docs to update**: `documents/engineering/unit_testing_policy.md`,
`documents/engineering/daemon_architecture.md`

### Objective

Land the `jitml-daemon-lifecycle` stanza covering the doctrine's Daemon
Lifecycle test category — spawn the real `jitml service`, exercise the
boot → ready → serve → SIGHUP reload → drain → exit lifecycle, and assert
at-least-once Pulsar consumer idempotency.

### Deliverables

- `test/daemon-lifecycle/Main.hs` spawns the real `jitml service` binary
  against a synthetic `BootConfig` Dhall.
- Drives the daemon through Lifecycle phases (`load → prereq → acquire →
  ready → serve → drain → exit`); polls `/healthz`, `/readyz`, `/metrics`.
- SIGHUP hot reload: mutates a `LiveConfig` field (e.g. `logLevel`),
  signals SIGHUP, asserts the change takes effect without process restart.
- At-least-once Pulsar consumer idempotency: replays the same envelope
  twice, asserts exactly one durable side effect (one MinIO write, one
  checkpoint pointer update).
- SIGTERM graceful drain: asserts the daemon completes in-flight envelopes,
  ACKs them, and exits `0` within the documented drain budget.

### Validation

1. `cabal test jitml-daemon-lifecycle` exits `0`.
2. SIGHUP reload toggles `LiveConfig.logLevel` without restart.
3. Replaying the same `StartTraining` envelope twice produces one durable
   side effect.

## Sprint 12.8: `jitml-e2e` Stanza and Pulumi Orchestrator ⏸️

**Status**: Blocked
**Blocked by**: 12.7, phase-11
**Implementation**: `infra/pulumi/`,
`infra/pulumi/package.json`, `infra/pulumi/Pulumi.yaml`,
`infra/pulumi/index.ts`,
`test/e2e/`,
`jitml.cabal` (the `jitml-e2e` stanza)
**Docs to update**: `documents/engineering/unit_testing_policy.md`

### Objective

Land the `jitml-e2e` stanza and the Pulumi TypeScript program that brings
up an ephemeral Kind stack, runs the six demo cohorts against the real
Envoy listener with Playwright, and tears the stack down deterministically.
This is the doctrine's Pulumi-Orchestrated Infrastructure test category.

### Deliverables

- `infra/pulumi/index.ts` provisions: an ephemeral Kind cluster
  (`XCLUSTER_KIND_NODES` workers per [system-components.md → POC Report-Card
  Knobs](system-components.md#poc-report-card-knobs)), the umbrella Helm
  chart in its `final` phase against a temporary registry image pushed
  during the run, and the `jitml-demo` Deployment.
- `test/e2e/` is a Haskell test driver that:
  1. Invokes `pulumi up` through the typed `Subprocess` boundary.
  2. Runs `jitml train`, `jitml rl train`, `jitml tune` against the
     ephemeral stack to seed the demo state.
  3. Drives the Playwright suite from
     [phase-11-purescript-frontend-and-demo.md → Sprint
     11.6](phase-11-purescript-frontend-and-demo.md) against the live
     bundle across the six demo cohorts (training control, MNIST
     handwriting, image upload, Connect 4 game-play, TensorBoard/Grafana
     navigation, hyperparameter sweep).
  4. Invokes `pulumi destroy` and asserts no orphaned MinIO buckets,
     Harbor projects, PVs, or Docker volumes survive.
- The Pulumi stack is the only path that touches Pulumi; it is gated by
  the `pulumi` prerequisite node from Sprint `2.2`.

### Validation

1. `cabal test jitml-e2e` brings up the ephemeral stack, runs the
   workloads, runs Playwright across the six cohorts, tears down, exits `0`.
2. After teardown, `kind get clusters | grep jitml-e2e` is empty.

## Sprint 12.9: `jitml test all` Orchestrator and Report Card ⏸️

**Status**: Blocked
**Blocked by**: 12.8
**Implementation**: `src/JitML/CLI/Commands/Test.hs`,
`src/JitML/Test/ReportCard.hs`,
`cabal.project` (report-card knob block)
**Docs to update**: `documents/engineering/unit_testing_policy.md`

### Objective

Land `jitml test all` (Plan/Apply with `--dry-run` and `--plan-file`) as the
canonical operator-facing test runner, plus the report-card emitter that
prints the tidy summary block answering the canonical questions (SL
convergence, RL reward, AlphaZero arena win rate, JIT cache hit rate, daemon
health, cross-substrate parity tolerance).

### Deliverables

- `jitml test all` plan steps:
  1. Resolve prerequisites.
  2. Schedule each stanza (`jitml-unit`, `jitml-integration`,
     `jitml-sl-canonicals`, `jitml-rl-canonicals`, `jitml-hyperparameter`,
     `jitml-cross-backend`, `jitml-daemon-lifecycle`, `jitml-e2e`,
     `jitml-haskell-style`, `jitml-purescript-style`) under `cabal test`
     through the typed `Subprocess` boundary.
  3. Aggregate results into the report card.
- The report-card knob block in `cabal.project` carries `SL_EPOCHS`,
  `SL_BATCH`, `RL_STEPS`, `RL_EVAL_EPISODES`, `AZ_GAMES`, `AZ_SIMS`,
  `TUNE_TRIALS`, `TUNE_BUDGET_PER_TRIAL`, `XCLUSTER_KIND_NODES` (see
  [system-components.md → POC Report-Card
  Knobs](system-components.md#poc-report-card-knobs)).
- `ReportCard.hs` renders the tidy summary block on stdout.
- `jitml test <stanza>` runs a single stanza.

### Validation

1. `jitml test all --dry-run` emits the typed plan enumerating all ten
   stanzas.
2. `jitml test all` exits `0` on a fully-implemented tree and prints the
   report card.

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
  `POC Report-Card Knobs` rows move from `⏸️ Blocked` through `🔄 Active`
  to `✅ Done`.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [development_plan_standards.md](development_plan_standards.md)
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
