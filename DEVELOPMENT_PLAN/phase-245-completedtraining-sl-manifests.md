# Phase 245: CompletedTraining SL Manifests

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: CompletedTraining SL Manifests. Single-session phase migrated from legacy Sprint 24.5 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

⏸️ **Blocked**. Blocked by Phase 244 (Sprint 244.1).

## Sprint 245.1: CompletedTraining SL Manifests [⏸️ Blocked]

**Status**: Blocked
**Implementation**: `src/JitML/SL/{Architecture,TrainingExecution}.hs`,
`src/JitML/Product/Completion.hs`, `test/sl-canonicals/Main.hs`
**Blocked by**: Sprint `244.1`
**Docs to update**: `../documents/engineering/training_workloads.md`,
`../documents/engineering/training_metrics_and_splits.md`

### Objective

Every supervised row hands the checkpoint boundary its exact trained
`LayerGraph`, initial and final flat weights, verified dataset-at-read digest,
measured update count, exact plan identity/budget, and passing convergence
observations, recorded as a CompletedTraining SL manifest. Phase `239` owns
constructing the single supervised-graph envelope from that graph; Phase `236`
alone admits a persisted artifact as inference eligible. This sprint also
migrates the checkpoint test surface to the single envelope.

### Deliverables

- Every supervised row produces non-optional completion inputs carrying exact
  `PlanId`, completed budget, convergence measurements, dataset-at-read digest,
  initial/final weight hashes, and positive measured update count, paired with
  the exact trained `LayerGraph` (deterministic graph order and parameter
  flattening).
- Partial, synthetic, non-finite, untrained, unchanged-weight, wrong-plan, and
  wrong-dataset training results cannot construct the completion input; no
  constructor mints an admitted artifact or inference eligibility from in-memory
  values (admission is Phase `236`).
- The V2-structure test sites (`test/unit/SupervisedCheckpointV2.hs`,
  `test/unit/SupervisedRuntimeArtifact.hs`, `test/sl-canonicals/Main.hs`,
  `test/integration/Main.hs`) are migrated to the single envelope, the frozen-V1
  byte-freeze golden test is retired, and `cifar10-vit`'s parameter count / slice
  offsets are updated to the IR layout (recorded in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) under this
  sprint).

### Remaining Work

- Produce non-optional completion inputs for the exact Phase `244` run: canonical
  `PlanId`, exact dataset-at-read identity, measured budget/update count, passing
  observations, and exact initial/final JMW1 identities.
- Prove the completed supervised manifest and the model later served describe the
  same trained `LayerGraph` and bytes (envelope construction is Phase `239`;
  admission is Phase `236`).
- Complete the checkpoint test migration and the byte-freeze golden retirement.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-integration --linux-cpu
docker compose run --rm jitml jitml test jitml-sl-canonicals --linux-cpu
docker compose run --rm jitml jitml check-code
```

### Historical Validation (completion-input surface)

`docker compose run --rm jitml jitml test
jitml-integration --linux-cpu` passed 81 / 81 on 2026-07-02, including the
supervised completed-manifest graph/layout/evidence cases and fail-closed
partial/synthetic/untrained/malformed manifest loader cases. `docker compose
run --rm jitml jitml test jitml-sl-canonicals --linux-cpu` passed 31 / 31,
including the live MNIST and all-canonical-row supervised materialization and
training checks. `docker compose run --rm jitml jitml check-code` passed after
formatting the Sprint `24.5` integration test wrapping.

### Retained Closure Boundary

- Phase `24` closes only with each real literal trained architecture and its
  measured, non-forgeable completion inputs. Exact persistence of the current
  Mixer executable does not meet that boundary, and this phase does not own
  persistence or loaded execution.
- The 2026-07-02 and 2026-07-10 checkpoint-reader results exercised the prior
  named-tensor format. They remain historical diagnostics and do not satisfy
  Sprint `10.6`'s V2 one-blob/virtual-slice parity or Sprint `10.12`'s persisted
  proof admission.

2026-07-10 validation showed the widened training path produced completion
values and passed `jitml-negative-controls --linux-cpu` **3 / 3** plus
`jitml-integration` **137 / 137**. Its contemporaneous claim that the stored
manifests were inference eligible is historical only; the current exact
artifact and admission gates are Sprints `10.6` and `10.12`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
