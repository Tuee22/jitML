# `linux-cuda` Per-Lane Attestation (Sprints 15.20 / 15.21 / 15.22)

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [../README.md](../README.md),
[../phase-15-linux-cuda-and-cluster-closure.md](../phase-15-linux-cuda-and-cluster-closure.md),
[../phase-17-cross-substrate-and-handoff.md](../phase-17-cross-substrate-and-handoff.md),
[../phase-18-no-caveat-product-handoff.md](../phase-18-no-caveat-product-handoff.md)
**Generated sections**: none

> **Purpose**: The committed `linux-cuda` per-lane report-card fragment. Sprint
> `15.20` supplied the earlier no-caveat runtime/browser fragment, Sprint
> `15.21` revalidated the expanded fixed-budget all-model lane on the same real
> NVIDIA host, and Sprint `15.22` revalidated that lane against the HA topology.
> Phase `17` and Phase `18` consume this fragment on `linux-cpu` and never
> re-run the `linux-cuda` lane (standards rule M(b)/(d)).

## Host

- NVIDIA GeForce RTX 5090, UUID `GPU-e764ef97-32d7-4981-c348-029983c64073`
- CUDA 12.8, driver `570.211.01`, Ubuntu 24.04 (x86_64), Docker 29.x,
  NVIDIA Container Runtime
- Revalidated 2026-06-28 for Sprint `15.22` HA topology.

## Current Sprint 15.22 HA validation gate (all green)

| Command | Result |
|---|---|
| `docker compose build jitml` | Image build PASS, including embedded `check-code: ok`, PureScript bundle build, and image manifest list `sha256:4357054cfac0135eccd06ddea37e4f0c4d9ed8d07abbe8cab9a278a98caa03b2` |
| `JITML_BOOTSTRAP_SKIP_IMAGE_BUILD=1 ./bootstrap/linux-cuda.sh up` | Clean HA rollout PASS: 130 steps, edge `9092`, all seven components Ready |
| HA MinIO | Distributed `statefulset/minio` Ready; buckets provisioned through Bitnami `provisioning.buckets` with `versioning: Unchanged`, including `harbor-registry` and all jitML object buckets |
| HA Pulsar | Three ZooKeeper, three bookie, three broker, and three proxy pods Ready; manual PV/PVC names match chart-generated claims (`pulsar-bookie-journal-*`, `pulsar-bookie-ledgers-*`, `pulsar-zookeeper-data-*`) |
| HA compute placement | Three `jitml-service` Engine pods spread across the three worker nodes with `jitml.compute-scope=service`; daemon-dispatched Training/RL workload Jobs completed with `jitml.compute-scope=workload` without anti-affinity deadlock |
| Canonical dataset staging | All 12 canonical artifacts present in live `jitml-datasets` MinIO with pinned SHA-256 verification |
| `docker compose run --rm jitml-cuda jitml test all --linux-cuda` | 8/8 stanzas PASS; `jitml-integration` live WorkflowMatrix 880.86s, live PPO convergence 264.46s, `jitml-backends` 20/20 on the RTX 5090 |
| `docker compose run --rm jitml jitml internal seed-demo-checkpoints` | 8 demo checkpoints seeded |
| Live Playwright product matrix against `http://127.0.0.1:9092/` | Clean 15/15 PASS (`15 passed (17.4s)`) |
| `docker compose run --rm jitml jitml docs check` | PASS (`docs check: ok`) |
| `docker compose run --rm jitml jitml check-code` | PASS (`check-code: ok`) |

`jitml-backends --linux-cuda` compiled and executed the real cuBLAS/cuDNN
bindings (`-fcuda`) on the attached RTX 5090 — every within-substrate
`linux-cuda` kernel case a real device PASS.

## Sprint 15.22 defects closed in this fragment

- Replaced invalid MinIO distributed-mode `defaultBuckets` with provisioning
  bucket declarations and `versioning: Unchanged`.
- Corrected MinIO readiness from `deployment/minio` to `statefulset/minio`.
- Corrected Pulsar manual PV/PVC claim names to match the Bitnami chart's
  journal, ledgers, and ZooKeeper data claims.
- Split HA compute placement into `jitml.compute-scope=service` for Engine
  replicas and `jitml.compute-scope=workload` for daemon-spawned Jobs, preserving
  the scoped one-numerical-worker-per-node invariant without blocking live work.
- Made in-cluster worker commands derive live MinIO/Pulsar settings from mounted
  `BootConfig.dhall`, so worker Jobs no longer require a host-local
  `.build/runtime/cluster-publication.json`.
- Updated the duplicate-`StartTraining` live assertion to read all HA service
  pod logs by label instead of byte-slicing one Deployment log stream.

## Historical Sprint 15.20 live `linux-cuda` report card

```
jitML POC report card
knobs:
  sl_epochs: 5
  sl_batch: 64
  rl_steps: 100000
  rl_eval_episodes: 25
  alphazero_games: 200
  alphazero_sims: 400
  tune_trials: 64
  tune_budget_per_trial: 1000
  xcluster_kind_nodes: 2
stanzas:
  jitml-unit: PASS
  jitml-integration: PASS
  jitml-sl-canonicals: PASS
  jitml-rl-canonicals: PASS
  jitml-hyperparameter: PASS
  jitml-backends: PASS
  jitml-daemon-lifecycle: PASS
  jitml-e2e: PASS
measurements:
  sl_final_loss: mnist-shallow-mlp=0.65
  rl_final_reward: ppo/cartpole=131.23101095715876
  alphazero_arena_win_rate: connect4/gen0=0.75
  tune_best_objective: TPE=1.0
  jit_cache_hit_rate: prometheus=1.0 hits=1 misses=0
  daemon_healthz: http://127.0.0.1:9092/healthz status=200
  browser_product_matrix: checkpoint-backed product panels 5/5 served at edge :9092
cabal_test:
  passed: 8
  failed: 0
```

Every measurement row is populated — **no `unavailable` product row**.

## Current browser product matrix — `15/15` via live Playwright

The authoritative browser proof is the live Playwright product matrix run against
the `linux-cuda` Envoy edge (`http://127.0.0.1:9092/`) after
`jitml internal seed-demo-checkpoints`:

```
15 passed (chromium)
  ✓ demo shell responds and renders the portals home
  ✓ portals home links to every bundled admin portal
  ✓ shared header is present on every panel
  ✓ mnist panel renders an inference canvas
  ✓ generic inference panel renders checkpoint output
  ✓ cifar panel renders an upload control
  ✓ checkpoint compare panel renders output deltas
  ✓ connect4 panel renders the board
  ✓ adversarial selectors render trained policy/value rows
  ✓ checkpoint browse renders every model row
  ✓ workflow status reconciles live state
  ✓ transcript replay renders persisted game history
  ✓ rl panel renders an episode timeline
  ✓ training panel renders a loss curve
  ✓ tune panel renders the trial heatmap
```

The matrix covers the checkpoint-backed inference panels, all-model checkpoint
browse, workflow-state reconciliation, persisted transcript replay, RL/training
state, and tuning controls against the published CUDA edge.

### `browser_product_matrix` row

The `measureBrowserProductMatrix` probe (`src/JitML/App.hs`) POSTs each panel's
canonical default request to the live demo edge and confirms each returns its
checkpoint-backed result kind; the historical Sprint `15.20` report card above
records `5/5 served`. Sprint `15.21` keeps that live edge and expands the
browser proof to the 15-case all-model product matrix. The `jitml-demo`
`runtimeClassName: nvidia` + 4Gi JIT-compile budget on `linux-cuda`
(`chart/local/jitml-demo/templates/deployment.yaml`) remains the validated
Webapp scheduling envelope; CUDA execution itself belongs to the Engine role.
