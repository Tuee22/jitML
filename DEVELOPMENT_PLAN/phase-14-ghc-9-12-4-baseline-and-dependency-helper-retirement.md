# Phase 14: GHC 9.12.4 Baseline and Dependency Helper Retirement

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: GHC 9.12.4 Baseline and Dependency Helper Retirement. Single-session phase migrated from legacy Sprint 1.11 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 14.1: GHC 9.12.4 Baseline and Dependency Helper Retirement [✅ Done]

**Status**: Done
**Implementation**: `jitml.cabal`, `cabal.project`, `docker/Dockerfile`,
`src/JitML/Prerequisite/Nodes/Toolchain.hs`,
`test/snapshots/cli/app-error-render.txt`,
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`
**Docs to update**: `README.md`, `documents/engineering/code_quality.md`,
`DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`,
`DEVELOPMENT_PLAN/system-components.md`,
`DEVELOPMENT_PLAN/development_plan_standards.md`

### Objective

Use one Haskell compiler version across the project and the code-quality image:
GHC `9.12.4`. Remove the post-`allow-newer` source-pin/vendor dependency helper
and the superseded reopened-phase development ledger.

### Deliverables

- `jitml.cabal` declares `tested-with:   ghc ==9.12.4` and all package targets
  use `base >=4.21 && <4.22`.
- `cabal.project` declares `with-compiler: ghc-9.12.4`, keeps the codegen
  comments and report-card knobs, and contains no `allow-newer`, no
  `source-repository-package`, and no local dependency packages.
- `docker/Dockerfile` installs only `GHC_VERSION=9.12.4`; the pinned
  Fourmolu / HLint tools are built with that same compiler.
- `third_party/haskell/lens-family-*` is deleted, and plain Hackage provides
  `serialise`, `cborg`, `dhall`, `lens-family`, and `lens-family-core`.
- The toolchain prerequisite node, CLI error snapshot, and cache-key
  fingerprint fixtures use `ghc-9.12.4`.
- The superseded reopened-phase development ledger is deleted, and reopened
  phase scope is tracked only in owning phase documents plus the deletion
  ledger when cleanup residue exists.

### Validation

1. `ghcup run --ghc 9.12.4 -- cabal build all --dry-run --jobs=2` solves
   against plain Hackage with no source pins or vendor packages.
2. `docker compose build jitml` passes and runs the image-local
   `jitml check-code` gate.
3. `docker compose run --rm jitml cabal test jitml-unit jitml-rl-canonicals --jobs=2`
   passes under the pinned compiler.
4. `docker compose run --rm jitml jitml check-code` passes.

### Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
