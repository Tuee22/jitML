# Phase 254: Arena Convergence + Evidence

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Arena Convergence + Evidence. Originally migrated from legacy Sprint 26.2 in the 2026-07-24 phase renumber; see the old→new map in [README.md](README.md).

## Phase State

⏸️ **Blocked** for the expanded validation foundation in Sprint `254.2`.
The earlier Sprint `254.1` record below is retained on its original source and
scope; it does not validate this target or a current hardware lane. The execution
order and transition authority are [the validation-foundation refactor](README.md#validation-foundation-refactor).

The new source/catalogue, runner and hardware controls remain unimplemented.
Sprint `221.2` owns reconciliation of the existing checker with these documented
targets; this documentation-only change supplies no machine-validation receipt.

## Sprint 254.2: Authentic arena-learning readiness for every game [⏸️ Blocked]

**Status**: Blocked
**Implementation**: Target changes to `src/JitML/RL/AlphaZero/PolicyValueNet.hs`, `src/JitML/Test/RowAssertions.hs`, `src/JitML/Product/NativeArenaLearningPolicy.hs`.
**Blocked by**: Sprint `160.2`, Sprint `225.2`.
**Docs to update**: `../documents/engineering/execution_resources.md`, `../documents/engineering/validation_execution.md`, `../documents/engineering/training_metrics_and_splits.md`, `../documents/engineering/determinism_contract.md`, `README.md`, `system-components.md`, `legacy-tracking-for-deletion.md`.

### Objective

Connect4 and Hex learning refusals are repaired with authentic arena evidence, while changed self-play/evaluation paths revalidate the other games they affect.

The target contracts are [execution resources](../documents/engineering/execution_resources.md)
and [validation execution](../documents/engineering/validation_execution.md).
Their acceptance requirements below are planned work, not implemented behavior.

### Deliverables

- Own the retained Connect4 and Hex failures: insufficient joint cohort successes or served-policy improvement must be explained and repaired, not hidden by opponent or seed selection.
- Validate actual multi-generation self-play, network updates and evaluation against the prospectively specified opponent/case policy; reject all-draw, initialized-only, scripted and stale arena results.
- Keep authentic initial/final observations, every cohort outcome and fixed served index. Separate development/calibration experiments from qualifying evidence under the `278.2` criterion policy.
- Reopen Phase `253` if root cause lies in its self-play implementation. Name and rerun affected Othello/Gomoku readiness when shared code changes; unchanged historical passes are not a final-source lane journal.

### Validation

1. Run each failed arena row individually through the bounded production path; retain every failure and measure actual generations, updates, evaluation cases and runtime resources.
2. Exercise independently specified untrained/all-draw/below-policy negatives and genuine learned positives; the exact reported metric must belong to the served artifact.
3. Check within-substrate reproducibility on the prescribed identical-seed controls without inventing cross-substrate parity.
4. After individual readiness succeeds, run the full relevant RL canonical/convergence obligations and supply the frozen candidate to campaign qualification.

Closure requires the owned targeted/hermetic controls listed above, with a
nonempty independently enumerated test inventory and exact scoped transcripts.
The implementation publishes actual selectable groups in the existing stanzas
and uses the supported `--test-options` passthrough; no invented selector or
unfiltered full-matrix acquisition is an acceptable substitute. A scoped result
is recorded as scoped, never as a passing full stanza. Resource/live controls
also require the actual owned runtime observations named above.

Complete evidence-dependent unit/integration/negative-control transcripts belong
to Sprints `277.2` and `280.2`; cross-family convergence belongs to `283.2` and
`285.2`. Those downstream records are not prerequisites for this foundation or
readiness closure. Every original case remains registered with an explicit owner.
The existing documentation/code-quality commands below run after source parity
is implemented, inside the admitted profile; they do not execute these controls.

```bash
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml docs check
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml check-code
```

Cluster-running jobs use the separately admitted cluster/lifecycle overlays
instead of the stopped-cluster build profile. A real hardware lane is never
claimed by CPU fixtures; absent required runtime capability fails that lane.

### Remaining Work

- Investigate and repair Connect4/Hex learning failures and revalidate affected games before any full lane campaign.
- Complete independently reviewed current criteria and artifact/arena replay; historical counts or a stored pass flag cannot close this sprint.

## Retained Historical Scope

The following state, commands, measurements and closure statements describe the
original Sprint `254.1` surface only. New execution rules and acceptance
above supersede any conflicting operational instruction; old receipts are not
reinterpreted as current readiness.

### Historical Phase State

✅ **Done**.

## Sprint 254.1: Arena Convergence + Evidence [✅ Done]

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

- `../documents/engineering/execution_resources.md`.
- `../documents/engineering/validation_execution.md`.
- `../documents/engineering/training_metrics_and_splits.md`.
- `../documents/engineering/determinism_contract.md`.

**Product docs to create/update:**

- [Development-plan entry](README.md#validation-foundation-refactor), [component inventory](system-components.md), and [deletion ledger](legacy-tracking-for-deletion.md).

**Cross-references to add:**

- Link the target contracts, exact sprint dependencies and evidence pointers together when source implementation lands; update root summaries only in an authorized root-file change.
