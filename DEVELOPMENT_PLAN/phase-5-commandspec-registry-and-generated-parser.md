# Phase 5: `CommandSpec` Registry and Generated Parser

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: CommandSpec Registry and Generated Parser. Single-session phase migrated from legacy Sprint 1.2 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 5.1: `CommandSpec` Registry and Generated Parser [✅ Done]

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
- The `CommandSpec` registry covers every current command surface from
  [system-components.md → Haskell CLI
  Surface](system-components.md#haskell-cli-surface): `cluster up`, `cluster down`,
  `cluster status`, `cluster reset`, `service`, `train`, `eval`, `tune`,
  `rl train`, `rl eval`, `rl rollout`, `inference run`, `test all`, every
  per-stanza `test` leaf, `lint files|docs|proto|chart|haskell|purescript|all`,
  `docs check`, `docs generate`, `check-code`, `build`,
  `internal materialize-substrate`, `internal list-prereqs`, `internal gc`,
  `internal upload-dataset`, `internal cache stat|list|evict`,
  `commands`, and `help`. Each leaf carries at least one `Example`. Earlier
  placeholder `verify`, `inspect`, `bench`, and user-facing `kubectl` leaves are
  removed by Sprint `1.16`.
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

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
