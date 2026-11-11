# Validation Execution

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [engineering index](README.md), [execution resources](execution_resources.md), [run contract](run_contract.md), [testing policy](unit_testing_policy.md), [product completion](product_completion_contract.md), [plan standards](../../DEVELOPMENT_PLAN/development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Define durable campaign ownership, incremental readiness and complete qualification independent of agent-session lifetime.

## TL;DR

The supervisor owns execution; agents and terminal clients observe it. Every
experiment uses a bounded manifest. Readiness establishes a candidate's fit and
behavior before qualification. The target complete gate joins authenticated
whole-row cohorts from one immutable campaign and validates the full admitted
system. Observer disconnection does not invalidate an already completed unit.

## Current Status

**Implemented boundary.** ProductScenario integration uses a fresh command-owned
workspace and aggregate acquisition; selecting an individual integration
assertion can still acquire the whole matrix. Existing child authorization and
journal mechanisms do not implement durable row-commit recovery. Copied local
operators and personal multiplexer sessions are not the supported target owner.

**Target.** Reopened [Phase 160](../../DEVELOPMENT_PLAN/phase-160-functional-core-live-workflow-interpreter.md)
owns the durable supervisor; [Phase 261](../../DEVELOPMENT_PLAN/phase-261-contract-driven-live-execution-integration-journal.md)
owns campaign authorization and row journals; [Phase 262](../../DEVELOPMENT_PLAN/phase-262-contract-driven-live-execution-browser-and-playwright.md)
and [Phase 263](../../DEVELOPMENT_PLAN/phase-263-contract-driven-live-execution-fragment-issuance.md)
own the consumer and fragment changes. The implementation, negative controls
and real lane evidence must pass before this protocol can admit results.
No current interrupted attempt or diagnostic review is promoted by this text.
The [development plan](../../DEVELOPMENT_PLAN/README.md) owns implementation
status, execution order, remaining work and dated evidence.

## Scope and Authority

[Run contract](run_contract.md) owns opaque plan/evidence types, reducers and
production admission. [Execution resources](execution_resources.md) owns limits,
measurements and retirement. [Training metrics](training_metrics_and_splits.md)
owns learning predicates and data separation. This document owns execution
boundaries and their verification, not a new parallel CLI or result ledger.

## Target Owner and Observer Boundary

One maintained implementation owns the campaign's validated process identities,
launch, resource admission, cancellation, bounded capture, deadlines, terminal
receipts and preservation. Attempt directories under ignored `.build/` hold
data and immutable receipts rather than forks of executable operator code.
Actual launch arguments and observed guard expectations derive from one manifest.

The owner is independent of a Codex/Claude tool handle, usage allowance,
conversation lifetime, PTY or attached multiplexer client. Observer loss leaves
healthy owned execution running. The same campaign can be inspected after
reconnection. Supervisor or safety-monitor loss triggers bounded retirement;
there is no uncontrolled child left waiting for the agent to return.

VM start/stop remain explicit operator steps. A durable job does not enable boot
or login startup. Existing public command/schema machinery remains the CLI
boundary; new supported surface requires its own implementation and generated
reference change before it appears in an operator example.

## Evidence Classes

| Class | What it can establish | What it cannot establish |
|---|---|---|
| Diagnostic | A bounded experiment distinguishes a declared hypothesis | Qualification or an independently reviewed criterion |
| Readiness | A selectable row/test passes on recorded candidate inputs | Complete-lane admission or unaffected status after arbitrary edits |
| Engineering | Process, resource, numerical and evidence controls pass their owned cases | Convergence of untested rows or absent hardware |
| Qualified row | One complete cohort has an authenticated commit and sealed preservation | A complete lane by itself |
| Complete lane | Exact full coverage plus production admission and final consumer checks | Another substrate's execution or cross-substrate numerical parity |

A zero exit or a narrative count cannot change evidence class. Every attempted
unit records source/image, recipe, criterion, substrate/device, resource policy,
result and capture location. Tests that cannot be selected without retraining the
matrix receive a supported selectable boundary before repeated diagnostics.

## Incremental Readiness

A fix is followed first by the failing test or row. Remaining failed and never-run
units precede repeated green work. A source or shared-policy change records its
impact on prior passes and revalidates the affected set. Known failures are not
allowlisted to reach a full campaign.

Experiments have finite work, owned resources and a falsifiable question.
Allocation, throughput and learning investigations stay separate from qualifying
credentials. Diagnostic review copies remain non-authoritative. Prospective
changes to recipes or independently reviewed criteria create a new qualification
epoch; no policy is lowered to match a disappointing final observation.

Hermetic controls precede costly qualification. Cases requiring new admitted lane
objects run after their producer; all original cases retain explicit ownership.
Missing selected hardware fails its lane instead of becoming a skipped pass.

## Immutable Qualification Campaign

The campaign manifest binds full source identity, binary/image digests,
toolchains, host/device configuration, datasets, ordered ProductRows, numerical
recipes, seed cohorts, acceptance-review identities, execution policy and runner.
Initially every source change starts a new epoch. Dependency-scoped qualifying
source reuse is a separate future contract, not an implicit optimization here.

The smallest recoverable unit is a whole row cohort. It includes all prescribed
seeds and outcomes, authentic initial/final observations, fixed served index,
actual counters, trained artifacts, Store admission/replay and required
before/after preservation. No mid-seed trainer resumption is introduced.

Each attempt is append-only. Scientific refusal, infrastructure interruption and
cleanup failure retain distinct outcomes. Recovery is not permission to discard
failed seeds or search for a better cohort. A scientific refusal blocks that
epoch's qualification; a correction requires new readiness and a new epoch.

## Atomic Commit and Recovery

A durable authenticated row commit is published only after its evidence and
required after-state proof are sealed. The protocol defines atomic publication,
fsync and crash ordering. Training finished without required preservation is
incomplete. A crash invalidates unsealed work, while earlier valid sealed units
remain independently verifiable under the same epoch.

The persistent issuer credential lives in a private owner-only scope outside
row-child mounts and diagnostic output. Recovery verifies ownership, nonlink
paths, credential authority, exclusive campaign lock and exact manifest identity
before accepting any commit. Public digests or readable hash-named files cannot
mint completion. Missing/lost authority fails closed. The trusted-local-issuer
model is explicit; it does not claim resistance to a malicious same-user owner.

Recovery rechecks every retained object and receipt. It imports no historical
prefix, mixed source/device/criterion identity, reordered seed cohort or foreign
issuer. An unfinished unit reruns in full under the recorded retry policy and
attempt history; a scientific failure is not relabeled as infrastructure.

## Retention and Finite Recovery

The campaign owns explicit retention pins for every committed row's weights,
companions, outcomes, journal objects and Store snapshots. Pins survive observer
loss, VM shutdown and recovery, and prevent ordinary GC from invalidating a sealed
row. Admission reserves bounded disk space and declares the retention lifetime;
if capacity cannot cover retained evidence plus the next unit, it refuses work
without silently evicting qualified evidence. Release follows final portable
admission and discharge of downstream retention duties, or explicit recorded
campaign abandonment. Recovery archives retain their separate protection.

The immutable policy fixes a finite infrastructure retry allowance and an absolute
campaign expiry. Reconnection resets neither attempts nor deadlines. The owner
records the observation and rule authorizing an infrastructure classification;
ambiguous partial execution is not silently retryable. Scientific refusal cannot
be bypassed by generating a new campaign identifier for the same candidate. A
new qualifying attempt after refusal needs a justified correction, prospective
review and affected readiness evidence. Host reboot cannot launder elapsed time
or missing terminal/preservation facts into a fresh allowance.

## Complete Gate and Final Admission

The final production reader joins every required row exactly once in canonical
order and rejects omissions, duplicates, conflicting commits, unresolved failures
and mixed epochs. It reopens/rechecks exact physical artifacts and Store/replay
proofs, then runs the owned aggregate, integration, browser, preservation and
cleanup checks over the complete admitted catalogue.

Real-size accumulation validation measures retained results, journal handling
and publication rather than assuming isolated row fit establishes whole-campaign
fit. Fixtures precede a measured production boundary check. Neither is a
substitute for complete lane admission.

CPU, Apple and CUDA owners consume shared readiness independently on their real
hardware. Scheduling on one host enforces the resource contract. Aggregation
consumes the admitted lane objects without launching an accelerator. Changing an
observer session does not repeat already committed training.

## Verification Matrix

| Boundary | Required controls |
|---|---|
| Ownership | Observer disconnect/reconnect; agent exit; owner death; concurrent campaign refusal; exact child-family retirement |
| Observation | Silent/noisy child; output saturation; reader timeout; stale heartbeat; failed sample retained; cancellation during capture |
| Commit | Crash before/after publication; truncated write; partial preservation; missing credential; abandoned uncommitted row |
| Retention/retry | Committed rows protected during GC/pause/VM restart; bounded disk refusal; expired campaign; exhausted retry allowance; refusal cannot be hidden by a new identifier |
| Evidence | Foreign epoch; changed source/device/criterion; duplicate row; seed reorder; omitted failure; byte substitution; rollback/replay |
| Admission | Complete real row units plus exact full join; incomplete/mixed catalogue rejection; browser/fragment consumer rejection |
| Cleanup | Primary failure preserved alongside secondary errors; no surviving owned helper; required data preserved; explicit VM stop |

Controlled fixtures use safely bounded thresholds. The mechanism is accepted
only after the actual platform launcher, failure paths and reconnect behavior
pass, not merely a dry-run parse or a healthy heartbeat.

## Validation

The owning phases add the matrix above to existing unit, integration and
negative-control stanzas. Targeted cases run first, with complete required
engineering gates at their dependency boundary. Existing supported commands are:

```bash
# Example: container checks after explicit VM start and resource admission.
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml test jitml-unit --linux-cpu
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml test jitml-negative-controls --linux-cpu
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml docs check
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml check-code
```

Real hardware qualification uses its owner's admitted profile and substrate
flag; these commands do not grant campaign recovery to the current implementation.
Machine catalogue/checker reconciliation remains an obligation of Sprint
`221.2`. No fixture or documentation pass closes the hardware gate.
