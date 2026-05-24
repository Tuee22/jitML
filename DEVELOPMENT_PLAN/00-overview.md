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
[../README.md](../README.md), [../README.md](../README.md)
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
serves the PureScript frontend bundle. The CLI is library-first per
[project structure doctrine](../README.md#repository-layout-target):
`app/Main.hs` is a six-line shim into
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
`./kind/cluster-<substrate>.yaml`, brings up Kind, writes/exports Kind's
kubeconfig through an in-container temporary file, copies it to
`./.build/jitml.kubeconfig` (the user's `~/.kube/config` is never touched), brings
MinIO and the registered `harbor-pg` database up first, then brings Harbor up
against those dependencies, builds `jitml:local` / `jitml-demo:local`, loads
those tags explicitly into Kind, and rolls out the remaining services using the
umbrella chart at `chart/`. The single exposed listener is one
`127.0.0.1:<edge-port>` socket on the Envoy Gateway; every HTTPRoute in the
cluster is rendered from the typed registry in `src/JitML/Routes.hs`.

The numerical core (layer catalog, real+complex activations, optimizers,
schedulers, losses, spectral ops) ships as a Haskell catalog with a Dhall
mirror, consumed by per-substrate JIT source renderers in the Haskell binary
that generate compiler input source on demand under
`./.build/jit-src/<substrate>/<hash>/` and write compiled artefacts into the
content-addressed cache at `./.build/jit/<substrate>/<hash>.<ext>`, with
stable host-side symlinks at `./.build/host/apple-silicon/` for FFI dlopen
stability. The Linux CPU identity, reduction-smoke, and family-scaffold paths
compile, load, execute, and report their exported `jitml_kernel_family_name`
and `jitml_kernel_output_count` through the Haskell FFI today; their local
toolchain fingerprint includes `artifact-abi=<os>-<arch>` and
`reduction-block=256` so host/container artifacts and fixed reduction-block
changes do not collide in the shared cache. `JitML.Engines.OneDnnRuntime`
probes `pkg-config` package metadata and dynamic-linker `libdnnl` visibility
through typed subprocesses for the future production graph path. Real oneDNN graph
kernels, Apple Metal loading, and Linux CUDA loading are owned by Phase `7`'s
Active sprints.

The SL/RL surfaces ship today as deterministic catalogs and summaries:
canonical SL cells, RL algorithm rows, deterministic trajectory generation,
AlphaZero Connect 4 helpers, text command-envelope parsers for the current
training/RL/tuning proto mirrors, and hyperparameter trial sequences. Real
daemon-backed SL/RL/AlphaZero training loops, real env stepping, real
checkpoint persistence, and Pulsar/MinIO-backed hyperparameter sweeps are
owned by Phase `8` and Phase `9`'s Active sprints.
The checked-in `experiments/mnist-tune.dhall` file carries the
`Some Tuning::{ ... }` fixture using a TPE sampler; the current Haskell catalog
in `src/JitML/Tune/Catalog.hs` includes the full target sampler set (`Grid`,
`Sobol`, `Random`, `TPE`, `GPBO`, `GeneticAlgorithm`, `NSGA2`, `MuLambdaES`,
`CMAES`, `EvolutionStrategies`, and `PBT`), and `jitml tune` decodes that
fixture into the local tuning ADT before rendering its deterministic plan.
`JitML.Proto.Tune` now covers the current tune command and event oneofs with
proto3-compatible byte round-trips; generated proto-lens interop remains target
work.

The checkpoint surface provides a typed manifest, split-blob object-key
renderers, pointer-CAS decisions, the binary `.jmw1` encoder/decoder, manifest
pointer renderer, a filesystem-backed checkpoint store,
`writeCheckpointSnapshotWithMinIO` over the `HasMinIO` conditional-write/CAS
boundary, decoded weight loading for the local Linux CPU generated-kernel
smoke path, and deterministic inference from the latest checkpoint. The live HTTP
MinIO capability path is implemented by `JitML.Service.MinIOSubprocess` and
validated against the routed `/minio/s3` edge for write-once conflicts, pointer
CAS conflicts, read, list, and delete. The frontend surface provides a
minimal PureScript entrypoint, generated contract file from
`src/JitML/Web/Contracts.hs`, typed bundle/panel/demo-route metadata from
`src/JitML/Web/Bundle.hs`, and the `jitml-demo` HTTP server in
`src/JitML/Web/Server.hs`; the typed demo route manifest covers the full
current local API route family. Checkpoint-store validation through the live MinIO
client, real kernel-handle loading, and the compiled Halogen bundle + live
WebSocket proxy are owned by Phase `10` and Phase `11`'s Active sprints.

`jitml test all --dry-run` renders the aggregate test plan and non-dry-run
`jitml test all` invokes every test-only Cabal test-suite stanza (`jitml-unit`,
`jitml-integration`, `jitml-sl-canonicals`, `jitml-rl-canonicals`,
`jitml-hyperparameter`, `jitml-cross-backend`, `jitml-daemon-lifecycle`,
`jitml-e2e`) through the typed `Subprocess` boundary before printing the
report-card summary. Style and code-quality gates run separately through
`jitml lint *` and `jitml check-code`. The
report-card knobs are pinned in `cabal.project`. The `jitml-e2e` stanza's
default body validates the typed live plan and inline DOM scaffold, while the
Pulumi + Kind + Helm live orchestrator remains Sprint `12.8` work.

Haskell style and code-quality execution is container-exclusive. The
`jitml:local` image is required on every substrate, including Apple Silicon for
the in-cluster daemon, so the Dockerfile owns the separate style-tools GHC plus
pinned `fourmolu` / `hlint` binaries and runs the Haskell style/code-quality
gate during image construction. Runtime lint/check-code commands run inside that
image or fail before linting; they never install, discover, or override host
style tools.

## Execution Roadmap

The dependency-ordered execution roadmap for the remaining Exit-Definition
obligations lives in [README.md → Execution Roadmap](README.md#execution-roadmap).
Each item there links to the owning sprint's `### Remaining Work` block,
where the validation gate lives. The roadmap closes when every Active phase
moves to Done and the legacy ledger is empty.

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
- **Cluster substrate and routing.** Per-substrate Kind configs at
  `./kind/cluster-<substrate>.yaml` (single-node `control-plane` topology with
  no separate worker, NodePort 30090 backing the edge listener, host
  `./.build/` bind-mounted into the Kind node via `extraMounts`); storage uses
  `kubernetes.io/no-provisioner` only — manual PVs against a
  `jitml-manual` StorageClass backed by hostPath under
  `./.data/<namespace>/<StatefulSet>/pv_<integer>`. The umbrella Helm
  chart at `chart/` carries subchart dependencies for Harbor, Apache
  Pulsar, MinIO, Percona PostgreSQL, Envoy Gateway, and
  kube-prometheus-stack, plus TensorBoard/observability renderers. The
  exposed listener is one `127.0.0.1:<edge-port>` Envoy Gateway socket;
  the typed route registry in `src/JitML/Routes.hs` is the source of
  truth for every HTTPRoute. The CLI never touches `~/.kube/config`.
  The explicit live bootstrap path now sequences typed Kind, Helm, Docker
  build / Kind image-load, repo-owned manifest apply, and Pulsar-topic
  subprocesses, writes the leased-port publication with Helm-status-derived
  component health, patches Apple host Dhall, serves `/api` through the single
  Envoy localhost socket, and tears the Kind cluster down through
  `jitml cluster down`. The renderer targets the single-node Kind shape, and
  2026-05-23 live Linux CPU validation proves bootstrap, Docker build / Kind
  image-load, ready publication health, `/api` through Envoy, and teardown on
  that topology.
  Phase: [phase-3-cluster-substrate-and-routing.md](phase-3-cluster-substrate-and-routing.md).
- **Stateful platform services.** Harbor as the in-cluster registry
  against dedicated PostgreSQL storage, with explicit Harbor registry/token
  edge routes and `JitML.Service.HarborSubprocess` settings for Docker/curl
  capability calls; MinIO buckets `harbor-registry`,
  `jitml-checkpoints`, `jitml-datasets`, `jitml-transcripts`,
  `jitml-trials`, `jitml-tensorboard`, `jitml-artifacts` validated through
  the typed in-pod `mc` readiness subprocess; live `harbor-pg`
  PerconaPGCluster readiness with manual `volumeName`-bound PVs; 2026-05-19
  live registry-API validation proving Harbor starts against that external
  database and writes registry objects into MinIO's `harbor-registry` S3
  bucket; 2026-05-19 live `JitML.Service.MinIOSubprocess` validation proving
  routed MinIO `If-None-Match` / `If-Match` conflicts map to `SEConflict` and
  read/list/delete works through `/minio/s3`; Apache Pulsar
  as the control-plane ↔ data-plane bus with topics
  `inference.command.apple-silicon` and `inference.event.apple-silicon`
  for the host↔cluster RPC plus typed Apple command/event envelopes in
  `JitML.Proto.Inference` plus the local `JitML.Service.AppleInferenceRpc`
  planning/correlation boundary, and `inference.request.<mode>` /
  `inference.result.<mode>` for the demo-facing inference flow; 2026-05-19
  live validation proving `/pulsar/admin` works through the edge,
  `/pulsar/ws` targets `pulsar-broker:8080` with
  `webSocketServiceEnabled=true`, the full typed substrate-scoped topic family
  exists, 2026-05-20 live validation proving the current 26-topic family is
  registered and `training.command.linux-cpu` publishes/consumes through the
  `jitml:local` WebSocket path, and
  `JitML.Service.PulsarWebSocketSubprocess` publishes and consumes through the
  routed WebSocket endpoint; Percona
  Operator-managed PostgreSQL for every packaged service that requires
  Postgres (jitML itself has no relational DB on its data path);
  kube-prometheus-stack with live-validated `/grafana` dashboard serving and
  `/prometheus` scraping of `jitml-service` `/metrics`; TensorBoard
  deployment/shard-key rendering, Haskell scalar-event writing, checkpoint
  sidecar dispatch, routed scalars API readback, and Linux CUDA
  RuntimeClass GPU visibility. Phase:
  [phase-4-stateful-platform-services.md](phase-4-stateful-platform-services.md).
- **`jitml service` daemon.** `BootConfig` / `LiveConfig` renderers,
  lifecycle phases, endpoint responses, structured JSON log rendering,
  service error/retry helpers, payload-hash deduplication, SIGHUP reload
  decisions, capability-class boundaries, stateless `Deployment`
  rendering, POSIX signal/control wiring, graceful-drain readiness,
  `DaemonClientSettings` derivation from loaded `BootConfig` plus the
  combined `DaemonServiceClient` interpreter,
  BootConfig-derived daemon Pulsar subscription planning rendered under
  `pulsar_subscriptions`, startup subscription acquisition rendered under
  `pulsar_subscription_status` after the routed WebSocket subscribe probe,
  read-only daemon client probes rendered under `client_probe_status`,
  typed mutating workload effects for MinIO write/CAS, Harbor promotion,
  kubectl apply/status/delete, and RunInference plus byte-faithful parsed daemon
  dispatcher routing,
  bounded acquired-subscription consumer batching exposed by
  `jitml service --consume-once <n>`, post-dispatch WebSocket ack command
  rendering, normal `jitml service` held-open background consumer workers
  sharing one process-lifetime handler router, LiveConfig-derived dedup
  cache sizing for the handler router,
  fully-qualified broker topic routing, required
  anti-affinity rendered for one service pod per node, and the in-binary HTTP
  listener. The standalone live MinIO
  capability client and one-shot plus held-open Pulsar WebSocket paths are validated;
  2026-05-21 live Linux CPU service-pod validation runs
  `jitml service --consume-once 1`, dispatches Training/RL/Tune/Inference
  messages before ack, applies Training/RL/Tune Jobs, routes
  `WriteCheckpointBlob` workload effects into MinIO,
  `PromoteWorkloadImage` workload effects into Harbor same-repository tag
  promotion, and handles `RunInference` through MinIO checkpoint reads plus
  Pulsar `InferenceResult` publication; 2026-05-21 live Linux CPU validation
  also proves normal service held-open-worker `RunInference` flow without
  `--consume-once`; 2026-05-21 live Linux CPU validation proves duplicate
  payload dedup through the held-open worker path and dispatch-failure
  negative-ack redelivery after a checkpoint is seeded; 2026-05-21 live Linux
  CUDA service-pod validation now targets the actual `jitml-service` pod with
  `runtimeClassName: nvidia` on the GPU-labelled single Kind node; 2026-05-21
  live Apple Silicon host validation runs the generated
  `./.build/conf/host/apple-silicon.dhall` through
  `jitml service --consume-once 0`, passes routed MinIO / Harbor / kubectl
  probes, and acquires `inference.command.apple-silicon` as `jitml-host`.
  Phase:
  [phase-5-jitml-service-daemon.md](phase-5-jitml-service-daemon.md).
- **Numerical core.** Haskell layer catalog (16 constructors: Dense,
  Embedding, Conv1D, Conv2D, Conv3D, ConvTranspose, ComplexDense,
  ComplexConv2D, BatchNorm, LayerNorm, GroupNorm, Dropout, ResidualBlock,
  ScaledDotProductAttention, MultiHeadAttention,
  RotaryPositionalEmbedding); 8 real activations (Relu, LeakyRelu, Elu,
  Silu, Gelu, Tanh, Sigmoid, Softmax) plus 3 complex activations
  (ComplexModRelu, ComplexCardioid, ComplexZRelu); 10 spectral /
  frequency-domain ops (FFT, FFTAlongAxis, IFFT, IFFTAlongAxis, RFFT,
  IRFFT, STFT, DCT, ComplexConjugate, ComplexMatMul); 13 optimizers
  (SGD, MomentumSGD, NesterovSGD, RMSProp, Adagrad, Adadelta, Adam,
  AdamW, LAMB, LARS, Lion, AdaFactor, Shampoo); 9 schedulers
  (Constant, Linear, Cosine, CosineWithWarmup, Exponential, Polynomial,
  OneCycle, Piecewise, ReduceOnPlateau); 10 loss functions
  (CrossEntropy, BinaryCrossEntropy, SparseCrossEntropy, Focal, MSE,
  Huber, IoU, Dice, KLDiv, Contrastive); Dhall mirror lists; and the
  cross-type lint audit. Owned by
  [phase-6-numerical-core.md](phase-6-numerical-core.md).
- **JIT codegen and per-substrate execution.** `src/JitML/Engines/`
  records backend metadata, determinism flags, typed kernel handles,
  cache hit/miss decisions, engine envelopes, and typed compile plans;
  `src/JitML/Codegen/` renders Metal / Swift, oneDNN C++, and CUDA
  runtime source bundles under
  `./.build/jit-src/<substrate>/<hash>/`. `JitML.Codegen.KernelFamily`
  defines the typed `KernelFamily` ADT (`identity`, `reduction`,
  `dense`, `conv2d`, `conv3d`, `batchnorm`, `layernorm`, `mha`,
  `embedding`) consumed by the family-aware renderers
  (`renderOneDnnFamilySource`, `renderCudaFamilySource`,
  `renderMetalFamilyPackage`). `JitML.Engines.Tuning` declares the
  per-substrate `KnobSpace` (matmul tile / block-dim / cuDNN
  deterministic algorithm pin / threadgroup size / micro-kernel /
  reduction strategy / no-TF32 / no-fast-math) with
  `selectDeterministic` choosing the deterministic default and
  `tuningChoiceForResult` emitting the cache-key payload; `benchmarkPlan`
  enumerates deterministic-only candidates in stable order, and
  `selectMeasuredTuning` ranks a fixed measurement set by lowest latency with
  stable plan-order tie-breaking. `JitML.Engines.TuningStore` persists a
  selected measured `TuningChoice` under `jit/tuning/<substrate>/<base-hash>.json`
  and `JitML.Engines.TuningBenchmark` collects candidate measurements in plan
  order with SHA-256 output digests for the future first-cache-miss hardware
  benchmark loop, while its CUDA/Metal runner entrypoints preflight runtime
  availability and fail closed before live FFI execution exists.
  `JitML.Engines.TuningCache` loads that persisted choice to
  derive the final
  runtime source and cache key.
  `JitML.Engines.Loader` owns cache-hit/cache-miss artifact materialization and
  compile-on-miss for the local Linux CPU FFI path, while
  `JitML.Engines.Local` loads and runs the generated Linux CPU identity kernel,
  reduction smoke kernel, and every family scaffold through the Haskell FFI,
  validating the exported family-name and output-count symbols from each loaded
  artifact, while `JitML.Engines.OneDnnRuntime` owns the typed `libdnnl`
  package/link visibility probe for future graph bindings. Generated CUDA and
  Swift/Metal source now exports the same family/output-count metadata contract
  for future non-local FFI loaders, and `JitML.Engines.CudaRuntime` owns the
  host-side CUDA reduction partial-count/finalization helper plus the typed
  `nvcc` / `nvidia-smi` / `ldconfig` CUDA runtime probe.
  `JitML.Engines.MetalRuntime` owns the corresponding host Metal runtime probe
  for Swift, `xcrun`, and Metal device visibility before the future host FFI
  launcher.
  `JitML.Tart.Build` renders and executes the Apple first-cache-miss lifecycle
  plan from `jitml-build` VM status/run/readiness validation through Swift
  package build, cache-artifact publication, and host-stable symlink repointing;
  its typed executor boundary still validates ordered success and failure
  short-circuiting with a synthetic executor, and `jitml internal vm
  bootstrap|up|down|status` now dispatches through live Tart lifecycle helpers
  for clone/status/start/stop operations.
  Real oneDNN graph
  kernels, provisioned Apple `jitml-build` VM live validation + Metal loading,
  Linux CUDA loading, and live benchmark-driven hardware auto-tuning are owned
  by Sprints `7.3` /
  `7.4` / `7.5` / `7.6`'s Remaining Work, preserving the determinism
  contract per
  [../documents/engineering/determinism_contract.md](../documents/engineering/determinism_contract.md):
  Metal single-stream launch order, oneDNN blocked reduction with fixed
  block size, CUDA deterministic warp-shuffle reductions with no device-side
  atomics plus host canonical partial finalization, `--use_fast_math=false`,
  and cuDNN explicit algorithm-id pinning.
  Phase:
  [phase-7-jit-codegen-and-substrates.md](phase-7-jit-codegen-and-substrates.md).
- **Supervised learning and RL framework.** `src/JitML/SL/` and
  `src/JitML/RL/` provide canonical SL problem curves, the typed
  dataset registry (`SL.Dataset.canonicalDatasets`), the deterministic
  SL training pipeline (`SL.Loop.runDeterministicLoop`,
  `SL.Train.train`), the RL algorithm catalog rows, canonical RL
  environment metadata, framework run-plan metadata, deterministic
  trajectory helpers, the three GADT-indexed lifecycles
  (`TrainingLifecycle`, `RLRunLifecycle`, `TuneSweepLifecycle`), the
  runtime RL primitives (`Policy`, `VecEnv`, `ReplayBuffer`, `RLLoop`),
  and a PPO/CartPole golden trajectory fixture. The typed proto
  envelopes (`proto/jitml/{training,rl,tune,inference}.proto` and
  `JitML.Proto.{Training,Rl,Tune,Inference}`) declare the substrate-scoped Pulsar
  topic family; the mirrors parse the deterministic text command envelopes
  emitted by their renderers, and the current Training/RL/Tune command and
  event oneofs plus Inference request/result envelopes also round-trip through
  proto3-compatible bytes. Live MinIO dataset fetch,
  daemon-backed training loops,
  and live Pulsar training/event flow are owned by Sprints `8.1`–`8.6`'s
  Remaining Work. Phase:
  [phase-8-supervised-and-rl-framework.md](phase-8-supervised-and-rl-framework.md).
- **RL algorithm catalog, AlphaZero, hyperparameter tuning.** Catalog
  covers PPO through AlphaZero as metadata rows with a Dhall
  mirror/audit; the 14 per-algorithm modules under
  `src/JitML/RL/Algorithms/{Ppo,A2c,Trpo,MaskablePpo,RecurrentPpo,Dqn,QrDqn,Ddpg,Td3,Sac,CrossQ,Tqc,Ars,Her}.hs`
  expose typed hyperparameter rows and deterministic per-seed rollout
  transcripts aggregated through `Registry.algorithmModuleRegistry`.
  The AlphaZero substack lives at
  `src/JitML/RL/AlphaZero/{Mcts,SelfPlay,Arena}.hs` with persistent
  search tree (UCB + visit-count), self-play buffer with content hash,
  and arena win-rate promotion. The `PerfectInformation` typeclass
  admits Connect 4 / Othello / Hex / Gomoku with per-game
  `applyMove` rules and per-game two-headed network metadata.
  `experiments/mnist-tune.dhall` renders the canonical `Some
  Tuning::{ … }` worked example from README. Real network forward /
  back through the JIT engine, live trial transcript persistence, and
  on-hardware reward thresholds are owned by Sprints `9.1`–`9.7`'s
  Remaining Work. Phase:
  [phase-9-rl-catalog-alphazero-and-tuning.md](phase-9-rl-catalog-alphazero-and-tuning.md).
- **Checkpointing and inference-only read path.** Typed manifest with
  the full split-blob shape (`TensorBlob`, `OptimizerBlob`, `RngBlob`,
  monotonic step, per-metric values, parent-manifest lineage SHA),
  deterministic manifest CBOR codec / content hash with canonical
  ordering, split-blob object-key renderers, pointer-CAS decision
  surface, the typed `AdvancePredicate` ADT
  (`AdvanceLatest`/`AdvanceBestMaximised`/`AdvanceBestMinimised`),
  `deriveExperimentHash` computing
  `sha256(resolved-dhall || substrate-fingerprint)`, the
  binary `.jmw1` encoder/decoder, manifest pointer, filesystem-backed
  checkpoint store, `writeCheckpointSnapshotWithMinIO` over the
  `HasMinIO` conditional-write/CAS boundary, latest-pointer read path,
  `inferWeightsOnlyFromLatestCheckpoint` for the weight-only inference
  path, `loadInferenceCheckpointWithWeights` for decoded `.jmw1` weights in
  the local Linux CPU generated-kernel smoke path,
  `daemonWorkloadDispatcherWithInference` for routing `linux-cpu` +
  `SelfInference` daemon inference through the generated-kernel checkpoint
  runner, and the GC reconciler surface
  (`RetentionPolicy{KeepAll,LastN}`, `walkLiveSet`,
  `applyRetentionPolicy`, `buildGcPlan` with `gcReapEvents` and the
  `gcNoOp` second-invocation detector). The inference request/result schema
  and local byte codecs live in `proto/jitml/inference.proto` and
  `JitML.Proto.Inference`. Live checkpoint-store validation
  through the HTTP MinIO client, live `gc_reaped` Pulsar publish, and real
  non-local kernel-handle loading are owned by Sprints `10.1`–`10.4`'s
  Remaining Work. Phase:
  [phase-10-checkpointing-and-inference.md](phase-10-checkpointing-and-inference.md).
- **PureScript frontend and demo.** Minimal PureScript entrypoint,
  generated contract file from `src/JitML/Web/Contracts.hs`, typed
  bundle/panel/demo-route metadata from `src/JitML/Web/Bundle.hs` (six
  canonical panel surfaces plus the full local API route family), the six panel modules under
  `web/src/Panels/{Mnist,Cifar,Connect4,Rl,Training,Tune}.purs` with
  typed request/response payload shapes, `web/test/Main.purs` smoke
  suite, the canonical seven-test Playwright matrix at
  `playwright/jitml-demo.spec.ts`, `jitml-demo` executable shim,
  `src/JitML/Web/Server.hs` HTTP serving, and demo deployment template.
  The Halogen mount machinery, compiled bundle output, live REST/WS
  proxying against real daemon Pulsar topics, `purescript-spec` execution,
  and Playwright against the live edge route rather than inline DOM stubs
  are owned by Sprints `11.3` / `11.4` / `11.5` / `11.6`'s Remaining Work.
  The default `purs-tidy check 'src/**/*.purs'` invocation in `web/` lands
  through `jitml lint purescript` (Sprint `11.3`). Phase:
  [phase-11-purescript-frontend-and-demo.md](phase-11-purescript-frontend-and-demo.md).
- **Test stanzas, lint matrix, cross-cluster parity.** Eight Cabal
  test-suite stanzas, each `type: exitcode-stdio-1.0` with `tasty` as
  the in-stanza runner: `jitml-unit`, `jitml-integration`,
  `jitml-sl-canonicals`, `jitml-rl-canonicals`, `jitml-hyperparameter`,
  `jitml-cross-backend`, `jitml-daemon-lifecycle`, `jitml-e2e`.
  `jitml test all
  --dry-run` renders the Plan/Apply test plan; non-dry-run `jitml test
  all` delegates to `cabal test` through the typed `Subprocess`
  boundary and prints the report-card summary. Lint and code-quality
  commands are separate from the test orchestrator.
  `JitML.Test.LivePlan.livePhasedClusterPlan` enumerates the typed
  phased Helm rollout per substrate; `infra/pulumi/index.ts` is the
  typed ephemeral-Kind orchestrator that runs `kind create cluster`
  → `helm dependency build` → `jitml bootstrap` →
  `publication-check` under the `@pulumi/command` resource graph,
  with the symmetric `kind delete cluster` rollback. Real-binary
  integration, live SL convergence, live RL trajectories, live
  hyperparameter reproducibility, live cross-substrate parity, and the
  explicit live Pulumi + Helm + Playwright path actually executed against an
  ephemeral Kind stack are owned by Sprints
  `12.2`–`12.6` / `12.8` / `12.9`'s Remaining Work. The seven doctrine
  test categories (Pure Logic, Parser, Property, Golden, Integration,
  Daemon Lifecycle, Pulumi-Orchestrated Infrastructure) all map to one
  or more of these stanzas, with the four `*-canonicals`/HPO/cross-
  backend rows being project-specific Integration extensions under
  doctrine §Test Organization → project-specific stanzas. Phase:
  [phase-12-test-stanzas-and-cross-cluster.md](phase-12-test-stanzas-and-cross-cluster.md).

## Doctrine Scope

[../README.md](../README.md) is the authoritative project and CLI doctrine.
The project [../README.md → Doctrine scope](../README.md#doctrine-scope) declares
which sections are binding and which are informational; this plan inherits that
split verbatim. No sprint may schedule adoption of an out-of-scope section.

**In scope (binding) from `README.md`, in doctrine order:**

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
- Generated Artifacts — paired check/write for generated sections and tracked
  generated files: route tables, Grafana dashboards, PureScript contracts, CLI
  help, markdown docs, manpages, shell completions, and chart YAML rendered from
  Haskell registries; `GeneratedSectionRule` registry;
  `trackingGeneratedPaths`.
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
  pinned `fourmolu.yaml` at repo root with the thirteen doctrine-mandated settings;
  jitML adopts the doctrine with a container-exclusive code-quality domain: the
  `jitml:local` Docker image installs the separate style-tools GHC and pinned
  `fourmolu` / `hlint` binaries, image construction runs the Haskell style gate,
  `jitml lint haskell` runs only inside the container-owned gate, and
  `jitml lint purescript` covers generated-contract, whitespace,
  panel-contract, and typed frontend-tool command checks.
- Testing Doctrine.
- Standard Testing Stack — Cabal + `exitcode-stdio-1.0` + tasty + tasty-hunit +
  tasty-quickcheck + tasty-golden + typed-process + temporary + Pulumi.
- Test Categories — each of the seven (Pure Logic, Parser, Property, Golden,
  Integration, Daemon Lifecycle, Pulumi-Orchestrated Infrastructure) mapped to a
  `jitml-*` stanza in
  [phase-12-test-stanzas-and-cross-cluster.md](phase-12-test-stanzas-and-cross-cluster.md).
- Test Organization — one `test-suite` stanza per tier; project-specific stanzas
  per [../README.md](../README.md).

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

The supported architecture closes on the following non-negotiable rules.
Each rule maps to one or more [Exit Definition](../DEVELOPMENT_PLAN/README.md#exit-definition)
items; whether the rule is met today is the owning sprint's status. The
phase docs and `system-components.md` carry the per-component status.
Numbered for referenceability. Cross-references to
[../README.md](../README.md) name the authoritative section that pins
each constraint.

1. One Haskell CLI binary named `jitml`, plus one bundled HTTP server shim named
   `jitml-demo`. Both are built by Cabal under GHC `9.14.1` and Cabal `3.16.1.0`.
2. Library-first layout per doctrine
   [§Project Structure](../README.md): `app/Main.hs` and `app/Demo.hs`
   are six-line shims into `App.main`; nearly all logic lives under `src/JitML/`.
3. Three supported substrates: `apple-silicon`, `linux-cpu`, `linux-cuda`. A
   fourth substrate `linux-opencl` (Intel GPU) is admitted as a future extension
   and is not in the current support matrix.
4. One CLI verb for the daemon — `jitml service` — parameterised entirely by its
   Dhall config. There is no separate `host-service` CLI verb. The Dhall declares
   `substrate`, `residency : Cluster | Host`, `inferenceMode : SelfInference |
   ForwardToHost`, and host-side connection info when `residency = Host`.
5. On every substrate the in-cluster `jitml-service` is a stateless `Deployment`,
   not a `StatefulSet`. Required pod anti-affinity at `topologyKey:
   kubernetes.io/hostname` enforces at most one replica per node. The local
   Kind topology is single-node, so the supported local service replica count
   is one; `maxSurge: 0` / `maxUnavailable: 1` keeps replacement rollouts valid
   on that node. Durable state lives in MinIO and Pulsar exclusively (no
   relational DB on jitML's data path).
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
    service, and one image. That image build owns the style-tools GHC/tool
    bootstrap and is the exclusive Haskell style/code-quality gate on every
    substrate.
22. `jitml service` is a long-running daemon parameterised by Dhall `BootConfig`
    / `LiveConfig`. SIGHUP triggers `LiveConfig` hot reload; restart-required
    fields force a full restart with a structured error. Endpoints `/healthz`,
    `/readyz`, `/metrics` are mandatory. Logging is structured JSON on stderr.
23. The daemon's Pulsar consumer is at-least-once. Idempotency is the consumer's
    responsibility: handlers derive deduplication keys from the protobuf message
    hash and do not trust client-supplied IDs. The current local subscription
    plan is derived from `BootConfig`, and the normal serve path starts
    held-open background consumer workers with live duplicate-payload dedup and
    dispatch-failure negative-ack redelivery validated on Linux CPU. The retry
    policy is a typed value with named retry strategies.
24. Capability classes `HasMinIO`, `HasPulsar`, `HasHarbor`, `HasKubectl` are the
    only allowed entry into external services from the daemon. Local workload
    effects route MinIO write/CAS, Harbor promotion, kubectl
    apply/status/delete, and RunInference through those classes via
    byte-faithful parsed dispatcher payloads; live running-daemon handler
    routing is validated by Phase `5`. The runner is `ReaderT Env IO`.
25. The Apple Silicon hybrid pattern: clustered Deployment (`Cluster +
    ForwardToHost`) plus host-native binary (`Host + SelfInference`). The
    cluster daemon publishes inference RPC envelopes on
    `inference.command.apple-silicon`; the host daemon ACKs on
    `inference.event.apple-silicon`. `JitML.Proto.Inference` owns the typed
    command/event render/parse surface, and `JitML.Service.AppleInferenceRpc`
    owns local command planning, `HasPulsar` publication, and event correlation
    by call id. Pulsar carries only small envelopes; large tensors travel via
    MinIO. Direct k8s API access from the host is forbidden and lint-enforced.
26. Numerical-core closure is fully Dhall-typed: every layer constructor,
    activation, optimizer, scheduler, and loss function has a Dhall type
    and a corresponding Haskell ADT. The implementation lives in
    `src/JitML/Numerics/Catalog.hs`, with constructor-name Dhall mirrors
    under `dhall/numerics/` and the cross-type audit in
    `src/JitML/Numerics/Schema.hs` / `src/JitML/Lint/DhallNumerics.hs`.
    Richer parameterized Dhall records are owned by future numerical-core
    work logged through standards rule G's Doc Requirements blocks.
27. Per-substrate determinism contract per
    [../documents/engineering/determinism_contract.md](../documents/engineering/determinism_contract.md):
    Metal single-stream launch order; oneDNN blocked reduction with fixed block
    size; CUDA `--use_fast_math=false`, deterministic warp-shuffle reductions
    with no device-side atomics, cuDNN explicit algorithm-id pinning.
    Same-substrate equality is guaranteed; cross-substrate drift is bounded by
    the per-tensor tolerance band measured by the cross-substrate tolerance
    methodology.
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
    The current worktree uses a local bridge-compatible renderer for
    `web/src/Generated/Contracts.purs` and `src/JitML/Web/Bundle.hs` records
    the bundle/panel/demo-route metadata. The generated contract file is
    protected by the active `trackingGeneratedPaths` registry.
32. `fourmolu.yaml` at repo root pins the thirteen doctrine-mandated settings.
    `docker/Dockerfile` installs the separate style-tools GHC and pinned
    `fourmolu` / `hlint` binaries for `jitml:local`; the image build runs the
    Haskell style/code-quality gate; `jitml lint haskell` runs only inside
    `jitml:local`; and `cabal format` is enforced by
    temp-file round-trip byte-equality. Test commands do not run style or
    code-quality gates.
33. Eight Cabal test-suite stanzas, each `type: exitcode-stdio-1.0` with `tasty`
    as the in-stanza runner: `jitml-unit`, `jitml-integration`,
    `jitml-sl-canonicals`, `jitml-rl-canonicals`, `jitml-hyperparameter`,
    `jitml-cross-backend`, `jitml-daemon-lifecycle`, `jitml-e2e`.
    A single `tasty` tree
    spanning all tiers is forbidden.
34. Target e2e closure uses the Pulumi TypeScript program at `infra/pulumi/` as
    the ephemeral-Kind orchestrator that the `jitml-e2e` stanza calls through the
    typed `Subprocess` boundary. The current Pulumi program contains a typed
    `@pulumi/command` resource graph for Kind, Helm, bootstrap, publication
    checking, and teardown; the current default `jitml-e2e` body validates that
    plan shape but does not invoke Pulumi.
35. Report-card knobs are pinned in `cabal.project` and surfaced through `jitml
    test all`. The exact knob list is owned by Sprint `12.9` and recorded in
    [system-components.md](system-components.md).
36. The toolchain is pinned at GHC `9.14.1` and Cabal `3.16.1.0`. `jitml.cabal`
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
| 6 | Phase 5 | The numerical core's current Haskell catalog and Dhall mirrors are consumed by the daemon's training and inference loops; the layer catalog precedes the JIT codegen that compiles it |
| 7 | Phase 6 | The per-substrate Haskell JIT source renderers (Metal / Swift, oneDNN C++, CUDA) consume the typed numerical core from Phase 6, generate compiler inputs under `./.build/jit-src/<substrate>/<hash>/`, and write compiled artefacts into the content-addressed cache established in Phase 2 |
| 8 | Phase 7 | The SL training loops and RL framework primitives compile their kernels through the JIT codegen established in Phase 7 and run on the daemon established in Phase 5 |
| 9 | Phase 8 | The RL algorithm catalog (PPO, A2C, ...), AlphaZero self-play, and hyperparameter tuner consume the framework primitives from Phase 8 |
| 10 | Phase 9 | Checkpointing serialises the trained models from Phases 8/9; the inference-only read path consumes the same wire format and flows back through the daemon |
| 11 | Phase 10 | The target PureScript frontend REST surfaces consume the inference-only read path established in Phase 10; current Phase `11` owns the minimal frontend/contract/demo shim scaffold and local HTTP server before the compiled bundle and live WebSocket proxy land |
| 12 | Phase 11 | The eight Cabal test-suite stanzas exercise every prior phase's surface end-to-end; `jitml-cross-backend` is the closure gate |

## Status Vocabulary

| Status | Meaning | Emoji |
|--------|---------|-------|
| **Done** | Every Exit-Definition obligation the sprint owns is met in the worktree, validated by the sprint's `### Validation` commands, and the listed docs are aligned. A sprint whose entire obligation is documentation, typed scaffolding, schema/ADT, generated-section, or pure-Haskell catalog work is legitimately Done when that surface is in place and tested; a sprint whose obligation includes live runtime behaviour (cluster up, Helm apply, Pulsar subscribe, MinIO put, kernel compile-and-execute, browser interaction, etc.) is Done only after that live behaviour is exercised through the sprint's validation. | ✅ |
| **Active** | Work has started and at least one owned Exit-Definition obligation is unmet. The sprint body lists those gaps in an explicit `### Remaining Work` block. | 🔄 |
| **Planned** | All upstream sprint dependencies are Done. The sprint has not yet started. It must list no unmet blockers. | 📋 |
| **Blocked** | At least one upstream sprint or external prerequisite required for this sprint's owned obligations is not Done. The sprint body lists the blockers in a `**Blocked by**:` line. | ⏸️ |

See [development_plan_standards.md → C. Honest Completion Tracking](development_plan_standards.md#c-honest-completion-tracking)
for the governing rule.

## Current Baseline

Phases `0`, `1`, `2`, `3`, and `6` are `✅ Done` — every Exit-Definition
obligation those phases own is met. Sprint `1.4` closes the
container-exclusive Haskell style/code-quality rule: the mandatory
`jitml:local` image build installs the separate style-tools GHC, builds pinned
Fourmolu / HLint binaries, runs `jitml check-code`, and host lint/check-code
execution is unsupported.
Phase `4` reclosed on 2026-05-23 against a Linux CUDA validation host
(NVIDIA GeForce RTX 5090, CUDA 12.8, compute capability `12.0`): the
single-node CUDA Kind cluster brings up `jitml-linux-cuda-control-plane` with
the GPU node label, the containerd `nvidia` runtime handler, the read-only
`/run/nvidia/driver` mount, and the repo-owned NVIDIA runtime config;
`RuntimeClass/nvidia` applies; the `nvidia-smi-probe` pod reaches `Succeeded`
and `kubectl logs nvidia-smi-probe` reports the RTX 5090. Phase `5` Sprint
`5.6`'s Linux CPU and Linux CUDA service-pod validations both closed the
same date: the live `jitml bootstrap --linux-cpu` rollout completes all seven
platform components ready and `kubectl rollout restart deployment/jitml-service`
cleanly replaces the pod without surge under `maxSurge: 0` /
`maxUnavailable: 1` with required hostname anti-affinity; the CUDA service-pod
variant runs `nvidia-smi -L` inside the service container. Phase `5` remains
`🔄 Active` for the Apple Silicon host-Dhall service-pod validation.
Phase `3` reclosed on 2026-05-23 after live Linux CPU bootstrap and teardown
validated the single-node topology.
Phases `7`, `8`, `9`, `10`, `11`, and `12` are
`🔄 Active` because at least one owned
Exit-Definition obligation remains unmet: single-node daemon validation
(Linux CPU, Linux CUDA, Apple Silicon), the explicit Pulumi-orchestrated
ephemeral Kind e2e path for Exit `3`, real kernel execution, checkpoint
storage, the PureScript default lint/spec path for Exit `15`, browser flow,
and cross-substrate parity.
Per-sprint Remaining Work blocks list the open work; the dependency-ordered
sequence lives in
[README.md → Execution Roadmap](README.md#execution-roadmap).

| Surface | Current Repo State | Intended End State |
|---------|--------------------|--------------------|
| Repository layout | Sprints `1.1` through `12.9` have landed the library-first Haskell CLI, AppError, cache, docs, env, lint, plan, subprocess, prerequisite, bootstrap, Tart, route, cluster-renderer, service-config, numerical-catalog, engine, runtime-source, SL/RL/tuning, checkpoint, web-contract, and report modules; stage-0 scripts; generated CLI docs; `compose.yaml`, `docker/`, `chart/`, `kind/`, `dhall/`, `web/`, `infra/`, `proto/`, and `experiments/` surfaces; and dedicated test bodies for every Cabal stanza | Full library-first Haskell layout with Haskell-owned runtime JIT source generation per [../README.md → Repository layout (target)](../README.md#repository-layout-target) |
| Build artefacts | The Cabal package declares `jitml` and `jitml-demo`; `bootstrap/apple-silicon.sh build` targets `./.build/jitml`; the typed JIT cache key/layout/manifest/symlink layer is implemented; `jitml build --dry-run --substrate <substrate>` renders generated-source compile plans under `./.build/jit-src/<substrate>/<hash>/`; non-dry-run `jitml build` routes the selected JIT artifact through `JitML.Engines.Loader`; `jitml-cross-backend` validates generated Linux CPU identity, reduction-smoke, and family-scaffold compile/load/run paths plus exported family/output-count metadata, local Linux CPU `HasEngine` dispatch, and Linux CPU benchmark candidate measurement through generated FFI output digests | `cabal build all`-produced `jitml` and `jitml-demo` binaries, generated JIT compiler inputs under `./.build/jit-src/<substrate>/<hash>/`, plus per-substrate JIT-cache artefacts under `./.build/jit/<substrate>/` |
| CLI surface | The full command family is registered and parseable from `CommandSpec`; implemented commands cover bootstrap materialization with no-op exit `3`, live Kind/Helm bootstrap, doctor/remediation, commands/help, docs, lint/check-code, Plan/Apply dry-runs, env resolution, AppError rendering, cluster status/up/down/reset summaries, typed Kind down execution, service dry-run/surface rendering plus HTTP listener startup and bounded `--consume-once` daemon batch execution, daemon workload dispatch from parsed Training/RL/Tune command envelopes into Kubernetes Job apply/delete effects, train/eval/tune/RL/inference deterministic summaries, test report rendering, internal substrate materialization, VM subprocess rendering, generated-source build-plan rendering, and cache stubs. The lint stack enforces config presence, whitespace normalization, forbidden paths, generated-doc drift, chart-shape checks, forbidden subprocess/terminal primitives, static JIT source/build artefact rejection, external `fourmolu`, `hlint`, `cabal format`, and warning-clean build execution inside `jitml:local`; host lint/check-code execution fails before linting. | The complete command family parses and runs against three substrates: `doctor`, `cluster {up,down,status,reset}`, `service`, `train`, `eval`, `tune`, `rl {train,eval,rollout}`, `verify {same-run,cross-backend,replay}`, `inspect {list,show,replay,trial,frontier}`, `bench {train,inference,env}`, `inference run`, `test`, `lint`, `docs`, `check-code`, `build`, `kubectl`, `internal {materialize-substrate,list-prereqs,gc,vm,cache}`, `commands`, `help`, plus the `jitml-demo` HTTP server |
| Test stanzas | Eight Cabal stanzas are declared with dedicated deterministic bodies; `jitml-unit` covers CLI/docs/prerequisite/env/cache/checkpoint-store surfaces, `jitml-integration` covers subprocess/bootstrap/renderers, BootConfig-derived daemon client settings, and local checkpoint inference through a Linux CPU generated kernel, `jitml-cross-backend` includes generated Linux CPU identity, reduction-smoke, family-scaffold compile/load/run, family/output-count symbol checks, local Linux CPU `HasEngine` dispatch, and Linux CPU benchmark candidate measurement, `jitml-daemon-lifecycle` covers injected engine-backed daemon inference dispatch, and `jitml-e2e` includes typed live-plan rendering plus report-card knob parsing. Live integration / SL convergence / RL trajectory / hyperparameter / cross-substrate parity / Pulumi+Playwright execution is owned by Sprints `12.2`–`12.6` / `12.8` / `12.9`'s Remaining Work | Eight Cabal stanzas: `jitml-unit`, `jitml-integration`, `jitml-sl-canonicals`, `jitml-rl-canonicals`, `jitml-hyperparameter`, `jitml-cross-backend`, `jitml-daemon-lifecycle`, `jitml-e2e` |
| Toolchain | `jitml.cabal` pins `tested-with: ghc ==9.14.1`; `cabal.project` pins `with-compiler: ghc-9.14.1`, records the codegen-toolchain comments and report-card knobs, carries a ledger-tracked scoped `allow-newer` for Dhall/CBOR package bounds under GHC `9.14.1`, and `jitml doctor --scope toolchain` validates the Sprint `2.2` host toolchain prerequisites after typed remediation | GHC `9.14.1`, Cabal `3.16.1.0`, LLVM pinned in `cabal.project`, NVCC pinned, Xcode/Metal pinned, oneDNN pinned, `kindest/node` pinned in `./kind/cluster-<substrate>.yaml` |
| Determinism contract | Deterministic SL curves, RL trajectories, tuning trials, checkpoint inference, engine flags, Linux CPU identity/reduction-smoke/family-scaffold execution, and local Linux CPU `HasEngine` dispatch are covered by dedicated Cabal stanzas; live cross-substrate equality is owned by Sprint `12.6`'s Remaining Work | Enforced by the `jitml-integration` (same-substrate bit-equality), `jitml-sl-canonicals`, `jitml-rl-canonicals`, and `jitml-cross-backend` stanzas plus the per-substrate determinism notes in [../documents/engineering/determinism_contract.md](../documents/engineering/determinism_contract.md) |
| Frontend | `web/` contains the PureScript shell, generated browser contracts from `src/JitML/Web/Contracts.hs`, and six panel payload modules under `web/src/Panels/`; `src/JitML/Web/Server.hs` serves the demo/API surface; Playwright and Pulumi scaffolds are present. Halogen mount machinery, compiled bundle, live WebSocket proxy, and Playwright against the live edge route are owned by Sprints `11.3`–`11.6`'s Remaining Work | PureScript shell under `web/`, generated contracts from `src/JitML/Web/Contracts.hs`, panel payload modules under `web/src/Panels/`, Playwright scaffold under `playwright/`, demo surface served by `jitml-demo` |

## Related Documents

- [README.md](README.md)
- [development_plan_standards.md](development_plan_standards.md)
- [system-components.md](system-components.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
- [../README.md](../README.md)
- [../README.md](../README.md)
