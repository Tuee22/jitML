# Phase 268: Contract-Driven CUDA Lane Revalidation

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Contract-Driven CUDA Lane Revalidation. Single-session phase migrated from legacy Sprint 29.5 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done** (2026-09-12). The prescribed `linux-cuda` lifecycle ran end to end
on the real RTX 5090 host and the durable typed lane journal it owes Phase `276`
is retained. `./bootstrap/linux-cuda.sh test` exited `0` with **10 / 10**
stanzas, `0` failed and `0` not-run; the live browser gate, the 55-row publisher
and the every-row wall-clock comparison all exited `0`; and the exact
175,023-byte version-`1` journal is tracked at
[attestations/linux-cuda-product-lane-journal.json](attestations/linux-cuda-product-lane-journal.json)
with pinned SHA-256
`e90dd1cdd633050987775e9566099ea7307abfdd8e2dd0f3a3d0326c85e4e6ea`. The
production `admitProductLaneJournal` reader admits all **55** rows against the
current `linux-cuda` projection. Teardown, documentation, code-quality and
phase-status gates passed. Phase `273` is the next owner and needs the Apple
host.

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

## Sprint 268.1: Contract-Driven CUDA Lane Revalidation [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Test/RunContract.hs`,
`src/JitML/Test/Report.hs`, `test/integration/Main.hs`,
`DEVELOPMENT_PLAN/attestations/linux-cuda-report-card.md`,
`DEVELOPMENT_PLAN/attestations/linux-cuda-product-lane-journal.json`
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

Build the current runtime source into `jitml:local` before starting the lifecycle.
The skip-image-build setting reuses that prepared image during bootstrap.

```bash
docker compose build jitml
JITML_BOOTSTRAP_SKIP_IMAGE_BUILD=1 ./bootstrap/linux-cuda.sh up
```

Before testing, stage all twelve exact canonical dataset artifacts through
`jitml internal upload-dataset`, using the operational prerequisites in
[Phase 261](phase-261-contract-driven-live-execution-integration-journal.md#validation).
First use does not download or populate MinIO. Run the publisher, the complete
CUDA lane, the live browser gate, and the every-row performance comparison in
sequence so checkpoint writers and measured GPU workloads do not overlap:

```bash
docker compose run --rm jitml-cuda jitml internal train-and-publish-product-rows --linux-cuda
./bootstrap/linux-cuda.sh test
docker compose run --rm jitml-cuda jitml test jitml-e2e --live --linux-cuda
docker compose run --rm jitml-cuda jitml internal benchmark-product-row-wall-clock
```

Retain the exact `.build/runtime/product-lane-journals/linux-cuda.json` emitted
by the successful integration invocation at
`DEVELOPMENT_PLAN/attestations/linux-cuda-product-lane-journal.json`, record its
SHA-256, and admit it against the current CUDA projection with the production
`admitProductLaneJournal` reader before closure. Complete teardown and the
container documentation, code-quality, and phase-status gates:

```bash
./bootstrap/linux-cuda.sh down
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
docker compose run --rm jitml jitml test jitml-unit --linux-cpu --test-options='-p "Product phase status registry"'
```

The three deterministic plan scans in standards rule `M` also report zero
backward dependencies, dual-accelerator gates, and aggregation accelerator
invocations.

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

### Closure Evidence

The prescribed lifecycle ran on Linux x86_64 with an NVIDIA GeForce RTX 5090,
driver `595.84`, CUDA `13.2`, and Docker with the `nvidia` runtime registered
as the default. `./bootstrap/linux-cuda.sh doctor` exited `0`.

| Gate | Result |
|---|---|
| `docker compose build jitml` | exit `0`; in-build `check-code: ok`; image `sha256:8e629e9d6091905818f65b716a5be4b474c32414c4fabd71487b0a76b386bc81` |
| `JITML_BOOTSTRAP_SKIP_IMAGE_BUILD=1 ./bootstrap/linux-cuda.sh up` | exit `0` — **113** live rollout steps, **18** third-party images pre-pulled, all **8** components ready, edge port `9092` |
| twelve canonical dataset uploads | **12 / 12** exit `0`, every artifact matching its governed SHA-256 pin |
| `jitml internal train-and-publish-product-rows --linux-cuda` | exit `0` — `rows: 55`, `eligible: 55`, `unsupported: 0`, `errors: 0` |
| `./bootstrap/linux-cuda.sh test` | exit `0` in **36,938.267859688** seconds — **10 / 10** stanzas, `0` failed, `0` not-run |
| `jitml test jitml-e2e --live --linux-cuda` | exit `0` — `jitml-integration` **197 / 197**, `jitml-e2e-playwright` **PASS**, Haskell `jitml-e2e` **30 / 30** |
| `jitml internal benchmark-product-row-wall-clock` | `rows=55`, `status=PASS`, `0` failed rows — item `29` met |
| `./bootstrap/linux-cuda.sh down` | exit `0`; both Kind nodes deleted; `.data` preserved (1.2 GiB) |
| `jitml docs check` / `jitml check-code` | PASS / PASS |
| focused `Product phase status registry` unit gate | **6 / 6** |

The complete lane's ten stanzas are `jitml-unit` **907 / 907**,
`jitml-integration` **197 / 197** (28,375.03 s), `jitml-sl-canonicals`
**36 / 36**, `jitml-rl-canonicals` **47 / 47**, `jitml-hyperparameter`
**26 / 26**, `jitml-backends` **28 / 28**, `jitml-daemon-lifecycle` **54 / 54**,
`jitml-e2e` **30 / 30**, `jitml-negative-controls` **3 / 3**, and
`jitml-model-convergence` **111 / 111** — **1,439** tests in total. The live
browser gate exercised **77** Playwright tests in 56.0 seconds across **55**
distinct `e2e.product.*` row selectors.

The publisher's 55 rows were trained fresh over 6h21m
(2026-09-10T21:31:57Z to 2026-09-11T03:53Z). Its retained transcript is the
confirming re-invocation that reused all **55** already-admitted checkpoints in
ten seconds and reported the same `55 / 55 / 0 / 0` counts with an empty stderr
stream.

The exact `.build/runtime/product-lane-journals/linux-cuda.json` issued by the
successful full-lane integration invocation is retained at
[attestations/linux-cuda-product-lane-journal.json](attestations/linux-cuda-product-lane-journal.json):
175,023 bytes, SHA-256
`e90dd1cdd633050987775e9566099ea7307abfdd8e2dd0f3a3d0326c85e4e6ea`, wire
version `1`, substrate `linux-cuda`, run id
`jitml-product-scenario-d039c90b33061fd0`, source journal SHA-256
`5cb77077b466b81635dbea1a740d8bc372263e45c4803aae0507477485ee53f7`. The
production `admitProductLaneJournal` reader, run against
`projectProductRows LinuxCUDA allProductRows`, admits all **55** rows with the
pinned digest and rejects nothing.

Its `DeviceEvidence` resolves to exactly two device witnesses — **45** rows on
`cuda` / `mlp-forward-backward-tanh-linear` with artifact SHA-256
`bfdeb1d4e39cf268461241c17849def2a5da36740f0998874a41e12166aaf3ae`, and **10**
rows on `linux-cuda-cudnn` / `cublas_sgemm_forward` with artifact SHA-256
`06afb721b891e7c73c92d7a9c940e0e6a468a8f29c5af86df0ba57cbff809d6b`. Both are
byte-identical to the values the 2026-08-19 and 2026-08-22 full-lane runs
issued, so Phase
[78](phase-78-kernelspec-cache-key-inputs-ffi-loader-surface.md)'s artifact
reproducibility now holds across three independent lanes on two separately
bootstrapped clusters.

The three deterministic plan scans in standards rule `M` report **0** backward
dependency edges, **0** dual-accelerator validation gates, and **0** accelerator
invocations across the **58** registered phases whose `### Validation` blocks are
`linux-cpu`-only. That mapping is a superset of the twenty aggregation blocks
earlier passes scanned.

Invocation stdout, stderr, and terminal status records for every step are
retained under `.build/runtime/phase268-20260910-linux/`.

#### Shared-host interruption (not closing evidence)

At 2026-09-11T15:52:59Z an unrelated cleanup on this shared host destroyed the
`jitml-linux-cuda-control-plane` container while the first
`jitml test jitml-e2e --live --linux-cuda` attempt was running. The lane stalled
against a dead API server and was aborted without a terminal status; it is not
closing evidence, and its empty transcript is retained as
`e2e-attempt1.*`. The complete `jitml test all --linux-cuda` lane had already
exited `0` before that point, and the journal it issued was written at
2026-09-11T14:09:57Z, so that evidence is unaffected. The cluster was rebuilt
(`up` exit `0`, **112** rollout steps, all **8** components ready, edge port
`9092`); the retained MinIO PV preserved all twelve dataset objects and all 55
admitted checkpoints, which the publisher re-audit confirmed at `55 / 55 / 0 / 0`
in ten seconds; and the live browser gate was then re-run from the beginning and
exited `0`.

### Historical 2026-09-09 Mac Prerequisite Check

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

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
