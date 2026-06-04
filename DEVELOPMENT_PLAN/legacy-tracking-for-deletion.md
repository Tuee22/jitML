# Legacy Tracking

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md),
[development_plan_standards.md](development_plan_standards.md),
[00-overview.md](00-overview.md), [system-components.md](system-components.md),
[phase-0-planning-documentation.md](phase-0-planning-documentation.md),
[phase-1-haskell-cli-surface.md](phase-1-haskell-cli-surface.md),
[phase-2-bootstrap-reconciler-and-jit-cache.md](phase-2-bootstrap-reconciler-and-jit-cache.md),
[phase-3-cluster-substrate-and-routing.md](phase-3-cluster-substrate-and-routing.md),
[phase-4-stateful-platform-services.md](phase-4-stateful-platform-services.md),
[phase-5-jitml-service-daemon.md](phase-5-jitml-service-daemon.md),
[phase-6-numerical-core.md](phase-6-numerical-core.md),
[phase-7-jit-codegen-and-substrates.md](phase-7-jit-codegen-and-substrates.md),
[phase-8-supervised-and-rl-framework.md](phase-8-supervised-and-rl-framework.md),
[phase-9-rl-catalog-alphazero-and-tuning.md](phase-9-rl-catalog-alphazero-and-tuning.md),
[phase-10-checkpointing-and-inference.md](phase-10-checkpointing-and-inference.md),
[phase-11-purescript-frontend-and-demo.md](phase-11-purescript-frontend-and-demo.md),
[phase-12-test-stanzas-and-cross-cluster.md](phase-12-test-stanzas-and-cross-cluster.md),
[phase-13-linux-cuda-and-cluster-closure.md](phase-13-linux-cuda-and-cluster-closure.md),
[phase-14-apple-silicon-closure.md](phase-14-apple-silicon-closure.md),
[phase-15-cross-substrate-and-handoff.md](phase-15-cross-substrate-and-handoff.md),
[../README.md](../README.md)
**Generated sections**: none

> **Purpose**: Record every surviving compatibility helper, deprecated path,
> doctrine deviation, and tooling residue still slated for deletion.

> **Authoritative Reference**:
> [development_plan_standards.md → I. Explicit Cleanup and Removal Ledger](development_plan_standards.md#i-explicit-cleanup-and-removal-ledger)

## Ledger Status

This ledger tracks **doctrine deviations and compatibility helpers**, not
unmet primary Exit-Definition obligations. Primary unmet obligations live in
the owning sprint's `### Remaining Work` block per
[development_plan_standards.md → C. Honest Completion Tracking](development_plan_standards.md#c-honest-completion-tracking).

Two cleanup rows are currently active. The scoped `allow-newer` block in
`cabal.project` keeps Dhall's transitive CBOR stack building under pinned
GHC `9.14.1` while upstream package bounds catch up; this reopened Phase `1`
Sprint `1.10` on 2026-06-04. The remaining stand-in row records the
deterministic atari-subset RAM-state stub awaiting a real ALE binding plus
explicit ROM handling; this reopened Phase `8` Sprint `8.8` on 2026-06-04.
Both rows gate Phase `15` Sprint `15.3`. Three rows added 2026-05-29 record
doctrine deviations scheduled by the reopened Phases `2` / `4` / `5` after the
cluster OOM-storm incident: the `JITML_*` run-parameter env IPC and the duplicate
`JITML_SUBSTRATE` / `JITML_PULSAR_WS` reads (both retired by the typed Dhall
`RunConfig` + BootConfig mount in Phase 5 Sprint `5.7`), and the embedded `sh -c`
reconciler control-flow (retired by Phase 2 Sprint `2.9` + Phase 4 Sprint `4.8`).
The 2026-05-30 headless Apple Metal JIT removals — the `src/JitML/Tart/*` modules,
the `jitml internal vm` command group, the `container.tart` prerequisite node,
`LiveConfig.tartIdleTimeout`, and the offline `.metallib` codegen path — **closed
the same day** (Sprints `7.8` / `2.10` / `5.8`) and now live in the `Completed`
table.
Sixteen cleanup rows have
closed and live in the `Completed` table:
Sprint `1.4` removed lint-time host `ghcup` style-tool bootstrap and moved the
style GHC/tool install plus `jitml check-code` gate into `jitml:local` image
construction and made lint/check-code execution container-only;
Sprint `3.5` removed the
`jitml-mirror` Helm placeholder and inserts the Docker build / explicit Kind
image-load phase directly in the live typed rollout; Sprint `4.3` folded the
standalone MinIO values fragment into `chart/values.yaml`; Sprint `7.7`
removed the static checked-in JIT source/build scaffold (JIT compiler inputs
are generated on demand by the Haskell binary) and removed the default
runtime-source placeholder fixture; Sprint `8.7` replaced the flat `RunPhase`
enum with the phase-indexed `RLRunLifecycle` GADT so all three jitML
lifecycles share doctrine-aligned shape; the 2026-06-03 Phase `15` pass
removed the synthetic MCTS `priorFor`, replaced the target-stanza-only report
card with `jitml test all --live` measured fields, deleted the committed
numerical fixture tree under `test/golden/`, closed the Metal
kernel-family validation residue with a headless Apple weighted export, and
retired the demo placeholder shell/local stream/offline Playwright fallback
paths after live Playwright validation; and
the 2026-05-28 Pulumi-removal cleanup deleted the `infra/pulumi/`
ephemeral-Kind orchestrator (added in error), its `toolchain.pulumi`
prerequisite, and the Pulumi-only Kind name-override surface, leaving the
`jitml bootstrap` + `jitml cluster down` path as the ephemeral-cluster e2e
orchestration.

Two classes of entries populate this ledger over time:

1. **Doctrine-deviation residue.** Any worktree behavior that the implemented
   code does not yet honour against an in-scope doctrine section, scheduled
   through the owning sprint per standards rule L.
2. **Stand-in residue.** Any temporary scaffolding (placeholder kernel, smoke
   subprocess, in-memory MinIO stub, etc.) used to keep CI green while the
   real implementation lands. Each stand-in must name the sprint that retires
   it.

The doctrine envelope at [00-overview.md → Doctrine Scope](00-overview.md#doctrine-scope)
admits no out-of-scope-but-implemented sections at write time — when the
`Smart Constructors for Paired Resources` doctrine section becomes in-scope
(any future PV/PVC pair, DNS/cert pair, or analogous coupled resources), that
opening event itself enqueues a row here naming the originating sprint.

## Pending Removal

| Item | Location | Reason | Owning Sprint / Gate |
|------|----------|--------|----------------------|
| Scoped `allow-newer` for Dhall / CBOR transitive package bounds | `cabal.project` | Upstream `dhall`, `cborg`, `cborg-json`, and `serialise` releases have not yet relaxed bounds for GHC `9.14.1`'s `base`, `template-haskell`, `containers`, `bytestring`, and `time`; remove once Hackage releases support the pinned toolchain without overrides | Reopened Phase 1 Sprint `1.10`; Phase 15 Sprint `15.3` final handoff gate |
| Deterministic atari-subset RAM-state stub | `src/JitML/RL/Simulator.hs` (`atariSubsetEnvironment`, `atariSubsetStep`, `AtariSubsetState`) | Sprint `8.3` (closed 2026-05-25) ships a deterministic 128-byte RAM-state stub matching the canonical Atari action/obs surface while a real Arcade Learning Environment binding lands. The replacement path is a pinned source-built ALE library in `jitml:local`, a small C ABI shim consumed by `JitML.RL.ALE`, and explicit uncommitted ROM handling; do not depend on Ubuntu `libale-dev`. The deterministic stub preserves the action/obs contract so upstream RL primitives (`AlgorithmModule`, `VecEnv`, `RLLoop`) consume the real binding identically when it lands. | Reopened Phase 8 Sprint `8.8`; Phase 15 Sprint `15.3` final handoff gate |


## Pending Removal Notes

Pending-removal rows normally resolve on the closure of the owning sprint
listed in the relevant phase document. Rows whose blocker is an external
upstream release still name the originating sprint, but resolve at the final
handoff toolchain refresh. Each row moves to `Completed` only when the
replacement is verified in the worktree.

Current `allow-newer` validation: on 2026-06-04, a temporary project file
under `.build/phase1/` with the scoped `allow-newer` block removed still fails
dependency solving under pinned GHC `9.14.1` after `cabal update` refreshed
Hackage to index-state `2026-06-04T13:02:57Z`: `serialise-0.2.6.1` excludes
the installed `base-4.22` (`base >=4.11 && <4.22`). The row remains pending
until upstream releases solve under the pinned toolchain without overrides.
Recommended unblock: keep the scoped override in place, file or track upstream
bound-relaxation issues / PRs / Hackage metadata revisions for `serialise`,
`cborg`, `cborg-json`, and the Dhall stack with GHC `9.14.1` / `base-4.22`
evidence, and re-run the no-override solver check before each final-handoff
retry. Do not downgrade the project compiler to clear this row.

Current ALE package validation: on 2026-06-04, `apt-get update` plus
`apt-cache policy` inside the `jitml:local` Ubuntu 24.04 image found
candidates for `libsdl2-dev` and `zlib1g-dev`, but no `libale-dev`
candidate; `apt-cache search` for `arcade learning environment` and
`libale` returned no matching Ubuntu package. The real ALE binding row should
therefore not wait on Ubuntu packaging. Recommended unblock: build ALE from a
pinned upstream tag or source SHA in `jitml:local`, enable the C++ library,
expose only a small C ABI to Haskell (`create`, `destroy`, `load_rom`, `reset`,
`act`, `game_over`, `get_ram`, `get_screen`, `legal_actions`, `seed`), and make
ROM inputs explicit and uncommitted. The row remains pending until that binding
and the ROM acquisition/test path are verified.

This ledger never holds primary unmet Exit-Definition obligations. Live
Kind/Helm rollout, real Pulsar/MinIO/Harbor clients, real per-substrate
kernel execution, real Playwright runs, and similar primary obligations live
in the owning sprint's `### Remaining Work` block per standards rule C —
not here. Rows here are exclusively for: an implemented behaviour that does
not yet honour an in-scope doctrine section (enqueued by the owning sprint
per standards rule L), or a temporary scaffold (placeholder kernel, smoke
subprocess, in-memory client stub) introduced to keep CI green while the
real implementation lands (with the retiring sprint named on the row).
Filesystem-backed `HasMinIO` interpreters and synthetic broker/client states
used as durable test harnesses are not pending-removal rows unless a sprint
explicitly schedules their deletion.

## Completed

| Item | Removed In | Notes |
|------|------------|-------|
| Tart VM build/lifecycle/exec modules, `jitml internal vm` command group, `container.tart` prerequisite, `LiveConfig.tartIdleTimeout`, and the offline `.metallib` codegen path | Sprints `7.8` + `2.10` + `5.8` (2026-05-30) | The headless Apple Metal JIT (host CommandLineTools `swift build` + runtime `MTLDevice.makeLibrary(source:)`, validated headless on Apple M1) superseded the Tart-VM build. Deleted `src/JitML/Tart/{Build,Lifecycle,Exec}.hs`; removed the `jitml internal vm bootstrap\|up\|down\|status\|exec` command group from `CommandSpec` + `App.hs` handlers (commands.md/man/completions regenerated); removed the `container.tart` prerequisite node + its `jit-cache-miss` dependency; removed `LiveConfig.tartIdleTimeout` from the Dhall schema + Haskell record + `daemon.surface` table; dropped the `.process("Kernels.metal")` resource, the `<hash>.metallib` publication, and the `JITML_METALLIB_PATH` env hand-off. `cabal build all` clean; 183 `jitml-unit` + 30 `jitml-daemon-lifecycle` + the Apple `jitml-cross-backend` cases pass. |
| Lint-time host `ghcup` style-tool bootstrap | Sprint 1.4 | Removed runtime `ensureStyleTools` / `installStyleToolsSubprocess` bootstrap from `src/JitML/Lint/Stack.hs`; `docker/Dockerfile` now installs the style-tools GHC plus pinned `fourmolu` / `hlint`, stamps the `jitml:local` code-quality domain, and runs `jitml check-code` during image construction. |
| `jitml-mirror` Helm release placeholder | Sprint 3.5 | Removed the stand-in `HelmRelease "jitml-mirror" "jitml-images"` row from `JitML.Cluster.Helm.phasedReleases`; `JitML.Bootstrap.livePhasedRolloutSubprocesses` now inserts the Docker build / explicit Kind image-load subprocesses directly before final services. |
| Static JIT source/build scaffolds | Sprint 7.7 | Removed checked-in substrate build scripts and kernel source scaffolds; Haskell renderers emit compiler inputs under `./.build/jit-src/<substrate>/<hash>/` |
| Default runtime-source placeholder | Sprint 7.7 | Removed `defaultRuntimeSourcePayload` and the `runtime-source:phase-2-placeholder` marker from `src/JitML/Cache/Key.hs`; cache-key snapshot now derives its `RuntimeSourcePayload` from `renderRuntimeSource`, and `test/snapshots/cache/kernel-key.txt` was refreshed to the rendered-source-backed hash. |
| Standalone MinIO values fragment | Sprint 4.3 | Folded MinIO subchart values into `chart/values.yaml`, removed `chart/minio-values.yaml`, and made bootstrap delete legacy standalone values files during materialization. |
| RL run sequencing as a `RunPhase` enum instead of an `RLRunLifecycle` GADT | Sprint 8.7 | Replaced the flat `RunPhase` enum with the `RLRunPhase` data kind plus the phase-indexed singleton GADT `RLRunLifecycle` in `src/JitML/RL/Framework.hs`; updated `rlRunPlan`, `renderRLRunPhase`, and the `jitml-unit` consumer; `cabal test jitml-unit` keeps 57/57 passing. |
| Non-production Metal kernel-family scaffolds | Phase 14 Sprint `14.5` / Phase 15 validation sweep (2026-06-03) | Apple-side per-family weighted Metal bodies now run through the headless host path: CommandLineTools `swift build`, runtime `MTLDevice.makeLibrary(source:)`, no Tart VM and no full Xcode. The Apple export `jitml verify cross-backend --experiment experiments/mnist.dhall --backends apple-silicon --export /tmp/jitml-apple.json` produced the Sprint `15.1` weighted bundle with 8 tensor families (`identity`, `dense`, `conv2d`, `conv3d`, `batchnorm`, `layernorm`, `mha`, `embedding`), and the 2026-06-03 Linux/Apple report-bundle comparison passed every weighted family against the in-code tolerance table. |
| Deterministic MCTS prior stub | Phase 15 Sprint `15.3` cleanup (2026-06-03) | Removed `priorFor` from `JitML.RL.AlphaZero.Mcts`. `defaultPriorOracle` is now a neutral uniform mechanics oracle; production self-play and engine-backed paths continue to consume the position-dependent policy/value `netOracleFactory`. Unit coverage now asserts neutral default priors separately from a biased custom oracle. |
| Target-stanza-only report card | Phase 15 Sprint `15.2` implementation (2026-06-03 / validated 2026-06-04) | `JitML.Test.Report.ReportCard` now carries typed `ReportMeasurements`, and `jitml test all --live` appends SL/RL/AlphaZero/tune/cache/daemon/cross-substrate fields after Cabal stanzas pass. Unreachable live sources render as `unavailable`; parser/e2e coverage and generated CLI docs/manpage were updated. The 2026-06-04 fresh Apple live aggregate passed all eight report stanzas and captured populated measured fields for RL reward, AlphaZero win rate, tuning objective, JIT cache hit rate, and daemon health. |
| Numerical-content golden fixtures under `test/golden/` | Phase 15 Sprint `15.3` cleanup (2026-06-03) | Deleted the committed numerical fixture tree under `test/golden/{sl,rl,alphazero,tune}` and moved pure renderer snapshots to `test/snapshots/{cache,cli,cluster,observability,prerequisite}/`. SL/RL/AlphaZero/tune tests now assert run-to-run determinism, finite/non-empty summaries, and property invariants instead of golden numeric files; `forbiddenPathRegistry` rejects `test/golden/`. |
| Demo placeholder shell, local stream frames, and inline DOM stubs | Phase 15 Sprint `15.3` cleanup (2026-06-04) | Removed Playwright's inline DOM fallback; `playwright/jitml-demo.spec.ts` now requires live `cluster-publication.json` and drives the real browser bundle through the published edge route. `JitML.Web.Server` no longer renders the placeholder manifest shell, no longer serves deterministic `/api/ws*` HTTP frames, serves only the browser-loadable `web/dist/Main/bundle.js`, returns `503` for plain HTTP stream GETs that lack a WebSocket upgrade, and emits a terminal error frame when no live publication exists. `JitML.Service.Http` now forks one worker per accepted connection so held-open stream sockets do not block HTTP/bundle routes. Validation: `jitml-e2e` passed 19 / 19, `jitml check-code` passed, `jitml:local` rebuilt, `jitml-demo:local` was loaded into the live Apple Silicon Kind cluster, and the live Playwright matrix passed 7 / 7 against `127.0.0.1:9091`. |
| `JITML_*` run-parameter env-var IPC | Sprint `5.7` (closed 2026-05-29) | The daemon round-tripped typed run records (`StartTraining` / `StartSweep` / `StartRLRun`) through ~20 stringly-typed `JITML_*` Job env vars. Sprint `5.7` introduced typed `dhall/run/Schema.dhall` + `JitML.Service.RunConfig` and changed `JitML.Service.Workload.renderTrainingJob` / `renderTuneJob` / `renderRlJob` to emit a per-run ConfigMap + Job pair: the Job mounts `RunConfig.dhall` at `/etc/jitml/run/`. The worker (`JitML.App.runRl` / `runTune` / `attemptRealMnistTraining`) loads the typed config via `RunConfig.tryLoad{Rl,Tune,Training}RunConfig`, falling back to the legacy env vars for developer-side CLI runs outside a Job pod. Application Environment doctrine alignment. |
| Duplicate `JITML_SUBSTRATE` / `JITML_PULSAR_WS` env reads vs `BootConfig` | Sprint `5.7` (closed 2026-05-29) | `JitML.App.workerBrokerTarget` now mounts the shared `jitml-service-config` ConfigMap at `/etc/jitml/service/`, loads `BootConfig.dhall` for the substrate, and reads the Pulsar WebSocket URL from any mounted `RunConfig.dhall` variant. The legacy `JITML_SUBSTRATE` / `JITML_PULSAR_WS` env reads survive only as the developer-side CLI fallback. |
| Embedded `sh -c` retry/poll/existence control-flow (reconciler + readiness halves) | Sprints `2.9` + `4.8` (closed 2026-05-29) | Sprint `2.9` retired the reconciler half: `JitML.Cluster.Helm.kindCreateSubprocess` / `kindDeleteSubprocess` / `helmDependencyBuildSubprocess` became typed single-command subprocesses, and the postgres schema grant moved to typed Haskell IO in `JitML.Bootstrap.postgresSchemaGrantIO` (typed `kubectl` capture + typed `psql` exec). Sprint `4.8` retired the readiness half: `JitML.Cluster.Readiness.runMinioBucketReadinessIO` + `JitML.Cluster.PulsarBootstrap.runPulsarTopicCreatesIO` perform bounded retries in Haskell over typed leaf `kubectl exec ... mc` / `... pulsar-admin` subprocesses; the final-gate `minioBucketReadinessSubprocess` is a typed single command using the `MC_HOST_jitml-minio` env hand-off. `JitML.Bootstrap.liveExecutePhasedRollout` runs all four IO steps (minio buckets / postgres grants / pulsar topics) between the typed subprocess phases. |
| Pulumi ephemeral-Kind orchestrator + `toolchain.pulumi` prerequisite | Pulumi-removal cleanup (2026-05-28) | Pulumi was added in error — the project needs no external IaC orchestrator. Removed completely: deleted `infra/pulumi/` (`index.ts`, `package.json`, `Pulumi.yaml`); rewrote `JitML.Test.LivePlan.liveE2EPlan` to the Pulumi-free sequence `helm dependency build chart` → `jitml bootstrap` → `npx playwright test` → `jitml cluster down`; removed the `toolchain.pulumi` prerequisite node and its unit tests; deleted the Pulumi-only `JitML.Cluster.Kind.kindConfigForNamed` / `kindConfigForEdgePortNamed` and the `jitml internal render-kind-config` CLI command (the renderer uses the substrate-default cluster name); dropped the `infra/pulumi/node_modules/` lint-skip entry. Renamed the doctrine test category "Pulumi-Orchestrated Infrastructure" → "Ephemeral-Cluster Infrastructure" across the project README, `DEVELOPMENT_PLAN/`, and `documents/engineering/`. The ephemeral-cluster e2e orchestration is now the `jitml bootstrap` + `jitml cluster down` path (Sprints 13.1 / 13.14). |

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [development_plan_standards.md](development_plan_standards.md)
- [../README.md](../README.md)
