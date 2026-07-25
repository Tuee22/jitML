# Phase 98: SL Substrate-Backed Training + Real Eval

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: SL Substrate-Backed Training + Real Eval. Single-session phase migrated from legacy Sprint 8.10 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 98.1: SL Substrate-Backed Training + Real Eval [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/SL/Classifier.hs`, `src/JitML/Numerics/MlpDevice.hs`, `src/JitML/App.hs` (`runTrain`, `runEval`), `src/JitML/SL/Canonicals.hs`, `src/JitML/SL/ConvergenceThresholds.hs`, `src/JitML/AppError/AppError.hs`
**Docs to update**: `../documents/engineering/training_workloads.md`, `../documents/engineering/checkpoint_format.md`, `system-components.md`

### Objective

Make `jitml train` and `jitml eval` exercise a real, substrate-backed model on the
resolved `--substrate`, with **no synthetic or pure-Haskell fallback on any runtime
path**. Owns the [Exit Definition](README.md#exit-definition) item 6 SL slice for
the canonical Dense-MLP cohort and item 7 inference-read slice (`runEval`).

### Deliverables

- `mlpDeviceForSubstrate :: Substrate -> Env -> MlpDevice` selecting
  `oneDnnMlpDevice` / `cudaMlpDevice` / `metalMlpDevice` for `LinuxCPU` /
  `LinuxCUDA` / `AppleSilicon` (in `JitML.Numerics.MlpDevice`, or a small
  `MlpDeviceSelect` module if an import cycle arises).
- A device-backed classifier trainer in `JitML.SL.Classifier` mirroring
  `trainPolicyValueNetOnSamplesWithDevice` — batched `mlpdForwardBatch` /
  `mlpdBatchGradient`, host-side softmax-cross-entropy head + Adam — returning
  `IO (Either Text (TrainedClassifier, Double))`; a `Left` propagates as a hard
  error (no pure fallback).
- `runTrain` resolves the substrate (reusing the `workerBrokerTarget` resolution),
  **requires** a live publication and a staged dataset, and otherwise
  `exitWithError (TrainingPrerequisiteUnmet …)` — nothing printed or published on
  failure; only the measured loss is published via `publishWorkerTrainingEvent`.
- `runEval` loads the `.jmw1` weight blob and computes a real held-out
  accuracy/loss through the device forward; missing checkpoint/test bytes →
  `InferenceCheckpointMissing`.
- `canonicalProblems` + `ConvergenceThresholds` scoped to the Dense-MLP cohort the
  JIT codegen trains; new `AppError` variants added to the single ADT and
  registered in `system-components.md`. Non-Dense canonical rows remain catalog
  entries for future trainable-architecture expansion, not the current closure
  gate.

### Validation

- `docker compose run --rm jitml jitml test jitml-sl-canonicals --linux-cpu`
  (device-backed convergence; live half in Sprint 15.17).
- Offline `jitml train` → typed error, exit 2, no number printed/published.
- `jitml check-code` + `jitml docs check` green inside `jitml:local`.

### Current Validation State

Host (`ghc-9.12.4`, no oneDNN/Metal toolchain) — landed and green:

- `JitML.SL.Classifier.trainClassifierWithDevice` /
  `trainClassifierWithDeviceFromIdxBounded` / `classifyWithDevice` /
  `accuracyWithDevice` route the softmax cross-entropy classifier through the
  injected `MlpDevice` (batched device forward + batched device gradient +
  host Adam), failing closed on a device `Left` — no pure-Haskell fallback.
- `runTrain` is fail-closed: `runDeviceMnistTraining` requires a live cluster
  publication and a staged dataset, otherwise `exitWithError
  (TrainingPrerequisiteUnmet …)` with nothing printed or published. The
  synthetic `train:`/`final_loss:` summary print is removed.
- `runEval` loads the named inference checkpoint and runs the substrate-bound
  weighted device forward; a missing pointer/manifest → `InferenceCheckpointMissing`.
- `AppError` gains `TrainingPrerequisiteUnmet Text` (exit 2) with its
  `renderError` line; registered in `system-components.md`.
- `JitML.SL.Canonicals.denseMlpCohort` / `isDenseMlpProblem` name the
  device-trainable single-hidden-layer Dense subset
  (`mnist-shallow-mlp`, `fashion-mnist-mlp`, `california-housing-mlp`).
- The residual synthetic `convergenceCurve` / `finalLoss` symbols and the
  `SL.Loop` / `SL.Train` deterministic-curve pipeline were deleted on
  2026-06-11; the ledger rows moved to `Completed`.
- `jitml-unit` (196/196, before the 2026-06-11 residual-source deletion),
  `jitml-sl-canonicals` (host device case skips when the probe reports no
  device), and `jitml-integration` Subprocess offline-`jitml train`
  fail-closed assertion pass on the host.

Container (`jitml:local`, oneDNN present) — boundary gate **passed**:

- `docker compose build jitml` built `jitml:local` with `check-code: ok`.
- `docker compose run --rm jitml jitml test jitml-sl-canonicals --linux-cpu`
  → **15/15 PASS** on 2026-06-11, including `SL classifier converges through
  the substrate JIT device (Sprint 8.10 --linux-cpu): OK (0.75s)` — the case ran the real
  generated oneDNN MLP kernel (compile + batched forward/gradient + Adam to
  convergence) instead of skipping.
- `docker compose run --rm jitml-cuda jitml test jitml-sl-canonicals
  --linux-cuda` → **15/15 PASS** on 2026-06-11 against the RTX 5090 CUDA lane.
- Live linux-cpu and linux-cuda workflow exercise closed in Phase `15` on
  2026-06-11: both lanes bootstrapped clean data and passed full live
  `jitml-integration` **67/67** plus `jitml-e2e` **20/20**.
- Continuation audit (2026-06-11): `docker compose run --rm jitml jitml test
  jitml-sl-canonicals --linux-cpu` revalidated the then-current Dense-MLP surface
  (**15/15 PASS**, including the device-backed classifier convergence case).
  Latest rerun: the device case reported
  `SL classifier converges through the substrate JIT device (Sprint 8.10
  --linux-cpu): OK (1.22s)`.
  This closes Sprint `8.10` against the current Exit Definition item 6 Dense-MLP
  scope. The repository still has no trainable non-Dense SL ABI: the available
  classifier path is the two-layer `MlpDevice` forward/batch-gradient ABI, while
  Conv2D / residual / ViT catalog rows need architecture-specific parameter
  layouts plus backward JIT kernels before they can become trainable follow-on
  cohorts.
- Code-boundary audit (2026-06-11): `JitML.Numerics.MlpDevice` exposes only the
  `jitml_mlp_*` two-layer MLP ABI, `JitML.SL.Classifier` trains only
  `MlpParams`, and `JitML.SL.Canonicals.denseMlpCohort` still filters by
  `problemModel == "Dense"`. The existing weighted Conv2D / BatchNorm /
  LayerNorm / MHA / Embedding codegen in `JitML.Codegen.{OneDnn,Cuda,Metal}`
  is forward/kernel-family coverage, not the supervised trainable-architecture
  backward ABI required to promote the non-Dense canonical rows.

### Remaining Work

None.

### Follow-on Scope

Historical note: this follow-on scope was superseded on 2026-06-14. Conv2D /
ResidualBlock / VisionTransformer forward+backward JIT codegen and backward
kernels are now part of Sprint `8.12` / Phase `13` no-caveat product closure,
not non-blocking future growth.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
