# Phase 204: Live `jitml test all` Report Card with Measured Metrics

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Live jitml test all Report Card with Measured Metrics. Single-session phase migrated from legacy Sprint 17.2 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 204.1: Live `jitml test all` Report Card with Measured Metrics [✅ Done]

> **PARTIALLY SUPERSEDED — `cross_substrate_parity` field removed by Sprint
> `17.4`.** The report-card `cross_substrate_parity` measured field this
> sprint added is **removed** because cross-substrate numeric parity left
> the determinism contract. The rest of the live report card (SL final
> loss, RL reward, AlphaZero arena win rate, tune objective, JIT cache hit
> rate, daemon health) survives as a within-substrate obligation. The
> content below is retained as a dated historical record only.

**Status**: Done — `cross_substrate_parity` field removed by Sprint `17.4` (2026-06-09); the rest of the live report card survives as a within-substrate obligation (was: Done, re-validated 2026-06-06 on RTX 5090; previously Done on RTX 3090, 2026-06-04)
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
and the then-planned cross-substrate comparison summary) back into the rendered report card,
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
  `/healthz` status, and the then-planned cross-substrate comparison summary
  from Sprint `17.1` (removed by Sprint `17.4`).
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
  daemon health, and the historical cross-substrate comparison fields. A missing or
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
2. `jitml test all --live` against an up cluster (Phase `15` Sprint
   `15.1` + Phase `16` Sprint `16.1` at minimum) must still print a
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
6. A historical live Apple Silicon bootstrap/report-card attempt on
   2026-06-03 used the rebuilt `jitml:local` image with host networking and a
   repo-local Cabal build directory. It is retained here as dated per-lane
   evidence, not as a current Phase `17` aggregation command.
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
   passed on 2026-06-03 after the Phase `17` source edits preceding
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
11. The historical host-networked live report-card run exited `0` on
    2026-06-04. All report stanzas passed:
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

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
