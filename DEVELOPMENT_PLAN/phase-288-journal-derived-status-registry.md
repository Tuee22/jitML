# Phase 288: Journal-Derived Status Registry

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Journal-Derived Status Registry. Single-session phase migrated from legacy Sprint 34.3 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

⏸️ **Blocked**. Blocked by Phase 285 (Sprint 285.1).

The journal-derived registry is implemented and `jitml docs status` derives the
counts, open chain, and unmet obligations from committed evidence; closure waits on
Sprint `285.1`.

## Sprint 288.1: Journal-Derived Status Registry [⏸️ Blocked]

**Status**: Blocked
**Implementation**: `src/JitML/Product/PhaseStatus.hs`,
`src/JitML/Product/StatusEvidence.hs`, `src/JitML/Product/StatusLoader.hs`,
`src/JitML/Product/PlanDoc.hs`, `src/JitML/Product/SourceDigest.hs`,
`src/JitML/Product/ValidationRecord.hs`, `src/JitML/Test/ValidationEvidence.hs`,
`src/JitML/Test/Command.hs`, `src/JitML/Test/ProductLaneJournal.hs`,
`src/JitML/Docs/Check.hs`, `src/JitML/Lint/Docs.hs`, `src/JitML/App.hs`,
`src/JitML/CLI/Spec.hs`, `test/unit/JournalDerivedStatus.hs`,
`test/unit/Main.hs`
**Blocked by**: Sprint `285.1`
**Docs to update**: `../README.md`, `README.md`, `00-overview.md`,
`development_plan_standards.md`, `../documents/documentation_standards.md`,
`system-components.md`, `legacy-tracking-for-deletion.md`

### Objective

Derive phase, sprint, and product status from the structured process and
scenario journals that produced the evidence, replacing the hand-maintained
registry. This sprint owns the [Exit Definition](README.md#exit-definition)
item `34` (journal-derived cross-lane handoff and plan status). The binding
design is [README.md → Typed run contracts](../README.md#typed-run-contracts).

### Deliverables

- Replace the hand-maintained provisional phase/sprint registry
  (`PhaseStatus.hs`) with a projection over versioned validation evidence and
  explicit unmet/blocked obligations.
- Make closure claims fail whenever required journals are missing, stale,
  mismatched, failed, or incomplete, even if prose/status literals say Done.
- Keep the live `Closure Status` narrative thin and point it to the derived
  evidence and outstanding sprint chain.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml test jitml-negative-controls --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Current Partial Validation

- 2026-09-30: `PhaseStatus.hs` is a catalogue, not a status literal. Each sprint
  carries either a frozen legacy attestation (**63** sprints, shrink-only, never
  able to mint a Done) or the obligations that must be proven (lane journals, the
  aggregate, gate transcripts, pending-control emptiness, the deletion ledger,
  upstream sprints, external context). `StatusLoader` reads only committed
  evidence, `StatusEvidence` projects `Proven | Unproven` per obligation and a
  `ClosureVerdict` that refuses on any missing, stale, mismatched, failed, or
  incomplete evidence, and `jitml docs check` now enforces the registry against the
  phase-document headers, Blocked-by edges, Remaining Work, and a **60**-line cap on
  the README's Closure Status section (`closureStatusLineCap`; the narrative moved
  to the historical diary). `jitml test` writes a versioned `jitml-validation-record` per
  invocation to `.build/runtime/validation/`; the human copies it under
  `DEVELOPMENT_PLAN/attestations/validation/`. The derived registry reproduces
  **63 Done / 1 Active / 0 Planned / 6 Blocked** and the open chain
  `278 → 280 → 281 → 282 → 285 → 288 → 289`. A gate transcript proves its
  obligation only for the gate's standing invocation; the `jitml-e2e` gate also
  requires that invocation to have been the `--live` run (recorded by its `nice`
  wrapper), so the non-live suite cannot stand for the live measurement glue. No record
  is written when the environment sets a run-altering `TASTY_*` variable
  (`TASTY_PATTERN`, `TASTY_TIMEOUT`, `TASTY_QUICKCHECK_*`, …): the recorded command
  cannot show it, and a diagnostic live run on 2026-10-05 excluded one test through
  `TASTY_PATTERN` and still produced a passing record with the standing command. Four
  unit cases cover the guard, and disabling it turns two of them red.
### Remaining Work

- Blocked until Sprint `285.1` closes, which waits on Sprint `278.1`.
- Run the Validation commands in the `linux-cpu` container lane on the final tree
  and commit the `jitml-unit` and `jitml-negative-controls` validation records; a
  missing transcript is `Unproven`, never Done.
- Reopening a legacy-attested sprint after an audit finding converts its catalogue
  entry to an evidenced one and shrinks the frozen set.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
