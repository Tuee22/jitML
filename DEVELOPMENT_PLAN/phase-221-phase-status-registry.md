# Phase 221: Phase Status Registry

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Phase Status Registry. Originally migrated from legacy Sprint 19.2 in the 2026-07-24 phase renumber; see the old→new map in [README.md](README.md).

## Phase State

🔄 **Active** for the expanded validation foundation in Sprint `221.2`.
The earlier Sprint `221.1` record below is retained on its original source and
scope; it does not validate this target or a current hardware lane. The execution
order and transition authority are [the validation-foundation refactor](README.md#validation-foundation-refactor).

The new source/catalogue, runner and hardware controls remain unimplemented.
Sprint `221.2` owns reconciliation of the existing checker with these documented
targets; this documentation-only change supplies no machine-validation receipt.

## Sprint 221.2: Evidence-derived foundation status and dependency execution [🔄 Active]

**Status**: Active
**Implementation**: Target changes to `src/JitML/Product/PhaseStatus.hs`, `src/JitML/Product/StatusEvidence.hs`, `src/JitML/Product/StatusLoader.hs`, `src/JitML/Product/PlanDoc.hs`, `test/unit/JournalDerivedStatus.hs`.
**Docs to update**: `../documents/engineering/execution_resources.md`, `../documents/engineering/validation_execution.md`, `../documents/documentation_standards.md`, `../documents/engineering/unit_testing_policy.md`, `README.md`, `system-components.md`, `legacy-tracking-for-deletion.md`.

### Objective

The status catalogue represents reopened foundation sprints and explicit acyclic dependencies, and reports the first executable owners from evidence rather than numerical phase position.

The target contracts are [execution resources](../documents/engineering/execution_resources.md)
and [validation execution](../documents/engineering/validation_execution.md).
Their acceptance requirements below are planned work, not implemented behavior.

### Deliverables

- Add scoped gate-transcript obligations binding actual selected test inventory, invocation and source; a targeted pass never satisfies a full-stanza obligation. Classify hermetic, selected-lane and cross-lane aggregation cases without dropping or allowlisting any assertion. Hardware lanes must not require another lane's journal merely to run their local engineering checks.

- Register the named foundation sprints below Phase `220` and all expanded product `.2` and `.3` sprints while retaining complete product inventory. Stable IDs are identities; topological execution uses explicit dependencies with deterministic ID tie-breaking.
- Validate duplicate/missing owners, unknown dependencies and dependency cycles. Preserve single-host/at-most-one-accelerator execution affinity and accelerator-free aggregation; replace numerical backward-edge rejection with actual cycle detection.
- Keep historical `.1` evidence and the shrink-only legacy-attested boundary. A reopened existing obligation leaves legacy attestation; a new `.2` sprint is evidenced from inception and cannot be marked Done by a Markdown literal.
- Extend plan parsing and docs checks to multiple sprints and the foundation inventory, and reconcile all changed headers/dependencies/obligations. The documentation-only refactor has not changed this source machinery.
- Classify the retained unit failures by hermetic fixture, lane-specific runtime and evidence-consumer dependencies. Fix stale wire/PlanId fixtures and incorrect lane registration; no allowlist, omitted case or false unavailable-hardware pass.

### Validation

1. Add independent catalogue controls for a valid higher-numbered dependency, an actual cycle, unknown sprint, duplicate owner, missing foundation and wrong lane. Check deterministic ready-owner order.
2. Prove that an unimplemented target, missing transcript, stale journal or pending external prerequisite cannot derive Done. Historical receipts retain their original source and scope.
3. Run affected hermetic status/plan controls first; run lane-admission/evidence-consumer tests only after their declared inputs exist, preserving every original test obligation.
4. After source parity is implemented, run docs status/check and compare the reported open chain with the plan; old checker disagreement is an open implementation result, never waived by this prose.

Closure requires the owned targeted/hermetic controls listed above, with a
nonempty independently enumerated test inventory and exact scoped transcripts.
The implementation publishes actual selectable groups in the existing stanzas
and uses the supported `--test-options` passthrough; no invented selector or
unfiltered full-matrix acquisition is an acceptable substitute. A scoped result
is recorded as scoped, never as a passing full stanza. Resource/live controls
also require the actual owned runtime observations named above.

Complete evidence-dependent unit/integration/negative-control transcripts belong
to Sprints `277.2` and `280.2`; cross-family convergence belongs to `283.2` and
`285.2`. Those downstream records are not prerequisites for this foundation or
readiness closure. Every original case remains registered with an explicit owner.
The existing documentation/code-quality commands below run after source parity
is implemented, inside the admitted profile; they do not execute these controls.

```bash
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml docs status
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml docs check
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml check-code
```

Cluster-running jobs use the separately admitted cluster/lifecycle overlays
instead of the stopped-cluster build profile. A real hardware lane is never
claimed by CPU fixtures; absent required runtime capability fails that lane.

### Remaining Work

- Implement catalogue, graph, parsing and obligation changes; no source or test file is changed by the present documentation-only refactor.
- Classify and fix the retained unit failures, then run targeted hermetic controls and canonical status/docs checks. Full evidence-dependent suites close after their declared lane inputs exist.
- Publish actual new test selectors and derived ready-owner/status output before allowing downstream foundation sprints to claim validated readiness.

## Retained Historical Scope

The following state, commands, measurements and closure statements describe the
original Sprint `221.1` surface only. New execution rules and acceptance
above supersede any conflicting operational instruction; old receipts are not
reinterpreted as current readiness.

### Historical Phase State

✅ **Done**.

## Sprint 221.1: Phase Status Registry [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Product/PhaseStatus.hs`, `test/unit/Main.hs`
**Docs to update**: `development_plan_standards.md`, `00-overview.md`, `system-components.md`

### Objective

`src/JitML/Product/PhaseStatus.hs` is the single typed source of Phase `19`–`34`
sprint status. A parity test asserts the typed registry agrees with the `Status`
headers declared in each `phase-*.md`.

### Deliverables

- A typed `PhaseStatus` registry enumerates every product phase (Phases `19`–`34`)
  and each of its sprints with a `Done | Active | Planned | Blocked` value.
- A parity test parses the `**Status**` header of every `phase-*.md` sprint block
  and asserts it equals the typed registry entry; any drift is a failure.
- The registry exposes a total `allProductPhasesDone` predicate that later gates
  consume, defined only over Phases `19`–`34`.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-unit --linux-cpu  # passed, 244/244 tests
docker compose run --rm jitml jitml docs check                  # passed
docker compose run --rm jitml jitml check-code                  # passed
```

### Closure Evidence

- None.

## Documentation Requirements

**Engineering docs to create/update:**

- `../documents/engineering/execution_resources.md`.
- `../documents/engineering/validation_execution.md`.
- `../documents/documentation_standards.md`.
- `../documents/engineering/unit_testing_policy.md`.

**Product docs to create/update:**

- [Development-plan entry](README.md#validation-foundation-refactor), [component inventory](system-components.md), and [deletion ledger](legacy-tracking-for-deletion.md).

**Cross-references to add:**

- Link the target contracts, exact sprint dependencies and evidence pointers together when source implementation lands; update root summaries only in an authorized root-file change.
