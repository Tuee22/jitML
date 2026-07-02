# PureScript Frontend

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: README.md, ../documentation_standards.md, ../../DEVELOPMENT_PLAN/phase-0-planning-documentation.md, ../../DEVELOPMENT_PLAN/phase-11-purescript-frontend-and-demo.md, ../../DEVELOPMENT_PLAN/phase-12-test-stanzas-and-cross-cluster.md, ../../DEVELOPMENT_PLAN/phase-14-interactive-demo-and-playwright-closure.md, ../../DEVELOPMENT_PLAN/phase-18-no-caveat-product-handoff.md, ../../DEVELOPMENT_PLAN/phase-27-demo-all-model-rendering.md, ../../DEVELOPMENT_PLAN/phase-28-per-model-integration-and-e2e.md, ../../DEVELOPMENT_PLAN/system-components.md, product_completion_contract.md, training_metrics_and_splits.md
**Generated sections**: none

> **Purpose**: Project-specific PureScript frontend doctrine for jitML — the
> current local PureScript shell, browser-contract renderer, bundle/panel
> metadata, demo-route manifest, Playwright scaffold, and `jitml-demo` Webapp
> workload, including the Halogen panels, compiled bundle, live WebSocket proxy,
> and the no-caveat Playwright product matrix.

**Current audit status (2026-07-01).** Browser product closure is reopened.
Existing panels and Playwright specs prove useful route and representative
workflow behavior, but a static generated model list or seeded demo checkpoint
does not prove that every documented product row renders from a real trained
artifact. The binding browser contract lives in
[product_completion_contract.md](product_completion_contract.md); Phase `27`
owns artifact-backed all-row demo rendering, and Phase `28` owns per-row e2e
coverage on `linux-cpu` before the accelerator lanes revalidate it.

## Stack

| Component | Current status | Owning module / path |
|-----------|----------------|----------------------|
| PureScript entrypoint | Halogen panel dispatcher keyed by URL hash; empty / unmatched hash routes to the portals home; hash transitions dispose the previous Halogen root before mounting the next panel | `web/src/Main.purs` |
| npm scripts | `build`, `test`, `format` wrappers plus checked-in Spago project | `web/package.json`, `web/spago.yaml` |
| Contract renderer | Local bridge-compatible renderer | `src/JitML/Web/Contracts.hs` |
| Generated contracts | Checked-in generated file protected by `trackingGeneratedPaths` | `web/src/Generated/Contracts.purs` |
| Admin-portal emitter | Bridge-compatible emitter for the bundled admin-portal directory; derived from the `routeAdminPortalLabel` metadata on the route registry | `src/JitML/Web/AdminPortals.hs` |
| Generated admin portals | Checked-in generated file protected by `trackingGeneratedPaths` | `web/src/Generated/AdminPortals.purs` |
| Bundle/panel/demo-route metadata | Local Haskell metadata | `src/JitML/Web/Bundle.hs` |
| Shared chrome | Slim header (`jitML` wordmark + `[home]` link to `#portals`) rendered by every panel | `web/src/Chrome/Header.purs` |
| SPA panel registry | Single hand-maintained list of demo panels consumed by both `Main.purs` and the portals home | `web/src/PanelRegistry.purs` |
| Portals home panel | Two-column directory composing `PanelRegistry.panels` with `Generated.AdminPortals.adminPortals`; default empty-hash landing | `web/src/Panels/Portals.purs` |
| Demo HTTP routes | Haskell HTTP server for API routes, compiled bundle serving, and live WebSocket bridge | `src/JitML/Web/Server.hs` |
| PureScript smoke file | Spec smoke file covering generated contracts and panel modules through the Node `spec-node` runner | `web/test/Main.purs` |
| Panel payload modules | Eight Halogen panels with REST or live WebSocket actions; Sprint `11.9` consumes generated typed payloads for current controls, metrics, animation, inference, checkpoint comparison, and replay instead of text-marker/default-value parsers | `web/src/Panels/{Mnist,GenericInference,Cifar,CheckpointCompare,Connect4,Rl,Training,Tune}.purs` |
| Playwright | Live-only spec currently covers portals/header/admin links, panel hashes, typed REST response/rendered-value updates, workflow status, checkpoint browse, persisted transcript replay, RL/training/tuning panels, and adversarial selectors. Phase `27`/`28` expand this into row-complete trained-artifact/convergence-statistics proof for every product row. | `playwright/jitml-demo.spec.ts`, `src/JitML/Test/LivePlan.hs`, `test/e2e/Main.hs` |
| Webapp role | HTTP/WebSocket server selected by typed `BootConfig.activeRole = Webapp` | `src/JitML/App.hs`, `chart/local/jitml-demo` |

The PureScript stack is project-specific (the doctrine does not address
browser-side code). Npm / Spago / Playwright invocations flow through
the typed `Subprocess` boundary from doctrine `Architecture → Subprocesses as
Typed Values`; the checked-in Cabal bodies perform local smoke checks,
validate the `spago test`, `purs-tidy check`, and Playwright command shapes,
and keep the live browser run on the explicit live orchestration path.
`web/spago.yaml` keeps `spec` and `spec-node` in the test dependency set, and
`web/test/Main.purs` uses `Test.Spec.Runner.Node.runSpecAndExitProcess` so
Node-local smoke runs exit with the real test status without the deprecated
generic `runSpec` compatibility alias. The runner's `.spec-results` file is
ignored under `web/.gitignore`.

## Layout

Current checked-in layout:

```text
web/
├── spago.yaml
├── package.json
├── src/
│   ├── Main.purs
│   ├── PanelRegistry.purs
│   ├── Chrome/
│   │   └── Header.purs
│   ├── Panels/
│   │   ├── Api.js
│   │   ├── Api.purs
│   │   ├── CheckpointCompare.purs
│   │   ├── Cifar.purs
│   │   ├── Connect4.purs
│   │   ├── GenericInference.purs
│   │   ├── Mnist.purs
│   │   ├── Portals.purs
│   │   ├── Rl.purs
│   │   ├── Stream.js
│   │   ├── Stream.purs
│   │   ├── Training.purs
│   │   └── Tune.purs
│   └── Generated/
│       ├── AdminPortals.purs
│       └── Contracts.purs
└── test/
    └── Main.purs

playwright/
└── jitml-demo.spec.ts
```

Build output under `web/dist/` is generated, not checked in. The Docker image
build runs `spago build --output dist` and esbuilds `dist/Main/index.js` into
the browser-loadable `web/dist/Main/bundle.js` served by `jitml-demo`.

## Current Local Surface

The current worktree contains `web/src/Main.purs`, generated
`web/src/Generated/Contracts.purs`, eight Halogen panel modules under
`web/src/Panels/`, `web/test/Main.purs`, `src/JitML/Web/Contracts.hs`, and
`src/JitML/Web/Bundle.hs`. `Web.Bundle` records the bundle output paths, the
current panel surfaces, the `demoStatusLine`, and the demo route
manifest for `/`, `/api`, `/api/inference`, `/api/inference/generic`,
`/api/images`, `/api/checkpoints/compare`, `/api/connect4/move`,
`/api/runs/{runId}/command`, `/api/ws`, `/api/ws/training`, `/api/ws/rl`,
and `/api/ws/tune`. `web/src/Main.purs`
dispatches through the SPA
`PanelRegistry`, stores the active Halogen disposer, and runs it before
mounting the next hash-selected panel so navigation does not leave
duplicate roots attached. `src/JitML/Web/Server.hs` serves the same HTTP surface,
returns `503` for plain stream GETs that do not upgrade to WebSocket, and
bridges upgraded `/api/ws*` clients to live Pulsar event topics.

## No-Caveat Closure Target

The final browser target is end-to-end rather than demonstrative. The demo app
starts or selects real SL, RL, AlphaZero, and tuning runs; consumes typed
payloads generated from Haskell-owned contracts; renders model-appropriate
interactions; animates RL trajectories from real event frames; renders canonical
adversarial games with legal move handling, MCTS/value/policy details, and
interactive replay; exposes tuning sweep controls/frontiers tied to real trial
state; and shows the completed-budget/convergence-statistics payload attached
to each selected checkpoint. Playwright proves those behaviors through the
explicit live `jitml-e2e` orchestration path; the 2026-06-26 `linux-cpu` run
closed this target for the baseline, with CUDA and Apple reruns owned by
downstream phases.

## Browser-Contract ADTs

`src/JitML/Web/Contracts.hs` is the **source of truth** for every ADT
crossed by the REST / WebSocket surface. The current local renderer produces
`web/src/Generated/Contracts.purs`, identifies itself as
`local-purescript-bridge-compatible-renderer`, and the generated contract path
is an active `trackingGeneratedPaths` entry; hand edits fail
`jitml docs check`. `CheckpointSummary` now carries only Engine-listed
inference-eligible artifacts and includes the manifest SHA, step, model family,
tensor count, eligibility string, completed-budget rendering,
convergence-metric rendering, and TensorBoard prefix. The browser contract
therefore receives the same `CompletedTraining`/checkpoint eligibility state
that the Haskell loader enforces, instead of inferring readiness from seeded or
smoke manifests.
The non-live integration selector test constructs one completed and one partial
manifest and asserts that only the completed manifest appears in the browser
summary list.

The current endpoint metadata covers:

- `RunCommand` at `POST /api/runs/{runId}/command`
- `InferenceRun` at `POST /api/inference`
- `GenericInference` at `POST /api/inference/generic`
- `UploadImage` at `POST /api/images`
- `CheckpointCompare` at `POST /api/checkpoints/compare`
- `Connect4Move` at `POST /api/connect4/move`
- `MetricsStream` at `GET /api/ws`
- `TrainingStream` at `GET /api/ws/training`
- `RlStream` at `GET /api/ws/rl`
- `TuneStream` at `GET /api/ws/tune`

Sprint `11.9` expands this endpoint list into generated payload records for
the current panel surface:

- `BrowserInferenceRequest`
- `BrowserGenericInferenceRequest`
- `BrowserImageRequest`
- `BrowserCheckpointCompareRequest`
- `BrowserAdversarialMoveRequest`
- `InferenceResult`
- `GenericInferenceResult`
- `ImageInferenceResult`
- `CheckpointCompareResult`
- `AdversarialMoveResult`
- `TrainingEventFrame`
- `RlAnimationFrame`
- `RlReplayFrame`
- `TuneTrialFrame`
- `TuneSweepDoneFrame`
- `WorkflowCommandAck`
- `WorkflowStatus`

The generated module also includes parser helpers, per-payload parsers,
daemon-compatible command-envelope renderers for the current
training/RL/tune start-stop protocols, browser REST request renderers,
an `RlReplayFrame` parser, a `WorkflowCommandAck` parser, and `WorkflowStatus`
render/parse helpers. MNIST, generic
tensor inference, CIFAR/ImageNet, checkpoint comparison, Connect 4, RL,
training, and tuning panels consume those generated parsers/renderers and
reject the former `prediction:`, `image:`, `move:`, and catch-all `data:`
marker payloads in the PureScript smoke suite.
Panel-side string marker parsing is not part of the final contract. The
no-caveat product contract expansion now includes checkpoint browse,
live-backed workflow-state reconciliation, lifecycle command acknowledgement,
and adversarial multi-game replay payloads.

## Panels

Every panel renders inside `Chrome.Header.render` (the slim shared header — `jitML` wordmark plus `[home]` link to `#portals`), so the directory is one click away from any panel view. `Main.purs`'s empty-hash fallback routes to the portals home; the named hashes below continue to address each panel directly. Panel mounts return their Halogen disposer to the hash dispatcher, which runs the previous disposer before mounting a new route. The portals home is itself a `Panels.Portals` Halogen component composing `PanelRegistry.panels` (left column) with `Generated.AdminPortals.adminPortals` (right column), the latter generated from `src/JitML/Routes.hs` via `JitML.Web.AdminPortals` so the registry remains the single source of truth. Admin backends stay as top-level routed links rather than iframes. Grafana, Prometheus, TensorBoard, Harbor, MinIO, and Pulsar each own authentication, CSP, websocket/base-path behavior, and internal navigation; the consistent jitML UI is the generated portal directory and shared chrome, not an embedded frame around each upstream console.

`Panels.Api.requestText` is the dependency-free text request bridge used by the
REST panels. MNIST, generic tensor inference, CIFAR/ImageNet, checkpoint
comparison, and Connect 4 issue real `POST` calls to the generated endpoint
paths and convert text replies into the panel-specific typed response records
before updating Halogen state. Sprint `10.6` removed the server-side inline demo
networks; Sprint `11.9` replaced the route-level `503 checkpoint-required`
result with an injected checkpoint runtime handler when `jitml-demo` has a live
publication. That handler loads the selected checkpoint with
`loadInferenceCheckpointWithWeights`, dispatches to the publication substrate's
weighted runner, and renders typed MNIST, generic tensor, CIFAR/ImageNet,
checkpoint comparison, and Connect 4 responses. Without the injected handler
those routes still fail closed with `503 checkpoint-required`. The Connect 4 panel
now acts as the adversarial-games panel: it selects Connect 4, Othello, Hex,
or Gomoku, renders the corresponding board dimensions from the move
transcript, displays the typed MCTS/value response, renders per-game rule
summaries plus rules-complete per-game annotations (board size, win condition,
and move semantics), live legal-action counts, and exposes prev/next scrub
controls over the local move transcript.
The training, RL, and tuning panels post generated
workflow command envelopes to `/api/runs/<run-id>/command`, parse
`WorkflowCommandAck`, and render generated `WorkflowStatus` records for
queued/running/failed/done browser state. The server route fails with `503`
when no live publication exists; with a publication it resolves the browser
`substrate: live` token to the publication substrate and publishes valid
start/stop envelopes to the matching daemon command topic. Live-backed
cross-session status reconciliation and all-model checkpoint eligibility are
validated for the `linux-cpu` baseline. The training
panel renders the latest throughput/device/checkpoint and
TensorBoard fields from `TrainingEventFrame` plus a window-normalized
throughput-telemetry sparkline; the RL panel parses both
animation and replay frames, drives a CSS-transform live environment animation
(a cart-pole scene plus a per-dimension observation strip and a recent-reward
sparkline) from `RlAnimationFrame.observation`, and exposes prev/next replay
scrub controls over the received `RlReplayFrame` list. These render surfaces
compile and pass the contract spec through `jitml lint purescript`; live
Playwright product proof of the animations is Phase `14` work. `Panels.Stream`
opens the live
WebSocket route, reports connection failures through typed actions, and the
RL/training/tune panels convert incoming frame text through generated stream
parsers instead of storing raw frame strings.

| Panel | URL hash | REST handler | WebSocket subscription |
|-------|----------|--------------|------------------------|
| Portals home (default) | `#portals` (empty hash) | — | — |
| MNIST | `#mnist-live-inference` | `POST /api/inference` | — |
| Generic inference | `#generic-inference-lab` | `POST /api/inference/generic` | — |
| CIFAR / ImageNet | `#cifar-imagenet-upload` | `POST /api/images` | — |
| Checkpoint compare | `#checkpoint-compare-lab` | `POST /api/checkpoints/compare` | — |
| Adversarial games | `#connect4-human-vs-alphazero` | `POST /api/connect4/move` | — |
| RL trajectory | `#rl-trajectory` | `POST /api/runs/rl-demo/command` | `/api/ws/rl` (proxies `rl.event.<mode>`) |
| Training | `#training-progress` | `POST /api/runs/training-demo/command` | `/api/ws/training` (proxies `training.event.<mode>`) |
| Tune | `#hyperparameter-sweep` | `POST /api/runs/tune-demo/command` | `/api/ws/tune` (proxies `tune.event.<mode>`) |

## REST and WebSocket Surface

The HTTP handlers live in `src/JitML/Web/Server.hs`; they provide responses for
the API index, compiled bundle serving, and live stream routes. The inference,
generic tensor, image, checkpoint-compare, and Connect 4 REST routes accept
generated browser request envelopes and call an injected
`BrowserRuntimeHandler` when `jitml-demo` has a live publication; the handler
uses the same weighted checkpoint read path as `jitml inference run`. Without
that handler the routes fail closed with `503 checkpoint-required`. A workflow
command route accepts
`/api/runs/<run-id>/command`, reads the POST body, resolves live-substrate
command envelopes, publishes protocol-supported training/RL/tune commands
when a live publication is supplied, and returns a typed acknowledgement.
Without a publication it fails closed with `503`; persisted cross-session
status tracking remains open. A stream route requested as plain HTTP returns
`503 live stream requires WebSocket upgrade`; upgraded clients are bridged to
Pulsar event topics by `liveDemoWebSocketRoutes`.

| Surface | Method | Path | Payload type |
|---------|--------|------|--------------|
| Inference | POST | `/api/inference` | `InferenceRun` |
| Generic inference | POST | `/api/inference/generic` | `GenericInference` |
| Image upload | POST | `/api/images` | `UploadImage` |
| Checkpoint compare | POST | `/api/checkpoints/compare` | `CheckpointCompare` |
| Connect 4 move | POST | `/api/connect4/move` | `Connect4Move` |
| Workflow command | POST | `/api/runs/<run-id>/command` | `WorkflowCommandAck` |
| Live event WS | GET | `/api/ws`, `/api/ws/training`, `/api/ws/rl`, `/api/ws/tune` | typed event envelopes |
| Checkpoint browse | GET | `/api/checkpoints/<experiment-hash>` | inference-eligible checkpoint summary list (cross-link to TB sidecars) |

## Webapp HTTP Server

The `jitml-demo` Kubernetes workload runs the one supported binary as
`jitml service --config /etc/jitml/BootConfig.dhall` with
`activeRole = Webapp`. `runWebappRole` in `src/JitML/App.hs` starts the
low-level HTTP/WebSocket listener from `src/JitML/Web/Server.hs`. It serves the
current route/API surface, `/bundle/main.js` from `web/dist/Main/bundle.js`
when the bundle exists, and the held-open `/api/ws*` WebSocket bridge. When no
live publication exists the bridge sends a terminal error frame instead of an
offline deterministic stream.

The `chart/local/jitml-demo` Deployment mounts `BootConfig.dhall` from the
`jitml-webapp-config` ConfigMap and points HTTPRoutes for `/`, `/api`, and
`/api/ws` at `jitml-demo:80`. Browser inference requests publish WorkCommands
to the Engine through Pulsar; the Webapp does not compile kernels or compute ML.
The `linux-cuda` chart still keeps the live-validated Sprint `15.20` / `15.21`
runtime/budget envelope, but CUDA execution belongs to the Engine role.

## Playwright E2E

`playwright/jitml-demo.spec.ts` is the current TypeScript Playwright scaffold.
`JitML.Test.LivePlan` records the target `npx playwright test` step after the
Helm dependency build and the `jitml bootstrap` ephemeral-cluster rollout. The
default `jitml-e2e` Cabal body validates that typed Playwright command shape
without starting the live stack. The checked-in spec is live-only: it reads
`.build/runtime/cluster-publication.json`, navigates to the published edge
route, and fails fast when no live publication exists. The historical matrix
covers the smoke shell plus the eight current panel hashes:

- Portals home: load the empty-hash root and assert both the panels
  column (`#jitml-portals-panels`) and the admin-portals column
  (`#jitml-portals-admin`) mount, plus every admin-portal link carries
  the expected root-relative `href` matching the route registry.
- Shared header: for each named panel hash, assert `#jitml-chrome`
  mounts and the `#jitml-chrome-home` anchor links to `#portals`.
- MNIST/generic/CIFAR/checkpoint compare/Connect 4: current panel reachability
  can issue the REST calls and assert typed response envelopes; Phase `14`
  expands that into no-caveat model artifact selection and rendered product
  state.
- RL trajectory: load the trajectory panel through the live edge route.
- Training / Tune: load the streaming metric panels through the live edge
  route.

Sprint `12.13` / Phase `14` replaced the original reachability matrix with a
broader product matrix, and the 2026-06-26 fixed-budget audit re-closed that
target on `linux-cpu`: Phase `14.4` covers every documented model family with
completed `InferenceEligibleCheckpoint` artifacts, visible convergence/
completion state, negative infer-before-complete checks, RL animations from
trained policies, adversarial-game boards from trained policy/value checkpoints,
transcript replay, tuning controls, and TensorBoard/checkpoint links. Phase
`15.21` then passed the same live Playwright product matrix 15/15 on the
published `linux-cuda` edge.

Playwright execution runs through the typed `Subprocess` boundary on the
explicit live orchestration path; it belongs to the doctrine's
Ephemeral-Cluster Infrastructure test category and does not have its own Cabal
stanza. Static route/API scaffold checks stay in the local Haskell e2e and
PureScript lint targets.
The 2026-06-26 CUDA-machine run used
`mcr.microsoft.com/playwright:v1.49.1-noble` with host networking against the
published `linux-cuda` edge and passed **15 / 15**.
The local PureScript smoke suite is `purescript-spec` executed through
`spec-node` by `spago test`; Playwright remains live-only and separate from the
default Cabal matrix.

## Cross-References

- [../../README.md → PureScript frontend](../../README.md#purescript-frontend)
- [../../README.md → Panels](../../README.md#panels)
- [../../README.md → Envoy Gateway API: a single localhost socket](../../README.md#envoy-gateway-api-a-single-localhost-socket) (`src/JitML/Routes.hs` is the upstream source for the generated `Generated.AdminPortals` artifact; the routes-published-at-the-edge table in that section is rendered from the same registry)
- [cluster_topology.md → Routes Published at the Edge](cluster_topology.md#routes-published-at-the-edge) (the canonical regenerated table)
- [daemon_architecture.md](daemon_architecture.md)
- [../../DEVELOPMENT_PLAN/phase-11-purescript-frontend-and-demo.md](../../DEVELOPMENT_PLAN/phase-11-purescript-frontend-and-demo.md)
- [../../DEVELOPMENT_PLAN/phase-12-test-stanzas-and-cross-cluster.md](../../DEVELOPMENT_PLAN/phase-12-test-stanzas-and-cross-cluster.md)
- [../../DEVELOPMENT_PLAN/phase-14-interactive-demo-and-playwright-closure.md](../../DEVELOPMENT_PLAN/phase-14-interactive-demo-and-playwright-closure.md)
