# Unit Testing Policy

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: README.md, ../documentation_standards.md, ../../DEVELOPMENT_PLAN/phase-0-planning-documentation.md, ../../DEVELOPMENT_PLAN/phase-11-purescript-frontend-and-demo.md, ../../DEVELOPMENT_PLAN/phase-12-test-stanzas-and-cross-cluster.md
**Generated sections**: none

> **Purpose**: Project-specific testing policy for jitML. Defers to the
> doctrine for the per-tier stanza model, the standard testing stack, the
> seven test categories, and the test-organization invariants; names the
> ten jitML stanzas and the doctrine-category mapping.

## Doctrine Deferrals

This doc defers to [../../HASKELL_CLI_TOOL.md](../../HASKELL_CLI_TOOL.md) for:

- **Testing Doctrine** — every behavioural surface gated by a stanza; no
  spanning `tasty` tree.
- **Standard Testing Stack** — Cabal + `exitcode-stdio-1.0` + `tasty` +
  `tasty-hunit` + `tasty-quickcheck` + `tasty-golden` + `typed-process` +
  `temporary` + Pulumi + `fourmolu` + `hlint` + `cabal format`.
- **Test Categories** — Pure Logic, Parser, Property, Golden, Integration,
  Daemon Lifecycle, Pulumi-Orchestrated Infrastructure.
- **Test Organization** — one `test-suite` stanza per tier with `type:
  exitcode-stdio-1.0` and `tasty` as the in-stanza runner; project-specific
  stanzas under §Test Organization → project-specific stanzas.

## jitML Stanzas

The ten Cabal test-suite stanzas declared in `jitml.cabal`:

| Stanza | Tier | Owning Sprint |
|--------|------|---------------|
| `jitml-unit` | Pure Logic + Parser + Property + Golden | Sprint 12.1 |
| `jitml-integration` | Integration | Sprint 12.2 |
| `jitml-sl-canonicals` | Integration (project-specific) | Sprint 12.3 |
| `jitml-rl-canonicals` | Integration (project-specific) | Sprint 12.4 |
| `jitml-hyperparameter` | Integration (project-specific) | Sprint 12.5 |
| `jitml-cross-backend` | Integration (project-specific) | Sprint 12.6 |
| `jitml-daemon-lifecycle` | Daemon Lifecycle | Sprint 12.7 |
| `jitml-e2e` | Pulumi-Orchestrated Infrastructure | Sprint 12.8 |
| `jitml-haskell-style` | Style (§Style as a Cabal test-suite) | Sprint 1.4 |
| `jitml-purescript-style` | Lint (project-specific) | Sprint 11.3 |

Each stanza is `type: exitcode-stdio-1.0` with `tasty` as the in-stanza
runner. A single `tasty` tree spanning all tiers is forbidden per doctrine
`Test Organization`.

## Doctrine Category → Stanza Mapping

| Doctrine Test Category | Owning Stanza |
|------------------------|---------------|
| Pure Logic | `jitml-unit` |
| Parser | `jitml-unit` |
| Property | `jitml-unit` |
| Golden | `jitml-unit` |
| Integration | `jitml-integration`, `jitml-sl-canonicals`, `jitml-rl-canonicals`, `jitml-hyperparameter`, `jitml-cross-backend` |
| Daemon Lifecycle | `jitml-daemon-lifecycle` |
| Pulumi-Orchestrated Infrastructure | `jitml-e2e` |
| Style (§Style as a Cabal test-suite) | `jitml-haskell-style` |
| Lint (project-specific) | `jitml-purescript-style` |

The four `*-canonicals`/HPO/cross-backend rows are **project-specific
Integration** stanzas under doctrine §Test Organization's project-specific
stanzas allowance — extensions of the Integration category, not parallel
test systems. `jitml-purescript-style` is a **project-specific Lint**
stanza under the same allowance.

`jitml test all` (Sprint `12.9`) fans out to every stanza above and
aggregates the report card.

## Project-Specific Stanza Notes

### `jitml-sl-canonicals` — SL canon coverage

Exercises the eleven canonical SL `(dataset, model)` pairs from
[../../README.md → Canonical supervised learning
problems](../../README.md#canonical-supervised-learning-problems). For
each cell:

1. **Same-substrate determinism.** Two runs with the same `(seed, knobs)`
   produce byte-equal training transcripts.
2. **Convergence golden.** `median(final_metric) ≥ T` where `T` is set per
   the `k=5` replicate methodology in [../../README.md → Threshold
   methodology](../../README.md#threshold-methodology); per-seed final-metric
   distributions are committed as JSON fixtures; regression detection by
   Kolmogorov–Smirnov shift.

### `jitml-rl-canonicals` — RL canon coverage

Exercises the stable-baselines3 algorithm family plus AlphaZero self-play
on the canonical Connect 4 surface. Forms (2) and (3) from
[../../README.md](../../README.md):

- **Form (2) trajectory determinism.** Fix `(env, algo, seed, policy_init)`,
  run a small fixed number of steps, SHA-256 the `(obs, action, reward,
  done)` sequence, assert byte equality across runs.
- **Form (3) final-reward distribution.** Fix `(env, algo, seed_pool of k=5,
  hyperparameters)`, train to budget, `median(final_reward) ≥ T`. Stores the
  full per-seed distribution as a JSON fixture; regression detection by
  Kolmogorov–Smirnov.

### `jitml-hyperparameter` — sampler / scheduler / pruner reproducibility

Per-sampler reproducibility for Grid, Random, Sobol, TPE, GP-BO, GA, NSGA-II,
(μ,λ)-ES, CMA-ES, PBT (fixing `(sampler, seed, search-space)` produces a
byte-equal trial proposal sequence); per-scheduler reproducibility for
Fifo, SuccessiveHalving, Hyperband, ASHA; per-pruner reproducibility for
median and percentile; resume-from-partial-sweep equality.

### `jitml-cross-backend` and the Tolerance Band

Cross-substrate cohorts `(cpu, cuda)` and `(cpu, metal)` on the SL canon.
For each `(workload, substrate-pair)` cell:

- Asserts same-substrate bit-equality across two runs (matches the per-
  substrate determinism contract from
  [determinism_contract.md](determinism_contract.md)).
- Asserts cross-substrate per-tensor `max-abs(deltaᵢⱼ)` drift fits inside
  the committed tolerance band at
  `test/golden/cross-backend/<pair>/<tensor>.json`; bands are set per
  layer family in [determinism_contract.md](determinism_contract.md) by the
  `k=5` replicate methodology.

Widening any committed band requires a written cause in the PR
description; tightening is a free win. This stanza is the closure gate for
the development plan.

### `jitml-daemon-lifecycle`

Spawns the real `jitml service` binary against a synthetic `BootConfig`
Dhall, drives it through `load → prereq → acquire → ready → serve → drain →
exit`, polls `/healthz` / `/readyz` / `/metrics`, exercises SIGHUP hot
reload, asserts at-least-once Pulsar consumer idempotency (replaying the
same envelope twice ⇒ one durable side effect), and asserts SIGTERM
graceful drain within the documented budget.

### `jitml-e2e` and Pulumi

The Pulumi TypeScript program at `infra/pulumi/` is the orchestrator for
the ephemeral Kind stack. It is the only path that touches Pulumi. Test
driver:

1. `pulumi up` brings up the stack (Kind cluster, Helm chart in its `final`
   phase against a temporary registry image pushed during the run, plus the
   `jitml-demo` Deployment).
2. The driver runs `jitml train`, `jitml rl run`, `jitml tune` against the
   ephemeral stack to seed the demo state.
3. The driver invokes the Playwright suite from
   [../../DEVELOPMENT_PLAN/phase-11-purescript-frontend-and-demo.md → Sprint
   11.6](../../DEVELOPMENT_PLAN/phase-11-purescript-frontend-and-demo.md)
   against the live bundle across the six demo cohorts (training control,
   MNIST handwriting, image upload, Connect 4 game-play, TensorBoard/Grafana
   navigation, hyperparameter sweep).
4. `pulumi destroy` and a teardown audit (no orphan PVs, MinIO buckets,
   Harbor projects, or Docker volumes survive).

All Pulumi invocations flow through the typed `Subprocess` boundary.

### `jitml-haskell-style`

Doctrine's Style stanza per §Style as a Cabal test-suite: `fourmolu --mode
check`, `hlint --with-group=default --with-group=extra` plus `.hlint.yaml`,
`cabal format` temp-file round-trip byte equality, route-registry / chart
consistency lint, generated-section drift check.

### `jitml-purescript-style`

Project-specific Lint extension under doctrine §Test Organization's
project-specific stanzas allowance: `purs format` round-trip byte equality
across every `web/src/**/*.purs` and `web/test/**/*.purs` file, plus the
`purescript-spec` smoke tests against the generated browser contracts. Both
run through the typed `Subprocess` boundary from the Haskell side.

### Playwright

Playwright belongs to the doctrine's Pulumi-Orchestrated Infrastructure
test category and runs inside `jitml-e2e`, not in its own stanza.

### Property Invariants

Per doctrine `Test Categories → Property Tests`, every codec exposes the
canonical invariants:

- `decode . encode == id`
- `render is deterministic`
- `parser roundtrips`

These hold for the transcript codec, the `.jmw1` checkpoint format, the
manifest CBOR, the route registry, the Grafana dashboard renderer, every
proto schema, the numerical-core ADT round-trips, and the RL framework
primitives.

### Golden Tests and Sentinel Placeholders

Golden fixtures live under `test/golden/`. Non-deterministic content (wall-
clock readings, hostnames, timestamps) is replaced with sentinel placeholders
per doctrine `Test Categories → Golden Tests`.

## Cross-References

- [../../HASKELL_CLI_TOOL.md](../../HASKELL_CLI_TOOL.md)
- [../../DEVELOPMENT_PLAN/phase-12-test-stanzas-and-cross-cluster.md](../../DEVELOPMENT_PLAN/phase-12-test-stanzas-and-cross-cluster.md)
- [determinism_contract.md](determinism_contract.md)
- [../documentation_standards.md](../documentation_standards.md)
