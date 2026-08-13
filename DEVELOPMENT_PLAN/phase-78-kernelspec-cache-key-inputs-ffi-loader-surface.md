# Phase 78: `KernelSpec`, Cache Key Inputs, FFI Loader Surface

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: KernelSpec, Cache Key Inputs, FFI Loader Surface. Single-session phase migrated from legacy Sprint 7.1 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

🔄 **Active** (2026-08-12). Reopened: the cache-key derivation this sprint locked is not
total over `ToolchainFingerprint`. `buildToolchainFingerprint` gives every
non-`linux-cpu` substrate one shared literal that names no compiler, no `sm_` target
and no bridge ABI, so a CUDA or Metal toolchain change does not invalidate a
`jitml build` artifact. The per-engine fingerprints are hand-written prose
duplicated across seven sites; one already describes a C ABI its artifact does not
export, and the Metal bridge-ABI token is interpolated in one site and hardcoded in
another, so bumping it invalidates one lane and not the other.

## Sprint 78.1: `KernelSpec`, Cache Key Inputs, FFI Loader Surface [🔄 Active]

**Status**: Active
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

### Remaining Work

- Derive each fingerprint from the emitter/primitive set it covers instead of
  restating C signatures in prose, so a renderer change invalidates its artifact
  automatically.
- Give every substrate a real fingerprint; delete the shared non-`linux-cpu` literal.
- Assert every fingerprint in the unit lane — only one of the eight has a test today.
- Record the duplicated fingerprint prose in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

### Historical Validation

Evidence for the surface this sprint actually exercised before the 2026-08-12 reopen:

> ✅ **Done**.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
