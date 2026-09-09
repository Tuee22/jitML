# Phase 268: Contract-Driven CUDA Lane Revalidation

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Contract-Driven CUDA Lane Revalidation. Single-session phase migrated from legacy Sprint 29.5 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

⏸️ **Blocked** (2026-09-09 prerequisite check under standards rule `C`). A Linux
host with an NVIDIA GPU and the NVIDIA container runtime is required; the current
Darwin arm64 / Colima host exposes no NVIDIA runtime. Phase `261` has re-closed
with the durable typed lane-journal projection and the exact `linux-cpu` journal
retained. This phase is the first open owner and must issue the equivalent
digest-pinned artifact from the real `linux-cuda` lifecycle. The historical CUDA
execution remains valid for its device/runtime surface, but its transient
authenticated journal cannot be consumed by Phase `276`. Later open phases stay
Blocked until this lifecycle passes and its exact evidence is retained.

### Historical Phase State

✅ **Done** (2026-08-24). The committed `linux-cuda` lane fragment is replaced
with journal-derived evidence and the standing drift gate accepts it:
`jitml test all --linux-cuda` exits `0` with `jitml-integration` **197 / 197**,
including `Phase 263 issues the committed lane fragment from the completed
scenario journal`. Every product cell in that table is derived from the opaque
`CompletedProductScenarioReport` rather than from a declared substrate and claim,
and its `DeviceEvidence` column was byte-identical across two independent
full-lane runs (2026-08-19 and 2026-08-22) — Phase
[78](phase-78-kernelspec-cache-key-inputs-ffi-loader-surface.md)'s artifact
reproducibility showing up as a stable identity rather than a per-compile nonce.

Both blockers this phase carried are discharged. Sprint `266.1` produced the
row-complete lane run the fragment is issued from, and Sprint `267.1` recorded
the per-row timing table it carries, so
[Exit Definition](README.md#exit-definition) item `29` is **met** — every one of
the 55 rows strictly faster on `linux-cuda`, no per-row exemptions. The
2026-08-12 `PPO/mountain-car` failure is also gone: the measured publisher run
reports `rows: 55`, `eligible: 55`, `unsupported: 0`, `errors: 0`, and because
the publisher turns a missed cohort bar into an `error`, `errors: 0` is those
bars being met rather than unchecked. The shared `cohortThresholds` table was not
modified.

The lifecycle obligation is discharged. On 2026-08-24 the sequence ran as the
validation block names it, against a cluster built from nothing: `up` exited `0`
in 112 steps with 21 pods ready, `test` passed the full lane (`jitml test all
--linux-cuda` exit `0`, **10 / 10** stanzas, `jitml-integration` **197 / 197**;
`jitml test jitml-e2e --live --linux-cuda` exit `0` with Playwright **PASS**),
and `down` exited `0`, deleting both Kind nodes while preserving `.data` as the
`down`-preserves-state contract requires. That run was shared with Phase
[269](phase-269-registry2-migration-and-harbor-deprecation.md), which replaced
Harbor with `registry:2` and needed the same from-nothing bootstrap, so the
cluster was torn down and rebuilt once rather than twice.

One observation from that teardown, recorded rather than acted on because it
predates this sprint and belongs to no obligation it owns: `down` preserves
`.data` as contracted but leaves `./.build/runtime/cluster-publication.json` in
place, still naming the edge of a cluster that no longer exists. Four
`jitml-unit` cases that mirror to live MinIO then fail with connection refused
against a dead edge; they pass either with the cluster up or with that file
absent. The publication is stale state after a teardown, not a live coordinate.

### Historical Phase State

> ⏸️ **Blocked** by Sprint `267.1`. This sprint replaces the committed `linux-cuda`
lane fragment, which it can only do from a completed row-complete scenario
journal plus the per-row timing table those two upstream sprints produce.
> Its two structural preconditions are now met. Sprints `229.1`, `264.1`, and
`265.1` landed the CUDA lowering and the execution witness, so the lane no longer
attests kernels it does not run; and Phase
[78](phase-78-kernelspec-cache-key-inputs-ffi-loader-surface.md) made `nvcc`
output byte-reproducible, so the artifact digests this fragment pins are
identities rather than per-compile nonces.

> ⏸️ **Blocked**. Blocked by Phase 263 (Sprint 263.1), which reopened on 2026-08-12
because the committed lane fragment's device-evidence column is derived from the
declared substrate and claim rather than from what executed. This lane's
revalidation cannot be meaningful while supervised rows on it execute oneDNN
kernels, so the CUDA lowering in Sprint `264.1` and the witness in Sprint `229.1`
land first.

## Sprint 268.1: Contract-Driven CUDA Lane Revalidation [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: External prerequisite — a Linux NVIDIA host whose Docker daemon
exposes a real GPU through the NVIDIA container runtime to the `jitml-cuda` service.
**Implementation**: `src/JitML/Test/RunContract.hs`,
`src/JitML/Test/Report.hs`, `test/integration/Main.hs`,
`DEVELOPMENT_PLAN/attestations/linux-cuda-report-card.md`
**Docs to update**: `../README.md`,
`../documents/engineering/product_completion_contract.md`,
`../documents/engineering/unit_testing_policy.md`,
`../documents/engineering/run_contract.md`, `system-components.md`

### Objective

Revalidate the full row-complete workflow contract on a real `linux-cuda` host
and replace the lane fragment with journal-derived evidence. This sprint owns
the CUDA-lane portions of [Exit Definition](README.md#exit-definition) items
`31`, `32`, and `34` while preserving the existing item `29` performance bar.
The binding design is
[README.md → Typed run contracts](../README.md#typed-run-contracts).

### Deliverables

- Run every supported CUDA product scenario through the same validated plan,
  receipt-bound consumer, exact evidence reducer, and scoped lifecycle used by
  the `linux-cpu` lane.
- Prove each completed row journal carries the CUDA substrate/device witness,
  exact terminal evidence, trained artifact hash, and measured inference result.
- Re-run the existing backend, publisher, integration, e2e, negative-control,
  model-convergence, and every-row CUDA-vs-CPU performance gates on the real GPU.
- Replace the committed `linux-cuda` fragment only after all scenarios complete;
  retain explicit failed/not-run entries rather than fabricating pass cells.
- Record cleanup and diagnostic evidence for the full bootstrap/test/down
  lifecycle without requiring Apple Silicon in this phase.

### Validation

```bash
./bootstrap/linux-cuda.sh up
./bootstrap/linux-cuda.sh test
./bootstrap/linux-cuda.sh down
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Historical Validation

2026-08-22 evidence on the source at that checkpoint, gathered against a running
`linux-cuda` cluster. Its bootstrap lifecycle subsequently passed on 2026-08-24;
neither run retained the typed journal required by the 2026-09-08 reopening:

| Gate | Result |
|---|---|
| `jitml test all --linux-cuda` | exit `0` — `jitml-integration` **197 / 197**, including the standing committed-fragment drift case; **10 / 10** stanzas |
| `jitml test jitml-e2e --live --linux-cuda` | exit `0` — `jitml-integration` **197 / 197**, Haskell e2e **30 / 30**, `jitml-e2e-playwright` **PASS** |
| `jitml internal train-and-publish-product-rows --linux-cuda` | `rows: 55`, `eligible: 55`, `unsupported: 0`, `errors: 0` |
| `jitml internal benchmark-product-row-wall-clock` | **PASS**, `rows=55` — item `29` met |
| `jitml docs check` / `jitml check-code` | PASS / PASS |

The fragment's `DeviceEvidence` column resolved to two witnesses across the 55
rows — `device:linux-cuda:cuda:mlp-forward-backward-tanh-linear:bfdeb1d4e39cf268`
for 45 rows and
`device:linux-cuda:linux-cuda-cudnn:cublas_sgemm_forward:06afb721b891e7c7` for 10
— and both were byte-identical to the values the 2026-08-19 run issued. The two
non-product rows (`tic-tac-toe`, `atari-subset`) remain declared literals, which
is what `renderProductLaneAttestationFragment` emits for rows that carry no
scenario evidence by construction.

### Current Validation State

- On 2026-09-09, `./bootstrap/linux-cuda.sh up` exited `2` at the stage-0
  prerequisite gate with `NVIDIA container runtime is not registered with Docker;
  install and configure nvidia-container-toolkit`.
- The host reports `Darwin arm64`; the active Docker context is `colima`, its
  daemon reports `linux aarch64`, and its registered runtimes are `runc` and
  `io.containerd.runc.v2`. No NVIDIA runtime is registered. Bootstrap stopped
  before image preparation or cluster creation; the lane tests and teardown were
  not run. No new CUDA completion evidence was produced.
- Numerical-order execution remains at this phase. A CUDA-host session with the
  required hardware/runtime must execute the prescribed lifecycle before Phase
  `273` can start.
- Checkpoint validation passed: `docker compose build jitml`, container
  `jitml docs check`, container `jitml check-code`, and
  `jitml test jitml-unit --linux-cpu --test-options='-p "Product phase status registry"'`
  inside the project container (**6 / 6**). The deterministic plan scans report
  **0** backward dependencies, **0** dual-accelerator gates, and **0** accelerator
  invocations across **20** aggregation validation blocks. The typed registry
  contains **60 Done / 0 Active / 0 Planned / 10 Blocked**; this corrects the
  stale summary count without closing any phase.
- These checks use the image's compiled source with the current plan mounted
  at `/jitml/DEVELOPMENT_PLAN`; the image's changed source and root README match
  the worktree byte-for-byte. Separate output streams and terminal result records
  are retained under `.build/runtime/phase268-20260909/`. These checkpoint checks
  do not discharge the CUDA lifecycle or journal-retention obligations.

### Remaining Work

- On a Linux NVIDIA host, rerun the prescribed `linux-cuda` lifecycle and retain
  the exact journal-derived CUDA projection with its SHA-256 pin.
- Revalidate its exact row order, plan identities, admitted manifests, measured
  evidence, device witnesses, and completion journal digests before restoring
  `Done`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
