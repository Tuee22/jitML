# Phase 20: Typed Numeric CLI Parsing and Generated-Only Command Reference

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Typed Numeric CLI Parsing and Generated-Only Command Reference. Single-session phase migrated from legacy Sprint 1.17 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 20.1: Typed Numeric CLI Parsing and Generated-Only Command Reference [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/App.hs`, `src/JitML/CLI/Parser.hs`,
`src/JitML/AppError/AppError.hs`, `documents/engineering/cli_command_surface.md`
**Docs to update**: `README.md`, `documents/engineering/cli_command_surface.md`,
`documents/engineering/unit_testing_policy.md`,
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`, `system-components.md`

### Objective

Make every user-provided numeric CLI value parse through the typed error surface
and remove stale duplicate command syntax from manually maintained docs.

### Deliverables

- Replace residual `readInt` use on user-facing flags with a parser that returns
  `InvalidConfig` for malformed integers.
- Cover `jitml service --consume-once`, `jitml rl rollout --seed`, and
  `jitml rl alphazero self-play --games/--sims/--max-plies/--updates/--arena-games`.
- Keep generated `CommandSpec` artifacts as the only exact command-reference
  mirror; engineering prose may describe intent but does not duplicate flag
  lists beside generated help blocks.
- Move the CLI parsing / stale-manual-reference ledger row to `Completed` only
  after code and docs validation pass.

### Validation

- `docker compose run --rm jitml jitml test jitml-unit --linux-cpu`
- `docker compose run --rm jitml jitml docs check`
- `docker compose run --rm jitml jitml check-code`

### Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
