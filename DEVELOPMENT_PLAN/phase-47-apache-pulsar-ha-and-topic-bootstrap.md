# Phase 47: Apache Pulsar HA and Topic Bootstrap

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Apache Pulsar HA and Topic Bootstrap. Single-session phase migrated from legacy Sprint 4.4 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 47.1: Apache Pulsar HA and Topic Bootstrap [✅ Done]

**Status**: Done
**Implementation**: `chart/values.yaml`,
`chart/values/pulsar.yaml`, `chart/templates/httproute-pulsar-ws.yaml`,
`src/JitML/Cluster/PulsarBootstrap.hs`,
`src/JitML/Service/PulsarWebSocketSubprocess.hs`, `src/JitML/Routes.hs`
**Docs to update**: `documents/engineering/daemon_architecture.md`

### Objective

Install Apache Pulsar in HA shape (3× ZooKeeper, 3× BookKeeper, 3× Broker, 3×
Proxy, WebSocket enabled) and bootstrap the substrate-scoped topic family.

### Deliverables

- `pulsar` subchart at a pinned HA release.
- 3 ZooKeepers, 3 BookKeepers, 3 Brokers, 3 Proxies, WebSocket enabled through
  broker config `webSocketServiceEnabled=true`.
- The direct local values file `chart/values/pulsar.yaml` sets
  `proxy.service.type=ClusterIP` so Helm `--wait` is valid in Kind without a
  cloud load balancer.
- `src/JitML/Cluster/PulsarBootstrap.hs` declares the typed topic family from
  [system-components.md → Pulsar Topic
  Family](system-components.md#pulsar-topic-family) and renders the
  idempotent `/pulsar/bin/pulsar-admin topics list` / `topics create`
  commands executed from `pulsar-toolset-0` after the phased bootstrap rollout.
  The registered family is derived from `JitML.Coordinator.Topology`: ten
  substrate-scoped workflow/phase topics per substrate plus the Apple-only
  `inference.command.apple-silicon` forward topic and host-command topics.
- HTTPRoutes for `/pulsar/admin` and `/pulsar/ws` (Sprint `3.4`).
  `/pulsar/ws` rewrites to `/ws` and now targets `pulsar-broker:8080`, the
  broker HTTP service that owns the embedded WebSocket endpoint.
- `JitML.Service.PulsarWebSocketSubprocess` is the live persistent WebSocket
  `HasPulsar` interpreter for the routed local edge. It publishes with Node's
  WebSocket constructor, with an `undici.WebSocket` fallback for older Node
  runtimes. The current `jitml:local` image carries Node.js `22.16.0`. Opaque
  typed subscriptions yield receipt-bearing deliveries, and the scoped
  interpreter applies exactly one handler disposition before it requests more
  work or drains. Sprint `5.18` supersedes the historical one-shot surface.

### Validation

1. `src/JitML/Cluster/PulsarBootstrap.hs` renders the typed topic-command
   surface; `jitml-integration` asserts the 34-topic derived family and rejects
   the retired `*.cluster` / `*.host` topics.
2. The route registry includes `/pulsar/admin` and `/pulsar/ws`.
3. Live Linux CPU validation on 2026-05-18 reaches Ready Pulsar components and
   creates every topic in
   [system-components.md → Pulsar Topic Family](system-components.md#pulsar-topic-family).
4. Live Linux CPU validation on 2026-05-19 confirms
   `pulsar-broker-0` carries `webSocketServiceEnabled=true`, HTTPRoute
   `pulsar-ws` is `Accepted=True` / `ResolvedRefs=True` against
   `pulsar-broker:8080`, and Gateway `jitml-edge` is `Programmed=True`.
5. Live Linux CPU validation on 2026-05-19 confirms every registered topic in
   [system-components.md → Pulsar Topic Family](system-components.md#pulsar-topic-family)
   exists in `public/default`.
6. Live Linux CPU validation on 2026-05-20 reconciled the then-current 26-topic
   substrate-scoped family into `jitml-linux-cpu` through `pulsar-toolset-0`.
   The current tree now derives 34 topics from `JitML.Coordinator.Topology`; the
   live bootstrap creates that derived set.
7. Live Linux CPU validation on 2026-05-19 opens a routed WebSocket consumer at
   `ws://127.0.0.1:9091/pulsar/ws/v2/consumer/...`, publishes through the
   matching routed producer endpoint, receives the same payload, and sends the
   WebSocket ack.
8. Live Linux CPU validation on 2026-05-19 exercises
   `JitML.Service.PulsarWebSocketSubprocess` through the same route:
   `pulsarPublish` returns broker message id `CBQQAjAA`, and concurrent
   `pulsarConsume` returns
   `("persistent://public/default/training.command.linux-cpu",
   "phase4-haskell-pulsar-1779216327")`.
9. Live Linux CPU validation on 2026-05-20 exercises the current routed topic
   `persistent://public/default/training.command.linux-cpu` from
   `jitml:local` through the WebSocket subprocess path;
   publish/consume succeeds through `/pulsar/ws`, returning broker message id
   `CDEQADAA`.
10. `cabal test jitml-integration` covers the rendered
   `JitML.Service.PulsarWebSocketSubprocess` command surface and asserts the
   producer and consumer target `/pulsar/ws/v2/...` on the routed local edge.
11. Live Linux CPU validation on 2026-05-19 confirms the direct Pulsar values
   upgrade the release to `deployed` in Kind with `proxy.service.type=ClusterIP`;
   leaving the upstream `LoadBalancer` default caused Helm `--wait` to fail
   despite Ready pods.

### Closure State

- `JitML.Cluster.PulsarBootstrap.pulsarTopicCreateSubprocesses` is appended to
  the typed `liveExecutePhasedRollout` step list in `JitML.Bootstrap`, so
  `jitml bootstrap --<substrate>` invokes `kubectl --kubeconfig
  ./.build/jitml.kubeconfig exec -n platform pulsar-toolset-0 -- sh -c
  '<list namespace>; <create if absent>' <topic>` for every registered topic
  after the phased Helm rollout completes. The script uses the chart's explicit
  `/pulsar/bin/pulsar-admin` path and treats an already-created topic as
  reconciled. The registered set matches the substrate-scoped Pulsar topic
  family: training, tune, RL, and inference request/result command/event topics
  for `apple-silicon`, `linux-cpu`, and `linux-cuda`, plus the Apple-only
  internal inference RPC pair.
- `chart/values.yaml` and `chart/values/pulsar.yaml` set
  `broker.configData.webSocketServiceEnabled: "true"`, enabling Pulsar's
  broker-embedded WebSocket service on port `8080`.
- `chart/values/pulsar.yaml` also sets `proxy.service.type: ClusterIP`,
  matching the single Envoy Gateway edge model instead of waiting for a
  cloud load balancer that Kind does not provide.
- The `/pulsar/ws` route no longer points at `pulsar-proxy`; it rewrites to
  `/ws` and targets `pulsar-broker:8080`, which serves `/ws/v2/producer/...`
  and `/ws/v2/consumer/...`.
- `JitML.Service.PulsarWebSocketSubprocess` validates the routed
  publish/consume path through the `HasPulsar` class. Sprint `5.18` supersedes
  the dated one-shot implementation described by Sprint `4.4`: the current
  interpreter keeps a persistent connection, keeps broker message ids private,
  settles each opaque receipt from one handler disposition, reconnects without
  accepting new work ahead of pending settlement, and drains before scoped
  cleanup. Its Node script uses `globalThis.WebSocket` when present and
  `require('undici').WebSocket` otherwise, so the path remains compatible with
  older Node runtimes while current `jitml:local` carries Node.js `22.16.0`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
