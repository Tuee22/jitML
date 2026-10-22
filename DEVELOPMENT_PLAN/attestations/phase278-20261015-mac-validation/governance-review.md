# Phase 278 Proposed Lane Ownership Repair — 2026-10-15

**Status**: Supporting reference
**Supersedes**: N/A
**Referenced by**: [Mac validation index](README.md), [Phase 278 Remaining Work](../../phase-278-external-bars-no-self-referential-gate-lint-and-exact-served.md#remaining-work)
**Generated sections**: none

> **Purpose**: Record a proposed forward-only, single-host ownership split and
> the test-gate changes it would require, without changing current obligations.

## Decision state

**OWNERSHIP TRANSFER PROPOSED — NOT IMPLEMENTED.** This review itself changes no phase status, catalogue
entry, dependency or evidence pin. Phase `278` remains
Active under its current obligations; later open phases remain Blocked. The
proposal is not authority to close a phase from the current scoped Mac results.

The prerequisite [shared local gate](runtime-receipts/local-gate-validation/README.md)
is subsequently implemented and validated: source `9142…` preserves all original
unit/SL inventories and negative leaves, and the expanded unfiltered CPU stanza
passes **990 / 990**. Its private full unit run retains the same eighteen failed
leaves. This resolves the gate-existence question at that source checkpoint;
the ownership catalogue, phase validation requirements, integration dependency
audit and compact-policy implementation remain separate open work. Later policy
changes require fresh validation of the gate.

The separate [Phase 279 status correction](../../phase-279-measured-declared-type-split-behavioral-scaffold-lint.md#phase-state)
reopens that phase Blocked under rule `C` because its already-owned behavioral
detector remains a name scanner. That correction implements none of this
proposal's lane, aggregate or full-unit ownership transfers. The first executable
owner remains Phase `278`.

The current [catalogue](../../../src/JitML/Product/PhaseStatus.hs) makes `278.1`
own CPU, CUDA, and Apple journals, their aggregate, full Linux CPU unit/backend
records, and unresolved external contexts. Its
[Remaining Work](../../phase-278-external-bars-no-self-referential-gate-lint-and-exact-served.md#remaining-work)
already records the tension with
[standards M](../../development_plan_standards.md#m-forward-only-single-accelerator-numerically-ordered-phases).
That rule permits explicit downstream ownership transfer while requiring one
accelerator per phase, single-host closeability, and validation before advancing.
The syntactic zero-count plan scans do not resolve this semantic ownership issue.

## Why moving only the CUDA obligation fails

Moving the CUDA journal to `279.1` while retaining full CPU units in `278.1`
creates a cycle: `278.1` needs current CUDA evidence to pass its unit gate, but
`279.1` cannot begin until `278.1` validates. The reader must continue rejecting
the stale journal; changing an obligation line cannot make it current.

The same problem remains if only `278.1` transfers its unit gate. Existing
[Phase 279 Validation](../../phase-279-measured-declared-type-split-behavioral-scaffold-lint.md#validation)
also requires full CPU units. After issuing a new CUDA journal, those units
still require the retained aggregate to equal the current three-lane join.
If aggregate regeneration belongs to `280.1`, retaining that gate in `279.1`
requires future work before `279.1` can close.

The dependencies are concrete. [ProductAggregation tests](../../../test/unit/ProductAggregation.hs)
require all real retained lanes to admit and the retained aggregate bytes to
equal the typed projection. [ProductBarProvenance tests](../../../test/unit/ProductBarProvenance.hs)
also read the admitted CUDA/CPU journals for real-row positive and adversarial
cases. [JournalDerivedStatus](../../../test/unit/JournalDerivedStatus.hs) and
[ReportMeasurements](../../../test/unit/ReportMeasurements.hs) contain further
retained-CUDA acceptance checks. The Mac full-unit invocation encountered
eighteen journal-dependent failures. The transfer must cover the dependency
class, not assume eighteen remains the count after other contract changes.

## Additional integration dependency

The subsequent source audit finds a further backedge in the proposed split:
[the full integration stanza](../../../test/integration/Main.hs) at line 2884 calls
`ProductAggregation.readRetainedProductAggregation` and requires all three
pinned lanes. Full integration therefore cannot remain a must-pass Phase `278`
gate when the new CUDA journal and aggregate belong to `279` and `280`.
A reviewed repair must explicitly transfer that unchanged full standing gate
to `280` as well, while retaining meaningful local/live checks in `278`.
No integration test is deleted, filtered into a standing pass, or changed to
accept obsolete evidence. This correction is still a proposal, not a transfer.

## Proposed ownership

| Owner | Obligations after a reviewed transfer | Execution host |
|---|---|---|
| `278.1` | Final independently reviewed policy and source; complete local source/lint/served-byte/learning-signal/split controls; fresh complete CPU and Apple journals; independent real CPU live checks and backend checks; Apple backend checks; docs and container code quality | Mac with Metal and Docker CPU |
| `279.1`, explicitly reopened | Preserve its measured/declared and scaffold-lint obligations; issue and validate fresh complete CUDA evidence on the frozen contracts; validate its retained local obligations without requiring the future aggregate | NVIDIA host with Docker CPU |
| `280.1` | Preserve its request/event negative-control obligations; consume the three earlier journals; regenerate and validate the aggregate; pass the unchanged full CPU unit and integration suites and required negative controls | Any Docker host |

The proposed edge sequence is `278.1 → 279.1 → 280.1`; later existing edges
remain forward-only. This uses the existing identifiers rather than appending
an accelerator owner after its consumers. Reopening `279.1` expands its scope;
its original closure remains historical evidence for the surface actually
validated. It cannot remain a frozen legacy Done while owing new CUDA work.
The frozen legacy set and independent catalogue pins would shrink accordingly.
The separate behavioral-detector reopening now makes the seventy-sprint
inventory 62 Done, one Active, and seven Blocked. The proposed CUDA ownership
transfer would expand that already-reopened phase's obligations; the count is
not evidence that the transfer or its prerequisite local gate exists.

Both `278.1` and reopened `279.1` must explicitly transfer full-unit closure
ownership and cross-lane retained-evidence success obligations to `280.1`.
The unit tests can remain in the same suite and files: no success check is
deleted, skipped, weakened, or changed to accept an incomplete journal. The
reissued journals must still be complete real 55-row outputs. `280.1` performs
only CPU aggregation and validation, never an accelerator re-run.

## A genuine local gate is required before transfer

Removing the full-unit requirement without replacing validation of retained
local obligations would weaken the phase. `278.1` needs an actual unfiltered,
source-bound gate that includes all of its owned controls, with explicit
registration and coverage checks. Two possible implementations are:

- Register the owned local controls in the existing unfiltered negative-control
  stanza, provided its full dependency audit confirms it has no future-lane
  prerequisite and its expanded coverage is explicit.
- Add a dedicated test stanza and typed standing-gate support for these local
  controls. This requires the real CLI, record writer/reader, catalogue, and
  associated regression controls to recognize the stanza.

The first option now exists at the checkpoint linked above. Its inventory
must include bar independence and source lint, exact admitted serving bytes,
classification and regression learning-signal boundaries, generic RL cohort
binding, publisher rejection wiring, and Tiny selection behavior as applicable.
Positive fixture controls must accompany their rejection controls; they are
tests of predicates, not substitute training or convergence evidence. Audit
the candidate gate and required CPU integration invocation for imported
cross-lane/aggregate dependencies before declaring them independently closeable.

[StatusLoader.commandIsStanding](../../../src/JitML/Product/StatusLoader.hs)
deliberately rejects focused `--test-options` invocations as substitutes for
standing gates. The existing passing filtered Mac receipts remain scoped
diagnostics. They cannot be relabelled or newly admitted as full closure
records. [PlanDoc.validationObligationIssues](../../../src/JitML/Product/PlanDoc.hs)
must continue requiring every gate declared in a phase's `### Validation`
section to match an owned transcript obligation.

The global `StandingGate JitmlUnit LinuxCPU` remains unchanged in
[productStandingObligations](../../../src/JitML/Product/PhaseStatus.hs), together
with negative controls, model convergence, and ledger clearance.
[StatusEvidence.projectStatusReport](../../../src/JitML/Product/StatusEvidence.hs)
projects individual sprint obligations separately from those global product
closure requirements. Thus honest local closure could precede the global unit
pass, while the product closure verdict must continue refusing until the full
suite and every other standing requirement passes. Transferring ownership does
not remove the standing gate or make a red full-unit invocation green.

## Policy and evidence still required

The [independent anchor review](../phase278-20261015-mac-review/supervised-anchor-review.md)
does not establish defensible published acceptance floors for the exact compact
graphs, sample selections, and budgets. Additional majority/binomial and strict
positive-R² guards reject trivial models; they do not establish published-model
convergence. Existing stronger bars and the independent-policy obligation remain
in force. A fresh diagnostic score cannot choose its own threshold or slack.

Before implementing a transfer, review the final policy, exact split/recipe,
owned test inventory, and evidence requirements together. Freeze the recipe,
completion-policy and scenario-contract edits before fresh lane issuance.
Historical per-phase `GateTranscript` obligations retain their validated source
scope; a later source-only detector change does not automatically reopen an
earlier phase. Global `StandingGate` obligations require current source and
become stale after such changes. Changed lane recipes, contracts or pinned
journals can separately invalidate earlier lane obligations. A later genuine
Failed record replacing a Passed canonical gate also changes its judgement.
These existing distinctions in
[StatusEvidence](../../../src/JitML/Product/StatusEvidence.hs) preserve numerical
order without relaxing freshness, evidence admission or failure reporting. The
[detailed local-gate and seed reviews](policy-scope-review/README.md) retain the
source trace and implementation inventory; they implement no transfer.

Implementing this proposal alone would resolve neither the independent anchors
nor missing execution evidence. It would not close `278`, authorize beginning
`279` early, or justify a Mac Done label. Until a reviewed repair is actually
implemented and validated, the current catalogue and numerical order remain
binding.
