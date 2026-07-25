# Phase 24: JIT Cache Layout and Content Addressing

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: JIT Cache Layout and Content Addressing. Single-session phase migrated from legacy Sprint 2.3 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 24.1: JIT Cache Layout and Content Addressing [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Cache/Key.hs`, `src/JitML/Cache/Layout.hs`,
`src/JitML/Cache/Manifest.hs`, `src/JitML/Cache/Symlink.hs`
**Docs to update**: `documents/engineering/jit_codegen_architecture.md`

### Objective

Stand up the content-addressed JIT cache root at
`./.build/jit/<substrate>/<hash>.<ext>` keyed on `(canonical-cbor(KernelSpec),
kind, substrate, toolchain-fingerprint, rendered-source-payload, tuning-choice)`
and the Apple stable-FFI symlink surface
at `./.build/host/apple-silicon/<model-id>.<ext>`.

### Deliverables

- `KernelSpec` ADT for the local cache-key surface; Phase `6` supplies the
  numerical catalog that participates in later kernel payloads.
- `cacheKey :: KernelSpec -> Kind -> Substrate -> ToolchainFingerprint ->
  RuntimeSourcePayload -> TuningChoice -> Hash` deterministically hashes
  `(canonical-cbor(KernelSpec) || kind || substrate || toolchain-fingerprint ||
  rendered-source-payload || tuning-choice)` to a 32-byte SHA-256 digest.
- `Kind` ADT: `Training | Inference`. Training and inference kernels are
  separate artefacts.
- The cache layout reserves `./.build/jit-src/<substrate>/<hex>/` for generated
  JIT compiler inputs. Sprint `7.7` now owns the Haskell runtime source
  renderers that populate this root for CUDA, oneDNN, and Swift / Metal source
  bundles during non-dry-run `jitml build`.
- `cachePath :: Path Abs Dir -> Substrate -> Hash -> Extension -> IO (Path Abs
  File)` resolves to `./.build/jit/<substrate>/<hex>.<ext>` under the configured
  build root.
- `manifest.json` index at `./.build/jit/manifest.json` keyed on `(model-id,
  kind, substrate, toolchain)` carries the latest `Hash` for each tuple. Atomic
  writes via temp-file + rename.
- `repointSymlink :: Path Abs Dir -> ModelId -> Hash -> Extension -> IO (Path
  Abs File)` (Apple only) atomically updates
  `./.build/host/apple-silicon/<model-id>.<ext>` to point at
  `./.build/jit/apple-silicon/<hash>.<ext>` under the configured build root.
- Linux substrates skip the symlink layer — the pod loads directly out of
  `./.build/jit/<substrate>/`.
- All cache writes are atomic (`tmp + rename`); concurrent writers writing the
  same content-addressed path are no-ops.

### Validation

1. `cacheKey` is deterministic — snapshot test under `test/snapshots/cache/`
   (SHA-256 over pure rendered runtime source; falls under
   [../README.md → Snapshot targets](../README.md#snapshot-targets), not
   the numerical-fixture prohibition).
2. `repointSymlink` is atomic — interleaved test asserts no torn read.
3. The `manifest.json` round-trips through `decode . encode == id`.

### Closure Checklist

- [x] Add typed `KernelSpec`, `Kind`, `Substrate`, `ToolchainFingerprint`,
  `Hash`, `ModelId`, and `Extension` values for the cache-key surface.
- [x] Implement deterministic SHA-256 cache keys over canonical-CBOR
  `KernelSpec`, kind, substrate, and toolchain fingerprint inputs.
- [x] Implement typed cache path, manifest path, and Apple stable symlink path
  resolution under `./.build/`.
- [x] Implement `manifest.json` entry round-trip, lookup, upsert, read, and
  atomic write helpers.
- [x] Implement atomic Apple stable-FFI symlink repointing into
  `jit/apple-silicon/`.
- [x] Add focused unit/snapshot coverage for cache-key determinism, path layout,
  manifest round-trip, and symlink repointing.

### Closure Validation

- `jitml-unit` now covers the Sprint `2.3` cache-key snapshot, typed cache path,
  manifest JSON round-trip/read/write, and Apple stable symlink repointing.
- `documents/engineering/jit_codegen_architecture.md` already describes the
  implemented cache layout, key shape, manifest, and Apple stable-FFI symlink
  surface; the code now matches that document.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
