# Phase 26: AlphaZero Real Self-Play Per Game

**Status**: Done
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [development_plan_standards.md](development_plan_standards.md), [phase-25-real-rl-algorithms-and-environments.md](phase-25-real-rl-algorithms-and-environments.md), [../documents/engineering/product_completion_contract.md](../documents/engineering/product_completion_contract.md), [../documents/engineering/training_workloads.md](../documents/engineering/training_workloads.md), [../documents/engineering/determinism_contract.md](../documents/engineering/determinism_contract.md)
**Generated sections**: none

> **Purpose**: Every documented adversarial game trains a real AlphaZero
> policy-value network through MCTS-guided self-play with persistent search
> state and converges its measured arena win-rate on `linux-cpu`.

## Phase State

✅ **Done**. Phase `25` is Done, Sprint `26.1` completed real per-game
self-play generation, product-row registration, game-specific MCTS visit
targets, and persistent cache evidence, and Sprint `26.2` completed arena
convergence, same-seed evidence, row evidence, and inference-eligible
checkpoint artifacts for every canonical AlphaZero game.

**Validation substrate**: `linux-cpu` only.

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

### Remaining Work

None.

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

### Remaining Work

None.

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
