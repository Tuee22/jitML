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
> cache discipline, the Apple Silicon stable-FFI symlink surface and lazy tart
> spin-up, and the outer-container Linux build flow.

## Phase Status

✅ **Done**. The phase owns
[Exit Definition](README.md#exit-definition) items 4 (stage-0 entrypoints
plus the typed Haskell prerequisite DAG that performs all post-stage-0
reconciliation) and 10 (toolchain pin), and contributes to item 12 (typed
`Subprocess` for `kubectl` / `helm` / `kind` / `docker`). Every owned
obligation is met in the worktree and validated by Sprints `2.1`–`2.7`:
the stage-0 scripts fail fast on host gates and delegate to
`jitml bootstrap --<substrate>`, the typed prerequisite DAG performs
renderable/applicable Homebrew remediation with postcondition validation,
the typed JIT cache key/layout/manifest/symlink layer is in place, the
one-service `compose.yaml` and `jitml:local` image definition exist,
the Tart command surface is typed, and the script-side `status`, `test`,
`down`, `purge`, and `purge --full` wrappers are wired without
intentionally touching global user state.

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
owns the local Tart command/state scaffold, the single Dockerfile producing the
baseline `jitml:local` image, and the one-service compose file. The substrate
image is **always**
`jitml:local` — substrate is a runtime Dhall choice, never an image-name
dimension.

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

- Toolchain nodes: `ghc-9.14.1`, `cabal-3.16.1.0`, `protoc`, `node`, `poetry`,
  `purescript`, `spago`, `pulumi`, and Homebrew package nodes as typed values.
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
- [x] Add typed Homebrew package prerequisite/remediation nodes and golden
  plan-render tests.
- [x] Ensure `tart` is validated/installed only on first Apple JIT cache miss,
  never during stage-0 bootstrap or host-daemon startup.

### Closure Validation

- `jitml doctor --scope toolchain --remediate` installed the missing Homebrew
  package nodes through typed remediation actions and postcondition validation.
- `jitml doctor --scope toolchain` exits `0` on this Apple Silicon host after
  stage-0 `bootstrap/apple-silicon.sh doctor`.
- `container.tart` remains registered, but it is reachable only from
  `container.apple-silicon.jit-cache-miss`; the Apple bootstrap/container
  prerequisite closure does not validate tart during stage-0 bootstrap or
  host-daemon startup.

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

1. `cacheKey` is deterministic — golden test under `test/golden/cache/`.
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
- [x] Add focused unit/golden coverage for cache-key determinism, path layout,
  manifest round-trip, and symlink repointing.

### Closure Validation

- `jitml-unit` now covers the Sprint `2.3` cache-key golden, typed cache path,
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

Deliver one Dockerfile producing one image (`jitml:local`) and one compose
service (`jitml`). Substrate is a runtime Dhall choice — there is no
`jitml-linux-cpu`, `jitml-linux-cuda`, etc. tag dimension. Target Harbor upload
is owned by `jitml bootstrap --<substrate>`, not by a stage-0 shell `push` verb;
the current command materializes bootstrap inputs only.

### Deliverables

- `docker/Dockerfile` currently builds on `ubuntu:24.04` with pinned GHC
  `9.14.1`, Cabal `3.16.1.0`, GCC/G++, LLVM, Docker CLI, Node.js/npm, Python,
  PureScript, spago, architecture-aware `kubectl` / `kind`, `helm`, and the
  Sprint `1.4` style-tools/code-quality image gate, then installs the `jitml`
  and `jitml-demo` executables into `/usr/local/bin`. The full target image still
  needs CUDA/NVCC/cuBLAS/cuDNN, oneDNN, Poetry, and Pulumi hardening before it
  can serve as the complete Linux CPU / CUDA runtime image.
- `compose.yaml` declares one service `jitml` with image `jitml:local`,
  bind-mounts the repository at the same absolute path inside the container that
  it has on the host, runs with host networking so the outer-container Kind
  kubeconfig loopback endpoint is reachable, and sets the same path as its
  working directory with no entrypoint default.
- `linux-cpu.sh` and `linux-cuda.sh` enter the image through
  `docker compose run --rm jitml ...`; Compose builds `jitml:local`
  automatically when needed.
- Current `jitml bootstrap --<substrate>` materializes the repo-local bootstrap
  files and reports no-op materialization with exit code `3`. The live Phase `3`
  apply path builds `jitml:local` / `jitml-demo:local` and loads those tags
  explicitly into Kind; live Harbor image push/pull is owned by the Phase `4`
  platform-service and Phase `5` daemon capability work.
- Current `jitml build` renders `/opt/build/jitml` plus engine metadata. The
  target in-CLI build operation will build the inner Haskell binary at
  `/opt/build/jitml` from inside the container.
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
- Container-internal `jitml build` producing `/opt/build/jitml` remains target
  runtime work; the current implementation renders the build destination and
  engine metadata only.

### Remaining Work

None.

## Sprint 2.5: Apple Silicon Lazy Tart Spin-Up and `internal vm exec` ✅

**Status**: Done
**Implementation**: `src/JitML/Tart/Lifecycle.hs`, `src/JitML/Tart/Exec.hs`,
`src/JitML/App.hs`
**Docs to update**: `documents/engineering/jit_codegen_architecture.md`

### Objective

Deliver the local Tart command/state scaffold that the target lazy VM contract
will consume. The target contract is that the host daemon's startup path never
touches tart; on a JIT cache miss the daemon calls `ensureVmUp jitml-build`; the
VM stays up for the daemon's lifetime once spun up; an idle timeout (default
30 min, configurable in `LiveConfig`) brings it down again.

### Deliverables

- Current `ensureVmUp :: FilePath -> VmName -> IO ()` materializes
  `./.build/runtime/<vm>.state` with `up`; it does not start or poll a real Tart
  VM yet.
- Current `tartSshSubprocess` renders the typed `tart ssh <vm> -- <cmd>`
  command used by `jitml internal vm exec -- <cmd>`.
- Target Swift-build dispatch will render the Swift / Metal package under
  `./.build/jit-src/apple-silicon/<hash>/`, run `swift build` through the typed
  subprocess boundary, atomically write the produced `.dylib` into
  `./.build/jit/apple-silicon/`, and repoint the stable symlink per Sprint `2.3`.
- Target `LiveConfig.tartIdleTimeout : Optional Natural` (seconds; default
  `1800`) controls VM idle shutdown once the real host daemon exists.

### Validation

- `JitML.Tart.Lifecycle.ensureVmUp` materializes repo-local VM state under
  `./.build/runtime/` without touching global state.
- `jitml internal vm exec -- <cmd>` renders the typed `tart ssh` subprocess.
- Cabal test stanzas exercise the local daemon lifecycle and subprocess
  boundaries.

### Target Integration Notes

- Real first-cache-miss Tart startup, reuse timing, idle shutdown, and
  `swift --version` execution through `jitml internal vm exec` remain target
  Apple runtime work.
- Cache-preserving `purge` plus subsequent inference cache resolution depends on
  the future inference/JIT runtime path, not the local state scaffold.

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
- Starting a host-native `jitml service` after Apple bootstrap remains Phase `5`
  daemon runtime work.

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

## Doctrine Sections Cited

- [../README.md → Prerequisites as typed effects](../README.md#prerequisites-as-typed-effects) (Sprints 2.1, 2.2)
- [../README.md → Outer-container Linux builds](../README.md#outer-container-linux-builds) (Sprints 2.4, 2.5)
- [../README.md → Plan / Apply commands](../README.md#doctrine-scope) (Sprint 2.4)
- [../README.md → Subprocesses as Typed Values](../README.md#doctrine-scope) (every sprint)
- [../README.md → Built-artifact and JIT-cache discipline](../README.md#built-artifact-and-jit-cache-discipline) (Sprint 2.5)

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

- `system-components.md → Bootstrap Reconciler Subcommands` rows remain aligned
  with the implemented bootstrap scripts and command surfaces.
- `system-components.md → JIT Codegen Components` cache-related rows likewise.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [development_plan_standards.md](development_plan_standards.md)
- [../README.md](../README.md)
