# Apple Silicon Metal Headless Builds

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: README.md
**Generated sections**: none

> **Purpose**: Define the target architecture for a truly headless Apple Silicon
> Metal JIT path that avoids Tart, keychain state, Xcode UI flows, and per-cache-
> miss Swift builds.

## Summary

The Apple Silicon JIT path should compile generated Metal Shading Language (MSL)
at runtime through the OS Metal framework, using a fixed host bridge that is built
or verified when jitML itself is built from source. A JIT cache miss should never
start a VM, invoke SwiftPM, compile a generated Swift package, ask for an Xcode
license, or depend on a user login keychain.

Target cache-miss path:

```text
Haskell renders MSL + launch metadata
  -> write content-addressed .metal.json cache record
  -> call fixed host Metal bridge
  -> bridge calls MTLDevice.makeLibrary(source:options:)
  -> bridge creates pipeline + command buffer
  -> bridge dispatches on the host GPU
```

The current Tart-VM path is retained only as current-state context in
[jit_codegen_architecture.md](jit_codegen_architecture.md#apple-silicon-tart-vm-build-jit)
and the development plan. This document describes the replacement target for
true headless operation.

## Requirements

The Apple Silicon JIT path must satisfy these constraints:

- **No interactive session dependency.** Cache misses must work from an SSH
  session, daemon context, CI runner, and `launchd` background service.
- **No keychain requirement.** Cache misses must not require an unlocked
  `login.keychain-db`, Secure Enclave prompt, or `security unlock-keychain`.
- **No Xcode app dependency.** Full Xcode is not installed on the host.
- **No offline `metal` compiler.** The Command Line Tools do not reliably ship
  `metal`; the core path must not require it.
- **No per-kernel Swift build.** A cache miss should not generate a Swift package
  and invoke `swift build`; that turns model cache misses into host-toolchain
  cache misses.
- **Same-substrate determinism.** The Apple path must preserve the
  [determinism contract](determinism_contract.md#apple-silicon-metal): fast math
  off, fixed reduction tree, and single-stream launch ordering unless a future
  tuning choice explicitly records a different deterministic launch discipline.

## Verification Findings

On 2026-06-12, a headless probe established the viable primitive:

- `/usr/bin/swiftc` from Command Line Tools can compile a Swift dylib that imports
  `Metal`.
- A separate process can `dlopen` that dylib and resolve a C-exported symbol.
- The dylib can call `MTLDevice.makeLibrary(source:options:)`, compile MSL from a
  string at runtime, dispatch a compute kernel, and return the expected output.
- `xcrun -find metal` fails on the same host, proving the probe did not use the
  offline `metal` compiler.
- Tart, keychain unlocks, VM startup, and GUI tools are not involved.

The probe returned:

```text
jitml_metal_runtime_probe=0
```

Homebrew's `swift` formula also installed headlessly as a bottled, keg-only
toolchain under `/opt/homebrew/opt/swift`. It could compile the same Swift +
Metal probe only after an SDK was supplied explicitly:

```sh
SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
/opt/homebrew/opt/swift/bin/swiftc -sdk "$SDKROOT" ...
```

Without `-sdk` / `SDKROOT`, Homebrew Swift failed to import `Darwin`. The
important conclusion is that `swiftc` is not the whole prerequisite for Swift +
Apple-framework builds: a macOS SDK must also be present and discoverable.

## Target Architecture

### Fixed Host Metal Bridge

jitML should have one fixed Apple Metal bridge for the process. The bridge may be
implemented in one of two viable forms:

- **Objective-C/C bridge** built with jitML from source and linked into the host
  binary or installed as a fixed `.dylib`.
- **Haskell Objective-C-runtime bridge** that calls the Metal framework directly
  through `objc_msgSend`, `MTLCreateSystemDefaultDevice`, and CoreFoundation /
  Foundation helpers.

The Objective-C/C bridge is the pragmatic first implementation. It exposes a
stable C ABI to Haskell and keeps Metal API details out of the generated JIT
artifacts:

```c
int jitml_metal_run(
  const char *metal_source,
  const char *function_name,
  const float *input,
  size_t input_count,
  const float *weights,
  size_t weight_count,
  float *output,
  size_t output_count,
  const struct jitml_metal_launch *launch,
  char *error_buffer,
  size_t error_buffer_len
);
```

The bridge owns:

- `MTLCreateSystemDefaultDevice()`
- `MTLCompileOptions` with fast math disabled (`mathMode = safe` on modern macOS,
  `fastMathEnabled = false` fallback)
- `MTLDevice.makeLibrary(source:options:)`
- compute pipeline creation
- command queue / command buffer / encoder construction
- input, output, and weight buffer allocation
- dispatch and `waitUntilCompleted`
- structured error capture into the Haskell-facing error buffer

The Haskell side owns:

- generated MSL rendering
- content-addressed cache key derivation
- source/metadata cache persistence
- bridge prerequisite verification
- input/output shape validation
- conversion from bridge return codes into `AppError`

### Cache Format

The Apple cache artifact should become source metadata, not a dylib:

```text
.build/jit/apple-silicon/<hash>.metal.json
```

Candidate record fields:

```json
{
  "abi": "jitml-metal-source-v1",
  "substrate": "apple-silicon",
  "family": "Dense2D",
  "functions": {
    "unweighted": "jitml_kernel",
    "weighted": "jitml_weighted_kernel"
  },
  "output_count": {
    "kind": "same-as-input"
  },
  "threadgroup_size": 256,
  "compile_options": {
    "fast_math": false,
    "math_mode": "safe"
  },
  "source_sha256": "...",
  "source": "..."
}
```

The source string is the canonical JIT payload. The cache key includes the
rendered source, launch metadata, bridge ABI version, Metal runtime policy, and
determinism options. This mirrors the existing doctrine that generated compiler
inputs are content-addressed, but changes the Apple compiler input from Swift
package source to MSL source.

### In-Process Pipeline Cache

Runtime MSL compilation has nonzero latency. jitML should therefore keep an
in-process cache:

```text
(device-registry-id, source-sha256, function-name, launch-policy) -> pipeline
```

On the first call in a process, the bridge compiles the MSL source and creates
the pipeline. Later calls in the same daemon process reuse the pipeline. This is
the cache-miss-resistant part that matters for training loops: a model cache miss
may pay the compile once, but not on every batch.

The process cache is an optimization only. The persistent source cache remains
the correctness artifact.

### Optional Binary Archive

Metal's `MTLBinaryArchive` can be added as a second-level performance cache. It
should never be the source of truth:

- If the archive exists and is valid, use it to accelerate pipeline creation.
- If it is missing, stale, invalid for the OS/GPU, or rejected by the runtime,
  fall back to compiling the cached MSL source.
- The archive path should include the device identity and OS/Metal runtime
  fingerprint.

This keeps cache misses reliable. Binary archives are not portable enough to
replace source artifacts.

## Build and Prerequisite Model

The headless Apple substrate should have separate prerequisites:

| Prerequisite | Required for | Install / verify |
|--------------|--------------|------------------|
| `apple.metal-runtime` | Core execution | Probe `MTLCreateSystemDefaultDevice` and a tiny runtime `makeLibrary(source:)` dispatch. |
| `apple.metal-bridge` | Core execution | Build or verify the fixed bridge, then `dlopen` and call its probe symbol. |
| `apple.swiftc` | Optional Swift JIT modules | Prefer Homebrew `swift`; verify `swiftc --version` and compile a Swift + Metal probe with explicit SDK. |
| `apple.macos-sdk` | Optional Swift / Objective-C source builds | Verify `xcrun --sdk macosx --show-sdk-path` or an explicitly configured SDK path. |

The core Metal JIT path requires `apple.metal-runtime` and `apple.metal-bridge`.
It does **not** require `apple.swiftc` during cache misses.

If jitML is always built from source, then building the fixed bridge from source
is acceptable at jitML build time. That build-time prerequisite is different from
a runtime JIT prerequisite. A source-build bootstrap may install Homebrew tools
or use an existing SDK, but `jitml service` and cache misses must not install
tools or wait on toolchain interactions.

## Optional Swift JIT Lane

jitML can still support arbitrary generated Swift modules, but this should be a
separate capability from the core Metal JIT:

```text
jitml internal swift-jit compile <generated-swift-dir>
```

That lane is enabled only when `apple.swiftc` and `apple.macos-sdk` pass a real
compile-and-load probe. It may produce a `.dylib` from generated Swift source.
It is useful for future host-side adapters, diagnostics, or non-kernel Swift
experiments.

It must not be the default training/inference cache-miss path. Swift compilation
brings host toolchain discovery, SDK discovery, Swift runtime linkage, and
package/build-system behavior into the critical path. The core Metal path needs
only the OS Metal runtime compiler.

## Why Tart Is Not Viable

Tart sounds attractive because it keeps the full Apple toolchain out of the host.
In practice it violates the headless contract.

The blocker is macOS `Virtualization.framework`, not ordinary Unix file
permissions. On headless macOS 15+ setups, Tart documents that VM startup may
require an unlocked `login.keychain`. The observed failure is:

```text
VZErrorDomain Code=-9
Failed to get current host key
Failed to create new HostKey
```

This is user-session keychain state. Running with `sudo` changes the problem
rather than solving it: root has a different environment, different keychains,
and a different Tart VM store. Unlocking or replacing the user login keychain can
make a machine work, but it is not a reliable daemon prerequisite and is
unacceptable for cache misses.

Tart also makes every first compile depend on VM lifecycle health: guest boot,
guest agent readiness, shared-mount behavior, resource sizing, and host security
state. Those are too many moving parts for a JIT miss.

## Why Full Xcode Is Not Viable

Full Xcode has the tools, but it is not appropriate for jitML's headless host
runtime:

- It is a GUI app with license and first-run surfaces.
- It is large, mutable host state outside jitML's typed prerequisite boundary.
- It includes the offline `metal` compiler, which tempts the architecture back
  toward ahead-of-time `.metallib` builds rather than runtime source JIT.
- Installing or updating it is not a reasonable side effect of `jitml bootstrap`.

The host should use OS frameworks already present on macOS for runtime Metal
execution. Source builds may use command-line compilers, but the runtime JIT path
must not require Xcode.

## Why Command Line Tools `swift build` Is Not Enough

The 2026-05-30 headless path proved that Command Line Tools `swift build` plus
runtime `MTLDevice.makeLibrary(source:)` can work. It is still not the best core
architecture.

The problem is not only interactivity; it is cache-miss coupling. A generated
Swift package per kernel means every first model shape must:

- materialize a Swift package,
- invoke SwiftPM / `swift build`,
- produce a dylib,
- copy or publish the dylib,
- `dlopen` generated code,
- resolve generated symbols.

That is much heavier than compiling MSL source in the Metal runtime. It also
requires a host Swift toolchain for every machine that may experience a cache
miss. For jitML, Swift is glue. The GPU kernel source is MSL. The JIT should
compile the kernel source, not rebuild glue code.

Command Line Tools Swift remains useful for source-building the fixed bridge or
for optional Swift JIT modules. It should not sit in the inner Apple cache-miss
path.

## Why Homebrew Swift Alone Is Not Enough

Homebrew Swift is promising because it is headless and Apache-2.0 licensed. It is
also keg-only on macOS and installs an Xcode-style toolchain under:

```text
/opt/homebrew/opt/swift/Swift-6.2.xctoolchain
```

However, the compiler alone is not enough to build Swift that imports Apple
frameworks. The verified Homebrew Swift probe failed to import `Darwin` until an
SDK was supplied explicitly. Therefore `apple.swiftc` must be paired with
`apple.macos-sdk` and validated by a real compile-and-load probe.

This is acceptable for optional Swift JIT modules. It is not necessary for the
core Metal source JIT.

## Why Offline `.metallib` Is Not the Core Path

Offline `.metallib` generation requires the `metal` compiler. Command Line Tools
do not reliably provide it; on the verified host, `xcrun -find metal` failed.
Using `.metallib` therefore pushes jitML back toward full Xcode or a VM.

Runtime source compilation through `MTLDevice.makeLibrary(source:options:)` is
the headless primitive that exists on the target OS and target GPU. It also
compiles for the actual device that will execute the kernel, which is the right
shape for a JIT.

## Migration Plan

1. Add `JitML.Engines.MetalBridge` with a small probe and C ABI wrapper.
2. Replace `GeneratedMetalPackage` with a Metal-source runtime artifact or add a
   new `GeneratedMetalSource` constructor.
3. Change `compileSubprocess AppleSilicon` so the core path no longer renders
   `swift build` or `tart exec`.
4. Change `ensureKernelArtifact AppleSilicon` to write/read
   `<hash>.metal.json` and treat source materialization as the cache fill.
5. Change `MetalLocal` to call the fixed bridge instead of `dlopen`ing a
   generated kernel dylib.
6. Add an in-process pipeline cache in the bridge or Haskell wrapper.
7. Add optional `MTLBinaryArchive` persistence after the source path is correct.
8. Keep optional `apple.swiftc` / `apple.macos-sdk` prerequisites for a separate
   Swift JIT lane.
9. Remove Tart from the runtime JIT prerequisite graph once the source path is
   validated by the apple-silicon backend and live workflow lanes.

## Validation Gates

Minimum closure gates for this architecture:

- A headless bridge probe compiles MSL from source and dispatches a known kernel.
- `xcrun -find metal` may fail; validation must still pass.
- `security list-keychains` may omit an unlocked login keychain; validation must
  still pass.
- `tart list` / `tart run` are not invoked by `jitml service`, `jitml train`,
  `jitml inference run`, or Apple backend tests.
- First cache miss writes `<hash>.metal.json`, compiles MSL through the bridge,
  and runs the kernel.
- Cache hit reuses the source artifact and avoids filesystem mutation.
- Repeated runs are bit-identical within the apple-silicon lane.
- Full live `WorkflowMatrix` passes on Apple Silicon with no VM process.

## External References

- Apple Metal `MTLDevice.makeLibrary(source:options:)`:
  <https://developer.apple.com/documentation/metal/mtldevice/makelibrary%28source%3Aoptions%3A%29>
- Apple Metal `MTLBinaryArchive`:
  <https://developer.apple.com/documentation/metal/mtlbinaryarchive>
- Swift macOS installation:
  <https://www.swift.org/install/macos/>
- Homebrew Swift formula:
  <https://formulae.brew.sh/formula/swift>
- Tart headless-machine FAQ:
  <https://tart.run/faq/#headless-machines>
