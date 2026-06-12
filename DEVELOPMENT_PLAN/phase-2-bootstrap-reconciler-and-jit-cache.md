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
[../README.md](../README.md)
**Generated sections**: none

> **Purpose**: Stand up the three stage-0 substrate bootstrap entrypoints, the
> Haskell `jitml bootstrap --<substrate>` reconciler, the typed prerequisite DAG
> that performs lazy package validation/remediation, the content-addressed JIT
> cache discipline, the Apple Silicon fixed Metal-bridge prerequisite/cache
> surface, and the outer-container Linux build flow.

## Phase Status

🔄 **Active** (reopened 2026-06-12 for the true-headless Apple Metal
fixed-bridge doctrine; Sprint `2.12`). The current prerequisite graph still
contains the `container.tart` node and the Tart lifecycle needed by the
now-legacy SwiftPM-in-VM cache-miss path. The target graph replaces that with
`apple.metal-runtime` and `apple.metal-bridge` as core Apple prerequisites plus
optional `apple.swiftc` / `apple.macos-sdk` probes for non-core Swift JIT
capabilities. The Apple cache artifact becomes `<hash>.metal.json` source
metadata; VM cleanup leaves `bootstrap purge`. The temporary residue is tracked
in
[legacy-tracking-for-deletion.md → Pending Removal](legacy-tracking-for-deletion.md#pending-removal).
Prior closure history follows.

✅ **Done** (reopened 2026-05-30 for the headless Apple Metal JIT workstream;
**re-closed the same day** after Sprint `2.10` removed the `container.tart`
prerequisite node, the `jitml internal vm` command group, and the
`src/JitML/Tart/*` modules — the Apple Metal build now uses a host
CommandLineTools `swift build` + runtime `MTLDevice.makeLibrary(source:)` with no
VM). See
[Reopened phases (2026-05-30)](README.md#reopened-phases-2026-05-30) and
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md). The status
text below predates the reopen.

✅ **Done** (re-closed 2026-05-29; Sprints `2.8` and `2.9` landed and validated
against the container build, unit tests, integration renderer assertions,
`jitml doctor --scope cluster`, `jitml bootstrap --dry-run`, and
`jitml docs check`; live re-exercise of the kind-node cap, pod convergence under
the cap, and the typed reconciler retries is owned by Phase 13 Sprint 13.1's
Remaining Work). The phase owns
[Exit Definition](README.md#exit-definition) items 4 (stage-0 entrypoints
plus the typed Haskell prerequisite DAG that performs all post-stage-0
reconciliation) and 10 (toolchain pin), and contributes to item 12 (typed
`Subprocess` for `kubectl` / `helm` / `kind` / `docker`). Every owned
obligation is met in the worktree and validated by Sprints `2.1`–`2.7`:
the stage-0 scripts fail fast on host gates and delegate to
`jitml bootstrap --<substrate>`, the typed prerequisite DAG performs
renderable/applicable Homebrew remediation with postcondition validation,
the typed JIT cache key/layout/manifest/symlink layer is in place, the
single `jitml:local` image plus the `jitml` / `jitml-cuda` compose wrappers
exist, the retired Tart/VM command surface is absent, and the script-side
`status`, `test`, `down`, `purge`, and `purge --full` wrappers are wired
without intentionally touching global user state.

### Reopened (2026-05-29)

Sprints `2.1`–`2.7` stay closed. The phase reopened to add two sprints after the
2026-05-29 host lockup (a cluster-wide OOM storm during `jitml bootstrap` made the
host unresponsive and forced a manual reboot): **Sprint `2.8`** adds the Dhall
cluster-resource profile, the kind-node memory/CPU cap, and the
`cluster.host-memory` preflight; **Sprint `2.9`** moves the reconciler's embedded
`sh -c` control-flow to typed Haskell with `RetryPolicy`. Both are listed below;
their live exercise is owned by Phase `13`.

### Current Implementation Scope

`jitml cluster up` materializes repo-local Kind, chart, Dhall, service, and
publication files, then prints reconciliation summaries or exits `3` when the
materialized files are already current. `jitml bootstrap --<substrate>`
materializes those files and then executes the live bootstrap runner that
drives typed `kind` / `helm` subprocesses; this phase's
closed surface remains the stage-0 gates, prerequisite DAG, and
content-addressed JIT cache key/layout/manifest/symlink layer that the
per-substrate engines in Phase `7` populate.

## Phase Summary

This phase delivers three idempotent substrate stage-0 scripts
(`bootstrap/{apple-silicon,linux-cpu,linux-cuda}.sh`) that do only the host checks
needed to reach the real bootstrap. Apple checks macOS on Apple Silicon, Xcode
Command Line Tools, and Homebrew, then builds `./.build/jitml` and calls
`./.build/jitml bootstrap --apple-silicon`. Linux CPU checks Docker is usable by
the current user without `sudo`, then calls
`docker compose run --rm jitml jitml bootstrap --linux-cpu`. Linux CUDA adds
NVIDIA container-runtime and `nvidia-smi` compute-capability gates before calling
`docker compose run --rm jitml jitml bootstrap --linux-cuda`.

The current Haskell bootstrap owns generated Dhall under `./.build/conf/`, Kind
metadata and cluster publication under `./.build/`, platform-service chart input
materialization, the cluster `jitml-service` ConfigMap / Deployment renderers,
Apple host Dhall materialization, and Linux in-cluster-only configuration
rendering. Harbor-first image rollout, Helm apply, and live daemon launch remain
target apply behavior.
The populated `prerequisiteRegistry` covers lazy Homebrew/package remediation via
typed predicates, typed remediation actions, pure plan rendering, effectful apply,
and postcondition validation. The typed cache layer now owns the
content-addressed JIT cache layout at `./.build/jit/<substrate>/<hash>.<ext>`
with the cache key `(canonical-cbor(KernelSpec), kind, substrate,
toolchain-fingerprint, rendered-source-payload, tuning-choice)`, the generated
compiler-input source root at
`./.build/jit-src/<substrate>/<hash>/`, the `manifest.json` index, and the Apple
Silicon `./.build/host/apple-silicon/` stable-FFI symlink surface. The phase also
owns the single Dockerfile producing the baseline `jitml:local` image and the
root compose wrappers over that image. The substrate image is **always**
`jitml:local` — substrate is a runtime Dhall choice, never an image-name
dimension. The former local Tart command/state scaffold was retired by Sprint
`2.10`.

## Sprint 2.1: Stage-0 Bootstrap Gates and Delegation ✅

**Status**: Done
**Implementation**: `bootstrap/apple-silicon.sh`, `bootstrap/linux-cpu.sh`,
`bootstrap/linux-cuda.sh`, `bootstrap/_lib.sh`,
`src/JitML/CLI/Spec.hs`, `src/JitML/CLI/Parser.hs`
**Docs to update**: `documents/engineering/cluster_topology.md`,
`DEVELOPMENT_PLAN/system-components.md`

### Objective

Deliver the three stage-0 bootstrap entrypoints with the smallest possible host
contract. The scripts fail fast with actionable installation guidance, then
delegate to the Haskell `jitml bootstrap --<substrate>` reconciler for every
cluster, package, image, Dhall, and daemon action.

### Deliverables

- `_lib.sh` is the shared helper layer for structured logging, OS/architecture
  checks, command existence checks, and actionable fatal diagnostics.
- `apple-silicon.sh` checks `Darwin` + `arm64`, Xcode Command Line Tools via
  `xcode-select`, and Homebrew via `brew --version`. Missing gates exit `2` with
  install instructions; the script does not install broad prerequisite sets.
- On Apple, `build` produces `./.build/jitml` host-native and `up` calls
  `./.build/jitml bootstrap --apple-silicon`.
- `linux-cpu.sh` checks Docker is installed and usable by the current user
  without `sudo`; missing Docker or group membership exits `2` with install
  instructions.
- `linux-cuda.sh` performs the Linux CPU gate plus NVIDIA container runtime and
  `nvidia-smi` checks. At least one GPU must satisfy the required compute
  capability; missing capability exits `2` with installation/remediation
  instructions.
- Stage-0 command test doubles are wired through the explicit
  `--command-dir <path>` script argument. The scripts do not consume test-only
  process environment variables for host OS, architecture, missing commands, or
  CUDA capability.
- Linux `up` calls the intended outer-container handoff:
  `docker compose run --rm jitml jitml bootstrap --linux-cpu` or
  `docker compose run --rm jitml jitml bootstrap --linux-cuda`; Sprint `2.4`
  owns the actual `compose.yaml` and image build target that make this
  handoff runnable from a clean checkout.
- `jitml bootstrap --apple-silicon|--linux-cpu|--linux-cuda` is registered in
  `CommandSpec` as the Haskell bootstrap command to be implemented by Sprint
  `2.2`.

### Validation

1. Each script's `help` exits `0` and prints the stage-0 contract plus the
   Haskell bootstrap command it delegates to.
2. Apple script tests cover non-macOS, non-Apple-Silicon, missing Xcode Command
   Line Tools, and missing Homebrew diagnostics without mutating host state.
3. Linux script tests cover Docker unavailable, Docker requiring `sudo`, missing
   NVIDIA runtime, and insufficient CUDA compute capability diagnostics.
4. `bash -n` syntax-checks every script in CI.
5. `jitml commands --tree`, generated CLI docs, and parser tests include the
   `bootstrap` command leaf.

### Closure Checklist

- [x] Rewrite Apple script gates to fail fast on macOS/arm64, Xcode Command Line
  Tools, and Homebrew only.
- [x] Make Apple `up` build `./.build/jitml` and call
  `./.build/jitml bootstrap --apple-silicon`.
- [x] Rewrite Linux CPU script gates to require Docker without `sudo`, then call
  `docker compose run --rm jitml jitml bootstrap --linux-cpu`.
- [x] Rewrite Linux CUDA script gates to require NVIDIA container runtime and a
  qualifying `nvidia-smi` device, then call
  `docker compose run --rm jitml jitml bootstrap --linux-cuda`.
- [x] Register the Haskell `jitml bootstrap --apple-silicon|--linux-cpu|--linux-cuda`
  command surface and regenerate generated CLI docs.
- [x] Update script tests so no stage-0 script installs Homebrew packages,
  `tart`, `kind`, `kubectl`, `helm`, Node.js, Poetry, or other broad toolchains.

## Sprint 2.2: Populated `prerequisiteRegistry` and Lazy Remediation ✅

**Status**: Done
**Implementation**: `src/JitML/Prerequisite/Nodes/Toolchain.hs`,
`src/JitML/Prerequisite/Nodes/Container.hs`,
`src/JitML/Prerequisite/Nodes/Cluster.hs`,
`src/JitML/Prerequisite/Plan.hs`, `src/JitML/App.hs`,
`src/JitML/CLI/Spec.hs`
**Docs to update**: `documents/engineering/cluster_topology.md`,
`documents/engineering/cli_command_surface.md`

### Objective

Populate the typed `prerequisiteRegistry` (Sprint `1.7`) with the toolchain,
container, and cluster nodes consumed by `jitml bootstrap --<substrate>`. Shell
scripts only guard the stage-0 host gates; Haskell is the source of truth for
lazy package validation and remediation.

### Deliverables

- Toolchain nodes: `ghc-9.12.4`, `cabal-3.16.1.0`, `protoc`, `node`, `poetry`,
  `purescript`, `spago`, and Homebrew package nodes as typed values.
- Container nodes: `docker`, `colima` (Apple), `tart` (Apple, lazy first-JIT
  validation/install rather than bootstrap startup).
- Cluster nodes: `kind`, `kubectl`, `helm`, `kindest-node-pin` (verifies the
  pin in `./kind/cluster-<substrate>.yaml` matches the comment in
  `cabal.project`).
- Each node carries `nodeId`, `nodeDescription`, predicate, optional typed
  remediation `Subprocess`, `dependsOn`, postcondition validation, and a remedy
  hint.
- Homebrew remediation is Plan/Apply: pure plan construction decides what is
  missing; apply executes `brew install` or `brew upgrade` through the typed
  subprocess interpreter; postconditions validate before dependents run.
- `jitml doctor [--scope toolchain|container|cluster]` reports the chosen
  subgraph. `jitml doctor --scope <scope> --remediate` applies typed
  remediation actions and validates postconditions through the same typed
  subprocess boundary that `jitml bootstrap --<substrate>` uses lazily as
  resources are needed.

### Validation

1. `jitml doctor --scope toolchain` exits `0` on a fresh Apple Silicon host
   after `bootstrap/apple-silicon.sh doctor` completes.
2. The structured diagnostic on a synthetic missing `kindest/node` pin names
   the failing node, the description, and the remedy hint.

### Closure Checklist

- [x] Add toolchain, container, and cluster prerequisite node modules.
- [x] Replace the empty initial `prerequisiteRegistry` with the populated
  transitive DAG.
- [x] Wire `jitml doctor [--scope toolchain|container|cluster]` through
  `reconcilePrerequisites`.
- [x] Add synthetic missing-node diagnostics and scope-selection tests.
- [x] Complete positive `jitml doctor --scope toolchain` validation on a host
  with the Sprint `2.2` toolchain prerequisites installed.
- [x] Add typed Homebrew package prerequisite/remediation nodes and
  snapshot plan-render tests.
- [x] Ensure Apple JIT cache-miss prerequisites are absent from stage-0
  bootstrap and host-daemon startup; the old Tart node was later deleted by
  Sprint `2.10`.

### Closure Validation

- `jitml doctor --scope toolchain --remediate` installed the missing Homebrew
  package nodes through typed remediation actions and postcondition validation.
- `jitml doctor --scope toolchain` exits `0` on this Apple Silicon host after
  stage-0 `bootstrap/apple-silicon.sh doctor`.
- The Apple bootstrap/container prerequisite closure does not validate any
  cache-miss-only Apple build prerequisite during stage-0 bootstrap or
  host-daemon startup. The later Sprint `2.10` deletion removed the old
  `container.tart` node entirely.

## Sprint 2.3: JIT Cache Layout and Content Addressing ✅

**Status**: Done
**Implementation**: `src/JitML/Cache/Key.hs`, `src/JitML/Cache/Layout.hs`,
`src/JitML/Cache/Manifest.hs`, `src/JitML/Cache/Symlink.hs`
**Docs to update**: `documents/engineering/jit_codegen_architecture.md`

### Objective

Stand up the content-addressed JIT cache root at
`./.build/jit/<substrate>/<hash>.<ext>` keyed on `(canonical-cbor(KernelSpec),
kind, substrate, toolchain-fingerprint, rendered-source-payload, tuning-choice)`
and the Apple stable-FFI symlink surface
at `./.build/host/apple-silicon/<model-id>.<ext>`.

### Deliverables

- `KernelSpec` ADT for the local cache-key surface; Phase `6` supplies the
  numerical catalog that participates in later kernel payloads.
- `cacheKey :: KernelSpec -> Kind -> Substrate -> ToolchainFingerprint ->
  RuntimeSourcePayload -> TuningChoice -> Hash` deterministically hashes
  `(canonical-cbor(KernelSpec) || kind || substrate || toolchain-fingerprint ||
  rendered-source-payload || tuning-choice)` to a 32-byte SHA-256 digest.
- `Kind` ADT: `Training | Inference`. Training and inference kernels are
  separate artefacts.
- The cache layout reserves `./.build/jit-src/<substrate>/<hex>/` for generated
  JIT compiler inputs. Sprint `7.7` now owns the Haskell runtime source
  renderers that populate this root for CUDA, oneDNN, and Swift / Metal source
  bundles during non-dry-run `jitml build`.
- `cachePath :: Path Abs Dir -> Substrate -> Hash -> Extension -> IO (Path Abs
  File)` resolves to `./.build/jit/<substrate>/<hex>.<ext>` under the configured
  build root.
- `manifest.json` index at `./.build/jit/manifest.json` keyed on `(model-id,
  kind, substrate, toolchain)` carries the latest `Hash` for each tuple. Atomic
  writes via temp-file + rename.
- `repointSymlink :: Path Abs Dir -> ModelId -> Hash -> Extension -> IO (Path
  Abs File)` (Apple only) atomically updates
  `./.build/host/apple-silicon/<model-id>.<ext>` to point at
  `./.build/jit/apple-silicon/<hash>.<ext>` under the configured build root.
- Linux substrates skip the symlink layer — the pod loads directly out of
  `./.build/jit/<substrate>/`.
- All cache writes are atomic (`tmp + rename`); concurrent writers writing the
  same content-addressed path are no-ops.

### Validation

1. `cacheKey` is deterministic — snapshot test under `test/snapshots/cache/`
   (SHA-256 over pure rendered runtime source; falls under
   [../README.md → Snapshot targets](../README.md#snapshot-targets), not
   the numerical-fixture prohibition).
2. `repointSymlink` is atomic — interleaved test asserts no torn read.
3. The `manifest.json` round-trips through `decode . encode == id`.

### Closure Checklist

- [x] Add typed `KernelSpec`, `Kind`, `Substrate`, `ToolchainFingerprint`,
  `Hash`, `ModelId`, and `Extension` values for the cache-key surface.
- [x] Implement deterministic SHA-256 cache keys over canonical-CBOR
  `KernelSpec`, kind, substrate, and toolchain fingerprint inputs.
- [x] Implement typed cache path, manifest path, and Apple stable symlink path
  resolution under `./.build/`.
- [x] Implement `manifest.json` entry round-trip, lookup, upsert, read, and
  atomic write helpers.
- [x] Implement atomic Apple stable-FFI symlink repointing into
  `jit/apple-silicon/`.
- [x] Add focused unit/snapshot coverage for cache-key determinism, path layout,
  manifest round-trip, and symlink repointing.

### Closure Validation

- `jitml-unit` now covers the Sprint `2.3` cache-key snapshot, typed cache path,
  manifest JSON round-trip/read/write, and Apple stable symlink repointing.
- `documents/engineering/jit_codegen_architecture.md` already describes the
  implemented cache layout, key shape, manifest, and Apple stable-FFI symlink
  surface; the code now matches that document.

## Sprint 2.4: Outer-Container Linux Builds and `jitml:local` Image ✅

**Status**: Done
**Implementation**: `docker/Dockerfile`, `compose.yaml`,
`bootstrap/linux-cpu.sh`, `bootstrap/linux-cuda.sh`,
`src/JitML/App.hs`, `src/JitML/Bootstrap.hs`
**Docs to update**: `documents/engineering/cluster_topology.md`,
`DEVELOPMENT_PLAN/system-components.md`

### Objective

Deliver one Dockerfile producing one image (`jitml:local`) and host-networked
compose wrappers over that image: headless `jitml` for bootstrap/code-quality
and non-GPU command runs, plus GPU-enabled `jitml-cuda` for direct live CUDA
validation. Substrate is a runtime Dhall choice — there is no `jitml-linux-cpu`,
`jitml-linux-cuda`, etc. tag dimension. Target Harbor upload is owned by
`jitml bootstrap --<substrate>`, not by a stage-0 shell `push` verb; the current
command materializes bootstrap inputs only.

### Deliverables

- `docker/Dockerfile` currently builds on `ubuntu:24.04` with pinned GHC
  `9.12.4`, Cabal `3.16.1.0`, GCC/G++, LLVM, Docker CLI, Node.js/npm, Python,
  Poetry, PureScript, spago, architecture-aware `kubectl` / `kind`, `helm`,
  CUDA/NVCC/cuBLAS/cuDNN, oneDNN, and the Sprint `1.4`
  style-tools/code-quality image gate, then installs the `jitml` and
  `jitml-demo` executables into `/usr/local/bin`.
- `compose.yaml` declares the shared `jitml:local` image/build/mount/network
  shape once, exposes it as the default headless `jitml` service, and adds a
  `jitml-cuda` companion with `gpus: all` for direct live CUDA tests. Both
  services bind-mount the repository at the same absolute path inside the
  container that it has on the host, run with host networking so the
  outer-container Kind kubeconfig loopback endpoint is reachable, and set the
  same path as the working directory with no entrypoint default.
- `linux-cpu.sh` and `linux-cuda.sh` enter the image through
  `docker compose run --rm jitml ...`; Compose builds `jitml:local`
  automatically when needed.
- Current `jitml bootstrap --<substrate>` materializes the repo-local bootstrap
  files and reports no-op materialization with exit code `3`. The live Phase `3`
  apply path builds `jitml:local` / `jitml-demo:local` and loads those tags
  explicitly into Kind; live Harbor image push/pull is owned by the Phase `4`
  platform-service and Phase `5` daemon capability work.
- Current `jitml build --dry-run` renders `/opt/build/jitml`, selected tuning
  metadata, engine metadata, generated-source locations, and the typed compile
  subprocess for the selected substrate. Non-dry-run `jitml build` now routes
  selected JIT artifacts through the shared Phase `7` cache artifact loader;
  the Docker image build remains the path that installs the inner Haskell binary
  at `/usr/local/bin/jitml` inside `jitml:local`.
- The bind chain host `./.build/` ⇄ Kind container `/jitml/.build/` ⇄ pod
  `/opt/build/` keeps artefacts coherent across duty cycles.

### Validation

- `docker compose config` validates the single `jitml`
  service, image tag `jitml:local`, source bind mount, and working directory.
- `jitml bootstrap --linux-cpu --dry-run` renders the typed bootstrap plan.
- Cabal test stanzas cover the bootstrap plan and script handoff surfaces with
  deterministic local tests.

### Target Integration Notes

- Full live `jitml bootstrap --linux-cpu` Harbor tagging/push and cluster-daemon
  rollout remain target apply behavior owned by the cluster/service phases.
- The container-exclusive style-tools bootstrap and image-build Haskell
  code-quality gate are closed by Sprint `1.4`; Sprint `2.4` owns only the
  one-Dockerfile / one-compose-service image shape.
- Container-internal `jitml build` now owns the selected JIT artifact build
  path. Building and installing the `jitml` binary itself remains the Docker
  image build's responsibility.

### Remaining Work

None.

## Sprint 2.5: Superseded Apple Silicon VM Scaffold ✅

**Status**: Done
**Implementation**: Superseded by Sprint `2.10`; no current `src/JitML/Tart/*`
modules or `jitml internal vm` commands remain
**Docs to update**: `documents/engineering/jit_codegen_architecture.md`

### Objective

This sprint originally delivered a local VM scaffold for the then-planned Apple
cache-miss build path. The current repository no longer uses that path:
Sprint `7.8` moved Apple Metal to a host CommandLineTools `swift build` plus
runtime `MTLDevice.makeLibrary(source:)`, and Sprint `2.10` deleted the VM
prerequisite, CLI, and modules.

### Deliverables

- No current deliverable remains in this sprint. The current Apple path renders
  Swift / Metal package inputs under `./.build/jit-src/apple-silicon/<hash>/`,
  runs host `swift build` through the typed subprocess boundary, atomically
  writes the produced `.dylib` into `./.build/jit/apple-silicon/`, repoints the
  stable symlink per Sprint `2.3`, and compiles MSL at runtime in-process.
- The removed VM command group and prerequisite are recorded in
  [legacy-tracking-for-deletion.md → Completed](legacy-tracking-for-deletion.md#completed).

### Validation

- Sprint `2.10` validation is the current closure gate for this superseded
  surface: no `jitml internal vm` commands exist in `CommandSpec`, no
  `src/JitML/Tart/*` modules are present, generated CLI docs/manpages/
  completions omit VM commands, and `container.tart` is absent from the
  prerequisite registry.

### Target Integration Notes

- First-cache-miss Apple execution now belongs to the headless host build path
  in Sprint `7.8` and Phase `14`.

### Remaining Work

None.

## Sprint 2.6: Bootstrap Script Wrappers and Status ✅

**Status**: Done
**Implementation**: `bootstrap/apple-silicon.sh`, `bootstrap/linux-cpu.sh`,
`bootstrap/linux-cuda.sh`
**Docs to update**: `documents/engineering/cluster_topology.md`

### Objective

Wire script-side wrapper subcommands after the Haskell bootstrap exists. Cluster
lifecycle, Dhall rendering, image upload, and daemon launch are owned by
`jitml bootstrap --<substrate>`; this sprint owns only the script-side glue and
status presentation.

### Deliverables

- `up` delegates to `jitml bootstrap --apple-silicon`, or to
  `docker compose run --rm jitml jitml bootstrap --linux-cpu|--linux-cuda`.
- `status` reads `./.build/runtime/cluster-publication.json` and prints
  `edge_port`, Pulsar URLs, MinIO URL, plus a per-component health summary.
- `test` is a thin wrapper for `jitml test all` from outside the container.

### Validation

- `bash -n bootstrap/_lib.sh bootstrap/apple-silicon.sh
  bootstrap/linux-cpu.sh bootstrap/linux-cuda.sh` exits `0`.
- `bootstrap/apple-silicon.sh status` reads
  `./.build/runtime/cluster-publication.json`.
- Cabal test stanzas cover the registered test and script surfaces.

### Target Integration Notes

- End-to-end `bootstrap/<substrate>.sh up` followed by a populated live
  cluster-publication status depends on the target live cluster apply path.
- Starting a host-native `jitml service` after Apple bootstrap is closed by
  Phase `5` daemon runtime validation.

### Remaining Work

None.

## Sprint 2.7: Bootstrap `down` and `purge` ✅

**Status**: Done
**Implementation**: `bootstrap/apple-silicon.sh`, `bootstrap/linux-cpu.sh`,
`bootstrap/linux-cuda.sh`
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
- Forbidden for stage-0 scripts: anything that touches `~/.kube/config`,
  `~/.docker/config.json`, the user's Homebrew prefix, or any global state
  outside the repo. Haskell `jitml` may install Homebrew packages only through
  typed lazy prerequisite remediation. `bash -n` plus a grep audit at CI time
  enforces the script boundary.

### Validation

- Script parsing validation (`bash -n`) covers all bootstrap wrappers.
- `down`, `purge`, and `purge --full` are repo-local and preserve the
  configured cache semantics; Linux `purge --full` additionally delegates to
  `docker compose down --rmi local --volumes`.
- The scripts contain no writes to `~/.kube/config`, `~/.docker/config.json`,
  Homebrew prefixes, or other global user state.

### Target Integration Notes

- Cache-preserving `purge` followed by live inference cache resolution depends
  on the future inference/JIT runtime path.
- Full byte-for-byte before/after validation of `~/.kube/config` and
  `~/.docker/config.json` belongs to the later live bootstrap test matrix; the
  current script boundary is covered by static and local wrapper tests.

### Remaining Work

None.

## Sprint 2.8: Dhall Cluster-Resource Profile, Kind-Node Cap, and Host-RAM Preflight ✅

**Status**: Done (code-surface closed 2026-05-29; live node-cap exercise owned by Phase 13 Sprint 13.1)
**Implementation**: `dhall/cluster/Schema.dhall`, `dhall/cluster/resources.dhall`, `src/JitML/Cluster/Resources.hs`, `src/JitML/Bootstrap.hs`, `src/JitML/Prerequisite/Nodes/Cluster.hs`
**Docs to update**: `documents/engineering/cluster_topology.md`, `system-components.md`

### Objective

Bound the kind cluster's memory and CPU so an over-budget bootstrap can never
exhaust the host (the 2026-05-29 OOM-storm incident), with the budget expressed as
typed Dhall rather than environment variables or shell arithmetic. Implements
doctrine `Application Environment` (typed config) and `Prerequisites as Typed
Effects`.

### Deliverables

- A typed `ClusterResources` Dhall schema (`dhall/cluster/Schema.dhall`) plus a
  concrete profile (`dhall/cluster/resources.dhall`) carrying `nodeMemoryMiB`,
  `nodeCpus`, and per-component `{ replicas, cpuRequest, cpuLimit, memoryRequest,
  memoryLimit }`, decoded by `JitML.Cluster.Resources.loadClusterResourcesOrDefault`
  (mirrors `JitML.Service.BootConfig.loadBootConfig` and `JitML.Numerics.Schema`).
- The bootstrap reconciler applies a typed `docker update
  --memory/--memory-swap/--cpus` cap to `jitml-<substrate>-control-plane` after
  `kind create`, fail-closed if the cap cannot be applied; the resolved profile is
  materialized to `./.build/conf/cluster/Resources.dhall`.
- A `cluster.host-memory` prerequisite added to the Sprint `2.2` registry that fails
  when host `MemTotal` is below `nodeMemoryMiB` + reserve (returns pass when
  `/proc/meminfo` is absent).

### Validation

- `jitml doctor --scope cluster` reports the `cluster.host-memory` node and fails
  with a remedy hint when `nodeMemoryMiB` exceeds host RAM.
- `jitml bootstrap --<substrate> --dry-run` renders the plan including the node-cap
  step and exits `0`.
- Live (owned by Phase `13`): after `kind create`, `docker inspect -f
  '{{.HostConfig.Memory}}' jitml-<substrate>-control-plane` reports the cap, and a
  forced over-budget cluster OOM-kills pods inside the node cgroup while the host
  stays up.

### Current Validation State

- `docker compose run --rm jitml cabal build all` succeeds (2026-05-29) — the new
  `JitML.Cluster.Resources` module and the wiring changes in
  `JitML.Bootstrap` / `JitML.Prerequisite.Nodes.Cluster` compile clean.
- `docker compose run --rm jitml jitml doctor --scope cluster` reports the new
  `cluster.host-memory` node and exits `0` on this host (15 GiB ≥ 10 GiB node cap +
  4 GiB reserve).
- `docker compose run --rm jitml jitml cluster up --substrate linux-cpu` materializes
  `./.build/conf/cluster/Resources.dhall` from the `dhall/cluster/` source.
- `cabal test jitml-unit` passes; `cabal test jitml-integration` failures are
  isolated to pre-existing live-cluster Sprint 13.x tests (Pulsar timeouts —
  no cluster up).
- `jitml docs check` exits `0`.

### Remaining Work

- The live node-cap exercise and the host-survives-over-budget validation are owned
  by Phase `13` Sprint `13.1`'s Remaining Work.
- The per-pod limits + right-sized replicas that make the stack converge under the
  cap are owned by Phase `4` Sprint `4.8` (and the PV-layout change by Phase `3`
  Sprint `3.2`).

## Sprint 2.9: Reconciler `sh -c` Control-Flow → Typed Haskell ✅

**Status**: Done (code-surface closed 2026-05-29; live re-validation owned by Phase 13 Sprint 13.1)
**Implementation**: `src/JitML/Cluster/Helm.hs`, `src/JitML/Bootstrap.hs`
**Docs to update**: `documents/engineering/daemon_architecture.md`, `documents/engineering/haskell_code_guide.md`, `legacy-tracking-for-deletion.md`

### Objective

Replace the embedded `sh -c` control-flow in the bootstrap reconciler with typed
multi-step Haskell, reusing the `RetryPolicy` value (Sprint `5.4`). Implements
doctrine `Subprocesses as Typed Values` and `Retry Policy as First-Class Values`;
the removed shell is tracked in the legacy ledger.

### Deliverables

- `kindCreateSubprocess` / `kindDeleteSubprocess` / `helmDependencyBuildSubprocess`
  (`src/JitML/Cluster/Helm.hs`) and the postgres schema-grant step
  (`src/JitML/Bootstrap.hs`) express their existence checks, branching, and
  command-substitution as typed Haskell over leaf `subprocess` values instead of
  `sh -c` strings.
- The retry/poll loops use `JitML.Service.Retry.RetryPolicy`, not shell
  `for`/`sleep`.

### Validation

- `jitml bootstrap --<substrate> --dry-run` renders the equivalent typed plan.
- Live (owned by Phase `13`): bootstrap converges and a forced topic/bucket
  not-ready path retries and succeeds exactly as the prior shell loops did.

### Current Validation State

- The 4 sh -c blocks (`kindCreate`, `kindDelete`, `helmDependencyBuild`,
  `postgresSchemaGrant`) are now typed: `JitML.Cluster.Helm` exposes typed
  `kind create cluster` / `kind delete cluster` / `helm dependency build`
  single-command subprocesses, and `JitML.Bootstrap` exposes
  `postgresSchemaGrantIO :: PerconaPGCluster -> IO (Either Text ())` —
  two typed `kubectl` subprocesses with the pod-name capture done in Haskell
  via `runStreaming`. `liveExecutePhasedRollout` splits the rollout into
  `livePreGrantSubprocessesForPort` + IO grants + `livePostGrantSubprocessesForPort`.
- `docker compose run --rm jitml cabal build all` (2026-05-29) succeeds.
- `cabal test jitml-unit` — all 185 tests pass.
- `cabal test jitml-integration` — only pre-existing live-cluster tests fail
  (Pulsar/MinIO/Harbor timeouts, no cluster up); the renderer assertions
  (`live phased rollout wires the explicit Kind image load phase`,
  `cluster down uses ... Kind delete subprocess`) pass against the typed forms.
- `jitml docs check` and `jitml bootstrap --linux-cpu --dry-run` exit `0`.

### Remaining Work

- Live re-validation of the converted reconciler steps is owned by Phase `13`
  Sprint `13.1`'s Remaining Work.

## Sprint 2.10: Retire the Tart Prerequisite and `jitml internal vm` Commands ✅

**Status**: Done (2026-05-30)
**Implementation**: `src/JitML/Prerequisite/Nodes/Container.hs`
(`container.tart` node + `container.apple-silicon.jit-cache-miss` deps),
`src/JitML/CLI/Spec.hs` (`internal vm` command group),
`src/JitML/App.hs` (`runInternalVmLifecycle` / `runInternalVmExec`),
`src/JitML/Tart/*` (deleted)
**Docs to update**: `../documents/engineering/cli_command_surface.md`,
`../documents/engineering/haskell_code_guide.md`,
`documents/cli/commands.md` (regenerated via `jitml docs generate`)

### Objective

With the Apple Metal build moving to a host CommandLineTools `swift build` +
runtime `MTLDevice.makeLibrary(source:)` (Phase `7` Sprint `7.8`), the Tart VM is
no longer part of the prerequisite DAG or the CLI surface. Remove the
`container.tart` node, the `jitml internal vm` command group, and the lazy-tart
prerequisite contract. Adopts `Prerequisites as Typed Effects` and `CommandSpec`
from [../README.md](../README.md).

### Deliverables

- `container.tart` removed from `JitML.Prerequisite.Nodes.Container`; the
  `container.apple-silicon.jit-cache-miss` node drops its `container.tart`
  dependency (the Apple cache miss now needs only the host toolchain).
- The `jitml internal vm bootstrap|up|down|status|exec` command group removed from
  `CommandSpec` and its `App.hs` handlers; `documents/cli/commands.md` regenerated.
- `src/JitML/Tart/{Build,Lifecycle,Exec}.hs` deleted; `jitml.cabal` updated.
- The prerequisite-closure unit test and the Tart-plan unit test removed/updated.
- Removals tracked in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

### Validation

1. `cabal build all` clean; `cabal test jitml-unit` green.
2. `jitml docs check` green after `jitml docs generate` (no `internal vm` verbs).
3. `grep -rn -i "tart" src` returns nothing after closure.

### Remaining Work

- None. Landed 2026-05-30: deleted `src/JitML/Tart/{Build,Lifecycle,Exec}.hs`,
  removed the `jitml internal vm` command group + `App.hs` handlers (commands.md /
  man / completions regenerated, `jitml docs check` ok), removed the
  `container.tart` prerequisite node + its `jit-cache-miss` dependency, and
  updated the unit tests (`grep -rn tart src` is clean; 183 `jitml-unit` pass;
  `cabal build all` clean).

## Doctrine Sections Cited

- [../README.md → Prerequisites as typed effects](../README.md#prerequisites-as-typed-effects) (Sprints 2.1, 2.2, 2.8)
- [../README.md → Outer-container Linux builds](../README.md#outer-container-linux-builds) (Sprints 2.4, 2.5)
- [../README.md → Plan / Apply commands](../README.md#doctrine-scope) (Sprint 2.4)
- [../README.md → Subprocesses as Typed Values](../README.md#doctrine-scope) (every sprint; Sprint 2.9 retires the embedded `sh -c` blocks)
- [../README.md → Retry Policy as First-Class Values](../README.md#doctrine-scope) (Sprint 2.9)
- [../README.md → Application Environment](../README.md#doctrine-scope) (Sprint 2.8)
- [../README.md → Built-artifact and JIT-cache discipline](../README.md#built-artifact-and-jit-cache-discipline) (Sprint 2.5)

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/cluster_topology.md` — bootstrap surface, hostPath
  layout, the `~/.kube/config` and `~/.docker/config.json` non-touch
  invariants, and (Sprint `2.8`) the `dhall/cluster/` resource profile +
  kind-node memory/CPU cap.
- `documents/engineering/jit_codegen_architecture.md` and
  `documents/engineering/apple_silicon_metal_headless_builds.md` — JIT cache
  layout, content-addressing, Apple fixed-bridge prerequisite surface, and
  `<hash>.metal.json` source/metadata cache pattern.
- `documents/engineering/daemon_architecture.md` / `haskell_code_guide.md` —
  (Sprint `2.9`) the reconciler `sh -c` → typed Haskell + `RetryPolicy`
  migration under `Subprocesses as Typed Values` / `Retry Policy as First-Class
  Values`.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- `system-components.md → Bootstrap Reconciler Subcommands` rows remain aligned
  with the implemented bootstrap scripts and command surfaces.
- `system-components.md → JIT Codegen Components` cache-related rows likewise.
- `system-components.md → Cluster Substrate Components` carries the
  `dhall/cluster/` profile and kind-node-cap rows; `legacy-tracking-for-deletion.md`
  carries the Sprint `2.9` embedded-`sh -c` removal row.
- `legacy-tracking-for-deletion.md` carries Pending Removal rows for
  `container.tart`, Tart lifecycle modules, and Apple generated-dylib cache
  residue owned by Sprints `2.12` / `7.11`.

## Sprint 2.11: Reinstate the Tart build-VM prerequisite and lifecycle [✅ Done]

**Status**: Done (2026-06-10)
**Implementation**: `src/JitML/Tart/Lifecycle.hs`, `src/JitML/Tart/Exec.hs`, `src/JitML/Prerequisite/Nodes/Container.hs`, `bootstrap/_lib.sh` (`purge` deletes the VM)
**Docs to update**: `documents/engineering/cluster_topology.md`, `documents/engineering/haskell_code_guide.md`, `system-components.md`

### Objective

Reinstate the `container.tart` prerequisite node and the `jitml`-owned Tart
build-VM lifecycle (create / start / stop / delete; `brew install` Tart if absent)
so the Apple Silicon JIT cache miss can build inside the VM, per the Apple Silicon
Tart-VM build-JIT doctrine (see
[../documents/engineering/jit_codegen_architecture.md → Apple Silicon Tart-VM Build JIT](../documents/engineering/jit_codegen_architecture.md#apple-silicon-tart-vm-build-jit)).

### Deliverables

- `container.tart` typed Homebrew package prerequisite (via
  `homebrewPackagePrerequisite`), with `container.apple-silicon.jit-cache-miss`
  re-pointed to depend on it.
- VM lifecycle helpers (create with Dhall-configured CPU/memory/storage, start,
  stop, delete) over the typed `Subprocess` boundary; bootstrap provisions the VM
  and `purge` deletes it (replacing the delete-only `tart delete jitml-build`
  residue in `bootstrap/_lib.sh`).

### Validation

- `jitml doctor --scope toolchain` reports the `container.tart` node on an Apple host.
- An Apple cache miss provisions/uses the VM and the prerequisite closure includes
  `container.tart`.
- Container `jitml check-code` and `jitml-unit` (prerequisite-closure tests) green.

### Validation State (2026-06-10)

- `container.tart` is back in the registry and the
  `container.apple-silicon.jit-cache-miss` closure depends on it (verified by the
  `jitml-unit` prerequisite-closure test, now flipped to require `container.tart`).
- `JitML.Tart.Lifecycle` reinstates the VM lifecycle (clone + `tart set`
  CPU/memory/disk, run headless with the repo mounted via `--dir`, stop, delete,
  status). Exercised live on Apple M1 / macOS 26: provision/`up` boots the
  `jitml-build` VM **headless** (no `HostKey` error), `status` and `down` work.
- `bootstrap/_lib.sh` `purge` deletes the VM (full create lifecycle now lives in
  the daemon acquire / `jitml internal vm`).

**Self-management hardening (2026-06-10).** The lifecycle was hardened so the
binary provisions and runs the VM end-to-end with no manual help, validated on
Apple M1 (`jitml internal vm delete` → `up` clones + configures + boots +
waits-exec-ready in ~20s → `exec`, and `jitml test jitml-backends --apple-silicon`
drives the in-VM `swift build` path 17 / 17):

- **Grow-only disk.** `provisionBuildVm` sets CPU/memory unconditionally and grows
  the disk only when the configured size exceeds the cloned image's current disk
  (`diskGrowthTarget`). `tart set --disk-size` can only grow, and cirruslabs base
  images already ship a large disk, so the previous fixed `--disk-size` smaller
  than the base failed provisioning outright.
- **Detached-start fd isolation.** `JitML.Sub.Stream.startDetached` wires the
  long-lived `tart run` process's stdin/stdout/stderr to `/dev/null` rather than
  inheriting them, so the VM process cannot hold a parent's captured output pipe
  open. Without this, starting the VM from inside an output-captured context (a
  `jitml test` cabal run, the daemon) deadlocked the parent's stream reader, which
  never saw EOF.
- **Generous boot wait + reproducible base image.** `waitForTartExec` allows ample
  headroom for a cold first-clone boot, and `defaultTartBaseImage` is pinned to
  `macos-sequoia-xcode:16` (reproducible toolchain, reused from the local image)
  rather than a moving `:latest`. New `jitml-unit` cases cover `diskGrowthTarget`
  and the `tart list` status/disk parser.

The downstream Apple cache-miss build *using* this VM lifecycle is owned by Phase
`7` Sprint `7.10`, which re-closed `✅ Done` (2026-06-10) after the apple-silicon
lane drove the in-VM `swift build` for real.

## Sprint 2.12: Replace Tart prerequisites with fixed-bridge Apple cache prerequisites [Active]

**Status**: Active
**Implementation**: `src/JitML/Prerequisite/Nodes/Container.hs`, `src/JitML/Cache/{Layout,Manifest}.hs`, `bootstrap/_lib.sh`
**Docs to update**: `documents/engineering/cluster_topology.md`, `documents/engineering/jit_codegen_architecture.md`, `documents/engineering/apple_silicon_metal_headless_builds.md`, `system-components.md`

### Objective

Make the Apple Silicon prerequisite and cache model match the fixed-bridge
architecture: core execution requires an OS Metal runtime probe and a fixed
bridge probe, not Tart, a keychain, SwiftPM, full Xcode, or the offline `metal`
compiler. Adopts `Prerequisites as typed effects`, `Subprocesses as typed
values`, and `Built-artifact and JIT-cache discipline` from
[../README.md](../README.md).

### Deliverables

- Replace the core `container.tart` / `container.apple-silicon.jit-cache-miss`
  closure with `apple.metal-runtime` and `apple.metal-bridge` nodes. The runtime
  probe dispatches a tiny `MTLDevice.makeLibrary(source:options:)` kernel; the
  bridge probe `dlopen`s/calls the fixed bridge's probe symbol.
- Add optional, non-core `apple.swiftc` and `apple.macos-sdk` nodes for future
  generated Swift modules. These nodes are not dependencies of training,
  inference, backend tests, or `jitml service`.
- Remove VM lifecycle cleanup from `bootstrap purge`; no bootstrap or cache-miss
  path starts/stops/deletes Tart.
- Change the Apple cache layout to persist source metadata at
  `./.build/jit/apple-silicon/<hash>.metal.json`, keyed by rendered MSL,
  launch metadata, bridge ABI version, Metal runtime policy, determinism
  options, and tuning choice.

### Validation

- `jitml doctor --scope toolchain` / `--scope container` reports the fixed-bridge
  Apple nodes and no core `container.tart` dependency.
- A synthetic Apple host with `xcrun -find metal` failing and no usable login
  keychain still passes the Metal runtime/bridge probes.
- `jitml-unit` prerequisite-closure and cache-layout tests pass.
- `bootstrap/apple-silicon.sh purge` preserves `./.build/jit/apple-silicon/` and
  invokes no `tart` subprocess.

### Remaining Work

- Implement the new Apple prerequisite nodes and remove `container.tart` from the
  core closure.
- Add `.metal.json` cache layout/manifest support and update tests.
- Remove bootstrap VM cleanup and move the Tart prerequisite/lifecycle ledger row
  to `Completed` after validation.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [development_plan_standards.md](development_plan_standards.md)
- [../README.md](../README.md)
