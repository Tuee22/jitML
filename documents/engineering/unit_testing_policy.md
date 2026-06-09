# Unit Testing Policy

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: README.md, ../documentation_standards.md, ../../README.md, determinism_contract.md, training_workloads.md, jit_codegen_architecture.md, ../../DEVELOPMENT_PLAN/phase-0-planning-documentation.md, ../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md, ../../DEVELOPMENT_PLAN/phase-8-supervised-and-rl-framework.md, ../../DEVELOPMENT_PLAN/phase-9-rl-catalog-alphazero-and-tuning.md, ../../DEVELOPMENT_PLAN/phase-11-purescript-frontend-and-demo.md, ../../DEVELOPMENT_PLAN/phase-12-test-stanzas-and-cross-cluster.md, ../../DEVELOPMENT_PLAN/phase-13-linux-cuda-and-cluster-closure.md, ../../DEVELOPMENT_PLAN/phase-15-cross-substrate-and-handoff.md
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

The eight Cabal test-suite stanzas are declared in `jitml.cabal`. Current bodies
exercise the local deterministic contracts for their owning surfaces while live
cluster validation remains phase-gated:

| Stanza | Current body | Final Tier | Owning Sprint |
|--------|--------------|------------|---------------|
| `jitml-unit` | `test/unit/Main.hs` covers current CLI, docs, prerequisite, env, app-error, plan, subprocess, bootstrap-script, cache, hot-reload, capability, RL framework, AlphaZero, tuning resume, checkpoint key/CAS/store, `.jmw1` encode/decode, TensorBoard scalar-event codec / TFRecord writer / sidecar, Grafana fixture, and frontend bundle/panel/demo-route surfaces | Pure Logic + Parser + Property + Snapshot | Sprint 12.1 |
| `jitml-integration` | `test/integration/Main.hs` covers typed subprocess execution, bootstrap/live-rollout renderers, route-table snapshot fixture, real-binary spawn matrix, filesystem-backed `HasMinIO` checkpoint / inference / resume coverage, local Linux CPU checkpoint inference through a generated oneDNN FFI kernel with decoded `.jmw1` weights, routed MinIO/Pulsar subprocess command rendering including the WebSocket subscribe probe, substrate-scoped Pulsar topic bootstrap, BootConfig-derived daemon client settings, single-node Kind rendering, required `jitml-service` anti-affinity plus single-node rollout strategy/RBAC rendering, Dhall numerics decode, linkable oneDNN runtime probing, and typed service command shapes | Integration | Sprint 12.2 |
| `jitml-sl-canonicals` | `test/sl-canonicals/Main.hs` covers the canonical SL `(dataset, model)` matrix as property tests over the typed `TrainingLifecycle` — loss is finite, decreases monotonically over the budget, and the median over `k` seeds clears a literature-derived sanity threshold computed at test time — dataset fetch verification, and Training command/event envelope round-trips. No per-substrate numerical fixtures are committed. | Integration (project-specific) | Sprint 12.3 |
| `jitml-rl-canonicals` | `test/rl-canonicals/Main.hs` covers the RL algorithm catalog as property tests (finite-and-decreasing loss, finite gradients, monotone evaluator reward over a sliding window, run-to-run bit-identical trajectory on the same substrate / same seed), the canonical-game RL surface (legal-move generation, terminal detection, draw conditions), and RL command/event envelope round-trips. No per-substrate trajectory or reward-distribution fixtures are committed. | Integration (project-specific) | Sprint 12.4 |
| `jitml-hyperparameter` | `test/hyperparameter/Main.hs` covers sampler / scheduler / pruner axes including TPE, the TPE worked-example Dhall decode, sampler resume equality (replay an event log → next-batch matches first-pass), and Tune command/event envelope round-trips. Sampler trial values are checked as properties (e.g. resume equality, sampler-state purity, scheduler ordering invariants) rather than committed numerical sequences. | Integration (project-specific) | Sprint 12.5 |
| `jitml-cross-backend` | `test/cross-backend/Main.hs` covers per-substrate **within-substrate** determinism: engine determinism flags, checkpoint inference summaries, generated kernel compile/load/run, exported family/output-count symbol verification, and `HasEngine` dispatch — each substrate's cases run **for real** in their own lane (Apple host-native; linux-cpu in the `jitml` container; linux-cuda in the `jitml-cuda` GPU container), selected via `--test-options='-p <substrate>'`, with **no skipped tests** and no cross-substrate cohort | Integration (project-specific) | Sprint 12.6 |
| `jitml-daemon-lifecycle` | `test/daemon-lifecycle/Main.hs` covers lifecycle ordering, endpoints, retry policy, at-least-once deduplication, inference request/result protobuf byte round-trips, fully-qualified Pulsar topic routing, BootConfig-derived daemon subscription planning, startup subscription acquisition through the combined daemon client interpreter, bounded acquired-subscription consumer batches, LiveConfig-derived handler-router dedup cache sizing, daemon runtime summary rendering including `pulsar_subscriptions` / `pulsar_subscription_status`, and one-shot daemon HTTP serving | Daemon Lifecycle | Sprint 12.7 |
| `jitml-e2e` | `test/e2e/Main.hs` covers route, bucket, publication, browser-contract, demo HTTP including generated stream routes, deployment, report-card, no leaked `jitml-e2e-*` clusters when `kind` and `/var/run/docker.sock` are available, and typed live-plan surfaces | Ephemeral-Cluster Infrastructure | Sprint 12.8 |
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
| Integration | `jitml-integration`, `jitml-sl-canonicals`, `jitml-rl-canonicals`, `jitml-hyperparameter`, `jitml-cross-backend` |
| Daemon Lifecycle | `jitml-daemon-lifecycle` |
| Ephemeral-Cluster Infrastructure | `jitml-e2e` |

The four `*-canonicals`/HPO/cross-backend rows are **project-specific
Integration** stanzas under doctrine §Test Organization's project-specific
stanzas allowance — extensions of the Integration category, not parallel
test systems.

`jitml test all` (Sprint `12.9`) fans out to every test stanza above by
invoking `cabal test` with the explicit eight test-only stanza names through
the typed `Subprocess` boundary, then renders a target-stanza report card after
Cabal succeeds. `jitml test <stanza>` renders the same report shape for the
selected stanza only. Style and code-quality commands are deliberately
separate; use `docker compose run --rm jitml jitml lint *` and
`docker compose run --rm jitml jitml check-code` inside the headless
`jitml:local` service.
`jitml test <stanza>` invokes one Cabal stanza through the same boundary.

## Project-Specific Stanza Notes

### `jitml-sl-canonicals` — SL canon coverage

The current body exercises the eleven canonical cells from
`src/JitML/SL/Canonicals.hs` as property tests over the typed
`TrainingLifecycle`: loss values are finite, decrease monotonically over the
training budget, and the median over a small fixed-seed pool clears a
sanity threshold derived from the literature reference at test time
(no per-substrate stored fixture). The stanza also verifies dataset fetch
and SHA validation through `HasMinIO`, and round-trips Training
command/event envelopes. No `.txt` / `.json` files of hardcoded per-epoch
loss values are committed — see [Snapshot Tests and the Prohibition on
Numerical Fixtures](#snapshot-tests-and-the-prohibition-on-numerical-fixtures).

### `jitml-rl-canonicals` — RL canon coverage

The current body checks representative entries in `algorithmCatalog`,
verifies same-substrate, same-seed run-to-run trajectory equality
(two fresh runs compared bit-for-bit against each other — no stored
trajectory file), property-tests the canonical environments (legal-move
generation, terminal detection, draw conditions for Connect 4, Othello,
Hex, and Gomoku), and round-trips RL command/event envelopes.
Convergence is asserted statistically: median evaluator reward over a
fixed-seed pool clears a literature-derived threshold computed at test
time. No per-substrate trajectory, reward-distribution, or AlphaZero
transcript files are committed.

`KeyDoorGrid-v0` is the required visual discrete-control canonical demo target
for the reopened Phase `8` / Phase `9` replacement work. Its tests assert
same-seed map generation, legal-action masks, key pickup, locked-door
transition behavior, goal termination, render-frame determinism, and run-to-run
trajectory equality without committed trajectory fixtures.

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

### `jitml-cross-backend` — per-substrate within-substrate determinism

The current body checks that every local substrate has deterministic engine
flags and that the local `inferFromManifest` helper returns the same summary
for every substrate. It also routes the generated oneDNN/CUDA/Metal primitive
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
skipped**: Apple Metal runs host-native, `linux-cpu` oneDNN runs in the
`jitml` container, and `linux-cuda` runs in the `jitml-cuda` GPU container.
A lane is selected with `jitml test jitml-cross-backend
--test-options='-p <substrate>'`. Within-substrate bit-for-bit
reproducibility is the only equality asserted here.

`jitml-unit` owns the CUDA runtime-probe parser snapshots for `nvcc`,
`nvidia-smi`, and `ldconfig`, plus the guarded CUDA benchmark-runner preflight
checks for wrong-substrate rejection, unavailable runtime summaries, and
available-runtime fail-closed behavior; `jitml-integration` owns the live probe
attempt through typed subprocesses. The same split covers the Metal runtime
probe snapshots for Swift, `xcrun`, and `system_profiler` and the guarded
Metal benchmark-runner preflight checks. On `apple-silicon` the live Metal/Swift
compile-and-execute path these probes guard runs **headless on the host**: the
CommandLineTools `swift build` produces the glue dylib and the launcher
JIT-compiles the Metal shader at runtime via `MTLDevice.makeLibrary(source:)` —
no Tart VM, no full Xcode. The Apple `jitml-cross-backend` lane runs
host-native on `apple-silicon` where a Metal device is usable headless; each
substrate's lane runs its own cases for real with no skipped tests. See
[../engineering/jit_codegen_architecture.md → Apple Silicon Headless JIT](../engineering/jit_codegen_architecture.md#apple-silicon-headless-jit).
Only within-substrate bit-for-bit reproducibility is asserted; there is no
cross-substrate drift check and no tolerance band. See
[determinism_contract.md → The Contract](determinism_contract.md#the-contract).

### `jitml-daemon-lifecycle`

The current body exercises local lifecycle ordering, renderable endpoint
responses, retry policy behavior, payload-hash deduplication,
Inference request/result protobuf byte round-trips, and one-shot
HTTP serving for `/healthz`. It also covers the `JitML.Service.Signal` mapping:
`SIGHUP` increments reload generation, while `SIGINT` / `SIGTERM` begin drain
and make readiness false. Real Pulsar redelivery remains target runtime
validation.

### `jitml-e2e` and the ephemeral-cluster live driver

The current `jitml-e2e` body validates local route, bucket, `chart/values.yaml`
MinIO coverage, publication, browser-contract, demo HTTP routes including the
generated stream endpoints, deployment, report-card rendering plus the
`cabal.project` knob-block parser, typed live-plan surfaces, no leaked
`jitml-e2e-*` Kind clusters when `kind` and `/var/run/docker.sock` are both
available, and the bundle-serving fallback. When the binary or Docker socket is
absent, only the local Docker-backed Kind query is skipped. The typed
`JitML.Test.LivePlan.liveE2EPlan` records the live orchestration as `Subprocess`
values: `helm dependency build chart` → `jitml bootstrap` (ephemeral Kind +
phased Helm rollout) → `npx playwright test` → `jitml cluster down`. The live
driver is an explicit command path, not a process-environment gate or part of
default `cabal test all`, because it creates and destroys Kind, builds Helm
dependencies, mutates image/runtime state, and polls live routes.
Live test driver:

1. A typed `helm dependency build chart` step prepares subchart dependencies
   before any apply. `Chart.lock` becomes part of the reproducible surface only
   if the project adopts committed chart dependency locking.
2. `jitml bootstrap --<substrate>` brings up the stack (ephemeral Kind cluster,
   Helm chart in its `final` phase, plus the `jitml-demo` Deployment) and writes
   `cluster-publication.json`.
3. The driver runs `jitml train`, `jitml rl train`, `jitml tune` against the
   ephemeral stack to seed the demo state.
4. The driver invokes the Playwright suite from
   [../../DEVELOPMENT_PLAN/phase-11-purescript-frontend-and-demo.md → Sprint
   11.6](../../DEVELOPMENT_PLAN/phase-11-purescript-frontend-and-demo.md)
   against the live bundle across the six demo cohorts (training control,
   MNIST handwriting, image upload, Connect 4 game-play, TensorBoard/Grafana
   navigation, hyperparameter sweep).
5. `jitml cluster down` and a teardown audit (no orphan PVs, MinIO buckets,
   Harbor projects, or Docker volumes survive).

All live driver invocations flow through the typed `Subprocess` boundary.

### Live Report Card

`jitml test all` remains local by default: it runs the eight test-only Cabal
stanzas and renders the typed target-stanza report card. `jitml test all
--live` appends measured fields to that same `ReportCard` value for SL final
loss, RL final reward, AlphaZero arena win rate, tuning objective, JIT cache
hit rate, and daemon `/healthz`. Cache hit rate is
read from daemon Prometheus counters (`jitml_jit_cache_hits` /
`jitml_jit_cache_misses`) on the published `/metrics` edge route; daemon health
is read from the published `/healthz` edge route. A live source that is not
reachable on the current host renders as `unavailable`; the command does not
silently substitute a deterministic fixture.

### Playwright

Playwright belongs to the doctrine's target Ephemeral-Cluster Infrastructure
test category. The current repository has `playwright/jitml-demo.spec.ts` as a
live-only seven-panel matrix: it reads
`.build/runtime/cluster-publication.json`, drives the published edge route, and
fails fast when no live publication exists. The default `jitml-e2e` body
validates the typed Playwright plan and server-side route/concurrency
invariants without invoking the live stack; live edge-route Playwright
execution stays on the explicit live orchestration path. Static route/API
scaffold checks stay in the local Haskell e2e and the `purescript-spec` smoke
suite run by `spago test` through the Node `spec-node` runner.

### Property Invariants

Per doctrine `Test Categories → Property Tests`, every codec exposes the
canonical invariants:

- `decode . encode == id`
- `render is deterministic`
- `parser roundtrips`

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
- [../../DEVELOPMENT_PLAN/phase-12-test-stanzas-and-cross-cluster.md](../../DEVELOPMENT_PLAN/phase-12-test-stanzas-and-cross-cluster.md)
- [determinism_contract.md](determinism_contract.md)
- [../documentation_standards.md](../documentation_standards.md)
