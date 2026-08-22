# Phase 268: Contract-Driven CUDA Lane Revalidation

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Contract-Driven CUDA Lane Revalidation. Single-session phase migrated from legacy Sprint 29.5 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

🔄 **Active** (2026-08-22). The committed `linux-cuda` lane fragment is replaced
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

One owned obligation is unmet, and it is the lifecycle one: the 2026-08-22
evidence was gathered against an already-running cluster rather than through the
`./bootstrap/linux-cuda.sh up` -> `test` -> `down` sequence this sprint's
validation block names, so the full bootstrap/test/down cleanup and diagnostic
evidence is not yet recorded.

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

## Sprint 268.1: Contract-Driven CUDA Lane Revalidation [🔄 Active]

**Status**: Active
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

2026-08-22 evidence on the current source, gathered against a running
`linux-cuda` cluster (the bootstrap lifecycle itself is still outstanding — see
below):

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

### Remaining Work

- **Full bootstrap/test/down lifecycle evidence.** The 2026-08-22 revalidation
  ran against a cluster that was already up, so this sprint's deliverable
  "record cleanup and diagnostic evidence for the full bootstrap/test/down
  lifecycle" is unmet. Closing it means running the validation block above as
  written and in order — `./bootstrap/linux-cuda.sh up`,
  `./bootstrap/linux-cuda.sh test`, `./bootstrap/linux-cuda.sh down` — and
  recording the teardown and cleanup diagnostics. Every other obligation this
  sprint owns is met and recorded above.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
