# Phase 7: Lint Stack, `fourmolu`, `hlint`, `cabal format`, `forbiddenPathRegistry`

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Lint Stack, fourmolu, hlint, cabal format, forbiddenPathRegistry. Single-session phase migrated from legacy Sprint 1.4 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done** (closed 2026-08-13). Totality is a build guarantee, not a convention:
every `jitml.cabal` stanza carries `-Werror=incomplete-patterns`, so an incomplete
`case` over `Substrate` or `LayerOp` fails an ordinary `cabal build` rather than
warning and then throwing `Non-exhaustive patterns` at runtime. The complementary
`src/JitML/Lint/FailOpen.hs` rule rejects a new fail-open catch-all on the
execution path — `_ -> []`, `_ -> False`, `_ -> 0`, `_ -> mempty`, `_ -> pure ()`,
and a rendered `switch` `default:` whose only statement is `break;` — over
`src/JitML/Codegen`, `src/JitML/Engines`, and `src/JitML/Numerics`, with the four
pre-existing sites held in an exact `failOpenPendingRegistry` that names the sprint
owning each fix.

## Sprint 7.1: Lint Stack, `fourmolu`, `hlint`, `cabal format`, `forbiddenPathRegistry` [✅ Done]

**Status**: Done
**Implementation**: `fourmolu.yaml`, `.hlint.yaml`, `jitml.cabal`,
`src/JitML/Lint/Stack.hs`, `src/JitML/Lint/FailOpen.hs`,
`src/JitML/Lint/ForbiddenPaths.hs`, `src/JitML/Lint/Chart.hs`,
`src/JitML/Lint/Stack/Types.hs`, `test/unit/Main.hs`, `docker/Dockerfile`
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
- Every `jitml.cabal` stanza — the library, the `jitml` executable, and all ten
  test suites — carries `-Werror=incomplete-patterns`, so a missing constructor
  is a build failure on an ordinary `cabal build`, not only under the
  `jitml check-code` gate.
- `src/JitML/Lint/FailOpen.hs` rejects a new fail-open catch-all on the
  execution path. The rejected forms are `_ -> []`, `_ -> False`, `_ -> 0`,
  `_ -> mempty`, `_ -> pure ()`, and a rendered native `switch` `default:`
  label whose only statement is `break;`. The scanned roots
  (`executionPathRoots`) are `src/JitML/Codegen`, `src/JitML/Engines`, and
  `src/JitML/Numerics`. `failOpenPendingRegistry` holds the exact
  `(path, form, count)` of the four sites that predate the rule together with
  the sprint that owns each fix — Sprint `233.1` for
  `src/JitML/Numerics/LayerGraph.hs`, Sprint `241.1` for
  `src/JitML/Numerics/LayerGraphOneDnn.hs` and `src/JitML/Codegen/OneDnn.hs`.
  The registry is exact in both directions: a count above it is
  `execution.fail-open.*`, and a closed site left registered is
  `execution.fail-open.stale-registration`.

### Validation

1. `docker compose build jitml` exits `0` and runs the
   Haskell style/code-quality gate as part of image construction.
2. `jitml lint haskell` runs inside `jitml:local` and host execution is
   rejected before linting.
3. `jitml lint all` exits `0` on the present tree inside `jitml:local`.
4. `jitml check-code` exits `0` on the present tree inside `jitml:local`.
5. Validation catches forbidden repository paths, tracked generated-doc drift,
   missing lint config, forbidden subprocess/terminal primitives, external
   formatter/HLint/cabal-format drift, execution-path fail-open catch-alls, and
   warning-clean build failures.
6. `jitml test jitml-unit --linux-cpu` passes, including the
   "Execution-path fail-open lint (Phase 7)" group that asserts the per-stanza
   `-Werror=incomplete-patterns` flag, the scanner's accept/reject behaviour,
   and a worktree free of unregistered fail-open sites.

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
- [x] Add `-Werror=incomplete-patterns` to every `jitml.cabal` stanza so a
  missing constructor is a build failure rather than a runtime throw, keeping
  the existing `cabal build all --ghc-options=-Werror` gate in
  `jitml check-code`.
- [x] Register the execution-path fail-open lint rejecting a new
  `_ -> []` / `_ -> False` / `default: break` catch-all, with an exact pending
  registry naming the sprint that owns each pre-existing site.

### Completed in this sprint

- `jitml.cabal`: all twelve stanzas carry `-Werror=incomplete-patterns`.
- `src/JitML/Lint/FailOpen.hs`: the typed `FailOpenForm` / `FailOpenSite` /
  `PendingFailOpen` surface, the pure `scanFailOpenSites` scanner, the
  `executionPathRoots` scope, and `checkFailOpenWildcards` reconciling the scan
  against `failOpenPendingRegistry` in both directions.
- `src/JitML/Lint/Stack.hs`: the scan runs inside `checkHaskellLint`, so
  `jitml lint haskell`, `jitml lint all`, and `jitml check-code` all enforce it.
- `test/unit/Main.hs`: the "Execution-path fail-open lint (Phase 7)" group
  (7 cases).
- `../documents/engineering/code_quality.md`: the
  `Execution-Path Fail-Open Lint` rule and the per-stanza totality guarantee.

This sprint implements the doctrine section `Lint, Format, and Code-Quality Stack`.

### Historical Validation

Evidence for the surface this sprint exercised before the 2026-08-12 reopen:

> ✅ **Done**.

## Documentation Requirements

**Engineering docs to create/update:**

- `../documents/engineering/code_quality.md` — the `Execution-Path Fail-Open
  Lint` rule (scope, rejected forms, pending registry) and the per-stanza
  `-Werror=incomplete-patterns` totality guarantee.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
