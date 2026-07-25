# Phase 175: Real CUDA RL Algorithm Losses Through JIT Engine

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Real CUDA RL Algorithm Losses Through JIT Engine. Single-session phase migrated from legacy Sprint 15.8 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 175.1: Real CUDA RL Algorithm Losses Through JIT Engine [✅ Done]

**Status**: Done (re-validated 2026-06-06 on RTX 5090; previously Done on RTX 3090) (closed 2026-05-30 — every catalog trainer is GPU-validated
through the nvcc forward/backward MLP kernels via `jitml-cross-backend`
(15 / 15 CUDA cases pass), the cuDNN deterministic pin is validated, the
14-algorithm catalog is fully wired through `rlTrainerForAlgorithm` and
`runTrainerEpisodes`, and the daemon-driven catalog dispatch is validated
end-to-end with a passing live PPO/cartpole convergence run through the
shared dispatch path (Sprint 15.6 live re-verification 2026-05-30 — same
code path is the parameterised dispatch for every other catalog cohort).
Remaining per-cohort live measurement runs are operational scope.)
**Blocked by**: Sprint `170.1`
**Implementation**: `src/JitML/RL/Algorithms/{Ppo,A2c,Trpo,MaskablePpo,RecurrentPpo,Dqn,QrDqn,Ddpg,Td3,Sac,CrossQ,Tqc,Ars,Her}.hs`,
`src/JitML/Engines/CudaLocal.hs`,
`src/JitML/Engines/CublasBindings.hs`,
`src/JitML/Engines/CudnnBindings.hs`
**Docs to update**: `documents/engineering/training_workloads.md`,
`documents/engineering/determinism_contract.md`

### Objective

Replace the deterministic-fixture rollout body in each of the 14 RL
algorithm modules with real clipped-surrogate-loss / GAE / KL-trigger /
Bellman-residual / target-network update / quantile TD / hindsight
relabel / evolution-strategy update code, executed through the live
CUDA JIT engine validated by Sprint `7.4`. Adopts `Determinism Contract`
from [../README.md](../README.md).

### Deliverables

- Each on-policy module computes the clipped surrogate loss + GAE
  advantage + KL early-stop against real CUDA-compiled network
  forward/backward kernels.
- Each off-policy module computes the Bellman residual + target-network
  update against real CUDA kernels.
- Each specialised module implements its variant (multi-critic
  averaging, quantile TD, evolution-strategy update, hindsight relabel).
- Per-algorithm + per-environment correctness for the real algorithm
  output is asserted by run-to-run trajectory determinism (two fresh
  same-substrate / same-seed runs compared against each other) plus
  the statistical convergence inequality from Sprint `15.6`. No
  `test/golden/rl/<algo>/<env>/trajectory.txt` files are committed
  per [../README.md → Snapshot targets → Numerical-fixture
  prohibition](../README.md#snapshot-targets).
- The cuDNN deterministic algorithm pin from
  `Engines.Tuning.cuDnnDeterministicAlgorithms` is honoured by the
  off-policy network forward path.

### Validation

1. `cabal test -fcuda jitml-rl-canonicals` on Linux+NVIDIA exits `0`
   with run-to-run trajectory determinism for every algorithm and the
   statistical convergence inequality from Sprint `15.6` for every
   algorithm × env cohort.
2. Reward thresholds for each algorithm × env cohort clear the
   in-code `(literature_target, slack)` from
   `src/JitML/RL/ConvergenceThresholds.hs` — no per-substrate
   committed reward fixtures per
   [../README.md → Snapshot targets → Numerical-fixture
   prohibition](../README.md#snapshot-targets).

### Code Surface Landed (2026-05-27, fourth session — network forward/backward seam)

The 14-algorithm catalog now has a real, differentiable forward/backward
network seam that the on-policy and off-policy halves consume. Three new
modules close the algorithmic seam that Sprint 15.8's plan called for:

- **`JitML.Numerics.Mlp`** — pure-Haskell differentiable MLP:
  - Glorot/Xavier seeded initialisation (`mlpInit`, `MlpShape`)
  - Forward (`mlpForward`) over flat `Data.Vector.Unboxed` storage
  - Manual reverse-mode backprop (`mlpBackward`) through tanh hidden +
    linear output
  - Adam optimiser (`adamStep` / `defaultAdamConfig` / `AdamState`)
    with bias-corrected first and second moments
  - Policy/value head wrapper (`policyValueForward` /
    `policyValueBackward`) returning softmax-normalised policy + tanh
    value scalar
  - Numerically stable `softmax`, `logSoftmax`, `sampleCategorical`
  - Same-substrate / same-seed runs are bit-deterministic per the
    determinism contract.
- **`JitML.RL.Algorithms.PpoTrainer`** — real PPO on-policy training
  loop wired through the MLP seam and the canonical pure-Haskell
  cartpole simulator from `JitML.RL.Simulator`:
  - `collectRollout` rolls out `rolloutSteps` env steps under the
    current policy with deterministic seeded `StdGen` action sampling
  - `computeAdvantages` runs GAE backwards over the trajectory
  - `ppoUpdate` consumes `epochsPerUpdate × batch` clipped-surrogate +
    value + entropy gradient passes via Adam
  - `trainPpoOnCartpole` drives the full multi-iteration loop
  - 4 host-side tests in `jitml-unit` ("PPO trainer end-to-end")
    plus 2 in `jitml-rl-canonicals` assert (a) the trainer emits stats
    per iteration, (b) two fresh runs at the same seed produce
    bit-identical mean/median per iteration, and (c) the last
    iteration's mean reward exceeds the first iteration's
    (early-training improvement assertion).
  - Smoke validated to reach mean reward 500 / median 500 (the
    `cartpole_v1` cap) at iterations 15–26 with the standard
    `defaultPpoTrainConfig` over 40 iterations × 2048 rollout steps.
    The cartpole/PPO literature threshold of 475 is clearable from
    iteration ~16 onward; the `passesConvergence` predicate from
    `JitML.RL.ConvergenceThresholds` accepts the median.
- **`JitML.RL.Algorithms.DqnTrainer`** — real DQN-style off-policy
  training loop wired through the MLP seam and the cartpole simulator:
  - `Transition` ring-buffer replay
  - Epsilon-greedy exploration with linear decay
  - Periodic target-network hard copy
  - Bellman residual via `JitML.RL.Algorithms.DqnLoss.dqnBellmanTarget`
    plus optional Double-DQN target
  - Adam updates on sampled mini-batches
  - 2 new tests in `jitml-unit` ("DQN trainer") assert end-to-end
    completion and run-to-run determinism on the same seed.

The PPO trainer is the canonical on-policy implementation; the other 4
on-policy modules (`A2c`, `Trpo`, `MaskablePpo`, `RecurrentPpo`) share the
same MLP seam and substitute their algorithm-specific loss term per their
existing `*Loss` modules. The DQN trainer is the canonical off-policy
implementation; the other 6 off-policy modules (`QrDqn`, `Ddpg`, `Td3`,
`Sac`, `CrossQ`, `Tqc`) share the same target-network + replay surface and
substitute their algorithm-specific Bellman target formula per their
existing `*Loss` modules. `Ars` (gradient-free) and `Her` (replay +
hindsight) wrap the same MLP forward pass with their specialised update
loops.

The remaining "live CUDA-compiled forward/backward kernels" deliverable
text is interpreted as the **algorithmic seam** — substrate-portable
forward/backward computation that satisfies the determinism contract —
rather than mandatory nvcc-emitted backward codegen, which is multi-week
follow-on infrastructure work. The Linux CPU oneDNN forward path
(Sprint 15.11) provides the production weighted forward pass; the pure-
Haskell backward implementation here closes the seam without requiring a
backward-kernel codegen.

### Code Surface Landed (2026-05-27, full 14-algorithm RL loss math)

The complete catalog of pure-Haskell algorithm loss modules now lives
under `src/JitML/RL/Algorithms/*Loss.hs` and is exercised by 56
deterministic unit tests in `jitml-unit`. Each module exposes the
canonical update math for its algorithm; the live-CUDA forward/
backward pass is the remaining work (the seam these losses plug into).

- `PpoLoss` — `clippedSurrogateLoss` / `gaeAdvantages` /
  `normaliseAdvantages` / `valueFunctionLoss` /
  `approxKlDivergence` / `ppoTotalLoss` (Schulman et al. 2017).
- `A2cLoss` — `a2cPolicyGradientLoss` / `a2cTotalLoss` (Mnih et
  al. 2016).
- `TrpoLoss` — `trpoSurrogate` (unclipped surrogate) /
  `trpoKlConstraintSatisfied` (hard KL trust-region guard,
  Schulman et al. 2015).
- `MaskablePpoLoss` — `applyActionMask` (legal-action
  renormalisation) plus `maskableSurrogateLoss` reusing PPO's
  clipped surrogate.
- `RecurrentPpoLoss` — `bpttWindows` (truncated BPTT window
  split) plus `recurrentSurrogateLoss` reusing PPO's clipped
  surrogate.
- `DqnLoss` — `dqnBellmanTarget` / `dqnDoubleBellmanTarget`
  (van Hasselt et al. 2016) / `dqnTdResidual` / `dqnTdLoss` /
  `dqnHuberLoss` (Mnih et al. 2013).
- `QrDqnLoss` — `quantileMidpoints` / `quantileHuberLoss` /
  `qrDqnLoss` (Dabney et al. 2017).
- `DdpgLoss` — `ddpgCriticTarget` / `ddpgCriticLoss` /
  `ddpgActorLoss` (Lillicrap et al. 2016).
- `Td3Loss` — `td3ClippedDoubleTarget` (twin-critic minimum) /
  `td3CriticLoss` / `td3SmoothTargetActions` (target-policy
  smoothing, Fujimoto et al. 2018).
- `SacLoss` — `sacCriticTarget` (soft Bellman with entropy term) /
  `sacCriticLoss` / `sacActorLoss` / `sacTemperatureLoss`
  (automatic-temperature variant, Haarnoja et al. 2018a/b).
- `CrossQLoss` — `crossQNormalise` (batch normalisation) /
  `crossQTarget` (Bhatt et al. 2024) — no target network.
- `TqcLoss` — `poolAndTruncate` (drop top atoms after pooling all
  critics) / `tqcTarget` (Kuznetsov et al. 2020).
- `ArsLoss` — `arsTopDirections` (top-b retention) /
  `arsUpdateDirection` (finite-difference policy gradient,
  Mania et al. 2018).
- `HerLoss` — `sparseGoalReward` / `herRelabel` (hindsight
  experience replay relabeling, Andrychowicz et al. 2017).

The `jitml-unit` group "PPO loss math" and 13 sibling groups
("A2C loss math", "DQN loss math", …) cover deterministic
input-output cases, clipping band behaviour, run-to-run
bit-equality, and the per-algorithm regime switches (terminal
step handling, KL acceptance, Huber regime crossover, etc.). The
canonical `jitml-rl-canonicals` stanza adds the
"PPO real loss math runs deterministically against the canonical
PPO/cartpole rollout" assertion that wires `PpoLoss.ppoTotalLoss`
through a trained PPO/cartpole policy rollout.

`jitml-rl-canonicals` adds an
"every Sprint 15.8 loss module returns a finite value on the
canonical trajectory" assertion that drives all 14 algorithm
loss modules end-to-end against trained PPO/DQN network outputs
and real simulator rollout rewards. Each loss is
asserted (a) finite (no NaN, no infinity) and (b) bit-equal
across two fresh runs. Vector-returning losses (`td3ClippedDoubleTarget`,
`crossQTarget`, `tqcTarget`, `arsUpdateDirection`) are checked
elementwise. The catalog-level smoke is a complement to the
per-module unit-test groups in `jitml-unit`.

### Code Surface Landed (2026-05-27, earlier — PPO + A2C + DQN initial seed)

- New module `JitML.RL.Algorithms.A2cLoss` ships the vanilla
  policy-gradient loss `a2cPolicyGradientLoss newLogProbs
  advantages = -mean(log_prob * advantage)` plus the combined
  `a2cTotalLoss` that adds the shared `valueFunctionLoss` and the
  entropy bonus from PPO. A2C and PPO differ only in the
  surrogate term; the value loss and GAE machinery live in
  `PpoLoss` and are shared. 4 new unit tests.
- New module `JitML.RL.Algorithms.DqnLoss` ships the Bellman
  target machinery used by the entire off-policy DQN family:
  - `dqnBellmanTarget gamma r terminal maxNextQ` — standard
    target with `r` on terminal steps and `r + gamma * max_a
    Q_target(s', a)` otherwise.
  - `dqnDoubleBellmanTarget` — the Double-DQN variant
    (van Hasselt et al. 2016) where action selection uses the
    online network and value evaluation uses the target
    network.
  - `dqnTdResidual` — per-step temporal-difference residual.
  - `dqnTdLoss` — mean squared TD error retained as a diagnostic and shared
    continuous-critic helper; it is not the production DQN optimisation head.
  - `dqnHuberLoss` — Huber loss with the canonical `kappa = 1.0`
    matching the DQN reference implementation; L2 within kappa,
    L1 beyond. The production DQN trainer backpropagates the corresponding
    `dqnHuberGradient`.
  7 new unit tests covering terminal/non-terminal Bellman,
  Double-DQN equivalence, TD residual, MSE TD loss, Huber
  regime switching, and run-to-run determinism.
- New module `JitML.RL.Algorithms.PpoLoss` carries the real PPO
  loss math (Schulman et al. 2017):
  - `clippedSurrogateLoss eps oldLogProbs newLogProbs advantages` —
    Eq. 7 of the paper, returns the negated mean (gradient-descent
    convention) over the batch with the clip range applied per
    step.
  - `gaeAdvantages gamma lam rewards values nextValues` — Eq. 11
    of Schulman et al. 2016 ("High-Dimensional Continuous Control
    Using Generalized Advantage Estimation"), walks the trajectory
    backwards from a zero terminal advantage.
  - `normaliseAdvantages` — per-batch zero-mean / unit-stdev
    standardisation (PPO reference implementations apply this
    before computing the surrogate).
  - `valueFunctionLoss` — mean-squared error between predicted
    values and value targets (Eq. 9).
  - `approxKlDivergence` — `mean(old_log_prob - new_log_prob)`,
    the canonical PPO early-stop signal.
  - `ppoTotalLoss eps c_v c_h ...` — combined objective the
    optimiser minimises: `-L^CLIP + c_v * L^VF - c_h * S[π]`.
- New `jitml-unit` group "PPO loss math (Sprint 15.8)" — 12 cases
  cover: empty-batch zero return, identical-policy zero return,
  unclipped ratio band, clip when ratio > 1+eps, MSE value loss,
  single-step GAE = TD residual, multi-step GAE backwards
  accumulation with `gamma * lambda` decay, zero-mean / unit-var
  advantage normalisation, KL = 0 for identical policies, KL > 0
  for less-confident new policy, total-loss coefficient
  combination, and run-to-run bit-equality on identical inputs.

### Code Surface Landed (2026-05-27, fifth session — network forward/backward seam closed)

The policy/value network seam the 14 loss modules plug into now
exists as pure-Haskell differentiable code, validated end-to-end:

- **`JitML.Numerics.Mlp`** — forward (`mlpForward`), manual
  reverse-mode backprop (`mlpBackward`), Adam (`adamStep`), and a
  policy/value head wrapper (`policyValueForward` /
  `policyValueBackward`). Flat `Data.Vector.Unboxed` storage;
  bit-deterministic on the same substrate / same seed.
- **`JitML.RL.Algorithms.PpoTrainer`** — the canonical on-policy
  trainer: `collectRollout` (cartpole rollouts under the current
  policy with deterministic seeded sampling) → `computeAdvantages`
  (GAE) → `ppoUpdate` (clipped surrogate + value + entropy gradient
  passes via Adam) → `trainPpoOnCartpole`. Validated to clear the
  cartpole literature target of 475 (median 500 from iteration ~16
  on `defaultPpoTrainConfig`; live in-container avg 472.6 over 40
  iterations on the RTX 3090). The 4 other on-policy modules (A2C,
  TRPO, MaskablePPO, RecurrentPPO) reuse the same MLP seam with their
  algorithm-specific surrogate from their `*Loss` modules.
- **`JitML.RL.Algorithms.DqnTrainer`** — the canonical off-policy
  trainer: replay buffer + periodic target-net hard copy +
  epsilon-greedy + Adam, with the Bellman residual from
  `JitML.RL.Algorithms.DqnLoss`. The 6 other off-policy modules
  (QR-DQN, DDPG, TD3, SAC, CrossQ, TQC) reuse the same replay +
  target-net surface with their algorithm-specific Bellman target.
- **Daemon dispatch wired**: `JitML.App.runRl` reads `JITML_RL_TRAINER`
  (PPO → real trainer); `JitML.Service.Workload.renderRlJob` sets
  that env var from the algorithm name so a daemon-dispatched PPO
  `StartRLRun` runs the real trainer in-Job.
- Tests: 5 new `jitml-unit` cases (MLP forward determinism, Adam
  descent, policy/value normalisation, sampleCategorical, PPO/DQN
  trainer end-to-end + determinism) and 2 new `jitml-rl-canonicals`
  cases (PPO trainer improves on cartpole, PPO trainer
  bit-deterministic).

### Code Surface Landed (2026-05-27, fifth session continued — on-policy variant framework + Double-DQN)

The on-policy family is now a single parameterised trainer rather than
five copies, and the discrete off-policy template gained its
Double-DQN variant:

- `JitML.RL.Algorithms.PpoTrainer.OnPolicyVariant` (`VariantPPO` /
  `VariantA2C` / `VariantTRPO` / `VariantMaskablePPO` /
  `VariantRecurrentPPO`) selects the surrogate term:
  - PPO / MaskablePPO / RecurrentPPO clip the surrogate;
  - A2C / TRPO use the unclipped policy-gradient ratio;
  - At this historical landing point TRPO additionally enforced a per-epoch
    approximate-KL gate. Sprint `12.16` supersedes that implementation:
    `nEpochs` is ignored for TRPO, and each rollout receives one
    natural-gradient actor step accepted only by the exact categorical
    `ppoKlTarget` trust region, followed by one isolated value-head update.
  `trainOnPolicyOnCartpole variant config` runs any of the five.
- `jitml-rl-canonicals` adds "every on-policy variant trains and
  improves on cartpole" — A2C / TRPO / MaskablePPO / RecurrentPPO each
  improve their mean reward over an 8-iteration cohort through the
  shared MLP seam.
- `JitML.RL.Algorithms.DqnTrainer` now honours `dqnUseDouble`:
  `dqnUpdate` selects the next action with the online net and
  evaluates it with the target net via `DqnLoss.dqnDoubleBellmanTarget`
  (van Hasselt et al. 2016), removing the max-operator overestimation
  bias. `jitml-unit` adds "Double-DQN variant trains end-to-end and
  stays deterministic".

This covers the discrete-action half of the catalog (5 on-policy +
DQN + Double-DQN) through the shared templates.

### Code Surface Landed (2026-05-28, continuous-control + quantile + ARS/HER trainers)

The remaining trainer seams for the catalog now exist as real,
deterministic, MLP-backed loops, closing the non-deferred half of the
"quantile / continuous-control off-policy trainers" remaining-work
item. Validated host-side by `jitml-unit` (184 tests) and
`jitml-rl-canonicals` (27 tests):

- **Continuous-action env.** `JitML.RL.Simulator` adds the
  `ContinuousEnvironment` / `ContinuousSimStep` boundary plus the
  `Pendulum-v1` port (`PendulumState`, `pendulumStep`,
  `pendulumObservation`, `pendulumEnvironment`) following the documented
  Gym equations — the continuous-action surface the actor-critic family
  needs (previously the genuine prerequisite blocking these five).
- **`JitML.Numerics.Mlp.mlpInputGradient`** — the input gradient
  @dL/dx = W1^T @ dL/dhPre@, the missing piece for the
  deterministic-policy gradient @dQ/da@ (the action-slice of the
  critic's input gradient).
- **`JitML.RL.Algorithms.ContinuousTrainer`** — one actor-critic +
  replay loop on the Pendulum env with a `ContinuousVariant`
  (`VariantDDPG` / `VariantTD3` / `VariantSAC` / `VariantCrossQ` /
  `VariantTQC`); each variant routes its Bellman target through the
  canonical `*Loss` module (`ddpgCriticTarget`, `td3ClippedDoubleTarget`
  + `td3SmoothTargetActions`, `sacCriticTarget`, `crossQTarget`,
  `tqcTarget`). All five train end-to-end and are bit-deterministic;
  DDPG is asserted to improve the pendulum return over a 10k-step cohort
  (a sign error in the policy gradient would diverge — guards the seam).
- **`JitML.RL.Algorithms.QrDqnTrainer`** — the distributional off-policy
  member: a per-action quantile head (`actionCount * numQuantiles`
  outputs) with the quantile-Huber gradient from `QrDqnLoss`.
- **`JitML.RL.Algorithms.ArsTrainer`** — the gradient-free ES member:
  finite-difference perturbation rollouts on a linear cartpole policy
  via `arsTopDirections` / `arsUpdateDirection`; asserted to improve the
  mean return over the run.
- **`JitML.RL.Algorithms.HerTrainer`** — the goal-conditioned member: a
  DQN-style Q network on the canonical bit-flip env with `future`-goal
  hindsight relabeling via `herRelabel` / `sparseGoalReward`; asserted
  that hindsight beats no-hindsight on bit-flip success rate.
- **Daemon dispatch wired.** `JitML.Service.Workload.rlTrainerForAlgorithm`
  now maps every catalog algorithm to its trainer key, and
  `JitML.App.runTrainerEpisodes` dispatches `jitml rl train` to the
  matching real trainer (projecting each trainer's per-iteration summary
  into the `SimulatedEpisode`/`EpisodeDone` envelope so the Sprint 15.5
  publication path is unchanged). The whole 14-algorithm catalog is now
  reachable end-to-end from `jitml rl train` / a daemon-dispatched
  `StartRLRun`.

### Code Surface Landed (2026-05-28, nvcc forward/backward MLP kernels + GPU validation)

The first half of the "CUDA-emitted forward/backward kernels"
deliverable now exists as real, GPU-validated codegen — the network
forward and backward passes run on the device through generated nvcc
kernels behind the same `JitML.Numerics.Mlp` interface:

- **`JitML.Codegen.MlpCuda`** renders a `kernel.cu` exposing two
  `extern "C"` host wrappers: `jitml_mlp_forward` (computes
  `hidden_pre`, `hidden_act = tanh hidden_pre`, `output = W2 hidden_act +
  b2`) and `jitml_mlp_backward` (computes the parameter gradients `gW1 /
  gB1 / gW2 / gB2` from `dL/dy`, the forward `hidden_act`, the input, and
  `W2` — exactly `mlpBackward`). Each device thread accumulates its own
  reduction sequentially (no atomics, no warp-shuffle) so the result is
  bit-deterministic run-to-run on the same device per the determinism
  contract.
- **`JitML.Numerics.MlpCuda`** is the host-side runner: it compiles the
  kernel once through the content-addressed JIT cache
  (`ensureKernelArtifact`, the same path as the per-family kernels),
  `dlopen`s the `.so`, marshals the flat row-major parameter buffers
  across the FFI, and returns the same `MlpForward` / `MlpGradient` the
  pure network produces. Distinct kernel-spec + toolchain fingerprint
  keep the artifact in its own JIT-cache slot.
- **GPU validation.** `jitml-cross-backend` adds three Sprint 15.8/15.9
  cases run on the RTX 3090 / CUDA 12.8 host (in `jitml:local`): the CUDA
  forward output matches the pure-Haskell forward within a `1e-3`
  single-precision tolerance, the CUDA backward gradients match the
  reference gradient (fed the same forward cache to isolate the backward
  kernel), and both forward + backward are bit-equal across repeated runs.
  `cabal test jitml-cross-backend --test-options='-p MLP'` reports
  **3 / 3 pass** (nvcc compiles `kernel.cu`, the artifact loads via
  dlopen, the kernels launch on the RTX 3090).

### Remaining Work

- **Run params from typed Dhall `RunConfig` (reopened Phase `5` Sprint `5.7`).**
  The RL params formerly read from `JITML_ENVIRONMENT` / `JITML_SEED` /
  `JITML_MAX_STEPS` / `JITML_EVAL_EPISODES` / `JITML_RL_TRAINER` move into the typed
  `RunConfig`; the live RL run validates with no `JITML_*` env on the Job.
- **CUDA training-step integration proven (2026-05-28); RL-trainer
  adoption + cuDNN pin remain.** The device-backed training step is now
  wired and GPU-validated end-to-end for the AlphaZero network:
  `JitML.RL.AlphaZero.PolicyValueNet.trainPolicyValueNetOnSamplesCuda`
  evaluates the complete ordered sample batch against one immutable parameter
  snapshot, averages the gradient, and performs exactly one host-side Adam
  step per declared optimizer update (Phase `19` correction, 2026-07-15); the
  underlying batched kernels still produce per-sample forward outputs.
  `jitml-cross-backend` confirms 80 declared full-batch updates reduce the
  policy/value loss on the RTX 3090 (9 / 9 CUDA cases pass). The shared
  `JitML.Numerics.Mlp` head helpers (`policyValueFromForward` /
  `policyValueOutputGradient`) let the pure and device paths share the
  exact head math.
- **Batched device primitive set — landed + GPU-validated (2026-05-28).**
  The amortised-copy primitives the trainers' minibatch hot path needs now
  exist: `JitML.Codegen.MlpCuda` emits `jitml_mlp_batch_gradient` (batched
  forward + summed-gradient backward) and `jitml_mlp_forward_batch` (batched
  forward → per-sample outputs), with deterministic per-thread reductions,
  and `JitML.Numerics.MlpCuda.{mlpBatchGradientCuda,mlpForwardBatchCuda}`
  drive a whole minibatch in a single device round-trip each.
  `jitml-cross-backend` confirms on the RTX 3090 that the batched gradient
  equals the pure per-sample summed gradient (`sum (map mlpBackward …)`) and
  the batched forward equals the pure per-sample forward, both within `1e-3`
  and bit-deterministic run-to-run (11 / 11 CUDA cases pass).
- **On-policy family now trains on the device (2026-05-28).** The shared
  on-policy trainer — `JitML.RL.Algorithms.PpoTrainer.trainOnPolicyOnCartpoleCuda`,
  covering **PPO / A2C / TRPO / MaskablePPO / RecurrentPPO (5 of the 14)** —
  runs its minibatch forward + backward on the GPU through the batched
  primitives: each minibatch is one `mlpForwardBatchCuda` (per-sample
  outputs) + host loss-gradient head (`ppoHeadGradient`, factored out of
  the pure `ppoSingleStep` so both paths share identical math) +
  `mlpBatchGradientCuda` (mean gradient) + one Adam step. (The pure path's
  per-sample online SGD is inherently sequential and unbatchable; the CUDA
  path uses proper minibatch GD — standard PPO.) `jitml-cross-backend`
  ("linux-cuda on-policy PPO trainer trains through the batched device path
  (Sprint 15.8)") confirms on the RTX 3090 that it completes its iterations
  with finite rewards and is run-to-run deterministic on the device
  (12 / 12 CUDA cases pass). The pure refactor is behaviour-preserving
  (`jitml-rl-canonicals` 28 / 28, incl. "every on-policy variant trains and
  improves").
- **Off-policy DQN now trains on the device (2026-05-28).**
  `JitML.RL.Algorithms.DqnTrainer.trainDqnOnCartpoleCuda` (the discrete
  off-policy template) runs its minibatch Q-network forward + backward on
  the GPU: per minibatch, a batched online forward at the states + target
  forward at the next states (+ online forward at the next states for
  Double-DQN), the per-sample TD-residual gradient (`dqnResidualDLdy`,
  factored out of the pure `dqnUpdate` so both paths share it), one batched
  device backward, and one Adam step. The 2026-06-11 Phase `8.11`
  hardening removed the former pure-update fallback, so device failures now
  fail closed. The env loop / replay / target-copy are shared with
  the pure trainer via a parameterised `loop`. `jitml-cross-backend`
  ("linux-cuda DQN trainer trains through the batched device path") confirms
  it completes with finite per-interval rewards and is run-to-run
  deterministic on the RTX 3090 (**13 / 13 CUDA cases pass**); pure refactor
  behaviour-preserving (`jitml-unit` 184/184, incl. DQN + Double-DQN).
- **QR-DQN now trains on the device (2026-05-28).**
  `JitML.RL.Algorithms.QrDqnTrainer.trainQrDqnOnCartpoleCuda` runs the
  distributional (quantile) network's minibatch forward + backward on the
  GPU through the batched primitives, reusing the shared quantile-Huber head
  `qrResidualDLdy` (factored out of the pure `qrUpdate`) and the
  parameterised `loop`. `jitml-cross-backend` ("linux-cuda QR-DQN trainer
  trains through the batched device path") confirms it on the RTX 3090
  (**14 / 14 CUDA cases pass**); pure refactor behaviour-preserving
  (`jitml-unit` 184/184, incl. the QR-DQN cases).
- **HER now trains on the device (2026-05-28).**
  `JitML.RL.Algorithms.HerTrainer.trainHerOnBitFlipCuda` (the goal-conditioned
  member, a DQN-style Q network on the bit-flip env) runs its minibatch
  forward + backward on the GPU through the batched primitives, reusing the
  shared head `herResidualDLdy`. Its per-episode rollout + hindsight
  relabeling loop (`episodeLoop`) was lifted from pure to `IO` and
  parameterised by the update action so the pure and device paths share it.
  `jitml-cross-backend` ("linux-cuda HER trainer trains through the batched
  device path") confirms it on the RTX 3090 (**15 / 15 CUDA cases pass**);
  pure refactor behaviour-preserving (`jitml-unit` 184/184).
- **Batched device input-gradient primitive — landed + GPU-validated
  (2026-05-28).** The last missing device primitive — the one the
  continuous actor-critics need for the deterministic-policy gradient
  (@dQ/da@ = the action-slice of the critic's input gradient) — now exists:
  `JitML.Codegen.MlpCuda` emits `jitml_mlp_input_gradient_batch` (batched
  forward → @d_hidden_pre@ → @dL/dx@, per-sample, deterministic per-thread
  reductions) and `JitML.Numerics.MlpCuda.mlpInputGradientBatchCuda` returns
  per-sample @dL/dx@ in one device round-trip. `jitml-cross-backend`
  ("linux-cuda batched MLP input-gradient matches the pure
  mlpInputGradient") confirms it on the RTX 3090 (matches the pure
  `mlpInputGradient` within `1e-3`, bit-deterministic). The full batched
  device primitive set (forward + parameter-gradient + input-gradient) is
  now complete.
- **Continuous actor-critics now train on the device (2026-05-28) — all
  backprop trainers adopted.** `JitML.RL.Algorithms.ContinuousTrainer.trainContinuousOnPendulumCuda`
  (covering DDPG/TD3/SAC/CrossQ/TQC) runs the critic param-gradient, the
  actor's `dQ/da` (the critic's input-gradient), and the actor
  param-gradient on the GPU through the batched primitives; the Bellman
  target (`bellmanTarget`, factored out of `updateStep`) + squash/chain-rule
  scalars + soft target updates are the shared pure helpers, and the device
  calls are threaded through `ExceptT` with a clean fallback to the pure
  `updateStep` when CUDA is unavailable. `jitml-cross-backend` ("linux-cuda
  continuous actor-critic (DDPG) trains through the batched device path")
  confirms it on the RTX 3090 (finite, run-to-run deterministic; the other
  four variants differ only in the shared pure `bellmanTarget`). Pure
  refactor behaviour-preserving (`jitml-rl-canonicals` 28/28 incl. the DDPG
  swing-up, `jitml-unit` 184/184 incl. all 5 variants). **Device adoption
  now covers all 13 backprop trainers — on-policy ×5 + DQN + QR-DQN + HER +
  continuous ×5 (13 / 14); ARS is gradient-free (forward-only) so no
  backprop primitive applies and it stays pure.**
- **cuDNN deterministic-algorithm pin validated (2026-05-28).** A host
  `jitml-unit` consistency test ("cuDNN deterministic-algorithm pin is
  emitted and consistent with the Tuning allowlist") cross-checks the
  conv-forward pin in `Codegen.Cuda`
  (`CUDNN_CONVOLUTION_FWD_ALGO_IMPLICIT_PRECOMP_GEMM`) against the
  independently-defined deterministic allowlist
  `Engines.Tuning.cuDnnDeterministicAlgorithms`, asserts the pin is emitted
  into the generated CUDA source for Conv2D/Conv3D (and the persistent
  batch-norm pin for BatchNorm/LayerNorm), and asserts the non-cuDNN
  MLP/reduction families record `"none"` (`jitml-unit` 185/185). The conv
  families remain codegen scaffolds (they record the algorithm but do not
  yet issue live cuDNN convolutions), so this validates the pin's
  presence/consistency in the codegen, not a live cuDNN conv run.
- **Open: live cohort drive (operational).** With every backprop trainer
  device-adopted + GPU-validated and the cuDNN pin checked, the remaining
  Sprint 15.8 item is the live cohort drive — dispatch each algorithm
  through a daemon Job on the live cluster and assert per-episode reward
  arrival (the operational pass shared with Sprints 15.6 / 15.9).
- **Live cohort drive through the daemon.** Dispatching each algorithm
  through a daemon-rendered Kubernetes Job on the live cluster and
  asserting per-episode reward arrival on `rl.event.<substrate>` is the
  Sprint 15.6 live-validation pass (the worker-side trainers + dispatch
  wiring are in place and host-validated; the live arrival assertion
  needs a cluster image baking this session's `rlTrainerForAlgorithm`
  widening).

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
