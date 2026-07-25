# Phase 206: Remove the cross-substrate parity surface; reframe the determinism contract to within-substrate-only

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Remove the cross-substrate parity surface; reframe the determinism contract to within-substrate-only. Single-session phase migrated from legacy Sprint 17.4 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 206.1: Remove the cross-substrate parity surface; reframe the determinism contract to within-substrate-only [✅ Done]

**Status**: Done (closed 2026-06-09 on the NVIDIA GeForce RTX 5090 host after the live `linux-cuda` lane re-validation and the full legacy-ledger sweep)
**Implementation**: deletions in `src/JitML/Engines/Tolerance.hs`,
`src/JitML/CrossBackend/Parity.hs`,
`test/cross-backend/Main.hs` (the `CrossSubstrate` drift group),
`test/unit/Main.hs` (the tolerance-band group),
`src/JitML/Test/Report.hs` + `src/JitML/App.hs` (the report-card
`cross_substrate_parity` field + `measureCrossSubstrateParity` +
`verify cross-backend` handlers), and `src/JitML/CLI/Spec.hs` (the
`verify cross-backend` leaf)
**Docs to update**: `documents/engineering/determinism_contract.md`,
`../README.md`, `documents/engineering/unit_testing_policy.md`,
`system-components.md`

### Objective

Delete the cross-substrate numeric parity surface and reframe the
determinism contract + [Exit Definition](README.md#exit-definition) to
within-substrate-only. Cross-substrate equivalence is out of contract
(RNG draw order and float reduction order differ between substrates), so
the tolerance band, the weighted cohort, the drift tests, the
`verify cross-backend` command, and the report-card
`cross_substrate_parity` field all assert a guarantee the project does not
make and must be removed. The surviving contract is: **within a
substrate, bit-for-bit reproducible** (validated per substrate by Phases
`15`/`16`); **across substrates, no guarantee**.

### Deliverables

- The deletions listed under **Implementation** land: `Tolerance.hs` and
  `CrossBackend/Parity.hs` are removed; the `CrossSubstrate` drift group
  in `test/cross-backend/Main.hs` and the tolerance-band group in
  `test/unit/Main.hs` are removed; the `cross_substrate_parity` field,
  `measureCrossSubstrateParity`, and the `verify cross-backend` handlers
  are removed from `src/JitML/Test/Report.hs` and `src/JitML/App.hs`; and
  the `verify cross-backend` leaf is removed from `src/JitML/CLI/Spec.hs`.
- `documents/engineering/determinism_contract.md` has its "Cross-Substrate
  Tolerance Methodology" section **removed**, and the contract is reframed
  to within-substrate bit-for-bit reproducibility with an explicit
  no-cross-substrate-guarantee statement.
- The [Exit Definition](README.md#exit-definition) items are reworded:
  within-substrate bit-for-bit reproducibility is the determinism claim;
  no cross-substrate numeric-parity claim remains.

### Validation

1. `jitml docs check` is clean after the doc cascade.
2. `jitml test all` passes on the per-substrate lanes (the cross-substrate
   drift/tolerance groups no longer exist).
3. Container `jitml check-code` passes after the source deletions.

### Closure Evidence

- **The code deletions have landed** (2026-06-08): `src/JitML/Engines/Tolerance.hs`
  and `src/JitML/CrossBackend/Parity.hs` are deleted (and removed from
  `jitml.cabal`); the `CrossSubstrate` drift group
  (`test/cross-backend/Main.hs`) and the tolerance-band group
  (`test/unit/Main.hs`) are removed; the `cross_substrate_parity` field,
  `measureCrossSubstrateParity`, and the `verify cross-backend` handlers are
  removed from `src/JitML/Test/Report.hs` and `src/JitML/App.hs`; and the
  `verify cross-backend` leaf is removed from `src/JitML/CLI/Spec.hs`.
- **The doc cascade has landed**: `determinism_contract.md`,
  `unit_testing_policy.md`, `training_workloads.md`, the generated
  `cli_command_surface.md` / `documents/cli/commands.md`, the project
  `../README.md` determinism doctrine, the Exit Definition wording, and
  `system-components.md` all describe within-substrate bit-for-bit
  reproducibility with an explicit no-cross-substrate-guarantee statement and
  carry no cross-substrate numeric-parity surface. `jitml docs check` is green
  host-native; the whole project compiles + links clean.
- **Closed (2026-06-09, RTX 5090):** Validation `2` (`jitml test all` on the
  per-substrate lanes — the cross-substrate drift/tolerance groups no longer
  exist) is complete for all three lanes: the `apple-silicon` lane (4 / 4
  host-native), the `linux-cpu` lane (10 / 10 through the canonical `jitml test`
  surface) + container `jitml check-code`, and now the `linux-cuda` lane,
  re-validated for real on the NVIDIA GeForce RTX 5090 host (UUID
  `GPU-e764ef97-32d7-4981-c348-029983c64073`) via the GPU-attached `jitml-cuda`
  compose service — `docker compose run --rm jitml-cuda cabal test -fcuda
  jitml-cross-backend --test-options '-p linux-cuda'` → 19 / 19 (12.26s, no
  skip-sentinels). Exit Definition item 18 (empty legacy ledger) is now fully
  met: this sprint's own rows (`Tolerance.hs`, `CrossBackend.Parity`) were
  already `Completed`, and the last open row — the `linux-cuda` half of the
  skip-guard removal owned jointly with Sprints `12.10` / `15.16` — moved to
  `Completed` when the GPU lane landed. The ledger is fully swept and the sprint
  is `✅ Done`.

### Remaining Work

- None. The cross-substrate parity surface is removed, the determinism contract
  is reframed to within-substrate-only, all three per-substrate lanes pass for
  real, and the legacy ledger is empty (Exit Definition item 18 met).

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
