# Phase 17: Interactive Demo and Playwright Closure

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md),
[development_plan_standards.md](development_plan_standards.md),
[system-components.md](system-components.md),
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md),
[phase-11-purescript-frontend-and-demo.md](phase-11-purescript-frontend-and-demo.md),
[phase-12-test-stanzas-and-cross-cluster.md](phase-12-test-stanzas-and-cross-cluster.md),
[phase-16-no-caveat-model-runtime.md](phase-16-no-caveat-model-runtime.md),
[phase-18-no-caveat-product-handoff.md](phase-18-no-caveat-product-handoff.md),
[../README.md](../README.md)
**Generated sections**: none

> **Purpose**: Own the product-level browser closure: every supported workload
> is controlled from the PureScript app, every trained model exposes the
> appropriate interaction, RL animations are live, adversarial games render with
> interactive replay, and Playwright validates those behaviours against real
> substrate-backed runs.

## Phase Status

⏸️ **Blocked** (opened 2026-06-14). The current browser app has panel shells,
REST calls, and WebSocket subscriptions, but the no-caveat target requires a
full interactive lab backed by the real runtime matrix. This phase is blocked by
Phase `11` Sprint `11.9` (feature implementation), Phase `12` Sprint `12.13`
(test orchestration), and Phase `16` Sprint `16.1` (full model runtime).

## Phase Summary

This phase is the user-visible closure gate. It requires real browser controls
for starting, pausing, resuming, stopping, inspecting, replaying, and comparing
workloads. It also requires Playwright tests that prove the browser is not merely
rendering panels: the tests must launch real workloads, observe real live events,
inspect real checkpoints, perform inference through those checkpoints, animate RL
frames, and replay adversarial games from recorded state.

## Sprint 17.1: Full Workflow Control Surface ⏸️

**Status**: Blocked
**Implementation**: `src/JitML/Web/Contracts.hs`, `src/JitML/Web/Server.hs`,
`web/src/Panels/*`, `src/JitML/App.hs`, `src/JitML/Service/*`
**Blocked by**: Phase `11` Sprint `11.9`; Phase `12` Sprint `12.13`; Phase
`16` Sprint `16.1`
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

- `docker compose run --rm jitml jitml lint purescript`
- `docker compose run --rm jitml jitml test jitml-e2e --linux-cpu`
- `docker compose run --rm jitml-cuda jitml test jitml-e2e --linux-cuda`
- `jitml test jitml-e2e --apple-silicon`

### Remaining Work

- Extend the Sprint `11.9` generated current-panel codecs into checkpoint
  browse, live-backed workflow-state reconciliation, adversarial multi-game
  replay, and persisted replay artifact payloads.
- Live-validate the Sprint `11.9` checkpoint-backed MNIST/generic/CIFAR/
  checkpoint-compare/Connect 4 runtime calls against real persisted
  checkpoints on every substrate.
- Extend the Sprint `11.9` request-aware command route with live publication
  proof across all substrates, persisted queued/running/failed/done status
  reconciliation, and unsupported pause/resume/promote lifecycle operations.
- Finish real charts/canvases/animations/replay beyond the current summary
  bars, MCTS metadata, and tuning heatmap/frontier.

## Sprint 17.2: Playwright No-Caveat Product Matrix ⏸️

**Status**: Blocked
**Implementation**: `playwright/jitml-demo.spec.ts`, `test/e2e/Main.hs`,
`src/JitML/Test/LivePlan.hs`
**Blocked by**: Sprint `17.1`; Phase `16` Sprint `16.1`
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

- `docker compose run --rm jitml jitml test jitml-e2e --linux-cpu`
- `docker compose run --rm jitml-cuda jitml test jitml-e2e --linux-cuda`
- `jitml test jitml-e2e --apple-silicon`

### Remaining Work

- The existing Playwright suite asserts panel visibility and a few REST values;
  it must expand to workload-launch, event, checkpoint, animation, replay, and
  model-interaction assertions across the full matrix.

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

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
- [../README.md](../README.md)
