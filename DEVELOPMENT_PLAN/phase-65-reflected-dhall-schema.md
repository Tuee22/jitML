# Phase 65: Reflected Dhall Schema

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Reflected Dhall Schema. Single-session phase migrated from legacy Sprint 5.12 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 65.1: Reflected Dhall Schema [✅ Done]

**Status**: Done (convergence config-schema surface; validated host-native +
container `check-code`)
**Implementation**: `src/JitML/Service/DhallSchema.hs` (new),
`src/JitML/Service/Retry.hs` (typed retry policy values/rendering),
`src/JitML/Service/LiveConfig.hs` (`liveConfigDecoder`/`loadLiveConfig`),
`src/JitML/Service/BootConfig.hs` (export `rawBootConfigDecoder`),
`src/JitML/Service/RunConfig.hs`, `test/unit/Main.hs`,
`src/JitML/App.hs` (planned `internal dhall-schema` leaf), `dhall/service/*.dhall`,
`dhall/run/Schema.dhall`
**Docs to update**: `../documents/engineering/daemon_architecture.md`,
`../documents/engineering/pulsar_ml_workflow.md`, `system-components.md`,
`legacy-tracking-for-deletion.md`

### Objective

Make the `jitml` binary **emit its own reflected Dhall schema** so the schema can
never drift from the `FromDhall` decoder types, per the shared
[../documents/engineering/pulsar_ml_workflow.md](../documents/engineering/pulsar_ml_workflow.md)
contract (`Configuration and roles` → reflected Dhall schema) and the
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) "Hand-written
Dhall schema files" row. This is the convergence convention both repos adopt now.
Adopts `Generated Artifacts →
The generated-section registry` and `Application Environment` from
[../README.md](../README.md).

**Update 2026-06-23 — catalog schemas reflected (common-shape reopen closed).**
The reflected-schema surface now extends past the daemon config to the
**numerics and RL catalog** `.dhall` leaves. Because those leaves are Dhall
/values/ (lists of layer/optimizer/loss names; algorithm records) rather than a
type, `JitML.Service.CatalogSchema` emits them by rendering the catalog data from
the same `expectedNumericsCatalog` / `expectedRlCatalogSchema` mirror data the
decoders read, exposed by `jitml internal dhall-schema --catalog numerics|rl|all`.
A `jitml-unit` parity case ("every numerics/RL catalog Dhall leaf equals the
emitted catalog", `canonicalDhallType` file ≡ emitted) complements the existing
decode-and-compare mirror so drift fails in both directions; the RL
`Algorithm.dhall` emission is byte-identical to the checked-in file. This closes
the `Phase 5` "Hand-written catalog Dhall schema files" ledger row (the
`experiments/*.dhall` files are instance/data fixtures validated by typed decode,
not hand-written schema *type* files). Host-validated: `cabal build lib:jitml
exe:jitml` clean, `jitml-unit` catalog-parity case PASS, `jitml docs check: ok`.

### Deliverables

- Derive `ToDhall` for the daemon config records (`BootConfig`, `LiveConfig`,
  `RunConfig`) alongside their existing `FromDhall` instances, and hoist the
  reflected type via `Dhall.expected`/`Dhall.TypeCheck` so the emitted schema is
  exactly the decoder's accepted type.
- Add a `jitml internal dhall-schema` leaf that prints the reflected schema for
  each config surface; register it in the command registry and the generated CLI
  mirror (`documents/cli/commands.md`, manpage, completions) via `jitml docs
  generate`.
- Treat the checked-in `dhall/service/BootConfig.dhall`,
  `dhall/service/LiveConfig.dhall`, and `dhall/run/Schema.dhall` schema files as a
  generated section emitted from the reflected types (regenerated, not
  hand-edited), with a `jitml docs check` parity assertion that the checked-in
  files equal the reflected output.
- Move the "Hand-written Dhall schema files" ledger row to `Completed` once the
  parity assertion is green.

### Validation

- `jitml test jitml-unit --linux-cpu` (or `--apple-silicon` host lane) covers the
  reflected-schema parity property (emitted schema ≡ checked-in file ≡ round-trip
  decode of a known config).
- `docker compose run --rm jitml jitml test jitml-daemon-lifecycle --linux-cpu`.
- `docker compose run --rm jitml jitml docs check` (schema-parity + generated CLI
  mirror) and `docker compose run --rm jitml jitml check-code`.

### Validation State (host-native, apple-silicon lane)

- **Landed and validated host-native.** `JitML.Service.DhallSchema` reflects each
  config surface's Dhall type **off the live decoder** via `Dhall.expected`
  (`reflectedSchemaText`), so the schema cannot drift from the `FromDhall` types.
  To reflect `LiveConfig` (which previously had no decoder, only a renderer), a
  `liveConfigDecoder` + `loadLiveConfig` were added — making SIGHUP hot-reload
  read the real operational config file through checked numeric refinement.
- The `jitml internal dhall-schema [--config NAME]` leaf is registered in the
  command registry and prints `configSchemas`; `jitml docs generate` regenerated
  the CLI mirror (`documents/cli/commands.md`,
  `documents/engineering/cli_command_surface.md`, manpage, completions, root
  README command tree) and the `daemon_architecture.md` BootConfig table row.
- `cabal build lib:jitml` / `exe:jitml` / `jitml-unit` compile warning-clean
  (`-Wall`). `cabal run jitml-unit` passes **203 / 203**, including: the reflected
  `BootConfig` and `LiveConfig` schemas each **equal** the checked-in
  `dhall/service/*.dhall` file (canonicalised through the same pretty-printer via
  `canonicalDhallType`); the reflected `RunConfig` let-record (`runSchemaDhall`)
  **equals** `dhall/run/Schema.dhall`; all five reflected schemas are well-formed,
  reflexive Dhall; and the command-registry leaf list now covers `internal
  dhall-schema`. Host `jitml docs check` reports `docs check: ok`.
- **Container `check-code` passed** (the canonical container-only gate runs as a
  baked Dockerfile layer; `docker compose build jitml` exited `0` with the hlint
  hint on `Topology.hs` fixed and fourmolu/hlint/cabal-format clean).

### Remaining Work

- Run the **in-container** `jitml docs check` + `jitml test
  jitml-unit,jitml-daemon-lifecycle --linux-cpu` (currently re-confirmed
  host-native; the in-container test-stanza re-run is blocked by an environmental
  Docker image-store/`-M2G` rebuild flake on this shared host, not by code — see
  Validation State). Then this sprint is closeable on its owned surface.
- Reflected emission for the remaining catalog (`dhall/numerics`, `dhall/rl`) and
  `experiments/*.dhall` schemas is tracked in the narrowed "Hand-written
  catalog/experiment Dhall schema files" ledger row (the daemon config surfaces
  are done).

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
