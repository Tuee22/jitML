# Code Quality

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: README.md, ../documentation_standards.md, ../../DEVELOPMENT_PLAN/phase-0-planning-documentation.md, ../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md, ../../DEVELOPMENT_PLAN/phase-11-purescript-frontend-and-demo.md
**Generated sections**: none

> **Purpose**: Project-specific code quality and lint stack for jitML. Defers
> to the doctrine for the formatter / hlint / cabal-format triple, the
> generated-section discipline, and the forbidden-path registry; records
> jitML's container-owned style-tool bootstrap; adds the chart-shape lint and
> the route-registry-drift check.

## Doctrine Deferrals

This doc defers to [../../HASKELL_CLI_TOOL.md](../../HASKELL_CLI_TOOL.md) for:

- **Lint, Format, and Code-Quality Stack** — `fourmolu` + `hlint` +
  `cabal format`; pinned `fourmolu.yaml` at repo root with the twelve
  doctrine-mandated settings; explicit style-tool bootstrap before lint
  execution; `cabal format` temp-file round-trip byte-equality compare.
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
`jitml check-code`, external `fourmolu`, `hlint`, `cabal format` round-trip
checks, the warning-clean build runner, and the `jitml-haskell-style` stanza.
Sprint `1.4` also owns the container style-tool bootstrap: `docker/Dockerfile`
installs the separate style-tools GHC and pinned `fourmolu` / `hlint` binaries
for `jitml:local`, runs Haskell style/code-quality checks during image
construction, and runtime lint never bootstraps missing tools through host
`ghcup`.
`cabal.project` currently carries a scoped `allow-newer` block for
Dhall / CBOR package bounds under GHC `9.14.1`; its removal is tracked in
[../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md](../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md).

## jitML Project-Specific Lint Rules

The doctrine doesn't address the chart, the route registry, or the
PureScript frontend. The project-specific rules below extend the lint stack.

### Chart-Shape Lint (`jitml lint chart`)

Owned by `src/JitML/Lint/Chart.hs` (Sprint `1.4`). The current implementation
runs against the checked-in `chart/` tree and refuses:

- Any `StorageClass` with a provisioner other than
  `kubernetes.io/no-provisioner`.
- Any `PersistentVolume` without an explicit `claimRef.namespace` /
  `claimRef.name` or a registered Percona `volumeName` binding.
- Any freestanding `PersistentVolumeClaim` (must be created by a
  `StatefulSet.volumeClaimTemplates`).
- Any `hostPath` under `chart/templates/pv-*.yaml` that does not match
  `<namespace>/<StatefulSet>/pv_<replica-int>`.
- Any `PerconaPGCluster` outside the typed service-Postgres registry.
- Drift between the `kindest/node` pin in `kind/cluster-<substrate>.yaml`
  and the comment-mirror in `cabal.project`.
- The lint rejects Helm values files or other non-manifest YAML under
  `chart/templates/`, following
  [cluster_topology.md → Helm Values
  Ownership](cluster_topology.md#helm-values-ownership). Standalone
  `chart/<subchart>-values.yaml` files are allowed only when a typed Helm
  invocation explicitly passes them with `--values`; otherwise they are cleanup
  candidates that should be folded into `chart/values.yaml`.

### Route-Registry Drift (`jitml lint chart` against `chart/templates/httproute-*.yaml`)

Owned by `src/JitML/Lint/Chart.hs` (Sprint `3.4`). Enforces:

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
- Hand-edited Grafana dashboard ConfigMaps, generated HTTPRoute manifests,
  generated Prometheus scrape config, or `web/src/Generated/Contracts.purs`
  outside the active `trackingGeneratedPaths` renderer.

### `trackingGeneratedPaths` (jitML scope)

The active project-specific tracked-generated-paths registry currently covers:

- `documents/cli/commands.md`
- `share/man/man1/jitml.1`
- `share/completion/bash/jitml`, `share/completion/zsh/_jitml`,
  `share/completion/fish/jitml.fish`
- `web/src/Generated/Contracts.purs`
- `chart/templates/httproute-*.yaml`
- `chart/templates/grafana-dashboard-*.yaml`
- `chart/templates/prometheus-scrapeconfig-jitml.yaml`

Sprint `1.3` also records future generated-path patterns for:

- `share/man/man1/jitml-*.1`

## Container-Owned Haskell Style Tools

The mandatory `jitml:local` image is built on every substrate, including Apple
Silicon for the cluster daemon. That image build is the canonical Haskell style
bootstrap point:

1. Install a separate style-tools GHC (`9.12.4`) that never becomes the project
   compiler.
2. Build pinned `fourmolu` / `hlint` binaries into a deterministic image-owned
   tool location.
3. Run Fourmolu, HLint, `cabal format`, generated-doc/lint checks, and the
   warning-clean build gate during image construction.
4. Make runtime `jitml lint haskell` and `jitml-haskell-style` use the prebuilt
   tools. If the tools are absent, the diagnostic points to rebuilding or
   entering the `jitml:local` image rather than installing a host GHC.

## `jitml check-code`

Current `jitml check-code` delegates to the in-repo lint stack: whitespace and
final-newline normalization checks, forbidden repository paths, generated-doc
drift checks, required lint config checks, optional-directory checks for
`proto/` and `web/`, chart-shape checks, route-registry drift checks, and
forbidden subprocess/terminal primitive scans. It also runs the external
Haskell style stack through the typed `Subprocess` boundary and adds the
warning-clean build gate. The `jitml:local` image construction path runs this
same gate with container-provisioned style tools.

Sprint `1.4` closes with `jitml check-code` and the Docker image build running
the full target stack:

1. `fourmolu --no-cabal --ghc-opt -XGHC2024 --mode check` over `src/`, `app/`,
   `test/`.
2. `hlint --with-group=default --with-group=extra --hint .hlint.yaml` over
   the same.
3. `cabal format` temp-file round-trip byte-equality on `jitml.cabal`.
4. `cabal build all --ghc-options=-Werror` (warning-clean build gate).
5. `jitml lint files` (`forbiddenPathRegistry` + tracked-generated-paths).
6. `jitml lint docs` (metadata, relative links, forbidden stale commands).
7. `jitml lint chart`.
8. `jitml lint haskell` (forbidden subprocess and IO primitives).
9. `jitml docs check` (generated-section drift).
10. `docker compose -f docker/compose.yaml build jitml` proves the same gate runs
    as part of the mandatory image build.

## Cross-References

- [../../HASKELL_CLI_TOOL.md](../../HASKELL_CLI_TOOL.md)
- [../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md](../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md)
- [../../DEVELOPMENT_PLAN/phase-3-cluster-substrate-and-routing.md](../../DEVELOPMENT_PLAN/phase-3-cluster-substrate-and-routing.md)
- [../documentation_standards.md](../documentation_standards.md)
