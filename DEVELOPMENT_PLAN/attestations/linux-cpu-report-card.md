# `linux-cpu` Per-Lane Attestation (Phases 13/14 + Sprint 17.8)

**Status**: Authoritative source
**Referenced by**: [../README.md](../README.md),
[../phase-13-no-caveat-model-runtime.md](../phase-13-no-caveat-model-runtime.md),
[../phase-14-interactive-demo-and-playwright-closure.md](../phase-14-interactive-demo-and-playwright-closure.md),
[../phase-17-cross-substrate-and-handoff.md](../phase-17-cross-substrate-and-handoff.md),
[../phase-18-no-caveat-product-handoff.md](../phase-18-no-caveat-product-handoff.md)
**Generated sections**: none

> **Purpose**: The committed `linux-cpu` per-lane report-card fragment that the
> always-available accelerator-free lane (Phases `13`/`14`) owns. Phase `17`
> (Sprint `17.8`) and Phase `18` (Sprint `18.1`) consume this fragment on
> `linux-cpu` as the third merge input alongside the committed `linux-cuda`
> (Phase `15`) and `apple-silicon` (Phase `16`) fragments (standards rule
> M(b)/(d)).

## Host

- Apple M1 Max workstation (macOS, arm64); Docker Desktop aarch64 Linux VM
  (47 GiB), no NVIDIA GPU. The `linux-cpu` lane runs in the `jitml:local`
  container where oneDNN (`libdnnl`, `oneapi/dnnl/dnnl.hpp`) is present.
- Validated 2026-06-23. The image under test was built from the worktree
  **including** the 2026-06-23 reflected-catalog-schema
  (`JitML.Service.CatalogSchema`), tuning-objective-migration
  (`JitML.SL.Architecture` seam + `pureReferenceMlpDevice`), and the three
  Sprint `14.1` browser product features (checkpoint browse, workflow-state
  reconciliation, persisted-transcript adversarial replay —
  `JitML.Service.{Transcript,WorkflowStatus}`, the new Engine workflows, and the
  `web/src/Panels/{Checkpoints,Workflow,Replay}.purs` panels) — the in-image
  `check-code` gate (fourmolu + hlint + docs check + `-Werror`) passed and the
  `-fcuda` library build linked, so all of those changes are live-validated on
  this lane.

## Validation gate (all green)

| Command | Result |
|---|---|
| `docker compose run --rm jitml jitml test all --live --linux-cpu` | 8/8 stanzas PASS (`cabal_test: passed: 8, failed: 0`) |
| `docker compose run --rm jitml jitml docs check` | ok |
| `docker compose run --rm jitml jitml lint haskell --write` (fourmolu + hlint) | ok |
| in-image `jitml check-code` (run during `jitml bootstrap --linux-cpu` image build) | ok |

The full-stack rollout came up clean: `bootstrap/linux-cpu.sh up` completed a
**110-step** live phased rollout (all platform components Ready — MinIO, Harbor +
`harbor-pg`, Pulsar broker/bookie/zookeeper/proxy, kube-prometheus-stack,
TensorBoard, `jitml-service`, `jitml-demo`) and wrote the leased-port publication
at the Envoy edge `127.0.0.1:9091`. All **12 canonical dataset blobs** (MNIST ×4,
Fashion-MNIST ×4, CIFAR-10, CIFAR-100, California Housing, Tiny ImageNet) were
SHA-verified against the pinned `JitML.SL.Dataset` hashes and staged into live
MinIO via `jitml internal upload-dataset`, and the five demo checkpoints were
seeded via `jitml internal seed-demo-checkpoints`.

`jitml-backends --linux-cpu` compiled and executed the real oneDNN primitive
paths through the Haskell FFI — every within-substrate `linux-cpu` kernel case
(identity, reduction, dense/conv/norm/attention/embedding family scaffolds,
benchmark candidate runner, tuning store, and the on-device PPO/DQN/QR-DQN/HER/
DDPG/AlphaZero trainers) a real device PASS (23/23).

## Live `linux-cpu` report card

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
  rl_final_reward: ppo/cartpole=119.99308238573022
  alphazero_arena_win_rate: connect4/gen0=0.75
  tune_best_objective: TPE=1.0
  jit_cache_hit_rate: prometheus=1.0 hits=1 misses=0
  daemon_healthz: http://127.0.0.1:9091/healthz status=200
  browser_product_matrix: checkpoint-backed product panels 5/5 served at edge :9091
cabal_test:
  passed: 8
  failed: 0
```

Every measurement row is populated — **no `unavailable` product row**. The
`sl_final_loss` is real `linux-cpu` oneDNN MNIST training through
`JitML.SL.Architecture` (the four canonical MNIST blobs staged + SHA-verified).
`tune_best_objective: TPE=1.0` was produced by the **migrated** tuning objective
(now trained through the `JitML.SL.Architecture` seam, not the legacy Dense-only
classifier); the value is unchanged at `1.0` — the deterministic separable tuning
dataset still admits a 100%-accuracy trial — so the migration is live-validated on
this lane and the committed `apple-silicon` / `linux-cuda` `TPE=1.0` fragments
stay consistent.

## Browser product matrix — `14/14` via live Playwright

The live Playwright product matrix ran against the `linux-cpu` Envoy edge
(`http://127.0.0.1:9091/`) after `jitml internal seed-demo-checkpoints`, via the
`mcr.microsoft.com/playwright:v1.61.0-noble` browser image (host networking),
exit `0`. The matrix is **14 tests**: the 11 baseline panels plus the three
**Sprint `14.1` net-new browser product features** (checkpoint browse,
live-backed workflow-state reconciliation, and persisted-transcript adversarial
replay):

```
9 passed
5 flaky
(14/14 — exit 0)
  ✓ demo shell responds and renders the portals home
  ✓ portals home links to every bundled admin portal
  ✓ shared header is present on every panel
  ✓ mnist panel renders an inference canvas          (kind: InferenceResult)        [flaky: cold-JIT first attempt]
  ✓ generic inference panel renders checkpoint output (kind: GenericInferenceResult)[flaky: cold-JIT first attempt]
  ✓ cifar panel renders an upload control            (kind: ImageInferenceResult)    [flaky: cold-JIT first attempt]
  ✓ checkpoint compare panel renders output deltas   (kind: CheckpointCompareResult) [flaky: cold-JIT first attempt]
  ✓ connect4 panel renders the board                 (kind: AdversarialMoveResult)   [flaky: cold-JIT first attempt]
  ✓ checkpoint browse panel lists seeded checkpoints  (kind: CheckpointList)    [NEW 14.1; flaky: cold-JIT first attempt]
  ✓ workflow status panel renders a live status table (kind: WorkflowStatus)    [NEW 14.1]
  ✓ transcript replay scrubs a persisted adversarial game (real MinIO transcript)[NEW 14.1; flaky: cold-JIT first attempt]
  ✓ rl panel renders an episode timeline
  ✓ training panel renders a loss curve
  ✓ tune panel renders the trial heatmap
```

The `flaky` panels are the checkpoint-backed panels whose **first** attempt times
out at the 45s `expect` budget while the `jitml-demo` Engine JIT-compiles the
oneDNN kernel for that panel's first inference (~46s cold); the retry serves the
real result in ~1.4s. This is the documented cold-start behavior the Playwright
config's `retries: 2` + raised `expect.timeout` accommodates (the report-card
`browser_product_matrix` 5/5 probe independently confirms every checkpoint panel
serves its result kind). The three new Sprint `14.1` features are real and
live-backed: **checkpoint browse** lists the seeded checkpoints from MinIO via a
`ListCheckpoints` Engine workflow; **workflow status** renders reconciled
`WorkflowStatus` frames the Engine projects to `workflow.status.<substrate>`; and
**transcript replay** scrubs a game's moves read back from a real persisted
`jitml-transcripts` MinIO object (the persisted `.cbor` object is confirmed in the
bucket). The matrix exits `0` — **all 14 pass**.
