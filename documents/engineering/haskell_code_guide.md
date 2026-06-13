# Haskell Code Guide

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: README.md, ../documentation_standards.md, ../../DEVELOPMENT_PLAN/phase-0-planning-documentation.md, ../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md, daemon_architecture.md
**Generated sections**: none

> **Purpose**: Project-specific Haskell code patterns for jitML. Defers to the
> doctrine for the patterns it owns; names jitML's lifecycle ADTs, the
> capability classes, the 17-variant `AppError` enumeration, the typed
> `Subprocess` consumers, the `Plan` / `apply` consumers, and the daemon
> shape.

## Doctrine Deferrals

This doc defers to [../../README.md](../../README.md) for:

- **GADT-Indexed State Machines** — phantom-type indices, singleton
  witnesses, the forbidden runtime-status-enum-with-manual-validation
  pattern.
- **Architecture → Subprocesses as Typed Values** — `Subprocess` ADT plus
  `runStreaming` / `capture` interpreter; `renderSubprocess` pure;
  forbidden primitives.
- **Plan / Apply** — `build :: inputs -> Either AppError Plan` /
  `apply :: Env -> Plan -> IO ExitCode`, with `--dry-run` and
  `--plan-file <path>` on every Plan/Apply command.
- **Prerequisites as Typed Effects** — `prerequisiteRegistry`, `nodeId`,
  `nodeDescription`, remedy hint, `AppError PrerequisiteUnmet`, typed lazy
  package remediation.
- **Application Environment** — `ReaderT Env IO`, single `Env` record.
- **Error Handling** — single `AppError` ADT, `renderError`, forbidden
  `print`/`exitFailure` outside the output module.
- **Capability Classes and Service Errors** — `HasMinIO`, `HasPulsar`,
  `HasHarbor`, `HasKubectl`; service errors `SEConflict`, `SEUnauthorized`,
  `SETimeout`, `SETransient`.
- **Retry Policy as First-Class Values** — `RetryPolicy` typed value with
  named strategies; `retryServiceAction` harness.
- **Long-Running Daemons in the Same Binary** — `Lifecycle: load → prereq
  → acquire → ready → serve → drain → exit`, `BootConfig` /
  `LiveConfig`, SIGHUP hot reload, `/healthz` / `/readyz` / `/metrics`,
  structured JSON logging on stderr, recoverable-vs-fatal error kinds.
- **At-Least-Once Event Processing** — protobuf-message-hash deduplication;
  Pulsar consumer semantics.
- **Reconcilers: Idempotent Mutation as a Single Command** — exit code `3`
  on no-op-on-match.

## Current Implementation Status

Sprints `1.1` through `1.9` have landed the Cabal
scaffold, registry-backed CLI, generated-docs reconciler, typed `Plan` modules,
typed `Subprocess` boundary, prerequisite registry, single `Env` record with the
`ReaderT Env IO` alias, the canonical `AppError` ADT, `renderError`, global
output flags, CLI output module, and full lint/check-code stack. `--dry-run`
and `--plan-file <path>` now render command plans for the registered Plan/Apply
surfaces; concrete apply bodies remain owned by later feature sprints.

## jitML Project-Specific Surfaces

### Lifecycle GADTs

Per doctrine `GADT-Indexed State Machines`, jitML carries three GADT-indexed
lifecycles:

| GADT | Indices (data kind) | Owning module |
|------|---------------------|---------------|
| `TrainingLifecycle` | `TrainingPhase`: `TrainingConfigured \| TrainingCollecting \| TrainingOptimizing \| TrainingEvaluating \| TrainingCheckpointing` | `src/JitML/RL/Framework.hs` |
| `RLRunLifecycle` | `RLRunPhase`: `RLCollect \| RLComputeAdvantages \| RLOptimise \| RLEvaluate \| RLCheckpoint` | `src/JitML/RL/Framework.hs` |
| `TuneSweepLifecycle` | `TuneSweepPhase`: `SweepConfigured \| SweepScheduling \| SweepRunningTrial \| SweepPruning \| SweepCompleted` | `src/JitML/RL/Framework.hs` |

The doctrine forbids the runtime-status-enum-with-manual-validation pattern;
each lifecycle is a phantom-type-indexed GADT with singleton witnesses
(`STrainingConfigured`, `SRLCollect`, `SSweepConfigured`, etc.). All three
GADTs currently co-locate in `src/JitML/RL/Framework.hs`; daemon-backed
runtime expansion may later split them into per-domain `Loop.hs` / `Sweep.hs`
homes, but the type-level shape is fixed.

### Capability Classes

| Class | Operations | Owning module |
|-------|-----------|---------------|
| `HasMinIO` | `minioPutIfAbsent`, `minioReadObject`, `minioReadBytes`, `putBlobIfAbsent`, `putBlobBytesIfAbsent`, `casPointer`, `listObjects`, `deleteObject` | `src/JitML/Service/Capabilities.hs` |
| `HasPulsar` | `pulsarPublish`, `pulsarAcknowledge`, `pulsarSubscribe`, `pulsarConsume`, `pulsarSeek` | `src/JitML/Service/Capabilities.hs` |
| `HasHarbor` | `harborImageExists`, `harborPromoteImage`, `harborPushImage`, `harborPullImage`, `harborListImages` | `src/JitML/Service/Capabilities.hs`; subprocess instance in `src/JitML/Service/HarborSubprocess.hs` |
| `HasKubectl` | `kubectlApply`, `kubectlStatus`, `kubectlGet`, `kubectlDelete` | `src/JitML/Service/Capabilities.hs` |

`HasKubectl` operations route through the typed `Subprocess` boundary.

### Canonical `AppError` Enumeration (17 Variants)

Defined in `src/JitML/AppError/AppError.hs`:

| Variant | Triggered by | Exit code |
|---------|--------------|-----------|
| `PrerequisiteUnmet` | Prerequisite reconciler failure | `2` |
| `SubprocessFailed` | Typed `Subprocess` boundary non-zero exit | `1` |
| `MinIOFailed` | `HasMinIO` operation failure (after `RetryPolicy`) | `1` |
| `PulsarFailed` | `HasPulsar` operation failure | `1` |
| `HarborFailed` | `HasHarbor` operation failure | `1` |
| `KubectlFailed` | `HasKubectl` operation failure | `1` |
| `DocsCheckDrift` | `jitml docs check` marker / file drift | `1` |
| `UnknownCommand` | Parser failure or substrate-only command on wrong substrate | `1` |
| `InvalidConfig` | `BootConfig` field changed under SIGHUP, or schema mismatch | `2` |
| `DhallTypeError` | Dhall decoding failure | `1` |
| `ChartLintFailed` | Chart-shape lint failure | `1` |
| `RouteRegistryDrift` | Route registry / generated HTTPRoute drift | `1` |
| `JitCacheMiss` | FFI loader could not resolve a kernel artefact | `1` (recovered by JIT compile) |
| `JitToolchainDrift` | `ToolchainFingerprint` mismatch against a cached artefact | `1` |
| `CheckpointFormatUnsupported` | `.jmw1` magic / version mismatch | `1` |
| `CheckpointWriteConflict` | `If-Match: <etag>` exhausted retries | `1` |
| `ReconcilerNoop` | Reconciler-on-match — no-op | `3` |

`renderError :: AppError -> Text` is the only Text rendering at the CLI
boundary, defined in `src/JitML/CLI/Output.hs`.

### Wrapped Subprocess Surface

Per doctrine `Architecture → Subprocesses as Typed Values`, every external
program invocation flows through the typed `Subprocess` boundary
(`runStreaming` / `capture` interpreters in `src/JitML/Sub/Stream.hs`):

- `kubectl`, `helm`, `kind`, `docker`, `cabal`,
  `npx playwright`, `spago`, `pulsar-admin`, `mc` (MinIO CLI),
  `nvcc`, `g++` (over oneDNN), `/usr/bin/clang` for the fixed Apple Metal
  bridge installer, `dhall freeze`, `proto-lens-protoc`.

Core Apple Metal cache misses are not subprocess builds: Haskell writes
`<hash>.metal.json`, then the fixed bridge JIT-compiles MSL in-process through
`MTLDevice.makeLibrary(source:)`.

`callProcess`, `readCreateProcess`, `System.Process.*`, `typed-process`
smart constructors are hlint-forbidden outside the interpreter module.

The bootstrap reconciler's remaining embedded `sh -c` control-flow (kind
create/delete, helm dependency-build guard, postgres schema grant, and the
MinIO/Pulsar readiness retry loops) moves to typed multi-step Haskell over leaf
`subprocess` values, with retries expressed through the typed `RetryPolicy` rather
than shell `for`/`sleep` — Phase `2` Sprint `2.9` and Phase `4` Sprint `4.8` under
`Subprocesses as Typed Values` and `Retry Policy as First-Class Values`. Run
parameters reach worker Jobs as a typed Dhall `RunConfig` (not `JITML_*` env vars)
under `Application Environment` (Phase `5` Sprint `5.7`). See
[Development Plan → Reopened phases](../../DEVELOPMENT_PLAN/README.md#reopened-phases-2026-05-29).

### Plan/Apply Consumers

Every command that mutates external state is Plan/Apply:

- `jitml bootstrap`, `jitml train`, `jitml tune`, `jitml rl train`,
  `jitml cluster up`, `jitml test all`, `jitml internal gc`, `jitml service`
  startup-as-plan.

All support `--dry-run` and `--plan-file <path>`.

### Lazy Prerequisite Remediation

Stage-0 shell scripts only check the host gates needed to reach Haskell.
Package validation and installation lives in the typed prerequisite DAG:

- A Homebrew package prerequisite is a typed value with a package identifier,
  validation predicate, install/upgrade policy, remedy hint, dependencies, and
  postcondition.
- The pure Plan phase decides which packages are missing and renders the
  intended `brew` actions.
- The apply phase executes through the typed `Subprocess` interpreter and then
  re-validates each postcondition before dependent nodes run.
- Ad hoc `brew install` calls in shell scripts or command runners are forbidden.
  The core Apple prerequisite surface is `apple.metal-runtime` plus
  `apple.metal-bridge`; the bridge installer compiles the fixed bridge with the
  system clang and Metal/Foundation frameworks, then probes the exported symbols.
  Tart, full Xcode, SwiftPM, the offline `metal` compiler, and keychain-changing
  commands are not remediation nodes for the training/inference cache-miss path.
  Optional generated Swift modules, if added later, must use explicit
  `apple.swiftc` + `apple.macos-sdk` probes and remain outside the core JIT path.

### Reconcilers (exit `3` on no-op)

- `jitml bootstrap` — already-converged substrate stack.
- `jitml cluster up` — already-converged lower-level cluster lifecycle.
- `jitml docs generate` — already-current generated regions.
- `jitml lint --write` — nothing to fix.
- `jitml internal gc <experiment-hash>` — steady-state retention.

### Daemon Shape

Per doctrine `Long-Running Daemons in the Same Binary`, `jitml service`:

- `BootConfig` Dhall: `substrate`, `residency`, `inferenceMode`, Pulsar /
  MinIO / Harbor connection info, HTTP listener.
- `LiveConfig` Dhall: log level, `RetryPolicy`, inference batch / latency,
  dedup cache size / TTL, `drainDeadlineSeconds`.
- SIGHUP triggers `LiveConfig` reload; restart-required field changes emit
  `AppError InvalidConfig` with exit `2`.
- `/healthz`, `/readyz`, `/metrics` are mandatory.
- Logging: structured JSON on stderr.
- At-least-once Pulsar consumer with protobuf-message-hash deduplication.

## Cross-References

- [../../README.md](../../README.md)
- [../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md](../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md)
- [../../DEVELOPMENT_PLAN/phase-5-jitml-service-daemon.md](../../DEVELOPMENT_PLAN/phase-5-jitml-service-daemon.md)
- [daemon_architecture.md](daemon_architecture.md)
- [../documentation_standards.md](../documentation_standards.md)
