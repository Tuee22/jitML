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
full interactive lab backed by the real runtime matrix. Phase `11` Sprint `11.9`
(feature implementation) and Phase `12` Sprint `12.13` (test orchestration)
closed `✅ Done` on 2026-06-16 on their owned code surface, and their live
browser/product obligations were deduped into this phase (Sprints `17.1` /
`17.2`) per rule E; this phase remains blocked by Phase `16` Sprint `16.1` (full
model runtime).

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
**Blocked by**: Phase `16` Sprint `16.1` (Phase `11` Sprint `11.9` and Phase
`12` Sprint `12.13` are now `✅ Done`; their browser/product live obligations are
owned here in Sprint `17.1` / `17.2` per rule E)
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

- **Confirmed defect (2026-06-16, live `linux-cpu` Playwright `6/11`).** The five
  checkpoint-backed panels (MNIST inference, generic inference, CIFAR upload,
  checkpoint compare, Connect 4 move) return `HTTP 503` against the live edge.
  Root cause 1: the in-cluster `jitml-demo` checkpoint runtime handler reads MinIO
  at the external edge URL `127.0.0.1:<edge_port>`
  (`src/JitML/App.hs:244`, `minioSettingsForLocalEdge`), which inside the demo pod
  resolves to the pod's own localhost (`minioReadBytes: curl exit 7: Failed to
  connect to 127.0.0.1 port 9091`); it must instead use the in-cluster MinIO
  service (`minio.platform.svc.cluster.local:9000`) the daemon already uses via
  `minioSettingsForEndpoint` — e.g. an env-driven endpoint on the `jitml-demo`
  deployment mirroring the existing `JITML_DEMO_PULSAR_WS` override. Root cause 2:
  no per-panel inference checkpoints are persisted/served — the live
  `jitml-checkpoints` bucket holds only RL/AlphaZero/tune/workflow-matrix
  artifacts, none at the experiment hashes the browser panels request (depends on
  Sprint `16.1` per-family checkpoint persistence). The static panels (portals
  home, shared header, RL timeline, training loss curve, tune heatmap) pass `5/5`.
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
- **Live `linux-cpu` Playwright baseline (2026-06-16): `6/11`.** Against a live
  bootstrapped edge (`mcr.microsoft.com/playwright:v1.49.1-noble`, host network),
  the five static panels pass; the five checkpoint-backed panels fail `HTTP 503`
  on the two Sprint `17.1` defects above (in-cluster demo MinIO endpoint + missing
  per-panel checkpoint serving). Closing `17.2` to green requires those fixes plus
  the Sprint `16.1` checkpoint persistence, then a rebuilt `jitml:local`
  re-bootstrap and a full re-run on every runnable lane.

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
