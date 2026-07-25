# Phase 6: Generated Sections and Tracking-Generated Paths

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Generated Sections and Tracking-Generated Paths. Single-session phase migrated from legacy Sprint 1.3 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 6.1: Generated Sections and Tracking-Generated Paths [✅ Done]

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

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
