# Phase 48: kube-prometheus-stack and Provisioned Dashboards

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: kube-prometheus-stack and Provisioned Dashboards. Single-session phase migrated from legacy Sprint 4.5 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 48.1: kube-prometheus-stack and Provisioned Dashboards [✅ Done]

**Status**: Done
**Implementation**: `chart/values.yaml`,
`src/JitML/Observability/Grafana.hs`,
`src/JitML/Observability/Prometheus.hs`
**Docs to update**: `documents/engineering/daemon_architecture.md`

### Objective

Install the kube-prometheus-stack (Prometheus operator + Grafana) and provision
Grafana dashboards from typed Haskell renderers. Prometheus scrape configs name
the daemon's `/metrics` endpoint.

### Deliverables

- `kube-prometheus-stack` subchart pinned.
- `src/JitML/Observability/Grafana.hs` renders typed dashboards (training
  throughput, RL episode reward, AlphaZero arena win rate, JIT cache hit rate,
  Pulsar consumer lag, MinIO PUT latency, daemon health), writes provisioned
  ConfigMaps under `chart/templates/grafana-dashboard-*.yaml`, and protects
  those YAML files through `trackingGeneratedPaths`.
- `src/JitML/Observability/Prometheus.hs` declares the typed scrape-target
  list for the `jitml-service` daemon's `/metrics` endpoint, renders
  `chart/templates/prometheus-scrapeconfig-jitml.yaml` with the
  `release=kube-prometheus-stack` selector label, and protects it through
  `trackingGeneratedPaths`.
- `chart/local/jitml-service/templates/service.yaml` exposes the daemon on
  ClusterIP port `8080` so Prometheus has a stable in-cluster scrape target.
- HTTPRoutes for `/grafana` and `/prometheus` (Sprint `3.4`).

### Validation

1. `src/JitML/Observability/Grafana.hs` renders the dashboard surface.
2. `src/JitML/Observability/Prometheus.hs` renders the scrape-target
   surface.
3. Live Linux CPU validation on 2026-05-18 confirms the kube-prometheus-stack
   operator, Grafana, kube-state-metrics, and Prometheus rollouts reach Ready.
4. Live Linux CPU validation on 2026-05-19 confirms Grafana serves all seven
   generated jitML dashboards behind `/grafana` (`training-throughput`,
   `rl-episode-reward`, `alphazero-arena`, `jit-cache`,
   `pulsar-consumer-lag`, `minio-put-latency`, `daemon-health`), and
   Prometheus reports
   `http://jitml-service.platform.svc.cluster.local:8080/metrics` as `up`
   through the routed `/prometheus` API.

### Closure State

- The live rollout applies the generated Grafana dashboard ConfigMaps and the
  generated Prometheus `ScrapeConfig` after the kube-prometheus-stack and
  `jitml-service` local charts are installed. The dashboard ConfigMaps use
  unique data keys (`<dashboard-name>.json`) so the Grafana sidecar writes
  every dashboard to a distinct file under `/tmp/dashboards`.
- The generated `ScrapeConfig` carries label
  `release: kube-prometheus-stack`, matching the Prometheus CR's
  `scrapeConfigSelector`, and targets only
  `jitml-service.platform.svc.cluster.local:8080` because that daemon service
  exposes the implemented `/metrics` endpoint.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
