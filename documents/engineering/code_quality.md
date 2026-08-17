# Code Quality

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: README.md, ../documentation_standards.md, ../../DEVELOPMENT_PLAN/phase-0-planning-documentation.md, ../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md, ../../DEVELOPMENT_PLAN/phase-8-supervised-and-rl-framework.md, ../../DEVELOPMENT_PLAN/phase-11-purescript-frontend-and-demo.md, ../../DEVELOPMENT_PLAN/phase-17-cross-substrate-and-handoff.md
**Generated sections**: none

> **Purpose**: Project-specific code quality and lint stack for jitML. Defers
> to the doctrine for the formatter / hlint / cabal-format triple, the
> generated-section discipline, and the forbidden-path registry; records
> jitML's container-exclusive code-quality domain; adds the chart-shape lint
> and the route-registry-drift check.

## Doctrine Deferrals

This doc defers to [../../README.md](../../README.md) for:

- **Lint, Format, and Code-Quality Stack** — `fourmolu` + `hlint` +
  `cabal format`; pinned `fourmolu.yaml` at repo root with the thirteen
  doctrine-mandated settings; jitML's style-tool bootstrap and lint execution
  happen only inside `jitml:local`; `cabal format` temp-file round-trip
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
docs, the manpage, and shell completions. Sprint `0.3` extends the docs-check
surface so that the required governed-document metadata declared in
`documents/documentation_standards.md` is also enforced by the checker.
Sprint `1.4` has landed
`fourmolu.yaml`, `.hlint.yaml`, `forbiddenPathRegistry`, `jitml lint`,
`jitml check-code`, external `fourmolu`, `hlint`, `cabal format` round-trip
checks, and the warning-clean build runner.
Sprint `1.4` also owns the container-exclusive code-quality domain:
`docker/Dockerfile` installs pinned `fourmolu` / `hlint` binaries under the
same image-local GHC `9.12.4` used for the project build, stamps the image as
the code-quality execution domain, runs Haskell style/code-quality checks
during image construction, and host lint/check-code execution is rejected
before linting.
`cabal.project` carries no `allow-newer` block, no source-repository package
pins, and no local dependency packages. Sprint `1.11` downgraded the project to
the GHC `9.12.4` / `base-4.21` family, allowing `serialise`, `cborg`, `dhall`,
and `lens-family` to solve from plain Hackage. The earlier source-pin/vendor
compatibility helper is removed and tracked as completed cleanup in
[../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md](../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md).
The file-lint traversal also skips `./.roms/`, matching `.gitignore` and
`.dockerignore`, so explicit developer-supplied Atari ROM files can exist
locally for optional manual ALE runs without entering Git, images, or text-file
hygiene checks. Preserved manual-PV snapshots under `.data-preserved*/` are
also ignored by `.gitignore`, `.dockerignore`, and the file-lint traversal:
they are local operational state, often root-owned database files, and not
repository source. Default examples and required
canonical tests must remain copyright-free, and no native C/C++ ALE adapter
source is checked in.
Phase `11` Sprint `11.3` also keeps the PureScript smoke suite warning-clean:
`web/test/Main.purs` runs `purescript-spec` through the Node `spec-node`
`runSpecAndExitProcess` runner, `web/spago.yaml` declares `spec-node` as a test
dependency, and `web/.gitignore` excludes the runner's `.spec-results` state.

## jitML Project-Specific Lint Rules

The doctrine doesn't address the chart, the route registry, or the
PureScript frontend. The project-specific rules below extend the lint stack.

### Static JIT Source Rejection (`jitml lint files`)

Owned by `src/JitML/Lint/Stack.hs` (Sprint `7.7`). The file lint rejects
checked-in CUDA `.cu`, C/C++ `.cc` / `.cpp`, Metal `.metal`, Swift `.swift`,
and `build.sh` files. Native/JIT source belongs in Haskell `RuntimeSource`
renderers and is materialized only under
`./.build/jit-src/<substrate>/<hash>/` on cache miss. There is no checked-in
foreign-language source allowlist; runtime adapter shims must also be generated
by Haskell into the build/cache tree or supplied outside the repository.

### ProductTruth Scaffold Lint (`jitml lint files`)

Owned by `src/JitML/Lint/ProductTruth.hs` (Sprint `20.2`). The file lint scans
`src/` for scaffold names that are enforced now: the relocated deterministic
environment step, the non-learned RL loop, and the fake simulated episode
runners. It separately walks the product module graph from `JitML.App` and
fails if that graph imports a forbidden fossil module such as `JitML.RL.Loop`,
`JitML.RL.SimulatorLoop`, or the test-support homes for those helpers.
`JitML.RL.VecEnv` is no longer forbidden by name: it is reintroduced as a real,
product-reachable learning vectorized-environment module, so the reachability
walk governs it like any other product module — the walk still fails any
dead/unreachable fake, and only the genuinely-dead fossils (`JitML.RL.Loop`,
`JitML.RL.SimulatorLoop`) remain forbidden by name.

The same registry now enforces the removed `completedTrainingFromMetrics`
fabrication helper and still lists future-owned scaffolds, including seeded demo
weights and degenerate Metal convolution scaffolds. Those future entries are
exposed as `nonProductScaffolding` so the unit suite can prove no `ProductRow`
implementation names them before their owning phases remove the source paths.

### Execution-Path Fail-Open Lint (`jitml lint haskell`)

Owned by `src/JitML/Lint/FailOpen.hs` (Sprint `7.1`). A *fail-open wildcard* is
a catch-all branch on the execution path whose right-hand side is a vacuously
successful value — `_ -> []`, `_ -> False`, `_ -> 0`, `_ -> mempty`,
`_ -> pure ()` — or, in rendered native source, a `switch` `default:` label
whose only statement is `break;`. Such a branch turns an unhandled operator
into a silent no-op instead of a typed failure, which the hardware-native
determinism contract forbids on the execution path.

The scan is scoped to `executionPathRoots` — `src/JitML/Codegen`,
`src/JitML/Engines`, and `src/JitML/Numerics`, that is the JIT source
renderers, the engine dispatch surface, and the numerical execution modules.
It is zero-tolerance for *new* sites: `failOpenPendingRegistry` enumerates the
exact `(path, form, count)` of every site that predates the rule together with
the sprint that owns closing it, and a count above the registered one is a
`execution.fail-open.*` finding. The registry is exact in both directions, so
closing a site without deleting its entry raises
`execution.fail-open.stale-registration` — the owning sprint cannot close its
fix and leave the registry stale. The registered sites are primary unmet
obligations of their owning sprints' `### Remaining Work` under development-plan
standards rule `C`, not deletion-ledger rows; the registry is the machine-checked
form of those obligations.

The complementary build-level guarantee is `-Werror=incomplete-patterns` in
every `jitml.cabal` stanza (Sprint `7.1`): a missing constructor is a build
failure on an ordinary `cabal build`, not only under the
`cabal build all --ghc-options=-Werror` gate, so every "total function over
`Substrate`" or `LayerOp` is a build guarantee rather than a convention. The
`jitml-unit` group "Execution-path fail-open lint (Phase 7)" asserts both the
per-stanza flag and a worktree free of unregistered fail-open sites.

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
  generated Prometheus scrape config, `web/src/Generated/Contracts.purs`,
  or `web/src/Generated/AdminPortals.purs`
  outside the active `trackingGeneratedPaths` renderer.
- `test/golden/`. Pure renderer snapshots live under `test/snapshots/`;
  numerical outputs are covered by run-to-run determinism, statistical,
  and property assertions instead of committed numeric fixture files.

### `trackingGeneratedPaths` (jitML scope)

The active project-specific tracked-generated-paths registry currently covers:

- `documents/cli/commands.md`
- `share/man/man1/jitml.1`
- `share/completion/bash/jitml`, `share/completion/zsh/_jitml`,
  `share/completion/fish/jitml.fish`
- `web/src/Generated/Contracts.purs`
- `web/src/Generated/AdminPortals.purs`
- `chart/templates/httproute-*.yaml`
- `chart/templates/grafana-dashboard-*.yaml`
- `chart/templates/prometheus-scrapeconfig-jitml.yaml`

Sprint `1.3` also records future generated-path patterns for:

- `share/man/man1/jitml-*.1`

### Governed-Document Metadata Lint (`jitml docs check`)

Sprint `0.3` makes the metadata contract executable. `JitML.Docs.Check` rejects
governed Markdown files missing `Status`, `Supersedes`, `Referenced by`,
`Generated sections`, or `Purpose`, and verifies that `Generated sections`
agrees with physical generated-region markers and the generated-section
registry.

## Container-Exclusive Code Quality

The mandatory `jitml:local` image is built on every substrate, including Apple
Silicon for the cluster daemon. That image build is the only supported Haskell
style and code-quality execution point:

1. Use the same pinned image-local GHC (`9.12.4`) for the project build and the
   Haskell style tools.
2. Build pinned `fourmolu` / `hlint` binaries into a deterministic image-owned
   tool location.
3. Stamp the image with the code-quality domain marker consumed by
   `src/JitML/Lint/Stack.hs`.
4. Run Fourmolu, HLint, `cabal format`, generated-doc/lint checks, and the
   warning-clean build gate during image construction.
5. Reject host `jitml lint *` and `jitml check-code` execution before linting.
   If the container marker or tools are absent, the diagnostic points to
   rebuilding and entering `jitml:local`.

## `jitml check-code`

Current `jitml check-code` delegates to the in-repo lint stack: whitespace and
final-newline normalization checks, forbidden repository paths, generated-doc
drift checks, required lint config checks, optional-directory checks for
`proto/` and `web/`, chart-shape checks, route-registry drift checks, and
forbidden subprocess/terminal primitive scans. It also runs the external
Haskell style stack through the typed `Subprocess` boundary and adds the
warning-clean build gate. The `jitml:local` image construction path runs this
same gate, and runtime use is supported only inside that image through the
headless `docker compose run --rm jitml ...` service. The GPU-enabled
`jitml-cuda` service is reserved for live CUDA tests, not code-quality runs.

Sprint `1.4` closes with `jitml check-code` and the Docker image build running
the full target stack:

1. `fourmolu --no-cabal --ghc-opt -XGHC2024 --mode check` over `src/`, `app/`,
   `test/`.
2. `hlint --with-group=default --with-group=extra --hint .hlint.yaml` over
   the same.
3. `cabal format` temp-file round-trip byte-equality on `jitml.cabal`.
4. `cabal build all --ghc-options=-Werror` (warning-clean build gate). Every
   `jitml.cabal` stanza additionally carries `-Werror=incomplete-patterns`, so
   a missing constructor fails an ordinary `cabal build` too.
5. `jitml lint files` (`forbiddenPathRegistry`, tracked-generated-paths,
   static-JIT artifact rejection, and ProductTruth scaffold/reachability lint).
6. `jitml lint docs` (metadata, relative links, forbidden stale commands).
7. `jitml lint chart`.
8. `jitml lint haskell` (forbidden subprocess and IO primitives, and the
   execution-path fail-open scan).
9. `jitml docs check` (generated-section drift).
10. `jitml lint purescript` / `spago test` keep the PureScript smoke suite on
    the `spec-node` runner rather than the deprecated generic `runSpec` alias.
11. `docker compose build jitml` proves the same gate runs
    as part of the mandatory image build.

## Cross-References

- [../../README.md](../../README.md)
- [../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md](../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md)
- [../../DEVELOPMENT_PLAN/phase-3-cluster-substrate-and-routing.md](../../DEVELOPMENT_PLAN/phase-3-cluster-substrate-and-routing.md)
- [../documentation_standards.md](../documentation_standards.md)
