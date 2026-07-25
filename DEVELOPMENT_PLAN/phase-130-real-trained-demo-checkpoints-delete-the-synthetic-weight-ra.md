# Phase 130: Real Trained Demo Checkpoints (Delete the Synthetic Weight Ramp)

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Real Trained Demo Checkpoints (Delete the Synthetic Weight Ramp). Single-session phase migrated from legacy Sprint 10.9 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 130.1: Real Trained Demo Checkpoints (Delete the Synthetic Weight Ramp) [✅ Done]

**Status**: Done — reopened 2026-06-24, re-closed 2026-06-25 on the `linux-cpu` lane.
The code landed and validated host-native (grep-clean + the `jitml-unit` "demo
checkpoints (Sprint 10.9)" distinctness/self-describing case + `jitml-e2e` 23/23), then
this phase's own live proof ran after a 109-step `linux-cpu` bootstrap: seeding all five
checkpoints into live MinIO and `jitml inference run` returning family-distinct outputs
for every seeded family. Phase 8 Sprint `8.13` and Phase 9 Sprint `9.13` (the real
training surfaces this reuses) have landed.

**Implementation**: `src/JitML/App.hs` (`seededDemoCheckpoints` + `SeededDemoCheckpoint`,
`demoClassifierDataset`, `mlpLayerTensorSpecs`, `buildShapedWeightCheckpointSnapshot` /
`writeMinIOWeightCheckpointShaped`, the rewritten `runInternalSeedDemoCheckpoints`),
`test/unit/Main.hs` (the distinctness test).

The hardcoded `demoWeights = [0.05 + ((i*7+3) mod 11)/20 | i in 0..255]` ramp
(byte-identical across all five seeded "models") is **removed**.
`runInternalSeedDemoCheckpoints` now seeds `seededDemoCheckpoints`: one **distinct,
provenance-tagged, self-describing fixture** checkpoint per demo family — the four classifier
families (`mnist-deep-mlp` 784→24→10, `cifar-imagenet` 3072→24→10, `generic-tensor-demo`
and `generic-tensor-demo-candidate` 4→8→3, distinct seeds) train a real softmax MLP
(`Classifier.trainClassifier`) on a small in-code separable task and flatten the trained
`MlpParams`; `connect4-alphazero` trains a real policy/value network through self-play
(`runOneGenerationOfSelfPlay`) and flattens it (`policyValueNetToFlat`). Each checkpoint's
manifest metric map records the run's provenance (training loss/accuracy or arena
win-rate, plus the seed).

**Self-describing checkpoints — the 10.9 → 14.3 shape contract.** `writeMinIOWeightCheckpointShaped`
records each model's **per-layer tensor shapes** (`W1/b1/W2/b2` in the `mlpParamsToFlat`
flatten order) plus an input `TensorSpec` and an output `TensorSpec` whose width is the
**class count** (`logits` `[10]`/`[3]`; AlphaZero `policy_value` `[8]`), so the checkpoint
satisfies "correct per-tensor shapes" and the downstream multi-layer-forward consumer
(Sprint `14.3`, "output width = class count") can reshape the flat `.jmw1` blob into its
layers without a hardcoded per-family lookup. (The classifier MLP carries one extra raw
value-head output, `classes + 1`, from the shared policy/value structure; the output spec
records the semantic class count and the layer specs keep the raw tensor shapes.)

### Exit Definition

- No synthetic/hardcoded weight ramp remains in `App.hs`; each demo family's checkpoint
  is distinct, provenance-tagged, and self-describing (per-layer shapes +
  class-count output spec). The legacy ledger row for the ramp moves to `Completed`. ✅
  (code; grep-clean + the distinctness/self-describing unit test confirm the worktree.)

### Validation

- Grep clean for the ramp — **confirmed** (`demoWeights` removed; no ramp remains).
- `jitml-unit` "demo checkpoints (Sprint 10.9)" — the five families are distinct,
  non-constant, self-describing (per-layer shapes sum to the flat length),
  and the output spec width equals the class count. **Host-native, no cluster.**
- `jitml-e2e` chart/bucket guards green — **23/23**; the five demo experiment hashes are
  preserved.
- **Live (this phase owns it, `linux-cpu`):** `jitml bootstrap --linux-cpu` →
  `jitml internal seed-demo-checkpoints` → `jitml inference run` over the five seeded
  checkpoints returns family-distinct outputs. Self-contained on the `linux-cpu` host (no
  accelerator), so Phase 10 closes in numerical order. Sprint `13.2`'s `jitml test all
  --live --linux-cpu` re-exercises this path as part of the full-runtime re-attest, but
  does **not** gate Phase 10.
- **Live validation completed 2026-06-25 (`linux-cpu`):** `docker compose build jitml`
  rebuilt `jitml:local` and ran `jitml check-code: ok`; the direct compose bootstrap
  (`docker compose run --rm -e JITML_BOOTSTRAP_SKIP_IMAGE_BUILD=1 jitml jitml bootstrap
  --linux-cpu`) completed **109 steps** after reusing that fresh image; `jitml internal
  seed-demo-checkpoints` seeded all five checkpoints (MNIST 19,115 weights, generic 76
  weights each, CIFAR 74,027 weights, Connect 4 1,672 weights); sequential live
  `jitml inference run --experiment-hash ...` returned family-distinct outputs:
  `mnist-deep-mlp` `[-0.14406323432922363,-5.201629549264908e-2]`,
  `generic-tensor-demo` `[0.10279107093811035,-0.7217661738395691]`,
  `generic-tensor-demo-candidate` `[-1.4564321041107178,0.761154294013977]`,
  `cifar-imagenet` `[0.19340509176254272,3.598484769463539e-2]`, and
  `connect4-alphazero` `[0.2905381917953491,0.38741081953048706]`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
