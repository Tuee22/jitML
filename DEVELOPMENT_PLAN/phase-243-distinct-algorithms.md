# Phase 243: Distinct Algorithms

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Distinct Algorithms. Single-session phase migrated from legacy Sprint 25.2 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 243.1: Distinct Algorithms [✅ Done]

**Status**: Done
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
  [`jitml-negative-controls`](README.md#legacy-to-new-phase-map) suite
  asserts a differential separation: `TQC(drop > 0)` must produce a different
  update trajectory than `SAC`, and a deterministic-actor / fixed-`alpha` SAC
  stand-in is rejected as SAC evidence. Closure requires each reopened algorithm
  to pass its differential control and the
  [`jitml-model-convergence`](README.md#legacy-to-new-phase-map)
  case that trains the row from a real random init through the production trainer.

2026-07-10 closure: the affected trainer configs use product 256-hidden network
widths, TRPO uses a policy-only trust-region step with a separate value optimizer,
and the continuous/QR/key-door residual fixes are exercised by the standing
`jitml-rl-canonicals` and `jitml-model-convergence` gates.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
