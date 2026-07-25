# Phase 78: `KernelSpec`, Cache Key Inputs, FFI Loader Surface

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: KernelSpec, Cache Key Inputs, FFI Loader Surface. Single-session phase migrated from legacy Sprint 7.1 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 78.1: `KernelSpec`, Cache Key Inputs, FFI Loader Surface [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Cache/Key.hs`, `src/JitML/Engines/Engine.hs`,
`src/JitML/Engines/Loader.hs`
**Docs to update**: `documents/engineering/jit_codegen_architecture.md`,
`documents/engineering/determinism_contract.md`

### Objective

Populate the local cache-key input surface and kernel-handle/cache-decision
surface, and lock the cache key derivation over `KernelSpec`, `Kind`,
`Substrate`, `ToolchainFingerprint`, `RuntimeSourcePayload`, and
`TuningChoice`. Downstream runtime phases consume the generic FFI loading
surface; the local Linux CPU identity runner is owned by Sprint `7.3`.

### Deliverables

- `KernelSpec` is the cache-key payload wrapper.
- `Kind` distinguishes `Training` from `Inference`.
- `ToolchainFingerprint`, `RuntimeSourcePayload`, and `TuningChoice` are typed
  cache-key inputs.
- `cacheKey` hashes the serialized kernel spec, kind, substrate, fingerprint,
  rendered-source payload, and tuning choice into a SHA-256 digest.
- `KernelHandle` names the engine, content hash, and canonical artifact path.
- `resolveKernelCache` returns a typed `JitCacheHit` or `JitCacheMiss` with the
  compile `Subprocess` needed to fill the cache.
- `JitML.Engines.Loader.ensureKernelArtifact` is the generic cache-hit/cache-miss
  artifact boundary: it materializes generated source, detects existing cache
  artifacts, runs the typed compile `Subprocess` on misses, and returns a
  `KernelArtifact` with the chosen `KernelHandle`.
- `JitML.Engines.Loader.withKernelSymbol` owns the reusable `dlopen`/`dlsym`
  helper used by the local Linux CPU FFI fixture.
- The production `HasEngine` graph-launch capability is consumed and
  validated by the later runtime and per-lane closure phases.

### Validation

1. `jitml-unit` verifies the cache-key snapshot under `test/snapshots/cache/`
   (pure-renderer output; see [../README.md → Snapshot
   targets](../README.md#snapshot-targets)).
2. `jitml-unit` verifies changing the rendered runtime-source payload changes
   the cache key.
3. `jitml-unit` verifies the typed cache-hit/cache-miss decision surface.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
