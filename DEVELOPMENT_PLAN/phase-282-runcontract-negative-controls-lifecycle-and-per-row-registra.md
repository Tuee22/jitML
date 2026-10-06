# Phase 282: RunContract Negative Controls - Lifecycle and Per-Row Registration

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: RunContract Negative Controls - Lifecycle and Per-Row Registration. Single-session phase migrated from legacy Sprint 32.6 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

⏸️ **Blocked**. Blocked by Phase 281 (Sprint 281.1).

The lifecycle controls, the mandatory per-row registration, and the reply-cursor
harness transport are implemented and pass on the host and in the `linux-cpu`
container; closure waits on Sprint `281.1`. The Apple host-forwarding observer of
the transport is compile-only on this host and runs in Sprint `278.1`'s Mac session
(see Remaining Work).

## Sprint 282.1: RunContract Negative Controls - Lifecycle and Per-Row Registration [⏸️ Blocked]

**Status**: Blocked
**Implementation**: `src/JitML/Test/NegativeControls.hs`,
`src/JitML/Test/NegativeControls/Lifecycle.hs`,
`src/JitML/Test/NegativeControls/PerRow.hs`,
`src/JitML/Test/LifecycleFixtures.hs`, `src/JitML/Test/RunContract.hs`,
`src/JitML/Test/LiveWorkflow.hs`, `src/JitML/Test/LiveWorkflowEstablishment.hs`,
`src/JitML/Test/LivePulsarTransport.hs`, `src/JitML/Test/PulsarTransport.hs`,
`src/JitML/Service/PulsarWebSocketSubprocess.hs`,
`test/negative-controls/Main.hs`, `test/integration/Main.hs`,
`test/unit/Main.hs`
**Blocked by**: Sprint `281.1`
**Docs to update**: `../README.md`,
`../documents/engineering/run_contract.md`,
`../documents/engineering/product_completion_contract.md`,
`../documents/engineering/unit_testing_policy.md`,
`../documents/engineering/pulsar_ml_workflow.md`, `system-components.md`

### Objective

Prove that the contract handles the full run lifecycle — settlement, timeout,
cleanup, and terminal ordering — and make contract-negative coverage mandatory
for every product workflow row. This sprint closes the adversarial coverage for
[Exit Definition](README.md#exit-definition) items `31` and `32`.

### Deliverables

- Exercise successful and failed settlement, timeout, cleanup failure, workload-
  terminal-before-evidence, and evidence-before-workload-terminal orderings.
- Require every product workflow contract to register at least one negative
  control; accepting any known-invalid fixture fails the standing stanza.
- Publish a correlated harness request through an established reply cursor
  rather than the diagnostic `ConsumerSessionConnected` socket-open event. This
  obligation transferred from Sprint `263.1` on 2026-08-11 under standards rule
  `M(a)`; it is an ownership transfer, not a blocker, and Phase `263` is `Done`
  on its retained fragment-issuance surface. Phase `262` already retired the
  shape on the production inference client; the remaining call sites are the
  `JitML.Test.LiveWorkflow` publish-gate observer and the two live integration
  observers. The replacement is a transport redesign rather than a deletion:
  `establishReplyCursor` admits only a `FromLatest`/`Owned` subscription minted
  from a broker admin CREATE, while `LiveWorkflow` must keep running over the
  non-broker `LocalEventSource`, so the harness transport needs an
  establishment step that is inert for local sources.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-negative-controls --linux-cpu
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Current Partial Validation

- 2026-09-30: **58** lifecycle controls run the unmodified `runLiveWorkflow` over
  scripted scenarios — successful and failed settlement, every timeout shape,
  observation exhaustion, a probe failure that is not absence, workload failure
  after evidence, cleanup failure of placement, event source, owned object, and
  diagnostics (never minting completion), completion-boundary mismatch in both
  directions, establishment/publication/acquisition failures, and MVar-gated
  terminal-first and evidence-first orders that mint the same completion. Every
  constructor of six closed sums (40 items) must be covered through total
  classifiers under `-Werror=incomplete-patterns` plus a stanza coverage guard.
  `registerRow` is derived from the closed family/run-kind sum and **165** per-row
  controls (`invalid-request`, `wrong-plan-event`, and `foreign-admission` for each
  of the 55 ProductRows) share one Store-admitted fixture, behind a four-way
  registration guard (registry, projection batch, registrations, committed
  controls) with 16 self-tests and a twin in `jitml-unit`. `pendingProductionControls`
  is empty and no category is deferred; `jitml-negative-controls` holds **578**
  cases. A 104-mutation campaign turned every lifecycle control, per-row control,
  and guard red at least once.
- The harness no longer gates publication on the diagnostic
  `ConsumerSessionConnected` socket-open event: `runLiveWorkflow` establishes an
  opaque `EstablishedEventSource` (for Pulsar, an acknowledged admin CREATE of an
  `Owned`/`FromLatest` cursor) before publishing through it, consumes its `Borrowed`
  view, and releases it exactly once after diagnostics and before placement
  cleanup; a failed establishment publishes nothing. The local transport is
  inert. 33 new unit cases (25 establishment, 8 `PulsarTransport`) and 30 falsifiability mutations cover ordering,
  single release, cancellation identity, and the typed-executable subscription-only
  CREATE.
### Remaining Work

- Blocked until Sprint `281.1` closes, which waits on Sprint `278.1`.
- Run the four Validation commands on the final tree in the `linux-cpu` container
  lane and commit the validation records.
- Record the outcome of the Apple host-forwarding observer, which is compile-only
  here and runs in the Mac session Sprint `278.1` already requires (see its
  Remaining Work); this sprint owes no separate Mac session. The harness
  transport's live cases passed on the `linux-cpu` cluster on 2026-09-30
  (see Phase `278` Current Partial Validation), except that the Tune daemon case
  needed a wider observation window (now 600 s) for its 128-trial sweep.
- Consolidate the two scripted interpreter fakes: the establishment tests'
  broker script (`JitML.Test.LiveWorkflowEstablishment`, now private) and the
  lifecycle controls' scenarios (`JitML.Test.LifecycleFixtures`) overlap, and no
  consumer shares them today. This is test-code debt, not a ledger row.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
