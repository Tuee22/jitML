# Phase 249: Per-Row Convergence and Evidence

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Per-Row Convergence and Evidence. Originally migrated from legacy Sprint 25.3 in the 2026-07-24 phase renumber; see the old→new map in [README.md](README.md).

## Phase State

⏸️ **Blocked** for the expanded validation foundation in Sprint `249.2`.
The earlier Sprint `249.1` record below is retained on its original source and
scope; it does not validate this target or a current hardware lane. The execution
order and transition authority are [the validation-foundation refactor](README.md#validation-foundation-refactor).

The new source/catalogue, runner and hardware controls remain unimplemented.
Sprint `221.2` owns reconciliation of the existing checker with these documented
targets; this documentation-only change supplies no machine-validation receipt.

## Sprint 249.2: RL convergence and runtime failure remediation [⏸️ Blocked]

**Status**: Blocked
**Implementation**: Target changes to `src/JitML/RL/Algorithms/ContinuousTrainer.hs`, `src/JitML/RL/Algorithms/PpoTrainer.hs`, `src/JitML/RL/Algorithms/DqnTrainer.hs`, `src/JitML/RL/Algorithms/QrDqnTrainer.hs`, `src/JitML/RL/Simulator.hs`.
**Blocked by**: Sprint `160.2`, Sprint `225.2`.
**Docs to update**: `../documents/engineering/execution_resources.md`, `../documents/engineering/validation_execution.md`, `../documents/engineering/training_metrics_and_splits.md`, `../documents/engineering/training_workloads.md`, `README.md`, `system-components.md`, `legacy-tracking-for-deletion.md`.

### Objective

Every RL row reaches measured runtime and learning readiness through bounded hypothesis-driven investigations before a hardware qualification campaign.

The target contracts are [execution resources](../documents/engineering/execution_resources.md)
and [validation execution](../documents/engineering/validation_execution.md).
Their acceptance requirements below are planned work, not implemented behavior.

### Deliverables

- Own the twelve retained RL learning refusals: `PPO/mountain-car`, `PPO/key-door-grid`, `A2C/lunar-lander`, `A2C/key-door-grid`, `MaskablePPO/mountain-car`, `MaskablePPO/key-door-grid`, `RecurrentPPO/mountain-car`, `RecurrentPPO/key-door-grid`, `QR-DQN/mountain-car`, `DQN/key-door-grid`, `SAC/pendulum`, and `CrossQ/lunar-lander`. Own the distinct `TRPO/key-door-grid` timeout.
- For SAC, first reproduce and attribute step-dependent memory growth in one capped process and determine whether it affects the qualification implementation. Verify authentic parameter/update changes before increasing steps or concurrency.
- Diagnose TRPO timing by stage and actual progress. Operational deadline/throughput refusal is distinct from a quality result; prospective scheduling policy cannot silently change numerical work.
- Check shared environment/action/reward/termination semantics for related key-door-grid and mountain-car failures, then investigate algorithm-specific mechanisms. Reopen Phase `248` only for defects in its owned implementations.
- Use independently justified development/calibration studies and the prospective `278.2` criterion policy. No passing seed substitution, post-hoc floor reduction, invented evidence, or hidden budget increase is permitted.

### Validation

1. Target a demonstrated failure first with the existing row-selectable production path and an exact source/image/recipe/substrate/resource ledger; select one bounded experiment at a time.
2. For each repair record initial/final per-seed values, actual updates/environment work, full cohort, served index, memory/counters and terminal result; reject scripted, unchanged and below-policy controls.
3. Rerun previously passing shared paths only when a recorded change impact requires it; continue unresolved rows before complete-lane qualification.
4. After all individual rows and affected owned canonical controls pass, hand the candidate to the lane owners. Complete cross-family convergence transcripts belong to 283.2/285.2 and are not this readiness closure prerequisite.

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

- Root-cause and fix SAC retention/update behavior, the TRPO timeout and all twelve RL learning refusals without treating supervision as a learning fix.
- Confirm affected regressions, current-source criteria and measured readiness before qualification; the historical all-RL convergence claim is not current readiness.

## Retained Historical Scope

The following state, commands, measurements and closure statements describe the
original Sprint `249.1` surface only. New execution rules and acceptance
above supersede any conflicting operational instruction; old receipts are not
reinterpreted as current readiness.

### Historical Phase State

✅ **Done**.

## Sprint 249.1: Per-Row Convergence and Evidence [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/App.hs`, `src/JitML/RL/ConvergenceThresholds.hs`, `src/JitML/RL/Algorithms/Common.hs`, `src/JitML/RL/Algorithms/PpoTrainer.hs`, `src/JitML/RL/Algorithms/DqnTrainer.hs`, `src/JitML/RL/Algorithms/QrDqnTrainer.hs`, `src/JitML/RL/Algorithms/ContinuousTrainer.hs`, `src/JitML/RL/Algorithms/HerTrainer.hs`, `src/JitML/RL/Algorithms/ArsTrainer.hs`, `src/JitML/Test/RowAssertions.hs`, `test/rl-canonicals/Main.hs`
**Docs to update**: `../documents/engineering/training_metrics_and_splits.md`, `../documents/engineering/product_completion_contract.md`

### Objective

Each RL row records initial/final policy-or-Q hashes, update counts, `linux-cpu`
device evidence, and a measured-median convergence metric, and that measured
metric clears the literature-anchored bar for its `(algorithm, environment)`
cohort.

### Deliverables

- Every neural RL row records a deterministic initial-parameter hash, a final
  parameter hash that differs from initialization, an update count for the fixed
  budget, and the `linux-cpu` device that executed the update-critical kernels.
- `RowAssertions` computes the measured median over the fixed seed cohort and
  asserts `passesConvergence` against the `cohortThreshold` entry for that
  `(algorithm, environment)` pair; a missing cohort threshold fails the row.
- `cohortThresholds` covers every product `(algorithm, environment)` row with a
  literature-anchored target and slack, and HER goal-conditioned rows assert real
  success-rate and achieved-goal-distance observations.
- The row assertions reject `deterministicStep` output, synthetic transitions,
  and initialized-only checkpoints as convergence evidence.
- The RL report card names each row id with its convergence metric, threshold,
  update count, and device evidence, and distinguishes unmet supported rows from
  typed-optional rows.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-rl-canonicals --linux-cpu
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

Validated on 2026-07-02: focused Sprint `25.3` RL canonical tests passed 2/2,
the ProductRow unit slice passed 8/8 after regenerating generated docs/contracts,
`jitml-rl-canonicals --linux-cpu` passed 35/35, and
`jitml-unit --linux-cpu` passed 274/274. Final `jitml docs check` and
`jitml check-code` passed after the Phase `25` closure and Phase `26.1`
activation status updates.

**Historical publisher diagnostic (2026-07-03 reopen).** The Phase `28` live
publisher run reported **18** error
rows, including supported RL rows that did not produce passing
`CompletedTraining` evidence in the reachability validation. After Sprint
`25.1` re-closed, a row-filtered publisher run for formerly unsupported rows
reported **0** unsupported rows and **4** `CompletedTraining` errors, confirming
that this sprint now owns the active RL blocker: live RL product rows must emit
passing convergence observations from real trainer evidence.

**Historical publisher diagnostic (2026-07-03 reclose).** `docker compose run
--rm jitml cabal build all
--ghc-options=-Werror` passed; the full RL-only live product publisher filter
reported **39** rows, **39** eligible, **0** unsupported, and **0** errors;
`jitml-rl-canonicals --linux-cpu` passed **37 / 37**; `jitml-unit --linux-cpu`
passed **277 / 277**; `jitml docs check` passed after regenerating tracked
contracts; and `jitml check-code` passed.

Reopened on 2026-07-05 (realness audit): the reported RL convergence reward is
**not** produced by the trained policy. `src/JitML/App.hs` builds evaluation
episodes as `fromMaybe (trained eval) (canonicalDiscreteEvaluation env)` and the
continuous counterpart `canonicalContinuousEvaluation env`, and those functions
return `Just` a hardcoded expert controller for every canonical environment
(~`4389`–`4525`: `cartPoleExpertAction`, the Acrobot 6-step lookahead, and
per-environment scripted controllers), so the `fromMaybe` fallback to the trained
policy is never taken and the "measured median" the row asserts is the expert
controller's reward, not the policy's. The HER goal-success observation is a
literal constant — `replicate evalEpisodes (1.0, herNumBits)` (~`4325`) — rather
than an achieved-goal trace from a relabelled off-policy learner. Every RL row's
`passesConvergence` check therefore grades a scripted controller, so the
2026-07-03 "0 errors" publisher result reflects controller reward, not learning.

### Closure Evidence

- **Closed Exit-Definition obligation (measured metric from the trained policy).**
  Delete the `canonicalDiscreteEvaluation` / `canonicalContinuousEvaluation`
  expert controllers in `src/JitML/App.hs` (~`4389`–`4525`) and evaluate the
  **trained policy** directly, so the per-row median convergence metric is the
  policy's reward. Replace the constant HER goal-success (~`4325`,
  `replicate evalEpisodes (1.0, herNumBits)`) with a real achieved-goal /
  success-rate trace from the hindsight-relabelled learner. The initial/final
  parameter hashes, update counts, and `linux-cpu` device evidence stay, but the
  convergence value must be recomputed from the served policy at read time.
- **Negative-control validation that closes it.** The
  [`jitml-negative-controls`](README.md#legacy-to-new-phase-map) suite
  rejects an expert-controller (scripted) reward trace as RL row evidence, and the
  per-model [`jitml-model-convergence`](README.md#legacy-to-new-phase-map)
  case trains each RL row from a real random init through the production device
  seam and asserts the **trained-policy** median over the seed cohort clears the
  external bar (`rleSyntheticTransitionEvidence = False`). Closure requires both
  suites green on `linux-cpu`; the plan-truth audit that keeps this row from being
  re-closed on self-authored evidence is
  [Phase `34`](README.md#legacy-to-new-phase-map).

2026-07-10 closure: every RL product row's literature-anchored convergence bar
is re-cleared under the vectorized and widened regime; `jitml-model-convergence
--linux-cpu` passed **111 / 111**, including all RL rows and their non-wall-clock
inference-performance floors.

## Documentation Requirements

**Engineering docs to create/update:**

- `../documents/engineering/execution_resources.md`.
- `../documents/engineering/validation_execution.md`.
- `../documents/engineering/training_metrics_and_splits.md`.
- `../documents/engineering/training_workloads.md`.

**Product docs to create/update:**

- [Development-plan entry](README.md#validation-foundation-refactor), [component inventory](system-components.md), and [deletion ledger](legacy-tracking-for-deletion.md).

**Cross-references to add:**

- Link the target contracts, exact sprint dependencies and evidence pointers together when source implementation lands; update root summaries only in an authorized root-file change.
