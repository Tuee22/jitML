# Phase 84: Haskell-Owned Runtime JIT Source Generation

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Haskell-Owned Runtime JIT Source Generation. Single-session phase migrated from legacy Sprint 7.7 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 84.1: Haskell-Owned Runtime JIT Source Generation [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Engines/Engine.hs`,
`src/JitML/Codegen/RuntimeSource.hs`,
`src/JitML/Codegen/{Cuda,OneDnn,Metal,SourceFile}.hs`
**Docs to update**: `documents/engineering/jit_codegen_architecture.md`,
`documents/engineering/determinism_contract.md`,
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Make the Haskell `jitml` binary the only source of JIT compiler inputs and
project-owned native adapter source. Static checked-in JIT build scripts,
kernel source files, and native adapter shims are forbidden: no checked-in CUDA
`.cu`, no checked-in oneDNN C/C++ source, no checked-in C/C++ adapter source,
and no checked-in Metal / Swift package source participates in a JIT build or
runtime adapter path.

### Deliverables

- `RuntimeSource` ADT describes generated source bundles:
  `GeneratedCudaSource`, `GeneratedOneDnnSource`, `GeneratedMetalPackage`.
- `renderRuntimeSource :: KernelSpec -> Kind -> Substrate -> TuningChoice ->
  RuntimeSource` is pure and deterministic.
- `materializeRuntimeSource :: Env -> RuntimeSource -> Hash -> IO (Path Abs Dir)`
  writes compiler inputs under `./.build/jit-src/<substrate>/<hash>/` using
  temp-file + rename discipline.
- The compile plans invoke `nvcc`, the oneDNN C++ compiler path, or
  `swift build` only against the generated directory through `Subprocess`.
- `cacheKey` includes the canonical rendered source payload and the
  `TuningChoice`, so changing a renderer invalidates the compiled artefact.
- Cache-key fixtures derive their `RuntimeSourcePayload` from
  `renderRuntimeSource`; the old `runtime-source:phase-2-placeholder` marker is
  gone from the worktree.
- Static source/script scaffolds are removed, as tracked in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md#completed).
- `jitml lint files` rejects future checked-in JIT build scripts, checked-in
  substrate source extensions, and native adapter shims. It additionally
  rejects any new file under `test/golden/` per
  [../README.md → Snapshot targets → Numerical-fixture
  prohibition](../README.md#snapshot-targets).

### Validation

1. `jitml build --dry-run --substrate linux-cuda` shows a generated-source
   directory under `./.build/jit-src/linux-cuda/<hash>`.
2. `jitml build --dry-run --substrate linux-cpu` shows oneDNN C++ generated
   under `./.build/jit-src/linux-cpu/<hash>/`.
3. `jitml build --dry-run --substrate apple-silicon` shows Swift / Metal
   generated under `./.build/jit-src/apple-silicon/<hash>/` before the host
   CommandLineTools `swift build --package-path <generated-source-dir> -c release`
   command; the former Tart executor path is retired.
4. Removing documentation-only substrate folders does not change any JIT build
   plan or cache key.
5. `jitml-unit` snapshot tests prove `renderRuntimeSource` is deterministic and
   that renderer changes alter the generated-source hash.
6. `cabal test jitml-unit --test-options='-p cacheKey'` on 2026-05-21 passes
   with the cache-key snapshot backed by rendered runtime source instead of the
   retired placeholder fixture.
7. `cabal test jitml-cross-backend` on 2026-05-21 passes the local
   generated-source FFI path: deterministic engine flags, manifest-read
   independence, Linux CPU identity compile/load/run, reduction-family
   compile/load/run, all-family scaffold compile/load/run, family/output-count
   symbol validation, repeated-run bit equality, and local Linux CPU
   `HasEngine` dispatch.

### Closure Checklist

- [x] Add the Haskell `RuntimeSource` renderers for CUDA, oneDNN C++, and
  Metal / Swift package generation.
- [x] Route every JIT compile plan through generated source under
  `./.build/jit-src/<substrate>/<hash>/`.
- [x] Remove checked-in JIT build scripts, checked-in `.cu`, checked-in `.cc`
  / `.cpp`, checked-in native adapter shims, and checked-in Metal / Swift
  package inputs from the build path.
- [x] Add lint coverage that rejects future static JIT source/build artefacts.
- [x] Move the static-codegen pending-removal ledger row to `Completed` once
  the generated-source path validates.
- [x] Move the default runtime-source placeholder ledger row to `Completed`
  once cache-key fixtures consume rendered `RuntimeSourcePayload`s.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
