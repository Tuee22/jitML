# Phase 203: Cross-Substrate Cohort Runs and In-Code Tolerance Bands

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Cross-Substrate Cohort Runs and In-Code Tolerance Bands. Single-session phase migrated from legacy Sprint 17.1 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 203.1: Cross-Substrate Cohort Runs and In-Code Tolerance Bands [✅ Done]

> **SUPERSEDED — surface removed by Sprint `17.4`.** The surface this
> sprint delivered (the `src/JitML/Engines/Tolerance.hs` per-layer-family
> L∞ tolerance band, the `JitML.CrossBackend.Parity` weighted cohort, the
> `CrossSubstrate` drift tests, and the `jitml verify cross-backend`
> command) is **removed** because cross-substrate numeric parity left the
> determinism contract (cross-substrate equivalence is not guaranteed). The
> content below is retained as a dated historical record only.

**Status**: Done — superseded by Sprint `17.4` (surface removed 2026-06-09; was: Done, re-validated 2026-06-06 on RTX 5090; previously Done on RTX 3090)
**Implementation**: `src/JitML/CrossBackend/Parity.hs`,
`src/JitML/App.hs`, `src/JitML/CLI/Spec.hs`,
`test/cross-backend/Main.hs`,
`src/JitML/Engines/Tolerance.hs`,
`src/JitML/Test/Report.hs`
**Docs to update**: `documents/engineering/determinism_contract.md`,
`documents/engineering/unit_testing_policy.md`

### Objective

Run the canonical SL cohort across the `(linux-cpu, linux-cuda)` and
`(linux-cpu, apple-silicon)` substrate pairs (and, opportunistically,
the triple cohort), assert per-tensor drift fits the **in-code**
per-layer-family tolerance band at `src/JitML/Engines/Tolerance.hs`,
and document the methodology in the determinism contract. Closes the
cross-substrate slice of Exit Definition item 5 and the cross-substrate
halves of Sprint `12.6` and Sprint `12.2`. No per-tensor fixture files
are committed per
[../README.md → Snapshot targets → Numerical-fixture
prohibition](../README.md#snapshot-targets) — hardcoding the
producing host's float-reduction behavior into the repository would
authoritatively encode whichever substrate ran the calibration first.

### Deliverables

- `src/JitML/Engines/Tolerance.hs` declares the
  `LayerFamilyTolerance` table (L∞ bound per layer family, calibrated
  from the public literature on cuDNN / Metal / oneDNN drift).
- `test/cross-backend/Main.hs` computes per-tensor `max-abs(delta)` at
  test time between the cohort substrates and asserts each tensor's
  drift fits the in-code band for its layer family.
- `documents/engineering/determinism_contract.md` records the in-code
  tolerance methodology and the per-layer-family bands.
- `jitml verify cross-backend` can export ephemeral cohort report
  bundles and compare them across hosts without committing numerical
  fixtures.

### Validation

1. Historical CUDA-enabled cross-backend stanza evidence exited `0`, with
   per-tensor drift fitting the in-code per-layer-family tolerance band for
   every locally runnable substrate pair. This superseded parity gate is not a
   current Phase `17` aggregation command.
2. A controlled regression — perturbing one substrate's output by more
   than the in-code tolerance band — fails the assertion.
3. `jitml verify cross-backend --compare <linux-report>,<apple-report>`
   exits `0` only when the ephemeral cross-host report bundles fit the
   same in-code tolerance table.

### Code Surface Landed (2026-05-25)

- `src/JitML/Engines/Tolerance.hs` defines `LayerFamilyTolerance` and
  `layerFamilyTolerance :: KernelFamily -> LayerFamilyTolerance` for
  every kernel family in `JitML.Codegen.KernelFamily`. Bounds are
  calibrated from the published cuBLAS / cuDNN / oneDNN / Metal float32
  reduction-drift envelopes: `Identity`/`EmbeddingKernel` at `1e-6`
  (pure copy/lookup), `Dense2D`/`BatchNormKernel`/`LayerNormKernel` at
  `5e-4` (GEMM-class reduction), `Conv2DKernel` at `1e-3`,
  `Conv3DKernel` and `MultiHeadAttentionKernel` at `2e-3`. The
  `withinTolerance family observed` helper is the assertion consumed
  by `jitml-cross-backend` and the report-bundle comparison path.
- `jitml-unit` adds 4 new tests under the "Cross-substrate tolerance
  bands (Sprint 17.1)" group asserting positive bounds, the
  Identity/Embedding-tightest invariant, MHA ≥ Dense, and the
  `withinTolerance` predicate's edge cases.

### Code Surface Landed (2026-06-01)

- `test/cross-backend/Main.hs` adds the "CrossSubstrate weighted drift
  assertions (Sprint 17.1)" group. The live `linux-cpu` / `linux-cuda`
  case probes CUDA, runs the weighted family cohort across
  `Identity`, `Dense2D`, `Conv2DKernel`, `Conv3DKernel`,
  `BatchNormKernel`, `LayerNormKernel`, `MultiHeadAttentionKernel`, and
  `EmbeddingKernel`, computes each per-tensor L∞ drift, and asserts the
  value through `JitML.Engines.Tolerance.withinTolerance`.
- The same group encodes the `linux-cpu` / `apple-silicon` assertion
  behind the existing headless Metal readiness probe; the 2026-06-03
  report-bundle comparison consumed the same in-code tolerance table
  instead of committed numerical fixtures.
- The group includes a controlled over-band perturbation check that
  rejects a `Dense2D` output delta larger than the in-code tolerance
  band.
- Validation on the Linux/NVIDIA host
  (`docker compose run --rm jitml cabal test -fcuda jitml-cross-backend --test-options='-p CrossSubstrate'`)
  passed 3 / 3 CrossSubstrate tests on 2026-06-01. The image build for
  that run also passed the container-only `jitml check-code` gate. This
  validates the `linux-cpu` / `linux-cuda` pair only; the `apple-silicon`
  comparison was outside that Linux/NVIDIA validation and was later superseded
  by the within-substrate-only determinism contract plus the Phase `16` Apple
  lane closure.
- `src/JitML/CrossBackend/Parity.hs` now owns the Sprint `17.1`
  weighted cohort, JSON encoding/decoding for ephemeral report bundles,
  pairwise L∞ drift comparison, and summary rendering. Both the
  `jitml-cross-backend` stanza and `jitml verify cross-backend` consume
  this shared module.
- `jitml verify cross-backend` accepts optional `--backends`, `--export`,
  and `--compare` controls. The command can run locally visible
  substrates, write an ephemeral report bundle, and compare any two or
  more report bundles without committing per-tensor outputs.
- Additional Linux/NVIDIA validation on 2026-06-01 passed:
  `docker compose run --rm jitml cabal build -fcuda lib:jitml`;
  `docker compose run --rm jitml cabal run -fcuda exe:jitml -- verify cross-backend --experiment experiments/mnist.dhall --backends linux-cpu,linux-cuda`;
  and the file handoff path using separate `/tmp/jitml-linux-cpu.json`
  and `/tmp/jitml-linux-cuda.json` exports followed by
  `--compare /tmp/jitml-linux-cpu.json,/tmp/jitml-linux-cuda.json`.

### Historical Validation Re-run (2026-06-03)

- Linux/NVIDIA validation passed:
  `docker compose run --rm jitml cabal test -fcuda jitml-cross-backend --test-options='-p CrossSubstrate'`.
  The run passed 3 / 3 CrossSubstrate tests: the
  `linux-cpu` / `linux-cuda` weighted cohort, the conditional
  `linux-cpu` / `apple-silicon` tolerance assertion, and the over-band
  perturbation rejection.
- The image build performed by that validation passed the container-only
  `jitml check-code` gate before running the test.
- The host-visible Linux report bundle was regenerated with
  `docker compose run --rm -v /tmp:/tmp jitml jitml verify cross-backend --experiment experiments/mnist.dhall --backends linux-cpu --export /tmp/jitml-linux-cpu.json`.
  The bundle is `version` 1, `cohort` `sprint-17.1-weighted`, with a
  single `linux-cpu` report.
- The Apple host export command
  `cabal run exe:jitml -- verify cross-backend --experiment experiments/mnist.dhall --backends apple-silicon --export /tmp/jitml-apple.json`
  passed on 2026-06-03. The ephemeral report bundle is `version` 1,
  `cohort` `sprint-17.1-weighted`, with one `apple-silicon` report and
  8 weighted tensor families (`identity`, `dense`, `conv2d`, `conv3d`,
  `batchnorm`, `layernorm`, `mha`, `embedding`). The prior Linux-host
  Apple export gate remains fail-closed when no Metal device is visible;
  that is expected and not a Sprint `17.1` failure.
- The cross-host Linux/Apple report-bundle comparison passed on
  2026-06-03 using ignored build-output copies under
  `dist-newstyle/phase15/`. The Linux CPU bundle was regenerated in
  `jitml:local`, then compared with the Apple host bundle:
  `docker run --rm -v "$PWD:/work" -w /work jitml:local sh -lc 'jitml verify cross-backend --experiment experiments/mnist.dhall --backends linux-cpu --export dist-newstyle/phase15/jitml-linux-cpu.json && jitml verify cross-backend --experiment experiments/mnist.dhall --compare dist-newstyle/phase15/jitml-linux-cpu.json,dist-newstyle/phase15/jitml-apple.json'`.
  Drift summary: `identity` `0.0` / `1e-6`, `dense` `0.0` / `5e-4`,
  `conv2d` `0.0` / `1e-3`, `conv3d` `0.0` / `2e-3`, `batchnorm`
  `2.384185791015625e-7` / `5e-4`, `layernorm` `0.0` / `5e-4`, `mha`
  `0.0` / `2e-3`, and `embedding` `0.0` / `1e-6`; every family passed.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
