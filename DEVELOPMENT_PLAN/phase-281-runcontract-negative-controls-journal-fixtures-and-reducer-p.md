# Phase 281: RunContract Negative Controls - Journal Fixtures and Reducer Properties

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: RunContract Negative Controls - Journal Fixtures and Reducer Properties. Originally migrated from legacy Sprint 32.5 in the 2026-07-24 phase renumber; see the old→new map in [README.md](README.md).

## Current execution ownership

**Historical record; no current execution gate.** Phases 1–289 retain their
original contracts, statuses and receipts below. Their former order, dependencies
and current-sounding statements are historical. They do not gate the new
[numerical execution sequence](ordered-execution-plan.md). No historical failure
is erased and no historical Done is promoted to current qualification.

Unfinished scope is **transferred, not completed**:

- Former sprint `281.2` → [311](phase-311-journal-reducer-controls.md), [328](phase-328-complete-standing-engineering.md).
- Former sprint `281.1` → [311](phase-311-journal-reducer-controls.md), [328](phase-328-complete-standing-engineering.md).

The [transfer register](ordered-plan-transfers.md) assigns implementation and
real-input acceptance separately. The complete retained contract is inherited;
examples or wrappers do not replace its detailed unmet requirements.

## Historical plan and evidence

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

## Sprint 281.1: RunContract Negative Controls - Journal Fixtures and Reducer Properties [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Sprint `261.2`
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

## Sprint 281.2: Campaign journal and reducer adversarial proof [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Sprint `261.2`
**Docs to update**: `../documents/engineering/validation_execution.md`, `../documents/engineering/execution_resources.md`, `../documents/engineering/run_contract.md`, `../documents/engineering/unit_testing_policy.md`, `README.md`, `system-components.md`

### Objective

Prove the new campaign/row reducer rejects fabricated completion and survives interruption without losing attempt history.

### Deliverables

- Cover gaps, conflicting duplicates, wrong source/PlanId/epoch, truncated commits, seed reordering, artifact mutation and unavailable authority.
- Check crash boundaries and replay deterministically; row completion requires every prescribed outcome and closing obligation.
- Keep hermetic reducer controls independent of hardware availability. Final real-record admission remains downstream.

### Validation

These are acceptance requirements for the target implementation. They are not
passes from this documentation change. Targeted failing controls run first; the
complete applicable stanzas run only after their actual evidence prerequisites
exist. Commands use the explicit named context and task-specific approved bounds;
cluster-running work uses the separately admitted cluster/lifecycle profile.

1. Demonstrate each guarded refusal with a deliberate negative and a valid paired case.
2. Pass targeted reducer properties followed by complete applicable unit/negative stanzas; unavailable future lane objects are explicit downstream prerequisites, not skipped positives.

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

⏸️ **Blocked**. Blocked by Phase 280 (Sprint 280.1).

The journal fixtures and reducer properties are implemented and pass on the host
and in the `linux-cpu` container; closure waits on Sprint `280.1`.

## Historical Sprint 281.1: RunContract Negative Controls - Journal Fixtures and Reducer Properties [⏸️ Blocked]

**Status**: Blocked
**Implementation**: `src/JitML/Test/NegativeControls.hs`,
`src/JitML/Test/NegativeControls/Journal.hs`,
`src/JitML/Test/JournalFixtures.hs`, `src/JitML/Test/ReducerProperties.hs`,
`src/JitML/Test/RunContract.hs`, `test/negative-controls/Main.hs`,
`test/unit/Main.hs`
**Blocked by**: Sprint `280.1`
**Docs to update**: `../documents/engineering/run_contract.md`,
`../documents/engineering/product_completion_contract.md`, `system-components.md`

### Objective

Prove that the contract rejects storage/completion journals that omit or corrupt
the opaque admitted identity, and that the event reducer stays total and
deterministic under event reordering and redelivery. This sprint owns the
journal-fixture and reducer-property portions of
[Exit Definition](README.md#exit-definition) items `31` and `32`.

### Deliverables

- Add journal fixtures that report storage success or caller-held completion but
  omit, substitute, or mismatch the opaque Store-admitted artifact identity;
  each must be rejected as ineligible without recreating admission logic in the
  harness.
- Property-test permutation invariance for independent events, idempotence for
  identical redelivery, deterministic rejection of conflicting duplicates, and
  exact missing-evidence diagnostics.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-negative-controls --linux-cpu
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml check-code
```

### Current Partial Validation

- 2026-09-30: **37** journal controls persist a Store-admitted journal in-process
  through the production writer, then omit, substitute, or mismatch its manifest
  identity (unsigned, and re-signed by a key holder) and read it back through the
  production authenticated reader, Store admission, and portable lane-journal
  admission; storage success without admission and a caller-held completion without
  an admitted checkpoint are both rejected as ineligible without the harness
  re-deriving admission. **19** QuickCheck reducer properties (permutation
  invariance, redelivery idempotence at any position, deterministic conflicting-
  duplicate rejection that leaves progress unchanged, exact ascending missing keys,
  left-then-right product diagnostics, wrong-plan rejection by every contract, and
  `CompletionJoin` laws) run in `jitml-unit`, and a fixed-seed subset of **9** runs
  inside the standing stanza. Every control family was shown to go red when its
  guarded check is weakened.
### Remaining Work

- Blocked until Sprint `280.1` closes, which waits on Sprint `278.1`.
- Run the three Validation commands on the final tree in the `linux-cpu` container
  lane and commit the validation records.

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
