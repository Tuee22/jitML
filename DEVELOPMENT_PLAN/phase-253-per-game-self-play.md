# Phase 253: Per-Game Self-Play

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Per-Game Self-Play. Single-session phase migrated from legacy Sprint 26.1 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 253.1: Per-Game Self-Play [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/RL/AlphaZero.hs`, `src/JitML/RL/AlphaZero/SelfPlay.hs`, `src/JitML/RL/AlphaZero/Mcts.hs`, `src/JitML/RL/AlphaZero/PolicyValueNet.hs`, `src/JitML/Product/Matrix.hs`, `src/JitML/App.hs`, `src/JitML/CLI/Spec.hs`, `test/rl-canonicals/Main.hs`
**Docs to update**: `../documents/engineering/training_workloads.md`, `../documents/engineering/product_completion_contract.md`

### Objective

Connect 4, Othello, Hex, and Gomoku each run real self-play generations through
the shared `PerfectInfoGame` interface: MCTS priors and leaf values are read from
the policy-value network forward pass, the per-move visit-count distribution is
the policy training target, the game outcome is the value training target, and
the Monte Carlo exploration cache persists across the moves of a single game.

### Deliverables

- Each of the four games instantiates the `PerfectInfoGame` interface and runs a
  fixed-budget self-play generation whose MCTS root priors and node leaf values
  come from `AlphaZeroNet` forward passes, not from a scaffold or uniform prior.
- The self-play buffer stores `(canonicalState, mctsVisits, valueTarget)` triples
  plus each game's board symmetries, and the training step regresses the policy
  head onto `softmax(visits)` and the value head onto the game outcome.
- Persistent MCTS state is preserved between moves of the same game and is a
  deterministic function of `(seed, episode-history)`, so re-executing an episode
  under the same seed reconstructs the exploration cache exactly.
- `src/JitML/Product/Matrix.hs` carries one `AlphaZero`-family `ProductRow` per
  game with `implementation`, `experimentConfig`, and `trainingEvidence` fields
  pointing at the real self-play path.
- Root Dirichlet noise per game is drawn from `splitSeed masterSeed gameIndex`,
  and MCTS argmax tie-breaking is by lowest action index.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-rl-canonicals --linux-cpu
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml check-code
```

Validated on 2026-07-02: focused Sprint `26.1` RL canonical test passed 1/1,
focused AlphaZero canonical group passed 7/7, `jitml-rl-canonicals
--linux-cpu` passed 36/36, `jitml-unit --linux-cpu` passed 274/274, and
`jitml check-code` passed after the Phase `26.1` closure and Sprint `26.2`
activation status updates.

### Closure Evidence

2026-07-05 realness-audit finding, closed 2026-07-06. The `PerfectInfoGame` instances, the MCTS
tree search, and the four games' board rules are real and stay closed; the unmet
Exit-Definition obligation is that the product publish path does not execute a
real fixed-budget self-play generation:

- **Full `maxPlies` per game.** `src/JitML/App.hs`
  `trainAndPublishAlphaZeroProductRow` (~line 6268) caps games at `maxPlies = 4`,
  so no game reaches a terminal outcome and every self-play trajectory truncates
  to a draw with a zero value target. Restore each game's full `maxPlies` so
  self-play produces real win/loss value targets.
- **The declared multi-generation / per-move simulation budget.** The path runs a
  single generation instead of the declared 64–128 generations at 128–256
  simulations per move; execute the declared budget so priors and leaf values
  drive real learned self-play.

Negative-control validation that closes it: the per-model convergence suite
`jitml-model-convergence`
([phase-33-per-model-convergence-and-inference-tests.md](README.md#legacy-to-new-phase-map))
runs real multi-generation self-play with full `maxPlies` and asserts
`assertAlphaZeroRowEvidence`, and the negative-control suite
`jitml-negative-controls`
([phase-32-external-truth-realness-harness.md](README.md#legacy-to-new-phase-map))
requires the truncated single-generation all-draw configuration to fail.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
