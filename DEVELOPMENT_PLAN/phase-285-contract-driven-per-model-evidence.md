# Phase 285: Contract-Driven Per-Model Evidence

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Contract-Driven Per-Model Evidence. Single-session phase migrated from legacy Sprint 33.3 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

⏸️ **Blocked**. Blocked by Phase 282 (Sprint 282.1).

The per-model evidence consumer is implemented and passes on the host and in the
`linux-cpu` container against the retained `linux-cpu` and `linux-cuda` journals;
closure waits on Sprint `282.1` and on the `apple-silicon` journal.

## Sprint 285.1: Contract-Driven Per-Model Evidence [⏸️ Blocked]

**Status**: Blocked
**Implementation**: `src/JitML/Test/ModelEvidence.hs`,
`src/JitML/Test/ModelEvidence/Internal.hs`,
`src/JitML/Test/ModelEvidence/Raw.hs`, `src/JitML/Test/ModelConvergence.hs`,
`src/JitML/Test/RowAssertions.hs`, `src/JitML/Product/ExternalBars.hs`,
`test/model-convergence/Main.hs`, `test/model-convergence/Controls.hs`,
`test/model-convergence/WiringControls.hs`,
`test/model-convergence/GateControls.hs`,
`test/unit/ProductExperimentExactness.hs`
**Blocked by**: Sprint `282.1`
**Docs to update**: `../README.md`,
`../documents/engineering/training_metrics_and_splits.md`,
`../documents/engineering/unit_testing_policy.md`,
`../documents/engineering/product_completion_contract.md`,
`../documents/engineering/run_contract.md`, `system-components.md`

### Objective

Make every per-model convergence and inference-performance assertion consume an
opaque completed run-evidence value produced by the same plan and contract used
in live execution. This sprint owns the per-model portion of
[Exit Definition](README.md#exit-definition) item `31`.
The binding design is
[README.md → Typed run contracts](../README.md#typed-run-contracts).

### Deliverables

- Drive every row from a validated plan and accept only
  `CompletedRunEvidence rowKind` from its exact contract.
- For RL, keep ordered learning-iteration summaries distinct from the exact
  keyed final `EvaluationSet`; neither may be substituted for the other.
- Require a validated non-empty seed cohort, finite per-seed measurements, exact
  seed coverage, and the independent external convergence criterion.
- Bind inference-performance measurement to the completed artifact and plan
  identity used by training, rather than reading an unrelated latest artifact.
- Preserve within-substrate deterministic rerun assertions while making missing,
  duplicate, or cross-plan evidence a typed failure.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-model-convergence --linux-cpu
docker compose run --rm jitml jitml test jitml-negative-controls --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
```

### Current Partial Validation

- 2026-09-30: `jitml-model-convergence` is a fail-closed grader of opaque
  completed-run evidence. It reads `JITML_SUBSTRATE` (default `linux-cpu`), admits
  that lane's pinned retained journal through `admitProductLaneJournal` against the
  validated projection, joins one row-kind-indexed `ModelRowEvidence` per
  ProductRow, and grades final-quality convergence against a criterion re-derived
  from the canonical threshold tables (never the registry bar), learning
  telemetry, committed deterministic `PerformanceBound`s bound to the plan,
  experiment, and admitted-manifest identity, and the cohort binding, with typed
  missing, duplicate, cross-plan, wrong-lane, stale-contract, seed-coverage,
  non-finite, below-bar, and channel-substitution failures. The stanza holds
  **390** cases: with the `linux-cuda` journal and with the re-issued `linux-cpu`
  journal it passes **390 / 390**, and with the retained `apple-silicon` journal
  it fails closed on **222** lane-dependent cases with the typed diagnostic. No
  journal wire changed and no live measurement was added.
- The journals retain the refined `CompletedTraining` (observed units, update
  count, weight hashes, dataset digest, passed measurements) but no per-iteration
  learning curve, per-episode evaluation set, checkpoint bytes, served-artifact
  inference measurement, rerun digest, or per-seed cohort beyond the singleton.
  The evidence layer therefore keeps learning telemetry and final quality as
  distinct types with distinct assertions, bounds RL sample efficiency by the
  plan's exact transition budget, and does not claim a recomputed median or a
  measured inference. Observed counts already equal their budget at refinement, so
  the performance bounds hold by construction on any admitted row; they remain
  graded because the raw boundary can violate them, and each has a falsifiable
  control. The forgeable `RowAssertions` records still serve the SL and RL
  canonical stanzas and the gate-soundness controls; migrating them is recorded in
  the legacy ledger.
### Remaining Work

- Blocked until Sprint `282.1` closes, which waits on Sprint `278.1` and on the
  `apple-silicon` lane journal: the stanza is exactly as current as the retained
  journals and fails closed for a stale lane.
- Run the five Validation commands on the final tree in the `linux-cpu` container
  lane and commit the validation records.
- Two Deliverables are met only on the docs' own definitions. The inference-
  performance bound is bound to the artifact identity but grades recorded work
  counts (no inference is executed or measured), and the learning curve and keyed
  evaluation set are distinct types without retained data. Measuring inference from
  the admitted artifact, proving same-seed reruns per model, and retaining the
  curve, evaluation set, and per-seed cohort need new journal fields and therefore
  a re-issue of all three lane journals. The owner decides whether this sprint
  closes on the graded-evidence scope or waits for that schema.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
