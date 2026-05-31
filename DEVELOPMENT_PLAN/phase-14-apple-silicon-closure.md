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
> batched session: the headless host `swift build` + runtime
> `MTLDevice.makeLibrary(source:)` Metal compilation, Metal FFI loading of the
> compiled `.dylib`, the host↔cluster Pulsar RPC for inference commands and
> events, the Metal benchmark candidate runner, and Apple Metal production
> weight loading from MinIO checkpoints. The phase exists because Phases
> `7`, `10`, and `12` are scoped to code-surface ownership; their live
> Apple-Silicon obligations migrated here so a single Apple-machine session
> closes them all.

## Phase Status

🔄 **Active** (re-scoped 2026-05-30 — headless Apple Metal JIT). The phase owns
the Apple-Silicon halves of [Exit Definition](README.md#exit-definition) items 1
(per-substrate JIT execution — Apple Metal side), 5 (substrate determinism —
Apple side), 7 (production weight loading — Apple Metal side), and 8 (live
Playwright panel matrix on the Apple host). Closure requires a single Apple
Silicon machine with the Xcode **Command Line Tools** (`swiftc`) and a
Metal-capable GPU — **no Tart VM and no full Xcode**. Sprint `14.4` additionally
needs a routable Kind cluster (local Apple-Silicon Kind, or remote against the
Phase `13` cluster).

**Architecture (2026-05-30 reopen)**: the Apple Metal build moves from the
Tart-VM ahead-of-time `.metallib` to a host CommandLineTools `swift build` of the
Swift glue dylib plus runtime `MTLDevice.makeLibrary(source:)` shader
compilation. This is the work of Phase `7` Sprint `7.8` (codegen + host build),
Phase `2` Sprint `2.10` (retire `container.tart` + `jitml internal vm`), and
Phase `5` Sprint `5.8` (retire `tartIdleTimeout`). It dissolves the prior
headless blocker: the macOS `jitml-build` guest could not boot in a background
session (`tart run` → `VZErrorDomain Code=-9 … HostKey`), but headless host
Metal compute needs no VM, so the live validations below become headless-runnable.

**Met today (2026-05-30, headless on Apple M1 / macOS 26)**: Phase `7` Sprint
`7.8` landed (runtime `makeLibrary(source:)` codegen + host `swift build`) and the
live headless validations passed. `cabal run jitml-cross-backend -p apple-silicon`
runs the real host `swift build` → `dlopen` → runtime `makeLibrary` → Metal
dispatch and asserts identity-kernel bit-equality across three runs **(closes
Sprint `14.1` host build + Sprint `14.2` FFI loader)** and weighted Dense2D ==
`[1, 4, 9]` **(closes Sprint `14.5` same-host determinism)**. `JitML.Engines.HasEngine`
dispatches `apple-silicon` via `LocalAppleSiliconEngine`; the per-family weighted
Metal bodies mirror the CUDA `weightedFamilyImpl`; the Apple daemon +
`jitml inference run` dispatch route through the Metal weighted runner; 185 / 185
`jitml-unit` pass; `cabal build all` clean. No Tart VM, no full Xcode.

**Unmet today**: Sprint `14.4`'s host↔cluster Pulsar RPC (needs the full Kind
cluster + a host daemon + live broker — the cluster bring-up the plan records as
having OOM-locked the host on 2026-05-29); and the Phase `15` cross-substrate ULP
tolerance comparison of the Apple Metal outputs against Linux CPU / CUDA (a
multi-host capture, since the Linux outputs come from the Phase `13` container /
CUDA host). Sprints `14.1` / `14.2` / `14.3` / `14.5` are closed (validated
headless on Apple M1).

### Current Implementation Scope

The Metal FFI loader, the Apple `HasEngine` dispatch, the per-family weighted
bodies, the benchmark candidate runner, and the daemon + inference dispatch are
implemented and host-compile-validated. What remains is (a) the Phase `7` Sprint
`7.8` build-mechanism change (runtime `makeLibrary` + host `swift build`), (b) the
**live headless exercise** of the host-build → `dlopen` → runtime-compile → Metal
launch → copy-back path (Sprints `14.1` / `14.2` / `14.3` / `14.5`), and (c) the
Sprint `14.4` host↔cluster RPC (which additionally needs the cluster up). The
phase closes only after the validation commands in each sprint pass headless on a
real Apple Silicon machine.

## Phase Summary

This phase batches the Apple-Silicon live runtime work so the user can
fully close it in one session. The order below is the natural execution
sequence: VM provisioning first, then Metal FFI loading, then the
benchmark runner, then the cross-machine RPC, then production weight
loading. The cross-substrate determinism cohort that consumes Apple
Metal outputs lives in Phase `15`.

## Sprint 14.1: Host Swift Toolchain and First-Cache-Miss Headless Build ✅

**Status**: Done (validated headless 2026-05-30, Apple M1 / macOS 26)
**Implementation**: `src/JitML/Engines/Engine.hs` (`compileSubprocess`
AppleSilicon), `src/JitML/Engines/Loader.hs` (`ensureKernelArtifact`
AppleSilicon branch + `publishAppleArtifact`), `src/JitML/Engines/MetalRuntime.hs`
**Docs to update**: `../documents/engineering/jit_codegen_architecture.md`,
`../documents/engineering/cluster_topology.md`
**Blocked by**: Phase `7` Sprint `7.8` (runtime-compile codegen + host build)

### Objective

Validate the headless host build on a real Apple Silicon machine: a first
`apple-silicon` JIT cache miss drives a host CommandLineTools `swift build` of the
generated Swift glue dylib (no Tart VM), and the runtime `MTLDevice.makeLibrary`
launcher compiles the embedded Metal shader in-process. Adopts `Subprocesses as
Typed Values` and `Prerequisites as Typed Effects` from
[../README.md](../README.md).

### Deliverables

- A one-time headless probe (`swiftc` + `MTLCreateSystemDefaultDevice()` +
  `makeLibrary(source:)` + a compute dispatch) confirms host Swift+Metal works in
  jitML's execution context; the fallback (run the daemon in the user's login
  session) is recorded if a pure `Background` session cannot reach the GPU.
- The first `apple-silicon` JIT cache miss drives `ensureKernelArtifact` →
  host `swift build --package-path <generated-source-dir> -c release` through the
  typed `Subprocess` boundary, copies the produced `libJitMLMetal.dylib` into
  `./.build/jit/apple-silicon/<hash>.dylib`, and repoints the stable symlink at
  `./.build/host/apple-silicon/<model-id>.dylib` via
  `JitML.Cache.Symlink.repointSymlink`.
- The cache-miss run completes headless without `AppError PrerequisiteUnmet` and
  needs only the Xcode Command Line Tools (no full Xcode, no Tart VM).

### Validation

1. On Apple Silicon, headless: the probe prints the expected compute result.
2. A controlled first cache miss (any `apple-silicon` kernel not yet under
   `./.build/jit/apple-silicon/`) drives the host build and writes the `.dylib`
   plus the symlink, headless, with no Tart VM present.

### Remaining Work

- None. Validated headless 2026-05-30: the first `apple-silicon` cache miss drove
  the host `swift build`, `publishAppleArtifact` copied the dylib to
  `./.build/jit/apple-silicon/<hash>.dylib` and repointed the symlink, and the
  kernel ran with no `AppError PrerequisiteUnmet` and no Tart VM. The prior
  Tart-VM provisioning obligation is retired (tracked in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)).

## Sprint 14.2: Metal FFI Loading and Host Kernel Launch ✅

**Status**: Done (validated headless 2026-05-30, Apple M1 / macOS 26)
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

### Code Surface Landed (2026-05-30)

- `JitML.Engines.MetalLocal.runMetalKernel` is implemented: it drives
  `ensureKernelArtifact` (Apple path; Phase `7` Sprint `7.8` moves this to a
  host `swift build`), `dlopen`s the cached `<hash>.dylib`, resolves
  `jitml_kernel_family_name` / `jitml_kernel_output_count` / `jitml_kernel`,
  and marshals the input / output buffers across the FFI — the mirror of
  `JitML.Engines.CudaLocal.runCudaKernel`.
- `JitML.Codegen.Metal` emits the host-callable launcher: a singleton
  `JitMLMetalLauncher` owning the `MTLDevice` / `MTLCommandQueue` and
  dispatching simd-aligned full threadgroups in single-stream launch order
  with bounded `jitml_kernel` shaders. (Phase `7` Sprint `7.8` switches the
  `MTLLibrary` source from the relocated metallib to in-process runtime
  `makeLibrary(source:)` with fast-math off.)
- `JitML.Engines.HasEngine` adds `LocalAppleSiliconEngine` +
  `runAppleSiliconEngine`, dispatching `apple-silicon` through
  `MetalLocal.runMetalFamilyKernel` when the Metal device is visible.
- `jitml-cross-backend` adds the Apple same-host bit-equality case
  ("apple-silicon kernel output is bit-equal across repeated runs
  (Sprint 14.2)"); it skips unless a Metal device is usable headless.
- All of the above compile host-native (`cabal build lib:jitml` +
  `cabal build jitml-cross-backend`, GHC `9.14.1`, exit 0).

### Remaining Work

- None. Validated headless 2026-05-30:
  `cabal run jitml-cross-backend -- -p apple-silicon` ran the real host build →
  `dlopen` → runtime `makeLibrary` → Metal launch → copy-back path and asserted
  three bit-identical identity-kernel runs. No objC class collision (the launcher
  is free functions over `let` globals).

## Sprint 14.3: Metal Benchmark Candidate Runner Live Execution ✅

**Status**: Done (validated headless 2026-05-31, Apple M1 / macOS 26)
**Blocked by**: Sprint `14.2` (closed)
**Implementation**: `src/JitML/Engines/TuningBenchmark.hs`,
`src/JitML/Engines/MetalLocal.hs`,
`src/JitML/Engines/Loader.hs`
**Docs to update**: `documents/engineering/jit_codegen_architecture.md`

### Objective

Replace the guarded preflight `metalBenchmarkCandidateRunner` with the
real Metal candidate runner: render the tuned Swift/Metal source,
compile through Sprint `14.1`'s host `swift build`, load + runtime-compile
through Sprint `14.2`'s FFI runner, measure latency, and capture an output digest.
The benchmark driver in `ensureKernelArtifact`'s first-cache-miss path
selects the Metal tuning choice for an `apple-silicon` kernel and
persists it via `Engines.TuningStore`.

### Deliverables

- `metalBenchmarkCandidateRunner` becomes a non-stub: it renders the
  candidate Metal source, drives the Sprint `14.1` host build, loads +
  runtime-compiles through Sprint `14.2`'s runner, measures elapsed time, and
  records the SHA-256 of the float output.
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

### Code Surface Landed (2026-05-30)

- `JitML.Engines.TuningBenchmark.metalBenchmarkCandidateRunner` is
  de-stubbed: it now takes `Env`, renders the tuned Metal package for the
  candidate, drives the host build + FFI launch through
  `MetalLocal.runMetalKernel`, times the round-trip with
  `getMonotonicTimeNSec`, and records the SHA-256 of the float output —
  the mirror of `cudaBenchmarkCandidateRunner`. `candidateRunnerForSubstrate
  AppleSilicon` routes to it directly.
- The `jitml-unit` "CUDA and Metal runners preflight runtime availability"
  case is updated for the new arity and passes; the live FFI measurement is
  exercised through `jitml-cross-backend` headless on a Metal-capable Apple
  host. Compiles host-native.

### Validation (passed 2026-05-31, Apple M1 / macOS 26, headless)

1. `jitml-cross-backend` "apple-silicon live Metal benchmark candidate runner
   produces a measurement" runs `metalBenchmarkCandidateRunner` on a real
   candidate (one host `swift build` + runtime `makeLibrary` + Metal launch),
   asserting a non-negative latency and the expected SHA-256 output digest,
   plus the wrong-substrate rejection.
2. The gated "apple-silicon first cache-miss persists and reuses a TuningChoice
   via the live runner" case (run with `JITML_TUNING_LIVE=1`) drove the full
   24-candidate Apple knob-space sweep (24 live host builds, 667 s), persisted
   a measured `TuningChoice` JSON under
   `./.build/jit/tuning/apple-silicon/<base-hash>.json`
   (`choice=threadgroup-size=64;matmul-tile=32x32;…`), and the second
   `ensureKernelArtifactWithBenchmarkTuning` call reused the persisted choice
   (no re-sweep). The expensive sweep stays gated so the routine suite is fast.

### Remaining Work

- None.

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
  memory, macOS + CommandLineTools `swiftc` version, cluster edge port).

### Validation

1. With Phase `13` cluster up and the host-native Apple daemon running:
   a single `InferenceRequest` published from a test driver produces a
   matching `InferenceResult` reply within the typed `RetryPolicy`
   budget, and `kubectl logs` shows the in-cluster daemon correlating
   the reply by `call-id`.
2. The Metal output read back from MinIO matches the deterministic
   reference output computed by the same Metal kernel run locally on
   the Apple host.

### Code Surface Landed (2026-05-31)

- **Cluster side** — `JitML.Service.Runtime.daemonWorkloadDispatcherForwardingInference`:
  on a parsed `InferenceRequest` it builds the RPC plan via
  `AppleInferenceRpc.appleInferenceRpcPlan` and publishes the
  `AppleInferenceCommand` on `inference.command.apple-silicon` through
  `HasPulsar.pulsarPublish` (non-inference payloads fall through to the standard
  workload dispatcher). `JitML.App.daemonWorkloadDispatcherForRuntime` routes
  `(AppleSilicon, ForwardToHost)` to it.
- **Host side** — `JitML.Service.AppleInferenceRpc.handleAppleInferenceCommand`
  runs the command's inference via an injected runner and builds the
  `AppleInferenceEvent` reply (completed-with-output-refs or error, echoing the
  `call-id`); `publishAppleInferenceEvent` publishes it on
  `inference.event.apple-silicon` through `HasPulsar`.
- **Host serve-loop integration** —
  `JitML.Service.Runtime.daemonWorkloadDispatcherHostingAppleInference` routes a
  parsed `AppleInferenceCommand` off the host daemon's subscription through
  `handleAppleInferenceCommand` → `publishAppleInferenceEvent`, falling through to
  the weighted self-inference path for direct `RunInference` payloads.
  `JitML.App.appleHostInferenceRunner` is the concrete runner: it parses the
  command inputs, runs `runMetalWeightedCheckpointInference` for the model
  (`loadInferenceCheckpointWithWeights`), stages the float output to a
  `call-id`-keyed MinIO object via `putBlobIfAbsent`, and returns that object
  reference. `daemonWorkloadDispatcherForRuntime` routes `(AppleSilicon,
  SelfInference)` to it.
- **Round-trip validated deterministically** — `jitml-daemon-lifecycle` (31 / 31)
  exercises command → `handleAppleInferenceCommand` → event →
  `correlateAppleInferenceEvent` (success + error paths) and the event publish
  through the synthetic broker. `cabal build all` clean.

### Validation (live broker, 2026-05-31, Apple M1 / macOS 26)

Exercised the full RPC round-trip over a **real standalone Pulsar broker**
(`apachepulsar/pulsar:3.3.1`, WebSocket enabled, ~2.25 GiB) through the live
`JitML.Service.PulsarWebSocketSubprocess` interpreter (Node-driven Pulsar
WebSocket producer/consumer) — no Kind cluster, low memory risk:

1. `pulsarSubscribe` created durable `jitml-host` / `jitml-cluster` subscriptions
   on `inference.command.apple-silicon` / `inference.event.apple-silicon`.
2. Cluster side `publishAppleInferenceRpcCommand` published the
   `AppleInferenceCommand` (broker msg id `CAkQADAA`).
3. Host side `pulsarConsume` received it (`call-id=live-call-14-4`),
   `handleAppleInferenceCommand` built the completed reply, and
   `publishAppleInferenceEvent` published it (msg id `CAoQADAA`).
4. Cluster side `pulsarConsume` received the event and
   `correlateAppleInferenceEvent` matched it by `call-id`, yielding
   `["minio://jitml-checkpoints/out/live-call-14-4"]`.

This validates the RPC envelope flow + bidirectional `call-id` correlation over a
live broker via the production WS interpreter.

### Remaining Work

- **Cluster-side event correlation loop**: add `inference.event.apple-silicon` to
  the cluster (`ForwardToHost`) daemon's subscription plan and a handler that
  consumes it, correlates by `call-id`
  (`AppleInferenceRpc.correlateAppleInferenceEvent`), and republishes the result
  on the client reply topic. (The cluster *publish* and the host *handle* serve
  loops are wired; this closing leg pairs the reply back to the requester.)
- **In-pod cluster deployment**: run the cluster-side daemon in-pod via
  `jitml bootstrap --apple-silicon` + a host-native daemon, and confirm the
  round-trip with `kubectl logs`. Deferred: the full Kind stack is **heavy on this
  16 GiB host and the `cluster.host-memory` preflight is a no-op on macOS**.

## Sprint 14.5: Apple Metal Production Weight Loading ✅

**Status**: Done (same-host determinism validated headless 2026-05-30; cross-substrate ULP parity is Phase `15`)
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

### Code Surface Landed (2026-05-30)

- `JitML.Engines.MetalLocal.runMetalWeightedKernel` /
  `runMetalWeightedFamilyKernel` / `runMetalWeightedCheckpointInference`
  are implemented (mirror of the CUDA weighted path): they resolve
  `jitml_weighted_kernel` and thread the input + flattened weight buffers
  across the FFI to the generated launcher.
- `JitML.Codegen.Metal` emits the **per-family** weighted shaders mirroring
  `JitML.Codegen.Cuda.weightedFamilyImpl`: Dense2D GEMM
  (`out[i] = sum_j input[j] * W[j*n + i]`), Conv2D / Conv3D 1×1 scaling,
  BatchNorm (`[scale, shift, mean, var]`), LayerNorm (input-mean/var +
  `[scale, shift]`), Embedding (row-major table lookup), and MHA
  (`Wq`/`Wk`/`Wv` blocks, no softmax). The `weighted-bodies=all-families`
  fingerprint tag invalidates the prior Dense2D-baseline cache entries.
- `JitML.App.daemonWorkloadDispatcherForRuntime` routes
  `(AppleSilicon, SelfInference)` through
  `daemonWorkloadDispatcherWithWeightedInference` →
  `runMetalWeightedCheckpointInference`; `JitML.App.inferenceForSubstrate`
  routes the `apple-silicon` `jitml inference run` CLI path through
  `loadInferenceCheckpointWithWeights` + the Metal weighted runner.
- `jitml-cross-backend` adds the weighted Dense2D bit-determinism case
  (skips unless a Metal device is usable headless); all 185 `jitml-unit`
  tests pass. (Phase `7` Sprint `7.8` moves the `MTLLibrary` source from the
  relocated metallib to in-process runtime `makeLibrary(source:)`.)

### Remaining Work

- Same-host determinism is validated headless 2026-05-30: the weighted Dense2D
  Metal kernel runs bit-identically across three runs and equals `[1, 4, 9]`
  through the host build → runtime `makeLibrary` → FFI path. The cross-substrate
  ULP tolerance comparison of these Apple outputs against Linux CPU / CUDA is
  owned by Phase `15` Sprint `15.1`; the `(AppleSilicon, ForwardToHost)`
  cluster-side dispatch is owned by Sprint `14.4`.

## Doctrine Sections Cited

- [../README.md → Subprocesses as Typed Values](../README.md#doctrine-scope) (Sprints 14.1, 14.3, 14.4 — host `swift build`, MinIO and Pulsar WebSocket subprocesses)
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
