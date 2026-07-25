# Phase 4: Toolchain Pin and Library-First Cabal Project

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Toolchain Pin and Library-First Cabal Project. Single-session phase migrated from legacy Sprint 1.1 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 4.1: Toolchain Pin and Library-First Cabal Project [✅ Done]

**Status**: Done
**Implementation**: `jitml.cabal`, `cabal.project`, `app/Main.hs`,
`src/JitML/App.hs`, `.gitignore`, `.dockerignore`
**Docs to update**: `documents/engineering/cli_command_surface.md`,
`documents/engineering/code_quality.md`,
`DEVELOPMENT_PLAN/system-components.md`

### Objective

Pin GHC `9.12.4` and Cabal `3.16.1.0` in the cabal manifest and project files,
declare the `jitml` executable as a thin shim into `App.main`, and lay down the
library-first source tree with the standardized library set per doctrine
`Overview → standardized stack`. The former `jitml-demo` executable shim was
retired by Phase `11` Sprint `11.10`; the demo workload now runs the Webapp role
through `jitml service`.

### Deliverables

- `jitml.cabal` declares `cabal-version: 3.16`, `tested-with: ghc ==9.12.4`, the
  `jitml` library exposing `src/JitML/`, the `jitml` executable as a thin shim
  into `App.main`, and the eight test-suite stanzas
  named in [system-components.md → Test
  Stanzas](system-components.md#test-stanzas) (each `type: exitcode-stdio-1.0`).
- `cabal.project` declares `with-compiler: ghc-9.12.4`, records codegen-toolchain
  pin comments (LLVM, NVCC, Metal/`swiftc`, oneDNN), the `kindest/node` mirror-pin
  comment, and the report-card knob list from [system-components.md → POC Report-Card
  Knobs](system-components.md#poc-report-card-knobs).
- `cabal.project` carries no `allow-newer` override, no source-repository
  package pins, and no local dependency packages. The GHC `9.12.4` /
  `base-4.21` package set solves from plain Hackage.
- `app/Main.hs` is a six-line shim into `App.main`. No business logic in `app/`.
- `src/JitML/App.hs` exports `main` and is the single composition
  root for the CLI runner and role dispatch per doctrine
  [§Project Structure](../README.md).
- The standardized library set is declared in `jitml.cabal`'s
  `library.build-depends`: `optparse-applicative`, `text`, `bytestring`, `aeson`,
  `prettyprinter`, `prettyprinter-ansi-terminal`, `ansi-terminal`, `path`,
  `path-io`, `typed-process`, `safe-exceptions`, `dhall`, `tasty`, `tasty-hunit`,
  `tasty-quickcheck`, `temporary` (`tasty-golden` is intentionally not
  adopted; see [../README.md → Snapshot targets → Numerical-fixture
  prohibition](../README.md#snapshot-targets)). Project-specific additions
  (`pulsar-client-haskell`, `minio-hs`, `purescript-bridge`, etc.) remain target
  dependencies for later live integrations unless a later phase explicitly moves
  them into the current Cabal manifest.
- `.gitignore` lists `./.build/`, `./.data/`, `./dist-newstyle/`,
  `./.hlint-output`. `.dockerignore` mirrors.

### Validation

1. `cabal build all` builds the one supported `jitml` executable under GHC
   `9.12.4`; the Webapp is selected by `BootConfig.activeRole = Webapp`.
2. `cabal test all` runs the eight declared test stanzas; Phase `12` now supplies the
   dedicated deterministic bodies.
3. `grep '^tested-with' jitml.cabal` returns `tested-with:   ghc ==9.12.4`.
4. `grep '^with-compiler' cabal.project` returns `with-compiler: ghc-9.12.4`.
5. Every report-card knob from [system-components.md → POC Report-Card
   Knobs](system-components.md#poc-report-card-knobs) is grep-findable in
   `cabal.project`.

### Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
