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

`jitml bootstrap --apple-silicon|--linux-cpu|--linux-cuda` is the canonical
full-stack rollout entrypoint. It writes generated Dhall and runtime metadata
under `./.build/`, materializes the per-substrate Kind config from
`./kind/cluster-<substrate>.yaml`, brings up Kind, writes
`./.build/jitml.kubeconfig` (the user's `~/.kube/config` is never touched), brings
Harbor up first, then rolls out every later container through Harbor using the
umbrella chart at `chart/`. The single exposed listener is one
`127.0.0.1:<edge-port>` socket on the Envoy Gateway; every HTTPRoute in the
cluster is rendered from the typed registry in `src/JitML/Routes.hs`.

The numerical core (layer catalog, real+complex activations, optimizers, schedulers,
losses, spectral ops) ships as a local Haskell catalog. The target architecture
keeps per-substrate JIT source renderers in the Haskell binary, consumes the
catalog, generates any compiler input source on demand under
`./.build/jit-src/<substrate>/<hash>/`, and writes compiled artefacts into the
content-addressed cache at `./.build/jit/<substrate>/<hash>.<ext>`, with stable
host-side symlinks at `./.build/host/apple-silicon/` for FFI dlopen stability.
Checked-in `codegen-*` directories are documentation-only; JIT compiler inputs
are rendered by Haskell modules under `src/JitML/Codegen/` and materialized
under `./.build/jit-src/<substrate>/<hash>/`.

The current SL/RL surfaces are local deterministic catalogs and summaries:
canonical SL cells, RL algorithm rows, deterministic trajectory generation,
AlphaZero Connect 4 helpers, and hyperparameter trial sequences. The target
runtime grows these into daemon-backed SL/RL/AlphaZero training loops and
Pulsar/MinIO-backed hyperparameter sweeps.

The current checkpoint surface provides a typed manifest, simplified `.jmw1`
encoder, manifest pointer renderer, and deterministic inference summary. The
current frontend surface provides a minimal PureScript entrypoint plus generated
contract file from `src/JitML/Web/Contracts.hs`; the target runtime adds the
real demo HTTP server, panel implementations, and full checkpoint read path.

`jitml test all --dry-run` renders the aggregate test plan and `jitml test all`
renders the current report-card summary. The target runner invokes every Cabal
test-suite stanza (`jitml-unit`,
`jitml-integration`, `jitml-sl-canonicals`, `jitml-rl-canonicals`,
`jitml-hyperparameter`, `jitml-cross-backend`, `jitml-daemon-lifecycle`,
`jitml-e2e`, `jitml-haskell-style`, `jitml-purescript-style`) with the
report-card knobs pinned in `cabal.project`. The `jitml-e2e` stanza
eventually orchestrates an ephemeral Kind stack via the Pulumi TypeScript
program at `infra/pulumi/`; the current Pulumi program exports stack metadata
only.

## Architecture Overview

- **Haskell CLI surface.** One binary `jitml` plus the `jitml-demo` HTTP server
  shim. The parser is generated from a separate `CommandSpec` registry — never the
  source of truth. The same registry feeds the parser, the command tree (`jitml
  commands --tree`), the JSON command schema (`jitml commands --json`), the markdown
  command reference, the manpages, and the shell completion scripts. Owned by
  [phase-1-haskell-cli-surface.md](phase-1-haskell-cli-surface.md).
- **Bootstrap reconciler, prerequisite DAG, JIT cache.** Three idempotent stage-0
  bootstrap scripts (`bootstrap/{apple-silicon,linux-cpu,linux-cuda}.sh`) perform
  only the minimal host gates needed to reach `jitml bootstrap --<substrate>`.
  Apple verifies macOS on Apple Silicon, Xcode Command Line Tools, and Homebrew,
  builds `./.build/jitml`, then delegates to `jitml bootstrap --apple-silicon`.
  Linux verifies Docker without `sudo`, CUDA additionally verifies the NVIDIA
  container runtime and a qualifying `nvidia-smi` device, then delegates through
  `docker compose run --rm jitml jitml bootstrap --linux-cpu|--linux-cuda`.
  The typed `Prerequisite` DAG consumed by the Haskell bootstrap performs lazy
  package validation/remediation, including Homebrew package installation when
  a resource is actually needed. The content-addressed JIT cache at
  `./.build/jit/<substrate>/<hash>.<ext>` is keyed on `(canonical-cbor(KernelSpec),
  kind, substrate, toolchain-fingerprint, rendered-source-payload, tuning-choice)`;
  on Apple Silicon, stable symlinks under
  `./.build/host/apple-silicon/` give the FFI a stable dlopen surface across
  re-JITs. The lazy-tart pattern keeps the Swift/Metal build VM down until a fresh
  `(model-shape, kind, substrate, toolchain)` tuple appears. Outer-container Linux
  commands run as `docker compose run --rm jitml jitml <command>`; the substrate
  image is `jitml:local`, the outer container is removed after cluster bootstrap,
  and the cluster daemon owns subsequent work. Owned by
  [phase-2-bootstrap-reconciler-and-jit-cache.md](phase-2-bootstrap-reconciler-and-jit-cache.md).
- **Cluster substrate and routing.** Current local renderer surface: per-substrate
  Kind configs at
  `./kind/cluster-<substrate>.yaml`, single control-plane + one worker, NodePort
  30090 backing the edge listener, host `./.build/` bind-mounted into the Kind
  worker via `extraMounts`. Storage uses `kubernetes.io/no-provisioner` only —
  manual PVs against a `jitml-manual` StorageClass backed by hostPath under
  `./.data/<namespace>/<StatefulSet>/pv_<integer>`. `.build` carries kubeconfig,
  generated Dhall, cluster publication, Kind metadata, and JIT artifacts. The
  umbrella Helm chart at `chart/` carries subchart
  dependencies for Harbor, Apache Pulsar, MinIO, Percona PostgreSQL, Envoy Gateway,
  and kube-prometheus-stack, with local TensorBoard/observability renderers. The
  target exposed listener is one
  `127.0.0.1:<edge-port>` Envoy Gateway socket; the typed route registry in
  `src/JitML/Routes.hs` is the source of truth for every HTTPRoute. Current
  commands materialize files locally and do not run Kind/Helm. The CLI never
  touches `~/.kube/config`. Owned by
  [phase-3-cluster-substrate-and-routing.md](phase-3-cluster-substrate-and-routing.md).
- **Stateful platform services.** Current local chart/catalog surface for Harbor as
  the target in-cluster registry against
  dedicated PostgreSQL storage; MinIO buckets `harbor-registry`,
  `jitml-checkpoints`, `jitml-datasets`, `jitml-transcripts`, `jitml-trials`,
  `jitml-tensorboard`, `jitml-artifacts`; Apache Pulsar as the control-plane ↔ data-plane
  bus with topics `inference.command.apple-silicon`,
  `inference.event.apple-silicon` for the host↔cluster RPC, plus
  `inference.request.<mode>` / `inference.result.<mode>` for the demo-facing
  inference flow; Percona Operator-managed PostgreSQL for every packaged service
  that requires Postgres — there is no relational DB on jitML's data path;
  kube-prometheus-stack for metrics scraping
  and Grafana dashboard rendering; TensorBoard deployment/event-key rendering.
  Live service readiness and object-store/event-bus effects remain target
  validation. Owned by
  [phase-4-stateful-platform-services.md](phase-4-stateful-platform-services.md).
- **`jitml service` daemon.** Current local daemon surface: `BootConfig` /
  `LiveConfig` renderers, lifecycle phases, pure endpoint responses, structured
  JSON log rendering, service error/retry helpers, payload-hash deduplication,
  and stateless `Deployment` rendering. A real long-running HTTP/Pulsar daemon,
  SIGHUP handling, and capability classes remain target runtime work. Owned by
  [phase-5-jitml-service-daemon.md](phase-5-jitml-service-daemon.md).
- **Numerical core.** Local Haskell layer catalog (Dense, Conv1D, Conv2D, Conv3D,
  ConvTranspose, BatchNorm, LayerNorm, GroupNorm, Dropout, ResidualBlock,
  MultiHeadAttention, ...), real + complex activations, spectral / frequency-
  domain ops, optimizers (SGD, Momentum SGD, Nesterov SGD, RMSProp, Adagrad,
  Adadelta, Adam, AdamW, LAMB, LARS, Lion), schedulers (constant, linear, cosine,
  cosine-with-warmup, exponential, polynomial, one-cycle, piecewise), loss
  functions (cross-entropy, focal, MSE, Huber, IoU). Dhall mirrors and richer
  parameterized constructors remain target work. Owned by
  [phase-6-numerical-core.md](phase-6-numerical-core.md).
- **JIT codegen and per-substrate execution.** Current `src/JitML/Engines/`
  records backend metadata, determinism flags, and typed compile plans, while
  `src/JitML/Codegen/` renders Metal / Swift, oneDNN C++, and CUDA runtime
  source bundles under `./.build/jit-src/<substrate>/<hash>/`. The real Apple
  hybrid execution path and runtime hardware auto-tuning remain target runtime
  work preserving the determinism contract per
  [../documents/engineering/determinism_contract.md](../documents/engineering/determinism_contract.md):
  Metal single-stream launch order, oneDNN blocked reduction with fixed block
  size, CUDA deterministic warp-shuffle reductions with `--use_fast_math=false` and
  cuDNN explicit algorithm-id pinning. Owned by
  [phase-7-jit-codegen-and-substrates.md](phase-7-jit-codegen-and-substrates.md).
- **Supervised learning and RL framework.** Current local summaries under
  `src/JitML/SL/` and `src/JitML/RL/` provide canonical SL problem curves, RL
  algorithm catalog rows, and deterministic trajectory helpers. Real datasets,
  environments, buffers, callbacks, target networks, GAE, and daemon-backed
  training loops remain target work. Owned by
  [phase-8-supervised-and-rl-framework.md](phase-8-supervised-and-rl-framework.md).
- **RL algorithm catalog, AlphaZero, hyperparameter tuning.** Current local
  catalog covers PPO through AlphaZero as metadata rows, Connect 4 transcript
  helpers, and deterministic tuning trial sequences for Sobol/random/GA/ES ×
  Fifo/SuccessiveHalving/Hyperband/ASHA × none/median/percentile. Real algorithm
  modules, persistent MCTS search, trial storage, and resume remain target work.
  Owned by
  [phase-9-rl-catalog-alphazero-and-tuning.md](phase-9-rl-catalog-alphazero-and-tuning.md).
- **Checkpointing and inference-only read path.** Current local format surface:
  a small typed manifest, simplified `.jmw1` text encoder, manifest pointer, and
  deterministic `inferFromManifest` helper. Full split-blob layout, canonical
  CBOR, MinIO write-once/CAS, retention, and real kernel-handle loading remain
  target work. Owned by
  [phase-10-checkpointing-and-inference.md](phase-10-checkpointing-and-inference.md).
- **PureScript frontend and demo.** Current local surface: minimal PureScript
  entrypoint, generated contract file from `src/JitML/Web/Contracts.hs`,
  `web/test/` smoke file, Playwright scaffold, `jitml-demo` executable shim, and
  demo deployment template. Halogen, `purescript-bridge`, real panels, REST/WS
  handlers, bundle output, and HTTP serving remain target work. Owned by
  [phase-11-purescript-frontend-and-demo.md](phase-11-purescript-frontend-and-demo.md).
- **Test stanzas, lint matrix, cross-cluster parity.** Ten Cabal test-suite
  stanzas, each `type: exitcode-stdio-1.0` with `tasty` as the in-stanza runner:
  `jitml-unit`, `jitml-integration`, `jitml-sl-canonicals`,
  `jitml-rl-canonicals`, `jitml-hyperparameter`, `jitml-cross-backend`,
  `jitml-daemon-lifecycle`, `jitml-e2e`, `jitml-haskell-style`,
  `jitml-purescript-style`. Current `jitml test all` renders the Plan/Apply
  test plan or report-card summary; the target runner delegates to `cabal test`.
  The current Pulumi TypeScript program at `infra/pulumi/` exports metadata; the
  target e2e program becomes the ephemeral-Kind orchestrator that the
  `jitml-e2e` stanza calls through the typed `Subprocess` boundary. The seven
  doctrine test categories (Pure Logic,
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
- Plan / Apply — `jitml bootstrap`, `jitml train`, `jitml tune`,
  `jitml rl train`, `jitml cluster up`, `jitml test all`, `jitml service`
  startup-as-plan, and `jitml internal gc` all Plan/Apply commands with `--dry-run` and
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
- Prerequisites as Typed Effects — stage-0 scripts only check the host gates
  required to reach `jitml bootstrap`; one `prerequisiteRegistry` spans every
  substrate's toolchain, lazy package remediation, the cluster lifecycle, the
  platform services, and the daemon's startup contract; failure emits
  `AppError PrerequisiteUnmet` carrying the failing `nodeId`, description, and
  remedy hint.
- Application Environment — `ReaderT Env IO` with a single `Env` record threaded
  through command runners.
- **Long-Running Daemons in the Same Binary** — `jitml service` is a real daemon
  with `BootConfig` / `LiveConfig` Dhall, SIGHUP hot reload, `/healthz` / `/readyz`
  / `/metrics`, structured JSON logging on stderr, recoverable-vs-fatal error
  kinds. (Contrast: sibling projects may opt out; jitML opts in.)
- At-Least-Once Event Processing — Pulsar consumer semantics.
- Reconcilers: Idempotent Mutation as a Single Command — `jitml bootstrap`,
  `jitml cluster up`, `jitml docs generate`, `jitml lint --write`,
  `jitml internal gc`.
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

**Stack deviations from doctrine:** None for the in-scope Haskell CLI doctrine
surface at write time. The full doctrine-mandated
standardized library set (including `dhall`, used as the configuration source for
both `BootConfig` / `LiveConfig` and every experiment / sweep / cluster-topology
file) is in scope. The PureScript stack (Halogen, `purescript-bridge`,
`purescript-spec`, Playwright) is a project-specific target owned by Phase `11`
and is not a doctrine deviation because the doctrine does not address browser-side
code; the current worktree implements only the minimal PureScript shell, generated
contract file, and Playwright scaffold.

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
   `./.build/jitml.kubeconfig`. Stage-0 bootstrap scripts never write
   `~/.kube/config`, `~/.docker/config.json`, the user's Homebrew prefix, or any
   global state outside the repo. Haskell `jitml` may install Homebrew packages
   lazily through typed prerequisite remediation, with pure plan construction,
   typed `Subprocess` apply, and postcondition validation.
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
12. `CommandSpec` is the implementation source for the parser, the command tree
    (`jitml commands --tree`), the JSON command schema (`jitml commands --json`),
    the markdown command reference, the manpages, and the shell completion
    scripts. The parser is a renderer of the spec.
13. The route registry `src/JitML/Routes.hs` is the source of truth for every
    HTTPRoute resource emitted by the umbrella chart's renderer. Hand-edited
    HTTPRoute YAML in the chart is hlint-forbidden.
14. The single exposed listener is one `127.0.0.1:<edge-port>` socket on the
    Envoy Gateway; the in-cluster NodePort `30090` backs that listener. The edge
    port is selected starting at `9090` and incremented until available; recorded
    as the `edge_port` field of `./.build/runtime/cluster-publication.json` (the
    single file bootstrap writes).
15. Storage uses `kubernetes.io/no-provisioner` only — manual PVs against the
    `jitml-manual` StorageClass backed by hostPath under
    `./.data/<namespace>/<StatefulSet>/pv_<integer>`.
16. `./.build/` is the host root for compiled artifacts, generated Dhall,
    kubeconfig, Kind metadata, cluster publication, and JIT cache entries.
    `./.data/` is strictly for manual PV bind mounts. Both are in `.gitignore`
    and `.dockerignore`.
17. The JIT cache root is `./.build/jit/<substrate>/<hash>.<ext>`; entries are
    content-addressed by `sha256(canonical-cbor(KernelSpec) || kind || substrate
    || toolchain-fingerprint || rendered-source-payload || tuning-choice)` where
    `KernelSpec` is model shape and `kind` is `training | inference`. Training
    and inference kernels are separate artifacts.
18. Apple Silicon stable-named symlinks live at `./.build/host/apple-silicon/`
    and resolve into `./.build/jit/apple-silicon/`; the FFI dlopen surface stays
    stable across re-JITs because the symlink is repointed atomically.
19. `./bootstrap/{apple-silicon,linux-cpu,linux-cuda}.sh` are idempotent stage-0
    entrypoints. Apple checks macOS/arm64, Xcode Command Line Tools, and
    Homebrew, builds `./.build/jitml`, then calls
    `jitml bootstrap --apple-silicon`. Linux checks Docker without `sudo`; CUDA
    additionally checks NVIDIA runtime and device compute capability; both call
    `docker compose run --rm jitml jitml bootstrap --linux-cpu|--linux-cuda`.
    The typed `Prerequisite` DAG is consumed in-process by the Haskell bootstrap.
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
    responsibility: handlers derive deduplication keys from the protobuf message
    hash and do not trust client-supplied IDs. The retry policy is a typed value
    with named retry strategies.
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
28. Target JIT compiler inputs are generated by the Haskell `jitml` binary on a
    cache miss. The repository does not use static checked-in `.cu`, `.cc` /
    `.cpp`, Metal / Swift package source files, or per-substrate JIT build
    `.sh` scripts as build inputs. The Haskell renderers emit those files into
    `./.build/jit-src/<substrate>/<hash>/` and invoke `nvcc`, the oneDNN C++
    compiler path, or `swift build` through the typed `Subprocess` boundary.
29. Same-substrate bit-equality means: a transcript or checkpoint produced on
    `<substrate>` is bit-identical when reproduced on the same `<substrate>`
    against the same toolchain pin. Cross-substrate bit-equality is **not**
    guaranteed.
30. The `.jmw1` dense weight blob format is magic bytes, `header_len`, a
    canonical-CBOR `JmwHeader`, and packed little-endian tensor payload bytes.
    Manifests are typed and content-addressed against MinIO bucket
    `jitml-checkpoints`. Optimizer state (Adam moments, RMSProp accumulators)
    lives as a separate checkpoint part.
31. The PureScript browser-contract ADTs live in `src/JitML/Web/Contracts.hs`.
    The current worktree uses a local renderer for
    `web/src/Generated/Contracts.purs`; the target generator is
    `purescript-bridge`. Active `trackingGeneratedPaths` protection for the
    generated contract file remains target work; today the path is still listed
    under `futureTrackingGeneratedPathPatterns`.
32. `fourmolu.yaml` at repo root pins the twelve doctrine-mandated settings; the
    `jitml-haskell-style` stanza enforces them plus `cabal format` temp-file
    round-trip byte-equality.
33. Ten Cabal test-suite stanzas, each `type: exitcode-stdio-1.0` with `tasty`
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
| 2 | Phase 1 | The stage-0 bootstrap entrypoints, Haskell `jitml bootstrap --<substrate>` reconciler, prerequisite DAG, and JIT cache discipline register their CLI surface (`jitml bootstrap`, `jitml service`, `jitml cluster up`, `--cache-dir`) and their Plan/Apply discipline through the registry built in Phase 1 |
| 3 | Phase 2 | The Kind cluster, Helm umbrella chart, and Envoy Gateway consume the prerequisite DAG (kind, helm, kubectl, docker) and the JIT cache mount (`extraMounts` from `./.build/`) established in Phase 2 |
| 4 | Phase 3 | Harbor, Pulsar, MinIO, PostgreSQL, kube-prometheus-stack, and TensorBoard install through the umbrella chart and route through the Envoy Gateway socket established in Phase 3 |
| 5 | Phase 4 | The `jitml service` daemon subscribes to Pulsar, persists to MinIO via capability classes (`HasMinIO`, `HasPulsar`, `HasHarbor`, `HasKubectl`), pulls images from Harbor, and reports metrics via the Prometheus stack established in Phase 4 |
| 6 | Phase 5 | The numerical core's Dhall types and Haskell ADTs are consumed by the daemon's training and inference loops; the layer catalog precedes the JIT codegen that compiles it |
| 7 | Phase 6 | The per-substrate Haskell JIT source renderers (Metal / Swift, oneDNN C++, CUDA) consume the typed numerical core from Phase 6, generate compiler inputs under `./.build/jit-src/<substrate>/<hash>/`, and write compiled artefacts into the content-addressed cache established in Phase 2 |
| 8 | Phase 7 | The SL training loops and RL framework primitives compile their kernels through the JIT codegen established in Phase 7 and run on the daemon established in Phase 5 |
| 9 | Phase 8 | The RL algorithm catalog (PPO, A2C, ...), AlphaZero self-play, and hyperparameter tuner consume the framework primitives from Phase 8 |
| 10 | Phase 9 | Checkpointing serialises the trained models from Phases 8/9; the inference-only read path consumes the same wire format and flows back through the daemon |
| 11 | Phase 10 | The target PureScript frontend REST surfaces consume the inference-only read path established in Phase 10; current Phase `11` owns the minimal frontend/contract/demo shim scaffold before the real demo HTTP server serves the bundle |
| 12 | Phase 11 | The ten Cabal test-suite stanzas exercise every prior phase's surface end-to-end; `jitml-cross-backend` is the closure gate |

## Status Vocabulary

| Status | Meaning | Emoji |
|--------|---------|-------|
| **Done** | Deliverables implemented for the sprint-owned surface, validated, and aligned in docs | ✅ |
| **Active** | Work has started and remaining implementation or documentation work is explicitly listed | 🔄 |
| **Planned** | Ready to start once execution reaches the sprint in sequence | 📋 |
| **Blocked** | Closure depends on an unmet prerequisite or prior sprint closure | ⏸️ |

## Current Baseline

Phases `0` through `12` are closed on their owned local surfaces. Phase `1`
includes the external lint/format/build runners and isolated style-tool GHC
bootstrap; Phase `7` includes Haskell-rendered runtime source under
`./.build/jit-src/<substrate>/<hash>/` and removal of static checked-in JIT
source/build inputs from the build path. Done status is scoped to checked-in
local renderers, catalogs, command summaries, contracts, runtime-source plans,
and test bodies. The overall handoff remains incomplete until the live-cluster
validation chain closes.

| Surface | Current Repo State | Intended End State |
|---------|--------------------|--------------------|
| Repository layout | Sprints `1.1` through `12.9` have landed the library-first Haskell CLI, AppError, cache, docs, env, lint, plan, subprocess, prerequisite, bootstrap, Tart, route, cluster-renderer, service-config, numerical-catalog, engine, runtime-source, SL/RL/tuning, checkpoint, web-contract, and report modules; stage-0 scripts; generated CLI docs; `docker/`, `chart/`, `kind/`, `dhall/`, `web/`, `infra/`, `proto/`, documentation-only `codegen-cuda/`, `codegen-metal/`, `codegen-onednn/`, and `experiments/` surfaces; and dedicated test bodies for every Cabal stanza | Full library-first Haskell layout with Haskell-owned runtime JIT source generation per [../README.md → Repository layout (target)](../README.md#repository-layout-target) |
| Build artefacts | The Cabal package declares `jitml` and `jitml-demo`; `bootstrap/apple-silicon.sh build` targets `./.build/jitml`; the typed JIT cache key/layout/manifest/symlink layer is implemented; `jitml build --dry-run --substrate <substrate>` renders generated-source compile plans under `./.build/jit-src/<substrate>/<hash>/` | `cabal build all`-produced `jitml` and `jitml-demo` binaries, generated JIT compiler inputs under `./.build/jit-src/<substrate>/<hash>/`, plus per-substrate JIT-cache artefacts under `./.build/jit/<substrate>/` |
| CLI surface | The full command family is registered and parseable from `CommandSpec`; the implemented commands now cover bootstrap materialization, doctor/remediation, commands/help, docs, lint/check-code, Plan/Apply dry-runs, env resolution, AppError rendering, cluster status/up/down/reset summaries, service dry-run/surface rendering, train/eval/tune/RL/inference deterministic local summaries, test report rendering, internal substrate materialization, VM subprocess rendering, generated-source build-plan rendering, and cache stubs. The lint stack enforces config presence, whitespace normalization, forbidden paths, generated-doc drift, chart-shape checks, forbidden subprocess/terminal primitives, static JIT source/build artefact rejection, external `fourmolu`, `hlint`, `cabal format`, and warning-clean build execution. Live Kind/Helm mutation remains an overall validation follow-up after the local phase surfaces | The complete command family parses and runs against three substrates: `doctor`, `cluster {up,down,status,reset}`, `service`, `train`, `eval`, `tune`, `rl {train,eval,rollout}`, `verify {same-run,cross-backend,replay}`, `inspect {list,show,replay,trial,frontier}`, `bench {train,inference,env}`, `inference run`, `test`, `lint`, `docs`, `check-code`, `build`, `kubectl`, `internal {materialize-substrate,list-prereqs,gc,vm,cache}`, `commands`, `help`, plus the `jitml-demo` HTTP server |
| Test stanzas | Ten Cabal stanzas are declared with dedicated deterministic local bodies; `jitml-unit` covers current CLI/docs/prerequisite/env/cache surfaces, `jitml-integration` covers subprocess/bootstrap/renderers, and the SL/RL/hyperparameter/cross-backend/daemon/e2e/PureScript stanzas exercise local scaffold invariants | Ten Cabal stanzas: `jitml-unit`, `jitml-integration`, `jitml-sl-canonicals`, `jitml-rl-canonicals`, `jitml-hyperparameter`, `jitml-cross-backend`, `jitml-daemon-lifecycle`, `jitml-e2e`, `jitml-haskell-style`, `jitml-purescript-style` |
| Toolchain | `jitml.cabal` pins `tested-with: ghc ==9.14.1`; `cabal.project` pins `with-compiler: ghc-9.14.1`, records the codegen-toolchain comments and report-card knobs, carries a ledger-tracked scoped `allow-newer` for Dhall/CBOR package bounds under GHC `9.14.1`, and `jitml doctor --scope toolchain` validates the Sprint `2.2` host toolchain prerequisites after typed remediation | GHC `9.14.1`, Cabal `3.16.1.0`, LLVM pinned in `cabal.project`, NVCC pinned, Xcode/Metal pinned, oneDNN pinned, `kindest/node` pinned in `./kind/cluster-<substrate>.yaml` |
| Determinism contract | Local deterministic SL curves, RL trajectories, tuning trials, checkpoint inference, and engine flags are covered by dedicated Cabal stanzas; live substrate equality remains owned by later phase validation | Enforced by the `jitml-integration` (same-substrate bit-equality), `jitml-sl-canonicals`, `jitml-rl-canonicals`, and `jitml-cross-backend` stanzas plus the per-substrate determinism notes in [../documents/engineering/determinism_contract.md](../documents/engineering/determinism_contract.md) |
| Frontend | `web/` contains the PureScript shell and generated browser contracts from `src/JitML/Web/Contracts.hs`; Playwright and Pulumi scaffolds are present for later live E2E validation | PureScript shell under `web/`, generated contracts from `src/JitML/Web/Contracts.hs`, Playwright scaffold under `playwright/`, demo surface served by `jitml-demo` |

## Related Documents

- [README.md](README.md)
- [development_plan_standards.md](development_plan_standards.md)
- [system-components.md](system-components.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
- [../README.md](../README.md)
