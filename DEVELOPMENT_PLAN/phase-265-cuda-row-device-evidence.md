# Phase 265: CUDA Row Device Evidence

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: CUDA Row Device Evidence. Single-session phase migrated from legacy Sprint 29.2 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done** (re-closed 2026-08-18). Every CUDA-supported product row records real
`linux-cuda` device evidence on the current source. The measured lane run
reported **`rows: 55`, `eligible: 55`, `unsupported: 0`, `errors: 0`**, with
**55** admitted inventory entries — so all 55 rows, including the five RL rows
that missed their cohort bars on the pre-alignment source, publish
inference-eligible artifacts. The publisher enforces each row's convergence bar
itself: a row that misses becomes an `error`, which is exactly how those five
surfaced on 2026-08-16, so `errors: 0` is the bars being met rather than
unchecked.

The one defect that separated the lanes is closed: the two Linux lanes' batched
MLP parameter gradients now agree **bit for bit**, because the activation is
rendered from glibc's own flt-32 algorithm rather than CUDA's `tanhf`. The
`cohortThresholds` table is untouched, and the per-substrate on-policy tuning
knob was not diverged — it was collapsed to one substrate-independent constant.

The 2026-08-12 reopen is discharged: the recorded engine is now the engine that
ran, minted from an execution witness rather than composed from the declared
substrate and claim.

One case in this sprint's `jitml test jitml-integration --linux-cuda` command is
red and is deliberately left so: the committed `linux-cuda` attestation still
carries pre-`229.1` declaration-derived cells with no artifact digest, which no
source state can satisfy. It is [Phase 268](phase-268-contract-driven-cuda-lane-revalidation.md)'s
deliverable to replace, mintable only from the report-card `--live` path that
[Phase 266](phase-266-cuda-integration-e2e-and-attestation.md) runs, and
hand-editing the cells is what the gate exists to reject. See
[Landed Evidence](#landed-evidence-2026-08-17).

## Sprint 265.1: CUDA Row Device Evidence [✅ Done]

**Status**: Done
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

- None.

### Resolved Work

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
- ~~Re-run the lane and record the measured result.~~ **Superseded baseline,
  measured 2026-08-16** (pre-alignment; the closing measurement is the
  2026-08-17 run below).
  `cabal run -fcuda exe:jitml -- internal train-and-publish-product-rows
  --linux-cuda`, against a freshly bootstrapped `linux-cuda` cluster (110 steps,
  nine components Ready, edge `9092`) with the twelve canonical dataset objects
  staged, reported `rows: 55`, `eligible: 50`, `unsupported: 0`, `errors: 5`.
  All eleven supervised rows and all four AlphaZero rows admitted, so the
  literal conv / attention / GeGLU architectures both execute and converge to
  bar through the Sprint `264.1` cuBLAS/cuDNN kernels. The retained transcript
  is the gitignored `.build/gate-logs/phase265-cuda-publisher.log`.
- **Five RL rows missed their convergence bars on the pre-alignment source.**
  Measured 2026-08-16, before the activation alignment above; retained as the
  baseline the re-run is compared against. The measured `median_final_reward`
  against the cohort threshold was:

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
  is **not** applicable and was not applied. `onPolicyTuning` in
  `src/JitML/RL/TrainerExecution.hs` was deliberately identical across all three
  substrates, and its comment recorded the reason: a more aggressive
  fewer-epochs / higher-learning-rate CUDA pair previously left PPO and
  MaskablePPO cartpole stuck at ~210. Re-diverging it would reintroduce a known
  failure to fix a different one. It also cannot cover `QR-DQN/mountain-car` or
  `CrossQ/lunar-lander`, which are off-policy trainers the on-policy knob does
  not reach. This sprint went the other way and **collapsed** the three-arm
  fan-out to one substrate-independent constant, so diverging an RL
  hyperparameter per lane now means deliberately replacing that constant. The
  shared `cohortThresholds` table is untouched: it is documented as
  substrate-invariant and fenced by the frozen external-bar set, so lowering a
  bar to admit a row was excluded.

  The diagnosis instead points at one mechanism rather than five independent
  tuning problems: three of the five rows are `mountain-car`, a sparse-reward
  exploration-sensitive environment, and the two Linux lanes were executing
  different arithmetic. With the MLP kernels now bit-identical and the rest of
  each trainer running in host `Double`, the CUDA trajectory should reproduce
  the `linux-cpu` one, which admits all 55 rows. The 2026-08-17 re-run below
  confirms it: all five rows admit, with no threshold moved and no
  per-substrate hyperparameter introduced.

- ~~**Align the two lanes' activation so their gradients agree bit-for-bit.**~~
  **Done 2026-08-17.** The lanes disagreed only in the activation: `MlpOneDnn.hs`
  emits `std::tanh`, which on a `float` argument is glibc's
  `sysdeps/ieee754/flt-32` `tanhf`, while `src/JitML/Codegen/MlpCuda.hs` emitted
  CUDA's libdevice `tanhf`. Every element-wise accumulation order already
  matched — `gW2[k][i]`, `gB1[i]`, `gW1[i][j]` and the inner `d_act` reduction
  all sum the same index ascending from the same `0.0f`, and both lanes spell
  the derivative `d_act * (1.0f - h * h)` — so the activation was the whole gap.

  Matching glibc's *output* is not achievable: glibc's `tanhf` is **not**
  correctly rounded, differing from a correctly-rounded reference on
  `118,674,314` of `4,278,190,080` floats, and on `44.4%` of those in
  `[0.1, 1]`. `MlpCuda.hs` therefore renders glibc's own algorithm — the
  `expm1f`-based reduction with its `Q1..Q5` coefficients — as CUDA device
  functions behind `mlpCudaActivation`. Because nvcc is given no fast-math
  argument, `--fmad=false`, and default correctly-rounded division, each device
  float operation rounds exactly as the host's does, so an identical operation
  sequence yields an identical float.

  Verified exhaustively over every finite float, twice: in pure C under
  `-ffp-contract=off`, and on the RTX 5090 under this lane's own compile
  arguments (`-arch=sm_70 --fmad=false`) — **0 mismatches out of
  4,278,190,080**, against `129,743,420` (3.03%, worst `1.79e-7` absolute) for
  CUDA's native `tanhf`. Only `MlpCuda.hs` moved, so the `linux-cpu` rendered
  text stays byte-identical and the digests Sprint `263.1` pinned on 45 of the
  55 committed rows are unmoved.

  The standing case named in `### Deliverables` is live:
  `jitml-backends --linux-cuda` asserts all four batched parameter gradients are
  exactly equal across the lanes (`@?=`, not tolerance) over a 32 x 64 = 2048
  activation shape, and a source guard rejects any call site that reverts to
  CUDA's `tanhf`. Both were negative-controlled: reverting the two call sites
  makes the bit-identity case **FAIL**, so it is not vacuous.

- ~~**Re-run the CUDA lane and record the measured result.**~~ **Measured
  2026-08-17.** `cabal run -fcuda exe:jitml -- internal
  train-and-publish-product-rows --linux-cuda`, against a freshly bootstrapped
  `linux-cuda` cluster (nine components Ready, edge `9092`, evidence
  `live-readiness`) with the twelve canonical dataset objects staged and
  SHA-verified on upload, reported **`rows: 55`, `eligible: 55`,
  `unsupported: 0`, `errors: 0`**, `admitted-inventory-entries: 55`. The run took
  ~6 h single-threaded on the RTX 5090.

  All five rows that missed their bars on the pre-alignment source
  (`PPO/mountain-car`, `A2C/mountain-car`, `QR-DQN/mountain-car`,
  `MaskablePPO/key-door-grid`, `CrossQ/lunar-lander`) now admit. The publisher
  gates each row on its cohort threshold and turns a miss into an `error` — the
  exact mechanism that produced `errors: 5` on 2026-08-16 — so `errors: 0` is
  those bars being met, not skipped. No threshold moved and no per-substrate
  hyperparameter was introduced; the only change between the two runs on the RL
  path is that the lanes' MLP kernels became bit-identical.

  The retained transcript is the gitignored
  `.build/gate-logs/phase265-cuda-publisher-aligned.log`, SHA-256
  `0eb9fa3e340e22608082aa24a0e99db38a62af6bfbe3912339538ff908094352`.
- **`median_final_reward` grades a policy that was never executed at that
  precision.** Twelve of the thirteen MLP-backed trainers evaluate through the
  pure host `Double` path while training through the device `float` path; DQN
  alone evaluates on device. The asymmetry is identical on every substrate, so
  it is not the cause of the lane gap, but it means the reported metric is not a
  rollout of the policy as executed.

### Landed Evidence (2026-08-17)

The closing lane measurement, on a live `linux-cuda` cluster with the RTX 5090
attached and the twelve canonical datasets staged:

- `cabal run -fcuda exe:jitml -- internal train-and-publish-product-rows
  --linux-cuda` → **`rows: 55`, `eligible: 55`, `unsupported: 0`, `errors: 0`**,
  `admitted-inventory-entries: 55`, `tune-trials-v2-transcripts: 1`. Transcript
  `.build/gate-logs/phase265-cuda-publisher-aligned.log`, SHA-256
  `0eb9fa3e340e22608082aa24a0e99db38a62af6bfbe3912339538ff908094352`.
- `jitml cluster status` → nine components ready on `linux-cuda`, edge
  `127.0.0.1:9092`, evidence `live-readiness`.
- All twelve canonical dataset artifacts staged through
  `jitml internal upload-dataset`, each SHA-256-verified against
  `JitML.SL.Dataset.canonicalArtifactSha256For` on upload.

The closure gate, from one source state (integration on the live CUDA lane, the
rest inside `jitml:local`):

- `jitml test jitml-integration --linux-cuda -p ProductRow` → **71 / 72**, 6 h13 m.
  Every ProductRow case passes: all 55 rows retrain from scratch through the
  production path (`ProductScenarioInvocation` disables checkpoint reuse, so the
  gate cannot inherit the publisher's work) and the matrix consumes the published
  `CompletedTraining` manifests.
- `jitml lint haskell` → `ok`; `jitml docs check` → `ok`;
  `jitml test jitml-unit --linux-cpu` → **897 / 897**; `jitml check-code` → `ok`.

**The one failing case is not this sprint's obligation and predates its work.**
`Phase 263 issues the committed lane fragment from the completed scenario
journal` reports that `attestations/linux-cuda-report-card.md` is not the
fragment this lane issues. The committed cells are
`device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:<claim>` — three *declared* tokens
carrying **no artifact digest at all**, identical across every row of a class.
That is the shape `productRowDeviceEvidenceForSubstrate` produced, the
declaration-derived composer Sprint `229.1` deleted because it "performed no
execution, could not fail". The `linux-cpu` card was re-issued from execution
witnesses on 2026-08-15 and carries real digests; the `linux-cuda` card never
was. It would therefore fail this check against any source state, including a
no-op commit — this sprint moved the digests, it did not create the mismatch.

Re-issuing it is [Phase 268](phase-268-contract-driven-cuda-lane-revalidation.md)'s
stated deliverable ("Replace the committed `linux-cuda` fragment only after all
scenarios complete; retain explicit failed/not-run entries rather than
fabricating pass cells"), and the fragment can only be minted from the
report-card `--live` path's `product_lane_fragment:` block, which
[Phase 266](phase-266-cuda-integration-e2e-and-attestation.md) runs. Editing the
cells by hand is exactly what this gate exists to reject, so it is left red here
and closed there.

The cross-lane deliverable and the sprint's three legacy-ledger rows are landed
and gated from one source state, inside `jitml:local`:

- `jitml lint haskell` → `ok`.
- `jitml docs check` → `ok`.
- `jitml test jitml-unit --linux-cpu` → **897 / 897 passed**, including the
  fifteen-case "Derived toolchain fingerprints (Phase 78)" group with the new
  *only the programs that call cuBLAS/cuDNN link them* case.
- `jitml test jitml-backends --linux-cpu` → **36 / 36 passed**.
- `jitml test jitml-backends --linux-cuda` → **27 / 27 passed** on the RTX 5090,
  including *linux-cuda batched MLP gradient is bit-identical to the oneDNN lane
  (Phase 265)* and its source guard.
- `jitml test jitml-rl-canonicals --linux-cpu` → **47 / 47 passed**, so the
  `linux-cpu` lane is unmoved by the alignment, as required — its rendered
  `kernel.cc` text is byte-identical.
- `jitml check-code` → `ok`.

Negative control: reverting the two `MlpCuda.hs` activation call sites to CUDA's
`tanhf` makes the bit-identity case **fail**, so the assertion is discriminating
rather than vacuous.

Every `linux-cuda` MLP cache key changes with this landing, by design: the
rendered source and the artifact's link line both move, so the lane recompiles
its MLP kernel once and that artifact's `DeviceEvidence` digest changes. The
`linux-cpu` lane's rendered text and digests are unmoved.

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
