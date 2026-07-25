# Phase 15: CLI Dhall Overrides

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: CLI Dhall Overrides. Single-session phase migrated from legacy Sprint 1.12 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 15.1: CLI Dhall Overrides [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/CLI/Spec.hs`, `src/JitML/Experiment/Overrides.hs` (new),
`src/JitML/Commands/Train.hs`, `src/JitML/Commands/Tune.hs`, `src/JitML/Commands/Rl.hs`
**Docs to update**: `../README.md`,
`../documents/engineering/cli_command_surface.md`,
`../documents/engineering/training_workloads.md`, `system-components.md`,
`legacy-tracking-for-deletion.md`

### Objective

Honor the doctrine prescription at
[../README.md → Hyperparameter tuning, first-class](../README.md#hyperparameter-tuning-first-class)
(line 1050): *"CLI flags (`--sampler …`, `--scheduler …`, `--pruner …`)
override the Dhall on each axis, never replace it."* Extend the override
pattern to substrate and seed on `train` and `rl train`, matching the worked
Dhall example at
[../README.md → Concrete Dhall worked example](../README.md#concrete-dhall-worked-example)
where `substrate` and `seed` are first-class Dhall fields and pillar 2 at
[../README.md → Why this exists](../README.md#why-this-exists) (*"CLI flags
layered on top override the Dhall; they never replace it"*) applies to every
Dhall field.

Close the documentation-versus-implementation contradictions surfaced on
2026-06-04: five README example fences (the `train` / `rl train` / `tune`
quickstart commands) currently violate
[../documents/documentation_standards.md → §6 Current-Surface Examples Only](../documents/documentation_standards.md#6-code-examples-markdown)
because the example flags do not parse against `CommandSpec`. Two additional
README example forms (`inspect frontier --tuning-run/--pareto` and
`--backends cpu,cuda`) are stale typos not backed by any doctrine and are
repaired in the same change.

### Deliverables

- `tuneCommand` (`src/JitML/CLI/Spec.hs:230`) accepts optional
  `--sampler <text>`, `--scheduler <text>`, `--pruner <text>`,
  `--trials <natural>`, `--parallelism <natural>` override flags. Values
  decode via the existing `JitML.Tune.Catalog.samplerFromText`,
  `schedulerFromText`, and `prunerFromText` helpers.
- `trainCommand` (`src/JitML/CLI/Spec.hs:206`) and the `rl train` subcommand
  (`src/JitML/CLI/Spec.hs:249`) accept optional `--substrate <substrate>`
  and `--seed <word64>` override flags.
- New module `src/JitML/Experiment/Overrides.hs` exports a pure
  `applyOverrides :: ExperimentOverrides -> ExperimentValue -> Either OverrideError ExperimentValue`
  resolver that substitutes CLI values into the parsed experiment Dhall
  before validation. Overrides act on the named axis only and never replace
  the surrounding record.
- Substrate-name parsing rejects bare `cpu` / `cuda` aliases at the CLI
  boundary (canonical identifiers `apple-silicon` / `linux-cpu` /
  `linux-cuda` only, per Plan Standards rule B).
- README example repairs:
  - `../README.md:880` — `--backends cpu,cuda` → `--backends linux-cpu,linux-cuda`.
  - `../README.md:881` — `jitml inspect frontier --tuning-run <ref> --pareto valLoss params`
    → `jitml inspect frontier <sweep-id>`.
- Generated mirror regeneration via `jitml docs generate`: rewrites the
  README registry and command tree blocks, `documents/cli/commands.md`,
  `documents/engineering/cli_command_surface.md` machine-rendered sections,
  the main manpage `share/man/man1/jitml.1`, and the bash / zsh / fish
  completion files.
- Hand-edited engineering doc updates:
  - `documents/engineering/cli_command_surface.md` — add the override-flag
    family to the "Standard flag families" section, citing the README
    anchors it defers to per Doc Standards §1.
  - `documents/engineering/training_workloads.md` — add a single reference
    sentence to the override surface (do not duplicate per Doc Standards
    §1).
- Test additions (test-suite refactor mapped in the planning document):
  - `test/unit/Main.hs` — new rows in the `(argv, ParsedCommand)` table,
    new `buildCommandPlan` cases, new help-snapshot files under
    `test/snapshots/cli/{help-train,help-rl-train,help-tune,help-inspect-frontier}.txt`,
    and negative substrate-name parser cases.
  - `test/hyperparameter/Main.hs` — round-trip tests for sampler / scheduler /
    pruner CLI decode plus an "override substitutes on the named axis only"
    test that exercises `JitML.Experiment.Overrides.applyOverrides`.
  - `test/integration/Main.hs` — `runJitml ["train", "--dry-run", path, "--substrate", "linux-cpu", "--seed", "42"]`
    and matching `rl train` / `tune` rows that assert the rendered plan
    reflects the substituted values.

### Validation

1. `docker compose run --rm jitml jitml docs check` exits `0` — the
   generated mirror (README registry/tree, `documents/cli/commands.md`,
   `documents/engineering/cli_command_surface.md`, manpage, completions) is
   aligned.
2. `docker compose run --rm jitml cabal test jitml-unit jitml-hyperparameter jitml-integration --jobs=2`
   passes — every new override test row is green.
3. `docker compose run --rm jitml jitml check-code` exits `0` — the
   container-only Haskell lint + warning-clean build gate is clean.
4. Spot-grep `grep -nE "jitml (train|rl train|tune|inspect frontier|verify cross-backend) " ../README.md`
   — every example parses against the regenerated registry table at
   `../README.md:751–806`. Doc Standards §6 violation count reaches zero.

### Remaining Work

None. All deliverables landed and validated 2026-06-04: `jitml docs check`
exits 0; 195/195 `jitml-unit` (including 11 new Sprint 1.12 cases); 14/14
`jitml-hyperparameter` (including 2 new cases); the
`jitml-integration` spawned-binary matrix exercises `train`/`tune` override
substitution and the negative `--substrate cpu` path; the container
`jitml check-code` gate passes. Five previously-broken README example fences
now parse against the regenerated registry table.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
