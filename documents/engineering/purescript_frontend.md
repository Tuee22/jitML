# PureScript Frontend

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: README.md, ../documentation_standards.md, ../../DEVELOPMENT_PLAN/phase-0-planning-documentation.md, ../../DEVELOPMENT_PLAN/phase-11-purescript-frontend-and-demo.md, ../../DEVELOPMENT_PLAN/phase-12-test-stanzas-and-cross-cluster.md, ../../DEVELOPMENT_PLAN/phase-14-interactive-demo-and-playwright-closure.md, ../../DEVELOPMENT_PLAN/phase-18-no-caveat-product-handoff.md, ../../DEVELOPMENT_PLAN/phase-27-demo-all-model-rendering.md, ../../DEVELOPMENT_PLAN/phase-28-per-model-integration-and-e2e.md, ../../DEVELOPMENT_PLAN/phase-30-apple-silicon-product-lane.md, ../../DEVELOPMENT_PLAN/phase-31-no-caveat-product-aggregation.md, ../../DEVELOPMENT_PLAN/phase-262-contract-driven-live-execution-browser-and-playwright.md, ../../DEVELOPMENT_PLAN/phase-272-apple-integration-e2e-and-attestation.md, ../../DEVELOPMENT_PLAN/system-components.md, product_completion_contract.md, training_metrics_and_splits.md, run_contract.md
**Generated sections**: none

> **Purpose**: Project-specific PureScript frontend doctrine for jitML — the
> current local PureScript shell, browser-contract renderer, bundle/panel
> metadata, demo-route manifest, live Playwright suite, and `jitml-demo` Webapp
> workload, including the Halogen panels, compiled bundle, live WebSocket proxy,
> and the no-caveat Playwright product matrix.

Phase state, remaining work, blockers, and validation evidence live only in
[Development Plan → Closure Status](../../DEVELOPMENT_PLAN/README.md#closure-status).
A static generated model list, declared workflow status, or seeded fixture
checkpoint is not product evidence. The binding browser bar lives in
[Product Completion Contract](product_completion_contract.md); the run state and
evidence projected into browser contracts come from
[Typed Run Contract](run_contract.md).

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
| Playwright | Live-only spec instantiates exactly 55 positive ProductRow tests from the command-owned browser catalogue, drives the real checkpoint API/UI path, and binds every rendered row to its exact row id, PlanId, experiment, manifest, and measured result. Separate route-mocked cases prove malformed or non-passing frames fail closed. A custom reporter publishes the authenticated browser-result journal. | `playwright/jitml-demo.spec.ts`, `playwright/jitml-browser-evidence-reporter.ts`, `src/JitML/Test/LivePlan.hs`, `test/e2e/Main.hs` |
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
├── jitml-browser-evidence-reporter.ts
├── jitml-demo.spec.ts
└── playwright.config.ts
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
state; and shows the completed-budget/measured-result payload attached to each
selected checkpoint. Playwright proves those behaviors through the explicit
live `jitml-e2e` orchestration path. It consumes a read-only catalogue derived
from the already-authenticated integration journal, then returns a separately
keyed browser-result journal; it cannot read or sign the integration journal
itself. The development plan owns current lane validation status.

## Browser-Contract ADTs

`src/JitML/Web/Contracts.hs` is the **source of truth** for every ADT
crossed by the REST / WebSocket surface. The current local renderer produces
`web/src/Generated/Contracts.purs`, identifies itself as
`local-purescript-bridge-compatible-renderer`, and the generated contract path
is an active `trackingGeneratedPaths` entry; hand edits fail
`jitml docs check`. `CheckpointList` is one strict, all-or-nothing 55-row frame.
Its scalar header binds `run-id`, substrate, catalogue SHA, source-journal SHA,
count, and selector state. Every ordered `ProductRowSelector` carries ordinal,
row id, PlanId, experiment hash, exact manifest SHA, family, explicit
`Passed`/`Failed`/`NotRun` status and reason, and panel. Every ordered
`CheckpointSummary` repeats ordinal, row id, PlanId, experiment, and manifest,
then supplies step, model family, tensor count, eligibility, completed budget,
measured result, and TensorBoard prefix. The generated parser rejects missing,
duplicated, orphaned, reordered, malformed, non-canonical-substrate, or
selector/summary-mismatched rows. Canonical text fields are trimmed, non-empty,
free of all Unicode `Cc` controls, and bounded to 4096 Unicode code points,
matching the Haskell and reporter boundaries. The backend publishes the frame only when all
55 source rows are `Passed`; Failed or NotRun source evidence returns a service
error and produces no partial catalogue. Browser records remain wire/view DTOs,
not proof-bearing domain values: decoding text cannot manufacture completion.
See
[Evidence Journals and Reporting](run_contract.md#evidence-journals-and-reporting).
`ModelMatrixRow` carries the generated PlanId, substrate, experiment hash, and
panel for each ProductRow on every substrate. Static rows are declaration-only
and render `NotRun` without displaying a substrate-specific PlanId; they never
look like live proof. The checkpoint panel
accepts only the direct REST response, renders explicit status/reason cells, and
joins selector to summary by the complete `(ordinal, row id, PlanId, experiment,
manifest)` identity before rendering family-specific supervised, RL, AlphaZero,
or tuning metadata.
Product REST routes validate the submitted artifact namespace against the
ProductRow registry before publishing work or calling the runtime; non-product
hashes and `*-demo-weights` names return `503 checkpoint-required` with
`selector-state: fail-closed:no-inference-eligible-artifact`, and panels render
that text through their existing error state.
Local parser and browser-negative coverage rejects partial selector or summary
coverage, duplicate/unknown/reordered fields, identity mismatch, and non-passing
source evidence. The service and panel never render a permissively filtered
prefix as a partial `CheckpointList`.

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

Every panel renders inside `Chrome.Header.render` (the slim shared header — `jitML` wordmark plus `[home]` link to `#portals`), so the directory is one click away from any panel view. `Main.purs`'s empty-hash fallback routes to the portals home; the named hashes below continue to address each panel directly. Panel mounts return their Halogen disposer to the hash dispatcher, which runs the previous disposer before mounting a new route. `Panels.Stream.subscribeStream` builds each browser WebSocket as a cleanup-bearing `Halogen.Subscription` emitter: disposal clears the JS callbacks and closes a connecting or open socket before the next route mounts. The server retains an independent read-side peer watcher for full-page navigation, tab closure, and other teardown that bypasses Halogen disposal. The portals home is itself a `Panels.Portals` Halogen component composing `PanelRegistry.panels` (left column) with `Generated.AdminPortals.adminPortals` (right column), the latter generated from `src/JitML/Routes.hs` via `JitML.Web.AdminPortals` so the registry remains the single source of truth. Admin backends stay as top-level routed links rather than iframes. Grafana, Prometheus, TensorBoard, MinIO, and Pulsar each own authentication, CSP, websocket/base-path behavior, and internal navigation; the consistent jitML UI is the generated portal directory and shared chrome, not an embedded frame around each upstream console.

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
those routes still fail closed with `503 checkpoint-required`.

A panel submits inputs inside the input domain the row it targets declares. A
trained classification row declares a unit-image transform, so the MNIST,
CIFAR/ImageNet, and checkpoint-comparison panels submit values in `[0,1]`; the
wider standardized vector belongs only to the generic-tensor panel's regression
row. This is a correctness obligation rather than a presentation detail: an
out-of-domain default asks the Engine for an answer no admitted checkpoint can
give, and the served path rejects it every time it is retried. The standing
`jitml-unit` gate reads `web/src/Panels/CheckpointCompare.purs` and holds its
default input to the domain of the rows it names. The Engine's side of that
contract — answering such a request terminally rather than starving its shared
subscription — is
[Terminal inference settlement](daemon_architecture.md#terminal-inference-settlement). The Connect 4 panel
now acts as the adversarial-games panel: it selects Connect 4, Othello, Hex,
or Gomoku, renders the corresponding board dimensions from the move
transcript, displays the typed MCTS/value response, renders per-game rule
summaries plus rules-complete per-game annotations (board size, win condition,
and move semantics), live legal-action counts, and exposes prev/next scrub
controls over the local move transcript.
The training, RL, and tuning panels post generated
workflow command envelopes to `/api/runs/<run-id>/command`, parse
`WorkflowCommandAck`, and render generated `WorkflowStatus` records for
queued/running/failed/done browser state. Those states are read-only projections
of the validated plan and evidence journal; the frontend neither derives
completion from event arrival order nor sends a status value back as evidence.
The server route fails with `503`
when no live publication exists; with a publication it resolves the browser
`substrate: live` token to the publication substrate and publishes valid
start/stop envelopes to the matching daemon command topic. The training
panel renders the latest throughput/device/checkpoint and
TensorBoard fields from `TrainingEventFrame` plus a window-normalized
throughput-telemetry sparkline; the RL panel parses both
animation and replay frames, drives a CSS-transform live environment animation
(a cart-pole scene plus a per-dimension observation strip and a recent-reward
sparkline) from `RlAnimationFrame.observation`, and exposes prev/next replay
scrub controls over the received `RlReplayFrame` list. These render surfaces
compile and pass the contract spec through `jitml lint purescript`; the
completed Phase `14` live Playwright matrix exercises their product behavior.
`Panels.Stream`
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
Without a publication it fails closed with `503`; with a publication the
Engine lifecycle projector publishes reconciled queued/running/failed/done
status on `workflow.status.<substrate>`, bridged to the browser through
`/api/ws/workflow`. A stream route requested as plain HTTP returns
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
| Checkpoint browse | POST | `/api/checkpoints` | complete publication-bound 55-row `CheckpointList` (cross-link to TB sidecars) |

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

`playwright/jitml-demo.spec.ts` is the live-only TypeScript suite.
`JitML.Test.LivePlan` gives the browser container a read-only repository mount,
an individual read-only catalogue file, an individual read-only cluster
publication, and one isolated read-write browser-evidence directory. It does
not mount the Phase 261 journal, ProductScenario signing capability, executable
challenge, or checkpoint root. Its only key is the independent browser-result
key created after the parent-only fallback is durable. The exact publication
must contain `live-readiness` and the
complete substrate-specific ready-component set. The exact catalogue must be a
strict version-1 55-row envelope whose run, substrate, catalogue SHA, source
journal SHA, row identity, PlanId, manifest, and measured result are canonical.
The default `jitml-e2e` Cabal body validates that typed mount/environment shape
without starting the live stack; the explicit live driver selects or boots the
cluster and runs it. The historical matrix
covers the smoke shell plus the original eight-panel cohort:

- Portals home: load the empty-hash root and assert both the panels
  column (`#jitml-portals-panels`) and the admin-portals column
  (`#jitml-portals-admin`) mount, plus every admin-portal link carries
  the expected root-relative `href` matching the route registry.
- Shared header: for each named panel hash, assert `#jitml-chrome`
  mounts and the `#jitml-chrome-home` anchor links to `#portals`.
- MNIST/generic/CIFAR/checkpoint compare/Connect 4: the original reachability
  cases issued REST calls and asserted typed response envelopes; completed
  Phase `14` expanded them into no-caveat model artifact selection and rendered
  product state.
- RL trajectory: load the trajectory panel through the live edge route.
- Training / Tune: load the streaming metric panels through the live edge
  route.

The 55 positive ProductRow cases are created from `JITML_BROWSER_CATALOGUE_PATH`,
not regexes over `Generated.Contracts` and not broad body substrings. Each case
has the exact catalogue title. A serial `beforeAll` performs one authenticated
real panel load through `/api/checkpoints`; the 55 cases then assert their exact
catalogue-bound row id, PlanId, experiment, manifest, measured result, status,
and family renderer against that same refined DOM. Route mocks exist only in a
separate negative suite, use the full frozen 55-row wire, and prove mismatched
manifests plus explicit Failed/NotRun source rows render no Passed fallback.

`jitml-browser-evidence-reporter.ts` keeps the final retry for each exact
catalogue test id and atomically publishes a strict version-1 result containing
55 ordered `Passed`, `Failed`, or `NotRun` rows. It consumes and unlinks a fresh
0600 file containing exactly 64 lowercase hexadecimal characters (32 key
bytes), constructs byte-length-delimited UTF-8 receipt material, signs it with
HMAC-SHA256, zeroes the in-memory key, and refuses to replace a stale result.
Failure details remove every Unicode `Cc` control and retain at most 4096 code
points; receipt lengths are UTF-8 byte lengths, with a multibyte golden shared
with the Haskell verifier.
`playwright.config.ts` retains the list reporter and enables this reporter only
when all four browser-evidence environment variables are present; a partial
configuration fails immediately. Current lane validation evidence belongs in
the development plan, not this architecture document.

The `apple-silicon` browser closure runs through
`jitml test jitml-e2e --live --apple-silicon` against the retained Apple
publication and host Engine daemon. Its positive matrix must contain all 55
catalogue-derived tests and render the exact Metal-trained row artifacts; a
missing daemon, Metal runtime, publication, catalogue row, or authenticated
browser result is a lane failure rather than an offline or static fallback.

Playwright execution runs through a structured process result on the explicit
live orchestration path and attaches its transcript to the scenario journal; it
belongs to the doctrine's
Ephemeral-Cluster Infrastructure test category and does not have its own Cabal
stanza. Static route/API scaffold checks stay in the local Haskell e2e and
PureScript lint targets.
The local PureScript smoke suite is `purescript-spec` executed through
`spec-node` by `spago test`; Playwright remains live-only and separate from the
default Cabal matrix.

## Cross-References

- [../../README.md → PureScript frontend](../../README.md#purescript-frontend)
- [../../README.md → Panels](../../README.md#panels)
- [../../README.md → Envoy Gateway API: a single localhost socket](../../README.md#envoy-gateway-api-a-single-localhost-socket) (`src/JitML/Routes.hs` is the upstream source for the generated `Generated.AdminPortals` artifact; the routes-published-at-the-edge table in that section is rendered from the same registry)
- [cluster_topology.md → Routes Published at the Edge](cluster_topology.md#routes-published-at-the-edge) (the canonical regenerated table)
- [daemon_architecture.md](daemon_architecture.md)
- [run_contract.md](run_contract.md)
- [Legacy Phase 11: PureScript Frontend and Demo](../../DEVELOPMENT_PLAN/README.md#legacy-to-new-phase-map)
- [Legacy Phase 12: Test Stanzas and Cross-Cluster Validation](../../DEVELOPMENT_PLAN/README.md#legacy-to-new-phase-map)
- [Legacy Phase 14: Interactive Demo and Playwright Closure](../../DEVELOPMENT_PLAN/README.md#legacy-to-new-phase-map)
