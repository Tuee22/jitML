# `linux-cpu` Per-Lane Attestation (Phases 13/14 + Sprints 17.10 / 18.7 + Phase 28)

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [../README.md](../README.md),
[../phase-13-no-caveat-model-runtime.md](../phase-13-no-caveat-model-runtime.md),
[../phase-14-interactive-demo-and-playwright-closure.md](../phase-14-interactive-demo-and-playwright-closure.md),
[../phase-17-cross-substrate-and-handoff.md](../phase-17-cross-substrate-and-handoff.md),
[../phase-18-no-caveat-product-handoff.md](../phase-18-no-caveat-product-handoff.md),
[../phase-28-per-model-integration-and-e2e.md](../phase-28-per-model-integration-and-e2e.md)
**Generated sections**: none

> **Purpose**: The committed `linux-cpu` per-lane report-card fragment that the
> always-available accelerator-free lane (Phases `13`/`14`) owns. Phase `17`
> (Sprint `17.10`) and Phase `18` (Sprints `18.5` / `18.6` / `18.7`) consume this fragment on
> `linux-cpu` as the third merge input alongside the committed `linux-cuda`
> (Phase `15`) and `apple-silicon` (Phase `16`) fragments (standards rule
> M(b)/(d)). Phase `28` re-attests this lane for the reopened row-complete
> product matrix on `linux-cpu`.

## Host

- Apple M1 Max workstation (macOS, arm64); Docker Desktop aarch64 Linux VM
  (47 GiB), no NVIDIA GPU. The `linux-cpu` lane runs in the `jitml:local`
  container where oneDNN (`libdnnl`, `oneapi/dnnl/dnnl.hpp`) is present.
- Validated 2026-06-23, re-attested 2026-06-26 after the real-SL/RL chain and
  Sprint `14.3` demo-runtime replacement, re-attested 2026-06-29 as the HA
  `linux-cpu` aggregation after Phases `15` / `16` re-closed, and re-aggregated
  2026-06-30 after the typed-failure/docs-governance remediation in Phases `0`,
  `1`, `8`, `9`, and `10`, then re-aggregated again for Sprint `18.7` after
  Phases `3`, `5`, and `9` re-closed the live cluster, mounted RunConfig, and
  tuning-fidelity remediation. The image under test was built from the worktree
  **including** the 2026-06-23 reflected-catalog-schema
  (`JitML.Service.CatalogSchema`), tuning-objective-migration
  (`JitML.SL.Architecture` seam + `pureReferenceMlpDevice`), and the three
  Sprint `14.1` browser product features (checkpoint browse, workflow-state
  reconciliation, persisted-transcript adversarial replay —
  `JitML.Service.{Transcript,WorkflowStatus}`, the new Engine workflows, and the
  `web/src/Panels/{Checkpoints,Workflow,Replay}.purs` panels), plus the Sprint
  `14.3` full-width MLP checkpoint runtime and eight seeded demo checkpoints —
  the in-image
  `check-code` gate (fourmolu + hlint + docs check + `-Werror`) passed and the
  `-fcuda` library build linked, so all of those changes are live-validated on
  this lane.

## Phase 28 row-complete re-attestation (2026-07-05)

| Command / probe | Result |
|---|---|
| `docker compose build jitml` | ok; embedded `check-code: ok`, PureScript bundle built, image `jitml:local` refreshed |
| `docker compose run --rm jitml cabal test jitml-integration --test-show-details=direct --test-options='-p EnvoyProxy'` | 1/1 PASS |
| `docker compose run --rm jitml cabal test jitml-integration --test-show-details=direct --test-options='-p HA'` | 3/3 PASS |
| `docker compose run --rm -e JITML_SUBSTRATE=linux-cpu jitml cabal test jitml-sl-canonicals --test-show-details=direct` | 31/31 PASS; live materialization 389.07s, live MNIST convergence 541.33s |
| `docker compose run --rm jitml jitml test all --live --linux-cpu` | 8/8 stanzas PASS (`cabal_test: passed: 8, failed: 0`) |
| `curl http://127.0.0.1:9091/healthz` | HTTP 200 |
| `POST http://127.0.0.1:9091/api/checkpoints` | `count: 55`, `row-selectors: 55`, `checkpoint-summaries: 55` |
| `docker compose run --rm jitml jitml cluster status` | all components Ready on `linux-cpu`, edge `127.0.0.1:9091` |

The full live gate log is
`.build/validation-logs/phase28-full-linux-cpu-20260705-after-edge-hardening.log`.
The report card emitted all eight passing stanzas, populated `daemon_healthz`,
reported `browser_product_matrix: checkpoint-backed product rows 55/55 served at
edge :9091`, and rendered the row-complete evidence table below. The stateful PV
overlay used node-local `/var/local/jitml-stateful-pv/...` directories for
Docker-backed live rollouts, preserved the checked-in `.data` PV identity,
normalized Postgres PV ownership to uid/gid `26:26`, and kept MinIO/Pulsar
stateful directories writable. MinIO curl paths used bounded timeouts and
retries, MinIO probes allowed slow recovery, and the managed Envoy Deployment
carried hardened readiness/startup/liveness probe tolerances for `envoy` and
`shutdown-manager`.

```
row_id	Catalog	Integration	E2E	Negative	Lane
mnist-shallow-mlp	generated-matrix:product-row-mnist-shallow-mlp	integration.product.mnist-shallow-mlp	e2e.product.mnist-shallow-mlp	checkpoint-required-fail-closed	linux-cpu
mnist-deep-mlp	generated-matrix:product-row-mnist-deep-mlp	integration.product.mnist-deep-mlp	e2e.product.mnist-deep-mlp	checkpoint-required-fail-closed	linux-cpu
mnist-lenet	generated-matrix:product-row-mnist-lenet	integration.product.mnist-lenet	e2e.product.mnist-lenet	checkpoint-required-fail-closed	linux-cpu
fashion-mnist-mlp	generated-matrix:product-row-fashion-mnist-mlp	integration.product.fashion-mnist-mlp	e2e.product.fashion-mnist-mlp	checkpoint-required-fail-closed	linux-cpu
fashion-mnist-resnet	generated-matrix:product-row-fashion-mnist-resnet	integration.product.fashion-mnist-resnet	e2e.product.fashion-mnist-resnet	checkpoint-required-fail-closed	linux-cpu
cifar10-resnet20	generated-matrix:product-row-cifar10-resnet20	integration.product.cifar10-resnet20	e2e.product.cifar10-resnet20	checkpoint-required-fail-closed	linux-cpu
cifar10-resnet56	generated-matrix:product-row-cifar10-resnet56	integration.product.cifar10-resnet56	e2e.product.cifar10-resnet56	checkpoint-required-fail-closed	linux-cpu
cifar100-wide-resnet	generated-matrix:product-row-cifar100-wide-resnet	integration.product.cifar100-wide-resnet	e2e.product.cifar100-wide-resnet	checkpoint-required-fail-closed	linux-cpu
cifar10-vit	generated-matrix:product-row-cifar10-vit	integration.product.cifar10-vit	e2e.product.cifar10-vit	checkpoint-required-fail-closed	linux-cpu
tiny-imagenet-resnet50	generated-matrix:product-row-tiny-imagenet-resnet50	integration.product.tiny-imagenet-resnet50	e2e.product.tiny-imagenet-resnet50	checkpoint-required-fail-closed	linux-cpu
california-housing-mlp	generated-matrix:product-row-california-housing-mlp	integration.product.california-housing-mlp	e2e.product.california-housing-mlp	checkpoint-required-fail-closed	linux-cpu
PPO/cartpole	generated-matrix:product-row-PPO.cartpole	integration.product.PPO.cartpole	e2e.product.PPO.cartpole	checkpoint-required-fail-closed	linux-cpu
PPO/mountain-car	generated-matrix:product-row-PPO.mountain-car	integration.product.PPO.mountain-car	e2e.product.PPO.mountain-car	checkpoint-required-fail-closed	linux-cpu
PPO/acrobot	generated-matrix:product-row-PPO.acrobot	integration.product.PPO.acrobot	e2e.product.PPO.acrobot	checkpoint-required-fail-closed	linux-cpu
PPO/lunar-lander	generated-matrix:product-row-PPO.lunar-lander	integration.product.PPO.lunar-lander	e2e.product.PPO.lunar-lander	checkpoint-required-fail-closed	linux-cpu
PPO/key-door-grid	generated-matrix:product-row-PPO.key-door-grid	integration.product.PPO.key-door-grid	e2e.product.PPO.key-door-grid	checkpoint-required-fail-closed	linux-cpu
PPO/gridworld-deterministic	generated-matrix:product-row-PPO.gridworld-deterministic	integration.product.PPO.gridworld-deterministic	e2e.product.PPO.gridworld-deterministic	checkpoint-required-fail-closed	linux-cpu
A2C/cartpole	generated-matrix:product-row-A2C.cartpole	integration.product.A2C.cartpole	e2e.product.A2C.cartpole	checkpoint-required-fail-closed	linux-cpu
A2C/mountain-car	generated-matrix:product-row-A2C.mountain-car	integration.product.A2C.mountain-car	e2e.product.A2C.mountain-car	checkpoint-required-fail-closed	linux-cpu
A2C/lunar-lander	generated-matrix:product-row-A2C.lunar-lander	integration.product.A2C.lunar-lander	e2e.product.A2C.lunar-lander	checkpoint-required-fail-closed	linux-cpu
A2C/key-door-grid	generated-matrix:product-row-A2C.key-door-grid	integration.product.A2C.key-door-grid	e2e.product.A2C.key-door-grid	checkpoint-required-fail-closed	linux-cpu
TRPO/cartpole	generated-matrix:product-row-TRPO.cartpole	integration.product.TRPO.cartpole	e2e.product.TRPO.cartpole	checkpoint-required-fail-closed	linux-cpu
TRPO/mountain-car	generated-matrix:product-row-TRPO.mountain-car	integration.product.TRPO.mountain-car	e2e.product.TRPO.mountain-car	checkpoint-required-fail-closed	linux-cpu
TRPO/lunar-lander	generated-matrix:product-row-TRPO.lunar-lander	integration.product.TRPO.lunar-lander	e2e.product.TRPO.lunar-lander	checkpoint-required-fail-closed	linux-cpu
TRPO/key-door-grid	generated-matrix:product-row-TRPO.key-door-grid	integration.product.TRPO.key-door-grid	e2e.product.TRPO.key-door-grid	checkpoint-required-fail-closed	linux-cpu
MaskablePPO/cartpole	generated-matrix:product-row-MaskablePPO.cartpole	integration.product.MaskablePPO.cartpole	e2e.product.MaskablePPO.cartpole	checkpoint-required-fail-closed	linux-cpu
MaskablePPO/mountain-car	generated-matrix:product-row-MaskablePPO.mountain-car	integration.product.MaskablePPO.mountain-car	e2e.product.MaskablePPO.mountain-car	checkpoint-required-fail-closed	linux-cpu
MaskablePPO/lunar-lander	generated-matrix:product-row-MaskablePPO.lunar-lander	integration.product.MaskablePPO.lunar-lander	e2e.product.MaskablePPO.lunar-lander	checkpoint-required-fail-closed	linux-cpu
MaskablePPO/key-door-grid	generated-matrix:product-row-MaskablePPO.key-door-grid	integration.product.MaskablePPO.key-door-grid	e2e.product.MaskablePPO.key-door-grid	checkpoint-required-fail-closed	linux-cpu
RecurrentPPO/cartpole	generated-matrix:product-row-RecurrentPPO.cartpole	integration.product.RecurrentPPO.cartpole	e2e.product.RecurrentPPO.cartpole	checkpoint-required-fail-closed	linux-cpu
RecurrentPPO/mountain-car	generated-matrix:product-row-RecurrentPPO.mountain-car	integration.product.RecurrentPPO.mountain-car	e2e.product.RecurrentPPO.mountain-car	checkpoint-required-fail-closed	linux-cpu
RecurrentPPO/lunar-lander	generated-matrix:product-row-RecurrentPPO.lunar-lander	integration.product.RecurrentPPO.lunar-lander	e2e.product.RecurrentPPO.lunar-lander	checkpoint-required-fail-closed	linux-cpu
RecurrentPPO/key-door-grid	generated-matrix:product-row-RecurrentPPO.key-door-grid	integration.product.RecurrentPPO.key-door-grid	e2e.product.RecurrentPPO.key-door-grid	checkpoint-required-fail-closed	linux-cpu
DQN/cartpole	generated-matrix:product-row-DQN.cartpole	integration.product.DQN.cartpole	e2e.product.DQN.cartpole	checkpoint-required-fail-closed	linux-cpu
DQN/mountain-car	generated-matrix:product-row-DQN.mountain-car	integration.product.DQN.mountain-car	e2e.product.DQN.mountain-car	checkpoint-required-fail-closed	linux-cpu
DQN/key-door-grid	generated-matrix:product-row-DQN.key-door-grid	integration.product.DQN.key-door-grid	e2e.product.DQN.key-door-grid	checkpoint-required-fail-closed	linux-cpu
QR-DQN/cartpole	generated-matrix:product-row-QR-DQN.cartpole	integration.product.QR-DQN.cartpole	e2e.product.QR-DQN.cartpole	checkpoint-required-fail-closed	linux-cpu
QR-DQN/mountain-car	generated-matrix:product-row-QR-DQN.mountain-car	integration.product.QR-DQN.mountain-car	e2e.product.QR-DQN.mountain-car	checkpoint-required-fail-closed	linux-cpu
QR-DQN/key-door-grid	generated-matrix:product-row-QR-DQN.key-door-grid	integration.product.QR-DQN.key-door-grid	e2e.product.QR-DQN.key-door-grid	checkpoint-required-fail-closed	linux-cpu
DDPG/lunar-lander	generated-matrix:product-row-DDPG.lunar-lander	integration.product.DDPG.lunar-lander	e2e.product.DDPG.lunar-lander	checkpoint-required-fail-closed	linux-cpu
TD3/lunar-lander	generated-matrix:product-row-TD3.lunar-lander	integration.product.TD3.lunar-lander	e2e.product.TD3.lunar-lander	checkpoint-required-fail-closed	linux-cpu
SAC/lunar-lander	generated-matrix:product-row-SAC.lunar-lander	integration.product.SAC.lunar-lander	e2e.product.SAC.lunar-lander	checkpoint-required-fail-closed	linux-cpu
SAC/pendulum	generated-matrix:product-row-SAC.pendulum	integration.product.SAC.pendulum	e2e.product.SAC.pendulum	checkpoint-required-fail-closed	linux-cpu
CrossQ/lunar-lander	generated-matrix:product-row-CrossQ.lunar-lander	integration.product.CrossQ.lunar-lander	e2e.product.CrossQ.lunar-lander	checkpoint-required-fail-closed	linux-cpu
TQC/lunar-lander	generated-matrix:product-row-TQC.lunar-lander	integration.product.TQC.lunar-lander	e2e.product.TQC.lunar-lander	checkpoint-required-fail-closed	linux-cpu
ARS/cartpole	generated-matrix:product-row-ARS.cartpole	integration.product.ARS.cartpole	e2e.product.ARS.cartpole	checkpoint-required-fail-closed	linux-cpu
ARS/mountain-car	generated-matrix:product-row-ARS.mountain-car	integration.product.ARS.mountain-car	e2e.product.ARS.mountain-car	checkpoint-required-fail-closed	linux-cpu
ARS/lunar-lander	generated-matrix:product-row-ARS.lunar-lander	integration.product.ARS.lunar-lander	e2e.product.ARS.lunar-lander	checkpoint-required-fail-closed	linux-cpu
ARS/key-door-grid	generated-matrix:product-row-ARS.key-door-grid	integration.product.ARS.key-door-grid	e2e.product.ARS.key-door-grid	checkpoint-required-fail-closed	linux-cpu
HER/goal-reaching	generated-matrix:product-row-HER.goal-reaching	integration.product.HER.goal-reaching	e2e.product.HER.goal-reaching	checkpoint-required-fail-closed	linux-cpu
connect4	generated-matrix:product-row-connect4	integration.product.connect4	e2e.product.connect4	checkpoint-required-fail-closed	linux-cpu
othello	generated-matrix:product-row-othello	integration.product.othello	e2e.product.othello	checkpoint-required-fail-closed	linux-cpu
hex	generated-matrix:product-row-hex	integration.product.hex	e2e.product.hex	checkpoint-required-fail-closed	linux-cpu
gomoku	generated-matrix:product-row-gomoku	integration.product.gomoku	e2e.product.gomoku	checkpoint-required-fail-closed	linux-cpu
hyperparameter-tuning	generated-matrix:product-row-hyperparameter-tuning	integration.product.hyperparameter-tuning	e2e.product.hyperparameter-tuning	checkpoint-required-fail-closed	linux-cpu
tic-tac-toe	non-product: unit-level minimax anchor documented outside the product matrix	not-required	not-required	not-required	not-required
atari-subset	non-product: optional ROM-backed runtime support, not a required product row	not-required	not-required	not-required	not-required
```

## Historical validation gate (all green)

| Command | Result |
|---|---|
| `docker compose run --rm jitml jitml test all --live --linux-cpu` | 8/8 stanzas PASS (`cabal_test: passed: 8, failed: 0`) |
| `docker compose run --rm jitml jitml docs check` | ok |
| `docker compose run --rm jitml jitml check-code` | ok |
| `docker compose run --rm jitml jitml lint haskell --write` (fourmolu + hlint) | ok |
| in-image `jitml check-code` (run during `jitml bootstrap --linux-cpu` image build) | ok |

The full-stack rollout came up clean: `bootstrap/linux-cpu.sh up` completed a
**130-step** live phased rollout (all platform components Ready — MinIO, Harbor +
`harbor-pg`, Pulsar broker/bookie/zookeeper/proxy, kube-prometheus-stack,
TensorBoard, `jitml-service`, `jitml-demo`) and wrote the leased-port publication
at the Envoy edge `127.0.0.1:9091`. All **12 canonical dataset blobs** (MNIST ×4,
Fashion-MNIST ×4, CIFAR-10, CIFAR-100, California Housing, Tiny ImageNet) were
SHA-verified against the pinned `JitML.SL.Dataset` hashes and staged into live
MinIO via `jitml internal upload-dataset`, and the eight demo checkpoints were
seeded via `jitml internal seed-demo-checkpoints`. During the 2026-06-29
aggregation, stale MNIST train placeholders (`28B` / `14B`) were deleted and
replaced with the canonical gzip artifacts before `jitml-sl-canonicals` and the
full live lane were rerun. During the 2026-06-30 Sprint `18.6` re-aggregation,
the canonical dataset artifacts were present, `jitml internal seed-demo-checkpoints`
re-seeded the eight demo checkpoints, and the full live report-card run passed
with `browser_product_matrix` populated. During Sprint `18.7`, the Envoy Gateway
data plane was restarted after the publication pointed at an unprogrammed edge,
all 12 canonical dataset artifacts were restaged through `jitml internal
upload-dataset`, the eight demo checkpoints were seeded again, and the full live
report-card run passed with `browser_product_matrix` **8 / 8** and no
`unavailable` row.

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
  sl_final_loss: mnist-shallow-mlp=TrainingMetrics {tmTrainLoss = 1.8540103969868302, tmValidationLoss = 1.8269221874061756, tmExamplesProcessed = 5001, tmHeldOutMetric = Just ("test_acc",0.348)}
  rl_final_reward: ppo/cartpole=119.99308238573022
  alphazero_arena_win_rate: connect4/gen0=0.75
  tune_best_objective: TPE=1.0
  jit_cache_hit_rate: prometheus=1.0 hits=1 misses=0
  daemon_healthz: http://127.0.0.1:9091/healthz status=200
  browser_product_matrix: checkpoint-backed product panels 8/8 served at edge :9091
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

## Browser product matrix — `15/15` via live Playwright

The live Playwright product matrix ran against the `linux-cpu` Envoy edge
(`http://127.0.0.1:9091/`) after `jitml internal seed-demo-checkpoints`, via the
`mcr.microsoft.com/playwright:v1.49.1-noble` browser image (host networking),
exit `0`. The matrix is **15 tests**: the 11 baseline panels, the three
**Sprint `14.1` net-new browser product features** (checkpoint browse,
live-backed workflow-state reconciliation, and persisted-transcript adversarial
replay), plus the adversarial-game selector coverage added for Sprint `14.3`:

```
15 passed
(15/15 — exit 0)
  ✓ demo shell responds and renders the portals home
  ✓ portals home links to every bundled admin portal
  ✓ shared header is present on every panel
  ✓ mnist panel renders an inference canvas          (kind: InferenceResult)
  ✓ generic inference panel renders checkpoint output (kind: GenericInferenceResult)
  ✓ cifar panel renders an upload control            (kind: ImageInferenceResult)
  ✓ checkpoint compare panel renders output deltas   (kind: CheckpointCompareResult)
  ✓ connect4 panel renders the board                 (kind: AdversarialMoveResult)
  ✓ adversarial panel selector exercises seeded games/checkpoints
  ✓ checkpoint browse panel lists seeded checkpoints  (kind: CheckpointList)
  ✓ workflow status panel renders a live status table (kind: WorkflowStatus)    [NEW 14.1]
  ✓ transcript replay scrubs a persisted adversarial game (real MinIO transcript)[NEW 14.1]
  ✓ rl panel renders an episode timeline
  ✓ training panel renders a loss curve
  ✓ tune panel renders the trial heatmap
```

The checkpoint-backed panels now submit user-derived inputs and parse full
Engine-backed result frames. The report-card `browser_product_matrix` **8/8**
probe independently confirms every seeded checkpoint-backed product panel serves
its result kind. The three Sprint `14.1` features are real and live-backed:
**checkpoint browse** lists the seeded checkpoints from MinIO via a
`ListCheckpoints` Engine workflow; **workflow status** renders reconciled
`WorkflowStatus` frames the Engine projects to `workflow.status.<substrate>`; and
**transcript replay** scrubs a game's moves read back from a real persisted
`jitml-transcripts` MinIO object (the persisted `.cbor` object is confirmed in the
bucket). The matrix exits `0` — **all 15 pass**.
