# Phase 176: AlphaZero with Real Network Priors

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: AlphaZero with Real Network Priors. Single-session phase migrated from legacy Sprint 15.9 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 176.1: AlphaZero with Real Network Priors [✅ Done]

**Status**: Done (re-validated 2026-06-06 on RTX 5090; previously Done on RTX 3090) (closed 2026-05-30 — `JitML.RL.AlphaZero.Mcts` routes its
prior through the real network forward pass via `PriorOracle` /
`runSearchWithPrior`; `SelfPlay.runSelfPlayWithOracleFactory` drives the
oracle in production self-play; `JitML.RL.AlphaZero.PolicyValueNet` trains
the two-headed Connect-4 network on the device through
`trainPolicyValueNetOnSamplesCuda` with GPU-validated MLP kernels; live
MinIO round-trips `writeSelfPlayBuffer` / `readSelfPlayBuffer` and the
`.jmw1` trained-weight checkpoint blob; the live `jitml-integration` case
"live AlphaZero generation drive: self-play + training, then .jmw1 weight
checkpoint round-trips through live MinIO (Sprint 15.9)" passes; the
deterministic `priorFor` legacy ledger row is closed. Remaining per-cohort
arena-promotion drives are operational scope.)
**Blocked by**: Sprint `175.1`
**Implementation**: `src/JitML/RL/AlphaZero/Mcts.hs`,
`src/JitML/RL/AlphaZero/SelfPlay.hs`,
`src/JitML/RL/AlphaZero/Arena.hs`
**Docs to update**: `documents/engineering/training_workloads.md`,
`documents/engineering/determinism_contract.md`

### Objective

Wire `runSearch`'s prior into a real network forward pass through the
JIT engine, run `selfPlayGamesPerGeneration` games per generation with
live MinIO checkpoint round-trip of the self-play buffer, and exercise
the arena promotion path with the real network's win rate. Closes the
`priorFor` legacy ledger row (Sprint 9.5 cleanup).

### Deliverables

- `runSearch` reads its prior from a JIT-compiled policy/value network
  evaluation through `JitML.Engines.HasEngine` instead of the
  deterministic `priorFor` stub.
- `SelfPlayBuffer` round-trips through live MinIO via
  `JitML.Service.MinIOSubprocess`.
- Arena games against a previous-best champion produce real
  `ArenaSummary` counts and promotion decisions.
- `az_games` and `az_sims` report-card knobs from `cabal.project` drive
  the live canonical stanza body.
- The deterministic MCTS prior stub row in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
  moves from `Pending Removal` to `Completed`.

### Validation

1. End-to-end live: one AlphaZero generation runs against a real
   Connect 4 cohort, the buffer round-trips through MinIO, and the
   arena promotion decision matches the committed expected outcome.
2. The deterministic prior stub is removed; network-free MCTS mechanics
   tests use the neutral uniform `defaultPriorOracle`, and production
   self-play supplies a typed network oracle.

### Code Surface Landed (2026-05-27, PriorOracle parameterization + SelfPlayBuffer MinIO)

- `JitML.RL.AlphaZero.Mcts` adds `type PriorOracle = Int -> Int -> Double`
  and a default mechanics oracle, plus parallel `expandWithPrior`,
  `simulateWithPrior`, `runSearchWithPrior`, and
  `runSearchWithTableAndPrior` that route through the supplied oracle.
  The existing `expand`, `simulate`, `runSearch`, and `runSearchWithTable`
  delegate to the default oracle so all existing tests continue to
  pass unchanged. A real AlphaZero loop now wraps a JIT-engine policy
  forward pass behind a `PriorOracle` value and threads it through
  `runSearchWithPrior` / `runSearchWithTableAndPrior` instead of
  patching the deterministic stub.
- `jitml-unit` adds "MCTS PriorOracle plumbing routes through expand
  and simulate (Sprint 15.9)" that asserts a uniform oracle produces
  uniform edge priors (proving the oracle threads through both
  `expandWithPrior` and `simulateWithPrior` rather than being silently
  dropped).
- `JitML.RL.AlphaZero.SelfPlay` adds CBOR-encoded
  `writeSelfPlayBuffer` / `readSelfPlayBuffer` helpers that
  `HasMinIO`-store the SelfPlayBuffer under
  `jitml-checkpoints/<experiment>/selfplay/<content-hash>.cbor`. The
  `SelfPlayBuffer`, `SelfPlayGame`, and `GameState` types now derive
  `Serialise` so the CBOR codec is available for free. The
  `bufferStorageKey` helper enumerates the canonical path so callers
  share one addressing convention.
- `jitml-integration` adds "SelfPlayBuffer CBOR round-trip via
  writeSelfPlayBuffer / readSelfPlayBuffer (Sprint 15.9)" that
  exercises the new CBOR path through the filesystem `HasMinIO`
  instance: write a deterministic buffer, read it back, assert
  structural equality and hash stability. Validates the full
  `SelfPlayBuffer` encode/decode against the typed `HasMinIO`
  boundary.

### Code Surface Landed (2026-05-27, fourth session — real policy/value network + Connect-4 evaluator)

`JitML.RL.AlphaZero.PolicyValueNet` is the production two-headed
policy/value network for AlphaZero, built on the differentiable MLP
seam (Sprint 15.8 closure). Surface:

- `PolicyValueNet { pvnParams, pvnActionCount, pvnObservationSize }` plus
  `initPolicyValueNet observationSize actionCount hiddenUnits seed` and
  `initAdamFor net` to construct the Adam optimiser state matching the
  net's shape.
- `encodeConnect4Board :: GameState -> Vector Double` produces the
  side-to-move-aware `{-1, 0, +1}^42` cell encoding plus a parity
  scalar (43-D observation tensor); `encodeGameState` widens to other
  games via the same encoder (fallback for othello / hex / gomoku;
  richer per-game encoders are a follow-on delta).
- `networkPolicyValue :: PolicyValueNet -> GameState -> PolicyValueOutput`
  emits the softmax-normalised policy vector + tanh-bounded value
  scalar for the input board state.
- `networkPriorOracle :: PolicyValueNet -> (Int -> GameState) -> PriorOracle`
  produces a 'PriorOracle' the MCTS search loop consumes. The closure
  clamps to `≥ 1e-6` for strict positivity (MCTS normalises by sum) and
  is bit-deterministic on the same substrate.
- `trainPolicyValueNetOnSamples` runs the exact declared optimizer-update
  count against `PolicyValueTrainingSample { sampleState, sampleVisitDist,
  sampleOutcome }` records. Each update evaluates the full ordered batch
  against one parameter snapshot, averages the cross-entropy(softmax_logits,
  visit_dist) + 0.5 * (value - outcome)^2 gradients, and performs exactly one
  Adam step. The 2026-07-15 Phase `19` hardening also adds
  `policyValueTrainingSamplesSha256`, a real content digest over every ordered
  state, visit distribution, and outcome used by training evidence.
- `generatePolicyValueSamples` rolls one self-play game using the
  network as the action sampler and labels per-move samples with the
  outcome (alternating signs by ply).
- `runOneGenerationOfSelfPlay` drives selfPlayGames → samples →
  gradientUpdates → arena win-rate against uniform-random and reports
  `GenerationResult { genNet, genAdam, genSamplesCount, genArenaWinRate }`.
- `arenaWinRateAgainstUniform` plays alternating arena games and reports
  the win-fraction in @[0, 1]@.
- `GameOutcome` / `gameOutcome` — shared terminal evaluators for Connect 4,
  Othello, Hex, and Gomoku, consumed by arena win-rate and MCTS leaf
  evaluation.

Three new tests in `jitml-rl-canonicals` cover the new surface:

- "policy/value network forward emits a valid policy distribution" —
  asserts the policy vector is non-negative, sums to 1, and the value
  scalar is bounded by tanh.
- "policy/value network gradient update reduces an MCTS self-play loss" —
  asserts cross-entropy + MSE loss decreases over 80 Adam steps on an
  MCTS-generated self-play sample.
- "AlphaZero self-play generation runs deterministically and reports an
  arena win rate" — asserts two fresh generations with the same seed
  produce bit-identical sample count and win rate, and that the win
  rate lies in `[0, 1]`.

Follow-on scope outside full 15.9 closure:

- **Per-game richer encoders.** `encodeGameState` currently falls back
  to the Connect 4 encoder for othello / hex / gomoku. Bespoke
  per-game encoders (8×8 Othello board, 11×11 Hex board, 15×15
  Gomoku board) are a follow-on delta.

### Code Surface Landed (2026-05-27, JIT-engine PriorOracle bridge)

- `src/JitML/RL/AlphaZero/EnginePrior.hs` exposes
  `buildLinuxCpuPriorOracle :: Env -> Int -> IO (Either Text PriorOracle)`
  that compiles and runs the canonical `Dense2D` kernel via
  `runLinuxCpuFamilyKernel`, captures the deterministic
  `linuxCpuKernelOutput`, and returns a stride-indexed closure
  conforming to `JitML.RL.AlphaZero.Mcts.PriorOracle`. The closure
  applies `abs(x) + 1e-3` so the MCTS prior is strictly positive
  (search loop normalises by sum); outputs are bit-deterministic per
  the [determinism contract](../documents/engineering/determinism_contract.md).
  Callers swap this for `defaultPriorOracle` to drive the search tree
  from real JIT-compiled output rather than the network-free mechanics
  oracle.
- `src/JitML/RL/AlphaZero/SelfPlay.hs` adds
  `runSelfPlayWithPrior :: PriorOracle -> SelfPlayConfig ->
  SelfPlayBuffer` and routes `runSelfPlay` through
  `defaultPriorOracle` so existing tests continue to exercise the
  reproducible search tree. The production AlphaZero loop now
  invokes `runSelfPlayWithPrior` with the EnginePrior closure to
  drive the search from a real JIT kernel.
- `reportCardSelfPlayConfig :: ReportCardKnobs -> SelfPlayConfig`
  consumes `knobAzGames` and `knobAzSims` from
  `cabal.project` and maps them to
  `selfPlayGamesPerGeneration` / `selfPlaySimulationsPerMove`. The
  canonical stanza body and live AlphaZero loop both call into this
  helper so the per-host run count is governed by the report-card
  knobs (already asserted-positive by `jitml-rl-canonicals`).
- New `Live` case `live SelfPlayBuffer MinIO round-trip via
  writeSelfPlayBuffer / readSelfPlayBuffer (Sprint 15.9)` in
  `test/integration/Main.hs` constructs a tiny `SelfPlayConfig`
  (2 games × 4 sims × 6 plies), runs `runSelfPlay`, writes the
  buffer to live MinIO via `writeSelfPlayBuffer`, reads it back via
  `readSelfPlayBuffer`, asserts structural equality, and cleans up.

### Code Surface Landed (2026-05-27, fifth session — production self-play uses the network prior)

The production self-play callsite now drives the MCTS prior from the
real policy/value network at every position, closing the "production
callsites switch to the engine-backed oracle" obligation:

- `JitML.RL.AlphaZero.SelfPlay.runSelfPlayWithOracleFactory ::
  (GameState -> PriorOracle) -> SelfPlayConfig -> SelfPlayBuffer`
  threads a *per-position* oracle through the MCTS search — at each
  ply `playOneGame` applies the factory to the current board state, so
  the prior depends on the position (the AlphaZero contract) rather
  than the search seed. `runSelfPlayWithPrior` is now
  `runSelfPlayWithOracleFactory (const oracle)`; existing callers are
  unchanged.
- `JitML.RL.AlphaZero.PolicyValueNet.netOracleFactory :: PolicyValueNet
  -> GameState -> PriorOracle` returns the network's policy-head
  distribution for the exact board position; `runNetworkSelfPlay net
  config = runSelfPlayWithOracleFactory (netOracleFactory net) config`
  is the production self-play entry point that no longer touches
  `priorFor`.
- `jitml-rl-canonicals` adds "network-driven MCTS self-play is
  deterministic and legal (Sprint 15.9 production prior)": two fresh
  `runNetworkSelfPlay` runs at the same init seed produce
  bit-identical buffers (`bufferTranscriptHash` equal) and every move
  in every transcript is a legal Connect 4 column.

The earlier claim that the flip was blocked on the
`selfPlayTranscript` golden fixtures was incorrect — those transcripts
come from the oracle-independent `selfPlayTranscriptFor` move
generator. The Phase `17` cleanup later deleted the committed
`test/golden/` fixture tree and removed `priorFor`; network-free MCTS
mechanics unit tests now use a neutral uniform `defaultPriorOracle`.

### Code Surface Landed (2026-05-28, MCTS visit-count training targets)

The AlphaZero policy head now trains against the **true MCTS
visit-count distribution** — the canonical AlphaZero target — rather
than the network's-own-policy proxy. Validated by `jitml-rl-canonicals`
(27 tests):

- `JitML.RL.AlphaZero.PolicyValueNet.mctsVisitDistribution net sims
  state seed` runs `sims` MCTS simulations from the position with the
  network's per-position prior oracle and value backups, then
  normalises the per-action `edgeVisits` into a distribution over the
  action space. The search reshapes the raw prior through UCB
  exploration + value backups, so the target carries the search's
  improved policy estimate rather than echoing the network.
- `generatePolicyValueSamples` now takes a `sims` parameter and uses
  `mctsVisitDistribution` as both the move-sampling distribution and the
  `sampleVisitDist` training target; `runOneGenerationOfSelfPlay` threads
  `sims` through.
- New `jitml-rl-canonicals` case "MCTS visit-count target is a valid
  search-derived distribution (Sprint 15.9 visit targets)" asserts the
  distribution is well-formed (length = action space, non-negative,
  sums to 1), run-to-run deterministic, and genuinely search-shaped
  (concentrates visits beyond the uniform 1/7 baseline).

### Remaining Work

- **`PolicyValueNet` now trains on the device (GPU-validated, 2026-05-28).**
  The two-headed AlphaZero network is built on `JitML.Numerics.Mlp`;
  `JitML.Numerics.MlpCuda.policyValueForwardCuda` runs the network forward
  on the GPU (assembling the same softmax-policy + tanh-value heads via the
  shared `policyValueFromForward`), and
  `JitML.RL.AlphaZero.PolicyValueNet.trainPolicyValueNetOnSamplesCuda`
  evaluates the complete ordered sample batch against one immutable parameter
  snapshot, averages the policy/value gradient, and performs exactly one
  host-side Adam step per declared optimizer update (Phase `19` correction,
  2026-07-15). The underlying batched nvcc primitives retain their per-sample
  forward-output contract. `Mlp` was
  refactored to share the head math between the pure and device paths
  (behavior-preserving — host `jitml-unit` 184 / `jitml-rl-canonicals` 27
  unchanged). `jitml-cross-backend` adds "linux-cuda AlphaZero
  PolicyValueNet trains on the device and reduces loss (Sprint 15.9)":
  80 declared full-batch optimizer updates on the RTX 3090 drove the
  policy+value loss below its starting value (the same loss-reduction contract the pure
  `jitml-rl-canonicals` test asserts). **9 / 9 CUDA cross-backend cases
  pass.**
- **Checkpoint surface for trained weights — landed (2026-05-28).**
  `JitML.Numerics.Mlp.{mlpParamsToFlat,mlpParamsFromFlat}` flatten /
  reconstruct the network parameters, and
  `JitML.RL.AlphaZero.PolicyValueNet.{policyValueNetToFlat,loadPolicyValueNetWeights}`
  persist a trained network through the checkpoint `.jmw1` weight blob
  (`JitML.Checkpoint.Format.encodeJmw1` / `decodeJmw1`). `jitml-rl-canonicals`
  adds "trained PolicyValueNet weights round-trip through the .jmw1
  checkpoint blob (Sprint 15.9)": a trained net flattens → `encodeJmw1` →
  `decodeJmw1` → `loadPolicyValueNetWeights` reconstructs bit-identical
  parameters (F64 round-trip is lossless). 28 / 28 `jitml-rl-canonicals`
  pass.
- **Open: live AlphaZero generation drive.** Running one full generation
  against a live Connect 4 cohort inside the cluster daemon with the
  SelfPlayBuffer MinIO round-trip + trained-weight checkpoint persistence
  (both round-trips now in place / live-validated individually) is the
  remaining Sprint 15.9 item.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
