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

This doc defers to [../../HASKELL_CLI_TOOL.md](../../HASKELL_CLI_TOOL.md) for:

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

Sprints `1.1` through `1.9` have landed the Cabal scaffold, registry-backed CLI,
generated-docs reconciler, lint stack, typed `Plan` modules, typed
`Subprocess` boundary, prerequisite registry, single `Env` record with the
`ReaderT Env IO` alias, the canonical `AppError` ADT, `renderError`, global
output flags, and the CLI output module. `--dry-run` and `--plan-file <path>`
now render command plans for the registered Plan/Apply surfaces; concrete apply
bodies remain owned by later feature sprints.

## jitML Project-Specific Surfaces

### Lifecycle GADTs

Per doctrine `GADT-Indexed State Machines`, jitML carries three GADT-indexed
lifecycles:

| GADT | Indices | Owning module |
|------|---------|---------------|
| `TrainingLifecycle` | `Loaded \| Ready \| Stepping \| Evaluating \| Checkpointing \| Finished` | `src/JitML/SL/Loop.hs` |
| `RLRunLifecycle` | `Loaded \| Ready \| Collecting \| Optimising \| Evaluating \| Checkpointing \| Finished` | `src/JitML/RL/Loop.hs` |
| `TuneSweepLifecycle` | `Sampled \| Scheduled \| Running \| Pruned \| Reported \| Finished` | `src/JitML/Tune/Sweep.hs` |

The doctrine forbids the runtime-status-enum-with-manual-validation pattern;
each lifecycle is a phantom-type-indexed GADT with singleton witnesses.

### Capability Classes

| Class | Operations | Owning module |
|-------|-----------|---------------|
| `HasMinIO` | `putBlobIfAbsent`, `casPointer`, `getObject`, `listPrefix` | `src/JitML/Service/Caps/MinIO.hs` |
| `HasPulsar` | `subscribe`, `produce`, `ack`, `seek` | `src/JitML/Service/Caps/Pulsar.hs` |
| `HasHarbor` | `pushImage`, `getImage`, `deleteImage` | `src/JitML/Service/Caps/Harbor.hs` |
| `HasKubectl` | `applyManifest`, `getResource`, `deleteResource` | `src/JitML/Service/Caps/Kubectl.hs` |

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

- `kubectl`, `helm`, `kind`, `docker`, `tart`, `cabal`, `pulumi`,
  `npx playwright`, `spago`, `pulsar-admin`, `mc` (MinIO CLI), `metal`,
  `nvcc`, `g++` (over oneDNN), `swift build` (inside the tart VM via `tart
  ssh`), `dhall freeze`, `proto-lens-protoc`.

`callProcess`, `readCreateProcess`, `System.Process.*`, `typed-process`
smart constructors are hlint-forbidden outside the interpreter module.

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
  `tart` follows this path lazily on the first Apple JIT cache miss, not during
  bootstrap or host-daemon startup.

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
- `LiveConfig` Dhall: log level, `RetryPolicy`, `tartIdleTimeout` (Apple),
  inference batch / latency, `drainDeadlineSeconds`.
- SIGHUP triggers `LiveConfig` reload; restart-required field changes emit
  `AppError InvalidConfig` with exit `2`.
- `/healthz`, `/readyz`, `/metrics` are mandatory.
- Logging: structured JSON on stderr.
- At-least-once Pulsar consumer with protobuf-message-hash deduplication.

## Cross-References

- [../../HASKELL_CLI_TOOL.md](../../HASKELL_CLI_TOOL.md)
- [../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md](../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md)
- [../../DEVELOPMENT_PLAN/phase-5-jitml-service-daemon.md](../../DEVELOPMENT_PLAN/phase-5-jitml-service-daemon.md)
- [daemon_architecture.md](daemon_architecture.md)
- [../documentation_standards.md](../documentation_standards.md)
