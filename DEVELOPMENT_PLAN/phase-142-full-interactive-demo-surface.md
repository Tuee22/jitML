# Phase 142: Full Interactive Demo Surface

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Full Interactive Demo Surface. Single-session phase migrated from legacy Sprint 11.9 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 142.1: Full Interactive Demo Surface [✅ Done]

**Status**: Done (closed 2026-06-16 on the owned interactive-demo code surface;
the live/product obligations were deduped to their owning downstream sprints per
standards rule E — see "Owned Surface Closed; Live Obligations Deferred" below)
**Implementation**: `src/JitML/Web/Contracts.hs`, `src/JitML/Web/Server.hs`,
`src/JitML/Web/Bundle.hs`, `web/src/Panels/*`, `web/src/PanelRegistry.purs`,
`playwright/jitml-demo.spec.ts`
**Docs to update**: `documents/engineering/purescript_frontend.md`,
`documents/engineering/training_workloads.md`, `system-components.md`,
`legacy-tracking-for-deletion.md`

### Objective

Make the PureScript app a complete interactive frontend for every supported
runtime workflow, with no demo-only parsing or visualization stand-ins.

### Deliverables

- `Web.Contracts` defines generated ADTs/codecs for training, RL, tuning,
  checkpoint browse, inference, image upload, adversarial move, replay, and live
  event payloads. Panels stop parsing text markers such as `prediction:` or any
  `data:` frame into hardcoded values.
- `/api/runs/<run-id>/command` and the panel controls publish typed
  `training.command.<substrate>`, `rl.command.<substrate>`, and
  `tune.command.<substrate>` envelopes for start/pause/resume/stop/kill/promote.
- MNIST, CIFAR/Tiny ImageNet, generic tensor inference, and checkpoint compare
  panels call checkpoint-backed inference endpoints and render real
  distributions/outputs.
- Training visualizations draw loss/validation curves, throughput, device
  telemetry, checkpoint markers, and TensorBoard links from typed live events.
- RL visualizations animate environment frames, reward distributions, policy
  probabilities, replay-buffer fill, and trajectory scrub/replay from persisted
  artifacts.
- Adversarial game panels render Connect 4, Othello, Hex, and Gomoku boards,
  legal moves, MCTS visit distributions, value estimates, engine analysis, and
  interactive replay from recorded game transcripts.
- Tuning visualizations render frontier, trial heatmap, sampler/scheduler/pruner
  state, PBT lineage, trial drill-down, kill/promote controls, and promoted
  checkpoint status.

### Historical Validation

- `docker compose run --rm jitml jitml lint purescript`
- `docker compose run --rm jitml jitml test jitml-e2e --linux-cpu`
- `docker compose run --rm jitml-cuda jitml test jitml-e2e --linux-cuda`
- `jitml test jitml-e2e --apple-silicon`
- `docker compose run --rm jitml jitml docs check`

### Current Validation State

The 2026-06-15 Sprint `11.9` slice lands the generated browser payload
surface and validates it locally:

- `src/JitML/Web/Contracts.hs` renders typed PureScript records and parsers
  for browser inference/image/generic tensor/checkpoint-compare/adversarial
  request envelopes, `InferenceResult`, `ImageInferenceResult`,
  `GenericInferenceResult`, `CheckpointCompareResult`,
  `AdversarialMoveResult`, `TrainingEventFrame`, `RlAnimationFrame`,
  `RlReplayFrame`, `TuneTrialFrame`, `TuneSweepDoneFrame`,
  `WorkflowCommandAck`, and `WorkflowStatus`;
  `web/src/Generated/Contracts.purs` matches the renderer.
- MNIST, generic tensor inference, CIFAR/ImageNet, checkpoint comparison,
  Connect 4, RL, training, and tuning panels consume generated parsers instead
  of `prediction:`, `image:`, `move:`, or catch-all `data:` marker parsers.
  `web/test/Main.purs` rejects those legacy marker payloads.
- `Generated.Contracts` renders browser-side training/RL/tune command
  envelopes for the daemon's existing text protocols, plus a
  `WorkflowCommandAck` parser and `WorkflowStatus` records. Training, RL, and
  tuning panels post those envelopes to `/api/runs/<run-id>/command` instead
  of bare words and render queued/running/failed/done status from command
  acks, stream frames, and parse/stream failures.
- `JitML.Service.Http` now passes request bodies into route handlers, and
  `JitML.Web.Server` resolves the browser `substrate: live` token from the
  live cluster publication before publishing valid start/stop envelopes to the
  fully qualified `training.command.<substrate>`,
  `rl.command.<substrate>`, or `tune.command.<substrate>` Pulsar topic. Without
  a live publication the route fails visibly with `503` instead of returning a
  fake queued acknowledgement.
- `JitML.Web.Server` accepts an injected `BrowserRuntimeHandler` for
  checkpoint-backed panel REST requests. The Webapp role supplies that handler
  from the live publication, loads the latest checkpoint through
  `loadInferenceCheckpointWithWeights`, dispatches to the selected substrate's
  weighted runner, returns the manifest content SHA, and renders typed MNIST,
  generic tensor, CIFAR/ImageNet, checkpoint-comparison, and Connect 4
  responses. Without the handler the routes still fail closed with
  `503 checkpoint-required`.
- The current panels render loss bars, training throughput/device/checkpoint
  and TensorBoard metadata, action-probability bars, parsed RL replay frames
  with prev/next scrub controls, adversarial board surfaces for Connect 4,
  Othello, Hex, and Gomoku, per-game rule summaries/legal-action counts, local
  transcript scrub controls, MCTS visit/policy/value details, and tuning
  trial/frontier summaries instead of placeholder canvases or raw text-only
  frame dumps.
- The RL panel additionally drives a CSS-transform live environment animation
  (a cart-pole scene driven by the cart position / pole angle, a per-dimension
  observation strip, and a recent-reward sparkline) from
  `RlAnimationFrame.observation`; the training panel adds a window-normalized
  throughput-telemetry sparkline from `TrainingEventFrame.throughput`; and the
  adversarial panel adds rules-complete per-game annotations (board size, win
  condition, and move semantics) for Connect 4, Othello, Hex, and Gomoku. These
  pure HTML+CSS render surfaces reuse the established `HP.style` bar idiom and
  add no canvas/svg dependency.
- Validated so far (the `jitml lint purescript` gate was re-run after the
  2026-06-15 visualization additions and is green):
  `docker compose run --rm jitml jitml lint purescript`;
  `docker compose run --rm jitml jitml test jitml-e2e --linux-cpu` (22 / 22,
  including the no-publication command-route 503 assertion, injected
  checkpoint-runtime REST route assertions, generic tensor inference, and
  checkpoint-comparison delta assertions);
  `docker compose run --rm jitml cabal run exe:jitml -- docs check`;
  `docker compose run --rm jitml cabal run exe:jitml -- check-code`.

### Owned Surface Closed; Live Obligations Deferred (rule E)

Sprint `11.9` owns the interactive-demo **code surface** — the typed/generated
browser contracts, the panel render/control/visualization surface, the
checkpoint-runtime REST route shape, the request-aware command route, and the
host-validatable lint/spec/e2e structure. That surface is complete and validated
on this host:

- `docker compose run --rm jitml jitml lint purescript` (compiles the Halogen
  app + purs-tidy + the contract round-trip spec);
- `docker compose run --rm jitml jitml test jitml-e2e --linux-cpu`
  (the structural demo-route / contract / runtime-handler assertions);
- `docker compose run --rm jitml jitml check-code`;
- `docker compose run --rm jitml jitml docs check`.

Every remaining obligation is **live-runtime** and is already owned by a
downstream sprint, so it lives there per standards rule E (one obligation, one
place) and the live-obligation consolidation doctrine (Phases `15`–`17` extract
every live-runtime obligation from Phases `7`–`12`):

- Live checkpoint-backed REST + `/api/runs/<run-id>/command` publication proof
  on every substrate, persisted queued/running/failed/done status
  reconciliation, the pause/resume/promote/adversarial command-topic extension,
  and the richer charts/canvases/replay-artifact/transcript-backed-replay
  surface → **Sprint `14.1` (Full Workflow Control Surface)**, which already
  names "Live-validate the Sprint `11.9` checkpoint-backed … calls", "Extend the
  Sprint `11.9` request-aware command route…", and "Finish real
  charts/canvases/animations/replay…".
- The live Playwright product matrix exercising those behaviours →
  **Sprint `14.2` (Playwright No-Caveat Product Matrix)** and the per-lane live
  runs in **Sprint `15.20` (linux-cpu / linux-cuda)** and **Sprint `16.11`
  (apple-silicon)**.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
