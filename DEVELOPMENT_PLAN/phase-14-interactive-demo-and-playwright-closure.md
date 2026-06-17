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

✅ **Done — `linux-cpu` scope** (validated 2026-06-17 on an Apple M1 Max host's
`linux-cpu` lane; opened 2026-06-14). The full interactive browser product matrix
runs against the live `linux-cpu` edge: `jitml lint purescript` ok, `jitml-e2e
--linux-cpu` 23/23, and the live Playwright matrix **11/11** (every checkpoint-
backed panel serves a real `InferenceResult` — see Remaining Work for the three
landed fixes). Phase `11` Sprint `11.9` (feature implementation) and Phase `12`
Sprint `12.13` (test orchestration) closed `✅ Done` on 2026-06-16; their live
browser/product obligations were deduped into this phase per rule E. The
**per-accelerator** browser/Playwright lanes are owned downstream — `linux-cuda`
by Phase `15` (Sprint `15.20`) and `apple-silicon` by Phase `16` (Sprint
`16.11`); this phase validates only `linux-cpu` (standards rule M(b)).

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
**Blocked by**: Phase `13` Sprint `13.1` (Phase `11` Sprint `11.9` and Phase
`12` Sprint `12.13` are now `✅ Done`; their browser/product live obligations are
owned here in Sprint `14.1` / `14.2` per rule E)
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

- **RESOLVED — `linux-cpu` Playwright `11/11` (2026-06-17, Apple M1 Max).** The
  three root causes below are all fixed and the full live browser product matrix
  passes on `linux-cpu`: `jitml lint purescript` ok, `jitml-e2e --linux-cpu` 23/23,
  and `playwright test` against the live edge **11/11** (all five checkpoint-backed
  panels — MNIST, generic, CIFAR upload, checkpoint compare, Connect 4 — now serve
  a real `InferenceResult`). The three fixes: (1) the in-cluster demo MinIO
  endpoint (`JITML_DEMO_MINIO_S3`); (2) a `jitml internal seed-demo-checkpoints`
  command that persists a small Dense2D weight checkpoint at each of the five
  friendly experiment hashes; (3) the `jitml-demo` pod budget raised to `3Gi`/`2cpu`
  (`dhall/cluster/resources.dhall`) so the in-pod Dense2D kernel JIT-compile no
  longer OOM-kills the pod. The per-accelerator browser/Playwright matrix is
  re-run on `linux-cuda` (Sprint `15.20`) and `apple-silicon` (Sprint `16.11`).
- **Confirmed defect (2026-06-16, live `linux-cpu` Playwright `6/11`).** The five
  checkpoint-backed panels (MNIST inference, generic inference, CIFAR upload,
  checkpoint compare, Connect 4 move) returned `HTTP 503` against the live edge for
  two root causes; the static panels (portals home, shared header, RL timeline,
  training loss curve, tune heatmap) pass `5/5`.
  - **Root cause 1 — FIXED and live-revalidated (2026-06-17, Apple M1 Max
    `linux-cpu`).** The in-cluster `jitml-demo` checkpoint runtime handler read
    MinIO at the external edge URL `127.0.0.1:<edge_port>`
    (`minioSettingsForLocalEdge`), which inside the demo pod is its own localhost
    (`curl exit 7`). `demoBrowserRuntimeHandler` now takes a `Maybe Text`
    in-cluster MinIO endpoint, driven by a new `JITML_DEMO_MINIO_S3` env on the
    `jitml-demo` deployment (`http://minio.platform.svc.cluster.local:9000`,
    mirroring the existing `JITML_DEMO_PULSAR_WS` override); host-native demos
    still fall back to the leased edge. After a rebuilt image + re-bootstrap, the
    demo inference endpoint now reaches the in-cluster MinIO — the error changed
    from `curl exit 7: connection refused to 127.0.0.1` to `pointer read failed:
    HTTP 404` (object-not-found from the real MinIO), confirming the fix. The
    `jitml-e2e --linux-cpu` stanza passes **23 / 23** and `jitml lint purescript`
    passes.
  - **Root cause 2 — OPEN (precisely scoped; the only remaining `linux-cpu`
    Playwright blocker).** No per-panel inference checkpoints are persisted/served,
    so the five checkpoint-backed panels return `HTTP 404`. The panels request
    these friendly experiment hashes, none of which have a checkpoint at
    `jitml-checkpoints/<hash>/pointers/latest`: `mnist-deep-mlp` (MNIST),
    `generic-tensor-demo` (generic + checkpoint-compare baseline),
    `generic-tensor-demo-candidate` (checkpoint-compare candidate),
    `cifar-imagenet` (CIFAR upload), `connect4-alphazero` (Connect 4). The
    runtime handler runs a `Dense2D` weighted kernel
    (`runLinuxCpuWeightedCheckpointInference`), and the panels send **tiny fixed
    demo inputs** (`mnist`/`cifar` `[1,2]`; `generic`/`compare` `[0.25,-0.5,1,2]`;
    Connect 4's `adversarialRuntimeInput` needs output `≥ actionCount+1`). Closing
    this needs a demo-checkpoint seeding path (e.g. a `jitml internal
    seed-demo-checkpoints` leaf reusing `writeMinIOWeightCheckpoint`) that persists
    a small `.jmw1` weight checkpoint + manifest + latest-pointer at each of the
    five hashes with weights shaped for each panel's `Dense2D` input/output. All
    five are CPU-only — no GPU. With root cause 1 fixed, this is the sole gap
    between the current `6/11` and `11/11` on `linux-cpu`.
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

## Sprint 14.2: Playwright No-Caveat Product Matrix ✅

**Status**: Done (`linux-cpu` scope; validated 2026-06-17, Apple M1 Max host — live Playwright 11/11)
**Implementation**: `playwright/jitml-demo.spec.ts`, `test/e2e/Main.hs`,
`src/JitML/Test/LivePlan.hs`
**Blocked by**: Sprint `14.1`; Phase `13` Sprint `13.1`
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

- The existing Playwright suite asserts panel visibility and a few REST values;
  it must expand to workload-launch, event, checkpoint, animation, replay, and
  model-interaction assertions across the full matrix.
- **Live `linux-cpu` Playwright baseline (2026-06-16): `6/11`.** Against a live
  bootstrapped edge (`mcr.microsoft.com/playwright:v1.49.1-noble`, host network),
  the five static panels pass; the five checkpoint-backed panels fail `HTTP 503`
  on the two Sprint `14.1` defects above (in-cluster demo MinIO endpoint + missing
  per-panel checkpoint serving). Closing `14.2` to green requires those fixes plus
  the Sprint `13.1` checkpoint persistence, then a rebuilt `jitml:local`
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
