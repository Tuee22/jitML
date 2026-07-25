# Phase 241: CompletedTraining SL Manifests

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: CompletedTraining SL Manifests. Single-session phase migrated from legacy Sprint 24.5 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

⏸️ **Blocked**. Blocked by Phase 240 (Sprint 240.1).

## Sprint 241.1: CompletedTraining SL Manifests [⏸️ Blocked]

**Status**: Blocked
**Implementation**: `src/JitML/SL/{Architecture,TrainingExecution}.hs`,
`src/JitML/Product/Completion.hs`, `test/sl-canonicals/Main.hs`
**Blocked by**: Sprint `240.1`
**Docs to update**: `../documents/engineering/training_workloads.md`,
`../documents/engineering/training_metrics_and_splits.md`

### Objective

Every supervised row hands the checkpoint boundary its exact executed graph,
initial and final flat weights, verified dataset-at-read digest, measured update
count, exact plan identity/budget, and passing convergence observations. This
sprint owns production of those training/completion inputs. Sprint `127.1` owns
their exact V2 persistence and trained-versus-loaded parity; Sprint `133.1`
alone admits a persisted artifact as inference eligible.

### Deliverables

- Every supervised row produces non-optional completion inputs carrying exact
  `PlanId`, completed budget, convergence measurements, dataset-at-read digest,
  initial/final weight hashes, and positive measured update count.
- The architecture value paired with those inputs is the graph actually
  executed by training, with deterministic graph order and parameter flattening
  suitable for Sprint `127.1`'s virtual `Flat` slices.
- Partial, synthetic, non-finite, untrained, unchanged-weight, wrong-plan, and
  wrong-dataset training results cannot construct the completion input.
- No Phase `237` constructor mints structural checkpoint completion, an admitted
  artifact, or inference eligibility from those in-memory values.

### Remaining Work

- Produce non-optional completion inputs for the exact Sprint `240.1` run:
  canonical `PlanId`, exact dataset-at-read identity, measured budget/update
  count, passing observations, and exact initial/final JMW1 identities.
- Prove the completed supervised manifest and the model later served describe
  the same literal graph and bytes. V2 encoding remains Sprint `127.1`, and only
  Sprint `133.1` may admit persisted eligibility.

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
