# Phase 99: RL Framework Substrate Routing

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: RL Framework Substrate Routing. Single-session phase migrated from legacy Sprint 8.11 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 99.1: RL Framework Substrate Routing [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/App.hs` (`runTrainerEpisodes`, `runRl`), `src/JitML/Numerics/MlpDevice.hs`, `src/JitML/RL/SimulatorLoop.hs`
**Docs to update**: `../documents/engineering/training_workloads.md`, `system-components.md`

### Objective

Route every MLP-backed RL trainer through the substrate engine selected by
`--substrate`, and remove the scripted non-learning default. Owns the
[Exit Definition](README.md#exit-definition) item 6 RL slice.

### Deliverables

- `rlDeviceForSubstrate :: Substrate -> Env -> MlpDevice` — one DRY seam for the 13
  MLP-backed algorithms; **ARS is the lone no-MLP exception**, stated once here and
  in `system-components.md`.
- `runTrainerEpisodes` dispatches each named trainer to its `*OnDevice` variant via
  the seam; iteration budgets raised so training actually learns (replacing
  `ppoNumIterations = max 1 evalEpisodes`).
- The `"simulator"` scripted default is removed; an unknown trainer →
  `InvalidConfig`, never a scripted fallback.

### Validation

- `docker compose run --rm jitml jitml test jitml-rl-canonicals --linux-cpu`
  (on-device reward improvement; live half in Sprint 15.17).
- Unknown `JITML_RL_TRAINER` → typed `InvalidConfig`, no episodes published.

### Current Validation State

Host (`ghc-9.12.4`, no oneDNN/Metal toolchain) — landed and green:

- `JitML.Numerics.MlpDeviceSelect.rlDeviceForSubstrate` is the single DRY seam
  for the 13 MLP-backed algorithms; ARS is the lone no-MLP exception, stated
  here and in `system-components.md`.
- `runTrainerEpisodes` takes the resolved `MlpDevice`, probes it once
  (`probeMlpDevice` — a 1×1×1 JIT forward) and **fails closed** when the
  substrate toolchain/hardware is absent, then dispatches each trainer to its
  `*OnDevice` variant. Iteration budgets are raised from the old
  `max 1 evalEpisodes` floor (PPO `max 50 evalEpisodes`, value-based / continuous
  `max 20000 (evalEpisodes × maxSteps)`, ARS `max 50 evalEpisodes`, HER
  `max 200 (evalEpisodes × 20)`) so training actually learns.
- The `"simulator"` scripted default is gone: `runRl` defaults the trainer to
  `ppo`, and an unknown trainer → `runTrainerEpisodes` returns `Left` →
  `runRl` `exitWithError (InvalidConfig …)`; nothing is published.
- `jitml-rl-canonicals` (27/27) passes on the host, including the new
  on-device PPO reward-improvement case, which skips when the device probe
  reports no toolchain.

Container (`jitml:local`, oneDNN present) — boundary gate **passed**:
`docker compose run --rm jitml jitml test jitml-rl-canonicals --linux-cpu`
→ **27/27 PASS** on 2026-06-11, including `PPO trains and improves on cartpole
through the substrate JIT device (Sprint 8.11 --linux-cpu): OK (0.75s)` — the case ran the
real generated oneDNN MLP kernel through `trainOnPolicyOnDevice` instead of
skipping. `check-code: ok` in the same image. The CUDA lane also passed
`docker compose run --rm jitml-cuda jitml test jitml-rl-canonicals
--linux-cuda` **27/27** on 2026-06-11. Live PPO convergence is stable on both
Linux substrates with substrate-specific tuning: `linux-cpu` uses 10 PPO epochs
per update at `5.0e-4`, while `linux-cuda` uses 8 epochs at `7.0e-4`; focused
and full live integration passed on both lanes.

### Remaining Work

- None on the owned RL-routing surface. The per-trainer internal device updates
  (`dqnUpdateDevice` and the `QrDqnTrainer` / `ContinuousTrainer` / `HerTrainer`
  peers) now **fail closed** on a mid-run device `Left` through typed trainer
  failures (no pure-Haskell fallback; completed by Sprint `8.15`). The live
  `--linux-cpu` / `--apple-silicon` on-device reward exercise is owned by
  Phases `15`/`16`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
