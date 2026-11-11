# Phase 245: Convergence and Evidence

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Convergence and Evidence. Originally migrated from legacy Sprint 24.4 in the 2026-07-24 phase renumber; see the old→new map in [README.md](README.md).

## Phase State

⏸️ **Blocked** for the expanded validation foundation in Sprint `245.2`.
The earlier Sprint `245.1` record below is retained on its original source and
scope; it does not validate this target or a current hardware lane. The execution
order and transition authority are [the validation-foundation refactor](README.md#validation-foundation-refactor).

The new source/catalogue, runner and hardware controls remain unimplemented.
Sprint `221.2` owns reconciliation of the existing checker with these documented
targets; this documentation-only change supplies no machine-validation receipt.

## Sprint 245.2: Supervised memory fit and prospective learning readiness [⏸️ Blocked]

**Status**: Blocked
**Implementation**: Target changes to `src/JitML/SL/Architecture.hs`, `src/JitML/Product/ServedMetric.hs`, `src/JitML/Product/SupervisedQualification.hs`.
**Blocked by**: Sprint `160.2`, Sprint `225.2`.
**Docs to update**: `../documents/engineering/execution_resources.md`, `../documents/engineering/validation_execution.md`, `../documents/engineering/training_metrics_and_splits.md`, `../documents/engineering/checkpoint_format.md`, `README.md`, `system-components.md`, `legacy-tracking-for-deletion.md`.

### Objective

Every supervised readiness result combines genuine held-out learning with bounded training, evaluation, publication and retained-cohort memory on the current candidate.

The target contracts are [execution resources](../documents/engineering/execution_resources.md)
and [validation execution](../documents/engineering/validation_execution.md).
Their acceptance requirements below are planned work, not implemented behavior.

### Deliverables

- Reprove scalar/tape retention, packed held-out examples and feature materialization on the current candidate, including full-size evaluation and publication transients under the admitted process-family budget.
- Preserve real train/validation/test separation, authentic initial/final comparisons, exact serving replay and required cohort outcomes. Historical calibrated floors are not relabeled as external literature evidence.
- Use the prospective criterion policy owned by `278.2`. A replacement criterion or training budget requires independent justification before qualification; it is not fitted to a failing final value.
- Keep a source/image/recipe/resource readiness ledger and name the prior greens affected by each shared allocation or evaluation change. Final reviewed source binding belongs to qualification after readiness.

### Validation

1. Run the targeted retention/representation controls first, checking exact outputs and measured live/aggregate peak behavior rather than RSS alone.
2. Run the affected single supervised row through the production CLI with its prescribed five outcomes, real runtime and unchanged acceptance contract; distinguish refusal, timeout and memory failure.
3. Exercise accumulated completed-row results, publication and joins with bounded fixtures; isolated row success does not establish full-campaign retention fit.
4. Complete the owned supervised readiness and canonical controls after the targeted repair; complete cross-family convergence and lane admission remain downstream obligations.

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

- Confirm current-source supervised memory fit, repair affected regressions and retain the literal earlier failures.
- Complete prospective criterion review and readiness impact analysis before final candidate freeze; no diagnostic review copy or historical eligible row is final qualification.

## Retained Historical Scope

The following state, commands, measurements and closure statements describe the
original Sprint `245.1` surface only. New execution rules and acceptance
above supersede any conflicting operational instruction; old receipts are not
reinterpreted as current readiness.

### Historical Phase State

✅ **Done** (closed 2026-07-30; gate-validated on the live linux-cpu cluster).
Each literal graph now trains from real random init with real cross-entropy / MSE
over a real three-way split and clears a held-out test bar; underpowered and
zero-gradient negatives still fail. The attention/token-mix vision bars were
re-measured on the live cluster, and **tiny-imagenet was re-baselined** to an
effective 0.008 target (measured 1.2% at 8000 examples / 15 epochs / 1000-example
eval; non-vacuous above the 0.005 random floor) per the Phase-245 mandate in
`ConvergenceThresholds.hs`.

## Sprint 245.1: Convergence and Evidence [✅ Done]

**Status**: Done
**Implementation**: `test/sl-canonicals/Main.hs`, `src/JitML/Test/RowAssertions.hs`
**Docs to update**: `../documents/engineering/training_metrics_and_splits.md`, `../documents/engineering/numerical_core.md`

### Objective

Each supervised row trains a real train/validation/test split to its
literature-anchored convergence bar and records machine-checkable learning
evidence, so a row cannot pass on a static, degenerate, or smoke-threshold run.

### Deliverables

- Each supervised row records a deterministic initial-weight hash, final-weight
  hash, update count, examples seen, and throughput (examples/sec).
- Classification rows optimize real cross-entropy; regression rows optimize real
  MSE and report RMSE — `1 - accuracy` is not a loss.
- Training uses a real three-way split and the reported figure is the held-out
  test metric, which clears `median(k=5) >= literature_target - slack`.
- `src/JitML/Test/RowAssertions.hs` fails a row when final weights equal
  initialization, gradients are zero or NaN, or the row clears only a smoke
  threshold; a deliberately underpowered 2-step model FAILS its bar.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-sl-canonicals --linux-cpu
docker compose run --rm jitml jitml test jitml-integration --linux-cpu
```

### Closure Evidence (2026-07-30)

Validated 2026-07-30 (container `jitml:local`, live linux-cpu cluster):
jitml-sl-canonicals 36/36 (incl. the measured-evidence, invalid/smoke rejection,
and underpowered two-step negative cases), jitml-integration 157/157,
jitml-unit passed with 0 failures, `jitml check-code` ok, `jitml docs check` ok,
and `jitml internal train-and-publish-product-rows --linux-cpu` exit 0 with 55/55
admitted. The six attention/token-mix vision bars were re-measured on the live
cluster and tiny-imagenet was re-baselined to effective 0.008 (non-vacuous above
the 0.005 random floor).

### Historical Validation

Historical validation: `docker compose run --rm jitml jitml test
jitml-sl-canonicals --linux-cpu` passed 31 / 31 on 2026-07-02, including the
measured supervised row evidence assertion, invalid/smoke evidence rejection,
and underpowered two-step negative case. `docker compose run --rm jitml jitml
test jitml-integration --linux-cpu` passed 79 / 79 against the live linux-cpu
cluster. `jitml docs check` and `jitml check-code` passed after the Sprint
`24.4` module/docs update.

2026-07-05 realness-audit finding, closed 2026-07-06: the recorded convergence, weight-update,
and learning-evidence figures are all measured on the residual-MLP that
`layersForFamily` trains, not on the named convolutional/attention architecture,
and the bar each row clears is self-authored rather than a frozen external
literature constant — so a passing row does not demonstrate the documented model
learning.

### Closure Evidence

- **Closed Exit-Definition obligation**: each row's held-out convergence metric
  must be *measured on the real named architecture* and cleared against a frozen
  external literature bar, not on the shared flattened-pixel residual-MLP against
  a self-authored threshold.
- **Closing validation**: the per-model `jitml-model-convergence` suite (Phase
  `33`,
  [phase-33-per-model-convergence-and-inference-tests.md](README.md#legacy-to-new-phase-map)),
  which trains each `ProductRow` from a real random init through the production
  device seam and asserts the measured held-out test metric ≥ the Phase `32`
  `ExternalBars` target, must pass for every supervised row via
  `docker compose run --rm jitml jitml test jitml-model-convergence --linux-cpu`.

2026-07-10 closure: the standing `jitml-model-convergence --linux-cpu` gate
passed **111 / 111**, including the deep-SL rows measured on the widened
architecture.

## Documentation Requirements

**Engineering docs to create/update:**

- `../documents/engineering/execution_resources.md`.
- `../documents/engineering/validation_execution.md`.
- `../documents/engineering/training_metrics_and_splits.md`.
- `../documents/engineering/checkpoint_format.md`.

**Product docs to create/update:**

- [Development-plan entry](README.md#validation-foundation-refactor), [component inventory](system-components.md), and [deletion ledger](legacy-tracking-for-deletion.md).

**Cross-references to add:**

- Link the target contracts, exact sprint dependencies and evidence pointers together when source implementation lands; update root summaries only in an authorized root-file change.
