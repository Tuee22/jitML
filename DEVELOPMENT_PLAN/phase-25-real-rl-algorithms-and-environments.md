# Phase 25: Real RL Algorithms & Environments

**Status**: Active
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [development_plan_standards.md](development_plan_standards.md), [phase-24-real-supervised-architectures.md](phase-24-real-supervised-architectures.md), [phase-26-alphazero-real-self-play.md](phase-26-alphazero-real-self-play.md), [../documents/engineering/product_completion_contract.md](../documents/engineering/product_completion_contract.md), [../documents/engineering/training_workloads.md](../documents/engineering/training_workloads.md), [../documents/engineering/training_metrics_and_splits.md](../documents/engineering/training_metrics_and_splits.md)
**Generated sections**: none

> **Purpose**: Implement every canonical RL environment from published dynamics
> and make every catalog algorithm a genuinely distinct learner that clears its
> per-row convergence bar on `linux-cpu`.

## Phase State

🔄 **Reopened (2026-07-07) by the real-device convergence audit.** The first
honest `jitml internal train-and-publish-product-rows --linux-cuda` run on the RTX
5090 (Phase `29`) found that many RL rows do **not** reach their literature-anchored
convergence bars — 23 / 55 product rows converged initially — which contradicts the
"real RL convergence" claim below. Per standards rule N the audit finding defines
status, so this phase is in remediation. Genuine implementation bugs were
root-caused and fixed (device-validated, moving the count to 30 / 55 and higher):
the actor-critic value head was tanh-clamped to [-1,1] (linearized); off-policy
trainers were budget-starved at 2000-4000 env-steps (raised to SB3 scale with O(1)
replay); the entropy term had the wrong sign (an entropy penalty, now a bonus);
DQN/HER floored the Bellman bootstrap at 0 on negative-reward envs; QR-DQN/continuous
stored time-limit truncation as a terminal; TRPO diverged on hard envs; CrossQ
z-scored / target-net-less; and the continuous actor had a spurious zero-torque
gradient. The **2026-07-07 session** then root-caused the dominant CUDA-vs-CPU gap
to nvcc **FMA contraction** (fixed with `--fmad=false`, making the substrates
track — PPO/cartpole and PPO/lunar-lander went error → eligible on the RTX 5090),
and landed real reward shaping (`JitML.RL.RewardShaping`, fixing PPO/acrobot), a
QR-DQN retune (fixing QR-DQN/cartpole), unified on-policy tuning, mountain-car
exploring starts + observation normalization, and AlphaZero arena-search fixes.
Remaining unconverged rows: the on-policy `mountain-car` cohort (a sparse-reward
exploration wall potential shaping provably cannot address on-policy), `DQN` /
`QR-DQN` mountain-car (−159 / −153, marginal), `TRPO/lunar-lander` (diagonal-Fisher
divergence), and `SAC/pendulum` (swing-up); the deep-SL and hex rows are owned by
Phases `33`/`26`/`29`. `jitml-model-convergence` and `jitml-negative-controls`
pass. **The per-sprint status flips landed 2026-07-08**: sprints 25.1/25.2/25.3
are now Active. The remediation scope has also **expanded** on top of the residual
convergence fixes above — this reopening now additionally covers environment
**vectorization** (~16 parallel env instances batched through the network in one
device call per step, reintroducing a real, product-reachable `JitML.RL.VecEnv`)
and **RL network right-sizing** (hidden widths raised 64/128 → ~256), alongside the
banded RecurrentPPO / policy-only-Fisher TRPO / value-clipped A2C / directed-SAC
residual fixes. Each sprint below carries a `### Remaining Work` block enumerating
its unmet obligations, and a fresh full real `linux-cpu` device run under the new
vectorized + widened regime is required to re-clear the per-row bars. The prior
closure narrative is retained below as the historical (now-contradicted) record.

✅ **Done** (reclosed 2026-07-06 after the 2026-07-05 realness audit). Phase `24`
is Done. RL product evidence now comes from the trained policy evaluator rather
than hardcoded expert controllers; HER reports real goal-conditioned rollouts;
TRPO, RecurrentPPO, SAC, TQC, and CrossQ carry their defining update mechanisms;
and the tuning catalog applies adaptive TPE, ASHA promotion, and MedianPruner
filtering to measured trial results. Validation: `jitml-hyperparameter` passed
**19 / 19**, `jitml-negative-controls` passed **3 / 3**, and
`jitml-rl-canonicals` passed **37 / 37** on `linux-cpu`.

**Validation substrate**: `linux-cpu` only.

## Objective

Every RL product row is a real algorithm/environment pair. Each documented
environment is implemented from its published dynamics, the trainer consumes the
environment the `ProductRow` requested instead of a hardcoded simulator, and each
catalog algorithm applies its own update math rather than aliasing a shared
template. A row is complete only when it records initial/final policy-or-Q
hashes, update counts, `linux-cpu` device evidence, and a measured-median
convergence metric that clears the literature-anchored bar in
`RL/ConvergenceThresholds.hs`. The catalog no longer collapses roughly fourteen
named algorithms onto three trainer templates plus ARS, and it no longer trains
only CartPole and Pendulum while claiming MountainCar, Acrobot, LunarLander,
KeyDoorGrid, GridWorld, or a goal-conditioned environment.

## Sprint 25.1: Real Environments [🔄 Active]

**Status**: Active
**Implementation**: `src/JitML/RL/Simulator.hs`, `src/JitML/RL/Environments.hs`, `src/JitML/RL/EpisodeEnvelope.hs`, `src/JitML/RL/Algorithms/Common.hs`, `test/rl-canonicals/Main.hs`
**Docs to update**: `../README.md`, `../documents/engineering/training_workloads.md`

### Objective

CartPole, MountainCar, Acrobot, Pendulum, LunarLander, KeyDoorGrid, and
GridWorld are each implemented from their published dynamics, and the trainer
steps the exact environment named by the requested `ProductRow` rather than a
hardcoded CartPole/Pendulum simulator.

### Deliverables

- Each canonical environment carries a native transition function matching its
  published dynamics: CartPole and Acrobot classic-control equations of motion,
  MountainCar sinusoidal potential, Pendulum continuous torque dynamics,
  LunarLander lander physics with discrete and continuous action variants, and
  the discrete KeyDoorGrid and GridWorld tabular dynamics.
- `RLEnvironment` records observation shape, action space, reward function,
  termination, and horizon per environment so the trainer resolves them from the
  `ProductRow` and never falls back to a default simulator.
- Continuous-control rows step the documented continuous environment (Pendulum,
  LunarLanderContinuous) with real action bounds, not a discretized stand-in.
- Product tests reject `deterministicStep` and synthetic environment transitions
  as canonical RL evidence; those helpers stay behind test-only gates.
- README RL environment tables and the `ProductRow` environment ids agree with
  the implemented catalog with no unimplemented row left claimed as product.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-rl-canonicals --linux-cpu
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml check-code
```

Validated on 2026-07-02: `jitml-rl-canonicals --linux-cpu` passed 32/32,
`jitml-unit --linux-cpu` passed 273/273, and `jitml check-code` passed after
the native Acrobot, Pendulum, KeyDoorGrid, and GridWorld catalog additions and
the trainer fail-closed environment-selection guard.

Reopened on 2026-07-03: the 2026-07-03 Phase `28` publisher reachability run
reported **29** RL rows as unsupported because the production trainer dispatch
still supports only CartPole for on-policy/discrete/ARS rows, Pendulum for
continuous rows, and goal-reaching for HER. The simulator catalog exists, but
the production trainer loops still do not consume the row-requested simulator
for MountainCar, Acrobot, LunarLander, KeyDoorGrid, or GridWorld rows.

Re-closed on 2026-07-03: `cabal build all --ghc-options=-Werror` passed in the
`jitml` container; `jitml-rl-canonicals --linux-cpu` passed **37 / 37**;
`jitml-unit --linux-cpu` passed **277 / 277**; and a row-filtered live
publisher run through the rebuilt worktree executable for
`PPO/mountain-car,DQN/key-door-grid,SAC/lunar-lander,ARS/lunar-lander` reported
**4** rows, **0** eligible, **0** unsupported, and **4** `CompletedTraining`
errors. That filtered publisher result proves the former fail-closed
environment-dispatch blocker moved from Sprint `25.1` to Sprint `25.3`
evidence/convergence work.

### Closure Evidence

None.

### Remaining Work

- Vectorize the RL environments so that ~16 parallel env instances are batched
  through the network in one device call per step, reintroducing a real,
  product-reachable `JitML.RL.VecEnv` seam that the production trainer loops step.
- **Dependency (Phase `20`-owned lint refinement):** the reintroduced real
  `JitML.RL.VecEnv` module must be admitted by the scaffold-lint forbidden-module
  list in `documents/engineering/code_quality.md`'s lint, which presently forbids
  such a module as a dead fake. Refine that forbidden-module list to permit the
  reintroduced REAL module while still catching dead fakes — a small
  Phase-`20`-owned lint refinement tracked here as a cross-phase dependency.

## Sprint 25.2: Distinct Algorithms [🔄 Active]

**Status**: Active
**Implementation**: `src/JitML/RL/Algorithms/PpoTrainer.hs`, `src/JitML/RL/Algorithms/DqnTrainer.hs`, `src/JitML/RL/Algorithms/ContinuousTrainer.hs`, `src/JitML/RL/Algorithms/QrDqnTrainer.hs`, `src/JitML/RL/Algorithms/HerTrainer.hs`, `src/JitML/RL/Algorithms/ArsTrainer.hs`, `src/JitML/RL/Algorithms/Registry.hs`
**Docs to update**: `../README.md`, `../documents/engineering/training_workloads.md`

### Objective

PPO, A2C, TRPO, DQN, QR-DQN, DDPG, TD3, SAC, CrossQ, TQC, HER, and ARS each
apply their own documented update math and no longer coincide exactly with PPO on
discrete environments or collapse into a shared trainer template.

### Deliverables

- On-policy rows are genuinely distinct: PPO uses clipped-surrogate updates, A2C
  uses the advantage-actor-critic update without the PPO clip, and TRPO uses a
  trust-region/KL-constrained step; none is an alias of another.
- Off-policy rows are genuinely distinct: DQN uses target-network bootstrapping,
  QR-DQN uses quantile regression, DDPG/TD3 use deterministic-policy-gradient
  critics (TD3 adds twin critics, target-policy smoothing, and delayed actor
  updates), and SAC/CrossQ/TQC use entropy-regularized critics (CrossQ drops the
  target network with batch-renormalized critics; TQC uses truncated quantile
  critics).
- HER wraps an off-policy learner with real hindsight goal relabeling on a
  goal-conditioned environment and records goal-success evidence.
- ARS is a non-neural policy-search row that carries a learned linear-policy
  artifact and policy-delta evidence, or is typed as a non-product row; it does
  not claim substrate-backed ANN training.
- ALE/Atari rows are implemented for real with ROM policy, implementation, and
  test evidence, or are typed as explicitly optional non-product rows.
- The algorithm registry maps each `ProductRow` algorithm id to its own trainer;
  a unit test fails when two distinct algorithm ids resolve to the same update.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-rl-canonicals --linux-cpu
docker compose run --rm jitml jitml test jitml-integration --linux-cpu
docker compose run --rm jitml jitml check-code
```

Validated on 2026-07-02: focused Sprint `25.2` unit and RL canonical tests
passed, `jitml-rl-canonicals --linux-cpu` passed 33/33,
`jitml-integration --linux-cpu` passed 81/81 after canonical MNIST train/test
image+label blobs were staged through `jitml internal upload-dataset`, and
`jitml check-code` passed.

Reopened on 2026-07-05 (realness audit): the distinct-algorithm registry test
proves that algorithm ids resolve to *distinct trainer entry points*, but several
of those entry points are stand-ins that do not apply their documented update
math. In `PpoTrainer.hs`, TRPO has no conjugate-gradient trust-region step and
RecurrentPPO has no recurrent cell or hidden state. In `ContinuousTrainer.hs`,
SAC uses a fixed `alpha = 0.2` with a deterministic actor and no entropy term,
TQC uses scalar critics with `drop = 0` (making it indistinguishable from SAC),
and CrossQ hardcodes an identity batch-renorm instead of the real
batch-renormalized critic. The genuine per-algorithm `*Loss` modules exist but
are imported only by tests, so the production trainer never exercises them. The
registry's "two ids never resolve to the same update" assertion passes on the
entry-point identity while the underlying update math still coincides.

### Closure Evidence

- **Closed Exit-Definition obligation (real distinct algorithm math).** Wire each
  algorithm's real per-algorithm mechanics into the production trainer, not just a
  distinct entry point: TRPO's conjugate-gradient trust-region step,
  RecurrentPPO's recurrent cell and carried hidden state, SAC's entropy term with
  a learned (non-fixed) `alpha`, TQC's truncated quantile critics with
  `drop > 0`, and CrossQ's real batch-renormalized critic without a target
  network. The production trainer must import and apply the real `*Loss` modules
  currently reachable only from tests.
- **Negative-control validation that closes it.** The
  [`jitml-negative-controls`](phase-32-external-truth-realness-harness.md) suite
  asserts a differential separation: `TQC(drop > 0)` must produce a different
  update trajectory than `SAC`, and a deterministic-actor / fixed-`alpha` SAC
  stand-in is rejected as SAC evidence. Closure requires each reopened algorithm
  to pass its differential control and the
  [`jitml-model-convergence`](phase-33-per-model-convergence-and-inference-tests.md)
  case that trains the row from a real random init through the production trainer.

### Remaining Work

- Land the RL residual algorithm fixes: raise RecurrentPPO's exploration-beta into
  the 8-10 band and drop the recurrent advantage/target perturbation; give TRPO a
  policy-only Fisher with a separate value-head Adam optimizer; add A2C
  value-gradient clipping plus a k3-estimator KL early-stop (~`0.02`); and give
  SAC/pendulum directed exploration.
- Raise the RL network hidden widths from 64/128 to ~256 across the affected
  trainers.

## Sprint 25.3: Per-Row Convergence and Evidence [🔄 Active]

**Status**: Active
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

Reopened on 2026-07-03: the Phase `28` live publisher run reported **18** error
rows, including supported RL rows that did not produce passing
`CompletedTraining` evidence in the reachability validation. After Sprint
`25.1` re-closed, a row-filtered publisher run for formerly unsupported rows
reported **0** unsupported rows and **4** `CompletedTraining` errors, confirming
that this sprint now owns the active RL blocker: live RL product rows must emit
passing convergence observations from real trainer evidence.

Re-closed on 2026-07-03: `docker compose run --rm jitml cabal build all
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
  [`jitml-negative-controls`](phase-32-external-truth-realness-harness.md) suite
  rejects an expert-controller (scripted) reward trace as RL row evidence, and the
  per-model [`jitml-model-convergence`](phase-33-per-model-convergence-and-inference-tests.md)
  case trains each RL row from a real random init through the production device
  seam and asserts the **trained-policy** median over the seed cohort clears the
  external bar (`rleSyntheticTransitionEvidence = False`). Closure requires both
  suites green on `linux-cpu`; the plan-truth audit that keeps this row from being
  re-closed on self-authored evidence is
  [Phase `34`](phase-34-plan-truth-governance.md).

### Remaining Work

- Re-clear every RL product row's literature-anchored convergence bar under the new
  vectorized (~16 parallel env instances batched per device step) and widened (~256
  hidden) regime, recording fresh `linux-cpu` device evidence for each re-cleared
  metric.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/training_workloads.md` — RL environment catalog, the
  distinct-algorithm update-math ownership, and the vectorized environment
  execution model (~16 parallel env instances batched through the network per
  device step via the reintroduced `JitML.RL.VecEnv`) with the raised ~256 hidden
  widths.
- `documents/engineering/training_metrics_and_splits.md` — per-row convergence
  metric, cohort threshold, and RL evidence fields re-cleared under the vectorized
  and widened regime.
- `documents/engineering/product_completion_contract.md` — RL product-row
  convergence and evidence bar.
- `documents/engineering/code_quality.md` — Phase-`20`-owned scaffold-lint
  forbidden-module list refined to permit the reintroduced real `JitML.RL.VecEnv`
  module while still catching dead fakes.

**Product docs to create/update:**
- `README.md` — RL environments table and convergence/determinism checks aligned
  with the implemented catalog.

**Cross-references to add:**
- Link the RL environment and control docs from `training_workloads.md`, link
  RL product rows from `product_completion_contract.md`, and link the reintroduced
  `JitML.RL.VecEnv` module from the `code_quality.md` scaffold-lint list.
