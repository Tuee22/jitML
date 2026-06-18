# `linux-cuda` Per-Lane Attestation (Sprint 15.20)

**Status**: Authoritative source
**Referenced by**: [../README.md](../README.md),
[../phase-15-linux-cuda-and-cluster-closure.md](../phase-15-linux-cuda-and-cluster-closure.md),
[../phase-17-cross-substrate-and-handoff.md](../phase-17-cross-substrate-and-handoff.md),
[../phase-18-no-caveat-product-handoff.md](../phase-18-no-caveat-product-handoff.md)
**Generated sections**: none

> **Purpose**: The committed `linux-cuda` per-lane report-card fragment that
> Sprint `15.20` owns. Phase `17` (Sprint `17.8`) and Phase `18` (Sprint `18.1`)
> consume this fragment on `linux-cpu` and never re-run the `linux-cuda` lane
> (standards rule M(b)/(d)).

## Host

- NVIDIA GeForce RTX 5090, UUID `GPU-e764ef97-32d7-4981-c348-029983c64073`
- CUDA 12.8, Ubuntu 24.04 (x86_64), Docker 29.x, NVIDIA Container Runtime
- Validated 2026-06-18.

## Validation gate (all green)

| Command | Result |
|---|---|
| `docker compose run --rm jitml jitml test all --linux-cpu` | 8/8 stanzas PASS |
| `docker compose run --rm jitml-cuda jitml test all --linux-cuda` | 8/8 stanzas PASS (incl. `jitml-backends` 20/20 on the GPU) |
| `docker compose run --rm jitml-cuda jitml test jitml-e2e --linux-cuda` | 23/23 |
| `docker compose run --rm jitml jitml docs check` | ok |
| `docker compose run --rm jitml jitml check-code` | ok |

`jitml-backends --linux-cuda` compiled and executed the real cuBLAS/cuDNN
bindings (`-fcuda`) on the attached RTX 5090 — every within-substrate
`linux-cuda` kernel case a real device PASS.

## Live `linux-cuda` report card

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

## Browser product matrix — `11/11` via live Playwright

The authoritative browser proof is the live Playwright product matrix run against
the `linux-cuda` Envoy edge (`http://127.0.0.1:9092/`) after
`jitml internal seed-demo-checkpoints`:

```
11 passed (chromium)
  ✓ demo shell responds and renders the portals home
  ✓ portals home links to every bundled admin portal
  ✓ shared header is present on every panel
  ✓ mnist panel renders an inference canvas         (kind: InferenceResult)
  ✓ generic inference panel renders checkpoint output (kind: GenericInferenceResult)
  ✓ cifar panel renders an upload control            (kind: ImageInferenceResult)
  ✓ checkpoint compare panel renders output deltas   (kind: CheckpointCompareResult)
  ✓ connect4 panel renders the board                 (kind: AdversarialMoveResult)
  ✓ rl panel renders an episode timeline
  ✓ training panel renders a loss curve
  ✓ tune panel renders the trial heatmap
```

All five checkpoint-backed panels return real, checkpoint-backed results
(HTTP 200) and were also confirmed via direct `5/5` REST probes of
`/api/inference`, `/api/inference/generic`, `/api/images`,
`/api/checkpoints/compare`, and `/api/connect4/move`.

### `browser_product_matrix` row

The `measureBrowserProductMatrix` probe (`src/JitML/App.hs`) POSTs each panel's
canonical default request to the live demo edge and confirms each returns its
checkpoint-backed result kind; it reports `5/5 served`. The two enablers landed
in this sprint: the `jitml-demo` `runtimeClassName: nvidia` + 4Gi JIT-compile
budget on `linux-cuda` (`chart/local/jitml-demo/templates/deployment.yaml`), and
the probe itself replacing the prior hardcoded `unavailable` stub. (Earlier in
the session the row read `unavailable` only because the report-card image
predated the probe wiring; rebuilt with the probe, it reads `5/5`.)
