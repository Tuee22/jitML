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
[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
**Generated sections**: none

> **Purpose**: Stand up the `jitml` Haskell binary, the `CommandSpec`-driven CLI
> surface, the typed `Subprocess` / `Plan` / `apply` / prerequisite / `Env` /
> `AppError` boundaries, the doctrine-mandated lint and code-quality stack, and the
> generated-section registry that every later phase consumes.

## Phase Status

✅ **Done** — Sprints `1.1` (toolchain pin and library-first Cabal project),
`1.2` (`CommandSpec` registry and generated parser), `1.3`
(`GeneratedSectionRule` and tracked-generated paths), `1.4` (lint stack and
`forbiddenPathRegistry`), `1.5` (`Plan` / `apply` boundary), `1.6`
(`Subprocess` typed values), `1.7` (typed prerequisite registry), and `1.8`
(`Env` and `ReaderT Env IO`) are `✅ Done`; Sprint `1.9` (`AppError`,
`renderError`, and output rules) is also `✅ Done`.

## Phase Summary

This phase delivers the single-binary `jitml` CLI built by Cabal under the pinned
toolchain (GHC `9.14.1`, Cabal `3.16.1.0`), with the library-first layout (`app/`
shims, `src/JitML/`), the `CommandSpec` registry as the code source for the
parser and every generated artefact (markdown command reference, manpages, shell
completions, JSON command schema, tree output), the typed `Subprocess` / `Plan` /
`apply` / `prerequisiteRegistry` / `Env` / `AppError` patterns from
[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md), the `fourmolu` + `hlint` +
`cabal format` lint stack, the `forbiddenPathRegistry`, and the
`GeneratedSectionRule` / `trackingGeneratedPaths` registries.

Phase `1` writes no daemon code, no cluster code, no ML code, no chart code, and
no PureScript. Its sole job is the CLI scaffold and the doctrine boundaries that
every subsequent phase plugs into.

## Sprint 1.1: Toolchain Pin and Library-First Cabal Project ✅

**Status**: Done
**Implementation**: `jitml.cabal`, `cabal.project`, `app/Main.hs`, `app/Demo.hs`,
`src/JitML/App.hs`, `.gitignore`, `.dockerignore`
**Docs to update**: `documents/engineering/cli_command_surface.md`,
`documents/engineering/code_quality.md`,
`DEVELOPMENT_PLAN/system-components.md`

### Objective

Pin GHC `9.14.1` and Cabal `3.16.1.0` in the cabal manifest and project files,
declare both `jitml` and `jitml-demo` executables as six-line shims into
`App.main`, and lay down the library-first source tree with the standardized
library set per doctrine `Overview → standardized stack`.

### Deliverables

- `jitml.cabal` declares `cabal-version: 3.16`, `tested-with: ghc ==9.14.1`, the
  `jitml` library exposing `src/JitML/`, the two executables `jitml` and
  `jitml-demo` as six-line shims into `App.main`, and the ten test-suite stanzas
  named in [system-components.md → Test
  Stanzas](system-components.md#test-stanzas) (each `type: exitcode-stdio-1.0`).
- `cabal.project` declares `with-compiler: ghc-9.14.1`, the codegen-toolchain pins
  (LLVM, NVCC, Xcode/Metal, oneDNN), the `kindest/node` mirror-pin comment, and
  the report-card knob list from [system-components.md → POC Report-Card
  Knobs](system-components.md#poc-report-card-knobs).
- `cabal.project` carries a narrow GHC `9.14.1` compatibility override for Dhall's
  transitive CBOR stack while upstream package bounds catch up; the removal is
  tracked in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md#pending-removal).
- `app/Main.hs` and `app/Demo.hs` are six-line shims into `App.main` and
  `App.demoMain`. No business logic in `app/`.
- `src/JitML/App.hs` exports `main` and `demoMain` and is the single composition
  root for the CLI runner per doctrine
  [§Project Structure](../HASKELL_CLI_TOOL.md).
- The standardized library set is declared in `jitml.cabal`'s
  `library.build-depends`: `optparse-applicative`, `text`, `bytestring`, `aeson`,
  `prettyprinter`, `prettyprinter-ansi-terminal`, `ansi-terminal`, `path`,
  `path-io`, `typed-process`, `safe-exceptions`, `dhall`, `tasty`, `tasty-hunit`,
  `tasty-quickcheck`, `tasty-golden`, `temporary`. Project-specific additions
  (`pulsar-client-haskell`, `minio-hs`, `purescript-bridge`, etc.) appear in
  later sprints.
- `.gitignore` lists `./.build/`, `./.data/`, `./dist-newstyle/`,
  `./.hlint-output`. `.dockerignore` mirrors.

### Validation

1. `cabal build all` builds the empty `jitml` and `jitml-demo` shells under GHC
   `9.14.1`.
2. `cabal test all` runs (no test stanzas have bodies yet; each prints a success
   sentinel and exits `0`).
3. `grep '^tested-with' jitml.cabal` returns `tested-with: ghc ==9.14.1`.
4. `grep '^with-compiler' cabal.project` returns `with-compiler: ghc-9.14.1`.
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

- `GeneratedSectionRule` registry in `src/JitML/Generated/Registry.hs` covers:
  - the command tree and command registry snapshots inside `README.md` (keys
    `command-tree`, `command-registry`),
  - the markdown command reference at `documents/cli/commands.md` (key
    `cli-commands.reference`),
  - the CLI help blocks inside `documents/engineering/cli_command_surface.md`
    (key `cli-commands.help-blocks`),
  - the route table in [`documents/engineering/cluster_topology.md`](../documents/engineering/cluster_topology.md)
    (key `cluster.routes` — populated when Phase `3` lands the route registry),
  - the layer / activation / optimizer / scheduler / loss tables in
    [`documents/engineering/numerical_core.md`](../documents/engineering/numerical_core.md)
    (key prefix `numerics.*` — populated by Phase `6`),
  - the RL algorithm catalog table in
    [`documents/engineering/training_workloads.md`](../documents/engineering/training_workloads.md)
    (key `training.rl.catalog` — populated by Phase `9`),
  - the daemon endpoint and config table in
    [`documents/engineering/daemon_architecture.md`](../documents/engineering/daemon_architecture.md)
    (key `daemon.surface` — populated by Phase `5`).
- `trackingGeneratedPaths` registry in `src/JitML/Generated/Paths.hs` covers:
  - `documents/cli/commands.md`,
  - `share/man/man1/jitml.1`, `share/man/man1/jitml-*.1`,
  - `share/completion/bash/jitml`,
  - `share/completion/zsh/_jitml`,
  - `share/completion/fish/jitml.fish`,
  - `web/src/Generated/Contracts.purs` (added by Phase `11`),
  - `chart/templates/httproute-*.yaml` (added by Phase `3`),
  - `chart/templates/grafana-dashboard-*.yaml` (added by Phase `4`).
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
`src/JitML/Lint/Stack/Types.hs`, `test/haskell-style/`
**Docs to update**: `documents/engineering/code_quality.md`

### Objective

Pin the doctrine-mandated `fourmolu` settings, layer `hlint` and `cabal format`
on top, declare the `forbiddenPathRegistry`, register the chart-shape lint, and
wire the entire stack into the `jitml-haskell-style` test stanza and the
`jitml lint` / `jitml check-code` commands per doctrine `Lint, Format, and
Code-Quality Stack`.

### Deliverables

- `fourmolu.yaml` at repo root pins the twelve doctrine-mandated settings
  (`indentation`, `column-limit`, `function-arrows`, `comma-style`,
  `import-export-style`, `indent-wheres`, `record-brace-space`,
  `newlines-between-decls`, `haddock-style`, `let-style`, `in-style`, `unicode`).
- `.hlint.yaml` declares the doctrine-required hlint rules: forbid `print`,
  `exitFailure`, direct terminal formatting (`putStrLn`, `hPutStrLn stdout`)
  outside `src/JitML/CLI/Output.hs`; forbid `callProcess`, `readCreateProcess`,
  `System.Process.*`, and `typed-process` smart constructors outside
  `src/JitML/Sub/Stream.hs` (the `runStreaming` / `capture` interpreter); forbid
  hand-written HTTPRoute YAML in `chart/templates/`; forbid use of `IO` outside
  the `runStreaming` / `capture` interpreter and the daemon main loop.
- `forbiddenPathRegistry` in `src/JitML/Lint/ForbiddenPaths.hs` refuses
  `.github/workflows/`, `.husky/`, `.githooks/`, `.pre-commit-config.yaml`, root
  `Makefile` / `justfile` / `Taskfile.yml`. `jitml lint files` enforces.
- `src/JitML/Lint/Chart.hs` enforces: every StorageClass uses
  `kubernetes.io/no-provisioner`; every PV has an explicit `claimRef.namespace`
  and `claimRef.name`; every PVC is created only by a StatefulSet's
  `volumeClaimTemplates`; every hostPath under `chart/templates/pv-*.yaml`
  matches `<namespace>/<StatefulSet>/pv_<replica-int>` per
  [00-overview.md → Hard Constraint 15](00-overview.md#hard-constraints).
- `cabal format` round-trip byte-equality is enforced by writing the output to
  a temp file and comparing against the source.
- The `jitml-haskell-style` test-suite stanza calls each tool through the typed
  `Subprocess` boundary (introduced in Sprint `1.6`) and aggregates results.
- `jitml check-code` runs the full stack plus the warning-clean build gate
  (`cabal build all -fwerror`).

### Validation

1. `jitml lint all` exits `0` on a freshly-formatted tree.
2. Introducing any forbidden path or hand-formatted source surfaces a typed
   error and a non-zero exit code.
3. `jitml-haskell-style` passes under `cabal test`.

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
- The Plan/Apply consumers — `jitml train`, `jitml tune`, `jitml cluster up`,
  `jitml test all`, `jitml service` startup-as-plan, `jitml internal gc` — all
  go through the same boundary.

### Validation

1. `jitml train --dry-run path/to/experiment.dhall` emits a typed plan and
   exits `0` without side effects.
2. `jitml train --plan-file /tmp/p.txt path/to/experiment.dhall` writes
   `/tmp/p.txt` and exits `0`.
3. `jitml-unit` exercises pure `build` invariants (golden render of the empty
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
  `subprocessPath`, `subprocessArguments`, `subprocessEnvironment`,
  `subprocessWorkingDirectory`.
- `renderSubprocess :: Subprocess -> Text` is pure and used by the Plan
  renderer and the structured logger.
- `runStreaming :: Env -> Subprocess -> IO (ExitCode, Text, Text)` and
  `capture :: Env -> Subprocess -> IO (ExitCode, ByteString, ByteString)` are
  the only IO interpreters.
- The hlint rules from Sprint `1.4` refuse `callProcess`, `readCreateProcess`,
  `System.Process.*`, and `typed-process` smart constructors outside this
  module.

### Validation

1. `jitml lint haskell` reports zero violations of the forbidden subprocess
   primitives across `src/`.
2. `jitml-unit` exercises `renderSubprocess` golden tests for the Plan renderer.
3. `jitml-integration` exercises `runStreaming` against a sentinel binary and
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
- `prerequisiteRegistry :: [Prerequisite]` enumerates the empty initial set;
  Phases `2`–`12` populate it (toolchain nodes by Phase `2`; cluster /
  Pulsar / MinIO / Harbor nodes by Phases `3`–`4`; Pulumi node by Phase `12`).
- `reconcilePrerequisites :: Env -> NodeId -> IO (Either AppError ())`
  evaluates the transitive closure rooted at `NodeId` and emits
  `AppError PrerequisiteUnmet (failingNodeId, description, remedyHint)` on
  failure. Exit code is `2`.
- Every `jitml` CLI entry point that mutates external state (`cluster up`,
  `train`, `tune`, `service`, `build`, `test all`) calls
  `reconcilePrerequisites` before `apply`.

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
  - `envCacheDir :: Path Abs Dir` (resolves `--cache-dir <path>` →
    `$JITML_BUILD_DIR` → `./.build/`),
  - `envDataDir :: Path Abs Dir` (resolves `$JITML_DATA_DIR` → `./.data/`),
  - `envFormat :: OutputFormat`, `envColor :: ColorMode`,
  - `envLogger :: Subprocess -> ExitCode -> Text -> IO ()` (defaults to
    structured JSON on stderr; daemon overrides),
  - `envClock :: IO MonotonicTime` (test-hook seam per doctrine
    [§Test hooks in Env](../HASKELL_CLI_TOOL.md)).
- `buildEnv :: GlobalFlags -> IO Env` is the single entry point used by
  `App.main`.
- All command runners are `ReaderT Env IO` actions; raw `IO` is hlint-forbidden
  outside `runStreaming` / `capture` and the daemon main loop.

### Validation

1. `jitml --format json commands --json | jq '.format'` returns `"json"`.
2. `JITML_BUILD_DIR=/tmp/jitml jitml internal gc <hash> --dry-run` resolves the
   cache against the env override.

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
  boundary, defined in `src/JitML/CLI/Output.hs`. The hlint rules from Sprint
  `1.4` refuse `print`, `exitFailure`, and direct terminal formatting outside
  this module.
- Exit codes follow doctrine `Error Handling` plus `3` on `ReconcilerNoop`
  (already declared in [00-overview.md → Hard Constraints item
  11](00-overview.md#hard-constraints)).
- Global flags `--format json|table|plain` and `--color auto|always|never` plus
  `--no-color` are wired through `Env` per doctrine `Output Rules`. Default is
  `table` on TTY else `plain`.

### Validation

1. Each `AppError` variant has a golden render fixture under
   `test/golden/cli/`.
2. Exit code on a forced `ReconcilerNoop` is `3`.
3. `jitml --format json commands` emits valid JSON; `jitml --format plain
   commands` emits a deterministic plain-text list.

### Remaining Work

None.

## Doctrine Sections Cited

- [../HASKELL_CLI_TOOL.md → Toolchain pinning](../HASKELL_CLI_TOOL.md) (Sprint 1.1)
- [../HASKELL_CLI_TOOL.md → Project Structure](../HASKELL_CLI_TOOL.md) (Sprint 1.1)
- [../HASKELL_CLI_TOOL.md → Command Topology](../HASKELL_CLI_TOOL.md) (Sprint 1.2)
- [../HASKELL_CLI_TOOL.md → Automatically Generated Documentation](../HASKELL_CLI_TOOL.md) (Sprints 1.2, 1.3)
- [../HASKELL_CLI_TOOL.md → Progressive Introspection](../HASKELL_CLI_TOOL.md) (Sprint 1.2)
- [../HASKELL_CLI_TOOL.md → Generated Artifacts](../HASKELL_CLI_TOOL.md) (Sprint 1.3)
- [../HASKELL_CLI_TOOL.md → Lint, Format, and Code-Quality Stack](../HASKELL_CLI_TOOL.md) (Sprint 1.4)
- [../HASKELL_CLI_TOOL.md → Plan / Apply](../HASKELL_CLI_TOOL.md) (Sprint 1.5)
- [../HASKELL_CLI_TOOL.md → Architecture → Subprocesses as Typed Values](../HASKELL_CLI_TOOL.md) (Sprint 1.6)
- [../HASKELL_CLI_TOOL.md → Prerequisites as Typed Effects](../HASKELL_CLI_TOOL.md) (Sprint 1.7)
- [../HASKELL_CLI_TOOL.md → Application Environment](../HASKELL_CLI_TOOL.md) (Sprint 1.8)
- [../HASKELL_CLI_TOOL.md → Error Handling](../HASKELL_CLI_TOOL.md) (Sprint 1.9)
- [../HASKELL_CLI_TOOL.md → Output Rules](../HASKELL_CLI_TOOL.md) (Sprint 1.9)
- [../HASKELL_CLI_TOOL.md → Reconcilers: Idempotent Mutation as a Single Command](../HASKELL_CLI_TOOL.md) (Sprint 1.3, 1.9)

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/cli_command_surface.md` — populate the project-specific
  command matrix; link generated tables (key `cli-commands.help-blocks`) to the
  `GeneratedSectionRule` registry.
- `documents/engineering/code_quality.md` — name the twelve `fourmolu` settings,
  the project-specific hlint rules, the `forbiddenPathRegistry`, and the chart-
  shape lint.
- `documents/engineering/haskell_code_guide.md` — name the `Subprocess`,
  `Plan / apply`, prerequisite, `Env`, and `AppError` patterns with project-
  specific elaborations (the 17-variant `AppError` enumeration).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- `system-components.md → CLI Doctrine Components` rows for Sprint `1.1`–`1.9`
  move from `⏸️ Blocked` to `🔄 Active` then `✅ Done` as each sprint closes.
- `legacy-tracking-for-deletion.md` enqueues a row only if Sprint `0.2`'s audit
  surfaces a doctrine-adoption gap that this phase does not own.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [development_plan_standards.md](development_plan_standards.md)
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
