# Phase 253: Arena Convergence + Evidence

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Arena Convergence + Evidence. Single-session phase migrated from legacy Sprint 26.2 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 253.1: Arena Convergence + Evidence [✅ Done]

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
([phase-32-external-truth-realness-harness.md](README.md#legacy-to-new-phase-map))
must fail the all-draw / never-win network (a known fake) against the arena bar,
and the per-model convergence suite `jitml-model-convergence`
([phase-33-per-model-convergence-and-inference-tests.md](README.md#legacy-to-new-phase-map))
asserts `assertAlphaZeroRowEvidence` with a strict win-margin over real
multi-generation self-play.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
