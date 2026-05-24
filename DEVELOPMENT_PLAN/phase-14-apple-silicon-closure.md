# Phase 14: Apple Silicon Closure

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md),
[development_plan_standards.md](development_plan_standards.md),
[system-components.md](system-components.md),
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md),
[phase-7-jit-codegen-and-substrates.md](phase-7-jit-codegen-and-substrates.md),
[phase-10-checkpointing-and-inference.md](phase-10-checkpointing-and-inference.md),
[phase-12-test-stanzas-and-cross-cluster.md](phase-12-test-stanzas-and-cross-cluster.md),
[phase-13-linux-cuda-and-cluster-closure.md](phase-13-linux-cuda-and-cluster-closure.md),
[phase-15-cross-substrate-and-handoff.md](phase-15-cross-substrate-and-handoff.md),
[../README.md](../README.md)
**Generated sections**: none

> **Purpose**: Close every Apple-Silicon-bound live-runtime obligation in one
> batched session: the `jitml-build` Tart VM, Metal FFI loading of the
> compiled `.dylib`, the host↔cluster Pulsar RPC for inference commands and
> events, the Metal benchmark candidate runner, and Apple Metal production
> weight loading from MinIO checkpoints. The phase exists because Phases
> `7`, `10`, and `12` are scoped to code-surface ownership; their live
> Apple-Silicon obligations migrated here so a single Apple-machine session
> closes them all.

## Phase Status

🔄 **Active**. The phase owns the Apple-Silicon halves of [Exit
Definition](README.md#exit-definition) items 1 (per-substrate JIT
execution — Apple Metal side), 5 (substrate determinism — Apple side),
7 (production weight loading — Apple Metal side), and 8 (live Playwright
panel matrix on the Apple host). Closure requires a single Apple Silicon
machine session with Xcode Command Line Tools, Tart, and a routable Kind
cluster (either local Apple-Silicon Kind, or remote against the cluster
brought up under Phase `13`).

**Met today**: nothing — the phase has not yet been exercised. The
upstream code surfaces are in place under Sprint `7.5`
(`renderMetalPackage`, `JitML.Tart.Build`, `JitML.Tart.Lifecycle`,
`JitML.Engines.MetalRuntime`, `JitML.Service.AppleInferenceRpc`), Sprint
`7.6` (`metalBenchmarkCandidateRunner` guarded preflight), and Sprint
`10.4` (`loadInferenceCheckpointWithWeights`, the typed checkpoint→runner
hook), all validated against synthetic broker / runner stand-ins.

**Unmet today**: every live obligation in the sprint bodies below.

### Current Implementation Scope

Nothing in this phase is implemented yet against a real Apple Silicon
host. The Haskell-side scaffolding is the worktree's Phase `7.5` / `7.6` /
`10.4` baseline. The phase closes only after the validation commands in
each sprint pass on a real Apple Silicon machine with Metal-capable
hardware and the project-owned Tart workflow.

## Phase Summary

This phase batches the Apple-Silicon live runtime work so the user can
fully close it in one session. The order below is the natural execution
sequence: VM provisioning first, then Metal FFI loading, then the
benchmark runner, then the cross-machine RPC, then production weight
loading. The cross-substrate determinism cohort that consumes Apple
Metal outputs lives in Phase `15`.

## Sprint 14.1: Apple Tart VM Provision and First-Cache-Miss Build 🔄

**Status**: Active
**Implementation**: `src/JitML/Tart/Build.hs`,
`src/JitML/Tart/Lifecycle.hs`,
`src/JitML/Tart/Exec.hs`,
`src/JitML/Engines/Loader.hs`
**Docs to update**: `documents/engineering/jit_codegen_architecture.md`,
`documents/engineering/cluster_topology.md`

### Objective

Provision the default `jitml-build` Tart VM on a real Apple Silicon
machine and exercise the first-cache-miss Swift build through the typed
lifecycle. Adopts `Subprocesses as Typed Values` and `Prerequisites as
Typed Effects` from [../README.md](../README.md).

### Deliverables

- `jitml internal vm bootstrap` clones the default Tart source image
  (`ghcr.io/cirruslabs/macos-sequoia-xcode:16`) into the `jitml-build`
  name on a real Apple Silicon host.
- `jitml internal vm up` starts the VM through `tart run --no-graphics`
  and reports the rendered status.
- The first `apple-silicon` JIT cache miss drives `ensureKernelArtifact`
  through `JitML.Tart.Lifecycle.ensureVmUpLive`, which polls
  `tart exec jitml-build true` for readiness and then executes
  `tart exec jitml-build swift --version`,
  `tart exec jitml-build swift build --package-path <generated-source-dir> -c release`,
  the host copy of the produced `libJitMLMetal.dylib` into
  `./.build/jit/apple-silicon/<hash>.dylib`, and the symlink repoint via
  `JitML.Cache.Symlink.repointSymlink`.
- The live run produces a content-addressed `.dylib` under the cache
  root and a stable symlink at `./.build/host/apple-silicon/<model-id>.dylib`
  for the FFI loader in Sprint `14.2`.
- `jitml internal vm status` reports `running` after the cache miss
  completes.

### Validation

1. On Apple Silicon: `jitml internal vm bootstrap` succeeds and the
   `jitml-build` VM appears under `tart list --source local --format
   json`.
2. `jitml internal vm up` succeeds; `jitml internal vm status` reports
   `running`.
3. A controlled first cache miss (any `apple-silicon` kernel not yet
   under `./.build/jit/apple-silicon/`) drives the full build plan and
   writes the `.dylib` plus the symlink. The cache-miss run completes
   without `AppError PrerequisiteUnmet`.

### Remaining Work

- Execute Validation step 3 on a real Apple Silicon host with Xcode 16
  installed.

## Sprint 14.2: Metal FFI Loading and Host Kernel Launch 🔄

**Status**: Active
**Blocked by**: Sprint `14.1`
**Implementation**: `src/JitML/Engines/MetalRuntime.hs`,
`src/JitML/Engines/Local.hs` (Apple branch), new
`src/JitML/Engines/MetalLocal.hs`
**Docs to update**: `documents/engineering/jit_codegen_architecture.md`,
`documents/engineering/determinism_contract.md`

### Objective

Load the symlinked `.dylib` produced by Sprint `14.1`, look up
`jitml_kernel`, `jitml_kernel_family_name`, and `jitml_kernel_output_count`
through `dlopen`, build an `MTLDevice` + pipeline + command buffer, launch
the kernel against a host input buffer, and copy the output back through
the FFI. Adopts `Capability Classes` from [../README.md](../README.md).

### Deliverables

- `JitML.Engines.MetalLocal.runMetalKernel` loads the symlinked dylib,
  resolves the three exported symbols, calls into `MTLDevice` /
  `MTLCommandQueue` / `MTLComputePipelineState` through the typed
  `JitML.Engines.MetalRuntime` boundary, and returns the output buffer
  to Haskell.
- `JitML.Engines.HasEngine` dispatches `apple-silicon` to
  `runMetalKernel` when the runtime probe reports Metal device
  visibility.
- The same-host bit-equality property holds: three successive
  invocations of the identity kernel produce bit-identical output (in
  the spirit of the closed Linux CPU same-host equality in
  `jitml-cross-backend`).

### Validation

1. On Apple Silicon, after Sprint `14.1` completes: `cabal test
   jitml-cross-backend --test-options='-p Apple'` exits `0` and asserts
   three successive identity-kernel runs produce bit-identical output.
2. `JitML.Engines.MetalRuntime.probeMetalRuntime` reports Metal device
   visibility on the same host.

### Remaining Work

- Implement `JitML.Engines.MetalLocal.runMetalKernel` against a real
  `MTLDevice` (pipeline state, command buffer encode, dispatch,
  synchronize, output buffer copy-back).
- Add the Metal branch to `JitML.Engines.HasEngine` dispatch.
- Extend `jitml-cross-backend` with the Apple-side same-host equality
  test.

## Sprint 14.3: Metal Benchmark Candidate Runner Live Execution 🔄

**Status**: Active
**Blocked by**: Sprint `14.2`
**Implementation**: `src/JitML/Engines/TuningBenchmark.hs`,
`src/JitML/Engines/MetalLocal.hs`,
`src/JitML/Engines/Loader.hs`
**Docs to update**: `documents/engineering/jit_codegen_architecture.md`

### Objective

Replace the guarded preflight `metalBenchmarkCandidateRunner` with the
real Metal candidate runner: render the tuned Swift/Metal source,
compile through Sprint `14.1`'s Tart pipeline, load through Sprint
`14.2`'s FFI runner, measure latency, and capture an output digest.
The benchmark driver in `ensureKernelArtifact`'s first-cache-miss path
selects the Metal tuning choice for an `apple-silicon` kernel and
persists it via `Engines.TuningStore`.

### Deliverables

- `metalBenchmarkCandidateRunner` becomes a non-stub: it renders the
  candidate Metal source, drives the Sprint `14.1` build, loads through
  Sprint `14.2`'s runner, measures elapsed time, and records the
  SHA-256 of the float output.
- The benchmark driver wired into `ensureKernelArtifact` in Sprint
  `7.6`'s code-only Remaining Work invokes the Metal runner on the
  first Apple cache miss; the persisted selection appears under
  `./.build/jit/tuning/apple-silicon/<base-hash>.json`.

### Validation

1. On Apple Silicon: a controlled first cache miss for an
   `apple-silicon` kernel selects a tuning choice through the live
   Metal runner, persists the selected `TuningChoice`, and the next
   build of the same kernel reads the persisted choice (cache hit on
   the tuned key).

### Remaining Work

- Implement the live Metal runner.
- Validate the persisted selection round-trip on Apple Silicon.

## Sprint 14.4: Apple Host↔Cluster Pulsar RPC Live Flow 🔄

**Status**: Active
**Blocked by**: Sprint `14.2`, Phase `13` Sprint `13.1` (cluster up),
Phase `13` Sprint `13.2` (live capability classes), Phase `13` Sprint
`13.3` (daemon handlers consuming live broker)
**Implementation**: `src/JitML/Service/AppleInferenceRpc.hs`,
`src/JitML/Service/PulsarWebSocketSubprocess.hs`,
`src/JitML/Service/MinIOSubprocess.hs`,
`src/JitML/Engines/MetalLocal.hs`
**Docs to update**: `documents/engineering/daemon_architecture.md`,
`documents/engineering/cluster_topology.md`

### Objective

Run the full Apple host↔cluster inference RPC end-to-end: the in-cluster
daemon publishes an `AppleInferenceCommand` on
`inference.command.apple-silicon` with a MinIO-staged input tensor
reference, the host-native `jitml service` consumes it through
`HasPulsar.pulsarConsume`, loads the staged tensor through
`HasMinIO.minioReadBytes`, runs the Metal kernel via Sprint `14.2`,
stages the output to MinIO, and publishes the
`AppleInferenceEvent` reply on `inference.event.apple-silicon`. The
in-cluster daemon correlates the reply by `call-id` through
`AppleInferenceRpc.correlateCompletedEvent`.

### Deliverables

- The Apple host-native `jitml service` (`Host + SelfInference` mode,
  `inferenceMode = ForwardToHost`) subscribes to
  `inference.command.apple-silicon` with subscription `jitml-host` and
  acks only after the Metal launch and MinIO output stage complete.
- The cluster-side daemon publishes the matching `AppleInferenceCommand`
  through `HasPulsar.pulsarPublish` and consumes the reply event.
- Large tensor payloads transit through MinIO objects keyed by
  `(call-id, stage)`; the broker carries only the references.
- 2026-MM-DD validation note recorded under the sprint after the live
  run succeeds, naming the validation host hardware (M-series chip,
  memory, Xcode version, Tart version, cluster edge port).

### Validation

1. With Phase `13` cluster up and the host-native Apple daemon running:
   a single `InferenceRequest` published from a test driver produces a
   matching `InferenceResult` reply within the typed `RetryPolicy`
   budget, and `kubectl logs` shows the in-cluster daemon correlating
   the reply by `call-id`.
2. The Metal output read back from MinIO matches the deterministic
   reference output computed by the same Metal kernel run locally on
   the Apple host.

### Remaining Work

- Wire the cluster-side daemon's `linux-cpu` + `ForwardToHost` dispatch
  path to produce `AppleInferenceCommand` envelopes and consume the
  reply events.
- Wire the host-native daemon's Apple-side subscription to invoke the
  Metal runner and publish reply envelopes.
- Validate the full round-trip live on Apple Silicon with the cluster up.

## Sprint 14.5: Apple Metal Production Weight Loading 🔄

**Status**: Active
**Blocked by**: Sprint `14.2`, Phase `13` Sprint `13.7` (live MinIO
checkpoint round-trip)
**Implementation**: `src/JitML/Checkpoint/Store.hs`,
`src/JitML/Engines/MetalLocal.hs`,
`src/JitML/Engines/Loader.hs`
**Docs to update**: `documents/engineering/checkpoint_format.md`,
`documents/engineering/determinism_contract.md`

### Objective

Extend `loadInferenceCheckpointWithWeights` to the Apple Metal runner so
real weight blobs decoded from `.jmw1` load into Metal `MTLBuffer`
device memory and feed `MTLComputePipelineState` execution. Closes the
Apple-Metal portion of Exit Definition item 7 (production weight
loading per substrate).

### Deliverables

- `JitML.Engines.MetalLocal.runMetalWeightedKernel` accepts decoded
  weight tensors from `loadInferenceCheckpointWithWeights` and binds
  them to the Metal kernel as `MTLBuffer` inputs.
- The daemon dispatches `apple-silicon` + `SelfInference` (Apple
  host-native) and `apple-silicon` + `ForwardToHost` (cluster-side
  forward) through the new weighted runner.

### Validation

1. A canonical Apple-Silicon inference request with weighted checkpoint
   produces a deterministic output bit-identical to the same request
   run twice in sequence.
2. The weighted output matches the cross-substrate ULP tolerance band
   pinned by Phase `15` Sprint `15.1`.

### Remaining Work

- Implement `runMetalWeightedKernel`.
- Wire the daemon dispatch in `JitML.Service.Runtime.daemonWorkloadDispatcherWithInference`.

## Doctrine Sections Cited

- [../README.md → Subprocesses as Typed Values](../README.md#doctrine-scope) (Sprints 14.1, 14.3, 14.4 — Tart, `tart exec`, MinIO and Pulsar WebSocket subprocesses)
- [../README.md → Capability Classes and Service Errors](../README.md#doctrine-scope) (Sprints 14.4, 14.5 — live `HasPulsar` / `HasMinIO` execution on Apple host)
- [../README.md → At-Least-Once Event Processing](../README.md#doctrine-scope) (Sprint 14.4 — Apple host daemon ack-after-success)
- [../README.md → Retry Policy as First-Class Values](../README.md#doctrine-scope) (Sprint 14.4 — typed `RetryPolicy` budget for RPC round-trip)
- [../README.md → Long-Running Daemons in the Same Binary](../README.md#doctrine-scope) (Sprint 14.4 — host-native `jitml service` as second instance distinguished by Dhall)

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/jit_codegen_architecture.md` — record Metal FFI
  loader, live Metal candidate runner, and the Apple Metal weighted
  runner path once Sprints `14.2`, `14.3`, and `14.5` close.
- `documents/engineering/daemon_architecture.md` — record the live
  Apple host↔cluster RPC flow once Sprint `14.4` closes.
- `documents/engineering/cluster_topology.md` — note the host-native
  daemon's edge-port discovery and Apple session prerequisites.
- `documents/engineering/checkpoint_format.md` — Apple Metal weighted
  inference path once Sprint `14.5` closes.
- `documents/engineering/determinism_contract.md` — Apple Metal
  same-host bit-equality observation once Sprint `14.2` closes;
  cross-substrate ULP work lives in Phase `15`.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- `system-components.md → Substrates` row for `apple-silicon` updates
  from "Active, missing live FFI + RPC" to closure once Sprints `14.2`
  and `14.4` close.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [development_plan_standards.md](development_plan_standards.md)
- [phase-7-jit-codegen-and-substrates.md](phase-7-jit-codegen-and-substrates.md)
- [phase-10-checkpointing-and-inference.md](phase-10-checkpointing-and-inference.md)
- [phase-13-linux-cuda-and-cluster-closure.md](phase-13-linux-cuda-and-cluster-closure.md)
- [phase-15-cross-substrate-and-handoff.md](phase-15-cross-substrate-and-handoff.md)
- [../README.md](../README.md)
