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

## jitML Project-Specific Lint Rules

The doctrine doesn't address the chart, the route registry, or the
PureScript frontend. The project-specific rules below extend the lint stack.

### Chart-Shape Lint (`jitml lint chart`)

Owned by `src/JitML/Lint/Chart.hs` (Sprint `1.4`). Refuses:

- Any `StorageClass` with a provisioner other than
  `kubernetes.io/no-provisioner`.
- Any `PersistentVolume` without an explicit `claimRef.namespace` and
  `claimRef.name`.
- Any freestanding `PersistentVolumeClaim` (must be created by a
  `StatefulSet.volumeClaimTemplates`).
- Any `hostPath` under `chart/templates/pv-*.yaml` that does not match
  `<substrate>/<namespace>/<statefulset>/pv_<replica-int>`.
- Any `PerconaPGCluster` outside the single Harbor-only instance.
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

- Anything that touches `~/.kube/config`, `~/.docker/config.json`, or the
  user's global Homebrew prefix as a writer (enforced by a `bash -n` plus
  grep audit at CI time, since these are bootstrap-script invariants per
  [../../DEVELOPMENT_PLAN/phase-2-bootstrap-reconciler-and-jit-cache.md →
  Sprint 2.7](../../DEVELOPMENT_PLAN/phase-2-bootstrap-reconciler-and-jit-cache.md)).
- Hand-edited Grafana dashboard ConfigMaps (tracked by
  `trackingGeneratedPaths`).
- Hand-edited `web/src/Generated/Contracts.purs` (tracked).

### `trackingGeneratedPaths` (jitML scope)

The project-specific tracked-generated-paths registry (Sprint `1.3` plus
later phase additions):

- `documents/cli/commands.md`
- `share/man/man1/jitml.1`, `share/man/man1/jitml-*.1`
- `share/completion/bash/jitml`, `share/completion/zsh/_jitml`,
  `share/completion/fish/jitml.fish`
- `web/src/Generated/Contracts.purs` (Phase 11)
- `chart/templates/httproute-*.yaml` (Phase 3)
- `chart/templates/grafana-dashboard-*.yaml` (Phase 4)
- `kind/cluster-*.yaml` (Phase 3)

## `jitml check-code`

`jitml check-code` runs the full stack:

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
