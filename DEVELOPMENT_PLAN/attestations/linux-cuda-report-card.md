# Current `linux-cuda` Per-Lane Attestation (Phase 29)

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [../README.md](../README.md),
[../phase-29-linux-cuda-product-lane.md](../phase-29-linux-cuda-product-lane.md),
[../phase-15-linux-cuda-and-cluster-closure.md](../phase-15-linux-cuda-and-cluster-closure.md),
[../phase-17-cross-substrate-and-handoff.md](../phase-17-cross-substrate-and-handoff.md),
[../phase-18-no-caveat-product-handoff.md](../phase-18-no-caveat-product-handoff.md)
**Generated sections**: none

> **Purpose**: The current `linux-cuda` per-lane report-card fragment for Phase
> `29`. This fragment records the fresh current-source CUDA publisher,
> integration/e2e, live Playwright, and performance evidence consumed by Phase
> `31` aggregation. Sprints `15.20`-`15.22` remain historical CUDA HA/runtime
> evidence for the earlier product baseline.

## Host

- NVIDIA GeForce RTX 5090, UUID `GPU-e764ef97-32d7-4981-c348-029983c64073`
- CUDA 12.8, driver `570.211.01`, Ubuntu 24.04 (x86_64), Docker 29.x,
  NVIDIA Container Runtime
- Current 2026-07-10 Phase `29` product-lane run. The current host exposes the
  NVIDIA runtime and `jitml-backends --linux-cuda` passes **22 / 22**.

## Current Phase 29 Product-Lane Validation Gate

| Command / evidence | Result |
|---|---|
| `docker info --format '{{json .Runtimes}}'` / `docker compose run --rm jitml-cuda nvidia-smi` | NVIDIA runtime present; in-container `nvidia-smi` saw NVIDIA GeForce RTX 5090, driver `570.211.01`, CUDA `12.8` |
| Live CUDA publication | Existing current CUDA publication selected at edge `:9092`; all seven components reported ready through `jitml cluster status` |
| Canonical dataset/ProductRow checkpoint staging | Current-source CUDA publisher produced **55 / 55** eligible ProductRows with **0** unsupported rows and **0** errors; live MinIO was refreshed with **407** ProductRow checkpoint objects from those validated local publisher artifacts through the signed edge route |
| `docker compose run --rm jitml-cuda jitml test jitml-backends --linux-cuda` | **22 / 22** PASS, including cuBLAS/cuDNN execution and the persistent CUDA MLP weight-buffer source guard |
| `docker compose run --rm jitml-cuda cabal run -fcuda exe:jitml -- internal train-and-publish-product-rows --linux-cuda` | Product checkpoints complete: **55 / 55** eligible rows, **0** unsupported, **0** errors |
| `docker compose run --rm jitml-cuda jitml test jitml-integration --linux-cuda --test-options '-p ProductRow --hide-successes --color=never'` | **56 / 56** ProductRow integration tests PASS |
| `docker compose run --rm jitml-cuda jitml test all --linux-cuda` | **10 / 10** stanzas PASS; `jitml-unit` 278/278, `jitml-integration` 137/137, `jitml-sl-canonicals` 31/31, `jitml-rl-canonicals` 39/39, `jitml-hyperparameter` 19/19, `jitml-backends` 22/22, `jitml-daemon-lifecycle` 32/32, `jitml-e2e` 27/27, `jitml-negative-controls` 3/3, `jitml-model-convergence` 111/111 |
| `docker compose run --rm jitml-cuda jitml test jitml-e2e --linux-cuda` | **27 / 27** PASS |
| `docker compose run --rm jitml-cuda jitml test jitml-e2e --live --linux-cuda` | Haskell e2e **27 / 27** PASS plus live Playwright **71 / 71** at `http://127.0.0.1:9092/`; `browser_product_matrix` **55 / 55** |
| `docker compose run --rm jitml-cuda sh -lc 'cabal run -fcuda exe:jitml -- internal benchmark-product-row-wall-clock'` | Phase `29.4` performance gate PASS: **55 / 55** ProductRows have `linux-cuda` wall-clock strictly less than `linux-cpu` wall-clock |
| `docker compose run --rm jitml-cuda cabal run -fcuda exe:jitml -- test jitml-backends --linux-cuda` | **22 / 22** PASS after the per-weight CUDA MLP batch-gradient update |
| `docker compose run --rm jitml cabal run exe:jitml -- docs check` | PASS (`docs check: ok`) |
| `docker compose run --rm jitml cabal run exe:jitml -- check-code` | PASS (`check-code: ok`) |

`jitml-backends --linux-cuda` compiled and executed the real cuBLAS/cuDNN
generated CUDA family surface (`-fcuda`) on the attached RTX 5090. The Phase
`29.1` backend assertion verifies generated source contains `cublasSgemm`,
`cudnnConvolutionForward`, cuDNN tensor descriptors, and cuDNN normalization
entry points, and the lane then executes the generated kernels on the real GPU.

## Phase 29.4 Performance Timing Table (2026-07-10)

Measured by:

```bash
docker compose run --rm jitml-cuda sh -lc 'cabal run -fcuda exe:jitml -- internal benchmark-product-row-wall-clock'
```

The command warms both real MLP devices, measures each ProductRow through the
same public `MlpDevice` API, and fails unless every row's `linux-cuda` wall-clock
is strictly less than the `linux-cpu` baseline. Result: **PASS**, **55 / 55**
rows faster on `linux-cuda`.

| ProductRow | Shape | Batch | Reps | linux-cpu seconds | linux-cuda seconds | Speedup | Status |
|---|---:|---:|---:|---:|---:|---:|---|
| `mnist-shallow-mlp` | 784x64x10 | 2048 | 4 | 1.206674 | 0.505556 | 2.386824 | PASS |
| `mnist-deep-mlp` | 784x128x10 | 2048 | 4 | 1.962170 | 0.627011 | 3.129403 | PASS |
| `mnist-lenet` | 784x96x10 | 2048 | 4 | 1.614431 | 0.634418 | 2.544743 | PASS |
| `fashion-mnist-mlp` | 784x96x10 | 2048 | 4 | 1.628659 | 0.641233 | 2.539888 | PASS |
| `fashion-mnist-resnet` | 784x160x10 | 2048 | 4 | 2.283322 | 0.664589 | 3.435692 | PASS |
| `cifar10-resnet20` | 3072x192x10 | 512 | 4 | 2.736958 | 0.868611 | 3.150960 | PASS |
| `cifar10-resnet56` | 3072x256x10 | 512 | 4 | 3.460169 | 0.955530 | 3.621205 | PASS |
| `cifar100-wide-resnet` | 3072x256x100 | 512 | 4 | 3.543992 | 0.853608 | 4.151781 | PASS |
| `cifar10-vit` | 3072x256x10 | 512 | 4 | 3.396690 | 0.843456 | 4.027111 | PASS |
| `tiny-imagenet-resnet50` | 3072x320x200 | 512 | 4 | 4.436388 | 1.178175 | 3.765475 | PASS |
| `california-housing-mlp` | 8x96x1 | 2048 | 4 | 0.019964 | 0.006636 | 3.008330 | PASS |
| `PPO/cartpole` | 4x128x2 | 65536 | 4 | 1.154179 | 0.323944 | 3.562892 | PASS |
| `PPO/mountain-car` | 2x128x3 | 65536 | 4 | 1.110585 | 0.290605 | 3.821624 | PASS |
| `PPO/acrobot` | 6x128x3 | 65536 | 4 | 1.441614 | 0.445420 | 3.236529 | PASS |
| `PPO/lunar-lander` | 8x128x4 | 65536 | 4 | 1.699346 | 0.459264 | 3.700148 | PASS |
| `PPO/key-door-grid` | 16x128x4 | 65536 | 4 | 2.287272 | 0.798312 | 2.865137 | PASS |
| `PPO/gridworld-deterministic` | 8x128x4 | 65536 | 4 | 1.685447 | 0.557014 | 3.025863 | PASS |
| `A2C/cartpole` | 4x128x2 | 65536 | 4 | 1.115364 | 0.309564 | 3.603012 | PASS |
| `A2C/mountain-car` | 2x128x3 | 65536 | 4 | 1.121857 | 0.298352 | 3.760181 | PASS |
| `A2C/lunar-lander` | 8x128x4 | 65536 | 4 | 1.707486 | 0.514747 | 3.317136 | PASS |
| `A2C/key-door-grid` | 16x128x4 | 65536 | 4 | 2.266345 | 0.785858 | 2.883912 | PASS |
| `TRPO/cartpole` | 4x128x2 | 65536 | 4 | 1.098936 | 0.312734 | 3.513967 | PASS |
| `TRPO/mountain-car` | 2x128x3 | 65536 | 4 | 1.119074 | 0.290038 | 3.858365 | PASS |
| `TRPO/lunar-lander` | 8x128x4 | 65536 | 4 | 1.691703 | 0.500382 | 3.380824 | PASS |
| `TRPO/key-door-grid` | 16x128x4 | 65536 | 4 | 2.362614 | 0.796947 | 2.964583 | PASS |
| `MaskablePPO/cartpole` | 4x128x2 | 65536 | 4 | 1.136897 | 0.321063 | 3.541037 | PASS |
| `MaskablePPO/mountain-car` | 2x128x3 | 65536 | 4 | 1.119466 | 0.289543 | 3.866325 | PASS |
| `MaskablePPO/lunar-lander` | 8x128x4 | 65536 | 4 | 1.831541 | 0.608859 | 3.008155 | PASS |
| `MaskablePPO/key-door-grid` | 16x128x4 | 65536 | 4 | 2.358427 | 0.820457 | 2.874527 | PASS |
| `RecurrentPPO/cartpole` | 4x128x2 | 65536 | 4 | 1.201206 | 0.319530 | 3.759295 | PASS |
| `RecurrentPPO/mountain-car` | 2x128x3 | 65536 | 4 | 1.204529 | 0.291490 | 4.132323 | PASS |
| `RecurrentPPO/lunar-lander` | 8x128x4 | 65536 | 4 | 1.755374 | 0.520671 | 3.371366 | PASS |
| `RecurrentPPO/key-door-grid` | 16x128x4 | 65536 | 4 | 2.434556 | 0.854252 | 2.849927 | PASS |
| `DQN/cartpole` | 4x128x2 | 65536 | 4 | 1.131112 | 0.334273 | 3.383800 | PASS |
| `DQN/mountain-car` | 2x128x3 | 65536 | 4 | 1.167069 | 0.291738 | 4.000395 | PASS |
| `DQN/key-door-grid` | 16x128x4 | 65536 | 4 | 2.420547 | 0.824445 | 2.935970 | PASS |
| `QR-DQN/cartpole` | 4x128x2 | 65536 | 4 | 1.146252 | 0.322452 | 3.554800 | PASS |
| `QR-DQN/mountain-car` | 2x128x3 | 65536 | 4 | 1.154032 | 0.287194 | 4.018300 | PASS |
| `QR-DQN/key-door-grid` | 16x128x4 | 65536 | 4 | 2.271558 | 0.715542 | 3.174598 | PASS |
| `DDPG/lunar-lander` | 8x128x2 | 65536 | 4 | 1.422743 | 0.450618 | 3.157314 | PASS |
| `TD3/lunar-lander` | 8x128x2 | 65536 | 4 | 1.413118 | 0.449911 | 3.140885 | PASS |
| `SAC/lunar-lander` | 8x128x2 | 65536 | 4 | 1.405433 | 0.442417 | 3.176714 | PASS |
| `SAC/pendulum` | 3x128x1 | 65536 | 4 | 0.912954 | 0.230979 | 3.952547 | PASS |
| `CrossQ/lunar-lander` | 8x128x2 | 65536 | 4 | 1.382716 | 0.426744 | 3.240153 | PASS |
| `TQC/lunar-lander` | 8x128x2 | 65536 | 4 | 1.402967 | 0.454247 | 3.088555 | PASS |
| `ARS/cartpole` | 4x128x2 | 65536 | 4 | 1.118048 | 0.316045 | 3.537626 | PASS |
| `ARS/mountain-car` | 2x128x3 | 65536 | 4 | 1.152100 | 0.318673 | 3.615301 | PASS |
| `ARS/lunar-lander` | 8x128x4 | 65536 | 4 | 1.780886 | 0.543343 | 3.277647 | PASS |
| `ARS/key-door-grid` | 16x128x4 | 65536 | 4 | 2.360869 | 0.829635 | 2.845672 | PASS |
| `HER/goal-reaching` | 6x128x4 | 65536 | 4 | 1.607028 | 0.483674 | 3.322541 | PASS |
| `connect4` | 42x160x8 | 4096 | 4 | 0.317271 | 0.080631 | 3.934842 | PASS |
| `othello` | 64x192x65 | 4096 | 4 | 0.937725 | 0.225590 | 4.156758 | PASS |
| `hex` | 121x224x122 | 4096 | 4 | 2.022758 | 0.517785 | 3.906556 | PASS |
| `gomoku` | 225x256x226 | 4096 | 4 | 4.518823 | 0.925964 | 4.880129 | PASS |
| `hyperparameter-tuning` | 784x128x10 | 2048 | 4 | 1.997553 | 0.684638 | 2.917678 | PASS |

## Phase 29 Row-Complete Evidence Table (2026-07-10)

The table below is the current `linux-cuda` fragment from 2026-07-10. It is the
row-complete ProductRow evidence consumed by Phase `31` after Sprint `29.4`
adds the strict per-row `linux-cuda` < `linux-cpu` performance table.

```
row_id	Catalog	Integration	E2E	Negative	DeviceEvidence	Lane
mnist-shallow-mlp	generated-matrix:product-row-mnist-shallow-mlp	integration.product.mnist-shallow-mlp	e2e.product.mnist-shallow-mlp	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:dense-conv-norm-attention-update-critical	linux-cuda
mnist-deep-mlp	generated-matrix:product-row-mnist-deep-mlp	integration.product.mnist-deep-mlp	e2e.product.mnist-deep-mlp	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:dense-conv-norm-attention-update-critical	linux-cuda
mnist-lenet	generated-matrix:product-row-mnist-lenet	integration.product.mnist-lenet	e2e.product.mnist-lenet	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:dense-conv-norm-attention-update-critical	linux-cuda
fashion-mnist-mlp	generated-matrix:product-row-fashion-mnist-mlp	integration.product.fashion-mnist-mlp	e2e.product.fashion-mnist-mlp	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:dense-conv-norm-attention-update-critical	linux-cuda
fashion-mnist-resnet	generated-matrix:product-row-fashion-mnist-resnet	integration.product.fashion-mnist-resnet	e2e.product.fashion-mnist-resnet	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:dense-conv-norm-attention-update-critical	linux-cuda
cifar10-resnet20	generated-matrix:product-row-cifar10-resnet20	integration.product.cifar10-resnet20	e2e.product.cifar10-resnet20	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:dense-conv-norm-attention-update-critical	linux-cuda
cifar10-resnet56	generated-matrix:product-row-cifar10-resnet56	integration.product.cifar10-resnet56	e2e.product.cifar10-resnet56	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:dense-conv-norm-attention-update-critical	linux-cuda
cifar100-wide-resnet	generated-matrix:product-row-cifar100-wide-resnet	integration.product.cifar100-wide-resnet	e2e.product.cifar100-wide-resnet	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:dense-conv-norm-attention-update-critical	linux-cuda
cifar10-vit	generated-matrix:product-row-cifar10-vit	integration.product.cifar10-vit	e2e.product.cifar10-vit	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:dense-conv-norm-attention-update-critical	linux-cuda
tiny-imagenet-resnet50	generated-matrix:product-row-tiny-imagenet-resnet50	integration.product.tiny-imagenet-resnet50	e2e.product.tiny-imagenet-resnet50	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:dense-conv-norm-attention-update-critical	linux-cuda
california-housing-mlp	generated-matrix:product-row-california-housing-mlp	integration.product.california-housing-mlp	e2e.product.california-housing-mlp	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:dense-conv-norm-attention-update-critical	linux-cuda
PPO/cartpole	generated-matrix:product-row-PPO.cartpole	integration.product.PPO.cartpole	e2e.product.PPO.cartpole	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:policy-mlp-update-critical	linux-cuda
PPO/mountain-car	generated-matrix:product-row-PPO.mountain-car	integration.product.PPO.mountain-car	e2e.product.PPO.mountain-car	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:policy-mlp-update-critical	linux-cuda
PPO/acrobot	generated-matrix:product-row-PPO.acrobot	integration.product.PPO.acrobot	e2e.product.PPO.acrobot	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:policy-mlp-update-critical	linux-cuda
PPO/lunar-lander	generated-matrix:product-row-PPO.lunar-lander	integration.product.PPO.lunar-lander	e2e.product.PPO.lunar-lander	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:policy-mlp-update-critical	linux-cuda
PPO/key-door-grid	generated-matrix:product-row-PPO.key-door-grid	integration.product.PPO.key-door-grid	e2e.product.PPO.key-door-grid	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:policy-mlp-update-critical	linux-cuda
PPO/gridworld-deterministic	generated-matrix:product-row-PPO.gridworld-deterministic	integration.product.PPO.gridworld-deterministic	e2e.product.PPO.gridworld-deterministic	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:policy-mlp-update-critical	linux-cuda
A2C/cartpole	generated-matrix:product-row-A2C.cartpole	integration.product.A2C.cartpole	e2e.product.A2C.cartpole	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:policy-mlp-update-critical	linux-cuda
A2C/mountain-car	generated-matrix:product-row-A2C.mountain-car	integration.product.A2C.mountain-car	e2e.product.A2C.mountain-car	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:policy-mlp-update-critical	linux-cuda
A2C/lunar-lander	generated-matrix:product-row-A2C.lunar-lander	integration.product.A2C.lunar-lander	e2e.product.A2C.lunar-lander	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:policy-mlp-update-critical	linux-cuda
A2C/key-door-grid	generated-matrix:product-row-A2C.key-door-grid	integration.product.A2C.key-door-grid	e2e.product.A2C.key-door-grid	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:policy-mlp-update-critical	linux-cuda
TRPO/cartpole	generated-matrix:product-row-TRPO.cartpole	integration.product.TRPO.cartpole	e2e.product.TRPO.cartpole	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:policy-mlp-update-critical	linux-cuda
TRPO/mountain-car	generated-matrix:product-row-TRPO.mountain-car	integration.product.TRPO.mountain-car	e2e.product.TRPO.mountain-car	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:policy-mlp-update-critical	linux-cuda
TRPO/lunar-lander	generated-matrix:product-row-TRPO.lunar-lander	integration.product.TRPO.lunar-lander	e2e.product.TRPO.lunar-lander	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:policy-mlp-update-critical	linux-cuda
TRPO/key-door-grid	generated-matrix:product-row-TRPO.key-door-grid	integration.product.TRPO.key-door-grid	e2e.product.TRPO.key-door-grid	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:policy-mlp-update-critical	linux-cuda
MaskablePPO/cartpole	generated-matrix:product-row-MaskablePPO.cartpole	integration.product.MaskablePPO.cartpole	e2e.product.MaskablePPO.cartpole	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:policy-mlp-update-critical	linux-cuda
MaskablePPO/mountain-car	generated-matrix:product-row-MaskablePPO.mountain-car	integration.product.MaskablePPO.mountain-car	e2e.product.MaskablePPO.mountain-car	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:policy-mlp-update-critical	linux-cuda
MaskablePPO/lunar-lander	generated-matrix:product-row-MaskablePPO.lunar-lander	integration.product.MaskablePPO.lunar-lander	e2e.product.MaskablePPO.lunar-lander	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:policy-mlp-update-critical	linux-cuda
MaskablePPO/key-door-grid	generated-matrix:product-row-MaskablePPO.key-door-grid	integration.product.MaskablePPO.key-door-grid	e2e.product.MaskablePPO.key-door-grid	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:policy-mlp-update-critical	linux-cuda
RecurrentPPO/cartpole	generated-matrix:product-row-RecurrentPPO.cartpole	integration.product.RecurrentPPO.cartpole	e2e.product.RecurrentPPO.cartpole	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:policy-mlp-update-critical	linux-cuda
RecurrentPPO/mountain-car	generated-matrix:product-row-RecurrentPPO.mountain-car	integration.product.RecurrentPPO.mountain-car	e2e.product.RecurrentPPO.mountain-car	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:policy-mlp-update-critical	linux-cuda
RecurrentPPO/lunar-lander	generated-matrix:product-row-RecurrentPPO.lunar-lander	integration.product.RecurrentPPO.lunar-lander	e2e.product.RecurrentPPO.lunar-lander	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:policy-mlp-update-critical	linux-cuda
RecurrentPPO/key-door-grid	generated-matrix:product-row-RecurrentPPO.key-door-grid	integration.product.RecurrentPPO.key-door-grid	e2e.product.RecurrentPPO.key-door-grid	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:policy-mlp-update-critical	linux-cuda
DQN/cartpole	generated-matrix:product-row-DQN.cartpole	integration.product.DQN.cartpole	e2e.product.DQN.cartpole	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:policy-mlp-update-critical	linux-cuda
DQN/mountain-car	generated-matrix:product-row-DQN.mountain-car	integration.product.DQN.mountain-car	e2e.product.DQN.mountain-car	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:policy-mlp-update-critical	linux-cuda
DQN/key-door-grid	generated-matrix:product-row-DQN.key-door-grid	integration.product.DQN.key-door-grid	e2e.product.DQN.key-door-grid	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:policy-mlp-update-critical	linux-cuda
QR-DQN/cartpole	generated-matrix:product-row-QR-DQN.cartpole	integration.product.QR-DQN.cartpole	e2e.product.QR-DQN.cartpole	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:policy-mlp-update-critical	linux-cuda
QR-DQN/mountain-car	generated-matrix:product-row-QR-DQN.mountain-car	integration.product.QR-DQN.mountain-car	e2e.product.QR-DQN.mountain-car	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:policy-mlp-update-critical	linux-cuda
QR-DQN/key-door-grid	generated-matrix:product-row-QR-DQN.key-door-grid	integration.product.QR-DQN.key-door-grid	e2e.product.QR-DQN.key-door-grid	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:policy-mlp-update-critical	linux-cuda
DDPG/lunar-lander	generated-matrix:product-row-DDPG.lunar-lander	integration.product.DDPG.lunar-lander	e2e.product.DDPG.lunar-lander	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:policy-mlp-update-critical	linux-cuda
TD3/lunar-lander	generated-matrix:product-row-TD3.lunar-lander	integration.product.TD3.lunar-lander	e2e.product.TD3.lunar-lander	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:policy-mlp-update-critical	linux-cuda
SAC/lunar-lander	generated-matrix:product-row-SAC.lunar-lander	integration.product.SAC.lunar-lander	e2e.product.SAC.lunar-lander	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:policy-mlp-update-critical	linux-cuda
SAC/pendulum	generated-matrix:product-row-SAC.pendulum	integration.product.SAC.pendulum	e2e.product.SAC.pendulum	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:policy-mlp-update-critical	linux-cuda
CrossQ/lunar-lander	generated-matrix:product-row-CrossQ.lunar-lander	integration.product.CrossQ.lunar-lander	e2e.product.CrossQ.lunar-lander	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:policy-mlp-update-critical	linux-cuda
TQC/lunar-lander	generated-matrix:product-row-TQC.lunar-lander	integration.product.TQC.lunar-lander	e2e.product.TQC.lunar-lander	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:policy-mlp-update-critical	linux-cuda
ARS/cartpole	generated-matrix:product-row-ARS.cartpole	integration.product.ARS.cartpole	e2e.product.ARS.cartpole	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:policy-mlp-update-critical	linux-cuda
ARS/mountain-car	generated-matrix:product-row-ARS.mountain-car	integration.product.ARS.mountain-car	e2e.product.ARS.mountain-car	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:policy-mlp-update-critical	linux-cuda
ARS/lunar-lander	generated-matrix:product-row-ARS.lunar-lander	integration.product.ARS.lunar-lander	e2e.product.ARS.lunar-lander	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:policy-mlp-update-critical	linux-cuda
ARS/key-door-grid	generated-matrix:product-row-ARS.key-door-grid	integration.product.ARS.key-door-grid	e2e.product.ARS.key-door-grid	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:policy-mlp-update-critical	linux-cuda
HER/goal-reaching	generated-matrix:product-row-HER.goal-reaching	integration.product.HER.goal-reaching	e2e.product.HER.goal-reaching	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:goal-policy-mlp-update-critical	linux-cuda
connect4	generated-matrix:product-row-connect4	integration.product.connect4	e2e.product.connect4	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:policy-value-mlp-update-critical	linux-cuda
othello	generated-matrix:product-row-othello	integration.product.othello	e2e.product.othello	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:policy-value-mlp-update-critical	linux-cuda
hex	generated-matrix:product-row-hex	integration.product.hex	e2e.product.hex	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:policy-value-mlp-update-critical	linux-cuda
gomoku	generated-matrix:product-row-gomoku	integration.product.gomoku	e2e.product.gomoku	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:policy-value-mlp-update-critical	linux-cuda
hyperparameter-tuning	generated-matrix:product-row-hyperparameter-tuning	integration.product.hyperparameter-tuning	e2e.product.hyperparameter-tuning	checkpoint-required-fail-closed	device:linux-cuda:cuBLAS-cuDNN:ffi:dispatch:tuning-promoted-mlp-update-critical	linux-cuda
tic-tac-toe	non-product: unit-level minimax anchor documented outside the product matrix	not-required	not-required	not-required	not-required	not-required
atari-subset	non-product: optional ROM-backed runtime support, not a required product row	not-required	not-required	not-required	not-required	not-required
```

## Historical Sprint 15.22 HA validation gate

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

## Historical Sprint 15.22 defects closed in this fragment

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

## Historical Sprint 15 browser product matrix — `15/15` via live Playwright

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
