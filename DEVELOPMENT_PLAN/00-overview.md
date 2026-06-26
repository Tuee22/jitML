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
[phase-13-no-caveat-model-runtime.md](phase-13-no-caveat-model-runtime.md),
[phase-14-interactive-demo-and-playwright-closure.md](phase-14-interactive-demo-and-playwright-closure.md),
[phase-15-linux-cuda-and-cluster-closure.md](phase-15-linux-cuda-and-cluster-closure.md),
[phase-16-apple-silicon-closure.md](phase-16-apple-silicon-closure.md),
[phase-17-cross-substrate-and-handoff.md](phase-17-cross-substrate-and-handoff.md),
[phase-18-no-caveat-product-handoff.md](phase-18-no-caveat-product-handoff.md),
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

One `jitml` Haskell CLI binary, built by Cabal under GHC `9.12.4` and Cabal
`3.16.1.0`, drives three substrates (`apple-silicon`, `linux-cpu`, `linux-cuda`)
behind a uniform command surface. The bundled Kubernetes workload named
`jitml-demo` is a Webapp role instance of that same binary (`jitml service` with
`activeRole = Webapp`) and serves the PureScript frontend bundle. The CLI is
library-first per [project structure doctrine](../README.md#repository-layout-target):
`app/Main.hs` is a six-line shim into `App.main`; nearly all logic lives under
`src/JitML/`.

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
against those dependencies, builds `jitml:local`, retags it as
`jitml-demo:local`, loads those tags explicitly into Kind, and rolls out the
remaining services using the
umbrella chart at `chart/`. The single exposed listener is one
`127.0.0.1:<edge-port>` socket on the Envoy Gateway; every HTTPRoute in the
cluster is rendered from the typed registry in `src/JitML/Routes.hs`.

The numerical core (layer catalog, real+complex activations, optimizers,
schedulers, losses, spectral ops) ships as a Haskell catalog with a Dhall
mirror, consumed by per-substrate JIT source renderers in the Haskell binary.
Linux renderers generate compiler input source on demand under
`./.build/jit-src/<substrate>/<hash>/` and write compiled shared objects into
the content-addressed cache. The Apple target renders MSL plus launch metadata
and persists `./.build/jit/apple-silicon/<hash>.metal.json`; a fixed host Metal
bridge compiles that source with `MTLDevice.makeLibrary(source:options:)` and
dispatches on the host GPU. The Linux CPU libdnnl-linked oneDNN primitive paths
compile, load, execute, and report their exported `jitml_kernel_family_name` and
`jitml_kernel_output_count` through the Haskell FFI today; their local toolchain
fingerprint includes `artifact-abi=<os>-<arch>` and `reduction-block=256` so
host/container artifacts and fixed reduction-block changes do not collide in the
shared cache. `JitML.Engines.OneDnnRuntime` probes `pkg-config` package metadata,
readable oneDNN headers, and dynamic-linker `libdnnl` visibility through typed
subprocesses for the production Linux CPU path. CUDA and Apple Metal execution
are validated through the Phase `15` / Phase `16` live closure paths; Phase `17`
consumes their within-substrate report evidence for final handoff.

The SL/RL surfaces ship today as deterministic catalogs and measured summaries:
canonical SL cells, the Dense-MLP substrate-trainable cohort, RL algorithm rows,
registered real-environment rollout generation, AlphaZero Connect 4 helpers,
text command-envelope parsers for the current training/RL/tuning proto mirrors,
and hyperparameter trial sequences. Real
daemon-backed SL/RL/AlphaZero training loops, real env stepping, real
checkpoint persistence, and Pulsar/MinIO-backed hyperparameter sweeps migrated
to Phases `15` / `16` / `17` during the 2026-05-24 refactor. Phase `8`
Sprint `8.8` retired the deterministic `atari-subset` stand-in and added the
runtime-loaded Haskell ALE boundary plus explicit ROM policy. The later static
foreign-source correction removed the checked-in C++ shim; any future ALE
adapter must be Haskell-generated into the build/cache tree or supplied outside
the repository. Phase `8` reopened and re-closed for Sprint `8.9`, which adds
the repo-owned `KeyDoorGrid-v0` environment so default RL demos and required
canonical examples need no copyrighted ROM material. Phase `9` reopened and
re-closed for Sprint `9.8`, which retargets the RL algorithm/convergence matrix.
The checked-in `experiments/mnist-tune.dhall` file carries the
`Some Tuning::{ ... }` fixture using a TPE sampler; the current Haskell catalog
in `src/JitML/Tune/Catalog.hs` includes the full target sampler set (`Grid`,
`Sobol`, `Random`, `TPE`, `GPBO`, `GeneticAlgorithm`, `NSGA2`, `MuLambdaES`,
`CMAES`, `EvolutionStrategies`, and `PBT`), and `jitml tune` decodes that
fixture into the local tuning ADT before rendering its deterministic plan.
`JitML.Proto.Tune` now covers the current tune command and event oneofs with
proto3-compatible byte round-trips; generated proto-lens Haskell bindings live
under `gen/Proto/Jitml/` and are exposed by the cabal library.

The checkpoint surface provides a typed manifest, split-blob object-key
renderers, pointer-CAS decisions, the binary `.jmw1` encoder/decoder, manifest
pointer renderer, a filesystem-backed checkpoint store,
`writeCheckpointSnapshotWithMinIO` over the `HasMinIO` conditional-write/CAS
boundary, decoded weight loading for the local Linux CPU generated-kernel
smoke path, and deterministic inference from the latest checkpoint. The live HTTP
MinIO capability path is implemented by `JitML.Service.MinIOSubprocess` and
validated against the routed `/minio/s3` edge for write-once conflicts, pointer
CAS conflicts, read, list, and delete. The frontend surface provides a
minimal PureScript entrypoint, generated endpoint and current-panel payload
contracts from `src/JitML/Web/Contracts.hs`, typed bundle/panel/demo-route
metadata from `src/JitML/Web/Bundle.hs`, and the `jitml-demo` Webapp workload
served by `src/JitML/Web/Server.hs`; the typed demo route manifest covers the full
current local API route family including `/api/runs/{runId}/command`. Sprint
`11.9` removes current marker/default parser residue from the panels and adds
typed controls/charts for the existing browser workflows plus generated REST
request envelopes, checkpoint-backed MNIST/CIFAR/Connect 4 route injection,
generic tensor inference, and checkpoint comparison, plus the RL environment
animation, training throughput-telemetry, and rules-complete adversarial
annotations; Sprint `11.9` closed `✅ Done` on 2026-06-16 on that owned code
surface, and its remaining live all-substrate REST proof, live command-state
reconciliation, expanded replay/game surfaces, and live no-caveat Playwright
product matrix are owned downstream by Sprint `14.1` / `14.2` and the Phase
`15`/`16` live lanes (rule E).

`jitml test all --dry-run` renders the aggregate test plan and non-dry-run
`jitml test all` invokes every test-only Cabal test-suite stanza (`jitml-unit`,
`jitml-integration`, `jitml-sl-canonicals`, `jitml-rl-canonicals`,
`jitml-hyperparameter`, `jitml-cross-backend`, `jitml-daemon-lifecycle`,
`jitml-e2e`) through the typed `Subprocess` boundary before printing the
report-card summary. Style and code-quality gates run separately through
`jitml lint *` and `jitml check-code`. The
report-card knobs are pinned in `cabal.project`. `jitml test all --live`
adds the live measured report-card fields; the 2026-06-04 fresh Apple
live validation passed the full aggregate and captured populated RL,
AlphaZero, tune, JIT-cache, and daemon-health measurements.
Sprint `12.11` adds `JitML.Test.WorkflowMatrix` as the single real-workflow
matrix for reopened SL/RL/tune/inference/AlphaZero coverage. The local e2e body
asserts complete matrix coverage; the integration `Live` body consumes the
current-substrate matrix cells and fails closed without a live publication; the
AlphaZero cell runs `jitml rl alphazero self-play`. On 2026-06-12 the
`linux-cpu` bootstrap completed **83** rollout steps after the Docker Desktop
Postgres PV, Harbor ownership, stale-publication, and Envoy request fixes; the
edge returned `HTTP/1.1 200 OK` from `/healthz`, and the live
`jitml-integration -p WorkflowMatrix` gate passed **1 / 1**; see
[phase-12-test-stanzas-and-cross-cluster.md](phase-12-test-stanzas-and-cross-cluster.md).

Haskell style and code-quality execution is container-exclusive. The
`jitml:local` image is required on every substrate, including Apple Silicon for
the in-cluster daemon, so the Dockerfile owns the separate toolchain plus
pinned `fourmolu` / `hlint` binaries and runs the Haskell style/code-quality
gate during image construction. Runtime lint/check-code commands run inside that
image or fail before linting; they never install, discover, or override host
style tools.

## Execution Roadmap

The dependency-ordered execution roadmap lives in
[README.md → Execution Roadmap](README.md#execution-roadmap). Each item there
links to the owning sprint's `### Remaining Work` block, where the validation
gate lives. The roadmap closes when every Active or Blocked phase moves to Done
and the deletion ledger has no pending rows.

## Architecture Overview

- **Haskell CLI surface.** One binary `jitml`; the `jitml-demo` workload is the
  Webapp role selected by typed Dhall. The parser is generated from a separate `CommandSpec` registry — never the
  source of truth. The same registry feeds the parser, the command tree (`jitml
  commands --tree`), the JSON command schema (`jitml commands --json`), the markdown
  command reference, the manpages, and the shell completion scripts. Owned by
  [phase-1-haskell-cli-surface.md](phase-1-haskell-cli-surface.md).
- **Bootstrap reconciler, prerequisite DAG, JIT cache.** Three idempotent stage-0
  bootstrap scripts (`bootstrap/{apple-silicon,linux-cpu,linux-cuda}.sh`) perform
  only the minimal host gates needed to reach `jitml bootstrap --<substrate>`.
  Apple verifies macOS on Apple Silicon, Homebrew, and the source-build
  prerequisites for `./.build/jitml`, then delegates to
  `jitml bootstrap --apple-silicon`.
  Linux verifies Docker without `sudo`, CUDA additionally verifies the NVIDIA
  container runtime and a qualifying `nvidia-smi` device, then delegates through
  `docker compose run --rm jitml jitml bootstrap --linux-cpu|--linux-cuda`.
  The typed `Prerequisite` DAG consumed by the Haskell bootstrap performs lazy
  package validation/remediation, including Homebrew package installation when
  a resource is actually needed. The content-addressed JIT cache is keyed on
  `(canonical-cbor(KernelSpec), kind, substrate, toolchain-fingerprint,
  rendered-source-payload, tuning-choice)`. Linux stores compiled shared objects
  under `./.build/jit/<substrate>/<hash>.so`; Apple stores
  `./.build/jit/apple-silicon/<hash>.metal.json` source metadata and executes it
  through a fixed host Metal bridge. Core Apple cache misses require
  `apple.metal-runtime` and `apple.metal-bridge`; they do not start Tart, invoke
  SwiftPM, require full Xcode, require the offline `metal` compiler, or depend
  on unlocked keychain state. This doctrine reopened and re-closed Phases
  `1`/`2`/`5`/`7`/`16`/`17` on 2026-06-12, and the legacy deletion ledger is
  empty. Outer-container Linux
  commands run as `docker compose run --rm jitml jitml <command>` against the
  headless default service; direct CUDA tests that need device exposure use the
  `jitml-cuda` companion service. The substrate image is `jitml:local`, the
  outer container is removed after cluster bootstrap, and the cluster daemon owns
  subsequent work. Owned by
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
  as the control-plane ↔ data-plane bus with topic
  `inference.command.apple-silicon` for Apple host↔cluster raw inference-domain
  forwarding through `JitML.Service.Runtime`, and `inference.request.<mode>` /
  `inference.result.<mode>` for the demo-facing inference flow; 2026-05-19
  live validation proving `/pulsar/admin` works through the edge,
  `/pulsar/ws` targets `pulsar-broker:8080` with
  `webSocketServiceEnabled=true`, the full typed derived topic family exists,
  2026-05-20 live validation proving the then-current 26-topic family was
  registered and `training.command.linux-cpu` published/consumed through the
  `jitml:local` WebSocket path, and the current 31-topic family derives from
  `JitML.Coordinator.Topology`;
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
  2026-05-23 CUDA service-pod validation runs the actual `jitml-service` pod
  with `runtimeClassName: nvidia` on the GPU-labelled single Kind node and
  confirms `nvidia-smi -L` inside the service container; 2026-05-23 live Apple
  Silicon host validation runs the generated
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
  `src/JitML/Codegen/` renders Apple MSL, oneDNN C++, and CUDA
  runtime source bundles under
  `./.build/jit-src/<substrate>/<hash>/`. `JitML.Codegen.KernelFamily`
  defines the typed `KernelFamily` ADT (`identity`, `reduction`,
  `dense`, `conv2d`, `conv3d`, `batchnorm`, `layernorm`, `mha`,
  `embedding`) consumed by the family-aware renderers
  (`renderOneDnnFamilySource`, `renderCudaFamilySource`,
  the target `renderMetalFamilySource`). `JitML.Engines.Tuning` declares the
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
  order with SHA-256 output digests for the first-cache-miss hardware benchmark
  loop, while its CUDA/Metal benchmark-runner entrypoints preflight runtime
  availability and fail closed before unavailable live benchmark FFI execution.
  `JitML.Engines.TuningCache` loads that persisted choice to
  derive the final
  runtime source and cache key.
  `JitML.Engines.Loader` owns cache-hit/cache-miss artifact materialization and
  compile-on-miss for the local Linux CPU FFI path, while
  `JitML.Engines.Local` loads and runs the generated Linux CPU oneDNN reorder,
  reduction, matmul, convolution, normalization, attention, and embedding
  primitive paths through the Haskell FFI, validating the exported family-name
  and output-count symbols from each loaded artifact, while
  `JitML.Engines.OneDnnRuntime` owns the typed `libdnnl` package/header/link
  visibility probe for that production Linux CPU path. Generated CUDA source
  now exports the same `jitml_kernel` / family / output-count ABI, and
  `JitML.Engines.CudaLocal` consumes a positive CUDA runtime probe before
  compile/load/launch while failing closed before compile when no CUDA runtime
  is visible. The Apple target no longer exports a generated Swift dylib per
  kernel; `JitML.Engines.MetalLocal` calls the fixed bridge with cached MSL
  source metadata and validates output shape/family metadata on the Haskell
  side.
  `JitML.Engines.CudaRuntime` owns the host-side CUDA reduction
  partial-count/finalization helper plus the typed `nvcc` / `nvidia-smi` /
  `ldconfig` CUDA runtime probe. `JitML.Engines.MetalRuntime` owns the
  corresponding host Metal runtime probe for `MTLDevice.makeLibrary` and Metal
  device visibility before host FFI execution.
  The Apple first-cache-miss path writes MSL source metadata, then compiles
  through the fixed bridge in-process on first use. The Tart VM lifecycle,
  generated Swift/Tart build path, and Apple generated-dylib symlink surface are
  deleted from the supported runtime path; the `jitml internal vm` command group
  was removed by Sprint `1.15`, the core Tart prerequisite / bootstrap cleanup
  was removed by Sprint `2.12`, the daemon build-VM acquire/config path was
  removed by Sprint `5.10`, and Sprint `7.11` removed the codegen/cache residue.
  Headless Apple Metal live validation + Metal loading, live
  CUDA GPU-host compile/load/run validation plus cuBLAS/cuDNN bindings, and
  live benchmark-driven hardware auto-tuning are closed by Phases `15` / `16` /
  `17`, preserving the determinism contract per
  [../documents/engineering/determinism_contract.md](../documents/engineering/determinism_contract.md):
  Metal single-stream launch order, oneDNN blocked reduction with fixed
  block size, CUDA deterministic warp-shuffle reductions with no device-side
  atomics plus host canonical partial finalization, `--use_fast_math=false`,
  and cuDNN explicit algorithm-id pinning.
  Phase:
  [phase-7-jit-codegen-and-substrates.md](phase-7-jit-codegen-and-substrates.md).
- **Supervised learning and RL framework.** `src/JitML/SL/` and
  `src/JitML/RL/` provide the canonical SL problem catalog and all-row
  device-trainable cohort, the typed dataset registry
  (`SL.Dataset.canonicalDatasets`), the substrate-backed SL architecture runtime, the RL
  algorithm catalog rows, canonical RL environment metadata, framework run-plan
  metadata, registered rollout helpers over real environment dynamics, the three
  GADT-indexed lifecycles
  (`TrainingLifecycle`, `RLRunLifecycle`, `TuneSweepLifecycle`), the
  runtime RL primitives (`Policy`, `VecEnv`, `ReplayBuffer`, `RLLoop`),
  and run-to-run determinism for the PPO/CartPole trajectory (two
  fresh runs compared against each other; no committed trajectory
  fixture per [../README.md → Snapshot targets → Numerical-fixture
  prohibition](../README.md#snapshot-targets)). The typed proto
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
  `src/JitML/RL/AlphaZero/{Mcts,SelfPlay,PolicyValueNet}.hs` with persistent
  search tree (PUCT + visit-count), device-backed policy/value leaf evaluation,
  self-play buffer with content hash, and arena win-rate promotion. The
  `PerfectInformation` typeclass
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
  monotonic step, per-metric values, parent-manifest lineage SHA,
  architecture metadata, preprocessing metadata, output decoders,
  model-family identifiers, weight-layout descriptors, replay/transcript
  pointers, and per-substrate artifact identity),
  deterministic manifest CBOR codec / content hash with canonical
  ordering, split-blob object-key renderers, pointer-CAS decision
  surface, the typed `AdvancePredicate` ADT
  (`AdvanceLatest`/`AdvanceBestMaximised`/`AdvanceBestMinimised`),
  `deriveExperimentHash` computing
  `sha256(resolved-dhall || substrate-fingerprint)`, the
  binary `.jmw1` encoder/decoder, manifest pointer, filesystem-backed
  checkpoint store, `writeCheckpointSnapshotWithMinIO` over the
  `HasMinIO` conditional-write/CAS boundary, latest-pointer read path,
  `loadInferenceCheckpointWith` for explicit injected runners,
  `loadInferenceCheckpointWithWeights` for decoded `.jmw1` weights in
  the local Linux CPU generated oneDNN path, manifest experiment/content-SHA
  compatibility checks, tensor-shape checks for decoded weight payloads,
  `daemonWorkloadDispatcherWithWeightedInference` for routing self-inference
  daemon requests through generated weighted checkpoint runners, and the GC reconciler surface
  (`RetentionPolicy{KeepAll,LastN}`, `walkLiveSet`,
  `applyRetentionPolicy`, `buildGcPlan` with `gcReapEvents` and the
  `gcNoOp` second-invocation detector). The inference request/result schema
  and local byte codecs live in `proto/jitml/inference.proto` and
  `JitML.Proto.Inference`. `src/JitML/Web/Server.hs` no longer serves inline
  demo policy/value networks on the inference/image/Connect 4 routes; Sprint
  `11.9` restores those routes through an injected checkpoint runtime handler
  that calls `loadInferenceCheckpointWithWeights` when `jitml-demo` has a live
  publication and fails closed with `503 checkpoint-required` otherwise.
  Sprint `10.6` re-closed after the live
  linux-cpu, linux-cuda, and apple-silicon integration lanes passed. Phase:
  [phase-10-checkpointing-and-inference.md](phase-10-checkpointing-and-inference.md).
- **PureScript frontend and demo.** Minimal PureScript entrypoint,
  generated contract file from `src/JitML/Web/Contracts.hs`, typed
  bundle/panel/demo-route metadata from `src/JitML/Web/Bundle.hs` (the current
  panel surfaces plus the full local API route family), the panel modules under
  `web/src/Panels/` with
  typed request/response payload shapes plus the shared API/WebSocket bridge
  modules, `web/test/Main.purs` smoke suite, the current eleven-test Playwright
  matrix at `playwright/jitml-demo.spec.ts`, `src/JitML/Web/Server.hs` HTTP
  serving, and the `chart/local/jitml-demo` Webapp deployment template.
  The Halogen mount machinery, compiled bundle output, and
  `purescript-spec` execution through the Node `spec-node` runner landed in
  Sprints `11.3` / `11.4` /
  `11.5`; the live REST/WS proxy, live-edge Playwright surfaces, and
  value assertions for MNIST / CIFAR / Connect 4 later closed in Phases
  `11` / `15`, and Phase `17` removed the offline fallback paths.
  Sprint `11.9` extends the generated PureScript contract with typed
  inference/generic/image/checkpoint-compare/adversarial/training/RL/tune/control
  payload decoders, browser REST request envelopes, request-aware command
  publication, and an injected checkpoint runtime handler for
  MNIST/generic/CIFAR/checkpoint-compare/Connect 4; it rewires
  the current panels away from marker/default parsers, adds training/RL/tune
  command-envelope controls, training metadata, RL replay scrub summaries, and
  multi-game adversarial boards, and renders non-placeholder loss/policy/MCTS/tuning
  summaries. The no-caveat product target remains open for live all-substrate
  REST proof, live command-state reconciliation, expanded replay/adversarial
  surfaces, and live Playwright proof.
  The default `purs-tidy check 'src/**/*.purs'` invocation in `web/` lands
  through `jitml lint purescript` (Sprint `11.3`). Phase:
  [phase-11-purescript-frontend-and-demo.md](phase-11-purescript-frontend-and-demo.md).
- **Test stanzas, lint matrix, live workflow matrix.** Eight Cabal
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
  phased Helm rollout per substrate; `JitML.Test.LivePlan.liveE2EPlan`
  is the typed ephemeral-Kind orchestration that runs `helm dependency
  build chart` → `jitml bootstrap` → `npx playwright test` →
  `jitml cluster down`. Real-binary
  integration, live SL convergence, live RL trajectories, live
  hyperparameter reproducibility, and the explicit live Helm +
  Playwright path actually executed against an ephemeral Kind stack are
  owned by Sprints `12.2`–`12.5` / `12.8` / `12.9`'s Remaining Work.
  Within-substrate apple-silicon reproducibility is validated host-native by
  Sprint `16.6`; no cross-substrate parity path remains. The seven doctrine
  test categories (Pure Logic, Parser, Property, Snapshot (pure-renderer
  output only), Integration, Daemon Lifecycle, Ephemeral-Cluster
  Infrastructure) all map to one
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
  pinning](../README.md#toolchain-pinning)): GHC `9.12.4`, Cabal `3.16.1.0`.
- Project Structure (library-first; instantiated by [../README.md → Repository
  layout (target)](../README.md#repository-layout-target)): thin `app/Main.hs`,
  role logic in `src/JitML/`.
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
  `jitml:local` Docker image installs the same pinned GHC `9.12.4` and pinned
  `fourmolu` / `hlint` binaries, image construction runs the Haskell style gate,
  `jitml lint haskell` runs only inside the container-owned gate, and
  `jitml lint purescript` covers generated-contract, whitespace,
  panel-contract, typed frontend-tool command checks, and the `spec-node`
  `purescript-spec` smoke suite.
- Testing Doctrine.
- Standard Testing Stack — Cabal + `exitcode-stdio-1.0` + tasty + tasty-hunit +
  tasty-quickcheck + typed-process + temporary. Snapshot
  comparisons for pure-renderer output use `tasty-hunit` text/byte
  equality; `tasty-golden` is intentionally not adopted, since the
  project forbids numerical fixtures per
  [../README.md → Snapshot targets → Numerical-fixture
  prohibition](../README.md#snapshot-targets).
- Test Categories — each of the seven (Pure Logic, Parser, Property,
  Snapshot (pure-renderer output only), Integration, Daemon Lifecycle,
  Ephemeral-Cluster Infrastructure) mapped to a
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
`purescript-spec`, `spec-node`, Playwright) is a project-specific target owned by Phase `11`
and is not a doctrine deviation because the doctrine does not address browser-side
code; the current worktree implements the PureScript shell, generated contract
file, `spec-node` smoke suite, Halogen panel modules, demo server, and live-only
Playwright scaffold.

## Hard Constraints

The supported architecture closes on the following non-negotiable rules.
Each rule maps to one or more [Exit Definition](../DEVELOPMENT_PLAN/README.md#exit-definition)
items; whether the rule is met today is the owning sprint's status. The
phase docs and `system-components.md` carry the per-component status.
Numbered for referenceability. Cross-references to
[../README.md](../README.md) name the authoritative section that pins
each constraint.

1. One Haskell CLI binary named `jitml`; the bundled `jitml-demo` workload is a
   Webapp role instance of that same binary. The binary is built by Cabal under
   GHC `9.12.4` and Cabal `3.16.1.0`.
2. Library-first layout per doctrine
   [§Project Structure](../README.md): `app/Main.hs` is a six-line shim into
   `App.main`; nearly all logic lives under `src/JitML/`.
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
   `helm`, `kind`, `docker`, `nvcc`, `g++` (over oneDNN), optional non-core Swift
   probes, and every kernel-compiler invocation goes through the typed boundary.
   The Apple core Metal path compiles MSL in-process through the fixed bridge via
   `MTLDevice.makeLibrary(source:options:)`, not through Tart, SwiftPM, full Xcode,
   or the offline `metal` compiler.
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
17. The JIT cache root is `./.build/jit/`; Linux entries are compiled shared
    objects and Apple target entries are `<hash>.metal.json` source metadata.
    Entries are content-addressed by `sha256(canonical-cbor(KernelSpec) || kind
    || substrate || toolchain-fingerprint || rendered-source-payload ||
    tuning-choice)` where `KernelSpec` is model shape and `kind` is
    `training | inference`. Training and inference kernels are separate artifacts.
18. Apple Silicon uses one fixed host bridge under `./.build/host/apple-silicon/`
    or linked into the host binary; per-kernel generated-dylib symlinks are
    legacy residue pending Sprint `7.11`.
19. `./bootstrap/{apple-silicon,linux-cpu,linux-cuda}.sh` are idempotent stage-0
    entrypoints. Apple checks macOS/arm64, Homebrew, and the source-build
    prerequisites for `./.build/jitml`, then calls
    `jitml bootstrap --apple-silicon`. Linux checks Docker without `sudo`; CUDA
    additionally checks NVIDIA runtime and device compute capability; both call
    `docker compose run --rm jitml jitml bootstrap --linux-cpu|--linux-cuda`.
    The typed `Prerequisite` DAG is consumed in-process by the Haskell bootstrap.
20. `purge` is destructive but cache-preserving (`./.build/` survives, including
    the JIT cache); `purge --full` additionally removes `./.build/` and, on Linux,
    the substrate image.
21. The substrate image is always `jitml:local`. Substrate is a runtime Dhall
    choice, never an image-name dimension. There is one Dockerfile, one image,
    and two compose service wrappers: headless `jitml` plus GPU-enabled
    `jitml-cuda`. The image build owns the style-tool bootstrap and is
    the exclusive Haskell style/code-quality gate on every substrate.
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
    cluster daemon forwards raw inference-domain payloads on
    `inference.command.apple-silicon`; the host Engine publishes results directly
    to each request's reply topic. `JitML.Proto.Inference` owns the typed
    render/parse surface and `JitML.Service.Runtime` owns the forwarding path.
    Pulsar carries only small envelopes; large tensors travel via MinIO. Direct
    k8s API access from the host is forbidden and lint-enforced.
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
    Within-substrate equality is guaranteed bit-for-bit; cross-substrate
    equivalence is not claimed (RNG draws and float reduction order differ
    between substrates), so no cross-substrate tolerance band is asserted.
28. Target JIT compiler inputs are generated by the Haskell `jitml` binary on a
    cache miss. The repository does not use static checked-in `.cu`, `.cc` /
    `.cpp`, per-kernel MSL source files, Swift package source files, native
    adapter shims, or per-substrate JIT build `.sh` scripts as build inputs. The Haskell
    renderers emit Linux compiler inputs into
    `./.build/jit-src/<substrate>/<hash>/`; the Apple renderer emits MSL into the
    `.metal.json` cache artifact consumed by the fixed bridge. Checked-in
    native/foreign source exceptions are allowed only for the fixed non-kernel
    bridge source or Haskell Objective-C-runtime bridge, not per-kernel adapters.
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
    the bundle/panel/demo-route metadata. Sprint `11.9` extends the generated
    file with current-panel inference/generic/image/checkpoint-compare/
    adversarial/training/RL/tune/control
    request/render/parser surfaces. The generated contract file is protected by the active
    `trackingGeneratedPaths` registry.
32. `fourmolu.yaml` at repo root pins the thirteen doctrine-mandated settings.
    `docker/Dockerfile` installs the same pinned GHC `9.12.4` and pinned
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
34. Target e2e closure uses the typed `JitML.Test.LivePlan.liveE2EPlan` as
    the ephemeral-Kind orchestration that the `jitml-e2e` stanza drives through
    the typed `Subprocess` boundary: `helm dependency build chart` → `jitml
    bootstrap` (ephemeral Kind + phased Helm rollout) → `npx playwright test`
    → `jitml cluster down`. The current default `jitml-e2e` body validates that
    plan shape but does not invoke the live stack.
35. Report-card knobs are pinned in `cabal.project` and surfaced through `jitml
    test all`. The exact knob list is owned by Sprint `12.9` and recorded in
    [system-components.md](system-components.md).
36. The toolchain is pinned at GHC `9.12.4` and Cabal `3.16.1.0`. `jitml.cabal`
    declares `tested-with: ghc ==9.12.4`; `cabal.project` declares
    `with-compiler: ghc-9.12.4`. Codegen toolchains (LLVM, NVCC, the host OS
    Metal runtime + fixed bridge ABI, oneDNN, `kindest/node`) are pinned in
    `cabal.project` or bridge metadata.

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
| 7 | Phase 6 | The per-substrate Haskell JIT source renderers (Apple MSL, oneDNN C++, CUDA) consume the typed numerical core from Phase 6, generate compiler inputs/source metadata, and write content-addressed artifacts into the cache established in Phase 2 |
| 8 | Phase 7 | The SL training loops and RL framework primitives compile their kernels through the JIT codegen established in Phase 7 and run on the daemon established in Phase 5 |
| 9 | Phase 8 | The RL algorithm catalog (PPO, A2C, ...), AlphaZero self-play, and hyperparameter tuner consume the framework primitives from Phase 8 |
| 10 | Phase 9 | Checkpointing serialises the trained models from Phases 8/9; the inference-only read path consumes the same wire format and flows back through the daemon |
| 11 | Phase 10 | The target PureScript frontend REST surfaces consume the inference-only read path established in Phase 10; current Phase `11` owns the minimal frontend/contract/demo shim scaffold and local HTTP server before the compiled bundle and live WebSocket proxy land |
| 12 | Phase 11 | The eight Cabal test-suite stanzas exercise every prior phase's surface end-to-end; `jitml-cross-backend` is the closure gate |
| 13 | Phase 8, Phase 9, Phase 10 | Full no-caveat model runtime closure on the always-available `linux-cpu` lane: every canonical SL/RL/AlphaZero/tuning workflow trains, checkpoints, reloads, and infers/evaluates through the substrate without scoped Dense-only or demo-only exceptions. Per-accelerator runtime convergence is owned downstream (Phases `15`/`16`). |
| 14 | Phase 13 | Full interactive demo + Playwright product closure over the Phase `13` runtime, validated on `linux-cpu`: every runtime workflow has browser controls, visualizations, animations, adversarial replay, and live e2e assertions against the routed app. Per-accelerator browser/Playwright is owned downstream (Phases `15`/`16`). |
| 15 | Phase 13, Phase 14 | Linux CUDA + Kind cluster + Helm + live broker + live MinIO + live Playwright closure: re-runs the full no-caveat runtime + browser matrix (Phases `13`/`14`) on `linux-cuda`, including deep-model GPU convergence, through one Linux/NVIDIA host (`linux-cpu`+`linux-cuda`). |
| 16 | Phase 13, Phase 14 | Apple Silicon fixed-bridge Metal JIT (`<hash>.metal.json` + host runtime `MTLDevice.makeLibrary(source:options:)`), Metal FFI, host↔cluster RPC, host-resident Metal placement, and the full runtime + browser matrix on `apple-silicon` through one Mac host (`linux-cpu`+`apple-silicon`); independent of Phase `15`. |
| 17 | Phase 15, Phase 16 | Within-substrate reproducibility aggregated on `linux-cpu` from the committed per-lane artifacts of Phases `13`/`15`/`16`, a populated live `jitml test all` report card, and an empty deletion ledger. No cross-substrate numeric-equivalence claim (out of contract). |
| 18 | Phase 13, Phase 14, Phase 15, Phase 16, Phase 17 | Final no-caveat handoff: a `linux-cpu` aggregation that merges the committed per-lane attestations into one report card, with docs aligned and the legacy ledger empty. Never runs two accelerators on one host. |

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

**✅ Current status (2026-06-26): all phases `0`–`18` are Done again after the
real-SL/RL chain re-aggregation.** The 2026-06-24 real-SL/RL audit reopened
Phases `8`/`9`/`10`/`13`/`14`/`18` to remove hardcoded weights, fake loss /
convergence metrics, missing train/test/validation split semantics, and demo
input stand-ins. **Phase `8` Sprint `8.13`** (real CE/MSE SL loss + held-out
validation loss, validation-driven selection, `examples_processed` throughput)
and **Phase `9` Sprint `9.13`** (real measured-median RL convergence +
env-steps sample-efficiency + AlphaZero arena-win-rate) re-closed on both the
`apple-silicon` and `linux-cpu` lanes (`sl-canonicals` 24/24 + 24/24,
`rl-canonicals` 31/31 + 31/31, `docs check: ok`, `check-code` green).
**Phase `10` Sprint `10.9`** re-closed on `linux-cpu` with real trained,
distinct, self-describing demo checkpoints and live family-distinct
`jitml inference run` proof. **Phase `13` Sprint `13.2`** re-closed with
`jitml test all --live --linux-cpu` passing 8/8 stanzas and all report-card
metrics populated. **Phase `14` Sprint `14.3`** re-closed with real full-width
MLP checkpoint forward for all eight seeded product hashes, user-derived panel
inputs, direct live endpoint probes, and Playwright **15/15**. **Phase `18`
Sprint `18.3`** re-closed with the final `linux-cpu` aggregation: all 12
canonical dataset blobs staged, eight demo checkpoints seeded, `jitml test all
--live --linux-cpu` **8/8**, `browser_product_matrix` **8/8**, `jitml
check-code: ok`, `jitml docs check: ok`, and the `Pending Removal` ledger empty
again (Exit Definition item 18 re-met). The durable-state DSL closure (below)
stands. The durable-state DSL refactor previously reopened **Phases
`2`/`4`/`5`/`10`/`18`**:
**Phase `2`** is **`✅ Done`** again (Sprint `2.15` — the closed self-validating
`jitml.dhall` foundation + `jitml project init` + the asserted `Budget`/`fitsWithin`,
`jitml-unit` 217/217); **Phase `4`** is **`✅ Done`** too (Sprint `4.9` — `bucketNames`
projected from the registry, `jitml-e2e` 23/23), and **Phase `5`** is **`✅ Done`**
(Sprint `5.15` — registry declares the logical Pulsar topic family,
anti-drift-checked), and **Phase `10`** is **`✅ Done`** (Sprint `10.8` — checkpoint GC
retention registry-sourced), and **Phase `18`** (Sprint `18.2`) re-aggregated the
no-caveat handoff — **all phases `0`–`18` are `✅ Done` again** with the durable-state
DSL landed. The `Pending Removal` ledger is empty again (Exit Definition item 18
re-met); `jitml-unit` 219/219, `jitml-e2e` 23/23, `cabal build all` clean. Phases `0`,
`1`, `3`, `6`–`9`, `11`–`17` remain `✅ Done`. The dated reopen/re-close narrative
below is retained as historical record.

**Reopened + re-closed (2026-06-20 — authenticated third-party image pre-pull).**
Phase `2` reopened for **Sprint `2.13`** and re-closed `✅ Done` on its retained
surface: the bootstrap pre-pulls the `docker.io/*` third-party chart images
authenticated on the host (reading, never writing, the host `docker login`)
before `kind load`, closing the cold-host **429** (live-proven: no 429 on the host
pull; overlay2 stores close the in-cluster 429 directly via `kind load`). The
in-cluster credential closure is jitML's own, self-contained Sprint `2.14`
`imagePullSecret` (projected from the host Docker Hub credential), which
authenticates the kind node's pulls; the host-dependent containerd-image-store
`kind load` behavior (the colima `ctr import` quirk) is a known characteristic
that owned path accommodates. It is an owned project mechanism, not a transfer to
any external foundation.

**Reopened + re-closed (Pulsar ML-Workflow convergence; closed 2026-06-20 on
owned surfaces).** Phases `5`, `10`, `11`, and `12` are **all `✅ Done`** on their
owned convergence surfaces (`5.12`/`5.13`/`5.14`, `10.7`, `11.10`, `12.14`); the
live behaviours — coordinator reconcile / multi-role serving and the panels' live
Playwright product proof — are forward ownership-transfers to Phases `11`/`15`/`16`
(rule M(a)). They were reopened for the cross-project
[../documents/engineering/pulsar_ml_workflow.md](../documents/engineering/pulsar_ml_workflow.md)
convergence — a one-binary **Engine / Coordinator / Webapp** role model selected by
typed Dhall, a derived **topic algebra** owned by the Coordinator (retiring the
hardcoded `PulsarBootstrap` list), a reflected Dhall schema, the `Work*` envelope
family unifying training + inference, the artifact + `.ready` readiness contract,
and websocket snapshot/patch inference. The decomposed convergence sprints are
**Phase `5`**: `5.12` (reflected Dhall schema), `5.13` (Coordinator topic algebra),
`5.14` (one-binary role model) — **all `✅ Done`** on their owned pure-logic
surfaces (validated by container `jitml check-code`, host `jitml docs check`,
`jitml-unit` 203/203, `jitml-daemon-lifecycle` 35/35; live coordinator
reconcile / multi-role serving are forward ownership-transfers to Phases
`11`/`15`); **Phase `10`**: `10.7` (async `Work*` inference + `.ready` gate,
collapsing the triplicated inference path into the Engine) — **`✅ Done`** on its
retained surface (`Work*` envelope family, readiness gate, single-`engineWeightedInference`
compute collapse), validated **statically in-container** (`check-code`/`docs
check`/`jitml-unit` 206) **and live on `linux-cpu`** (clean 84-step bootstrap +
`jitml-integration` 71/71 incl. inference round-trip); the publish-only async
behavior (CLI/demo publish a `WorkCommand`) transferred to `11.10`. **Phase `11`**:
`11.10` (Webapp role + websocket-driven panels + the transferred CLI publish,
folding `jitml-demo` in and dissolving the Apple in-pod-Metal browser-forward) —
**`✅ Done`** on its owned surface (all five panels async over `/api/ws/inference`
via the typed-decode pipeline; CheckpointCompare + Connect-4 as Engine workflows;
validated `cabal build all` / `jitml-unit` 208 / `jitml-e2e` 23 / `spago test`
17/17 / `check-code`, and live on `linux-cpu` for the Webapp pod + CLI publish;
live Playwright transfers to `14.2`/`16.x`); **Phase `12`**: `12.14`
(common-shape test coverage) — **`✅ Done`** (`jitml-unit` 208 + `web/test`
snapshot frames; `-p Live` integration is the standard runtime gate). Every
convergence `Blocked by` edge references a strictly lower-numbered sprint
(forward-DAG, rule M), and each closes on the `linux-cpu` / pure-logic lane with no
dual-accelerator gate. The live `linux-cpu` convergence validation caught and fixed a real
regression (the hand-written jitml-service chart ConfigMap lacked the new
`activeRole` field). The closure narrative below predates this reopen and is retained as dated
history.

**Reopened 2026-06-14 (no-caveat end-to-end product target).** The current
worktree has re-closed Phase `8` on all-row SL trainable runtime coverage and
typed RL event payloads, but the intended product is stricter: every RL
algorithm, every AlphaZero game, every tuning workflow, every model-family
checkpoint/reload/inference path, and every browser interaction must run
end-to-end with no synthetic, placeholder, demo-only, or parser-default
stand-ins. Sprint `11.9` removes the current browser parser-default residue and
adds generic/checkpoint-comparison route surfaces plus the RL/training/adversarial
visualization surface; it closed `✅ Done` on 2026-06-16 on that owned code
surface, with live checkpoint-backed interactions, live command-state
reconciliation, and Playwright proof owned downstream by Sprint `14.1` / `14.2`
and the Phase `15`/`16` live lanes (rule E). Phase `9` has its Sprint `9.12` code surface in place and has passed
linux-cpu, apple-silicon, and linux-cuda validation, so it is `✅ Done`.
Phase `10` has its Sprint `10.6` code surface in place and has passed
linux-cpu, linux-cuda, and apple-silicon validation, so it is `✅ Done`.
The 2026-06-15 bootstrap image-rebuild blocker had a validated Dockerfile fix
on the exact bootstrap-owned legacy-builder command, and all three live
integration lanes passed 71 / 71. At this 2026-06-14/16 checkpoint, Phase `13`
was still `🔄 Active`; Phases `11`–`12` re-closed `✅ Done` on 2026-06-16 (Sprints
`11.9` / `12.13` closed on their owned code surface, with the live-runtime
obligations deduped to Phases `15`/`16`/`14` per rule E); Phases `15`–`17` were
`⏸️ Blocked` behind the remaining runtime/browser surfaces; and Phases `14` and
`18` owned interactive demo/Playwright closure and final no-caveat product
handoff. Phases `0`–`12` were `✅ Done` on their owned
foundational/framework/frontend/test surfaces.

**Reopened 2026-06-13 (Apple Silicon host-resident workload placement).** Phase
`5` reopened and re-closed for Sprint `5.11`; Phase `12` reopened and re-closed
for Sprint `12.12`; Phase `16` reopened and re-closed for Sprint `16.10`; Phase
`17` reopened and re-closed for Sprint `17.7`. The Apple fixed bridge and
device selection remain valid, and the daemon now routes Apple Metal-backed
Training/RL/Tune starts through the Apple host daemon over Pulsar and MinIO.
Phase `12` asserts that no `jitml-rl-*` or sibling Apple Metal Job is created in
focused live tests, Phase `16` validates the full Apple lane through
`bootstrap/apple-silicon.sh test`, and Phase `17` moves the ledger row to
`Completed`. Phases `8`, `9`, and `10` stay
closed on their algorithm/checkpoint surfaces.

**Reopened and re-closed 2026-06-12 (true-headless Apple Metal fixed-bridge
doctrine).** Phase `1` reopened and re-closed for Sprint `1.15`; Phase `2`
reopened and re-closed for Sprint `2.12`; Phase `5` reopened and re-closed for
Sprint `5.10`; Phase `7` reopened and re-closed for Sprint `7.11`; Phase `16`
reopened and re-closed for Sprint `16.9`; Phase `17` re-closed after the Apple
lane passed and the deletion ledger became empty.

**Reopened 2026-06-10 (real-workflow refactor — superseded by the 2026-06-12
fixed-bridge closure and the 2026-06-13 placement reopen above).** A realness
audit found that every user-facing
workload and the demo used a synthetic/echo/pure-Haskell stand-in instead of the
substrate JIT path (`MlpDevice` → real `jitml_mlp_*` kernels) that the
`jitml-backends` lane already exercises. **Phases `8`–`12` reopened `🔄 Active` on
their code surfaces and Phases `15`–`17` on their live-runtime validation
surfaces**; Phases `0`–`7` stayed `✅ Done` (the engines and the backend lane are
real). As of 2026-06-12, Phases `8`, `9`, `10`, `11`, `12`, and `15` have
re-closed, and the subsequent Apple fixed-bridge closure re-closed Phases `16`
and `17` as of 2026-06-12. Exit-Definition items `6`, `8`, and `9` remain
strengthened; item `18` reopened and re-closed on 2026-06-13 with the Apple
placement ledger row now moved to `Completed`. Full detail and the exact
phase/sprint map live once in
[README.md → Closure Status / Reopened phases (2026-06-10)](README.md#reopened-phases-2026-06-10--real-workflow-refactor);
the historical baseline below is retained as dated record of the superseded state.

**Historical baseline before the 2026-06-13 placement reopen: all Phases
`0`, `1`, `2`, `3`, `4`, `5`, `6`, `7`, `8`, `9`, `10`, `11`, `12`, `15`, `16`, and `17` were `✅ Done`.** Phases `1`, `12`, `15`, `16`, and `17`
reopened `🔄 Active` on 2026-06-08 to remove the
cross-substrate numeric parity surface after the reproducibility contract was
clarified to within-substrate bit-for-bit only (across substrates there is no
guarantee — RNG draws and float reduction order differ). The reopened sprints are
`1.13` (remove `verify cross-backend`; add the `jitml test` `--test-options`
passthrough), `12.10` (realign `jitml-cross-backend` to within-substrate cases,
relocate the two agnostic cases to `jitml-unit`, remove the report-card
`cross_substrate_parity` field, wire substrate-partitioned test lanes with no
skips), `15.16` / `16.6` (re-validate the linux-cuda / apple-silicon lanes run
for real with the skip guards removed), and `17.4` (delete the parity surface
and reframe the determinism contract + Exit Definition to within-substrate
only). **On 2026-06-09 the full source/code removal landed and was validated** on
the `apple-silicon` lane (4 / 4 host-native) and the `linux-cpu` lane (10 / 10 in
the `jitml` container), plus `jitml-unit` 193 / 193, container `jitml check-code`,
and `jitml docs check` — all green. Sprints `1.13` and `16.6` re-closed `✅ Done`.
Sprints `12.10` / `15.16` / `17.4` then closed their one shared remaining
obligation on **2026-06-09**: the live `linux-cuda` lane was re-validated for
real on the NVIDIA GeForce RTX 5090 host (UUID
`GPU-e764ef97-32d7-4981-c348-029983c64073`) via the GPU-attached `jitml-cuda`
compose service —
`docker compose run --rm jitml-cuda cabal test -fcuda jitml-cross-backend
--test-options '-p linux-cuda'` passed **19 / 19 (12.26s, no skip-sentinels)**,
every within-substrate CUDA case a real device PASS. (`-fcuda` is the `cabal`
build flag compiling the real cuBLAS / cuDNN bindings — off by default to keep
the headless `jitml` baseline warning-clean — so the GPU lane runs through the
GPU container's `cabal test -fcuda` form, while the flag-free `jitml test`
orchestrator owns the apple-silicon / linux-cpu lanes.) With that run, **Sprints
`12.10` / `15.16` / `17.4` re-closed `✅ Done`, the last `Pending Removal` row
(the `linux-cuda` half of the skip-guard removal) moved to `Completed`, the
legacy ledger is empty, Exit Definition item 18 is met, and final handoff is
complete.** The 2026-06-10 Apple Silicon Tart-VM build-JIT doctrine reversal
reopened Phases `1`/`2`/`5`/`7`/`16` and the final handoff; all re-closed
`✅ Done` the same day after the live apple-silicon lane ran through the
Tart-VM-built path (`jitml test jitml-backends --apple-silicon`, 17/17 through
in-VM `swift build` + host Metal execution), so the six Tart-reversal ledger
rows moved to `Completed` and the ledger was empty / item 18 met again. That VM
doctrine was superseded by the 2026-06-12 fixed-bridge closure above. The earlier
reopen history stands
as dated record: **Phase `15` (all 15 sprints) and Phase `17` Sprints
`17.1`/`17.2` reopened `🔄 Active` on 2026-06-06 and re-closed `✅ Done` the
same day** (Sprint `17.3` stayed `✅ Done`) after re-validating the live CUDA,
GPU-training, cross-substrate, and final-`jitml test all` obligations on the
current **RTX 5090** host (UUID `GPU-e764ef97-32d7-4981-c348-029983c64073`,
CUDA 12.8, driver `570.211.01`, compute capability `12.0`); the original
evidence ran on an RTX 3090 (Plan Standards rule C). The re-validation passed
`jitml-cross-backend -fcuda` 38 / 38 (incl. `CrossSubstrate`), a fresh
`jitml bootstrap --linux-cuda` with the in-pod `nvidia-smi` reporting the
RTX 5090, the live `jitml-integration` cohort 19 / 19, live MNIST SL
convergence, PPO/cartpole RL convergence, and `jitml test all --live` 8 / 8
stanzas with a populated report card; the flagged `nvcc -arch=sm_70` →
Blackwell `sm_120` PTX forward-JIT was confirmed (no `-arch` bump). See
[README.md → Reopened phases (2026-06-06)](README.md#reopened-phases-2026-06-06).
Phase `1` reopened then re-closed on 2026-06-04 after
Sprint `1.12` landed the CLI Dhall override surface
(`train --substrate / --seed`, `rl train --substrate / --seed`,
`tune --sampler / --scheduler / --pruner / --trials / --parallelism`) honoring
[../README.md → Hyperparameter tuning, first-class](../README.md#hyperparameter-tuning-first-class)
line 1050 and pillar 2 at
[../README.md → Why this exists](../README.md#why-this-exists). The
pure `JitML.Experiment.Overrides.applyOverrides` resolver substitutes CLI
values into the parsed experiment Dhall before validation; the README
registry/tree, `documents/cli/commands.md`,
`documents/engineering/cli_command_surface.md`, the manpage, and the shell
completions were regenerated via `jitml docs generate`; the doctrine-deviation
row in [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
moved to `Completed`. Phase `1` previously also reopened and re-closed on
2026-06-04 after Sprint
`1.10` removed the scoped `allow-newer` block and Sprint `1.11` moved the
project to a single GHC `9.12.4` baseline with no source pins, no local
dependency packages, and no reopened-phase development ledger. Phase `8` and
Phase `9` re-closed on 2026-06-04 after `KeyDoorGrid-v0` landed and the
required RL matrix retargeted away from `atari-subset`. Phases `2`,
`3`, `4`, and `5`
**reopened then re-closed on 2026-05-29** after four workstreams hardening
the cluster against host exhaustion and aligning run configuration and
subprocess control-flow with project doctrine landed: the Dhall
`dhall/cluster/` resource profile + kind-node memory/CPU cap + the
`cluster.host-memory` preflight (Phase `2` Sprint `2.8`), the right-sized
manual-PV layout (Phase `3` Sprint `3.2`), the per-pod resource limits and
right-sized replicas across the platform stack (Phase `4` Sprint `4.8`), and
the typed Dhall `RunConfig` + BootConfig-mounted worker dispatch that retires
the `JITML_*` run-parameter environment-variable IPC (Phase `5` Sprint
`5.7`); the reconciler + readiness `sh -c` control-flow also moved to typed
Haskell with `RetryPolicy` (Phases `2` Sprint `2.9` / `4` Sprint `4.8`). The
originating incident is the 2026-05-29 cluster OOM storm that froze the
host. The changes implement already-in-scope doctrine (`Application
Environment`, `Subprocesses as Typed Values`, `Retry Policy as First-Class
Values`), so [Doctrine Scope](#doctrine-scope) is unchanged. The live
re-validation of every reopened-phase obligation is owned by Phase `15`
(closed 2026-05-30 on the RTX 3090, 15 / 15 sprints Done; reopened and
re-closed 2026-06-06 after re-validation on the RTX 5090); the
doctrine-deviation removals are tracked in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md). See
[README.md → Reopened phases (2026-05-29)](README.md#reopened-phases-2026-05-29).
Sprint `1.4` closes the
container-exclusive Haskell style/code-quality rule: the mandatory
`jitml:local` image build uses the same pinned GHC `9.12.4` to build pinned
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
variant runs `nvidia-smi -L` inside the service container, and the Apple
Silicon host-Dhall path completes `./bootstrap/apple-silicon.sh up` on
`edge_port: 9090` before the host-native
`jitml service --consume-once 0` run acquires
`inference.command.apple-silicon` as `jitml-host`.
Phase `3` reclosed on 2026-05-23 after live Linux CPU bootstrap and teardown
validated the single-node topology.
Phase `7` (JIT codegen) closed its code surface on 2026-05-24 against an
RTX 3090 + CUDA 12.8 validation host; the live CUDA execution obligation it
fed migrated to Phase `15`, which reopened 2026-06-06 for re-validation on the
RTX 5090 (the RTX 3090 record here is retained as dated history). Phases `8` (supervised learning + RL framework),
`9` (RL catalog + AlphaZero + tuning),
`10` (checkpointing + inference), `11` (PureScript frontend + demo), and
`12` (test stanzas, lint matrix, live workflow matrix) closed on
2026-05-25 — every owned code-surface obligation landed in the worktree;
each phase's live obligations migrated to Phases `15` / `16` / `17`.
Phase `8` Sprint `8.3` (lunar-lander + atari-subset simulators) originally
closed through pure-Haskell ports in `src/JitML/RL/Simulator.hs`; Sprint `8.8`
retired the deterministic `atari-subset` stand-in behind explicit ROM handling,
and the static-foreign-source correction removed the checked-in C++ shim path.
Sprint `8.9` landed the `KeyDoorGrid-v0` copyright-free default demo
replacement, and Phase `9` Sprint `9.8` retargeted the required RL matrix to
use it.
Per-sprint Remaining Work blocks list the open work; the dependency-ordered
sequence lives in
[README.md → Execution Roadmap](README.md#execution-roadmap).

| Surface | Current Repo State | Intended End State |
|---------|--------------------|--------------------|
| Repository layout | Sprints `1.1` through `12.9` have landed the library-first Haskell CLI, AppError, cache, docs, env, lint, plan, subprocess, prerequisite, bootstrap, route, cluster-renderer, service-config, numerical-catalog, engine, runtime-source, SL/RL/tuning, checkpoint, web-contract, and report modules; stage-0 scripts; generated CLI docs; `compose.yaml`, `docker/`, `chart/`, `kind/`, `dhall/`, `web/`, `infra/`, `proto/`, and `experiments/` surfaces; and dedicated test bodies for every Cabal stanza. Sprint `1.15` removed the VM command surface, Sprints `2.12` / `5.10` removed Tart prerequisite/bootstrap and daemon acquire/config residue, and Sprint `7.11` removed the generated Swift/Tart cache-miss code path. | Full library-first Haskell layout with Haskell-owned runtime JIT source generation per [../README.md → Repository layout (target)](../README.md#repository-layout-target) |
| Build artefacts | The Cabal package declares one supported executable, `jitml`; `bootstrap/apple-silicon.sh build` targets `./.build/jitml`; the `jitml-demo` image/tag/workload is a retagged Webapp role of that binary. The typed JIT cache key/layout/manifest layer is implemented; Apple uses `.metal.json` source metadata plus a fixed host bridge under `./.build/host/apple-silicon/`; `jitml build --dry-run --substrate <substrate>` renders generated-source compile plans under `./.build/jit-src/<substrate>/<hash>/`; non-dry-run `jitml build` routes the selected JIT artifact through `JitML.Engines.Loader`; `jitml-cross-backend` validates generated Linux CPU libdnnl-linked oneDNN primitive compile/load/run paths plus exported family/output-count metadata, local Linux CPU `HasEngine` dispatch, Linux CPU benchmark candidate measurement through generated FFI output digests, and Apple fixed-bridge Metal execution in the Apple lane; `jitml-unit` validates the CUDA host-callable wrapper/source ABI and guarded local CUDA runner fail-closed path | `cabal build all`-produced `jitml` binary, generated JIT compiler inputs under `./.build/jit-src/<substrate>/<hash>/`, plus per-substrate JIT-cache artefacts under `./.build/jit/<substrate>/` |
| CLI surface | The full command family is registered and parseable from `CommandSpec`; implemented commands cover bootstrap materialization with no-op exit `3`, live Kind/Helm bootstrap, doctor/remediation, commands/help, docs, lint/check-code, Plan/Apply dry-runs, env resolution, AppError rendering, cluster status/up/down/reset summaries, typed Kind down execution, service dry-run/surface rendering plus HTTP listener startup and bounded `--consume-once` daemon batch execution, daemon workload dispatch from parsed Training/RL/Tune command envelopes into Kubernetes Job apply/delete effects, train/eval/tune/RL/inference execution paths, test report rendering, internal substrate materialization, dataset upload, generated-source build-plan rendering, and cache stubs. Sprint `5.11` replaced Apple Metal-backed Job placement with host-resident workload commands while preserving Linux Job placement. Sprint `1.15` removed the `jitml internal vm` group from the implemented command surface and regenerated the CLI mirrors. The lint stack enforces config presence, whitespace normalization, forbidden paths, generated-doc drift, chart-shape checks, forbidden subprocess/terminal primitives, static JIT source/build artefact rejection, external `fourmolu`, `hlint`, `cabal format`, and warning-clean build execution inside `jitml:local`; host lint/check-code execution fails before linting. | The complete `jitml` command family parses and runs against three substrates: `doctor`, `cluster {up,down,status,reset}`, `service`, `train`, `eval`, `tune`, `rl {train,eval,rollout}`, `verify {same-run,replay}`, `inspect {list,show,replay,trial,frontier}`, `bench {train,inference,env}`, `inference run`, `test`, `lint`, `docs`, `check-code`, `build`, `kubectl`, `internal {materialize-substrate,list-prereqs,upload-dataset,gc,cache}`, `commands`, and `help`; the `jitml-demo` HTTP surface is the Webapp role run by `jitml service` |
| Test stanzas | Eight Cabal stanzas are declared with dedicated deterministic bodies; `jitml-unit` covers CLI/docs/prerequisite/env/cache/checkpoint-store surfaces, `jitml-integration` covers subprocess/bootstrap/renderers, BootConfig-derived daemon client settings, linkable oneDNN probing, local checkpoint inference through a Linux CPU generated oneDNN kernel, and live daemon/event dispatch cases, `jitml-cross-backend` includes generated Linux CPU oneDNN primitive compile/load/run, family/output-count symbol checks, local Linux CPU `HasEngine` dispatch, Linux CPU benchmark candidate measurement, and per-substrate run-to-run bit-identity (within-substrate reproducibility); `jitml-daemon-lifecycle` covers injected engine-backed daemon inference dispatch, and `jitml-e2e` includes typed live-plan rendering plus report-card knob parsing. Sprint `12.12` adds failed Kubernetes Job fail-fast diagnostics, bounded host-command polling, and Apple host-resident placement assertions while preserving Linux Job assertions. | Eight Cabal stanzas: `jitml-unit`, `jitml-integration`, `jitml-sl-canonicals`, `jitml-rl-canonicals`, `jitml-hyperparameter`, `jitml-cross-backend`, `jitml-daemon-lifecycle`, `jitml-e2e` |
| Toolchain | `jitml.cabal` pins `tested-with: ghc ==9.12.4`; `cabal.project` pins `with-compiler: ghc-9.12.4`, records the codegen-toolchain comments and report-card knobs, carries no `allow-newer`, no `source-repository-package` pins, and no local dependency packages, and `jitml doctor --scope toolchain` validates the Sprint `2.2` host toolchain prerequisites after typed remediation. Plain Hackage solves under the GHC `9.12.4` / `base-4.21` baseline. Phase `8` Sprint `8.8` leaves only pinned ALE library/runtime prerequisites for optional external/generated `atari-subset` adapter experiments, while Sprint `8.9` moved default demos to `KeyDoorGrid-v0`. | GHC `9.12.4`, Cabal `3.16.1.0`, LLVM pinned in `cabal.project`, NVCC pinned, optional ALE library/runtime pinned in `docker/Dockerfile`, host OS Metal runtime + fixed bridge for core Apple execution, optional `swiftc`/macOS SDK only for non-core Swift JIT modules, oneDNN pinned, `kindest/node` pinned in `./kind/cluster-<substrate>.yaml`, and no `allow-newer` override |
| Determinism contract | Deterministic SL curves, RL trajectories, tuning trials, checkpoint inference, engine flags, Linux CPU oneDNN primitive execution, local Linux CPU `HasEngine` dispatch, CUDA host-wrapper source ABI, and per-substrate run-to-run bit-identity (within-substrate reproducibility) are covered by dedicated Cabal stanzas. Cross-substrate equivalence is out of contract and not asserted | Enforced by the `jitml-integration` (same-substrate bit-equality), `jitml-sl-canonicals`, `jitml-rl-canonicals`, and `jitml-cross-backend` stanzas plus the per-substrate determinism notes in [../documents/engineering/determinism_contract.md](../documents/engineering/determinism_contract.md) |
| Frontend | `web/` contains the PureScript shell, generated browser contracts from `src/JitML/Web/Contracts.hs`, Halogen panel modules under `web/src/Panels/`, and a `spec-node` `purescript-spec` smoke suite under `web/test/`; Sprint `11.9` adds current-panel generated payload parsers and request renderers, generated training/RL/tune command-envelope controls, request-aware command publication when a live cluster publication is present, checkpoint-runtime-backed MNIST/generic/CIFAR/checkpoint-compare/Connect 4 REST route injection, training metadata, RL replay scrub summaries, multi-game adversarial boards, and non-placeholder summary charts; `src/JitML/Web/Server.hs` serves the demo/API/WebSocket surface; the live-only Playwright scaffold drives the published edge route | PureScript shell under `web/`, generated contracts from `src/JitML/Web/Contracts.hs`, panel modules under `web/src/Panels/`, Playwright scaffold under `playwright/`, demo surface served by `jitml-demo` |

## Related Documents

- [README.md](README.md)
- [development_plan_standards.md](development_plan_standards.md)
- [system-components.md](system-components.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
- [../README.md](../README.md)
- [../README.md](../README.md)
