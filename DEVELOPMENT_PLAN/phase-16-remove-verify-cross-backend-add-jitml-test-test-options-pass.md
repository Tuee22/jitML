# Phase 16: Remove `verify cross-backend`, add `jitml test --test-options` passthrough

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Remove verify cross-backend, add jitml test --test-options passthrough. Single-session phase migrated from legacy Sprint 1.13 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 16.1: Remove `verify cross-backend`, add `jitml test --test-options` passthrough [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/CLI/Spec.hs`, `src/JitML/App.hs`
**Docs to update**: `documents/engineering/cli_command_surface.md` (regenerated
help-blocks, key `cli-commands.help-blocks`), `documents/cli/commands.md`
(regenerated tracked path)

### Objective

The reproducibility contract is clarified to *within a substrate: bit-for-bit
reproducible; across substrates: no guarantee*. Cross-substrate numeric parity
has left the contract, so the `jitml verify cross-backend` parity command no
longer has a doctrine to back it and is removed from the `CommandSpec` registry
(doctrine `CommandSpec`). The surviving contract is enforced per substrate, so
each substrate's bootstrap selects its own test lane: add a `--test-options`
passthrough to the `jitml test` leaves that forwards arbitrary arguments to
`cabal test` so a bootstrap can target a tasty lane via `-p`
(e.g. `jitml test jitml-cross-backend --test-options='-p linux-cuda'`).

### Deliverables

- Delete the `verify` → `cross-backend` leaf from the `CommandSpec` registry in
  `src/JitML/CLI/Spec.hs`, keeping the then-current `verify same-run` and
  `verify replay` leaves intact. Sprint `1.16` later removes the remaining
  placeholder `verify` group.
- Add an optional `--test-options <text>` option to the `test` and `test all`
  leaves in `src/JitML/CLI/Spec.hs`.
- Forward the value from `runCabalTest` in `src/JitML/App.hs` as
  `cabal test <stanzas> --test-options <value>`; the option is a passthrough,
  the value is opaque to jitML.
- Regenerate every CLI artifact via `jitml docs generate` (doctrine
  `Generated Artifacts`): the README `command-tree` / `command-registry` blocks,
  the `documents/engineering/cli_command_surface.md` `cli-commands.help-blocks`
  region, the `documents/cli/commands.md` tracked path, the main manpage
  `share/man/man1/jitml.1`, and the bash / zsh / fish completion files. These
  generated regions are produced by `jitml docs generate`, never hand-edited.

### Validation

1. `docker compose run --rm jitml jitml docs check` exits `0` — the regenerated
   mirror (README registry/tree, `documents/cli/commands.md`,
   `documents/engineering/cli_command_surface.md`, manpage, completions) is
   aligned and carries no `verify cross-backend` leaf.
2. `docker compose run --rm jitml cabal test jitml-unit --jobs=2` passes — the
   CLI parser/spec tests reflect the removed leaf and the new `--test-options`
   option.
3. `docker compose run --rm jitml jitml check-code` exits `0` — the
   container-only Haskell lint + warning-clean build gate is clean.

**2026-06-09 (closed)** — all three edits landed and validated:

- `src/JitML/CLI/Spec.hs` no longer carries the `verify` → `cross-backend`
  leaf; at the time `verify same-run` / `verify replay` stayed, and Sprint
  `1.16` later removed them with the rest of the placeholder group. The new
  `testOptionsOption` (`--test-options <text>`) is attached to both the
  `test all` and the per-stanza `test <stanza>` leaves.
- `src/JitML/App.hs` removes `runVerifyCrossBackend` and all its helpers
  (`selectedCrossBackendSubstrates`, `readCrossBackendBundle`,
  `writeCrossBackendExport`, `assertCrossBackendBundle`, `crossBackendResult`,
  `commaSeparatedValues`), and `runCabalTest` forwards the opaque
  `--test-options` value verbatim as `cabal test <stanzas> --test-options
  <value>`.
- `jitml docs generate` regenerated the README `command-tree` /
  `command-registry` blocks, `documents/cli/commands.md`,
  `documents/engineering/cli_command_surface.md` (`cli-commands.help-blocks`),
  `share/man/man1/jitml.1`, and the bash / zsh / fish completions.

Validation: `jitml docs check` exits `0` (host **and** container) — the
regenerated mirror carries no `verify cross-backend` leaf; `jitml-unit`
passes **193 / 193** (the parser/spec leaf-path enumeration drops the leaf and
a new case covers `test jitml-cross-backend --test-options='-p linux-cuda'`);
the container `jitml check-code` exits `0`; and the passthrough was exercised
end-to-end through the built binary —
`jitml test jitml-cross-backend --test-options='-p apple-silicon'` selected the
apple-silicon lane and `--test-options='-p linux-cpu'` selected the linux-cpu
lane. The `jitml verify cross-backend` row in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) moves to
`Completed`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
