# Phase 2: Bootstrap Reconciler, Prerequisite DAG, JIT Cache

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md),
[development_plan_standards.md](development_plan_standards.md),
[system-components.md](system-components.md),
[phase-0-planning-documentation.md](phase-0-planning-documentation.md),
[phase-1-haskell-cli-surface.md](phase-1-haskell-cli-surface.md),
[phase-3-cluster-substrate-and-routing.md](phase-3-cluster-substrate-and-routing.md),
[phase-7-jit-codegen-and-substrates.md](phase-7-jit-codegen-and-substrates.md),
[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
**Generated sections**: none

> **Purpose**: Stand up the three substrate bootstrap reconcilers, the typed
> prerequisite DAG that they share with the in-process Haskell daemon, the
> content-addressed JIT cache discipline, the Apple Silicon stable-FFI symlink
> surface and lazy tart spin-up, and the outer-container Linux build flow.

## Phase Status

⏸️ **Blocked** on Phase `0` closure and Phase `1` closure. The bootstrap
reconcilers consume the typed `Subprocess`, `Plan` / `apply`, prerequisite, and
`Env` boundaries laid down by Phase `1`.

## Phase Summary

This phase delivers the three idempotent substrate bootstrap scripts
(`bootstrap/{apple-silicon,linux-cpu,linux-cuda}.sh`) under the unified subcommand
surface `help | doctor | build | up | status | test | down | purge` (Linux adds
`push`), the populated `prerequisiteRegistry` covering Homebrew/ghcup/Colima/tart
(Apple) and Docker (Linux) plus `kind`, `kubectl`, `helm`, `protoc`, Node.js,
Poetry, the content-addressed JIT cache at `./.build/jit/<substrate>/<hash>.<ext>`
with the four-tuple cache key `(canonical-cbor(KernelSpec), kind, substrate,
toolchain-fingerprint)`, the Apple Silicon `./.build/host/apple-silicon/` stable-
FFI symlink surface and the lazy tart-VM spin-up contract, the single Dockerfile
producing the `jitml:local` image, and the one-service compose file. The substrate
image is **always** `jitml:local` — substrate is a runtime Dhall choice, never an
image-name dimension.

## Sprint 2.1: Bootstrap Script Skeleton and `doctor` Subcommand ⏸️

**Status**: Blocked
**Blocked by**: phase-0, 1.7
**Implementation**: `bootstrap/apple-silicon.sh`, `bootstrap/linux-cpu.sh`,
`bootstrap/linux-cuda.sh`, `bootstrap/_lib.sh`
**Docs to update**: `documents/engineering/cluster_topology.md`,
`DEVELOPMENT_PLAN/system-components.md`

### Objective

Deliver the three bootstrap reconcilers under a single subcommand surface, with
`doctor` invoking the in-process `jitml doctor` (which reconciles the typed
prerequisite DAG from Sprint `1.7`).

### Deliverables

- Each of the three scripts implements `help | doctor | build | up | status |
  test | down | purge` (Linux additionally implements `push`). Each subcommand
  is idempotent and restartable.
- `_lib.sh` is the shared helper layer: structured logging matching the daemon's
  JSON-on-stderr format, `prerequisite` shell helper that mirrors the in-process
  `Prerequisite` predicate, `must` / `info` / `warn` / `die` log levels.
- `doctor` shells into the inner `jitml` binary (when present) and runs `jitml
  doctor`; falls back to the script-side reconciliation when the binary is not
  yet built.
- `apple-silicon.sh` reconciles Homebrew, ghcup (pinned GHC `9.14.1`, Cabal
  `3.16.1.0`), `protoc`, Colima (`8 CPU / 16 GiB`), Docker, `kind`, `kubectl`,
  `helm`, Node.js, Poetry, plus `tart` (`brew install
  cirruslabs/cli/tart`).
- `linux-cpu.sh` reconciles only Docker on the host. Subsequent subcommands wrap
  `docker compose run --rm jitml jitml <subcommand>`. There is no outer
  container, no `compose up`, no long-running daemon outside Kind.
- `linux-cuda.sh` adds NVIDIA driver checks; on missing driver it installs and
  asks the user to reboot. Otherwise mirrors `linux-cpu.sh`.
- The CLI verb `jitml doctor` shells into the same in-process registry.

### Validation

1. Each script's `help` exits `0` and prints the supported subcommand surface.
2. Each script's `doctor` exits `0` on a host with all prerequisites met; exit
   `2` and a typed diagnostic on missing prerequisites (matches in-process
   `AppError PrerequisiteUnmet`).
3. `bash -n` syntax-checks every script in CI.

## Sprint 2.2: Populated `prerequisiteRegistry` ⏸️

**Status**: Blocked
**Blocked by**: 1.7, 2.1
**Implementation**: `src/JitML/Prerequisite/Nodes/Toolchain.hs`,
`src/JitML/Prerequisite/Nodes/Container.hs`,
`src/JitML/Prerequisite/Nodes/Cluster.hs`
**Docs to update**: `documents/engineering/cluster_topology.md`

### Objective

Populate the typed `prerequisiteRegistry` (Sprint `1.7`) with the toolchain,
container, and cluster nodes that the bootstrap scripts shell-reconcile against,
so the in-process `jitml doctor` is the source of truth and the shell scripts
mirror it.

### Deliverables

- Toolchain nodes: `ghc-9.14.1`, `cabal-3.16.1.0`, `protoc`, `node`, `poetry`,
  `purescript`, `spago`, `pulumi`.
- Container nodes: `docker`, `colima` (Apple), `tart` (Apple).
- Cluster nodes: `kind`, `kubectl`, `helm`, `kindest-node-pin` (verifies the
  pin in `./kind/cluster-<substrate>.yaml` matches the comment in
  `cabal.project`).
- Each node carries `nodeId`, `nodeDescription`, predicate, optional
  remediation `Subprocess`, `dependsOn`.
- `jitml doctor [--scope toolchain|container|cluster]` reconciles the chosen
  subgraph; default is the transitive closure rooted at `cluster`.

### Validation

1. `jitml doctor --scope toolchain` exits `0` on a fresh Apple Silicon host
   after `bootstrap/apple-silicon.sh doctor` completes.
2. The structured diagnostic on a synthetic missing `kindest/node` pin names
   the failing node, the description, and the remedy hint.

## Sprint 2.3: JIT Cache Layout and Content Addressing ⏸️

**Status**: Blocked
**Blocked by**: 1.5
**Implementation**: `src/JitML/Cache/Key.hs`, `src/JitML/Cache/Layout.hs`,
`src/JitML/Cache/Manifest.hs`, `src/JitML/Cache/Symlink.hs`
**Docs to update**: `documents/engineering/jit_codegen_architecture.md`

### Objective

Stand up the content-addressed JIT cache root at
`./.build/jit/<substrate>/<hash>.<ext>` keyed on `(canonical-cbor(KernelSpec),
kind, substrate, toolchain-fingerprint)` and the Apple stable-FFI symlink surface
at `./.build/host/apple-silicon/<model-id>.<ext>`.

### Deliverables

- `KernelSpec` ADT (placeholder — populated in Phase `6` once the numerical core
  lands; this sprint owns the *cache key shape*, not its inputs).
- `cacheKey :: KernelSpec -> Kind -> Substrate -> ToolchainFingerprint -> Hash`
  deterministically hashes `(canonical-cbor(KernelSpec) || kind || substrate ||
  toolchain-fingerprint)` to a 32-byte SHA-256 digest.
- `Kind` ADT: `Training | Inference`. Training and inference kernels are
  separate artefacts.
- `cachePath :: Substrate -> Hash -> Extension -> Path Abs File` resolves to
  `./.build/jit/<substrate>/<hex>.<ext>`.
- `manifest.json` index at `./.build/jit/manifest.json` keyed on `(model-id,
  kind, substrate, toolchain)` carries the latest `Hash` for each tuple. Atomic
  writes via temp-file + rename.
- `repointSymlink :: ModelId -> Hash -> IO ()` (Apple only) atomically updates
  `./.build/host/apple-silicon/<model-id>.<ext>` to point at
  `./.build/jit/apple-silicon/<hash>.<ext>`.
- Linux substrates skip the symlink layer — the pod loads directly out of
  `./.build/jit/<substrate>/`.
- All cache writes are atomic (`tmp + rename`); concurrent writers writing the
  same content-addressed path are no-ops.

### Validation

1. `cacheKey` is deterministic — golden test under `test/golden/cache/`.
2. `repointSymlink` is atomic — interleaved test asserts no torn read.
3. The `manifest.json` round-trips through `decode . encode == id`.

## Sprint 2.4: Outer-Container Linux Builds and `jitml:local` Image ⏸️

**Status**: Blocked
**Blocked by**: 2.1
**Implementation**: `docker/Dockerfile`, `docker/compose.yaml`,
`bootstrap/linux-cpu.sh build`, `bootstrap/linux-cpu.sh push`,
`src/JitML/CLI/Commands/Build.hs`
**Docs to update**: `documents/engineering/cluster_topology.md`,
`DEVELOPMENT_PLAN/system-components.md`

### Objective

Deliver one Dockerfile producing one image (`jitml:local`) and one compose
service (`jitml`). Substrate is a runtime Dhall choice — there is no
`jitml-linux-cpu`, `jitml-linux-cuda`, etc. tag dimension.

### Deliverables

- `docker/Dockerfile` builds on `ubuntu:24.04` with pinned GHC `9.14.1`, Cabal
  `3.16.1.0`, GCC, LLVM, NVCC, oneDNN, Node.js, Poetry, PureScript, spago,
  Pulumi, `kubectl`, `helm`, `kind`, and `docker` CLI client. NVCC + cuBLAS +
  cuDNN are baked unconditionally and activate at runtime when the pod is
  scheduled with `runtimeClassName: nvidia`.
- `docker/compose.yaml` declares one service `jitml` with image `jitml:local`,
  bind-mounts `./` to `/jitml`, working dir `/jitml`, no entrypoint default.
- `linux-cpu.sh build` runs `docker compose build jitml`. The image is
  rebuilt only when the Dockerfile or any sibling input changes.
- `linux-cpu.sh push` tags the image as
  `harbor.platform.svc.cluster.local/jitml/jitml:<sha>` and pushes it (the SHA
  is the Cabal-derived build identifier).
- `jitml build` (in-CLI) is the same operation invoked from inside the
  container; it builds the inner Haskell binary at `/opt/build/jitml`.
- The bind chain host `./.build/` ⇄ Kind container `/jitml/.build/` ⇄ pod
  `/opt/build/` keeps artefacts coherent across duty cycles.

### Validation

1. `bootstrap/linux-cpu.sh build` produces `jitml:local` and exits `0` from
   scratch.
2. `bootstrap/linux-cpu.sh push` succeeds against the bootstrap-phase Harbor
   (Phase `4` integration test).
3. `jitml build` from inside the container produces `/opt/build/jitml`.

## Sprint 2.5: Apple Silicon Lazy Tart Spin-Up and `internal vm exec` ⏸️

**Status**: Blocked
**Blocked by**: 2.3
**Implementation**: `src/JitML/Tart/Lifecycle.hs`, `src/JitML/Tart/Exec.hs`,
`src/JitML/CLI/Commands/InternalVm.hs`
**Docs to update**: `documents/engineering/jit_codegen_architecture.md`

### Objective

Deliver the lazy tart-VM contract: the host daemon's startup path never touches
tart; on a JIT cache miss the daemon calls `ensureVmUp jitml-build`; the VM
stays up for the daemon's lifetime once spun up; an idle timeout (default 30
min, configurable in `LiveConfig`) brings it down again.

### Deliverables

- `ensureVmUp :: VmName -> IO ()` is idempotent — if the VM is up, no-op; if
  down, `tart run jitml-build --no-graphics &` and poll until reachable.
- Atomic Swift-build dispatch: `tart ssh jitml-build -- swift build
  --package-path codegen-metal -c release`.
- Atomic write of the produced `.dylib` into `./.build/jit/apple-silicon/`
  (`tmp + rename`); symlink repointed atomically per Sprint `2.3`.
- `jitml internal vm exec -- <cmd>` is a pass-through to `tart ssh`.
  Apple-only; rejected on Linux substrates.
- `LiveConfig.tartIdleTimeout : Optional Natural` (in seconds; default `1800`).

### Validation

1. From a clean state, the first cache miss triggers tart spin-up; the second
   cache miss reuses the running VM (golden timing).
2. `purge` destroys the VM but preserves `./.build/jit/apple-silicon/`; a
   subsequent inference command resolves from cache without spinning tart up.
3. `jitml internal vm exec -- swift --version` succeeds on Apple, exits with
   `AppError UnknownCommand` on Linux.

## Sprint 2.6: Bootstrap `up`, `status`, `test` ⏸️

**Status**: Blocked
**Blocked by**: 2.4, 2.5
**Implementation**: `bootstrap/{apple-silicon,linux-cpu,linux-cuda}.sh`
**Docs to update**: `documents/engineering/cluster_topology.md`

### Objective

Wire the script-side `up`, `status`, and `test` subcommands. Cluster lifecycle is
owned by Phase `3`; this sprint owns only the script-side glue and the host-
daemon launch on Apple.

### Deliverables

- `up` shells into `jitml cluster up`. On Apple, additionally launches
  `./.build/jitml service --config conf/host/apple-silicon.dhall` host-native
  (Dhall: `residency = Host`, `inferenceMode = SelfInference`).
- `status` reads `./.data/runtime/cluster-publication.json` and prints
  `edge_port`, Pulsar URLs, MinIO URL, plus a per-component health summary.
- `test` is a thin wrapper for `jitml test all` from outside the container.

### Validation

1. After `bootstrap/<substrate>.sh up`, `bootstrap/<substrate>.sh status`
   prints a populated cluster-publication summary.
2. `bootstrap/apple-silicon.sh up` leaves both cluster and host-native
   `jitml service` running.

## Sprint 2.7: Bootstrap `down` and `purge` ⏸️

**Status**: Blocked
**Blocked by**: 2.6
**Implementation**: `bootstrap/{apple-silicon,linux-cpu,linux-cuda}.sh`
**Docs to update**: `documents/engineering/cluster_topology.md`

### Objective

Wire `down`, `purge`, and `purge --full` semantics. `down` preserves both
`./.data/` and `./.build/` and (on Apple) leaves the tart VM up; `purge` is
destructive but cache-preserving (`./.build/` survives, including the JIT
cache); `purge --full` additionally removes `./.build/` and (on Linux) the
substrate image.

### Deliverables

- `down`: `kind delete cluster --name jitml-<substrate>`, leave `./.data/` and
  `./.build/` intact, leave the host-native `jitml service` running on Apple
  (graceful shutdown via SIGTERM is owned by Phase `5`).
- `purge`: `down` plus `rm -rf ./.data/`; on Apple, `tart delete jitml-build`
  (the Swift incremental build cache inside the VM goes with it). `./.build/`
  survives.
- `purge --full`: `purge` plus `rm -rf ./.build/`; on Linux, `docker compose
  down --rmi local --volumes`.
- Forbidden: anything that touches `~/.kube/config`,
  `~/.docker/config.json`, the user's global Homebrew prefix as a writer, or
  any global state outside the repo. `bash -n` plus a grep audit at CI time
  enforces.

### Validation

1. `purge` followed by `up` plus a previously-cached inference command
   resolves from cache without spinning tart up.
2. `~/.kube/config` and `~/.docker/config.json` are byte-identical before and
   after a full `up` / `purge --full` cycle.

## Doctrine Sections Cited

- [../HASKELL_CLI_TOOL.md → Prerequisites as Typed Effects](../HASKELL_CLI_TOOL.md) (Sprints 2.1, 2.2)
- [../HASKELL_CLI_TOOL.md → Architecture → Subprocesses as Typed Values](../HASKELL_CLI_TOOL.md) (Sprints 2.4, 2.5)
- [../HASKELL_CLI_TOOL.md → Plan / Apply](../HASKELL_CLI_TOOL.md) (Sprint 2.4)
- [../HASKELL_CLI_TOOL.md → Reconcilers: Idempotent Mutation as a Single Command](../HASKELL_CLI_TOOL.md) (every sprint)
- [../HASKELL_CLI_TOOL.md → Application Environment](../HASKELL_CLI_TOOL.md) (Sprint 2.5)

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/cluster_topology.md` — bootstrap surface, hostPath
  layout, the `~/.kube/config` and `~/.docker/config.json` non-touch
  invariants.
- `documents/engineering/jit_codegen_architecture.md` — JIT cache layout,
  content-addressing, Apple stable-FFI symlink surface, lazy tart pattern.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- `system-components.md → Bootstrap Reconciler Subcommands` rows move from
  `⏸️ Blocked` through `🔄 Active` to `✅ Done`.
- `system-components.md → JIT Codegen Components` cache-related rows likewise.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [development_plan_standards.md](development_plan_standards.md)
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
