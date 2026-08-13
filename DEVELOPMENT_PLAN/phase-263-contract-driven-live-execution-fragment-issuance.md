# Phase 263: Contract-Driven Live Execution - Fragment Issuance

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Contract-Driven Live Execution - Fragment Issuance. Single-session phase migrated from legacy Sprint 28.6 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

🔄 **Active** (2026-08-12). Reopened: the committed fragment is issued from the completed
scenario journal, but its `DeviceEvidence` column is derived from the declared
substrate and the declared claim rather than from what executed. The standing drift
gate therefore compares a declaration against itself, and passes on a lane where the
claim is false. The 2026-08-12 issuance remains valid evidence for the surface it
exercised — row identity, plan identity, and cross-process journal re-mint.

## Sprint 263.1: Contract-Driven Live Execution - Fragment Issuance [🔄 Active]

**Status**: Active
**Implementation**: `src/JitML/Test/Report.hs`, `src/JitML/Product/Matrix.hs`,
`src/JitML/Service/Workload.hs`, `src/JitML/Test/RunContract.hs`,
`test/integration/Main.hs`, `test/unit/Main.hs`,
`DEVELOPMENT_PLAN/attestations/linux-cpu-report-card.md`
**Docs to update**: `system-components.md`, `../README.md`

### Objective

The committed `linux-cpu` lane fragment is issued only from the completed
scenario journal produced by the full live matrix run, so no prose table or
hand-edited totals can attest a row cell the live lane did not prove.

### Deliverables

- Issue the committed `linux-cpu` lane fragment only from the completed scenario
  journal — no prose table or hand-edited totals.
- Prove every row cell through the full-matrix live run before the fragment is
  re-issued.

### Validation

```bash
docker compose run --rm jitml jitml test all --live --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Historical Validation

`jitml test all --live --linux-cpu` passed **11 / 11 invocations, 0 failed,
0 NotRun** in 43,940.53s on 2026-08-12 against image
`jitml:local@sha256:e36d6ca11f4cc75c231ac8ba2e7f238b1e1ce68623b550b55c94be075ad599e7`
and the nine-component single-worker `linux-cpu` publication
`6e57383cbcb8bd89b1ec08a6bd876651075e74707965f2fe31f0a1e3b28f1806`:
`jitml-integration` **197 / 197**, Playwright **77 passed**, `jitml-e2e`
**30 / 30**, `jitml-unit` **829 / 829**, `jitml-sl-canonicals` **36 / 36**,
`jitml-rl-canonicals` **47 / 47**, `jitml-hyperparameter` **26 / 26**,
`jitml-backends` **35 / 35**, `jitml-daemon-lifecycle` **54 / 54**,
`jitml-negative-controls` **3 / 3**, and `jitml-model-convergence` **111 / 111**.
`jitml docs check` and `jitml check-code` passed on the same source state. The
retained transcript is the gitignored
`.build/gate-logs/phase263-closure-gate.log`, SHA-256
`8c409f5c72477c752f7bd2ef97b5f301f49aab280428a7c66470d54efc3efc8a`.

Issuance is now derived rather than transcribed. `renderProductLaneAttestationFragment`
builds every product cell from the opaque `CompletedProductScenarioReport` — row
id, `generated-matrix:` catalog address, integration and e2e test identities, the
negative-control cell guarded by the journal-enforced pre-completion rejection
flag, the claim-level device evidence, and the executing lane — with no
`MISSING` branch, because coverage, duplicates, orphans, plan identity, lane
identity, and contract staleness already fail closed in
`projectCompletedProductScenarioReport`. `productLaneAttestationFragmentDrift`
extracts the committed table with the same predicate the legacy parser uses, so
the comparator and the parser cannot disagree about which lines are the table.
The live case `Phase 263 issues the committed lane fragment from the completed
scenario journal` renders from the **journal** report rather than the executed
one, making the comparison a cross-process re-mint from persisted HMAC-bound
rows, and reports drift per row and column.

The committed table required no edit: the run reported zero drift, so its cells
are unchanged. That is the expected outcome, not evidence the work was vacuous.
Before this phase the `DeviceEvidence` column was unverified prose that merely
happened to match — `productRowDeviceEvidenceForSubstrate` had no caller
anywhere in the repository. It is now a wrapper over the claim-level
`deviceEvidenceForClaim`, which the issuer calls and which a standing unit case
pins against the row-level composer for all 55 rows across all three substrates.

Retirement: the provenance-free `CheckpointList` renderers
(`renderCheckpointListResult`, `renderCheckpointListResultWithSelectors`,
`checkpointSelectorState`) are deleted with their exports and their two
fabricated-frame fixtures. They had no production caller;
`renderAdmittedProductBrowserCatalogue` is the sole producer of the frame the
Engine publishes, and the retired renderer omitted the `run-id`, `substrate`,
`catalogue-sha256`, and `source-journal-sha256` fields the topology validator
requires. The authenticated frame's field set stays pinned by the Phase `262`
validator/contract unit case and by the live browse cases, because
`AdmittedProductBrowserCatalogue` is abstract and cannot be forged offline.

Scope note: this phase retains the fragment-issuance surface and transfers the
harness half of the readiness contract — publishing a correlated request through
an established reply cursor instead of the diagnostic `ConsumerSessionConnected`
event — forward to Sprint `281.1` under standards rule `M(a)`. That residue is a
transport redesign rather than a deletion: `establishReplyCursor` admits only a
`FromLatest`/`Owned` subscription minted from a broker admin CREATE, while
`JitML.Test.LiveWorkflow` must keep running over the non-broker
`LocalEventSource`. The legacy prose parser, `ProductRowReportEvidence`, and the
cross-lane round-trip tests are deliberately retained for Phase `275`, which owns
retiring them; changing the fragment's wire shape here would strand the
`linux-cuda` and `apple-silicon` lanes behind the Phase `272` hardware boundary.

### Remaining Work

- Re-issue the committed `linux-cpu` fragment from witness-minted device evidence
  once Sprint `229.1` lands the witness type.
- Re-run the full live gate so the drift comparison is measurement against
  commitment rather than declaration against declaration.

### Historical Phase State

> ✅ **Done** (2026-08-12). The committed `linux-cpu` lane fragment is issued only
> from the completed scenario journal, and a standing live case fails closed on any
> drift between the committed table and that issuance.

*(Retained as historical evidence for the surface it exercised; superseded by the 2026-08-12 reopen above.)*

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
