# Unit Testing Policy

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: README.md, ../documentation_standards.md, ../../DEVELOPMENT_PLAN/phase-0-planning-documentation.md, ../../DEVELOPMENT_PLAN/phase-11-purescript-frontend-and-demo.md, ../../DEVELOPMENT_PLAN/phase-12-test-stanzas-and-cross-cluster.md
**Generated sections**: none

> **Purpose**: Project-specific testing policy for jitML. Defers to the
> doctrine for the per-tier stanza model, the standard testing stack, the
> seven test categories, and the test-organization invariants; names the
> eight jitML test stanzas and the doctrine-category mapping.

## Doctrine Deferrals

This doc defers to [../../README.md](../../README.md) for:

- **Testing Doctrine** — every behavioural surface gated by a stanza; no
  spanning `tasty` tree.
- **Standard Testing Stack** — Cabal + `exitcode-stdio-1.0` + `tasty` +
  `tasty-hunit` + `tasty-quickcheck` + `tasty-golden` + `typed-process` +
  `temporary` + Pulumi.
- **Test Categories** — Pure Logic, Parser, Property, Golden, Integration,
  Daemon Lifecycle, Pulumi-Orchestrated Infrastructure.
- **Test Organization** — one `test-suite` stanza per tier with `type:
  exitcode-stdio-1.0` and `tasty` as the in-stanza runner; project-specific
  stanzas under §Test Organization → project-specific stanzas.

## jitML Stanzas

The eight Cabal test-suite stanzas are declared in `jitml.cabal`. Current bodies
exercise the local deterministic contracts for their owning surfaces while live
cluster validation remains phase-gated:

| Stanza | Current body | Final Tier | Owning Sprint |
|--------|--------------|------------|---------------|
| `jitml-unit` | `test/unit/Main.hs` covers current CLI, docs, prerequisite, env, app-error, plan, subprocess, bootstrap-script, cache, hot-reload, capability, RL framework, AlphaZero, tuning resume, checkpoint key/CAS/store, `.jmw1` encode/decode, TensorBoard scalar-event codec / TFRecord writer / sidecar, Grafana fixture, and frontend bundle/panel/demo-route surfaces | Pure Logic + Parser + Property + Golden | Sprint 12.1 |
| `jitml-integration` | `test/integration/Main.hs` covers typed subprocess execution, bootstrap/live-rollout renderers, route-table golden fixture, real-binary spawn matrix, filesystem-backed `HasMinIO` checkpoint / inference / resume coverage, local Linux CPU checkpoint inference through a generated FFI kernel with decoded `.jmw1` weights, routed MinIO/Pulsar subprocess command rendering including the WebSocket subscribe probe, substrate-scoped Pulsar topic bootstrap, BootConfig-derived daemon client settings, single-node Kind rendering, required `jitml-service` anti-affinity plus single-node rollout strategy/RBAC rendering, Dhall numerics decode, and typed service command shapes | Integration | Sprint 12.2 |
| `jitml-sl-canonicals` | `test/sl-canonicals/Main.hs` covers deterministic supervised canonical curves, the committed per-problem fixtures under `test/golden/sl/`, dataset fetch verification, and Training command/event envelope round-trips | Integration (project-specific) | Sprint 12.3 |
| `jitml-rl-canonicals` | `test/rl-canonicals/Main.hs` covers the RL algorithm catalog, deterministic trajectories, PPO/CartPole golden trajectory, AlphaZero transcript fixtures for Connect 4, Othello, Hex, and Gomoku, and RL command/event envelope round-trips | Integration (project-specific) | Sprint 12.4 |
| `jitml-hyperparameter` | `test/hyperparameter/Main.hs` covers sampler / scheduler / pruner axes including TPE, deterministic trial generation, the TPE worked-example Dhall decode, Sobol/GA golden fixtures, and Tune command/event envelope round-trips | Integration (project-specific) | Sprint 12.5 |
| `jitml-cross-backend` | `test/cross-backend/Main.hs` covers per-substrate engine determinism flags, checkpoint inference parity, generated Linux CPU identity/reduction-smoke/family-scaffold kernel compile/load/run, exported family/output-count symbol verification, and local Linux CPU `HasEngine` dispatch | Integration (project-specific) | Sprint 12.6 |
| `jitml-daemon-lifecycle` | `test/daemon-lifecycle/Main.hs` covers lifecycle ordering, endpoints, retry policy, at-least-once deduplication, inference request/result protobuf byte round-trips, fully-qualified Pulsar topic routing, BootConfig-derived daemon subscription planning, startup subscription acquisition through the combined daemon client interpreter, bounded acquired-subscription consumer batches, LiveConfig-derived handler-router dedup cache sizing, daemon runtime summary rendering including `pulsar_subscriptions` / `pulsar_subscription_status`, and one-shot daemon HTTP serving | Daemon Lifecycle | Sprint 12.7 |
| `jitml-e2e` | `test/e2e/Main.hs` covers route, bucket, publication, browser-contract, demo HTTP including generated stream routes, deployment, report-card, no leaked `jitml-e2e-*` clusters when `kind` and `/var/run/docker.sock` are available, and typed live-plan surfaces | Pulumi-Orchestrated Infrastructure | Sprint 12.8 |
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

The four `*-canonicals`/HPO/cross-backend rows are **project-specific
Integration** stanzas under doctrine §Test Organization's project-specific
stanzas allowance — extensions of the Integration category, not parallel
test systems.

`jitml test all` (Sprint `12.9`) fans out to every test stanza above by
invoking `cabal test` with the explicit eight test-only stanza names through
the typed `Subprocess` boundary, then renders a target-stanza report card after
Cabal succeeds. `jitml test <stanza>` renders the same report shape for the
selected stanza only. Style and code-quality commands are deliberately
separate; use `jitml lint *` and `jitml check-code` inside `jitml:local`.
`jitml test <stanza>` invokes one Cabal stanza through the same boundary.

## Project-Specific Stanza Notes

### `jitml-sl-canonicals` — SL canon coverage

The current body exercises the eleven local canonical cells from
`src/JitML/SL/Canonicals.hs`, verifies each synthetic convergence curve is
deterministic, and asserts the final synthetic loss improves over the initial
loss. It also checks every current deterministic curve against the committed
fixture under `test/golden/sl/<problem-key>/curve.txt`, verifies dataset fetch
and SHA validation through `HasMinIO`, and round-trips Training command/event
envelopes. Live measured training transcript byte equality remains target
runtime validation.

### `jitml-rl-canonicals` — RL canon coverage

The current body checks representative entries in `algorithmCatalog`, verifies
`deterministicTrajectory` is stable for a fixed algorithm and seed, compares the
PPO/CartPole trajectory to `test/golden/rl/ppo/cartpole/trajectory.txt`, and
checks the local Connect 4, Othello, Hex, and Gomoku transcript helpers against
`test/golden/alphazero/<game>-transcript.txt`. It also round-trips RL
command/event envelopes. Environment rollouts, policy training,
reward-distribution fixtures, and live AlphaZero arena measurements remain
target validation.

### `jitml-hyperparameter` — sampler / scheduler / pruner reproducibility

The current body checks the local `Grid`, `Sobol`, `Random`, `TPE`, `GPBO`,
`GeneticAlgorithm`, `NSGA2`, `MuLambdaES`, `CMAES`, `EvolutionStrategies`,
and `PBT` samplers; `Fifo`, `SuccessiveHalving`, `Hyperband`, and `ASHA`
schedulers; and `NoPruner`, `MedianPruner`, and `PercentilePruner` pruners.
It verifies deterministic local trial values, sampler-label parsing, the
current Sobol/GA golden fixtures, and the `experiments/mnist-tune.dhall` TPE
worked-example decode, and round-trips Tune command/event envelopes. Live trial
persistence and resume-from-partial-sweep
equality against MinIO remain target validation.

### `jitml-cross-backend` and the Tolerance Band

The current body checks that every local substrate has deterministic engine
flags and that the local `inferFromManifest` helper returns the same summary
for every substrate. It also routes the generated Linux CPU identity kernel
plus the generated reduction-smoke and family-scaffold kernels through the
shared cache artifact loader, loads `jitml_kernel` and
`jitml_kernel_family_name` / `jitml_kernel_output_count` with `dlopen`,
verifies the reported family and output length, and asserts three successive
FFI runs return bit-identical fixture output. It also dispatches a generated
family kernel through the local Linux CPU `HasEngine` interpreter and checks
the loaded family metadata at that boundary, and measures the Linux CPU
benchmark candidate runner against generated FFI output with digest capture.
`jitml-unit` owns the CUDA runtime-probe parser fixtures for `nvcc`,
`nvidia-smi`, and `ldconfig`, plus the guarded CUDA benchmark-runner preflight
fixtures for wrong-substrate rejection, unavailable runtime summaries, and
available-runtime fail-closed behavior; `jitml-integration` owns the live probe
attempt through typed subprocesses.
The same split covers the Metal runtime probe fixtures for Swift, `xcrun`, and
`system_profiler` and the guarded Metal benchmark-runner preflight fixtures.
Live
cross-substrate graph-kernel launches and cross-substrate tolerance fixtures
under `test/golden/cross-backend/` remain the final handoff validation gate.

### `jitml-daemon-lifecycle`

The current body exercises local lifecycle ordering, renderable endpoint
responses, retry policy behavior, payload-hash deduplication,
Inference request/result protobuf byte round-trips, and one-shot
HTTP serving for `/healthz`. It also covers the `JitML.Service.Signal` mapping:
`SIGHUP` increments reload generation, while `SIGINT` / `SIGTERM` begin drain
and make readiness false. Real Pulsar redelivery remains target runtime
validation.

### `jitml-e2e` and Pulumi

The current `jitml-e2e` body validates local route, bucket, `chart/values.yaml`
MinIO coverage, publication, browser-contract, demo HTTP routes including the
generated stream endpoints, deployment, report-card rendering plus the
`cabal.project` knob-block parser, typed live-plan surfaces, no leaked
`jitml-e2e-*` Kind clusters when `kind` and `/var/run/docker.sock` are both
available, and the bundle-serving fallback. When the binary or Docker socket is
absent, only the local Docker-backed Kind query is skipped. The Pulumi
TypeScript program at
`infra/pulumi/`
contains a typed `@pulumi/command` resource graph for Kind creation, Helm
dependency build, `jitml bootstrap`, publication checking, and symmetric Kind
deletion. The live driver is an explicit command path, not a process-environment
gate or part of default `cabal test all`, because it creates and destroys Kind,
builds Helm dependencies, mutates
image/runtime state, and polls live routes.
Future live test driver:

1. A typed `helm dependency build chart` step prepares subchart dependencies
   before any apply. `Chart.lock` becomes part of the reproducible surface only
   if the project adopts committed chart dependency locking.
2. `pulumi up` brings up the stack (Kind cluster, Helm chart in its `final`
   phase against a temporary registry image pushed during the run, plus the
   `jitml-demo` Deployment).
3. The driver runs `jitml train`, `jitml rl train`, `jitml tune` against the
   ephemeral stack to seed the demo state.
4. The driver invokes the Playwright suite from
   [../../DEVELOPMENT_PLAN/phase-11-purescript-frontend-and-demo.md → Sprint
   11.6](../../DEVELOPMENT_PLAN/phase-11-purescript-frontend-and-demo.md)
   against the live bundle across the six demo cohorts (training control,
   MNIST handwriting, image upload, Connect 4 game-play, TensorBoard/Grafana
   navigation, hyperparameter sweep).
5. `pulumi destroy` and a teardown audit (no orphan PVs, MinIO buckets,
   Harbor projects, or Docker volumes survive).

Future Pulumi invocations flow through the typed `Subprocess` boundary.

### Playwright

Playwright belongs to the doctrine's target Pulumi-Orchestrated Infrastructure
test category. The current repository has `playwright/jitml-demo.spec.ts` as a
scaffold. The default `jitml-e2e` body validates the typed Playwright plan and
the current inline DOM stub spec without invoking the live stack. Live
edge-route Playwright execution waits until panels
consume fixture-backed or live-backed state through `jitml-demo`; static
route/API scaffold checks stay in the local Haskell e2e and PureScript-style
stanzas.

### Property Invariants

Per doctrine `Test Categories → Property Tests`, every codec exposes the
canonical invariants:

- `decode . encode == id`
- `render is deterministic`
- `parser roundtrips`

Current checked coverage applies these invariants to the local parser, renderers,
route registry, cache helpers, checkpoint key/CAS/store helpers, runtime-source
renderers, numerical/RL Dhall catalog mirrors, local catalog helpers, and the
current route/Grafana/tuning/RL golden fixtures.
Transcript codecs, manifest CBOR, protobuf schemas, generated Grafana fixtures,
and richer numerical-core Dhall round-trips remain target validation.

### Golden Tests and Sentinel Placeholders

Golden fixtures live under `test/golden/`. Non-deterministic content (wall-
clock readings, hostnames, timestamps) is replaced with sentinel placeholders
per doctrine `Test Categories → Golden Tests`.

## Cross-References

- [../../README.md](../../README.md)
- [../../DEVELOPMENT_PLAN/phase-12-test-stanzas-and-cross-cluster.md](../../DEVELOPMENT_PLAN/phase-12-test-stanzas-and-cross-cluster.md)
- [determinism_contract.md](determinism_contract.md)
- [../documentation_standards.md](../documentation_standards.md)
