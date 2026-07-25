# Phase 39: Envoy Gateway and Single `127.0.0.1:<edge-port>` Listener

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Envoy Gateway and Single 127.0.0.1:<edge-port> Listener. Single-session phase migrated from legacy Sprint 3.3 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 39.1: Envoy Gateway and Single `127.0.0.1:<edge-port>` Listener [✅ Done]

**Status**: Done
**Implementation**: `chart/templates/gatewayclass-jitml.yaml`,
`chart/templates/gateway-jitml-edge.yaml`,
`chart/templates/envoyproxy-jitml-edge.yaml`, `src/JitML/Cluster/Gateway.hs`
**Docs to update**: `documents/engineering/cluster_topology.md`

### Objective

Stand up the Envoy Gateway controller deployment and the single edge listener
at `127.0.0.1:<edge-port>` backed by the in-cluster NodePort `30090`.

### Deliverables

- `GatewayClass/jitml-gateway` declares the Envoy Gateway controller as the
  controller name and references `EnvoyProxy/jitml-edge` through
  `parametersRef`.
- `Gateway/jitml-edge` listens on port `<edge-port>` (templated; the actual port
  is selected by `jitml bootstrap --<substrate>` starting at `9090` and incremented until
  available).
- `EnvoyProxy/jitml-edge` is a NodePort service with `externalTrafficPolicy:
  Cluster`; the Gateway listener port is pinned to NodePort `30090` for the
  Kind host-port mapping.
- The `gateway-helm` subchart in `chart/Chart.yaml` provides the Envoy Gateway
  controller.
- `src/JitML/Cluster/Gateway.hs` is the typed source for the Gateway shape;
  templates are present in the chart and checked locally.

### Validation

1. `chart/templates/gatewayclass-jitml.yaml`,
   `chart/templates/gateway-jitml-edge.yaml`, and
   `chart/templates/envoyproxy-jitml-edge.yaml` exist in the chart.
2. `src/JitML/Cluster/Gateway.hs` renders the Gateway shape.
3. Live `kubectl get gateway` and `curl` validation against a real
   cluster is validated by Sprint `3.5`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
