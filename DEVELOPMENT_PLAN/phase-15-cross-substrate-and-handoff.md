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

**Blocked by**: Sprint `15.2`'s clean full-aggregate live report-card
run and the remaining legacy-ledger rows owned by external/upstream or
live-runtime surfaces. Phase `13` closed 2026-05-30 (15 / 15 sprints
Done) and Phase `14` closed 2026-05-31 (5 / 5 sprints Done), so each
substrate can produce its weighted outputs on its owning host; Sprint
`15.1` closed the cross-host Linux/Apple report-bundle comparison on
2026-06-03.

**Current validation evidence**: Phase `13` live outputs (Linux CUDA SL convergence
2026-05-29 `778.27s`, PPO/cartpole RL convergence 2026-05-30 `230.72s`,
weighted inference / `gc.event.<substrate>` / live `jitml-integration`
12 / 12 Live cohort) are available; Phase `14` Apple Metal weighted
inference is available from the headless host path; the 2026-06-03
Apple export bundle contains all eight weighted tensor families; and
the `linux-cpu` / `linux-cuda` weighted cross-substrate cohort passed
the Sprint `15.1` in-code tolerance assertion on the Linux/NVIDIA host
on 2026-06-01 and again on 2026-06-03. The 2026-06-03 Linux/Apple
report-bundle comparison passed across all eight weighted tensor
families against the same in-code tolerance table. The 2026-06-03 Apple
live bootstrap now reaches a healthy published cluster after the
Kind-node inotify-cap and Percona PV-ownership fixes; the edge
`/healthz`, `/readyz`, and `/metrics` routes return `200`, and targeted
live integration reruns passed the StartRLRun event-dispatch smoke case
and the PPO/cartpole convergence case. The full `jitml test all --live`
aggregate still needs a clean rerun to capture the final populated
report card.

### Current Implementation Scope

The Haskell-side scaffolding is in place: `JitML.Test.Report.ReportCard`
renders the eight-stanza summary, `test/cross-backend/Main.hs` exercises
the engine-flag + inference-summary surface, the Linux CPU FFI kernel
path, and the locally runnable weighted cross-substrate drift assertion,
and `JitML.Test.Report.parseReportCardKnobs` reads `cabal.project`. The
closure of this phase requires the populated live-cluster report card
and the final legacy-ledger sweep.

## Phase Summary

Sprints below execute after both `Phase 13` and `Phase 14` close at
least their inference-producing sprints. The work is live cohort
execution + tolerance assertion + final report-card population + ledger
sweep-up.

## Sprint 15.1: Cross-Substrate Cohort Runs and In-Code Tolerance Bands ✅

**Status**: Done
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
  by `jitml-cross-backend` and the report-bundle comparison path.
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

### Validation Re-run (2026-06-03)

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
  The bundle is `version` 1, `cohort` `sprint-15.1-weighted`, with a
  single `linux-cpu` report.
- The Apple host export command
  `cabal run exe:jitml -- verify cross-backend --experiment experiments/mnist.dhall --backends apple-silicon --export /tmp/jitml-apple.json`
  passed on 2026-06-03. The ephemeral report bundle is `version` 1,
  `cohort` `sprint-15.1-weighted`, with one `apple-silicon` report and
  8 weighted tensor families (`identity`, `dense`, `conv2d`, `conv3d`,
  `batchnorm`, `layernorm`, `mha`, `embedding`). The prior Linux-host
  Apple export gate remains fail-closed when no Metal device is visible;
  that is expected and not a Sprint `15.1` failure.
- The cross-host Linux/Apple report-bundle comparison passed on
  2026-06-03 using ignored build-output copies under
  `dist-newstyle/phase15/`. The Linux CPU bundle was regenerated in
  `jitml:local`, then compared with the Apple host bundle:
  `docker run --rm -v "$PWD:/work" -w /work jitml:local sh -lc 'jitml verify cross-backend --experiment experiments/mnist.dhall --backends linux-cpu --export dist-newstyle/phase15/jitml-linux-cpu.json && jitml verify cross-backend --experiment experiments/mnist.dhall --compare dist-newstyle/phase15/jitml-linux-cpu.json,dist-newstyle/phase15/jitml-apple.json'`.
  Drift summary: `identity` `0.0` / `1e-6`, `dense` `0.0` / `5e-4`,
  `conv2d` `0.0` / `1e-3`, `conv3d` `0.0` / `2e-3`, `batchnorm`
  `2.384185791015625e-7` / `5e-4`, `layernorm` `0.0` / `5e-4`, `mha`
  `0.0` / `2e-3`, and `embedding` `0.0` / `1e-6`; every family passed.

## Sprint 15.2: Live `jitml test all` Report Card with Measured Metrics 🔄

**Status**: Active
**Implementation**: `src/JitML/App.hs`, `src/JitML/Test/Report.hs`,
`src/JitML/CLI/Spec.hs`, `cabal.project`
**Docs to update**: `documents/engineering/unit_testing_policy.md`,
`documents/engineering/training_workloads.md`,
`documents/engineering/cli_command_surface.md`, `README.md`,
`documents/cli/commands.md`, `share/man/man1/jitml.1`

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

### Code Surface Landed (2026-06-03)

- `jitml test all --live` is part of `CommandSpec`, the parser accepts
  it, and the generated CLI docs/manpage include the flag.
- `runTest` passes the parsed options through the test runner. After
  the eight Cabal test-only stanzas pass, `--live` collects
  `ReportMeasurements` and renders them in the same typed report card.
- `ReportMeasurements` carries SL final loss, RL final reward,
  AlphaZero arena win rate, tuning best objective, JIT cache hit rate,
  daemon health, and cross-substrate parity fields. A missing or
  unreachable source renders as `unavailable`.
- Local deterministic collectors exist for the SL/RL/AlphaZero/tune
  and cross-substrate surfaces where the current host can run them.
  Live JIT cache hit-rate now reads the daemon Prometheus counters
  (`jitml_jit_cache_hits` / `jitml_jit_cache_misses`) from `/metrics`
  through the published edge port, and daemon health now probes
  `/healthz` through the same edge route. Stale or missing
  `cluster-publication.json` state, failed HTTP probes, missing
  counters, and zero-total cache counters render as `unavailable`
  rather than silently falling back.
- The edge route registry now publishes `/healthz`, `/readyz`, and
  `/metrics` to `jitml-service:8080`; the generated HTTPRoute
  manifests and route-table snapshots were updated with those paths.
- `jitml-e2e` covers available and unavailable measurement rendering,
  and `jitml-unit` covers the `jitml test all --live` parser path. The
  "Target-stanza-only report card" legacy row has moved to Completed.

### Validation

1. `cabal build lib:jitml` passed on 2026-06-03 after the live
   telemetry changes and again after the full-response socket read plus
   fourmolu wrapping fix.
2. `jitml test all --live` against an up cluster (Phase `13` Sprint
   `13.1` + Phase `14` Sprint `14.1` at minimum) must still print a
   report card with non-empty measured fields.
3. A controlled regression — disabling one live source — surfaces
   `unavailable` in the corresponding measured field rather than a
   silent fallback to a deterministic-stub value.
4. Host-side `docker ps` and `kind get clusters` were empty on
   2026-06-03, so no existing live cluster was available for the full
   measurement pass before rebuilding `jitml:local`.
5. `docker compose build jitml` passed on 2026-06-03 after the route
   snapshot and fourmolu fixes. The image-local `jitml check-code`
   gate reported `check-code: ok`, and the web bundle build completed
   with the existing PureScript `runSpec` deprecation warning only.
6. A live Apple Silicon bootstrap/report-card attempt on 2026-06-03
   used the rebuilt `jitml:local` image with host networking and a
   repo-local Cabal build directory:
   `docker run --rm --name jitml-phase15-live --network host -v /var/run/docker.sock:/var/run/docker.sock -v "$PWD:$PWD" -w "$PWD" jitml:local sh -lc 'mkdir -p /tmp/jitml-cache && export XDG_CACHE_HOME=/tmp/jitml-cache && cabal --builddir=.build/live-cabal run -fcuda exe:jitml -- bootstrap --apple-silicon && cabal --builddir=.build/live-cabal run -fcuda exe:jitml -- test all --live'`.
   Bootstrap completed and reported `bootstrap: live phased rollout
   executed 85 steps`; the generated
   `.build/runtime/cluster-publication.json` reported Harbor, MinIO,
   Pulsar, PostgreSQL, observability, `jitml-service`, and `jitml-demo`
   as ready on `edge_port` `9090`. The subsequent aggregate
   `jitml test all --live` reached the Cabal test fan-out but exited `1`
   because `jitml-integration` failed in that aggregate run; this keeps
   Sprint `15.2` Active until the full aggregate is rerun cleanly and
   the report card is captured.
7. The same live cluster's edge routes were validated on 2026-06-03:
   `curl -sS -i http://127.0.0.1:9090/healthz` returned `200` with
   body `ok`; `/readyz` returned `200` with body `ready`; `/metrics`
   returned `200` Prometheus text including `jitml_jit_cache_hits 1`,
   `jitml_jit_cache_misses 0`, and `jitml_pulsar_consumer_lag 0`.
8. Targeted live integration reruns against the published cluster passed
   after the aggregate failure was isolated: the StartRLRun dispatch
   smoke case passed in `1.78s`, and the PPO/cartpole convergence case
   passed in `205.83s`. The PPO worker Job `jitml-rl-livecv1780529861`
   completed with `episodes: 200` and `avg-reward:
   658.4104921102621`, clearing the in-code threshold.
9. `docker run --rm -v "$PWD:/work" -w /work jitml:local jitml check-code`
   passed on 2026-06-03 after the Phase `15` source edits preceding
   this documentation refresh.

### Remaining Work

- Rerun the full aggregate `jitml test all --live` against the current
  live Apple Silicon cluster or a fresh equivalent cluster, with the
  live SL/RL/AlphaZero/tune, daemon, cache, and cross-substrate sources
  reachable. The previous aggregate reached the live Cabal fan-out and
  then exited `1` in `jitml-integration`; targeted reruns for the
  StartRLRun and PPO/cartpole convergence cases now pass, so the next
  session should rerun the aggregate and capture the final report card
  rather than re-debugging rollout.
- Record the populated non-empty report-card measured fields here after
  the clean aggregate pass.

## Sprint 15.3: Empty Legacy Ledger and Final Handoff ⏸️

**Status**: Blocked
**Blocked by**: Sprint `15.2`, the upstream Dhall/CBOR bound refresh
required to remove scoped `allow-newer`, the live demo/browser
validation that retires the demo placeholder row, and the real ALE
binding work that retires the deterministic Atari-subset RAM-state stub.
**Implementation**: `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`,
`cabal.project`, `src/JitML/Codegen/{Cuda,Metal}.hs`,
`src/JitML/Web/Server.hs`, `playwright/jitml-demo.spec.ts`,
`test/e2e/Main.hs`, `test/snapshots/`
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
- Demo placeholder shell + inline DOM stubs removed once Phase `13`
  Sprints `13.13` / `13.14` close.
- The ledger Pending Removal section is empty; every row lives in
  Completed.

### Cleanup Landed (2026-06-03)

- The Metal kernel-family validation residue moved to Completed after
  the Apple host exported the Sprint `15.1` weighted bundle with all
  eight tensor families.
- The deterministic MCTS `priorFor` helper was removed; the default
  mechanics oracle is neutral uniform and production self-play consumes
  the policy/value network oracle.
- The target-stanza-only report-card row moved to Completed. `ReportCard`
  now carries `ReportMeasurements`, and `jitml test all --live` renders
  measured or `unavailable` fields.
- The Sprint `15.2` cache and daemon live-report probes now use
  host-reachable daemon edge routes instead of a cache placeholder or a
  publication-file-only health check.
- The committed numerical fixture tree under `test/golden/` was deleted.
  Pure renderer snapshots moved to `test/snapshots/`, numerical tests
  now use run-to-run/property assertions, and lint rejects
  `test/golden/`.

### Validation

1. `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md` Pending Removal
   table is empty.
2. `docker compose run --rm jitml jitml check-code` passes after every
   ledger removal.
3. The Closure Status section in
   [README.md](README.md) records the final handoff date and host
   details.

### Remaining Work

- Remove the scoped `allow-newer` block once Hackage releases solve
  under pinned GHC `9.14.1` without overrides.
- Remove the demo placeholder shell, local stream frames, and inline DOM
  stubs after the live browser cluster pass proves the panels populate
  from real broker frames.
- Replace the deterministic Atari-subset RAM-state stub with the real
  ALE FFI binding, including ROM handling and container packages.
- Update the README and overview to reflect the final handoff state
  only after the Pending Removal table is empty.

## Doctrine Sections Cited

- [../README.md → Determinism Contract](../README.md#doctrine-scope) (Sprint 15.1 — cross-substrate ULP tolerance methodology)
- [../README.md → Test-suite stanzas](../README.md#test-suite-stanzas) (Sprints 15.1, 15.2 — `jitml-cross-backend` and `jitml test all` closure)
- [../README.md → Plan / Apply commands](../README.md#doctrine-scope) (Sprint 15.2 — `jitml test all --live` Plan/Apply surface)
- [../README.md → Generated Artifacts → The generated-section registry](../README.md#doctrine-scope) (Sprint 15.3 — final ledger sweep aligns with generated-section discipline)

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/determinism_contract.md` — record the
  in-code per-layer-family tolerance methodology and the validated
  `linux-cpu` / `linux-cuda` plus `linux-cpu` / `apple-silicon`
  assertions for Sprint `15.1`.
- `documents/engineering/unit_testing_policy.md` — record the
  `jitml-cross-backend` CrossSubstrate tolerance tests for Sprint
  `15.1`; record the `jitml test all --live` report-card surface and
  missing-source `unavailable` behavior while full live-cluster
  validation remains in Sprint `15.2` Remaining Work.
- `documents/engineering/cli_command_surface.md` — generated command
  surface records `jitml verify cross-backend --export/--compare` for
  the Sprint `15.1` cross-host handoff.
- `documents/engineering/training_workloads.md` — document the
  report-card measurement fields for SL / RL / AlphaZero / tune and
  keep full live-cluster measurement capture in Sprint `15.2`
  Remaining Work.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- `system-components.md → Test runner` row reflects the `--live`
  measured fields and the remaining live-cluster validation gap.
- `system-components.md → Test Stanzas` row for `jitml-cross-backend`
  records the 2026-06-01 `linux-cpu` / `linux-cuda` validation and the
  2026-06-03 `linux-cpu` / `apple-silicon` report-bundle comparison.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
- [development_plan_standards.md](development_plan_standards.md)
- [phase-13-linux-cuda-and-cluster-closure.md](phase-13-linux-cuda-and-cluster-closure.md)
- [phase-14-apple-silicon-closure.md](phase-14-apple-silicon-closure.md)
- [../README.md](../README.md)
