# Phase 88: Fixed host Metal bridge and source-metadata Apple cache

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Fixed host Metal bridge and source-metadata Apple cache. Single-session phase migrated from legacy Sprint 7.11 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 88.1: Fixed host Metal bridge and source-metadata Apple cache [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Engines/{MetalBridge,MetalLocal,MetalRuntime,Engine,Loader}.hs`, `src/JitML/Codegen/{Metal,RuntimeSource}.hs`
**Docs to update**: `documents/engineering/jit_codegen_architecture.md`, `documents/engineering/apple_silicon_metal_headless_builds.md`, `documents/engineering/determinism_contract.md`, `system-components.md`

### Objective

Replace per-kernel generated Swift packages and Tart/SwiftPM cache misses with a
fixed host Metal bridge that runtime-compiles generated MSL source through the
OS Metal framework. Adopts `Built-artifact and JIT-cache discipline`,
`Subprocesses as typed values`, and `Toolchain pinning` from
[../README.md](../README.md).

### Deliverables

- Add `JitML.Engines.MetalBridge` exposing a stable Haskell-facing ABI over the
  fixed bridge: probe, source compile, pipeline creation, buffer binding,
  dispatch, wait, and structured error capture.
- Replace `GeneratedMetalPackage` / Swift package rendering with a canonical MSL
  source renderer and launch-metadata encoder whose persistent cache artifact is
  `./.build/jit/apple-silicon/<hash>.metal.json`.
- Remove the Apple `compileSubprocess` / `tart exec swift build` branch from the
  core cache-miss path. Filling an Apple cache miss writes source metadata; the
  bridge compiles the MSL in-process on first use.
- Replace generated-dylib `dlopen` in `MetalLocal` with bridge calls and an
  in-process pipeline cache keyed by `(device-registry-id, source-sha256,
  function-name, launch-policy)`.
- Key Apple toolchain fingerprints on bridge ABI, OS/Metal runtime policy,
  rendered MSL, launch metadata, determinism options, and tuning choice.

### Validation

- A headless bridge probe compiles and dispatches a tiny MSL kernel with
  `xcrun -find metal` failing and no usable login keychain.
- `jitml test jitml-backends --apple-silicon` fills a fresh cache miss as
  `<hash>.metal.json`, runs identity/weighted kernels through the fixed bridge,
  and proves same-substrate bit-equality.
- `tart`, `swift build`, and the offline `metal` compiler are not invoked by
  `jitml service`, `jitml train`, `jitml inference run`, or the Apple backend
  tests.
- Container `jitml check-code`, `jitml docs check`, and relevant host-native
  `jitml-unit` / backend tests pass.

### Validation State (2026-06-12)

- `cabal run exe:jitml -- internal install-metal-bridge` built
  `.build/host/apple-silicon/libJitMLMetalBridge.dylib` and the bridge probe
  returned `ok`.
- `cabal test jitml-unit` passed 195 / 195, including the Apple source-metadata
  cache-fill regression and Metal metadata renderer checks.
- `cabal test jitml-daemon-lifecycle` passed 33 / 33, including the fixed
  Apple Metal acquire status.
- Focused backend checks passed through the fixed bridge:
  `apple-silicon kernel output is bit-equal`, `apple-silicon weighted Dense2D`,
  and the Metal MLP forward/backward/batched/determinism cases.
- `jitml test jitml-backends --apple-silicon` passed all 17 / 17 apple-silicon
  cases through the fixed bridge, including the benchmark candidate runner,
  tuning cache reuse, MLP, RL trainer, and AlphaZero PolicyValueNet cases.
- `docker compose build jitml` passed after the fixed-bridge source and docs
  changes; the image-local gate reported `check-code: ok` and the PureScript
  bundle rebuilt successfully.
- `docker compose run --rm jitml jitml docs check`,
  `docker compose run --rm jitml jitml check-code`, and `git diff --check`
  passed after the final validation sweep.

### Remaining Work

- None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
