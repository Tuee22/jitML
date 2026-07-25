# Phase 153: `jitml test all` Orchestrator and Report Card

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: jitml test all Orchestrator and Report Card. Single-session phase migrated from legacy Sprint 12.9 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 153.1: `jitml test all` Orchestrator and Report Card [✅ Done]

**Status**: Done
**Owned obligations after refactor**: code-surface only. Live `jitml
test all` mode threading live measurements into the report card and the
live integration test that surfaces real metrics migrated to Phase `17`
Sprint `17.2`.
**Implementation**: `src/JitML/App.hs`,
`src/JitML/Test/Report.hs`,
`cabal.project` (report-card knob block)
**Docs to update**: `documents/engineering/unit_testing_policy.md`

### Objective

Land `jitml test all` (Plan/Apply with `--dry-run` and `--plan-file`) as the
current operator-facing report-card surface, plus the report-card emitter that
prints the tidy summary block answering the canonical questions (SL
convergence, RL reward, AlphaZero arena win rate, JIT cache hit rate, daemon
health, and the then-planned cross-substrate comparison summary).

### Deliverables

- Target `jitml test all` plan steps:
  1. Resolve prerequisites.
  2. Schedule each stanza (`jitml-unit`, `jitml-integration`,
     `jitml-sl-canonicals`, `jitml-rl-canonicals`, `jitml-hyperparameter`,
     `jitml-cross-backend`, `jitml-daemon-lifecycle`, `jitml-e2e`) under `cabal test`
     through the typed `Subprocess` boundary.
  3. Aggregate results into the report card.
- Current `jitml test all --dry-run` renders the aggregate plan from
  `src/JitML/Plan/Plan.hs`; current non-dry-run `jitml test all` invokes
  Cabal through `JitML.Sub.Stream.runStreaming` and then renders a typed
  `ReportCard` with `ReportCardKnobs` and the actual target stanza list after
  Cabal succeeds. Without a substrate selector it keeps the legacy single
  `cabal test` invocation over the explicit test-only stanza names; with a
  substrate selector it serializes stanzas as separate Cabal subprocesses so
  live tests do not contend over one cluster/device.
- The report-card knob block in `cabal.project` carries `sl_epochs`,
  `sl_batch`, `rl_steps`, `rl_eval_episodes`, `az_games`, `az_sims`,
  `tune_trials`, `tune_budget_per_trial`, `xcluster_kind_nodes` (see
  [system-components.md → POC Report-Card
  Knobs](system-components.md#poc-report-card-knobs)).
- `src/JitML/Test/Report.hs` renders the tidy summary block on stdout, exposes
  `parseReportCardKnobs`, and `jitml test all` now reads the `cabal.project`
  knob block before rendering the report card instead of relying only on the
  in-code defaults. `renderReportCardForTargets` renders the expanded
  eight-stanza list for `jitml test all` and the selected stanza for
  `jitml test <stanza>`.
- `jitml test <stanza>` invokes that single Cabal stanza through the same typed
  `Subprocess` boundary.
- 2026-05-19 container validation ran `jitml test all --dry-run` and
  non-dry-run `jitml test all` inside `jitml:local`; the non-dry-run path
  passed all eight test stanzas and printed the report card with the
  `cabal.project` knob values.
- 2026-05-21 local validation re-ran `jitml test all --dry-run` and
  non-dry-run `jitml test all`; all eight test stanzas passed and the
  report-card summary printed the current knob block plus target stanza list.

### Validation

1. `jitml test all --dry-run` emits the typed plan enumerating all eight
   test stanzas.
2. `jitml test all` invokes Cabal over the explicit eight test-only stanza
   names (serializing by stanza under a substrate selector), exits `0` on the
   current tree, parses the `cabal.project` report-card knob block, and prints
   the target-stanza report card.
3. `cabal test jitml-e2e` verifies report-card default rendering and that the
   `cabal.project` knob block matches the typed defaults.
4. Transferred live validation: the explicit live `jitml test all` path schedules
   the live `jitml-e2e` body too; the rendered report card adds live
   measurements (SL convergence, RL reward, AlphaZero arena win rate,
   JIT cache hit rate, daemon health, and final handoff fields)
   on top of the target-stanza summary.

### Remaining Work

- No sprint-owned code-surface Remaining Work remains. The live `jitml
  test all` mode threading live measurements into the report card, the
  population of canonical report-card metrics with real data, and the
  live integration test that confirms the populated report card are
  owned by
  [phase-17-cross-substrate-and-handoff.md](README.md#legacy-to-new-phase-map)
  Sprint `17.2`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
