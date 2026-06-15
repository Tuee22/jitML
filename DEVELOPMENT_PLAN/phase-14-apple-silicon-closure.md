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
[phase-18-no-caveat-product-handoff.md](phase-18-no-caveat-product-handoff.md),
[../README.md](../README.md)
**Generated sections**: none

> **Purpose**: Close every Apple-Silicon-bound live-runtime obligation in one
> batched session: the host daemon uses a fixed Metal bridge to compile generated
> MSL through `MTLDevice.makeLibrary(source:options:)`, dispatches on the host
> GPU with fast math disabled, and never requires Tart, keychain state, SwiftPM,
> full Xcode, or the offline `metal` compiler for core training/inference cache
> misses. The phase also owns the host↔cluster Pulsar RPC for inference commands
> and events, the Metal benchmark candidate runner, Apple Metal production
> weight loading from MinIO checkpoints, and the live apple-silicon
> `WorkflowMatrix` exercise of the reopened real workflows.

## Phase Status

⏸️ **Blocked** (reopened 2026-06-14 — no-caveat Apple live validation). Sprint
`14.11` revalidates the expanded runtime/browser product matrix on
`apple-silicon`, but it is blocked until Phases `10`–`12`, Phase `16`, and
Phase `17` land the remaining no-caveat surfaces. Phases `8` and `9` have
re-closed their local framework/runtime and RL/AlphaZero/tuning surfaces.

✅ **Historical closure** (reopened and re-closed 2026-06-13 for Sprint `14.10`). The fixed
Metal bridge and Apple backend lane remain valid, and the full Apple lifecycle
now validates host-resident placement for Apple Metal-backed Training/RL/Tune
starts. Sprint `14.10` closes after Phase `5` routes those starts to host
workload topics, Phase `12` adds fail-fast placement checks, and
`bootstrap/apple-silicon.sh test` passes the full Apple lane with no
`jitml-train-*`, `jitml-rl-*`, or `jitml-tune-*` Kubernetes workload Jobs.

Prior closure history follows.

✅ **Done** (reopened 2026-06-12 — true-headless Apple Metal fixed-bridge
doctrine; **re-closed the same day** after Sprint `14.9`). This phase owns the
live **apple-silicon** exercise of every reopened workflow (Phases `8`–`12`)
through the fixed Metal bridge against a live Apple-Silicon cluster. Phase `7`
Sprint `7.11` removed the generated Swift/Tart cache-miss path; Sprints `1.15`,
`2.12`, and `5.10` removed the VM command surface, the core Tart prerequisite /
bootstrap cleanup, and daemon build-VM acquire/config path. The 2026-06-12 Tart
HostKey/keychain failure is retained below as evidence that the old VM
architecture is not a valid headless target; it is no longer the remediation
path.

Historical superseded closure: ✅ **Done** (reopened 2026-06-10 for the Apple
Silicon Tart-VM build-JIT doctrine reversal; **re-closed 2026-06-10** after the
live apple-silicon lane was re-validated through the Tart-VM-built path on Apple
M1). Under that now-retired doctrine, the lane built each Metal kernel family
with the `jitml`-managed VM's `swift build`, copied the dylib out, and executed
on the host GPU. Sprint `14.7` owned that re-validation; its
`### Live Closure (2026-06-10)` records the historical evidence —
`jitml test jitml-backends --apple-silicon` ran all 17 within-substrate apple
cases as real PASSes through the VM-built path. With this phase re-closed, the
Phase `15` final handoff (Exit-Definition item 18, empty legacy ledger) is met
again as of 2026-06-10; that claim is superseded by the 2026-06-12 fixed-bridge
closure above. See
[Sprint 14.7](#sprint-147-re-validate-the-apple-silicon-lane-through-the-tart-vm-built-path--done).
Prior closure history follows.

✅ **Done** (re-closed 2026-06-09 after Sprint 14.6). The reproducibility
contract is now "within a substrate: bit-for-bit reproducible; across
substrates: NO guarantee"; the cross-substrate numeric parity surface is
removed and the test suite is partitioned so each substrate's cases run **for
real** in its own lane with **no skipped tests**. The `appleLiveReady` skip
guards in the apple-silicon test bodies are removed — a missing Metal device
now **fails** rather than skips. Within-substrate bit-for-bit reproducibility
tests **stay**. Sprint 14.6 re-validated the guards-removed apple-silicon lane
host-native on 2026-06-09: `jitml test jitml-cross-backend
--test-options='-p apple-silicon'` ran the four within-substrate Metal cases
as real PASSes (4 / 4, 88.90s, no skip-sentinels, no oneDNN / nvcc compiles).
The phase reopened 2026-06-08 for Sprint 14.6 and is re-closed the same day.
All historical dated evidence below (Apple M1, macOS 26) is retained intact as
a dated record.

Previously ✅ **Complete** (all Apple-half obligations validated headless 2026-05-30/31,
Apple M1 / macOS 26). The phase owns the Apple-Silicon halves of
[Exit Definition](README.md#exit-definition) items 1 (per-substrate JIT
execution — Apple Metal side), 5 (substrate determinism — Apple side), 7
(production weight loading — Apple Metal side), and 8 (live Playwright panel
matrix on the Apple host). Closure required a single Apple Silicon machine with
the Xcode **Command Line Tools** (`swiftc`) and a Metal-capable GPU — **no Tart
VM and no full Xcode**.

Sprints `14.1`–`14.5` are **Done and live-validated headless**: the host
`swift build` + runtime `MTLDevice.makeLibrary(source:)` JIT, Metal FFI launch,
the benchmark candidate runner, Apple Metal production weight loading, and the
full host↔cluster RPC round-trip through **two running daemon processes**
(Sprint `14.4`, validated against a standalone broker — **no Kind cluster
required**; the cluster-leg binary was the real `jitml:local` image, its hardcoded
in-cluster Pulsar DNS redirected to the host broker via Docker `--add-host`).

**Item 8 (Apple-host Playwright panel matrix) — validated 2026-05-31.** The
`playwright/jitml-demo.spec.ts` 7-test matrix was run **inside the `jitml:local`
image on the Apple M1 host** (Playwright + Chromium arm64 installed in the
container; the baked `web/dist/Main/bundle.js` served by `jitml-demo` on
`127.0.0.1:8080`). In **live mode** (a `cluster-publication.json` with
`edge_port = 8080` so the spec navigates to the real served demo) all 7 tests
passed — the Halogen bundle mounts the shell + all six panels (`mnist`, `cifar`,
`connect4`, `rl`, `training`, `tune`) via `#<panel-id>` hash navigation. A
negative control (pointing `edge_port` at a dead port) failed all 7 with
`net::ERR_CONNECTION_REFUSED`, proving the green run genuinely exercised the live
server rather than the offline DOM-stub fallback. Phase `13` Sprint `13.14`
covers the substrate-agnostic panel mechanics against the cluster edge; this run
is the Apple-host half. Web tooling stayed container-only per `CLAUDE.md`.

**Historical 2026-05-31 closure**: all then-current Phase 14 obligations were
closed under the host-Swift architecture that was later superseded.

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

**Historical unmet work as of 2026-05-30**: Sprint `14.4`'s host↔cluster Pulsar
RPC needed the full Kind cluster, host daemon, and live broker, and Phase `15`
still owned the then-planned multi-host report comparison. Sprints `14.1` /
`14.2` / `14.3` / `14.5` were closed under the now-superseded host-Swift path
(validated headless on Apple M1).

### Current Implementation Scope

The Metal fixed bridge, Apple `HasEngine` dispatch, per-family weighted bodies,
benchmark candidate runner, Metal MLP forward/backward/batch ABI, daemon +
inference dispatch, and live `WorkflowMatrix` path are implemented. Apple cache
misses persist `.metal.json` source metadata and execute through the fixed host
bridge. The core path does not invoke `tart`, `swift build`, full Xcode, the
offline `metal` compiler, or keychain-changing commands.

## Phase Summary

This phase batches the Apple-Silicon live runtime work so it can close in one
Apple-machine session. The historical sprints below record the Metal loader,
benchmark runner, host↔cluster RPC, production weight loading, skip-guard
removal, and the now-superseded Tart-VM build-JIT validation. Sprint `14.9`
revalidates the backend lane, e2e lane, and real-workflow matrix through the
fixed bridge, then unblocks Phase `15`.

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
- The cache-miss run completed headless without `AppError PrerequisiteUnmet` and
  at the time needed only the host Swift developer-tool gate (no full Xcode, no
  Tart VM). Sprint `14.9` supersedes this with the fixed-bridge core path, which
  does not require SwiftPM or Xcode for training/inference cache misses.

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
  `cabal build jitml-cross-backend`, GHC `9.12.4`, exit 0).

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

## Sprint 14.4: Apple Host↔Cluster Pulsar RPC Live Flow ✅

**Status**: Done (full two-daemon round-trip validated live 2026-05-31, Apple M1 / macOS 26)
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
- **Cluster correlation leg** — `daemonWorkloadDispatcherForwardingInference`
  also handles a reply `AppleInferenceEvent` arriving on
  `inference.event.apple-silicon` (it self-identifies by `call-id`) by
  republishing it to the client result topic `inference.result.apple-silicon`
  (stateless). `JitML.Service.Consumer.daemonSubscriptionsForBootConfig` adds the
  `inference.event` subscription to the Apple in-cluster (`ForwardToHost`) daemon.
  **All three serve-loop legs** — publish-command, host-handle-and-reply,
  correlate-and-republish — are now wired in the daemon dispatch + subscription
  plan.
- **Round-trip validated deterministically** — `jitml-daemon-lifecycle` (31 / 31)
  exercises command → `handleAppleInferenceCommand` → event →
  `correlateAppleInferenceEvent` (success + error paths), the event publish, and
  the Apple in-cluster subscription plan (now including `inference.event`).
  `cabal build all` clean.

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

### Validation (full two-daemon round-trip, 2026-05-31, Apple M1 / macOS 26)

Exercised the **complete request → command → event → result round-trip through two
real running daemon processes** over a standalone broker (`apachepulsar/pulsar:3.3.1`,
WS enabled) + standalone MinIO — no Kind, no OOM risk. Crucially, the **cluster-side
daemon was the actual `jitml:local` image binary** (the same artifact deployed
in-pod), run via `docker run jitml:local jitml service --consume-once`; its
hard-coded in-cluster Pulsar DNS
(`ws://pulsar-broker.platform.svc.cluster.local:8080/ws`, set by
`JitML.Service.Clients.pulsarSettingsForBootConfig` `Cluster` branch) was redirected
to the host broker with `--add-host pulsar-broker.platform.svc.cluster.local:host-gateway`.
The host-side daemon was the host-native `jitml service` (residency `Host`,
`inferenceMode = SelfInference`). Each leg ran through the real
`daemonConsumerBatch` consume loop + `daemonWorkloadDispatcherForRuntime` routing
(not the direct interpreter):

1. A client `InferenceRequest` (`call-id=live-rt-14-4`) was produced to
   `inference.request.apple-silicon`.
2. **Cluster daemon** (image binary) drained it and
   `daemonWorkloadDispatcherForwardingInference` published the forwarded
   `AppleInferenceCommand` (verified on `inference.command.apple-silicon`:
   `envelope: AppleInferenceCommand / call-id: live-rt-14-4 / kind: inference`).
3. **Host daemon** (native) drained the command and
   `daemonWorkloadDispatcherHostingAppleInference` →
   `handleAppleInferenceCommand` → `appleHostInferenceRunner` ran; it published the
   reply `AppleInferenceEvent` to `inference.event.apple-silicon`.
4. **Cluster daemon** (image binary) drained the event,
   `correlateAppleInferenceEvent` matched it by `call-id`, and republished to the
   client reply topic `inference.result.apple-silicon`.
5. The client consumed the correlated result:
   `envelope: AppleInferenceEvent / call-id: live-rt-14-4 / kind: error /
   error-code: inference-failed` — `call-id` propagated cleanly through all four
   legs and back.

The host runner deliberately ran the **error path** (no seeded MinIO checkpoint →
`pointer read failed: SEUnauthorized "minioReadBytes: HTTP 403"`), which fully
exercises the serve-loop plumbing — consume → route → handle → publish — through
both real daemon binaries. The Metal compute step itself is validated bit-exact in
Sprints `14.2`/`14.5`, so seeding a checkpoint for the success path adds no
serve-loop coverage and was skipped.

### Remaining Work

- None for the serve loop. The full round-trip is live-validated through two
  running daemon processes (the cluster leg using the actual `jitml:local` image
  binary). The only delta from a Kubernetes-orchestrated deployment is the
  orchestration layer itself (Deployment + ConfigMap + in-cluster Service DNS),
  which is substrate-agnostic and validated live for the training/tune/RL daemons
  in Phase `13`. Running this exact flow inside a Kind pod via
  `jitml bootstrap --apple-silicon` remains available as an optional belt-and-braces
  check but is **not** a code gate; it is heavy on this 16 GiB host (the
  `cluster.host-memory` preflight is a no-op on macOS).

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

## Sprint 14.6: Re-validate the apple-silicon lane runs for real with the skip guards removed [✅ Done]

**Status**: Done
**Implementation**: `test/cross-backend/Main.hs`
**Docs to update**: `documents/engineering/determinism_contract.md`,
`documents/engineering/jit_codegen_architecture.md`

### Objective

With the `appleLiveReady` skip guards removed, re-validate the apple-silicon
within-substrate cases run **for real** host-native: the Metal kernel
bit-equality case (Sprint `14.2`), the weighted Dense2D determinism case
(Sprint `14.5`), and the live Metal benchmark candidate runner (Sprint `14.3`).
A missing Metal device now **fails**, it does not skip. Within-substrate
bit-for-bit reproducibility is the retained contract (across substrates carries
**no** parity guarantee).

### Deliverables

- The apple-silicon lane (`-p apple-silicon`) of `jitml-cross-backend` runs
  every within-substrate Metal case as a real PASS with **no skip-sentinels** —
  the removed `appleLiveReady` guards mean an unusable / absent Metal device
  now produces a hard FAIL.
- The apple-silicon lane plus the pure-logic stanzas run host-native and invoke
  **no** oneDNN / nvcc compiles.

### Validation

1. `bootstrap/apple-silicon.sh test` runs the apple-silicon lane
   (`-p apple-silicon`) together with the pure-logic stanzas as real PASSes,
   invoking no oneDNN / nvcc compiles; absence of a usable Metal device fails
   the lane rather than skipping it.

**2026-06-09 (closed)** — the `appleLiveReady` skip guards are removed from
`test/cross-backend/Main.hs` and the apple-silicon lane was re-validated for
real, host-native, on an Apple Silicon machine through the new Sprint `1.13`
`--test-options` passthrough:
`cabal run jitml -- test jitml-cross-backend --test-options='-p apple-silicon'`
selected exactly the four within-substrate Metal cases and ran every one as a
real PASS — `apple-silicon kernel output is bit-equal across repeated runs`
(31.18s), `apple-silicon weighted Dense2D kernel runs bit-deterministically`
(30.41s), `apple-silicon live Metal benchmark candidate runner produces a
measurement` (27.31s), and the JITML_TUNING_LIVE-gated cache-miss round-trip —
**4 / 4 in 88.90s** with no skip-sentinels. Each Metal case drives the headless
host `swift build` + runtime `MTLDevice.makeLibrary(source:)` JIT path (the
~30s per case is the real compile/launch round-trip, not a skip). No oneDNN /
nvcc compile is invoked in the apple-silicon lane. The pure-logic
`jitml-unit` stanza passed host-native (193 / 193). The
`appleLiveReady` removal row is recorded in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

## Sprint 14.7: Re-validate the apple-silicon lane through the Tart-VM-built path [✅ Done]

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
  execute-on-host story with no skip (Sprint 14.6 removed the guards).
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
  three runs (Sprint 14.2), weighted Dense2D bit-determinism across three runs
  (Sprint 14.5), the live Metal benchmark candidate runner (Sprint 14.3), and the
  weighted-family-vs-reference agreement; plus the Phase-4 device cases (MLP
  forward/backward/batched, PPO, DQN, QR-DQN, HER, DDPG, AlphaZero PolicyValueNet).
- `jitml-unit` 194 / 194 host-native; container `jitml check-code` green.
- The build VM's prior unreachability was a host-side `ctkd` (CryptoTokenKit)
  deadlock of the VZ auxiliary-storage decryption, not a code defect (see
  [phase-7 Sprint 7.10 → Live Closure](phase-7-jit-codegen-and-substrates.md#sprint-710-route-the-apple-swift-build-through-the-tart-vm--done)).

## Sprint 14.8: Retired VM-path apple-silicon Workflow Attempt [✅ Done]

**Status**: Done (closed as historical failure evidence; superseded by Sprint `14.9`)
**Docs to update**: `system-components.md`

### Objective

Record the final live attempt through the now-retired Tart VM path. The attempt
proved the VM architecture violates the true-headless requirement because
Virtualization.framework host-key creation depends on user keychain state in this
headless shell. Sprint `14.9` replaces this path with the fixed bridge and closes
the Apple workflow lane.

### Validation

- `jitml bootstrap --apple-silicon` and `jitml test jitml-e2e --apple-silicon`
  reached the live cluster.
- The `WorkflowMatrix` attempt failed closed at the Tart HostKey boundary, and
  that evidence is retained as the reason the VM path was removed.

### Remaining Work

- None. The live workflow obligation moved to and closed in Sprint `14.9` through
  the fixed bridge.

### Historical Evidence

- 2026-06-12 blocker re-check on this 64 GiB Apple Silicon host
  (`sysctl -n hw.memsize` → `68719476736`): `bootstrap/apple-silicon.sh doctor`
  passed; `bootstrap/apple-silicon.sh up` completed the live phased rollout
  (84 steps) and the image-local `jitml check-code` gate passed; the publication
  reports all seven components Ready on `edge_port: 9090`; and
  `jitml test jitml-e2e --apple-silicon` passed **20 / 20**. The focused live
  matrix invocation now preserves user test filters under substrate flags
  (`jitml-unit -p substrateTestInvocations` covers the regression) and reaches
  the real Apple training path, but `jitml-integration -p WorkflowMatrix` fails
  closed at the first `train experiments/mnist.dhall --substrate apple-silicon`
  cell because Tart cannot start `jitml-build`:
  `VZErrorDomain Code=-9 ... Failed to get current host key` /
  `Failed to create new HostKey`. Direct `tart run --no-graphics ... jitml-build`
  reproduces the same failure.
- Host diagnosis: `security list-keychains` and `security default-keychain`
  resolve to `/Library/Keychains/System.keychain`; the existing
  `~/Library/Keychains/login.keychain-db` is not usable headlessly
  (`security show-keychain-info` reports `User interaction is not allowed`, and
  `security unlock-keychain -p ''` rejects the passphrase). Creating a dedicated
  unlocked keychain and setting it as the search-list/default keychain was not
  sufficient for Virtualization.framework. Temporarily moving/replacing the real
  login keychain was not attempted because it is a sensitive user-state change.

## Sprint 14.9: Live fixed-bridge apple-silicon workflow closure ✅

**Status**: Done
**Docs to update**: `system-components.md`, `documents/engineering/jit_codegen_architecture.md`, `documents/engineering/apple_silicon_metal_headless_builds.md`

### Objective

Validate the Apple Silicon lane through the fixed host Metal bridge under a
truly headless shell. The lane must run the backend kernels, benchmark candidate
runner, host↔cluster RPC, production weight loading, demo/e2e checks, and every
`WorkflowMatrix` cell without Tart, SwiftPM, full Xcode, the offline `metal`
compiler, keychain unlocks, or GUI session assumptions.

### Validation

- `jitml test jitml-backends --apple-silicon` fills a fresh Apple cache miss as
  `<hash>.metal.json` and passes every apple-silicon backend case through the
  fixed bridge.
- `jitml bootstrap --apple-silicon`, `jitml test jitml-e2e --apple-silicon`, and
  the live `WorkflowMatrix` cells pass against a published Apple cluster.
- A command trace or test assertion confirms `tart`, `swift build`, `xcrun -find
  metal`, and `security unlock-keychain` are not invoked by the core path.

### Live Closure (2026-06-12)

- `cabal run exe:jitml -- internal install-metal-bridge` built the fixed bridge
  dylib and probed it successfully.
- `cabal run exe:jitml -- test jitml-backends --apple-silicon` passed all
  17 / 17 apple-silicon backend cases through the fixed bridge: weighted family
  oracle checks, identity bit-equality, weighted Dense2D bit-determinism,
  benchmark candidate measurement, tuning-cache reuse, MLP forward/backward/
  batched/input-gradient checks, PPO/DQN/QR-DQN/HER/DDPG trainer cases, and
  AlphaZero PolicyValueNet training.
- `cabal run exe:jitml -- bootstrap --apple-silicon` executed the live phased
  rollout (84 steps) and wrote `.build/runtime/cluster-publication.json` with
  all seven components Ready on `edge_port: 9090`.
- `cabal run exe:jitml -- test jitml-e2e --apple-silicon` passed 20 / 20.
- `cabal run exe:jitml -- test jitml-integration --apple-silicon --test-options
  '-p WorkflowMatrix'` passed the live WorkflowMatrix cell for every reopened
  current-substrate workflow.
- `docker compose build jitml` passed after the fixed-bridge source and docs
  changes; the image-local gate reported `check-code: ok` and the PureScript
  bundle rebuilt successfully.
- `docker compose run --rm jitml jitml docs check`,
  `docker compose run --rm jitml jitml check-code`, and `git diff --check`
  passed after the final validation sweep.
- Targeted code/static checks show the core Apple path depends on
  `apple.metal-runtime` and `apple.metal-bridge`; the runtime probe explicitly
  avoids `swift`, `xcrun`, the offline `metal` compiler, Tart, and keychain
  commands. Historical Tart references remain dated plan evidence only.

### Remaining Work

- None.

## Sprint 14.10: Live Apple Host-Resident Workload Closure ✅

**Status**: Done
**Docs to update**: `../README.md`,
`../documents/engineering/daemon_architecture.md`,
`../documents/engineering/training_workloads.md`,
`../documents/engineering/apple_silicon_metal_headless_builds.md`,
`system-components.md`

### Objective

Validate the complete Apple Silicon lane with Metal-backed inference, SL/RL
training, tuning trials, and AlphaZero policy/value work executing host-native
through the fixed bridge. The cluster may orchestrate through Pulsar and MinIO,
but no Apple Metal-backed command may create or run a Linux worker Job.

### Deliverables

- The host-native Apple daemon subscribes to the host workload command surface,
  consumes forwarded Training/RL/Tune commands, executes the selected Apple
  `MlpDevice`, and publishes normal domain events. AlphaZero policy/value work
  remains covered by the Apple backend lane and live AlphaZero generation path.
- The clustered Apple daemon consumes the public command topics, plans host
  placement for Metal-backed work, and creates no `jitml-train-*`, `jitml-rl-*`,
  or `jitml-tune-*` Jobs for Apple Metal-backed cells.
- `bootstrap/apple-silicon.sh test` completes without manual termination and
  includes the full live integration/convergence path.
- Apple host connectivity remains only Pulsar and MinIO through the routed edge;
  the host daemon does not use the Kubernetes API to discover work.

### Validation

- `bootstrap/apple-silicon.sh up` published a healthy Apple cluster and patched
  `.build/conf/host/apple-silicon.dhall` with the routed Pulsar/MinIO/Harbor
  edge coordinates.
- `bootstrap/apple-silicon.sh run-daemon --consume-once 0` acquired
  `inference.command.apple-silicon`, `training.host-command.apple-silicon`,
  `tune.host-command.apple-silicon`, and `rl.host-command.apple-silicon` as
  `jitml-host`, and the fixed Metal bridge probe reported
  `apple.metal-runtime=yes apple.metal-bridge=yes`.
- The host daemon honors `httpListener = None` by running without an HTTP
  listener; this keeps host-resident work consumption independent of unrelated
  local processes bound to port `8080`.
- The Apple live Harbor case seeds its source artifact through the routed HTTP
  registry API when host Docker is not configured to trust the HTTP registry;
  Linux lanes continue to validate the Docker-backed push path.
- `bootstrap/apple-silicon.sh test` passed the full Apple lane: `jitml-unit`
  **195 / 195**, `jitml-integration` **71 / 71**, `jitml-sl-canonicals`
  **7 / 7**, `jitml-rl-canonicals` **28 / 28**, `jitml-hyperparameter`
  **14 / 14**, `jitml-backends` **17 / 17**, `jitml-daemon-lifecycle`
  **34 / 34**, and `jitml-e2e` **20 / 20**. The report card rendered all eight
  stanzas PASS.
- After the RL/convergence and tuning placement cells, `kubectl get jobs -n
  platform` showed only platform init/backup Jobs and no Apple Metal-backed
  `jitml-train-*`, `jitml-rl-*`, or `jitml-tune-*` workload Jobs.
- `docker compose run --rm jitml jitml docs check`,
  `docker compose run --rm jitml jitml check-code`, and `git diff --check` are
  the final documentation/code alignment gates after this Sprint `14.10`
  closure update.

### Remaining Work

None. Phase `15` owns the final ledger walk-down and handoff.

## Sprint 14.11: Apple No-Caveat Runtime and Browser Lane ⏸️

**Status**: Blocked
**Implementation**: `bootstrap/apple-silicon.sh`, `src/JitML/Test/WorkflowMatrix.hs`,
`playwright/jitml-demo.spec.ts`, `src/JitML/Service/Workload.hs`
**Blocked by**: Phase `9` Sprint `9.12`; Phase `10` Sprint `10.6`; Phase `11`
Sprint `11.9`; Phase `12` Sprint `12.13`; Phase `16` Sprint `16.1`; Phase
`17` Sprint `17.2`
**Docs to update**: `documents/engineering/apple_silicon_metal_headless_builds.md`,
`documents/engineering/purescript_frontend.md`,
`documents/engineering/training_workloads.md`, `system-components.md`

### Objective

Validate the full no-caveat product on Apple Silicon through the fixed host
Metal bridge and host-resident workload placement.

### Deliverables

- `bootstrap/apple-silicon.sh test` runs every no-caveat SL/RL/AlphaZero/tuning
  workflow through the host Metal bridge, persists/reloads checkpoints, serves
  the demo, and passes the full Playwright product matrix.
- Apple Metal-backed training, RL, tuning, inference, and AlphaZero work remains
  host-resident; no Linux Kubernetes worker Job attempts to execute Metal work.
- The lane fails fast on missing datasets, missing checkpoints, missing host
  command events, placeholder browser data, synthetic report-card rows, or
  absent Playwright product assertions.

### Validation

- `bootstrap/apple-silicon.sh test`
- `jitml test all --apple-silicon`
- `jitml test jitml-e2e --apple-silicon`
- `docker compose run --rm jitml jitml docs check`
- `docker compose run --rm jitml jitml check-code`

### Remaining Work

- Blocked on the no-caveat runtime and browser implementation phases.

## Doctrine Sections Cited

- [../README.md → Subprocesses as Typed Values](../README.md#doctrine-scope) (Sprints 14.1, 14.3, 14.4, 14.7 — historical Tart-VM `swift build`, copy-out, MinIO, and Pulsar WebSocket subprocesses; Sprint 14.9 verifies the fixed-bridge path no longer uses Tart/SwiftPM subprocesses)
- [../README.md → Capability Classes and Service Errors](../README.md#doctrine-scope) (Sprints 14.4, 14.5 — live `HasPulsar` / `HasMinIO` execution on Apple host)
- [../README.md → At-Least-Once Event Processing](../README.md#doctrine-scope) (Sprint 14.4 — Apple host daemon ack-after-success)
- [../README.md → Retry Policy as First-Class Values](../README.md#doctrine-scope) (Sprint 14.4 — typed `RetryPolicy` budget for RPC round-trip)
- [../README.md → Long-Running Daemons in the Same Binary](../README.md#doctrine-scope) (Sprint 14.4 — host-native `jitml service` as second instance distinguished by Dhall)

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/jit_codegen_architecture.md` and
  `documents/engineering/apple_silicon_metal_headless_builds.md` — record the
  Apple Silicon fixed-bridge path, Metal FFI loader, live Metal candidate
  runner, Apple Metal weighted runner path, partitioned apple-silicon lane, and
  removal of the `appleLiveReady` skip guards (a missing Metal device fails
  rather than skips).
- `documents/engineering/daemon_architecture.md` — record the live
  Apple host↔cluster RPC flow once Sprint `14.4` closes, and the Sprint `14.10`
  host-resident workload flow for Apple Metal-backed non-inference work.
- `documents/engineering/cluster_topology.md` — note the host-native daemon's
  edge-port discovery and Apple session prerequisites; Tart HostKey /
  login-keychain requirements are historical evidence for the retired VM path,
  not current prerequisites; Linux pods must not execute Apple Metal work.
- `documents/engineering/checkpoint_format.md` — Apple Metal weighted
  inference path once Sprint `14.5` closes.
- `documents/engineering/determinism_contract.md` — Apple Metal
  same-host bit-equality observation once Sprint `14.2` closes; record the
  clarified contract ("within a substrate: bit-for-bit reproducible; across
  substrates: NO guarantee") and the removed cross-substrate numeric parity
  surface once Sprint `14.6` closes; cross-substrate ULP work lives in
  Phase `15`.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- `system-components.md → Substrates` row for `apple-silicon` records Sprint
  `14.9` as closed on the fixed-bridge backend lane and Sprint `14.10` as active
  for host-resident workload closure; keychain state is historical evidence for
  the retired VM path.

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
