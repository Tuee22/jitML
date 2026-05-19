# System Components

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md),
[development_plan_standards.md](development_plan_standards.md),
[00-overview.md](00-overview.md),
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md),
[phase-0-planning-documentation.md](phase-0-planning-documentation.md),
[phase-1-haskell-cli-surface.md](phase-1-haskell-cli-surface.md),
[phase-2-bootstrap-reconciler-and-jit-cache.md](phase-2-bootstrap-reconciler-and-jit-cache.md),
[phase-3-cluster-substrate-and-routing.md](phase-3-cluster-substrate-and-routing.md),
[phase-4-stateful-platform-services.md](phase-4-stateful-platform-services.md),
[phase-5-jitml-service-daemon.md](phase-5-jitml-service-daemon.md),
[phase-6-numerical-core.md](phase-6-numerical-core.md),
[phase-7-jit-codegen-and-substrates.md](phase-7-jit-codegen-and-substrates.md),
[phase-8-supervised-and-rl-framework.md](phase-8-supervised-and-rl-framework.md),
[phase-9-rl-catalog-alphazero-and-tuning.md](phase-9-rl-catalog-alphazero-and-tuning.md),
[phase-10-checkpointing-and-inference.md](phase-10-checkpointing-and-inference.md),
[phase-11-purescript-frontend-and-demo.md](phase-11-purescript-frontend-and-demo.md),
[phase-12-test-stanzas-and-cross-cluster.md](phase-12-test-stanzas-and-cross-cluster.md),
[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md), [../README.md](../README.md)
**Generated sections**: none

> **Purpose**: Authoritative target component inventory for the jitML Haskell CLI, the
> three substrates, the bootstrap reconciler, the cluster substrate, the stateful
> platform services, the `jitml service` daemon, the numerical core, the JIT codegen
> drivers, the SL/RL/AlphaZero/tuning surfaces, the checkpoint format, the PureScript
> frontend, and the Cabal test stanzas.

The inventory documents the authoritative target end state and the present
checked-in implementation. Phases `0`, `1`, `2`, `3`, and `6` are `✅ Done`;
Phases `4`, `5`, `7`, `8`, `9`, `10`, `11`, and `12` are `🔄 Active`
because at least one owned Exit-Definition obligation requires live runtime
behaviour that the worktree does not yet exercise. Components move from
`🔄 Active` to `✅ Done` as each owning sprint closes per
[development_plan_standards.md → C. Honest Completion Tracking](development_plan_standards.md#c-honest-completion-tracking).

A component row is `✅ Done` only when every Exit-Definition obligation that
the row contributes to is met in the worktree. Typed renderers, catalogs,
ADTs, and generated-section surfaces are `✅ Done` once the typed surface is
in place and tested. Components whose obligation includes live runtime
behaviour (cluster apply, real service clients, real kernel execution,
checkpoint storage, browser interaction) are `🔄 Active` with a one-line
qualifier naming what is missing, until the live behaviour is exercised.

## Substrates

| Substrate | Identifier | Codegen | Container Shape | Daemon Topology | Status | Owning Phase |
|-----------|------------|---------|-----------------|-----------------|--------|--------------|
| Apple Silicon | `apple-silicon` | generated Swift + Metal package under `./.build/jit-src/apple-silicon/<hash>/` | partial — cluster services in Kind; target second `jitml service` runs host-native (Metal cannot be containerized) | target two instances of one binary, distinguished by Dhall: `Cluster + ForwardToHost` (in-pod) + `Host + SelfInference` (host-native); current code renders configs and lifecycle summaries | 🔄 Active; missing: real Tart spin-up, Metal FFI loading, and live host↔cluster RPC | [Phase 7](phase-7-jit-codegen-and-substrates.md) |
| Linux CPU | `linux-cpu` | generated oneDNN-style C++ source under `./.build/jit-src/linux-cpu/<hash>/`, plus local identity-kernel compile/load/run through `JitML.Engines.Local` | fully containerized target: `jitml:local` | target one daemon: `Cluster + SelfInference`; current code renders configs and summaries and validates a same-host identity kernel path | 🔄 Active; missing: real oneDNN graph wrappers beyond the identity fixture | [Phase 7](phase-7-jit-codegen-and-substrates.md) |
| Linux CUDA | `linux-cuda` | generated CUDA C source under `./.build/jit-src/linux-cuda/<hash>/` | fully containerized target: `jitml:local` (CUDA activates at runtime when scheduled to `runtimeClassName: nvidia`) | target one daemon: `Cluster + SelfInference`, pod anti-affinity = one per node; current code renders configs and summaries | 🔄 Active; missing: live NVIDIA runtime, CUDA compile/load, and cuBLAS/cuDNN execution | [Phase 7](phase-7-jit-codegen-and-substrates.md) |

A fourth substrate `linux-opencl` (Intel GPU) is admitted as a future extension and
is not in the current support matrix.

## Haskell CLI Surface

| Surface | Command | Purpose | Status | Owning Sprint |
|---------|---------|---------|--------|---------------|
| Bootstrap | `jitml bootstrap --apple-silicon\|--linux-cpu\|--linux-cuda` | Plan/Apply substrate bootstrap surface; non-dry-run apply materializes Kind/chart/Dhall/publication files locally and then runs `JitML.Bootstrap.liveExecutePhasedRollout` through typed `kind` / Helm / Docker build and explicit Kind image-load / repo-owned manifest apply / readiness / Pulsar-topic subprocesses with no process-environment gate, writing the leased-port publication with Helm-status-derived component health | ✅ Done; live Linux CPU validation on 2026-05-18 executed the 83-step rollout, served `/api` through Envoy, wrote ready publication health, and tore the Kind cluster down through `jitml cluster down` | Sprints 2.1–2.7, 3.5 |
| Service daemon | `jitml service` | Renders daemon lifecycle, BootConfig/LiveConfig, endpoint, logging, retry, and at-least-once helper surfaces; starts the in-binary HTTP listener | 🔄 Active; missing: daemon-acquired Pulsar long-lived subscription/redelivery, live MinIO put/CAS, live Harbor pull, live kubectl call | Sprints 5.1, 5.4, 5.5, 5.6 |
| Cluster lifecycle | `jitml cluster up`, `jitml cluster down`, `jitml cluster status`, `jitml cluster reset` | `up` materializes substrate files and exits `3` on no-op materialization; `status` reads local publication JSON or defaults; `down` deletes the publication-named Kind cluster through a typed idempotent subprocess, preserves `./.build` and `./.data`, and marks preserved publication components `stopped`; `reset` remains the guarded destructive local-state summary | ✅ Done for Phase 3 lifecycle; live `cluster down` deleted `jitml-linux-cpu` and a second down run exited `3` | Sprint 3.5 |
| Train | `jitml train` | Current command renders a deterministic local canonical-problem summary | 🔄 Active; missing: real Pulsar `training.command.<mode>` publish → daemon `TrainingHandler` → real loop → `training.event.<mode>` round-trip | Sprint 8.2 |
| Eval | `jitml eval` | Current command accepts a checkpoint selector and prints a deterministic summary | 🔄 Active; missing: real checkpoint load + eval loop | Sprint 8.2 |
| Tune | `jitml tune` | Current command renders deterministic local trial samples from `JitML.Tune.Catalog` | 🔄 Active; missing: live `tune.command.<mode>` / `tune.event.<mode>` Pulsar round-trip, live trial persistence in MinIO | Sprint 9.5 |
| RL lifecycle | `jitml rl train`, `jitml rl eval`, `jitml rl rollout` | Current commands render algorithm-count, checkpoint, and fixed-seed trajectory summaries | 🔄 Active; missing: real env step boundary, real RL loop, real `rl.command.<mode>` / `rl.event.<mode>` round-trip | Sprint 8.5 |
| Verification | `jitml verify same-run`, `jitml verify cross-backend`, `jitml verify replay` | Registered command summaries | 🔄 Active; missing: real same-substrate byte equality, cross-backend tolerance, and checkpoint replay verification | Sprints 10.4, 12.2, 12.6 |
| Inspection | `jitml inspect list`, `jitml inspect show`, `jitml inspect replay`, `jitml inspect trial`, `jitml inspect frontier` | Registered command summaries | 🔄 Active; missing: real cached-transcript / checkpoint / trial / hyperparameter-frontier inspection against live MinIO | Sprints 9.7, 10.4 |
| Benchmarks | `jitml bench train`, `jitml bench inference`, `jitml bench env` | Registered command summaries | 🔄 Active; missing: reproducible benchmark harnesses with measured throughput/latency | Sprint 12.9 |
| Inference | `jitml inference run` | Current command runs deterministic `inferFromManifest` summary against a local manifest value | 🔄 Active; missing: real MinIO manifest fetch, real weight-blob load, FFI kernel handle execution | Sprint 10.4 |
| Test runner | `jitml test all` / `jitml test <stanza>` | `--dry-run` renders the aggregate plan; non-dry-run invokes `cabal test all` or `cabal test <stanza>` through typed `Subprocess`, then emits the report-card summary on success | ✅ Done | Sprint 12.9 |
| Lint stack | `jitml lint files\|docs\|proto\|chart\|haskell\|purescript\|all` | In-repo hygiene, config, forbidden-path, generated-doc, chart-shape, forbidden-primitive, static-JIT-artifact, Fourmolu, HLint, and `cabal format` checks are implemented | ✅ Done | Sprint 1.4 |
| Docs generation | `jitml docs check` / `jitml docs generate` | Paired generated-section check and write per the `GeneratedSectionRule` registry | ✅ Done | Sprint 1.3 |
| Command introspection | `jitml commands [--tree\|--json]` | Flat list, tree rendering, or JSON command schema from the `CommandSpec` registry | ✅ Done | Sprint 1.2 |
| Focused help | `jitml help <subcommand>` | Equivalent to `<subcommand> --help`; same renderer | ✅ Done | Sprint 1.2 |
| Code quality gate | `jitml check-code` | Delegates to `jitml lint all` and adds the warning-clean `cabal build all --ghc-options=-Werror` gate | ✅ Done | Sprint 1.4 |
| Build | `jitml build` | Build-plan surface for the inner Haskell binary inside the substrate container; mirrors `bootstrap/<substrate>.sh build` semantics from inside the daemon | ✅ Done | Sprint 2.4 |
| Prerequisite doctor | `jitml doctor [--scope toolchain\|container\|cluster] [--remediate]` | In-process prerequisite registry reconciliation and typed remediation apply/postcondition validation | ✅ Done | Sprint 2.2 |
| Kubectl passthrough | `jitml kubectl` | Current command renders the intended kubeconfig-bound invocation | 🔄 Active; missing: live `kubectl` execution against the per-substrate kubeconfig through the typed `Subprocess` boundary | Sprint 3.5 |
| Internal prerequisite listing | `jitml internal list-prereqs` | Prints the typed prerequisite registry from the current Haskell process | ✅ Done | Sprint 1.7 |
| Internal substrate materialization | `jitml internal materialize-substrate` | Validates the supported substrate identifier and renders Kind config, chart templates, publication metadata, and per-substrate Dhall | ✅ Done | Sprint 2.1 / Sprint 3.1 |
| Internal VM lifecycle (Apple) | `jitml internal vm bootstrap\|up\|down\|status\|exec` | Current lifecycle commands write/read the local VM state marker; `exec` renders a typed `tart ssh` subprocess command | 🔄 Active; missing: live `tart` invocation on the first JIT cache miss, real VM spin-up, real `swift build` execution | Sprint 2.5 |
| Internal cache inspection | `jitml internal cache stat\|list\|evict` | JIT cache introspection and idempotent eviction helpers | 🔄 Active; missing: effectful bodies that operate on populated codegen entries against a real cache root | Sprint 7.1 |
| Internal GC | `jitml internal gc <experiment-hash>` | Current command prints `gc: <experiment-hash> kept=<n> reaped=<n>`, exits `3` on the local no-op plan, and supports Plan/Apply output | 🔄 Active; missing: live pointer live-set traversal, blob reaping in HTTP MinIO, `gc_reaped` event emission | Sprint 10.3 |
| Demo executable shim | `jitml-demo` | Sibling binary that prints `demoStatusLine` and serves the frontend/API route surface through `src/JitML/Web/Server.hs`; `loadBundleEntry` + `demoHttpRoutesWithBundle` append a `/bundle/main.js` route serving the compiled Halogen bundle from `web/dist/Main/index.js` when present | 🔄 Active; bundle-serving path validated by `jitml-e2e`; missing: `spago` bundle build wired into the demo image, live `/api/ws` proxy, real panel state from the daemon | Sprint 11.5 |

## Bootstrap Stage-0 Script Surface

The shell scripts are stage-0 entrypoints, not broad package reconcilers. They
fail fast with installation instructions, then delegate to the Haskell
`jitml bootstrap --<substrate>` command.

| Verb | Purpose | Status | Owning Sprint |
|------|---------|--------|---------------|
| `help` | Print supported subcommands | ✅ Done | Sprint 2.1 |
| `doctor` | Run only stage-0 host gates: Apple macOS/arm64/Xcode CLT/Homebrew; Linux Docker without `sudo`; CUDA NVIDIA runtime and compute capability | ✅ Done | Sprint 2.1 |
| `build` | Apple convenience to build `./.build/jitml`; Linux builds the one-service `jitml:local` Compose image | ✅ Done | Sprint 2.1 / Sprint 2.4 |
| `up` | Apple builds `./.build/jitml` and delegates to `jitml bootstrap --apple-silicon`; Linux calls the intended Compose handoff, with the actual `docker/compose.yaml` target delivered by Sprint 2.4 | ✅ Done | Sprint 2.1 |
| `status` | Report bootstrap-side stack health from `./.build/runtime/cluster-publication.json` | ✅ Done | Sprint 2.6 |
| `test` | Thin wrapper for `jitml test all` from outside the container | ✅ Done | Sprint 2.6 |
| `down` | Tear down the cluster; preserve `./.data/` and `./.build/`; on Apple, leave the tart VM up | ✅ Done | Sprint 2.7 |
| `purge` | Cluster down, `rm -rf ./.data/`, tart VM destroyed (Apple); preserves `./.build/` (including JIT cache) | ✅ Done | Sprint 2.7 |
| `purge --full` | `purge` plus `rm -rf ./.build/`; Linux additionally drops the substrate image | ✅ Done | Sprint 2.7 |

## Cluster Substrate Components

| Component | Implementation | Status | Owning Sprint |
|-----------|----------------|--------|---------------|
| Per-substrate Kind config | `./kind/cluster-{apple-silicon,linux-cpu,linux-cuda}.yaml` rendered from `JitML.Cluster.Kind` | ✅ Done | Sprint 3.1 |
| Kind worker labels (CUDA) | `jitml.runtime/gpu=true` on the worker so the `nvidia` RuntimeClass binds | ✅ Done | Sprint 3.1 |
| Kubeconfig home | `./.build/jitml.kubeconfig`; `~/.kube/config` is never touched | ✅ Done | Sprint 3.5 |
| `extraMounts` of `./.build/` | Bind-mounts host `./.build/` into the Kind worker so the in-cluster `jitml-service` pod sees the same JIT artefacts the host built | ✅ Done | Sprint 3.1 |
| `jitml-manual` StorageClass | `kubernetes.io/no-provisioner`; the only StorageClass in the chart | ✅ Done | Sprint 3.2 |
| Manual PV templates | `chart/templates/pv-*.yaml`; StatefulSet PVs bind through explicit `claimRef`, and registered Percona PG PVs bind through CR-rendered `volumeName` because operator PVC names include controller suffixes; Kind mounts repo-local `./.data` at `/jitml/.data` | ✅ Done | Sprint 3.2 |
| HostPath layout | `./.data/<namespace>/<StatefulSet>/pv_<replica-int>/`; lint-enforced by `jitml lint chart` | ✅ Done | Sprint 3.2 |
| `GatewayClass/jitml-gateway` + `Gateway/jitml-edge` | Single localhost listener at `127.0.0.1:<edge-port>`; GatewayClass attaches `EnvoyProxy/jitml-edge` via `parametersRef` | ✅ Done | Sprint 3.3 |
| `EnvoyProxy/jitml-edge` | NodePort service, `externalTrafficPolicy: Cluster`, Gateway listener port pinned to NodePort 30090 | ✅ Done | Sprint 3.3 |
| Route registry | `src/JitML/Routes.hs` — single source of truth for every HTTPRoute resource; Phase `4` routes target the actual Helm release services, send Harbor's public portal/API/registry/token paths through the chart's public `harbor` service, and send `/pulsar/ws` to the broker's embedded WebSocket service on `pulsar-broker:8080` | ✅ Done | Sprint 3.4 |
| Generated HTTPRoute manifests | `chart/templates/httproute-*.yaml`, rendered from the route registry; hand edits fail `jitml lint chart` | ✅ Done | Sprint 3.4 |
| Cluster publication | `./.build/runtime/cluster-publication.json` — `edge_port`, Pulsar URL, MinIO URL, component health; `src/JitML/Cluster/EdgePort.hs` (`leaseEdgePort`) returns the first available 127.0.0.1 port from `[9090, 9091, 9092]` via `Network.Socket.bind`; `liveExecutePhasedRollout` writes the publication with `publicationWithLeasedPort` and replaces default component status with measured Helm release status | ✅ Done; live Linux CPU validation wrote ready measured status for Harbor, MinIO, Pulsar, Postgres, observability, `jitml-service`, and `jitml-demo`; `cluster down` preserves the coordinates and marks components `stopped` | Sprint 3.5 |
| Phased deploy | Target order is Harbor prerequisites first (retry-hardened MinIO bucket readiness, Percona `harbor-pg` readiness, schema grant) → Harbor → local image build/load into Kind → final services; code renders the ordered plan, materializes local inputs, emits typed image subprocesses via `src/JitML/Cluster/DockerImage.hs` (`dockerBuildSubprocess`, `kindLoadDockerImageSubprocess`, `dockerBuildAndKindLoadPlan`, plus Harbor-oriented `dockerTagSubprocess`, `dockerPushSubprocess`, `dockerLoginSubprocess`, `dockerMirrorPlan` for later platform-service work), installs external Helm dependencies from generated `.tgz` archives with typed per-release values under `chart/values/`, installs jitML-owned charts from `chart/local/{tensorboard,jitml-service,jitml-demo}`, and the explicit live executor replaces the mirror placeholder with Docker build + Kind image-load subprocesses before final services | ✅ Done; `jitml-integration` covers the typed plan, 2026-05-18 live Linux CPU validation completed the Kind-loaded final workloads, ready publication checks, Pulsar topic creation, and Envoy `/api` route, and 2026-05-19 validation completed the Harbor prerequisite ordering against MinIO and external Postgres | Sprint 3.5 |
| Helm dependency build | `src/JitML/Cluster/Helm.hs` renders the typed dependency-build step before live apply; live execution skips the build when every expected `.tgz` already exists under `chart/charts/`, otherwise it invokes `helm dependency build chart` | ✅ Done; canonical command rendering, idempotent archive detection, and live bootstrap execution are validated | Sprint 3.5 |

## Stateful Platform Services

| Component | Helm Subchart | Routing | Status | Owning Sprint |
|-----------|---------------|---------|--------|---------------|
| Harbor (image registry) | `harbor` subchart values + typed `helm install` plan; `chart/values/harbor.yaml` points the registry storage backend at MinIO bucket `harbor-registry` and the database at `harbor-pg-pgbouncer.platform.svc`; `JitML.Service.HarborSubprocess` provides explicit Docker/curl-backed `HasHarbor` settings and commands | `/harbor` (portal), `/harbor/api` (API), `/v2` (Docker registry), `/service` (token service), all through the chart's public `harbor` nginx service | ⏸️ Blocked; live Harbor rollout readiness, typed command rendering, live push/pull/list/artifact-existence through `HasHarbor`, and 2026-05-19 registry-API validation of the MinIO S3 backend plus external Postgres wiring are validated; blocked: host Docker still attempts HTTPS against the local HTTP registry until insecure-registry handling or Harbor TLS is codified | Sprint 4.1 |
| Percona PG operator | `pg-operator` subchart values plus local PV templates and `JitML.Cluster.PostgresRegistry` `PerconaPGCluster` rendering | (internal — packaged services that require Postgres) | ✅ Done; live `harbor-pg` reconciliation, database readiness, schema grant, and Harbor startup against `harbor-pg-pgbouncer.platform.svc` are validated | Sprint 4.2 |
| Helm values ownership | `chart/templates/` is manifest-only; subchart values belong under `chart/values.yaml` unless a typed Helm invocation passes a separate values file; `jitml lint chart` rejects values files under `chart/templates/` | ✅ Done | Sprint 4.3 |
| MinIO (object store) | `minio` values and bucket list live in `chart/values.yaml`; the direct live install uses `chart/values/minio.yaml`; `src/JitML/Storage/Buckets.hs` is the typed bucket registry; `JitML.Cluster.Readiness.minioBucketReadinessSubprocess` checks every typed bucket through the in-pod Bitnami `mc` client with bounded retries; `JitML.Service.MinIOSubprocess` provides the subprocess-backed HTTP S3 `HasMinIO` instance | `/minio/console`, `/minio/s3` | ✅ Done; live Linux CPU validation confirms MinIO rollout readiness, all seven typed buckets, routed `HasMinIO` conditional writes/read/list/delete through `http://127.0.0.1:9091/minio/s3`, and the retry-hardened bucket check against a live transient startup window | Sprint 4.3 |
| Apache Pulsar | `pulsar` HA values and topic-command renderer; direct live install uses `chart/values/pulsar.yaml`; `broker.configData.webSocketServiceEnabled: "true"` enables the broker-embedded WebSocket service; topic creation runs an idempotent `/pulsar/bin/pulsar-admin topics list` / `topics create` script from `pulsar-toolset-0`; `JitML.Service.PulsarWebSocketSubprocess` is the routed one-shot WebSocket `HasPulsar` interpreter | `/pulsar/admin`, `/pulsar/ws` (`pulsar-broker:8080`, rewrite `/ws`) | ✅ Done; live Linux CPU validation confirms broker/bookkeeper/proxy readiness, the full topic family, accepted `/pulsar/ws` routing to `pulsar-broker:8080`, broker config `webSocketServiceEnabled=true`, and routed WebSocket publish/consume through both a raw Node probe and `JitML.Service.PulsarWebSocketSubprocess`; daemon long-lived redelivery/seek remains Sprint 5.5 work | Sprint 4.4 |
| Envoy Gateway controller | `gateway-helm` | (controller — dispatches the GatewayClass) | ✅ Done; live Linux CPU validation programmed the Gateway and served `/api` through the single localhost listener | Sprint 3.3 |
| kube-prometheus-stack | `kube-prometheus-stack` values plus Grafana/Prometheus renderers | `/grafana`, `/prometheus` | ✅ Done; live Prometheus + Grafana rollout readiness is validated, Grafana serves all seven generated jitML dashboards, and Prometheus reports `jitml-service` `/metrics` as an `up` target | Sprint 4.5 |
| TensorBoard | TensorBoard scalar-event codec (`JitML.Proto.TensorBoard`), TFRecord/shard writer (`JitML.Observability.TensorBoard`), checkpoint sidecar dispatcher (`JitML.Observability.TbSidecar`), and local chart; `chart/local/tensorboard` runs native `python:3.11-slim` with pinned TensorBoard and a Bitnami MinIO-client sidecar mirroring `jitml-tensorboard` into `/tensorboard/logs` | `/tensorboard` | ✅ Done; live Linux CPU validation confirms TensorBoard serves through Envoy, reads a mirrored MinIO TFRecord shard via the scalars API, live `dispatchCheckpointDone` writes the CBOR sidecar through routed MinIO, and a Haskell-written scalar shard reaches TensorBoard through routed `JitML.Service.MinIOSubprocess` | Sprint 4.6 |
| `jitml-service` Deployment | `chart/templates/deployment-jitml-service.yaml` | (internal target Pulsar consumer) | 🔄 Active; live single-replica Deployment readiness is validated; missing: live pod anti-affinity across multiple replicas and real Pulsar subscription from the running pod | Sprint 5.6 |
| `jitml-demo` Deployment | `chart/templates/deployment-jitml-demo.yaml`; executable runs the local demo HTTP server with explicit `--host 0.0.0.0 --port 80` in Kubernetes | `/`, `/api`, `/api/ws` target | 🔄 Active; live Deployment readiness behind the Envoy listener is validated; missing: compiled bundle served from the pod and live WebSocket proxy | Sprint 11.5 |
| NVIDIA RuntimeClass (CUDA) | `chart/templates/runtimeclass-nvidia.yaml`; binds to nodes labelled `jitml.runtime/gpu=true` | (RuntimeClass — selected by the Linux CUDA Deployment podSpec) | ⏸️ Blocked; RuntimeClass apply/get is validated in live Linux CPU bootstrap; blocked: this host exposes only Docker `runc` runtimes and no `nvidia-smi`, so live binding requires an NVIDIA-capable worker | Sprint 4.7 |

## MinIO Bucket Layout

| Bucket | Purpose | Owning Sprint |
|--------|---------|---------------|
| `harbor-registry` | Harbor's S3 backend (128 MiB chunk size) | Sprint 4.3 |
| `jitml-checkpoints` | Training checkpoints; one prefix per experiment hash; content-addressed blobs + manifests + ETag-guarded pointers | Sprint 10.1 |
| `jitml-datasets` | Pinned source datasets (MNIST, Fashion-MNIST, CIFAR-10 binaries); SHA-256 verified against the experiment Dhall | Sprint 8.1 |
| `jitml-transcripts` | RL trajectory transcripts | Sprint 8.4 |
| `jitml-trials` | Hyperparameter trial transcripts; content-addressed by `sha256(resolved-dhall || trial-seed)` | Sprint 9.5 |
| `jitml-tensorboard` | TensorBoard event files; the TB pod is stateless | Sprint 4.6 |
| `jitml-artifacts` | Large inference outputs when the demo is in inference mode | Sprint 11.4 |

## Pulsar Topic Family

`<mode>` ∈ `apple-silicon`, `linux-cpu`, `linux-cuda`. Apple Silicon adds the
internal-RPC pair.

| Topic | Direction | Carrying | Owning Sprint |
|-------|-----------|----------|---------------|
| `training.command.<mode>` | control plane → daemon | `StartTraining`, `StopTraining`, `ResumeFromCheckpoint`, `AbortTraining` | Sprint 8.2 |
| `training.event.<mode>` | daemon → control plane / frontend | `StepDone`, `EpochDone`, `EvalDone`, `CheckpointDone`, `MetricUpdate`, `TrainingFinished`, `TrainingFailed` | Sprint 8.2 |
| `tune.command.<mode>` | control plane → daemon | `RunTrial`, `StopTrial` | Sprint 9.5 |
| `tune.event.<mode>` | daemon → control plane / frontend | `TrialStarted`, `TrialMetricUpdate`, `TrialFinished`, `TrialFailed` | Sprint 9.5 |
| `rl.command.<mode>` | control plane → daemon | `StartRLRun`, `StopRLRun` | Sprint 8.5 |
| `rl.event.<mode>` | daemon → control plane / frontend | `EpisodeDone`, `EvalDone`, `CheckpointDone`, `MetricUpdate` | Sprint 8.5 |
| `inference.request.<mode>` | demo frontend → daemon | inference requests (when demo is in inference mode) | Sprint 11.4 |
| `inference.result.<mode>` | daemon → demo frontend | inference results | Sprint 11.4 |
| `inference.command.apple-silicon` (Apple only) | cluster orchestrator → host daemon | internal RPC envelopes (`call-id`, `kind`, `model-id`, `starting-snapshot`, `reply-topic`, `inputs`) | Sprint 7.5 |
| `inference.event.apple-silicon` (Apple only) | host daemon → cluster orchestrator | ACK envelopes (`call-id`, `kind`, MinIO refs to outputs) | Sprint 7.5 |

## `jitml service` Daemon Surface

| Component | Doctrine Section | Status | Owning Sprint |
|-----------|------------------|--------|---------------|
| `BootConfig` Dhall (start-time only; restart-required) | Long-Running Daemons in the Same Binary → BootConfig | ✅ Done | Sprint 5.2 |
| `LiveConfig` Dhall (target hot-reloadable on SIGHUP) | Long-Running Daemons in the Same Binary → LiveConfig | ✅ Done | Sprint 5.2 |
| SIGHUP hot reload handler | Long-Running Daemons in the Same Binary | ✅ Done in `src/JitML/Service/HotReload.hs` plus POSIX signal/control wiring in `src/JitML/Service/Signal.hs` | Sprint 5.2 |
| `/healthz` endpoint | Long-Running Daemons → /healthz | ✅ Done as `EndpointResponse` served by `JitML.Service.Runtime.daemonHttpRoutes` | Sprint 5.3 |
| `/readyz` endpoint | Long-Running Daemons → /readyz | ✅ Done as `EndpointResponse` served by `JitML.Service.Runtime.daemonHttpRoutes` | Sprint 5.3 |
| `/metrics` endpoint | Long-Running Daemons → /metrics | ✅ Done as Prometheus text served by `JitML.Service.Runtime.daemonHttpRoutes` | Sprint 5.3 |
| Structured JSON stderr logging | Long-Running Daemons → structured logging | ✅ Done as pure `renderLogEvent`, wired through the in-binary listener | Sprint 5.3 |
| Recoverable-vs-fatal error kinds | Long-Running Daemons → error classification | ✅ Done through `ServiceError` → `AppError` retry mapping | Sprint 5.3 |
| `HasMinIO` capability class (`minioPutIfAbsent`, `minioReadObject`, `minioReadBytes`, `putBlobIfAbsent`, `putBlobBytesIfAbsent`, `casPointer`, `listObjects`, `deleteObject`) plus `ETag` newtype; filesystem-backed instance `JitML.Service.FilesystemMinIO` and subprocess-backed HTTP S3 instance `JitML.Service.MinIOSubprocess` exercised by `jitml-integration` | Capability Classes and Service Errors | ✅ Done for the standalone capability path; 2026-05-19 live Linux CPU validation confirms `If-None-Match: *` and `If-Match` conflicts map to `SEConflict` against the routed MinIO edge; daemon acquisition wiring remains Phase 5 work | Sprint 5.4 |
| `HasPulsar` capability class (`pulsarPublish`, `pulsarAcknowledge`, `pulsarSubscribe`, `pulsarConsume`, `pulsarSeek`) plus `SubscriptionId` newtype and routed one-shot WebSocket instance `JitML.Service.PulsarWebSocketSubprocess` | Capability Classes and Service Errors | 🔄 Active; standalone publish/consume through live Pulsar is validated; missing: daemon-acquired long-lived subscription, post-dispatch ack/redelivery, and seek semantics | Sprints 4.4, 5.4 |
| `HasHarbor` capability class (`harborImageExists`, `harborPromoteImage`, `harborPushImage`, `harborPullImage`, `harborListImages`) | Capability Classes and Service Errors; subprocess-backed explicit local settings live in `JitML.Service.HarborSubprocess` | ✅ Done for the standalone capability path; typed Docker/curl command rendering and live push/pull/list/artifact-existence against Harbor are validated; daemon wiring remains Phase `5` work | Sprint 5.4 |
| `HasKubectl` capability class (`kubectlApply` with stdin-piped YAML via `subprocessWithStdin`, `kubectlStatus`, `kubectlGet`, `kubectlDelete`); subprocess-backed instance `JitML.Service.KubectlSubprocess` pins `./.build/jitml.kubeconfig` explicitly and validates stdin command shape in `jitml-integration` | Capability Classes and Service Errors | ✅ Done | Sprint 5.4 |
| `RetryPolicy` typed value | Retry Policy as First-Class Values | ✅ Done | Sprint 5.4 |
| At-least-once Pulsar consumer | At-Least-Once Event Processing | 🔄 Active; typed dispatcher (`JitML.Service.Consumer.{consumerStep,runConsumerLoop,consumerOutcomeError}`) + lifecycle-exit wiring (`JitML.Service.Runtime.consumerLoopExit`) validated by `jitml-daemon-lifecycle` against a synthetic `HasPulsar` instance; missing: daemon long-lived Pulsar subscription, post-dispatch ack/redelivery, and LRU dedup cache populated by live events | Sprint 5.5 |
| Protobuf-message-hash deduplication keys | At-Least-Once Event Processing → idempotency | ✅ Done as payload SHA-256 event id helper | Sprint 5.5 |
| Stateless `Deployment` (not `StatefulSet`) | Long-Running Daemons | 🔄 Active; live single-replica readiness is validated through the live bootstrap path; missing: anti-affinity validation across multiple replicas and real Pulsar subscription from the running pod | Sprint 5.6 |
| Pod anti-affinity (`topologyKey: kubernetes.io/hostname`) | Long-Running Daemons | 🔄 Active; missing: anti-affinity validated across multiple live replicas | Sprint 5.6 |

## Numerical Core Inventory

| Component | Implementation | Status | Owning Sprint |
|-----------|----------------|--------|---------------|
| Layer catalog (16: Dense, Embedding, Conv1D, Conv2D, Conv3D, ConvTranspose, ComplexDense, ComplexConv2D, BatchNorm, LayerNorm, GroupNorm, Dropout, ResidualBlock, ScaledDotProductAttention, MultiHeadAttention, RotaryPositionalEmbedding) | `src/JitML/Numerics/Catalog.hs`; rendered through `renderNumericalCatalog` | ✅ Done | Sprint 6.1 |
| Real-valued activations (8: Relu, LeakyRelu, Elu, Silu, Gelu, Tanh, Sigmoid, Softmax) | `src/JitML/Numerics/Catalog.hs` | ✅ Done | Sprint 6.2 |
| Complex-valued activations (3: ComplexModRelu, ComplexCardioid, ComplexZRelu) | `src/JitML/Numerics/Catalog.hs` | ✅ Done | Sprint 6.2 |
| Spectral / frequency-domain ops (10: FFT, FFTAlongAxis, IFFT, IFFTAlongAxis, RFFT, IRFFT, STFT, DCT, ComplexConjugate, ComplexMatMul) | `src/JitML/Numerics/Catalog.hs` | ✅ Done | Sprint 6.3 |
| Optimizers (13: SGD, MomentumSGD, NesterovSGD, RMSProp, Adagrad, Adadelta, Adam, AdamW, LAMB, LARS, Lion, AdaFactor, Shampoo) | `src/JitML/Numerics/Catalog.hs` | ✅ Done | Sprint 6.4 |
| Schedulers (9: Constant, Linear, Cosine, CosineWithWarmup, Exponential, Polynomial, OneCycle, Piecewise, ReduceOnPlateau) | `src/JitML/Numerics/Catalog.hs` | ✅ Done | Sprint 6.4 |
| Loss functions (10: CrossEntropy, BinaryCrossEntropy, SparseCrossEntropy, Focal, MSE, Huber, IoU, Dice, KLDiv, Contrastive) | `src/JitML/Numerics/Catalog.hs` | ✅ Done | Sprint 6.5 |
| Dhall numerical mirror and cross-type audit | `dhall/numerics/`, `src/JitML/Numerics/Schema.hs`, `src/JitML/Lint/DhallNumerics.hs` | ✅ Done | Sprint 6.6 |
| Experiment Dhall fixtures that exercise the catalog | `experiments/mnist.dhall`, `experiments/mnist-tune.dhall`, `experiments/cartpole.dhall` | ✅ Done | Sprint 6.6 |

## JIT Codegen Components

| Component | Implementation | Status | Owning Sprint |
|-----------|----------------|--------|---------------|
| Apple Silicon engine (Metal codegen + host daemon shim + lazy tart spin-up) | `src/JitML/Engines/Engine.hs`, `src/JitML/Codegen/{RuntimeSource,Metal}.hs`, `src/JitML/Tart/{Lifecycle,Exec}.hs`; generated Swift / Metal inputs under `./.build/jit-src/apple-silicon/<hash>/` | 🔄 Active; missing: real Tart spin-up on first JIT cache miss, real `swift build` execution, Metal FFI loading, MinIO tensor handoff, live Pulsar RPC | Sprints 7.5, 7.7 |
| Linux CPU engine (oneDNN codegen + local FFI fixture) | `src/JitML/Engines/{Engine,Local}.hs`, `src/JitML/Codegen/{RuntimeSource,OneDnn}.hs`; generated oneDNN C++ inputs under `./.build/jit-src/linux-cpu/<hash>/`; local identity kernel compiles with `g++`, loads with `dlopen`, and runs through the Haskell FFI | 🔄 Active; missing: real oneDNN graph wrappers beyond the identity kernel, real reduction kernels satisfying the determinism contract, full `HasEngine` production loading | Sprints 7.3, 7.7 |
| Linux CUDA engine (CUDA C codegen) | `src/JitML/Engines/Engine.hs`, `src/JitML/Codegen/{RuntimeSource,Cuda}.hs`; generated CUDA inputs under `./.build/jit-src/linux-cuda/<hash>/` | 🔄 Active; missing: cuBLAS/cuDNN bindings, deterministic algorithm-id capture, splitmix RNG, FFI loading, live CUDA transcript determinism | Sprints 7.4, 7.7 |
| Haskell-owned runtime JIT source generation | `src/JitML/Codegen/{RuntimeSource,Cuda,OneDnn,Metal,SourceFile}.hs`; no checked-in generated compiler-input directories | ✅ Done | Sprint 7.7 |
| Kernel handle, cache hit/miss, and engine envelope surface | `src/JitML/Engines/Engine.hs`; `KernelHandle`, `JitCacheStatus`, `KernelInputs`, `KernelOutputs`, `EngineEnvelope` | ✅ Done | Sprints 7.1, 7.2 |
| Content-addressed cache key shape | `src/JitML/Cache/Key.hs`; `KernelSpec` hashes `(canonical payload, kind, substrate, toolchain-fingerprint, rendered-source payload, tuning choice)` | ✅ Done | Sprints 2.3, 7.7 |
| Cache root layout | `src/JitML/Cache/Layout.hs`; `./.build/jit/<substrate>/<hash>.<ext>` plus `manifest.json` path resolution | ✅ Done | Sprint 2.3 |
| Cache manifest index | `src/JitML/Cache/Manifest.hs`; JSON round-trip, lookup, upsert, read, and atomic write helpers | ✅ Done | Sprint 2.3 |
| Apple stable FFI symlink surface | `src/JitML/Cache/Symlink.hs`; `./.build/host/apple-silicon/<model-id>.dylib` repoints atomically into `jit/apple-silicon/` | ✅ Done | Sprint 2.3 |
| Hardware auto-tuning | `src/JitML/Engines/Tuning.hs`; `TuningChoice` is a cache-key input and generated-source metadata string; per-substrate knob spaces and deterministic defaults are checked in, including deterministic-only cuDNN choices | 🔄 Active; missing: benchmark-driven on-hardware selection and cross-substrate equality beyond the local Linux CPU identity fixture | Sprint 7.6 |
| Apple Silicon host↔cluster RPC contract | Topic names `inference.command.apple-silicon` / `inference.event.apple-silicon` are documented | 🔄 Active; missing: live envelope flow over real Pulsar topics, real MinIO tensor handoff | Sprint 7.5 |

## Training Workload Surfaces

| Component | Implementation | Status | Owning Sprint |
|-----------|----------------|--------|---------------|
| Supervised training summaries | `src/JitML/SL/Canonicals.hs`; command surface in `src/JitML/App.hs` renders deterministic canonical-problem summaries; `test/sl-canonicals/Main.hs` checks the per-problem deterministic fixtures under `test/golden/sl/<problem-key>/curve.txt` | 🔄 Active; missing: real dataset loaders, daemon-backed training loops, and measured live convergence fixtures from real datasets | Sprint 8.1 |
| Canonical SL problem set | `src/JitML/SL/Canonicals.hs`; deterministic coverage in `test/sl-canonicals/Main.hs` | 🔄 Active; missing: real training runs against MNIST/Fashion-MNIST/CIFAR-10/Tiny-ImageNet/California Housing with measured convergence | Sprint 8.1 |
| Canonical RL environments (cartpole, mountain-car, lunar-lander, atari-subset) | `src/JitML/RL/Environments.hs`; deterministic local step surface and catalog renderer | 🔄 Active; missing: real env step boundary, daemon-backed env loop, real simulator bindings | Sprint 8.3 |
| RL Algorithm catalog and local trajectory surface | `src/JitML/RL/Algorithms.hs`; `dhall/rl/Schema.dhall` mirror/audit; deterministic command summaries in `src/JitML/App.hs`; typed runtime primitives in `src/JitML/RL/{Policy,VecEnv,Buffer,AsyncBuffer,Loop}.hs` with filesystem-backed async-sink coverage | 🔄 Active; missing: live HTTP-backed `HasMinIO` transcript writes and daemon-backed environment execution | Sprint 8.4 |
| Replay/rollout trajectory determinism | `src/JitML/RL/Algorithms.hs`; `deterministicTrajectory` | 🔄 Active; missing: trajectory determinism validated under real env stepping | Sprint 8.4 |
| Schedules, action distributions, action noise, target networks, GAE, callbacks, logger, evaluator | `src/JitML/RL/Framework.hs`; typed framework catalog, run plan, evaluator, and callback surfaces | ✅ Done | Sprint 8.5 |
| Training loops as typed pipelines | Plan/Apply command rendering in `src/JitML/Plan/Plan.hs` and `src/JitML/App.hs`; deterministic `SL.Loop` / `SL.Train` and `RL.Loop.{RLLoop,RLConfig,runRLLoop}` surfaces are checked in | 🔄 Active; missing: daemon-backed execution against live Pulsar / MinIO and real simulator / kernel work | Sprint 8.6 |
| RL algorithm catalog (15 entries: 5 OnPolicy — PPO, A2C, TRPO, MaskablePPO, RecurrentPPO; 5 OffPolicy — DQN, QR-DQN, DDPG, TD3, SAC; 4 Specialized — CrossQ, TQC, ARS, HER; 1 SelfPlay — AlphaZero) | `src/JitML/RL/Algorithms.hs` (catalog); one module per algorithm under `src/JitML/RL/Algorithms/{Ppo,A2c,Trpo,MaskablePpo,RecurrentPpo,Dqn,QrDqn,Ddpg,Td3,Sac,CrossQ,Tqc,Ars,Her}.hs` aggregated by `Registry.algorithmModuleRegistry` | 🔄 Active; missing: real loss / network forward/back through the JIT engine, per-algorithm on-hardware reward thresholds | Sprints 9.1–9.3, 9.5 |
| RL golden tests | deterministic local tests in `test/rl-canonicals/Main.hs` plus `test/golden/rl/ppo/cartpole/trajectory.txt` | 🔄 Active; missing: per-algorithm reward/trajectory fixture trees, real rl_steps/rl_eval_episodes consumption | Sprint 9.4 |
| AlphaZero-style self-play and persistent MCTS state | `src/JitML/RL/AlphaZero.hs` provides game state/move helpers and deterministic transcript summaries; `src/JitML/RL/AlphaZero/{Mcts,SelfPlay,Arena}.hs` carry the typed persistent search tree (UCB + visit-count), self-play buffer with `bufferTranscriptHash`, and arena win-rate promotion gate | 🔄 Active; missing: real network evaluation through the JIT engine inside the prior function, live MinIO checkpoint round-trip of the self-play buffer | Sprint 9.5 |
| Perfect-information game, two-headed network, and arena summary surface | `src/JitML/RL/AlphaZero.hs`; canonical game catalog, Connect 4 two-headed network metadata, and arena summary helpers | 🔄 Active; missing: real two-headed network training, real arena evaluation against measured win rates | Sprint 9.5 |
| Canonical adversarial games (Connect 4, Othello, Hex, Gomoku) | `src/JitML/RL/AlphaZero.hs` `canonicalGames` lists all four; `initialConnect4`, `initialOthello`, `initialHex`, `initialGomoku` plus per-game `applyMove` rules + per-game two-headed network metadata (`connect4Network`, `othelloNetwork`, `hexNetwork`, `gomokuNetwork`); the typeclass `PerfectInformation` admits all four games; per-game transcript fixtures are committed under `test/golden/alphazero/` | 🔄 Active; missing: real position-evaluator network forward pass per game and rule-complete measured arena fixtures | Sprint 9.6 |
| Hyperparameter tuning (sampler × scheduler × pruner) | `src/JitML/Tune/Catalog.hs` covers Sobol/random/GA/ES, Fifo/SuccessiveHalving/Hyperband/ASHA, and none/median/percentile catalogs | 🔄 Active; missing: real `Some Tuning::{ … }` Dhall flow end to end, real proto bindings, live tuner trial execution | Sprint 9.7 |
| Trial storage and resume summary surface | `src/JitML/Tune/Catalog.hs` (key/summary helpers) + `src/JitML/Tune/Resume.hs` (`persistTrialTranscript`, `replaySweep` over `HasMinIO`) | 🔄 Active; resume round-trip validated by `jitml-integration` against filesystem-backed `HasMinIO`; missing: live MinIO persistence against a real cluster | Sprint 9.7 |

## Checkpoint and Inference Components

| Component | Implementation | Status | Owning Sprint |
|-----------|----------------|--------|---------------|
| Storage layout (typed) | `src/JitML/Checkpoint/Format.hs` plus bucket registry in `src/JitML/Storage/Buckets.hs`; `CheckpointManifest` carries tensor/optimizer/RNG blobs, monotonic step, metrics, parent lineage, deterministic CBOR/content hash, and typed object-key renderers | 🔄 Active; missing: checkpoint key layout exercised against a real bucket after a real training step through `JitML.Service.MinIOSubprocess` | Sprint 10.1 |
| Split-blob layout (`blobs/<sha256>`, `manifests/<sha256>`, `pointers/{latest,best/<metric>,trial/...}`) | `src/JitML/Checkpoint/Format.hs`; typed object-key renderers for blobs, manifests, latest, best, and trial pointers | ✅ Done | Sprint 10.1 |
| `.jmw1` dense weight blob format | `src/JitML/Checkpoint/Format.hs`; `encodeJmw1` writes `JMW1`, a CBOR header length/header, and little-endian `F64` payload bytes | ✅ Done | Sprint 10.2 |
| Manifest pointer surface | `src/JitML/Checkpoint/Format.hs`; `CheckpointManifest`, deterministic manifest CBOR codec/content hash, `manifestPointer` | ✅ Done | Sprint 10.2 |
| Write-once and CAS protocol surface | `src/JitML/Checkpoint/{Format,Store}.hs`; pure pointer-write CAS decision surface plus filesystem-backed write-once object/manifest writes and latest-pointer CAS; `JitML.Service.MinIOSubprocess` live-validates the underlying `HasMinIO` conditional-write effects | 🔄 Active; missing: checkpoint-store CAS retry coverage against live MinIO after a real training step | Sprint 10.2 |
| Bit-determinism contract + cross-substrate tolerance methodology | [../documents/engineering/determinism_contract.md](../documents/engineering/determinism_contract.md) | 🔄 Active; missing: per-substrate ULP measurements from real cross-substrate runs | Sprint 10.3 |
| Inference-only read path | `src/JitML/Checkpoint/{Format,Store}.hs`; deterministic `inferFromManifest`, `loadInferenceCheckpoint`, and `inferWeightsOnlyFromLatestCheckpoint` cover the local latest-pointer → manifest → weight-only inference helper consumed by tests | 🔄 Active; missing: live HTTP MinIO fetches, real weight-blob loading into an FFI kernel handle | Sprint 10.4 |
| Retention reconciler (`jitml internal gc <experiment-hash>`) | `src/JitML/Checkpoint/Store.hs` (`walkLiveSet`, `applyRetentionPolicy`, `buildGcPlan`, `executeGcPlan`) plus `src/JitML/App.hs` no-op exit `3` command wiring | 🔄 Active; missing: live HTTP MinIO blob deletion and `gc_reaped` Pulsar events from a real bucket | Sprint 10.3 |
| TensorBoard checkpoint sidecar (`<step>-<manifest-sha>.cbor` under `jitml-tensorboard/<experiment-hash>/checkpoints/`) | `src/JitML/Observability/TensorBoard.hs` (key + CBOR encoder); `src/JitML/Observability/TbSidecar.hs` (`writeCheckpointSidecar`, `dispatchCheckpointPayload` over `HasMinIO`); `src/JitML/Service/Runtime.hs` (`daemonTensorBoardDispatcher`) | ✅ Done; sidecar writer validated by `jitml-integration` against filesystem-backed `HasMinIO`, real `CheckpointDone` payload dispatch is wired through the daemon dispatcher contract, and live-routed MinIO validation covers the write through `JitML.Service.MinIOSubprocess` | Sprint 4.6 |

## Frontend Components

| Component | Implementation | Status | Owning Sprint |
|-----------|----------------|--------|---------------|
| Minimal PureScript application | `web/src/Main.purs` | ✅ Done | Sprint 11.1 |
| Browser-contract source ADTs | `src/JitML/Web/Contracts.hs` renders `web/src/Generated/Contracts.purs` through the local bridge-compatible renderer | ✅ Done | Sprint 11.2 |
| Generated PureScript contracts | `web/src/Generated/Contracts.purs`; the contract renderer is covered by the PureScript-style stanza | ✅ Done | Sprint 11.2 |
| PureScript style smoke tests | `web/test/`, `test/purescript-style/`; current Cabal stanza checks generated-contract presence, source whitespace shape, panel-contract coverage, and explicit typed `spago test` + `purs-tidy check` command shapes | 🔄 Active; missing: default `purs format` round-trip and `purescript-spec` invocation from inside the stanza | Sprint 11.3 |
| Playwright scaffold | `playwright/jitml-demo.spec.ts`; `jitml-e2e` validates the typed Playwright plan and inline DOM scaffold | 🔄 Active; missing: Playwright validation against the live edge route and real panel state | Sprint 11.6 |
| Bundle output | `src/JitML/Web/Bundle.hs`; typed bundle asset manifest and demo route manifest for the generated PureScript bundle output paths; `src/JitML/Web/Server.hs` serves `web/dist/Main/index.js` as `/bundle/main.js` when the file exists | 🔄 Active; missing: demo image `spago` bundle build and live `/api/ws` proxy | Sprint 11.4 |
| MNIST live inference panel | `src/JitML/Web/Bundle.hs`; panel metadata bound to `InferenceRun`; `web/src/Panels/Mnist.purs` carries the typed request/response payload shape | 🔄 Active; missing: Halogen mount/rendering and real inference round-trip against the daemon | Sprint 11.4 |
| CIFAR/ImageNet upload panel | `src/JitML/Web/Bundle.hs`; panel metadata bound to `UploadImage`; `web/src/Panels/Cifar.purs` carries the typed request/response payload shape | 🔄 Active; missing: Halogen mount/rendering and real upload+inference round-trip | Sprint 11.4 |
| AlphaZero-vs-human Connect 4 panel | `src/JitML/Web/Bundle.hs`; panel metadata bound to `Connect4Move`; `web/src/Panels/Connect4.purs` carries the typed `Connect4MoveRequest` / `Connect4MoveResponse` payload shapes | 🔄 Active; missing: Halogen mount + real MCTS move suggestions from the daemon | Sprint 11.4 |
| RL trajectory render panel | `src/JitML/Web/Bundle.hs`; panel metadata bound to `MetricsStream`; `web/src/Panels/Rl.purs` carries the typed stream payload shape | 🔄 Active; missing: Halogen mount/rendering and live WebSocket metric stream | Sprint 11.4 |
| Training metrics panel | `src/JitML/Web/Bundle.hs`; `web/src/Panels/Training.purs` carries the typed `TrainingStream` payload shape | 🔄 Active; missing: Halogen mount/rendering and live training WebSocket stream | Sprint 11.4 |
| Tuning frontier panel | `src/JitML/Web/Bundle.hs`; `web/src/Panels/Tune.purs` carries the typed `TuneStream` payload shape | 🔄 Active; missing: Halogen mount/rendering and live tuning WebSocket stream | Sprint 11.4 |
| Demo executable shim (`jitml-demo`) | `app/Demo.hs` shim into `App.demoMain`; `demoMain` prints `demoStatusLine` and starts `WebServer.serveDemo`, which serves `/bundle/main.js` when `web/dist/Main/index.js` exists | 🔄 Active; missing: demo image bundle build and live WebSocket proxy to the daemon | Sprint 11.5 |

## CLI Doctrine Components

Components introduced by the doctrine adoption sprints scheduled in
[phase-1-haskell-cli-surface.md](phase-1-haskell-cli-surface.md) and the surfaces
that consume them. Citations name the doctrine sections they implement per
standards rule L.

| Component | Doctrine Section | Status | Owning Sprint |
|-----------|------------------|--------|---------------|
| `CommandSpec` registry as implementation source | Automatically Generated Documentation; Command Topology | ✅ Done | Sprint 1.2 |
| `OptionSpec` record fields (`longName`, `shortName`, `metavar`, `description`, `required`) | Automatically Generated Documentation | ✅ Done | Sprint 1.2 |
| Per-leaf `Example` entries on every `CommandSpec` | Automatically Generated Documentation | ✅ Done | Sprint 1.2 |
| Parser generated from the registry (parser is a renderer, not the source of truth) | Command Topology | ✅ Done | Sprint 1.2 |
| Parser-test category via `execParserPure` | Testing Doctrine → Parser Tests | ✅ Done | Sprint 1.2 |
| `jitml commands --tree` and `jitml commands --json` introspection | Progressive Introspection | ✅ Done | Sprint 1.2 |
| `Subprocess` ADT plus `runStreaming` / `capture` interpreter; pure `renderSubprocess` | Architecture → Subprocesses as Typed Values | ✅ Done | Sprint 1.6 |
| Forbidden subprocess primitives (`callProcess`, `readCreateProcess`, `System.Process` constructors, `typed-process` smart constructors) | Architecture → Subprocesses as Typed Values | ✅ Done | Sprint 1.6 |
| `Plan` / `apply` boundary with `--dry-run` and `--plan-file <path>` | Plan / Apply | ✅ Done | Sprint 1.5 |
| `prerequisiteRegistry` with `nodeId`, `nodeDescription`, remedy hint, transitive closure | Prerequisites as Typed Effects | ✅ Done | Sprint 1.7 |
| Single `Env` record threaded via `ReaderT Env IO` | Application Environment | ✅ Done | Sprint 1.8 |
| Single `AppError` ADT (`PrerequisiteUnmet`, `SubprocessFailed`, `MinIOFailed`, `PulsarFailed`, `HarborFailed`, `KubectlFailed`, `DocsCheckDrift`, `UnknownCommand`, `InvalidConfig`, `DhallTypeError`, `ChartLintFailed`, `RouteRegistryDrift`, `JitCacheMiss`, `JitToolchainDrift`, `CheckpointFormatUnsupported`, `CheckpointWriteConflict`, `ReconcilerNoop`) | Error Handling | ✅ Done | Sprint 1.9 |
| `renderError :: AppError -> Text` boundary | Error Handling | ✅ Done | Sprint 1.9 |
| Exit code `3` for reconciler no-op-on-match | Error Handling | ✅ Done | Sprint 1.9 |
| HLint rule config and in-repo primitive scan cover terminal output primitives, `exitFailure`, and subprocess constructors outside their approved modules | Error Handling | ✅ Done | Sprint 1.4 |
| `--format json\|table\|plain` (default `table` on TTY else `plain`) | Output Rules | ✅ Done | Sprint 1.9 |
| `--color auto\|always\|never` plus `--no-color` | Output Rules | ✅ Done | Sprint 1.9 |
| `fourmolu.yaml` 12-setting list at repo root | Lint, Format, and Code-Quality Stack → Pinned fourmolu.yaml | ✅ Done | Sprint 1.4 |
| `cabal format` temp-file round-trip byte-equality check | Lint, Format, and Code-Quality Stack | ✅ Done | Sprint 1.4 |
| `forbiddenPathRegistry` (`.github/workflows/`, `.husky/`, `.githooks/`, `.pre-commit-config.yaml`, root `Makefile`/`justfile`/`Taskfile.yml`) | Lint, Format, and Code-Quality Stack → Forbidden Surfaces | ✅ Done | Sprint 1.4 |
| `GeneratedSectionRule` registry for marker-delimited generated regions | Generated Artifacts → The generated-section registry | ✅ Done | Sprint 1.3 |
| `trackingGeneratedPaths` registry for active fully-generated files (`documents/cli/commands.md`, `share/man/man1/jitml.1`, shell completions, PureScript contracts, chart HTTPRoutes, Grafana dashboards, Prometheus scrape config) | Generated Artifacts → Two categories of generation | ✅ Done | Sprint 1.3 |
| `futureTrackingGeneratedPathPatterns` registry for later generated artefacts (`share/man/man1/jitml-*.1`) | Generated Artifacts → Two categories of generation | ✅ Done | Sprint 1.3 |
| GADT-indexed `TrainingLifecycle`, `RLRunLifecycle`, and `TuneSweepLifecycle` with singleton witnesses in `src/JitML/RL/Framework.hs` (`RLRunLifecycle` indexes the `RLRunPhase` data kind: `RLCollect`, `RLComputeAdvantages`, `RLOptimise`, `RLEvaluate`, `RLCheckpoint`) | GADT-Indexed State Machines | ✅ Done | Sprints 8.4, 8.6, 8.7, 9.7 |
| Capability classes (`HasMinIO`, `HasPulsar`, `HasHarbor`, `HasKubectl`) — full doctrine-required methods checked in | Capability Classes and Service Errors | 🔄 Active; `HasMinIO`, one-shot `HasPulsar`, `HasHarbor`, and `HasKubectl` subprocess instances are live-validated; missing: daemon wiring for all clients and long-lived Pulsar ack/seek semantics | Sprints 4.4, 5.4 |
| `RetryPolicy` typed value with named strategies | Retry Policy as First-Class Values | ✅ Done | Sprint 5.4 |
| At-least-once Pulsar consumer with protobuf-message-hash deduplication | At-Least-Once Event Processing | 🔄 Active; missing: daemon long-lived Pulsar subscription, post-dispatch ack/redelivery, and LRU dedup cache populated by live messages | Sprint 5.5 |
| Long-running daemon shape (`BootConfig` / `LiveConfig`, SIGHUP, `/healthz`, `/readyz`, `/metrics`, structured JSON stderr logging) | Long-Running Daemons in the Same Binary | 🔄 Active; missing: live service clients acquired from daemon config and wired through the running daemon, especially Pulsar event flow | Sprints 5.2, 5.3 |
| Implemented reconciler discipline (`jitml docs generate`, `jitml lint --write`, `jitml bootstrap`, `jitml cluster up`, `--dry-run` / `--plan-file` plan rendering, no-op exit code `3`) | Reconcilers: Idempotent Mutation as a Single Command; Plan / Apply | ✅ Done | Sprints 1.3, 1.4, 1.5, 1.9, 2.1, 3.5 |
| Mutating reconciler effects (`jitml bootstrap` live Kind/Helm apply, `jitml internal gc` live MinIO deletion) | Reconcilers: Idempotent Mutation as a Single Command | 🔄 Active; live `jitml bootstrap` Kind/Helm apply is validated through Sprint 3.5; missing: live `jitml internal gc` HTTP MinIO deletion and `gc_reaped` Pulsar events | Sprints 3.5, 10.3 |
| Cabal-manifest toolchain pin (`tested-with: ghc ==9.14.1` in `jitml.cabal`, `with-compiler: ghc-9.14.1` in `cabal.project`, codegen toolchains pinned in `cabal.project`) | Toolchain pinning | ✅ Done | Sprint 1.1 |
| Library-first layout audit (thin `app/Main.hs` and `app/Demo.hs`, logic in `src/JitML/`) | Project Structure | ✅ Done | Sprint 1.1 |
| Durable CLI documentation artefacts (`documents/cli/commands.md`, `share/man/man1/jitml*.1`, `share/completion/{bash,zsh,fish}/`) | Automatically Generated Documentation | ✅ Done | Sprint 1.3 |
| Standardized library set audit in `jitml.cabal` (`optparse-applicative`, `text`, `bytestring`, `aeson`, `prettyprinter*`, `ansi-terminal`, `path`, `path-io`, `typed-process`, `safe-exceptions`, `dhall`, `tasty*`, `temporary`) | Overview → standardized stack | ✅ Done | Sprint 1.1 |

## Test Stanzas

Per doctrine `Test Organization`, each tier is a separate Cabal `test-suite` with
`type: exitcode-stdio-1.0` and `tasty` as the in-stanza runner. A single `tasty`
tree spanning all tiers is forbidden. All ten stanza declarations exist today,
and each non-style phase stanza now has a dedicated local deterministic body.

| Stanza | Current body | Target expansion | Status | Owning Sprint |
|--------|--------------|------------------|--------|---------------|
| `jitml-unit` | `test/unit/Main.hs` covers current parser, docs, prerequisite, env, app-error, plan, subprocess, bootstrap-script, cache, runtime-source, daemon-surface, checkpoint, frontend, Grafana fixture, and catalog helpers | Final Pure Logic, Parser, Property, and Golden coverage across engine invariants, richer transcript codecs, RNG mixers, generated Grafana fixture breadth, and richer RL/tuning/checkpoint codecs | ✅ Done | Sprint 12.1 |
| `jitml-integration` | `test/integration/Main.hs` covers typed subprocess execution, renderer suites, route-table golden fixture, real-binary spawn matrix, filesystem-backed `HasMinIO` checkpoint / inference / resume coverage, routed MinIO and Pulsar subprocess command rendering, Dhall numerics decode, and typed live-rollout command shapes | Live checkpoint round-trip, live daemon service capability effects, and per-substrate determinism | 🔄 Active; missing: live checkpoint round-trip, daemon-acquired Pulsar / cluster effects, and real generated-kernel determinism beyond the local Linux CPU identity fixture | Sprint 12.2 |
| `jitml-sl-canonicals` | `test/sl-canonicals/Main.hs` covers eleven deterministic synthetic convergence curves and their committed per-problem fixtures under `test/golden/sl/<problem-key>/curve.txt` | Live SL convergence and per-distribution regression detection against real datasets | 🔄 Active; missing: real training runs, live measured convergence fixtures, and `sl_epochs` / `sl_batch` knob consumption | Sprint 12.3 |
| `jitml-rl-canonicals` | `test/rl-canonicals/Main.hs` covers algorithm metadata, deterministic trajectory helper, PPO/CartPole golden trajectory, and all four AlphaZero transcript fixtures | RL target matrix forms (2) and (3): same-substrate trajectory determinism plus per-seed final-reward distribution against live committed fixtures | 🔄 Active; missing: same-substrate live trajectory determinism, per-seed final-reward distribution, and measured AlphaZero arena fixtures | Sprint 12.4 |
| `jitml-hyperparameter` | `test/hyperparameter/Main.hs` covers sampler / scheduler / pruner axes, deterministic trial values, and Sobol/GA golden fixtures | Per-sampler reproducibility, per-scheduler reproducibility, per-pruner reproducibility, and resume-from-partial-sweep equality against live storage | 🔄 Active; missing: per-sampler / per-scheduler / per-pruner reproducibility against live trial storage in MinIO | Sprint 12.5 |
| `jitml-cross-backend` | `test/cross-backend/Main.hs` covers engine determinism flags, checkpoint inference summaries, and generated Linux CPU identity-kernel compile/load/run | Cross-substrate cohort `(cpu, cuda)` and `(cpu, metal)` on the SL canon; per-tensor drift fits the committed tolerance band per [../documents/engineering/determinism_contract.md](../documents/engineering/determinism_contract.md) | 🔄 Active; missing: live cross-substrate runs against committed `test/golden/cross-backend/` tolerance fixtures | Sprint 12.6 |
| `jitml-daemon-lifecycle` | `test/daemon-lifecycle/Main.hs` covers lifecycle / retry / signal-control tests plus one-shot daemon HTTP `/healthz` | Real Pulsar idempotency assertion against a live consumer | ✅ Done | Sprint 12.7 |
| `jitml-e2e` | `test/e2e/Main.hs` plus `src/JitML/Test/LivePlan.hs` covers route/bucket/chart-values/publication/contract/demo HTTP/report/no leaked `jitml-e2e-*` clusters and typed Helm/Pulumi/Playwright plan tests | Explicit live e2e path brings up an ephemeral Kind stack via Pulumi, Helm dependency build, Playwright against real Envoy, deterministic teardown | 🔄 Active; missing: live Pulumi + Helm + Playwright execution path against an ephemeral Kind stack, deterministic teardown with no leaked PVs / Harbor projects / Docker volumes | Sprint 12.8 |
| `jitml-haskell-style` | `test/haskell-style/Main.hs` runs the lint stack | Formatter, hlint/config, forbidden-path, chart, generated-section, external formatter/hlint/cabal-format/build gates, and optional future lints as they land | ✅ Done | Sprint 1.4 |
| `jitml-purescript-style` | `test/purescript-style/Main.hs` checks generated-contract presence/header, whitespace, panel-contract smoke, and explicit typed `spago test` / `purs-tidy check` command shapes | PureScript `purs format` round-trip and `purescript-spec` smoke tests run from inside the stanza | 🔄 Active; missing: default `purs format` and `purescript-spec` invocations | Sprint 11.3 |

## Test Categories Mapping (Doctrine → Stanza)

| Doctrine Test Category | Owning Stanza |
|------------------------|---------------|
| Pure Logic | `jitml-unit` |
| Parser | `jitml-unit` |
| Property | `jitml-unit` |
| Golden | `jitml-unit` |
| Integration | `jitml-integration`, `jitml-sl-canonicals`, `jitml-rl-canonicals`, `jitml-hyperparameter`, `jitml-cross-backend` (the four canonicals/HPO/cross-backend rows are project-specific Integration per doctrine §Test Organization → project-specific stanzas) |
| Daemon Lifecycle | `jitml-daemon-lifecycle` |
| Pulumi-Orchestrated Infrastructure | `jitml-e2e` |
| Style (§Style as a Cabal test-suite) | `jitml-haskell-style` |
| Lint (project-specific) | `jitml-purescript-style` |

## POC Report-Card Knobs

Pinned in `cabal.project` for reproducibility across hosts; see
[phase-12-test-stanzas-and-cross-cluster.md](phase-12-test-stanzas-and-cross-cluster.md).

| Knob | Value | Purpose |
|------|-------|---------|
| `sl_epochs` | `5` | Canonical SL training epoch count for golden curves |
| `sl_batch` | `64` | Canonical SL minibatch size for golden curves |
| `rl_steps` | `100_000` | Canonical RL training step budget for golden trajectories |
| `rl_eval_episodes` | `25` | Per-eval episode count for the RL Evaluator |
| `az_games` | `200` | Self-play game count per AlphaZero generation in the golden suite |
| `az_sims` | `400` | MCTS simulation budget per move in the golden AlphaZero suite |
| `tune_trials` | `64` | Trial count for the report-card tuning workload |
| `tune_budget_per_trial` | `1_000` | Per-trial step budget for the report-card tuning workload |
| `xcluster_kind_nodes` | `2` | Worker count for the ephemeral `jitml-e2e` Kind stack |

## Toolchain

| Component | Pinned Version | Purpose | Status | Owning Sprint |
|-----------|----------------|---------|--------|---------------|
| GHC | `9.14.1` | Haskell compiler for the CLI binary, the daemon, and every library module | ✅ Done | Sprint 1.1 |
| Cabal | `3.16.1.0` | Haskell build tool; per-stanza `type: exitcode-stdio-1.0` | ✅ Done | Sprint 1.1 |
| LLVM | pinned in `cabal.project` | Shared by GHC `-fllvm` and JIT codegen | ✅ Done | Sprint 1.1 |
| NVCC | pinned in `cabal.project` (`--use_fast_math=false`, baseline `sm_70`) | CUDA kernel codegen for `linux-cuda` | ✅ Done | Sprint 7.4 |
| Xcode/Metal | pinned in bootstrap script + `cabal.project` | Metal kernel codegen for `apple-silicon` (runs inside the `jitml-build` tart VM) | ✅ Done | Sprint 7.5 |
| oneDNN | pinned in `cabal.project` (AVX2 baseline, AVX-512 detected at JIT time) | CPU kernel codegen for `linux-cpu` | ✅ Done | Sprint 7.3 |
| `kindest/node` | pinned in `./kind/cluster-<substrate>.yaml`; mirrored as a comment in `cabal.project` | Kind worker image; the comment-mirror is a single-source-of-toolchain-truth record (`jitml lint chart` rejects drift) | ✅ Done | Sprint 3.1 |
| `tart` | latest stable, `brew install cirruslabs/cli/tart` | macOS VM runner for the Apple Silicon Swift/Metal build; validated only through the first-JIT-cache-miss prerequisite root | ✅ Done | Sprint 2.2 |
| `kind` | Haskell prerequisite DAG | Kubernetes-in-Docker | ✅ Done | Sprint 2.2 |
| `kubectl` | Haskell prerequisite DAG | k8s API client invoked through the typed `Subprocess` boundary | ✅ Done | Sprint 2.2 |
| `helm` | Haskell prerequisite DAG | Helm CLI invoked through the typed `Subprocess` boundary | ✅ Done | Sprint 2.2 |
| `docker` | stage-0 Linux gate plus Haskell prerequisite DAG | Container runtime; the only host runtime touched on Linux | ✅ Done | Sprint 2.2 |
| Node.js | Haskell prerequisite DAG | Required by the PureScript toolchain (`spago`, `purescript`) and Pulumi | ✅ Done | Sprint 2.2 |
| Poetry | Haskell prerequisite DAG | Required for ancillary Python tooling (none on the supported runtime path; only present for codegen support tools) | ✅ Done | Sprint 2.2 |
| Formatter GHC | separate isolated install under `.build/jitml-style-tools/` | Lint stack only; never affects the project compiler | ✅ Done | Sprint 1.4 |
| PureScript contract generator | local renderer in `src/JitML/Web/Contracts.hs` | Bridge-compatible endpoint renderer for `web/src/Generated/Contracts.purs`; no external `purescript-bridge` package is required for the current implementation | ✅ Done | Sprint 11.2 |
| Pulumi (TypeScript) | `infra/pulumi/package.json` plus `infra/pulumi/index.ts` `@pulumi/command` resource graph | Typed ephemeral-Kind orchestrator scaffold for the explicit live `jitml-e2e` path | 🔄 Active; missing: live Pulumi execution in the e2e stanza | Sprint 12.8 |
| Target platforms | `arm64` macOS (Apple Silicon), `amd64` Linux, optional `arm64` Linux | Three substrates × supported host arches | ✅ Done | Phases 3, 7 |

## State Locations

| State Class | Authority | Durable Home | Notes |
|-------------|-----------|--------------|-------|
| Build artefacts | `cabal` (Apple) or `docker compose run` (Linux) | `./.build/` (gitignored, dockerignored) | The only host folder holding compiled artefacts |
| Generated JIT compiler inputs | `jitml` Haskell runtime source renderers | `./.build/jit-src/<substrate>/<hash>/` | CUDA, oneDNN C++, and Metal / Swift inputs are generated on demand; the local Linux CPU identity path compiles and loads from this tree |
| JIT cache | `jitml service` and `jitml build` | `./.build/jit/<substrate>/<hash>.<ext>` content-addressed by `(canonical-cbor(KernelSpec), kind, substrate, toolchain-fingerprint, rendered-source-payload, tuning-choice)` | Survives `purge`; only `purge --full` removes it |
| Apple FFI dlopen surface | `jitml service` (host-native instance) | `./.build/host/apple-silicon/<model-id>.dylib` (symlinks into `jit/apple-silicon/`) | Stable-named so the FFI key never changes across re-JITs |
| Kubeconfig | `jitml bootstrap --<substrate>` | `./.build/jitml.kubeconfig` | The CLI never touches `~/.kube/config` |
| Generated Dhall and runtime metadata | `jitml bootstrap --<substrate>` | `./.build/conf/`, `./.build/runtime/cluster-publication.json`, `./.build/kind/<substrate>/` | Host Dhall exists only on Apple; Linux uses only the cluster ConfigMap Dhall |
| Kind hostPath PV state | per-StatefulSet PVs | `./.data/<namespace>/<StatefulSet>/pv_<replica-int>/` | `.data` is strictly manual PV bind mounts; lint-enforced by `jitml lint files` |
| Checkpoint store | `jitml service` (training path); local interpreter in `JitML.Checkpoint.Store` | MinIO `jitml-checkpoints/<experiment-hash>/{blobs,manifests,pointers}`; local tests use a filesystem object root with the same key layout | Concurrency: write-once + If-Match CAS on pointers; local tests exercise write-once objects, manifest writes, latest pointer CAS, and inference from latest |
| Trial store | `jitml tune` | MinIO `jitml-trials/<sha256(resolved-dhall \|\| trial-seed)>/` | Trial transcripts content-addressed |
| TensorBoard events | `jitml service` writers | MinIO `jitml-tensorboard/<experiment-hash>/shards/*.tfevents` plus checkpoint sidecars | Stateless TB pod reads from MinIO |
| RL transcripts | `jitml rl train` / `jitml rl rollout` | MinIO `jitml-transcripts/` | Analog of MCTS's `.mcts-cache/transcripts/` |
| Plan suite | repository worktree | `DEVELOPMENT_PLAN/` | This document set |
| Doctrine | repository worktree | `HASKELL_CLI_TOOL.md` (root) | Authoritative CLI doctrine |
| Governed engineering docs | repository worktree | `documents/engineering/` | Project-specific elaborations of the doctrine and project-owned content |
| Generated-section registry | code | `src/JitML/Generated/Registry.hs` | Authoritative for `jitml docs check` and `jitml docs generate` |
| Tracking-generated-paths registry | code | `src/JitML/Generated/Paths.hs` | Authoritative for `jitml lint files` drift detection |

## Artefact Locations

This table is the local artefact inventory for the implemented plan surfaces.
The current concrete worktree is summarized in
[00-overview.md → Current Baseline](00-overview.md#current-baseline).

| Type | Location | Purpose |
|------|----------|---------|
| Haskell application entrypoints | `app/Main.hs`, `app/Demo.hs` | Six-line shims into `App.main` per the library-first layout |
| Haskell source modules | `src/JitML/` | CLI, cluster, daemon, runtime, SL/RL/AlphaZero/tuning, proto, engines, codegen, numerics, storage, inference, web, observability, generated-artifact tracking, checkpointing, `Test.{LivePlan,Report}`, bootstrap live rollout, and typed `Subprocess` support |
| Cabal package definition | `jitml.cabal` | Build, test, and dependency definition with `tested-with: ghc ==9.14.1`; declares both `jitml` and `jitml-demo` executables and the ten test-suite stanzas |
| Cabal project definition | `cabal.project` | Repository-wide Cabal package-set definition with `with-compiler: ghc-9.14.1`, the codegen-toolchain pins, and the report-card knobs |
| Formatter config | `fourmolu.yaml` | Pinned 12 doctrine-mandated settings at repo root |
| Per-substrate Kind configs | `./kind/cluster-{apple-silicon,linux-cpu,linux-cuda}.yaml` | Single control-plane + one worker; bind-mounts `./.build/` into the worker via `extraMounts` |
| Bootstrap scripts | `./bootstrap/{apple-silicon,linux-cpu,linux-cuda}.sh` | Stage-0 idempotent reconcilers |
| Docker assets | `docker/Dockerfile`, `docker/compose.yaml` | One Dockerfile producing one image (`jitml:local`) with `jitml` and `jitml-demo` installed; one compose service (`jitml`) |
| Helm umbrella chart | `chart/Chart.yaml`, `chart/values.yaml`, `chart/values/`, `chart/templates/`, `chart/local/` | Subchart deps for Harbor, Pulsar, MinIO, Postgres, Envoy Gateway, Prometheus; checked-in local charts for TensorBoard, `jitml-service`, and `jitml-demo`; typed per-release values for direct dependency installs; templates for GatewayClass / Gateway / HTTPRoutes / EnvoyProxy / manual PVs / Deployments / RuntimeClass / dashboards; umbrella values live in `chart/values.yaml` unless a typed Helm subprocess passes a file from `chart/values/` |
| JIT source generation | `src/JitML/Codegen/{RuntimeSource,Cuda,OneDnn,Metal,SourceFile}.hs`, `src/JitML/Engines/Local.hs`, `./.build/jit-src/<substrate>/<hash>/` | Haskell-generated compiler inputs for CUDA, oneDNN C++, and Metal / Swift; local Linux CPU identity compile/load/run |
| Protobuf contracts | `proto/tensorboard/event.proto`, `proto/jitml/{training,rl,tune}.proto` | TensorBoard scalar Event schema plus jitML command/event envelopes |
| PureScript frontend | `web/package.json`, `web/src/`, `web/test/`, `playwright/` | Minimal PureScript shell, generated contract file, smoke tests, and Playwright scaffold |
| Pulumi infrastructure | `infra/pulumi/` | Current TypeScript metadata scaffold; target ephemeral-Kind stack used by `jitml-e2e` |
| Experiments | `experiments/` | Canonical experiment Dhall files (the "configuration is code" surface) |
| Tests | `test/` | Per-stanza test trees (`test/unit/`, `test/integration/`, `test/sl-canonicals/`, `test/rl-canonicals/`, `test/hyperparameter/`, `test/cross-backend/`, `test/daemon-lifecycle/`, `test/e2e/`, `test/haskell-style/`, `test/purescript-style/`) and current golden fixtures under `test/golden/{cache,cli,prerequisite}/` |
| Development plan | `DEVELOPMENT_PLAN/` | This plan suite |
| Doctrine | `HASKELL_CLI_TOOL.md` | Authoritative CLI doctrine at repo root |
| Project README | `README.md` | Project intent, command surface, doctrine scope, build instructions |
| Agent guardrails | `AGENTS.md`, `CLAUDE.md` | Git-command restrictions and doctrine pointers for LLM agents |
| Generated CLI artefacts | `documents/cli/commands.md`, `share/man/man1/jitml*.1`, `share/completion/{bash,zsh,fish}/` | Fully-generated; tracked by `trackingGeneratedPaths`; hand edits fail `jitml lint files` |

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [development_plan_standards.md](development_plan_standards.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
