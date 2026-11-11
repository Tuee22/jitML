# Phase 115: Real Hyperparameter Tuning Objective Executor

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Real Hyperparameter Tuning Objective Executor. Originally migrated from legacy Sprint 9.11 in the 2026-07-24 phase renumber; see the old→new map in [README.md](README.md).

## Phase State

⏸️ **Blocked** for the expanded validation foundation in Sprint `115.2`.
The earlier Sprint `115.1` record below is retained on its original source and
scope; it does not validate this target or a current hardware lane. The execution
order and transition authority are [the validation-foundation refactor](README.md#validation-foundation-refactor).

The new source/catalogue, runner and hardware controls remain unimplemented.
Sprint `221.2` owns reconciliation of the existing checker with these documented
targets; this documentation-only change supplies no machine-validation receipt.

## Sprint 115.2: Bounded tuning readiness and allocation regressions [⏸️ Blocked]

**Status**: Blocked
**Implementation**: Target changes to `src/JitML/Tune/Catalog.hs`, `src/JitML/SL/Architecture.hs`, `test/hyperparameter/Main.hs`.
**Blocked by**: Sprint `160.2`, Sprint `225.2`.
**Docs to update**: `../documents/engineering/execution_resources.md`, `../documents/engineering/validation_execution.md`, `../documents/engineering/training_workloads.md`, `../documents/engineering/training_metrics_and_splits.md`, `README.md`, `system-components.md`, `legacy-tracking-for-deletion.md`.

### Objective

Tuning uses measured bounded allocation and concurrency with unchanged objective semantics, and current-source targeted readiness precedes lane qualification.

The target contracts are [execution resources](../documents/engineering/execution_resources.md)
and [validation execution](../documents/engineering/validation_execution.md).
Their acceptance requirements below are planned work, not implemented behavior.

### Deliverables

- Prove the feature-materialization and held-out representation corrections on the current candidate; the earlier eligible row is scoped readiness, not final-source qualification.
- Bound trial concurrency by the admitted resource policy and effective runtime capability. Count pending/training/evaluation/publication memory together instead of using one trial heap as an aggregate ceiling.
- Retain objective, candidate order, trial budget, seeds and artifact identity comparisons where bit-identical behavior is required. Operational fixes cannot alter measured objective provenance silently.
- Use the prospective criterion policy owned by `278.2`; diagnostic review copies remain non-authoritative, and final independent source review is required only before qualifying execution.

### Validation

1. Target the feature-materialization/concurrency regression first; record live residency, fragmentation, aggregate peak, actual concurrency and unchanged output semantics.
2. Run the single tuning row under the intended gate envelope and deadline with complete outcome/capture; rerun affected supervised paths only when impact is named.
3. Run the full hyperparameter stanza after its individual controls pass. Qualification and fragment publication remain owned by the lane/campaign phases.

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

- Confirm current-source tuning memory fit and objective behavior through the supported bounded runner.
- Record change impact and fix any regressions before the frozen lane candidate; no larger heap or changed numerical work is adopted without a prospective policy decision.

## Retained Historical Scope

The following state, commands, measurements and closure statements describe the
original Sprint `115.1` surface only. New execution rules and acceptance
above supersede any conflicting operational instruction; old receipts are not
reinterpreted as current readiness.

### Historical Phase State

✅ **Done**.

## Sprint 115.1: Real Hyperparameter Tuning Objective Executor [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Tune/Catalog.hs` (`deterministicTrials`,
`deterministicTrialsWithDevice` → `Tune.Trial` executor),
`src/JitML/Tune/Resume.hs` (`resumeMatchesFullRun`), `src/JitML/App.hs`
(`publishWorkerTuneEvent`, `measureTuneBestObjective`)
**Docs to update**: `../documents/engineering/training_workloads.md`, `system-components.md`

### Objective

Replace the per-sampler LCG `deterministicTrials` with a real trial executor
that, for each sampled hyperparameter configuration, trains the substrate-backed
model and measures the real objective, and replace the `resumeMatchesFullRun`
tautology with a genuine resume-equality check. Owns the tuning slice of
[Exit Definition](README.md#exit-definition) item 6.

### Deliverables

- A `Tune.Trial` executor maps each sampled config (sampler × scheduler × pruner)
  to a real measured objective by training the substrate-backed model
  (`trainClassifierWithDevice` / the RL device trainers) over a bounded budget;
  no LCG-derived trial value remains.
- `resumeMatchesFullRun` compares a resumed sweep's trial objectives against the
  full-run objectives bit-for-bit (within-substrate determinism), not a
  structural tautology.
- The `jitml tune` summary and tuning transcript/report-card surfaces read the
  real measured objective; the old `inspect trial` / `inspect frontier`
  placeholders were retired by Phase `1` Sprint `1.16`.

### Validation

- `docker compose run --rm jitml jitml test jitml-hyperparameter --linux-cpu`
  (real measured objective; live half in Sprint 15.17 / 15.10).
- `jitml check-code` + `jitml docs check` green inside `jitml:local`.

### Current Validation State

Landed and validated (2026-06-10):

- `Tune.deterministicTrials` now returns __real measured objectives__:
  each trial samples a hyperparameter configuration, trains the reference
  classifier on a fixed separable dataset, and returns train accuracy in
  `[0, 1]`, matching the worked example's `valAcc:Maximise` direction. No
  LCG-derived trial value remains.
- `Tune.deterministicTrialsWithDevice` executes the same deterministic sampler
  stream through `Classifier.trainClassifierWithDevice`; the live worker path
  (`publishWorkerTuneEvent`) uses that substrate-selected JIT device and aborts
  on device failure, while `measureTuneBestObjective` reports unavailable rather
  than falling back when no live publication/device is usable.
- Sprint `9.12` extends the measured trial result with checkpointable trained
  weights. `jitml tune` writes the best local trial as a `.jmw1` checkpoint and
  a line-oriented `tune-trials` artifact; daemon-dispatched tune workers also
  promote each measured trial into the `jitml-checkpoints` bucket while keeping
  the `jitml-trials` transcript.
- Host: `jitml-hyperparameter` 14/14 (distinct per-sampler real objectives,
  values normalised, resume determinism), `jitml-unit` 196/196. Container:
  `check-code: ok`, `jitml test jitml-hyperparameter --linux-cpu` **14/14** and
  `jitml test jitml-hyperparameter --linux-cuda` **14/14** on 2026-06-11. Live
  tune trial persist/replay and daemon `StartSweep` dispatch passed in both
  linux-cpu and linux-cuda full integration suites (**67/67** each).
- Continuation validation (2026-06-11): `docker compose run --rm jitml jitml
  test jitml-hyperparameter --linux-cpu` → **15/15 PASS**, including
  `device-backed trial executor is deterministic through the substrate JIT
  device (Sprint 9.11 --linux-cpu): OK (0.12s)`.

### Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**

- `../documents/engineering/execution_resources.md`.
- `../documents/engineering/validation_execution.md`.
- `../documents/engineering/training_workloads.md`.
- `../documents/engineering/training_metrics_and_splits.md`.

**Product docs to create/update:**

- [Development-plan entry](README.md#validation-foundation-refactor), [component inventory](system-components.md), and [deletion ledger](legacy-tracking-for-deletion.md).

**Cross-references to add:**

- Link the target contracts, exact sprint dependencies and evidence pointers together when source implementation lands; update root summaries only in an authorized root-file change.
