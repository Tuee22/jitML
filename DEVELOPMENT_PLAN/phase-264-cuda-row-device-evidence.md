# Phase 264: CUDA Row Device Evidence

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: CUDA Row Device Evidence. Single-session phase migrated from legacy Sprint 29.2 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 264.1: CUDA Row Device Evidence [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Product/Matrix.hs`, `src/JitML/App.hs`, `test/backends/Main.hs`, `test/integration/Main.hs`
**Docs updated**: `../documents/engineering/jit_codegen_architecture.md`, `../documents/engineering/unit_testing_policy.md`

### Objective

Every CUDA-supported product row records real `linux-cuda` device evidence:
runtime probe, generated-source compile/load/launch where applicable, and
substrate-backed learned-state updates through the CUDA device path. Missing
CUDA runtime, driver, or GPU availability fails the lane before row evidence can
be minted.

### Deliverables

- The live CUDA preflight proved Docker exposed the `nvidia` runtime and the RTX
  5090 GPU before any row validation ran.
- All 12 canonical dataset artifacts were uploaded through
  `jitml internal upload-dataset` and SHA-verified against
  `JitML.SL.Dataset.canonicalArtifactSha256For` before supervised rows trained.
- `jitml internal train-and-publish-product-rows --linux-cuda` produced
  inference-eligible artifacts for all **55 / 55** ProductRows on the current
  source after the CUDA publisher memory and convergence calibrations.
- The row-keyed integration matrix consumed the published
  `CompletedTraining` manifests and failed closed before this sprint whenever a
  required product-row checkpoint pointer or live cluster publication was absent.

### Validation

```bash
docker compose run --rm jitml-cuda jitml test jitml-backends --linux-cuda
docker compose run --rm jitml-cuda cabal run -fcuda exe:jitml -- internal train-and-publish-product-rows --linux-cuda
docker compose run --rm jitml-cuda jitml test jitml-integration --linux-cuda
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml check-code
```

2026-07-10 status: Sprint `29.1` is live and passing on the RTX 5090. Focused
current-source CUDA publisher runs validated the missing/failing supervised rows:
`fashion-mnist-resnet` publishes with `test_accuracy=0.826`, and the compact
real-budget rows `cifar10-resnet20`, `cifar10-resnet56`, `cifar10-vit`, and
`tiny-imagenet-resnet50` publish with **4 / 4** eligible. CUDA publisher memory
growth was fixed by evicting cached MLP device weights on allocation pressure and
reusing loaded kernel libraries for the process lifetime; the post-fix narrowed
`PPO/key-door-grid` publisher run passed with `rows: 1`, `eligible: 1`,
`unsupported: 0`, and `errors: 0`. The full current-source CUDA publisher then
passed with `rows: 55`, `eligible: 55`, `unsupported: 0`, and `errors: 0`.
The row-keyed ProductRow integration matrix over the refreshed CUDA checkpoint
pointers passed with **56 / 56** tests using:

```bash
docker compose run --rm jitml-cuda jitml test jitml-integration --linux-cuda --test-options '-p ProductRow --hide-successes --color=never'
```

### Closure Evidence

- **Closed Exit-Definition obligation (real per-row CUDA device evidence).** Every
  CUDA-supported product row must record real `linux-cuda` device evidence backed
  by a measured convergence metric that clears an external literature bar, not an
  eligibility flag minted from a tautological gate, an expert-controller reward,
  or a residual-MLP stand-in.
- **Negative-control validation that closes it.** After Phases `19`–`28`
  re-close, re-run
  `docker compose run --rm jitml-cuda jitml internal train-and-publish-product-rows --linux-cuda`
  and gate each row on the
  [`jitml-negative-controls`](README.md#legacy-to-new-phase-map) suite
  (which rejects an under-target run) and the
  [`jitml-model-convergence`](README.md#legacy-to-new-phase-map)
  case that trains the CUDA-supported row from a real random init through the
  production path. Validation stays single accelerator: `linux-cuda` plus
  `linux-cpu`, never `apple-silicon`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
