# Phase 265: CUDA Row Device Evidence

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: CUDA Row Device Evidence. Single-session phase migrated from legacy Sprint 29.2 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

🔄 **Active** (2026-08-12). Reopened under standards rule `C`. This sprint's evidence is
dated 2026-07-10, three weeks before the 2026-07-30 landing that made the typed
`LayerGraph` the owner of supervised training and pinned that path to the oneDNN
engine. That evidence remains historical evidence for the surface it exercised; it
cannot close the per-row device-witness obligation for the current source, in which
supervised rows on this lane execute oneDNN kernels.

## Sprint 265.1: CUDA Row Device Evidence [🔄 Active]

**Status**: Active
**Implementation**: `src/JitML/Product/Matrix.hs`, `src/JitML/App.hs`, `test/backends/Main.hs`, `test/integration/Main.hs`
**Docs updated**: `../documents/engineering/jit_codegen_architecture.md`, `../documents/engineering/unit_testing_policy.md`

### Objective

Every CUDA-supported product row records real `linux-cuda` device evidence:
runtime probe, generated-source compile/load/launch where applicable, and
substrate-backed learned-state updates through the CUDA device path. Missing
CUDA runtime, driver, or GPU availability fails the lane before row evidence can
be minted.

### Deliverables

- The live CUDA preflight proved Docker exposed the `nvidia` runtime and the RTX
  5090 GPU before any row validation ran.
- All 12 canonical dataset artifacts were uploaded through
  `jitml internal upload-dataset` and SHA-verified against
  `JitML.SL.Dataset.canonicalArtifactSha256For` before supervised rows trained.
- `jitml internal train-and-publish-product-rows --linux-cuda` produced
  inference-eligible artifacts for all **55 / 55** ProductRows on the current
  source after the CUDA publisher memory and convergence calibrations.
- The row-keyed integration matrix consumed the published
  `CompletedTraining` manifests and failed closed before this sprint whenever a
  required product-row checkpoint pointer or live cluster publication was absent.
- The `linux-cpu` and `linux-cuda` MLP training kernels agree **bit-for-bit** on
  the batched parameter gradient for identical inputs. This is the deliverable
  that makes per-row CUDA evidence comparable to the `linux-cpu` lane rather than
  merely present: `src/JitML/Codegen/MlpOneDnn.hs` already declares its reduction
  order matches CUDA's, and `src/JitML/Engines/Engine.hs` already passes
  `--fmad=false` for exactly this reason, so agreement is the stated design and
  divergence is a defect. The activation is aligned so both lanes evaluate `tanh`
  identically, with the `linux-cpu` rendered text left byte-identical because
  Sprint `263.1` pins that artifact's digest on 45 committed rows. A standing
  `jitml-backends --linux-cuda` case asserts the cross-lane bit-identity, since
  the existing per-lane oracle tests compare against the pure reference at
  `1.0e-3` — four orders too loose to observe it.

### Validation

```bash
docker compose run --rm jitml-cuda jitml test jitml-backends --linux-cuda
docker compose run --rm jitml-cuda cabal run -fcuda exe:jitml -- internal train-and-publish-product-rows --linux-cuda
docker compose run --rm jitml-cuda jitml test jitml-integration --linux-cuda
docker compose run --rm jitml jitml test jitml-rl-canonicals --linux-cpu
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

The `jitml-backends --linux-cuda` gate carries the cross-lane bit-identity
assertion for the batched MLP gradient, so it fails closed if the two Linux
lanes drift apart again. `jitml-rl-canonicals --linux-cpu` guards the other
direction: the activation change must not move the `linux-cpu` lane, whose
rendered MLP text stays byte-identical.

2026-07-10 status: Sprint `29.1` is live and passing on the RTX 5090. Focused
current-source CUDA publisher runs validated the missing/failing supervised rows:
`fashion-mnist-resnet` publishes with `test_accuracy=0.826`, and the compact
real-budget rows `cifar10-resnet20`, `cifar10-resnet56`, `cifar10-vit`, and
`tiny-imagenet-resnet50` publish with **4 / 4** eligible. CUDA publisher memory
growth was fixed by evicting cached MLP device weights on allocation pressure and
reusing loaded kernel libraries for the process lifetime; the post-fix narrowed
`PPO/key-door-grid` publisher run passed with `rows: 1`, `eligible: 1`,
`unsupported: 0`, and `errors: 0`. The full current-source CUDA publisher then
passed with `rows: 55`, `eligible: 55`, `unsupported: 0`, and `errors: 0`.
The row-keyed ProductRow integration matrix over the refreshed CUDA checkpoint
pointers passed with **56 / 56** tests using:

```bash
docker compose run --rm jitml-cuda jitml test jitml-integration --linux-cuda --test-options '-p ProductRow --hide-successes --color=never'
```

### Historical Validation

- **Closed Exit-Definition obligation (real per-row CUDA device evidence).** Every
  CUDA-supported product row must record real `linux-cuda` device evidence backed
  by a measured convergence metric that clears an external literature bar, not an
  eligibility flag minted from a tautological gate, an expert-controller reward,
  or a residual-MLP stand-in.
- **Negative-control validation that closes it.** After Phases `19`–`28`
  re-close, re-run
  `docker compose run --rm jitml-cuda jitml internal train-and-publish-product-rows --linux-cuda`
  and gate each row on the
  [`jitml-negative-controls`](README.md#legacy-to-new-phase-map) suite
  (which rejects an under-target run) and the
  [`jitml-model-convergence`](README.md#legacy-to-new-phase-map)
  case that trains the CUDA-supported row from a real random init through the
  production path. Validation stays single accelerator: `linux-cuda` plus
  `linux-cpu`, never `apple-silicon`.

### Remaining Work

- ~~Re-mint per-row CUDA device evidence from an execution witness once Sprints
  `229.1` and `264.1` land, so the recorded engine is the engine that ran.~~
  **Done 2026-08-16.** `LayerGraphDevice.layerGraphDeviceExecutionWitness` mints
  the witness from `layerTrainingBackendSubstrate` — the substrate the executing
  backend *is*, not the substrate that was requested — together with the
  artifact's own content hash and the primitive name read back out of the loaded
  artifact. An admitted row's persisted manifest carries
  `linux-cuda` / `linux-cuda-cudnn` /
  `.build/jit/linux-cuda/4656c4808cb3e2f3927d852598b0dd6a001073fc5e2cabe4b017fe81ea1d139e.so`
  / `cublas_sgemm_forward`, so the recorded engine is the engine that ran.
- ~~Re-run the lane and record the measured result.~~ **Measured 2026-08-16.**
  `cabal run -fcuda exe:jitml -- internal train-and-publish-product-rows
  --linux-cuda`, against a freshly bootstrapped `linux-cuda` cluster (110 steps,
  nine components Ready, edge `9092`) with the twelve canonical dataset objects
  staged, reported `rows: 55`, `eligible: 50`, `unsupported: 0`, `errors: 5`.
  All eleven supervised rows and all four AlphaZero rows admitted, so the
  literal conv / attention / GeGLU architectures both execute and converge to
  bar through the Sprint `264.1` cuBLAS/cuDNN kernels. The retained transcript
  is the gitignored `.build/gate-logs/phase265-cuda-publisher.log`.
- **Five RL rows miss their convergence bars on this lane and the sprint stays
  open until they are resolved.** The measured `median_final_reward` against the
  cohort threshold is:

  | Row | Measured | Threshold | Env steps |
  |-----|----------|-----------|-----------|
  | `PPO/mountain-car` | `-159.0` | `-155.0` | 1,228,800 |
  | `A2C/mountain-car` | `-158.0` | `-155.0` | 1,228,800 |
  | `QR-DQN/mountain-car` | `-161.0` | `-145.0` | 120,000 |
  | `MaskablePPO/key-door-grid` | `-0.64` | `0.85` | 1,228,800 |
  | `CrossQ/lunar-lander` | `72.66` | `160.0` | 50,000 |

  This is not a Sprint `264.1` regression: on the same source
  `jitml test jitml-rl-canonicals --linux-cuda` passes **47 / 47**, including the
  on-device PPO/DQN/QR-DQN/HER/DDPG trainer cases, and
  `jitml test jitml-model-convergence --linux-cuda` passes **111 / 111**.
  Three of the five are `mountain-car`, a sparse-reward exploration-sensitive
  environment where the `linux-cpu` and `linux-cuda` float32 GEMM paths diverge
  into different trajectories.

  The remedy named by Sprint `268.1` — the per-substrate on-policy tuning knob —
  is **not** simply applicable and must not be applied blind. `onPolicyTuning`
  in `src/JitML/RL/TrainerExecution.hs` is deliberately identical across all
  three substrates, and its comment records the reason: a more aggressive
  fewer-epochs / higher-learning-rate CUDA pair previously left PPO and
  MaskablePPO cartpole stuck at ~210. Re-diverging it would reintroduce a known
  failure to fix a different one. It also cannot cover `QR-DQN/mountain-car` or
  `CrossQ/lunar-lander`, which are off-policy trainers the on-policy knob does
  not reach. The shared `cohortThresholds` table stays untouched: it is
  documented as substrate-invariant and fenced by the frozen external-bar set,
  so lowering a bar to admit a row is excluded.

  Closing this sprint therefore requires real per-trainer convergence work on
  the `linux-cuda` lane for these five rows, not a knob change.

- **Align the two lanes' activation so their gradients agree bit-for-bit.** This
  is an owned deliverable of this sprint, not a deferred observation.
  `src/JitML/Codegen/MlpOneDnn.hs` states its parameter-gradient loop "matches
  the CUDA batch-grad reduction order: batch index b ascending", and
  `src/JitML/Engines/Engine.hs` passes `--fmad=false` specifically so the lanes
  agree, recording that with FMA contraction "that sub-ULP skew amplifies into
  materially different convergence". Measured at batch 256 / hidden 256 against a
  float64 pure oracle, both lanes carry the *same* relative error (`4.19e-7`,
  ≈3.5× fp32 epsilon) yet differ from each other by `9.54e-7` absolute. The
  accumulation loops are equivalent; the activation is not — `MlpOneDnn.hs`
  emits `std::tanh` and `src/JitML/Codegen/MlpCuda.hs` emits `tanhf`, two
  implementations of one function. The alignment changes only
  `src/JitML/Codegen/MlpCuda.hs`, leaving the `linux-cpu` rendered text
  byte-identical because Sprint `263.1` pins that artifact's digest on 45 of the
  55 committed rows, and lands with the standing cross-lane bit-identity case
  named in `### Deliverables`. Whether it moves the five rows onto their bars is
  a measurement this sprint takes, not an assumption it makes.
- **`median_final_reward` grades a policy that was never executed at that
  precision.** Twelve of the thirteen MLP-backed trainers evaluate through the
  pure host `Double` path while training through the device `float` path; DQN
  alone evaluates on device. The asymmetry is identical on every substrate, so
  it is not the cause of the lane gap, but it means the reported metric is not a
  rollout of the policy as executed.

### Historical Phase State

> ✅ **Done**.

*(Retained as historical evidence for the surface it exercised; superseded by the 2026-08-12 reopen above.)*

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
