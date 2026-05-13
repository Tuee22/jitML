# jitML

> Deterministic, reproducible, JIT-compiled machine learning for Haskell.

`jitML` is a Haskell-native machine learning framework for training deep artificial neural networks with fully reproducible execution semantics across supervised learning and reinforcement learning workloads.

Unlike traditional ML frameworks that embed dynamic Python runtimes, opaque kernels, and nondeterministic execution paths, `jitML` treats *the entire training process* as a declarative, reproducible program.

Models, optimizers, datasets, reinforcement learning environments, checkpoints, hardware backends, loss functions, training schedules, hyperparameter sweeps, and cluster topology are all described in `.dhall`.

`jitML` then compiles hardware-specific kernels on demand, builds optimized native binaries, and executes them through Haskell FFI bindings.

The result is:

- reproducible training
- reproducible reinforcement learning
- reproducible stochasticity
- reproducible checkpoint recovery
- deterministic distributed execution
- hardware-native performance
- fully declarative experiment definitions

> **Status:** This README expresses the project's intent and roadmap. The repository is in its bootstrap phase. The first deliverable is the MNIST shallow-MLP training run described in [First milestone](#first-milestone).

> **Doctrine and siblings:** The authoritative CLI doctrine lives at [`HASKELL_CLI_TOOL.md`](HASKELL_CLI_TOOL.md). Two sibling projects inform the structure of this repository — `~/MCTS` (a deterministic Monte Carlo Tree Search runtime; jitML borrows its testing-and-determinism arc) and `~/infernix` (a k8s-first inference control plane; jitML borrows its infrastructure layout). Their scopes are not combined with jitML's.

---

# Why this exists

The mainstream ML stack is Python + PyTorch / JAX + dynamic graphs + opaque CUDA kernels + best-effort seeding. It is fast at iterating on research ideas and slow at giving the same answer twice. Bit-exact reproduction is a debugging aid, not an architectural invariant: cuDNN convolutions are nondeterministic by default; data loaders shuffle in OS-thread order; mixed-precision reductions reassociate; checkpoint replay restores weights but not RNG state; hyperparameter sweeps record best-trial numbers but not the search-strategy state that produced them.

We want a runtime that is:

1. **Reproducible by construction.** Given identical inputs, seeds, and configuration, two runs produce identical outputs — including parameter initialization, minibatch ordering, optimizer state, RL trajectories, MCTS exploration paths, hyperparameter-trial selection, and checkpoint recovery. Reproducibility is an architectural requirement, not a flag.
2. **Declarative end-to-end.** A `.dhall` file is the full source of truth for a training run, a hyperparameter sweep, an RL experiment, or a cluster deployment. The CLI flags layered on top *override* the Dhall; they never replace it.
3. **Hardware-native without an embedded Python runtime.** jitML compiles kernels on demand for Apple Metal, NVIDIA CUDA, oneDNN/AVX, or OpenCL, and executes them through Haskell FFI bindings. The runtime has no Python interpreter in the loop.

---

# Substrates and runtime modes

jitML produces **one Haskell front end** with JIT codegen for several hardware targets, packaged as **three supported substrates**:

| Substrate | Codegen | Container shape | Daemon shape |
|---|---|---|---|
| `apple-silicon` | Swift + Metal | partial (cluster services in Kind; Metal-using daemon host-native — Metal can't be containerized) | host-native `./.build/jitml service` subscribed to cluster Pulsar |
| `linux-cpu` | oneDNN + AVX2/AVX-512 | fully containerized: `jitml-linux-cpu:local` | clustered `jitml-service` pod |
| `linux-cuda` | CUDA C + cuBLAS / cuDNN | fully containerized: `jitml-linux-cuda:local` (NVIDIA runtime class) | clustered `jitml-service` pod |

A fourth "coverage" target (`linux-opencl` / Intel GPU) is reserved as an optional substrate; it is not part of the v1 milestone.

Each substrate carries its own determinism contract:

- **`apple-silicon`** — Metal compute kernels execute on the host GPU; float-accumulation order is fixed by the kernel's reduction tree (no fast-math); RNG state lives in the host daemon; kernel-launch ordering is single-stream by default.
- **`linux-cpu`** — oneDNN dispatches to a per-host vector ISA detected at JIT time; reductions are blocked with a fixed block size so the accumulation tree is host-independent; RNG state lives in the clustered service pod.
- **`linux-cuda`** — CUDA kernels disable `--use_fast_math`; per-block reductions use a deterministic warp-shuffle pattern; cuBLAS and cuDNN are pinned to deterministic algorithm selections; RNG is the host's splitmix, never the GPU's curand.

Cross-substrate equality is not guaranteed bit-for-bit — float arithmetic on different hardware reassociates at the last few ULPs — but *same-substrate equality is guaranteed*, and cross-substrate tolerance is measured and tracked per [Cross-substrate verification](#test-suite-stanzas).

---

# Apple Silicon hybrid pattern

Metal cannot be containerized. The supported Apple lane is therefore hybrid: a host-native daemon for compute, with the rest of the stack in Kind.

Shape:

- `./.build/jitml service` runs **host-native** on Apple (no HTTP listener; Pulsar subscriber only).
- The host daemon owns the Kind lifecycle: `jitml cluster up` writes the Kind config, brings up Kind, writes kubeconfig to `./.build/jitml.kubeconfig`, runs the phased Helm deploy from [Helm chart layout](#helm-chart-layout).
- The host daemon **subscribes to cluster Pulsar** for instructions — `training.command.apple-silicon`, `tune.command.apple-silicon`, `rl.command.apple-silicon` — and **publishes events back to cluster Pulsar** (`training.event.apple-silicon`, etc.).
- The host daemon **reads and writes checkpoints from cluster MinIO** through the routed `/minio/s3` surface.
- The host daemon JIT-compiles Metal kernels and executes them with direct GPU access.
- Pulsar endpoint discovery: the daemon reads `./.data/runtime/cluster-publication.json` (written by `cluster up`) for `pulsar_ws_url`, `pulsar_admin_url`, `minio_s3_url`, `edge_port`. No service-discovery RPC; the cluster publishes its own coordinates to a known file.

On Linux substrates the daemon runs **in-cluster** as the `jitml-service` deployment; nothing else changes. The Pulsar topic semantics are identical; only the daemon's residence differs.

---

# Bootstrap scripts

Stage-0 idempotent prereq reconcilers, one per substrate:

```
./bootstrap/apple-silicon.sh
./bootstrap/linux-cpu.sh
./bootstrap/linux-cuda.sh
```

Each script is **idempotent and restartable**: it probes host state, installs missing prerequisites, verifies tools in the same process before continuing.

- `apple-silicon.sh` reconciles Homebrew + ghcup (pinned GHC 9.14.1 + Cabal 3.16.1.0) + `protoc` + Colima (8 CPU / 16 GiB) + Docker + `kind` + `kubectl` + `helm` + Node.js + Poetry on demand.
- `linux-cpu.sh` builds the `jitml-linux-cpu:local` substrate image and then runs all further commands as `docker compose run --rm jitml jitml ...`.
- `linux-cuda.sh` adds NVIDIA driver checks; on missing driver it installs, then stops and asks the user to reboot.

Forbidden: anything that touches `~/.kube/config`, `~/.docker/config.json`, the user's global Homebrew prefix as a writer, or any global state outside the repo. All build state lives under `./.build/`; all runtime state lives under `./.data/`; both are `.gitignore`'d.

---

# Cluster topology and Kind

Per-substrate Kind configs at `./kind/cluster-<substrate>.yaml`. Single control-plane + one worker on Apple Silicon (collocated); identical layout for Linux CPU; Linux CUDA labels the worker `jitml.runtime/gpu=true` so the NVIDIA runtime class binds there.

The edge port (Envoy listener) is selected starting at 9090 and incremented until available; recorded at `./.data/runtime/edge-port.json` and reported by `jitml cluster status`. NodePort 30090 is the in-cluster service for the edge gateway.

Kubeconfig lives at `./.build/jitml.kubeconfig`. The CLI never touches `~/.kube/config`. The `kindest/node` version is pinned in `cabal.project` so reproducibility includes the cluster image, not just the GHC version.

Storage is a `jitml-manual` storage class (no provisioner) backed by host-path PVs under `./.data/kind/<substrate>/`. State is **replayed in/out** of the worker on Apple Silicon (slower bind-mounts, large state) and bind-mounted on Linux.

---

# Envoy Gateway API: a single localhost socket

> "There is to be a single socket accessible to localhost with Envoy as the reverse proxy to all the endpoints."

One Envoy-Gateway-API-owned localhost listener (`Gateway/jitml-edge`, port chosen by `cluster up` starting at `9090`) backed by the repo-owned `EnvoyProxy/jitml-edge` service shape:

- `GatewayClass/jitml-gateway` + `Gateway/jitml-edge` listening at `127.0.0.1:<edge-port>`.
- `EnvoyProxy/jitml-edge` is a NodePort service with `externalTrafficPolicy: Cluster`, port 30090 in-cluster.
- Routes are not hand-written YAML; they are Haskell-rendered `HTTPRoute` resources from a single **route registry** in `src/JitML/Routes.hs`. The registry is the source of truth, consumed by both the chart-template renderer and the `docs check`/`docs generate` pair that gates README drift (per [`HASKELL_CLI_TOOL.md`](HASKELL_CLI_TOOL.md) §Generated Artifacts).

Routes published at the edge (all under one `127.0.0.1:<edge-port>`):

| Path prefix | Upstream | Rewrite |
|---|---|---|
| `/` | `jitml-demo:80` (the PureScript app) | (none) |
| `/api` | `jitml-demo:80` | (none) |
| `/api/ws` | `jitml-demo:80` WebSocket | (none) — live training events |
| `/tensorboard` | `tensorboard:6006` | `/` |
| `/grafana` | `grafana:3000` | `/` |
| `/prometheus` | `prometheus:9090` | `/` |
| `/harbor` | `jitml-harbor-portal:80` | `/` |
| `/harbor/api` | `jitml-harbor-core:80` | `/api` |
| `/minio/console` | `jitml-minio-console:9090` | `/` |
| `/minio/s3` | `jitml-minio:9000` | `/` |
| `/pulsar/admin` | `jitml-pulsar-proxy:80` | `/admin` |
| `/pulsar/ws` | `jitml-pulsar-proxy:80` WebSocket | `/ws` |

TLS is off for the local demo. Production deployments are out of scope for v1; the route registry just declares the surfaces.

---

# Helm chart layout

Single umbrella chart at `./chart/`. `Chart.yaml` declares subchart dependencies:

- `harbor` — image registry.
- `pg-operator` + `pg-db` — Percona Kubernetes Operator, providing HA Postgres for Harbor and experiment metadata.
- `pulsar` — Apache Pulsar with ZooKeeper + BookKeeper + Broker + Proxy + WebSocket.
- `minio` — distributed mode, four replicas.
- `gateway-helm` — Envoy Gateway controller.
- `kube-prometheus-stack` — Prometheus operator + Grafana.
- `tensorboard` — a jitML-owned chart for TensorBoard with MinIO-backed event storage.

Templates in `chart/templates/`: GatewayClass, Gateway, HTTPRoutes (rendered from the route registry), EnvoyProxy, PVCs, NVIDIA RuntimeClass for the CUDA substrate, Grafana datasources and dashboards (provisioned ConfigMaps), Prometheus scrape configs.

Namespace: `platform` (fixed for v1). `jitml cluster up` creates it idempotently.

**Phased deploy** (verbatim from infernix's lessons):

1. **Bootstrap phase**: Harbor + MinIO + Postgres only, pulling images from public registries.
2. **Mirror phase**: every third-party image is mirrored into Harbor.
3. **Final phase**: Pulsar, Envoy Gateway, kube-prometheus-stack, TensorBoard, the jitML service workload (Linux substrates), the jitML-demo workload — all pulling exclusively from local Harbor.

This avoids the chicken-and-egg of "Harbor isn't up yet, but everything wants to pull from it" without resorting to image-pull-secret juggling.

---

# Harbor as the registry

All container images go through Harbor. No Docker Hub pulls after the bootstrap phase. The build pipeline pushes to `harbor.platform.svc.cluster.local/jitml/<image>:<tag>` and the in-cluster `imagePullPolicy: IfNotPresent` resolves from there.

Harbor's own image-chart storage backend is **MinIO** (S3 API), so Harbor's blobs and MinIO's buckets share a durability story.

Routed at `/harbor` (portal) and `/harbor/api` (API).

---

# MinIO object store

Buckets, provisioned by the Helm `provisioning.buckets` block:

- `harbor-registry` — Harbor's S3 backend (128 MiB chunk size).
- `jitml-checkpoints` — training checkpoints. One prefix per experiment hash; content-addressed inside the prefix.
- `jitml-datasets` — pinned source datasets (MNIST, Fashion-MNIST, CIFAR-10 binaries). Lazily populated on first use, SHA-256 verified against the experiment Dhall.
- `jitml-transcripts` — RL trajectory transcripts (the analog of MCTS's `.mcts-cache/transcripts/`).
- `jitml-trials` — hyperparameter trial transcripts, content-addressed by `sha256(resolved-dhall || trial-seed)`.
- `jitml-tensorboard` — TensorBoard event files so the TB pod is stateless and can reschedule freely.
- `jitml-artifacts` — large inference outputs (when the demo is in inference mode).

Endpoints: `jitml-minio.platform.svc.cluster.local:9000` (in-cluster); `127.0.0.1:<edge-port>/minio/s3` (routed). Credentials pinned in values for the local demo; production posture is out of scope.

---

# Pulsar as the control-plane ↔ data-plane bus

Apache Pulsar HA chart: 3× ZooKeeper, 3× BookKeeper, 3× Broker, 3× Proxy, WebSocket enabled. WebSocket is what lets the PureScript frontend subscribe to live training events through the Envoy `/pulsar/ws` route.

Topic family (substrate-scoped — `<mode>` ∈ `apple-silicon`, `linux-cpu`, `linux-cuda`):

| Topic | Direction | Carrying |
|---|---|---|
| `training.command.<mode>` | control plane → daemon | StartTraining, StopTraining, ResumeFromCheckpoint, AbortTraining |
| `training.event.<mode>` | daemon → control plane / frontend | StepDone, EpochDone, EvalDone, CheckpointDone, MetricUpdate, TrainingFinished, TrainingFailed |
| `tune.command.<mode>` | control plane → daemon | RunTrial, StopTrial |
| `tune.event.<mode>` | daemon → control plane / frontend | TrialStarted, TrialMetricUpdate, TrialFinished, TrialFailed |
| `rl.command.<mode>` | control plane → daemon | StartRLRun, StopRLRun |
| `rl.event.<mode>` | daemon → control plane / frontend | EpisodeDone, EvalDone, CheckpointDone, MetricUpdate |
| `inference.request.<mode>` | demo frontend → daemon | inference requests (when demo is in inference mode) |
| `inference.result.<mode>` | daemon → demo frontend | inference results |

**Protobuf contract.** Schemas in `./proto/jitml/`, with Haskell bindings via `proto-lens` and PureScript bindings via `purescript-bridge`.

**Fallback when Pulsar is absent.** When `JITML_PULSAR_WS_BASE_URL` and `JITML_PULSAR_ADMIN_URL` env vars are unset (e.g., unit tests), the harness uses a repo-local topic spool at `./.data/runtime/pulsar/`. Tests use this; nothing else.

---

# PostgreSQL

Percona Kubernetes Operator manages a Patroni-backed HA Postgres cluster. Roles:

- Harbor's metadata store.
- Experiment metadata: run identifiers, trial state, checkpoint references, lineage between training runs and their resumes.

Every PVC workload that needs Postgres uses the operator-managed Patroni cluster, not a chart-deployed standalone instance.

---

# TensorBoard, Prometheus, Grafana as first-class

**TensorBoard.** A `tensorboard` pod that uses the `jitml-tensorboard` MinIO bucket as its event-file backend, routed at `/tensorboard`. Every training run writes scalars, distributions, histograms, and image summaries to a per-run prefix in the bucket. The bucket's per-prefix layout is content-addressed by the experiment hash, so re-running an experiment overlays its events on the same TB run by default (configurable). TensorBoard is the headline visualization for SL training; the PureScript frontend's training panel embeds the TB iframe.

**Prometheus.** Deployed via `kube-prometheus-stack`. Scrape targets, declared as a typed Haskell value in `src/JitML/Observability/Prometheus.hs`:

- The `jitml-service` daemon (`/metrics` endpoint) — training-step latency, GPU utilization (Metal/CUDA queries), batch throughput, checkpoint write latency, MinIO call latency, Pulsar consume-lag.
- Pulsar broker / proxy.
- MinIO (S3 API metrics).
- Harbor.
- Kind nodes (kubelet + cAdvisor).

**Grafana.** Provisioned dashboards committed to the repo, **generated from typed Haskell datatypes** via a renderer in `src/JitML/Observability/Grafana.hs`. Dashboards rendered for v1:

- *Training overview* — loss curves, validation metrics, throughput, GPU utilization, GC time per run.
- *RL overview* — per-env episode reward distribution, env-steps/sec, replay-buffer fill, exploration rate.
- *Hyperparameter sweep* — Pareto frontier, trial heatmap, search-strategy state (Sobol cursor, GA generation).
- *Cluster health* — node CPU/mem, pod restarts, image-pull latency, PVC saturation.

The dashboards are gated by lint just like the route registry: `jitml docs check` compares the renderer's output against committed JSON fixtures, and `jitml docs generate` writes them back.

---

# Outer-container Linux builds

On Linux substrates, *all* builds happen inside `docker compose run --rm jitml jitml ...` against the substrate image (`jitml-linux-cpu:local` or `jitml-linux-cuda:local`). The image carries ghcup, Poetry, Node.js 22+, Kind/kubectl/Helm/Docker toolbelt, LLVM, NVCC (on CUDA), and Playwright. Bind mounts: `./` for source, `./.build/` for outputs.

On Apple Silicon, `cabal install` runs directly on the host because the host is the GPU. The asymmetry is intentional: the inner container ensures the Linux build is bit-reproducible across hosts; the Apple host build is reproducible because the host GHC and Cabal versions are pinned by the bootstrap script.

---

# CLI command topology, typed

Per [`HASKELL_CLI_TOOL.md`](HASKELL_CLI_TOOL.md) §Command Topology, commands are modelled as ordinary Haskell data types and the parser is generated from a separate `CommandSpec`. Two Haskell executables share one Cabal library: `app/Main.hs` → `jitml` (control plane + daemon); `app/Demo.hs` → `jitml-demo` (HTTP server hosting the PureScript bundle).

```haskell
data Command
  = Cluster   ClusterCommand          -- up, down, status, reset
  | Service   ServiceOptions          -- the production daemon (Pulsar subscriber)
  | Train     TrainOptions            -- one-shot training; publishes to Pulsar internally
  | Eval      EvalOptions
  | Tune      TuneOptions             -- hyperparameter search
  | RL        RLCommand               -- start an RL run; the daemon executes
  | Verify    VerifyCommand           -- cross-backend / cross-run determinism
  | Inspect   InspectCommand          -- transcripts, checkpoints, trials, frontiers
  | Bench     BenchCommand            -- throughput / scaling measurements
  | Test      TestCommand             -- jitml test all + per-stanza
  | Lint      LintCommand
  | Docs      DocsCommand
  | Kubectl   KubectlPassthrough      -- pre-bound to ./.build/jitml.kubeconfig
  | Internal  InternalCommand         -- materialize-substrate, generate-purs-contracts, ...
  | Commands  CommandsOptions
  | Help      HelpOptions
  deriving stock (Show, Eq)

data ClusterCommand
  = ClusterUp     ClusterUpOptions
  | ClusterDown   ClusterDownOptions
  | ClusterStatus
  | ClusterReset                       -- destructive; requires --yes
  deriving stock (Show, Eq)

data TrainOptions = TrainOptions
  { trainExperiment       :: FilePath
  , trainSubstrate        :: Substrate
  , trainSeed             :: Word64
  , trainResume           :: Maybe CheckpointRef
  , trainMaxSteps         :: Maybe Int
  , trainCheckpointBucket :: Text
  } deriving stock (Show, Eq)

data RLCommand
  = RLTrain    RLTrainOptions
  | RLEval     RLEvalOptions
  | RLRollout  RLRolloutOptions        -- fixed-seed determinism cohort
  deriving stock (Show, Eq)

data InspectCommand
  = InspectList
  | InspectShow      ShowOptions
  | InspectReplay    ReplayOptions     -- TUI replay
  | InspectTrial     TrialOptions
  | InspectFrontier  FrontierOptions
  deriving stock (Show, Eq)

data InternalCommand
  = MaterializeSubstrate     SubstrateOptions
  | GeneratePursContracts
  | GenerateRouteTable
  | GenerateGrafanaDashboards
  | GenerateProtoSchemas
  deriving stock (Show, Eq)

data Substrate = AppleSilicon | LinuxCPU | LinuxCUDA
                  deriving stock (Show, Eq)
```

Concrete invocations:

```bash
./bootstrap/apple-silicon.sh                 # stage-0, idempotent
./.build/jitml cluster up                    # phased Helm deploy + route table
./.build/jitml cluster status                # prints edge port and routes

./.build/jitml train  experiments/mnist-mlp.dhall --substrate apple-silicon --seed 42
./.build/jitml tune   experiments/mnist-mlp.dhall --strategy sobol --trials 64 --parallelism 8
./.build/jitml tune   experiments/mnist-mlp.dhall --strategy ga    --population 32 --generations 20
./.build/jitml rl     train experiments/cartpole-ppo.dhall --substrate apple-silicon --seed 42
./.build/jitml verify same-run     --experiment experiments/mnist-mlp.dhall --runs 3
./.build/jitml verify cross-backend --experiment experiments/mnist-mlp.dhall --backends cpu,cuda
./.build/jitml inspect frontier --tuning-run <ref> --pareto valLoss params
./.build/jitml test   all
```

`Service` is the long-running daemon. Per [`HASKELL_CLI_TOOL.md`](HASKELL_CLI_TOOL.md) §Long-Running Daemons in the Same Binary it ships with `/healthz`, `/readyz`, `/metrics`, structured JSON logging, drain-on-SIGTERM, and a `BootConfig`/`LiveConfig` split with SIGHUP hot reload of the latter. See [Doctrine scope](#doctrine-scope) for the in-scope/out-of-scope split.

### Progressive introspection

Per doctrine §Progressive Introspection:

```bash
jitml commands              # flat list of every subcommand
jitml commands --tree       # tree rendering
jitml commands --json       # JSON command schema (externally stable interface)
jitml help <subcommand>     # focused help, equivalent to `<subcommand> --help`
```

---

# Numerical core

## Deep neural networks

`jitML` supports arbitrarily-shaped non-recurrent feedforward networks including:

- dense / fully-connected layers
- convolutional layers
- residual blocks
- batch normalization
- multi-headed architectures
- arbitrary DAG-style computation graphs

## Activation functions

### Real-valued

ReLU, LeakyReLU, GELU, ELU, Sigmoid, Tanh, Softmax.

### Complex-valued

Complex-valued neural networks are first-class citizens. Supported and planned activations:

- zReLU (Guberman 2016)
- modReLU (Arjovsky 2016)
- complex tanh
- complex sigmoid
- phase-preserving activations

Complex arithmetic is represented natively throughout tensors, convolutions, optimizers, normalization, FFT/DFT transforms, and loss functions.

## Spectral / frequency-domain operations

Native support for DFT, inverse DFT, FFT-based convolutions, spectral pooling, complex-domain architectures.

## Optimization

Supported optimizers: SGD, Momentum SGD, RMSProp, Adam, AdamW. Optimizer state is fully deterministic and checkpointable.

## Loss functions

Loss functions are represented declaratively in Dhall: scalar losses, multi-headed losses, weighted losses, policy/value hybrid losses, and arbitrary symbolic compositions.

---

# Concrete Dhall worked example

A canonical SL experiment, end-to-end:

```dhall
-- experiments/mnist-mlp.dhall

let Activation = ./types/Activation.dhall
let Layer      = ./types/Layer.dhall
let Optimizer  = ./types/Optimizer.dhall
let Dataset    = ./types/Dataset.dhall
let Split      = ./types/Split.dhall
let Checkpoint = ./types/Checkpoint.dhall
let Substrate  = ./types/Substrate.dhall

let mnistTrain : Dataset =
      { name   = "mnist-train"
      , url    = "https://storage.googleapis.com/cvdf-datasets/mnist/train-images-idx3-ubyte.gz"
      , sha256 = "440fcabf73cc546fa21475e81ea370265605f56be210a4024d2ca8f203523609"
      , kind   = Dataset.Kind.MNIST
      }

let mnistTest : Dataset =
      { name   = "mnist-test"
      , url    = "https://storage.googleapis.com/cvdf-datasets/mnist/t10k-images-idx3-ubyte.gz"
      , sha256 = "8d422c7b0a1c1c79245a5bcf07fe86e33eeafee792b84584aec276f5a2dbc4e6"
      , kind   = Dataset.Kind.MNIST
      }

in
{ experiment = "mnist-mlp"
, model =
    [ Layer.Dense    { in_ = 784, out = 128, activation = Activation.ReLU }
    , Layer.Dropout  { rate = 0.2 }
    , Layer.Dense    { in_ = 128, out =  10, activation = Activation.Softmax }
    ]
, loss = Layer.Loss.CrossEntropy
, optimizer = Optimizer.Adam { learningRate = 1.0e-3, beta1 = 0.9, beta2 = 0.999, eps = 1.0e-8 }
, dataset = { train = mnistTrain, test = mnistTest }
, split = Split.PermuteUnderSeed { fullTrain = mnistTrain, trainFraction = 55000.0 / 60000.0, seed = 1729 }
, schedule =
    { epochs = 20
    , batchSize = 128
    , validationCadence = Some 200            -- every 200 steps
    , earlyStopping = None Layer.EarlyStop
    }
, checkpoint =
    { cadence  = Checkpoint.Cadence.EveryEpoch
    , bucket   = "jitml-checkpoints"
    , retain   = Checkpoint.Retention.LastN 5
    }
, substrate = Substrate.AppleSilicon
, seed = 42
}
```

The `Tuning` block, when present, turns the single-run definition into a sweep — see [Hyperparameter tuning](#hyperparameter-tuning-first-class).

---

# Hyperparameter tuning, first-class

A `Tuning` block in any experiment Dhall converts a single-run definition into a multi-trial sweep. The same Dhall describes a single training run (no `tuning`) or a 128-trial sweep (`tuning = Some Tuning::{ … }`); the CLI flag `--strategy …` *overrides* the Dhall, never replaces it.

## Search-space declaration

```dhall
let Continuous   = { min : Double, max : Double, scale : < Linear | Log > }
let Discrete     = { values : List Natural }
let Categorical  = { values : List Text }

let SearchSpace =
      { learningRate : Continuous
      , batchSize    : Discrete
      , dropout      : Continuous
      , optimizer    : Categorical
      }
```

## Search strategies

```dhall
let Strategy =
      < Sobol  : { dimensions : Natural, seed : Natural }
      | Random : { seed : Natural }
      | GA     : { population : Natural
                 , generations : Natural
                 , mutationRate : Double
                 , crossoverRate : Double
                 , seed : Natural
                 }
      | ES     : { mu : Natural, lambda : Natural, sigma : Double, seed : Natural }
      >
```

- **Sobol low-discrepancy quasi-random** — deterministic given the Sobol seed + dimensions; bit-reproducible trial selection.
- **Random search (uniform)** — trivial baseline.
- **Evolutionary / genetic algorithm** — explicit parent-selection, mutation, and crossover operators per parameter type.
- **(μ, λ) evolution strategies** — for continuous spaces.

## Trial storage and resume

Each trial writes a self-contained transcript to MinIO bucket `jitml-trials`, content-addressed by `sha256(resolved-dhall || trial-seed)`. Trial contents: the resolved Dhall, the seed, the metric trajectory, the final-checkpoint MinIO ref, the wall-clock.

A `tune` run can be resumed: the resumed run re-reads the trial bucket, skips already-completed `(resolved-dhall, seed)` pairs, and proceeds. The search-strategy state (Sobol cursor, GA population, etc.) is itself reproducible from the strategy's seed and the set of completed trials.

## Parallelism

`--parallelism N` schedules N trials concurrently; the search algorithm exposes a "next batch of K candidates" interface, and the dispatcher publishes them to N workers via `tune.command.<mode>` Pulsar messages. Per-trial determinism is unaffected by N (each trial owns its seed); only wall-clock changes.

## Frontend integration

The PureScript frontend's hyperparameter panel subscribes to `tune.event.<mode>` over `/pulsar/ws` and animates the Pareto frontier and trial heatmap live (see [PureScript frontend](#purescript-frontend)).

---

# Canonical supervised learning problems

Five problems, all small enough to live in CI:

| Dataset | Model | Source | Test target (golden) | Train budget |
|---|---|---|---|---|
| MNIST | shallow MLP (1×128 hidden) | LeCun mirror | TBD | TBD |
| MNIST | deep CNN (LeNet-5 variant) | LeCun mirror | TBD | TBD |
| Fashion-MNIST | shallow MLP | Zalando mirror | TBD | TBD |
| Fashion-MNIST | deep CNN | Zalando mirror | TBD | TBD |
| CIFAR-10 | ResNet-20 | Toronto mirror | TBD | TBD |

## Threshold methodology

The literal numbers in the table are derived from a `k=5` replicate baseline on the pinned reference host: five seeds, each trained to a budget that visibly plateaus the loss curve, then

```
target = median(test_acc) − slack
slack  = 95th-percentile residual deviation across the five seeds
```

so the golden passes with 95% probability if no regression has occurred. The README ships with TBD cells; populating them is gated on the baseline run. Treating the numbers as load-bearing before baselining is forbidden.

## Dataset pinning

Each dataset's source URL is pinned, the source bytes' SHA-256 is recorded, and the train/val/test split is a deterministic permutation under a fixed seed. Datasets land in MinIO bucket `jitml-datasets` on first use; subsequent runs read from MinIO.

## Golden test shapes

For each `(dataset, model)` pair the test suite asserts three goldens:

- **Determinism golden** — `train` produces bit-identical checkpoint files on the same substrate across runs.
- **Convergence golden** — the median over `k=5` seeds clears the row's target.
- **Curve golden** — the per-epoch curves match a stored fixture within the measured tolerance.

---

# Canonical reinforcement learning environments

Own implementations in Haskell (no Gymnasium dependency at the env layer; jitML reaches every environment through the same `Env` capability, whether native Haskell, FFI, or RPC):

| Env | Action space | Obs space | Termination |
|---|---|---|---|
| CartPole-v1 | Discrete(2) | Box(4) | pole-angle out of bounds or 500 steps |
| MountainCar-v0 | Discrete(3) | Box(2) | reach goal or 200 steps |
| Acrobot-v1 | Discrete(3) | Box(6) | tip above height or 500 steps |
| Pendulum-v1 | Box(1) | Box(3) | 200 steps |
| LunarLander-v2 (discrete) | Discrete(4) | Box(8) | crash, land, or 1000 steps |
| GridWorld-Deterministic-v0 | Discrete(4) | Discrete(N) | reach goal or 100 steps |

GridWorld is jitML-original and serves as a deterministic-by-construction unit-level golden — its trajectory is a pure function of `(seed, policy)` and can be asserted bit-for-bit. For each non-jitML-original env, the dynamics are re-implemented in Haskell from the published equations.

---

# RL framework primitives

We borrow the *concepts* stable-baselines3 codifies — policies, environments, buffers, schedules, distributions, callbacks, loggers, evaluators, action noise, target networks, advantage estimation, training loops — and express them as idiomatic Haskell types. We do not borrow the class hierarchy, the pickle save/load path, or the `gym.make()` registry. We are not reimplementing PyTorch; we are giving the RL training-loop domain a typed Haskell vocabulary.

## Algorithm class taxonomy at the type level

`OnPolicy` and `OffPolicy` are phantom kinds; the algorithm GADT is indexed by class. PPO touching a `ReplayBuffer`, or DQN touching a `RolloutBuffer`, is a compile-time error rather than a runtime surprise.

```haskell
data AlgoClass = OnPolicy | OffPolicy

type AlgoSpec :: AlgoClass -> Type -> Type -> Type
data AlgoSpec c obs act where
  PPO  :: PPOConfig  -> AlgoSpec 'OnPolicy  obs act
  A2C  :: A2CConfig  -> AlgoSpec 'OnPolicy  obs act
  DQN  :: DQNConfig  -> AlgoSpec 'OffPolicy obs 'Discrete
  DDPG :: DDPGConfig -> AlgoSpec 'OffPolicy obs 'Continuous
  TD3  :: TD3Config  -> AlgoSpec 'OffPolicy obs 'Continuous
  SAC  :: SACConfig  -> AlgoSpec 'OffPolicy obs 'Continuous
```

HER is a buffer transformer, not its own GADT case; see [Buffers](#buffers).

## Policy as typed value

Feature extractor + action head + (optional) value head, all expressed as `Network` graphs that jitML's JIT compiler lowers to whichever substrate is selected. Variants are records of named layers, *not* a class hierarchy:

```haskell
data Policy obs act = Policy
  { features   :: Network obs Features
  , actionHead :: Network Features (DistParams act)
  , valueHead  :: Maybe (Network Features Scalar)        -- present iff actor-critic
  }
```

SB3's `MlpPolicy` / `CnnPolicy` / `MultiInputPolicy` distinction collapses into "what does the feature extractor look like" — a Dhall-level choice, not a separate type.

## Environment as a typed capability

Record-of-functions shape; the same type covers native Haskell envs, FFI envs (C/C++/Rust), and RPC envs.

```haskell
data Env obs act = Env
  { envStep             :: Action act -> IO (Obs obs, Reward, Done, Info)
  , envReset            :: Seed -> IO (Obs obs)
  , envActionSpace      :: ActionSpace act
  , envObservationSpace :: ObservationSpace obs
  }

data ActionSpace a where
  Discrete       :: Int -> ActionSpace 'Discrete
  Box            :: Shape -> Bounds -> ActionSpace 'Continuous
  MultiDiscrete  :: [Int] -> ActionSpace 'MultiDiscrete
  Dict           :: Map Text SomeActionSpace -> ActionSpace 'Dict
```

Env *wrappers* are pure `Env -> Env` transformations: `clipReward`, `normaliseObservations`, `frameStack`, `noopReset`, `timeLimit`, `rewardShaper`. They compose via function composition; no class hierarchy.

## Vectorised environments (VecEnv)

Two implementations behind one type, mirroring SB3's `DummyVecEnv` / `SubprocVecEnv`:

```haskell
data VecEnv obs act
  = SyncVec   { syncEnvs     :: [Env obs act] }                  -- single-threaded N envs
  | AsyncVec  { asyncWorkers :: WorkerPool (Env obs act) }        -- N OS processes / threads
```

The per-env RNG seed is split deterministically by `splitmix64(master_seed, env_index)`. Worker count and scheduling never affect any individual env's RNG stream — only wall-clock changes.

## Buffers

Two distinct buffer types; the GADT indexing in [Algorithm class taxonomy](#algorithm-class-taxonomy-at-the-type-level) keeps each algorithm restricted to its own.

```haskell
data RolloutBuffer obs act = RolloutBuffer
  { rolloutSize  :: Int                                    -- fixed length per update
  , gamma        :: Double
  , gaeLambda    :: Double
  , transitions  :: MutableArray (Transition obs act)
  }

data ReplayBuffer obs act = ReplayBuffer
  { capacity     :: Int                                    -- ring size
  , prioritised  :: Maybe PriorityConfig                   -- α, β, ε for PER
  , storage      :: RingBuffer (Transition obs act)
  , samplingSeed :: Seed                                   -- bit-reproducible batch draws
  }

-- HER as a buffer transformer; not its own algorithm case
data HerWrapper inner = HerWrapper
  { strategy      :: HerStrategy                           -- Future | Final | Episode
  , nSampledGoals :: Int
  , innerBuffer   :: inner
  }
```

HER composes onto any off-policy buffer: SB3's `HerReplayBuffer` becomes `HerWrapper (ReplayBuffer obs act)` in jitML.

## Schedules

Pure functions of progress ∈ `[0,1]`:

```haskell
data Schedule a
  = Constant     a
  | Linear       a a                                       -- start, end
  | Piecewise    [(Double, a)]
  | Exponential  { initial :: a, decay :: Double }

evalSchedule :: Schedule a -> Double -> a
```

Used for learning rate, PPO clip range, DQN exploration ε, SAC entropy coefficient floor. SB3's `get_schedule_fn` callable-or-float duality is replaced by a single ADT.

SAC's auto-tuned entropy coefficient uses a related ADT:

```haskell
data EntropyCoef = FixedEntropy Double
                 | AutoEntropy { initial :: Double, targetEntropy :: Double, optimizer :: OptimizerSpec }
```

## Action distributions

Sample, log-prob, entropy, and `mode` (deterministic action) per variant. All sampling is seeded.

```haskell
data ActionDistribution
  = Categorical      { logits :: Tensor }
  | DiagGaussian     { mean :: Tensor, logStd :: Tensor }
  | SquashedGaussian { mean :: Tensor, logStd :: Tensor }    -- tanh-squashed, used by SAC
  | Bernoulli        { logits :: Tensor }

sample  :: ActionDistribution -> Seed -> Action
logProb :: ActionDistribution -> Action -> Tensor
entropy :: ActionDistribution -> Tensor
mode    :: ActionDistribution -> Action                       -- deterministic
```

`gSDE` (generalised State-Dependent Exploration, SB3's alternative continuous-control exploration scheme) is reserved as a future variant; not in v1.

## Action noise

DDPG/TD3 use additive action noise during rollout collection.

```haskell
data ActionNoise
  = NormalNoise            { mean :: Tensor, std :: Tensor }
  | OrnsteinUhlenbeckNoise { mean :: Tensor, std :: Tensor
                           , theta :: Double, sigma :: Double, state :: Tensor }

stepNoise  :: ActionNoise -> Seed -> (Tensor, ActionNoise)    -- sample + advanced state
resetNoise :: ActionNoise -> ActionNoise                       -- on episode boundary
```

OU noise carries state across steps and is reset on episode boundary. Both forms are seed-driven and reproducible.

## Target networks and Polyak averaging

Used by DQN (hard updates) and DDPG/TD3/SAC (soft updates):

```haskell
data TargetNetwork p = TargetNetwork
  { online :: p
  , target :: p
  , tau    :: Double                                       -- 1.0 = hard copy (DQN); 0.005 = soft (TD3/SAC)
  }

polyakUpdate :: TargetNetwork p -> TargetNetwork p
```

Twin critics (TD3, SAC) are a structural pattern, not a separate type: the algorithm record carries `critic1, critic2 :: TargetNetwork ValueNetwork` and the Bellman target takes the min.

## Advantage estimation (GAE)

Pure transformation over the rollout buffer's trajectory tape:

```haskell
computeGae :: RolloutBuffer obs act -> ValueEstimates -> (Advantages, Returns)
```

`gamma` and `gaeLambda` come from the buffer; the bootstrap value comes from a final-step value estimate.

## Callbacks as composable hooks

Typed lifecycle hook set; composes via `Semigroup`:

```haskell
data Callback = Callback
  { onTrainingStart :: TrainingHandle -> IO ()
  , onRolloutStart  :: TrainingHandle -> IO ()
  , onStep          :: TrainingHandle -> Step -> IO StepDecision   -- Continue | StopTraining
  , onRolloutEnd    :: TrainingHandle -> IO ()
  , onEvaluation    :: TrainingHandle -> EvalResult -> IO ()
  , onCheckpoint    :: TrainingHandle -> CheckpointRef -> IO ()
  , onTrainingEnd   :: TrainingHandle -> TrainingResult -> IO ()
  }

instance Semigroup Callback where
  a <> b = Callback { onStep = \h s -> (<>) <$> onStep a h s <*> onStep b h s, ... }
```

Standard library: `checkpointEveryN`, `evaluateEveryN`, `stopOnRewardThreshold`, `stopOnMaxEpisodes`, `stopOnNoImprovement`, `progressBar`. The **production callback** ships every event to Pulsar (`training.event.<mode>`, `rl.event.<mode>`) — every callback invocation is also a typed event on the wire, which is what makes the PureScript frontend's live panels work.

## Logger as multi-sink event emitter

Co-located with the callback set. Logs scalars / histograms / distributions / images to any subset of sinks:

```haskell
data LogSink = LogStdout | LogTensorBoard | LogCsv | LogPulsar | LogJson

data Logger = Logger { sinks :: [LogSink], minLevel :: LogLevel, ... }
```

TensorBoard is the canonical visualisation sink (writes to MinIO bucket `jitml-tensorboard` so the TB pod is stateless and reschedulable). Pulsar is the canonical live-event sink (the frontend reads `/api/ws` ← Pulsar via the demo proxy). `Logger`s compose via `Semigroup`.

## Evaluator

Runs a policy on a fresh seed pool; returns mean ± std reward and per-episode length:

```haskell
data EvalConfig = EvalConfig
  { nEpisodes     :: Int
  , deterministic :: Bool                                  -- True ⇒ uses `mode`, not `sample`
  , maxStepsPerEp :: Maybe Int
  , evalSeed      :: Seed
  }

data EvalResult = EvalResult
  { meanReward     :: Double
  , stdReward      :: Double
  , meanEpisodeLen :: Double
  , perEpisode     :: [EpisodeStats]
  }

evaluatePolicy :: Policy obs act -> Env obs act -> EvalConfig -> IO EvalResult
```

The convergence golden in [Golden tests for RL](#golden-tests-for-rl) lives directly on top of this primitive.

## Training loops as typed pipelines

The load-bearing primitive — the actual `learn()` shape — comes in two variants, indexed by algorithm class so a wrong-loop-for-wrong-algo is a type error.

```haskell
-- On-policy loop (PPO, A2C)
data OnPolicyLoop = OnPolicyLoop
  { totalTimesteps :: Int
  , rolloutSteps   :: Int                                  -- collect this many transitions per update
  , nEpochs        :: Int                                  -- gradient epochs per update
  , miniBatchSize  :: Int
  , callbacks      :: Callback
  , logger         :: Logger
  }

-- Off-policy loop (DQN, DDPG, TD3, SAC)
data OffPolicyLoop = OffPolicyLoop
  { totalTimesteps       :: Int
  , learningStarts       :: Int                            -- random-action warm-up
  , trainFreq            :: TrainFrequency                  -- Step Int | Episode Int
  , gradientSteps        :: Int                            -- updates per trainFreq trigger
  , targetUpdateInterval :: Maybe Int                       -- DQN hard; DDPG/TD3/SAC soft via tau
  , callbacks            :: Callback
  , logger               :: Logger
  }

-- The actual driver; LoopFor is a type family:
--   LoopFor 'OnPolicy  = OnPolicyLoop
--   LoopFor 'OffPolicy = OffPolicyLoop
learn ::
  AlgoSpec c obs act ->
  Env obs act ->
  LoopFor c ->
  Seed ->
  IO (TrainedPolicy obs act, TrainingResult)
```

`PPO + OffPolicyLoop` does not typecheck. The loop body itself decomposes into phases (collect → compute-advantages → optimise → evaluate → checkpoint), each implemented as a pure function over the typed buffers; the IO-effectful steps are env stepping and the checkpoint write to MinIO.

## Worked Dhall: PPO on CartPole

A concrete PPO algorithm config in Dhall, decoded into the `AlgoSpec 'OnPolicy` + `OnPolicyLoop` pair. This is the file `experiments/cartpole-ppo.dhall` referenced from [First milestone](#first-milestone).

```dhall
let Schedule   = ./types/Schedule.dhall
let Activation = ./types/Activation.dhall

in
{ algorithm =
    { kind = "PPO"
    , gamma        = 0.99
    , gaeLambda    = 0.95
    , clipRange    = Schedule.Linear { from = 0.2, to = 0.0 }
    , vfCoef       = 0.5
    , entCoef      = 0.0
    , maxGradNorm  = 0.5
    , learningRate = Schedule.Linear { from = 3.0e-4, to = 0.0 }
    }
, policy =
    { features =
        [ { kind = "Dense", in_ = 4,  out = 64, activation = Activation.Tanh }
        , { kind = "Dense", in_ = 64, out = 64, activation = Activation.Tanh }
        ]
    , actionHead = "CategoricalLogits"
    , valueHead  = Some "Scalar"
    }
, loop =
    { totalTimesteps = 100000
    , rolloutSteps   = 2048
    , nEpochs        = 10
    , miniBatchSize  = 64
    }
, env       = "CartPole-v1"
, vecEnv    = { kind = "Sync", numEnvs = 8 }
, callbacks = [ "checkpointEveryN", "evaluateEveryN" ]
, logger    = { sinks = [ "stdout", "tensorboard", "pulsar" ] }
, seed      = 42
}
```

The Dhall is what the user writes; the typed Haskell record is what the engine sees after `dhall decode`. Every field in the Dhall maps to a primitive named in a subsection above.

## What we explicitly do not borrow

The user's framing for this section was *"we're not reimplementing PyTorch."* The list below names patterns we drop and what jitML uses instead.

- **Python class hierarchy** (`BaseAlgorithm` → `OnPolicyAlgorithm` → `PPO`). Replaced with ADTs + GADTs. Inheritance is not an idiomatic Haskell tool here.
- **Pickle-based save/load** (`model.save()` / `model.load()`). Replaced with Dhall-described configuration + MinIO-checkpointed weights, optimizer state, RNG state, buffer state, and normalisation stats. The full state is reconstructible from `(experiment.dhall, seed, checkpoint blob)`.
- **`gym.make()` env registry.** Replaced with explicit Dhall env declarations referencing typed envs in `src/JitML/Env/`. No global registry; no string-keyed env lookup.
- **Atari preprocessing wrappers** (`NoopResetEnv`, `FireResetEnv`, `MaxAndSkipEnv`, `WarpFrame`, `EpisodicLifeEnv`). Atari is out of scope for v1 (none of the six canonical envs are Atari). These wrappers are reserved for a future Atari milestone.
- **gSDE** (generalised State-Dependent Exploration). Reserved as a future `ActionDistribution` variant; not in v1.
- **stable-baselines3 contrib** (TRPO, ARS, RecurrentPPO, MaskablePPO, CrossQ, TQC). Out of scope for v1 catalog. Each can be added later as another `AlgoSpec` case once the primitives prove out on the v1 seven.
- **PyTorch `DataParallel` / `DistributedDataParallel`.** jitML's distribution story is different: the daemon is single-node by design for v1; cross-substrate determinism is the headline distributed-execution property, not multi-GPU SGD.
- **The default multi-sink logger** that fans out to stdout, csv, log, and tensorboard simultaneously. Replaced with `Semigroup` composition over typed `Logger` and `Callback` values, so the developer states the fan-out explicitly.

---

# RL algorithm catalog

Reproduce the **stable-baselines3** major algorithms. Each row is a typed crosswalk into [RL framework primitives](#rl-framework-primitives) — `Class` names the `AlgoSpec` index, `Loop` names the training-loop variant, `Buffer` names the buffer composition, `Distribution` names the action-distribution variant.

| Algorithm | Class | Loop | Buffer | Distribution | Notes |
|---|---|---|---|---|---|
| PPO | `OnPolicy` | `OnPolicyLoop` | `RolloutBuffer` + GAE | `Categorical` / `DiagGaussian` | the canonical baseline; first to implement |
| A2C | `OnPolicy` | `OnPolicyLoop` | `RolloutBuffer` + GAE | `Categorical` / `DiagGaussian` | sanity check against PPO |
| DQN | `OffPolicy` | `OffPolicyLoop` | `ReplayBuffer` + `TargetNetwork` (hard) | (none; ε-greedy over Q-net) | Atari-class problems out of scope for v1 |
| DDPG | `OffPolicy` | `OffPolicyLoop` | `ReplayBuffer` + `TargetNetwork` (soft) + `ActionNoise` | (deterministic policy + noise) | included for parity with SB3 |
| TD3 | `OffPolicy` | `OffPolicyLoop` | `ReplayBuffer` + 2× `TargetNetwork` + `ActionNoise` | (deterministic policy + noise) | DDPG with twin critics + delayed updates |
| SAC | `OffPolicy` | `OffPolicyLoop` | `ReplayBuffer` + 2× `TargetNetwork` | `SquashedGaussian` | headline off-policy continuous-control algo; `AutoEntropy` |
| HER | meta | (composes onto any off-policy) | `HerWrapper ReplayBuffer` | (inherits) | goal-conditioned replay buffer |

Retired SB3 algorithms (`ACER`, `ACKTR`, `GAIL`) are out of scope.

Algorithm defaults are pinned via SB3 RL Zoo3 as a sanity check, not as a source of truth (a baselined number that differs from RL Zoo3's by more than 1σ on the same env+algo is worth investigating before pinning).

---

# Golden tests for RL

RL goldens are harder than SL goldens because the reward landscape is stochastic and high-variance; a single seed's final reward is not a reliable signal. Five forms stack:

1. **Trajectory determinism golden (cheap, bit-exact).**
   Fix `(env, algo, seed, policy_init)`. Run for a small fixed number of steps. SHA-256 the resulting `(obs, action, reward, done)` sequence. Assert byte equality across runs. Runs in `jitml-unit`; costs seconds.

2. **Convergence golden (the headline test, statistical).**
   Fix `(env, algo, seed_pool of k=5 seeds, hyperparameters)`. Train each seed to the budgeted timesteps. Golden assertion: `median(final_reward) ≥ T`, where `T` is derived on the reference host by `T = median(reward) − slack` with `slack` from the same `k=5` replicate variance methodology used for SL. Stores the full per-seed final-reward distribution as a JSON fixture; regression detection is by distribution shift (Kolmogorov–Smirnov) against the fixture. Runs in `jitml-rl-canonicals`; costs minutes-to-hours per `(env, algo)`.

3. **Replay-from-checkpoint golden.**
   Train to step `S/2`, checkpoint to MinIO, resume to step `S`, compare final checkpoint and final reward distribution to a from-scratch run trained to step `S` with the same seed. Enforces the determinism claim through the checkpoint boundary.

4. **Curve golden (regression detection).**
   The per-evaluation reward curve (20 evaluations across the budget) is stored as a fixture. Regression: any evaluation falls outside the `[μ − 3σ, +∞)` band derived from the k-seed pool. Catches "still passes the final threshold but learning is now slower" regressions.

5. **Wall-clock golden (perf regression).**
   On the pinned reference host, env-steps/sec and gradient-updates/sec are recorded with the convergence run and checked against fixture.

Target matrix (all numeric cells TBD pending baseline; same methodology as the SL canon):

| env | algo | timesteps | reward |
|---|---|---|---|
| CartPole-v1 | PPO | TBD | TBD |
| CartPole-v1 | DQN | TBD | TBD |
| Acrobot-v1 | PPO | TBD | TBD |
| MountainCar-v0 | DQN | TBD | TBD |
| Pendulum-v1 | SAC | TBD | TBD |
| Pendulum-v1 | TD3 | TBD | TBD |
| LunarLander-v2 | PPO | TBD | TBD |
| LunarLander-v2 | DQN | TBD | TBD |
| LunarLander-v2 | SAC | TBD | TBD |

The convergence golden is the load-bearing test; the trajectory-determinism golden runs every commit; the convergence golden runs nightly or on labeled CI only.

---

# Reinforcement learning

`jitML` provides deterministic reinforcement learning infrastructure with reproducible stochastic execution.

## Supported styles

- policy gradient methods
- actor-critic methods
- AlphaZero-style self-play
- Monte Carlo Tree Search
- value learning
- offline RL

## Deterministic stochasticity

All stochastic systems are seed-driven, reproducible, and replayable. RL episode simulators are modeled as Markovian, memoizable, path-dependent stochastic systems. This enables exact replay, deterministic debugging, cache reconstruction, and distributed reproducibility.

## Persistent MCTS state

Monte Carlo exploration caches are preserved between moves. The cache is treated as deterministic, reconstructible, seed-dependent, and path-dependent. Full episode history is sufficient to rebuild exploration state exactly.

---

# Checkpointing

Checkpoints are immutable deterministic snapshots containing:

- model weights
- optimizer state
- RNG state
- replay buffers
- exploration caches
- training metadata
- hardware compilation metadata

Persistence backend: MinIO bucket `jitml-checkpoints` (in-cluster). Checkpoint replay is guaranteed deterministic; the [Replay-from-checkpoint golden](#golden-tests-for-rl) test enforces this through the test suite, not just by design statement.

---

# JIT compilation architecture

The compilation pipeline:

1. Parse `.dhall`
2. Construct typed computation graph
3. Lower graph into backend IR
4. Generate backend-specific source code
5. Compile native binary
6. Load via Haskell FFI
7. Execute pilot benchmarks
8. Determine optimal runtime parameters
9. Begin training

## Hardware auto-tuning

After JIT compilation, `jitML` performs pilot execution to determine optimal batch size, optimal concurrency, optimal self-play parallelism, memory utilization limits, and hardware saturation points. The scheduler dynamically determines the number of simultaneous environments, inference queue batching strategy, GPU occupancy targets, and throughput/latency tradeoffs — all while preserving deterministic execution semantics.

```text
           +----------------------+
           |     .dhall config    |
           +----------+-----------+
                      |
                      v
           +----------------------+
           | typed graph builder  |
           +----------+-----------+
                      |
                      v
           +----------------------+
           | backend codegen IR   |
           +----------+-----------+
                      |
       +--------------+---------------+
       |              |               |
       v              v               v
+-------------+ +-------------+ +-------------+
| Swift/Metal | | CUDA        | | oneDNN/OCL  |
+------+------+ +------+------+ +------+------+
       |               |               |
       +---------------+---------------+
                       |
                       v
            +-------------------+
            | native compilation|
            +---------+---------+
                      |
                      v
            +-------------------+
            | Haskell FFI layer |
            +---------+---------+
                      |
                      v
            +-------------------+
            | deterministic run |
            +-------------------+
```

---

# PureScript frontend

Source at `./web/`; spago + `purs` + esbuild bundle to `./web/dist/app.js`. UI framework: **Halogen** (mature reactive PureScript framework, signals model fits live-events well).

## Generated contracts

`jitml internal generate-purs-contracts` emits `./web/src/Generated/Contracts.purs` from Haskell-owned browser-contract ADTs in `src/JitML/Web/Contracts.hs` via `purescript-bridge`. The Pulsar event protobuf-derived types are included so live event streams are typed end-to-end.

## Backend integration

- **REST + JSON** for one-shot operations (`/api/experiments`, `/api/checkpoints`, `/api/runs`, `/api/trials`).
- **WebSocket** for live event streams: the frontend connects to `/api/ws` (served by `jitml-demo`), which in turn subscribes to `training.event.<mode>` / `rl.event.<mode>` / `tune.event.<mode>` on Pulsar and proxies the relevant subset to the connected client. The frontend never connects to Pulsar directly — Envoy is the single localhost socket.

## Panels

- **Run list.** All experiments + runs from MinIO `jitml-checkpoints`, with status.
- **Live training panel.** Loss curve, validation curves, throughput sparkline, GPU-util gauge — animated from `training.event.<mode>` over WebSocket. Embeds the TensorBoard iframe at `/tensorboard/?run=<experiment-hash>` in a side tab.
- **RL panel.** Episode-reward distribution (live), env render preview (canvas-rendered from `EpisodeFrame` events), replay-buffer fill bar, exploration rate.
- **Hyperparameter panel.** Pareto frontier (live), trial-by-trial heatmap, search-strategy state, trial detail drill-down.
- **Cluster panel.** Embedded Grafana iframe at `/grafana` + the route table from `cluster status`.
- **Inference panel** (demo-only). Pick a checkpoint, submit a request, see the result.

## Tests

`purescript-spec` unit tests in `./web/test/`; Playwright E2E in `./web/playwright/` against the real Envoy route surface. The E2E suite is the `jitml-e2e` cabal stanza.

## Deployment

- **Linux substrates:** the bundle is built into the substrate image; `jitml-demo` workload serves it via Helm.
- **Apple Silicon:** the bundle is built host-native; `cluster up` deploys the `jitml-demo` pod (Linux-CPU image); the host daemon publishes events to cluster Pulsar; the routed demo loads in the browser at `127.0.0.1:<edge-port>/`.

---

# Test-suite stanzas

Per [`HASKELL_CLI_TOOL.md`](HASKELL_CLI_TOOL.md) §Test Organization, one cabal `test-suite` per tier:

| Stanza | Tier | Scope |
|---|---|---|
| `jitml-unit` | pure logic, parser, property, fast golden | CommandSpec golden, Dhall round-trip, autodiff property, optimizer-step property, route-registry render golden, Grafana-dashboard render golden, RNG mixer property, trajectory-determinism RL goldens |
| `jitml-integration` | subprocess + FFI | `jitml` binary across all substrates; checkpoint round-trip; resume semantics; Dhall→typed-record decode; per-substrate determinism |
| `jitml-sl-canonicals` | end-to-end SL convergence + curve | the five SL `(dataset, model)` pairs |
| `jitml-rl-canonicals` | end-to-end RL convergence + replay-from-checkpoint | the RL target matrix, forms (2) and (3) |
| `jitml-hyperparameter` | end-to-end tuning | Sobol reproducibility, GA reproducibility, resume-from-partial-sweep equality |
| `jitml-cross-backend` | determinism between hardware backends | cohort `(cpu, cuda)` and `(cpu, metal)` on the SL canon; tolerance from measured float-accumulation drift |
| `jitml-cluster-lifecycle` | daemon lifecycle | spawn `jitml service`, poll `/readyz`, exercise Pulsar protocol, SIGTERM, assert graceful drain |
| `jitml-haskell-style` | lint | `fourmolu --mode check`, `hlint`, `cabal format` round-trip |
| `jitml-purescript-style` | lint | PureScript `purs format` round-trip + `purescript-spec` smoke tests |
| `jitml-e2e` | Playwright through Envoy | demo HTTP + WebSocket: kick off a training run via `/api`, observe live metrics over `/api/ws`, navigate to `/tensorboard` and `/grafana` |

Single `tasty` trees across stanzas are forbidden (doctrine §Test Organization): separate stanzas give Cabal-native parallelism, let CI and developers target one tier, and isolate dependency creep.

---

# `jitml test all`

The doctrine-mandatory canonical test command. Three phases:

1. **Delegates to `cabal test`.** Runs every `test-suite` stanza above.
2. **Executes a fixed report-card workload.** A deterministic battery of `bench` and `verify` runs, pinned in `cabal.project`, so the headline numbers are reproducible across hosts.
3. **Prints a single tidy summary block** on stdout.

Literal example (sentinel placeholders in the golden file; live runs render real values):

```
jitML POC report card — seed=42, host=<uname -m>, ghc=9.14.1, substrate=<mode>
─────────────────────────────────────────────────────────────────
SL  MNIST         shallow MLP    <acc>%   (target ≥ <T>%)
SL  MNIST         deep CNN       <acc>%   (target ≥ <T>%)
SL  Fashion-MNIST shallow MLP    <acc>%   (target ≥ <T>%)
SL  Fashion-MNIST deep CNN       <acc>%   (target ≥ <T>%)
SL  CIFAR-10      ResNet-20      <acc>%   (target ≥ <T>%)
RL  CartPole-v1   PPO            <r>      (median k=5)   (target ≥ <T>)
RL  LunarLander-v2 SAC           <r>      (median k=5)   (target ≥ <T>)
Determinism  same-substrate      PASS     (3 substrates × 3 seeds)
Determinism  cross-substrate     PASS     (cpu↔cuda, tolerance <ε>)
Tuning       Sobol resume        PASS     (N-trial run resumed at trial M)
Cluster      bring-up time       <s>s
Cluster      route table         PASS     (12 routes published at /:<edge-port>)
Bench        MNIST/CUDA          <k> samples/s
Bench        LunarLander/CPU     <k> env-steps/s

cabal test                       PASS     (jitml-unit, jitml-integration,
                                           jitml-sl-canonicals, jitml-rl-canonicals,
                                           jitml-hyperparameter, jitml-cross-backend,
                                           jitml-cluster-lifecycle,
                                           jitml-haskell-style, jitml-purescript-style,
                                           jitml-e2e)
```

`jitml test all` is a Plan/Apply command per doctrine §Plan/Apply. `--dry-run` prints the rendered plan and exits 0. The summary block is rendered by a pure function over a typed `ReportCard` value, golden-testable with sentinel placeholders.

---

# Benchmarks

Three workloads:

- **(a) Training throughput.** Samples/sec on a fixed `(dataset, model, batch_size, substrate)`.
- **(b) Inference throughput / latency.** Batched and unbatched.
- **(c) RL environment throughput.** Env-steps/sec on each canonical env (the env runs on CPU; the policy network runs on the substrate under test — this surfaces FFI cost and GPU-batching strategy under realistic RL loads).

The clock is `Data.Time.Clock.getMonotonicTimeNSec`, started just before the first batch and stopped just after the last. The benchmark binary is the same `jitml` binary; instrumented and non-instrumented build targets per the MCTS pattern.

---

# Compiler, runtime, and backend tuning

Per-target codegen stack:

- **GHC:** 9.14.1, Cabal 3.16.1.0, `-O2 -fllvm -funbox-strict-fields -fspecialise-aggressively -fexpose-all-unfoldings`, RTS `-A64m -n4m -qg1 -qb -T`.
- **CUDA codegen:** pinned NVCC, `-O3 --use_fast_math=false` (bit-determinism), `--gpu-architecture=sm_70` baseline + per-host detection at JIT time.
- **Metal codegen:** pinned Xcode toolchain, `-O2`, no fast-math.
- **CPU oneDNN:** pinned version, AVX2 baseline + AVX-512 detection at JIT time.
- **LLVM:** pinned LLVM version across GHC's `-fllvm` and the JIT codegen, so codegen is reproducible.

**Documented asymmetry.** jitML has no equivalent of the PyTorch JIT autotuner — its kernel cache is built on the fly during pilot execution, not from a profile from a prior run. The pilot-tuning state is itself checkpointed for replay.

---

# Build and run

End-to-end walkthrough:

```bash
# Apple Silicon
./bootstrap/apple-silicon.sh
./.build/jitml cluster up                                  # phased Helm deploy
./.build/jitml cluster status                              # prints edge port
./.build/jitml service &                                   # host-native daemon
./.build/jitml train experiments/mnist-mlp.dhall --substrate apple-silicon --seed 42

# Linux CPU
./bootstrap/linux-cpu.sh                                   # builds the substrate image
docker compose run --rm jitml jitml cluster up
docker compose run --rm jitml jitml train \
  experiments/mnist-mlp.dhall --substrate linux-cpu --seed 42

# Linux CUDA
./bootstrap/linux-cuda.sh                                  # adds NVIDIA-driver checks
docker compose run --rm jitml jitml cluster up
docker compose run --rm jitml jitml train \
  experiments/cifar10-resnet.dhall --substrate linux-cuda --seed 42
```

After `cluster up`, the full surface lives at one URL — `127.0.0.1:<edge-port>/` — with the demo at `/`, TensorBoard at `/tensorboard`, Grafana at `/grafana`, Prometheus at `/prometheus`, Harbor at `/harbor`, MinIO at `/minio/console`, and Pulsar at `/pulsar/admin`.

---

# Repository layout (target)

```
jitML/
  app/                          -- Haskell CLI entry points
    Main.hs                     -- jitml (control plane + daemon)
    Demo.hs                     -- jitml-demo (HTTP server for the PureScript bundle)
  src/JitML/                    -- shared Haskell library
    CLI/                        -- CommandSpec, parser, docs, JSON, tree
    Cluster.hs                  -- kind + helm lifecycle, route registry consumer
    Routes.hs                   -- single source of truth for HTTPRoutes
    Service.hs                  -- the Pulsar-subscribed daemon
    Runtime/                    -- worker, Pulsar client, cache
    SL/                         -- supervised learning training loops
    RL/                         -- PPO, A2C, DQN, DDPG, TD3, SAC, HER
    Env/                        -- own envs (cartpole, mountain-car, ...)
    Tune/                       -- Sobol, random, GA, ES search
    Engines/
      AppleSilicon.hs           -- Metal codegen + host daemon shim
      LinuxCPU.hs               -- oneDNN codegen
      LinuxCUDA.hs              -- CUDA codegen
    Observability/
      Prometheus.hs             -- typed scrape-target list + /metrics endpoint
      Grafana.hs                -- typed dashboard renderer
      TensorBoard.hs            -- event-file writer
    Web/
      Contracts.hs              -- browser-contract ADTs (source for purescript-bridge)
  codegen-cuda/                 -- CUDA kernel templates + JIT driver
  codegen-metal/                -- Swift/Metal kernel templates + JIT driver
  codegen-onednn/               -- oneDNN graph wrappers + JIT driver
  proto/jitml/                  -- protobuf contracts (training, tune, rl, inference)
  web/                          -- PureScript frontend
    spago.yaml
    src/                        -- handwritten PureScript (Halogen components)
    src/Generated/Contracts.purs -- generated from src/JitML/Web/Contracts.hs
    test/                       -- purescript-spec
    playwright/                 -- E2E suite
    dist/                       -- bundle output
  chart/                        -- single umbrella Helm chart
    Chart.yaml                  -- subchart deps (harbor, pulsar, minio, postgres, gateway, prometheus, tensorboard, ...)
    values.yaml
    templates/                  -- GatewayClass, Gateway, HTTPRoutes, EnvoyProxy, ...
  kind/                         -- per-substrate Kind configs
  bootstrap/                    -- stage-0 idempotent reconcilers
  docker/                       -- substrate Dockerfiles, compose.yaml, playwright.Dockerfile
  experiments/                  -- canonical experiment Dhall files
  test/                         -- per-stanza test trees
    test/golden/sl/             -- SL convergence/curve fixtures
    test/golden/rl/             -- RL trajectory + curve fixtures
    test/golden/cli/            -- CommandSpec + help text fixtures
    test/golden/routes/         -- route-table render fixture
    test/golden/grafana/        -- dashboard JSON fixtures
    test/golden/tuning/         -- Sobol sequences, GA traces
  cabal.project                 -- toolchain pin, report-card knobs
  fourmolu.yaml                 -- formatter config
  README.md
  HASKELL_CLI_TOOL.md
  AGENTS.md / CLAUDE.md
  LICENSE
  .build/                       -- gitignored: outputs, kubeconfig
  .data/                        -- gitignored: kind state, runtime spool
```

---

# Doctrine scope

In-scope (binding) from [`HASKELL_CLI_TOOL.md`](HASKELL_CLI_TOOL.md):

- Command Topology
- CommandSpec + Generated Artifacts (paired check/write for the route table, the Grafana dashboards, the protobuf schemas, the PureScript contracts, the CLI help, the markdown docs)
- Progressive Introspection
- Subprocesses as Typed Values (kernel-compiler subprocesses, `kubectl`, `helm`, `kind`, `docker` all wrapped)
- Plan / Apply (`train`, `tune`, `cluster up`, `test all`, `service` startup-as-plan all Plan/Apply with `--dry-run` and `--plan-file`)
- Prerequisites as Typed Effects (bootstrap scripts' contract is also encoded as a typed DAG)
- Application Environment (`ReaderT Env IO`)
- Lint / Format / Code-Quality Stack
- Testing Doctrine + Test Organization
- Output Rules, Error Handling
- GADT-indexed state machines (training lifecycle, RL run lifecycle, tuning sweep lifecycle)
- Capability Classes + Service Errors (`HasMinIO`, `HasPulsar`, `HasHarbor`, `HasKubectl`)
- Retry Policy as First-Class Values
- At-Least-Once Event Processing (Pulsar consumer semantics)
- **Long-Running Daemons in the Same Binary** — `jitml service` is a real daemon with `BootConfig`/`LiveConfig` Dhall, SIGHUP hot reload, `/healthz`/`/readyz`/`/metrics`, structured JSON logging on stderr, recoverable-vs-fatal error kinds. (Contrast: MCTS opts out of this section; jitML opts in.)
- Daemon Lifecycle Tests
- Reconcilers (`cluster up` is a reconciler; idempotent)
- Pulumi-Orchestrated Infrastructure Tests (the `jitml-e2e` stanza brings up an ephemeral Kind cluster; the doctrine's invariants — ephemeral, tagged, always-teardown — apply)

Out of scope (informational only): Smart Constructors for Paired Resources (no paired infra resources at present; if a PV/PVC pattern emerges, this section comes back into scope).

---

# First milestone

The first concrete deliverable is `./.build/jitml train experiments/mnist-mlp.dhall --substrate apple-silicon --seed 42` succeeding on a Mac with a fresh `./bootstrap/apple-silicon.sh` + `cluster up`, producing bit-identical checkpoints across reruns, hitting the baselined MNIST shallow-MLP target (TBD; established by the first `k=5` replicate run on the reference host), with live training events flowing to the PureScript frontend at `127.0.0.1:<edge-port>` and TensorBoard scalars visible at `/tensorboard`, all while Harbor, MinIO, Pulsar, Postgres, Envoy Gateway, Prometheus, Grafana run in the Kind cluster and the Metal-using daemon runs on the host.

From there: add Linux CPU substrate, then Linux CUDA, then the Sobol sweep, then the first RL env (CartPole + PPO), then cross-substrate determinism, then the convergence-golden baselines that populate the TBD cells.

---

# Why Haskell?

`jitML` is built in Haskell because:

- purity improves reproducibility
- algebraic data types map naturally onto ML graphs
- type systems improve configuration safety
- deterministic semantics are easier to reason about
- Dhall integrates naturally into typed configuration systems

---

# Vision

The long-term goal of `jitML` is to provide:

> A fully declarative, reproducible, deterministic machine learning runtime capable of compiling itself efficiently onto heterogeneous hardware while preserving exact experimental replay semantics across both supervised and reinforcement learning workloads.

---

# License

See [`LICENSE`](LICENSE).
