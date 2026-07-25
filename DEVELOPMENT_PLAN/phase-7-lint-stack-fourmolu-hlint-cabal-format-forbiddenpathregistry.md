# Phase 7: Lint Stack, `fourmolu`, `hlint`, `cabal format`, `forbiddenPathRegistry`

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Lint Stack, fourmolu, hlint, cabal format, forbiddenPathRegistry. Single-session phase migrated from legacy Sprint 1.4 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 7.1: Lint Stack, `fourmolu`, `hlint`, `cabal format`, `forbiddenPathRegistry` [✅ Done]

**Status**: Done
**Implementation**: `fourmolu.yaml`, `.hlint.yaml`, `src/JitML/Lint/Stack.hs`,
`src/JitML/Lint/ForbiddenPaths.hs`, `src/JitML/Lint/Chart.hs`,
`src/JitML/Lint/Stack/Types.hs`, `src/JitML/Lint/Stack.hs`, `docker/Dockerfile`
**Docs to update**: `README.md`, `DEVELOPMENT_PLAN/README.md`,
`DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`,
`README.md`, `documents/engineering/code_quality.md`,
`documents/engineering/unit_testing_policy.md`, `documents/engineering/cluster_topology.md`

### Objective

Pin the doctrine-mandated `fourmolu` settings, layer `hlint` and `cabal format`
on top, declare the `forbiddenPathRegistry`, register the chart-shape lint, and
wire the entire stack into the `jitml lint` / `jitml check-code` commands per
doctrine `Lint, Format, and Code-Quality Stack`. Style and code-quality
execution is container-exclusive and separate from `jitml test`:
`jitml:local` image construction uses the pinned project GHC `9.12.4` to build
the pinned external style tools, runs the Haskell style/code-quality gate, and
runtime lint/check-code rejects host execution before linting.

### Deliverables

- `fourmolu.yaml` at repo root pins the thirteen doctrine-mandated settings
  (`indentation`, `column-limit`, `function-arrows`, `comma-style`,
  `import-export-style`, `indent-wheres`, `record-brace-space`,
  `newlines-between-decls`, `haddock-style`, `let-style`, `in-style`, `unicode`,
  `respectful`).
- `.hlint.yaml` declares project hints for `print`, `putStrLn`, `hPutStrLn
  stdout`, `exitFailure`, `callProcess`, `readCreateProcess`, and
  `System.Process.Typed.proc`. The in-repo scan also rejects direct terminal
  output primitives outside `src/JitML/CLI/Output.hs`, subprocess primitives
  outside `src/JitML/Sub/Stream.hs`, and hand-written HTTPRoute YAML drift via
  the chart lint.
- `forbiddenPathRegistry` in `src/JitML/Lint/ForbiddenPaths.hs` refuses
  `.github/workflows/`, `.husky/`, `.githooks/`, `.pre-commit-config.yaml`, root
  `Makefile` / `justfile` / `Taskfile.yml`. `jitml lint files` enforces.
- `src/JitML/Lint/Chart.hs` is a no-op when `chart/` is absent. When chart
  files are present, it enforces: every StorageClass uses
  `kubernetes.io/no-provisioner`; every PV has an explicit `claimRef.namespace`
  / `claimRef.name` or a registered Percona `volumeName` binding; every PVC is
  created only by a StatefulSet's `volumeClaimTemplates` or the registered
  Percona operator resource; every hostPath under `chart/templates/pv-*.yaml`
  matches `<namespace>/<StatefulSet>/pv_<replica-int>` per
  [00-overview.md → Hard Constraint 15](00-overview.md#hard-constraints).
- `cabal format` round-trip byte-equality writes the output to a temp file and
  compares against `jitml.cabal`; `jitml lint haskell --write` formats the
  manifest in place.
- `docker/Dockerfile` installs one pinned GHC (`9.12.4`) and builds pinned
  `fourmolu` / `hlint` binaries for `jitml:local`; image construction runs the
  Haskell style gate before publishing the image used by every substrate,
  including Apple Silicon's in-cluster daemon.
- `jitml lint haskell` runs the same lint stack inside `jitml:local`.
  External tools are called through the typed `Subprocess`
  boundary introduced in Sprint `1.6`.
- `jitml lint *` and `jitml check-code` reject host execution before linting;
  missing container markers or tools produce diagnostics that point to
  rebuilding and entering `jitml:local`.
- `jitml check-code` delegates to `jitml lint all` and adds the warning-clean
  build gate (`cabal build all --ghc-options=-Werror`).

### Validation

1. `docker compose build jitml` exits `0` and runs the
   Haskell style/code-quality gate as part of image construction.
2. `jitml lint haskell` runs inside `jitml:local` and host execution is
   rejected before linting.
3. `jitml lint all` exits `0` on the present tree inside `jitml:local`.
4. `jitml check-code` exits `0` on the present tree inside `jitml:local`.
5. Validation catches forbidden repository paths, tracked generated-doc drift,
   missing lint config, forbidden subprocess/terminal primitives, external
   formatter/HLint/cabal-format drift, and warning-clean build failures.

### Closure Checklist

- [x] Add `fourmolu.yaml`, `.hlint.yaml`, `forbiddenPathRegistry`,
  `jitml lint`, and `jitml check-code`.
- [x] Enforce tracked generated-section drift, forbidden repository paths, and
  forbidden subprocess primitives through the in-repo lint stack.
- [x] Replace the initial `JitML.Lint.Chart` body with chart-shape checks
  once `chart/` lands.
- [x] Record and close the external style-tool resolver blocker by using the
  pinned GHC `9.12.4` project compiler for both the project build and style
  tools.
- [x] Run `fourmolu --mode check` over `src/`, `app/`, and `test/` through the
  typed `Subprocess` boundary using the image-local GHC `9.12.4`.
- [x] Run `hlint --with-group=default --with-group=extra --hint .hlint.yaml`
  through the typed `Subprocess` boundary using the image-local GHC `9.12.4`.
- [x] Implement `cabal format` temp-file round-trip byte-equality on
  `jitml.cabal`.
- [x] Add the warning-clean `cabal build all --ghc-options=-Werror` gate to `jitml
  check-code`.
- [x] Move style-tool installation into `docker/Dockerfile` for `jitml:local`.
- [x] Run Haskell style/code-quality checks during image construction.
- [x] Remove the `jitml lint haskell` path that bootstraps missing style tools
  through host `ghcup`; replace it with a container-domain check and
  image-rebuild diagnostic.

### Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
