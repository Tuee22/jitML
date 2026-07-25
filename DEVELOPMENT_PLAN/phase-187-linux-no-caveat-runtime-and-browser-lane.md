# Phase 187: Linux No-Caveat Runtime and Browser Lane

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Linux No-Caveat Runtime and Browser Lane. Single-session phase migrated from legacy Sprint 15.20 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 187.1: Linux No-Caveat Runtime and Browser Lane [✅ Done]

**Status**: Done (closed 2026-06-18 on the NVIDIA GeForce RTX 5090 host, UUID
`GPU-e764ef97-32d7-4981-c348-029983c64073`, CUDA 12.8)
**Implementation**: `bootstrap/linux-cpu.sh`, `bootstrap/linux-cuda.sh`,
`src/JitML/Test/WorkflowMatrix.hs`, `playwright/jitml-demo.spec.ts`,
`chart/local/jitml-demo/templates/deployment.yaml` (linux-cuda demo GPU +
JIT-compile memory budget), `src/JitML/App.hs`
(`measureBrowserProductMatrix` live probe), `test/unit/Main.hs`
(command-registry golden)
**Docs to update**: `documents/engineering/training_workloads.md`,
`documents/engineering/purescript_frontend.md`, `system-components.md`

### Objective

Validate the full no-caveat product on real Linux CPU and Linux CUDA lanes.

### Deliverables

- `linux-cpu` and `linux-cuda` bootstrap clean clusters, run every no-caveat
  SL/RL/AlphaZero/tuning workflow, persist/reload checkpoints, serve the demo,
  and pass the full Playwright product matrix.
- CUDA worker Jobs use the NVIDIA runtime class and attached GPU for every
  substrate-backed cell that requires `linux-cuda`.
- The lane fails fast on missing datasets, missing checkpoints, missing live
  event frames, placeholder browser data, synthetic report-card rows, failed
  Kubernetes Jobs, or absent Playwright product assertions.
- This sprint **owns and commits the `linux-cuda` per-lane report-card fragment**
  (within-substrate reproducibility + measured no-caveat rows) produced on the
  NVIDIA host. The Phase `17` aggregation (Sprint `17.8`) and the Phase `18`
  handoff consume this committed fragment on `linux-cpu`; they never re-run the
  `linux-cuda` lane (standards rule M(b)/(d)).

### Validation

- `docker compose run --rm jitml jitml test all --linux-cpu`
- `docker compose run --rm jitml-cuda jitml test all --linux-cuda`
- `docker compose run --rm jitml-cuda jitml test jitml-e2e --linux-cuda`
- `docker compose run --rm jitml jitml docs check`
- `docker compose run --rm jitml jitml check-code`

### Validation State (2026-06-18, RTX 5090 host)

Both lanes closed on a single NVIDIA host (which also provides `linux-cpu`),
satisfying standards rule M's single-accelerator-per-phase invariant.

- **`linux-cpu` lane.** Live `jitml bootstrap --linux-cpu` cluster (edge `9091`);
  all 12 canonical dataset blobs staged + SHA-verified into live MinIO;
  `jitml test all --linux-cpu` **8/8 stanzas** — `jitml-unit` 197/197 (after the
  stale registry-golden fix), `jitml-integration` live group, `jitml-sl-canonicals`
  24/24 (live MNIST convergence `267.7s`, all-row materialize `29.8s`),
  `jitml-rl-canonicals`, `jitml-hyperparameter`, `jitml-daemon-lifecycle`,
  `jitml-e2e` 23/23, `jitml-backends` (oneDNN).
- **`linux-cuda` lane.** Live `jitml bootstrap --linux-cuda` cluster (edge `9092`,
  GPU-attached `jitml-service` + `jitml-demo`); `jitml test all --linux-cuda`
  **8/8 stanzas** including `jitml-backends` **20/20** with the real cuBLAS/cuDNN
  bindings compiled and executed on the RTX 5090; `jitml test jitml-e2e
  --linux-cuda` **23/23**. The live report card measured every runtime row
  (`sl_final_loss=mnist-shallow-mlp 0.65`, `rl_final_reward=ppo/cartpole 131.2`,
  `alphazero_arena_win_rate=connect4/gen0 0.75`, `tune_best_objective=TPE 1.0`,
  `jit_cache_hit_rate=1.0`, `daemon_healthz=200`).
- **Browser product matrix `11/11` on the `linux-cuda` edge.** The five
  checkpoint-backed panels (MNIST inference, generic inference, CIFAR upload,
  checkpoint compare, Connect-4 move) initially failed `503 runtime unavailable:
  libcuda=no` under the older checkpoint-runtime Webapp shape because the
  `jitml-demo` pod had no GPU on `linux-cuda` and its 256Mi limit could not support
  that path. Fixed in `chart/local/jitml-demo/templates/deployment.yaml` (adds
  `runtimeClassName: nvidia`, the NVIDIA env, and a 4Gi/2-CPU budget on
  `linux-cuda`); after
  `jitml internal seed-demo-checkpoints`, all five panels serve real
  checkpoint-backed results and the live Playwright spec passes **11/11**.
- **Current role-boundary supersession (Sprint `12.16`).** The Webapp no longer
  executes checkpoint inference in-process: it publishes through Pulsar to the
  CUDA Engine. The historical Webapp GPU workaround above is therefore removed
  from the current chart; `jitml-demo` requests no NVIDIA RuntimeClass/device
  environment or Kubernetes API token, while the CUDA Engine and worker Jobs
  retain the lane's real GPU attachment.
- **Real defects fixed (all in the worktree):** the `jitml-unit` registry golden
  (`test/unit/Main.hs`), the demo `linux-cuda` GPU/memory gap (chart), and the
  `measureBrowserProductMatrix` report-card stub (now a live endpoint probe in
  `src/JitML/App.hs`).
- **Environmental notes (non-product, shared host):** Apache BookKeeper went
  read-only under co-tenant disk pressure — the bookie `diskUsageThreshold` was
  raised on the jitML clusters only — and a co-tenant disk-full event was ridden
  out. Neither is a jitML defect.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
