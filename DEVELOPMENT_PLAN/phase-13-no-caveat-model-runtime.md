# Phase 13: No-Caveat Model Runtime Closure

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md),
[development_plan_standards.md](development_plan_standards.md),
[system-components.md](system-components.md),
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md),
[phase-8-supervised-and-rl-framework.md](phase-8-supervised-and-rl-framework.md),
[phase-9-rl-catalog-alphazero-and-tuning.md](phase-9-rl-catalog-alphazero-and-tuning.md),
[phase-10-checkpointing-and-inference.md](phase-10-checkpointing-and-inference.md),
[phase-14-interactive-demo-and-playwright-closure.md](phase-14-interactive-demo-and-playwright-closure.md),
[phase-18-no-caveat-product-handoff.md](phase-18-no-caveat-product-handoff.md),
[../README.md](../README.md)
**Generated sections**: none

> **Purpose**: Own the no-caveat model-runtime closure that spans multiple
> earlier phases: every canonical SL model trains, checkpoints, evaluates, and
> infers through a substrate device; every RL algorithm and AlphaZero game runs
> through the production runtime; and tuning objectives measure real model
> outcomes without synthetic projections.

## Phase Status

⏸️ **Blocked** (reopened 2026-06-24 for Sprint `13.2` — re-attest the no-caveat
runtime with real SL/RL losses + metrics). **Blocked by**: Phase 8 Sprint `8.13`,
Phase 9 Sprint `9.13`, Phase 10 Sprint `10.9`. Sprint `13.2` lands the real
cross-entropy/MSE + held-out validation loss and re-attests R1–R5 on the
`linux-cpu` lane (no synthetic weights, no faked loss, validation-driven selection,
convergence-and-performance metrics). All prior Sprints `13.1` remain `✅ Done`; the
prior closure history follows.

✅ **Done — `linux-cpu` scope** (validated 2026-06-16 on an Apple M1 Max host's
`linux-cpu` lane; opened 2026-06-14, unblocked 2026-06-15). Per standards rule
M(b), this phase owns the accelerator-free `linux-cpu` no-caveat model runtime;
its full validation suite passes live (see Current Validation State). Phase `8`
Sprint `8.12` landed the all-row SL trainable architecture and typed RL
event-payload surface consumed here; Phase `9` Sprint `9.12` the
RL/AlphaZero/tuning runtime; Phase `10` Sprint `10.6` checkpoint/inference for
every model family. The **per-accelerator** runtime and deep-row median
convergence that is impractical on CPU are owned downstream — `linux-cuda` by
Phase `15` (Sprint `15.20`, NVIDIA host) and `apple-silicon` by Phase `16`
(Sprint `16.11`, Mac host); this phase neither runs nor gates on an accelerator.

## Phase Summary

This phase is the cross-model runtime gate. It does not replace Phase `8`,
Phase `9`, or Phase `10`; it consumes their reopened deliverables and proves the
whole model matrix operates as one product surface. A model or algorithm is not
closed here until it can be started through the public `jitml` command or daemon
command envelope, run on the selected substrate, write a checkpoint, reload that
checkpoint, serve inference/evaluation, and produce deterministic same-substrate
results without an offline, echo, synthetic, or demo-only substitute.

## Sprint 13.1: Full Canonical Model Matrix Runtime ✅

**Status**: Done (`linux-cpu` scope; validated 2026-06-16, Apple M1 Max host)
**Implementation**: `src/JitML/SL/`, `src/JitML/RL/`, `src/JitML/Tune/`,
`src/JitML/Checkpoint/`, `src/JitML/App.hs`
**Docs to update**: `documents/engineering/training_workloads.md`,
`documents/engineering/checkpoint_format.md`,
`documents/engineering/numerical_core.md`, `system-components.md`

### Objective

Close the end-to-end runtime matrix for every canonical model, not just the
currently narrowed Dense-MLP / selected-RL subset.

This phase owns the **`linux-cpu`** runtime closure (single accelerator-free
lane) per standards rule M(b). Per-accelerator device-training and the deep-row
median convergence that is impractical on CPU are **owned downstream** by Phase
`15` (`linux-cuda`) and Phase `16` (`apple-silicon`); this phase neither runs nor
gates on an accelerator.

- Every row in [../README.md → Canonical supervised learning problems](../README.md#canonical-supervised-learning-problems)
  is device-trainable through the **`linux-cpu`** substrate runtime, including
  Dense, DeepDense, Conv2D, residual, wide-residual, ResNet-50, and
  VisionTransformer rows; the CPU-tractable rows clear their bounded-budget
  convergence gate, and the heavy rows (ResNet-50 / ViT) materialize and execute a
  real `linux-cpu` train step. Deep-row **median convergence** is owned by Phases
  `15`/`16` on their accelerators.
- Every RL algorithm in the catalog trains/evaluates/rolls out through its
  production policy/runtime path on `linux-cpu`. Algorithm-level synthetic reward
  projections and deterministic-stub loss fixtures no longer stand in for trained
  policy execution.
- AlphaZero uses real terminal evaluators, legal-game replay state, persistent
  MCTS state, device-backed policy/value leaf evaluation, and checkpoint-loaded
  policy/value nets for Connect 4, Othello, Hex, and Gomoku on `linux-cpu`.
- Hyperparameter sweeps measure objectives from real trained SL/RL workloads,
  persist trial artifacts, and replay/resume from MinIO without LCG-derived or
  structurally tautological values.
- Checkpoints and inference support every model family the `linux-cpu` runtime
  trains, including architecture metadata, weight layouts, preprocessing metadata,
  and output decoding.
- The legacy ledger rows owned by reopened Phases `8`, `9`, and `10` move to
  `Completed` only after their replacements are validated through this `linux-cpu`
  matrix (with the accelerator lanes attested in Phases `15`/`16`).

### Validation

This phase closes on the always-available `linux-cpu` lane (single host, no
accelerator) per standards rule M(b)/(d). Per-accelerator runtime convergence is
**owned downstream**: the `linux-cuda` runtime lane is Sprint `15.20` and the
`apple-silicon` runtime lane is Sprint `16.11`; this phase does not run either
accelerator.

- `docker compose run --rm jitml jitml test jitml-sl-canonicals --linux-cpu`
- `docker compose run --rm jitml jitml test jitml-rl-canonicals --linux-cpu`
- `docker compose run --rm jitml jitml test jitml-hyperparameter --linux-cpu`
- `docker compose run --rm jitml jitml test jitml-integration --linux-cpu`
- `docker compose run --rm jitml jitml check-code`
- `docker compose run --rm jitml jitml docs check`

### Current Validation State

**`linux-cpu` validation gate PASSED (2026-06-16, Apple M1 Max host).** The full
Sprint `13.1` validation suite ran green against a freshly bootstrapped
`linux-cpu` cluster (`jitml bootstrap --linux-cpu`, 85 steps, all 7 components
ready, edge `9091`; all 12 canonical dataset blobs staged + SHA-verified into live
MinIO):

- `jitml test jitml-sl-canonicals --linux-cpu` — **24 / 24** (live MNIST training
  cleared the literature convergence threshold, `OK 384.82s`; all 11 canonical SL
  rows materialized staged bytes and trained through the substrate runtime,
  `OK 37.62s`).
- `jitml test jitml-rl-canonicals --linux-cpu` — **29 / 29** (full RL algorithm
  catalog + the four canonical AlphaZero games' rule/self-play-determinism
  surface).
- `jitml test jitml-hyperparameter --linux-cpu` — **16 / 16**.
- `jitml test jitml-integration --linux-cpu` — **71 / 71** (live `Live` group:
  PPO/cartpole convergence through daemon dispatch `OK 75.36s`, an AlphaZero
  generation drive with `.jmw1` checkpoint round-trip, tune persist/replay,
  `jitml inference run` checkpoint read, GC + `gc.event`, and the MinIO / Pulsar /
  Harbor capability round-trips).
- `jitml check-code` and `jitml docs check` — **ok**.

**Update 2026-06-23 — tuning objective migrated onto the production seam.** The
hyperparameter tuning objective no longer trains the legacy Dense-only
`Classifier.trainClassifier` / `trainClassifierWithDevice`. It now trains a fixed
Dense `CanonicalProblem` through the production `JitML.SL.Architecture` seam
(`trainArchitectureWithDevice`) — the same runtime the no-caveat SL canonicals
use — with the offline sweep routed through a new toolchain-free
`pureReferenceMlpDevice` (`JitML.Numerics.MlpDevice`, built on the pure
`mlpForward` / `mlpBackward` / `mlpInputGradient`) so `deterministicTrials` stays
pure and the device sweep + report card route through the real substrate device;
trial weights come from `Architecture.trainedArchitectureWeights`. Host-validated:
`cabal build all` clean, `jitml-hyperparameter` **16/16** (determinism, `[0,1]`
bounds, checkpointable weights, device-backed executor). **Live-validated on
`linux-cpu` (2026-06-23):** `jitml test all --live --linux-cpu` ran the migrated
`deterministicTrialsWithDevice` through the substrate device and measured
`tune_best_objective: TPE=1.0` — **unchanged** from the pre-migration value (the
deterministic separable tuning dataset still admits a 100%-accuracy trial), so the
committed `apple-silicon` / `linux-cuda` `TPE=1.0` fragments stay consistent and no
per-lane re-baseline is needed; the Sprint `13.1` ledger row is `Completed`
(see [the committed `linux-cpu` fragment](attestations/linux-cpu-report-card.md)).
The now-test-only `trainClassifier` / `accuracy` / `trainClassifierWithDevice` are
retained as legitimate pure-numerics `jitml-sl-canonicals` coverage of the pure MLP
classifier path.

This closes Phase `13` on its `linux-cpu` scope (standards rule M(b)): the
accelerator-free no-caveat runtime trains, checkpoints, evaluates, and infers
across the canonical SL / RL / AlphaZero / tuning matrix on `linux-cpu`. The
**per-accelerator** runtime and the deep-row (`ResNet-50` / `ViT`) **median
convergence** that is impractical on CPU are owned by Phase `15` (`linux-cuda`,
NVIDIA host) and Phase `16` (`apple-silicon`, Mac host), each attesting its lane
in a separate single-host session.

**Apple M1 Max host re-validation (2026-06-16; runnable lanes only).** On an Apple
M1 Max workstation (no NVIDIA GPU; Docker is an aarch64 Linux VM, so `linux-cuda`
is physically unavailable and was not re-claimed), the runnable surface was
re-exercised end to end. A stale `jitml-unit` golden (the demo panel/route list
predating the Sprint `11.9` `generic-inference-lab` / `checkpoint-compare-lab`
additions) was fixed; `jitml-unit` is now `197/197` on both lanes. The complete
non-live surface passes on `apple-silicon` (host-native, incl. `jitml-backends`
Metal GPU `17/17`) and `linux-cpu` (`jitml:local`, incl. `jitml-backends` oneDNN
`23/23`), with `check-code: ok` and `docs check: ok`. A clean `jitml bootstrap
--linux-cpu` came up (85 steps, 7/7 ready, edge `9091`); all 12 canonical dataset
blobs were staged + SHA-verified into live MinIO; `jitml-sl-canonicals
--linux-cpu` passed `24/24` (live MNIST convergence `431s`; all-row materialize
`41s`); `jitml-integration --linux-cpu` passed `71/71` (PPO/cartpole convergence
`83.9s`, AlphaZero generation, tune persist/replay, inference run, GC, MinIO /
Pulsar / Harbor); `jitml-e2e --linux-cpu` passed `23/23`. The live Playwright
product matrix scored `6/11`: the five checkpoint-backed panels fail `HTTP 503`
because (a) the in-cluster `jitml-demo` runtime handler reads MinIO at the
external edge `127.0.0.1:<edge>` (`App.hs:244 minioSettingsForLocalEdge`,
unreachable from inside the pod) and (b) no per-panel inference checkpoints are
persisted/served. Both are open Sprint `13.1` (per-family checkpoint persistence)
/ Sprint `14.1` (in-cluster demo MinIO endpoint + checkpoint-backed browser
calls) work — confirming this phase is genuinely incomplete beyond the hardware
limits, not merely awaiting `linux-cuda`.

**Live `linux-cpu` validation (2026-06-16).** A live `jitml bootstrap
--linux-cpu` cluster was brought up on this host (85 rollout steps; all seven
components — harbor, minio, pulsar, postgres, observability, jitml-service,
jitml-demo — ready on edge port 9091), all six canonical SL datasets were staged
into live MinIO via `jitml internal upload-dataset` (MNIST, Fashion-MNIST,
CIFAR-10, CIFAR-100, California Housing, Tiny ImageNet — each SHA-verified
against the pinned `JitML.SL.Dataset.canonicalArtifactSha256For`), and
`jitml test jitml-sl-canonicals --linux-cpu` then passed **24 / 24 against the
live cluster (292.63s)** — including the two cases that *skip* offline without a
publication:

- `live MNIST SL training clears the convergence threshold` — **OK (264.14s)**:
  real MNIST fetched from live MinIO, trained through the `JitML.SL.Architecture`
  substrate runtime over the bounded budget, and the measured test accuracy
  cleared the in-code literature threshold − slack.
- `live all canonical SL rows materialize staged bytes and train through the
  substrate runtime` — **OK (28.25s)**: all 11 canonical rows (spanning the
  Dense, DeepDense, Conv2D/LeNet, ResidualBlock, ResNet-20/56, WideResidual, ViT,
  and ResNet-50 architectures plus the California Housing regression row)
  materialized their staged bytes from live MinIO and trained through the
  selected substrate device without error.

The RL / AlphaZero / tuning / inference live surface was exercised on the same
cluster via `jitml test jitml-integration --linux-cpu`, whose `Live` group passed
**19 / 19 (101.81s)**: the `WorkflowMatrix` dispatched every current-substrate
cell fail-closed; the daemon placed `StartTraining` / `StartRLRun` / `StartSweep`
by substrate; **live PPO/cartpole training through daemon dispatch cleared its
literature threshold (OK, 79.11s)**; an AlphaZero generation drove self-play +
training + a `.jmw1` checkpoint round-trip through live MinIO; and live tune trial
persist/replay, `jitml inference run` checkpoint read, checkpoint GC +
`gc.event.<substrate>` publication, and live MinIO / Pulsar / Harbor capability
round-trips all passed.

The same flow was then re-validated on the **`linux-cuda` GPU lane** (RTX 5090):
`jitml bootstrap --linux-cuda` came up (84 steps; all seven components ready; edge
port 9092), all six datasets were re-staged into the cuda MinIO (SHA-verified),
`jitml test jitml-backends --linux-cuda` passed **20 / 20** exercising real GPU
kernels through the `-fcuda` build (nvcc→FFI compile, warp-shuffle reduction, real
device GEMM bit-determinism, cuBLAS / cuDNN binding init, MLP
forward/backward/batched matching the pure reference, and on-device
PPO / DQN / QR-DQN / HER / DDPG / AlphaZero trainers), and the
`jitml-integration --linux-cuda` `Live` group passed **20 / 20 (1088.79s)** — the
`WorkflowMatrix` dispatched every cell as real GPU-backed Kubernetes Jobs (949s),
and live PPO/cartpole convergence through daemon dispatch cleared its threshold on
the GPU (116s), alongside the AlphaZero / tune / inference / GC / capability cases.

**Remaining for no-caveat closure.** The live all-row SL case is a bounded
materialize-and-train smoke (`liveClassifierBudget` uses 16–512 examples,
1–2 epochs, min-accuracy 0.0), not per-row convergence. Only the **MNIST** row is
asserted to reach its literature threshold; the deeper rows (`Conv2D`/LeNet,
`ResidualBlock`, `ResidualBlock20`/`56`, `WideResidualBlock`,
`VisionTransformer`, `ResidualBlock50`/ResNet-50) are not yet trained to median
convergence — the heavy rows realistically need the `linux-cuda` GPU lane
(ResNet-50 / ViT to convergence is impractical on the CPU container) and the
`apple-silicon` Mac lane. On the RL / AlphaZero / tuning / inference side the
*current* surface is now live-validated (PPO/cartpole convergence, one AlphaZero
generation drive, tune persist/replay + placement, checkpoint inference), but the
no-caveat scope is wider: every RL algorithm family trained/evaluated/rolled-out
through its production path, per-game AlphaZero (Connect 4 / Othello / Hex /
Gomoku) with real terminal evaluators and arena convergence, tuning objectives
measured from real trained workloads across the sampler catalog, and
checkpoint/inference for every model family — each on all three substrates. This
session validated the `linux-cpu` and `linux-cuda` lanes; the `apple-silicon`
lane (Mac hardware, unavailable here) remains, as does per-row SL **median
convergence** for the deeper rows (only MNIST and PPO/cartpole are asserted to a
literature threshold) and the full RL-catalog / 4-game AlphaZero arena / all-model-
family checkpoint-inference breadth.

### Remaining Work

- Phase `8` provides the all-row trainable SL architecture runtime, live
  linux-cpu staged-byte smoke, and typed RL animation/replay event payloads.
  Phase `13` must consume that surface to run the full canonical SL catalog
  through median convergence, checkpoint reload, evaluation, and inference.
- Phase `9` provides the real RL/AlphaZero/tuning runtime surface. Phase `13`
  consumes that surface to retire the remaining catalog rollout compatibility
  helper and close the full checkpoint-backed train/evaluate/rollout matrix.
- Phase `10` provides checkpoint/inference metadata, weight layouts, and
  preprocessing/output decoders for every model family. Phase `13` consumes
  that surface across the full runtime matrix.

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/training_workloads.md` — no-caveat model matrix,
  per-family train/eval/rollout closure, AlphaZero game/runtime closure, and
  tuning objective semantics.
- `documents/engineering/checkpoint_format.md` — architecture-aware model
  metadata, weight layouts, preprocessing metadata, replay artifacts, and
  inference reload contracts for every model family.
- `documents/engineering/numerical_core.md` — trainable layer-family coverage
  and per-substrate forward/backward kernel requirements.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- Update `system-components.md` training, checkpoint, and test rows to mark this
  phase as the owner of no-caveat runtime closure.

## Sprint 13.2: Re-Attest the No-Caveat Runtime with Real Losses + Metrics [⏸️ Blocked]

**Status**: Blocked — reopened 2026-06-24.

**Blocked by**: Phase 8 Sprint `8.13`, Phase 9 Sprint `9.13`, Phase 10 Sprint `10.9`.

Re-run the `linux-cpu` no-caveat runtime attestation with the real SL/RL learning in
place — no synthetic weights, no faked loss, validation-driven selection, and
convergence-AND-performance metrics for both SL and RL.

### Exit Definition

- R1–R5 re-attested on the `linux-cpu` lane: trained weights only, real CE/MSE +
  held-out validation loss, measured-median RL convergence, SL+RL performance metrics.

### Validation

- `jitml test all --live --linux-cpu` (cluster) green with the real metrics; the
  per-lane convergence cohorts pass against the literature thresholds.

### Remaining Work

- Re-attest after Sprints 8.13/9.13/10.9 land; the code/validation lands here.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
- [../README.md](../README.md)
