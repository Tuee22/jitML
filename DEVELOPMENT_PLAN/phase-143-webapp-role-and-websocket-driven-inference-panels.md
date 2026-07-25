# Phase 143: Webapp Role and Websocket-Driven Inference Panels

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Webapp Role and Websocket-Driven Inference Panels. Single-session phase migrated from legacy Sprint 11.10 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 143.1: Webapp Role and Websocket-Driven Inference Panels [✅ Done]

**Status**: Done — on its owned surface: `jitml-demo` folded into the one-binary
**Webapp** role (computes no ML), the CLI publishes an inference `WorkCommand`,
and **all five** inference panels are asynchronous over `/api/ws/inference` via
the typed-decode pipeline (Engine `decodeInference` → `decoded-*` `WorkResult` →
bridge `DecodedInference` → thin pure render), with **CheckpointCompare** and
**Connect4** moved to Engine workflows (delta + MCTS computed in the daemon).
Validated: `cabal build all` clean, `jitml-unit` 208/208, `jitml-e2e` 23/23,
`spago build` 0 errors + `spago test` 17/17, `jitml lint purescript`/`docs
check`/`check-code` ok, and live on `linux-cpu` (Webapp pod serves the bundle;
CLI publish round-trip via `jitml-integration`). The **live Playwright product
proof** of the panels transfers to Sprints `14.2` / `16.x` (rule E / M(a)).
**Depends-On**: Sprint `5.14` (one-binary role model — the `Webapp` role), Sprint
`10.7` (async `Work*` inference workflow + envelope family)
**Implementation**: `jitml.cabal` (retire `exe:jitml-demo`), `app/Demo.hs`
(retired), `src/JitML/App.hs` (`runWebappRole`; retired `demoMain`,
`demoBrowserRuntimeHandler`, `weightedInferenceForBrowser`), `src/JitML/Web/Server.hs`,
`src/JitML/Service/WebSocket.hs`, `web/src/Panels/{Mnist,GenericInference,Cifar,CheckpointCompare,Connect4}.purs`,
`web/src/Generated/Contracts.purs`
**Docs to update**: `../documents/engineering/purescript_frontend.md`,
`../documents/engineering/pulsar_ml_workflow.md`, `system-components.md`,
`legacy-tracking-for-deletion.md`

### Objective

Fold `jitml-demo` into the one-binary **Webapp** role (a thin websocket server
that talks only to Pulsar + MinIO and **computes no inference**) and make the
browser inference panels **websocket-driven** via snapshot/patch frames — the same
`subscribeStream` pattern the training/RL/tune panels already use. Because the
Webapp is substrate-agnostic, this **dissolves the Apple in-pod-Metal
browser-forward** problem (the webapp publishes `inference.request.<substrate>` and
never touches Metal). Implements `The three roles` (Webapp) and the `Websocket
surface` of
[../documents/engineering/pulsar_ml_workflow.md](../documents/engineering/pulsar_ml_workflow.md);
retires the "Two-binary `jitml-demo` split", "Demo in-process inference compute",
and "Synchronous inference REST + PureScript fetch panels" ledger rows.

### Deliverables

- Retire `exe:jitml-demo` / `app/Demo.hs` / `JITML_DEMO_*` env selection; the
  Webapp runs as `jitml service` with `activeRole = Webapp` (Sprint `5.14`).
- Remove in-process demo compute (`demoBrowserRuntimeHandler`,
  `weightedInferenceForBrowser`) and the synchronous `withTimedRuntime` REST
  handlers; the Webapp publishes a `WorkCommand` (Sprint `10.7`) and renders the
  streamed `WorkResult` over websocket snapshot/patch frames.
- Convert `web/src/Panels/{Mnist,GenericInference,Cifar,CheckpointCompare,Connect4}.purs`
  from blocking `requestText` fetch to `subscribeStream`; static artifacts and
  uploads move via MinIO presigned URLs; no business logic in the browser.
- **CLI publish-only (transferred from Sprint `10.7`).** `jitml inference run`
  publishes a `JitML.Work.Envelope.WorkCommand` (inference `WorkCommand` →
  `inference.request.<substrate>`) and renders the streamed `WorkResult` from the
  reply topic, instead of computing in-process via `engineWeightedInference`; it
  shares the same publish/consume client this sprint builds for the Webapp. The
  Engine (daemon) becomes the sole inference computer.
- Move the three named ledger rows to `Completed`.

### Validation

- `jitml lint purescript` + the generated-contract spec.
- `docker compose run --rm jitml jitml test jitml-e2e --linux-cpu`.
- Live websocket inference panels on the routed edge are owned by Sprint `14.x`
  (Playwright) and the Phase `15`/`16` live lanes; per standards rule M(b) this
  sprint closes on the `linux-cpu` lint/e2e proof.
- `docker compose run --rm jitml jitml docs check` and `jitml check-code`.

### Validation State (in-container build + baked style tools + live `linux-cpu`)

- **CLI publish-only landed and live-validated.** `jitml inference run` no longer
  computes in-process: `requestInferenceViaEngine` (`src/JitML/App.hs`) publishes an
  inference `WorkCommand` (the `Inference.InferenceRequest` wire form) to
  `inference.request.<substrate>` and renders the streamed `WorkResult` from the
  reply topic; a new `JitML.Proto.Inference.parseInferenceResult` decodes the
  Engine's reply. The single Engine (daemon) is the only role that computes and
  owns the `.ready` gate. Validated **live**: against a running `linux-cpu` cluster
  `jitml test jitml-integration --linux-cpu` passes **71 / 71**, with the "live
  jitml inference run reads checkpoint from live MinIO" case now exercising the
  publish→Engine→reply path. `hlint` (no hints) and `fourmolu --mode check` (clean)
  on `App.hs` + `Inference.hs` via the baked `jitml:local` style tools.

- **Webapp role serve-path foundation landed.** `runService` now dispatches on
  `BootConfig.bootActiveRole` (Sprint `5.14`): `activeRole = Webapp` runs
  `runWebappRole` (serves the compiled browser bundle + held-open `/api/ws` Pulsar
  bridge from typed Dhall config) with a **publish-only** browser-runtime handler
  that calls `requestInferenceViaEngine` (the Engine computes, the Webapp does
  not); every other role runs `runEngineServe` (the unchanged Engine path). A new
  optional `BootConfig.bootWebappPulsarWsUrl` carries the broker WebSocket endpoint
  the Webapp bridge/publish client needs (reflected into the schema; `Engine`
  configs set `None`). Validated: in-container `cabal build` clean, `hlint` (no
  hints) + `fourmolu --mode check` clean, `jitml-unit` **206/206** (reflected
  `BootConfig` schema parity holds with the new field), `jitml-daemon-lifecycle`
  **35/35**.

- **Webapp role fold complete + live-validated.** `exe:jitml-demo` / `app/Demo.hs`
  / `demoMain` / `demoBrowserRuntimeHandler` (in-process compute) and their
  orphaned helpers are deleted; the `Demo.hs` build/`cp` is removed from
  `docker/Dockerfile`. The `jitml-demo` chart deployment runs `jitml service
  --config /etc/jitml/BootConfig.dhall` against a `jitml-webapp-config` ConfigMap
  (`activeRole = Webapp`, `webappPulsarWsUrl = ws://pulsar-broker…:8080/ws`);
  `jitml-demo:local` remains a retag of `jitml:local` (which carries the `jitml`
  binary + the baked bundle). **Live on `linux-cpu`:** the redeployed pod logs
  `webapp: serving 0.0.0.0:80` and the routed edge serves `/` (demo HTML, 200) and
  `/bundle/main.js` (340 KB Halogen bundle, 200). The Webapp's handler publishes a
  `WorkCommand` to the Engine (no in-process compute). Validated: image
  `check-code` clean, `jitml-unit` 206/206, `jitml-daemon-lifecycle` 35/35,
  `jitml-e2e` 23/23 (no golden breaks). The "Two-binary `jitml-demo` split" +
  "Demo in-process inference compute" ledger rows moved to `Completed`.

- **Inference result-stream foundation landed.** Added the `/api/ws/inference`
  websocket route (`src/JitML/Web/Server.hs`) forwarding
  `inference.result.<substrate>` (the Engine's `WorkResult` topic) — the
  snapshot/patch stream the panels subscribe to — plus its generated-contract
  surface (`demoRoutes`, the `InferenceStream` `ApiEndpoint`, regenerated
  `web/src/Generated/Contracts.purs`). Validated: `jitml-unit` 206/206,
  `jitml-e2e` 23/23, `jitml lint purescript: ok`, hlint/fourmolu clean.

- **Design of record — Engine-decodes-into-a-typed-result (pure + bridged).**
  Output decoding (logits → top-class/probabilities/etc.) is __not__ done in the
  webapp or PureScript (both stay thin). The __Engine__ decodes once, via a single
  pure function over the checkpoint's `OutputDecoder`, producing a typed
  `DecodedInference` ADT (one variant per `OutputDecoderKind`:
  classification/regression/policy/value/MCTS/replay/generic). That typed value
  travels the `Work*` result wire, the purescript-bridge-compatible renderer
  reflects the same type into PureScript, and the panels render it with a pure
  render — one pure type, one pure decode, one pure render. (This also retires the
  small contract smell of the webapp REST handler computing argmax/softmax.)
- **Keystone landed + validated:** `JitML.Inference.Decode` (`DecodedInference`,
  `decodeInference`, `firstOutputDecoder`/`decodeManifestOutput`,
  `renderDecodedInference`, pure `softmax`/`argmax` matching the prior webapp
  `probabilityVector`/`topIndex`). `jitml-unit` **207/207** (decode + render
  cases), hlint/fourmolu clean.
- **Step 1 (Engine decode-emit) landed + validated.** `loadInferenceCheckpointWithWeights`
  was refactored to a shared `withWeightedCheckpoint` core, with a new
  `loadInferenceCheckpointDecodedWithWeights` that applies the manifest's output
  decoder; the daemon's `runInferenceRequestWithWeightedInference`
  (`JitML.Service.Workload`) now appends the typed `decoded-*` lines to the
  `inference.result` `WorkResult` (additive — the base `output` line is untouched,
  so `jitml inference run` and the live integration are unaffected). Validated:
  in-container build clean, hlint/fourmolu clean, `jitml-unit` 207/207,
  `jitml-daemon-lifecycle` 35/35.

- **Step 2 (bridge reflection) landed + validated.** `renderPureScriptContracts`
  now emits a typed PureScript `DecodedInference` record (discriminated by `kind`)
  + a lenient `parseDecodedInference` for the `decoded-*` wire lines (+ a
  `stringListField` helper); `web/src/Generated/Contracts.purs` regenerated.
  Validated: `jitml lint purescript: ok` (parity), **`spago build` 0 errors/0
  warnings** (the generated PureScript compiles), `jitml-unit` 207/207,
  `jitml-e2e` 23/23. So the typed-decode __pipeline is complete end to end__:
  Engine `decodeInference` → `decoded-*` `WorkResult` wire → PureScript
  `DecodedInference` + parser.

- **Step 3 (uniform single-inference panels) landed + validated.** The Webapp
  handler (`runWebappRole`) now branches on `BrowserRuntimeSurface`:
  `Inference`/`Generic`/`Image` __publish fire-and-forget__
  (`publishInferenceRequestOnly`, return an ack) while `Compare`/`Adversarial`
  keep the synchronous publish-and-await path (a new `BrowserRuntimeCompare`
  surface decouples checkpoint-compare's two inferences from the generic
  surface). The three single-inference panels
  (`web/src/Panels/{Mnist,GenericInference,Cifar}.purs`) now
  `subscribeStream "/api/ws/inference"`, publish on the user action, and render
  the Engine-decoded `parseDecodedInference` frame matched by `experiment-hash`
  — __no browser compute__. Validated: `cabal build all` clean, hlint/fourmolu
  clean, **`spago build` 0 errors + `spago test` 16/16** (new
  `parseDecodedInference` case), `jitml lint purescript: ok`, `jitml-unit`
  207/207, `jitml-e2e` 23/23, `jitml-daemon-lifecycle` 35/35.

- **Step 3 (heterogeneous panels — Engine workflows) landed + validated.** The
  contract's "the Engine is the only role that computes" required moving the two
  webapp-side computations into the daemon as new __Engine workflows__, riding the
  existing `inference.request`/`inference.result` topics + `/api/ws/inference`
  stream with new command kinds:
  - **CheckpointCompare** — `CheckpointCompareCommand` → daemon runs both
    inferences + computes the delta (`runCheckpointCompareRequestWithWeightedInference`,
    reusing `loadInferenceCheckpointDecodedWithWeights`) → `CheckpointCompareResult`
    on the stream → panel renders the `CompareFrame`.
  - **Connect4** — `AdversarialMoveCommand` → daemon runs the policy/value
    inference __and__ the MCTS tree search (relocated to the pure
    `JitML.Inference.AdversarialMove`) → `AdversarialMoveResult` → panel renders
    the `MoveFrame`.

  The Webapp role publishes both commands fire-and-forget
  (`publishCheckpointCompareCommandOnly` / `publishAdversarialMoveCommandOnly` via
  the injected `BrowserCommandPublishers`); the synchronous handler path remains
  only as the no-publisher test fallback. Both panels
  (`CheckpointCompare.purs`, `Connect4.purs`) now `subscribeStream
  "/api/ws/inference"` and render the Engine-computed frame matched by
  `experiment-hash` — __no webapp or browser compute__. Validated: `cabal build
  all` clean, hlint/fourmolu clean, **`spago build` 0 errors + `spago test`
  16/16**, `jitml lint purescript: ok`, `jitml-unit` 208/208 (compare/move
  envelope round-trip + MCTS-legality case), `jitml-e2e` 23/23,
  `jitml-daemon-lifecycle` 35/35.

### Remaining Work

- Live Playwright proof of the five async panels is downstream (Sprints `14.2` /
  `16.11`). **All 5/5 inference panels are now asynchronous to the browser and the
  Engine is the only role that computes** (decode, delta, and MCTS all run in the
  daemon).

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
