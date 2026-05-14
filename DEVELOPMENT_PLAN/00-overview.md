# jitML Development Plan — Overview

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md),
[development_plan_standards.md](development_plan_standards.md),
[system-components.md](system-components.md),
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md),
[phase-0-planning-documentation.md](phase-0-planning-documentation.md),
[phase-1-haskell-cli-surface.md](phase-1-haskell-cli-surface.md),
[phase-2-bootstrap-reconciler-and-jit-cache.md](phase-2-bootstrap-reconciler-and-jit-cache.md),
[phase-3-cluster-substrate-and-routing.md](phase-3-cluster-substrate-and-routing.md),
[phase-4-stateful-platform-services.md](phase-4-stateful-platform-services.md),
[phase-5-jitml-service-daemon.md](phase-5-jitml-service-daemon.md),
[phase-6-numerical-core.md](phase-6-numerical-core.md),
[phase-7-jit-codegen-and-substrates.md](phase-7-jit-codegen-and-substrates.md),
[phase-8-supervised-and-rl-framework.md](phase-8-supervised-and-rl-framework.md),
[phase-9-rl-catalog-alphazero-and-tuning.md](phase-9-rl-catalog-alphazero-and-tuning.md),
[phase-10-checkpointing-and-inference.md](phase-10-checkpointing-and-inference.md),
[phase-11-purescript-frontend-and-demo.md](phase-11-purescript-frontend-and-demo.md),
[phase-12-test-stanzas-and-cross-cluster.md](phase-12-test-stanzas-and-cross-cluster.md),
[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md), [../README.md](../README.md)
**Generated sections**: none

> **Purpose**: Capture the target architecture, current baseline, doctrine scope,
> hard constraints, and dependency chain that every jitML phase depends on.

## Vision

jitML is a Haskell-native machine learning framework that treats *the entire training
process* as a declarative, reproducible program. Models, optimizers, datasets, RL
environments, checkpoints, hardware backends, loss functions, training schedules,
hyperparameter sweeps, and cluster topology are all described in `.dhall`. jitML
JIT-compiles hardware-specific kernels on demand, builds optimized native binaries,
and executes them through Haskell FFI bindings.

The jitML runtime closes on three properties simultaneously:

- **Reproducible by construction.** Given identical inputs, seeds, and configuration,
  two runs produce identical outputs — including parameter initialization, minibatch
  ordering, optimizer state, RL trajectories, MCTS exploration paths, hyperparameter-
  trial selection, and checkpoint recovery. Reproducibility is an architectural
  requirement, not a flag.
- **Declarative end-to-end.** A `.dhall` file is the full source of truth for a
  training run, a hyperparameter sweep, an RL experiment, or a cluster deployment.
  CLI flags layered on top *override* the Dhall; they never replace it.
- **Hardware-native without an embedded Python runtime.** jitML compiles kernels on
  demand for Apple Metal, NVIDIA CUDA, and oneDNN/AVX, and executes them through
  Haskell FFI bindings. The runtime has no Python interpreter in the loop.

## Target Outcome

One `jitml` Haskell CLI binary, built by Cabal under GHC `9.14.1` and Cabal
`3.16.1.0`, drives three substrates (`apple-silicon`, `linux-cpu`, `linux-cuda`)
behind a uniform command surface, plus one bundled `jitml-demo` HTTP server shim that
serves the PureScript frontend bundle. The CLI is library-first per doctrine
[§Project Structure](../HASKELL_CLI_TOOL.md): `app/Main.hs` is a six-line shim into
`App.main`; nearly all logic lives under `src/JitML/`.

There is **one CLI verb for the daemon — `jitml service` — parameterised entirely by
its Dhall config**. The Dhall declares substrate, residency (`Cluster | Host`),
inference mode (`SelfInference | ForwardToHost`), and host-side MinIO/Pulsar
connection info when `residency = Host`. There is no separate `host-service` CLI
verb. On Linux substrates one daemon runs in-cluster (`Cluster + SelfInference`); on
Apple Silicon two daemons run, both the same binary distinguished by Dhall
(`Cluster + ForwardToHost` in-pod and `Host + SelfInference` host-native) because
Metal cannot be containerized.

`jitml cluster up` is the canonical full-stack rollout entrypoint: it writes the
per-substrate Kind config from `./kind/cluster-<substrate>.yaml`, brings up Kind,
writes `./.build/jitml.kubeconfig` (the user's `~/.kube/config` is never touched),
and runs the phased Helm rollout from the umbrella chart at `chart/`. The single
exposed listener is one `127.0.0.1:<edge-port>` socket on the Envoy Gateway; every
HTTPRoute in the cluster is rendered from the typed registry in
`src/JitML/Routes.hs`.

The numerical core (layer catalog, real+complex activations, optimizers, schedulers,
losses, spectral ops) ships as a Dhall-typed catalog. Per-substrate JIT codegen
drivers (`codegen-cuda/`, `codegen-metal/`, `codegen-onednn/`) consume the catalog
and write into the content-addressed cache at
`./.build/jit/<substrate>/<hash>.<ext>`, with stable host-side symlinks at
`./.build/host/apple-silicon/` for FFI dlopen stability.

The full SL training loop, canonical SL problem set with golden curve fixtures, the
RL framework primitives (Algorithm typeclass at the type level, Policy, Environment,
VecEnv, buffers, schedules, action distributions, action noise, target networks,
GAE, callbacks, Logger, Evaluator, training loops as typed pipelines), the RL
algorithm catalog (PPO, A2C, TRPO, MaskablePPO, RecurrentPPO, DQN, QR-DQN, DDPG,
TD3, SAC, CrossQ, TQC, ARS, HER), AlphaZero-style self-play with persistent MCTS
state, and the hyperparameter tuner (Sobol/random/GA/ES samplers ×
Fifo/SuccessiveHalving/Hyperband/ASHA schedulers × {none/median/percentile} pruners)
all run on the same `jitml service` daemon.

Checkpoints write the split-blob `.jmw1` format with the typed manifest; the
inference-only read path is consumed by both the demo HTTP server and the PureScript
panels. The PureScript frontend under `web/` is generated from
`src/JitML/Web/Contracts.hs` via `purescript-bridge`.

`jitml test all` runs every Cabal test-suite stanza (`jitml-unit`,
`jitml-integration`, `jitml-sl-canonicals`, `jitml-rl-canonicals`,
`jitml-hyperparameter`, `jitml-cross-backend`, `jitml-daemon-lifecycle`,
`jitml-e2e`, `jitml-haskell-style`, `jitml-purescript-style`) with the
report-card knobs pinned in `cabal.project`. The `jitml-e2e` stanza
orchestrates an ephemeral Kind stack via the Pulumi TypeScript program at
`infra/pulumi/`.

## Architecture Overview

- **Haskell CLI surface.** One binary `jitml` plus the `jitml-demo` HTTP server
  shim. The parser is generated from a separate `CommandSpec` registry — never the
  source of truth. The same registry feeds the parser, the command tree (`jitml
  commands --tree`), the JSON command schema (`jitml commands --json`), the markdown
  command reference, the manpages, and the shell completion scripts. Owned by
  [phase-1-haskell-cli-surface.md](phase-1-haskell-cli-surface.md).
- **Bootstrap reconciler, prerequisite DAG, JIT cache.** Three idempotent bootstrap
  scripts (`bootstrap/{apple-silicon,linux-cpu,linux-cuda}.sh`) reconcile host
  prerequisites under the same subcommand surface
  `help | doctor | build | up | status | test | down | purge` (Linux adds `push`).
  The same typed `Prerequisite` DAG that the scripts use is consumed in-process by
  the Haskell daemon. The content-addressed JIT cache at
  `./.build/jit/<substrate>/<hash>.<ext>` is keyed on `(canonical-cbor(KernelSpec),
  kind, substrate, toolchain-fingerprint)`; on Apple Silicon, stable symlinks under
  `./.build/host/apple-silicon/` give the FFI a stable dlopen surface across
  re-JITs. The lazy-tart pattern keeps the Swift/Metal build VM down until a fresh
  `(model-shape, kind, substrate, toolchain)` tuple appears. Outer-container Linux
  builds run as `docker compose run --rm jitml jitml <subcommand>`; the substrate
  image is `jitml:local`. Owned by
  [phase-2-bootstrap-reconciler-and-jit-cache.md](phase-2-bootstrap-reconciler-and-jit-cache.md).
- **Cluster substrate and routing.** Per-substrate Kind configs at
  `./kind/cluster-<substrate>.yaml`, single control-plane + one worker, NodePort
  30090 backing the edge listener, host `./.build/` bind-mounted into the Kind
  worker via `extraMounts`. Storage uses `kubernetes.io/no-provisioner` only —
  manual PVs against a `jitml-manual` StorageClass backed by hostPath under
  `./.data/kind/<substrate>/`. The umbrella Helm chart at `chart/` carries subchart
  dependencies for Harbor, Apache Pulsar, MinIO, Percona PostgreSQL, Envoy Gateway,
  kube-prometheus-stack, and TensorBoard. The single exposed listener is one
  `127.0.0.1:<edge-port>` Envoy Gateway socket; the typed route registry in
  `src/JitML/Routes.hs` is the source of truth for every HTTPRoute. The CLI never
  touches `~/.kube/config`. Owned by
  [phase-3-cluster-substrate-and-routing.md](phase-3-cluster-substrate-and-routing.md).
- **Stateful platform services.** Harbor as the in-cluster registry against
  dedicated PostgreSQL storage; MinIO buckets `harbor`, `jitml-checkpoints`,
  `jitml-events`, `jitml-trials`; Apache Pulsar as the control-plane ↔ data-plane
  bus with topics `inference.command.apple-silicon`,
  `inference.event.apple-silicon` for the host↔cluster RPC, plus
  `inference.request.<mode>` / `inference.result.<mode>` for the demo-facing
  inference flow; Percona Operator-managed PostgreSQL **only for Harbor** — there is
  no relational DB on jitML's data path; kube-prometheus-stack for metrics scraping
  and Grafana dashboards; TensorBoard event storage with shard rotation against
  MinIO bucket `jitml-events`. Owned by
  [phase-4-stateful-platform-services.md](phase-4-stateful-platform-services.md).
- **`jitml service` daemon.** The single Pulsar-subscribed worker. `BootConfig` /
  `LiveConfig` Dhall split with mandatory SIGHUP hot reload, `/healthz` / `/readyz`
  / `/metrics` endpoints, structured JSON stderr logging, recoverable-vs-fatal
  error kinds, at-least-once Pulsar consumer semantics with the typed retry policy,
  capability classes `HasMinIO`, `HasPulsar`, `HasHarbor`, `HasKubectl`, `ReaderT
  Env IO` runner. Stateless `Deployment` (not `StatefulSet`) with pod anti-affinity
  at `topologyKey: kubernetes.io/hostname`. Owned by
  [phase-5-jitml-service-daemon.md](phase-5-jitml-service-daemon.md).
- **Numerical core.** Dhall-typed layer catalog (Dense, Conv1D, Conv2D, Conv3D,
  ConvTranspose, BatchNorm, LayerNorm, GroupNorm, Dropout, ResidualBlock,
  MultiHeadAttention, ...), real + complex activations, spectral / frequency-
  domain ops, optimizers (SGD, Momentum, Adam, AdamW, RMSProp, Lion, Adafactor,
  ...), schedulers (constant, step, cosine, polynomial, warmup-cosine), loss
  functions (cross-entropy, focal, MSE, Huber, IoU). Every constructor has a Dhall
  type. Owned by [phase-6-numerical-core.md](phase-6-numerical-core.md).
- **JIT codegen and per-substrate execution.** `src/JitML/Engines/{AppleSilicon,
  LinuxCPU, LinuxCUDA}.hs`, plus the substrate-specific codegen drivers
  `codegen-metal/`, `codegen-onednn/`, `codegen-cuda/`. The Apple Silicon hybrid
  pattern (host daemon shim + lazy tart VM spin-up) is owned here. Hardware auto-
  tuning chooses among reduction strategies, tile sizes, and prefetch widths per
  substrate while preserving the determinism contract per
  [../documents/engineering/determinism_contract.md](../documents/engineering/determinism_contract.md):
  Metal single-stream launch order, oneDNN blocked reduction with fixed block
  size, CUDA deterministic warp-shuffle reductions with `--use_fast_math=false` and
  cuDNN explicit algorithm-id pinning. Owned by
  [phase-7-jit-codegen-and-substrates.md](phase-7-jit-codegen-and-substrates.md).
- **Supervised learning and RL framework.** `src/JitML/SL/` supervised training
  loops, canonical SL problem set (MNIST, CIFAR-10, CIFAR-100, ImageNet) with
  golden convergence curves; `src/JitML/Env/` canonical RL environments (cartpole,
  mountain-car, lunar-lander, ...); `src/JitML/RL/` framework primitives —
  Algorithm class taxonomy at the type level, Policy as typed value, Environment /
  VecEnv as typed capability, replay & rollout buffers with `Async` write
  discipline, schedules, action distributions, action noise, target networks +
  Polyak averaging, GAE, callbacks as composable hooks, multi-sink Logger,
  Evaluator, training loops as typed pipelines. Owned by
  [phase-8-supervised-and-rl-framework.md](phase-8-supervised-and-rl-framework.md).
- **RL algorithm catalog, AlphaZero, hyperparameter tuning.** `src/JitML/RL/`
  algorithm catalog (PPO, A2C, TRPO, MaskablePPO, RecurrentPPO, DQN, QR-DQN, DDPG,
  TD3, SAC, CrossQ, TQC, ARS, HER) with golden trajectory fixtures. AlphaZero-
  style self-play with persistent MCTS state, perfect-information game type
  class, two-headed network, MCTS-guided self-play loop, arena gating, canonical
  adversarial games (Connect 4 canonical). `src/JitML/Tune/` hyperparameter tuning
  across the sampler × scheduler × pruner axes (Sobol / random / GA / ES samplers
  × Fifo / SuccessiveHalving / Hyperband / ASHA schedulers × {none / median /
  percentile} pruners), trial storage and resume against MinIO `jitml-trials`,
  parallelism. Owned by
  [phase-9-rl-catalog-alphazero-and-tuning.md](phase-9-rl-catalog-alphazero-and-tuning.md).
- **Checkpointing and inference-only read path.** Split-blob layout (one immutable
  weight blob per uniquely shaped tensor group, one manifest per snapshot
  enumerating the blob keys). `.jmw1` dense weight blob wire format. Typed
  manifest. Bit-determinism contract scoped to same-substrate equality;
  cross-substrate drift is bounded by the per-tensor tolerance band measured by
  the cross-substrate tolerance methodology. No Postgres on jitML's data path —
  manifests and blobs live in MinIO bucket `jitml-checkpoints`. The inference-only
  read path is the supported entrypoint for the demo HTTP server and the
  PureScript panels. Owned by
  [phase-10-checkpointing-and-inference.md](phase-10-checkpointing-and-inference.md).
- **PureScript frontend and demo.** `web/` Halogen application; `purescript-spec`
  unit tests under `web/test/`; `playwright/` E2E suite. The browser-contract ADTs
  live in `src/JitML/Web/Contracts.hs` and are the source for `purescript-bridge`,
  which generates `web/src/Generated/Contracts.purs`. REST surfaces for interactive
  panels (training-run lifecycle, MNIST live inference, CIFAR/ImageNet upload, RL
  trajectory render, AlphaZero-vs-human Connect 4). The bundle is served by the
  `jitml-demo` HTTP server shim into `App.main`. Owned by
  [phase-11-purescript-frontend-and-demo.md](phase-11-purescript-frontend-and-demo.md).
- **Test stanzas, lint matrix, cross-cluster parity.** Ten Cabal test-suite
  stanzas, each `type: exitcode-stdio-1.0` with `tasty` as the in-stanza runner:
  `jitml-unit`, `jitml-integration`, `jitml-sl-canonicals`,
  `jitml-rl-canonicals`, `jitml-hyperparameter`, `jitml-cross-backend`,
  `jitml-daemon-lifecycle`, `jitml-e2e`, `jitml-haskell-style`,
  `jitml-purescript-style`. `jitml test all` is a Plan/Apply command that
  delegates to `cabal test`, runs the pinned report-card workload, and emits the
  tidy summary block. The Pulumi TypeScript program at `infra/pulumi/` is the
  ephemeral-Kind orchestrator that the `jitml-e2e` stanza calls through the
  typed `Subprocess` boundary; the seven doctrine test categories (Pure Logic,
  Parser, Property, Golden, Integration, Daemon Lifecycle, Pulumi-Orchestrated
  Infrastructure) all map to one or more of these stanzas, with the four
  `*-canonicals`/HPO/cross-backend rows being project-specific Integration
  extensions under doctrine §Test Organization → project-specific stanzas, and
  `jitml-purescript-style` a project-specific Lint extension. Owned by
  [phase-12-test-stanzas-and-cross-cluster.md](phase-12-test-stanzas-and-cross-cluster.md).

## Doctrine Scope

[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md) is the authoritative CLI doctrine.
The project [../README.md → Doctrine scope](../README.md#doctrine-scope) declares
which sections are binding and which are informational; this plan inherits that
split verbatim. No sprint may schedule adoption of an out-of-scope section.

**In scope (binding) from `HASKELL_CLI_TOOL.md`, in doctrine order:**

- Overview (toolchain pinning — instantiated by [../README.md → Toolchain
  pinning](../README.md#toolchain-pinning)): GHC `9.14.1`, Cabal `3.16.1.0`.
- Project Structure (library-first; instantiated by [../README.md → Repository
  layout (target)](../README.md#repository-layout-target)): `app/Main.hs` and
  `app/Demo.hs` thin, logic in `src/JitML/`.
- Command Topology — commands as ordinary Haskell ADTs.
- GADT-Indexed State Machines — training lifecycle, RL run lifecycle, tuning sweep
  lifecycle.
- Progressive Introspection — `jitml commands [--tree|--json]`, `jitml help
  <subcommand>`.
- Automatically Generated Documentation.
- Generated Artifacts — paired check/write for the route table, Grafana dashboards,
  protobuf schemas, PureScript contracts, CLI help, markdown docs;
  `GeneratedSectionRule` registry; `trackingGeneratedPaths`.
- Architecture — including Subprocesses as Typed Values: kernel-compiler
  subprocesses (`metal`, `nvcc`, `g++` over oneDNN), `kubectl`, `helm`, `kind`,
  `docker` all wrapped through the typed `Subprocess` boundary with `runStreaming` /
  `capture` as the only IO interpreter; `callProcess`, `readCreateProcess`,
  `System.Process` constructors, and `typed-process` smart constructors are
  forbidden from command runners.
- Plan / Apply — `jitml train`, `jitml tune`, `jitml cluster up`, `jitml test all`,
  `jitml service` startup-as-plan all Plan/Apply commands with `--dry-run` and
  `--plan-file <path>`.
- Output Rules — `--format json|table|plain`, default `table` on TTY else `plain`;
  `--color auto|always|never` / `--no-color`.
- Standard Flag Families — Plan/Apply, Daemon, Output families per
  [../README.md → Standard flag families](../README.md#standard-flag-families).
- Error Handling — single `AppError` ADT with `renderError :: AppError -> Text` as
  the only Text rendering at the CLI boundary; extended with exit code `3` for
  reconciler no-op-on-match per
  [../README.md → Exit codes and error rendering](../README.md#exit-codes-and-error-rendering).
- Capability Classes and Service Errors — `HasMinIO`, `HasPulsar`, `HasHarbor`,
  `HasKubectl`.
- Retry Policy as First-Class Values.
- Prerequisites as Typed Effects — bootstrap scripts' contract is also encoded as
  a typed DAG; one `prerequisiteRegistry` spans every substrate's toolchain, the
  cluster lifecycle, the platform services, and the daemon's startup contract;
  failure emits `AppError PrerequisiteUnmet` carrying the failing `nodeId`,
  description, and remedy hint.
- Application Environment — `ReaderT Env IO` with a single `Env` record threaded
  through command runners.
- **Long-Running Daemons in the Same Binary** — `jitml service` is a real daemon
  with `BootConfig` / `LiveConfig` Dhall, SIGHUP hot reload, `/healthz` / `/readyz`
  / `/metrics`, structured JSON logging on stderr, recoverable-vs-fatal error
  kinds. (Contrast: sibling projects may opt out; jitML opts in.)
- At-Least-Once Event Processing — Pulsar consumer semantics.
- Reconcilers: Idempotent Mutation as a Single Command — `jitml cluster up`,
  `jitml docs generate`, `jitml lint --write`.
- Lint, Format, and Code-Quality Stack — `fourmolu` + `hlint` + `cabal format`;
  pinned `fourmolu.yaml` at repo root with the twelve doctrine-mandated settings;
  the `jitml-haskell-style` stanza enforces all three plus the `cabal format`
  temp-file round-trip byte-equality compare, and `jitml-purescript-style`
  extends the surface to PureScript `purs format` round-trip plus
  `purescript-spec` smoke tests.
- Testing Doctrine.
- Standard Testing Stack — Cabal + `exitcode-stdio-1.0` + tasty + tasty-hunit +
  tasty-quickcheck + tasty-golden + typed-process + temporary + Pulumi + fourmolu
  + hlint + cabal format.
- Test Categories — each of the seven (Pure Logic, Parser, Property, Golden,
  Integration, Daemon Lifecycle, Pulumi-Orchestrated Infrastructure) mapped to a
  `jitml-*` stanza in
  [phase-12-test-stanzas-and-cross-cluster.md](phase-12-test-stanzas-and-cross-cluster.md).
- Test Organization — one `test-suite` stanza per tier; project-specific stanzas
  per [../HASKELL_CLI_TOOL.md → Test Organization →
  project-specific stanzas](../HASKELL_CLI_TOOL.md).

**Out of scope (informational only — no sprint may schedule adoption):**

- Smart Constructors for Paired Resources — no paired infra resources at present;
  if a PV/PVC pattern emerges, this section comes back into scope.
- The Architecture (the doctrine's closing capsule) — informational summary; the
  individual sections it recaps are the binding contract.

**Stack deviations from doctrine:** None at write time. The full doctrine-mandated
standardized library set (including `dhall`, used as the configuration source for
both `BootConfig` / `LiveConfig` and every experiment / sweep / cluster-topology
file) is in scope. The PureScript stack (Halogen, `purescript-bridge`,
`purescript-spec`, Playwright) is a project-specific surface owned by Phase `11`
and is not a doctrine deviation because the doctrine does not address browser-side
code.

## Hard Constraints

The supported architecture closes on the following non-negotiable rules. Numbered
for referenceability. Cross-references to [../README.md](../README.md) name the
authoritative section that pins each constraint.

1. One Haskell CLI binary named `jitml`, plus one bundled HTTP server shim named
   `jitml-demo`. Both are built by Cabal under GHC `9.14.1` and Cabal `3.16.1.0`.
2. Library-first layout per doctrine
   [§Project Structure](../HASKELL_CLI_TOOL.md): `app/Main.hs` and `app/Demo.hs`
   are six-line shims into `App.main`; nearly all logic lives under `src/JitML/`.
3. Three supported substrates: `apple-silicon`, `linux-cpu`, `linux-cuda`. A
   fourth substrate `linux-opencl` (Intel GPU) is admitted as a future extension
   and is not in the current support matrix.
4. One CLI verb for the daemon — `jitml service` — parameterised entirely by its
   Dhall config. There is no separate `host-service` CLI verb. The Dhall declares
   `substrate`, `residency : Cluster | Host`, `inferenceMode : SelfInference |
   ForwardToHost`, and host-side connection info when `residency = Host`.
5. On every substrate the in-cluster `jitml-service` is a stateless `Deployment`,
   not a `StatefulSet`. Pod anti-affinity at `topologyKey:
   kubernetes.io/hostname`. Durable state lives in MinIO and Pulsar exclusively
   (no relational DB on jitML's data path).
6. The CLI never touches `~/.kube/config`. Cluster kubeconfig lives at
   `./.build/jitml.kubeconfig`. The bootstrap scripts forbid touches to
   `~/.kube/config`, `~/.docker/config.json`, the user's global Homebrew prefix as
   a writer, or any global state outside the repo.
7. Every Plan/Apply command supports `--dry-run` (renders the plan and exits 0)
   and `--plan-file <path>` (writes the rendered plan for out-of-band review).
8. `Subprocess` is the only IO boundary for subprocess execution. `kubectl`,
   `helm`, `kind`, `docker`, `metal`, `nvcc`, `g++` (over oneDNN), `tart`, and
   every kernel-compiler invocation goes through the typed boundary.
   `callProcess`, `readCreateProcess`, `System.Process` constructors, and
   `typed-process` smart constructors are hlint-forbidden outside the
   `runStreaming` / `capture` interpreter.
9. One `prerequisiteRegistry` spans every substrate's toolchain, the cluster
   lifecycle, the platform services, and the daemon's startup contract. Failure
   emits `AppError PrerequisiteUnmet` carrying the failing `nodeId`, description,
   and remedy hint, with exit code `2`.
10. Single `AppError` ADT; `renderError :: AppError -> Text` is the only Text
    rendering at the CLI boundary; `print`, `exitFailure`, and direct terminal
    formatting are hlint-forbidden outside `src/JitML/CLI/Output.hs`.
11. Exit codes follow the doctrine plus exit code `3` for reconciler no-op-on-
    match (the resource already matches the desired state; no change applied).
12. `CommandSpec` is the source of truth for the parser, the command tree
    (`jitml commands --tree`), the JSON command schema (`jitml commands --json`),
    the markdown command reference, the manpages, and the shell completion
    scripts. The parser is a renderer of the spec.
13. The route registry `src/JitML/Routes.hs` is the source of truth for every
    HTTPRoute resource emitted by the umbrella chart's renderer. Hand-edited
    HTTPRoute YAML in the chart is hlint-forbidden.
14. The single exposed listener is one `127.0.0.1:<edge-port>` socket on the
    Envoy Gateway; the in-cluster NodePort `30090` backs that listener. The edge
    port is selected starting at `9090` and incremented until available; recorded
    as the `edge_port` field of `./.data/runtime/cluster-publication.json` (the
    single file `cluster up` writes).
15. Storage uses `kubernetes.io/no-provisioner` only — manual PVs against the
    `jitml-manual` StorageClass backed by hostPath under `./.data/kind/<substrate>/`.
16. `./.build/` is the only host folder that holds compiled artifacts; `./.data/`
    is the only host folder that holds runtime state. Both are in `.gitignore`
    and `.dockerignore`.
17. The JIT cache root is `./.build/jit/<substrate>/<hash>.<ext>`; entries are
    content-addressed by `sha256(canonical-cbor(KernelSpec) || kind || substrate
    || toolchain-fingerprint)` where `KernelSpec` is model shape and `kind` is
    `training | inference`. Training and inference kernels are separate
    artifacts.
18. Apple Silicon stable-named symlinks live at `./.build/host/apple-silicon/`
    and resolve into `./.build/jit/apple-silicon/`; the FFI dlopen surface stays
    stable across re-JITs because the symlink is repointed atomically.
19. `./bootstrap/{apple-silicon,linux-cpu,linux-cuda}.sh` are idempotent
    reconcilers under `help | doctor | build | up | status | test | down |
    purge` (Linux adds `push`). The same typed `Prerequisite` DAG that the
    scripts use is consumed in-process by the Haskell daemon.
20. `purge` is destructive but cache-preserving (`./.build/` survives, including
    the JIT cache); `purge --full` additionally removes `./.build/` and, on Linux,
    the substrate image.
21. The substrate image is always `jitml:local`. Substrate is a runtime Dhall
    choice, never an image-name dimension. There is one Dockerfile, one compose
    service, and one image.
22. `jitml service` is a long-running daemon parameterised by Dhall `BootConfig`
    / `LiveConfig`. SIGHUP triggers `LiveConfig` hot reload; restart-required
    fields force a full restart with a structured error. Endpoints `/healthz`,
    `/readyz`, `/metrics` are mandatory. Logging is structured JSON on stderr.
23. The daemon's Pulsar consumer is at-least-once. Idempotency is the consumer's
    responsibility (typed `EventID` deduplication keys). The retry policy is a
    typed value with named retry strategies.
24. Capability classes `HasMinIO`, `HasPulsar`, `HasHarbor`, `HasKubectl` are the
    only allowed entry into external services from the daemon. The runner is
    `ReaderT Env IO`.
25. The Apple Silicon hybrid pattern: clustered Deployment (`Cluster +
    ForwardToHost`) plus host-native binary (`Host + SelfInference`). The
    cluster daemon publishes inference RPC envelopes on
    `inference.command.apple-silicon`; the host daemon ACKs on
    `inference.event.apple-silicon`. Pulsar carries only small envelopes; large
    tensors travel via MinIO. Direct k8s API access from the host is forbidden
    and lint-enforced.
26. The numerical core is fully Dhall-typed: every layer constructor, every
    activation, every optimizer, every scheduler, every loss function has a
    Dhall type and a corresponding Haskell ADT.
27. Per-substrate determinism contract per
    [../documents/engineering/determinism_contract.md](../documents/engineering/determinism_contract.md):
    Metal single-stream launch order; oneDNN blocked reduction with fixed block
    size; CUDA `--use_fast_math=false`, deterministic warp-shuffle reductions,
    cuDNN explicit algorithm-id pinning. Same-substrate equality is guaranteed;
    cross-substrate drift is bounded by the per-tensor tolerance band measured
    by the cross-substrate tolerance methodology.
28. Same-substrate bit-equality means: a transcript or checkpoint produced on
    `<substrate>` is bit-identical when reproduced on the same `<substrate>`
    against the same toolchain pin. Cross-substrate bit-equality is **not**
    guaranteed.
29. The `.jmw1` dense weight blob format is little-endian binary with no schema-
    library dependency. Manifests are typed and content-addressed against MinIO
    bucket `jitml-checkpoints`. Optimizer state (Adam moments, RMSProp
    accumulators) lives in a separate manifest blob keyed by training-run id.
30. The PureScript browser-contract ADTs live in `src/JitML/Web/Contracts.hs`
    and are the source for `purescript-bridge`. `web/src/Generated/Contracts.purs`
    is generated; hand edits fail `jitml lint files` per the
    `trackingGeneratedPaths` registry.
31. `fourmolu.yaml` at repo root pins the twelve doctrine-mandated settings; the
    `jitml-haskell-style` stanza enforces them plus `cabal format` temp-file
    round-trip byte-equality.
32. Ten Cabal test-suite stanzas, each `type: exitcode-stdio-1.0` with `tasty`
    as the in-stanza runner: `jitml-unit`, `jitml-integration`,
    `jitml-sl-canonicals`, `jitml-rl-canonicals`, `jitml-hyperparameter`,
    `jitml-cross-backend`, `jitml-daemon-lifecycle`, `jitml-e2e`,
    `jitml-haskell-style`, `jitml-purescript-style`. A single `tasty` tree
    spanning all tiers is forbidden.
33. The Pulumi TypeScript program at `infra/pulumi/` is the ephemeral-Kind
    orchestrator that the `jitml-e2e` stanza calls through the typed
    `Subprocess` boundary. The Pulumi stack is one of the seven doctrine test
    categories.
34. Report-card knobs are pinned in `cabal.project` and surfaced through `jitml
    test all`. The exact knob list is owned by Sprint `12.9` and recorded in
    [system-components.md](system-components.md).
35. The toolchain is pinned at GHC `9.14.1` and Cabal `3.16.1.0`. `jitml.cabal`
    declares `tested-with: ghc ==9.14.1`; `cabal.project` declares
    `with-compiler: ghc-9.14.1`. Codegen toolchains (LLVM, NVCC, Xcode/Metal,
    oneDNN, `kindest/node`) are pinned in `cabal.project`.

## Dependency Chain

| Phase | Depends On | Why |
|-------|------------|-----|
| 0 | — | Bootstrap |
| 1 | Phase 0 | The CLI surface and lint stack consume the doctrine in-scope/out-of-scope split and the standards rule L doctrine-citation contract |
| 2 | Phase 1 | The bootstrap reconciler, prerequisite DAG, and JIT cache discipline register their CLI surface (`jitml service`, `jitml cluster up`, `--cache-dir`) and their Plan/Apply discipline through the registry built in Phase 1 |
| 3 | Phase 2 | The Kind cluster, Helm umbrella chart, and Envoy Gateway consume the prerequisite DAG (kind, helm, kubectl, docker) and the JIT cache mount (`extraMounts` from `./.build/`) established in Phase 2 |
| 4 | Phase 3 | Harbor, Pulsar, MinIO, PostgreSQL, kube-prometheus-stack, and TensorBoard install through the umbrella chart and route through the Envoy Gateway socket established in Phase 3 |
| 5 | Phase 4 | The `jitml service` daemon subscribes to Pulsar, persists to MinIO via capability classes (`HasMinIO`, `HasPulsar`, `HasHarbor`, `HasKubectl`), pulls images from Harbor, and reports metrics via the Prometheus stack established in Phase 4 |
| 6 | Phase 5 | The numerical core's Dhall types and Haskell ADTs are consumed by the daemon's training and inference loops; the layer catalog precedes the JIT codegen that compiles it |
| 7 | Phase 6 | The per-substrate JIT codegen drivers (Metal, oneDNN, CUDA) consume the typed numerical core from Phase 6 and write into the content-addressed cache established in Phase 2 |
| 8 | Phase 7 | The SL training loops and RL framework primitives compile their kernels through the JIT codegen established in Phase 7 and run on the daemon established in Phase 5 |
| 9 | Phase 8 | The RL algorithm catalog (PPO, A2C, ...), AlphaZero self-play, and hyperparameter tuner consume the framework primitives from Phase 8 |
| 10 | Phase 9 | Checkpointing serialises the trained models from Phases 8/9; the inference-only read path consumes the same wire format and flows back through the daemon |
| 11 | Phase 10 | The PureScript frontend's REST surfaces consume the inference-only read path established in Phase 10; the demo HTTP server (`jitml-demo`) serves the bundle |
| 12 | Phase 11 | The ten Cabal test-suite stanzas exercise every prior phase's surface end-to-end; `jitml-cross-backend` is the closure gate |

## Current Baseline

| Surface | Current Repo State | Intended End State |
|---------|--------------------|--------------------|
| Repository layout | `README.md`, `HASKELL_CLI_TOOL.md`, `AGENTS.md`, `CLAUDE.md`, `LICENSE`. No `app/`, `src/`, `cabal.project`, `*.cabal`, `chart/`, `kind/`, `bootstrap/`, `docker/`, `web/`, `infra/`, `proto/`, `codegen-cuda/`, `codegen-metal/`, `codegen-onednn/`, `experiments/`, `test/`, or generated `documents/cli/commands.md` | Full library-first Haskell layout per [../README.md → Repository layout (target)](../README.md#repository-layout-target) |
| Build artefacts | None | `cabal build all`-produced `jitml` and `jitml-demo` binaries, plus per-substrate JIT-cache artefacts under `./.build/jit/<substrate>/` |
| CLI surface | None | The complete command family parses and runs against three substrates: `service`, `cluster {up,down,status}`, `train`, `tune`, `test`, `lint`, `docs`, `commands`, `help`, `check-code`, `build`, `inspect`, `internal vm exec`, plus the `jitml-demo` HTTP server |
| Test stanzas | None | Ten Cabal stanzas: `jitml-unit`, `jitml-integration`, `jitml-sl-canonicals`, `jitml-rl-canonicals`, `jitml-hyperparameter`, `jitml-cross-backend`, `jitml-daemon-lifecycle`, `jitml-e2e`, `jitml-haskell-style`, `jitml-purescript-style` |
| Toolchain | Project README declares the pins (GHC `9.14.1`, Cabal `3.16.1.0`); no `cabal.project` or `*.cabal` exists yet | GHC `9.14.1`, Cabal `3.16.1.0`, LLVM pinned in `cabal.project`, NVCC pinned, Xcode/Metal pinned, oneDNN pinned, `kindest/node` pinned in `./kind/cluster-<substrate>.yaml` |
| Determinism contract | None | Enforced by the `jitml-integration` (same-substrate bit-equality), `jitml-sl-canonicals`, `jitml-rl-canonicals`, and `jitml-cross-backend` stanzas plus the per-substrate determinism notes in [../documents/engineering/determinism_contract.md](../documents/engineering/determinism_contract.md) |
| Frontend | None | Halogen application under `web/`, generated contracts from `src/JitML/Web/Contracts.hs`, Playwright E2E suite under `web/playwright/`, demo bundle served by `jitml-demo` |

## Related Documents

- [README.md](README.md)
- [development_plan_standards.md](development_plan_standards.md)
- [system-components.md](system-components.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
- [../README.md](../README.md)
