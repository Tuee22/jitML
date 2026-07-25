# Phase 22: Stage-0 Bootstrap Gates and Delegation

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Stage-0 Bootstrap Gates and Delegation. Single-session phase migrated from legacy Sprint 2.1 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 22.1: Stage-0 Bootstrap Gates and Delegation [✅ Done]

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
- `apple-silicon.sh` historically checked `Darwin` + `arm64`, the then-current
  Apple developer-tool gate, and Homebrew via `brew --version`. Sprint `2.12`
  replaces the Apple-specific gate with source-build prerequisites plus the
  fixed-bridge runtime prerequisites. Missing gates exit `2` with install
  instructions; the script does not install broad prerequisite sets.
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

### Historical Validation

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

- [x] Rewrite Apple script gates to fail fast on macOS/arm64, the then-current
  Apple developer-tool gate, and Homebrew only.
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

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
