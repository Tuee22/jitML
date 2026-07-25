# Phase 141: Demo Endpoints Render Real Substrate Output

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Demo Endpoints Render Real Substrate Output. Single-session phase migrated from legacy Sprint 11.8 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 141.1: Demo Endpoints Render Real Substrate Output [✅ Done]

**Status**: Done (historical; server-side inline response functions removed by
Phase `10` Sprint `10.6`)
**Implementation**: historical `src/JitML/Web/Server.hs` inline response
functions removed by Sprint `10.6`; panels under
`web/src/Panels/*`, `web/src/Panels/Api.{purs,js}`,
`web/src/Panels/Stream.js`, `playwright/jitml-demo.spec.ts`
**Docs to update**: `../documents/engineering/purescript_frontend.md`, `system-components.md`

### Objective

Make the demo endpoints render real model output instead of constants, and make
the panels issue real fetches over the typed contracts. Owns the frontend slice
of [Exit Definition](README.md#exit-definition) item 6/7.

### Deliverables

- Historical Sprint `11.8` state: `Web.Server` `/api/inference` ran the real
  policy/value network forward (`PolicyValueNet.networkPolicyValue`) and
  reported the value/policy heads; `/api/images` ran the same policy/value
  network over the demo board state and reported a top-k probability vector
  instead of an upload acknowledgement; `/api/connect4/move` ran the real MCTS
  tree search (`PolicyValueNet.mctsVisitDistribution`) and returned the
  highest-visit move —
  no hard-coded column, no synthetic manifest-only number. Sprint `10.6`
  supersedes this server implementation by removing the inline networks and
  returning `503 checkpoint-required`; Sprint `11.9` later restored the routes
  through an injected checkpoint runtime handler.
- The panels issue real HTTP fetches over the generated contracts and parse the
  typed responses; the dead `*Received` handlers, the raw `LiveFrame String`
  path, and the `Stream.js` socket-failure swallow are removed.
- Playwright asserts real rendered values (not just DOM visibility) against the
  live demo edge route.

### Validation

- `docker compose run --rm jitml jitml check-code` (the `Web.Server` change)
  and `jitml lint purescript` (the panel rewrite).
- Live: `playwright/jitml-demo.spec.ts` against `jitml bootstrap --<substrate>`.

### Current Validation State

Historical landed state: the `Web.Server` `/api/inference`, `/api/images`, and
`/api/connect4/move` endpoints ran the real network forward / image top-k
render / real MCTS path (pure, host lib type-checks; container `check-code`
validated at the Phase 11 boundary). Sprint `10.6` later removed those inline
endpoint bodies and made the routes fail closed; Sprint `11.9` later restored
the routes through an injected checkpoint runtime handler. On 2026-06-11 the panels were
rewired through `Panels.Api.requestText`, `Panels.Stream.openWebSocket` now reports
failures, raw `LiveFrame String` storage was removed from the RL / training /
tuning panels, and `docker compose run --rm jitml jitml lint purescript`
returned `ok`. The final CUDA-machine rebuild passed `docker compose build
jitml` (`check-code: ok` plus the PureScript bundle), the rebuilt images were
loaded into the `linux-cuda` Kind cluster, and the Playwright suite now asserts
live values, not just DOM visibility: MNIST waits for `/api/inference` and checks
the rendered prediction badge, CIFAR waits for `/api/images` and checks the
response + attached top-k result list, and Connect 4 waits for
`/api/connect4/move` and checks the rendered move list. The container-only live
run passed **9 / 9** against the published `linux-cuda` edge route, and
`docker compose run --rm jitml-cuda jitml test jitml-e2e --linux-cuda` passed
**20 / 20** after the same server/frontend rebuild.

### Remaining Work

- None. Apple Silicon can re-run the same live Playwright suite under Phase `16`
  once Sprint `16.8` is on an Apple host; no Phase `11` code-surface obligation
  remains.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
