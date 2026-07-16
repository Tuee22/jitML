# Phase 33: Per-Model Convergence & Inference-Performance Tests

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [development_plan_standards.md](development_plan_standards.md), [phase-32-external-truth-realness-harness.md](phase-32-external-truth-realness-harness.md), [phase-34-plan-truth-governance.md](phase-34-plan-truth-governance.md), [../README.md](../README.md), [../documents/engineering/training_metrics_and_splits.md](../documents/engineering/training_metrics_and_splits.md), [../documents/engineering/unit_testing_policy.md](../documents/engineering/unit_testing_policy.md)
**Generated sections**: none

> **Purpose**: Give every product row a model-specific integration test that trains
> the model from a real random initialization and asserts both a **measured**
> convergence metric against its external bar and a **non-wall-clock inference
> performance** metric — so a row is closed by demonstrated learning and inference,
> never by a declared constant or an artifact-read.

## Phase State

⏸️ **Blocked** (reopened 2026-07-12 for Sprint `33.3`). The per-model
suite does not yet consume opaque completed run evidence or structurally
distinguish ordered training iterations from the keyed final evaluation set.
Sprint `33.3` is blocked by Sprint `32.4`. Sprints `33.1`–`33.2` remain Done on
their retained measured-model surface.

**Historical retained closure.** ✅ **Done** (reclosed 2026-07-10). The widened supervised architecture regime,
vectorized RL regime, and row-specific convergence/performance floors are again
covered by the standing per-model measurement suite. The validation run
`docker compose run --rm jitml jitml test jitml-model-convergence --linux-cpu`
passed **111 / 111** after the Phase `24` and Phase `25` remediation, including
one measured convergence case and one non-wall-clock inference-performance case
for every ProductRow. Phase `29` still owns the separate live `linux-cuda`
publisher, integration/e2e, attestation, and wall-clock speedup obligations.

The reopened Phase `28` found that the per-model integration tests were
artifact-readers, not training drivers, and that the "measured" reward was a
scripted expert controller. This phase installs the standing per-model
measurement suite that consumes the Phase `32` external bars and
negative-control primitives. It depends on Phases `24`–`28` (real models) and
Phase `32` (the grader).

**Validation substrate**: `linux-cpu` only.

## Objective

A `jitml-model-convergence` stanza owns one case per `ProductRow`, enumerated from the
registry so coverage cannot silently drop. Each case trains the row's model from a
real random init through the production device seam and asserts: (1) the measured
convergence metric clears the row's external bar (`Phase 32` `ExternalBars`) — median
over `k` seeds for RL, held-out test split for SL, arena win-margin for AlphaZero; and
(2) a non-wall-clock inference-performance metric clears a committed floor (SL
examples/sec throughput; RL sample-efficiency / env-steps-to-threshold), reproduced
bit-identically on a same-seed re-run. Rows whose full literature run is impractical on
`linux-cpu` are typed `Declared` (Phase `32`) until a real run exists — never faked.

## Sprint 33.1: Per-Model Measured Convergence [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Test/RowAssertions.hs`, `test/model-convergence/Main.hs`, `jitml.cabal`
**Docs to update**: `../documents/engineering/training_metrics_and_splits.md`, `../documents/engineering/unit_testing_policy.md`, `system-components.md`

### Objective

Every SL/RL/AlphaZero product row has a case that trains from a real random init and
asserts the measured metric ≥ the external bar, feeding the already-sound
`RowAssertions` helpers with real training output rather than synthetic fixtures.

### Deliverables

- One `jitml-model-convergence` case per `ProductRow`, enumerated from
  `JitML.Product.Matrix.allProductRows`; a missing case fails the coverage assertion.
- SL: train through `JitML.SL.Architecture` on the real staged dataset (held-out test
  split); assert `assertSupervisedRowEvidence` against the measured test metric and a
  real, decreasing loss trajectory.
- RL: train the policy, evaluate the **trained policy** (never the removed expert
  controller), assert `assertRlRowEvidence` with `rleSyntheticTransitionEvidence = False`
  and median-over-`k`-seeds ≥ external bar.
- AlphaZero: real multi-generation self-play + full-`maxPlies` arena; assert
  `assertAlphaZeroRowEvidence` with a strict win-margin.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-model-convergence --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Closure Evidence

- Implemented the row-complete model-convergence stanza; `docker compose run --rm jitml env JITML_SUBSTRATE=linux-cpu cabal test jitml-model-convergence --test-options='--hide-successes --color=never'` passed 111/111 on 2026-07-06.
- Revalidated after the widened architecture/vectorized-RL remediation:
  `docker compose run --rm jitml jitml test jitml-model-convergence --linux-cpu`
  passed **111 / 111** on 2026-07-10.

## Sprint 33.2: Inference-Performance & Determinism [✅ Done]

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

## Sprint 33.3: Contract-Driven Per-Model Evidence [⏸️ Blocked]

**Status**: Blocked
**Implementation**: `src/JitML/Test/RowAssertions.hs`,
`src/JitML/Test/RunContract.hs`, `test/model-convergence/Main.hs`,
`src/JitML/Product/ExternalBars.hs`
**Blocked by**: Sprint `32.4`
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
```

### Remaining Work

- Blocked until Sprint `32.4` establishes the contract's adversarial acceptance
  boundary.
- Migrate all per-model assertions to completed run evidence and separate RL
  learning/evaluation observations.
- Revalidate every ProductRow before returning this phase to Done.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/run_contract.md` — contract-derived per-model
  completion, learning-curve, and final-evaluation evidence.
- `documents/engineering/training_metrics_and_splits.md` — the per-model measured
  convergence + inference-performance contract at the widened + vectorized regime;
  RL reward is a trained-policy rollout, re-measured at the new model sizes.
- `documents/engineering/unit_testing_policy.md` — ownership of the
  `jitml-model-convergence` stanza and its re-clearance obligation across all 55 rows
  at the raised widths / vectorized envs.

**Product docs to create/update:**
- `README.md` — the `Convergence and determinism checks for RL` and
  `Canonical supervised learning problems` sections reference the per-model suite.

**Cross-references to add:**
- Add this phase to `README.md`, `00-overview.md`, `system-components.md`, and
  `development_plan_standards.md §E`.
