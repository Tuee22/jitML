# Phase 113: Real `rl eval` / `rollout` and Per-Algorithm On-Device Rollouts

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Real rl eval / rollout and Per-Algorithm On-Device Rollouts. Single-session phase migrated from legacy Sprint 9.9 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 113.1: Real `rl eval` / `rollout` and Per-Algorithm On-Device Rollouts [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/App.hs` (`runCheckpointEval`, `runRl ["rl","eval"]`,
`runRl ["rl","rollout"]`, `runDeviceRollout`),
`src/JitML/RL/Algorithms/*.hs` (`moduleRolloutGenerator`)
**Docs to update**: `../documents/engineering/training_workloads.md`, `system-components.md`

### Objective

Make `jitml rl eval` and `jitml rl rollout` exercise the real substrate JIT
engine — load a real checkpoint and run a real device rollout — with **no echo
stub and no LCG `deterministicTrajectory`**, and replace the shared
`moduleRolloutGenerator` stub so each algorithm's rollout runs its real trained
policy on-device. Owns the catalog slice of
[Exit Definition](README.md#exit-definition) item 6.

### Deliverables

- `runCheckpointEval :: Text -> [ParsedOption] -> App ()` is the shared
  checkpoint read path used by `jitml eval` and `jitml rl eval`: it loads the
  named `.jmw1` checkpoint and runs the substrate-bound weighted device forward;
  a missing pointer/manifest → `InferenceCheckpointMissing` (exit 1).
- `jitml rl rollout --seed N` runs one real on-device PPO rollout on cartpole
  through `rlDeviceForSubstrate` (`runDeviceRollout` → `trainOnPolicyOnDevice`,
  one iteration) and prints the measured per-iteration episode rewards; an
  unavailable substrate device fails closed with `InvalidConfig`.
- `moduleRolloutGenerator` is retired as the shared LCG generator: each
  algorithm module's rollout runs its real (device-backed) trained policy on the
  canonical environment, so the per-algorithm rollout surface is genuine.

### Validation

- `docker compose run --rm jitml jitml test jitml-rl-canonicals --linux-cpu`
  (per-algorithm on-device rollouts; live half in Sprint 15.17).
- Offline `jitml rl eval` → `InferenceCheckpointMissing`; offline `jitml rl
  rollout` → `InvalidConfig`; neither prints a synthetic trajectory.
- `jitml check-code` + `jitml docs check` green inside `jitml:local`.

### Current Validation State

Landed and host-validated (`ghc-9.12.4`, device cases fail closed offline):

- `runCheckpointEval` shared by `jitml eval` / `jitml rl eval`; the `rl eval`
  echo stub is removed (ledger row resolved jointly with the `rl rollout` LCG).
- `jitml rl rollout` routes through `runDeviceRollout` (real on-device PPO
  rollout), removing the `deterministicTrajectory` LCG; fails closed on an
  absent device. Host `cabal build` clean; the command-registration unit test
  still lists `rl eval` / `rl rollout`.
- 2026-06-11: `docker compose run --rm jitml jitml test jitml-rl-canonicals
  --linux-cpu` → **27/27 PASS**, including the PPO/CartPole registered rollout
  determinism case and the on-device PPO reward-improvement case.
- 2026-06-11: `docker compose run --rm jitml-cuda jitml test
  jitml-rl-canonicals --linux-cuda` → **27/27 PASS**.
- 2026-06-11: `docker compose run --rm jitml-cuda jitml rl rollout
  experiments/cartpole.dhall --seed 42` printed
  `rl rollout: seed=42 substrate=linux-cuda rewards=[18.96]`, confirming the
  CLI boundary resolves the live CUDA publication and executes the device path.

### Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
