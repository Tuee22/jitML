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

Seven cleanup rows are currently active. The scoped `allow-newer` block in
`cabal.project` keeps Dhall's transitive CBOR stack building under pinned
GHC `9.14.1` while upstream package bounds catch up; five rows record
checked-in stand-ins that are deliberately keeping local test coverage
green until their owning live-runtime surfaces land (CUDA/Metal kernel
scaffolds, deterministic MCTS prior, demo placeholder shell, target
report-card stanza-only mode, and deterministic atari-subset RAM-state
stub awaiting a real ALE FFI binding); the seventh row schedules
deletion of the committed numerical fixture tree under `test/golden/`
and migration of its consumers to statistical / run-to-run / property
assertions per [../README.md → Snapshot targets → Numerical-fixture
prohibition](../README.md#snapshot-targets). Seven cleanup rows have
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
lifecycles share doctrine-aligned shape; and the 2026-05-28 Pulumi-removal
cleanup deleted the `infra/pulumi/` ephemeral-Kind orchestrator (added in
error), its `toolchain.pulumi` prerequisite, and the Pulumi-only Kind
name-override surface, leaving the `jitml bootstrap` + `jitml cluster down`
path as the ephemeral-cluster e2e orchestration.

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
| Scoped `allow-newer` for Dhall / CBOR transitive package bounds | `cabal.project` | Upstream `dhall`, `cborg`, `cborg-json`, and `serialise` releases have not yet relaxed bounds for GHC `9.14.1`'s `base`, `template-haskell`, `containers`, `bytestring`, and `time`; remove once Hackage releases support the pinned toolchain without overrides | Phase 15 Sprint `15.3` (final handoff toolchain refresh) |
| Non-production Metal kernel-family scaffolds | `src/JitML/Codegen/Metal.hs` | Apple-side Metal kernel-family bodies intentionally render identity/scaffold bodies pending the Apple Silicon validation host. The CUDA half closed 2026-05-27 (Sprint 13.11): `JitML.Codegen.Cuda.weightedFamilyImpl` now routes Dense2D / Conv2D / Conv3D / BatchNorm / LayerNorm / Embedding / MHA to real per-family weighted device kernels via `jitml_cuda_copy_and_launch_weighted`, validated by `cabal test jitml-cross-backend -p weighted` inside `jitml:local`. Metal-side closure waits on Phase 14's Apple validation host. | Phase 14 Sprint `14.5` (Metal) |
| Deterministic MCTS prior stub | `src/JitML/RL/AlphaZero/Mcts.hs` | `priorFor` stands in for the real policy/value network call so the bare MCTS / transposition-table *mechanics* unit tests stay deterministic without a network. Sprint 13.9 (2026-05-27 third → fifth sessions) closed the production self-play path against the real network: `JitML.RL.AlphaZero.PolicyValueNet` ships the two-headed policy/value network (`networkPolicyValue`), a real Connect-4 4-in-a-row terminal evaluator (`evaluateTerminal`), a differentiable forward + backward + Adam loop (`trainPolicyValueNetOnSamples`), and an arena win-rate loop against a uniform-random baseline (`arenaWinRateAgainstUniform`). `SelfPlay.runSelfPlayWithOracleFactory` threads a *per-position* oracle so `PolicyValueNet.runNetworkSelfPlay` drives the MCTS prior from the network's policy-head forward pass at every board position — the production AlphaZero self-play callsite no longer uses `priorFor`. (The earlier claim that this flip was blocked on `selfPlayTranscript` golden fixtures was incorrect: those transcripts come from the oracle-independent `selfPlayTranscriptFor` move generator; their removal is owned by the separate `test/golden/` fixture row, not this one.) `priorFor` survives only as `defaultPriorOracle` for the network-free MCTS mechanics tests. | Phase 13 Sprint `13.9` (production path closed; remaining residue is the `priorFor` default kept for network-free MCTS unit tests + full policy/value network *codegen* through nvcc, multi-week) |
| Demo placeholder shell, local stream frames, and inline DOM stubs | `src/JitML/Web/Server.hs`, `playwright/jitml-demo.spec.ts`, `test/e2e/Main.hs` | Sprint 13.13 (2026-05-27) closed the bulk of the demo Halogen + bridge work: all six panels (`Mnist`, `Cifar`, `Connect4`, `Rl`, `Training`, `Tune`) carry typed `State` / `Action` / `handleAction` / `render` machinery; the held-open WebSocket-upgrade bridge in `JitML.Service.WebSocket` + `JitML.Service.Http.WebSocketRoute` + `JitML.Web.Server.liveDemoWebSocketRoutes` forwards live Pulsar event-topic deliveries through a single TCP connection. Playwright's `loadLiveEdge()` reads `cluster-publication.json` and falls back to inline DOM stubs offline. What remains: a live render validation pass against the cluster (Sprint 13.14) confirming the panels populate from real broker frames, plus the small bundle-side glue that connects the browser's WebSocket `onmessage` handler to the typed `Action` values. | Phase 13 Sprints `13.13`, `13.14` |
| Target-stanza-only report card | `src/JitML/Test/Report.hs`, `src/JitML/App.hs` | `jitml test all` now renders the actual target stanza names after Cabal succeeds, but live SL/RL/AlphaZero/tuning/daemon/cross-substrate measurements are still absent; extend the report with measured values from the live e2e path | Phase 15 Sprint `15.2` |
| Numerical-content golden fixtures under `test/golden/` | `test/golden/{sl,rl,alphazero,tune,cross-backend}/`, any consumers under `test/*-canonicals/Main.hs`, `test/cross-backend/Main.hs` | The repo previously committed per-substrate numerical fixtures (SL convergence curves, RL trajectories, AlphaZero transcripts, sampler trial values, per-tensor cross-substrate deltas). These hardcode whichever host wrote the calibration into the repository as authoritative; jitML is a numerical-methods project where RNG and FP-reduction order vary across substrates, so committed fixtures give a false sense of correctness. Delete the directories, port consumers to statistical / run-to-run / property assertions per [../README.md → Snapshot targets → Numerical-fixture prohibition](../README.md#snapshot-targets), and add a `jitml lint files` rule that fails on any new file under `test/golden/`. Pure-renderer snapshot fixtures move to `test/snapshots/{cli,routes,grafana,cache,prerequisite,cluster,observability}/`. | Phase 12 Sprint `12.1` (rule + directory rename) and Sprint `12.3`–`12.6` (numerical-stanza ports) |
| Deterministic atari-subset RAM-state stub | `src/JitML/RL/Simulator.hs` (`atariSubsetEnvironment`, `atariSubsetStep`, `AtariSubsetState`) | Sprint `8.3` (closed 2026-05-25) ships a deterministic 128-byte RAM-state stub matching the canonical Atari action/obs surface while a real Arcade Learning Environment binding waits on (a) C++ FFI bindings via `inline-c-cpp` against `libale.so`, (b) ROM licensing handling for Atari 2600 titles (Stella ROMs are not redistributable; an `autorom`-style download flow or a single permissively-licensed homebrew ROM such as `tetris` must land alongside), and (c) baking `libale-dev`, `libsdl2-dev`, and `zlib1g-dev` into `jitml:local`. The deterministic stub preserves the action/obs contract so upstream RL primitives (`AlgorithmModule`, `VecEnv`, `RLLoop`) consume the real binding identically when it lands. | Phase 13 Sprint `13.6` (live RL training) or a successor cross-substrate cleanup sprint |

## Pending Removal Notes

Pending-removal rows normally resolve on the closure of the owning sprint
listed in the relevant phase document. Rows whose blocker is an external
upstream release still name the originating sprint, but resolve at the final
handoff toolchain refresh. Each row moves to `Completed` only when the
replacement is verified in the worktree.

Current `allow-newer` validation: after `cabal update` set Hackage index-state
`2026-05-21T09:04:39Z`, a temporary project file with the scoped
`allow-newer` block removed still fails dependency solving under pinned GHC
`9.14.1`, because `serialise-0.2.6.1` excludes the installed `base-4.22`.
The row remains pending.

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
| Lint-time host `ghcup` style-tool bootstrap | Sprint 1.4 | Removed runtime `ensureStyleTools` / `installStyleToolsSubprocess` bootstrap from `src/JitML/Lint/Stack.hs`; `docker/Dockerfile` now installs the style-tools GHC plus pinned `fourmolu` / `hlint`, stamps the `jitml:local` code-quality domain, and runs `jitml check-code` during image construction. |
| `jitml-mirror` Helm release placeholder | Sprint 3.5 | Removed the stand-in `HelmRelease "jitml-mirror" "jitml-images"` row from `JitML.Cluster.Helm.phasedReleases`; `JitML.Bootstrap.livePhasedRolloutSubprocesses` now inserts the Docker build / explicit Kind image-load subprocesses directly before final services. |
| Static JIT source/build scaffolds | Sprint 7.7 | Removed checked-in substrate build scripts and kernel source scaffolds; Haskell renderers emit compiler inputs under `./.build/jit-src/<substrate>/<hash>/` |
| Default runtime-source placeholder | Sprint 7.7 | Removed `defaultRuntimeSourcePayload` and the `runtime-source:phase-2-placeholder` marker from `src/JitML/Cache/Key.hs`; cache-key snapshot now derives its `RuntimeSourcePayload` from `renderRuntimeSource`, and `test/snapshots/cache/kernel-key.txt` was refreshed to the rendered-source-backed hash. |
| Standalone MinIO values fragment | Sprint 4.3 | Folded MinIO subchart values into `chart/values.yaml`, removed `chart/minio-values.yaml`, and made bootstrap delete legacy standalone values files during materialization. |
| RL run sequencing as a `RunPhase` enum instead of an `RLRunLifecycle` GADT | Sprint 8.7 | Replaced the flat `RunPhase` enum with the `RLRunPhase` data kind plus the phase-indexed singleton GADT `RLRunLifecycle` in `src/JitML/RL/Framework.hs`; updated `rlRunPlan`, `renderRLRunPhase`, and the `jitml-unit` consumer; `cabal test jitml-unit` keeps 57/57 passing. |
| Pulumi ephemeral-Kind orchestrator + `toolchain.pulumi` prerequisite | Pulumi-removal cleanup (2026-05-28) | Pulumi was added in error — the project needs no external IaC orchestrator. Removed completely: deleted `infra/pulumi/` (`index.ts`, `package.json`, `Pulumi.yaml`); rewrote `JitML.Test.LivePlan.liveE2EPlan` to the Pulumi-free sequence `helm dependency build chart` → `jitml bootstrap` → `npx playwright test` → `jitml cluster down`; removed the `toolchain.pulumi` prerequisite node and its unit tests; deleted the Pulumi-only `JitML.Cluster.Kind.kindConfigForNamed` / `kindConfigForEdgePortNamed` and the `jitml internal render-kind-config` CLI command (the renderer uses the substrate-default cluster name); dropped the `infra/pulumi/node_modules/` lint-skip entry. Renamed the doctrine test category "Pulumi-Orchestrated Infrastructure" → "Ephemeral-Cluster Infrastructure" across the project README, `DEVELOPMENT_PLAN/`, and `documents/engineering/`. The ephemeral-cluster e2e orchestration is now the `jitml bootstrap` + `jitml cluster down` path (Sprints 13.1 / 13.14). |

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [development_plan_standards.md](development_plan_standards.md)
- [../README.md](../README.md)
