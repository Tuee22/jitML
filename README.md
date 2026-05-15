# jitML

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: HASKELL_CLI_TOOL.md, DEVELOPMENT_PLAN/README.md, DEVELOPMENT_PLAN/00-overview.md, DEVELOPMENT_PLAN/system-components.md, documents/documentation_standards.md, documents/engineering/README.md, documents/engineering/cli_command_surface.md, documents/engineering/cluster_topology.md, documents/engineering/daemon_architecture.md, documents/engineering/jit_codegen_architecture.md, documents/engineering/numerical_core.md, documents/engineering/training_workloads.md, documents/engineering/checkpoint_format.md, documents/engineering/purescript_frontend.md
**Generated sections**: command-tree, command-registry

> **Purpose**: Operator-facing project intent and authoritative high-level architecture for jitML.

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

> **Doctrine and siblings:** The authoritative CLI doctrine lives at [`HASKELL_CLI_TOOL.md`](HASKELL_CLI_TOOL.md). jitML borrows its testing-and-determinism arc from a sibling deterministic Monte Carlo Tree Search runtime and its infrastructure layout from a sibling k8s-first inference control plane; the scopes of those projects are not combined with jitML's.

> **Development plan:** The single execution-ordered plan, sprint status, and cleanup ownership for jitML lives at [`DEVELOPMENT_PLAN/README.md`](DEVELOPMENT_PLAN/README.md). The plan adopts every in-scope doctrine section enumerated above in [Doctrine scope](#doctrine-scope) and binds each to an owning sprint; project-specific engineering docs live under [`documents/engineering/`](documents/engineering/README.md).

---

## Table of contents

**Substrates & bootstrap** — [Why this exists](#why-this-exists) · [Toolchain pinning](#toolchain-pinning) · [Substrates and runtime modes](#substrates-and-runtime-modes) · [Apple Silicon hybrid pattern](#apple-silicon-hybrid-pattern) · [Bootstrap scripts](#bootstrap-scripts) · [Built-artifact and JIT-cache discipline](#built-artifact-and-jit-cache-discipline) · [Prerequisites as typed effects](#prerequisites-as-typed-effects)

**Cluster & storage** — [Cluster topology and Kind](#cluster-topology-and-kind) · [Envoy Gateway API](#envoy-gateway-api-a-single-localhost-socket) · [Helm chart layout](#helm-chart-layout) · [Harbor](#harbor-as-the-registry) · [MinIO](#minio-object-store) · [TensorBoard event storage](#tensorboard-event-storage) · [Pulsar](#pulsar-as-the-control-plane--data-plane-bus) · [PostgreSQL](#postgresql) · [TensorBoard / Prometheus / Grafana](#tensorboard-prometheus-grafana-as-first-class)

**CLI & doctrine** — [Outer-container Linux builds](#outer-container-linux-builds) · [CLI command topology, typed](#cli-command-topology-typed) · [Doctrine scope](#doctrine-scope)

**Numerical & RL core** — [Numerical core](#numerical-core) · [Concrete Dhall worked example](#concrete-dhall-worked-example) · [Hyperparameter tuning](#hyperparameter-tuning-first-class) · [Canonical supervised learning problems](#canonical-supervised-learning-problems) · [Canonical reinforcement learning environments](#canonical-reinforcement-learning-environments) · [RL framework primitives](#rl-framework-primitives) · [RL algorithm catalog](#rl-algorithm-catalog) · [Golden tests for RL](#golden-tests-for-rl) · [AlphaZero-style self-play and persistent MCTS state](#alphazero-style-self-play-and-persistent-mcts-state) · [Checkpointing](#checkpointing) · [JIT compilation architecture](#jit-compilation-architecture) · [PureScript frontend](#purescript-frontend)

**Tests & benchmarks** — [Test-suite stanzas](#test-suite-stanzas) · [`jitml test all`](#jitml-test-all) · [Benchmarks](#benchmarks) · [Compiler, runtime, and backend tuning](#compiler-runtime-and-backend-tuning)

**Build & layout** — [Build and run](#build-and-run) · [Repository layout (target)](#repository-layout-target) · [Why Haskell?](#why-haskell) · [Vision](#vision) · [License](#license)

---

# Why this exists

The mainstream ML stack is Python + PyTorch / JAX + dynamic graphs + opaque CUDA kernels + best-effort seeding. It is fast at iterating on research ideas and slow at giving the same answer twice. Bit-exact reproduction is a debugging aid, not an architectural invariant: cuDNN convolutions are nondeterministic by default; data loaders shuffle in OS-thread order; mixed-precision reductions reassociate; checkpoint replay restores weights but not RNG state; hyperparameter sweeps record best-trial numbers but not the search-strategy state that produced them.

We want a runtime that is:

1. **Reproducible by construction.** Given identical inputs, seeds, and configuration, two runs produce identical outputs — including parameter initialization, minibatch ordering, optimizer state, RL trajectories, MCTS exploration paths, hyperparameter-trial selection, and checkpoint recovery. Reproducibility is an architectural requirement, not a flag.
2. **Declarative end-to-end.** A `.dhall` file is the full source of truth for a training run, a hyperparameter sweep, an RL experiment, or a cluster deployment. The CLI flags layered on top *override* the Dhall; they never replace it.
3. **Hardware-native without an embedded Python runtime.** jitML compiles kernels on demand for Apple Metal, NVIDIA CUDA, or oneDNN/AVX, with OpenCL held as a future extension, and executes them through Haskell FFI bindings. The runtime has no Python interpreter in the loop.

---

# Toolchain pinning

Per doctrine §Overview → Toolchain pinning, these versions are normative, not recommendations. The `.cabal` file declares `tested-with: ghc ==9.14.1`; `cabal.project` pins `with-compiler: ghc-9.14.1`; CI uses the same versions. Codegen toolchains (LLVM, NVCC, Xcode/Metal, oneDNN) are pinned in `cabal.project` so kernel output is reproducible across hosts.

| Tool | Pinned version | Where it's pinned |
|---|---|---|
| GHC | `9.14.1` | `.cabal` (`tested-with`) and `cabal.project` (`with-compiler`) |
| Cabal | `3.16.1.0` | `cabal.project` |
| LLVM | pinned across GHC's `-fllvm` and JIT codegen | `cabal.project` |
| NVCC | pinned | `cabal.project` (`--use_fast_math=false`, baseline `sm_70`) |
| Xcode/Metal | pinned | bootstrap script + `cabal.project` |
| oneDNN | pinned | `cabal.project` (AVX2 baseline, AVX-512 detected at JIT time) |
| `kindest/node` | pinned | `./kind/cluster-<substrate>.yaml` (canonical); mirrored as a comment in `cabal.project` for the toolchain-truth record |
| Node.js, Poetry | pinned | Haskell prerequisite DAG |
| Formatter GHC | separate isolated install under `.build/jitml-style-tools/` | lint stack (does not affect the project compiler) |

The full per-target codegen detail (build flags, RTS options, fast-math discipline) lives under [Compiler, runtime, and backend tuning](#compiler-runtime-and-backend-tuning).

---

# Substrates and runtime modes

jitML produces **one Haskell front end** with JIT codegen for several hardware targets, packaged as **three supported substrates**[^linux-opencl]:

| Substrate | Codegen | Container shape | Service residency |
|---|---|---|---|
| `apple-silicon` | Swift + Metal | partial — cluster services in Kind; a second `jitml service` runs host-native because Metal cannot be containerized | **one binary, two instances** of `jitml service`, distinguished entirely by their Dhall configs: clustered (Dhall: `residency = Cluster`, `inferenceMode = ForwardToHost`) + host-native (Dhall: `residency = Host`, `inferenceMode = SelfInference`). See [Bit-determinism contract](#bit-determinism-contract) for what same-substrate equality means under this split. |
| `linux-cpu` | oneDNN + AVX2/AVX-512 | fully containerized: `jitml:local` | one daemon: clustered `jitml service` (Dhall: `residency = Cluster`, `inferenceMode = SelfInference`); pod anti-affinity = one per node |
| `linux-cuda` | CUDA C + cuBLAS / cuDNN | fully containerized: `jitml:local` (CUDA activates at runtime when scheduled to `runtimeClassName: nvidia`) | one daemon: clustered `jitml service` (Dhall: `residency = Cluster`, `inferenceMode = SelfInference`); pod anti-affinity = one per node |

There is **one CLI surface for the daemon — `jitml service` — parameterised entirely by its Dhall config** ([CLI command topology, typed](#cli-command-topology-typed)). The Dhall declares substrate, residency (cluster | host), inference mode (`SelfInference` | `ForwardToHost`), and the host-side MinIO / Pulsar connection info when `residency = Host`. There is no separate `host-service` CLI verb.

On every substrate the in-cluster `jitml-service` Deployment is a **stateless Deployment**, not a StatefulSet: durable state lives in MinIO and Pulsar exclusively (no relational DB in jitML's path), the orchestrator owns no PVC of its own, and pod anti-affinity at `topologyKey: kubernetes.io/hostname` ensures multi-replica deployments place at most one pod per node. Each node keeps its own JIT cache (per-node hostPath; see [Built-artifact and JIT-cache discipline](#built-artifact-and-jit-cache-discipline)). On every substrate the clustered daemon performs Pulsar fan-in/fan-out and inference batching. Linux substrates additionally execute inference kernels in-pod (`SelfInference`); Apple Silicon forwards kernel execution to the host daemon (`ForwardToHost`) over the internal `inference.command.apple-silicon` Pulsar topic, since Metal cannot be containerized. Either mode is in principle expressible on either substrate; the substrate × mode table above reflects current practice.

[^linux-opencl]: An optional fourth substrate `linux-opencl` (Intel GPU) is admitted as a future extension; the codegen path is shaped to accept it without disturbing the three primary substrates above. Not in the current support matrix.

Each substrate carries its own determinism contract:

- **`apple-silicon`** — Metal compute kernels execute on the host GPU; float-accumulation order is fixed by the kernel's reduction tree (no fast-math); RNG state lives in the host daemon; kernel-launch ordering is single-stream by default. *Tradeoff: single-stream launch forfeits the multi-stream concurrency that hides launch latency at small batch sizes — the throughput cost is real and is the price of the bit-determinism contract.*
- **`linux-cpu`** — oneDNN dispatches to a per-host vector ISA detected at JIT time; reductions are blocked with a fixed block size so the accumulation tree is host-independent; RNG state lives in the clustered service pod.
- **`linux-cuda`** — CUDA kernels disable `--use_fast_math`; per-block reductions use a deterministic warp-shuffle pattern; cuBLAS and cuDNN are pinned to deterministic algorithm selections (`cudnnSetConvolutionMathType` + explicit algorithm-id pinning); RNG is the host's splitmix, never the GPU's curand. *Tradeoff: cuDNN's deterministic convolution algorithms are typically 20-50% slower than its non-deterministic defaults on training workloads; this is the price of the bit-determinism contract.*

Cross-substrate equality is not guaranteed bit-for-bit — float reductions reassociate across vendor BLAS/DNN libraries and transcendentals (`exp`, `log`, `sqrt`, `tanh`) are implemented differently by cuDNN, Metal, and oneDNN, so per-tensor drift compounds through the forward + backward pass. *Same-substrate equality is guaranteed* (see [Bit-determinism contract](#bit-determinism-contract)); cross-substrate drift is bounded by a per-tensor tolerance band measured by the [Cross-substrate tolerance methodology](#cross-substrate-tolerance-methodology) and enforced by the [`jitml-cross-backend`](#test-suite-stanzas) stanza.

---

# Apple Silicon hybrid pattern

Metal cannot be containerized. The supported Apple lane is therefore hybrid: a stateless orchestrator pod runs in Kind exactly like on Linux, **and** a second `jitml service` runs host-native because the GPU lives there. Both daemons are the same binary; their Dhall configs are what differ.

Shape:

- The clustered `jitml-service` Deployment runs on every substrate (stateless; pod anti-affinity = one per node). On Apple Silicon its Dhall sets `inferenceMode = ForwardToHost`, so it **still** performs Pulsar fan-in/fan-out, inference batching, demo proxying, and trial-state persistence to MinIO bucket `jitml-trials`, but it forwards the actual kernel execution to the host daemon over the internal topic `inference.command.apple-silicon`.
- `./.build/jitml service --config ./.build/conf/host/apple-silicon.dhall` runs **host-native** on Apple (Dhall: `residency = Host`, `inferenceMode = SelfInference`; no HTTP listener; Pulsar subscriber only). `./bootstrap/apple-silicon.sh` only performs stage-0 host gates and builds `./.build/jitml`; it then delegates to `./.build/jitml bootstrap --apple-silicon`, which writes the host and cluster Dhall files, brings up Kind, runs the phased Helm deploy from [Helm chart layout](#helm-chart-layout), and starts the host daemon once the cluster publication is known.
- The cluster daemon publishes inference RPC envelopes on the internal topic `inference.command.apple-silicon`. The host daemon **subscribes** to that topic and ACKs on `inference.event.apple-silicon` with small envelopes (call-id, kind tag, MinIO refs to outputs). Pulsar carries only small envelopes; large tensors travel via MinIO.
- The host daemon **reads and writes large artifacts directly to MinIO** through the routed `/minio/s3` surface — same protocol the cluster daemon uses. New snapshot weights, optimizer state, and inference outputs go to MinIO straight from the host; the ACK envelope just references the MinIO keys. This keeps Pulsar lean and lets MinIO's optimistic concurrency on HEAD updates serialize concurrent commits (see [Checkpoint snapshot model](#checkpoint-object-layout)).
- The host daemon JIT-compiles Metal kernels and executes them with direct GPU access. JIT compilation happens inside a `jitml-build` tart VM whose lifecycle is managed by the host binary — see [Bootstrap scripts](#bootstrap-scripts) and [Built-artifact and JIT-cache discipline](#built-artifact-and-jit-cache-discipline).
- Pulsar endpoint discovery: `jitml bootstrap --apple-silicon` writes the routed coordinates to `./.build/runtime/cluster-publication.json`, then updates `./.build/conf/host/apple-silicon.dhall` with `pulsar_ws_url`, `pulsar_admin_url`, `minio_s3_url`, and `edge_port`. No service-discovery RPC; the cluster publishes its own coordinates to a known file and the host daemon reads its Dhall config.
- The host daemon's only cluster contracts are Pulsar (RPC envelopes) and MinIO (large artifacts). Direct k8s API access from the host is forbidden and lint-enforced.

On Linux substrates the clustered daemon's Dhall sets `inferenceMode = SelfInference`, so it executes inference kernels in-pod (the substrate image carries the full JIT toolchain). There is no separate `inference.command.linux-*` topic; the Pulsar topology degenerates to the demo-facing `inference.request.<mode>` / `inference.result.<mode>` pair. Apple Silicon is the only substrate where a second daemon resides on the host and the internal-RPC topic pair is active — but the daemon code path is the same; the Dhall flips the mode.

---

# Bootstrap scripts

Stage-0 bootstrap entrypoints, one per substrate:

```
./bootstrap/apple-silicon.sh
./bootstrap/linux-cpu.sh
./bootstrap/linux-cuda.sh
```

Each script is **idempotent and restartable**, but deliberately small: it probes only the host state needed to get to the real Haskell bootstrap, fails fast with installation instructions when a non-recoverable host prerequisite is missing, then delegates. Package reconciliation after that point belongs to `jitml bootstrap --<substrate>` and the typed prerequisite DAG in [Prerequisites as typed effects](#prerequisites-as-typed-effects).

> **Bootstrap verbs are not CLI verbs.** Historical script verbs such as `doctor`, `status`, `down`, and `purge` remain script conveniences, but the cluster bootstrap contract is the Haskell command `jitml bootstrap --apple-silicon | --linux-cpu | --linux-cuda`. Script `up` is a wrapper around that command.

- `apple-silicon.sh` checks that the host is macOS on Apple Silicon, Xcode Command Line Tools are available, and Homebrew is installed. If any gate fails, it exits with a short, actionable install message. If the gates pass, it builds `./.build/jitml` host-native, then calls `./.build/jitml bootstrap --apple-silicon`. The Haskell bootstrap writes Dhall under `./.build/conf/`, creates the Kind cluster, brings Harbor up first, then rolls out every subsequent container through Harbor: MinIO, Pulsar, Prometheus/Grafana, Envoy Gateway, the Percona operator plus Patroni-managed Postgres for services that need Postgres, the `jitml-service` cluster daemon via Helm, and the demo app built from its own Dockerfile. Once the localhost edge port is selected, bootstrap updates the host Dhall so the host daemon can reach Pulsar and MinIO and then starts the host daemon as the long-running Apple inference resident. The host does **not** install or start tart during bootstrap; tart is installed and started lazily on the first JIT that misses the cache.
- `linux-cpu.sh` checks that Docker is installed and usable by the current user without `sudo`. If the gate passes, it calls `docker compose run --rm jitml jitml bootstrap --linux-cpu`; Compose builds the outer `jitml` image automatically, the in-container bootstrap deploys the same cluster stack, and the outer container exits once the in-cluster daemon is in charge. Linux has no host daemon and no host-level Dhall: only the ConfigMap Dhall mounted into the cluster daemon is needed.
- `linux-cuda.sh` performs the Linux CPU Docker gate plus CUDA gates: the NVIDIA container runtime must be available, and `nvidia-smi` must report at least one device meeting the required compute capability. Missing gates fail fast with installation instructions. If the gates pass, it calls `docker compose run --rm jitml jitml bootstrap --linux-cuda`; after that the rollout is the same as Linux CPU, with the CUDA RuntimeClass and GPU worker labeling applied by bootstrap.

Cleanup semantics matter:

- `down` tears down the cluster; preserves `./.data/`, preserves `./.build/`, leaves any already-started tart VM up (Apple).
- `purge` is destructive but **cache-preserving**: cluster down, `rm -rf ./.data/`, tart VM destroyed if it exists (Swift incremental build cache inside the VM is wiped with it). `./.build/` survives — including `./.build/jit/apple-silicon/`, `./.build/runtime/`, `./.build/conf/`, and the Kind metadata needed for subsequent `docker compose run --rm jitml jitml <command>` calls. A subsequent bootstrap or inference command can resolve from cache without re-JITting any model already compiled. The cache is the payoff: tart need only be installed or spun up when a *new* model shape or *new* kind (training vs inference) appears.
- `purge --full` is `purge` plus `rm -rf ./.build/` (and on Linux, `docker compose down --rmi local --volumes` to drop the substrate image). Use only for fresh-start debugging.

Forbidden: anything that touches `~/.kube/config`, `~/.docker/config.json`, or global state outside the repo except typed prerequisite remediation that explicitly installs Homebrew packages. Shell bootstrap scripts never write the user's Homebrew prefix; Haskell `jitml` may validate and install Homebrew packages lazily, on demand, through the typed prerequisite DAG. Build outputs, generated Dhall, runtime coordinates, kubeconfig, Kind metadata, and JIT artifacts live under `./.build/`; `./.data/` is reserved strictly for manual PV bind mounts. Both roots are in `.gitignore` **and** `.dockerignore` so the substrate image never accidentally bakes in host artifacts.

---

# Built-artifact and JIT-cache discipline

`./.build/` is the **only** host folder that holds compiled artifacts and bootstrap runtime metadata: the `jitml` binary, JIT-compiled kernels, generated JIT source inputs, generated Dhall, kubeconfig, Kind metadata, and cluster publication files. Layout:

```
.build/
├── jitml                                    -- the binary (Apple: host-built via ghcup; Linux: container-built, bind-mounted out)
├── jitml.kubeconfig                         -- repo-local kubeconfig only
├── conf/
│   ├── host/apple-silicon.dhall             -- Apple-only host daemon config, patched with routed cluster coordinates
│   └── cluster/<substrate>.dhall            -- rendered into the jitml-service ConfigMap
├── runtime/cluster-publication.json          -- edge port, Pulsar, MinIO, and related routed coordinates
├── kind/<substrate>/                         -- Kind metadata/config needed by later bootstrap and docker-compose invocations
├── host/apple-silicon/                      -- Apple-only: stable-named dlopen() targets (symlinks into jit/) the Haskell FFI loads at runtime
├── jit-src/<substrate>/<hash>/               -- generated compiler inputs emitted by Haskell renderers
└── jit/
    ├── manifest.json                        -- cache index keyed on (model-id, kind, substrate, toolchain)
    └── <substrate>/<hash>.<ext>             -- one file per cached kernel (content-addressed; the canonical location of every kernel artifact)
```

**Role split.** `jit/<substrate>/<hash>.<ext>` is the canonical content-addressed cache — every cached kernel lives there, on every substrate. `host/apple-silicon/` is *only* on Apple, and holds **stable-named symlinks** into `jit/apple-silicon/`: the Haskell FFI `dlopen()`s `host/apple-silicon/<model-id>.dylib`, which resolves through the symlink to `jit/apple-silicon/<hash>.dylib`. The indirection lets the FFI path stay stable across re-JITs (a new hash repoints the symlink; the FFI key never changes). Linux substrates don't need this — the pod loads directly out of `jit/<substrate>/` because there is no host↔VM artifact-copy step.

**Cache key — shape + kind + generated source, weight-independent.** Each entry is hashed over `(canonical-cbor(KernelSpec), kind, substrate, toolchain-fingerprint, rendered-source-payload, tuning-choice)` where `KernelSpec` is model shape (layer topology, dtype layouts, activation choices) and `kind` is `training | inference`. Training and inference kernels are **separate artifacts** because they have different compute graphs — training carries the backward pass and optimizer-step kernel; inference is forward-only with frozen-weight constant folding enabled. Sharing one artifact across both would force one of them to be sub-optimal. The rendered-source payload is generated by the Haskell runtime source renderers under `src/JitML/Codegen/`; changing a renderer invalidates the compiled artifact.

Consequence: a model that is both trained and used for inference has **two JIT artifacts in its lifetime**, regardless of how many checkpoints exist along its training history. Two snapshots of the same model share their weight layers (per the multi-object snapshot model in [Checkpoint object layout](#checkpoint-object-layout)) but never produce additional JIT compiles.

**Lazy tart spin-up on Apple Silicon.** Bootstrap and host daemon startup never touch tart. On a JIT cache miss the daemon first uses the typed prerequisite DAG to install or validate the `tart` Homebrew package if needed, then calls `JitML.Tart.ensureVmUp jitml-build`, which is idempotent — if the VM is up, no-op; if down, `tart run jitml-build --no-graphics &` and poll until reachable. The daemon then dispatches the Swift build inside the VM via `tart ssh`, writes the artifact into `./.build/jit/apple-silicon/<hash>.dylib` atomically (`tmp + rename`), repoints the stable-named symlink under `./.build/host/apple-silicon/`, and loads via FFI. The VM stays up for the daemon's lifetime once spun up; an idle timeout (default 30 min, configurable in `LiveConfig`) may bring it down again. Subsequent cache hits skip the spin-up entirely.

Manual VM access is available through the pass-through CLI verb (handy for debugging Swift build failures without dropping into Tart by hand):

```bash
./.build/jitml internal vm exec -- swift build --package-path .build/jit-src/apple-silicon/<hash> -c release
```

**Cache survives VM teardown.** `./bootstrap/apple-silicon.sh purge` destroys the tart VM (along with the Swift incremental build cache *inside* the VM) but **preserves `./.build/`**. After `purge`, every previously compiled kernel is still on disk under `./.build/jit/apple-silicon/`, so the next `up` plus any inference command can resolve from cache without spinning tart up at all. Tart only fires on a fresh `(model-shape, kind, substrate, toolchain)` tuple — typically only when a new model is added or a toolchain is bumped.

**Linux substrates share the same cache via Kind extraMounts.** The Kind cluster config bind-mounts host `./.build/` into the worker node, and the `jitml-service` Deployment mounts that path into the pod at `/opt/build`. Cache hits/misses behave identically to Apple Silicon — the only difference is that on a Linux miss the compile runs in-process inside the pod (which has the full toolchain baked into the substrate image), not in a separate VM. Linux JIT operations happen entirely in the cluster; the outer `docker compose run --rm jitml jitml <command>` container only re-enters the cluster using metadata persisted under `./.build/`. This is the **one** exception to the "no freestanding host paths in pod specs" discipline; the chart lint permits exactly this hostPath and rejects any other.

---

# Prerequisites as typed effects

Per doctrine §Prerequisites as Typed Effects, prerequisite checks are first-class typed values: a DAG of named `Prerequisite` nodes that gate every reconcile run. Each node has a typed predicate, a typed remediation action (or `Nothing` if the prerequisite is non-recoverable), and an explicit dependency list. Stage-0 shell scripts use only the minimal host gates required to reach the Haskell binary or outer Docker container; the Haskell prerequisite DAG is the source of truth for every lazy package remediation after that.

Homebrew package installation is allowed only through this typed path. A Homebrew prerequisite carries a package identity, install/upgrade policy, validation predicate, and human-readable remediation. The pure plan phase computes which packages are missing; the apply phase executes through the typed `Subprocess` layer; the postcondition re-validates the package before the next dependent node runs. This keeps lazy package installation deterministic and testable without spreading ad hoc `brew install` calls through scripts.

A reconciler that finds a missing prerequisite fails with exit code `2` (system error per [Exit codes and error rendering](#exit-codes-and-error-rendering)) and a structured diagnostic naming the missing node plus its remediation, if any. The bootstrap scripts at [`./bootstrap/`](#bootstrap-scripts) are the user-facing tip of this system; the Haskell prerequisite DAG is the in-process source of truth.

---

# Cluster topology and Kind

Per-substrate Kind configs at `./kind/cluster-<substrate>.yaml`. Single control-plane + one worker on Apple Silicon (collocated); identical layout for Linux CPU; Linux CUDA labels the worker `jitml.runtime/gpu=true` so the NVIDIA runtime class binds there.

The edge port (Envoy listener) is selected starting at 9090 and incremented until available; recorded as the `edge_port` field of `./.build/runtime/cluster-publication.json` (the single file bootstrap writes; see [Apple Silicon hybrid pattern](#apple-silicon-hybrid-pattern) for its other fields) and reported by `jitml cluster status`. NodePort 30090 is the in-cluster service for the edge gateway.

Kubeconfig lives at `./.build/jitml.kubeconfig`. The CLI never touches `~/.kube/config`. The `kindest/node` version is referenced in the Kind config under `./kind/cluster-<substrate>.yaml`; the same pin appears as a comment in `cabal.project` purely as a single-source-of-toolchain-truth record (Cabal itself does nothing with it), and the lint stack rejects drift between the two.

Storage is a `jitml-manual` storage class (no provisioner) backed by host-path PVs under `./.data/<namespace>/<StatefulSet>/pv_<integer>`. `.data` is only for these manual PV bind mounts; runtime metadata, Kind metadata, generated config, and kubeconfig live under `./.build/`.

The host `./.build/` directory is bind-mounted into the Kind worker node via the `extraMounts` block in `./kind/cluster-<substrate>.yaml`, which is what lets the in-cluster `jitml-service` pod see the same JIT artifacts the host built (see [Built-artifact and JIT-cache discipline](#built-artifact-and-jit-cache-discipline)).

---

# Envoy Gateway API: a single localhost socket

> "There is to be a single socket accessible to localhost with Envoy as the reverse proxy to all the endpoints."

**Ports at a glance.**

- `127.0.0.1:<edge-port>` — the single user-facing socket. Selected by bootstrap starting at `9090` and autoincremented if taken.
- `NodePort 30090` — the in-cluster Envoy service that the edge port maps to.
- `./.build/runtime/cluster-publication.json` — the single file bootstrap writes; `edge_port` lives here alongside `pulsar_ws_url`, `pulsar_admin_url`, and `minio_s3_url`. `jitml cluster status` reads this file.

One Envoy-Gateway-API-owned localhost listener (`Gateway/jitml-edge`, port chosen by bootstrap starting at `9090`) backed by the repo-owned `EnvoyProxy/jitml-edge` service shape:

- `GatewayClass/jitml-gateway` + `Gateway/jitml-edge` listening at `127.0.0.1:<edge-port>`.
- `EnvoyProxy/jitml-edge` is a NodePort service with `externalTrafficPolicy: Cluster`, port 30090 in-cluster.
- Routes are not hand-written YAML; they are Haskell-rendered `HTTPRoute` resources from a single **route registry** in `src/JitML/Routes.hs`. The registry is the source of truth, consumed by both the chart-template renderer and the `docs check`/`docs generate` pair that gates README drift (per doctrine §Generated Artifacts).

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

TLS is off for the local demo. The production-deployment posture is intentionally not specified by this README; the route registry just declares the local-demo surfaces.

---

# Helm chart layout

Single umbrella chart at `./chart/`. `Chart.yaml` declares subchart dependencies:

- `harbor` — image registry.
- `pg-operator` + `pg-db` — Percona Kubernetes Operator, providing Patroni-managed HA Postgres for every packaged service that requires Postgres (jitML itself never writes to it — see [PostgreSQL](#postgresql)).
- `pulsar` — Apache Pulsar with ZooKeeper + BookKeeper + Broker + Proxy + WebSocket.
- `minio` — distributed mode, four replicas.
- `gateway-helm` — Envoy Gateway controller.
- `kube-prometheus-stack` — Prometheus operator + Grafana.
- `tensorboard` — a jitML-owned chart for TensorBoard with MinIO-backed event storage.

Templates in `chart/templates/`: GatewayClass, Gateway, HTTPRoutes (rendered from the route registry), EnvoyProxy, manual PVs (one per replica, see below), the `jitml-service` Deployment, the `jitml-demo` Deployment, NVIDIA RuntimeClass for the CUDA substrate, Grafana datasources and dashboards (provisioned ConfigMaps), Prometheus scrape configs.

## Storage discipline: `kubernetes.io/no-provisioner` only

Every StorageClass uses the `kubernetes.io/no-provisioner` provisioner — no dynamic provisioning anywhere in the chart. Every PV is **manually defined** in `chart/templates/pv-<statefulset>.yaml` against the `jitml-manual` StorageClass and backed by a `hostPath` under `./.data/<namespace>/<StatefulSet-name>/pv_<replica-int>/`. Every PVC is created **only** by a StatefulSet's `volumeClaimTemplates`; freestanding PVCs are a chart-lint failure. Each PV's `claimRef.namespace` and `claimRef.name` explicitly bind it to one PVC so a teardown/spinup yields the exact same binding — the PV ↔ PVC pairing is the persistence contract; dynamic provisioning would erode reproducibility.

Naming convention is uniform: **`<k8s-namespace>/<StatefulSet-name>/pv_<replica-int>`** on disk, and **`<namespace>-<statefulset>-pv-<int>`** as the PV resource name (DNS-1123 compatible). Example layout for the `platform` namespace on the Apple Silicon substrate:

```
.data/
└── platform/
    ├── minio/{pv_0, pv_1, pv_2, pv_3}                  -- 4 distributed replicas
    ├── pulsar-bookkeeper/{pv_0, pv_1, pv_2}            -- 3 bookies
    └── pulsar-zookeeper/{pv_0, pv_1, pv_2}             -- 3 ZK nodes
```

Corresponding PV resources are named `platform-minio-pv-0`, `platform-pulsar-bookkeeper-pv-1`, etc.; each is bound to the per-replica StatefulSet PVC (e.g. `data-minio-0`, `journal-pulsar-bookkeeper-1`). `jitml lint files` rejects any path under `.data/` that does not match the `<namespace>/<StatefulSet>/pv_<int>` regex, and `jitml lint chart` rejects any StorageClass with a provisioner other than `kubernetes.io/no-provisioner`, any freestanding PVC, and any PV without an explicit `claimRef`.

## `jitml-service` Deployment, not StatefulSet

The orchestrator is a stateless **Deployment** with `replicas: 1` by default and pod **anti-affinity** at `topologyKey: kubernetes.io/hostname`, which lets the cluster scale to N replicas (one per node) when throughput requires it without ever placing two on the same node. The daemon owns no PVC of its own — durable state lives entirely in MinIO and Pulsar — so a StatefulSet (which exists for stable identity + ordered scale-up + per-pod PVCs) would be the wrong shape. Each node maintains its own JIT cache under that node's `./.build/jit/<substrate>/` hostPath, which is fine because JIT artifacts are deterministic functions of `(model-shape, kind, substrate, toolchain)` — the worst case is that the same model gets JITted once per node on first use.

Namespace: `platform` (fixed). `jitml bootstrap --<substrate>` creates it idempotently.

**Phased deploy** (verbatim from infernix's lessons):

1. **Harbor phase**: Harbor plus the Percona operator / Patroni-managed Postgres required by packaged services comes up first, using only the public pulls needed to make Harbor available.
2. **Mirror/build phase**: third-party images are mirrored into Harbor; the `jitml` image and the demo image are built and pushed to Harbor.
3. **Final phase**: MinIO, Pulsar, Envoy Gateway, kube-prometheus-stack, TensorBoard, the jitML service workload (all substrates: Linux self-inference plus Apple forward-to-host), and the jitML-demo workload — all pulling exclusively from local Harbor.

This avoids the chicken-and-egg of "Harbor isn't up yet, but everything wants to pull from it" without resorting to image-pull-secret juggling.

---

# Harbor as the registry

All container images go through Harbor. No Docker Hub pulls after the Harbor phase. The build pipeline pushes to `harbor.platform.svc.cluster.local/jitml/<image>:<tag>` and the in-cluster `imagePullPolicy: IfNotPresent` resolves from there.

Harbor's own image-chart storage backend is **MinIO** (S3 API), so Harbor's blobs and MinIO's buckets share a durability story.

Routed at `/harbor` (portal) and `/harbor/api` (API).

---

# MinIO object store

Buckets, provisioned by the Helm `provisioning.buckets` block:

- `harbor-registry` — Harbor's S3 backend (128 MiB chunk size).
- `jitml-checkpoints` — training checkpoints. One prefix per experiment hash; content-addressed blobs + manifests + ETag-guarded pointers inside the prefix (see [Checkpoint object layout](#checkpoint-object-layout)).
- `jitml-datasets` — pinned source datasets (MNIST, Fashion-MNIST, CIFAR-10 binaries). Lazily populated on first use, SHA-256 verified against the experiment Dhall.
- `jitml-transcripts` — RL trajectory transcripts (the analog of MCTS's `.mcts-cache/transcripts/`).
- `jitml-trials` — hyperparameter trial transcripts, content-addressed by `sha256(resolved-dhall || trial-seed)`.
- `jitml-tensorboard` — TensorBoard event files so the TB pod is stateless and can reschedule freely (see [TensorBoard event storage](#tensorboard-event-storage)).
- `jitml-artifacts` — large inference outputs (when the demo is in inference mode).

Endpoints: `jitml-minio.platform.svc.cluster.local:9000` (in-cluster); `127.0.0.1:<edge-port>/minio/s3` (routed). Credentials pinned in values for the local demo; the production-deployment posture is intentionally not specified by this README.

The MinIO server version is pinned to a release with S3 conditional-write support (`If-None-Match`, `If-Match`) — `RELEASE.2024-08-26T15-33-07Z` or later. The concurrency story below depends on it.

## Checkpoint object layout

The `jitml-checkpoints` bucket uses a fixed prefix schema, owned by a Haskell module (`src/JitML/Storage/Layout.hs`) so paths are typed values rather than stringly-typed call sites:

```
jitml-checkpoints/
  <experiment-hash>/                      -- sha256(resolved-dhall || graph-shape-hash)
    blobs/<sha256>                        -- write-once, content-addressed, opaque bytes
    manifests/<sha256>                    -- write-once, content-addressed, CBOR manifest objects
    pointers/
      latest                              -- mutable, ETag-CAS; body = 32-byte manifest sha
      best/<metric>                       -- mutable, ETag-CAS; body = 32-byte manifest sha
      trial/<trial-hash>/latest           -- per-HPO-trial latest pointer
      trial/<trial-hash>/best/<metric>    -- per-HPO-trial best pointer
```

Three object classes, two write protocols:

- **`blobs/<sha256>`** — write-once content-addressed payloads. Each blob's key *is* `sha256(its bytes)`. PUTs use `If-None-Match: *` and treat `412 Precondition Failed` as success (the bytes already exist by definition). One checkpoint produces **many blobs**: one per model layer's weights (`encoder.weight`, `encoder.bias`, `head.weight`, …), plus one for optimizer state, one for RNG state, and (RL only) one each for replay buffer and exploration cache. Per-layer granularity is what makes dedup across checkpoints automatic — two consecutive checkpoints that differ only in their final layer share every other layer's blob by content hash.
- **`manifests/<sha256>`** — write-once content-addressed CBOR objects naming the blob SHAs that constitute one logical checkpoint plus the metadata needed to interpret them: the parent manifest's SHA (for linear history), the layer-name → blob-SHA map, the step count, the resolved Dhall hash, the substrate that produced the bytes. Same `If-None-Match: *` write protocol. The manifest's SHA is the canonical *checkpoint id* used by Pulsar `CheckpointDone` events, RPC envelopes, and `--resume <checkpoint-id>`.
- **`pointers/*`** — the only mutable objects. Each pointer's body is a 32-byte manifest SHA. Updates use S3 conditional `PUT` with `If-Match: <etag>` — textbook compare-and-swap. The `pointers/latest` update is the **single atomic commit point** for a checkpoint: layer-level blob writes can happen in any order and may even leave orphans on failure, but the manifest is only adopted as HEAD when its pointer update succeeds. Optimistic concurrency therefore applies to the **entire snapshot**, not per layer — which is what guarantees a linear sequence of checkpoints with no orphan branches or split heads.

## Concurrency model

All race conditions between trainers, hyperparameter-trial workers, and inference clients are eliminated at the protocol layer; nothing in the doctrine relies on advisory locks, leases, or a separate lock service.

- **Write/write on `blobs/*` and `manifests/*`** — impossible by construction. Keys are derived from `sha256(payload)`. Two writers with the same logical payload write the same key with the same bytes; the second `If-None-Match: *` PUT returns `412`, which the client treats as success because the SHA already exists. Two writers with different logical payloads write different keys; no collision is possible.
- **Write/read on `blobs/*` and `manifests/*`** — impossible. S3 object PUT is atomic at the object level; a partial blob is never visible. An inference client reading `blobs/<sha>` either sees the full object or gets `404`.
- **Write/write on `pointers/*`** — handled by `If-Match: <etag>` CAS. The loser receives `412`, which `MinIOPreconditionFailed` translates into the doctrine's `SEConflict` (already classified retryable per doctrine §Capability Classes and Service Errors). The retry re-reads the pointer, applies the caller's resolution policy, and retries through the existing `retryServiceAction` harness. The policy is a typed predicate `CurrentManifest -> ProposedManifest -> Bool`; concrete predicates are `advanceLatest` (`cpStep new > cpStep cur`), `advanceBestMaximised` (`lookupMetric m new > lookupMetric m cur`), and `advanceBestMinimised` (`lookupMetric m new < lookupMetric m cur`). Trainers pick `Maximised` vs `Minimised` from the experiment Dhall's `metrics[i].direction` field (see [Concrete Dhall worked example](#concrete-dhall-worked-example)); the direction is part of the resolved-Dhall hash, so flipping a metric's direction defines a *different experiment*.
- **Write/read on `pointers/*`** — a reader observes either the old ETag's bytes or the new ETag's bytes. Both name valid immutable manifests, both of which name valid immutable blobs. No torn state is possible because the only mutation is a single object PUT (atomic) of a 32-byte body.

Sketch of the checkpoint-write orchestration:

```haskell
writeCheckpoint :: HasCheckpointStore m => CheckpointPayload -> m CheckpointId
writeCheckpoint payload = do
  parts    <- traverse (putBlobIfAbsent . encodePart) (payloadParts payload)
                                                  -- If-None-Match: *  (412 = success)
  manifest <- putBlobIfAbsent (encodeManifestCanonical (mkManifest parts payload))
  retryServiceAction defaultRetryPolicy $
    casPointer (pointerKeyLatest (experimentHash payload))
               advanceLatest
                                                  -- If-Match: <etag>  (412 = SEConflict, retry)
                                                  -- advanceLatest :: CurrentManifest -> ProposedManifest -> Bool
  pure (CheckpointId manifest)
```

Inference at any point in training or hyperparameter search is symmetric: read `pointers/latest` (or `pointers/best/<metric>`, or a known manifest SHA from a Pulsar `CheckpointDone` event), fetch `manifests/<sha>`, then fetch only the `Weights` part's blob — the optimizer-state and replay-buffer blobs are skipped on the inference path. The snapshot the reader operates against is immutable, so concurrent training advances are invisible to it.

## Retention and GC

Retention (`retain = Checkpoint.Retention.LastN k` in the experiment Dhall) is enforced by a reconciler — `jitml internal gc <experiment-hash>` — invoked by the trainer at training-end. It is not an out-of-band sweep job. Per doctrine §Reconcilers, re-running `gc` on a steady-state experiment is a no-op (exit code `3`).

- **Live set.** The reconciler reads `pointers/latest`, every `pointers/best/<metric>` for the metrics declared in the experiment Dhall, every `pointers/trial/<trial-hash>/*` reachable from the experiment, and follows `cmParentManifest` along the lineage chain from those tips. The transitive closure is the live set.
- **`LastN k` semantics.** `LastN k` keeps the k most-recent manifests on the `latest` chain (by `cmStep`). **`pointers/best/<m>` target manifests are always live regardless of `LastN`** — otherwise GC could invalidate a published "best" checkpoint that a downstream reader is pointing at.
- **Blob GC.** A blob is reapable iff no live manifest references it (the `cpBlobSha` of any live `CheckpointPart`). Per-layer content-addressing means that consecutive checkpoints sharing weight layers keep those layer blobs alive as long as *any* referencing manifest remains live.
- **Audit trail.** GC emits a structured `gc_reaped` event per doctrine §At-Least-Once Event Processing, naming every reaped manifest and blob SHA so the audit trail survives the deletion.

---

# TensorBoard event storage

TensorBoard renders scalars, histograms, distributions, and image summaries from the `jitml-tensorboard` MinIO bucket. The TB pod itself is stateless: it reads MinIO at panel-load time, and reschedules freely. Writers are the clustered `jitml-service` daemon, the host-native Apple daemon, and per-trial workers during hyperparameter sweeps — all writing into the same bucket without coordination.

## Format

The event-file format is **dictated by TensorBoard**, not by us: TFRecord framing wrapping a `tensorflow.Event` protobuf message. We vendor `proto/tensorboard/event.proto` from TensorFlow at a pinned commit and generate Haskell bindings via `proto-lens` (the same toolchain that produces the Pulsar protobuf bindings). The TFRecord frame is:

```
uint64 LE   length
uint32 LE   masked-CRC32C(length-as-8-byte-LE-encoded-bytes)
bytes       payload                     -- a serialised tensorflow.Event protobuf message
uint32 LE   masked-CRC32C(payload-bytes)
```

CRC32C is the Castagnoli polynomial (treating each input byte as an unsigned 32-bit accumulator's input). The mask is TF's standard rotation, applied to the unsigned 32-bit `crc`:

```
masked(crc) = ((crc >> 15) | (crc << 17)) + 0xa282ead8    (mod 2^32)
```

Both shift-and-OR halves are 32-bit unsigned operations; the final addition is unsigned with mod-2^32 wraparound. The first CRC covers the 8 bytes of the little-endian encoded length; the second covers the payload bytes. Nothing about this format is jitML-original — we conform to TB because TB is the reader.

## Bucket layout

```
jitml-tensorboard/
  <experiment-hash>/                                            -- TB's logdir for the experiment
    [tbMode = Overlay (default)]
    shards/<writer-id>-<shard-seq>.tfevents                     -- writer-id = first 16 hex of sha256(host || pid || run-uuid || trial-hash)
    checkpoints/<step>-<manifest-sha>.cbor                      -- one sidecar per checkpoint event

    [tbMode = Isolated, set in the experiment Dhall]
    run/<run-uuid>/shards/<writer-id>-<shard-seq>.tfevents
    run/<run-uuid>/checkpoints/<step>-<manifest-sha>.cbor

    [HPO trials, always isolated by trial-hash]
    trial/<trial-hash>/run/<run-uuid>/shards/<writer-id>-<shard-seq>.tfevents
    trial/<trial-hash>/run/<run-uuid>/checkpoints/<step>-<manifest-sha>.cbor
```

Overlay mode is the default — multiple reruns of the same experiment land under the same TB logdir and TB's UI renders them as one timeline. Isolated mode is the per-Dhall knob that gives each run its own subdirectory and so its own TB "run" entry.

## Shard rotation and append-model mapping

TensorBoard writes append-only event streams locally; S3-like object stores have no append. We map between them with **write-once shards** rotated by size, time, or explicit flush.

Each writer holds an in-memory `Shard` buffer of TFRecord-framed bytes. The buffer flushes — i.e., `PUT`s a single whole object as the next shard, then resets — when **any** of:

- buffer ≥ 4 MiB
- wall-clock elapsed since last flush ≥ 10 s
- an explicit `flush` is called (e.g., on `CheckpointDone`, on graceful shutdown, on `SIGTERM` drain)

Shards are write-once, never modified. PUTs use `If-None-Match: *` so retries are idempotent: the same `(writer-id, shard-seq)` key holds the same bytes; a second PUT returns `412` which the client treats as success. Shard-seq is a monotonic per-writer counter held in-memory by the writer; it is **not** the global training step.

## Concurrency

No CAS, no advisory locks, no leader election — namespacing alone is sufficient:

- **Write/write** is impossible by construction. Two writers with different `(host, pid, run-uuid, trial-hash)` tuples have different writer-ids, therefore different keys. One writer's successive shards have monotonically increasing shard-seq, so two PUTs from the same writer never target the same key either.
- **Write/read** is benign. TB's reader polls the logdir and ingests new shards as they appear; S3 object PUT is atomic, so the reader either sees a complete shard or doesn't see it yet. TB tolerates "new shards appear over time" by design — that's exactly how its local-filesystem mode works.
- **Cross-writer ordering** is handled by TB itself: every `Event` carries `step` and `wall_time`, and TB merges streams by step in its renderer. Out-of-order shard arrival is fine.

This is materially simpler than the checkpoint-pointer concurrency story above, and the difference is intentional — TB events are streaming telemetry, not state needed for resume.

## Cross-link to checkpoint manifests

Every `CheckpointDone` event also writes a CBOR sidecar at:

```
jitml-tensorboard/<experiment-hash>/checkpoints/<step>-<manifest-sha>.cbor
```

```haskell
data TbCheckpointMarker = TbCheckpointMarker
  { tcmStep          :: !Word64
  , tcmEpoch         :: !Word64
  , tcmManifestSha   :: !Hash32     -- references the checkpoint manifest in jitml-checkpoints
  , tcmExperimentSha :: !Hash32
  , tcmTrialSha      :: !(Maybe Hash32)
  , tcmRunUuid       :: !Uuid
  , tcmMetricsAtStep :: ![(Text, Double)]   -- mirror of the manifest's metric snapshot
  }
```

Sidecars are CBOR canonical-form, content-addressed-style, and written with `If-None-Match: *`. The PureScript frontend lists the `checkpoints/` prefix once at panel-load and overlays clickable markers on the TB iframe's loss curve — clicking a marker opens the [Inference panel](#panels) pre-loaded with that manifest SHA. The overlay is a positioned div on top of the iframe; we do not ship a TensorBoard plugin (which would require a TB-extension build chain). This is the single design move that turns TB from passive telemetry into a navigable index into the checkpoint store, and it costs two extra MinIO PUTs per checkpoint event.

## Determinism caveat

**The TensorBoard byte stream is not part of any bit-determinism golden.** TF's `Event` message carries `wall_time` in every payload; shard boundaries depend on wall-clock-driven flush thresholds; writer metadata varies across writer-ids. None of those bytes can be SHA-equal across two runs.

The **scalar values themselves** at each `(tag, step)` *are* deterministic under the [Bit-determinism contract](#bit-determinism-contract): two same-substrate runs with the same seed produce identical `Summary.value.simple_value` at every `(tag, step)`. The TB-event determinism test, in [`jitml-unit`](#test-suite-stanzas), is therefore: decode both runs' shards, project to `[(tag, step, value)]`, sort canonically, assert equality. This caveat is called out so the determinism golden for TB events is not conflated with the checkpoint determinism golden (which is byte-level via `sha256(weights.bin)`).

---

# Pulsar as the control-plane ↔ data-plane bus

Apache Pulsar HA chart: 3× ZooKeeper, 3× BookKeeper, 3× Broker, 3× Proxy, WebSocket enabled. The Pulsar WebSocket proxy is routed at `/pulsar/ws` for operator diagnostics; the PureScript frontend subscribes to live events through the `jitml-demo` proxy at `/api/ws`.

Topic family (substrate-scoped — `<mode>` ∈ `apple-silicon`, `linux-cpu`, `linux-cuda`):

| Topic | Direction | Carrying |
|---|---|---|
| `training.command.<mode>` | control plane → daemon | StartTraining, StopTraining, ResumeFromCheckpoint, AbortTraining |
| `training.event.<mode>` | daemon → control plane / frontend | StepDone, EpochDone, EvalDone, CheckpointDone, MetricUpdate, TrainingFinished, TrainingFailed |
| `tune.command.<mode>` | control plane → daemon | RunTrial, StopTrial |
| `tune.event.<mode>` | daemon → control plane / frontend | TrialStarted, TrialMetricUpdate, TrialFinished, TrialFailed (wire-format protobuf messages; the durable `TrialEvent` CBOR record in the `jitml-trials` MinIO bucket — see [Trial storage and resume](#trial-storage-and-resume) — is *constructed from* these wire events at trial-end, not the same type) |
| `rl.command.<mode>` | control plane → daemon | StartRLRun, StopRLRun |
| `rl.event.<mode>` | daemon → control plane / frontend | EpisodeDone, EvalDone, CheckpointDone, MetricUpdate |
| `inference.request.<mode>` | demo frontend → daemon | inference requests (when demo is in inference mode) |
| `inference.result.<mode>` | daemon → demo frontend | inference results |
| `inference.command.apple-silicon` (Apple only) | cluster orchestrator → host daemon | internal RPC envelopes — see below |
| `inference.event.apple-silicon` (Apple only) | host daemon → cluster orchestrator | ACK envelopes — see below |

The `inference.command.apple-silicon` / `inference.event.apple-silicon` pair only exists on Apple Silicon. On Linux substrates the orchestrator pod runs inference in-process, so the demo-facing `inference.request.<mode>` / `inference.result.<mode>` pair is the only inference topology. On Apple Silicon the cluster orchestrator publishes RPC envelopes on the internal topic, the host daemon consumes them and ACKs on the event topic; demo-facing topics still flow through the orchestrator unchanged.

**Internal RPC envelope (Apple Silicon `inference.command.apple-silicon`):**

```jsonc
{
  "call-id":            "<uuid>",                    // for ACK correlation
  "kind":               "training" | "inference",    // determines pre-flight checks
  "model-id":           "<stable-id>",                // selects the shape-keyed JIT artifact
  "starting-snapshot":  "<manifest-sha>",             // points at the checkpoint manifest in MinIO
  "reply-topic":        "inference.event.apple-silicon",
  "inputs": { /* training: batch-spec, n-steps; inference: input refs */ }
}
```

Pulsar carries small envelopes only. Per-layer weight blobs, optimizer state, and inference outputs travel through MinIO via the same protocol the orchestrator uses; the host daemon writes large artifacts to MinIO directly and the ACK envelope just references the resulting manifest SHAs.

**Stale-starting-snapshot pre-flight (training only).** When `kind == "training"`, the host daemon's first step on receipt is to read `pointers/latest` for the model and compare against `starting-snapshot`. If they disagree (another trainer committed first), the daemon publishes an error envelope on `inference.event.apple-silicon` with shape `{ "call-id": "<uuid>", "kind": "error", "code": "stale-starting-snapshot", "expected": "<latest>", "got": "<starting>" }` and aborts. This is a **recoverable** error per HASKELL_CLI_TOOL.md §Error Handling — the daemon stays healthy, the call is rejected, and the orchestrator either surfaces to the demo or rebases (rebase is a future enhancement; day 1 surfaces). Inference calls skip this check — running inference at any historical snapshot is a legitimate operation.

**Protobuf contract.** Schemas in `./proto/jitml/`, with Haskell bindings via `proto-lens` and PureScript bindings via `purescript-bridge`.

**Fallback when Pulsar is absent.** When `JITML_PULSAR_WS_BASE_URL` and `JITML_PULSAR_ADMIN_URL` env vars are unset (e.g., unit tests), the harness uses a repo-local topic spool at `./.build/runtime/pulsar/`. Tests use this; nothing else.

**At-least-once delivery.** Per doctrine §At-Least-Once Event Processing, every Pulsar message handler is idempotent: idempotency is enforced via MinIO `If-None-Match: *` writes on content-addressed blobs (a redelivered message produces the same SHA, the second PUT returns `412 Precondition Failed`, the handler treats it as success). Redelivery on broker restart or consumer crash is expected and benign. Handlers classify transient failures using the shared [Retry policy](#retry-policy); a `Fatal` classification negatively-acks the message and lets the broker redeliver after backoff. Idempotency keys derive from the protobuf message hash; the daemon does not trust client-supplied IDs.

---

# PostgreSQL

Percona Kubernetes Operator manages a Patroni-backed HA Postgres cluster. Roles:

- Harbor's metadata store.
- (Optional, deployment-time) Grafana dashboard provisioning history when an operator wants persistence across pod restarts beyond what SQLite gives.

**jitML itself does not use Postgres.** Trial state, experiment lineage, checkpoint references, and lineage between training runs and their resumes all live in MinIO — content-addressed manifests carry their own `parent-manifest` pointer (see [Checkpoint object layout](#checkpoint-object-layout)) and the `jitml-trials` bucket is the trial transcript store. jitML's only durable contracts are **MinIO** (artifacts) and **Pulsar** (job queues + events). The Postgres cluster exists for third-party services that themselves require a relational DB; the cluster may add it or remove it without affecting any jitML workload.

---

# TensorBoard, Prometheus, Grafana as first-class

**TensorBoard.** A `tensorboard` pod routed at `/tensorboard`, reading from the `jitml-tensorboard` MinIO bucket. The TB pod is stateless and reschedulable. See [TensorBoard event storage](#tensorboard-event-storage) for the event-file format, bucket layout, shard rotation, concurrency model, cross-link to checkpoint manifests, and determinism caveat. TensorBoard is the headline visualization for SL training; the PureScript frontend's training panel embeds the TB iframe and overlays clickable checkpoint markers.

**Prometheus.** Deployed via `kube-prometheus-stack`. Scrape targets, declared as a typed Haskell value in `src/JitML/Observability/Prometheus.hs`:

- The `jitml-service` daemon (`/metrics` endpoint) — training-step latency, GPU utilization (Metal/CUDA queries), batch throughput, checkpoint write latency, MinIO call latency, Pulsar consume-lag.
- Pulsar broker / proxy.
- MinIO (S3 API metrics).
- Harbor.
- Kind nodes (kubelet + cAdvisor).

**Grafana.** Provisioned dashboards committed to the repo, **generated from typed Haskell datatypes** via a renderer in `src/JitML/Observability/Grafana.hs`. Dashboards rendered by the renderer:

- *Training overview* — loss curves, validation metrics, throughput, GPU utilization, GC time per run.
- *RL overview* — per-env episode reward distribution, env-steps/sec, replay-buffer fill, exploration rate.
- *Hyperparameter sweep* — Pareto frontier (populated by `NSGA-II` when multi-objective; collapses to a single best trial under any single-objective sampler), trial heatmap, per-axis state (Sobol cursor, GA generation, TPE surrogate, ASHA brackets, PBT population).
- *Cluster health* — node CPU/mem, pod restarts, image-pull latency, PVC saturation.

The dashboards are gated by lint just like the route registry: `jitml docs check` compares the renderer's output against committed JSON fixtures, and `jitml docs generate` writes them back.

---

# Outer-container Linux builds

On Linux substrates, *all* builds happen inside `docker compose run --rm jitml jitml ...` against the single substrate image `jitml:local`. The repo has **one Dockerfile** under `docker/`, **one compose service named `jitml`**, and **one image tag `jitml:local`** — no substrate-suffixed variants. The image carries ghcup, Poetry, Node.js 22+, Kind/kubectl/Helm/Docker toolbelt, LLVM, NVCC + cuBLAS + cuDNN (the CUDA bits are baked unconditionally; they activate at runtime only when the pod is scheduled with `runtimeClassName: nvidia`), and Playwright. Bind mounts: `./` for source, `./.build/` for outputs. Substrate selection (linux-cpu vs linux-cuda) happens at runtime via the Dhall config passed to `jitml service`, not via the image or the compose service.

On Apple Silicon, `cabal install` runs directly on the host because the host is the GPU. The asymmetry is intentional: the inner container ensures the Linux build is bit-reproducible across hosts; the Apple host build is reproducible because the host GHC and Cabal versions are pinned by the bootstrap script.

---

# CLI command topology, typed

Per doctrine §Command Topology, commands are modelled as ordinary Haskell data types and the parser is generated from a separate `CommandSpec`. Two Haskell executables share one Cabal library: `app/Main.hs` → `jitml` (control plane + daemon); `app/Demo.hs` → `jitml-demo` (HTTP server hosting the PureScript bundle).

This README is the authoritative documentation for the target command surface. In the implemented tree, `CommandSpec` is the code source that renders the optparse-applicative parser, `--help` text, JSON schema, Markdown, manpages, and the command tree below (doctrine §Command Topology + §Generated Artifacts). Top-level verbs (`train`, `eval`, `tune`) name the primary workflows; noun groups (`bootstrap`, `cluster`, `rl`, `verify`, `inspect`, `bench`, `test`, `lint`, `docs`) hold substrate bootstrap, lifecycle, introspection, benchmarks, and tooling. Sub-ADTs that model >2-state workflows — `ClusterCommand`, `VerifyCommand`, the RL lifecycle — are GADT-indexed in `src/` per doctrine §GADT-Indexed State Machines; the snapshot below elides phantom indices for readability. `jitml bootstrap --<substrate>`, `cluster up`, `docs generate`, `lint --write`, and `internal gc` are reconcilers (idempotent; no-op on match → exit code `3`) per doctrine §Reconcilers.

**Generated mirror.** Every command-surface artifact in this README — the registry snapshot, the command tree, and generated help fragments — is rendered from `CommandSpec` by `jitml docs generate`.

<!-- jitml:command-tree:start -->
```mermaid
mindmap
  root((jitml))
    bootstrap
    doctor
    service
    cluster
      up
      down
      status
      reset
    train
    eval
    tune
    rl
      train
      eval
      rollout
    verify
      same-run
      cross-backend
      replay
    inspect
      list
      show
      replay
      trial
      frontier
    bench
      train
      inference
      env
    inference
      run
    test
      all
      jitml-unit
      jitml-integration
      jitml-sl-canonicals
      jitml-rl-canonicals
      jitml-hyperparameter
      jitml-cross-backend
      jitml-daemon-lifecycle
      jitml-e2e
      jitml-haskell-style
      jitml-purescript-style
    lint
      files
      docs
      proto
      chart
      haskell
      purescript
      all
    docs
      check
      generate
    check-code
    build
    kubectl
    internal
      materialize-substrate
      list-prereqs
      gc
      vm
        bootstrap
        up
        down
        status
        exec
      cache
        stat
        list
        evict
    commands
    help
```
<!-- jitml:command-tree:end -->

<!-- jitml:command-registry:start -->
| Command | Summary | Usage |
|---------|---------|-------|
| `jitml bootstrap` | Bootstrap a substrate stack. | `jitml bootstrap [--apple-silicon] [--linux-cpu] [--linux-cuda] [--dry-run] [--plan-file <path>]` |
| `jitml doctor` | Check host prerequisites. | `jitml doctor [--scope <toolchain\|container\|cluster>] [--remediate]` |
| `jitml service` | Run the jitML daemon. | `jitml service [--config <path>] [--dry-run] [--plan-file <path>]` |
| `jitml cluster up` | Bring the cluster up. | `jitml cluster up [--substrate <substrate>] [--dry-run] [--plan-file <path>]` |
| `jitml cluster down` | Bring the cluster down. | `jitml cluster down` |
| `jitml cluster status` | Report cluster status. | `jitml cluster status` |
| `jitml cluster reset` | Destructively reset cluster state. | `jitml cluster reset --yes` |
| `jitml train` | Run a supervised training job. | `jitml train <experiment-dhall> [--resume <checkpoint-id>] [--dry-run] [--plan-file <path>]` |
| `jitml eval` | Run deterministic evaluation. | `jitml eval <experiment-dhall> [--checkpoint <checkpoint-id>]` |
| `jitml tune` | Run a hyperparameter sweep. | `jitml tune <tune-dhall> [--resume <sweep-id>] [--dry-run] [--plan-file <path>]` |
| `jitml rl train` | Train an RL policy. | `jitml rl train <rl-experiment-dhall> [--resume <checkpoint-id>] [--dry-run] [--plan-file <path>]` |
| `jitml rl eval` | Evaluate an RL policy. | `jitml rl eval <rl-experiment-dhall> [--checkpoint <checkpoint-id>]` |
| `jitml rl rollout` | Run a fixed-seed rollout. | `jitml rl rollout <rl-experiment-dhall> [--seed <word64>]` |
| `jitml verify same-run` | Verify same-run determinism. | `jitml verify same-run --experiment <experiment-dhall> --runs <int>` |
| `jitml verify cross-backend` | Verify cross-backend parity. | `jitml verify cross-backend --experiment <experiment-dhall> --backends <list>` |
| `jitml verify replay` | Verify checkpoint replay. | `jitml verify replay --experiment <experiment-dhall> --checkpoint <checkpoint-id>` |
| `jitml inspect list` | List cached manifests. | `jitml inspect list` |
| `jitml inspect show` | Show a manifest. | `jitml inspect show <manifest-sha> [--with-equity]` |
| `jitml inspect replay` | Replay a manifest. | `jitml inspect replay <manifest-sha>` |
| `jitml inspect trial` | Inspect a trial. | `jitml inspect trial <trial-hash>` |
| `jitml inspect frontier` | Inspect a tuning frontier. | `jitml inspect frontier <sweep-id>` |
| `jitml bench train` | Benchmark training. | `jitml bench train <experiment-dhall>` |
| `jitml bench inference` | Benchmark inference. | `jitml bench inference <experiment-dhall> --checkpoint <checkpoint-id>` |
| `jitml bench env` | Benchmark environment stepping. | `jitml bench env <rl-experiment-dhall>` |
| `jitml inference run` | Run inference at any point. | `jitml inference run <experiment-dhall> --checkpoint <latest\|best/<metric>\|manifest-sha> [--trial <trial-hash>]` |
| `jitml test all` | Run all test stanzas. | `jitml test all [--dry-run] [--plan-file <path>]` |
| `jitml test jitml-unit` | Run jitml-unit. | `jitml test jitml-unit` |
| `jitml test jitml-integration` | Run jitml-integration. | `jitml test jitml-integration` |
| `jitml test jitml-sl-canonicals` | Run jitml-sl-canonicals. | `jitml test jitml-sl-canonicals` |
| `jitml test jitml-rl-canonicals` | Run jitml-rl-canonicals. | `jitml test jitml-rl-canonicals` |
| `jitml test jitml-hyperparameter` | Run jitml-hyperparameter. | `jitml test jitml-hyperparameter` |
| `jitml test jitml-cross-backend` | Run jitml-cross-backend. | `jitml test jitml-cross-backend` |
| `jitml test jitml-daemon-lifecycle` | Run jitml-daemon-lifecycle. | `jitml test jitml-daemon-lifecycle` |
| `jitml test jitml-e2e` | Run jitml-e2e. | `jitml test jitml-e2e` |
| `jitml test jitml-haskell-style` | Run jitml-haskell-style. | `jitml test jitml-haskell-style` |
| `jitml test jitml-purescript-style` | Run jitml-purescript-style. | `jitml test jitml-purescript-style` |
| `jitml lint files` | Run file hygiene checks. | `jitml lint files [--write]` |
| `jitml lint docs` | Run generated documentation checks. | `jitml lint docs [--write]` |
| `jitml lint proto` | Run protobuf schema lint checks. | `jitml lint proto [--write]` |
| `jitml lint chart` | Run Helm chart shape checks. | `jitml lint chart [--write]` |
| `jitml lint haskell` | Run Haskell lint configuration and primitive checks. | `jitml lint haskell [--write]` |
| `jitml lint purescript` | Run PureScript contract and format checks. | `jitml lint purescript [--write]` |
| `jitml lint all` | Run every currently implemented lint check. | `jitml lint all [--write]` |
| `jitml docs check` | Check generated docs. | `jitml docs check` |
| `jitml docs generate` | Generate docs. | `jitml docs generate` |
| `jitml check-code` | Run the code quality gate. | `jitml check-code` |
| `jitml build` | Build inside the substrate container. | `jitml build [--substrate <substrate>] [--dry-run] [--plan-file <path>]` |
| `jitml kubectl` | Run kubectl against the jitML kubeconfig. | `jitml kubectl [-- <kubectl-args...>]` |
| `jitml internal materialize-substrate` | Materialize substrate files. | `jitml internal materialize-substrate [--substrate <substrate>]` |
| `jitml internal list-prereqs` | List prerequisite checks. | `jitml internal list-prereqs` |
| `jitml internal gc` | Apply checkpoint retention. | `jitml internal gc <experiment-hash> [--dry-run] [--plan-file <path>]` |
| `jitml internal vm bootstrap` | Bootstrap the VM. | `jitml internal vm bootstrap` |
| `jitml internal vm up` | Start the VM. | `jitml internal vm up` |
| `jitml internal vm down` | Stop the VM. | `jitml internal vm down` |
| `jitml internal vm status` | Report VM status. | `jitml internal vm status` |
| `jitml internal vm exec` | Run a command in the VM. | `jitml internal vm exec -- <cmd...>` |
| `jitml internal cache stat` | Print cache stats. | `jitml internal cache stat` |
| `jitml internal cache list` | List cache entries. | `jitml internal cache list` |
| `jitml internal cache evict` | Evict a cache entry. | `jitml internal cache evict <hash>` |
| `jitml commands` | Print the command registry. | `jitml commands [--tree] [--json]` |
| `jitml help` | Print focused command help. | `jitml help [-- <subcommand...>]` |
<!-- jitml:command-registry:end -->

### Generated documentation flow

**`docs *` vs `lint *` — distinct surfaces, no overlap.** Per doctrine §Generated Artifacts, `docs check` / `docs generate` cover artifacts that are *rendered from typed Haskell source* into a committed file or marker region — the route table, Grafana dashboards, PureScript contracts, proto-derived modules, and CLI help. Per doctrine §Lint, Format, and Code-Quality Stack, `lint *` covers *hand-written* source: Haskell (`fourmolu --mode check` + `hlint`), PureScript (`purs format` round-trip), proto schemas, chart structural invariants, and file-hygiene rules. The two surfaces do not overlap; an artifact owned by `docs *` is never lint-managed, and vice versa. When adding a new generated artifact, extend the `GeneratedSectionRule` registry; when adding a new lint rule, extend the appropriate `LintCommand` constructor.

Per doctrine §Automatically Generated Documentation and §Generated Artifacts, `CommandSpec` fans out to several artifact families:

```mermaid
flowchart LR
    spec[CommandSpec]
    parser["optparse-applicative parser<br/><i>runtime: jitml &lt;args&gt;</i>"]
    help["--help text<br/><i>runtime + golden test</i>"]
    md["Markdown sections<br/><i>spliced between sentinel markers</i>"]
    man["manpage&lpar;s&rpar;<br/><i>rendered for distribution</i>"]
    json["JSON schema<br/><i>jitml commands --json;</i><br/><i>externally stable</i>"]
    spec --> parser
    spec --> help
    spec --> md
    spec --> man
    spec --> json
```

Every entry in the `DocsTarget` enum above has a paired `docs check` / `docs generate` command. `docs check <target>` exact-string-compares the in-tree rendering against the file (or marker region) it should match and exits non-zero with the marker key and a remedy hint on drift; `docs generate <target>` is the reconciler that splices the freshly-rendered content between sentinel markers in place. Implementing only the check half is forbidden by doctrine §Generated Artifacts: a contributor who sees `"X has drifted"` with no way to fix it will eventually disable the lint rather than fight the loop.

The marker-key registry is a `GeneratedSectionRule` table in `src/JitML/Docs/Rules.hs`. Current keys in this README are `command-tree` and `command-registry`; route-table, Grafana-dashboard, PureScript-contract, and proto-schema rules are used in their owning files.

### Architecture: module tiers

Per doctrine §Architecture, the CLI binary is one dataflow from typed surface to subprocess interpreter:

```mermaid
flowchart LR
    Spec["CLI.Spec<br/><i>CommandSpec value</i><br/>code registry"]
    Parser["CLI.Parser<br/><i>optparse-applicative</i><br/>generated from the spec"]
    Docs["CLI.Docs<br/><i>Markdown, manpages,</i><br/><i>JSON schema, command tree</i>"]
    Commands["Commands.*<br/><i>one module per top-level constructor</i><br/>build :: Inputs → Either AppError Plan<br/>apply :: Env → Plan → IO ExitCode"]
    Sub["Subprocess<br/><i>pure ADT; rendered for logs /</i><br/><i>--dry-run / golden tests;</i><br/><i>interpreter at the boundary</i>"]
    App["App<br/><i>ReaderT Env IO;</i><br/><i>owns process exit</i>"]
    Spec --> Parser --> Docs --> Commands --> Sub --> App
```

`app/Main.hs` is a six-line shim into `App.main`. Logic that fits in any of the upper tiers stays out of `app/`. Module layout lives at [Repository layout (target)](#repository-layout-target).

### Standard flag families

Per doctrine §Standard Flag Families for the canonical spellings, semantics, and prohibitions (notably `--detach`); the table below pins jitML's binding of each family to commands.

| Command | Plan/Apply | Daemon | Output |
|---|:---:|:---:|:---:|
| `bootstrap --apple-silicon` / `bootstrap --linux-cpu` / `bootstrap --linux-cuda` | ✓ |   |   |
| `cluster up` / `cluster down` / `cluster reset` | ✓ |   |   |
| `cluster status` |   |   | ✓ |
| `service` | ✓ | ✓ |   |
| `train` / `eval` / `tune` / `rl *` | ✓ |   | ✓ |
| `verify *` / `inspect *` / `bench *` / `inference run` |   |   | ✓ |
| `test all` | ✓ |   | ✓ |
| `test <stanza>` / `lint *` / `docs *` |   |   | ✓ |
| `check-code` / `build` / `kubectl` |   |   | ✓ |
| `internal gc` | ✓ |   | ✓ |
| `internal materialize-substrate` / `internal list-prereqs` / `internal vm *` / `internal cache *` |   |   | ✓ |
| `commands` / `help` |   |   | ✓ |

Concrete invocations:

```bash
./bootstrap/apple-silicon.sh                 # stage-0 gates + build ./.build/jitml + delegates to jitml bootstrap --apple-silicon
./.build/jitml cluster status                # prints edge port and routes

./.build/jitml train  experiments/mnist-mlp.dhall --substrate apple-silicon --seed 42
./.build/jitml tune   experiments/mnist-mlp.dhall --sampler sobol --trials 64 --parallelism 8
./.build/jitml tune   experiments/mnist-mlp.dhall --sampler tpe --scheduler asha --trials 256 --parallelism 8
./.build/jitml rl     train experiments/cartpole-ppo.dhall --substrate apple-silicon --seed 42
./.build/jitml verify same-run     --experiment experiments/mnist-mlp.dhall --runs 3
./.build/jitml verify cross-backend --experiment experiments/mnist-mlp.dhall --backends cpu,cuda
./.build/jitml inspect frontier --tuning-run <ref> --pareto valLoss params
./.build/jitml test   all
```

### Exit codes and error rendering

Per doctrine §Error Handling for the typed-domain-ADT discipline and single rendering site. jitML's `AppError` at the CLI boundary and per-`Commands.*` validation errors follow that shape; the exit-code table below extends the doctrine with code `3` for reconciler no-op-on-match.

| Code | Meaning |
|---|---|
| `0` | success |
| `1` | user / usage error (bad flag, missing argument, malformed Dhall, validation failure) |
| `2` | system / capability error (MinIO, Pulsar, Harbor, kubectl, network failure after retry) |
| `3` | reconciler no-op-on-match (`bootstrap`, `cluster up`, `docs generate`, `lint --write` found nothing to do) |

`test all`, `verify *`, `lint *`, and `docs check` communicate pass/fail by exit code only; their stdout is the rendered Plan, golden output, or summary block — never a status string for callers to grep.

The daemon classifies thrown errors as `Recoverable` or `Fatal`. `Recoverable` logs structured JSON and continues after retry per [Retry policy](#retry-policy); `Fatal` drains in-flight work, emits a final structured event, and exits. The full daemon contract (`/healthz`, `/readyz`, `/metrics`, structured JSON logging, drain-on-SIGTERM, `BootConfig`/`LiveConfig` split with SIGHUP hot reload) is doctrine §Long-Running Daemons in the Same Binary; jitML opts in (see [Doctrine scope](#doctrine-scope)).

### Capability classes and the service-error union

Per doctrine §Capability Classes and Service Errors. jitML's capability typeclasses are `HasMinIO`, `HasPulsar`, `HasHarbor`, `HasKubectl`; each capability's typed error injects into a unified `ServiceError` via `AsServiceError`.

### Retry policy

Per doctrine §Retry Policy as First-Class Values. jitML's `RetryPolicy` value is consumed by reconcilers, the Pulsar consumer (alongside its at-least-once guarantee — see [Pulsar as the control-plane ↔ data-plane bus](#pulsar-as-the-control-plane--data-plane-bus)), and capability-call wrappers.

### Daemon environment: Env, BootConfig, LiveConfig

Per doctrine §Application Environment and §Long-Running Daemons for the `ReaderT Env IO` shape, SIGHUP semantics, and drain contract. jitML's keys:

- **`BootConfig`** (immutable post-launch): listening port, MinIO endpoint, Pulsar broker URL, Harbor registry, kubeconfig path, drain deadline.
- **`LiveConfig`** (hot-reloadable via SIGHUP): log level, request-timeout budgets, retry-policy values from [Retry policy](#retry-policy), feature gates.

`Env` additionally carries the structured logger, metrics handle, shutdown signal, and explicit test hooks (e.g., a `clock` field so determinism tests can fix time). The lifecycle is exercised by the [`jitml-daemon-lifecycle`](#test-suite-stanzas) test stanza.

### Progressive introspection

Per doctrine §Progressive Introspection: `jitml commands`, `jitml commands --tree`, `jitml commands --json`, `jitml help <subcommand>`.

---

# Numerical core

## Layer catalog

`jitML` supports arbitrarily-shaped non-recurrent feedforward networks. Every layer is a first-class Dhall constructor; networks are composed as arbitrary DAGs over these primitives.

- **Dense / Linear.** With or without bias; optional spectral norm.
- **Convolution.** `Conv1D`, `Conv2D`, `Conv3D`. Variants: standard, transposed, depthwise / separable, dilated / atrous, grouped.
- **Pooling.** `MaxPool{1,2,3}D`, `AvgPool{1,2,3}D`, `AdaptiveAvgPool`, `GlobalAvgPool`, spectral pooling (see [Spectral / frequency-domain operations](#spectral--frequency-domain-operations)).
- **Normalization.** `BatchNorm{1,2,3}D`, `LayerNorm`, `GroupNorm`, `InstanceNorm{1,2,3}D`, `RMSNorm`, `WeightNorm`. Running statistics are deterministic and checkpointable.
- **Residual building blocks.** `BasicBlock` (ResNet), `BottleneckBlock` (ResNet-50+), `InvertedResidual` (MobileNet-style), `DenseBlock` (DenseNet-style concat).
- **Regularization.** `Dropout`, `Dropout2D`, `StochasticDepth`, `DropPath`. All seed-deterministic.
- **Attention.** `ScaledDotProductAttention`, `MultiHeadAttention`, `RotaryPositionalEmbedding`. A `FlashAttention`-style fused kernel is a JIT codegen target.
- **Embedding.** `TokenEmbedding`, `LearnedPositionalEmbedding`, `SinusoidalPositionalEmbedding`.
- **Multi-headed architectures.** Explicit Dhall support for K policy/value/auxiliary heads sharing a trunk (used by both actor-critic RL and [AlphaZero-style self-play](#alphazero-style-self-play)).
- **Arbitrary DAG-style computation graphs.** Composition is a value, not a class hierarchy.

## Activation functions

### Real-valued

ReLU, LeakyReLU, PReLU, ELU, SELU, GELU (exact + tanh approximation), SiLU/Swish, Mish, Sigmoid, Tanh, Softmax, LogSoftmax, Hardtanh, Hardsigmoid, Hardswish, Softplus, Softsign, GLU, GeGLU, SwiGLU.

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

Supported optimizers: SGD, Momentum SGD, Nesterov SGD, RMSProp, Adagrad, Adadelta, Adam, AdamW, LAMB, LARS, Lion. All are composable with gradient-clipping wrappers (`ClipByNorm`, `ClipByValue`, `ClipByGlobalNorm`). Optimizer state is fully deterministic and checkpointable.

## Schedulers

Pure functions of `progress ∈ [0, 1]`, applicable to any scalar hyperparameter (learning rate, momentum, weight decay, dropout rate). Variants: `Constant`, `Linear`, `Cosine`, `CosineWithWarmup`, `Exponential`, `Polynomial`, `OneCycle`, `Piecewise`. The RL `Schedule` ADT used by PPO clip ranges, DQN ε, and SAC entropy floors (see [Schedules](#schedules)) is the same type.

History-dependent adjustments such as `ReduceOnPlateau` do not fit the `Schedule a` shape (they consume metric history, not `progress ∈ [0,1]`). They live in the [Callbacks](#callbacks-as-composable-hooks) family — the `onEvaluation` hook has access to the `EvalResult` and can mutate the optimiser's learning-rate field directly. Keeping `Schedule` purely a function of progress preserves `evalSchedule :: Schedule a -> Double -> a` as a property-test surface.

## Loss functions

Loss functions are represented declaratively in Dhall: scalar losses, multi-headed losses, weighted losses, policy/value hybrid losses, and arbitrary symbolic compositions.

---

# Concrete Dhall worked example

A canonical SL experiment, end-to-end. The `dataset.train` field is the source for *both* train and validation splits — `Split.PermuteUnderSeed` slices `fullTrain` into a 55 000-example training partition and a 5 000-example validation partition under a fixed seed. `dataset.test` is the held-out final-evaluation set used by the convergence golden, never seen during training. The `metrics` list declares each metric's direction (`Maximise` for accuracy, `Minimise` for loss), which the trainer's `pointers/best/<m>` CAS predicate consumes (see [Concurrency model](#concurrency-model)). The `tuning` field is `None Tuning` for single-run experiments; setting it to `Some Tuning::{ … }` turns the definition into a sweep — see [Hyperparameter tuning](#hyperparameter-tuning-first-class).

```dhall
-- experiments/mnist-mlp.dhall

let Activation       = ./types/Activation.dhall
let Layer            = ./types/Layer.dhall
let Optimizer        = ./types/Optimizer.dhall
let Dataset          = ./types/Dataset.dhall
let Split            = ./types/Split.dhall
let Checkpoint       = ./types/Checkpoint.dhall
let Substrate        = ./types/Substrate.dhall
let MetricDirection  = ./types/MetricDirection.dhall
let Tuning           = ./types/Tuning.dhall

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
, split = Split.PermuteUnderSeed
    { fullTrain     = mnistTrain
    , trainFraction = 0.9166666666666666     -- 55000 / 60000 of mnistTrain → train; remainder → val
    , seed          = 1729
    }
, metrics =
    [ { name = "valLoss", direction = MetricDirection.Minimise }
    , { name = "valAcc",  direction = MetricDirection.Maximise }
    ]
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
, tuning = None Tuning                        -- single-run; see Hyperparameter tuning for the Some shape
}
```

---

# Hyperparameter tuning, first-class

A `Tuning` block in any experiment Dhall converts a single-run definition into a multi-trial sweep. The same Dhall describes a single training run (no `tuning`) or a 128-trial sweep (`tuning = Some Tuning::{ … }`); CLI flags (`--sampler …`, `--scheduler …`, `--pruner …`) *override* the Dhall on each axis, never replace it.

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

## Three orthogonal axes: sampler × scheduler × pruner

HPO is decomposed into three independent typed axes rather than one flat `Strategy` enum. Any **sampler** (what hyperparameter point to evaluate next) composes with any **scheduler** (how to allocate compute budget across trials) and any **pruner** (whether to terminate a trial early). The combinatorial product is expressible directly in Dhall.

### Samplers

```dhall
let Sampler =
      < Grid                                                          -- exhaustive baseline
      | Random      : { seed : Natural }
      | Sobol       : { dimensions : Natural, skipAhead : Natural }   -- low-discrepancy quasi-random; skipAhead is the start index in the sequence, not an RNG seed
      | TPE         : { seed : Natural, nStartupTrials : Natural }    -- Tree-structured Parzen Estimator
      | GPBO        : { seed : Natural, acquisition : Acquisition }   -- Gaussian-process Bayesian Opt
      | GA          : { population : Natural, generations : Natural
                      , mutationRate : Double, crossoverRate : Double
                      , seed : Natural
                      }
      | NSGA2       : { population : Natural, generations : Natural, seed : Natural }   -- multi-objective
      | MuLambdaES  : { mu : Natural, lambda : Natural, sigma : Double, seed : Natural }
      | CMAES       : { sigma0 : Double, popSize : Natural, seed : Natural }            -- adaptive covariance
      | PBT         : { population : Natural, exploitFraction : Double
                      , exploreSigma : Double, readyInterval : Natural, seed : Natural
                      }
      >
```

- **Grid** — exhaustive baseline; trivial determinism.
- **Random search (uniform)** — trivial baseline.
- **Sobol low-discrepancy quasi-random** — deterministic given `skipAhead` + `dimensions` (Sobol is a deterministic sequence; the `skipAhead` argument is the start index, not an RNG seed); bit-reproducible trial selection.
- **TPE (Tree-structured Parzen Estimator)** — Bayesian sampler; the workhorse of modern HPO (Optuna / Hyperopt default).
- **GP-BO** — Gaussian-process Bayesian optimisation; for continuous spaces with expensive evaluations.
- **GA** — genetic algorithm; explicit parent-selection, mutation, crossover.
- **NSGA-II** — multi-objective GA; produces a Pareto frontier directly (the frontend's Pareto-frontier panel actually has a *producer*).
- **(μ, λ) evolution strategies** — for continuous spaces.
- **CMA-ES** — Covariance Matrix Adaptation ES; the canonical continuous black-box optimizer.
- **PBT (Population Based Training)** — population-based; mutates hyperparameters *during* training (touches the inner loop, not just trial scheduling). Especially well-suited to RL where stationary HPO is a poor fit for non-stationary learning dynamics.

### Schedulers

```dhall
let Scheduler =
      < Fifo                                                          -- trial-equal-budget; default
      | SuccessiveHalving : { eta : Natural, maxBudget : Natural }
      | Hyperband         : { eta : Natural, maxBudget : Natural, rBrackets : Natural }
      | ASHA              : { eta : Natural, maxBudget : Natural, parallelism : Natural }
      >
```

`Fifo` runs every trial to its full budget. `SuccessiveHalving`, `Hyperband`, and `ASHA` allocate compute progressively, terminating under-performing trials at rung boundaries. ASHA is Hyperband's asynchronous variant; it pairs naturally with high `parallelism`.

### Pruners

```dhall
let Pruner =
      < NoPruner
      | MedianPruner     : { warmupTrials : Natural, evalAtPercentile : Natural }
      | PercentilePruner : { warmupTrials : Natural, percentile : Double }
      >
```

Pruners are orthogonal to schedulers: a `Fifo` scheduler with a `MedianPruner` still terminates trials whose intermediate metric drops below the running median, just without the Hyperband-style rung structure.

### Composition

```dhall
let Tuning =
      { space       : SearchSpace
      , sampler     : Sampler
      , scheduler   : Scheduler
      , pruner      : Pruner
      , trials      : Natural
      , parallelism : Natural
      , objectives  : List ObjectiveSpec    -- length 1 → single-objective; ≥ 2 → multi-objective (requires NSGA2)
      }
```

The `objectives` field must list metrics declared in the parent experiment's `metrics` list so the trial scoreboard knows the direction of each. A length-≥ 2 `objectives` is only meaningful with `sampler = NSGA2`; the validator rejects other pairings.

## Concrete `Some Tuning::{ … }` example

The `tuning = None Tuning` placeholder in [Concrete Dhall worked example](#concrete-dhall-worked-example) becomes:

```dhall
, tuning = Some Tuning::{
    , space     = SearchSpace::{ learningRate = { min = 1.0e-5, max = 1.0e-2, scale = Log }
                               , batchSize    = { values = [32, 64, 128, 256] }
                               , dropout      = { min = 0.0, max = 0.5, scale = Linear }
                               , optimizer    = { values = ["Adam", "AdamW", "SGD"] }
                               }
    , sampler   = Sampler.TPE { seed = 1729, nStartupTrials = 16 }
    , scheduler = Scheduler.ASHA { eta = 3, maxBudget = 50000, parallelism = 8 }
    , pruner    = Pruner.MedianPruner { warmupTrials = 8, evalAtPercentile = 50 }
    , trials    = 128
    , parallelism = 8
    , objectives = [ { metric = "valAcc", direction = MetricDirection.Maximise } ]
    }
```

Replacing `sampler` with `Sampler.GA { … }`, `Sampler.NSGA2 { … }`, or `Sampler.PBT { … }` changes the search method without touching any other axis. Replacing `scheduler` with `Scheduler.Hyperband { … }` opts into bracketed multi-fidelity scheduling.

## Trial storage and resume

The trial transcript is an **append-only event log** in MinIO bucket `jitml-trials`, per doctrine §At-Least-Once Event Processing. Each trial completion is one immutable object, content-addressed by `sha256(resolved-dhall || trial-seed)`. The payload is a canonical-CBOR `TrialEvent`:

```haskell
data TrialEvent = TrialEvent
  { teExperimentHash    :: !Hash32
  , teSampler           :: !SamplerTag         -- Grid | Random | Sobol | TPE | GPBO | GA | NSGA2 | MuLambdaES | CMAES | PBT
  , teStrategyStep      :: !Word64             -- cursor index / generation / iteration
  , teIntraStepRank     :: !Word32             -- dispatch order within the step (0..K-1)
  , teBracketIndex      :: !(Maybe Word16)     -- Hyperband / ASHA bracket
  , teRungIndex         :: !(Maybe Word16)     -- Hyperband / ASHA rung within bracket
  , teBudgetAtRung      :: !(Maybe Word64)     -- per-rung compute budget
  , tePbtEvent          :: !(Maybe PbtEvent)   -- Exploit / Explore; PBT only
  , teTrialHash         :: !Hash32             -- sha256(resolved-dhall || trial-seed)
  , teSeed              :: !Word64
  , teMetrics           :: ![(Text, Double)]
  , teCheckpointSha     :: !(Maybe Hash32)     -- final-manifest sha, if checkpoint write succeeded
  , teParentTrialHashes :: ![Hash32]           -- GA / NSGA2 crossover lineage; PBT exploit source; [] otherwise
  , teCreatedAtNs       :: !Word64             -- monotonic; recorded for telemetry; NEVER load-bearing
  }

data PbtEvent
  = Exploit { from :: Hash32, to :: Hash32 }
  | Explore { trialHash :: Hash32, mutations :: [(Text, Double, Double)] }   -- (hpName, before, after)
```

**Canonical replay order.** On resume, events are read out of MinIO and sorted by `(teStrategyStep, teIntraStepRank)`. **Not** by `teCreatedAtNs`, **not** by wall-clock arrival, **not** by trial-hash — wall-clock order is non-reproducible under parallelism, and a sort that depends on it would re-introduce the determinism gap. The strategy-emitted `(step, rank)` tuple is the canonical ordering because the strategy itself is the only thing that knows which trials belong to which generation/cursor position.

**Strategy as a pure state machine.** Each strategy exposes

```haskell
step      :: StrategyState -> TrialEvent -> StrategyState
nextBatch :: StrategyState -> [TrialSpec]    -- the next K candidates to dispatch
```

Resume is `foldl step initialState (sortByCanonical events)`; the next batch follows deterministically. Per-sampler state:

- **Grid / Sobol / Random** — a single `Word64` cursor; replay coincides with cursor order because `teStrategyStep` *is* the cursor index.
- **TPE / GP-BO** — the surrogate is a pure function of the canonically-ordered trial-event log; replay rebuilds the surrogate exactly. Acquisition is seeded.
- **GA / NSGA-II** — `[GenomeWithFitness]` for the current generation plus an in-progress buffer; parents come from `teParentTrialHashes`. Replay order is load-bearing: same generation index, same intra-generation rank, same selection-pressure ranking. NSGA-II additionally sorts fronts by domination rank then by crowding distance, both canonical.
- **(μ, λ) ES** — `(mean, sigma, generation)`; order-dependent.
- **CMA-ES** — `(mean, covariance, generation)`; serialised in CBOR the same way as ES.
- **PBT** — population snapshot at each ready-interval; `Exploit` events copy weights between trial hashes, `Explore` events perturb hyperparameters. Resume replays both event kinds against the canonical event log to reconstruct the population.

Scheduler state (orthogonal to sampler state):

- **Fifo** — none.
- **SuccessiveHalving / Hyperband / ASHA** — bracket/rung occupancy tables, keyed on `(teBracketIndex, teRungIndex)`. Promotions are deterministic on the canonical event log.

**Tightened claim.** The (sampler, scheduler, pruner) state is reproducible from `(strategy-seed, canonically-ordered event log of completed TrialEvents)`. For Grid/Sobol/Random the canonical ordering coincides with cursor order; for everything else the ordering is load-bearing.

## Parallelism

`--parallelism N` schedules N trials concurrently; the sampler exposes a "next batch of K candidates" interface, and the dispatcher publishes them to N workers via `tune.command.<mode>` Pulsar messages. Per-trial determinism is unaffected by N (each trial owns its seed); only wall-clock changes. The trial-event log records `(strategyStep, intraStepRank)` at dispatch time, so concurrent completions can land in MinIO in any order without disturbing replay.

Hyperband / ASHA introduce variable per-trial budgets, so the canonical ordering is augmented with `(bracketIndex, rungIndex)`. PBT couples trials by `Exploit` events, so its parallelism story differs from independent-trial sampling: workers report metrics at each `readyInterval` and a controller publishes `Exploit / Explore` events deterministically based on the canonical-replay order. Workers never compute `Exploit / Explore` decisions on their own — only the controller does, and only from the canonical log. *This is a deliberate deviation from Jaderberg et al.'s decentralised exploit/explore between worker pairs (Population Based Training, 2017): the controller-only routing is what makes resume-from-event-log reconstructive. The cost is scalability — a single decision-maker is a serial bottleneck — which jitML accepts in exchange for bit-deterministic PBT replay.*

## Frontend integration

The PureScript frontend's hyperparameter panel subscribes to `tune.event.<mode>` over `/api/ws` and animates the Pareto frontier (populated by NSGA-II under multi-objective sweeps; collapses to a best-trial highlight under single-objective samplers), the trial-by-trial heatmap, and the per-axis state live. PBT gets its own panel layout — population over time, hyperparameter-mutation lineage tree, `Exploit`/`Explore` event timeline — see [PureScript frontend](#purescript-frontend).

---

# Canonical supervised learning problems

Eleven problems spanning the architectural breadth of the [Layer catalog](#layer-catalog), each compact enough to baseline on a single reference host.

| Dataset | Model | Architectural features showcased | Literature target | Citation |
|---|---|---|---|---|
| MNIST | shallow MLP (1×128 hidden) | Dense + ReLU + Softmax | ~98.0% test acc | LeCun et al. 1998 [^lecun1998] |
| MNIST | deep MLP w/ BN + Dropout | Dense + BatchNorm + Dropout + GELU | ~98.5–99.0% | Ioffe & Szegedy 2015 [^ioffe2015] |
| MNIST | deep CNN (LeNet-5 variant) | Conv2D + AvgPool + Tanh | ~99.05% (1998); 99.2–99.4% modern | LeCun et al. 1998 [^lecun1998] |
| Fashion-MNIST | shallow MLP | Dense + ReLU | ~87–88% | Xiao et al. 2017 [^xiao2017] |
| Fashion-MNIST | small ResNet | Conv2D + BatchNorm + BasicBlock | ~93% | He et al. 2015 [^he2015] |
| CIFAR-10 | ResNet-20 | BasicBlock + global avg pool | 91.25% | He et al. 2015 [^he2015] |
| CIFAR-10 | ResNet-56 | Deeper residual + 3-stage downsample | ~93.0% | He et al. 2015 [^he2015] |
| CIFAR-100 | Wide ResNet-28-10 | Wider residual + Dropout | ~81.2% | Zagoruyko & Komodakis 2016 [^zagoruyko2016] |
| CIFAR-10 | small ViT | Patch embed + MultiHeadAttention + LayerNorm + GeGLU | ~80–85% from-scratch (no pre-training) | Dosovitskiy et al. 2020 [^dosovitskiy2020] |
| Tiny ImageNet (200-class, 64×64) | ResNet-50 | BottleneckBlock + GroupNorm option | ~50–65% top-1 from-scratch | Le & Yang 2015 [^leyang2015]; He et al. 2015 [^he2015] |
| California Housing (UCI tabular regression) | small MLP | MSE loss; non-classification path | RMSE ≈ 0.50 (standardized target) | Pace & Barry 1997 [^pace1997]; Hernández-Lobato & Adams 2015 [^hernandez2015] |

## Dataset sources

Each dataset's source URL is pinned, the source bytes' SHA-256 is recorded (in the experiment Dhall, not in this table), and the train/val/test split is a deterministic permutation under a fixed seed. Datasets land in MinIO bucket `jitml-datasets` on first use; subsequent runs read from MinIO.

| Dataset | Public download URL | Size (gzipped) | License / re-distribution note |
|---|---|---|---|
| MNIST | `https://storage.googleapis.com/cvdf-datasets/mnist/` (4 files: `{train,t10k}-{images-idx3,labels-idx1}-ubyte.gz`) | ~11 MB total | CC BY-SA 3.0 (per LeCun's original distribution terms; CVDF mirrors with permission) |
| Fashion-MNIST | `https://github.com/zalandoresearch/fashion-mnist/raw/master/data/fashion/` (same 4-file IDX layout as MNIST) | ~30 MB total | MIT license [^xiao2017] |
| CIFAR-10 | `https://www.cs.toronto.edu/~kriz/cifar-10-binary.tar.gz` | ~170 MB | research use, see Krizhevsky 2009 TR [^krizhevsky2009] |
| CIFAR-100 | `https://www.cs.toronto.edu/~kriz/cifar-100-binary.tar.gz` | ~170 MB | research use, same TR |
| Tiny ImageNet | `http://cs231n.stanford.edu/tiny-imagenet-200.zip` | ~237 MB | Stanford CS231N course; derived from ImageNet — abide by ImageNet terms |
| California Housing (UCI) | `https://www.dcc.fc.up.pt/~ltorgo/Regression/cal_housing.tgz` (or via `sklearn.datasets.fetch_california_housing`) | ~370 KB | public domain (StatLib); cite Pace & Barry 1997 |

## Threshold methodology

The literature-target column above is a **sanity-check expectation**, not the golden. The actual golden numbers are derived from a `k=5` replicate baseline on the pinned reference host: five seeds, each trained to a budget that visibly plateaus the loss curve, then

```
target = median(test_acc) − slack
slack  = 95th-percentile residual deviation across the five seeds
```

so the golden passes with 95% probability if no regression has occurred. If the reference-host `k=5` median materially undershoots the literature target (e.g. by > 1–2 percentage points on classification, or proportionally on RMSE), that's an investigation trigger before the golden is committed. Treating the literature-target numbers as load-bearing — or as a substitute for the empirical baseline — is forbidden.

## Citations

[^lecun1998]: LeCun, Bottou, Bengio, Haffner. ["Gradient-Based Learning Applied to Document Recognition."](http://yann.lecun.com/exdb/publis/pdf/lecun-01a.pdf) Proc. IEEE 86(11):2278–2324, 1998.
[^ioffe2015]: Ioffe & Szegedy. ["Batch Normalization: Accelerating Deep Network Training by Reducing Internal Covariate Shift."](https://arxiv.org/abs/1502.03167) ICML 2015.
[^xiao2017]: Xiao, Rasul, Vollgraf. ["Fashion-MNIST: a Novel Image Dataset for Benchmarking Machine Learning Algorithms."](https://arxiv.org/abs/1708.07747) 2017.
[^he2015]: He, Zhang, Ren, Sun. ["Deep Residual Learning for Image Recognition."](https://arxiv.org/abs/1512.03385) CVPR 2016.
[^zagoruyko2016]: Zagoruyko & Komodakis. ["Wide Residual Networks."](https://arxiv.org/abs/1605.07146) BMVC 2016.
[^dosovitskiy2020]: Dosovitskiy et al. ["An Image is Worth 16×16 Words: Transformers for Image Recognition at Scale."](https://arxiv.org/abs/2010.11929) ICLR 2021.
[^krizhevsky2009]: Krizhevsky. ["Learning Multiple Layers of Features from Tiny Images."](https://www.cs.toronto.edu/~kriz/learning-features-2009-TR.pdf) Technical Report, University of Toronto, 2009.
[^leyang2015]: Le & Yang. ["Tiny ImageNet Visual Recognition Challenge."](http://cs231n.stanford.edu/reports/2015/pdfs/yle_project.pdf) Stanford CS231N final report, 2015.
[^pace1997]: Pace & Barry. "Sparse Spatial Autoregressions." Statistics & Probability Letters 33(3):291–297, 1997.
[^hernandez2015]: Hernández-Lobato & Adams. ["Probabilistic Backpropagation for Scalable Learning of Bayesian Neural Networks."](https://arxiv.org/abs/1502.05336) ICML 2015.

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

`AlgoClass` is a `DataKinds`-promoted enumeration; `AlgoSpec` is a GADT indexed by it, so each algorithm constructor records its class at the type level. PPO touching a `ReplayBuffer`, or DQN touching a `RolloutBuffer`, is a compile-time error rather than a runtime surprise.

```haskell
data AlgoClass = OnPolicy | OffPolicy | BlackBox | SelfPlay

type AlgoSpec :: AlgoClass -> Type -> Type -> Type
data AlgoSpec c obs act where
  PPO          :: PPOConfig          -> AlgoSpec 'OnPolicy  obs act
  A2C          :: A2CConfig          -> AlgoSpec 'OnPolicy  obs act
  TRPO         :: TRPOConfig         -> AlgoSpec 'OnPolicy  obs act
  MaskablePPO  :: MaskablePPOConfig  -> AlgoSpec 'OnPolicy  obs 'Masked
  RecurrentPPO :: RecurrentPPOConfig -> AlgoSpec 'OnPolicy  obs act           -- carries RNN state
  DQN          :: DQNConfig          -> AlgoSpec 'OffPolicy obs 'Discrete
  QRDQN        :: QRDQNConfig        -> AlgoSpec 'OffPolicy obs 'Discrete
  DDPG         :: DDPGConfig         -> AlgoSpec 'OffPolicy obs 'Continuous
  TD3          :: TD3Config          -> AlgoSpec 'OffPolicy obs 'Continuous
  SAC          :: SACConfig          -> AlgoSpec 'OffPolicy obs 'Continuous
  CrossQ       :: CrossQConfig       -> AlgoSpec 'OffPolicy obs 'Continuous
  TQC          :: TQCConfig          -> AlgoSpec 'OffPolicy obs 'Continuous
  ARS          :: ARSConfig          -> AlgoSpec 'BlackBox  obs act
  AlphaZero    :: AlphaZeroConfig    -> AlgoSpec 'SelfPlay  obs 'Masked
```

HER is a buffer transformer, not its own GADT case; see [Buffers](#buffers). Mis-pairing an algorithm with the wrong training loop is a type error: `PPO + OffPolicyLoop`, `ARS + OnPolicyLoop`, `DQN + AlphaZeroLoop` all fail to typecheck.

> **Note on action-kind tags.** The `act` parameter of `AlgoSpec` carries a type-level *action-kind* tag (`'Discrete` / `'Continuous` / `'Masked` / `'MultiDiscrete` / `'Dict`) drawn from a promoted `data ActionKind = ...` enum. The same identifiers are reused as `ActionSpace` constructor names at the value level (`Discrete :: Int -> ActionSpace 'Discrete`, etc.) — type-level tags and value-level constructors share names by design, the way `'True` mirrors `True`.

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
  Masked         :: ActionSpace base -> ActionSpace 'Masked   -- legal-action mask injected at step
```

`MaskablePPO` and `AlphaZero` both consume `'Masked` action spaces. The mask is supplied by an additional `Env.envLegalMoves :: Obs -> Mask` field on `Env` for any environment that opts into masked actions.

Env *wrappers* are pure `Env -> Env` transformations: `clipReward`, `normaliseObservations`, `frameStack`, `noopReset`, `timeLimit`, `rewardShaper`. They compose via function composition; no class hierarchy.

## Vectorised environments (VecEnv)

Two implementations behind one type, mirroring SB3's `DummyVecEnv` / `SubprocVecEnv`:

```haskell
data VecEnv obs act
  = Sync   { syncEnvs     :: [Env obs act] }                     -- single-threaded N envs
  | Async  { asyncWorkers :: WorkerPool (Env obs act) }           -- N OS processes / threads
                                                                 -- (Dhall tag tokens match: "Sync" / "Async")
```

The per-env RNG seed is derived deterministically by `splitSeed masterSeed envIndex`, where `splitSeed :: Seed -> Word64 -> Seed` is the canonical seed-splitter — internally, it folds `envIndex` into the master seed's splitmix64 state, returning a fresh independent stream. Worker count and scheduling never affect any individual env's RNG stream — only wall-clock changes.

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
  { capacity     :: Int                                    -- ring size (per shard; see below)
  , prioritised  :: Maybe PriorityConfig                   -- α, β, ε for PER
  , storage      :: PerWorkerShards (Transition obs act)   -- one ring per env-worker; canonical join at sample time
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

### Replay-buffer write discipline under `Async`

Multi-worker rollout collection cannot serialise writes into one shared ring without re-introducing wall-clock dependence (whichever worker's `envStep` finishes first writes first). jitML's discipline:

- **Per-worker shards.** Each env-worker writes to its own private ring sized at `capacity / numEnvs`. A worker's own write sequence is monotone in `(workerId, localStep)`; a worker never sees another worker's ring.
- **Canonical join at sample time.** `samplingSeed` seeds a draw over the shards: for each batch slot, pick `workerId = (sampleIndex `mod` numEnvs)` and within that worker draw `localStep ∈ [0, ring-fill)`. Both decisions are pure functions of `samplingSeed` and the shards' current fill levels — never of the wall-clock order in which workers wrote.
- **Determinism golden scope.** With per-worker shards + canonical join, the off-policy `(env, algo, seed, numEnvs)` tuple is bit-deterministic under both `Sync` and `Async` `VecEnv` variants. The PER `α/β` weights are computed against per-shard priorities; PER's sumtree is one-per-shard for the same reason.

The shard count is part of the resolved-Dhall hash; changing `numEnvs` defines a different experiment (it changes which transitions a given `samplingSeed` selects).

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
  = Categorical         { logits :: Tensor }
  | MaskedCategorical   { logits :: Tensor, mask :: BoolTensor }    -- −∞ on illegal indices before softmax
  | DiagGaussian        { mean :: Tensor, logStd :: Tensor }
  | SquashedGaussian    { mean :: Tensor, logStd :: Tensor }        -- tanh-squashed, used by SAC
  | Bernoulli           { logits :: Tensor }                        -- independent-multi-label (factorial Bernoulli), distinct from Categorical(2)
  | QuantileDistribution { quantiles :: Tensor }                    -- QR-DQN / TQC distributional head
  | GSDE                 { mu :: Tensor, sigma :: Tensor, latentState :: Tensor }  -- generalised State-Dependent Exploration

sample  :: ActionDistribution -> Seed -> Action
logProb :: ActionDistribution -> Action -> Tensor
entropy :: ActionDistribution -> Tensor
mode    :: ActionDistribution -> Action                       -- deterministic
```

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
-- On-policy loop (PPO, A2C, MaskablePPO, RecurrentPPO, TRPO)
data OnPolicyLoop = OnPolicyLoop
  { totalTimesteps :: Int
  , rolloutSteps   :: Int                                  -- collect this many transitions per update
  , nEpochs        :: Int                                  -- gradient epochs per update (ignored for TRPO)
  , miniBatchSize  :: Int
  , optimiserStep  :: OnPolicyOptimiserStep                 -- which inner-update routine to run
  , callbacks      :: Callback
  , logger         :: Logger
  }

-- The inner-update routine. PPO/A2C minimise the clipped/A2C surrogate by minibatch SGD;
-- TRPO replaces that with a natural-gradient step inside a KL trust region, computed by
-- conjugate-gradient on the Fisher–vector product and accepted by backtracking line search.
data OnPolicyOptimiserStep
  = MinibatchSGD                                            -- PPO, A2C, MaskablePPO, RecurrentPPO
  | NaturalGradientTrustRegion                              -- TRPO: CG iterations + backtracking line search
      { cgIters      :: Int
      , damping      :: Double
      , maxKL        :: Double
      , backtrackMax :: Int
      , backtrackC   :: Double
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

-- Black-box loop (ARS)
data BlackBoxLoop = BlackBoxLoop
  { totalTimesteps   :: Int
  , perturbations    :: Int                                  -- ARS: paired ± perturbations per update
  , topElite         :: Int                                  -- ARS: keep best-K perturbations
  , noiseStd         :: Double
  , callbacks        :: Callback
  , logger           :: Logger
  }

-- Self-play loop (AlphaZero); full definition under [AlphaZero-style self-play](#alphazero-style-self-play)
data AlphaZeroLoop = AlphaZeroLoop { ... }

-- The actual driver; LoopFor is a type family:
--   LoopFor 'OnPolicy  = OnPolicyLoop
--   LoopFor 'OffPolicy = OffPolicyLoop
--   LoopFor 'BlackBox  = BlackBoxLoop
--   LoopFor 'SelfPlay  = AlphaZeroLoop
learn ::
  AlgoSpec c obs act ->
  Env obs act ->
  LoopFor c ->
  Seed ->
  IO (TrainedPolicy obs act, TrainingResult)
```

`PPO + OffPolicyLoop` does not typecheck. Neither does `ARS + OnPolicyLoop`, `DQN + AlphaZeroLoop`, etc. Each on-policy / off-policy loop body decomposes into phases (collect → compute-advantages → optimise → evaluate → checkpoint), each implemented as a pure function over the typed buffers; the IO-effectful steps are env stepping and the checkpoint write to MinIO. The black-box and self-play loops have different phase structures, defined alongside their respective algorithms.

## Worked Dhall: PPO on CartPole

A concrete PPO algorithm config in Dhall, decoded into the `AlgoSpec 'OnPolicy` + `OnPolicyLoop` pair. This is the canonical CartPole experiment file, `experiments/cartpole-ppo.dhall`.

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
    , optimiserStep  = OnPolicyOptimiserStep.MinibatchSGD            -- PPO uses minibatch SGD; for TRPO this would be NaturalGradientTrustRegion { … }
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

The framing for this section is *"we're not reimplementing PyTorch."* The list below names genuine non-goals and what jitML uses instead.

- **Python class hierarchy** (`BaseAlgorithm` → `OnPolicyAlgorithm` → `PPO`). Replaced with ADTs + GADTs. Inheritance is not an idiomatic Haskell tool here.
- **Pickle-based save/load** (`model.save()` / `model.load()`). Replaced with Dhall-described configuration + MinIO-checkpointed weights, optimizer state, RNG state, buffer state, and normalisation stats. The full state is reconstructible from `(experiment.dhall, seed, checkpoint blob)`.
- **`gym.make()` env registry.** Replaced with explicit Dhall env declarations referencing typed envs in `src/JitML/Env/`. No global registry; no string-keyed env lookup.
- **PyTorch `DataParallel` / `DistributedDataParallel`.** jitML's distribution story is different: the daemon is single-node by design; multi-node distributed SGD is an explicit non-goal. Cross-substrate determinism is the headline distributed-execution property, not multi-GPU SGD.
- **The default multi-sink logger** that fans out to stdout, csv, log, and tensorboard simultaneously. Replaced with `Semigroup` composition over typed `Logger` and `Callback` values, so the developer states the fan-out explicitly.

Patterns we *do* borrow, contrary to "out of scope" language that earlier drafts of this section included: Atari-style env wrappers (`NoopResetEnv`, `FireResetEnv`, `MaxAndSkipEnv`, `WarpFrame`, `EpisodicLifeEnv`) live alongside the standard six wrappers and admit Atari envs whenever the canonical-env table chooses to populate one; gSDE is a first-class `ActionDistribution` variant; every SB3-contrib algorithm (TRPO, MaskablePPO, RecurrentPPO, QR-DQN, CrossQ, TQC, ARS) is a first-class `AlgoSpec` case in [RL algorithm catalog](#rl-algorithm-catalog).

---

# RL algorithm catalog

Reproduce the entire **stable-baselines3** family — core and contrib — as first-class `AlgoSpec` cases, plus AlphaZero-style self-play. Each row is a typed crosswalk into [RL framework primitives](#rl-framework-primitives) — `Class` names the `AlgoSpec` index, `Loop` names the training-loop variant, `Buffer` names the buffer composition, `Distribution` names the action-distribution variant.

| Algorithm | Class | Loop | Buffer | Distribution | Notes |
|---|---|---|---|---|---|
| PPO | `OnPolicy` | `OnPolicyLoop` | `RolloutBuffer` + GAE | `Categorical` / `DiagGaussian` | canonical baseline |
| A2C | `OnPolicy` | `OnPolicyLoop` | `RolloutBuffer` + GAE | `Categorical` / `DiagGaussian` | synchronous A3C variant |
| TRPO | `OnPolicy` | `OnPolicyLoop` with `optimiserStep = NaturalGradientTrustRegion` | `RolloutBuffer` + GAE | `Categorical` / `DiagGaussian` | trust-region natural gradient; the loop is shared with PPO/A2C but the inner update is CG + line search rather than minibatch SGD |
| MaskablePPO | `OnPolicy` | `OnPolicyLoop` | `RolloutBuffer` + GAE | `MaskedCategorical` | for envs with illegal-action masking (Connect 4 et al.) |
| RecurrentPPO | `OnPolicy` | `OnPolicyLoop` + `RecurrentState` | `RolloutBuffer` (sequence-batched) | `Categorical` / `DiagGaussian` | LSTM / GRU policy |
| DQN | `OffPolicy` | `OffPolicyLoop` | `ReplayBuffer` + `TargetNetwork` (hard) | ε-greedy over Q-net | classic value-based |
| QR-DQN | `OffPolicy` | `OffPolicyLoop` | `ReplayBuffer` + `TargetNetwork` (hard) | `QuantileDistribution` | distributional value learning |
| DDPG | `OffPolicy` | `OffPolicyLoop` | `ReplayBuffer` + `TargetNetwork` (soft) + `ActionNoise` | deterministic policy + noise | continuous control |
| TD3 | `OffPolicy` | `OffPolicyLoop` | `ReplayBuffer` + 2× `TargetNetwork` + `ActionNoise` | deterministic policy + noise | DDPG with twin critics + delayed updates |
| SAC | `OffPolicy` | `OffPolicyLoop` | `ReplayBuffer` + 2× `TargetNetwork` | `SquashedGaussian` | headline off-policy continuous-control; `AutoEntropy` |
| CrossQ | `OffPolicy` | `OffPolicyLoop` | `ReplayBuffer` + BatchRenorm | `SquashedGaussian` | sample-efficient SAC variant |
| TQC | `OffPolicy` | `OffPolicyLoop` | `ReplayBuffer` + K× `TargetNetwork` + quantile head | `SquashedGaussian` | truncated quantile critics |
| ARS | `BlackBox` | `BlackBoxLoop` | (none — perturbation evaluation) | deterministic linear policy + noise | augmented random search |
| HER | *meta* | (composes onto any off-policy) | `HerWrapper ReplayBuffer` | inherits | goal-conditioned replay buffer |
| AlphaZero | `SelfPlay` | `AlphaZeroLoop` | `SelfPlayBuffer` + MCTS | softmax(visits) + scalar value head | two-player perfect-info; see [AlphaZero-style self-play](#alphazero-style-self-play) |

Retired SB3 algorithms (`ACER`, `ACKTR`, `GAIL`) are not adopted.

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
| MountainCar-v0 | DQN[^mc-dqn] | TBD | TBD |
| Pendulum-v1 | SAC | TBD | TBD |
| Pendulum-v1 | TD3 | TBD | TBD |
| LunarLander-v2 | PPO | TBD | TBD |
| LunarLander-v2 | DQN | TBD | TBD |
| LunarLander-v2 | SAC | TBD | TBD |

The convergence golden is the load-bearing test; the trajectory-determinism golden runs every commit; the convergence golden runs nightly or on labeled CI only.

[^mc-dqn]: Vanilla DQN does not converge on MountainCar-v0 — the reward is `-1` per step until reaching a goal that random exploration almost never finds, so the Bellman target is uninformative. The jitML convergence golden for this row uses DQN augmented with a *count-based intrinsic-motivation bonus* over a coarse position-velocity tile coding (Bellemare et al., "Unifying Count-Based Exploration", 2016). This is encoded as a typed wrapper on `Env` in `src/JitML/RL/Exploration.hs` and named explicitly in the row's experiment Dhall — the row does not claim a target reachable by *unmodified* DQN.

---

# AlphaZero-style self-play and persistent MCTS state

The RL surface as a whole is specified earlier in this README — see [RL framework primitives](#rl-framework-primitives) for the type-level taxonomy (algorithm GADT, policy/env types, buffer kinds, schedules, distributions, action noise, callbacks, evaluator, training loops), [RL algorithm catalog](#rl-algorithm-catalog) for the per-algorithm crosswalk, [Canonical reinforcement learning environments](#canonical-reinforcement-learning-environments) for the env list, and [Golden tests for RL](#golden-tests-for-rl) for the determinism / convergence / replay golden stack. This section adds the pieces that don't fit those tables: the AlphaZero-style self-play loop and the persistent-MCTS-state contract.

## Persistent MCTS state

Monte Carlo exploration caches are preserved between moves of the same game. The cache is a deterministic function of `(seed, episode-history)` — re-executing the episode under the same seed reconstructs the cache exactly, which is what makes MCTS replayable rather than merely stochastically reproducible. The cache is checkpointed alongside the policy via the `ExplorationCache` checkpoint part — see [Split-blob layout](#split-blob-layout).

## AlphaZero-style self-play

jitML's RL stack is a strict superset of stable-baselines3's catalog; it also hosts the AlphaZero family — two-player perfect-information games with MCTS-guided self-play and a two-headed policy/value ANN. The AlphaZero loop reuses the buffer-and-logger primitives from [RL framework primitives](#rl-framework-primitives); the only new pieces are the game type class, the MCTS-guided self-play generator, and the dual-headed network.

### Perfect-information game type class

```haskell
data PerfectInfoGame s a = PerfectInfoGame
  { gameInitial    :: s
  , gameLegalMoves :: s -> ActionMask a
  , gameApply      :: s -> a -> s
  , gameTerminal   :: s -> Maybe Outcome             -- Win Player | Draw | Nothing
  , gameToPlay     :: s -> Player
  , gameCanonical  :: s -> CanonicalForm s           -- player-to-move-normalised view
  , gameEncode     :: CanonicalForm s -> Tensor      -- network input
  , gameSymmetries :: CanonicalForm s -> [(CanonicalForm s, Perm a)]    -- e.g. Connect 4 mirror
  }
```

Connect 4 is the canonical instance. The same type class also instantiates Tic-Tac-Toe, Othello, Gomoku, and Hex; see [Canonical adversarial games](#canonical-adversarial-games).

### Two-headed network

The `Policy` shape from [RL framework primitives](#rl-framework-primitives), specialised:

```haskell
data AlphaZeroNet s a = AlphaZeroNet
  { trunk      :: Network (Encoded s) Features       -- ResNet-style backbone canonical
  , policyHead :: Network Features (Logits a)        -- softmax over legal actions
  , valueHead  :: Network Features Scalar            -- ∈ [-1, +1] from player-to-move view
  }
```

The trunk is **any** composition of the SL [Layer catalog](#layer-catalog) primitives via Dhall — typically a stack of `BasicBlock` plus `BatchNorm`, but the user may choose `BottleneckBlock`, attention-augmented trunks, etc.

### MCTS-guided self-play loop

```haskell
data AlphaZeroLoop = AlphaZeroLoop
  { totalIterations     :: Int                       -- outer (self-play, train, arena) cycles
  , selfPlayGames       :: Int                       -- games per iteration
  , mctsSimsPerMove     :: Int                       -- e.g. 800 for Connect 4
  , temperatureSchedule :: Schedule Double           -- 1.0 for first N moves, 0.0 after
  , dirichletAlpha      :: Double                    -- root exploration α
  , dirichletEpsilon    :: Double                    -- root noise mixing weight
  , cpuct               :: Double                    -- PUCT exploration constant
  , trainingBatchSize   :: Int
  , trainingEpochs      :: Int
  , replayBufferGames   :: Int                       -- last-K games retained
  , arenaConfig         :: ArenaConfig               -- gating new vs old net
  , callbacks           :: Callback
  , logger              :: Logger
  }
```

### Deterministic stochasticity

Root Dirichlet noise is drawn from a seed derived per game via `splitSeed masterSeed gameIndex` (same canonical splitter used by VecEnv — see [Vectorised environments (VecEnv)](#vectorised-environments-vecenv)). MCTS tie-breaking in argmax is by lowest action index; node expansion order is deterministic given seed. Same-substrate `(seed, net-state)` produces a bit-identical self-play game sequence.

### Self-play buffer

Triples `(canonicalState, mctsVisits, valueTarget)` plus all game symmetries (Connect 4's horizontal mirror is a free 2× data multiplier). The buffer is content-addressed and checkpointed exactly like the off-policy `ReplayBuffer` (see [Checkpoint object layout](#checkpoint-object-layout)).

### Arena gating

After each training iteration, the candidate net plays the incumbent for N games; promoted only if win rate ≥ threshold (e.g. 55%). This is the AlphaGo Zero gating policy (AlphaZero proper dropped it); jitML adopts it because it gives a stable regression target for the convergence golden.

### Borrowed engineering from the sibling MCTS project

The deterministic-search arc — replay-from-transcript, exploration-cache reproducibility, seed-split discipline — was developed for the sibling MCTS project. jitML's MCTS module exposes an API-compatible surface so the underlying engine could be shared at the package level later (decision deferred).

### Determinism contract

The trajectory-determinism golden from [Golden tests for RL](#golden-tests-for-rl) applies unchanged to AlphaZero self-play. The convergence golden becomes: ELO ≥ T against a fixed random baseline (and ≥ T' against a fixed depth-N alpha-beta baseline for Connect 4), with T and T' derived from `k=5` replicates per the [Threshold methodology](#threshold-methodology).

### Canonical adversarial games

| Game | Players | Board / state | Action space | Branching | Notes / golden anchor |
|---|---|---|---|---|---|
| Tic-Tac-Toe | 2 | 3×3 | `Masked Discrete(9)` | ≤ 9 | optimal play → draw; minimax-equivalence golden |
| Connect 4 | 2 | 6×7 (gravity) | `Masked Discrete(7)` | ≤ 7 | **canonical entry**; ELO vs random baseline; ELO vs depth-6 alpha-beta |
| Othello (Reversi) | 2 | 8×8 | `Masked Discrete(64)` | ~ 5–15 | ELO targets TBD |
| Gomoku-9x9 | 2 | 9×9 | `Masked Discrete(81)` | ≤ 81 | ELO targets TBD |
| Hex-7x7 | 2 | 7×7 hex | `Masked Discrete(49)` | ≤ 49 | ELO targets TBD |

Connect 4 is the canonical AlphaZero target; the others share the same `PerfectInfoGame` interface and self-play loop — switching games is a Dhall change, not a code change. Tic-Tac-Toe doubles as a unit-level golden: the game is solved by minimax, so a sufficiently-trained AlphaZero policy's argmax-visit move at every reachable state must lie in the minimax-optimal move set. (Raw visit *counts* are a function of `mctsSimsPerMove`, the PUCT exploration constant, the policy prior, and the Dirichlet root noise — those are not equal to minimax values; only the argmax over visits is.)

---

# Checkpointing

A checkpoint is an immutable deterministic snapshot of one point in training, RL, or hyperparameter-trial execution. It contains:

- model weights
- optimizer state
- RNG state
- replay buffers (RL)
- exploration caches (RL / MCTS)
- training metadata
- hardware compilation metadata

Persistence backend: MinIO bucket `jitml-checkpoints`, laid out per [Checkpoint object layout](#checkpoint-object-layout) and written under the [Concurrency model](#concurrency-model). Checkpoint replay is guaranteed deterministic; the [Replay-from-checkpoint golden](#golden-tests-for-rl) test enforces this through the test suite, not just by design statement.

## Split-blob layout

A checkpoint is **N + 1 content-addressed objects** in MinIO — not one monolithic blob:

| Part | Required for | Why separate |
|---|---|---|
| `weights.bin` (`.jmw1`) | always | inference-at-any-point reads only this part; downloading the optimizer state would double bandwidth for Adam/AdamW |
| `optimizer_state.bin` (`.jmw1`) | training & resume | rarely needed by readers; ~2× weights for Adam |
| `rng_state.bin` | always | tiny, but separately addressed so consecutive checkpoints dedup when only the step counter changes |
| `replay_buffer.bin` | off-policy RL | can dwarf the policy itself; never needed for inference |
| `exploration_cache.bin` | MCTS / AlphaZero-style RL | path-dependent state, see [Persistent MCTS state](#persistent-mcts-state) |
| `manifests/<sha256>` (CBOR) | always | names the SHAs above and carries lineage |

The manifest SHA is the canonical *checkpoint id*. It is the value carried by `CheckpointDone` Pulsar events, by RPC envelopes' `starting-snapshot` field, and by `--resume <checkpoint-id>` on the CLI.

## The dense weight blob format (`.jmw1`)

```
offset   field         type             notes
0        magic         4 bytes          "JMW1"
4        header_len    uint32 LE        size of CBOR header in bytes
8        header_cbor   bytes            CBOR canonical form (RFC 8949 §4.2.1)
8+H      payload       bytes            packed dense tensors, no padding, little-endian dtype-native
```

The CBOR header (canonical-form, keys sorted lexicographically by the byte string of their CBOR encoding — with shorter encodings sorting before longer encodings with a shared prefix, per RFC 8949 §4.2.1 (deterministic encoding)) decodes into:

```haskell
-- Hash32 ≡ raw 32-byte SHA-256 digest (ByteString of length 32).
type Hash32 = ByteString

data JmwHeader = JmwHeader
  { jmwExperimentHash :: !Hash32     -- sha256(resolved-dhall)
  , jmwGraphShapeHash :: !Hash32     -- sha256 over canonicalised (path,dtype,shape) list — locked at experiment start
  , jmwStep           :: !Word64
  , jmwEpoch          :: !Word64
  , jmwSubstrate      :: !Substrate  -- substrate that produced these bytes (for cross-substrate equality tests)
  , jmwDtypeMap       :: !DtypeMap   -- self-contained enum-to-byte mapping
  , jmwTensors        :: ![TensorEntry]
                                     -- canonical-ordered by `path` ascending bytewise
                                     -- entry = (path :: Text, dtype :: Dtype, shape :: [Word32],
                                     --          offset :: Word64, byte_length :: Word64, sha256 :: Hash32)
  }

data Dtype = F32 | F64 | C32 | C64 | I32 | I64 | U8 | BF16
```

The payload is contiguous, little-endian, dtype-native, no padding. Tensors appear in `jmwTensors` order — ascending bytewise on the `path` field. The Dhall locks the graph, the graph determines the path set, sorted-by-path locks the order. Readers `memcpy` each tensor into a substrate-appropriate aligned buffer; alignment is an in-memory concern and never leaks into the persistence format.

**Format choices, justified:**

- **CBOR canonical form** (not JSON, not SafeTensors' JSON header, not protobuf). RFC 8949 §4.2.1 specifies an unambiguous canonical encoding — sorted keys, shortest integer encoding, no indefinite-length items. Haskell's `cborg`/`serialise` libraries implement it directly. JSON has no canonical-encoding requirement (whitespace, key order, integer/float ambiguity, NaN/Infinity); SafeTensors inherits all of that. Protobuf has no canonical-encoding guarantee at all (unknown-field ordering, map ordering, default-value emission all vary). Protobuf is correct for the *wire* (Pulsar topics), but the wire isn't trying to be SHA-stable.
- **Dense, little-endian, packed tensors with no padding.** "Same logical state ⇒ same bytes" requires the byte layout be a pure function of `(tensor_ordering, dtype_layout, raw_values)`. Every supported substrate (Apple ARM, x86_64, NVIDIA) is little-endian; we still spec it.
- **A SafeTensors *exporter* is fine later** (`jitml internal export-safetensors`) for interop with HuggingFace tooling. It is not the source-of-truth format.

## The manifest

`manifests/<sha>` is a CBOR canonical-form object:

```haskell
data CheckpointManifest = CheckpointManifest
  { cmExperimentHash :: !Hash32
  , cmTrialHash      :: !(Maybe Hash32)
  , cmStep           :: !Word64
  , cmEpoch          :: !Word64
  , cmWallClockNs    :: !Word64       -- monotonic, recorded for telemetry, NEVER part of any hash
  , cmSubstrate      :: !Substrate
  , cmSchemaVersion  :: !Word32
  , cmParts          :: ![CheckpointPart]    -- canonical-ordered by role
  , cmMetrics        :: ![(Text, Double)]    -- metric snapshot at this checkpoint (sorted by metric name)
  , cmParentManifest :: !(Maybe Hash32)      -- lineage chain; set on resume
  }

data CheckpointPart = CheckpointPart
  { cpRole    :: !PartRole   -- Weights | OptimizerState | RngState | ReplayBuffer | ExplorationCache
  , cpBlobSha :: !Hash32
  , cpBytes   :: !Word64
  , cpFormat  :: !PartFormat -- Jmw1 | RawBytes
  }
```

`sha256(canonical_cbor(manifest))` *is* the manifest's address. The pointers' bodies are 32-byte SHAs of manifests; the manifest is the deterministic identity of the checkpoint.

## Bit-determinism contract

For two runs on the same substrate, `sha256(weights.bin)` is byte-identical when seed, resolved Dhall, step, data ordering, kernel reduction order, RNG state, and optimizer state all agree. This is the same-substrate-equality contract declared earlier in the README, now *checkable by SHA-equality* rather than by tolerant numeric comparison.

Cross-substrate, the weight blobs are not byte-equal — float reductions reassociate across vendor libraries, transcendentals (`exp`, `log`, `sqrt`, `tanh`) differ between cuDNN/Metal/oneDNN, and the drift compounds through forward + backward. The [`jitml-cross-backend`](#test-suite-stanzas) stanza measures per-tensor max-abs-delta against a committed tolerance band — see [Cross-substrate tolerance methodology](#cross-substrate-tolerance-methodology) below — rather than asserting byte equality.

### Cross-substrate tolerance methodology

ε is established by the same `k=5` replicate methodology that pins SL/RL convergence targets (see [Threshold methodology](#threshold-methodology)). For each canonical `(dataset, model)` and `(env, algo)` pair, the reference host runs `k=5` same-substrate replicates per backend; per-tensor `max-abs(deltaᵢⱼ)` is computed across every substrate pair `(cpu↔cuda)` and `(cpu↔metal)`. The 95th-percentile delta across the replicates is stored as a committed fixture under `test/golden/cross-backend/<pair>/<tensor>.json`. The fixture is byte-deterministic per doctrine §Golden Tests — no timestamps, no random IDs, no nondeterministic ordering — and the cross-backend stanza asserts each tensor's drift falls within its committed band. Widening a band requires explaining the cause in the PR description; tightening is a free win.

## No Postgres on jitML's data path

jitML keeps no derived index in Postgres. Every fact about a training run, a hyperparameter trial, or a lineage relationship is encoded **inside the MinIO manifests themselves** — `cmParentManifest` carries lineage, `pointers/latest` and `pointers/best/<metric>` index by experiment, and the `jitml-trials` bucket holds trial transcripts keyed on `sha256(resolved-dhall || trial-seed)`. Queries that would naturally be SQL (e.g. "every manifest produced by experiment X past step Y") are answered by `mc ls`-style listings or by `jitml inspect`, both of which read MinIO directly. The cluster may host Postgres for third-party services (Harbor's metadata, optional Grafana history), but jitML itself never writes to it — its durable contracts are MinIO and Pulsar only.

## Inference-only read path

The inference-at-any-point primitive lives in `src/JitML/Storage/Inference.hs` and reads *only* the `Weights` part of a manifest. The CLI surface is the `Inference` constructor of the top-level `Command` (see [CLI command topology, typed](#cli-command-topology-typed)):

```bash
jitml inference run experiments/mnist-mlp.dhall --checkpoint latest
jitml inference run experiments/mnist-mlp.dhall --checkpoint best/acc
jitml inference run experiments/mnist-mlp.dhall --checkpoint <manifest-sha256>
jitml inference run experiments/mnist-mlp.dhall --trial <trial-hash> --checkpoint latest
```

Each variant resolves to one immutable `manifests/<sha>` object and one `blobs/<weight-sha>` object. Training and HPO trials can be writing concurrently to the same `<experiment-hash>` prefix; the inference reader is unaffected.

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

```mermaid
flowchart TD
    dhall[.dhall config]
    graph[typed graph builder]
    ir[backend codegen IR]
    metal[Swift / Metal]
    cuda[CUDA]
    onednn[oneDNN]
    native[native compilation]
    ffi[Haskell FFI layer]
    run[deterministic run]
    dhall --> graph --> ir
    ir --> metal
    ir --> cuda
    ir --> onednn
    metal --> native
    cuda --> native
    onednn --> native
    native --> ffi --> run
```

---

# PureScript frontend

Source at `./web/`; spago + `purs` + esbuild bundle to `./web/dist/app.js`. UI framework: **Halogen** (mature reactive PureScript framework, signals model fits live-events well).

## Generated contracts

`jitml docs generate purs-contracts` emits `./web/src/Generated/Contracts.purs` from Haskell-owned browser-contract ADTs in `src/JitML/Web/Contracts.hs` via `purescript-bridge`. It is one entry in the `GeneratedSectionRule` registry (see [Generated documentation flow](#generated-documentation-flow)) and is paired with `jitml docs check purs-contracts`. The Pulsar event protobuf-derived types are included so live event streams are typed end-to-end.

## Backend integration

- **REST + JSON** for one-shot operations (`/api/experiments`, `/api/checkpoints`, `/api/runs`, `/api/trials`).
- **WebSocket** for live event streams: the frontend connects to `/api/ws` (served by `jitml-demo`), which in turn subscribes to `training.event.<mode>` / `rl.event.<mode>` / `tune.event.<mode>` on Pulsar and proxies the relevant subset to the connected client. The frontend never connects to Pulsar directly — Envoy is the single localhost socket.

## Stance

The PureScript frontend is not a metrics dashboard with passive read-only panes; it is an interactive lab for every workload jitML supports. Training runs are started, paused, resumed, and stopped from the UI; inference is invoked against any checkpoint by direct human input — drawing, uploading, or playing. Every interactive surface is covered end-to-end by Playwright in [`jitml-e2e`](#test-suite-stanzas).

## Panels

- **Run list.** All experiments + runs from MinIO `jitml-checkpoints`, with status, lineage tree, and one-click "branch a new run from this checkpoint."
- **Live training panel.** Loss / validation curves, throughput sparkline, GPU-util gauge — animated from `training.event.<mode>` over WebSocket. Embeds the TensorBoard iframe at `/tensorboard/?run=<experiment-hash>` in a side tab. **Interactive controls:** start a new run from any committed experiment Dhall, pause/resume the current run, stop with optional final-checkpoint flush, change `LiveConfig` knobs (LR schedule, log level, retry budgets) and apply via SIGHUP. The control surface publishes `training.command.<mode>` envelopes; the daemon responds with `training.event.<mode>`.
- **RL panel.** Episode-reward distribution (live), env render preview (canvas-rendered from `EpisodeFrame` events), replay-buffer fill, exploration rate. **Interactive controls:** start / pause / stop, swap policy, force-evaluate, scrub through a recorded trajectory.
- **Hyperparameter panel.** Pareto frontier (live; populated by NSGA-II for multi-objective sweeps), trial-by-trial heatmap, per-axis (sampler / scheduler / pruner) state, PBT population view + hyperparameter-mutation lineage tree, trial detail drill-down. **Interactive controls:** launch a sweep, kill an individual trial, pin a trial as the "promote" candidate.
- **MNIST handwriting panel.** A canvas component the user draws on with mouse or touchpad. The drawing is downsampled to 28×28, normalised, and fired at `inference.request.<mode>` against the configured MNIST checkpoint. The result panel shows the predicted class plus the full softmax distribution as a bar chart, updated live as the user draws (re-inference on stroke-end). The checkpoint is configurable to any committed MNIST run; the user can flip between the shallow-MLP run and the LeNet-5 CNN run to compare predictions side by side.
- **Image-recognition panel (CIFAR / Tiny ImageNet).** Drag-and-drop or file-picker upload. The frontend center-crops + resizes to the model's input size client-side, posts to `/api/inference/image`, and shows top-K predictions with class probabilities. A "swap checkpoint" dropdown switches between ResNet-20 (CIFAR-10), Wide ResNet-28-10 (CIFAR-100), and ResNet-50 (Tiny ImageNet) without page reload.
- **Game-play panel (Connect 4 et al.).** An interactive board for each game in [Canonical adversarial games](#canonical-adversarial-games). Click-to-drop on Connect 4; click-to-place on Tic-Tac-Toe / Othello / Gomoku / Hex. The user plays against the AlphaZero policy at a chosen checkpoint, with sliders for `mctsSimsPerMove` and temperature. A side pane renders the MCTS visit distribution (which the user can compare against the policy head's raw logits), the value head's evaluation of the current position, and a one-click "request engine analysis" that runs a deeper search at temperature 0. A "swap opponent" dropdown pits the latest checkpoint against an older one — the arena gating from [AlphaZero-style self-play](#alphazero-style-self-play) made interactive.
- **Cluster panel.** Embedded Grafana iframe at `/grafana` + the route table from `cluster status`.
- **Inference panel.** Catch-all for non-canvas, non-image, non-game inference — paste a tensor as JSON, see the output tensor.

## REST surfaces for interactive panels

Every interactive panel maps to a small REST + WebSocket pair, all under `/api` and all WebSocket fan-in on `/api/ws` (no new top-level localhost routes):

| Surface | HTTP | Daemon contract |
|---|---|---|
| Training control | `POST /api/runs/<run-id>/command` | publishes `training.command.<mode>` on Pulsar |
| MNIST handwriting | `POST /api/inference/mnist` (28×28 tensor as base64 PNG or JSON array) | publishes `inference.request.<mode>`; result on `inference.result.<mode>` |
| Image upload | `POST /api/inference/image` (multipart form) | same flow |
| Game move | `POST /api/games/<game-id>/move` (`{player, move}`) | engine move via `inference.result.<mode>` |

## Tests

`purescript-spec` unit tests in `./web/test/`; Playwright E2E in `./web/playwright/` against the real Envoy route surface. The E2E suite is the `jitml-e2e` cabal stanza.

## Deployment

- **Linux substrates:** the bundle is built into the substrate image at image-build time; `jitml-demo` workload serves it via Helm.
- **Apple Silicon:** the bundle is built host-native, then mounted into the `jitml:local` image when `jitml bootstrap --apple-silicon` builds and uploads it to Harbor. (The same image is used for the in-cluster `jitml-service` pod that runs with `inferenceMode = ForwardToHost` — Apple builds `jitml:local` for cluster-resident services even though host-native execution uses the separate `./.build/jitml` binary built directly via ghcup. Apple uses *one* image, same as Linux; the substrate-table "Container shape: partial" refers to where kernels execute, not to how many images exist.) The host daemon publishes events to cluster Pulsar; the routed demo loads in the browser at `127.0.0.1:<edge-port>/`.

---

# Test-suite stanzas

**Doctrine coverage.** Every one of the seven test categories in [`HASKELL_CLI_TOOL.md` §Test Categories](HASKELL_CLI_TOOL.md#test-categories) is exercised by a jitML stanza — no category omitted, no parallel test surface outside this list:

| Doctrine category | jitML stanzas |
|---|---|
| Pure Logic | `jitml-unit` |
| Parser | `jitml-unit` |
| Property | `jitml-unit` |
| Golden | `jitml-unit` |
| Integration | `jitml-integration`, `jitml-sl-canonicals`, `jitml-rl-canonicals`, `jitml-hyperparameter`, `jitml-cross-backend` (the four `*-canonicals` and the HPO stanza are project-specific Integration per doctrine §Test Organization → project-specific stanzas) |
| Daemon Lifecycle | `jitml-daemon-lifecycle` |
| Pulumi-Orchestrated Infrastructure | `jitml-e2e` |

Plus the doctrine-mandated style stanza (per §Style as a Cabal test-suite): `jitml-haskell-style`, with `jitml-purescript-style` as the project-specific Lint extension.

Per doctrine §Test Organization, one cabal `test-suite` stanza per tier. The **Doctrine category** column below mirrors the matrix above per stanza. The **Delegated by** column names the `TestCommand` constructor that targets the stanza. Per doctrine, the first four categories (Pure / Parser / Property / Golden) share the single `jitml-unit` stanza.

| Stanza | Doctrine category | Delegated by | Scope |
|---|---|---|---|
| `jitml-unit` | Pure Logic + Parser + Property + Golden | `TestUnit` | CommandSpec golden, Dhall round-trip, autodiff property, optimizer-step property, route-registry render golden, Grafana-dashboard render golden, RNG mixer property, trajectory-determinism RL goldens |
| `jitml-integration` | Integration | `TestIntegration` | `jitml` binary across all substrates; checkpoint round-trip; resume semantics; Dhall→typed-record decode; per-substrate determinism |
| `jitml-sl-canonicals` | Integration (project-specific) | `TestSL` | the eleven SL `(dataset, model)` pairs from [Canonical supervised learning problems](#canonical-supervised-learning-problems) |
| `jitml-rl-canonicals` | Integration (project-specific) | `TestRL` | the RL target matrix, forms (2) and (3) |
| `jitml-hyperparameter` | Integration (project-specific) | `TestHyperparameter` | per-sampler reproducibility (Grid, Random, Sobol, TPE, GP-BO, GA, NSGA-II, (μ,λ)-ES, CMA-ES, PBT), per-scheduler reproducibility (Hyperband / ASHA bracket scheduling), per-pruner reproducibility (median / percentile), resume-from-partial-sweep equality |
| `jitml-cross-backend` | Integration (project-specific) | `TestCrossBackend` | cohort `(cpu, cuda)` and `(cpu, metal)` on the SL canon; tolerance from measured float-accumulation drift |
| `jitml-daemon-lifecycle` | Daemon Lifecycle | `TestDaemonLifecycle` | spawn `jitml service`, poll `/readyz`, exercise Pulsar protocol, SIGTERM, assert graceful drain |
| `jitml-e2e` | Pulumi-Orchestrated Infrastructure | `TestE2E` | Pulumi-orchestrated ephemeral Kind stack + Playwright against real Envoy routes; six cohorts — see [E2E cohorts](#e2e-cohorts) below. |
| `jitml-haskell-style` | doctrine-mandated style stanza (§Style as a Cabal test-suite) | `TestHaskellStyle` | `fourmolu --mode check`, `hlint`, `cabal format` round-trip |
| `jitml-purescript-style` | Lint (project-specific) | `TestPureScriptStyle` | PureScript `purs format` round-trip + `purescript-spec` smoke tests |

`TestAll` fans out to every stanza above (via phase 1 of `jitml test all`). Lint runs inside `cabal test` via the `jitml-haskell-style` stanza, not as a separate `test` subcommand — `jitml lint all --check` is the lint surface.

Notes on the mapping:

- jitML's project-specific stanzas (`sl-canonicals`, `rl-canonicals`, `hyperparameter`, `cross-backend`, `purescript-style`) are **extensions of the Integration / Lint categories under §Test Organization's project-specific allowance**, not parallel test systems.
- Every stanza uses `type: exitcode-stdio-1.0` (doctrine §Standard Testing Stack): the test binary signals pass/fail by exit code, which is the only contract Cabal needs to schedule and aggregate stanzas in parallel. Each stanza's `main-is` is a thin `Main.hs` calling into a library module where the tests live.
- Single `tasty` trees across stanzas are forbidden (doctrine §Test Organization): separate stanzas give Cabal-native parallelism, let CI and developers target one tier (`cabal test jitml-unit`), and isolate dependency creep so heavy integration deps do not leak into the unit suite.

**No opt-out flags.** No developer mode skips `jitml-e2e` or any other stanza; Pulumi-orchestrated infrastructure is always-on, every `cabal test` run, with always-teardown via `bracket`. Doctrine §Test Organization → project-specific stanzas forbids parallel developer workflows that bypass cloud-backed tests.

### E2E cohorts

Per doctrine §Pulumi-Orchestrated Infrastructure Tests, Pulumi (program at `infra/pulumi/`) owns the lifecycle of an **ephemeral** Kind stack — unique stack name per run, aggressive resource tagging, `pulumi up` → run tests → `pulumi destroy` → `pulumi stack rm`. The e2e cluster is **distinct** from the developer's local bootstrap Kind: different stack name, different lifetime; the e2e teardown never touches the dev cluster. Always-teardown via `bracket`. Playwright drives the demo surface end-to-end against the real Envoy routes. Six cohorts:

1. **Training control.** Start a run from a committed Dhall, observe live metrics on `/api/ws`, pause, resume, stop, assert checkpoint flush.
2. **MNIST handwriting.** Navigate to the MNIST panel, simulate a touchpad stroke for each of the 10 digits via Playwright's pointer events, assert predicted class matches in ≥ 9/10 strokes.
3. **Image upload.** Upload three fixture images per dataset (CIFAR-10, CIFAR-100, Tiny ImageNet) via Playwright's `setInputFiles`, assert top-1 / top-5 inclusion.
4. **Game-play.** Drive a full Connect 4 game where Playwright plays a fixed-seed opponent sequence against the AlphaZero policy at a pinned checkpoint, assert the engine's response sequence matches a committed transcript fixture.
5. **TensorBoard / Grafana navigation.** Assert iframes load and the checkpoint markers from [TensorBoard event storage / Cross-link to checkpoint manifests](#cross-link-to-checkpoint-manifests) appear.
6. **Hyperparameter sweep.** Launch a small Sobol sweep from the UI, observe live Pareto-frontier updates, kill a trial, assert state propagates.

### Golden targets

Per doctrine §Plan / Apply and §Generated Artifacts, the canonical goldens are:

- **doctrine-canonical** — `jitml --help` (every command and subcommand path), `jitml commands --tree`, `jitml commands --json`, generated Markdown docs, generated manpages.
- **plan-render goldens** — the rendered Plan for every Plan/Apply command, reproduced via `--dry-run` and compared exact-string against a committed file: `bootstrap`, `cluster up`, `train`, `eval`, `tune`, `rl train`, `test all`.
- **jitML-specific** — route-table render from `src/JitML/Routes.hs`, Grafana-dashboard render from `src/JitML/Observability/Grafana.hs`, PureScript contracts (`web/src/Generated/Contracts.purs`), proto-derived Haskell schemas, the report-card summary block from [`jitml test all`](#jitml-test-all).

Golden outputs are deterministic. Renderers are pure; timestamps, random IDs, locale-dependent ordering, and terminal-width-dependent wrapping are forbidden in golden content per doctrine §Generated Artifacts.

### Per-stanza invocations

A developer or CI can target one tier directly:

```bash
cabal test jitml-unit
cabal test jitml-daemon-lifecycle
cabal test                          # every stanza — equivalent to phase 1 of `jitml test all`
```

`jitml test <stanza>` is sugar over `cabal test jitml-<stanza>`. The authoritative stanza list lives in `jitml.cabal`.

### Lint matrix

Per doctrine §Lint, Format, and Code-Quality Stack and §Standard Testing Stack, `lint *` is the surface for hand-written sources (paired with `docs *` for generated artifacts; see [Generated documentation flow](#generated-documentation-flow)). Each row below maps a `LintCommand` constructor to the tool family it gates. Execution lives inside `cabal test` via the `jitml-haskell-style` and `jitml-purescript-style` stanzas per doctrine §Style as a Cabal test-suite.

| Target | Tools | Covered scope |
|---|---|---|
| `lint files` | repo-internal | whitespace, trailing newlines, forbidden paths, tracked-generated drift |
| `lint docs` | repo-internal | documentation metadata, relative links, forbidden stale commands, and hand-written documentation hygiene |
| `lint proto` | `protoc` round-trip | wire schemas in `proto/jitml/` |
| `lint chart` | repo-internal | Helm structural invariants (no dynamic provisioning, every PV with explicit `claimRef`, no freestanding PVCs) |
| `lint haskell` | `fourmolu --mode check` + `hlint` + `cabal format` round-trip | per doctrine §Lint stack |
| `lint purescript` | `purs format` round-trip + `purescript-spec` smoke | PureScript sources |
| `lint all` | aggregate | every row above, then `cabal build all` |

Every entry has a paired `--write` mode per doctrine §Paired check and write semantics; `--write` fixes what is auto-fixable and exits `3` when there is nothing to do.

---

# `jitml test all`

The doctrine-mandatory canonical test command. `cabal test` is the real test runner; `jitml test all` is a thin wrapper that runs `cabal test` and then layers a report-card workload and a summary block on top. Three phases:

1. **Delegates to `cabal test`.** Runs every `test-suite` stanza above — including `jitml-haskell-style`, which is how lint and style enforcement participate in the canonical suite (not as a separate phase).
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
                                           jitml-daemon-lifecycle,
                                           jitml-haskell-style, jitml-purescript-style,
                                           jitml-e2e)
```

`jitml test all` is a Plan/Apply command per doctrine §Plan / Apply. `--dry-run` prints the rendered plan and exits 0. The summary block is rendered by a pure function over a typed `ReportCard` value, golden-testable with sentinel placeholders.

The report-card surfaces a representative subset of the SL and RL canonical pairs (chosen to fit one screen). The full matrices are exercised by `cabal test jitml-sl-canonicals` and `cabal test jitml-rl-canonicals` — see [Canonical supervised learning problems](#canonical-supervised-learning-problems) and [Golden tests for RL](#golden-tests-for-rl).

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
./bootstrap/apple-silicon.sh                                    # stage-0 gates, builds ./.build/jitml, delegates bootstrap
./.build/jitml cluster status                                   # prints edge port
./.build/jitml train experiments/mnist-mlp.dhall --substrate apple-silicon --seed 42

# Linux CPU
./bootstrap/linux-cpu.sh                                        # docker gate, then compose-run bootstrap
docker compose run --rm jitml jitml train \
  experiments/mnist-mlp.dhall --substrate linux-cpu --seed 42

# Linux CUDA
./bootstrap/linux-cuda.sh                                       # docker + NVIDIA runtime/device gates, then compose-run bootstrap
docker compose run --rm jitml jitml train \
  experiments/cifar10-resnet.dhall --substrate linux-cuda --seed 42
```

After bootstrap, the full surface lives at one URL — `127.0.0.1:<edge-port>/` — with the demo at `/`, TensorBoard at `/tensorboard`, Grafana at `/grafana`, Prometheus at `/prometheus`, Harbor at `/harbor`, MinIO at `/minio/console`, and Pulsar at `/pulsar/admin`.

---

# Repository layout (target)

Per doctrine §Project Structure, jitML is **library-first**: nearly all logic lives in `src/JitML/`, not `app/`, so it is importable by tests and reusable by sibling binaries (`jitml-demo` shares the library with `jitml`). `app/Main.hs` and `app/Demo.hs` are six-line shims into `App.main`.

```
jitML/
  app/                          -- Haskell CLI entry points (thin shims only)
    Main.hs                     -- jitml (control plane + daemon)
    Demo.hs                     -- jitml-demo (HTTP server for the PureScript bundle)
  src/JitML/                    -- shared Haskell library (all logic lives here)
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
    Codegen/
      RuntimeSource.hs          -- generated-source ADT + materialization
      Cuda.hs                   -- Haskell renderer for generated CUDA inputs
      Metal.hs                  -- Haskell renderer for generated Swift/Metal package
      OneDnn.hs                 -- Haskell renderer for generated oneDNN C++ inputs
    Observability/
      Prometheus.hs             -- typed scrape-target list + /metrics endpoint
      Grafana.hs                -- typed dashboard renderer
      TensorBoard.hs            -- event-file writer
    Web/
      Contracts.hs              -- browser-contract ADTs (source for purescript-bridge)
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
  infra/
    pulumi/                     -- ephemeral-Kind stack for jitml-e2e (TypeScript program; see Test-suite stanzas)
  docker/                       -- one Dockerfile (jitml:local), compose.yaml (one service: jitml), playwright.Dockerfile
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
  .build/                       -- gitignored: outputs, kubeconfig, generated Dhall, runtime/kind metadata, JIT cache
  .data/                        -- gitignored: manual PV bind mounts only
```

---

# Doctrine scope

In-scope (binding) from [`HASKELL_CLI_TOOL.md`](HASKELL_CLI_TOOL.md), in doctrine order:

- Overview (toolchain pinning — instantiated by [Toolchain pinning](#toolchain-pinning))
- Project Structure (library-first; instantiated by [Repository layout (target)](#repository-layout-target))
- Command Topology
- GADT-Indexed State Machines (training lifecycle, RL run lifecycle, tuning sweep lifecycle)
- Progressive Introspection
- Automatically Generated Documentation
- Generated Artifacts (paired check/write for the route table, Grafana dashboards, protobuf schemas, PureScript contracts, CLI help, markdown docs)
- Architecture — including Subprocesses as Typed Values (kernel-compiler subprocesses, `kubectl`, `helm`, `kind`, `docker` all wrapped)
- Plan / Apply (`bootstrap`, `train`, `tune`, `cluster up`, `test all`, `service` startup-as-plan all Plan/Apply with `--dry-run` and `--plan-file`)
- Output Rules
- Standard Flag Families (Plan/Apply, Daemon, Output — see [Standard flag families](#standard-flag-families) for jitML's binding table)
- Error Handling (extended with exit code `3` for reconciler no-op-on-match; see [Exit codes and error rendering](#exit-codes-and-error-rendering))
- Capability Classes and Service Errors (`HasMinIO`, `HasPulsar`, `HasHarbor`, `HasKubectl`)
- Retry Policy as First-Class Values
- Prerequisites as Typed Effects (bootstrap scripts' contract is also encoded as a typed DAG)
- Application Environment (`ReaderT Env IO`)
- **Long-Running Daemons in the Same Binary** — `jitml service` is a real daemon with `BootConfig`/`LiveConfig` Dhall, SIGHUP hot reload, `/healthz`/`/readyz`/`/metrics`, structured JSON logging on stderr, recoverable-vs-fatal error kinds. (Contrast: sibling projects may opt out; jitML opts in.)
- At-Least-Once Event Processing (Pulsar consumer semantics)
- Reconcilers: Idempotent Mutation as a Single Command (`bootstrap`, `cluster up`, `docs generate`, `lint --write`)
- Lint, Format, and Code-Quality Stack
- Testing Doctrine
- Standard Testing Stack (Cabal + `exitcode-stdio-1.0` + tasty + tasty-hunit + tasty-quickcheck + tasty-golden + typed-process + temporary + Pulumi + fourmolu + hlint + cabal format)
- Test Categories (each of the seven mapped to a `jitml-*` stanza in [Test-suite stanzas](#test-suite-stanzas), including Daemon Lifecycle and Pulumi-Orchestrated Infrastructure)
- Test Organization (one `test-suite` stanza per tier; project-specific stanzas under §Test Organization → project-specific stanzas)

Out of scope (informational only):

- Smart Constructors for Paired Resources — no paired infra resources at present; if a PV/PVC pattern emerges, this section comes back into scope.
- The Architecture (the doctrine's closing capsule) — informational summary; the individual sections it recaps are the binding contract.

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

jitML's long-term goal is a fully declarative, reproducible, deterministic ML runtime that:

- compiles itself efficiently onto heterogeneous hardware (Apple Metal, NVIDIA CUDA, oneDNN/AVX) while preserving exact experimental replay semantics;
- covers the full feedforward / convolutional / residual / attention SL design space with first-class Dhall types for every layer, activation, optimizer, and scheduler;
- hosts the entire stable-baselines3 algorithm family — PPO, A2C, TRPO, MaskablePPO, RecurrentPPO, DQN, QR-DQN, DDPG, TD3, SAC, CrossQ, TQC, ARS, HER — plus AlphaZero-style self-play on perfect-information games (Connect 4 canonical);
- offers hyperparameter optimisation across the sampler × scheduler × pruner axes — Grid, Random, Sobol, TPE, GP-BO, GA, NSGA-II, (μ,λ)-ES, CMA-ES, PBT × Fifo, SuccessiveHalving, Hyperband, ASHA × {none, median, percentile} pruners;
- treats complex-valued networks as first-class citizens throughout the stack;
- ships an interactive demo app that lets users start, pause, and stop training runs from the browser, draw handwritten digits on a touchpad for live MNIST inference, upload images for CIFAR/ImageNet recognition, and play Connect 4 (and the rest of the canonical adversarial games) against the AlphaZero policy at any committed checkpoint;
- exercises every test category in [`HASKELL_CLI_TOOL.md` §Test Categories](HASKELL_CLI_TOOL.md#test-categories) — Pure Logic, Parser, Property, Golden, Integration, Daemon Lifecycle, Pulumi-Orchestrated Infrastructure — with Playwright e2e covering every interactive panel above.

---

# License

See [`LICENSE`](LICENSE).
