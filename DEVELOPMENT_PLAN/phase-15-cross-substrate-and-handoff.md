# Phase 15: Cross-Substrate Parity and Final Handoff

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md),
[development_plan_standards.md](development_plan_standards.md),
[system-components.md](system-components.md),
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md),
[phase-7-jit-codegen-and-substrates.md](phase-7-jit-codegen-and-substrates.md),
[phase-10-checkpointing-and-inference.md](phase-10-checkpointing-and-inference.md),
[phase-12-test-stanzas-and-cross-cluster.md](phase-12-test-stanzas-and-cross-cluster.md),
[phase-13-linux-cuda-and-cluster-closure.md](phase-13-linux-cuda-and-cluster-closure.md),
[phase-14-apple-silicon-closure.md](phase-14-apple-silicon-closure.md),
[../README.md](../README.md)
**Generated sections**: none

> **Purpose**: Close the cross-substrate parity obligations that consume
> outputs from both Phase `13` (Linux CUDA) and Phase `14` (Apple Silicon),
> populate the live `jitml test all` report card with measured metrics
> from every preceding live phase, and reach the empty
> [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) state
> required by Exit Definition item 18.

## Phase Status

🔄 **Active**. The phase owns [Exit Definition](README.md#exit-definition)
item 18 (legacy ledger empty), the cross-substrate slices of items 5
(per-substrate determinism contract — cross-substrate tolerance
methodology) and 9 (`jitml test all` schedules every stanza and the
live report card surfaces real measurements), plus the cross-cohort
slice of `jitml-cross-backend` (Sprint 12.6) and the live report-card
slice of `jitml test all` (Sprint 12.9).

**Blocked by**: Sprint `15.1`'s apple-involving cross-substrate drift
comparison. Phase `13` closed 2026-05-30 (15 / 15 sprints Done) and
Phase `14` closed 2026-05-31 (5 / 5 sprints Done), so each substrate can
produce its weighted outputs on its owning host. The remaining parity
gap is cross-host: no single validation host runs Linux oneDNN, NVIDIA
CUDA, and Apple Metal weighted kernels in one process.

**Met today**: Phase `13` live outputs (Linux CUDA SL convergence
2026-05-29 `778.27s`, PPO/cartpole RL convergence 2026-05-30 `230.72s`,
weighted inference / `gc.event.<substrate>` / live `jitml-integration`
12 / 12 Live cohort) are available; Phase `14` Apple Metal weighted
inference is available from the headless host path; and the
`linux-cpu` / `linux-cuda` weighted cross-substrate cohort passed the
Sprint `15.1` in-code tolerance assertion on the Linux/NVIDIA host on
2026-06-01.

### Current Implementation Scope

The Haskell-side scaffolding is in place: `JitML.Test.Report.ReportCard`
renders the eight-stanza summary, `test/cross-backend/Main.hs` exercises
the engine-flag + inference-summary surface, the Linux CPU FFI kernel
path, and the locally runnable weighted cross-substrate drift assertion,
and `JitML.Test.Report.parseReportCardKnobs` reads `cabal.project`. The
closure of this phase requires the remaining apple-involving measured
cross-substrate values plus the populated live report card and final
legacy-ledger sweep.

## Phase Summary

Sprints below execute after both `Phase 13` and `Phase 14` close at
least their inference-producing sprints. The work is live cohort
execution + tolerance assertion + final report-card population + ledger
sweep-up.

## Sprint 15.1: Cross-Substrate Cohort Runs and In-Code Tolerance Bands 🔄

**Status**: Active
**Blocked by**: Apple-involving cross-substrate comparison. Phase `13`
Sprint `13.11` (Linux CPU + CUDA weighted inference live) closed
2026-05-27 and Phase `14` Sprint `14.5` (Apple Metal weighted inference
live) closed 2026-05-31, but the assertion remains multi-host for the
`linux-cpu` / `apple-silicon` pair because no single host runs both the
Linux oneDNN weighted path and Metal.
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

1. `docker compose run --rm jitml cabal test -fcuda jitml-cross-backend --test-options='-p CrossSubstrate'`
   exits `0`, with per-tensor drift fitting the in-code per-layer-family
   tolerance band for every locally runnable substrate pair.
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
  by `jitml-cross-backend` once cross-substrate live outputs land.
- `jitml-unit` adds 4 new tests under the "Cross-substrate tolerance
  bands (Sprint 15.1)" group asserting positive bounds, the
  Identity/Embedding-tightest invariant, MHA ≥ Dense, and the
  `withinTolerance` predicate's edge cases.

### Code Surface Landed (2026-06-01)

- `test/cross-backend/Main.hs` adds the "CrossSubstrate weighted drift
  assertions (Sprint 15.1)" group. The live `linux-cpu` / `linux-cuda`
  case probes CUDA, runs the weighted family cohort across
  `Identity`, `Dense2D`, `Conv2DKernel`, `Conv3DKernel`,
  `BatchNormKernel`, `LayerNormKernel`, `MultiHeadAttentionKernel`, and
  `EmbeddingKernel`, computes each per-tensor L∞ drift, and asserts the
  value through `JitML.Engines.Tolerance.withinTolerance`.
- The same group encodes the `linux-cpu` / `apple-silicon` assertion
  behind the existing headless Metal readiness probe so a future
  same-host or cross-host validation path consumes the same in-code
  tolerance table instead of committed numerical fixtures.
- The group includes a controlled over-band perturbation check that
  rejects a `Dense2D` output delta larger than the in-code tolerance
  band.
- Validation on the Linux/NVIDIA host
  (`docker compose run --rm jitml cabal test -fcuda jitml-cross-backend --test-options='-p CrossSubstrate'`)
  passed 3 / 3 CrossSubstrate tests on 2026-06-01. The image build for
  that run also passed the container-only `jitml check-code` gate. This
  validates the `linux-cpu` / `linux-cuda` pair only; the
  `apple-silicon` comparison remains open because this host has no
  Metal device.
- `src/JitML/CrossBackend/Parity.hs` now owns the Sprint `15.1`
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

### Remaining Work

- Validate the `linux-cpu` / `apple-silicon` weighted drift with real
  Apple Metal output against the same in-code tolerance table. The
  implementation path is now the documented cross-host handoff:
  run `jitml verify cross-backend --experiment experiments/mnist.dhall --backends apple-silicon --export /tmp/jitml-apple.json`
  on the Apple host, run
  `jitml verify cross-backend --experiment experiments/mnist.dhall --backends linux-cpu --export /tmp/jitml-linux-cpu.json`
  on a Linux oneDNN host, then run
  `jitml verify cross-backend --experiment experiments/mnist.dhall --compare /tmp/jitml-linux-cpu.json,/tmp/jitml-apple.json`
  with both ephemeral report bundles visible. This remains
  **inherently multi-host** under the current runtime split: no single
  host runs both the Linux oneDNN weighted path and Metal. Confirmed
  2026-05-31 on the Apple M1 host: `apple-silicon` weighted Dense2D
  runs (Metal), but `linux-cpu` weighted Dense2D returns `Left` (the
  GEMM-class weighted body is the Linux/oneDNN path — the
  self-contained identity/reduction kernels do run on macOS) and
  `linux-cuda` needs an NVIDIA GPU. Symmetrically, the 2026-06-01
  Linux/NVIDIA host validates the `(linux-cpu, linux-cuda)` pair and
  the report-bundle handoff path but has no Metal device.

## Sprint 15.2: Live `jitml test all` Report Card with Measured Metrics ⏸️

**Status**: Blocked
**Blocked by**: Sprint `15.1`, every preceding live sprint in Phases
`13` and `14` that emits a report-card metric.
**Implementation**: `src/JitML/App.hs`, `src/JitML/Test/Report.hs`,
`cabal.project`
**Docs to update**: `documents/engineering/unit_testing_policy.md`,
`documents/engineering/training_workloads.md`

### Objective

Drive the live `jitml-e2e` body from an explicit `jitml test all` live
mode, thread the resulting live measurements (SL convergence, RL
reward, AlphaZero arena win rate, JIT cache hit rate, daemon health,
cross-substrate parity tolerance) back into the rendered report card,
and add the live integration test that confirms the report card
surfaces real numbers on top of the existing target-stanza summary.
Closes Exit Definition item 9's live report-card slice.

### Deliverables

- `jitml test all --live` invokes the live `jitml-e2e` orchestration
  alongside the eight test-only stanzas, captures the measured
  metrics from each live phase, and renders the populated report card.
- `JitML.Test.Report.ReportCard` carries optional measured fields for:
  SL final loss per canonical cell, RL final reward per cohort,
  AlphaZero arena win rate per generation, JIT cache hit rate, daemon
  `/healthz` status, and the cross-substrate parity tolerance summary
  from Sprint `15.1`.
- The live integration test confirms the report card surfaces these
  measured values (not just the target-stanza summary).
- The "Target-stanza-only report card" row in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
  moves from `Pending Removal` to `Completed`.

### Validation

1. `jitml test all --live` against an up cluster (Phase `13` Sprint
   `13.1` + Phase `14` Sprint `14.1` at minimum) prints a report card
   with non-empty measured fields.
2. A controlled regression — disabling one live source — surfaces
   `unavailable` in the corresponding measured field rather than a
   silent fallback to a deterministic-stub value.

### Remaining Work

- Extend `jitml test all` with an explicit `--live` mode that runs the
  live e2e path.
- Wire each measured value through the report card.
- Add the live integration test.
- Retire the legacy ledger row.

## Sprint 15.3: Empty Legacy Ledger and Final Handoff ⏸️

**Status**: Blocked
**Blocked by**: Sprint `15.1`, Sprint `15.2`, every remaining ledger
row's owning sprint closure. Phase `13` Sprint `13.9` (MCTS prior stub
retirement) closed 2026-05-30.
**Implementation**: `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`,
`cabal.project`, `src/JitML/Codegen/{Cuda,Metal}.hs`,
`src/JitML/Web/Server.hs`, `playwright/jitml-demo.spec.ts`,
`test/e2e/Main.hs`
**Docs to update**: `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`,
`DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`

### Objective

Resolve every remaining row in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
Pending Removal so the ledger is empty. Closes Exit Definition item 18.

### Deliverables

- Scoped `allow-newer` block removed from `cabal.project` once upstream
  Dhall/CBOR releases support GHC `9.14.1`'s `base-4.22`. If the
  upstream releases remain blocking, this row stays in Pending Removal
  and Phase `15` cannot close until they land.
- Non-production CUDA/Metal kernel-family scaffolds replaced by real
  cuBLAS/cuDNN GEMM/conv and Metal kernels once Phase `13` Sprint
  `13.11` and Phase `14` Sprint `14.5` close.
- Deterministic MCTS prior stub removed once Phase `13` Sprint `13.9`
  closes.
- Demo placeholder shell + inline DOM stubs removed once Phase `13`
  Sprints `13.13` / `13.14` close.
- Target-stanza-only report card surface superseded by Sprint `15.2`.
- The ledger Pending Removal section is empty; every row lives in
  Completed.

### Validation

1. `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md` Pending Removal
   table is empty.
2. `docker compose run --rm jitml jitml check-code` passes after every
   ledger removal.
3. The Closure Status section in
   [README.md](README.md) records the final handoff date and host
   details.

### Remaining Work

- Walk every Pending Removal row in dependency order and apply the
  removal once the owning sprint closes.
- Update the README and overview to reflect the final handoff state.

## Doctrine Sections Cited

- [../README.md → Determinism Contract](../README.md#doctrine-scope) (Sprint 15.1 — cross-substrate ULP tolerance methodology)
- [../README.md → Test-suite stanzas](../README.md#test-suite-stanzas) (Sprints 15.1, 15.2 — `jitml-cross-backend` and `jitml test all` closure)
- [../README.md → Plan / Apply commands](../README.md#doctrine-scope) (Sprint 15.2 — `jitml test all --live` Plan/Apply surface)
- [../README.md → Generated Artifacts → The generated-section registry](../README.md#doctrine-scope) (Sprint 15.3 — final ledger sweep aligns with generated-section discipline)

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/determinism_contract.md` — record the
  in-code per-layer-family tolerance methodology, the locally runnable
  `linux-cpu` / `linux-cuda` assertion, and the remaining
  apple-involving validation path for Sprint `15.1`.
- `documents/engineering/unit_testing_policy.md` — record the
  `jitml-cross-backend` CrossSubstrate tolerance tests for Sprint
  `15.1`; record the live report-card surface once Sprint `15.2`
  closes.
- `documents/engineering/cli_command_surface.md` — generated command
  surface records `jitml verify cross-backend --export/--compare` for
  the Sprint `15.1` cross-host handoff.
- `documents/engineering/training_workloads.md` — append measured live
  summaries for SL / RL / AlphaZero / tune once Sprint `15.2` closes.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- `system-components.md → POC Report-Card Knobs` row reflects the
  populated live measured fields once Sprint `15.2` closes.
- `system-components.md → Test Stanzas` row for `jitml-cross-backend`
  records the 2026-06-01 `linux-cpu` / `linux-cuda` validation and
  flips to Done once the apple-involving comparison closes.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
- [development_plan_standards.md](development_plan_standards.md)
- [phase-13-linux-cuda-and-cluster-closure.md](phase-13-linux-cuda-and-cluster-closure.md)
- [phase-14-apple-silicon-closure.md](phase-14-apple-silicon-closure.md)
- [../README.md](../README.md)
