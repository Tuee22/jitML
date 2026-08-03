# Phase 25: Outer-Container Linux Builds and `jitml:local` Image

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Outer-Container Linux Builds and jitml:local Image. Single-session phase migrated from legacy Sprint 2.4 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 25.1: Outer-Container Linux Builds and `jitml:local` Image [✅ Done]

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
`jitml bootstrap --<substrate>`, not by a stage-0 shell `push` verb; after
materialization the supported command enters the live Phase `3` reconcile.

### Deliverables

- `docker/Dockerfile` currently builds on `ubuntu:24.04` with pinned GHC
  `9.12.4`, Cabal `3.16.1.0`, GCC/G++, LLVM, Docker CLI, Node.js/npm, Python,
  Poetry, PureScript, spago, architecture-aware `kubectl` / `kind`, `helm`,
  CUDA/NVCC/cuBLAS/cuDNN, oneDNN, and the Sprint `1.4`
  style-tools/code-quality image gate, then installs the `jitml` executable into
  `/usr/local/bin`.
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
- `jitml bootstrap --<substrate>` materializes the repo-local bootstrap inputs
  and then executes the live Phase `3` apply path, which builds `jitml:local`,
  retags it as `jitml-demo:local`, and loads both tags explicitly into Kind.
  Exit code `3` is reserved for full live convergence. Harbor registry
  push/pull remains owned by the Phase `4` platform-service and Phase `5`
  daemon capability work.
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

- Full live `jitml bootstrap --linux-cpu` / `jitml cluster up --substrate
  linux-cpu` reconciliation is exercised by Phase `3` Sprint `3.7` through the
  local image build/load path. Harbor registry push/pull remains owned by the
  platform-service and daemon capability phases.
- The container-exclusive style-tools bootstrap and image-build Haskell
  code-quality gate are closed by Sprint `1.4`; Sprint `2.4` owns only the
  one-Dockerfile / one-compose-service image shape.
- Container-internal `jitml build` now owns the selected JIT artifact build
  path. Building and installing the `jitml` binary itself remains the Docker
  image build's responsibility.

### Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
