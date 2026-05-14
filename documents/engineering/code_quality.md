# Code Quality

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: README.md, ../documentation_standards.md, ../../DEVELOPMENT_PLAN/phase-0-planning-documentation.md, ../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md, ../../DEVELOPMENT_PLAN/phase-11-purescript-frontend-and-demo.md
**Generated sections**: none

> **Purpose**: Project-specific code quality and lint stack for jitML. Defers
> to the doctrine for the formatter / hlint / cabal-format triple, the
> generated-section discipline, and the forbidden-path registry; adds the
> chart-shape lint and the route-registry-drift check.

## Doctrine Deferrals

This doc defers to [../../HASKELL_CLI_TOOL.md](../../HASKELL_CLI_TOOL.md) for:

- **Lint, Format, and Code-Quality Stack** — `fourmolu` + `hlint` +
  `cabal format`; pinned `fourmolu.yaml` at repo root with the twelve
  doctrine-mandated settings; `cabal format` temp-file round-trip
  byte-equality compare.
- **Forbidden Surfaces** — the `forbiddenPathRegistry` refusing
  `.github/workflows/`, `.husky/`, `.githooks/`,
  `.pre-commit-config.yaml`, root `Makefile` / `justfile` / `Taskfile.yml`.
- **Generated Artifacts → The generated-section registry** —
  `GeneratedSectionRule`, `trackingGeneratedPaths`, paired
  `jitml docs check` / `jitml docs generate` reconciler.
- **Error Handling** — `print`, `exitFailure`, direct terminal formatting
  forbidden outside the output module (`src/JitML/CLI/Output.hs`).
- **Architecture → Subprocesses as Typed Values** — `callProcess`,
  `readCreateProcess`, `System.Process.*`, `typed-process` smart
  constructors forbidden outside `src/JitML/Sub/Stream.hs`.

## Current Implementation Status

Sprint `1.1` has landed `jitml.cabal`, `cabal.project`, the app shims, and
sentinel Cabal test stanzas. Sprint `1.2` has replaced the `jitml-unit` sentinel
with parser/registry coverage. Sprint `1.3` has landed `jitml docs check`,
`jitml docs generate`, and the active tracked-generated-path registry for CLI
docs, the manpage, and shell completions. Sprint `1.4` has landed
`fourmolu.yaml`, `.hlint.yaml`, `forbiddenPathRegistry`, `jitml lint`,
`jitml check-code`, and the `jitml-haskell-style` stanza, but remains open for
the external `fourmolu`, `hlint`, `cabal format`, and warning-clean build
runners. `cabal.project` currently carries a scoped `allow-newer` block for
Dhall / CBOR package bounds under GHC `9.14.1`; its removal is tracked in
[../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md](../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md).

## jitML Project-Specific Lint Rules

The doctrine doesn't address the chart, the route registry, or the
PureScript frontend. The project-specific rules below extend the lint stack.

### Chart-Shape Lint (`jitml lint chart`)

Owned by `src/JitML/Lint/Chart.hs` (Sprint `1.4`). The current implementation is
a no-op while `chart/` is absent. Once chart files land, it refuses:

- Any `StorageClass` with a provisioner other than
  `kubernetes.io/no-provisioner`.
- Any `PersistentVolume` without an explicit `claimRef.namespace` and
  `claimRef.name`.
- Any freestanding `PersistentVolumeClaim` (must be created by a
  `StatefulSet.volumeClaimTemplates`).
- Any `hostPath` under `chart/templates/pv-*.yaml` that does not match
  `<namespace>/<StatefulSet>/pv_<replica-int>`.
- Any `PerconaPGCluster` outside the typed service-Postgres registry.
- Drift between the `kindest/node` pin in `kind/cluster-<substrate>.yaml`
  and the comment-mirror in `cabal.project`.

### Route-Registry Drift (`jitml lint files` against `chart/templates/httproute-*.yaml`)

Owned by `src/JitML/Lint/RouteRegistry.hs` (Sprint `3.4`). Enforces:

- Every route declared in `src/JitML/Routes.hs` has a generated
  `chart/templates/httproute-*.yaml` manifest.
- Every generated manifest has a registry entry.
- No hand-written HTTPRoute YAML exists.

### `forbiddenPathRegistry` (jitML extensions)

The project-specific `forbiddenPathRegistry` (Sprint `1.4`) extends the
doctrine's set with:

- Stage-0 scripts or ad hoc command runners touching `~/.kube/config`,
  `~/.docker/config.json`, the user's Homebrew prefix, or other global state.
  Homebrew package installation is allowed only through Haskell typed
  prerequisite remediation, with pure plan construction, typed `Subprocess`
  apply, and postcondition validation.
- Hand-edited Grafana dashboard ConfigMaps once Phase `4` promotes them from a
  future generated-path pattern into active `trackingGeneratedPaths`.
- Hand-edited `web/src/Generated/Contracts.purs` once Phase `11` promotes it
  from a future generated-path pattern into active `trackingGeneratedPaths`.

### `trackingGeneratedPaths` (jitML scope)

The active project-specific tracked-generated-paths registry currently covers:

- `documents/cli/commands.md`
- `share/man/man1/jitml.1`
- `share/completion/bash/jitml`, `share/completion/zsh/_jitml`,
  `share/completion/fish/jitml.fish`

Sprint `1.3` also records future generated-path patterns for:

- `share/man/man1/jitml-*.1`
- `web/src/Generated/Contracts.purs` (Phase 11)
- `chart/templates/httproute-*.yaml` (Phase 3)
- `chart/templates/grafana-dashboard-*.yaml` (Phase 4)

## `jitml check-code`

Current `jitml check-code` delegates to the in-repo lint stack: whitespace and
final-newline normalization checks, forbidden repository paths, generated-doc
drift checks, required lint config checks, optional-directory placeholders for
future `proto/` and `web/`, a no-op chart check while `chart/` is absent, and
forbidden subprocess primitive scans.

Sprint `1.4` remains open until `jitml check-code` runs the full target stack:

1. `fourmolu --mode check` over `src/`, `app/`, `test/`.
2. `hlint --with-group=default --with-group=extra --hint .hlint.yaml` over
   the same.
3. `cabal format` temp-file round-trip byte-equality on `jitml.cabal`.
4. `cabal build all -fwerror` (warning-clean build gate).
5. `jitml lint files` (`forbiddenPathRegistry` + tracked-generated-paths).
6. `jitml lint docs` (metadata, relative links, forbidden stale commands).
7. `jitml lint chart`.
8. `jitml lint haskell` (forbidden subprocess and IO primitives).
9. `jitml docs check` (generated-section drift).

## Cross-References

- [../../HASKELL_CLI_TOOL.md](../../HASKELL_CLI_TOOL.md)
- [../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md](../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md)
- [../../DEVELOPMENT_PLAN/phase-3-cluster-substrate-and-routing.md](../../DEVELOPMENT_PLAN/phase-3-cluster-substrate-and-routing.md)
- [../documentation_standards.md](../documentation_standards.md)
