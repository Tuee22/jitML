# Phase 82: Apple Silicon Engine, Metal Codegen, Host Forwarding Scaffolding

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Apple Silicon Engine, Metal Codegen, Host Forwarding Scaffolding. Single-session phase migrated from legacy Sprint 7.5 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 82.1: Apple Silicon Engine, Metal Codegen, Host Forwarding Scaffolding [✅ Done]

**Status**: Done
**Owned obligations after refactor**: code-surface only. Every live
Apple-Silicon obligation (retired Tart provisioning, Metal FFI loading,
host↔cluster forwarding, Apple Metal candidate runner, Apple Metal production
weight loading) migrated to Phase `16`. The early Swift-package and
`AppleInferenceCommand`/`AppleInferenceEvent` refs-RPC scaffolds were later
retired by Sprint `7.11` and Sprint `16.12`; the retained current surface is
`.metal.json` source metadata, the fixed bridge, and raw inference-domain
payload forwarding on `inference.command.apple-silicon`. See
[phase-16-apple-silicon-closure.md](README.md#legacy-to-new-phase-map).
**Implementation**: `src/JitML/Engines/Engine.hs`,
`src/JitML/Codegen/Metal.hs`, `src/JitML/Engines/MetalRuntime.hs`,
`src/JitML/Engines/MetalBridge.hs`, `src/JitML/Engines/MetalLocal.hs`,
`src/JitML/Service/Runtime.hs`, `src/JitML/Proto/Inference.hs`
**Docs to update**: `documents/engineering/jit_codegen_architecture.md`,
`documents/engineering/determinism_contract.md`,
`documents/engineering/daemon_architecture.md`

### Objective

Land the `apple-silicon` engine metadata, Metal renderer, host runtime probe,
fixed-bridge cache-miss shape, and Apple host-forwarding topic names. The
deleted Tart VM executor, Swift package cache-miss path, `jitml internal vm`
command group, and refs/event Apple RPC are no longer part of this surface.

### Deliverables

- `engineForSubstrate AppleSilicon` records backend `metal` and artifact
  extension `.metal.json`.
- `renderMetalFamilyMetadata` emits `kernel.metal.json` with the rendered MSL
  source, family name, output-count policy, bridge ABI, deterministic compile
  options, launch policy, source hash, and threadgroup size.
- `JitML.Engines.Loader.ensureKernelArtifact` fills an Apple cache miss by
  writing `./.build/jit/apple-silicon/<hash>.metal.json`; it does not invoke
  SwiftPM, Tart, the offline `metal` compiler, or a generated dylib symlink.
- `JitML.Engines.MetalBridge` is the fixed host bridge ABI. `MetalLocal` calls
  the bridge to compile MSL with `MTLDevice.makeLibrary(source:options:)`,
  disable fast math, create/reuse pipelines, bind buffers, and dispatch on the
  host GPU.
- `JitML.Engines.MetalRuntime.probeMetalRuntime` establishes the typed host
  Metal runtime availability boundary without making `swiftc`, `xcrun metal`,
  Tart, or login-keychain state core prerequisites.
- The route/topic documentation records `inference.command.apple-silicon` as
  the Apple-only host-forwarding topic. `JitML.Service.Runtime` forwards raw
  `RunInference`, `CheckpointCompareCommand`, and `AdversarialMoveCommand`
  payloads to that topic; the host Engine publishes the matching result directly
  to the request's reply topic.
- Metal bridge loading, MinIO tensor handoff, and live Pulsar forwarding are
  live-closed by [phase-16-apple-silicon-closure.md](README.md#legacy-to-new-phase-map)
  Sprints `16.2`, `16.4`, `16.9`, and `16.12`; this sprint's retained
  code-surface obligations are met.

### Validation

1. `jitml build --dry-run --substrate apple-silicon` renders the Apple
   `.metal.json` source metadata plan rather than a generated Swift package.
2. `jitml-unit` validates deterministic Metal metadata rendering, output-count
   policy, cache-key changes when the MSL payload changes, and the absence of the
   retired Tart/SwiftPM core prerequisites.
3. `jitml test jitml-backends --apple-silicon` fills a fresh cache miss as
   `<hash>.metal.json`, runs identity/weighted kernels through the fixed bridge,
   and proves same-substrate bit equality on Apple hardware.
4. `jitml-daemon-lifecycle` / `jitml-integration` validate the live Apple topic
   names and values-model forwarding: the cluster publishes raw inference-domain
   commands on `inference.command.apple-silicon`, and the host Engine publishes
   results on each request's reply topic.

### Remaining Work

- No sprint-owned code-surface Remaining Work remains for Sprint `7.5`.
  Apple Silicon live validation (first-cache-miss host build, Metal FFI
  loading, host↔cluster Pulsar RPC, full host-resident inference) is closed by
  [phase-16-apple-silicon-closure.md](README.md#legacy-to-new-phase-map)
  Sprints `16.1`, `16.2`, `16.4`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
