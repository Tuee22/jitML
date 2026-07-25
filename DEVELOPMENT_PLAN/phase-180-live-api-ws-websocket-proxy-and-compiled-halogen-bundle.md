# Phase 180: Live `/api/ws` WebSocket Proxy and Compiled Halogen Bundle

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Live /api/ws WebSocket Proxy and Compiled Halogen Bundle. Single-session phase migrated from legacy Sprint 15.13 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 180.1: Live `/api/ws` WebSocket Proxy and Compiled Halogen Bundle [✅ Done]

**Status**: Done (re-validated 2026-06-06 on RTX 5090; previously Done on RTX 3090) (closed 2026-05-28)
**Blocked by**: Sprint `170.1`
**Implementation**: `src/JitML/Web/Server.hs`,
`web/src/Panels/{Mnist,Cifar,Connect4,Rl,Training,Tune}.purs`,
`web/spago.yaml`, `docker/Dockerfile`
**Docs to update**: `documents/engineering/purescript_frontend.md`,
`documents/engineering/daemon_architecture.md`

### Objective

Replace the deterministic local stream frames served from `/api/ws*`
with a live WebSocket proxy that bridges browser clients to the
daemon's metric/event Pulsar topics. The compiled Halogen bundle
(baked into `jitml:local` per Sprint `11.5`) renders against live
daemon state. Closes Exit Definition item 8's live-panel slice.

### Deliverables

- `JitML.Web.Server` accepts `/api/ws`, `/api/ws/training`,
  `/api/ws/rl`, and `/api/ws/tune` upgrade requests, opens a Pulsar
  WebSocket subscription to the matching event topic, and forwards
  frames downstream.
- The six Halogen panels (`Panels.{Mnist,Cifar,Connect4,Rl,Training,Tune}`)
  render against live frames received through the proxy.
- The demo `web/dist/Main/bundle.js` baked into `jitml:local` renders
  against the live `/api/ws` proxy when served from the cluster
  `jitml-demo` pod.

### Validation

1. Manual: the demo loaded in a browser against the live Envoy edge
   route shows real-time updates while a live training/tune run is in
   progress.
2. `JitML.Web.Server` proxy correctness is exercised by an automated
   test that publishes a known event on the broker and asserts the
   browser client receives a matching frame.

### Code Surface Landed (2026-05-27, /api/ws snapshot + Halogen render machinery seed)

- `JitML.Web.Server.liveEventSnapshotResponse :: Text -> Maybe Text
  -> EndpointResponse` renders a Server-Sent-Events-shaped frame
  (`event: <domain>`/`data: <payload>` lines) from a live broker
  payload. The initial 2026-05-27 polling snapshot fell back to
  deterministic per-domain frames when no live payload was supplied;
  Phase `17` Sprint `17.3` later removed those local stream frames and
  made plain HTTP stream requests return `503` unless the client uses a
  WebSocket upgrade.
- `web/src/Panels/Mnist.purs` gains real Halogen render machinery:
  - typed `State` carrying `lastPrediction`, `pendingInference`, and
    `lastError`
  - `data Action = Predict | PredictionReceived ... | PredictionFailed ...`
    plus `handleAction` setting the corresponding state slice
  - `render` switches on state (pending → disabled button + spinner
    text; prediction → `<div id="mnist-live-inference-prediction">`
    with the predicted class / confidence / latency; error → red
    error badge)
  - `renderPredictionSnapshot :: Maybe MnistInferenceResponse -> String`
    so the Playwright stub can assert against the deterministic
    snapshot.
- The pattern in `Panels.Mnist` is the demo template for the other
  five panels (`Cifar`, `Connect4`, `Rl`, `Training`, `Tune`); each
  panel adds the same `State` / `Action` / `handleAction` / `render`
  shape with its own action set.

### Code Surface Landed (2026-05-27, 5 remaining Halogen panels + WS-upgrade proxy)

- **Halogen render machinery on the five remaining panels.**
  `web/src/Panels/{Cifar,Connect4,Rl,Training,Tune}.purs` each now
  carry the same typed `State` / `data Action = ...` /
  `handleAction` / `render` pattern as `Panels.Mnist`:
  - `Cifar` — `UploadImage` / `UploadCompleted` / `UploadFailed`
    plus a top-k probability `<ol>` and a `renderTopKSnapshot`
    deterministic snapshot.
  - `Connect4` — `PlayColumn col` / `MoveReceived` / `MoveFailed` /
    `ResetGame`, snoc-appends moves on each click, renders the
    7-column board with `disabled` while a daemon move is pending.
  - `Rl` — `FrameReceived` / `StreamFailed` / `ClearFrames`,
    appends RL episode frames to a bounded (200-frame) `<ol>`.
  - `Training` — `FrameReceived` / `StreamFailed`, appends
    (epoch, train_loss, val_loss) rows to a `<table>` next to the
    canvas placeholder.
  - `Tune` — `TrialReceived` / `SweepCompleted` / `StreamFailed`,
    tracks the running best objective via `foldl max` and renders
    the trial `<table>` plus the sweep-done summary badge.
  Each panel keeps the same `mount` entrypoint shape so the demo
  bundle wires unchanged.
- **WebSocket primitives (`JitML.Service.WebSocket`).** Minimal
  RFC 6455 server primitives: `webSocketAcceptKey` (SHA-1 + Base64
  of `key + magic`), `renderUpgradeAccept` (101 Switching
  Protocols response), `encodeTextFrame` (FIN=1 / opcode=0x1 /
  mask=0; 16-bit and 64-bit extended-length forms for payloads >
  125 bytes), `encodeCloseFrame` (opcode=0x8), and
  `detectWebSocketUpgrade` (parse `Upgrade: websocket` +
  `Sec-WebSocket-Key` from raw request bytes). The `jitml-unit`
  group "WebSocket frame and handshake primitives (Sprint 15.13)"
  covers the RFC 6455 §1.3 known answer plus the frame-encoder
  byte-level fixtures (7/7 tests). New deps:
  `base64-bytestring` + `cryptohash-sha1`.
- **Held-open WebSocket bridge in `JitML.Service.Http`.** New
  `WebSocketRoute { webSocketRoutePath, webSocketRouteHandler }`
  type plus `serveHttpRoutesWithWebSockets` route variant. The
  listener checks each accepted connection for the upgrade
  headers; on a match it (a) sends the upgrade response, (b)
  invokes the route handler with a typed
  `writeFrame :: Text -> IO Bool` callback that returns `False` on
  a closed socket, (c) writes a close frame on a clean exit. Plain
  HTTP routes continue to use the one-request-one-response path
  unchanged.
- **Pulsar bridge in `JitML.Web.Server.liveDemoWebSocketRoutes`.**
  Four `WebSocketRoute` entries for `/api/ws`,
  `/api/ws/training`, `/api/ws/tune`, `/api/ws/rl`. With a live
  publication the handler opens a Pulsar subscription on
  `<domain>.event.<substrate>` via
  `PulsarWebSocketSubprocess.runPulsarWebSocketSubprocess` and
  forwards each consumed delivery as a WebSocket text frame
  (ack-after-write per at-least-once doctrine). Without a live
  publication the original handler emitted the deterministic fallback
  frame once; Phase `17` Sprint `17.3` replaced that with a terminal
  error frame. New `serveDemoWithBridge` entrypoint exposes the bridge
  surface to the demo binary.

### Live Validation Note (2026-05-27, fifth session — diagnosed bundler gap)

Inspecting the `jitml:local` image's baked `web/dist/Main/index.js`
(1616 bytes) and the live demo `/` route showed the precise blocker:
`spago build --output web/dist` emits **per-module CommonJS** CoreFn
artifacts (`web/dist/Main/index.js` `require`s
`../Panels.Mnist/index.js`, …). The demo serves that raw
`Main/index.js` as `/bundle/main.js`, but a browser cannot resolve the
CommonJS `require` calls, so `Main.main` never runs and no panel mounts.
The panels' Halogen `render` already produces the correct top-level IDs
(`HP.id "mnist-live-inference"` etc.), so the matrix would pass once the
bundle is browser-loadable.

### Code Surface Landed (2026-05-27, fifth session — browser-loadable bundle + live render)

The two blockers diagnosed above are closed, and the live panel render
is validated:

- **esbuild bundling.** The Dockerfile now runs `npx esbuild
  dist/Main/index.js --bundle --format=iife --global-name=jitmlDemo
  --outfile=dist/Main/bundle.js` after `spago build` and appends
  `jitmlDemo.main();`, producing a 225 KB self-contained browser
  bundle. `JitML.Web.Server.bundleEntryPath` points at
  `web/dist/Main/bundle.js`; Phase `17` Sprint `17.3` removed the
  per-module fallback entry for offline shells.
- **Per-panel hash navigation.** `playwright/jitml-demo.spec.ts`'s
  `loadPanel` now navigates to `LIVE_DEMO_URL#<panel-id>` so
  `Main.main` mounts the matching `Panels.*` component.
- **Live render validated.** The rebuilt image was `kind load`ed +
  the `jitml-demo` Deployment rollout-restarted; the live demo serves
  the 225 KB IIFE through the Envoy edge, and the Playwright matrix
  mounts + asserts all six panels (7 / 7, see Sprint 15.14 Live
  Validation Note).

### Code Surface Landed (2026-05-28, bridge activation + in-cluster endpoint + browser glue)

The three open code items below are closed (compile-validated on the
host for Haskell; `spago build` inside `jitml:local` for PureScript):

- **(a) `demoMain` activates the bridge.** `JitML.App.demoMain` now
  calls `WebServer.serveDemoWithBridgeEndpoint` (not plain
  `serveDemo`), so the held-open Pulsar→WebSocket bridge is live in the
  running demo. With no cluster the `/api/ws` handshake now completes
  and emits a terminal error frame instead of a deterministic local
  stream.
- **(b) in-cluster broker endpoint.** New
  `JitML.Web.Server.serveDemoWithBridgeEndpoint` threads an optional
  Pulsar WebSocket endpoint override through
  `liveDemoWebSocketRoutes` / `bridgeHandler`
  (`pulsarSettingsForEndpoint` when set, else `pulsarSettingsForLocalEdge`
  from the leased edge port). `demoMain` reads `JITML_DEMO_PULSAR_WS`
  (in-cluster broker WS endpoint) + `JITML_SUBSTRATE` for the in-cluster
  `jitml-demo` pod, falling back to the local `cluster-publication.json`
  host-edge settings otherwise.
- **(c) browser-side `onmessage`→typed-`Action` glue.** New
  `web/src/Panels/Stream.purs` + `Stream.js` FFI (`subscribeStream` /
  `openWebSocket`) opens `/api/ws/<domain>` and feeds each frame into the
  calling component's action queue via a `Halogen.Subscription` emitter.
  The three streaming panels (`Rl`, `Training`, `Tune`) now carry an
  `Initialize` action that subscribes and a `LiveFrame` action that
  appends each received frame to a rendered `<ol id="<panel>-live">`.

### Live Validation Note (2026-05-28 — live broker-frame round-trip)

Closes Sprint 13.13. The `jitml-demo` chart now sets
`JITML_DEMO_PULSAR_WS=ws://pulsar-broker.platform.svc.cluster.local:8080/ws`
+ `JITML_SUBSTRATE` on the Deployment (verified on the live pod), so the
held-open bridge consumes from the in-cluster broker. Validated against
the live RTX 3090 / CUDA 12.8 cluster:

- **Validation step 2 (publish → client receives matching frame)**: a
  WebSocket client connected to `ws://127.0.0.1:9092/api/ws/training`
  through the Envoy edge; a unique payload `LIVE-DEMO-FRAME-<suffix>`
  was then published on `persistent://public/default/training.event.linux-cuda`
  via the routed Pulsar WS producer; the client received the exact
  payload forwarded by the demo's in-cluster Pulsar consumer
  (`MARKER_FOUND=true`). This is the end-to-end broker → bridge →
  browser-client frame round-trip.
- The bridge handshake is a real `HTTP/1.1 101 Switching Protocols` with
  a valid `sec-websocket-accept`; `GET /` returns 200 and
  `GET /bundle/main.js` serves the 236 KB browser IIFE; the Playwright
  panel matrix (Sprint 15.14) mounts all six panels from that bundle.

### Follow-On Note

- **Idle-stream keepalive (minor refinement).** The bridge's
  `consumeLoop` exits after one 15-second idle `pulsarConsume` timeout,
  emitting a terminal `event: error` frame and closing the stream. During
  an active training/tune/rl run events arrive continuously so this never
  fires; when idle it prematurely closes the held-open stream. Making
  `consumeLoop` retry on `SETimeout` (sending a keepalive frame, exiting
  only when the downstream socket is gone) is a small follow-on
  robustness improvement; it does not affect the validated broker-frame
  round-trip.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
