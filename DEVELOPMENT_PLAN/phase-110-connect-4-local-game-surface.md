# Phase 110: Connect 4 Local Game Surface

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Connect 4 Local Game Surface. Single-session phase migrated from legacy Sprint 9.6 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 110.1: Connect 4 Local Game Surface [✅ Done]

**Status**: Done
**Owned obligations after refactor**: code-surface — the real rule
engines for Othello (8-direction capture-flip), Hex (border-to-border
connectivity), and Gomoku (line-of-five) closed on 2026-05-24 in
`src/JitML/RL/AlphaZero.hs` (`othelloLegalMove` / `othelloFlipsFor` /
`othelloBoardAfter`; `hexLegalMove` + `hexConnected`; `gomokuLegalMove`
+ `hasGomokuLine`); `selfPlayTranscriptFor` advances past illegal
candidates via `nextLegalMove`. The JIT-backed network position
evaluation that consumes these rules is owned by Phase `15`
Sprint `15.9`.
**Implementation**: `src/JitML/RL/AlphaZero.hs`,
`src/JitML/Web/Contracts.hs`, `test/rl-canonicals/Main.hs`
**Docs to update**: `documents/engineering/training_workloads.md`

### Objective

Land the current Connect 4 local game surface, canonical adversarial-game
catalog, and corresponding browser-contract endpoint metadata.

### Deliverables

- `src/JitML/RL/AlphaZero.hs` names the local game `connect4`.
- `applyMove` normalizes moves into legal Connect 4 columns.
- `src/JitML/Web/Contracts.hs` includes the `Connect4Move` endpoint metadata
  used by the frontend scaffold.
- `canonicalGames` lists Connect 4, Othello, Hex, and Gomoku as local
  `PerfectInformationGame` metadata rows.
- `initialOthello`, `initialHex`, and `initialGomoku` plus per-game
  `applyMove` dispatch are checked in.
- `PerfectInformation` admits all four canonical games through
  `gameTwoHeadedNetwork` and `gameActionCount`.
- Per-game transcript determinism is asserted by `jitml-rl-canonicals`
  as run-to-run equality (`selfPlayTranscriptFor` is invoked twice
  in-process and the outputs are compared bit-for-bit) plus
  rule-conformance properties (every emitted move is legal under the
  per-game `applyMove`, terminal states match `gameTerminal`). No
  `test/golden/alphazero/<game>-transcript.txt` files are committed
  per [../README.md → Snapshot targets → Numerical-fixture
  prohibition](../README.md#snapshot-targets) — MCTS visit counts and
  prior-evaluator output depend on substrate float behavior and
  hardcoding a host's transcript would lock that host's RNG / FP order
  into the repository as authoritative.

### Validation

1. `cabal test jitml-rl-canonicals` validates the Connect 4 move bounds.
2. Local validation re-runs the per-game self-play transcript twice
   in-process and asserts bit-identity between the two outputs plus
   rule-conformance properties — no committed transcript fixtures.
3. Transferred live validation: Othello, Hex, and Gomoku graduate from the
   deterministic local rules to full rule-complete position evaluators
   and JIT-backed network forward passes.

### Remaining Work

- The real rule engines in `src/JitML/RL/AlphaZero.hs` closed on
  2026-05-24: `othelloLegalMove` / `othelloFlipsFor` /
  `othelloBoardAfter` cover the 8-direction capture-flip rule;
  `hexLegalMove` plus `hexConnected` (border-to-border DFS using the
  six standard hex neighbours plus parallelogram diagonals) covers
  Hex; `gomokuLegalMove` plus `hasGomokuLine` (line-of-five
  detection) covers Gomoku. `selfPlayTranscriptFor` advances past
  illegal candidates via `nextLegalMove`. The per-game self-play
  helpers are exercised by run-to-run equality plus rule-conformance
  properties — no per-game transcript files are committed per
  [../README.md → Snapshot targets → Numerical-fixture
  prohibition](../README.md#snapshot-targets).
- JIT-backed network position evaluation that consumes these rule
  engines is owned by
  [phase-15-linux-cuda-and-cluster-closure.md](README.md#legacy-to-new-phase-map)
  Sprint `15.9`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
