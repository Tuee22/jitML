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

Five cleanup rows are currently active. The scoped `allow-newer` block in
`cabal.project` keeps Dhall's transitive CBOR stack building under pinned
GHC `9.14.1` while upstream package bounds catch up; the other pending rows
record checked-in stand-ins that are deliberately keeping local test coverage
green until their owning live-runtime surfaces land. Six cleanup rows have
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
lifecycles share doctrine-aligned shape.

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
| Scoped `allow-newer` for Dhall / CBOR transitive package bounds | `cabal.project` | Upstream `dhall`, `cborg`, `cborg-json`, and `serialise` releases have not yet relaxed bounds for GHC `9.14.1`'s `base`, `template-haskell`, `containers`, `bytestring`, and `time`; remove once Hackage releases support the pinned toolchain without overrides | Sprint 1.1 / final handoff toolchain refresh |
| Non-production CUDA/Metal kernel-family scaffolds | `src/JitML/Codegen/Cuda.hs`, `src/JitML/Codegen/Metal.hs` | Several non-CPU kernel families intentionally render identity/scaffold bodies while the source payload, cache key, metadata ABI, and guarded CUDA loader boundary are validated; replace with real cuBLAS/cuDNN and Metal kernels when production non-CPU execution lands | Sprints 7.4, 7.5 |
| Deterministic MCTS prior stub | `src/JitML/RL/AlphaZero/Mcts.hs` | `priorFor` stands in for the real policy/value network call so MCTS and transposition-table tests are deterministic before AlphaZero uses JIT-backed network inference | Sprint 9.5 |
| Demo placeholder shell, local stream frames, and inline DOM stubs | `src/JitML/Web/Server.hs`, `playwright/jitml-demo.spec.ts`, `test/e2e/Main.hs` | The demo server falls back to a placeholder shell and deterministic local stream frames, while Playwright uses inline DOM stubs until the compiled Halogen bundle and live edge route are wired | Sprints 11.5, 11.6, 12.8 |
| Target-stanza-only report card | `src/JitML/Test/Report.hs`, `src/JitML/App.hs` | `jitml test all` now renders the actual target stanza names after Cabal succeeds, but live SL/RL/AlphaZero/tuning/daemon/cross-substrate measurements are still absent; extend the report with measured values from the live e2e path | Sprint 12.9 |

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
| Default runtime-source placeholder | Sprint 7.7 | Removed `defaultRuntimeSourcePayload` and the `runtime-source:phase-2-placeholder` marker from `src/JitML/Cache/Key.hs`; cache-key fixtures now derive their `RuntimeSourcePayload` from `renderRuntimeSource`, and `test/golden/cache/kernel-key.txt` was refreshed to the rendered-source-backed hash. |
| Standalone MinIO values fragment | Sprint 4.3 | Folded MinIO subchart values into `chart/values.yaml`, removed `chart/minio-values.yaml`, and made bootstrap delete legacy standalone values files during materialization. |
| RL run sequencing as a `RunPhase` enum instead of an `RLRunLifecycle` GADT | Sprint 8.7 | Replaced the flat `RunPhase` enum with the `RLRunPhase` data kind plus the phase-indexed singleton GADT `RLRunLifecycle` in `src/JitML/RL/Framework.hs`; updated `rlRunPlan`, `renderRLRunPhase`, and the `jitml-unit` consumer; `cabal test jitml-unit` keeps 57/57 passing. |

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [development_plan_standards.md](development_plan_standards.md)
- [../README.md](../README.md)
