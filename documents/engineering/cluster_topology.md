# Cluster Topology

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: README.md, ../documentation_standards.md, ../../DEVELOPMENT_PLAN/phase-0-planning-documentation.md, ../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md, ../../DEVELOPMENT_PLAN/phase-2-bootstrap-reconciler-and-jit-cache.md, ../../DEVELOPMENT_PLAN/phase-3-cluster-substrate-and-routing.md, ../../DEVELOPMENT_PLAN/phase-4-stateful-platform-services.md, ../../DEVELOPMENT_PLAN/phase-5-jitml-service-daemon.md, daemon_architecture.md
**Generated sections**: cluster.routes

> **Purpose**: Project-specific cluster topology for jitML — Kind cluster
> shapes per substrate, the umbrella Helm chart, the storage discipline, the
> Envoy Gateway listener, the typed route registry, and the no-kubeconfig-
> pollution invariant.

## Substrates and Cluster Shapes

| Substrate | Kind shape | Worker labels | Daemon residency |
|-----------|------------|---------------|------------------|
| `apple-silicon` | 1 control-plane + 1 worker | none | clustered (`Cluster + ForwardToHost`) + host-native (`Host + SelfInference`) |
| `linux-cpu` | 1 control-plane + 1 worker | none | clustered only (`Cluster + SelfInference`) |
| `linux-cuda` | 1 control-plane + 1 worker | `jitml.runtime/gpu=true` | clustered only (`Cluster + SelfInference`) |

Per-substrate Kind configs at `kind/cluster-<substrate>.yaml`. The `kindest/
node` pin is the single source of toolchain truth; it is mirrored as a
comment in `cabal.project`. `jitml lint chart` rejects drift between the two.

The host `./.build/` directory is bind-mounted into the Kind worker via the
`extraMounts` block in the Kind config. This is what lets the in-cluster
`jitml-service` pod see the same JIT artefacts the host built. This is the
**one** exception to the "no freestanding host paths in pod specs"
discipline; the chart lint permits exactly this hostPath and rejects any
other.

## Storage Discipline: `kubernetes.io/no-provisioner` Only

Every StorageClass uses the `kubernetes.io/no-provisioner` provisioner — no
dynamic provisioning anywhere in the chart. Every PV is **manually defined**
in `chart/templates/pv-<statefulset>.yaml` against the `jitml-manual`
StorageClass and backed by a `hostPath` under
`./.data/kind/<substrate>/<namespace>/<statefulset>/pv_<replica-int>/`.

Every PVC is created **only** by a StatefulSet's `volumeClaimTemplates`;
freestanding PVCs are a chart-lint failure. Each PV's `claimRef.namespace`
and `claimRef.name` explicitly bind it to one PVC so a teardown / spinup
yields the exact same binding. Dynamic provisioning would erode
reproducibility.

Naming convention is uniform:

- on disk: `<k8s-namespace>/<StatefulSet-name>/pv_<replica-int>`
- as a PV resource: `<namespace>-<statefulset>-pv-<int>` (DNS-1123 compatible)

Example layout for the `platform` namespace on the Apple Silicon substrate:

```
.data/kind/apple-silicon/
└── platform/
    ├── minio/{pv_0, pv_1, pv_2, pv_3}                  -- 4 distributed replicas
    ├── pulsar-bookkeeper/{pv_0, pv_1, pv_2}            -- 3 bookies
    └── pulsar-zookeeper/{pv_0, pv_1, pv_2}             -- 3 ZK nodes
```

`jitml lint files` rejects any path under `.data/` that does not match the
`<substrate>/<namespace>/<statefulset>/pv_<int>` regex. `jitml lint chart`
rejects any StorageClass with a provisioner other than
`kubernetes.io/no-provisioner`, any freestanding PVC, and any PV without an
explicit `claimRef`.

## Helm Chart Layout

Single umbrella chart at `chart/`. `Chart.yaml` declares subchart
dependencies:

| Subchart | Purpose | Owning sprint |
|----------|---------|---------------|
| `harbor` | Image registry | Sprint 4.1 |
| `pg-operator` + `pg-db` | Percona Operator HA Postgres for Harbor (jitML itself never writes to it) | Sprint 4.2 |
| `pulsar` | Apache Pulsar HA (3× ZooKeeper, 3× BookKeeper, 3× Broker, 3× Proxy, WebSocket) | Sprint 4.4 |
| `minio` | Distributed-mode object store (4 replicas) | Sprint 4.3 |
| `gateway-helm` | Envoy Gateway controller | Sprint 3.3 |
| `kube-prometheus-stack` | Prometheus operator + Grafana | Sprint 4.5 |
| `tensorboard` | jitML-owned chart with MinIO event-storage backing | Sprint 4.6 |

Templates in `chart/templates/`: GatewayClass, Gateway, HTTPRoutes (rendered
from the route registry), EnvoyProxy, manual PVs (one per replica),
`jitml-service` Deployment, `jitml-demo` Deployment, NVIDIA RuntimeClass for
the CUDA substrate, Grafana datasources and dashboards (provisioned
ConfigMaps), Prometheus scrape configs.

## Phased Deploy

`jitml cluster up` runs the phased rollout (verbatim from infernix's
lessons):

1. **Bootstrap phase**: Harbor + MinIO + Postgres only, pulling images from
   public registries.
2. **Mirror phase**: every third-party image is mirrored into Harbor.
3. **Final phase**: Pulsar, Envoy Gateway, kube-prometheus-stack,
   TensorBoard, the `jitml-service` workload (Linux substrates), the
   `jitml-demo` workload — all pulling exclusively from local Harbor.

This avoids the chicken-and-egg of "Harbor isn't up yet, but everything wants
to pull from it" without resorting to image-pull-secret juggling.

## `jitml-service` Deployment, Not StatefulSet

The orchestrator is a stateless **Deployment** with `replicas: 1` by default
and pod **anti-affinity** at `topologyKey: kubernetes.io/hostname`, which
lets the cluster scale to N replicas (one per node) when throughput requires
it without ever placing two on the same node. The daemon owns no PVC of its
own — durable state lives entirely in MinIO and Pulsar — so a StatefulSet
would be the wrong shape.

Each node maintains its own JIT cache under that node's
`./.build/jit/<substrate>/` hostPath. JIT artifacts are deterministic
functions of `(model-shape, kind, substrate, toolchain)`, so the worst case
is that the same model gets JITted once per node on first use.

Namespace: `platform` (fixed). `jitml cluster up` creates it idempotently.

## Envoy Gateway: A Single Localhost Socket

There is **one user-facing socket**: `127.0.0.1:<edge-port>`. Selected by
`jitml cluster up` starting at `9090` and incremented until available.
Recorded as the `edge_port` field of `./.data/runtime/cluster-publication.json`
alongside `pulsar_ws_url`, `pulsar_admin_url`, `minio_s3_url`. `jitml cluster
status` reads this file.

The shape:

- `GatewayClass/jitml-gateway` declares the Envoy Gateway controller.
- `Gateway/jitml-edge` listens at `127.0.0.1:<edge-port>`.
- `EnvoyProxy/jitml-edge` is a NodePort service, `externalTrafficPolicy:
  Cluster`, port `30090` in-cluster.

Routes are rendered from the typed route registry in `src/JitML/Routes.hs`.
Hand-written HTTPRoute YAML is hlint-forbidden.

## Routes Published at the Edge

<!-- jitml:cluster.routes:start -->
| Path prefix | Upstream | Rewrite |
|---|---|---|
| `/` | `jitml-demo:80` (PureScript bundle) | (none) |
| `/api` | `jitml-demo:80` | (none) |
| `/api/ws` | `jitml-demo:80` (WebSocket) | (none) — live training events |
| `/tensorboard` | `tensorboard:6006` | `/` |
| `/grafana` | `grafana:3000` | `/` |
| `/prometheus` | `prometheus:9090` | `/` |
| `/harbor` | `jitml-harbor-portal:80` | `/` |
| `/harbor/api` | `jitml-harbor-core:80` | `/api` |
| `/minio/console` | `jitml-minio-console:9090` | `/` |
| `/minio/s3` | `jitml-minio:9000` | `/` |
| `/pulsar/admin` | `jitml-pulsar-proxy:80` | `/admin` |
| `/pulsar/ws` | `jitml-pulsar-proxy:80` (WebSocket) | `/ws` |
<!-- jitml:cluster.routes:end -->

This table is regenerated from the route registry (Sprint `3.4`) by
`jitml docs generate`. Hand edits fail `jitml docs check`.

TLS is off for the local demo. The production-deployment posture is
intentionally not specified.

## No Kubeconfig Pollution

The CLI never touches `~/.kube/config`. Cluster kubeconfig lives at
`./.build/jitml.kubeconfig`. The bootstrap scripts forbid touches to
`~/.kube/config`, `~/.docker/config.json`, the user's global Homebrew prefix
as a writer, or any global state outside the repo. All build state lives
under `./.build/`; all runtime state lives under `./.data/`.

## Cross-References

- [../README.md → Cluster topology and Kind](../README.md#cluster-topology-and-kind)
- [../README.md → Envoy Gateway API](../README.md#envoy-gateway-api-a-single-localhost-socket)
- [../README.md → Helm chart layout](../README.md#helm-chart-layout)
- [daemon_architecture.md](daemon_architecture.md)
- [../../DEVELOPMENT_PLAN/phase-3-cluster-substrate-and-routing.md](../../DEVELOPMENT_PLAN/phase-3-cluster-substrate-and-routing.md)
- [../../DEVELOPMENT_PLAN/phase-4-stateful-platform-services.md](../../DEVELOPMENT_PLAN/phase-4-stateful-platform-services.md)
