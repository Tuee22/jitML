# Phase 26: AlphaZero Real Self-Play Per Game

**Status**: Done
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [development_plan_standards.md](development_plan_standards.md), [phase-25-real-rl-algorithms-and-environments.md](phase-25-real-rl-algorithms-and-environments.md), [../documents/engineering/product_completion_contract.md](../documents/engineering/product_completion_contract.md), [../documents/engineering/training_workloads.md](../documents/engineering/training_workloads.md), [../documents/engineering/determinism_contract.md](../documents/engineering/determinism_contract.md)
**Generated sections**: none

> **Purpose**: Every documented adversarial game trains a real AlphaZero
> policy-value network through MCTS-guided self-play with persistent search
> state and converges its measured arena win-rate on `linux-cpu`.

## Phase State

✅ **Done** (reclosed 2026-07-06 after the 2026-07-05 realness audit). The
AlphaZero product path now uses full per-game horizons, declared multi-generation
self-play budgets, device-backed policy/value updates, MCTS-guided arena play,
and a strict arena threshold that rejects the all-draw `0.5` sentinel. Validation:
focused `AlphaZero per-game arena evidence` passed **1 / 1**, full
`jitml-rl-canonicals` passed **37 / 37**, and `jitml-negative-controls` passed
**3 / 3** on `linux-cpu`.

**Validation substrate**: `linux-cpu` only.

### 2026-07-05 realness-audit finding, closed 2026-07-06

The realness audit found the AlphaZero product path passes its arena bar without
ever winning a game:

- `src/JitML/App.hs` `trainAndPublishAlphaZeroProductRow` (~line 6268) runs a
  **single** generation with `maxPlies = 4`, so no game can reach a terminal win
  and every self-play and arena game truncates to a draw. The declared 64–128
  generation / 128–256 simulation budget is never executed.
- With every arena game a draw, `arenaWinRateAgainstUniformFrom` returns exactly
  `0.5` (`src/JitML/RL/AlphaZero/PolicyValueNet.hs:654,684`), and
  `passesAlphaZeroArena` accepts `>= 0.50` **inclusive**
  (`src/JitML/RL/ConvergenceThresholds.hs:266,270`), so a network that never wins
  "passes".
- The Othello, Hex, and Gomoku demo checkpoints from `policyValuePanelDemo`
  (~line 6659) are untrained random-init networks, not trained per-game
  checkpoints.

What stayed real: the MCTS tree search and the four games' board rules. The
closed defect was the product path: full `maxPlies` per game, the declared
multi-generation / per-move simulation budget, a strict win-margin arena
threshold that rejects the all-draw `0.5` pass, and trained product artifacts are
now wired into the product path and validated by the `jitml-negative-controls`
and `jitml-rl-canonicals` gates.

## Objective

Connect 4, Othello, Hex, and Gomoku are each row-complete AlphaZero product
rows. The MCTS engine and the two-headed policy-value network are already real;
this phase makes the self-play loop close for every game rather than for the
canonical Connect 4 entry alone. Each game runs real self-play generations whose
priors and leaf values come from the network forward pass, trains against the
visit-count distribution and the game outcome, carries persistent MCTS state
between the moves of a game, and records init/final network hashes, generation
count, and a measured arena win-rate that clears the declared convergence bar and
is bit-identical on rerun under the same seed. Each game writes an
inference-eligible checkpoint artifact for the demo and inference read paths.

## Sprint 26.1: Per-Game Self-Play [✅ Done]

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
([phase-33-per-model-convergence-and-inference-tests.md](phase-33-per-model-convergence-and-inference-tests.md))
runs real multi-generation self-play with full `maxPlies` and asserts
`assertAlphaZeroRowEvidence`, and the negative-control suite
`jitml-negative-controls`
([phase-32-external-truth-realness-harness.md](phase-32-external-truth-realness-harness.md))
requires the truncated single-generation all-draw configuration to fail.

## Sprint 26.2: Arena Convergence + Evidence [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/App.hs`, `src/JitML/Product/Matrix.hs`, `src/JitML/Test/RowAssertions.hs`, `src/JitML/Checkpoint/Format.hs`, `src/JitML/Checkpoint/Store.hs`, `test/rl-canonicals/Main.hs`
**Docs to update**: `../documents/engineering/determinism_contract.md`, `../documents/engineering/product_completion_contract.md`

### Objective

Each game records its initial and final network hashes and generation count,
measures an arena win-rate against the baseline opponent that clears
`JitML.RL.ConvergenceThresholds.alphaZeroArenaThreshold`, reproduces that result
bit-identically on rerun under the same seed, and writes an inference-eligible
checkpoint artifact.

### Deliverables

- Each game's canonical case records a deterministic initial-parameter hash, a
  distinct final-parameter hash, and the self-play generation count in the
  checkpoint manifest, proving learned state changed.
- The measured arena win-rate for Connect 4, Othello, Hex, and Gomoku clears the
  declared `alphaZeroArenaThreshold`; the assertion is the threshold, not a stored
  per-substrate empirical fixture.
- Two same-seed `linux-cpu` runs of each game produce bit-identical self-play
  game sequences and visit counts, per the determinism contract.
- `src/JitML/Test/RowAssertions.hs` asserts each `AlphaZero` row carries
  `trainingEvidence`, `checkpointEvidence` (a `CompletedTraining` witness plus
  convergence metrics), and `deviceEvidence`, and names any missing row.
- Each game writes an inference-eligible checkpoint through
  `src/JitML/Checkpoint/Store.hs` that the demo and inference read paths select.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-rl-canonicals --linux-cpu
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

Validated on 2026-07-02: focused Sprint `26.2` RL canonical test passed 1/1,
`jitml-rl-canonicals --linux-cpu` passed 37/37, `jitml-unit --linux-cpu`
passed 274/274, `jitml docs generate` reported no changes, `jitml docs check`
passed, and `jitml check-code` passed.

### Closure Evidence

2026-07-05 realness-audit finding, closed 2026-07-06. The arena "pass" was vacuous because no
game is ever won, and the demo checkpoints are untrained:

- **Strict win-margin arena threshold (no 0.5-draw pass).** When every arena
  game truncates to a draw, `arenaWinRateAgainstUniformFrom` returns exactly
  `0.5` (`src/JitML/RL/AlphaZero/PolicyValueNet.hs:654,684`), and
  `passesAlphaZeroArena` accepts `>= 0.50` **inclusive**
  (`src/JitML/RL/ConvergenceThresholds.hs:266,270`), so a network that never wins
  clears the bar. Replace the inclusive `0.5` threshold with a strict win-margin
  bar that rejects an all-draw result.
- **Trained per-game demo checkpoints.** The Othello, Hex, and Gomoku demo
  checkpoints written by `policyValuePanelDemo` (~line 6659) are untrained
  random-init networks. Write trained, inference-eligible per-game checkpoints
  that the demo and inference read paths select.

Negative-control validation that closes it: the negative-control suite
`jitml-negative-controls`
([phase-32-external-truth-realness-harness.md](phase-32-external-truth-realness-harness.md))
must fail the all-draw / never-win network (a known fake) against the arena bar,
and the per-model convergence suite `jitml-model-convergence`
([phase-33-per-model-convergence-and-inference-tests.md](phase-33-per-model-convergence-and-inference-tests.md))
asserts `assertAlphaZeroRowEvidence` with a strict win-margin over real
multi-generation self-play.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/training_workloads.md` — the real AlphaZero self-play
  loop per game, persistent MCTS state, and the visit-count/outcome targets.
- `documents/engineering/determinism_contract.md` — same-seed self-play
  bit-identity and arena-threshold convergence for all four games.
- `documents/engineering/product_completion_contract.md` — AlphaZero rows as
  row-complete product entries with training, checkpoint, and device evidence.

**Product docs to create/update:**
- `README.md` — AlphaZero self-play and the canonical adversarial games status
  across Connect 4, Othello, Hex, and Gomoku.

**Cross-references to add:**
- Link this phase from the AlphaZero control docs and the canonical adversarial
  games section in `README.md`.
