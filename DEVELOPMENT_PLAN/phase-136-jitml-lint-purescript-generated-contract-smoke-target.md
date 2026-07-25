# Phase 136: `jitml lint purescript` Generated-Contract Smoke Target

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: jitml lint purescript Generated-Contract Smoke Target. Single-session phase migrated from legacy Sprint 11.3 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 136.1: `jitml lint purescript` Generated-Contract Smoke Target [✅ Done]

**Status**: Done
**Implementation**: `web/test/Main.purs`, `web/spago.yaml`,
`src/JitML/Lint/Stack.hs`
**Docs to update**: `documents/engineering/purescript_frontend.md`,
`documents/engineering/unit_testing_policy.md`

### Objective

Keep `jitml lint purescript` as the generated-contract, whitespace,
panel-contract, `purs-tidy`-formatting, and `purescript-spec` smoke target.
The smoke suite runs under Node through `spec-node`.

### Deliverables

- `web/test/Main.purs` is present as a `purescript-spec` test entrypoint.
- `web/spago.yaml` declares both `spec` and `spec-node` for the test target.
- `web/test/Main.purs` uses
  `Test.Spec.Runner.Node.runSpecAndExitProcess`, not the deprecated generic
  `Test.Spec.Runner.runSpec` compatibility alias.
- `src/JitML/Lint/Stack.hs` verifies
  `web/src/Generated/Contracts.purs` exists and names the expected endpoint
  surface.
- The lint target also checks `renderPureScriptContracts` emits the PureScript
  module header.
- The lint target recursively checks every checked-in `web/src/**/*.purs` and
  `web/test/**/*.purs` source for tab-free, final-newline source shape and
  verifies each typed panel endpoint is covered by the generated contract
  endpoint list.
- It validates the explicit `spago test` and `purs-tidy check` typed
  `Subprocess` values without invoking them through process-environment gates.
- The default lint path now invokes `purs-tidy check 'src/**/*.purs'` against
  the container-installed `/usr/local/bin/purs-tidy` (added to the
  `npm install -g` line in `docker/Dockerfile`). When the binary is missing
  (host invocation or a partial image), `runPureScriptTidyCheck` reports a
  `purescript.tools.missing` finding instead of silently skipping.
- `web/.gitignore` excludes `.spec-results`, the persistent Node runner state
  emitted by `spec-node`.

### Validation

1. `docker compose run --rm jitml jitml lint purescript` exits `0` for the smoke body.
2. Missing generated-contract output fails the lint target.
3. PureScript whitespace and panel-contract validation run in the lint target.
4. The lint target validates `spago test` and `purs-tidy check` as explicit typed
   `Subprocess` values with no process-environment gate.
5. The default lint path invokes `/usr/local/bin/purs-tidy check 'src/**/*.purs'`
   in `web/` through the typed `Subprocess` and surfaces formatting drift as a
   `purescript.purs-tidy.drift` finding. 2026-05-23 validation in `jitml:local`
   confirms `purs-tidy check` reports no drift on the checked-in
   `web/src/**/*.purs` set, and a deliberately mis-formatted source produces
   the expected `Some files are not formatted` finding.
6. Target validation: the default style path adds a `purescript-spec` smoke
   suite that touches every typed panel contract through
   `/usr/local/bin/spago test` in `web/`.
7. 2026-06-04 validation:
   `docker compose run --rm jitml sh -lc 'cd web && spago test'` passes
   7 / 7 with zero PureScript warnings after the `spec-node` runner update.

### Remaining Work

None. The `purescript-spec` smoke suite closed on 2026-05-24 and was refreshed
on 2026-06-04 to use the current Node runner API: `spec` and `spec-node` are
`web/spago.yaml` test dependencies, `web/test/Main.purs` is a `describe`/`it`
block that touches every typed `Panels.*` payload-shape contract and the
generated `Generated.Contracts` endpoint catalog, and
`JitML.Lint.Stack.runPureScriptSpecSuite` invokes `/usr/local/bin/spago test`
through the typed `Subprocess` boundary on the default
`jitml lint purescript` path. The in-container
`docker compose run --rm jitml sh -lc 'cd web && spago test'` validation
passed 7 / 7 with no PureScript warnings on 2026-06-04.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
