# Phase 196: Re-validate the apple-silicon lane through the Tart-VM-built path

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Re-validate the apple-silicon lane through the Tart-VM-built path. Single-session phase migrated from legacy Sprint 16.7 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 196.1: Re-validate the apple-silicon lane through the Tart-VM-built path [✅ Done]

**Status**: Done (re-closed 2026-06-10 — live apple-silicon lane exercised through the VM-built path on Apple M1)
**Implementation**: `test/backends/Main.hs`, live apple-silicon lane
**Docs to update**: `documents/engineering/unit_testing_policy.md`, `documents/engineering/jit_codegen_architecture.md`

### Objective

Re-validate the live apple-silicon `jitml-backends` lane end-to-end through the
Tart-VM-built path — build in the `jitml`-managed VM, copy the dylib out, execute
on the host GPU — on real Apple hardware, per the Apple Silicon Tart-VM build-JIT
doctrine, now retired in favor of the fixed bridge (see
[../documents/engineering/apple_silicon_metal_headless_builds.md → Why Tart Is Not Viable](../documents/engineering/apple_silicon_metal_headless_builds.md#why-tart-is-not-viable)).

### Deliverables

- The four within-substrate Metal cases (identity bit-equality, weighted Dense2D
  determinism, live benchmark candidate runner) pass for real through the VM-built
  dylib with no skip sentinels.
- The stale "build runs inside the `jitml-build` Tart VM" comment in
  `test/backends/Main.hs` is corrected to the build-in-VM / execute-on-host story.

### Validation

- `jitml test jitml-backends --apple-silicon` (or
  `--test-options='-p apple-silicon'`) runs the VM build + host execution and
  passes; `jitml-unit` passes host-native.
- Container `jitml check-code` green.

### Validation State (2026-06-10)

- The stale "build runs inside the `jitml-build` Tart VM … logs a skip" comment in
  `test/backends/Main.hs` is corrected to the build-in-VM / copy-out /
  execute-on-host story with no skip (Sprint 16.6 removed the guards).
- Phases `1` / `2` / `5` code landed and validated; the VM boots headless on Apple
  M1.

### Live Closure (2026-06-10)

The live apple-silicon `jitml-backends` lane was re-validated end-to-end through
the Tart-VM-built path on the Apple M1 host. `jitml test jitml-backends
--apple-silicon` (which the orchestrator runs as `cabal test jitml-backends
--test-options '-p apple-silicon'` after the device-only Metal probe) drove the
in-VM `swift build` for each Metal kernel family, copied each `libJitMLMetal.dylib`
out of the VM, and executed it on the host GPU:

- **All 17 within-substrate apple-silicon cases PASS (62.84s, no skip sentinels).**
  This includes the four Metal cases the sprint owns: identity bit-equality across
  three runs (Sprint 16.2), weighted Dense2D bit-determinism across three runs
  (Sprint 16.5), the live Metal benchmark candidate runner (Sprint 16.3), and the
  weighted-family-vs-reference agreement; plus the Phase-4 device cases (MLP
  forward/backward/batched, PPO, DQN, QR-DQN, HER, DDPG, AlphaZero PolicyValueNet).
- `jitml-unit` 194 / 194 host-native; container `jitml check-code` green.
- The build VM's prior unreachability was a host-side `ctkd` (CryptoTokenKit)
  deadlock of the VZ auxiliary-storage decryption, not a code defect (see
  [phase-7 Sprint 7.10 → Live Closure](README.md#legacy-to-new-phase-map)).

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
