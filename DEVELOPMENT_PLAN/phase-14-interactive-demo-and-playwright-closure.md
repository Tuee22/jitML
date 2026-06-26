# Phase 14: Interactive Demo and Playwright Closure

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md),
[development_plan_standards.md](development_plan_standards.md),
[system-components.md](system-components.md),
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md),
[phase-11-purescript-frontend-and-demo.md](phase-11-purescript-frontend-and-demo.md),
[phase-12-test-stanzas-and-cross-cluster.md](phase-12-test-stanzas-and-cross-cluster.md),
[phase-13-no-caveat-model-runtime.md](phase-13-no-caveat-model-runtime.md),
[phase-18-no-caveat-product-handoff.md](phase-18-no-caveat-product-handoff.md),
[../README.md](../README.md)
**Generated sections**: none

> **Purpose**: Own the product-level browser closure: every supported workload
> is controlled from the PureScript app, every trained model exposes the
> appropriate interaction, RL animations are live, adversarial games render with
> interactive replay, and Playwright validates those behaviours against real
> substrate-backed runs.

## Phase Status

✅ **Done** (reopened and re-closed 2026-06-26 for Sprint `14.4` — all-model
trained-artifact browser and Playwright closure on `linux-cpu`). Sprint `14.3`
remains historically closed for selected seeded-demo inference; prior close
2026-06-17. The interactive browser product matrix ran against the
real full-width checkpoint runtime on the live `linux-cpu` edge: the Webapp
publishes through the Engine and returns deterministic Engine-backed POST frames
for inference, checkpoint compare, adversarial moves, and transcript replay;
the demo checkpoints are completed seeded, self-describing `W1`/`b1`/`W2`/`b2`
MLP fixture manifests carrying `CompletedTraining`; MNIST, CIFAR/ImageNet,
generic tensor inference, checkpoint compare, Connect 4, Othello, Hex, and
Gomoku all use inference-eligible checkpoint hashes; and the PureScript panels
submit user-derived input instead of constants.

Validation for the re-close: `spago test` **17/17**, `jitml-unit` **222/222**,
`jitml check-code` **ok**, `docker compose build jitml` **ok** (embedded
`check-code: ok`; PureScript build warnings/errors `0/0`), live
`jitml internal seed-demo-checkpoints` seeded all eight demo hashes
(`mnist-deep-mlp`, `generic-tensor-demo`, `generic-tensor-demo-candidate`,
`cifar-imagenet`, `connect4-alphazero`, `othello-alphazero`, `hex-alphazero`,
`gomoku-alphazero`), direct live endpoint probes returned full response bodies
and expected widths (`InferenceResult` 10 MNIST probabilities/logits,
`ImageInferenceResult` top-k 10, generic output width 3, compare output width
3/3, `AdversarialMoveResult` with transcript id, `TranscriptReplay` with moves),
and the live Playwright matrix passed **15/15** against `http://127.0.0.1:9091`.
Sprint `14.4` extended that proof with the generated all-model matrix and
trained-artifact metadata assertions.
Phase `11` Sprint `11.9` (feature implementation) and Phase `12` Sprint `12.13`
(test orchestration) stay closed; their live browser/product obligations are
deduped into this phase per rule E. The **per-accelerator** browser/Playwright
lanes remain owned downstream — `linux-cuda` by Phase `15` (Sprint `15.20`) and
`apple-silicon` by Phase `16` (Sprint `16.11`); this phase validates only
`linux-cpu` (standards rule M(b)).

## Phase Summary

This phase is the user-visible closure gate. It requires real browser controls
for starting, pausing, resuming, stopping, inspecting, replaying, and comparing
workloads. It also requires Playwright tests that prove the browser is not merely
rendering panels: the tests must launch real workloads, observe real live events,
inspect real checkpoints, perform inference through those checkpoints, animate RL
frames, and replay adversarial games from recorded state.

## Sprint 14.1: Full Workflow Control Surface ✅

**Status**: Done (`linux-cpu` scope; validated 2026-06-17, Apple M1 Max host)
**Implementation**: `src/JitML/Web/Contracts.hs`, `src/JitML/Web/Server.hs`,
`web/src/Panels/*`, `src/JitML/App.hs`, `src/JitML/Service/*`
**Previously blocked by**: Phase `13` Sprint `13.1` (Phase `11` Sprint `11.9`
and Phase `12` Sprint `12.13` are now `✅ Done`; their browser/product live
obligations are owned here in Sprint `14.1` / `14.2` per rule E)
**Docs to update**: `documents/engineering/purescript_frontend.md`,
`system-components.md`

### Objective

Expose every no-caveat runtime workflow through generated browser contracts and
the PureScript app.

### Deliverables

- Browser-generated contracts cover typed request/response/event payloads for
  training control, RL control, tuning control, checkpoint browse, inference,
  image upload, adversarial game moves, adversarial replay, and workload status.
- Training panels start every committed SL experiment, display loss/validation
  curves, throughput, device telemetry, checkpoints, TensorBoard links, and
  pause/resume/stop outcomes.
- Model interaction panels cover MNIST drawing, CIFAR/Tiny ImageNet upload,
  generic tensor inference, checkpoint swap/compare, and output visualizations
  appropriate to each model family.
- RL panels animate live environment frames, reward distributions, policy/action
  probabilities, replay-buffer state, and recorded trajectory scrub/replay.
- Adversarial game panels render Connect 4, Othello, Hex, and Gomoku boards,
  legal moves, MCTS visit distributions, value estimates, engine analysis, and
  interactive replay from persisted game transcripts.
- Hyperparameter panels launch/stop sweeps, render live frontier/heatmap/state,
  inspect trials, and promote a trial to a checkpointed run.

### Validation

This sprint closes on `linux-cpu` (single host) per standards rule M(b)/(d); the
per-accelerator browser/Playwright lanes are owned downstream by Sprint `15.20`
(`linux-cuda`) and Sprint `16.11` (`apple-silicon`).

- `docker compose run --rm jitml jitml lint purescript`
- `docker compose run --rm jitml jitml test jitml-e2e --linux-cpu`

### Remaining Work

None for the `linux-cpu` scope owned by Sprint `14.1`. The historical gaps in
checkpoint browse, workflow-state reconciliation, and persisted transcript replay
remain closed by the 2026-06-23 live Playwright expansion, and Sprint `14.3`
re-validates the broader browser matrix at **15/15** after the full-width demo
runtime replacement.

## Sprint 14.2: Playwright No-Caveat Product Matrix ✅

**Status**: Done (`linux-cpu` scope; re-validated 2026-06-26 — live Playwright 15/15)
**Implementation**: `playwright/jitml-demo.spec.ts`, `test/e2e/Main.hs`,
`src/JitML/Test/LivePlan.hs`
**Previously blocked by**: Sprint `14.1`; Phase `13` Sprint `13.1`
**Docs to update**: `documents/engineering/purescript_frontend.md`,
`documents/engineering/unit_testing_policy.md`, `system-components.md`

### Objective

Make Playwright the product proof that every supported model trains and exposes
its expected browser interaction.

### Deliverables

- Playwright starts every canonical SL training workflow, waits for live events,
  verifies convergence/status, opens the resulting checkpoint, and exercises the
  model-specific interaction.
- Playwright starts every RL algorithm family, observes live reward/trajectory
  frames, verifies animation updates, records a trajectory, and scrubs/replays it.
- Playwright launches AlphaZero self-play for every canonical adversarial game,
  plays against a checkpointed policy, verifies legal moves and visit
  distributions, and replays the completed game interactively.
- Playwright launches a bounded tuning sweep, verifies trial/final-frontier
  visualization updates, stops or kills a trial, promotes a trial, and verifies
  the promoted checkpoint is usable.
- The e2e driver owns an ephemeral Kind lifecycle and tears it down even on
  failure; tests fail fast if the live publication, bundle, route, or workload
  event stream is absent.

### Validation

This sprint closes the Playwright product matrix on `linux-cpu` (single host) per
standards rule M(b)/(d); the same matrix is re-run per-accelerator by Sprint
`15.20` (`linux-cuda`) and Sprint `16.11` (`apple-silicon`).

- `docker compose run --rm jitml jitml test jitml-e2e --linux-cpu`

### Remaining Work

None for the `linux-cpu` scope owned by Sprint `14.2`. The live Playwright matrix
now covers the portals/header surfaces, MNIST, generic inference, CIFAR/ImageNet,
checkpoint compare, Connect 4, Othello/Hex/Gomoku adversarial selectors,
checkpoint browse, workflow status, persisted transcript replay, RL, training,
and tuning panels against the live edge, and it passes **15/15**.

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/purescript_frontend.md` — full generated browser
  contracts, control surfaces, visualization expectations, and Playwright matrix.
- `documents/engineering/unit_testing_policy.md` — live Playwright product
  assertions and the boundary between numerical fixtures and user-provided
  image/stroke/game interaction fixtures.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- Update `system-components.md` frontend and test rows to mark this phase as the
  owner of no-caveat browser closure.

## Sprint 14.3: Real Demo Inference — Full-Width Multi-Layer Forward, Real Input, All Families [✅ Done]

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

## Sprint 14.4: All-Model Browser and Playwright Trained-Artifact Matrix [✅ Done]

**Status**: Done
**Implementation**: `playwright/jitml-demo.spec.ts`, `test/e2e/Main.hs`,
`web/src/Panels/*.purs`, `src/JitML/Web/Server.hs`,
`src/JitML/Test/WorkflowMatrix.hs`
**Docs to update**: `../documents/engineering/purescript_frontend.md`,
`../documents/engineering/unit_testing_policy.md`,
`../documents/engineering/training_metrics_and_splits.md`,
`system-components.md`

### Objective

Playwright proves every supported model through the real browser, not merely
that representative panels and routes respond. The browser must reject
untrained artifacts, select trained artifacts, show convergence statistics, and
drive the model's natural interaction.

### Deliverables

- Add Playwright cells for every SL model row, every RL algorithm row, and every
  AlphaZero game.
- Assert the displayed checkpoint includes completed budget, convergence
  metric, substrate, TensorBoard link, and readiness status.
- Drive model-appropriate interactions: drawing for MNIST, upload for image
  classifiers, tensor/regression inputs for tabular/generic models, trajectory
  replay for RL, and legal board moves for AlphaZero games.
- Assert that partial, random, hardcoded, smoke, and fake-runtime checkpoints do
  not appear as selectable inference artifacts.

### Validation

- `docker compose run --rm jitml jitml test jitml-e2e --linux-cpu`
- live Playwright against a bootstrapped `linux-cpu` edge
- `docker compose run --rm jitml jitml docs check`

### Current Validation State

- `docker compose run --rm jitml cabal test jitml-e2e --test-show-details=direct`
  passed **23 / 23** with the regenerated trained-artifact contract present.
- `docker compose run --rm jitml cabal run jitml -- test jitml-e2e --linux-cpu`
  passed through the project wrapper with **23 / 23** tests.
- `docker compose run --rm jitml cabal run jitml -- lint purescript` passed
  (`jitml lint purescript: ok`).
- `docker compose run --rm jitml cabal run jitml -- docs check` passed
  (`docs check: ok`).
- `docker compose run --rm jitml cabal run jitml -- check-code` passed
  (`check-code: ok`).
- `./bootstrap/linux-cpu.sh up` completed the live `linux-cpu` rollout
  (**111** steps), leaving a live edge publication at `127.0.0.1:9091`.
- `docker compose build jitml` passed after the Phase `14.4` browser and
  generated-contract changes, including embedded `check-code: ok` and a clean
  PureScript bundle build.
- The rebuilt `jitml:local` / `jitml-demo:local` image was loaded into the
  `jitml-linux-cpu` Kind cluster, `deployment/jitml-service` and
  `deployment/jitml-demo` rolled out successfully, and
  `jitml internal seed-demo-checkpoints` seeded all eight completed demo
  checkpoints into live MinIO.
- Live Playwright passed **15 / 15** against `http://127.0.0.1:9091`. The
  checkpoint browse test asserts completed-budget, convergence, TensorBoard
  link, eligibility, absence of partial/untrained/smoke/fake artifacts, and
  every generated `WorkflowMatrix.allModelCells` browser row.

### Remaining Work

- None.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
- [../README.md](../README.md)
