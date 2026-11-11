# Phase 289: Evidence-Typed Report Measurements

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Evidence-Typed Report Measurements. Originally migrated from legacy Sprint 34.4 in the 2026-07-24 phase renumber; see the old→new map in [README.md](README.md).

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

## Sprint 289.1: Evidence-Typed Report Measurements [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Sprint `289.2`
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

## Sprint 289.2: Final evidence-typed report and handoff [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Sprint `288.2`, Sprint `285.2`, Sprint `287.2`, Sprint `278.3`, Sprint `279.2`
**Docs to update**: `../documents/engineering/validation_execution.md`, `../documents/engineering/execution_resources.md`, `../documents/engineering/run_contract.md`, `../documents/engineering/unit_testing_policy.md`, `README.md`, `system-components.md`

### Objective

Final handoff exposes only measurements and completion states supported by the exact current campaigns and all required clean gates.

### Deliverables

- Render immutable row/lane/source/criterion identities, all-attempt history and the limits of each measured claim.
- Require complete current evidence, no owned pending legacy residue, clean required suites, real browser outcomes and final preservation/stop receipts.
- Do not equate controlled containment with universal kernel-panic immunity or claim scientific generalization beyond the actual qualification design.

### Validation

These are acceptance requirements for the target implementation. They are not
passes from this documentation change. Targeted failing controls run first; the
complete applicable stanzas run only after their actual evidence prerequisites
exist. Commands use the explicit named context and task-specific approved bounds;
cluster-running work uses the separately admitted cluster/lifecycle profile.

1. Verify report types reject declarations, absent/foreign evidence and incomplete coverage, including real browser consumer records.
2. Pass the final complete CPU unit/negative/convergence/live-e2e stanzas and current docs/quality checks without accelerator retraining.

```bash
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml test jitml-unit --linux-cpu
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml test jitml-negative-controls --linux-cpu
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml test jitml-model-convergence --linux-cpu
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml test jitml-e2e --live --linux-cpu
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

⏸️ **Blocked**. Blocked by Phase 288 (Sprint 288.1).

The evidence-typed measurements are implemented and pass on the host and in the
`linux-cpu` container; closure waits on Sprint `288.1`.

## Historical Sprint 289.1: Evidence-Typed Report Measurements [⏸️ Blocked]

**Status**: Blocked
**Implementation**: `src/JitML/Test/Measurement.hs`,
`src/JitML/Test/TrainingMeasurement.hs`, `src/JitML/Test/LiveMeasurements.hs`,
`src/JitML/Test/Report.hs`, `src/JitML/Test/Command.hs`,
`src/JitML/Test/BrowserEvidenceJournal.hs`, `src/JitML/Test/LiveE2EScope.hs`,
`src/JitML/App.hs`, `test/unit/ReportMeasurements.hs`, `test/unit/Main.hs`,
`test/e2e/Main.hs`
**Blocked by**: Sprint `288.1`
**Docs to update**: `../documents/engineering/run_contract.md`,
`../documents/engineering/unit_testing_policy.md`,
`../documents/engineering/training_workloads.md`, `README.md`

### Objective

Represent report measurements as typed evidence and derive suite, lane, and
product counts from execution journals rather than a second post-test
measurement path. This sprint owns the [Exit Definition](README.md#exit-definition)
item `33` (lossless process and suite outcomes). It reads the journal-derived
status registry that Sprint `288.1` lands.

### Deliverables

- Represent report measurements as
  `NotRequested | Unavailable reason | Available evidence`; remove overlapping
  `Maybe` fields and unavailable sentinels.
- Derive suite counts from `Passed | Failed | NotRun` invocation results and
  lane/product counts from validated scenario journals.
- Remove post-test probes that manufacture a second measurement path; reports
  are projections of execution evidence already captured by the interpreter.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml test jitml-negative-controls --linux-cpu
docker compose run --rm jitml jitml test jitml-model-convergence --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
docker compose run --rm jitml jitml test jitml-e2e --live --linux-cpu
```

The last command needs the live cluster (`jitml bootstrap --linux-cpu`) with the
twelve canonical datasets staged (the `stage_dataset` commands in Phase `262`'s
Validation); it runs the complete integration matrix as its producer, about 10–14 h
on an otherwise idle host (the fail-closed four-hour per-row envelope of Phase `262`
expires under CPU contention, see Current Partial Validation).
Its validation record is the one this sprint commits: the derived status accepts a
`jitml-e2e` transcript only when it records the live run, because a non-live pass
never executes the live measurement glue in `Command.hs` that this sprint owns.

### Current Partial Validation

- 2026-09-30: report measurements are `Measurement e = NotRequested |
  Unavailable UnavailableReason | Available e` with a closed reason set, so a
  requested measurement whose source failed renders `unavailable (<reason>)` and is
  never indistinguishable from `NotRequested`. Suite counts derive from
  `Passed | Failed | NotRun` invocations; completed and eligible product counts and
  the browser row denominator derive from the validated ProductScenario journal and
  the registry. The post-test probes (SL retrain, fresh PPO/cartpole, fixed-seed
  AlphaZero, re-run tuning sweep, raw-socket `/metrics` and `/healthz`) and their
  `TestCommandRuntime` fields are deleted; the four family report lines are
  projections of `completedTrainingMetrics`. The committed lane fragment and
  `product_rows:` block are byte-unchanged. **43** new `jitml-unit` cases and the
  non-live `jitml-e2e` suite (**28**) pass, with **18** mutations shown red.
- 2026-10-01: the first `jitml test jitml-e2e --live --linux-cpu` attempt on the final
  tree (fresh `linux-cpu` cluster, twelve datasets staged) ran **36,402 s** and failed
  closed. The ProductScenario's four-hour envelope expired on row 9, `cifar10-vit`,
  while an unrelated workload held the host at load ≈ 35 on 32 cores, so its **72**
  integration failures were the Apple aggregate case plus the cases that depend on the
  completed scenario; the other **126** passed. Capping the lane container to 26 of 32
  cores (a compose `cpuset`) left headroom: the retry completed the whole matrix in
  **44,731 s** and passed **197 / 198** integration cases. The one failure is the
  `Phase 276: retained product aggregate` case, which fails while the Apple journal is
  stale, and it blocks the Playwright and Haskell e2e steps behind it (`NotRun`), so the
  standing live e2e cannot pass until Phase `278`'s Apple journal is re-issued.
- 2026-10-05/06, diagnostic only: with that single case excluded through
  `TASTY_PATTERN` (the orchestrator builds the integration producer without user test
  options, so `--test-options` does not reach it), the live e2e lane ran end to end in
  **41,559 s** and exited `0`: `jitml-integration` **197 / 197**, `jitml-e2e-playwright`
  **PASS** (**77 / 77** browser tests in 52.6 s), `jitml-e2e` **28 / 28**. This is the
  first execution of the `Command.hs` live glue: the report card shows `Available`
  measurements projected from the validated scenario journals (supervised metrics for all
  11 rows, the 39 RL median rewards, the four AlphaZero arena win rates, tuning best
  objective `0.9754`, `product_row_counts: completed=55/55 supervised=11/11 rl=39/39
  alphazero=4/4 tuning=1/1`, and `browser_product_matrix: 55/55 Passed`), while the two
  edge observations render `unavailable (not journaled: …)` as designed. The records the
  run wrote carry the live wrapper (`/usr/bin/nice -n 10 …/cabal test jitml-e2e`), and the
  loader judges the passing e2e record `proven`, so a real live record satisfies the
  live-gate rule. The run is not closure evidence: its integration producer ran with a
  test excluded, which is exactly what the new environment guard now refuses to record
  (see Phase `288`).
- The jit-cache and healthz observations cannot be journaled as `LivePlan` body
  steps (the edge port is leased after the plan is fixed and body steps would
  inflate suite counts), so they render `unavailable (not journaled: <observation>)` on every live
  run; the `Command.hs` live glue is type-checked and covered through its pure
  functions; it ran end to end in the diagnostic live run recorded above.
### Remaining Work

- Blocked until Sprint `288.1` closes, which waits on Sprint `278.1`.
- Run the Validation commands in the `linux-cpu` container lane on the final tree,
  and run the live e2e command above once Sprint `278.1` has re-issued the Apple
  journal: until then its integration producer fails the Phase `276` aggregate case and
  Playwright and the Haskell e2e suite do not run. On a shared host cap the container
  (for example `cpuset: "0-25"` in a compose override) so other workloads cannot push a
  row past the four-hour envelope. Commit the resulting `jitml-e2e.linux-cpu.json`
  record; the diagnostic run above is not that evidence.
- Add journaled observation steps for the edge `/metrics` and `/healthz` readings
  (a deferred, port-resolving plan step that does not count as a test invocation)
  so those two fields can carry evidence instead of `not journaled`.

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
