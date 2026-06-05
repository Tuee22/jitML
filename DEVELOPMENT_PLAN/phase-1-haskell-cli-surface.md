# Phase 1: Haskell CLI Surface, `CommandSpec`, Lint Stack

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md),
[development_plan_standards.md](development_plan_standards.md),
[system-components.md](system-components.md),
[phase-0-planning-documentation.md](phase-0-planning-documentation.md),
[phase-2-bootstrap-reconciler-and-jit-cache.md](phase-2-bootstrap-reconciler-and-jit-cache.md),
[phase-3-cluster-substrate-and-routing.md](phase-3-cluster-substrate-and-routing.md),
[phase-5-jitml-service-daemon.md](phase-5-jitml-service-daemon.md),
[phase-12-test-stanzas-and-cross-cluster.md](phase-12-test-stanzas-and-cross-cluster.md),
[../README.md](../README.md)
**Generated sections**: none

> **Purpose**: Stand up the `jitml` Haskell binary, the `CommandSpec`-driven CLI
> surface, the typed `Subprocess` / `Plan` / `apply` / prerequisite / `Env` /
> `AppError` boundaries, the doctrine-mandated lint and code-quality stack, and the
> generated-section registry that every later phase consumes.

## Phase Status

✅ **Done** (re-closed 2026-06-04 after Sprint `1.11`). The original
CLI, `CommandSpec`, lint, prerequisite, environment, and error-surface
obligations remain closed, and the narrow reopened
toolchain-compatibility cleanup removed the scoped `allow-newer` block,
downgraded the project to the single pinned GHC `9.12.4` / Cabal
`3.16.1.0` toolchain, removed the upstream source pins and local
`third_party/haskell/lens-family-*` compatibility packages, and validated a
plain-Hackage solve.

The phase owns
[Exit Definition](README.md#exit-definition) items 11 (Plan/Apply
`--dry-run` / `--plan-file`), 12 (typed `Subprocess` boundary), 13 (one
`prerequisiteRegistry`), 14 (single `AppError` ADT and `renderError`), 15
(`fourmolu.yaml` + lint targets), 16 (`CommandSpec` as implementation
source) and contributes to item 4 (stage-0 entrypoints + typed prerequisite
DAG). Sprints `1.1`–`1.11` are closed. Sprint `1.4` includes the
container-exclusive style/code-quality rule: `docker/Dockerfile` installs
pinned Fourmolu / HLint binaries with the same image-local GHC `9.12.4` used
for the project build, runs the Haskell style/code-quality gate during image
construction, and rejects host lint/check-code execution before linting.

## Phase Summary

This phase delivers the single-binary `jitml` CLI built by Cabal under the pinned
toolchain (GHC `9.12.4`, Cabal `3.16.1.0`), with the library-first layout (`app/`
shims, `src/JitML/`), the `CommandSpec` registry as the code source for the
parser and every generated artefact (markdown command reference, manpages, shell
completions, JSON command schema, tree output), the typed `Subprocess` / `Plan` /
`apply` / `prerequisiteRegistry` / `Env` / `AppError` patterns from
[../README.md](../README.md), the
`forbiddenPathRegistry`, and the `GeneratedSectionRule` /
`trackingGeneratedPaths` registries. The Phase `1` lint stack runs the
doctrine's `fourmolu` + `hlint` + `cabal format` + warning-clean build gate
from the canonical `jitml` command surface.

Phase `1` writes no daemon code, no cluster code, no ML code, no chart code, and
no PureScript. Its sole job is the CLI scaffold and the doctrine boundaries that
every subsequent phase plugs into, with the narrow Dockerfile touch required for
the style-tool/code-quality image gate.

### Current Implementation Scope

The current codebase contains the Cabal package, two executable shims, the
`CommandSpec` registry/parser/help/JSON/tree renderers, generated CLI docs,
tracked generated CLI paths, in-repo lint checks, the prerequisite registry,
generic command-plan rendering, and local command dispatch. Later-phase command
leaves are registered, but many currently dispatch to deterministic summaries or
file materializers rather than live cluster, daemon, training, or JIT effects.
The active `trackingGeneratedPaths` registry protects CLI docs, the main
manpage, shell completions, PureScript contracts, route YAML, Grafana dashboard
YAML, and the Prometheus scrape config. The remaining future generated-path
pattern is for per-command manpages (`share/man/man1/jitml-*.1`). The
Plan/Apply `apply` interpreter is currently a no-op, and normal command
execution enters the plan renderer only when `--dry-run` or `--plan-file` is
requested on selected plan-capable leaves. Phase `1`'s Haskell lint and
code-quality gate is container-exclusive: the mandatory `jitml:local` image
build uses the same pinned GHC `9.12.4` for the project and pinned Fourmolu /
HLint binaries, then runs `jitml check-code`. Sprint `1.10` retired the scoped
`allow-newer` compatibility block, and Sprint `1.11` removed the old
source-pin/vendor helper by downgrading to the GHC `9.12.4` / `base-4.21`
baseline that solves from plain Hackage.

## Sprint 1.1: Toolchain Pin and Library-First Cabal Project ✅

**Status**: Done
**Implementation**: `jitml.cabal`, `cabal.project`, `app/Main.hs`, `app/Demo.hs`,
`src/JitML/App.hs`, `.gitignore`, `.dockerignore`
**Docs to update**: `documents/engineering/cli_command_surface.md`,
`documents/engineering/code_quality.md`,
`DEVELOPMENT_PLAN/system-components.md`

### Objective

Pin GHC `9.12.4` and Cabal `3.16.1.0` in the cabal manifest and project files,
declare both `jitml` and `jitml-demo` executables as six-line shims into
`App.main`, and lay down the library-first source tree with the standardized
library set per doctrine `Overview → standardized stack`.

### Deliverables

- `jitml.cabal` declares `cabal-version: 3.16`, `tested-with: ghc ==9.12.4`, the
  `jitml` library exposing `src/JitML/`, the two executables `jitml` and
  `jitml-demo` as six-line shims into `App.main`, and the ten test-suite stanzas
  named in [system-components.md → Test
  Stanzas](system-components.md#test-stanzas) (each `type: exitcode-stdio-1.0`).
- `cabal.project` declares `with-compiler: ghc-9.12.4`, records codegen-toolchain
  pin comments (LLVM, NVCC, Metal/`swiftc`, oneDNN), the `kindest/node` mirror-pin
  comment, and the report-card knob list from [system-components.md → POC Report-Card
  Knobs](system-components.md#poc-report-card-knobs).
- `cabal.project` carries no `allow-newer` override, no source-repository
  package pins, and no local dependency packages. The GHC `9.12.4` /
  `base-4.21` package set solves from plain Hackage.
- `app/Main.hs` and `app/Demo.hs` are six-line shims into `App.main` and
  `App.demoMain`. No business logic in `app/`.
- `src/JitML/App.hs` exports `main` and `demoMain` and is the single composition
  root for the CLI runner per doctrine
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

1. `cabal build all` builds the `jitml` and `jitml-demo` shells under GHC
   `9.12.4`.
2. `cabal test all` runs the eight declared test stanzas; Phase `12` now supplies the
   dedicated deterministic bodies.
3. `grep '^tested-with' jitml.cabal` returns `tested-with:   ghc ==9.12.4`.
4. `grep '^with-compiler' cabal.project` returns `with-compiler: ghc-9.12.4`.
5. Every report-card knob from [system-components.md → POC Report-Card
   Knobs](system-components.md#poc-report-card-knobs) is grep-findable in
   `cabal.project`.

### Remaining Work

None.

## Sprint 1.2: `CommandSpec` Registry and Generated Parser ✅

**Status**: Done
**Implementation**: `src/JitML/CLI/Spec.hs`, `src/JitML/CLI/Parser.hs`,
`src/JitML/CLI/Tree.hs`, `src/JitML/CLI/Json.hs`, `src/JitML/CLI/Help.hs`,
`test/unit/Main.hs`
**Docs to update**: `documents/engineering/cli_command_surface.md`

### Objective

Establish the `CommandSpec` registry as the single implementation source for the
parser, the command tree (`jitml commands --tree`), the JSON command schema
(`jitml commands --json`), the markdown command reference, the manpages, and the
shell completion scripts per doctrine `Command Topology` and `Automatically
Generated Documentation`.

### Deliverables

- `CommandSpec`, `OptionSpec`, and `Example` records live in
  `src/JitML/CLI/Spec.hs` with the doctrine-mandated fields (`name`, `summary`,
  `description`, `children`, `options`, `examples`, `longName`, `shortName`,
  `metavar`, `description`, `required`).
- The `CommandSpec` registry covers every command surface from
  [system-components.md → Haskell CLI
  Surface](system-components.md#haskell-cli-surface): `cluster up`, `cluster down`,
  `cluster status`, `cluster reset`, `service`, `train`, `eval`, `tune`,
  `rl train`, `rl eval`, `rl rollout`, `verify same-run`, `verify cross-backend`,
  `verify replay`, `inspect list`, `inspect show`, `inspect replay`,
  `inspect trial`, `inspect frontier`, `bench train`, `bench inference`,
  `bench env`, `inference run`, `test all`, every per-stanza `test` leaf,
  `lint files|docs|proto|chart|haskell|purescript|all`, `docs check`,
  `docs generate`, `check-code`, `build`, `kubectl`,
  `internal materialize-substrate`, `internal list-prereqs`, `internal gc`,
  `internal vm bootstrap|up|down|status|exec`, `internal cache stat|list|evict`,
  `commands`, and `help`. Each leaf carries at least one `Example`.
- The parser in `src/JitML/CLI/Parser.hs` is generated from the registry — it is
  a renderer of the spec, not its own source. Hand-written
  `optparse-applicative` parsers outside the renderer are hlint-forbidden.
- `jitml commands` flat-prints the leaf commands; `jitml commands --tree` renders
  the tree; `jitml commands --json` emits the JSON schema. All three are
  generated from one walk of the registry.
- `jitml help <subcommand>` is equivalent to `<subcommand> --help`; same
  renderer.
- Parser-test category via `execParserPure` lives under `test/unit/` per
  doctrine `Testing Doctrine → Parser Tests`.

### Validation

1. `jitml commands --tree` emits a deterministic tree spanning every command
   from [system-components.md → Haskell CLI
   Surface](system-components.md#haskell-cli-surface).
2. `jitml commands --json | jq '.commands | length'` matches the leaf count.
3. `jitml help cluster up` and `jitml cluster up --help` produce byte-identical
   output.
4. `jitml-unit` exercises `execParserPure` for the canonical surface and asserts
   parser/registry agreement.

### Remaining Work

None.

## Sprint 1.3: Generated Sections and Tracking-Generated Paths ✅

**Status**: Done
**Implementation**: `src/JitML/Generated/Registry.hs`,
`src/JitML/Generated/Paths.hs`, `src/JitML/Docs/Check.hs`,
`src/JitML/Docs/Generate.hs`, `src/JitML/Docs/Render.hs`,
`documents/cli/commands.md`,
`share/man/man1/jitml.1`, `share/completion/{bash,zsh,fish}/`
**Docs to update**: `documents/documentation_standards.md`,
`documents/engineering/code_quality.md`

### Objective

Stand up the `GeneratedSectionRule` registry for marker-delimited generated
regions and the `trackingGeneratedPaths` registry for fully-generated files,
plus the paired `jitml docs check` / `jitml docs generate` reconciler per
doctrine `Generated Artifacts → The generated-section registry`.

### Deliverables

- Active `GeneratedSectionRule` entries in
  `src/JitML/Generated/Registry.hs` cover:
  - the command tree and command registry snapshots inside `README.md` (keys
    `command-tree`, `command-registry`),
  - the CLI help blocks inside `documents/engineering/cli_command_surface.md`
    (key `cli-commands.help-blocks`),
  - the generated-section index inside `documents/documentation_standards.md`
    (key `documentation-standards.generated-section-index`),
  - the cluster route table, daemon surface table, numerical catalog tables,
    RL algorithm catalog table, and hyperparameter tuning catalog tables.
- `futureGeneratedSections` records the remaining marker family that a later
  phase still owns: `cross-language-types.*`.
- Active `trackingGeneratedPaths` entries in `src/JitML/Generated/Paths.hs`
  cover:
  - `documents/cli/commands.md`,
  - `share/man/man1/jitml.1`,
  - `share/completion/bash/jitml`,
  - `share/completion/zsh/_jitml`,
  - `share/completion/fish/jitml.fish`,
  - `web/src/Generated/Contracts.purs`,
  - every `chart/templates/httproute-*.yaml` rendered from
    `src/JitML/Routes.hs`,
  - every `chart/templates/grafana-dashboard-*.yaml` rendered from
    `src/JitML/Observability/Grafana.hs`,
  - `chart/templates/prometheus-scrapeconfig-jitml.yaml`.
- `futureTrackingGeneratedPathPatterns` records later generated files:
  `share/man/man1/jitml-*.1`. The owning later sprint moves a future pattern
  into an active tracked path when the renderer lands.
- `jitml docs check` walks both registries, fails on drift with the doctrine's
  three-element error message (file path, marker key, literal `` Run `jitml
  docs generate` to update. ``).
- `jitml docs generate` writes the current renderer output between every marker
  pair and atomically replaces every tracked-generated file.
- `jitml docs generate` is a reconciler: re-running it on a steady-state tree
  exits `3` (no-op-on-match) per [00-overview.md → Hard Constraints item
  11](00-overview.md#hard-constraints).
- The CLI markdown reference, the manpages, and the three shell completion
  scripts are populated for the Sprint `1.2` command surface.

### Validation

1. `jitml docs check` exits `0` on a freshly-generated tree.
2. Hand-editing any tracked-generated file or any marker-delimited region
   surfaces the three-element error from `jitml docs check` and a non-zero exit.
3. `jitml docs generate` followed by `jitml docs generate` returns exit `0`
   (first run mutates) then exit `3` (no-op).

### Remaining Work

None.

## Sprint 1.4: Lint Stack, `fourmolu`, `hlint`, `cabal format`, `forbiddenPathRegistry` ✅

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

## Sprint 1.5: `Plan` / `apply` Boundary with `--dry-run` and `--plan-file` ✅

**Status**: Done
**Implementation**: `src/JitML/Plan/Plan.hs`, `src/JitML/Plan/Apply.hs`,
`src/JitML/Plan/Render.hs`
**Docs to update**: `documents/engineering/haskell_code_guide.md`

### Objective

Establish the `Plan` / `apply` separation per doctrine `Plan / Apply`, with
`--dry-run` and `--plan-file <path>` on every Plan/Apply command.

### Deliverables

- `Plan` ADT in `src/JitML/Plan/Plan.hs` parameterised over `inputs` and
  `result`. `build :: inputs -> Either AppError Plan` is pure; `apply :: Env ->
  Plan -> IO ExitCode` is the only IO-ful side.
- `--dry-run` renders the plan to stdout via `renderPlan` and exits `0`.
- `--plan-file <path>` writes the rendered plan to `<path>` for out-of-band
  review and exits `0`.
- The current Plan/Apply branch is wired for `jitml bootstrap`, `jitml service`,
  `jitml cluster up`, `jitml train`, `jitml tune`, `jitml rl train`,
  `jitml test all`, and `jitml internal gc` when `--dry-run` or `--plan-file` is
  requested. Normal command execution still uses local command implementations;
  live effectful application remains later-phase work.

### Validation

1. `jitml train --dry-run path/to/experiment.dhall` emits a typed plan and
   exits `0` without side effects.
2. `jitml train --plan-file /tmp/p.txt path/to/experiment.dhall` writes
   `/tmp/p.txt` and exits `0`.
3. `jitml-unit` exercises pure `build` invariants (snapshot render of the empty
   plan, idempotence of `--plan-file`).

### Remaining Work

None.

## Sprint 1.6: `Subprocess` Typed Values, `runStreaming` / `capture` Interpreter ✅

**Status**: Done
**Implementation**: `src/JitML/Sub/Subprocess.hs`, `src/JitML/Sub/Stream.hs`,
`src/JitML/Sub/Render.hs`
**Docs to update**: `documents/engineering/haskell_code_guide.md`

### Objective

Make `Subprocess` the only IO boundary for subprocess execution per doctrine
`Architecture → Subprocesses as Typed Values`. `kubectl`, `helm`, `kind`,
`docker`, `tart`, and the per-substrate kernel compilers all flow through it in
later phases.

### Deliverables

- `Subprocess` record in `src/JitML/Sub/Subprocess.hs` carrying
  `subprocessPath`, `subprocessArguments`, `subprocessWorkingDirectory`, and
  optional stdin payload. It deliberately does not carry process-environment
  overrides; command configuration is explicit in arguments, working directory,
  stdin, Dhall, or typed config.
- `renderSubprocess :: Subprocess -> Text` is pure and used by the Plan
  renderer and the structured logger.
- `runStreaming :: Env -> Subprocess -> IO (ExitCode, Text, Text)` and
  `capture :: Env -> Subprocess -> IO (ExitCode, ByteString, ByteString)` are
  the only IO interpreters.
- The Sprint `1.4` in-repo primitive scan refuses `callProcess`,
  `readCreateProcess`, `System.Process.*`, and `typed-process` smart
  constructors outside this module.

### Validation

1. `jitml lint haskell` reports zero violations of the forbidden subprocess
   primitives across `src/`.
2. `jitml-unit` exercises `renderSubprocess` snapshot tests for the Plan renderer.
3. `jitml-integration` exercises `runStreaming` against a fixture binary and
   asserts the typed `(ExitCode, Text, Text)` shape.

### Remaining Work

None.

## Sprint 1.7: Prerequisite Registry as Typed Effects ✅

**Status**: Done
**Implementation**: `src/JitML/Prerequisite/Registry.hs`,
`src/JitML/Prerequisite/Reconcile.hs`
**Docs to update**: `documents/engineering/haskell_code_guide.md`

### Objective

Stand up the typed `prerequisiteRegistry` per doctrine `Prerequisites as Typed
Effects`. This is the in-process source of truth that the bootstrap shell
scripts (Phase `2`) reflect.

### Deliverables

- `Prerequisite` record carrying `nodeId`, `nodeDescription`, predicate
  (`Env -> IO Bool`), optional remediation `Subprocess`, and `dependsOn :: [NodeId]`.
- `prerequisiteRegistry :: [Prerequisite]` is the in-process registry; the
  current tree is populated by later phases with toolchain, container, cluster,
  and frontend/infrastructure prerequisite nodes.
- `reconcilePrerequisites :: Env -> NodeId -> IO (Either AppError ())`
  evaluates the transitive closure rooted at `NodeId` and emits
  `AppError PrerequisiteUnmet (failingNodeId, description, remedyHint)` on
  failure. Exit code is `2`.
- `jitml doctor [--scope toolchain|container|cluster]` currently calls
  `reconcilePrerequisites`; `jitml doctor --scope <scope> --remediate` builds and
  applies typed remediation plans. The target live mutation leaves (`cluster up`,
  `train`, `tune`, `service`, `build`, `test all`) must call the prerequisite
  gate before effectful apply once those commands stop being local summaries.

### Validation

1. A synthetic missing prerequisite surfaces the typed error and exit `2`.
2. The structured diagnostic names the failing node, its description, and its
   remediation hint.

### Remaining Work

None.

## Sprint 1.8: `Env` Record and `ReaderT Env IO` Runner ✅

**Status**: Done
**Implementation**: `src/JitML/Env/Env.hs`, `src/JitML/Env/Build.hs`
**Docs to update**: `documents/engineering/haskell_code_guide.md`

### Objective

Establish the single `Env` record and the `ReaderT Env IO` runner that command
runners thread through, per doctrine `Application Environment`.

### Deliverables

- `Env` record in `src/JitML/Env/Env.hs` carrying:
  - `envCacheDir :: Path Abs Dir` (resolves explicit `--cache-dir <path>` or
    defaults to `./.build/`),
  - `envDataDir :: Path Abs Dir` (resolves explicit `--data-dir <path>` or
    defaults to `./.data/`),
  - `envFormat :: OutputFormat`, `envColor :: ColorMode`,
  - `envLogger :: Subprocess -> ExitCode -> Text -> IO ()` (defaults to
    structured JSON on stderr; daemon overrides),
  - `envClock :: IO MonotonicTime` (test-hook seam per doctrine
    [§Test hooks in Env](../README.md)).
- `buildEnv :: GlobalFlags -> IO Env` is the single entry point used by
  `App.main`.
- All command runners are `ReaderT Env IO` actions; raw `IO` is hlint-forbidden
  outside `runStreaming` / `capture` and the daemon main loop.

### Validation

1. `jitml --format json commands --json | jq '.format'` returns `"json"`.
2. `jitml --cache-dir /tmp/jitml internal gc <hash> --dry-run` resolves the
   cache against the explicit CLI override.

### Remaining Work

None.

## Sprint 1.9: `AppError` ADT, `renderError`, Output Rules ✅

**Status**: Done
**Implementation**: `src/JitML/CLI/Output.hs`, `src/JitML/AppError/AppError.hs`,
`src/JitML/AppError/Render.hs`
**Docs to update**: `documents/engineering/haskell_code_guide.md`,
`documents/engineering/cli_command_surface.md`

### Objective

Land the canonical `AppError` ADT, the single Text rendering boundary
`renderError`, exit codes including the `3`-on-no-op-on-match for reconcilers,
and the doctrine-mandated output flags `--format` and `--color`.

### Deliverables

- `AppError` ADT in `src/JitML/AppError/AppError.hs` carries the canonical
  17-variant set per [system-components.md → CLI Doctrine
  Components](system-components.md#cli-doctrine-components):
  `PrerequisiteUnmet`, `SubprocessFailed`, `MinIOFailed`, `PulsarFailed`,
  `HarborFailed`, `KubectlFailed`, `DocsCheckDrift`, `UnknownCommand`,
  `InvalidConfig`, `DhallTypeError`, `ChartLintFailed`, `RouteRegistryDrift`,
  `JitCacheMiss`, `JitToolchainDrift`, `CheckpointFormatUnsupported`,
  `CheckpointWriteConflict`, `ReconcilerNoop`.
- `renderError :: AppError -> Text` is the only Text rendering at the CLI
  boundary, defined in `src/JitML/CLI/Output.hs`. Sprint `1.4` has `.hlint.yaml`
  hints and an in-repo primitive scan for direct terminal formatting and
  subprocess primitives outside their approved modules.
- Exit codes follow doctrine `Error Handling` plus `3` on `ReconcilerNoop`
  (already declared in [00-overview.md → Hard Constraints item
  11](00-overview.md#hard-constraints)).
- Global flags `--format json|table|plain` and `--color auto|always|never` plus
  `--no-color` are wired through `Env` per doctrine `Output Rules`. Default is
  `table` on TTY else `plain`.

### Validation

1. Each `AppError` variant has a snapshot render fixture under
   `test/snapshots/cli/` (pure renderer output — falls under
   [../README.md → Snapshot targets](../README.md#snapshot-targets)).
2. Exit code on a forced `ReconcilerNoop` is `3`.
3. `jitml --format json commands` emits valid JSON; `jitml --format plain
   commands` emits a deterministic plain-text list.

### Remaining Work

None.

## Sprint 1.10: Scoped `allow-newer` Retirement Gate ✅

**Status**: Done
**Implementation**: `cabal.project`,
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`
**Docs to update**: `README.md`, `documents/engineering/code_quality.md`,
`DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`,
`DEVELOPMENT_PLAN/system-components.md`

### Objective

Remove the scoped `allow-newer` block from `cabal.project`. This sprint first
closed the override by using temporary upstream source pins and local
`lens-family` compatibility packages; Sprint `1.11` later removed that helper
when the project baseline moved to GHC `9.12.4`.

### Deliverables

- `cabal.project` drops the compatibility override entirely.
- The `Scoped allow-newer for Dhall / CBOR transitive package bounds` row moves
  from Pending Removal to Completed in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).
- The source-pin/vendor helper introduced during this sprint is no longer part
  of the current package set; Sprint `1.11` deletes it.

### Validation

1. `cabal build all --dry-run` solves with no `allow-newer` stanza in
   `cabal.project`.
2. `docker compose build jitml` passes and the image build runs the
   container-only `jitml check-code` gate.
3. `docker compose run --rm jitml jitml check-code` passes after the block is
   removed.

### Remaining Work

None.

## Sprint 1.11: GHC 9.12.4 Baseline and Dependency Helper Retirement ✅

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

## Doctrine Sections Cited

- [../README.md → Toolchain pinning](../README.md#toolchain-pinning) (Sprints 1.1, 1.10, 1.11)
- [../README.md → Repository layout (target)](../README.md#repository-layout-target) (Sprint 1.1)
- [../README.md → CLI command topology, typed](../README.md#cli-command-topology-typed) (Sprint 1.2)
- [../README.md → Generated documentation flow](../README.md#generated-documentation-flow) (Sprints 1.2, 1.3)
- [../README.md → Command introspection](../README.md#cli-command-topology-typed) (Sprint 1.2)
- [../README.md → Generated artifacts](../README.md#generated-documentation-flow) (Sprint 1.3)
- [../README.md → Lint matrix](../README.md#lint-matrix) (Sprint 1.4)
- [../README.md → Plan / Apply commands](../README.md#doctrine-scope) (Sprint 1.5)
- [../README.md → Subprocesses as Typed Values](../README.md#doctrine-scope) (Sprint 1.6)
- [../README.md → Prerequisites as typed effects](../README.md#prerequisites-as-typed-effects) (Sprint 1.7)
- [../README.md → Application Environment](../README.md#doctrine-scope) (Sprint 1.8)
- [../README.md → Error Handling](../README.md#exit-codes-and-error-rendering) (Sprint 1.9)
- [../README.md → Output Rules](../README.md#doctrine-scope) (Sprint 1.9)
- [../README.md → Reconcilers](../README.md#doctrine-scope) (Sprint 1.3, 1.9)

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/cli_command_surface.md` — populate the project-specific
  command matrix; link generated tables (key `cli-commands.help-blocks`) to the
  `GeneratedSectionRule` registry.
- `documents/engineering/code_quality.md` — name the thirteen `fourmolu` settings,
  the project-specific hlint rules, the `forbiddenPathRegistry`, the
  container-exclusive style/code-quality gate, the chart-shape lint, the
  no-`allow-newer` package set, and the single-GHC `9.12.4` code-quality image
  from Sprint `1.11`.
- `documents/engineering/unit_testing_policy.md` — record that
  `jitml lint haskell` runs inside `jitml:local`.
- `documents/engineering/cluster_topology.md` — record that the `jitml:local`
  image build is also the Haskell style-tool/code-quality gate on every
  substrate.
- `documents/engineering/haskell_code_guide.md` — name the `Subprocess`,
  `Plan / apply`, prerequisite, `Env`, and `AppError` patterns with project-
  specific elaborations (the 17-variant `AppError` enumeration).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- `system-components.md → CLI Doctrine Components` rows for Sprint `1.1`–`1.11`
  remain aligned with the implemented command, lint, parser, subprocess,
  plan/apply, prerequisite, env, and error-rendering surfaces.
- `legacy-tracking-for-deletion.md` enqueues a row only if Sprint `0.2`'s audit
  surfaces a doctrine-adoption gap that this phase does not own.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [development_plan_standards.md](development_plan_standards.md)
- [../README.md](../README.md)
