# Phase 154: Substrate-partitioned test lanes; remove the cross-substrate parity test surface

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Substrate-partitioned test lanes; remove the cross-substrate parity test surface. Single-session phase migrated from legacy Sprint 12.10 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 154.1: Substrate-partitioned test lanes; remove the cross-substrate parity test surface [✅ Done]

**Status**: Done (closed 2026-06-09 on the NVIDIA GeForce RTX 5090 host after the live `linux-cuda` lane re-validation)
**Implementation**: `test/cross-backend/Main.hs`, `test/unit/Main.hs`,
`test/integration/Main.hs`, `src/JitML/Test/Report.hs`, `src/JitML/App.hs`,
`jitml.cabal` (the `jitml-cross-backend` / `jitml-unit` / `jitml-integration`
stanzas), `cabal.project` (report-card knob block)
**Docs to update**: `documents/engineering/unit_testing_policy.md`

### Objective

Realign the test surface to the clarified reproducibility contract —
within a substrate: bit-for-bit reproducible; across substrates: NO
guarantee. The cross-substrate numeric parity surface is therefore removed
in full, the cross-backend / canonicals / integration stanzas are
partitioned into per-substrate lanes selected with the
`--test-options='-p <substrate>'` switch (added by Phase 1 Sprint `1.13`),
and every selected case runs for real in its lane with NO skip sentinels — a
missing toolchain fails by design. Within-substrate bit-for-bit
reproducibility coverage stays, including ALL `linux-cuda` within-substrate
cases (CUDA is NOT being removed). This keeps each stanza inside its
doctrine [Test Organization](../README.md#test-suite-stanzas) shape
(`type: exitcode-stdio-1.0`, `tasty` per stanza, no spanning tree) and the
doctrine [Test Categories](../README.md#test-suite-stanzas) mapping while
dropping the cross-substrate parity category that the contract no longer
supports.

### Deliverables

- `jitml-cross-backend` (`test/cross-backend/Main.hs`) realigned to
  within-substrate cases only: the `CrossSubstrate weighted drift
  assertions` test group is deleted.
- The two substrate-agnostic cross-backend cases — "each substrate has
  deterministic engine flags" and "checkpoint inference is backend
  independent for manifest reads" — are relocated into `jitml-unit`
  (`test/unit/Main.hs`).
- The cross-substrate tolerance-band test group is deleted from
  `test/unit/Main.hs`.
- The report-card `cross_substrate_parity` field is removed:
  `ReportMeasurements` in `src/JitML/Test/Report.hs` loses the field, and
  `measureCrossSubstrateParity` plus its call site are removed from
  `src/JitML/App.hs`.
- Substrate-partitioned `jitml test` lanes are wired: each substrate's
  cases run for real in its own lane selected via
  `jitml test ... --test-options='-p <substrate>'` (the `-p` switch is
  added by Phase 1 Sprint `1.13`); the six pure-logic stanzas
  (`jitml-unit`, `jitml-sl-canonicals`, `jitml-rl-canonicals`,
  `jitml-hyperparameter`, `jitml-daemon-lifecycle`, `jitml-e2e`) run in
  every lane; NO tests are skipped — a missing toolchain fails by design.
- The skip-antipattern guards are removed from the cross-backend and
  integration test bodies: the `probeCudaRuntime` / `cudaRuntimeAvailable`,
  `appleLiveReady`, and `cublasBindingsCompiledIn` /
  `cudnnBindingsCompiledIn` skip branches, and the oneDNN-availability
  assertion in the integration probe test. Within-substrate bit-for-bit
  reproducibility tests STAY — including ALL `linux-cuda` within-substrate
  cases.

### Historical Validation

Each lane is green with every selected case actually executing (no
skip-sentinels):

1. Apple host (`apple-silicon` lane): `bootstrap/apple-silicon.sh test`.
2. linux-cpu lane:
   `docker compose run --rm jitml jitml test ... -p linux-cpu`.
3. linux-cuda lane:
   `docker compose run --rm jitml-cuda jitml test ... -p linux-cuda -fcuda`.
4. Container code-quality gate: `jitml check-code`.

### Remaining Work

- **The test/report code edits have landed** (2026-06-08): the `CrossSubstrate
  weighted drift assertions` group and every skip-guard branch
  (`probeCudaRuntime` / `cudaRuntimeAvailable`, `appleLiveReady`,
  `cublasBindingsCompiledIn` / `cudnnBindingsCompiledIn`) are removed from
  `test/cross-backend/Main.hs`; the two substrate-agnostic cases
  (`each substrate has deterministic engine flags`, `checkpoint inference is
  backend independent for manifest reads`) are relocated into
  `test/unit/Main.hs` and the cross-substrate tolerance-band group there is
  deleted; the `cross_substrate_parity` field is removed from
  `ReportMeasurements` (`src/JitML/Test/Report.hs`) and
  `measureCrossSubstrateParity` plus its call site are removed from
  `src/JitML/App.hs`; the oneDNN-availability assertion is removed from the
  integration probe test; and the per-substrate `--test-options='-p
  <substrate>'` lanes are wired (the passthrough landed in Sprint `1.13`). The
  cuBLAS / cuDNN cases are renamed with the `linux-cuda` prefix so
  `-p linux-cuda` selects them, and every remaining cross-backend case carries
  its substrate id so `-p <substrate>` partitions cleanly.
- **Validated lanes (2026-06-08):** the `apple-silicon` lane ran for real
  host-native — `jitml test jitml-cross-backend --test-options='-p
  apple-silicon'` selected exactly the four Metal cases and passed **4 / 4
  (88.90s, no skip-sentinels)**; `jitml-unit` passed **193 / 193** host-native
  (covering the relocated backend-agnostic group and the new
  `--test-options` parse case); the whole edited suite compiles + links clean
  host-native; `jitml docs check` is green. The `linux-cpu` lane and the
  container `jitml check-code` gate run in the `jitml` container.
- **linux-cuda lane re-validated (2026-06-09, RTX 5090):** on the NVIDIA
  GeForce RTX 5090 host (UUID `GPU-e764ef97-32d7-4981-c348-029983c64073`) the
  GPU-attached `jitml-cuda` compose service ran the lane for real —
  `docker compose run --rm jitml-cuda cabal test -fcuda jitml-cross-backend
  --test-options '-p linux-cuda'` passed **19 / 19 (12.26s, no skip-sentinels)**,
  selecting exactly the within-substrate CUDA cases (the `-fcuda` cabal build
  flag compiles the real cuBLAS / cuDNN bindings, and the GPU lane is driven
  through the GPU container's `cabal test -fcuda` form per the `jitml-cuda`
  compose-service contract and every historical CUDA evidence line; the
  flag-free `jitml test` orchestrator owns the apple-silicon / linux-cpu lanes).
  This closes the sprint's one remaining obligation — owned jointly with Sprint
  `15.16`, whose [GPU Re-validation Evidence](README.md#legacy-to-new-phase-map)
  records the full case list. Sprint `12.10` is `✅ Done`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
