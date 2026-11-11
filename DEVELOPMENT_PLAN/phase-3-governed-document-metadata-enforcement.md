# Phase 3: Governed-Document Metadata Enforcement

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Governed-Document Metadata Enforcement. Originally migrated from legacy Sprint 0.3 in the 2026-07-24 phase renumber; see the old→new map in [README.md](README.md).

## Phase State

⏸️ **Blocked** for the expanded validation foundation in Sprint `3.2`.
The earlier Sprint `3.1` record below is retained on its original source and
scope; it does not validate this target or a current hardware lane. The execution
order and transition authority are [the validation-foundation refactor](README.md#validation-foundation-refactor).

The new source/catalogue, runner and hardware controls remain unimplemented.
Sprint `221.2` owns reconciliation of the existing checker with these documented
targets; this documentation-only change supplies no machine-validation receipt.

## Sprint 3.2: Canonical doctrine ownership and executable documentation governance [⏸️ Blocked]

**Status**: Blocked
**Implementation**: Target changes to `src/JitML/Docs/Check.hs`, `src/JitML/Lint/Docs.hs`, `src/JitML/Product/PlanDoc.hs`.
**Blocked by**: Sprint `221.2`.
**Docs to update**: `../documents/engineering/execution_resources.md`, `../documents/engineering/validation_execution.md`, `../documents/documentation_standards.md`, `../documents/engineering/code_quality.md`, `README.md`, `system-components.md`, `legacy-tracking-for-deletion.md`.

### Objective

The documentation checker enforces one canonical owner per durable contract, current-versus-target boundaries, valid links and anchors, and evidence-backed phase state. Root authority migration remains explicit work; the root files are outside this documentation-only refactor.

The target contracts are [execution resources](../documents/engineering/execution_resources.md)
and [validation execution](../documents/engineering/validation_execution.md).
Their acceptance requirements below are planned work, not implemented behavior.

### Deliverables

- Reconcile the plan and documentation standards through an authority-transfer inventory: contract, old root anchor, canonical topic owner, consumer changes, replacement link, and acceptance check. Keep the existing root CLI contract binding until its transfer is implemented and verified.
- Check relative link targets and section anchors, required metadata, generated-region ownership, and portable paths. A missing shared resource protocol must fail; an index cannot mint an implemented contract.
- Migrate root incident diaries and duplicate architecture to their canonical homes only in a subsequent change authorized to edit `README.md`, `AGENTS.md`, and `CLAUDE.md`; retain useful curated history and temporary redirect anchors with deletion owners.
- Reconcile actual derived sprint status and the explicit dependency graph after `221.2`; no Markdown declaration is proof that the new operational contracts exist.

### Validation

1. A missing target, broken anchor, duplicate canonical owner, generated-marker mismatch, and target phrased as implemented each fail their owned checker controls.
2. Valid metadata, a target labeled with its implementation owner, and an intentional historical evidence section pass without manufacturing reciprocal backlinks.
3. Check the root-authority inventory and all changed references before retiring any old binding anchor.

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
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml docs check
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml check-code
```

Cluster-running jobs use the separately admitted cluster/lifecycle overlays
instead of the stopped-cluster build profile. A real hardware lane is never
claimed by CPU fixtures; absent required runtime capability fails that lane.

### Remaining Work

- Implement the new link/authority checks and reconcile their source registration with the documentation targets.
- Complete the authorized root-document migration as a separate implementation change; no root file is changed by this refactor.

## Retained Historical Scope

The following state, commands, measurements and closure statements describe the
original Sprint `3.1` surface only. New execution rules and acceptance
above supersede any conflicting operational instruction; old receipts are not
reinterpreted as current readiness.

### Historical Phase State

✅ **Done**.

## Sprint 3.1: Governed-Document Metadata Enforcement [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Docs/Check.hs`, `src/JitML/Lint/Stack.hs`,
`DEVELOPMENT_PLAN/attestations/*.md`,
`documents/documentation_standards.md`
**Docs to update**: `README.md`, `DEVELOPMENT_PLAN/README.md`,
`DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`,
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`,
`documents/engineering/code_quality.md`

### Objective

Make the documentation metadata contract executable instead of aspirational.
Owns the project-doctrine `Generated Artifacts` and documentation-standard
surfaces for governed Markdown files.

### Deliverables

- `jitml docs check` validates the required governed-document header fields:
  `Status`, `Supersedes`, `Referenced by`, `Generated sections`, and `Purpose`.
- The `Generated sections` metadata must agree with physical generated-region
  markers and with the `GeneratedSectionRule` registry.
- The three per-lane attestation documents carry `**Supersedes**: N/A`, matching
  [../documents/documentation_standards.md](../documents/documentation_standards.md).
- Documentation status lives in `DEVELOPMENT_PLAN/README.md`; engineering docs
  explain architecture and link back instead of maintaining a competing status
  ledger.

### Validation

- `docker compose run --rm jitml jitml docs check`
- `docker compose run --rm jitml jitml lint docs`
- `docker compose run --rm jitml jitml check-code`

### Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**

- `../documents/engineering/execution_resources.md`.
- `../documents/engineering/validation_execution.md`.
- `../documents/documentation_standards.md`.
- `../documents/engineering/code_quality.md`.

**Product docs to create/update:**

- [Development-plan entry](README.md#validation-foundation-refactor), [component inventory](system-components.md), and [deletion ledger](legacy-tracking-for-deletion.md).

**Cross-references to add:**

- Link the target contracts, exact sprint dependencies and evidence pointers together when source implementation lands; update root summaries only in an authorized root-file change.
