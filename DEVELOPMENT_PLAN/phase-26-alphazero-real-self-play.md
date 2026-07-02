# Phase 26: AlphaZero Real Self-Play Per Game

**Status**: Blocked
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [development_plan_standards.md](development_plan_standards.md), [phase-25-real-rl-algorithms-and-environments.md](phase-25-real-rl-algorithms-and-environments.md), [../documents/engineering/product_completion_contract.md](../documents/engineering/product_completion_contract.md), [../documents/engineering/training_workloads.md](../documents/engineering/training_workloads.md), [../documents/engineering/determinism_contract.md](../documents/engineering/determinism_contract.md)
**Generated sections**: none

> **Purpose**: Every documented adversarial game trains a real AlphaZero
> policy-value network through MCTS-guided self-play with persistent search
> state and converges its measured arena win-rate on `linux-cpu`.

## Phase State

⏸️ **Blocked by** Phase `25`.

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

## Sprint 26.1: Per-Game Self-Play [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Phase `25`
**Implementation**: `src/JitML/RL/AlphaZero/SelfPlay.hs`, `src/JitML/RL/AlphaZero/Mcts.hs`, `src/JitML/RL/AlphaZero/PolicyValueNet.hs`, `src/JitML/Product/Matrix.hs`
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

### Remaining Work

- Wire each game's self-play generation to the network forward pass and the
  visit-count/outcome training targets.
- Bind the persistent exploration cache across moves for all four games and prove
  its `(seed, episode-history)` reconstruction.
- Add the four `AlphaZero` product rows to the typed matrix.

## Sprint 26.2: Arena Convergence + Evidence [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Sprint `26.1`
**Implementation**: `test/rl-canonicals/Main.hs`, `src/JitML/Test/RowAssertions.hs`, `src/JitML/Checkpoint/Format.hs`, `src/JitML/Checkpoint/Store.hs`
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

### Remaining Work

- Collect init/final network hashes and generation counts into each game's
  checkpoint manifest.
- Add the per-game arena-win-rate convergence assertions and the same-seed
  determinism reruns.
- Emit and register the four inference-eligible AlphaZero artifacts and their row
  assertions.

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
