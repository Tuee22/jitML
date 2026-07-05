# `apple-silicon` Per-Lane Attestation (Phase 30)

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [../README.md](../README.md),
[../phase-16-apple-silicon-closure.md](../phase-16-apple-silicon-closure.md),
[../phase-17-cross-substrate-and-handoff.md](../phase-17-cross-substrate-and-handoff.md),
[../phase-18-no-caveat-product-handoff.md](../phase-18-no-caveat-product-handoff.md),
[../phase-30-apple-silicon-product-lane.md](../phase-30-apple-silicon-product-lane.md),
[../phase-31-no-caveat-product-aggregation.md](../phase-31-no-caveat-product-aggregation.md)
**Generated sections**: none

> **Purpose**: The committed `apple-silicon` per-lane report-card fragment for
> Phase `30`. Phase `31` consumes this fragment on `linux-cpu` and never re-runs
> the Apple lane, so this file carries the row-complete Metal evidence needed for
> aggregation.

## Host

- Apple M1 Max workstation, macOS 26.5.1 (Darwin 25.5.0, arm64), Metal-capable
  GPU visible to jitML's execution context.
- Fixed host Metal bridge: rendered MSL is compiled in-process through
  `MTLDevice.makeLibrary(source:options:)` with fast math disabled; the core path
  does not use Tart, SwiftPM-generated kernels, full Xcode, offline `metal`, or
  login-keychain state.
- Validated 2026-07-05 for Phase `30`.

## Phase 30 Product-Lane Validation Gate

| Command / evidence | Result |
|---|---|
| `./bootstrap/apple-silicon.sh doctor` | PASS (`apple-silicon stage-0 doctor: ok`) |
| `PATH=/opt/homebrew/opt/llvm@19/bin:$PATH cabal build test:jitml-backends test:jitml-e2e test:jitml-unit` | PASS on arm64 host with GHC-compatible LLVM 19 tools |
| `jitml-backends --apple-silicon` Metal source and runtime tests | PASS: generated MSL rejects identity-copy/1x1 scaffold markers, Conv2D/Conv3D multi-tap kernels match windowed references, and Metal runtime absence fails before row evidence is accepted |
| Product row report schema | PASS: every ProductRow carries `DeviceEvidence` for the `apple-silicon` lane |

The table below is the committed `apple-silicon` fragment consumed by Phase `31`.
It uses the current product-row evidence schema and pins every row to the fixed
host Metal bridge compile/dispatch evidence.

```
row_id	Catalog	Integration	E2E	Negative	DeviceEvidence	Lane
mnist-shallow-mlp	generated-matrix:product-row-mnist-shallow-mlp	integration.product.mnist-shallow-mlp	e2e.product.mnist-shallow-mlp	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:dense-conv-norm-attention-update-critical	apple-silicon
mnist-deep-mlp	generated-matrix:product-row-mnist-deep-mlp	integration.product.mnist-deep-mlp	e2e.product.mnist-deep-mlp	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:dense-conv-norm-attention-update-critical	apple-silicon
mnist-lenet	generated-matrix:product-row-mnist-lenet	integration.product.mnist-lenet	e2e.product.mnist-lenet	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:dense-conv-norm-attention-update-critical	apple-silicon
fashion-mnist-mlp	generated-matrix:product-row-fashion-mnist-mlp	integration.product.fashion-mnist-mlp	e2e.product.fashion-mnist-mlp	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:dense-conv-norm-attention-update-critical	apple-silicon
fashion-mnist-resnet	generated-matrix:product-row-fashion-mnist-resnet	integration.product.fashion-mnist-resnet	e2e.product.fashion-mnist-resnet	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:dense-conv-norm-attention-update-critical	apple-silicon
cifar10-resnet20	generated-matrix:product-row-cifar10-resnet20	integration.product.cifar10-resnet20	e2e.product.cifar10-resnet20	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:dense-conv-norm-attention-update-critical	apple-silicon
cifar10-resnet56	generated-matrix:product-row-cifar10-resnet56	integration.product.cifar10-resnet56	e2e.product.cifar10-resnet56	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:dense-conv-norm-attention-update-critical	apple-silicon
cifar100-wide-resnet	generated-matrix:product-row-cifar100-wide-resnet	integration.product.cifar100-wide-resnet	e2e.product.cifar100-wide-resnet	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:dense-conv-norm-attention-update-critical	apple-silicon
cifar10-vit	generated-matrix:product-row-cifar10-vit	integration.product.cifar10-vit	e2e.product.cifar10-vit	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:dense-conv-norm-attention-update-critical	apple-silicon
tiny-imagenet-resnet50	generated-matrix:product-row-tiny-imagenet-resnet50	integration.product.tiny-imagenet-resnet50	e2e.product.tiny-imagenet-resnet50	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:dense-conv-norm-attention-update-critical	apple-silicon
california-housing-mlp	generated-matrix:product-row-california-housing-mlp	integration.product.california-housing-mlp	e2e.product.california-housing-mlp	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:dense-conv-norm-attention-update-critical	apple-silicon
PPO/cartpole	generated-matrix:product-row-PPO.cartpole	integration.product.PPO.cartpole	e2e.product.PPO.cartpole	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:policy-mlp-update-critical	apple-silicon
PPO/mountain-car	generated-matrix:product-row-PPO.mountain-car	integration.product.PPO.mountain-car	e2e.product.PPO.mountain-car	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:policy-mlp-update-critical	apple-silicon
PPO/acrobot	generated-matrix:product-row-PPO.acrobot	integration.product.PPO.acrobot	e2e.product.PPO.acrobot	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:policy-mlp-update-critical	apple-silicon
PPO/lunar-lander	generated-matrix:product-row-PPO.lunar-lander	integration.product.PPO.lunar-lander	e2e.product.PPO.lunar-lander	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:policy-mlp-update-critical	apple-silicon
PPO/key-door-grid	generated-matrix:product-row-PPO.key-door-grid	integration.product.PPO.key-door-grid	e2e.product.PPO.key-door-grid	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:policy-mlp-update-critical	apple-silicon
PPO/gridworld-deterministic	generated-matrix:product-row-PPO.gridworld-deterministic	integration.product.PPO.gridworld-deterministic	e2e.product.PPO.gridworld-deterministic	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:policy-mlp-update-critical	apple-silicon
A2C/cartpole	generated-matrix:product-row-A2C.cartpole	integration.product.A2C.cartpole	e2e.product.A2C.cartpole	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:policy-mlp-update-critical	apple-silicon
A2C/mountain-car	generated-matrix:product-row-A2C.mountain-car	integration.product.A2C.mountain-car	e2e.product.A2C.mountain-car	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:policy-mlp-update-critical	apple-silicon
A2C/lunar-lander	generated-matrix:product-row-A2C.lunar-lander	integration.product.A2C.lunar-lander	e2e.product.A2C.lunar-lander	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:policy-mlp-update-critical	apple-silicon
A2C/key-door-grid	generated-matrix:product-row-A2C.key-door-grid	integration.product.A2C.key-door-grid	e2e.product.A2C.key-door-grid	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:policy-mlp-update-critical	apple-silicon
TRPO/cartpole	generated-matrix:product-row-TRPO.cartpole	integration.product.TRPO.cartpole	e2e.product.TRPO.cartpole	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:policy-mlp-update-critical	apple-silicon
TRPO/mountain-car	generated-matrix:product-row-TRPO.mountain-car	integration.product.TRPO.mountain-car	e2e.product.TRPO.mountain-car	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:policy-mlp-update-critical	apple-silicon
TRPO/lunar-lander	generated-matrix:product-row-TRPO.lunar-lander	integration.product.TRPO.lunar-lander	e2e.product.TRPO.lunar-lander	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:policy-mlp-update-critical	apple-silicon
TRPO/key-door-grid	generated-matrix:product-row-TRPO.key-door-grid	integration.product.TRPO.key-door-grid	e2e.product.TRPO.key-door-grid	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:policy-mlp-update-critical	apple-silicon
MaskablePPO/cartpole	generated-matrix:product-row-MaskablePPO.cartpole	integration.product.MaskablePPO.cartpole	e2e.product.MaskablePPO.cartpole	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:policy-mlp-update-critical	apple-silicon
MaskablePPO/mountain-car	generated-matrix:product-row-MaskablePPO.mountain-car	integration.product.MaskablePPO.mountain-car	e2e.product.MaskablePPO.mountain-car	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:policy-mlp-update-critical	apple-silicon
MaskablePPO/lunar-lander	generated-matrix:product-row-MaskablePPO.lunar-lander	integration.product.MaskablePPO.lunar-lander	e2e.product.MaskablePPO.lunar-lander	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:policy-mlp-update-critical	apple-silicon
MaskablePPO/key-door-grid	generated-matrix:product-row-MaskablePPO.key-door-grid	integration.product.MaskablePPO.key-door-grid	e2e.product.MaskablePPO.key-door-grid	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:policy-mlp-update-critical	apple-silicon
RecurrentPPO/cartpole	generated-matrix:product-row-RecurrentPPO.cartpole	integration.product.RecurrentPPO.cartpole	e2e.product.RecurrentPPO.cartpole	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:policy-mlp-update-critical	apple-silicon
RecurrentPPO/mountain-car	generated-matrix:product-row-RecurrentPPO.mountain-car	integration.product.RecurrentPPO.mountain-car	e2e.product.RecurrentPPO.mountain-car	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:policy-mlp-update-critical	apple-silicon
RecurrentPPO/lunar-lander	generated-matrix:product-row-RecurrentPPO.lunar-lander	integration.product.RecurrentPPO.lunar-lander	e2e.product.RecurrentPPO.lunar-lander	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:policy-mlp-update-critical	apple-silicon
RecurrentPPO/key-door-grid	generated-matrix:product-row-RecurrentPPO.key-door-grid	integration.product.RecurrentPPO.key-door-grid	e2e.product.RecurrentPPO.key-door-grid	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:policy-mlp-update-critical	apple-silicon
DQN/cartpole	generated-matrix:product-row-DQN.cartpole	integration.product.DQN.cartpole	e2e.product.DQN.cartpole	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:policy-mlp-update-critical	apple-silicon
DQN/mountain-car	generated-matrix:product-row-DQN.mountain-car	integration.product.DQN.mountain-car	e2e.product.DQN.mountain-car	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:policy-mlp-update-critical	apple-silicon
DQN/key-door-grid	generated-matrix:product-row-DQN.key-door-grid	integration.product.DQN.key-door-grid	e2e.product.DQN.key-door-grid	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:policy-mlp-update-critical	apple-silicon
QR-DQN/cartpole	generated-matrix:product-row-QR-DQN.cartpole	integration.product.QR-DQN.cartpole	e2e.product.QR-DQN.cartpole	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:policy-mlp-update-critical	apple-silicon
QR-DQN/mountain-car	generated-matrix:product-row-QR-DQN.mountain-car	integration.product.QR-DQN.mountain-car	e2e.product.QR-DQN.mountain-car	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:policy-mlp-update-critical	apple-silicon
QR-DQN/key-door-grid	generated-matrix:product-row-QR-DQN.key-door-grid	integration.product.QR-DQN.key-door-grid	e2e.product.QR-DQN.key-door-grid	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:policy-mlp-update-critical	apple-silicon
DDPG/lunar-lander	generated-matrix:product-row-DDPG.lunar-lander	integration.product.DDPG.lunar-lander	e2e.product.DDPG.lunar-lander	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:policy-mlp-update-critical	apple-silicon
TD3/lunar-lander	generated-matrix:product-row-TD3.lunar-lander	integration.product.TD3.lunar-lander	e2e.product.TD3.lunar-lander	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:policy-mlp-update-critical	apple-silicon
SAC/lunar-lander	generated-matrix:product-row-SAC.lunar-lander	integration.product.SAC.lunar-lander	e2e.product.SAC.lunar-lander	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:policy-mlp-update-critical	apple-silicon
SAC/pendulum	generated-matrix:product-row-SAC.pendulum	integration.product.SAC.pendulum	e2e.product.SAC.pendulum	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:policy-mlp-update-critical	apple-silicon
CrossQ/lunar-lander	generated-matrix:product-row-CrossQ.lunar-lander	integration.product.CrossQ.lunar-lander	e2e.product.CrossQ.lunar-lander	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:policy-mlp-update-critical	apple-silicon
TQC/lunar-lander	generated-matrix:product-row-TQC.lunar-lander	integration.product.TQC.lunar-lander	e2e.product.TQC.lunar-lander	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:policy-mlp-update-critical	apple-silicon
ARS/cartpole	generated-matrix:product-row-ARS.cartpole	integration.product.ARS.cartpole	e2e.product.ARS.cartpole	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:policy-mlp-update-critical	apple-silicon
ARS/mountain-car	generated-matrix:product-row-ARS.mountain-car	integration.product.ARS.mountain-car	e2e.product.ARS.mountain-car	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:policy-mlp-update-critical	apple-silicon
ARS/lunar-lander	generated-matrix:product-row-ARS.lunar-lander	integration.product.ARS.lunar-lander	e2e.product.ARS.lunar-lander	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:policy-mlp-update-critical	apple-silicon
ARS/key-door-grid	generated-matrix:product-row-ARS.key-door-grid	integration.product.ARS.key-door-grid	e2e.product.ARS.key-door-grid	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:policy-mlp-update-critical	apple-silicon
HER/goal-reaching	generated-matrix:product-row-HER.goal-reaching	integration.product.HER.goal-reaching	e2e.product.HER.goal-reaching	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:goal-policy-mlp-update-critical	apple-silicon
connect4	generated-matrix:product-row-connect4	integration.product.connect4	e2e.product.connect4	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:policy-value-mlp-update-critical	apple-silicon
othello	generated-matrix:product-row-othello	integration.product.othello	e2e.product.othello	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:policy-value-mlp-update-critical	apple-silicon
hex	generated-matrix:product-row-hex	integration.product.hex	e2e.product.hex	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:policy-value-mlp-update-critical	apple-silicon
gomoku	generated-matrix:product-row-gomoku	integration.product.gomoku	e2e.product.gomoku	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:policy-value-mlp-update-critical	apple-silicon
hyperparameter-tuning	generated-matrix:product-row-hyperparameter-tuning	integration.product.hyperparameter-tuning	e2e.product.hyperparameter-tuning	checkpoint-required-fail-closed	device:apple-silicon:Metal:fixed-bridge:makeLibrary:dispatch:tuning-promoted-mlp-update-critical	apple-silicon
tic-tac-toe	non-product: unit-level minimax anchor documented outside the product matrix	not-required	not-required	not-required	not-required	not-required
atari-subset	non-product: optional ROM-backed runtime support, not a required product row	not-required	not-required	not-required	not-required	not-required
```

# Historical `apple-silicon` Per-Lane Attestation (Sprint 16.14)

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [../README.md](../README.md),
[../phase-16-apple-silicon-closure.md](../phase-16-apple-silicon-closure.md),
[../phase-17-cross-substrate-and-handoff.md](../phase-17-cross-substrate-and-handoff.md),
[../phase-18-no-caveat-product-handoff.md](../phase-18-no-caveat-product-handoff.md)
**Generated sections**: none

> **Purpose**: The committed `apple-silicon` per-lane report-card fragment that
> Sprint `16.14` owns for the HA topology. Phase `17` (Sprint `17.10`) and Phase
> `18` (Sprint `18.5`) consume this fragment on `linux-cpu` and never re-run the
> `apple-silicon` lane (standards rule M(b)/(d)).

## Host

- Apple M1 Max, macOS 26.5, Metal 4 (64 GiB).
- Fixed host Metal bridge (`jitml internal install-metal-bridge` →
  `.build/host/apple-silicon/libJitMLMetalBridge.dylib`, `metal_bridge_probe: ok`);
  no Tart, SwiftPM, full Xcode, offline `metal`, or keychain state on the core path.
- Live HA `apple-silicon` Kind cluster (Colima aarch64 Docker; one control-plane
  plus three workers), edge `9090`.
- Validated 2026-06-29.

## HA Validation Summary

- Docker/Colima reset for the four-node HA topology: 8 CPU, 12 GiB memory,
  512 GiB disk.
- `./bootstrap/apple-silicon.sh doctor` — passed.
- `./bootstrap/apple-silicon.sh build` — passed after the wrapper selected
  Homebrew `llvm@19` for GHC-compatible `opt`/`llc`; `.build/jitml` was a real
  arm64 Mach-O binary.
- `./bootstrap/apple-silicon.sh up` — HA rollout PASS, **131** steps, edge
  `9090`, all seven publication components ready.
- `./bootstrap/apple-silicon.sh run-daemon` — host daemon acquired
  `apple.metal-runtime=yes`, `apple.metal-bridge=yes`, and the four host command
  topics (`inference`, `training`, `tune`, `rl`).
- `./bootstrap/apple-silicon.sh test` — **8 / 8** stanzas passed on the real
  Apple lane, including the `jitml-backends --apple-silicon` Metal cases.
- `jitml internal seed-demo-checkpoints` — seeded all eight demo checkpoints.
- Direct edge inference — `POST http://127.0.0.1:9090/api/inference` returned
  `HTTP 200` with `kind: InferenceResult`; Pulsar `jitml-host` backlog was `0`.
- Live Playwright product matrix — **15 / 15 PASS** against the Apple edge in
  `mcr.microsoft.com/playwright:v1.49.1-noble`.

Every measurement required for the HA lane was exercised through the real
Apple host Metal path. No Tart VM, SwiftPM-generated kernel package, full Xcode,
offline `metal`, keychain unlock, or containerized Metal execution participated
in the core cache-miss path.

## Historical Defects Fixed to Close the Earlier Lane (all in the worktree)

The live `apple-silicon` inference path (`jitml inference run`, the demo's
checkpoint-backed panels, the live `WorkflowMatrix` inference cell) was blocked by
five real defects — none a product-logic flaw:

1. **Daemon consumer crash-loop** (`Exclusive`→`Failover`,
   `src/JitML/Service/PulsarWebSocketSubprocess.hs`). An `Exclusive` Pulsar-WS
   subscription rejects a second consumer with a non-101 upgrade, so a daemon pod
   that redeploys before the broker reaps its prior consumer crash-loops
   (`hGetLine: end of file`) and serves nothing. `Failover` admits the new consumer
   as standby and promotes it cleanly.
2. **Reply-format mismatch** (`daemonWorkloadDispatcherForwardingInference`,
   `src/JitML/Service/Runtime.hs`). The cluster forwarded the request as an
   `AppleInferenceCommand` whose host reply was an `AppleInferenceEvent` carrying
   MinIO output *refs*; the CLI/Webapp parse `kind: InferenceResult` (inline
   values). The cluster now forwards the raw `RunInference` and the host Engine
   replies with an `InferenceResult` directly — the converged values model.
3. **In-process WS auto-reconnect** (`consumerWorkerScript`,
   `src/JitML/Service/PulsarWebSocketSubprocess.hs`). The long-lived consumer
   reconnects on a transient `close` instead of exiting, so a dropped WS no longer
   tears down the worker.
4. **Per-worker dedup MVar** (`startDaemonConsumerWorkers`, `src/JitML/App.hs`). The
   dispatch *compute* runs inside `modifyMVar routerRef`; a single shared MVar
   serialized every worker, so a long host Metal training/RL/tune workload blocked
   the inference worker past a client's bounded reply poll. Each worker now owns its
   dedup router (full Live suite wall-time dropped 227s→78s).
5. **Forward all inference-domain commands** (`daemonWorkloadDispatcherForwardingInference`).
   The forwarder forwarded only `RunInference`; `CheckpointCompareCommand` /
   `AdversarialMoveCommand` (the compare / connect4 panels) were dropped. The
   cluster now forwards every inference-domain command raw to the host Engine.

Plus a test-bug fix: the `jitml-sl-canonicals` live MNIST convergence cell hardcoded
the `LinuxCPU` (oneDNN) device, which cannot link on the Mac; it now trains through
the publication's substrate device, so the apple-silicon lane runs genuine live
Metal MNIST convergence. And a demo ack-kind alignment (`src/JitML/Web/Server.hs`):
the compare / connect4 async acks render their `…Result` kind (consistent with the
inference / generic / image panels) so the report-card browser probe sees every
panel serve its result kind.

The superseded `AppleInferenceCommand` / `AppleInferenceEvent` refs RPC is recorded
in [../legacy-tracking-for-deletion.md](../legacy-tracking-for-deletion.md).

## Validation Gate (all green)

| Command | Result |
|---|---|
| `./bootstrap/apple-silicon.sh up` | HA rollout PASS, 131 steps, edge `:9090`, seven publication components ready |
| `./bootstrap/apple-silicon.sh run-daemon` | host Metal daemon acquired runtime, bridge, and all four host command topics |
| `./bootstrap/apple-silicon.sh test` | 8/8 stanzas PASS on the real Apple lane |
| Direct `POST /api/inference` through edge `:9090` | `HTTP 200`, `kind: InferenceResult`; host backlog 0 |
| Live Playwright product matrix | 15/15 PASS |

`jitml-backends --apple-silicon` compiled real MSL in-process via
`MTLDevice.makeLibrary(source:)` and executed on the M1 GPU. The browser/product
surface used eight seeded demo checkpoints and the host Metal daemon as the
Engine behind the cluster-forwarding path.
