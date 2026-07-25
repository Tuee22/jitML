# Phase 166: Real Demo Inference — Full-Width Multi-Layer Forward, Real Input, All Families

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Real Demo Inference — Full-Width Multi-Layer Forward, Real Input, All Families. Single-session phase migrated from legacy Sprint 14.3 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 166.1: Real Demo Inference — Full-Width Multi-Layer Forward, Real Input, All Families [✅ Done]

**Status**: Done — reopened 2026-06-24; unblocked 2026-06-25 after Phase 10
Sprint `10.9` and Phase 13 Sprint `13.2` re-closed; re-closed 2026-06-26 on the
live `linux-cpu` edge.

**Implementation**: checkpoint-backed demo inference detects self-describing
`W1`/`b1`/`W2`/`b2` manifests and routes them through the real substrate MLP
forward (`oneDNN` / CUDA / Metal), trimming classifier outputs to the semantic
output spec. The browser panels submit user-derived inputs instead of constants,
and the adversarial selector hashes (`othello-alphazero`, `hex-alphazero`,
`gomoku-alphazero`) are seeded as full-width policy/value MLP checkpoints
alongside the original five browser hashes.

Make the demo render real, input-driven predictions for every trained family:

- Route the demo forward through the real multi-layer MLP kernels (which exist in
  `Codegen/Mlp{OneDnn,Cuda,Metal}.hs`) instead of the single fixed-vector Dense2D path
  (`Engines/Local.hs` `runLinuxCpuWeightedCheckpointInference`, which hardcodes `Dense2D`),
  so output width is the real class count (MNIST → 10). **Consumes the 10.9 shape
  contract:** the seeded checkpoints are self-describing — the manifest's per-layer
  `WeightLayout` tensor specs (`W1/b1/W2/b2` in flatten order) drive the reshape of the
  flat `.jmw1` blob into layers, and the output `TensorSpec` width is the class count to
  render (the classifier MLP's extra raw value-head output beyond `classes` is dropped).
  No hardcoded per-family shape lookup is needed.
- Wire the drawn-canvas / uploaded image into the inference request, replacing the
  constant panel inputs (`[1.0,2.0]` Mnist/Cifar; `[0.25,-0.5,1.0,2.0]`
  GenericInference/CheckpointCompare).
- Render the unrendered families (SL regression, TinyImageNet, othello/hex/gomoku, the
  RL algorithm catalog) via panels/selectors + seeded checkpoints.
- Add a Playwright assertion that the rendered prediction tracks the user's input.

### Exit Definition

- Each demo family renders a real, full-width, input-driven prediction; no constant
  panel input or single-Dense2D collapse remains; Playwright asserts input-tracking.

### Validation

- Live Playwright demo matrix green on the `linux-cpu` edge, asserting the prediction
  changes with the drawn input and the output width equals the class count.
- `docker compose run --rm -w /home/matt/jitML/web jitml spago test` — **17/17**.
- `docker compose run --rm jitml cabal test jitml-unit` — **222/222**.
- `docker compose run --rm jitml jitml check-code` — **check-code: ok**.
- `docker compose build jitml` — **ok**, including embedded `check-code: ok`
  and PureScript production build warnings/errors `0/0`.
- `docker compose run --rm jitml jitml internal seed-demo-checkpoints` — seeded
  all eight demo hashes with trained weights and four typed tensors each.
- Live direct endpoint probes:
  `/api/inference` returned MNIST `InferenceResult` with 10 probabilities and
  10 logits; `/api/images` returned `ImageInferenceResult` top-k 10; `/api/inference/generic`
  returned output width 3; `/api/checkpoints/compare` returned baseline/candidate
  outputs and deltas; `/api/connect4/move` returned `AdversarialMoveResult` with
  legal moves, policy priors, value, and transcript id; `/api/transcripts/replay`
  returned `TranscriptReplay` with persisted moves.
- `docker run --rm --network host -v "$PWD:/work:ro" -w /work mcr.microsoft.com/playwright:v1.49.1-noble ...`
  — live Playwright **15/15**.

### Remaining Work

None for historical Sprint `14.3`. The two Phase `14.3` legacy rows moved to
`Completed`; Sprint `14.4` reopens the browser proof for the expanded all-model
contract.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
