# Phase 168: Ephemeral Kind + Helm Rollout

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Ephemeral Kind + Helm Rollout. Single-session phase migrated from legacy Sprint 15.1 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 168.1: Ephemeral Kind + Helm Rollout [✅ Done]

**Status**: Done (re-validated 2026-06-06 on RTX 5090; previously Done on RTX 3090) (closed 2026-05-29 after the reopened-scope live re-verification
on `linux-cuda` — see the **Live re-verification (2026-05-29 …)** block in the
Remaining Work section. The 75-step typed phased rollout converged with all 39
pods Running/Completed under the 10 GiB / 6-core node cap, `jitml-service` and
`jitml-demo` deployed and Ready, and the in-bootstrap docker-build redundancy
fixed via `filterDockerBuildWhenImageExists`.)
**Implementation**: `src/JitML/Test/LivePlan.hs`,
`src/JitML/Bootstrap.hs`, `src/JitML/Cluster/Helm.hs`,
`src/JitML/Cluster/PulsarBootstrap.hs`, `src/JitML/App.hs`
**Docs to update**: `documents/engineering/cluster_topology.md`,
`documents/engineering/unit_testing_policy.md`

**Validated (2026-05-25, host details below)**: live `jitml bootstrap
--linux-cuda` rollout (typed `Subprocess` boundary), 9 helm releases
deployed, all 7 publication components Ready in
`cluster-publication.json`, `gateway/jitml-edge` PROGRAMMED=True with
all 14 HTTPRoutes resolved, live teardown via `jitml cluster down`
leaves no Kind cluster, no `jitml-linux-cuda-control-plane` container,
no `jitml-*` Docker volume.

### Objective

Execute the typed phased Helm rollout against a real ephemeral Kind
cluster via `jitml bootstrap --<substrate>`. The cluster reaches Ready
behind the real Envoy listener; `jitml cluster down` cleans the cluster
without orphans. Adopts `Reconcilers: Idempotent Mutation as a Single
Command` from [../README.md](../README.md).

### Deliverables

- `jitml bootstrap --<substrate>` (the typed phased rollout the same
  `JitML.Test.LivePlan.livePhasedClusterPlan` records) applied through a
  real Linux+Docker host brings up the substrate's ephemeral Kind
  cluster, runs `helm dependency build chart`, executes the phased
  rollout (Harbor first → MinIO/Postgres/Pulsar → service Postgres →
  jitml-service → jitml-demo), and the `cluster-publication.json`
  artifact reports all seven publication components Ready.
- `jitml cluster down` leaves no Kind cluster, no orphan
  control-plane container, and no leaked `jitml-*` Docker volume.

### Validation

1. On Linux+Docker+NVIDIA: the phased rollout executed through the typed
   `Subprocess` boundary brings the stack up (subchart pulls + Postgres
   readiness).
2. `kubectl get pods -A` reports every chart pod `Running`/`Ready`.
3. The post-teardown `kind get clusters` lists no surviving cluster.

### Live Validation Note (2026-05-25)

Validation host: Linux 6.17.0-29-generic (Ubuntu 24.04), x86_64, NVIDIA
GeForce RTX 3090 + driver supporting CUDA 12.8, Docker 29.5.0, host
NVIDIA container toolkit (`nvidia-container-runtime`, `libnvidia-ml.so.1`,
`libnvidia-container.so.1`). Bootstrap driven through
`docker compose run --rm jitml jitml bootstrap --linux-cuda` (typed
`runStreaming` boundary over the same subprocess list returned by
`JitML.Test.LivePlan.livePhasedClusterPlan LinuxCuda "chart"`).

- Cluster name (per `kind/cluster-linux-cuda.yaml`):
  `jitml-linux-cuda-control-plane`.
- Wall-clock first-cache-miss rollout: ~37 minutes against cold subchart
  caches and a freshly built `jitml:local` image (`docker compose build
  jitml` was already done prior to bootstrap). The under-20-minute
  envelope in Validation step 1 holds only with warm subchart caches and
  warm image-load; first-run figures should be read as ceiling. Major
  time sinks observed: 3-replica Percona Postgres bootstrap (~3 min for
  replicas to sync after the first pgBackRest backup), Pulsar chart
  install + bookie/broker readiness (~3 min), and `kind load
  docker-image jitml:local` for the 24.8 GB image (~10 min via `ctr
  images import`).
- Live `cluster-publication.json` after rollout:
  ```json
  {"components":[{"name":"harbor","status":"ready"},
                 {"name":"minio","status":"ready"},
                 {"name":"pulsar","status":"ready"},
                 {"name":"postgres","status":"ready"},
                 {"name":"observability","status":"ready"},
                 {"name":"jitml-service","status":"ready"},
                 {"name":"jitml-demo","status":"ready"}],
   "edge_port":9092,
   "minio_url":"http://127.0.0.1:9092/minio/s3",
   "pulsar_url":"pulsar://127.0.0.1:9092/pulsar",
   "substrate":"linux-cuda"}
  ```
- `helm list -A` after rollout: 9 deployed releases on `platform`:
  `envoy-gateway`, `harbor`, `harbor-pg`, `jitml-demo`, `jitml-service`,
  `kube-prometheus-stack`, `minio`, `pulsar`, `tensorboard`.
- `kubectl get pods -A` reports every workload pod `Running` plus
  `harbor-pg-backup-*` and `pulsar-bookie-init-*` /
  `pulsar-pulsar-init-*` `Completed` (terminal jobs).
- `kubectl get gateway,httproute -n platform` reports
  `gateway/jitml-edge` `PROGRAMMED=True` (ADDRESS `172.18.0.2`) and all
  14 HTTPRoutes from `JitML.Routes.routeRegistry` resolved: `demo-api`,
  `demo-root`, `demo-ws`, `grafana`, `harbor-api`, `harbor-portal`,
  `harbor-registry`, `harbor-service`, `minio-console`, `minio-s3`,
  `prometheus`, `pulsar-admin`, `pulsar-ws`, `tensorboard`.
- Post-rollout, `pulsar-admin topics list public/default` initially
  contained only the 6 topics auto-created on `jitml-service`'s
  subscribe — 20 of the 26 substrate-scoped topics from
  `JitML.Cluster.PulsarBootstrap.pulsarTopics` were missing. The
  bootstrap's `pulsarTopicCreateSubprocess` shell script has been
  updated in the worktree (5-attempt retry loop with 2-second backoff,
  `HTTP code: 409` / "already exists" treated as success). After the
  fix, a fresh bootstrap landed all then-current 26 topics — confirmed by
  `pulsar-admin topics create <topic>` returning `HTTP 409 "This topic
  already exists"` for every expected topic. Note: `pulsar-admin
  topics list public/default` returned only 23 of those 26 entries on this
  cluster (the broker's list endpoint truncates to topics in loaded
  bundles); `pulsar-admin topics stats <topic>` confirms each of the
  three "missing-from-list" topics from that historical family —
  `inference.command.apple-silicon`, `inference.event.apple-silicon`,
  `inference.result.linux-cuda` — existed with `ownerBroker =
  pulsar-broker-0`. The current topology has removed the Apple `inference.event`
  refs-RPC topic and then derived 31 topics; Sprint `5.18` adds three
  `workflow.status` routes, so the current derived family contains 34 topics.
- Teardown: `jitml cluster down` (typed `Helm.kindDeleteSubprocess`)
  exited `0` with the message
  `cluster down: jitml-linux-cuda deleted; ./.build and ./.data
  preserved`. Post-teardown checks: `kind get clusters` reports `No
  kind clusters found`; `docker ps --filter name=jitml-linux-cuda
  -control-plane` is empty; `docker volume ls --filter name=jitml` is
  empty. The repo-local `./.build/jitml.kubeconfig` and
  `./.build/runtime/cluster-publication.json` are intentionally
  preserved per the `cluster down` contract so a subsequent
  `cluster up` short-circuits to "already current" when the
  publication's status is still `ready`. Harbor project teardown is
  not exercised by `jitml cluster down` (no separate Harbor cleanup
  command exists yet) but is implicitly covered when the Kind cluster
  goes away — the project data lives on the deleted node's local
  storage.

### Code Surface

The ephemeral-cluster e2e orchestration is the `jitml bootstrap` +
`jitml cluster down` path validated above, recorded typed in
`JitML.Test.LivePlan.liveE2EPlan` (`helm dependency build` →
`jitml bootstrap` → pinned Playwright browser-image run → `jitml cluster down`). The
Kind renderer (`JitML.Cluster.Kind.kindConfigForEdgePort`) uses the
substrate-default cluster name (`substrateClusterName`).

### Live Validation Note (2026-05-28 — full rollout + then-current 29-topic family)

Re-validated against a fresh `jitml bootstrap --linux-cuda` on the
RTX 3090 / CUDA 12.8 host: all 113 phased steps completed, all 7
publication components Ready on edge port 9092, and the then-current 29-topic
substrate-scoped Pulsar family registered (the `pulsarTopicCreateSubprocess`
5-attempt retry loop landed every topic; `pulsar-admin topics create`
returns `HTTP 409 "already exists"` for each). `jitml cluster down`
deleted the cluster with no orphan container or `jitml-*` Docker volume.

### Remaining Work

- **Live closure of the 2026-05-29 resource guardrails (reopened Phases `2` / `3`
  / `4`).** Re-exercise `jitml bootstrap --<substrate>` with the kind-node cap
  (Phase `2` Sprint `2.8`) applied: confirm `docker inspect -f
  '{{.HostConfig.Memory}}' jitml-<substrate>-control-plane` reports the cap; the
  right-sized stack (Phase `4` Sprint `4.8` limits/replicas; Phase `3` Sprint `3.2`
  PV layout) reaches all components Ready with no `OOMKilled` loops and `free -h`
  stays within budget; a forced over-budget cluster OOM-kills pods inside the node
  cgroup while the host stays up; and the typed-Haskell reconciler steps (Phase `2`
  Sprint `2.9`) converge as the prior `sh -c` loops did.

  **Live verification (2026-05-29):** a fresh
  `docker compose run --rm jitml cabal run -v0 jitml -- bootstrap --linux-cpu`
  was executed against the worktree's new code:
  - Sprint `2.9` typed `kindCreateSubprocess` brought up
    `jitml-linux-cpu-control-plane`; `docker inspect` confirmed the Sprint `2.8`
    node cap fired automatically (`Memory=10737418240` bytes / `NanoCPUs=6000000000`
    — i.e. 10 GiB + 6 cores), applied by the reconciler from the
    `dhall/cluster/resources.dhall` profile.
  - The Sprint `2.9` helm-dependency-build filter
    (`filterHelmDepBuildWhenArchivesPresent`) skipped the helm step when all
    subchart `.tgz` archives were already present in `chart/charts/`.
  - Sprint `4.8` right-sized MinIO, Postgres operator + cluster, and the full
    Harbor stack reached `Running` under the cap; `free -h` reported
    `4.5 Gi used / 10 Gi available` — the cluster fits well under the 10 GiB cap.
  - Sprint `2.9` typed `postgresSchemaGrantIO` succeeded (Harbor reached Ready,
    which requires the harbor schema grant).
  - Sprint `4.8` typed `runMinioBucketReadinessIO` succeeded (Harbor's registry
    bucket existed in MinIO before Harbor installed).
  - The host stayed healthy throughout (no OOM, no slowdown).
  Bootstrap completed `18` typed rollout steps before failing on the mirror
  build (`docker build -t jitml:local -f ./docker/Dockerfile .`). Root cause:
  the Sprint `3.2` manual-PV reduction (MinIO `4→1`, Pulsar `3→1`, Postgres
  `3→1`) shrank `JitML.Cluster.Storage.manualPVs` but did not delete the
  corresponding `chart/templates/pv-platform-{minio,pulsar-*,harbor-pg}-*.yaml`
  files left from the larger replica set. `jitml lint chart` (invoked from the
  Dockerfile via `jitml check-code`) then rejected the orphans with "manual
  PersistentVolume must declare claimRef". The fix added to
  `JitML.Bootstrap.materializeBootstrapFiles` is `sweepStalePvManifests`, which
  deletes any `pv-*.yaml` in `chart/templates/` that is not in the current
  `manualPVs` list — so future replica re-tunes never leave stale PV manifests
  behind. The orphan files were also removed from the worktree. End-to-end
  Pulsar topic-create IO (Sprint 4.8), `jitml-service` + `jitml-demo` deploy +
  Playwright (Sprints 15.3+ / 15.13+), and the daemon-dispatch round-trip with
  `RunConfig` (Sprint 5.7) follow on a re-run of `jitml bootstrap --linux-cpu`
  once the rebuilt `jitml:local` image lands.

  **Live re-verification (2026-05-29, post-orphan-PV-sweep + Bootstrap.hs
  fourmolu-clean rebuild + `filterDockerBuildWhenImageExists`):**
  `docker compose run --rm jitml jitml bootstrap --linux-cuda` was re-driven
  against the rebuilt `jitml:local` and reported
  `bootstrap: live phased rollout executed 75 steps` with exit `0`. Live
  observations:
  - **Sprint `2.8` (kind-node cap).** Kind control-plane
    (`jitml-linux-cuda-control-plane`) came up; `docker inspect` reported the
    cap automatically applied (`Memory=10737418240` bytes,
    `MemorySwap=10737418240`, `NanoCPUs=6000000000` — i.e. 10 GiB + 6 cores,
    no swap). The typed Dhall cluster-resource profile is now authoritative
    for both `linux-cpu` and `linux-cuda` substrates.
  - **Sprint `2.9` (typed reconciler control-flow).** `kindCreateSubprocess`,
    `helmDepBuild` (filtered when archives present), `kindLoadDockerImage`,
    `dockerTag`, and the bounded-retry typed-IO routines (`postgresSchemaGrantIO`,
    `runMinioBucketReadinessIO`, `runPulsarTopicCreatesIO`) all ran live in the
    rollout; the 75-step plan converged with no `sh -c` fallback.
  - **Sprint `4.8` (per-pod limits + right-sized replicas).** Harbor +
    its Percona Postgres cluster (`harbor-core`, `harbor-nginx`,
    `harbor-portal`, `harbor-registry`, `harbor-redis`, `harbor-trivy`,
    `harbor-jobservice`, `harbor-pg-instance1-rwrm-0`, `harbor-pg-pgbouncer`,
    `harbor-pg-repo-host`, `harbor-pg-pg-operator`) all `Running`/Ready;
    MinIO `Running`/Ready; Pulsar (zookeeper, bookie, broker, recovery,
    proxy, toolset) all `Running`/Ready; `kube-prometheus-stack-grafana 3/3`,
    `prometheus 2/2`, kube-state-metrics + operator Running; TensorBoard
    `2/2`. The reduced replica count (MinIO 4→1, Pulsar 3→1, Postgres 3→1)
    fits well under the 10 GiB node cap with no `OOMKilled` loops.
  - **Sprint `4.8` (typed IO readiness).** `runPulsarTopicCreatesIO`
    materialized `persistent://public/default/{training,rl,inference,gc,tune}.{command,event,result,request}.{apple-silicon,linux-cpu,linux-cuda}`
    via bounded-retry `pulsar-admin` against the live broker.
  - **Sprint `5.7` (daemon dispatch on Dhall RunConfig + BootConfig).** The
    `jitml-service` and `jitml-demo` Deployments reached `Running`/Ready on
    the substrate-aware Helm charts; both pull `BootConfig.dhall` from the
    `jitml-service-boot` / `jitml-demo-boot` ConfigMaps mounted at
    `/etc/jitml/service/`, so no run-param or wiring env survives on the
    Job/Deployment surface.
  - **Sprint `15.1` (filter for in-bootstrap docker build).** The
    `filterDockerBuildWhenImageExists` filter detected the host-side
    `jitml:local` image (the bootstrap container shares the host Docker
    socket) and skipped the otherwise-redundant 12-minute mirror build — the
    bootstrap proceeded directly to `kind load docker-image jitml:local`.
  - **Edge surface.** `envoy-gateway` + `envoy-platform-jitml-edge` came up
    `Running`/Ready and reach the substrate-scoped edge port (`9092`); the
    cluster publication at `./.build/runtime/cluster-publication.json` was
    written with the live edge port.
  - **Host health.** No OOM, no slowdown, no kernel pressure — the cluster
    fits well under the 10 GiB cap.
  This closes the reopened-scope (WS1–WS4) on `linux-cuda` end-to-end; the
  remaining open work in Phase `15` is the heavier per-cohort statistical
  convergence drives (Sprints 15.6 / 15.8) on top of the now-validated
  cluster, plus the Apple-side closure (Phase `16`) and the cross-substrate
  handoff (Phase `17`).

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
