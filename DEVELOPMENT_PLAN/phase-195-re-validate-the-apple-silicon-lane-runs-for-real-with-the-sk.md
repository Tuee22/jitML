# Phase 195: Re-validate the apple-silicon lane runs for real with the skip guards removed

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Re-validate the apple-silicon lane runs for real with the skip guards removed. Single-session phase migrated from legacy Sprint 16.6 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 195.1: Re-validate the apple-silicon lane runs for real with the skip guards removed [✅ Done]

**Status**: Done
**Implementation**: `test/cross-backend/Main.hs`
**Docs to update**: `documents/engineering/determinism_contract.md`,
`documents/engineering/jit_codegen_architecture.md`

### Objective

With the `appleLiveReady` skip guards removed, re-validate the apple-silicon
within-substrate cases run **for real** host-native: the Metal kernel
bit-equality case (Sprint `16.2`), the weighted Dense2D determinism case
(Sprint `16.5`), and the live Metal benchmark candidate runner (Sprint `16.3`).
A missing Metal device now **fails**, it does not skip. Within-substrate
bit-for-bit reproducibility is the retained contract (across substrates carries
**no** parity guarantee).

### Deliverables

- The apple-silicon lane (`-p apple-silicon`) of `jitml-cross-backend` runs
  every within-substrate Metal case as a real PASS with **no skip-sentinels** —
  the removed `appleLiveReady` guards mean an unusable / absent Metal device
  now produces a hard FAIL.
- The apple-silicon lane plus the pure-logic stanzas run host-native and invoke
  **no** oneDNN / nvcc compiles.

### Validation

1. `bootstrap/apple-silicon.sh test` runs the apple-silicon lane
   (`-p apple-silicon`) together with the pure-logic stanzas as real PASSes,
   invoking no oneDNN / nvcc compiles; absence of a usable Metal device fails
   the lane rather than skipping it.

**2026-06-09 (closed)** — the `appleLiveReady` skip guards are removed from
`test/cross-backend/Main.hs` and the apple-silicon lane was re-validated for
real, host-native, on an Apple Silicon machine through the new Sprint `1.13`
`--test-options` passthrough:
`cabal run jitml -- test jitml-cross-backend --test-options='-p apple-silicon'`
selected exactly the four within-substrate Metal cases and ran every one as a
real PASS — `apple-silicon kernel output is bit-equal across repeated runs`
(31.18s), `apple-silicon weighted Dense2D kernel runs bit-deterministically`
(30.41s), `apple-silicon live Metal benchmark candidate runner produces a
measurement` (27.31s), and the JITML_TUNING_LIVE-gated cache-miss round-trip —
**4 / 4 in 88.90s** with no skip-sentinels. Each Metal case drives the headless
host `swift build` + runtime `MTLDevice.makeLibrary(source:)` JIT path (the
~30s per case is the real compile/launch round-trip, not a skip). No oneDNN /
nvcc compile is invoked in the apple-silicon lane. The pure-logic
`jitml-unit` stanza passed host-native (193 / 193). The
`appleLiveReady` removal row is recorded in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
