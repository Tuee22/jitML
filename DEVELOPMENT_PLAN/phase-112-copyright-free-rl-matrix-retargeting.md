# Phase 112: Copyright-Free RL Matrix Retargeting

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Copyright-Free RL Matrix Retargeting. Single-session phase migrated from legacy Sprint 9.8 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 112.1: Copyright-Free RL Matrix Retargeting [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/RL/ConvergenceThresholds.hs`,
`src/JitML/RL/Algorithms/Registry.hs`, `test/rl-canonicals/Main.hs`,
`documents/engineering/training_workloads.md`
**Docs to update**: `README.md`,
`documents/engineering/training_workloads.md`,
`documents/engineering/unit_testing_policy.md`,
`DEVELOPMENT_PLAN/system-components.md`

### Objective

Retarget the required RL algorithm/convergence matrix so visual
discrete-control coverage uses `KeyDoorGrid-v0` rather than `atari-subset`,
keeping all required demos and canonical checks free of copyrighted runtime
assets.

### Deliverables

- `JitML.RL.ConvergenceThresholds` replaces `atari-subset` cohorts with
  `key-door-grid` / `KeyDoorGrid-v0` cohorts where a visual discrete-action
  environment is needed.
- `jitml-rl-canonicals` covers the algorithm × environment matrix without
  requiring Atari ROM bytes.
- Maskable algorithms exercise `KeyDoorGrid-v0` legal-action masks.
- Required docs and report-card language refer to Atari/ALE only as optional
  runtime support, not canonical demo coverage.

### Validation

1. Phase `8` Sprint `8.9` validation has passed.
2. `docker compose run --rm jitml cabal test jitml-rl-canonicals --jobs=2`
   passes with the retargeted matrix.
3. `rg -n 'atari-subset' src/JitML/RL/ConvergenceThresholds.hs
   test/rl-canonicals/Main.hs README.md documents` shows no required
   convergence/demo wording.
4. `docker compose run --rm jitml jitml check-code` passes.

### Validation Re-run (2026-06-04)

- Phase `8` Sprint `8.9` validation passed in the same container session.
- `docker compose run --rm -e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0='*' jitml cabal test jitml-unit jitml-rl-canonicals --jobs=2`
  passed: `jitml-unit` 184 / 184 and `jitml-rl-canonicals` 27 / 27.
  The `jitml-rl-canonicals` pass includes the retargeted convergence
  threshold lookup and the `KeyDoorGrid-v0` maskable canonical case.
- `docker compose run --rm jitml jitml check-code` passed during
  `jitml:local` image construction with `check-code: ok`.

### Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
