# Phase 15: Substrate Reproducibility and Final Handoff

> **Reopened 🔄 Active 2026-06-08 for Sprint `15.4`.** The cross-substrate
> numeric parity surface is being **removed** because cross-substrate
> equivalence is **out of contract**: the reproducibility contract is
> "within a substrate: bit-for-bit reproducible; across substrates: NO
> guarantee" (RNG draw order and float reduction order differ between
> substrates). The tolerance-band + weighted-cohort + drift-test +
> `verify cross-backend` surface (Sprint `15.1`) and the report-card
> `cross_substrate_parity` field (Sprint `15.2`) asserted a guarantee the
> project does not make and are superseded by Sprint `15.4`. The phase's
> remaining obligations are: within-substrate bit-for-bit reproducibility
> (validated **per substrate** by Phases `13`/`14`), a populated live
> report card, and an empty legacy ledger.
>
> **Filename note**: this file deliberately retains the historical
> `phase-15-cross-substrate-and-handoff.md` filename by exception.
> Renaming it would cascade link updates across the plan suite; the H1
> title and scope are reframed instead.

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

> **Purpose**: Establish **within-substrate** bit-for-bit reproducibility
> as the determinism contract (each substrate validated on its own host by
> Phases `13`/`14`), **remove** the out-of-contract cross-substrate numeric
> parity surface, populate the live `jitml test all` report card with
> measured metrics from every preceding live phase, and reach the empty
> legacy-ledger state required by Exit Definition item 18 and final handoff.

## Phase Status

🔄 **Active** (reopened 2026-06-08 for Sprint `15.4`). The cross-substrate
numeric parity surface delivered by Sprints `15.1` and `15.2` is being
removed because cross-substrate equivalence is out of contract; see Sprint
`15.4` for the deletions and the determinism-contract reframe. Sprints
`15.1` and `15.2` are reframed to `🔄 Active — surface removed by Sprint
15.4`; their historical dated evidence is retained as a dated record below.
The phase stays Active until the Sprint `15.4` deletions land and the
`legacy-tracking-for-deletion.md` Pending Removal rows it owns close.

The pre-reopen ✅ Done evidence is retained verbatim below as the dated
historical record.

✅ **Done** (re-validated 2026-06-06 on the current **RTX 5090** host; Sprints
`15.1` and `15.2` reopened 2026-06-06 and re-closed the same day). These two
sprints consume Phase `13`'s live Linux/NVIDIA outputs; Phase `13` reopened
2026-06-06 for full re-validation on the RTX 5090 (UUID
`GPU-e764ef97-32d7-4981-c348-029983c64073`, CUDA 12.8, driver `570.211.01`,
compute capability `12.0`) — every prior closure ran on an **RTX 3090** host —
and re-closed the same day, so the dependent obligations were re-exercised here:

- **Sprint `15.1`** (`linux-cpu` / `linux-cuda` weighted cross-substrate
  tolerance) re-validated 2026-06-06:
  `docker compose run --rm jitml-cuda cabal test -fcuda jitml-cross-backend`
  passed **38 / 38**, including the `CrossSubstrate` group (weighted cohort
  within the in-code tolerance table plus the over-band perturbation rejection).
- **Sprint `15.2`** (the final test suite — live `jitml test all` report card
  with measured metrics) re-validated 2026-06-06: against the fresh
  `linux-cuda` cluster,
  `docker compose run --rm jitml-cuda cabal --builddir=.build/live-cabal run -fcuda exe:jitml -- test all --live`
  exited `0` with **all eight stanzas green** (`cabal_test: passed: 8, failed:
  0`) and a populated report card — `sl_final_loss: mnist-shallow-mlp=0.119`,
  `rl_final_reward: ppo/cartpole=20.06118881118881`,
  `alphazero_arena_win_rate: connect4/gen0=0.625`, `tune_best_objective:
  TPE=0.9792`, `jit_cache_hit_rate: prometheus=1.0 hits=1 misses=0`,
  `daemon_healthz: http://127.0.0.1:9092/healthz status=200`;
  `cross_substrate_parity: unavailable` (expected — no Apple host on this
  Linux/NVIDIA session). Note: on a CUDA host the aggregate must run through
  the **GPU-exposed** `jitml-cuda` service (the documented plain `docker run`
  omits `--gpus all`, whose prior closure ran on Apple where Metal cases skip);
  without GPU visibility the Sprint 13.12 `jitml inference run` case fails
  closed with `linux-cuda runtime unavailable: … gpu_devices=0`. The SL final
  loss is populated because the four canonical MNIST blobs were staged into the
  cluster MinIO via `jitml internal upload-dataset` (SHAs verified).

**Sprint `15.3` remained ✅ Done on its owned surface** (the legacy ledger is
empty — Exit Definition item 18); reopening `15.1`/`15.2` did not reopen the
ledger sweep. The RTX 3090 evidence below is retained as a dated historical
record and is not rewritten as RTX 5090 evidence.

**Remaining Work**: None. Sprints `15.1` and `15.2` were re-exercised on the
RTX 5090 on 2026-06-06 with the evidence above.

Previously ✅ **Done** (re-closed 2026-06-04 after Sprint `15.3` and Phase `1`
Sprint `1.11`). The phase owns [Exit Definition](README.md#exit-definition)
item 18 (legacy ledger empty), the cross-substrate slices of items 5
(per-substrate determinism contract — cross-substrate tolerance
methodology) and 9 (`jitml test all` schedules every stanza and the
live report card surfaces real measurements), plus the cross-cohort
slice of `jitml-cross-backend` (Sprint 12.6) and the live report-card
slice of `jitml test all` (Sprint 12.9).

Phase `13` closed 2026-05-30 (15 / 15 sprints Done) and Phase `14` closed
2026-05-31 (5 / 5 sprints Done), so each substrate produced its weighted
outputs on its owning host; Sprint `15.1` closed the cross-host Linux/Apple
report-bundle comparison on 2026-06-03, and Sprint `15.2` closed the full live
report-card aggregate on 2026-06-04. Sprint `15.3` retired the demo placeholder
row on 2026-06-04; Phase `1` Sprint `1.10` removed the scoped `allow-newer`
block; Phase `1` Sprint `1.11` retired the source-pin/vendor helper by
downgrading to the single GHC `9.12.4` baseline; and the superseded
development ledger was deleted. Phase `8` Sprint `8.8` retired the deterministic
Atari-subset RAM-state stub row, and Phase `8` Sprint `8.9` plus Phase `9`
Sprint `9.8` closed the copyright-free `KeyDoorGrid-v0` replacement on
2026-06-04. Final handoff has no active legacy-ledger rows.

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
and the PPO/cartpole convergence case. On 2026-06-04, a fresh Apple
Silicon live cluster published on fallback `edge_port` `9091`; the full
`jitml test all --live` aggregate passed all eight report stanzas and
rendered populated measured fields for RL reward, AlphaZero arena win
rate, tuning objective, JIT cache hit rate, and daemon `/healthz`.

### Current Implementation Scope

The Haskell-side scaffolding is in place: `JitML.Test.Report.ReportCard`
renders the eight-stanza summary, `test/cross-backend/Main.hs` exercises
the engine-flag + inference-summary surface, the Linux CPU FFI kernel
path, and the locally runnable weighted cross-substrate drift assertion,
and `JitML.Test.Report.parseReportCardKnobs` reads `cabal.project`. The
closure of this phase requires the deletion ledger to have no pending rows.

## Phase Summary

Sprints below execute after both `Phase 13` and `Phase 14` close at
least their inference-producing sprints. The work is live cohort
execution + tolerance assertion + final report-card population + ledger
sweep-up.

## Sprint 15.1: Cross-Substrate Cohort Runs and In-Code Tolerance Bands 🔄

> **SUPERSEDED — surface removed by Sprint `15.4`.** The surface this
> sprint delivered (the `src/JitML/Engines/Tolerance.hs` per-layer-family
> L∞ tolerance band, the `JitML.CrossBackend.Parity` weighted cohort, the
> `CrossSubstrate` drift tests, and the `jitml verify cross-backend`
> command) is **removed** because cross-substrate numeric parity left the
> determinism contract (cross-substrate equivalence is not guaranteed). The
> content below is retained as a dated historical record only.

**Status**: 🔄 Active — surface removed by Sprint `15.4` (was: Done, re-validated 2026-06-06 on RTX 5090; previously Done on RTX 3090)
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

> **PARTIALLY SUPERSEDED — `cross_substrate_parity` field removed by Sprint
> `15.4`.** The report-card `cross_substrate_parity` measured field this
> sprint added is **removed** because cross-substrate numeric parity left
> the determinism contract. The rest of the live report card (SL final
> loss, RL reward, AlphaZero arena win rate, tune objective, JIT cache hit
> rate, daemon health) survives as a within-substrate obligation. The
> content below is retained as a dated historical record only.

**Status**: 🔄 Active — `cross_substrate_parity` field removed by Sprint `15.4` (was: Done, re-validated 2026-06-06 on RTX 5090; previously Done on RTX 3090, 2026-06-04)
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
- The 2026-06-04 live-aggregate closure fixed two Apple live-runner
  issues discovered by the full gate: live bootstrap no longer trusts a
  stale publication's occupied edge port, and the live integration test
  keeps `jitml inference run` fail-closed for Apple Metal while skipping
  only that single CLI invocation when the Linux container cannot see
  host Metal.

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
   with only the then-existing PureScript test-runner warning. Reopened
   Phase `11` Sprint `11.3` retired that warning on 2026-06-04 by switching
   the smoke suite to `spec-node`.
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
   because `jitml-integration` failed in that aggregate run; the
   2026-06-04 validation below closed that failure with a clean full
   aggregate pass and populated report card.
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
10. The full live aggregate passed on 2026-06-04 against a fresh
    Apple Silicon cluster published at `edge_port` `9091`. Setup:
    `docker compose build jitml` produced `jitml:local`; the first live
    run exposed the stale-publication edge-port bug (`9090` occupied by
    another Kind cluster), then a second run exposed stale retained
    `.data/platform/harbor-pg` state. After `jitml cluster down` and
    clearing `.data/`, bootstrap selected `9091`, executed 84 rollout
    steps, wrote a ready publication, and `/healthz` returned `200 ok`.
    Focused `jitml-integration` live reruns passed 19 / 19 before the
    aggregate was rerun.
11. `docker run --rm --name jitml-report-card --network host -v /var/run/docker.sock:/var/run/docker.sock -v "$PWD:$PWD" -w "$PWD" jitml:local cabal --builddir=.build/live-cabal run -fcuda exe:jitml -- test all --live`
    exited `0` on 2026-06-04. All report stanzas passed:
    `jitml-unit`, `jitml-integration`, `jitml-sl-canonicals`,
    `jitml-rl-canonicals`, `jitml-hyperparameter`,
    `jitml-cross-backend`, `jitml-daemon-lifecycle`, and `jitml-e2e`.
    Populated measured fields: `rl_final_reward:
    ppo/cartpole=20.06118881118881`,
    `alphazero_arena_win_rate: connect4/gen0=0.625`,
    `tune_best_objective: TPE=0.9792`, `jit_cache_hit_rate:
    prometheus=1.0 hits=1 misses=0`, and `daemon_healthz:
    http://127.0.0.1:9091/healthz status=200`. `sl_final_loss` and
    `cross_substrate_parity` rendered `unavailable` because those live
    sources were not present in the cluster/report-card probe.

## Sprint 15.3: Empty Legacy Ledger and Final Handoff ✅

**Status**: Done
**Implementation**: `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`,
`cabal.project`, `src/JitML/Codegen/{Cuda,Metal}.hs`,
`src/JitML/Web/Server.hs`, `playwright/jitml-demo.spec.ts`,
`test/e2e/Main.hs`, `test/snapshots/`
**Docs to update**: `README.md`,
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`,
`DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`,
`DEVELOPMENT_PLAN/system-components.md`,
`documents/engineering/code_quality.md`,
`documents/engineering/purescript_frontend.md`,
`documents/engineering/unit_testing_policy.md`

### Objective

Resolve every remaining row in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
Pending Removal so the final handoff has no open legacy rows. Closes Exit
Definition item 18.

### Deliverables

- The dependency source-pin/vendor helper introduced by Phase `1` Sprint
  `1.10` is retired by Phase `1` Sprint `1.11`: GHC `9.12.4` / `base-4.21`
  solves from plain Hackage without source pins or local package patches.
- The copyright-free RL demo replacement row is completed: `KeyDoorGrid-v0`
  owns default visual discrete-control demos and the required algorithm matrix,
  while Atari/ALE is optional runtime support only and requires generated or
  externally supplied adapter support.
- Demo placeholder shell, local stream frames, and inline DOM stubs are
  removed. Plain HTTP stream routes now require a WebSocket upgrade,
  no-publication WebSocket bridges emit a terminal error frame, and
  Playwright requires the live cluster publication.
- The deletion ledger Pending Removal section is empty; every cleanup row lives
  in Completed. The superseded development ledger is deleted.

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

### Cleanup Landed (2026-06-04)

- The scoped `allow-newer` row moved to Completed. `cabal.project` now has no
  `allow-newer` stanza.
- The source-pin/vendor helper moved to Completed. Phase `1` Sprint `1.11`
  changed the project baseline to GHC `9.12.4` / `base-4.21`, removed the
  upstream source pins and local `third_party/haskell/lens-family-*` packages,
  and validated a plain-Hackage solve.
- The superseded reopened-phase development ledger was deleted; reopened-phase
  closure now lives in the owning phase documents, with cleanup residue tracked
  only in the deletion ledger.
- The demo placeholder shell/local stream/offline Playwright fallback
  row moved to Completed. `JitML.Web.Server` now serves the minimal
  compiled-bundle shell, loads only `web/dist/Main/bundle.js`, returns
  `503 live stream requires WebSocket upgrade` for plain HTTP
  `/api/ws*` requests, and emits a terminal error frame instead of a
  deterministic stream when no live publication exists.
- `playwright/jitml-demo.spec.ts` is live-only: it reads
  `.build/runtime/cluster-publication.json`, fails fast when the
  publication is absent, and navigates each panel through the live
  Envoy edge route.
- `JitML.Service.Http.serveHttpRoutesWithWebSockets` forks one worker
  per accepted connection; a held-open WebSocket bridge no longer
  serializes and blocks later HTTP or bundle requests. `jitml-e2e`
  covers both the plain HTTP 503 stream response and the non-blocking
  held-open WebSocket case.
- The browser-contract and route metadata include the live
  `/api/ws/rl` route used by the RL panel.
- The deterministic Atari-subset RAM-state stub row moved to Completed. Phase
  `8` Sprint `8.8` now keeps explicit uncommitted ROM inputs, ignored
  `./.roms/` storage, and the runtime-loaded `JitML.RL.ALE` boundary. The
  later static-foreign-source correction removed the checked-in ALE C++ shim,
  Dockerfile compile step, and lint allowlist; any future project-owned adapter
  must be Haskell-generated or supplied outside the repository.
- The copyright-free RL demo replacement row moved to Completed. Phase `8`
  Sprint `8.9` landed `KeyDoorGrid-v0`, the checked-in
  `experiments/key-door-grid.dhall` demo path, and unit/canonical coverage;
  Phase `9` Sprint `9.8` retargeted the required RL algorithm/convergence
  matrix away from `atari-subset`.

### Validation

1. `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md` Pending Removal
   table is empty, and the superseded reopened-phase development ledger has
   been removed.
2. `docker compose run --rm jitml jitml check-code` passes after every
   ledger removal.
3. The Closure Status section in
   [README.md](README.md) records the final handoff date and host
   details.
4. 2026-06-04 demo cleanup validation: mounted-container
   `jitml-e2e` passed 19 / 19; `jitml check-code` passed; the rebuilt
   image was loaded into the live Apple Silicon cluster as
   `jitml-demo:local`; the live Playwright matrix passed 7 / 7 against
   the published `127.0.0.1:9091` edge route.
5. 2026-06-04 dependency validation: after downgrading to GHC `9.12.4`,
   `cabal.project` has no `allow-newer`, no `source-repository-package`
   entries, and no local dependency packages. A container-local
   `ghcup run --ghc 9.12.4 -- cabal build all --dry-run --jobs=2` solves
   against plain Hackage.
6. 2026-06-04 ALE/foreign-source validation: `docker compose build jitml`
   passed with image-local `check-code: ok` and a rebuilt PureScript bundle;
   `docker compose run --rm jitml jitml check-code` passed; focused
  `jitml-unit` / `jitml-rl-canonicals` tests passed 184 / 184 and 27 / 27;
  `jitml rl train` with `JITML_ENVIRONMENT=atari-subset` and no ROM env
  failed closed with the ROM-policy diagnostic; and the static C++ shim was
  removed from the repository. ROM-backed ALE smoke is optional/manual and was
  not part of required validation.
7. 2026-06-04 KeyDoorGrid validation: `docker compose run --rm -e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0='*' jitml cabal test jitml-unit jitml-rl-canonicals --jobs=2`
   passed, and `docker compose run --rm -e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0='*' -e JITML_ENVIRONMENT=key-door-grid jitml jitml rl train experiments/key-door-grid.dhall`
   exited `0` with `environment: key-door-grid`.
8. 2026-06-04 source-pin/vendor retirement validation: `third_party/` is
   deleted, `cabal.project` references only the root package, and the plain
   Hackage solve selects `serialise-0.2.6.1`, `cborg-0.2.10.0`,
   `dhall-1.42.3`, `lens-family-2.1.3`, and `lens-family-core-2.1.3`.

### Remaining Work

None.

## Sprint 15.4: Remove the cross-substrate parity surface; reframe the determinism contract to within-substrate-only [🔄 Active]

**Status**: 🔄 Active
**Implementation**: deletions in `src/JitML/Engines/Tolerance.hs`,
`src/JitML/CrossBackend/Parity.hs`,
`test/cross-backend/Main.hs` (the `CrossSubstrate` drift group),
`test/unit/Main.hs` (the tolerance-band group),
`src/JitML/Test/Report.hs` + `src/JitML/App.hs` (the report-card
`cross_substrate_parity` field + `measureCrossSubstrateParity` +
`verify cross-backend` handlers), and `src/JitML/CLI/Spec.hs` (the
`verify cross-backend` leaf)
**Docs to update**: `documents/engineering/determinism_contract.md`,
`../README.md`, `documents/engineering/unit_testing_policy.md`,
`system-components.md`

### Objective

Delete the cross-substrate numeric parity surface and reframe the
determinism contract + [Exit Definition](README.md#exit-definition) to
within-substrate-only. Cross-substrate equivalence is out of contract
(RNG draw order and float reduction order differ between substrates), so
the tolerance band, the weighted cohort, the drift tests, the
`verify cross-backend` command, and the report-card
`cross_substrate_parity` field all assert a guarantee the project does not
make and must be removed. The surviving contract is: **within a
substrate, bit-for-bit reproducible** (validated per substrate by Phases
`13`/`14`); **across substrates, no guarantee**.

### Deliverables

- The deletions listed under **Implementation** land: `Tolerance.hs` and
  `CrossBackend/Parity.hs` are removed; the `CrossSubstrate` drift group
  in `test/cross-backend/Main.hs` and the tolerance-band group in
  `test/unit/Main.hs` are removed; the `cross_substrate_parity` field,
  `measureCrossSubstrateParity`, and the `verify cross-backend` handlers
  are removed from `src/JitML/Test/Report.hs` and `src/JitML/App.hs`; and
  the `verify cross-backend` leaf is removed from `src/JitML/CLI/Spec.hs`.
- `documents/engineering/determinism_contract.md` has its "Cross-Substrate
  Tolerance Methodology" section **removed**, and the contract is reframed
  to within-substrate bit-for-bit reproducibility with an explicit
  no-cross-substrate-guarantee statement.
- The [Exit Definition](README.md#exit-definition) items are reworded:
  within-substrate bit-for-bit reproducibility is the determinism claim;
  no cross-substrate numeric-parity claim remains.

### Validation

1. `jitml docs check` is clean after the doc cascade.
2. `jitml test all` passes on the per-substrate lanes (the cross-substrate
   drift/tolerance groups no longer exist).
3. Container `jitml check-code` passes after the source deletions.

### Remaining Work

- The code deletions and the doc cascade are **not yet all landed** (they
  proceed under a separate approved code plan); this sprint stays Active
  until they do.
- Exit Definition item 18 (empty legacy ledger) is **unmet** while the
  `legacy-tracking-for-deletion.md` Pending Removal rows owned by this
  sprint (`Tolerance.hs`, `CrossBackend.Parity`) are open. The sprint
  stays Active until those rows close.

## Doctrine Sections Cited

- [../README.md → Determinism Contract](../README.md#doctrine-scope) (Sprint 15.1 — cross-substrate ULP tolerance methodology)
- [../README.md → Test-suite stanzas](../README.md#test-suite-stanzas) (Sprints 15.1, 15.2 — `jitml-cross-backend` and `jitml test all` closure)
- [../README.md → Plan / Apply commands](../README.md#doctrine-scope) (Sprint 15.2 — `jitml test all --live` Plan/Apply surface)
- [../README.md → Generated Artifacts → The generated-section registry](../README.md#doctrine-scope) (Sprint 15.3 — final ledger sweep aligns with generated-section discipline)

## Documentation Requirements

The reframe (Sprint `15.4`) removes the cross-substrate numeric-parity
documentation surface and replaces it with the within-substrate-only
determinism contract. The Sprint `15.1`/`15.2` doc rows below are retained
as a dated historical record; the live actions are the Sprint `15.4`
removals.

**Engineering docs to create/update:**

- `documents/engineering/determinism_contract.md` — **remove** the
  "Cross-Substrate Tolerance Methodology" section (Sprint `15.4`) and
  reframe the contract to within-substrate bit-for-bit reproducibility
  with an explicit no-cross-substrate-guarantee statement. (Historical:
  Sprint `15.1` had recorded the in-code per-layer-family tolerance
  methodology and the `linux-cpu` / `linux-cuda` plus
  `linux-cpu` / `apple-silicon` assertions.)
- `documents/engineering/unit_testing_policy.md` — **remove** the
  `jitml-cross-backend` CrossSubstrate tolerance-test and tolerance-band
  documentation (Sprint `15.4`); keep the `jitml test all --live`
  report-card surface (minus the `cross_substrate_parity` field),
  missing-source `unavailable` behavior, and the 2026-06-04 full
  live-cluster validation.
- `documents/engineering/cli_command_surface.md` — **remove** the
  `jitml verify cross-backend --export/--compare` generated command-surface
  rows (Sprint `15.4`); this leaf is deleted.
- `documents/engineering/training_workloads.md` — document the
  report-card measurement fields for SL / RL / AlphaZero / tune and
  the 2026-06-04 measured live aggregate (the `cross_substrate_parity`
  field is dropped per Sprint `15.4`).
- `../README.md` — reframe the determinism doctrine to
  within-substrate-only (Sprint `15.4`).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- `system-components.md → Test runner` row reflects the `--live`
  measured fields (minus `cross_substrate_parity`, removed by Sprint
  `15.4`) and the 2026-06-04 full live aggregate pass.
- `system-components.md → Test Stanzas` row for `jitml-cross-backend` —
  **remove** the CrossSubstrate tolerance/drift cross-reference (Sprint
  `15.4`). (Historical: it had recorded the 2026-06-01
  `linux-cpu` / `linux-cuda` validation and the 2026-06-03
  `linux-cpu` / `apple-silicon` report-bundle comparison.)

**Legacy ledger (rule G — Pending Removal rows owned by this phase):**

- `legacy-tracking-for-deletion.md` Pending Removal rows owned by Sprint
  `15.4`: `src/JitML/Engines/Tolerance.hs` (per-layer-family tolerance
  band) and `src/JitML/CrossBackend/Parity.hs` (weighted cross-substrate
  cohort). These rows must move to Completed before Exit Definition item
  18 (empty legacy ledger) is met and the phase can re-close.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
- [development_plan_standards.md](development_plan_standards.md)
- [phase-13-linux-cuda-and-cluster-closure.md](phase-13-linux-cuda-and-cluster-closure.md)
- [phase-14-apple-silicon-closure.md](phase-14-apple-silicon-closure.md)
- [../README.md](../README.md)
