# Phase 114: Real MCTS Tree Search with Substrate-Backed Leaf Evaluation

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Real MCTS Tree Search with Substrate-Backed Leaf Evaluation. Single-session phase migrated from legacy Sprint 9.10 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 114.1: Real MCTS Tree Search with Substrate-Backed Leaf Evaluation [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/RL/AlphaZero/Mcts.hs`
(`runSearchWithPrior`, `runSearchWithPriorIO`, position-aware oracle),
`src/JitML/RL/AlphaZero/PolicyValueNet.hs` (`netOracleFactory`,
`networkPriorOracleWithDevice`, `mctsVisitDistribution`,
`mctsVisitDistributionWithDevice`); deletes
`src/JitML/RL/AlphaZero/Arena.hs` and `src/JitML/RL/AlphaZero/EnginePrior.hs`
**Docs to update**: `../documents/engineering/training_workloads.md`, `system-components.md`

### Objective

Replace the one-ply MCTS bandit with a real tree search — selection (descend
root→leaf by UCB), expansion (position priors at the leaf), evaluation (the
network **value head** on the device at the leaf position), and backpropagation
(sign-flipped value up the path) — and delete the dead `Arena.playArena` and
`EnginePrior` modules. Owns the AlphaZero search slice of
[Exit Definition](README.md#exit-definition) item 6.

### Deliverables

- The `PriorOracle` is generalised to be **position-dependent** (it receives the
  descended position / move history), so the search evaluates the network at
  each expanded node rather than only the root. `defaultPriorOracle` and the
  mechanics tests keep a neutral position-independent shim.
- `simulateWithPrior` performs one real MCTS simulation: UCB selection down to an
  unexpanded leaf, expansion with the position priors, value-head leaf
  evaluation, and backup with the adversarial sign flip; `runSearchWithPrior`
  runs `mctsSimulations` such simulations over the persistent tree (the
  transposition table keys positions). `runSearchWithPriorIO` is the
  substrate-backed analogue: leaf evaluation may compile/load/execute the
  selected JIT `MlpDevice`, and any device error returns `Left` rather than
  falling back to pure evaluation.
- `netOracleFactory` in `PolicyValueNet` supplies the position-aware policy +
  value oracle from the real network forward; `networkPriorOracleWithDevice` /
  `mctsVisitDistributionWithDevice` run the same leaf policy/value evaluation
  through the substrate JIT device. The existing determinism + visit-target
  property tests in `jitml-rl-canonicals` hold (run-to-run determinism,
  non-negative, sums to 1, search concentrates beyond uniform).
- `Arena.playArena` (SHA/LCG outcome generator, no caller) and the `EnginePrior`
  Dense2D prior module are deleted; the real arena lives in `PolicyValueNet`
  self-play generation.

### Validation

- `docker compose run --rm jitml cabal test jitml-rl-canonicals --linux-cpu`
  (MCTS visit-target + network-self-play determinism through real tree search).
- `rg -n 'Arena\.playArena|EnginePrior' src test` returns nothing outside the
  ledger.
- `jitml check-code` + `jitml docs check` green inside `jitml:local`.

### Current Validation State

Landed and validated (2026-06-10):

- `Mcts.hs` is a real recursive tree search — PUCT selection down to an
  unexpanded leaf, expansion with the position priors, value-head leaf
  evaluation, and sign-flipped backup up the path (depth-bounded by
  `mctsMaxDepth`). `PriorOracle` is now position-aware (`[Int] -> NodeEval`);
  `PolicyValueNet.netOracleFactory` roots it at the search position.
- `Arena.hs` and `EnginePrior.hs` are deleted and removed from the cabal
  exposed-modules; `rg 'Arena.playArena|EnginePrior' src test` is clean.
- Host: `jitml-unit` 196/196 (migrated MCTS oracle case, before the 2026-06-11
  rollout-helper deletion), `jitml-rl-canonicals` real-search determinism,
  legality, and valid search-derived visit distribution that concentrates
  beyond uniform. Container: `check-code: ok`, `jitml test
  jitml-rl-canonicals --linux-cpu` **27/27 PASS** and `jitml test
  jitml-rl-canonicals --linux-cuda` **27/27 PASS** on 2026-06-11. The live
  AlphaZero generation drive also passed in both full linux-cpu and linux-cuda
  integration suites (**67/67** each).
- Continuation validation (2026-06-11): `docker compose run --rm jitml jitml
  test jitml-rl-canonicals --linux-cpu` → **28/28 PASS**, including
  `MCTS visit-count target evaluates leaves through the substrate JIT device
  (Sprint 9.10 --linux-cpu): OK (0.02s)`. The device-backed path uses
  `runSearchWithPriorIO` plus `PolicyValueNet.mctsVisitDistributionWithDevice`
  and fails closed on device errors.

### Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
