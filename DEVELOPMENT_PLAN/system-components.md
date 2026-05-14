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
Phase `1` is `🔄 Active` because Sprint `1.4` is reopened for the external
lint/format/build runners; Phase `2` is `🔄 Active` with Sprints `2.1`, `2.2`,
and `2.3` closed; later implementation rows remain `⏸️ Blocked` until their owning
predecessor phases close. Status moves to `🔄 Active` and then `✅ Done` as
each owning sprint closes per
[development_plan_standards.md → C. Honest Completion
Tracking](development_plan_standards.md#c-honest-completion-tracking).

Rows marked `✅ Done` name the implemented surface in the current worktree. Rows
marked `⏸️ Blocked` or `📋 Planned` name target paths and responsibilities, not
files that already exist. When a command or Cabal stanza is registered early as a
scaffold, the row explicitly distinguishes the current scaffold from the final
phase-owned body.

## Substrates

| Substrate | Identifier | Codegen | Container Shape | Daemon Topology | Status | Owning Phase |
|-----------|------------|---------|-----------------|-----------------|--------|--------------|
| Apple Silicon | `apple-silicon` | Swift + Metal | partial — cluster services in Kind; second `jitml service` runs host-native (Metal cannot be containerized) | two instances of one binary, distinguished by Dhall: `Cluster + ForwardToHost` (in-pod) + `Host + SelfInference` (host-native) | ⏸️ Blocked | [Phase 7](phase-7-jit-codegen-and-substrates.md) |
| Linux CPU | `linux-cpu` | oneDNN + AVX2/AVX-512 | fully containerized: `jitml:local` | one daemon: `Cluster + SelfInference` | ⏸️ Blocked | [Phase 7](phase-7-jit-codegen-and-substrates.md) |
| Linux CUDA | `linux-cuda` | CUDA C + cuBLAS / cuDNN | fully containerized: `jitml:local` (CUDA activates at runtime when scheduled to `runtimeClassName: nvidia`) | one daemon: `Cluster + SelfInference`, pod anti-affinity = one per node | ⏸️ Blocked | [Phase 7](phase-7-jit-codegen-and-substrates.md) |

A fourth substrate `linux-opencl` (Intel GPU) is admitted as a future extension and
is not in the current support matrix.

## Haskell CLI Surface

| Surface | Command | Purpose | Status | Owning Sprint |
|---------|---------|---------|--------|---------------|
| Bootstrap | `jitml bootstrap --apple-silicon\|--linux-cpu\|--linux-cuda` | Registered Plan/Apply substrate bootstrap surface; stage-0 handoff, prerequisite remediation, and JIT cache layers are present, while real generated-Dhall, Kind, Harbor-first rollout, platform-service, daemon, demo, and Apple host-daemon apply steps land in later sprints | 🔄 Active | Sprints 2.1–2.7 |
| Service daemon | `jitml service` | Long-running daemon parameterised entirely by Dhall config (`BootConfig` / `LiveConfig`); no separate `host-service` verb | ⏸️ Blocked | Sprint 5.1 |
| Cluster lifecycle | `jitml cluster up`, `jitml cluster down`, `jitml cluster status`, `jitml cluster reset` | Plan/Apply rollout, preserving teardown, status reporting, and destructive reset guarded by `--yes` | ⏸️ Blocked | Sprint 3.5 |
| Train | `jitml train` | Plan/Apply: run a training job described by an experiment Dhall, publish events on `training.event.<mode>` | ⏸️ Blocked | Sprint 8.2 |
| Eval | `jitml eval` | Evaluate a trained model or policy against a deterministic evaluation cohort | ⏸️ Blocked | Sprint 8.2 |
| Tune | `jitml tune` | Plan/Apply: run a hyperparameter sweep described by a tuning Dhall, publish trial events on `tune.event.<mode>` | ⏸️ Blocked | Sprint 9.5 |
| RL lifecycle | `jitml rl train`, `jitml rl eval`, `jitml rl rollout` | Plan/Apply RL training, deterministic policy evaluation, and fixed-seed rollout cohorts | ⏸️ Blocked | Sprint 8.5 |
| Verification | `jitml verify same-run`, `jitml verify cross-backend`, `jitml verify replay` | Same-substrate byte-equality, cross-backend tolerance, and checkpoint replay verification | ⏸️ Blocked | Sprints 10.4, 12.2, 12.6 |
| Inspection | `jitml inspect list`, `jitml inspect show`, `jitml inspect replay`, `jitml inspect trial`, `jitml inspect frontier` | Inspect cached transcripts, checkpoints, trials, and hyperparameter frontiers | ⏸️ Blocked | Sprints 9.7, 10.4 |
| Benchmarks | `jitml bench train`, `jitml bench inference`, `jitml bench env` | Reproducible benchmark harnesses for training, inference, and environment-step throughput | ⏸️ Blocked | Sprint 12.9 |
| Inference | `jitml inference run` | Inference-at-any-point against `latest`, `best/<metric>`, or a manifest SHA | ⏸️ Blocked | Sprint 10.4 |
| Test runner | `jitml test all` / `jitml test <stanza>` | Plan/Apply over Cabal test stanzas plus the pinned report-card workload | ⏸️ Blocked | Sprint 12.9 |
| Lint stack | `jitml lint files\|docs\|proto\|chart\|haskell\|purescript\|all` | Current in-repo hygiene, config, forbidden-path, generated-doc, and forbidden-primitive checks are implemented; external formatter/hlint/cabal-format/build runners remain open | 🔄 Active | Sprint 1.4 |
| Docs generation | `jitml docs check` / `jitml docs generate` | Paired generated-section check and write per the `GeneratedSectionRule` registry | ✅ Done | Sprint 1.3 |
| Command introspection | `jitml commands [--tree\|--json]` | Flat list, tree rendering, or JSON command schema from the `CommandSpec` registry | ✅ Done | Sprint 1.2 |
| Focused help | `jitml help <subcommand>` | Equivalent to `<subcommand> --help`; same renderer | ✅ Done | Sprint 1.2 |
| Code quality gate | `jitml check-code` | Currently delegates to the in-repo lint stack; external `fourmolu`, `hlint`, `cabal format`, and warning-clean build execution remains open | 🔄 Active | Sprint 1.4 |
| Build | `jitml build` | Build the inner Haskell binary inside the substrate container; mirrors `bootstrap/<substrate>.sh build` semantics from inside the daemon | ⏸️ Blocked | Sprint 2.4 |
| Prerequisite doctor | `jitml doctor [--scope toolchain\|container\|cluster] [--remediate]` | In-process prerequisite registry reconciliation and typed remediation apply/postcondition validation | ✅ Done | Sprint 2.2 |
| Kubectl passthrough | `jitml kubectl` | `kubectl` passthrough pre-bound to `./.build/jitml.kubeconfig` | ⏸️ Blocked | Sprint 3.5 |
| Internal prerequisite listing | `jitml internal list-prereqs` | Prints the typed prerequisite registry from the current Haskell process | ✅ Done | Sprint 1.7 |
| Internal substrate materialization scaffold | `jitml internal materialize-substrate` | Validates the supported substrate identifier and reports the scaffold; real Kind/Dhall file materialization is owned by Phase 3 | ✅ Done | Sprint 2.1 |
| Internal VM lifecycle (Apple) | `jitml internal vm bootstrap\|up\|down\|status\|exec` | Tart VM lifecycle and pass-through debugging for Swift/Metal builds | ⏸️ Blocked | Sprint 2.5 |
| Internal cache inspection | `jitml internal cache stat\|list\|evict` | JIT cache introspection and idempotent eviction helpers; command leaves are registered, while effectful bodies wait for populated codegen entries | ⏸️ Blocked | Sprint 7.1 |
| Internal GC | `jitml internal gc <experiment-hash>` | Reconciler that enforces the experiment Dhall's `retain` policy on the checkpoint store; exit code `3` on no-op | ⏸️ Blocked | Sprint 10.3 |
| Demo HTTP server | `jitml-demo` | Sibling binary serving the PureScript bundle plus the inference REST surface; both binaries share the `src/JitML/` library | ⏸️ Blocked | Sprint 11.5 |

## Bootstrap Stage-0 Script Surface

The shell scripts are stage-0 entrypoints, not broad package reconcilers. They
fail fast with installation instructions, then delegate to the Haskell
`jitml bootstrap --<substrate>` command.

| Verb | Purpose | Status | Owning Sprint |
|------|---------|--------|---------------|
| `help` | Print supported subcommands | ✅ Done | Sprint 2.1 |
| `doctor` | Run only stage-0 host gates: Apple macOS/arm64/Xcode CLT/Homebrew; Linux Docker without `sudo`; CUDA NVIDIA runtime and compute capability | ✅ Done | Sprint 2.1 |
| `build` | Apple-only convenience to build `./.build/jitml`; Linux scripts currently report the Sprint 2.4 placeholder until Compose assets land | ✅ Done | Sprint 2.1 |
| `up` | Apple builds `./.build/jitml` and delegates to `jitml bootstrap --apple-silicon`; Linux calls the intended Compose handoff, with the actual `docker/compose.yaml` target delivered by Sprint 2.4 | ✅ Done | Sprint 2.1 |
| `status` | Report bootstrap-side stack health from `./.build/runtime/cluster-publication.json` | ⏸️ Blocked | Sprint 2.6 |
| `test` | Thin wrapper for `jitml test all` from outside the container | ⏸️ Blocked | Sprint 2.6 |
| `down` | Tear down the cluster; preserve `./.data/` and `./.build/`; on Apple, leave the tart VM up | ⏸️ Blocked | Sprint 2.7 |
| `purge` | Cluster down, `rm -rf ./.data/`, tart VM destroyed (Apple); preserves `./.build/` (including JIT cache) | ⏸️ Blocked | Sprint 2.7 |
| `purge --full` | `purge` plus `rm -rf ./.build/`; Linux additionally drops the substrate image | ⏸️ Blocked | Sprint 2.7 |

## Cluster Substrate Components

| Component | Implementation | Status | Owning Sprint |
|-----------|----------------|--------|---------------|
| Per-substrate Kind config | `./kind/cluster-{apple-silicon,linux-cpu,linux-cuda}.yaml` | ⏸️ Blocked | Sprint 3.1 |
| Kind worker labels (CUDA) | `jitml.runtime/gpu=true` on the worker so the `nvidia` RuntimeClass binds | ⏸️ Blocked | Sprint 3.1 |
| Kubeconfig home | `./.build/jitml.kubeconfig`; `~/.kube/config` is never touched | ⏸️ Blocked | Sprint 3.5 |
| `extraMounts` of `./.build/` | Bind-mounts host `./.build/` into the Kind worker so the in-cluster `jitml-service` pod sees the same JIT artefacts the host built | ⏸️ Blocked | Sprint 3.1 |
| `jitml-manual` StorageClass | `kubernetes.io/no-provisioner`; the only StorageClass in the chart | ⏸️ Blocked | Sprint 3.2 |
| Manual PV templates | `chart/templates/pv-<statefulset>.yaml`; one per replica with explicit `claimRef` | ⏸️ Blocked | Sprint 3.2 |
| HostPath layout | `./.data/<namespace>/<StatefulSet>/pv_<replica-int>/`; lint-enforced by `jitml lint files` | ⏸️ Blocked | Sprint 3.2 |
| `GatewayClass/jitml-gateway` + `Gateway/jitml-edge` | Single localhost listener at `127.0.0.1:<edge-port>` | ⏸️ Blocked | Sprint 3.3 |
| `EnvoyProxy/jitml-edge` | NodePort service, `externalTrafficPolicy: Cluster`, port 30090 | ⏸️ Blocked | Sprint 3.3 |
| Route registry | `src/JitML/Routes.hs` — single source of truth for every HTTPRoute resource | ⏸️ Blocked | Sprint 3.4 |
| Generated HTTPRoute manifests | `chart/templates/httproute-*.yaml`, rendered from the route registry; hand edits fail `jitml lint chart` | ⏸️ Blocked | Sprint 3.4 |
| Cluster publication | `./.build/runtime/cluster-publication.json` — `edge_port`, `pulsar_ws_url`, `pulsar_admin_url`, `minio_s3_url` | ⏸️ Blocked | Sprint 3.5 |
| Phased deploy | Harbor first → Mirror/build into Harbor → Final (MinIO, Pulsar, Envoy, kube-prometheus-stack, TensorBoard, `jitml-service`, `jitml-demo`) | ⏸️ Blocked | Sprint 3.5 |

## Stateful Platform Services

| Component | Helm Subchart | Routing | Status | Owning Sprint |
|-----------|---------------|---------|--------|---------------|
| Harbor (image registry) | `harbor` | `/harbor` (portal), `/harbor/api` (API) | ⏸️ Blocked | Sprint 4.1 |
| Percona PG operator | `pg-operator` + Patroni-managed service Postgres | (internal — packaged services that require Postgres) | ⏸️ Blocked | Sprint 4.2 |
| MinIO (object store) | `minio` (4 distributed replicas) | `/minio/console`, `/minio/s3` | ⏸️ Blocked | Sprint 4.3 |
| Apache Pulsar | `pulsar` (3× ZK + 3× BK + 3× Broker + 3× Proxy + WebSocket) | `/pulsar/admin`, `/pulsar/ws` | ⏸️ Blocked | Sprint 4.4 |
| Envoy Gateway controller | `gateway-helm` | (controller — dispatches the GatewayClass) | ⏸️ Blocked | Sprint 3.3 |
| kube-prometheus-stack | `kube-prometheus-stack` | `/grafana`, `/prometheus` | ⏸️ Blocked | Sprint 4.5 |
| TensorBoard | jitML-owned `tensorboard` chart with MinIO event-storage backing | `/tensorboard` | ⏸️ Blocked | Sprint 4.6 |
| `jitml-service` Deployment | `chart/templates/deployment-jitml-service.yaml` | (internal Pulsar consumer) | ⏸️ Blocked | Sprint 5.6 |
| `jitml-demo` Deployment | `chart/templates/deployment-jitml-demo.yaml` | `/`, `/api`, `/api/ws` | ⏸️ Blocked | Sprint 11.5 |
| NVIDIA RuntimeClass (CUDA) | `chart/templates/runtimeclass-nvidia.yaml`; binds to nodes labelled `jitml.runtime/gpu=true` | (RuntimeClass — selected by the Linux CUDA Deployment podSpec) | ⏸️ Blocked | Sprint 4.7 |

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
| `BootConfig` Dhall (start-time only; restart-required) | Long-Running Daemons in the Same Binary → BootConfig | ⏸️ Blocked | Sprint 5.2 |
| `LiveConfig` Dhall (hot-reloadable on SIGHUP) | Long-Running Daemons in the Same Binary → LiveConfig | ⏸️ Blocked | Sprint 5.2 |
| SIGHUP hot reload handler | Long-Running Daemons in the Same Binary | ⏸️ Blocked | Sprint 5.2 |
| `/healthz` endpoint | Long-Running Daemons → /healthz | ⏸️ Blocked | Sprint 5.3 |
| `/readyz` endpoint | Long-Running Daemons → /readyz | ⏸️ Blocked | Sprint 5.3 |
| `/metrics` endpoint | Long-Running Daemons → /metrics | ⏸️ Blocked | Sprint 5.3 |
| Structured JSON stderr logging | Long-Running Daemons → structured logging | ⏸️ Blocked | Sprint 5.3 |
| Recoverable-vs-fatal error kinds | Long-Running Daemons → error classification | ⏸️ Blocked | Sprint 5.3 |
| `HasMinIO` capability class | Capability Classes and Service Errors | ⏸️ Blocked | Sprint 5.4 |
| `HasPulsar` capability class | Capability Classes and Service Errors | ⏸️ Blocked | Sprint 5.4 |
| `HasHarbor` capability class | Capability Classes and Service Errors | ⏸️ Blocked | Sprint 5.4 |
| `HasKubectl` capability class | Capability Classes and Service Errors | ⏸️ Blocked | Sprint 5.4 |
| `RetryPolicy` typed value | Retry Policy as First-Class Values | ⏸️ Blocked | Sprint 5.4 |
| At-least-once Pulsar consumer | At-Least-Once Event Processing | ⏸️ Blocked | Sprint 5.5 |
| Protobuf-message-hash deduplication keys | At-Least-Once Event Processing → idempotency | ⏸️ Blocked | Sprint 5.5 |
| Stateless `Deployment` (not `StatefulSet`) | Long-Running Daemons | ⏸️ Blocked | Sprint 5.6 |
| Pod anti-affinity (`topologyKey: kubernetes.io/hostname`) | Long-Running Daemons | ⏸️ Blocked | Sprint 5.6 |

## Numerical Core Inventory

| Component | Implementation | Status | Owning Sprint |
|-----------|----------------|--------|---------------|
| Layer catalog (Dense, Conv1D, Conv2D, Conv3D, ConvTranspose, BatchNorm, LayerNorm, GroupNorm, Dropout, ResidualBlock, MultiHeadAttention, ...) | `src/JitML/Numerics/Layer.hs` + Dhall types under `dhall/numerics/Layer.dhall` | ⏸️ Blocked | Sprint 6.1 |
| Real-valued activations (ReLU, LeakyReLU, GELU, SiLU, Tanh, Sigmoid, Softmax, ...) | `src/JitML/Numerics/Activation.hs` | ⏸️ Blocked | Sprint 6.2 |
| Complex-valued activations (modReLU, zReLU, complex GELU, ...) | `src/JitML/Numerics/Activation/Complex.hs` | ⏸️ Blocked | Sprint 6.2 |
| Spectral / frequency-domain ops (FFT, IFFT, RFFT, complex multiply) | `src/JitML/Numerics/Spectral.hs` | ⏸️ Blocked | Sprint 6.3 |
| Optimizers (SGD, Momentum SGD, Nesterov SGD, RMSProp, Adagrad, Adadelta, Adam, AdamW, LAMB, LARS, Lion) | `src/JitML/Numerics/Optimizer.hs` | ⏸️ Blocked | Sprint 6.4 |
| Schedulers (constant, linear, cosine, cosine-with-warmup, exponential, polynomial, one-cycle, piecewise; `ReduceOnPlateau` as a callback) | `src/JitML/Numerics/Scheduler.hs` | ⏸️ Blocked | Sprint 6.4 |
| Loss functions (cross-entropy, focal, MSE, Huber, IoU) | `src/JitML/Numerics/Loss.hs` | ⏸️ Blocked | Sprint 6.5 |
| Dhall types for every constructor | `dhall/numerics/{Layer,Activation,Optimizer,Scheduler,Loss}.dhall` | ⏸️ Blocked | Sprint 6.6 |

## JIT Codegen Components

| Component | Implementation | Status | Owning Sprint |
|-----------|----------------|--------|---------------|
| Apple Silicon engine (Metal codegen + host daemon shim + lazy tart spin-up) | `src/JitML/Engines/AppleSilicon.hs`, `codegen-metal/` | ⏸️ Blocked | Sprint 7.5 |
| Linux CPU engine (oneDNN codegen) | `src/JitML/Engines/LinuxCPU.hs`, `codegen-onednn/` | ⏸️ Blocked | Sprint 7.3 |
| Linux CUDA engine (CUDA C codegen) | `src/JitML/Engines/LinuxCUDA.hs`, `codegen-cuda/` | ⏸️ Blocked | Sprint 7.4 |
| Content-addressed cache key shape | `src/JitML/Cache/Key.hs`; placeholder `KernelSpec` hashes `(canonical-cbor(KernelSpec), kind, substrate, toolchain-fingerprint)`, with full numerical payload populated by Sprint `7.1` | ✅ Done | Sprint 2.3 |
| Cache root layout | `src/JitML/Cache/Layout.hs`; `./.build/jit/<substrate>/<hash>.<ext>` plus `manifest.json` path resolution | ✅ Done | Sprint 2.3 |
| Cache manifest index | `src/JitML/Cache/Manifest.hs`; JSON round-trip, lookup, upsert, read, and atomic write helpers | ✅ Done | Sprint 2.3 |
| Apple stable FFI symlink surface | `src/JitML/Cache/Symlink.hs`; `./.build/host/apple-silicon/<model-id>.dylib` repoints atomically into `jit/apple-silicon/` | ✅ Done | Sprint 2.3 |
| Hardware auto-tuning | per-substrate reduction strategy / tile size / prefetch width selection preserving the determinism contract | ⏸️ Blocked | Sprint 7.6 |
| Apple Silicon host↔cluster RPC contract | `inference.command.apple-silicon` / `inference.event.apple-silicon` envelope shape | ⏸️ Blocked | Sprint 7.5 |

## Training Workload Surfaces

| Component | Implementation | Status | Owning Sprint |
|-----------|----------------|--------|---------------|
| Supervised training loops | `src/JitML/SL/Train.hs`, `src/JitML/SL/Loop.hs` | ⏸️ Blocked | Sprint 8.1 |
| Canonical SL problem set (eleven README cells: MNIST MLP/CNN variants, Fashion-MNIST variants, CIFAR-10 variants, CIFAR-100 WideResNet, CIFAR-10 ViT, Tiny ImageNet ResNet-50, California Housing MLP) | `src/JitML/SL/Problems/`; threshold methodology and golden curve fixtures under `test/golden/sl/` | ⏸️ Blocked | Sprint 8.1 |
| Canonical RL environments (cartpole, mountain-car, lunar-lander, atari-subset) | `src/JitML/Env/` | ⏸️ Blocked | Sprint 8.3 |
| RL Algorithm class taxonomy (type-level) | `src/JitML/RL/Algorithm.hs` (GADT-indexed per doctrine `GADT-Indexed State Machines`) | ⏸️ Blocked | Sprint 8.4 |
| Policy as typed value | `src/JitML/RL/Policy.hs` | ⏸️ Blocked | Sprint 8.4 |
| Environment / VecEnv as typed capability | `src/JitML/RL/Env.hs` | ⏸️ Blocked | Sprint 8.4 |
| Replay & rollout buffers (with `Async` write discipline) | `src/JitML/RL/Buffer.hs` | ⏸️ Blocked | Sprint 8.4 |
| Schedules, action distributions, action noise, target networks + Polyak averaging, GAE | `src/JitML/RL/{Schedule,Distribution,Noise,Target,GAE}.hs` | ⏸️ Blocked | Sprint 8.5 |
| Callbacks as composable hooks | `src/JitML/RL/Callback.hs` | ⏸️ Blocked | Sprint 8.5 |
| Multi-sink Logger | `src/JitML/RL/Logger.hs` (TensorBoard + Pulsar `rl.event.<mode>` + Prometheus) | ⏸️ Blocked | Sprint 8.5 |
| Evaluator | `src/JitML/RL/Eval.hs` | ⏸️ Blocked | Sprint 8.5 |
| Training loops as typed pipelines | `src/JitML/RL/Loop.hs` | ⏸️ Blocked | Sprint 8.6 |
| RL algorithm catalog (PPO, A2C, TRPO, MaskablePPO, RecurrentPPO, DQN, QR-DQN, DDPG, TD3, SAC, CrossQ, TQC, ARS, HER) | `src/JitML/RL/Algos/` (one module per algorithm) | ⏸️ Blocked | Sprints 9.1–9.3 |
| RL golden tests | `test/golden/rl/` | ⏸️ Blocked | Sprint 9.4 |
| AlphaZero-style self-play | `src/JitML/AlphaZero/SelfPlay.hs` | ⏸️ Blocked | Sprint 9.5 |
| Persistent MCTS state | `src/JitML/AlphaZero/Mcts.hs` (borrows from a sibling MCTS engineering arc) | ⏸️ Blocked | Sprint 9.5 |
| Perfect-information game type class | `src/JitML/AlphaZero/Game.hs` | ⏸️ Blocked | Sprint 9.5 |
| Two-headed network | `src/JitML/AlphaZero/Network.hs` | ⏸️ Blocked | Sprint 9.5 |
| Arena gating | `src/JitML/AlphaZero/Arena.hs` | ⏸️ Blocked | Sprint 9.5 |
| Canonical adversarial games (Connect 4, Othello, Hex, Gomoku) | `src/JitML/AlphaZero/Games/` | ⏸️ Blocked | Sprint 9.6 |
| Hyperparameter tuning (sampler × scheduler × pruner) | `src/JitML/Tune/` (`Sampler.hs`, `Scheduler.hs`, `Pruner.hs`) | ⏸️ Blocked | Sprint 9.7 |
| Trial storage and resume | `src/JitML/Tune/Storage.hs`, MinIO `jitml-trials` | ⏸️ Blocked | Sprint 9.7 |

## Checkpoint and Inference Components

| Component | Implementation | Status | Owning Sprint |
|-----------|----------------|--------|---------------|
| Storage layout (typed) | `src/JitML/Storage/Layout.hs` | ⏸️ Blocked | Sprint 10.1 |
| Split-blob layout (`blobs/<sha256>`, `manifests/<sha256>`, `pointers/{latest,best/<metric>,trial/...}`) | `src/JitML/Storage/Checkpoint.hs` | ⏸️ Blocked | Sprint 10.1 |
| `.jmw1` dense weight blob format (magic bytes, `header_len`, canonical-CBOR `JmwHeader`, packed little-endian payload) | `src/JitML/Storage/Format.hs` | ⏸️ Blocked | Sprint 10.2 |
| CBOR manifest | `src/JitML/Storage/Manifest.hs` | ⏸️ Blocked | Sprint 10.2 |
| `If-None-Match: *` write-once protocol for blobs and manifests | `src/JitML/Storage/Write.hs` | ⏸️ Blocked | Sprint 10.2 |
| `If-Match: <etag>` CAS for pointers; typed advance predicates (`advanceLatest`, `advanceBestMaximised`, `advanceBestMinimised`) | `src/JitML/Storage/Pointer.hs` | ⏸️ Blocked | Sprint 10.2 |
| Bit-determinism contract + cross-substrate tolerance methodology | [../documents/engineering/determinism_contract.md](../documents/engineering/determinism_contract.md) | ⏸️ Blocked | Sprint 10.3 |
| Inference-only read path | `src/JitML/Inference/Read.hs` (consumed by `jitml-demo` and the PureScript panels) | ⏸️ Blocked | Sprint 10.4 |
| Retention reconciler (`jitml internal gc <experiment-hash>`) | `src/JitML/Storage/GC.hs`; exit code `3` on no-op | ⏸️ Blocked | Sprint 10.3 |
| TensorBoard checkpoint sidecar (`<step>-<manifest-sha>.cbor` under `jitml-tensorboard/<experiment-hash>/checkpoints/`) | `src/JitML/Observability/TensorBoard.hs` | ⏸️ Blocked | Sprint 4.6 |

## Frontend Components

| Component | Implementation | Status | Owning Sprint |
|-----------|----------------|--------|---------------|
| Halogen application | `web/src/` | ⏸️ Blocked | Sprint 11.1 |
| Browser-contract source ADTs | `src/JitML/Web/Contracts.hs` (source for `purescript-bridge`) | ⏸️ Blocked | Sprint 11.2 |
| Generated PureScript contracts | `web/src/Generated/Contracts.purs`; Sprint 11.2 promotes the reserved future generated-path pattern into an active `trackingGeneratedPaths` entry so hand edits fail `jitml lint files` | ⏸️ Blocked | Sprint 11.2 |
| `purescript-spec` unit tests | `web/test/` | ⏸️ Blocked | Sprint 11.3 |
| Playwright E2E suite | `web/playwright/` | ⏸️ Blocked | Sprint 11.6 |
| Bundle output | `web/dist/` | ⏸️ Blocked | Sprint 11.4 |
| MNIST live inference panel | `web/src/Panels/Mnist.purs` | ⏸️ Blocked | Sprint 11.4 |
| CIFAR/ImageNet upload panel | `web/src/Panels/Cifar.purs` | ⏸️ Blocked | Sprint 11.4 |
| AlphaZero-vs-human Connect 4 panel | `web/src/Panels/Connect4.purs` | ⏸️ Blocked | Sprint 11.4 |
| RL trajectory render panel | `web/src/Panels/Rl.purs` | ⏸️ Blocked | Sprint 11.4 |
| Demo HTTP server (`jitml-demo`) | `app/Demo.hs` shim into `App.main`; serves the bundle plus the inference REST surface | ⏸️ Blocked | Sprint 11.5 |

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
| GADT-indexed `TrainingLifecycle`, `RLRunLifecycle`, `TuneSweepLifecycle` | GADT-Indexed State Machines | ⏸️ Blocked | Sprint 8.4, 8.6, 9.7 |
| Capability classes (`HasMinIO`, `HasPulsar`, `HasHarbor`, `HasKubectl`) | Capability Classes and Service Errors | ⏸️ Blocked | Sprint 5.4 |
| `RetryPolicy` typed value with named strategies | Retry Policy as First-Class Values | ⏸️ Blocked | Sprint 5.4 |
| At-least-once Pulsar consumer with protobuf-message-hash deduplication | At-Least-Once Event Processing | ⏸️ Blocked | Sprint 5.5 |
| Long-running daemon shape (`BootConfig` / `LiveConfig`, SIGHUP, `/healthz`, `/readyz`, `/metrics`, structured JSON stderr logging) | Long-Running Daemons in the Same Binary | ⏸️ Blocked | Sprints 5.2, 5.3 |
| Implemented reconciler discipline (`jitml docs generate`, `jitml lint --write`, `--dry-run` / `--plan-file` plan rendering, no-op exit code `3`) | Reconcilers: Idempotent Mutation as a Single Command; Plan / Apply | ✅ Done | Sprints 1.3, 1.4, 1.5, 1.9 |
| Future mutating reconcilers (`jitml bootstrap` full apply, `jitml cluster up`, `jitml internal gc`) | Reconcilers: Idempotent Mutation as a Single Command | ⏸️ Blocked | Sprints 3.5, 10.3 |
| Cabal-manifest toolchain pin (`tested-with: ghc ==9.14.1` in `jitml.cabal`, `with-compiler: ghc-9.14.1` in `cabal.project`, codegen toolchains pinned in `cabal.project`) | Toolchain pinning | ✅ Done | Sprint 1.1 |
| Library-first layout audit (thin `app/Main.hs` and `app/Demo.hs`, logic in `src/JitML/`) | Project Structure | ✅ Done | Sprint 1.1 |
| Durable CLI documentation artefacts (`documents/cli/commands.md`, `share/man/man1/jitml*.1`, `share/completion/{bash,zsh,fish}/`) | Automatically Generated Documentation | ✅ Done | Sprint 1.3 |
| Standardized library set audit in `jitml.cabal` (`optparse-applicative`, `text`, `bytestring`, `aeson`, `prettyprinter*`, `ansi-terminal`, `path`, `path-io`, `typed-process`, `safe-exceptions`, `dhall`, `tasty*`, `temporary`) | Overview → standardized stack | ✅ Done | Sprint 1.1 |

## Test Stanzas

Per doctrine `Test Organization`, each tier is a separate Cabal `test-suite` with
`type: exitcode-stdio-1.0` and `tasty` as the in-stanza runner. A single `tasty`
tree spanning all tiers is forbidden. All ten stanza declarations exist today;
the `Current body` column records whether that body is already real coverage or
only the Sprint `1.1` sentinel.

| Stanza | Current body | Final Phase-Owned Scope | Status | Owning Sprint |
|--------|--------------|-------------------------|--------|---------------|
| `jitml-unit` | `test/unit/Main.hs` covers current parser, docs, prerequisite, env, app-error, plan, subprocess, bootstrap-script, and cache surfaces | Expand to every final Pure Logic, Parser, Property, and Golden category: engine invariants, numerical-core round-trips, RL framework primitives, AlphaZero MCTS invariants, hyperparameter sampler determinism, checkpoint codec round-trips, route registry, Grafana renderer, transcript codecs, RNG mixers, Sobol sequence golden, GA trace golden | ⏸️ Blocked | Sprint 12.1 |
| `jitml-integration` | `test/integration/Main.hs` covers a typed subprocess sentinel | Expand to real-binary subprocess integration, checkpoint round-trip, resume semantics, Dhall→typed-record decode, and per-substrate determinism | ⏸️ Blocked | Sprint 12.2 |
| `jitml-sl-canonicals` | `test/sentinel/Main.hs` | Eleven SL `(dataset, model)` pairs from [../README.md → Canonical supervised learning problems](../README.md#canonical-supervised-learning-problems), convergence golden, and per-distribution regression detection | ⏸️ Blocked | Sprint 12.3 |
| `jitml-rl-canonicals` | `test/sentinel/Main.hs` | RL target matrix forms (2) and (3): same-substrate trajectory determinism plus per-seed final-reward distribution against committed fixtures | ⏸️ Blocked | Sprint 12.4 |
| `jitml-hyperparameter` | `test/sentinel/Main.hs` | Per-sampler reproducibility, per-scheduler reproducibility, per-pruner reproducibility, and resume-from-partial-sweep equality | ⏸️ Blocked | Sprint 12.5 |
| `jitml-cross-backend` | `test/sentinel/Main.hs` | Cross-substrate cohort `(cpu, cuda)` and `(cpu, metal)` on the SL canon; per-tensor drift fits the committed tolerance band per [../documents/engineering/determinism_contract.md](../documents/engineering/determinism_contract.md) | ⏸️ Blocked | Sprint 12.6 |
| `jitml-daemon-lifecycle` | `test/sentinel/Main.hs` | Spawn `jitml service`, poll `/readyz`, exercise the Pulsar consumer protocol, drive SIGHUP hot reload, and assert graceful drain on SIGTERM | ⏸️ Blocked | Sprint 12.7 |
| `jitml-e2e` | `test/sentinel/Main.hs` | Pulumi-orchestrated ephemeral Kind stack + Playwright against the real Envoy listener across training control, MNIST handwriting, image upload, Connect 4 game-play, TensorBoard/Grafana navigation, and hyperparameter sweep | ⏸️ Blocked | Sprint 12.8 |
| `jitml-haskell-style` | `test/haskell-style/Main.hs` runs the current lint stack | Formatter, hlint/config, forbidden-path, chart, generated-section, external formatter/hlint/cabal-format/build gates, and optional future lints as they land | 🔄 Active | Sprint 1.4 |
| `jitml-purescript-style` | `test/sentinel/Main.hs` | PureScript `purs format` round-trip plus `purescript-spec` smoke tests against the generated browser contracts | ⏸️ Blocked | Sprint 11.3 |

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
| NVCC | pinned in `cabal.project` (`--use_fast_math=false`, baseline `sm_70`) | CUDA kernel codegen for `linux-cuda` | ⏸️ Blocked | Sprint 7.4 |
| Xcode/Metal | pinned in bootstrap script + `cabal.project` | Metal kernel codegen for `apple-silicon` (runs inside the `jitml-build` tart VM) | ⏸️ Blocked | Sprint 7.5 |
| oneDNN | pinned in `cabal.project` (AVX2 baseline, AVX-512 detected at JIT time) | CPU kernel codegen for `linux-cpu` | ⏸️ Blocked | Sprint 7.3 |
| `kindest/node` | pinned in `./kind/cluster-<substrate>.yaml`; mirrored as a comment in `cabal.project` | Kind worker image; the comment-mirror is a single-source-of-toolchain-truth record (`jitml lint chart` rejects drift) | ⏸️ Blocked | Sprint 3.1 |
| `tart` | latest stable, `brew install cirruslabs/cli/tart` | macOS VM runner for the Apple Silicon Swift/Metal build; validated only through the first-JIT-cache-miss prerequisite root | ✅ Done | Sprint 2.2 |
| `kind` | Haskell prerequisite DAG | Kubernetes-in-Docker | ✅ Done | Sprint 2.2 |
| `kubectl` | Haskell prerequisite DAG | k8s API client invoked through the typed `Subprocess` boundary | ✅ Done | Sprint 2.2 |
| `helm` | Haskell prerequisite DAG | Helm CLI invoked through the typed `Subprocess` boundary | ✅ Done | Sprint 2.2 |
| `docker` | stage-0 Linux gate plus Haskell prerequisite DAG | Container runtime; the only host runtime touched on Linux | ✅ Done | Sprint 2.2 |
| Node.js | Haskell prerequisite DAG | Required by the PureScript toolchain (`spago`, `purescript`) and Pulumi | ✅ Done | Sprint 2.2 |
| Poetry | Haskell prerequisite DAG | Required for ancillary Python tooling (none on the supported runtime path; only present for codegen support tools) | ✅ Done | Sprint 2.2 |
| Formatter GHC | separate isolated install under `.build/jitml-style-tools/` | Lint stack only; never affects the project compiler | 🔄 Active | Sprint 1.4 |
| `purescript-bridge` | pinned in `cabal.project` | Generates PureScript contracts from `src/JitML/Web/Contracts.hs` | ⏸️ Blocked | Sprint 11.2 |
| Pulumi (TypeScript) | pinned in `infra/pulumi/package.json` | Ephemeral-Kind orchestrator for `jitml-e2e` | ⏸️ Blocked | Sprint 12.8 |
| Target platforms | `arm64` macOS (Apple Silicon), `amd64` Linux, optional `arm64` Linux | Three substrates × supported host arches | ⏸️ Blocked | Phases 3, 7 |

## State Locations

| State Class | Authority | Durable Home | Notes |
|-------------|-----------|--------------|-------|
| Build artefacts | `cabal` (Apple) or `docker compose run` (Linux) | `./.build/` (gitignored, dockerignored) | The only host folder holding compiled artefacts |
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

This table is a target inventory. The current concrete worktree through Sprint
`2.3` is summarized in [00-overview.md → Current Baseline](00-overview.md#current-baseline);
target roots such as `kind/`, `docker/`, `chart/`, `web/`, `infra/`, `proto/`,
the codegen directories, and canonical experiment directories are not present
until their owning blocked sprint lands.

| Type | Location | Purpose |
|------|----------|---------|
| Haskell application entrypoints | `app/Main.hs`, `app/Demo.hs` | Six-line shims into `App.main` per the library-first layout |
| Haskell source modules | `src/JitML/` | CLI, cluster, daemon, runtime, SL, RL, AlphaZero, Tune, Engines, Numerics, Storage, Inference, Web, Observability, Generated |
| Cabal package definition | `jitml.cabal` | Build, test, and dependency definition with `tested-with: ghc ==9.14.1`; declares both `jitml` and `jitml-demo` executables and the ten test-suite stanzas |
| Cabal project definition | `cabal.project` | Repository-wide Cabal package-set definition with `with-compiler: ghc-9.14.1`, the codegen-toolchain pins, and the report-card knobs |
| Formatter config | `fourmolu.yaml` | Pinned 12 doctrine-mandated settings at repo root |
| Per-substrate Kind configs | `./kind/cluster-{apple-silicon,linux-cpu,linux-cuda}.yaml` | Single control-plane + one worker; bind-mounts `./.build/` into the worker via `extraMounts` |
| Bootstrap scripts | `./bootstrap/{apple-silicon,linux-cpu,linux-cuda}.sh` | Stage-0 idempotent reconcilers |
| Docker assets | `docker/Dockerfile`, `docker/compose.yaml`, `docker/playwright.Dockerfile` | One Dockerfile producing one image (`jitml:local`); one compose service (`jitml`); separate Playwright image for E2E |
| Helm umbrella chart | `chart/Chart.yaml`, `chart/values.yaml`, `chart/templates/` | Subchart deps for Harbor, Pulsar, MinIO, Postgres, Envoy Gateway, Prometheus, TensorBoard; templates for GatewayClass / Gateway / HTTPRoutes / EnvoyProxy / manual PVs / Deployments / RuntimeClass / dashboards |
| Codegen sources | `codegen-cuda/`, `codegen-metal/`, `codegen-onednn/` | Per-substrate kernel templates and JIT drivers |
| Protobuf contracts | `proto/jitml/`, `proto/tensorboard/event.proto` | Pulsar event schemas, TensorBoard event vendor proto |
| PureScript frontend | `web/spago.yaml`, `web/src/`, `web/test/`, `web/playwright/`, `web/dist/` | Halogen application + tests + E2E + bundle |
| Pulumi infrastructure | `infra/pulumi/` | TypeScript program for the ephemeral-Kind stack used by `jitml-e2e` |
| Experiments | `experiments/` | Canonical experiment Dhall files (the "configuration is code" surface) |
| Tests | `test/` | Per-stanza test trees (`test/unit/`, `test/integration/`, `test/sl-canonicals/`, `test/rl-canonicals/`, `test/hyperparameter/`, `test/cross-backend/`, `test/daemon-lifecycle/`, `test/e2e/`, `test/haskell-style/`, `test/purescript-style/`) and golden fixtures (`test/golden/sl/`, `test/golden/rl/`, `test/golden/cli/`, `test/golden/routes/`, `test/golden/grafana/`, `test/golden/tuning/`, `test/golden/cross-backend/`) |
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
