# Phase 288: Journal-Derived Status Registry

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Journal-Derived Status Registry. Originally migrated from legacy Sprint 34.3 in the 2026-07-24 phase renumber; see the old→new map in [README.md](README.md).

## Phase State

⏸️ **Blocked** on the expanded campaign obligations below. Historical closure
remains scoped to the execution and implementation it actually proved.

The [validation foundation refactor](README.md#validation-foundation-refactor)
owns the current execution order. Sprint `221.2` first updates the source
catalogue/checkers for the reopened sprint graph; those source changes are not
part of this documentation-only revision. Current machine projection still
reflects the old catalogue and must not be reported as validating these targets.

The [execution contract](../documents/engineering/validation_execution.md) and
[resource contract](../documents/engineering/execution_resources.md) state the
new targets. Atomic row recovery is not implemented or authorized by prose: until
`261.2` passes, existing qualification remains non-resumable. No historical partial
attempt, diagnostic review copy or readiness ledger is adopted as qualification.

## Sprint 288.1: Journal-Derived Status Registry [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Sprint `288.2`
**Docs to update**: `../documents/engineering/validation_execution.md`, `../documents/engineering/execution_resources.md`, `../documents/engineering/run_contract.md`, `../documents/engineering/unit_testing_policy.md`, `README.md`, `system-components.md`

### Objective

Retain the original unmet obligation and historical failures while completing
its explicitly reassigned or expanded proof below. The prior numerical chain
and old command sequence in the historical section are not current launch
authority. No previous failure or missing closing proof is erased.

### Deliverables

- Preserve the original contract and evidence obligations through the named
  current owners; qualify no obligation from diagnostic or historical data.
- Reconcile the typed catalogue and replacement acceptance in 221.2, then admit
  the complete current evidence without duplicate training at consumer phases.

### Validation

Run the applicable complete CPU unit and negative-control stanzas only after
their real data/live prerequisites exist; the expanded sprint below specifies
its live or production-reader acceptance.

```bash
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml test jitml-unit --linux-cpu
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml test jitml-negative-controls --linux-cpu
```

### Remaining Work

- Complete the named prerequisites and expanded acceptance below.
- Reconcile all original owned obligations and obtain evidence-derived status;
  the historical text supplies no current closure claim.

## Sprint 288.2: Evidence projection for reopened campaigns [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Sprint `221.2`, Sprint `285.2`, Sprint `286.2`
**Docs to update**: `../documents/engineering/validation_execution.md`, `../documents/engineering/execution_resources.md`, `../documents/engineering/run_contract.md`, `../documents/engineering/unit_testing_policy.md`, `README.md`, `system-components.md`

### Objective

Project the final current state over the explicit foundation/product sprint catalogue and campaign evidence.221.2 owns enabling early status/graph support; this sprint owns final evidence integration.

### Deliverables

- Represent reopened foundational sprints and all new campaign obligations explicitly; preserve complete product coverage and the shrink-only legacy-attested class.
- Accept no Done header without matching fulfilled obligations and no Blocked header with missing actual prerequisites.
- Derive status without requiring an agent to hand-edit counters or re-pin an old transcript.

### Validation

These are acceptance requirements for the target implementation. They are not
passes from this documentation change. Targeted failing controls run first; the
complete applicable stanzas run only after their actual evidence prerequisites
exist. Commands use the explicit named context and task-specific approved bounds;
cluster-running work uses the separately admitted cluster/lifecycle profile.

1. Verify empty, incomplete, mixed-source, failed and fully proven evidence indexes against expected sprint/phase/closure projections.
2. Pass full unit/negative and documentation checks after actual final campaign evidence exists.

```bash
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml test jitml-unit --linux-cpu
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml test jitml-negative-controls --linux-cpu
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml docs check
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml check-code
```

### Remaining Work

- Implement the deliverables after the listed prerequisites; retain every failed or incomplete observation in its original scope.
- Complete the listed acceptance in its declared evidence scope, retain the required records, and reconcile the source status catalogue before claiming closure.

## Retained Historical Contract and Evidence

The remainder records prior implementation, commands, status and failures. Its
claims retain their original source, policy and date. Superseded launch ordering,
resource rules and uninterrupted-process requirements do not override the current
sprints above. Preserve these receipts; do not execute a historical recipe as a
current authorized campaign.

## Retained Historical Phase State

⏸️ **Blocked**. Blocked by Phase 285 (Sprint 285.1).

The journal-derived registry is implemented and `jitml docs status` derives the
counts, open chain, and unmet obligations from committed evidence; closure waits on
Sprint `285.1`.

## Historical Sprint 288.1: Journal-Derived Status Registry [⏸️ Blocked]

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

## Historical Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

## Documentation Requirements

**Engineering docs to create/update:**

- [Validation execution](../documents/engineering/validation_execution.md),
  [execution resources](../documents/engineering/execution_resources.md),
  [run contract](../documents/engineering/run_contract.md), and
  [testing policy](../documents/engineering/unit_testing_policy.md).

**Product docs to create/update:**

- [Plan](README.md#validation-foundation-refactor), [overview](00-overview.md),
  [component inventory](system-components.md), and the corresponding lane
  report/portable evidence after actual qualification.

**Cross-references to add:**

- The current typed catalogue and [legacy removal ledger](legacy-tracking-for-deletion.md)
  name every changed owner and deprecated active path; original evidence is retained.
