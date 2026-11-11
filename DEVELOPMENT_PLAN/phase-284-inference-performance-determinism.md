# Phase 284: Inference-Performance & Determinism

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Inference-Performance & Determinism. Originally migrated from legacy Sprint 33.2 in the 2026-07-24 phase renumber; see the old→new map in [README.md](README.md).

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

## Sprint 284.2: Measured performance and within-lane determinism [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Sprint `263.3`, Sprint `268.2`, Sprint `273.2`
**Docs to update**: `../documents/engineering/validation_execution.md`, `../documents/engineering/execution_resources.md`, `../documents/engineering/run_contract.md`, `../documents/engineering/unit_testing_policy.md`, `README.md`, `system-components.md`

### Objective

Performance and determinism claims name the actual device, workload, resource envelope and measurement scope of the current campaigns.

### Deliverables

- Preserve within-substrate deterministic behavior and artifact identity without requiring numerical parity across substrates.
- Distinguish resource-induced timeout, execution failure and learning refusal. Set finite operational deadlines prospectively from required work and measured throughput; a changed deadline does not rewrite old outcomes.
- Retain actual inference/throughput/counter evidence and independently reviewed performance predicates; never infer speed from device labels.

### Validation

These are acceptance requirements for the target implementation. They are not
passes from this documentation change. Targeted failing controls run first; the
complete applicable stanzas run only after their actual evidence prerequisites
exist. Commands use the explicit named context and task-specific approved bounds;
cluster-running work uses the separately admitted cluster/lifecycle profile.

1. Verify reproducible within-lane artifacts/outputs under the declared policy and reject missing/foreign measurement provenance.
2. Run required model-convergence and current-lane performance checks through their hardware owners; CPU aggregation reruns no accelerator.

```bash
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml test jitml-model-convergence --linux-cpu
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml test jitml-unit --linux-cpu
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

## Sprint 284.1: Inference-Performance & Determinism [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Test/RowAssertions.hs`, `test/model-convergence/Main.hs`, `src/JitML/Product/ExternalBars.hs`
**Docs to update**: `../documents/engineering/training_metrics_and_splits.md`, `system-components.md`

### Objective

Every row reports a non-wall-clock inference-performance metric against a committed
floor, reproduced bit-identically on re-run.

### Deliverables

- SL rows assert examples/sec throughput ≥ floor; RL rows assert
  env-steps-to-threshold ≤ ceiling (sample efficiency); both from real inference on the
  trained artifact.
- A same-seed re-run reproduces the metric bit-identically (determinism contract).
- The performance floors live in `ExternalBars.hs`, never derived from the measured
  value.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-model-convergence --linux-cpu
docker compose run --rm jitml jitml check-code
```

### Closure Evidence

- Implemented the inference-performance assertions and floors.
- Revalidated the non-wall-clock inference-performance floors and same-seed
  determinism contract at the widened/vectorized regime:
  `docker compose run --rm jitml jitml test jitml-model-convergence --linux-cpu`
  passed **111 / 111** on 2026-07-10.

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
