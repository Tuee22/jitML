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

**2026-06-10 — real-workflow refactor (reopened; ledger non-empty).** A realness
audit found that every user-facing workload and the demo used a synthetic, echo,
or pure-Haskell-only stand-in instead of the substrate JIT path (`MlpDevice` →
compile → dlopen → real `jitml_mlp_*` kernels) that already exists and is
parity-tested in the `jitml-backends` lane. The refactor reopens Phases `8`–`12`
(code) and `13`–`15` (live validation) and enqueues Pending Removal rows — each
a concrete synthetic value or dead symbol the refactor deletes. **The ledger is
therefore non-empty and Exit Definition item 18 is no longer met**; the rows
close as each owning sprint verifies its replacement on its
substrate lane, and Sprint `15.6` re-asserts the empty-ledger gate. The primary
obligations (route each surface through `MlpDevice`, build the non-Dense2D weighted
bodies, add Conv2D/ResNet/ViT codegen) are **not** ledger rows — they are in the
owning sprints' `### Remaining Work` per rule C.

**2026-06-10 — Apple Silicon Tart-VM build-JIT doctrine reversal (reopened and
re-closed the same day).** All Apple Silicon Swift/Metal builds move back into a
`jitml`-managed Tart VM (build in the VM, copy the dylib out to the host, execute
on the host GPU), reversing the 2026-05-30 headless-host-build doctrine. This
reopened Phases `1` / `2` / `5` / `7` / `14` and enqueued six Pending Removal rows
covering the now-legacy headless-host build surface. **All six rows moved to
`Completed` on 2026-06-10** once the replacement was verified working: the live
apple-silicon `jitml-backends` lane ran end-to-end through the Tart-VM-built path
on Apple M1 (`jitml test jitml-backends --apple-silicon`, 17 / 17, in-VM
`swift build` + copy-out + host Metal execution, no skip sentinels). With those
rows closed the **ledger is empty again, Exit Definition item 18 (empty legacy
ledger) is met, and the final handoff is complete.** The prior environment block
(the "Tart guest agent unreachable / `tart exec` control-socket GRPC error"
symptom) traced to a stale host `ctkd` (CryptoTokenKit) daemon deadlocking the
Virtualization.framework auxiliary-storage decryption — a host-ops condition, not
a code defect — cleared by restarting `ctkd` and running the build VM in the host
GUI launchd session. The 2026-05-30 `Completed` rows that recorded the original
Tart deletion stay as historical fact; the 2026-06-10 rows track the reversal.

On 2026-06-08 the cross-substrate numeric parity surface removal reopened
Phases `1` / `12` / `13` / `14` / `15` and enqueued six Pending Removal rows: the
cross-substrate per-layer-family tolerance band, the cross-substrate parity
cohort / drift / report-bundle module, the `jitml verify cross-backend` CLI
command, the report-card `cross_substrate_parity` field, the `CrossSubstrate`
weighted-drift and cross-substrate tolerance-band test groups, and the test
skip-antipattern guards. The reproducibility contract is now within-substrate
bit-for-bit reproducible with no cross-substrate equivalence asserted. On
2026-06-09 the full source/code removal landed and **all six rows moved to
`Completed`** (validated by a clean host + container build, `jitml check-code`,
`jitml docs check`, `jitml-unit` 193 / 193, the `apple-silicon` lane 4 / 4, and
the `linux-cpu` lane 10 / 10). The last of the six — the `linux-cuda` half of the
skip-guard removal — closed the same day when its live GPU re-run landed on the
NVIDIA GeForce RTX 5090 host (Sprint `13.16`): `docker compose run --rm jitml-cuda
cabal test -fcuda jitml-cross-backend --test-options '-p linux-cuda'` passed
19 / 19 with no skip-sentinels. **The ledger was empty and Exit Definition
item 18 (empty legacy ledger) was met and the final handoff complete as of
2026-06-09 — both reopened on 2026-06-10 by the Tart-VM build-JIT doctrine
reversal noted above, which enqueued six new Pending Removal rows.** The 2026-06-05 Sprint `11.7`
doctrine-deviation row covering the SPA discoverability gap closed the
same day: the generated `Generated.AdminPortals` artifact, the
`Chrome.Header` / `PanelRegistry` / `Panels.Portals` modules, the
hash-router disposal path, and the live Playwright home/header/portal
matrix landed and validated against the Apple Silicon edge route. The
Sprint `1.12` doctrine-deviation
row that opened 2026-06-04 (missing CLI Dhall overrides on `train`,
`rl train`, `tune`) closed the same day after the
`JitML.Experiment.Overrides.applyOverrides` resolver, the new flag surface
on `CommandSpec`, and the regenerated CLI mirror landed; the row now lives
in the `Completed` table below. Sprint `1.11` downgraded the project to
the single GHC `9.12.4` baseline, removed the source-repository package pins
and local `third_party/haskell/lens-family-*` compatibility packages, and
validated a plain-Hackage solve. The former dependency source-pin/vendor helper
and the superseded reopened-phase development ledger now live in the
`Completed` table. Reopened Phase `11` Sprint `11.3` retired the deprecated
PureScript generic `runSpec` Node runner alias on 2026-06-04 by moving
`web/test/Main.purs` to the `spec-node` `runSpecAndExitProcess` API. Three rows
added 2026-05-29 record
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
Cleanup rows have closed and live in the `Completed` table:
Sprint `1.4` removed lint-time host `ghcup` style-tool bootstrap and moved the
style GHC/tool install plus `jitml check-code` gate into `jitml:local` image
construction and made lint/check-code execution container-only;
Sprint `3.5` removed the
`jitml-mirror` Helm placeholder and inserts the Docker build / explicit Kind
image-load phase directly in the live typed rollout; Sprint `4.3` folded the
standalone MinIO values fragment into `chart/values.yaml`; Sprint `7.7`
removed the static checked-in JIT source/build scaffold (JIT compiler inputs
are generated on demand by the Haskell binary; documented non-JIT runtime
adapters are not JIT compiler inputs) and removed the default runtime-source
placeholder fixture; Sprint `8.7` replaced the flat `RunPhase`
enum with the phase-indexed `RLRunLifecycle` GADT so all three jitML
lifecycles share doctrine-aligned shape; Sprint `8.8` retired the
deterministic atari-subset RAM-state stub with an explicit ROM-policy boundary,
and the later 2026-06-04 static-foreign-source correction removed the checked-in
ALE C++ shim and its Dockerfile/lint exception; the 2026-06-03 Phase `15` pass
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

**Reopened 2026-06-10 (real-workflow refactor — see
[README.md → Reopened phases (2026-06-10)](README.md#reopened-phases-2026-06-10--real-workflow-refactor)).**
The ledger is **non-empty again**: a realness audit found that every user-facing
workload and the demo used a synthetic/echo/dead-code stand-in instead of the
substrate JIT path. The rows below are the concrete synthetic values and dead
symbols the refactor **deletes** (rule I temporary stand-ins / rule L doctrine
deviations). Each moves to `Completed` only when its replacement — routing the
surface through the substrate `MlpDevice` / real weighted kernel — is verified in
the worktree on the owning sprint's lane. The primary obligations themselves
("route X through `MlpDevice`", "build the non-Dense2D weighted bodies",
"Conv2D/ResNet/ViT JIT codegen") are **not** rows here — they live in the owning
sprint's `### Remaining Work` per standards rule C. While any row is `Pending`,
**Exit Definition item 18 is unmet and the final handoff is incomplete**; Sprint
`15.6` walks the rows to `Completed`.

| Stand-in / dead code to delete | Location | Reason (rule I / L) | Owning sprint |
|---|---|---|---|
| Vacuous-pass integration `-p Live` asserts + model-less e2e asserts | `test/integration/Main.hs`, `test/e2e/Main.hs` | Sprint 12.11 added `JitML.Test.WorkflowMatrix` (the DRY enumeration of the 8 reopened workflows × every substrate, each with its canonical command) and a host-validatable e2e coverage assertion. The residual work is wiring the Live tests to **iterate** the matrix and execute each cell fail-closed against a live cluster — owned by the live per-lane sprints (13/14/15). | 12.11 / 13 |

New rows are enqueued here only when a future sprint introduces a doctrine
deviation or a temporary stand-in (per standards rule I / L).


## Pending Removal Notes

Pending-removal rows normally resolve on the closure of the owning sprint
listed in the relevant phase document. Rows whose blocker is an external
upstream release still name the originating sprint, but resolve at the final
handoff toolchain refresh. Each row moves to `Completed` only when the
replacement is verified in the worktree.

On 2026-06-11 Sprint `11.8` closed the demo endpoint and browser-value
assertion rows on the CUDA machine. `Web.Server` now renders policy/value output
for `/api/inference`, MCTS output for `/api/connect4/move`, and a policy-network
top-k response for `/api/images`; the PureScript panels issue live fetches and
parse the replies; and the Playwright Docker image ran the live edge suite
**9 / 9** after the rebuilt `jitml:local` / `jitml-demo:local` images were
loaded into the `linux-cuda` Kind cluster and both deployments were
rollout-restarted. The same rebuilt source passed `docker compose build jitml`
(`check-code: ok` plus PureScript bundle) and
`docker compose run --rm jitml-cuda jitml test jitml-e2e --linux-cuda`
(**20 / 20**).

On 2026-06-10 the Phase 8 SL/RL substrate-routing session landed and verified
the code removal for four of the synthetic rows; they moved to `Completed`
below after the `jitml:local` container `--linux-cpu` boundary run confirmed the
device replacement executing the real oneDNN kernel. The 2026-06-11 source
cleanup removed the residual SL synthetic helpers and production trajectory LCG,
then revalidated the narrowed canonical stanzas (`check-code: ok`,
`jitml-sl-canonicals` 15 / 15 with the device-convergence case `OK (0.75s)`,
`jitml-rl-canonicals` 27 / 27 with the on-device PPO case `OK (0.75s)`):

- The `final_loss` synthetic print + `fromMaybe (SL.finalLoss …)` publish
  fallback, `attemptRealMnistTraining` / `attemptFetchTrainingDataset`, and the
  `runEval` echo stub are deleted from `src/JitML/App.hs`; `jitml train` now
  routes through `runDeviceMnistTraining` (mandatory live publication + staged
  dataset + `trainClassifierWithDevice`, fail-closed `TrainingPrerequisiteUnmet`)
  and `runEval` runs the substrate weighted device forward.
- The `"simulator"` scripted default trainer is removed from the `runRl`
  dispatch (default → `ppo`, unknown → `InvalidConfig`); `runTrainerEpisodes`
  routes every MLP-backed trainer through `rlDeviceForSubstrate` behind a
  fail-closed `probeMlpDevice` gate.

On 2026-06-11 the residual synthetic SL symbols and dead deterministic SL
pipeline were deleted as source, and the old trajectory-helper assertion moved
to the registered real-environment rollout surface.

On 2026-06-08 the cross-substrate numeric parity surface removal reopened
Phases `1` / `12` / `13` / `14` / `15` and enqueued six Pending Removal rows.
The reproducibility contract is clarified to within-substrate bit-for-bit
reproducible with no cross-substrate equivalence asserted, so the cross-substrate
numeric parity surface (tolerance band, parity module, `jitml verify
cross-backend`, the report-card `cross_substrate_parity` field, the weighted-drift
and tolerance-band test groups, and the test skip-antipattern guards) leaves the
contract. On 2026-06-09 the **entire source/code removal landed and was
validated**: five of the six rows moved to `Completed` (tolerance band, parity
module, `jitml verify cross-backend`, the report-card field, and the
weighted-drift / tolerance-band test groups), each verified by a clean host +
container build, `jitml check-code`, `jitml docs check`, `jitml-unit` 193 / 193,
the `apple-silicon` lane (4 / 4) and the `linux-cpu` lane (10 / 10). The **sixth
and final row** — the `linux-cuda` half of the skip-guard removal — closed the
same day (Sprint `13.16`): the live GPU re-run landed on the NVIDIA GeForce RTX
5090 host via the GPU-attached `jitml-cuda` compose service
(`docker compose run --rm jitml-cuda cabal test -fcuda jitml-cross-backend
--test-options '-p linux-cuda'` → 19 / 19, no skip-sentinels). **All six rows are
`Completed`, the ledger is empty, Exit Definition item 18 is met, and the final
handoff is complete.**

Current dependency validation: on 2026-06-04, the project uses GHC `9.12.4`,
`cabal.project` contains no `allow-newer` stanza and no `source-repository-package`
entries, and the local `third_party/haskell/lens-family-*` packages have been
removed. A container-local `cabal build all --dry-run --jobs=2` solves against
plain Hackage with `serialise-0.2.6.1`, `cborg-0.2.10.0`, `dhall-1.42.3`,
`lens-family-2.1.3`, and `lens-family-core-2.1.3`.

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
| Demo endpoint `/api/images` placeholder and live-cluster round-trip residue | Sprint `11.8` / Phase `13` (2026-06-11) | `src/JitML/Web/Server.hs` now routes `/api/images` to `renderImageResponse`, which returns the policy-network top-k vector rather than an upload acknowledgement. After `docker compose build jitml` passed `check-code: ok` and rebuilt the PureScript bundle, `jitml:local` and `jitml-demo:local` were loaded into the `linux-cuda` Kind cluster, `jitml-service` / `jitml-demo` were rollout-restarted, and the Playwright Docker image passed **9 / 9** against the published edge. |
| DOM-only Playwright panel assertions | Sprint `11.8` / Phase `13` (2026-06-11) | `playwright/jitml-demo.spec.ts` now clicks the MNIST, CIFAR/ImageNet, and Connect 4 controls, waits for `POST /api/inference`, `POST /api/images`, and `POST /api/connect4/move`, and asserts rendered value updates instead of only panel visibility. The live CUDA edge run passed **9 / 9**, and `docker compose run --rm jitml-cuda jitml test jitml-e2e --linux-cuda` passed **20 / 20** after the same rebuild. |
| PureScript panel no-fetch / raw-stream cleanup | Sprint `11.8` (2026-06-11) | Added `web/src/Panels/Api.{purs,js}` for real text requests, wired MNIST / CIFAR / Connect4 button actions to `/api/inference`, `/api/images`, and `/api/connect4/move`, removed raw `LiveFrame String` storage from the RL/training/tune panels, and changed `web/src/Panels/Stream.js` to report WebSocket errors through typed actions instead of swallowing them. Validated with `docker compose run --rm jitml jitml lint purescript` (`ok`). |
| `inferFromManifest` faithful read and default manifest-only inference helpers | Sprint `10.5` (2026-06-11) | Deleted `inferFromManifest` from `src/JitML/Checkpoint/Format.hs`; removed `Checkpoint.Store`'s default `inferFromLatestCheckpoint`, `inferWeightsOnlyFromLatestCheckpoint`, and `loadInferenceCheckpoint` wrappers; changed `Service.Workload` default inference to fail closed with `weighted inference runner required`; and kept only explicit injected-runner / weighted APIs (`loadInferenceCheckpointWith`, `loadInferenceCheckpointWithWeights`). Validated in the container: `jitml test jitml-unit --linux-cpu` 196 / 196, `jitml test jitml-daemon-lifecycle --linux-cpu` 31 / 31, and focused offline `jitml-integration` cases for `loadInferenceCheckpointWithWeights` and HasMinIO conditional checkpoint writes passed. |
| Synthetic SL final loss + convergence curve (`finalLoss` / `convergenceCurve` / `baseLoss`) and dead deterministic SL pipeline (`SL.Train` / `SL.Loop`) | Sprint `8.10` (2026-06-11) | Removed the closed-form geometric loss helpers from `src/JitML/SL/Canonicals.hs`, deleted `src/JitML/SL/Train.hs` and `src/JitML/SL/Loop.hs`, removed them from `jitml.cabal`, and rewired `jitml-sl-canonicals` away from deterministic-curve assertions to the canonical catalog, Dense-MLP device-trainable cohort, classifier, and report-card knob checks. The published training path already routes through `runDeviceMnistTraining` and `trainClassifierWithDevice`. |
| `rl rollout` `deterministicTrajectory` production LCG helper | Sprint `9.9` (2026-06-11) | Removed `deterministicTrajectory` from `src/JitML/RL/Algorithms.hs` and changed the canonical PPO rollout determinism test to use the registered `moduleRolloutGenerator` over `JitML.RL.Algorithms.Common.trajectoryRollout`, which steps real named environment dynamics. The CLI `rl rollout` already runs `runDeviceRollout` through the selected substrate device and fails closed when unavailable. |
| `trajectoryRollout` / `moduleRolloutGenerator` LCG rollout registry | Sprint `9.9` (2026-06-11) | `JitML.RL.Algorithms.Common.trajectoryRollout` (the generator every algorithm module registers) now steps the **real** named environment dynamics via `JitML.RL.SimulatorLoop.realRolloutByName` for the rollout horizon with a deterministic seeded policy, returning the real per-step actions + rewards — replacing the shared per-algorithm LCG. Deterministic given the seed. Host lib type-checks; the `jitml-rl-canonicals` per-algorithm rollout cases (determinism + non-empty rewards) hold under real env dynamics. The substrate-device-backed /trained/ policy rollout is the Phase 13 live follow-on. |
| Per-trainer mid-run pure device fallback (`dqnUpdateDevice` and peers) | Sprint `8.11` (2026-06-11) | The four device updaters (`DqnTrainer` / `QrDqnTrainer` / `ContinuousTrainer` / `HerTrainer`) no longer silently fall back to the pure update on a mid-run device `Left` — they fail closed with a descriptive error. The dispatch-level `probeMlpDevice` gate confirms the kernel runs before training, so the branch is unreachable in practice; removing it leaves no pure-Haskell fallback on any runtime path. Host lib type-checks; container `check-code` validated. |
| AlphaZero one-ply MCTS bandit + dead `Arena` / `EnginePrior`, and the `Tune.deterministicTrials` LCG objective | Sprints `9.10` / `9.11` (2026-06-10) | `src/JitML/RL/AlphaZero/Mcts.hs` is rewritten as a real recursive tree search: each simulation descends from the root by PUCT to an unexpanded leaf, expands it with the position's network priors, evaluates the leaf through the network __value head__, and backs the value up the path with the adversarial sign flip (depth-bounded). The `PriorOracle` is now position-aware (`[Int] -> NodeEval`); `PolicyValueNet.netOracleFactory` roots it at the search position. `src/JitML/RL/AlphaZero/Arena.hs` and `EnginePrior.hs` (dead modules) are deleted and dropped from the cabal. `Tune.deterministicTrials` now returns __real measured objectives__ (`trialObjective`: train the reference classifier with the sampled hyperparameters, return the normalised cross-entropy loss), not a per-sampler LCG. **Verified working**: host `jitml-unit` 196/196 (migrated MCTS oracle case), `jitml-rl-canonicals` 27/27 (real-search determinism + valid search-derived visit distribution after the production rollout-LCG deletion), `jitml-hyperparameter` 14/14 (distinct per-sampler real objectives); container `check-code: ok`. Substrate-device-backed MCTS leaf eval + live trial executor are Phase 13 (Sprint 13.10) follow-ons. |
| SL/RL synthetic CLI surfaces — `final_loss` print + `fromMaybe (SL.finalLoss …)` publish, `attemptRealMnistTraining` / `attemptFetchTrainingDataset` Maybe-fallback, `runEval` echo stub, and the `"simulator"` scripted non-learning default trainer | Sprints `8.10` / `8.11` (2026-06-10) | `src/JitML/App.hs` `runTrain` now delegates to `runDeviceMnistTraining` (mandatory live publication + staged dataset + `JitML.SL.Classifier.trainClassifierWithDevice` through `mlpDeviceForSubstrate`, fail-closed `TrainingPrerequisiteUnmet`); `runEval` runs the substrate weighted device forward (missing checkpoint → `InferenceCheckpointMissing`); `runRl` defaults the trainer to `ppo` and dispatches every MLP-backed trainer through `rlDeviceForSubstrate` behind a fail-closed `probeMlpDevice` gate (unknown trainer → `InvalidConfig`). **Verified working** in `jitml:local`: `check-code: ok`, `jitml test jitml-sl-canonicals --linux-cpu` 15 / 15 (device-convergence case `OK (0.75s)` ran the real oneDNN kernel after residual SL helper deletion), `jitml test jitml-rl-canonicals --linux-cpu` 27 / 27 (on-device PPO case `OK (0.75s)` after production rollout-LCG deletion); host `jitml-unit` 196 / 196 and the `jitml-integration` offline-`jitml train` fail-closed assertion pass. ARS remains the lone no-MLP exception. |
| Host `swift build` for the Apple glue dylib | Sprint `7.10` (2026-06-10) | `src/JitML/Engines/Engine.hs` `compileSubprocess` `AppleSilicon` now dispatches `swift build` into the `jitml`-managed Tart VM via `tartExecSubprocess` against the shared-mount `guestSourcePath`. Verified working: the live apple-silicon lane built each Metal kernel family in the VM (Xcode 16 `swift-build`) and the host executed the copied-out dylib (`jitml test jitml-backends --apple-silicon`, 17 / 17). |
| Host-side artifact read | Sprint `7.10` (2026-06-10) | `src/JitML/Engines/Loader.hs` `publishAppleArtifact` copies `libJitMLMetal.dylib` **out of the VM's** `.build/release/` (host-visible via the shared mount) into the content-addressed cache (atomic `tmp + rename`) and repoints the stable FFI symlink. Verified by the live lane's first cache-miss case (39.55s) producing a working host dylib. |
| Host-based Metal toolchain fingerprint | Sprint `7.10` (2026-06-10) | `src/JitML/Engines/MetalLocal.hs` `metalToolchainFingerprint` keys on `metal-build-vm-runtime-makelibrary` (VM-based) rather than the host toolchain. |
| Host `swiftc`/`metal` requirement in the runtime probe | Sprint `7.10` (2026-06-10) | `src/JitML/Engines/MetalRuntime.hs` `metalRuntimeAvailable` gates on a visible host Metal device only (no host `swiftc`/`metal`). The `jitml test --apple-silicon` device-only precondition probe passed on Apple M1, and `jitml-unit`'s Metal-probe regression (device-visible + no host toolchain ⇒ available) is green. |
| `container.apple-silicon.jit-cache-miss` → `container.tart` dependency | Sprint `2.11` (2026-06-10) | `src/JitML/Prerequisite/Nodes/Container.hs` cache-miss node depends on the reinstated `container.tart` node + VM lifecycle (the `container.tart` closure flip is unit-validated and the live VM lifecycle ran for the apple-silicon lane). |
| Delete-only Tart cleanup | Sprint `2.11` (2026-06-10) | `bootstrap/_lib.sh` `purge_state` performs the full Tart VM lifecycle (create/start/stop/delete) rather than a delete-only residue. |
| Test skip-antipattern guards — `linux-cuda` half re-validation | Sprint `13.16` (2026-06-09) | The skip branches (`probeCudaRuntime` / `cudaRuntimeAvailable`, `appleLiveReady`, `cublasBindingsCompiledIn` / `cudnnBindingsCompiledIn`) and the integration-probe oneDNN-availability assertion were deleted from `test/cross-backend/Main.hs` and `test/integration/Main.hs` on 2026-06-08/09; a missing toolchain now fails by design. The final gate — the live `linux-cuda` re-run on real NVIDIA hardware — landed 2026-06-09 on the NVIDIA GeForce RTX 5090 host (UUID `GPU-e764ef97-32d7-4981-c348-029983c64073`) via the GPU-attached `jitml-cuda` compose service: `docker compose run --rm jitml-cuda cabal test -fcuda jitml-cross-backend --test-options '-p linux-cuda'` passed **19 / 19 (12.26s, no skip-sentinels)**, every within-substrate CUDA case a real device PASS (`nvidia-smi -L` reported the matching RTX 5090). With the guards removed, a build without `-fcuda` would hard-FAIL the cuBLAS / cuDNN cases rather than skip them. This was the last open Pending Removal row; with it closed the ledger is empty and Exit Definition item 18 is met. |
| Cross-substrate per-layer-family tolerance band | Sprint `15.4` (2026-06-09) | `src/JitML/Engines/Tolerance.hs` deleted and removed from `jitml.cabal`. Cross-substrate numeric parity left the contract (within-substrate bit-for-bit only; cross-substrate equivalence is not asserted). Validation: project + all test stanzas compile/link clean host-native and under the in-container `-fcuda` library build; container `jitml check-code` and `jitml docs check` green. |
| Cross-substrate parity cohort / drift / report-bundle module | Sprint `15.4` (2026-06-09) | `src/JitML/CrossBackend/Parity.hs` deleted and removed from `jitml.cabal`; the last consumers (`App.hs` `measureCrossSubstrateParity`, the cross-backend `CrossSubstrate` group) were removed in the same change. Validation: `jitml check-code` + `jitml docs check` green; `jitml-unit` 193 / 193. |
| `jitml verify cross-backend` CLI command | Sprint `1.13` (2026-06-09) | The `verify` → `cross-backend` leaf removed from `src/JitML/CLI/Spec.hs` and `runVerifyCrossBackend` + helpers removed from `src/JitML/App.hs`. `jitml docs generate` regenerated the README registry/tree, `documents/cli/commands.md`, `documents/engineering/cli_command_surface.md`, the manpage, and the bash/zsh/fish completions with no `verify cross-backend` leaf. Validation: `jitml docs check` (host + container) and container `jitml check-code` green; `jitml-unit` 193 / 193 (leaf-path enumeration drops the leaf). |
| Report-card `cross_substrate_parity` field | Sprint `12.10` (2026-06-09) | `measuredCrossSubstrateParity` removed from `ReportMeasurements` (`src/JitML/Test/Report.hs`) and `measureCrossSubstrateParity` plus its call site removed from `src/JitML/App.hs`. The `jitml test all --live` report card no longer renders a `cross_substrate_parity` line. Validation: `jitml-unit` 193 / 193; container `jitml check-code` green; the `apple-silicon` (4 / 4) and `linux-cpu` (10 / 10) report cards render without the field. |
| `CrossSubstrate` weighted-drift test group + cross-substrate tolerance-band unit test group | Sprint `12.10` (2026-06-09) | The `CrossSubstrate weighted drift assertions` group removed from `test/cross-backend/Main.hs`; the `Cross-substrate tolerance bands` group removed from `test/unit/Main.hs`; the two substrate-agnostic cross-backend cases relocated into the `jitml-unit` `Backend-agnostic engine + manifest invariants` group. Validation: `jitml-unit` 193 / 193 (incl. the relocated group); `apple-silicon` lane 4 / 4 and `linux-cpu` lane 10 / 10 each select only their substrate's cases with no skip-sentinels. |
| MNIST as default empty-hash landing; absent SPA discoverability for Envoy-routed admin portals | Reopened Phase 11 Sprint `11.7` (2026-06-05) | `src/JitML/Routes.hs` now carries `routeAdminPortalLabel` metadata and `adminPortalRoutes` for the six Envoy-routed admin portals. `src/JitML/Web/AdminPortals.hs` renders the tracked `web/src/Generated/AdminPortals.purs` artifact. `web/src/Chrome/Header.purs`, `web/src/PanelRegistry.purs`, and `web/src/Panels/Portals.purs` add the shared header, SPA-side panel registry, and default portals home. `web/src/Main.purs` routes empty / unmatched hashes to the portals home and runs the previous Halogen disposer before mounting a new hash route. Existing panels prepend `Chrome.Header.render`; `web/test/Main.purs` covers the generated portal array; live Playwright covers the empty-hash home, admin-portal hrefs, shared header across panels, and six panel hashes. Validation: `docker compose build jitml`, `jitml docs check`, `jitml-unit`, `jitml-integration`, `spago test`, `jitml check-code`, Apple Silicon `./bootstrap/apple-silicon.sh up` + `run-daemon`, and live Playwright 9 / 9 against `127.0.0.1:9091` pass. |
| Missing CLI Dhall overrides on `train`, `rl train`, `tune` | Reopened Phase 1 Sprint `1.12` (2026-06-04) | `src/JitML/CLI/Spec.hs` now accepts `--substrate` / `--seed` on `trainCommand` and the `rl train` subcommand, and `--sampler` / `--scheduler` / `--pruner` / `--trials` / `--parallelism` on `tuneCommand`. Values resolve through the pure `JitML.Experiment.Overrides.applyOverrides` (new module `src/JitML/Experiment/Overrides.hs`) before validation, substituting on the named axis only per README pillar 2. The substrate parser at `src/JitML/Substrate.hs` rejects bare `cpu` / `cuda` aliases; the canonical identifiers `apple-silicon` / `linux-cpu` / `linux-cuda` are the only accepted forms. `jitml docs generate` regenerated the README registry/tree blocks, `documents/cli/commands.md`, the `cli-commands.help-blocks` and `cli-commands.reference` sections in `documents/engineering/cli_command_surface.md`, `share/man/man1/jitml.1`, and the bash/zsh/fish completions. The two stale README example forms (`inspect frontier --tuning-run/--pareto`, `--backends cpu,cuda`) were repaired in the same change. Validation: `jitml docs check` exits 0; 195/195 `jitml-unit` (11 new Sprint 1.12 cases); 14/14 `jitml-hyperparameter` (2 new cases including the catalog round-trip and pillar-2 axis-only substitution); the `jitml-integration` spawned-binary matrix exercises `train`/`tune` override summaries and rejects bare `--substrate cpu`; the container `jitml check-code` gate passes. |
| Tart VM build/lifecycle/exec modules, `jitml internal vm` command group, `container.tart` prerequisite, `LiveConfig.tartIdleTimeout`, and the offline `.metallib` codegen path | Sprints `7.8` + `2.10` + `5.8` (2026-05-30) | The headless Apple Metal JIT (host CommandLineTools `swift build` + runtime `MTLDevice.makeLibrary(source:)`, validated headless on Apple M1) superseded the Tart-VM build. Deleted `src/JitML/Tart/{Build,Lifecycle,Exec}.hs`; removed the `jitml internal vm bootstrap\|up\|down\|status\|exec` command group from `CommandSpec` + `App.hs` handlers (commands.md/man/completions regenerated); removed the `container.tart` prerequisite node + its `jit-cache-miss` dependency; removed `LiveConfig.tartIdleTimeout` from the Dhall schema + Haskell record + `daemon.surface` table; dropped the `.process("Kernels.metal")` resource, the `<hash>.metallib` publication, and the `JITML_METALLIB_PATH` env hand-off. `cabal build all` clean; 183 `jitml-unit` + 30 `jitml-daemon-lifecycle` + the Apple `jitml-cross-backend` cases pass. |
| Lint-time host `ghcup` style-tool bootstrap | Sprint 1.4 | Removed runtime `ensureStyleTools` / `installStyleToolsSubprocess` bootstrap from `src/JitML/Lint/Stack.hs`; `docker/Dockerfile` now builds pinned `fourmolu` / `hlint` with the same image-local GHC `9.12.4`, stamps the `jitml:local` code-quality domain, and runs `jitml check-code` during image construction. |
| Scoped `allow-newer` for Dhall / CBOR / lens-family transitive package bounds | Sprint `1.10` (2026-06-04) | Removed the `allow-newer` stanza from `cabal.project`. The temporary source-pin/vendor replacement used to keep the package set solving was removed by Sprint `1.11`; the current `cabal.project` solves from plain Hackage under GHC `9.12.4`. |
| Dependency source-pin/vendor helper for the GHC `9.12.4` downgrade | Sprint `1.11` / Phase `15` Sprint `15.3` (2026-06-04) | Removed the upstream `cborg` / `dhall-haskell` source-repository pins from `cabal.project`, deleted the local `third_party/haskell/lens-family-*` packages, and changed the package baseline to GHC `9.12.4` / `base-4.21`. Plain Hackage now solves for `serialise`, `cborg`, `dhall`, and `lens-family`; the helper no longer gates final handoff. |
| Reopened-phase development ledger | Sprint `1.11` / Phase `15` Sprint `15.3` (2026-06-04) | Deleted the superseded development ledger and folded reopened-phase status back into the owning phase documents and the top-level plan. The deletion ledger remains the only explicit legacy ledger. |
| Deprecated PureScript generic `runSpec` Node runner alias | Reopened Phase `11` Sprint `11.3` (2026-06-04) | Replaced `Test.Spec.Runner.runSpec` plus `launchAff_` in `web/test/Main.purs` with `Test.Spec.Runner.Node.runSpecAndExitProcess`, added `spec-node` to `web/spago.yaml`, ignored the runner's `.spec-results` state in `web/.gitignore`, and validated `docker compose run --rm jitml sh -lc 'cd web && spago test'` at 7 / 7 with zero PureScript warnings. |
| `jitml-mirror` Helm release placeholder | Sprint 3.5 | Removed the stand-in `HelmRelease "jitml-mirror" "jitml-images"` row from `JitML.Cluster.Helm.phasedReleases`; `JitML.Bootstrap.livePhasedRolloutSubprocesses` now inserts the Docker build / explicit Kind image-load subprocesses directly before final services. |
| Static JIT source/build scaffolds | Sprint 7.7 | Removed checked-in substrate build scripts and kernel source scaffolds; Haskell renderers emit compiler inputs under `./.build/jit-src/<substrate>/<hash>/`. The static-source lint rejects future native compiler inputs and adapter shims; there is no checked-in foreign-source allowlist. |
| Default runtime-source placeholder | Sprint 7.7 | Removed `defaultRuntimeSourcePayload` and the `runtime-source:phase-2-placeholder` marker from `src/JitML/Cache/Key.hs`; cache-key snapshot now derives its `RuntimeSourcePayload` from `renderRuntimeSource`, and `test/snapshots/cache/kernel-key.txt` was refreshed to the rendered-source-backed hash. |
| Deterministic atari-subset RAM-state stub | Reopened Phase 8 Sprint `8.8` (2026-06-04) | Removed the deterministic 128-byte RAM-state production stand-in from `src/JitML/RL/Simulator.hs` and routed `atari-subset` through `JitML.RL.ALE` with typed `RunConfig.atariRomPath`, explicit `JITML_ATARI_ROM` / `JITML_ALE_ROM` fallbacks, ignored `./.roms/` local ROM storage, and a fail-closed no-ROM diagnostic. The checked-in C++ adapter used during the first ALE validation was later removed by the static-foreign-source correction below. ROM-backed ALE smoke is optional/manual and was not part of required validation. |
| Checked-in ALE C++ shim and lint exception | Static-foreign-source correction (2026-06-04) | Deleted `csrc/jitml_ale_shim.cpp`, removed the Dockerfile compile step that produced `/usr/local/lib/libjitml_ale_shim.so` from checked-in source, removed the one-file `src/JitML/Lint/Stack.hs` allowlist, and updated `src/JitML/RL/ALE.hs` to describe a generated or externally supplied runtime shim. The repository now has no checked-in C/C++ ALE adapter source; any future project-owned adapter must be generated by Haskell into the build/cache tree. Validation: `docker compose run --rm jitml jitml check-code` passes after this correction. |
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
