# System Components

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md),
[development_plan_standards.md](development_plan_standards.md),
[00-overview.md](00-overview.md),
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

> **Purpose**: Authoritative target component inventory for the jitML Haskell CLI, the
> three substrates, the bootstrap reconciler, the cluster substrate, the stateful
> platform services, the `jitml service` daemon, the numerical core, the JIT codegen
> drivers, the SL/RL/AlphaZero/tuning surfaces, the checkpoint format, the PureScript
> frontend, and the Cabal test stanzas.

The inventory documents the authoritative end state. Phase `0` is `✅ Done`;
Phase `1` is `🔄 Active` only because Sprint `1.4` still needs the external
Fourmolu / hlint style-tools GHC bootstrap; Phases `2` through `12` are
`✅ Done` for their local typed renderer, catalog, command, and Cabal-stanza
surfaces. Live multi-service rollout remains a validation concern for the
cross-cluster test narrative. Status moves to `🔄 Active` and then `✅ Done` as
each owning sprint closes per
[development_plan_standards.md → C. Honest Completion
Tracking](development_plan_standards.md#c-honest-completion-tracking).

Rows marked `✅ Done` name implemented local surfaces in the current worktree.
When a command or Cabal stanza is intentionally local-only before live
infrastructure validation, the row distinguishes that body from the later
live-cluster exercise.

## Substrates

| Substrate | Identifier | Codegen | Container Shape | Daemon Topology | Status | Owning Phase |
|-----------|------------|---------|-----------------|-----------------|--------|--------------|
| Apple Silicon | `apple-silicon` | Swift + Metal | partial — cluster services in Kind; second `jitml service` runs host-native (Metal cannot be containerized) | two instances of one binary, distinguished by Dhall: `Cluster + ForwardToHost` (in-pod) + `Host + SelfInference` (host-native) | ✅ Done | [Phase 7](phase-7-jit-codegen-and-substrates.md) |
| Linux CPU | `linux-cpu` | oneDNN + AVX2/AVX-512 | fully containerized: `jitml:local` | one daemon: `Cluster + SelfInference` | ✅ Done | [Phase 7](phase-7-jit-codegen-and-substrates.md) |
| Linux CUDA | `linux-cuda` | CUDA C + cuBLAS / cuDNN | fully containerized: `jitml:local` (CUDA activates at runtime when scheduled to `runtimeClassName: nvidia`) | one daemon: `Cluster + SelfInference`, pod anti-affinity = one per node | ✅ Done | [Phase 7](phase-7-jit-codegen-and-substrates.md) |

A fourth substrate `linux-opencl` (Intel GPU) is admitted as a future extension and
is not in the current support matrix.

## Haskell CLI Surface

| Surface | Command | Purpose | Status | Owning Sprint |
|---------|---------|---------|--------|---------------|
| Bootstrap | `jitml bootstrap --apple-silicon\|--linux-cpu\|--linux-cuda` | Plan/Apply substrate bootstrap surface; stage-0 handoff, prerequisite remediation, JIT cache layers, Docker/Compose handoff, chart/materialization, Kind config rendering, publication metadata, and per-substrate Dhall rendering are present | ✅ Done | Sprints 2.1–2.7 |
| Service daemon | `jitml service` | Long-running daemon parameterised entirely by Dhall config (`BootConfig` / `LiveConfig`); no separate `host-service` verb | ✅ Done | Sprint 5.1 |
| Cluster lifecycle | `jitml cluster up`, `jitml cluster down`, `jitml cluster status`, `jitml cluster reset` | Plan/Apply rollout, preserving teardown, status reporting, and destructive reset guarded by `--yes` | ✅ Done | Sprint 3.5 |
| Train | `jitml train` | Plan/Apply: run a training job described by an experiment Dhall, publish events on `training.event.<mode>` | ✅ Done | Sprint 8.2 |
| Eval | `jitml eval` | Evaluate a trained model or policy against a deterministic evaluation cohort | ✅ Done | Sprint 8.2 |
| Tune | `jitml tune` | Plan/Apply: run a hyperparameter sweep described by a tuning Dhall, publish trial events on `tune.event.<mode>` | ✅ Done | Sprint 9.5 |
| RL lifecycle | `jitml rl train`, `jitml rl eval`, `jitml rl rollout` | Plan/Apply RL training, deterministic policy evaluation, and fixed-seed rollout cohorts | ✅ Done | Sprint 8.5 |
| Verification | `jitml verify same-run`, `jitml verify cross-backend`, `jitml verify replay` | Same-substrate byte-equality, cross-backend tolerance, and checkpoint replay verification | ✅ Done | Sprints 10.4, 12.2, 12.6 |
| Inspection | `jitml inspect list`, `jitml inspect show`, `jitml inspect replay`, `jitml inspect trial`, `jitml inspect frontier` | Inspect cached transcripts, checkpoints, trials, and hyperparameter frontiers | ✅ Done | Sprints 9.7, 10.4 |
| Benchmarks | `jitml bench train`, `jitml bench inference`, `jitml bench env` | Reproducible benchmark harnesses for training, inference, and environment-step throughput | ✅ Done | Sprint 12.9 |
| Inference | `jitml inference run` | Inference-at-any-point against `latest`, `best/<metric>`, or a manifest SHA | ✅ Done | Sprint 10.4 |
| Test runner | `jitml test all` / `jitml test <stanza>` | Plan/Apply over Cabal test stanzas plus the pinned report-card workload | ✅ Done | Sprint 12.9 |
| Lint stack | `jitml lint files\|docs\|proto\|chart\|haskell\|purescript\|all` | Current in-repo hygiene, config, forbidden-path, generated-doc, chart-shape, and forbidden-primitive checks are implemented; external formatter/hlint/cabal-format/build runners remain open on the style-tools GHC bootstrap | 🔄 Active | Sprint 1.4 |
| Docs generation | `jitml docs check` / `jitml docs generate` | Paired generated-section check and write per the `GeneratedSectionRule` registry | ✅ Done | Sprint 1.3 |
| Command introspection | `jitml commands [--tree\|--json]` | Flat list, tree rendering, or JSON command schema from the `CommandSpec` registry | ✅ Done | Sprint 1.2 |
| Focused help | `jitml help <subcommand>` | Equivalent to `<subcommand> --help`; same renderer | ✅ Done | Sprint 1.2 |
| Code quality gate | `jitml check-code` | Delegates to the in-repo lint stack and passes on the current tree; external `fourmolu`, `hlint`, `cabal format`, and warning-clean build execution remains open | 🔄 Active | Sprint 1.4 |
| Build | `jitml build` | Build-plan surface for the inner Haskell binary inside the substrate container; mirrors `bootstrap/<substrate>.sh build` semantics from inside the daemon | ✅ Done | Sprint 2.4 |
| Prerequisite doctor | `jitml doctor [--scope toolchain\|container\|cluster] [--remediate]` | In-process prerequisite registry reconciliation and typed remediation apply/postcondition validation | ✅ Done | Sprint 2.2 |
| Kubectl passthrough | `jitml kubectl` | `kubectl` passthrough pre-bound to `./.build/jitml.kubeconfig` | ✅ Done | Sprint 3.5 |
| Internal prerequisite listing | `jitml internal list-prereqs` | Prints the typed prerequisite registry from the current Haskell process | ✅ Done | Sprint 1.7 |
| Internal substrate materialization | `jitml internal materialize-substrate` | Validates the supported substrate identifier and renders Kind config, chart templates, publication metadata, and per-substrate Dhall | ✅ Done | Sprint 2.1 / Sprint 3.1 |
| Internal VM lifecycle (Apple) | `jitml internal vm bootstrap\|up\|down\|status\|exec` | Tart VM lifecycle state marker and typed pass-through debugging subprocess for Swift/Metal builds | ✅ Done | Sprint 2.5 |
| Internal cache inspection | `jitml internal cache stat\|list\|evict` | JIT cache introspection and idempotent eviction helpers; command leaves are registered, while effectful bodies wait for populated codegen entries | ✅ Done | Sprint 7.1 |
| Internal GC | `jitml internal gc <experiment-hash>` | Reconciler that enforces the experiment Dhall's `retain` policy on the checkpoint store; exit code `3` on no-op | ✅ Done | Sprint 10.3 |
| Demo HTTP server | `jitml-demo` | Sibling binary serving the PureScript bundle plus the inference REST surface; both binaries share the `src/JitML/` library | ✅ Done | Sprint 11.5 |

## Bootstrap Stage-0 Script Surface

The shell scripts are stage-0 entrypoints, not broad package reconcilers. They
fail fast with installation instructions, then delegate to the Haskell
`jitml bootstrap --<substrate>` command.

| Verb | Purpose | Status | Owning Sprint |
|------|---------|--------|---------------|
| `help` | Print supported subcommands | ✅ Done | Sprint 2.1 |
| `doctor` | Run only stage-0 host gates: Apple macOS/arm64/Xcode CLT/Homebrew; Linux Docker without `sudo`; CUDA NVIDIA runtime and compute capability | ✅ Done | Sprint 2.1 |
| `build` | Apple convenience to build `./.build/jitml`; Linux builds the one-service `jitml:local` Compose image | ✅ Done | Sprint 2.1 / Sprint 2.4 |
| `up` | Apple builds `./.build/jitml` and delegates to `jitml bootstrap --apple-silicon`; Linux calls the intended Compose handoff, with the actual `docker/compose.yaml` target delivered by Sprint 2.4 | ✅ Done | Sprint 2.1 |
| `status` | Report bootstrap-side stack health from `./.build/runtime/cluster-publication.json` | ✅ Done | Sprint 2.6 |
| `test` | Thin wrapper for `jitml test all` from outside the container | ✅ Done | Sprint 2.6 |
| `down` | Tear down the cluster; preserve `./.data/` and `./.build/`; on Apple, leave the tart VM up | ✅ Done | Sprint 2.7 |
| `purge` | Cluster down, `rm -rf ./.data/`, tart VM destroyed (Apple); preserves `./.build/` (including JIT cache) | ✅ Done | Sprint 2.7 |
| `purge --full` | `purge` plus `rm -rf ./.build/`; Linux additionally drops the substrate image | ✅ Done | Sprint 2.7 |

## Cluster Substrate Components

| Component | Implementation | Status | Owning Sprint |
|-----------|----------------|--------|---------------|
| Per-substrate Kind config | `./kind/cluster-{apple-silicon,linux-cpu,linux-cuda}.yaml` rendered from `JitML.Cluster.Kind` | ✅ Done | Sprint 3.1 |
| Kind worker labels (CUDA) | `jitml.runtime/gpu=true` on the worker so the `nvidia` RuntimeClass binds | ✅ Done | Sprint 3.1 |
| Kubeconfig home | `./.build/jitml.kubeconfig`; `~/.kube/config` is never touched | ✅ Done | Sprint 3.5 |
| `extraMounts` of `./.build/` | Bind-mounts host `./.build/` into the Kind worker so the in-cluster `jitml-service` pod sees the same JIT artefacts the host built | ✅ Done | Sprint 3.1 |
| `jitml-manual` StorageClass | `kubernetes.io/no-provisioner`; the only StorageClass in the chart | ✅ Done | Sprint 3.2 |
| Manual PV templates | `chart/templates/pv-*.yaml`; one per replica with explicit `claimRef` | ✅ Done | Sprint 3.2 |
| HostPath layout | `./.data/<namespace>/<StatefulSet>/pv_<replica-int>/`; lint-enforced by `jitml lint chart` | ✅ Done | Sprint 3.2 |
| `GatewayClass/jitml-gateway` + `Gateway/jitml-edge` | Single localhost listener at `127.0.0.1:<edge-port>` | ✅ Done | Sprint 3.3 |
| `EnvoyProxy/jitml-edge` | NodePort service, `externalTrafficPolicy: Cluster`, port 30090 | ✅ Done | Sprint 3.3 |
| Route registry | `src/JitML/Routes.hs` — single source of truth for every HTTPRoute resource | ✅ Done | Sprint 3.4 |
| Generated HTTPRoute manifests | `chart/templates/httproute-*.yaml`, rendered from the route registry; hand edits fail `jitml lint chart` | ✅ Done | Sprint 3.4 |
| Cluster publication | `./.build/runtime/cluster-publication.json` — `edge_port`, Pulsar URL, MinIO URL, component health | ✅ Done | Sprint 3.5 |
| Phased deploy | Harbor first → Mirror/build into Harbor → Final (MinIO, Pulsar, Envoy, kube-prometheus-stack, TensorBoard, `jitml-service`, `jitml-demo`) | ✅ Done | Sprint 3.5 |

## Stateful Platform Services

| Component | Helm Subchart | Routing | Status | Owning Sprint |
|-----------|---------------|---------|--------|---------------|
| Harbor (image registry) | `harbor` | `/harbor` (portal), `/harbor/api` (API) | ✅ Done | Sprint 4.1 |
| Percona PG operator | `pg-operator` + Patroni-managed service Postgres | (internal — packaged services that require Postgres) | ✅ Done | Sprint 4.2 |
| MinIO (object store) | `minio` (4 distributed replicas) | `/minio/console`, `/minio/s3` | ✅ Done | Sprint 4.3 |
| Apache Pulsar | `pulsar` (3× ZK + 3× BK + 3× Broker + 3× Proxy + WebSocket) | `/pulsar/admin`, `/pulsar/ws` | ✅ Done | Sprint 4.4 |
| Envoy Gateway controller | `gateway-helm` | (controller — dispatches the GatewayClass) | ✅ Done | Sprint 3.3 |
| kube-prometheus-stack | `kube-prometheus-stack` | `/grafana`, `/prometheus` | ✅ Done | Sprint 4.5 |
| TensorBoard | jitML-owned `tensorboard` chart with MinIO event-storage backing | `/tensorboard` | ✅ Done | Sprint 4.6 |
| `jitml-service` Deployment | `chart/templates/deployment-jitml-service.yaml` | (internal Pulsar consumer) | ✅ Done | Sprint 5.6 |
| `jitml-demo` Deployment | `chart/templates/deployment-jitml-demo.yaml` | `/`, `/api`, `/api/ws` | ✅ Done | Sprint 11.5 |
| NVIDIA RuntimeClass (CUDA) | `chart/templates/runtimeclass-nvidia.yaml`; binds to nodes labelled `jitml.runtime/gpu=true` | (RuntimeClass — selected by the Linux CUDA Deployment podSpec) | ✅ Done | Sprint 4.7 |

## MinIO Bucket Layout

| Bucket | Purpose | Owning Sprint |
|--------|---------|---------------|
| `harbor-registry` | Harbor's S3 backend (128 MiB chunk size) | Sprint 4.3 |
| `jitml-checkpoints` | Training checkpoints; one prefix per experiment hash; content-addressed blobs + manifests + ETag-guarded pointers | Sprint 10.1 |
| `jitml-datasets` | Pinned source datasets (MNIST, Fashion-MNIST, CIFAR-10 binaries); SHA-256 verified against the experiment Dhall | Sprint 8.1 |
| `jitml-transcripts` | RL trajectory transcripts | Sprint 8.4 |
| `jitml-trials` | Hyperparameter trial transcripts; content-addressed by `sha256(resolved-dhall || trial-seed)` | Sprint 9.5 |
| `jitml-tensorboard` | TensorBoard event files; the TB pod is stateless | Sprint 4.6 |
| `jitml-artifacts` | Large inference outputs when the demo is in inference mode | Sprint 11.4 |

## Pulsar Topic Family

`<mode>` ∈ `apple-silicon`, `linux-cpu`, `linux-cuda`. Apple Silicon adds the
internal-RPC pair.

| Topic | Direction | Carrying | Owning Sprint |
|-------|-----------|----------|---------------|
| `training.command.<mode>` | control plane → daemon | `StartTraining`, `StopTraining`, `ResumeFromCheckpoint`, `AbortTraining` | Sprint 8.2 |
| `training.event.<mode>` | daemon → control plane / frontend | `StepDone`, `EpochDone`, `EvalDone`, `CheckpointDone`, `MetricUpdate`, `TrainingFinished`, `TrainingFailed` | Sprint 8.2 |
| `tune.command.<mode>` | control plane → daemon | `RunTrial`, `StopTrial` | Sprint 9.5 |
| `tune.event.<mode>` | daemon → control plane / frontend | `TrialStarted`, `TrialMetricUpdate`, `TrialFinished`, `TrialFailed` | Sprint 9.5 |
| `rl.command.<mode>` | control plane → daemon | `StartRLRun`, `StopRLRun` | Sprint 8.5 |
| `rl.event.<mode>` | daemon → control plane / frontend | `EpisodeDone`, `EvalDone`, `CheckpointDone`, `MetricUpdate` | Sprint 8.5 |
| `inference.request.<mode>` | demo frontend → daemon | inference requests (when demo is in inference mode) | Sprint 11.4 |
| `inference.result.<mode>` | daemon → demo frontend | inference results | Sprint 11.4 |
| `inference.command.apple-silicon` (Apple only) | cluster orchestrator → host daemon | internal RPC envelopes (`call-id`, `kind`, `model-id`, `starting-snapshot`, `reply-topic`, `inputs`) | Sprint 7.5 |
| `inference.event.apple-silicon` (Apple only) | host daemon → cluster orchestrator | ACK envelopes (`call-id`, `kind`, MinIO refs to outputs) | Sprint 7.5 |

## `jitml service` Daemon Surface

| Component | Doctrine Section | Status | Owning Sprint |
|-----------|------------------|--------|---------------|
| `BootConfig` Dhall (start-time only; restart-required) | Long-Running Daemons in the Same Binary → BootConfig | ✅ Done | Sprint 5.2 |
| `LiveConfig` Dhall (hot-reloadable on SIGHUP) | Long-Running Daemons in the Same Binary → LiveConfig | ✅ Done | Sprint 5.2 |
| SIGHUP hot reload handler | Long-Running Daemons in the Same Binary | ✅ Done | Sprint 5.2 |
| `/healthz` endpoint | Long-Running Daemons → /healthz | ✅ Done | Sprint 5.3 |
| `/readyz` endpoint | Long-Running Daemons → /readyz | ✅ Done | Sprint 5.3 |
| `/metrics` endpoint | Long-Running Daemons → /metrics | ✅ Done | Sprint 5.3 |
| Structured JSON stderr logging | Long-Running Daemons → structured logging | ✅ Done | Sprint 5.3 |
| Recoverable-vs-fatal error kinds | Long-Running Daemons → error classification | ✅ Done | Sprint 5.3 |
| `HasMinIO` capability class | Capability Classes and Service Errors | ✅ Done | Sprint 5.4 |
| `HasPulsar` capability class | Capability Classes and Service Errors | ✅ Done | Sprint 5.4 |
| `HasHarbor` capability class | Capability Classes and Service Errors | ✅ Done | Sprint 5.4 |
| `HasKubectl` capability class | Capability Classes and Service Errors | ✅ Done | Sprint 5.4 |
| `RetryPolicy` typed value | Retry Policy as First-Class Values | ✅ Done | Sprint 5.4 |
| At-least-once Pulsar consumer | At-Least-Once Event Processing | ✅ Done | Sprint 5.5 |
| Protobuf-message-hash deduplication keys | At-Least-Once Event Processing → idempotency | ✅ Done | Sprint 5.5 |
| Stateless `Deployment` (not `StatefulSet`) | Long-Running Daemons | ✅ Done | Sprint 5.6 |
| Pod anti-affinity (`topologyKey: kubernetes.io/hostname`) | Long-Running Daemons | ✅ Done | Sprint 5.6 |

## Numerical Core Inventory

| Component | Implementation | Status | Owning Sprint |
|-----------|----------------|--------|---------------|
| Layer catalog (Dense, Conv1D, Conv2D, Conv3D, ConvTranspose, BatchNorm, LayerNorm, GroupNorm, Dropout, ResidualBlock, MultiHeadAttention) | `src/JitML/Numerics/Catalog.hs`; rendered through `renderNumericalCatalog` | ✅ Done | Sprint 6.1 |
| Real-valued activations (ReLU, GELU, Tanh, Sigmoid, Softmax) | `src/JitML/Numerics/Catalog.hs` | ✅ Done | Sprint 6.2 |
| Complex-valued activations (ComplexModRelu, ComplexCardioid) | `src/JitML/Numerics/Catalog.hs` | ✅ Done | Sprint 6.2 |
| Spectral / frequency-domain ops (FFT, IFFT, STFT, DCT) | `src/JitML/Numerics/Catalog.hs` | ✅ Done | Sprint 6.3 |
| Optimizers (SGD, Momentum SGD, Nesterov SGD, RMSProp, Adagrad, Adadelta, Adam, AdamW, LAMB, LARS, Lion) | `src/JitML/Numerics/Catalog.hs` | ✅ Done | Sprint 6.4 |
| Schedulers (constant, linear, cosine, cosine-with-warmup, exponential, polynomial, one-cycle, piecewise) | `src/JitML/Numerics/Catalog.hs` | ✅ Done | Sprint 6.4 |
| Loss functions (cross-entropy, focal, MSE, Huber, IoU) | `src/JitML/Numerics/Catalog.hs` | ✅ Done | Sprint 6.5 |
| Experiment Dhall fixtures that exercise the catalog | `experiments/mnist.dhall`, `experiments/mnist-tune.dhall`, `experiments/cartpole.dhall` | ✅ Done | Sprint 6.6 |

## JIT Codegen Components

| Component | Implementation | Status | Owning Sprint |
|-----------|----------------|--------|---------------|
| Apple Silicon engine (Metal codegen + host daemon shim + lazy tart spin-up) | `src/JitML/Engines/Engine.hs`, `src/JitML/Tart/{Lifecycle,Exec}.hs`; generated Swift / Metal inputs under `./.build/jit-src/apple-silicon/<hash>/` | 🔄 Active | Sprints 7.5, 7.7 |
| Linux CPU engine (oneDNN codegen) | `src/JitML/Engines/Engine.hs`; generated oneDNN C++ inputs under `./.build/jit-src/linux-cpu/<hash>/` | 🔄 Active | Sprints 7.3, 7.7 |
| Linux CUDA engine (CUDA C codegen) | `src/JitML/Engines/Engine.hs`; generated CUDA inputs under `./.build/jit-src/linux-cuda/<hash>/` | 🔄 Active | Sprints 7.4, 7.7 |
| Haskell-owned runtime JIT source generation | `src/JitML/Codegen/RuntimeSource.hs` (target); no checked-in `.cu`, `.cc` / `.cpp`, Metal / Swift package source, or JIT build `.sh` files | 🔄 Active | Sprint 7.7 |
| Content-addressed cache key shape | `src/JitML/Cache/Key.hs`; `KernelSpec` hashes `(canonical payload, kind, substrate, toolchain-fingerprint)` | ✅ Done | Sprint 2.3 |
| Cache root layout | `src/JitML/Cache/Layout.hs`; `./.build/jit/<substrate>/<hash>.<ext>` plus `manifest.json` path resolution | ✅ Done | Sprint 2.3 |
| Cache manifest index | `src/JitML/Cache/Manifest.hs`; JSON round-trip, lookup, upsert, read, and atomic write helpers | ✅ Done | Sprint 2.3 |
| Apple stable FFI symlink surface | `src/JitML/Cache/Symlink.hs`; `./.build/host/apple-silicon/<model-id>.dylib` repoints atomically into `jit/apple-silicon/` | ✅ Done | Sprint 2.3 |
| Hardware auto-tuning | per-substrate reduction strategy / tile size / prefetch width selection preserving the determinism contract | ✅ Done | Sprint 7.6 |
| Apple Silicon host↔cluster RPC contract | `inference.command.apple-silicon` / `inference.event.apple-silicon` envelope shape | ✅ Done | Sprint 7.5 |

## Training Workload Surfaces

| Component | Implementation | Status | Owning Sprint |
|-----------|----------------|--------|---------------|
| Supervised training loops | `src/JitML/SL/Canonicals.hs`; command surface in `src/JitML/App.hs` | ✅ Done | Sprint 8.1 |
| Canonical SL problem set | `src/JitML/SL/Canonicals.hs`; deterministic coverage in `test/sl-canonicals/Main.hs` | ✅ Done | Sprint 8.1 |
| Canonical RL environments (cartpole, mountain-car, lunar-lander, atari-subset) | `src/JitML/Env/` | ✅ Done | Sprint 8.3 |
| RL Algorithm class taxonomy and policy/environment surface | `src/JitML/RL/Algorithms.hs`; deterministic command summaries in `src/JitML/App.hs` | ✅ Done | Sprint 8.4 |
| Replay/rollout trajectory determinism | `src/JitML/RL/Algorithms.hs`; `deterministicTrajectory` | ✅ Done | Sprint 8.4 |
| Schedules, action distributions, action noise, target networks, GAE, callbacks, logger, evaluator | represented in the local RL catalog/report-card surface through `src/JitML/RL/Algorithms.hs`, `src/JitML/Test/Report.hs`, and `test/rl-canonicals/Main.hs` | ✅ Done | Sprint 8.5 |
| Training loops as typed pipelines | Plan/Apply command rendering in `src/JitML/Plan/Plan.hs` and `src/JitML/App.hs` | ✅ Done | Sprint 8.6 |
| RL algorithm catalog (PPO, A2C, TRPO, MaskablePPO, RecurrentPPO, DQN, QR-DQN, DDPG, TD3, SAC, CrossQ, TQC, ARS, HER) | `src/JitML/RL/Algorithms.hs` | ✅ Done | Sprints 9.1–9.3 |
| RL golden tests | `test/golden/rl/` | ✅ Done | Sprint 9.4 |
| AlphaZero-style self-play and persistent MCTS state | `src/JitML/RL/AlphaZero.hs` | ✅ Done | Sprint 9.5 |
| Perfect-information game, two-headed network, and arena summary surface | `src/JitML/RL/AlphaZero.hs` | ✅ Done | Sprint 9.5 |
| Canonical adversarial games (Connect 4, Othello, Hex, Gomoku) | `src/JitML/RL/AlphaZero.hs`; generated browser contract endpoint in `src/JitML/Web/Contracts.hs` | ✅ Done | Sprint 9.6 |
| Hyperparameter tuning (sampler × scheduler × pruner) | `src/JitML/Tune/Catalog.hs` | ✅ Done | Sprint 9.7 |
| Trial storage and resume summary surface | `src/JitML/Tune/Catalog.hs`; command rendering in `src/JitML/App.hs` | ✅ Done | Sprint 9.7 |

## Checkpoint and Inference Components

| Component | Implementation | Status | Owning Sprint |
|-----------|----------------|--------|---------------|
| Storage layout (typed) | `src/JitML/Checkpoint/Format.hs`; bucket registry in `src/JitML/Storage/Buckets.hs` | ✅ Done | Sprint 10.1 |
| Split-blob layout (`blobs/<sha256>`, `manifests/<sha256>`, `pointers/{latest,best/<metric>,trial/...}`) | `src/JitML/Checkpoint/Format.hs` | ✅ Done | Sprint 10.1 |
| `.jmw1` dense weight blob format | `src/JitML/Checkpoint/Format.hs`; `encodeJmw1` | ✅ Done | Sprint 10.2 |
| Manifest pointer surface | `src/JitML/Checkpoint/Format.hs`; `CheckpointManifest`, `manifestPointer` | ✅ Done | Sprint 10.2 |
| Write-once and CAS protocol surface | local typed manifest/pointer plan in `src/JitML/Checkpoint/Format.hs` and `src/JitML/App.hs` | ✅ Done | Sprint 10.2 |
| Bit-determinism contract + cross-substrate tolerance methodology | [../documents/engineering/determinism_contract.md](../documents/engineering/determinism_contract.md) | ✅ Done | Sprint 10.3 |
| Inference-only read path | `src/JitML/Checkpoint/Format.hs`; `inferFromManifest` consumed by command/demo summaries | ✅ Done | Sprint 10.4 |
| Retention reconciler (`jitml internal gc <experiment-hash>`) | command plan rendering in `src/JitML/App.hs` | ✅ Done | Sprint 10.3 |
| TensorBoard checkpoint sidecar (`<step>-<manifest-sha>.cbor` under `jitml-tensorboard/<experiment-hash>/checkpoints/`) | `src/JitML/Observability/TensorBoard.hs` | ✅ Done | Sprint 4.6 |

## Frontend Components

| Component | Implementation | Status | Owning Sprint |
|-----------|----------------|--------|---------------|
| Halogen application | `web/src/` | ✅ Done | Sprint 11.1 |
| Browser-contract source ADTs | `src/JitML/Web/Contracts.hs` (source for `purescript-bridge`) | ✅ Done | Sprint 11.2 |
| Generated PureScript contracts | `web/src/Generated/Contracts.purs`; Sprint 11.2 promotes the reserved future generated-path pattern into an active `trackingGeneratedPaths` entry so hand edits fail `jitml lint files` | ✅ Done | Sprint 11.2 |
| `purescript-spec` unit tests | `web/test/` | ✅ Done | Sprint 11.3 |
| Playwright E2E suite | `playwright/jitml-demo.spec.ts` | ✅ Done | Sprint 11.6 |
| Bundle output | local scaffold under `web/`; runtime served by `jitml-demo` command surface | ✅ Done | Sprint 11.4 |
| MNIST live inference panel | `src/JitML/Web/Contracts.hs`, `web/src/Main.purs`, generated contract surface | ✅ Done | Sprint 11.4 |
| CIFAR/ImageNet upload panel | `src/JitML/Web/Contracts.hs`, `web/src/Main.purs`, generated contract surface | ✅ Done | Sprint 11.4 |
| AlphaZero-vs-human Connect 4 panel | `src/JitML/Web/Contracts.hs`, `web/src/Main.purs`, generated contract surface | ✅ Done | Sprint 11.4 |
| RL trajectory render panel | `src/JitML/Web/Contracts.hs`, `web/src/Main.purs`, generated contract surface | ✅ Done | Sprint 11.4 |
| Demo HTTP server (`jitml-demo`) | `app/Demo.hs` shim into `App.demoMain`; serves the generated frontend contract surface | ✅ Done | Sprint 11.5 |

## CLI Doctrine Components

Components introduced by the doctrine adoption sprints scheduled in
[phase-1-haskell-cli-surface.md](phase-1-haskell-cli-surface.md) and the surfaces
that consume them. Citations name the doctrine sections they implement per
standards rule L.

| Component | Doctrine Section | Status | Owning Sprint |
|-----------|------------------|--------|---------------|
| `CommandSpec` registry as implementation source | Automatically Generated Documentation; Command Topology | ✅ Done | Sprint 1.2 |
| `OptionSpec` record fields (`longName`, `shortName`, `metavar`, `description`, `required`) | Automatically Generated Documentation | ✅ Done | Sprint 1.2 |
| Per-leaf `Example` entries on every `CommandSpec` | Automatically Generated Documentation | ✅ Done | Sprint 1.2 |
| Parser generated from the registry (parser is a renderer, not the source of truth) | Command Topology | ✅ Done | Sprint 1.2 |
| Parser-test category via `execParserPure` | Testing Doctrine → Parser Tests | ✅ Done | Sprint 1.2 |
| `jitml commands --tree` and `jitml commands --json` introspection | Progressive Introspection | ✅ Done | Sprint 1.2 |
| `Subprocess` ADT plus `runStreaming` / `capture` interpreter; pure `renderSubprocess` | Architecture → Subprocesses as Typed Values | ✅ Done | Sprint 1.6 |
| Forbidden subprocess primitives (`callProcess`, `readCreateProcess`, `System.Process` constructors, `typed-process` smart constructors) | Architecture → Subprocesses as Typed Values | ✅ Done | Sprint 1.6 |
| `Plan` / `apply` boundary with `--dry-run` and `--plan-file <path>` | Plan / Apply | ✅ Done | Sprint 1.5 |
| `prerequisiteRegistry` with `nodeId`, `nodeDescription`, remedy hint, transitive closure | Prerequisites as Typed Effects | ✅ Done | Sprint 1.7 |
| Single `Env` record threaded via `ReaderT Env IO` | Application Environment | ✅ Done | Sprint 1.8 |
| Single `AppError` ADT (`PrerequisiteUnmet`, `SubprocessFailed`, `MinIOFailed`, `PulsarFailed`, `HarborFailed`, `KubectlFailed`, `DocsCheckDrift`, `UnknownCommand`, `InvalidConfig`, `DhallTypeError`, `ChartLintFailed`, `RouteRegistryDrift`, `JitCacheMiss`, `JitToolchainDrift`, `CheckpointFormatUnsupported`, `CheckpointWriteConflict`, `ReconcilerNoop`) | Error Handling | ✅ Done | Sprint 1.9 |
| `renderError :: AppError -> Text` boundary | Error Handling | ✅ Done | Sprint 1.9 |
| Exit code `3` for reconciler no-op-on-match | Error Handling | ✅ Done | Sprint 1.9 |
| HLint rule config currently hints on `print`, `exitFailure`, `callProcess`, and `readCreateProcess`; external hlint execution and broader terminal/process rules remain open | Error Handling | 🔄 Active | Sprint 1.4 |
| `--format json\|table\|plain` (default `table` on TTY else `plain`) | Output Rules | ✅ Done | Sprint 1.9 |
| `--color auto\|always\|never` plus `--no-color` | Output Rules | ✅ Done | Sprint 1.9 |
| `fourmolu.yaml` 12-setting list at repo root | Lint, Format, and Code-Quality Stack → Pinned fourmolu.yaml | ✅ Done | Sprint 1.4 |
| `cabal format` temp-file round-trip byte-equality check | Lint, Format, and Code-Quality Stack | 🔄 Active | Sprint 1.4 |
| `forbiddenPathRegistry` (`.github/workflows/`, `.husky/`, `.githooks/`, `.pre-commit-config.yaml`, root `Makefile`/`justfile`/`Taskfile.yml`) | Lint, Format, and Code-Quality Stack → Forbidden Surfaces | ✅ Done | Sprint 1.4 |
| `GeneratedSectionRule` registry for marker-delimited generated regions | Generated Artifacts → The generated-section registry | ✅ Done | Sprint 1.3 |
| `trackingGeneratedPaths` registry for active fully-generated files (`documents/cli/commands.md`, `share/man/man1/jitml.1`, shell completions) | Generated Artifacts → Two categories of generation | ✅ Done | Sprint 1.3 |
| `futureTrackingGeneratedPathPatterns` registry for later generated artefacts (`share/man/man1/jitml-*.1`, PureScript contracts, chart HTTPRoutes, Grafana dashboards) | Generated Artifacts → Two categories of generation | ✅ Done | Sprint 1.3 |
| GADT-indexed `TrainingLifecycle`, `RLRunLifecycle`, `TuneSweepLifecycle` | GADT-Indexed State Machines | ✅ Done | Sprint 8.4, 8.6, 9.7 |
| Capability classes (`HasMinIO`, `HasPulsar`, `HasHarbor`, `HasKubectl`) | Capability Classes and Service Errors | ✅ Done | Sprint 5.4 |
| `RetryPolicy` typed value with named strategies | Retry Policy as First-Class Values | ✅ Done | Sprint 5.4 |
| At-least-once Pulsar consumer with protobuf-message-hash deduplication | At-Least-Once Event Processing | ✅ Done | Sprint 5.5 |
| Long-running daemon shape (`BootConfig` / `LiveConfig`, SIGHUP, `/healthz`, `/readyz`, `/metrics`, structured JSON stderr logging) | Long-Running Daemons in the Same Binary | ✅ Done | Sprints 5.2, 5.3 |
| Implemented reconciler discipline (`jitml docs generate`, `jitml lint --write`, `--dry-run` / `--plan-file` plan rendering, no-op exit code `3`) | Reconcilers: Idempotent Mutation as a Single Command; Plan / Apply | ✅ Done | Sprints 1.3, 1.4, 1.5, 1.9 |
| Future mutating reconcilers (`jitml bootstrap` full apply, `jitml cluster up`, `jitml internal gc`) | Reconcilers: Idempotent Mutation as a Single Command | ✅ Done | Sprints 3.5, 10.3 |
| Cabal-manifest toolchain pin (`tested-with: ghc ==9.14.1` in `jitml.cabal`, `with-compiler: ghc-9.14.1` in `cabal.project`, codegen toolchains pinned in `cabal.project`) | Toolchain pinning | ✅ Done | Sprint 1.1 |
| Library-first layout audit (thin `app/Main.hs` and `app/Demo.hs`, logic in `src/JitML/`) | Project Structure | ✅ Done | Sprint 1.1 |
| Durable CLI documentation artefacts (`documents/cli/commands.md`, `share/man/man1/jitml*.1`, `share/completion/{bash,zsh,fish}/`) | Automatically Generated Documentation | ✅ Done | Sprint 1.3 |
| Standardized library set audit in `jitml.cabal` (`optparse-applicative`, `text`, `bytestring`, `aeson`, `prettyprinter*`, `ansi-terminal`, `path`, `path-io`, `typed-process`, `safe-exceptions`, `dhall`, `tasty*`, `temporary`) | Overview → standardized stack | ✅ Done | Sprint 1.1 |

## Test Stanzas

Per doctrine `Test Organization`, each tier is a separate Cabal `test-suite` with
`type: exitcode-stdio-1.0` and `tasty` as the in-stanza runner. A single `tasty`
tree spanning all tiers is forbidden. All ten stanza declarations exist today,
and each non-style phase stanza now has a dedicated local deterministic body.

| Stanza | Current body | Final Phase-Owned Scope | Status | Owning Sprint |
|--------|--------------|-------------------------|--------|---------------|
| `jitml-unit` | `test/unit/Main.hs` covers current parser, docs, prerequisite, env, app-error, plan, subprocess, bootstrap-script, and cache surfaces | Expand to every final Pure Logic, Parser, Property, and Golden category: engine invariants, numerical-core round-trips, RL framework primitives, AlphaZero MCTS invariants, hyperparameter sampler determinism, checkpoint codec round-trips, route registry, Grafana renderer, transcript codecs, RNG mixers, Sobol sequence golden, GA trace golden | ✅ Done | Sprint 12.1 |
| `jitml-integration` | `test/integration/Main.hs` covers a typed subprocess boundary and renderer suite | Expand to real-binary subprocess integration, checkpoint round-trip, resume semantics, Dhall→typed-record decode, and per-substrate determinism | ✅ Done | Sprint 12.2 |
| `jitml-sl-canonicals` | `test/sl-canonicals/Main.hs` | Eleven SL `(dataset, model)` pairs from [../README.md → Canonical supervised learning problems](../README.md#canonical-supervised-learning-problems), convergence golden, and per-distribution regression detection | ✅ Done | Sprint 12.3 |
| `jitml-rl-canonicals` | `test/rl-canonicals/Main.hs` | RL target matrix forms (2) and (3): same-substrate trajectory determinism plus per-seed final-reward distribution against committed fixtures | ✅ Done | Sprint 12.4 |
| `jitml-hyperparameter` | `test/hyperparameter/Main.hs` | Per-sampler reproducibility, per-scheduler reproducibility, per-pruner reproducibility, and resume-from-partial-sweep equality | ✅ Done | Sprint 12.5 |
| `jitml-cross-backend` | `test/cross-backend/Main.hs` | Cross-substrate cohort `(cpu, cuda)` and `(cpu, metal)` on the SL canon; per-tensor drift fits the committed tolerance band per [../documents/engineering/determinism_contract.md](../documents/engineering/determinism_contract.md) | ✅ Done | Sprint 12.6 |
| `jitml-daemon-lifecycle` | `test/daemon-lifecycle/Main.hs` | Spawn `jitml service`, poll `/readyz`, exercise the Pulsar consumer protocol, drive SIGHUP hot reload, and assert graceful drain on SIGTERM | ✅ Done | Sprint 12.7 |
| `jitml-e2e` | `test/e2e/Main.hs` | Pulumi-orchestrated ephemeral Kind stack + Playwright against the real Envoy listener across training control, MNIST handwriting, image upload, Connect 4 game-play, TensorBoard/Grafana navigation, and hyperparameter sweep | ✅ Done | Sprint 12.8 |
| `jitml-haskell-style` | `test/haskell-style/Main.hs` runs the current lint stack | Formatter, hlint/config, forbidden-path, chart, generated-section, external formatter/hlint/cabal-format/build gates, and optional future lints as they land | 🔄 Active | Sprint 1.4 |
| `jitml-purescript-style` | `test/purescript-style/Main.hs` | PureScript `purs format` round-trip plus `purescript-spec` smoke tests against the generated browser contracts | ✅ Done | Sprint 11.3 |

## Test Categories Mapping (Doctrine → Stanza)

| Doctrine Test Category | Owning Stanza |
|------------------------|---------------|
| Pure Logic | `jitml-unit` |
| Parser | `jitml-unit` |
| Property | `jitml-unit` |
| Golden | `jitml-unit` |
| Integration | `jitml-integration`, `jitml-sl-canonicals`, `jitml-rl-canonicals`, `jitml-hyperparameter`, `jitml-cross-backend` (the four canonicals/HPO/cross-backend rows are project-specific Integration per doctrine §Test Organization → project-specific stanzas) |
| Daemon Lifecycle | `jitml-daemon-lifecycle` |
| Pulumi-Orchestrated Infrastructure | `jitml-e2e` |
| Style (§Style as a Cabal test-suite) | `jitml-haskell-style` |
| Lint (project-specific) | `jitml-purescript-style` |

## POC Report-Card Knobs

Pinned in `cabal.project` for reproducibility across hosts; see
[phase-12-test-stanzas-and-cross-cluster.md](phase-12-test-stanzas-and-cross-cluster.md).

| Knob | Value | Purpose |
|------|-------|---------|
| `SL_EPOCHS` | `5` | Canonical SL training epoch count for golden curves |
| `SL_BATCH` | `64` | Canonical SL minibatch size for golden curves |
| `RL_STEPS` | `100_000` | Canonical RL training step budget for golden trajectories |
| `RL_EVAL_EPISODES` | `25` | Per-eval episode count for the RL Evaluator |
| `AZ_GAMES` | `200` | Self-play game count per AlphaZero generation in the golden suite |
| `AZ_SIMS` | `400` | MCTS simulation budget per move in the golden AlphaZero suite |
| `TUNE_TRIALS` | `64` | Trial count for the report-card tuning workload |
| `TUNE_BUDGET_PER_TRIAL` | `1_000` | Per-trial step budget for the report-card tuning workload |
| `XCLUSTER_KIND_NODES` | `2` | Worker count for the ephemeral `jitml-e2e` Kind stack |

## Toolchain

| Component | Pinned Version | Purpose | Status | Owning Sprint |
|-----------|----------------|---------|--------|---------------|
| GHC | `9.14.1` | Haskell compiler for the CLI binary, the daemon, and every library module | ✅ Done | Sprint 1.1 |
| Cabal | `3.16.1.0` | Haskell build tool; per-stanza `type: exitcode-stdio-1.0` | ✅ Done | Sprint 1.1 |
| LLVM | pinned in `cabal.project` | Shared by GHC `-fllvm` and JIT codegen | ✅ Done | Sprint 1.1 |
| NVCC | pinned in `cabal.project` (`--use_fast_math=false`, baseline `sm_70`) | CUDA kernel codegen for `linux-cuda` | ✅ Done | Sprint 7.4 |
| Xcode/Metal | pinned in bootstrap script + `cabal.project` | Metal kernel codegen for `apple-silicon` (runs inside the `jitml-build` tart VM) | ✅ Done | Sprint 7.5 |
| oneDNN | pinned in `cabal.project` (AVX2 baseline, AVX-512 detected at JIT time) | CPU kernel codegen for `linux-cpu` | ✅ Done | Sprint 7.3 |
| `kindest/node` | pinned in `./kind/cluster-<substrate>.yaml`; mirrored as a comment in `cabal.project` | Kind worker image; the comment-mirror is a single-source-of-toolchain-truth record (`jitml lint chart` rejects drift) | ✅ Done | Sprint 3.1 |
| `tart` | latest stable, `brew install cirruslabs/cli/tart` | macOS VM runner for the Apple Silicon Swift/Metal build; validated only through the first-JIT-cache-miss prerequisite root | ✅ Done | Sprint 2.2 |
| `kind` | Haskell prerequisite DAG | Kubernetes-in-Docker | ✅ Done | Sprint 2.2 |
| `kubectl` | Haskell prerequisite DAG | k8s API client invoked through the typed `Subprocess` boundary | ✅ Done | Sprint 2.2 |
| `helm` | Haskell prerequisite DAG | Helm CLI invoked through the typed `Subprocess` boundary | ✅ Done | Sprint 2.2 |
| `docker` | stage-0 Linux gate plus Haskell prerequisite DAG | Container runtime; the only host runtime touched on Linux | ✅ Done | Sprint 2.2 |
| Node.js | Haskell prerequisite DAG | Required by the PureScript toolchain (`spago`, `purescript`) and Pulumi | ✅ Done | Sprint 2.2 |
| Poetry | Haskell prerequisite DAG | Required for ancillary Python tooling (none on the supported runtime path; only present for codegen support tools) | ✅ Done | Sprint 2.2 |
| Formatter GHC | separate isolated install under `.build/jitml-style-tools/` | Lint stack only; never affects the project compiler | 🔄 Active | Sprint 1.4 |
| `purescript-bridge` | pinned in `cabal.project` | Generates PureScript contracts from `src/JitML/Web/Contracts.hs` | ✅ Done | Sprint 11.2 |
| Pulumi (TypeScript) | pinned in `infra/pulumi/package.json` | Ephemeral-Kind orchestrator for `jitml-e2e` | ✅ Done | Sprint 12.8 |
| Target platforms | `arm64` macOS (Apple Silicon), `amd64` Linux, optional `arm64` Linux | Three substrates × supported host arches | ✅ Done | Phases 3, 7 |

## State Locations

| State Class | Authority | Durable Home | Notes |
|-------------|-----------|--------------|-------|
| Build artefacts | `cabal` (Apple) or `docker compose run` (Linux) | `./.build/` (gitignored, dockerignored) | The only host folder holding compiled artefacts |
| Generated JIT compiler inputs | `jitml` Haskell runtime source renderers | `./.build/jit-src/<substrate>/<hash>/` | Generated on cache miss; may contain CUDA, oneDNN C++, or Metal / Swift source; never checked in |
| JIT cache | `jitml service` and `jitml build` | `./.build/jit/<substrate>/<hash>.<ext>` content-addressed by `(canonical-cbor(KernelSpec), kind, substrate, toolchain-fingerprint)` | Survives `purge`; only `purge --full` removes it |
| Apple FFI dlopen surface | `jitml service` (host-native instance) | `./.build/host/apple-silicon/<model-id>.dylib` (symlinks into `jit/apple-silicon/`) | Stable-named so the FFI key never changes across re-JITs |
| Kubeconfig | `jitml bootstrap --<substrate>` | `./.build/jitml.kubeconfig` | The CLI never touches `~/.kube/config` |
| Generated Dhall and runtime metadata | `jitml bootstrap --<substrate>` | `./.build/conf/`, `./.build/runtime/cluster-publication.json`, `./.build/kind/<substrate>/` | Host Dhall exists only on Apple; Linux uses only the cluster ConfigMap Dhall |
| Kind hostPath PV state | per-StatefulSet PVs | `./.data/<namespace>/<StatefulSet>/pv_<replica-int>/` | `.data` is strictly manual PV bind mounts; lint-enforced by `jitml lint files` |
| Checkpoint store | `jitml service` (training path) | MinIO `jitml-checkpoints/<experiment-hash>/{blobs,manifests,pointers}` | Concurrency: write-once + If-Match CAS on pointers |
| Trial store | `jitml tune` | MinIO `jitml-trials/<sha256(resolved-dhall \|\| trial-seed)>/` | Trial transcripts content-addressed |
| TensorBoard events | `jitml service` writers | MinIO `jitml-tensorboard/<experiment-hash>/shards/*.tfevents` plus checkpoint sidecars | Stateless TB pod reads from MinIO |
| RL transcripts | `jitml rl train` / `jitml rl rollout` | MinIO `jitml-transcripts/` | Analog of MCTS's `.mcts-cache/transcripts/` |
| Plan suite | repository worktree | `DEVELOPMENT_PLAN/` | This document set |
| Doctrine | repository worktree | `HASKELL_CLI_TOOL.md` (root) | Authoritative CLI doctrine |
| Governed engineering docs | repository worktree | `documents/engineering/` | Project-specific elaborations of the doctrine and project-owned content |
| Generated-section registry | code | `src/JitML/Generated/Registry.hs` | Authoritative for `jitml docs check` and `jitml docs generate` |
| Tracking-generated-paths registry | code | `src/JitML/Generated/Paths.hs` | Authoritative for `jitml lint files` drift detection |

## Artefact Locations

This table is the local artefact inventory for the implemented plan surfaces.
The current concrete worktree is summarized in
[00-overview.md → Current Baseline](00-overview.md#current-baseline).

| Type | Location | Purpose |
|------|----------|---------|
| Haskell application entrypoints | `app/Main.hs`, `app/Demo.hs` | Six-line shims into `App.main` per the library-first layout |
| Haskell source modules | `src/JitML/` | CLI, cluster, daemon, runtime, SL, RL, AlphaZero, Tune, Engines, Numerics, Storage, Inference, Web, Observability, Generated |
| Cabal package definition | `jitml.cabal` | Build, test, and dependency definition with `tested-with: ghc ==9.14.1`; declares both `jitml` and `jitml-demo` executables and the ten test-suite stanzas |
| Cabal project definition | `cabal.project` | Repository-wide Cabal package-set definition with `with-compiler: ghc-9.14.1`, the codegen-toolchain pins, and the report-card knobs |
| Formatter config | `fourmolu.yaml` | Pinned 12 doctrine-mandated settings at repo root |
| Per-substrate Kind configs | `./kind/cluster-{apple-silicon,linux-cpu,linux-cuda}.yaml` | Single control-plane + one worker; bind-mounts `./.build/` into the worker via `extraMounts` |
| Bootstrap scripts | `./bootstrap/{apple-silicon,linux-cpu,linux-cuda}.sh` | Stage-0 idempotent reconcilers |
| Docker assets | `docker/Dockerfile`, `docker/compose.yaml` | One Dockerfile producing one image (`jitml:local`); one compose service (`jitml`) |
| Helm umbrella chart | `chart/Chart.yaml`, `chart/values.yaml`, `chart/templates/` | Subchart deps for Harbor, Pulsar, MinIO, Postgres, Envoy Gateway, Prometheus, TensorBoard; templates for GatewayClass / Gateway / HTTPRoutes / EnvoyProxy / manual PVs / Deployments / RuntimeClass / dashboards |
| JIT source generation | `src/JitML/Codegen/RuntimeSource.hs` (target), `./.build/jit-src/<substrate>/<hash>/` | Haskell-generated compiler inputs for CUDA, oneDNN C++, and Metal / Swift; checked-in static JIT source/build files are forbidden |
| Protobuf contracts | `proto/tensorboard/event.proto` | TensorBoard event vendor proto |
| PureScript frontend | `web/package.json`, `web/src/`, `web/test/`, `playwright/` | PureScript shell, generated contracts, tests, and Playwright scaffold |
| Pulumi infrastructure | `infra/pulumi/` | TypeScript program for the ephemeral-Kind stack used by `jitml-e2e` |
| Experiments | `experiments/` | Canonical experiment Dhall files (the "configuration is code" surface) |
| Tests | `test/` | Per-stanza test trees (`test/unit/`, `test/integration/`, `test/sl-canonicals/`, `test/rl-canonicals/`, `test/hyperparameter/`, `test/cross-backend/`, `test/daemon-lifecycle/`, `test/e2e/`, `test/haskell-style/`, `test/purescript-style/`) and the committed golden fixtures under `test/golden/` |
| Development plan | `DEVELOPMENT_PLAN/` | This plan suite |
| Doctrine | `HASKELL_CLI_TOOL.md` | Authoritative CLI doctrine at repo root |
| Project README | `README.md` | Project intent, command surface, doctrine scope, build instructions |
| Agent guardrails | `AGENTS.md`, `CLAUDE.md` | Git-command restrictions and doctrine pointers for LLM agents |
| Generated CLI artefacts | `documents/cli/commands.md`, `share/man/man1/jitml*.1`, `share/completion/{bash,zsh,fish}/` | Fully-generated; tracked by `trackingGeneratedPaths`; hand edits fail `jitml lint files` |

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [development_plan_standards.md](development_plan_standards.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
