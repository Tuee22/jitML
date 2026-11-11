# Phase 287: Standing Adversarial Audit & Thin Plan

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Standing Adversarial Audit & Thin Plan. Originally migrated from legacy Sprint 34.2 in the 2026-07-24 phase renumber; see the old→new map in [README.md](README.md).

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

## Sprint 287.2: Standing audit of campaign truth and plan coherence [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Sprint `221.2`, Sprint `286.2`
**Docs to update**: `../documents/engineering/validation_execution.md`, `../documents/engineering/execution_resources.md`, `../documents/engineering/run_contract.md`, `../documents/engineering/unit_testing_policy.md`, `README.md`, `system-components.md`

### Objective

A standing audit checks the complete evidence-derived graph and thin current narrative against actual retained campaign evidence.

### Deliverables

- Check explicit dependency acyclicity, single-host lane affinity, no accelerator execution in aggregation, canonical topic ownership and current/target distinctions.
- Keep dated receipts and historical status out of current engineering claims; preserve curated historical evidence without making it a competing plan.

### Validation

These are acceptance requirements for the target implementation. They are not
passes from this documentation change. Targeted failing controls run first; the
complete applicable stanzas run only after their actual evidence prerequisites
exist. Commands use the explicit named context and task-specific approved bounds;
cluster-running work uses the separately admitted cluster/lifecycle profile.

1. Introduce missing/cyclic dependency, false completion, broken canonical link and stale policy fixtures and require precise failures.
2. Complete the production documentation/status and quality checks; no manually transcribed pass counts decide closure.

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

✅ **Done**.

## Sprint 287.1: Standing Adversarial Audit & Thin Plan [✅ Done]

**Status**: Done
**Implementation**: `DEVELOPMENT_PLAN/README.md`, `../documents/documentation_standards.md`, `development_plan_standards.md`
**Docs to update**: `README.md`, `00-overview.md`, `development_plan_standards.md`, `../documents/documentation_standards.md`

### Objective

A recurring adversarial realness audit is a required gate; the plan's `Closure Status`
becomes a thin pointer to evidence.

### Deliverables

- `development_plan_standards.md` adds a rule (N) requiring a periodic adversarial
  realness audit — authored/run by a process that does not own turning phases green —
  whose findings define status, and forbidding closure-narrative growth: `Closure
  Status` links to the machine-checkable evidence and does not accrete per-commit
  prose.
- The historical closure narrative is archived out of `README.md → Closure Status`
  into a dated appendix so the live status is short.

### Validation

```bash
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Closure Evidence

- Added rule N; archived the historical narrative; thinned `Closure Status`.

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
