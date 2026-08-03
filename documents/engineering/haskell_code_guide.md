# Haskell Code Guide

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: README.md, ../documentation_standards.md, ../../DEVELOPMENT_PLAN/phase-0-planning-documentation.md, ../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md, ../../DEVELOPMENT_PLAN/phase-8-supervised-and-rl-framework.md, ../../DEVELOPMENT_PLAN/phase-9-rl-catalog-alphazero-and-tuning.md, ../../DEVELOPMENT_PLAN/phase-10-checkpointing-and-inference.md, ../../DEVELOPMENT_PLAN/phase-262-contract-driven-live-execution-browser-and-playwright.md, daemon_architecture.md, run_contract.md
**Generated sections**: none

> **Purpose**: Project-specific Haskell code patterns for jitML. Defers to the
> doctrine for the patterns it owns; names jitML's lifecycle ADTs, the
> capability classes, the 20-variant `AppError` enumeration, the typed
> `Subprocess` consumers, the `Plan` / `apply` consumers, and the daemon
> shape.

## Doctrine Deferrals

This doc defers to [../../README.md](../../README.md) for:

- **GADT-Indexed State Machines** — phantom-type indices, singleton
  witnesses, the forbidden runtime-status-enum-with-manual-validation
  pattern.
- **Architecture → Subprocesses as Typed Values** — `Subprocess` ADT plus
  `JitML.Sub.Outcome` and the `runStreaming` / `capture` interpreter;
  `renderSubprocess` pure; forbidden primitives.
- **Plan / Apply** — `build :: inputs -> Either AppError Plan` /
  `apply :: Env -> Plan -> IO ExitCode`, with `--dry-run` and
  `--plan-file <path>` on every Plan/Apply command.
- **Prerequisites as Typed Effects** — `prerequisiteRegistry`, `nodeId`,
  `nodeDescription`, remedy hint, `AppError PrerequisiteUnmet`, typed lazy
  package remediation.
- **Application Environment** — `ReaderT Env IO`, single `Env` record.
- **Error Handling** — single `AppError` ADT, `renderError`, forbidden
  `print`/`exitFailure` outside the output module. Domain code that must
  fail closed returns `Either` / `ExceptT` / `AppError`; it does not use
  `error` as the fail-closed mechanism.
- **Capability Classes and Service Errors** — `HasMinIO`, `HasPulsar`,
  `HasHarbor`, `HasKubectl`; service errors `SEConflict`, `SEUnauthorized`,
  `SETimeout`, `SETransient`.
- **Retry Policy as First-Class Values** — `RetryPolicy` typed value with
  named strategies; `retryServiceAction` harness.
- **Long-Running Daemons in the Same Binary** — `Lifecycle: load → prereq
  → acquire → ready → serve → drain → exit`, `BootConfig` /
  `LiveConfig`, SIGHUP hot reload, `/healthz` / `/readyz` / `/metrics`,
  structured JSON logging on stderr, recoverable-vs-fatal error kinds. The
  operational stderr sink reads the active `LiveConfig` threshold for every
  emission, and retry, inference batch/SLO, dedup, and drain policies each have
  live runtime readers.
- **At-Least-Once Event Processing** — semantic event IDs derived from the
  validated plan, event kind, and logical key; Pulsar consumer semantics.
- **Reconcilers: Idempotent Mutation as a Single Command** — exit code `3`
  on no-op-on-match.

The project-specific refinement, lifecycle, evidence-reducer, delivery-
settlement, and live-interpreter rules are owned by
[Typed Run Contract](run_contract.md). This guide records their Haskell module
shape only; it does not restate that contract.

## Implementation Status

Phase order, implementation status, blockers, remaining work, and validation
evidence live only in the
[Development Plan](../../DEVELOPMENT_PLAN/README.md). The patterns below define
the current module and type boundaries; any remaining target is labeled
explicitly.

## jitML Project-Specific Surfaces

### Validated Plans and Pure Evidence Contracts

| Surface | Invariants | Owning module |
|---------|------------|---------------|
| `RunPlan kind` | Hidden constructor; one accumulating `RawRunRequest` refinement validates the version, non-empty identities, substrate/placement, non-empty unique seed cohort, and positive unit-indexed budget before deriving `PlanId` | `src/JitML/Plan/Plan.hs` |
| `Quantity unit`, `FiniteMeasurement`, `PlanId`, `EventId` | Hidden constructors prevent zero/overflow counts, non-finite measurements, and caller-manufactured identities; semantic event identity is derived from plan, event kind, and logical key | `src/JitML/Plan/Plan.hs` |
| `Contract event progress evidence` | Pure total `initial`/`ingest`/`finish` reducer with `exactlyOne`, `atLeastOne`, exact keyed coverage, product composition, idempotent identical redelivery, and typed wrong-plan/conflict/gap failures | `src/JitML/Run/Contract.hs` |

The shared core does not serialize resolved worker plans, join terminal workload
success with completion evidence, or acquire live resources. Those consumers
reuse these opaque values at their numerically ordered owning sprints.

### Exact Supervised Runtime and Persistence Boundaries

| Surface | Invariants | Owning module |
|---------|------------|---------------|
| `RawSupervisedRuntimePayload` → refined supervised runtime payload | One topology-complete typed graph description plus exact outside-the-graph transforms/decoder; refinement derives its graph-ordered parameter count and rejects inconsistent values. `TrainingRuntimeArtifact` separately binds canonical initial/final JMW1 bytes and hashes to that count. | `src/JitML/SL/RuntimeArtifact.hs` |
| `TrainingMetrics` | A successful training return carries the exact runtime payload and trained `LayerGraph`, canonical initial/final JMW1 bytes, verified dataset digest, a finite held-out parity probe, and the trainer-owned successful mini-batch count; no caller may reconstruct an observation from the plan | `src/JitML/SL/TrainingExecution.hs` with loop-owned counters in `Architecture.hs` / `Regression.hs` |
| Supervised-graph construction and reload | Product construction binds the authoritative row projection; generic construction binds the composite `(rowId, canonicalPlanTransport)` origin, and `PlanId` alone is insufficient. Both rederive the canonical dataset-read digest, bind exact runtime/JMW1 bytes and observed updates, and reload only from the persisted graph and physical bytes. Product completion additionally requires exactly four finite metric rows in canonical order: `train_loss`, `validation_loss`, `examples_processed`, and the authoritative held-out metric. | `src/JitML/SL/RuntimeArtifact.hs`, `src/JitML/Checkpoint/{Writer,Format,Store,WeightCodec}.hs`, `src/JitML/Product/Publisher.hs` |
| Completed supervised pointer publication | A writer reads the current latest-pointer ETag, uses that exact expectation for compare-and-swap, and may publish a completed-checkpoint event only after Store returns `PointerWritten manifestSha` for the exact stored manifest. Conflict or acknowledgement of another manifest is a typed non-publication. | `src/JitML/Checkpoint/{Writer,Store}.hs` and supervised publication call sites |
| Candidate/completed persistence split | Candidate writers take no completion proof, return opaque `StoredCandidateCheckpoint`, and never publish `latest`. Completed writers take `CompletedTraining` directly and return opaque `StoredCompletedCheckpoint` only after exact pointer CAS adoption and the attempt-independent commit; no completed persistence/event boundary carries `Maybe CompletedTraining`. Both register their full reservation in `ExperimentGcFence` before marker creation and delete the owned marker before unregistering the owned entry. A marker conflict cannot prove ownership, so the conflicted entry stays as conservative protection while a fresh registration advances. Immutable create conflict is otherwise accepted only after an exact read proves byte equality. Local `CheckpointWriteError` distinguishes invalid input, object conflict, pointer conflict, and filesystem failure; MinIO retains typed `ServiceError`. | `src/JitML/Checkpoint/{Writer,Store}.hs` and training/RL publication call sites |
| Experiment writer/GC coordination | The versioned `ExperimentGcFence` at `gc/coordination-fence.txt` binds its experiment, monotonic CAS revision, separate monotonic writer/root-activity epoch, canonical full reservation set, and contiguous `GcFenceDecision` histories; all prior generations are complete `Cancelled`, and only the latest may be nonterminal/destructive. Reservation register/unregister advances the epoch. Writer CAS insertion atomically moves overlapping planned events to `Cancelling`, helps persist the byte-identical immutable cancellation artifact and complete `Cancelled` without deleting the semantic intent before mutation, and rejects executing/reaped overlap before marker creation. GC converges its complete fresh root view in a bounded loop: epoch churn restarts the view, and an epoch-stable plan that discovers an absent exact durable intent persists it and restarts the entire view. Only the converged plan supplies `kept` and no-op; exact initial/fresh intent creation counts as work. GC moves `Open`/`Cancelled` to `Planned` only at the exact witnessed epoch while sibling GC-only revisions leave the witness valid, and reaches opaque helpable execution only from exact freshly re-read executing state with no active overlap. `executeAuthorizedGcIntents` is Store's only destructive execution API; plan/raw-intent compatibility exports do not exist. Stable intent/cancellation artifacts may span generations, the latest exact fence phase decides logical activity, delayed helpers only repeat idempotent PUTs, authorization never retires the cancellation artifact, and semantic-intent cleanup is post-`Reaped` ready/published terminal handling. Experiment scope preserves child `parentManifestSha` overlap across snapshot ids. Atomic byte-plus-ETag read plus CAS is the distributed primitive; local locks or repeated listings are not proof. | `src/JitML/Checkpoint/Store.hs`, `src/JitML/Service/{Capabilities,FilesystemMinIO,MinIOSubprocess}.hs` |
| Exact persisted admission | `admitLatestCheckpoint` reads `P1`, verifies the exact addressed envelope outer/body, and requires exact `P1 == P2`. Store then requires the exact commit, validates every canonical-original → exact-scoped → payload-SHA descriptor row, reconstructs the logical manifest, re-derives the snapshot id, and fetches/binds the scoped payload objects. `admitCheckpointAt` performs the same commit/descriptor/object binding without pointer reads. Only after opaque `AdmittedCheckpoint` exists can `requireAdmittedCompletedCheckpoint` refine opaque `AdmittedCompletedCheckpoint`; decoded Format values and structural completion prechecks are not persisted proof. | `src/JitML/Checkpoint/Store.hs` |
| Store-owned checkpoint namespace | Generic weighted and unweighted `JitML.Service.Workload` mutations first require a canonical single-segment bucket and canonical relative object-key segments, then reject checkpoint `manifests/`, `pointers/`, `snapshots/`, and `gc/` control prefixes before `HasMinIO`; path aliases cannot normalize onto Store state, and only Store may mutate transaction, selection, and GC state. | `src/JitML/Service/Workload.hs`, `src/JitML/Checkpoint/Store.hs` |
| Store/Pipeline dependency direction | Store is the lower persistence layer and imports no Product Pipeline module. Product Pipeline accepts `AdmittedCompletedCheckpoint` and derives its inference reference above Store. | `src/JitML/Checkpoint/Store.hs`, `src/JitML/Product/Pipeline.hs` |
| Typed-graph training and serving | Supervised training updates the canonical `LayerGraph` through the selected device-backed path. Serving reconstructs and refines the admitted graph, applies transforms outside it, and calls the shared pure `runLayerGraph`; the deleted `RuntimeOperations*` structural ABI is not an executor or fallback. `[LayerSpec]` / `[LayerState]` remain only as the Dense-family initialization adapter. | `src/JitML/SL/Architecture.hs`, `src/JitML/Numerics/{LayerGraph,LayerGraphOneDnn}.hs`, `src/JitML/SL/RuntimeArtifact.hs`, `src/JitML/Checkpoint/Store.hs` |

### Lifecycle GADTs

The current framework exposes three phase-indexed computation lifecycles:

| GADT | Indices (data kind) | Owning module |
|------|---------------------|---------------|
| `TrainingLifecycle` | `TrainingPhase`: `TrainingConfigured \| TrainingCollecting \| TrainingOptimizing \| TrainingEvaluating \| TrainingCheckpointing` | `src/JitML/RL/Framework.hs` |
| `RLRunLifecycle` | `RLRunPhase`: `RLCollect \| RLComputeAdvantages \| RLOptimise \| RLEvaluate \| RLCheckpoint` | `src/JitML/RL/Framework.hs` |
| `TuneSweepLifecycle` | `TuneSweepPhase`: `SweepConfigured \| SweepScheduling \| SweepRunningTrial \| SweepPruning \| SweepCompleted` | `src/JitML/RL/Framework.hs` |

These computation-phase GADTs do not by themselves prove placement, terminal
workload success, evidence completeness, delivery settlement, or cleanup. The
common orchestration lifecycle and its opaque `CompletedRunEvidence` boundary
are defined by
[Typed Run Contract → Lifecycle State Machine](run_contract.md#lifecycle-state-machine).
Domain modules project their legal computation transitions into that common
run protocol rather than maintaining a second manually validated status enum.

### Capability Classes

| Class | Operations | Owning module |
|-------|-----------|---------------|
| `HasMinIO` | `minioPutIfAbsent`, `minioReadObject`, `minioReadBytes`, `putBlobIfAbsent`, `putBlobBytesIfAbsent`, `casPointer`, `listObjects`, `deleteObject` | `src/JitML/Service/Capabilities.hs` |
| `HasPulsar` | Typed publication plus scoped subscriptions yielding receipt-bearing deliveries; the consumer handler returns one disposition and the interpreter owns settlement | `src/JitML/Service/Capabilities.hs` and `src/JitML/Service/PulsarWebSocketSubprocess.hs` |
| `HasHarbor` | `harborImageExists`, `harborPromoteImage`, `harborPushImage`, `harborPullImage`, `harborListImages` | `src/JitML/Service/Capabilities.hs`; subprocess instance in `src/JitML/Service/HarborSubprocess.hs` |
| `HasKubectl` | `kubectlApply`, `kubectlStatus`, `kubectlGet`, `kubectlDelete` | `src/JitML/Service/Capabilities.hs` |

`HasKubectl` operations route through the typed `Subprocess` boundary.

### Canonical `AppError` Enumeration (21 Variants)

Defined in `src/JitML/AppError/AppError.hs`:

| Variant | Triggered by | Exit code |
|---------|--------------|-----------|
| `PrerequisiteUnmet` | Prerequisite reconciler failure | `2` |
| `SubprocessFailed` | Typed `Subprocess` boundary non-zero exit | `1` |
| `SubprocessAttemptFailed` | Typed `Subprocess` runner raised synchronously before an exit status was observed | `1` |
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
| `InferenceCheckpointMissing` | No inference-eligible checkpoint exists for the requested experiment | `1` |
| `InferenceManifestShaMismatch` | Requested and loaded inference manifest SHAs disagree | `1` |
| `TrainingPrerequisiteUnmet` | Required live publication or staged dataset is absent | `2` |
| `ReconcilerNoop` | Reconciler-on-match — no-op | `3` |

`renderError :: AppError -> Text` is the only Text rendering at the CLI
boundary, defined in `src/JitML/CLI/Output.hs`.

Fail-closed runtime paths still cross typed boundaries. A substrate device
failure after an upfront probe, a corrupt persisted transcript, an invalid CLI
integer, or an unsafe local checkpoint key is fatal to the requested operation
but must be data at the boundary: `Left`, `ServiceError`/domain error, or
`AppError`, rendered once by `renderError`.
The current checkpoint store follows that rule: local object-key-to-path
conversion returns `Either Text FilePath`, and app-level command paths such as
`jitml internal gc` render unsafe user-supplied experiment hashes as
`InvalidConfig`.

### Wrapped Subprocess Surface

Per doctrine `Architecture → Subprocesses as Typed Values`, every external
program invocation flows through the typed `Subprocess` boundary.
`JitML.Sub.Outcome` defines the interpreter result as
`ProcessSucceeded ProcessTranscript | ProcessFailed ProcessFailure`, and
`JitML.Sub.Stream.runStreaming` / `capture` return it directly. The transcript
retains the rendered command, stdout, stderr, working directory, and monotonic
duration; opaque `ProcessFailure` adds the genuinely non-zero exit status.
Callers cannot discard stdout by selecting one field from an
`(ExitCode, stdout, stderr)` tuple, and neither `ExitSuccess` nor the malformed
`ExitFailure 0` representation can construct a process failure. The
run-contract journal consumes that structured result; see
[Evidence Journals and Reporting](run_contract.md#evidence-journals-and-reporting).

Orchestration that must account for the attempt even when the runner raises
uses the additive `ObservedProcessOutcome` boundary through
`runStreamingObserved` / `observeProcessAction`. Its failure branch is either
the original non-zero `ProcessFailure` or `ProcessAttemptFailure`, which records
the exact command, working directory, monotonic attempt duration, synchronous
exception detail, and whether each captured stream was available. A missing
exit status is rendered as unavailable; it is never replaced with a made-up
code. The observer catches only synchronous exceptions. Asynchronous exceptions
are rethrown unchanged so cancellation reaches the surrounding `generalBracket`
and its release action.

External programs include:

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
parameters reach worker Jobs as a versioned Dhall raw DTO rather than `JITML_*`
environment variables. Before effects begin, the DTO is refined into the opaque
dimensionally valid plan described by
[Raw and Validated Boundaries](run_contract.md#raw-and-validated-boundaries).
The development plan owns the migration status.

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
- `LiveConfig` Dhall: structured-log threshold, retry policy, positive
  inference batch size / maximum latency, dedup cache size / TTL, and
  `drainDeadlineSeconds`; every accepted field has a live operational reader.
- SIGHUP triggers `LiveConfig` reload; restart-required field changes emit
  `AppError InvalidConfig` with exit `2`.
- `/healthz`, `/readyz`, `/metrics` are mandatory.
- Logging: structured JSON on stderr.
- At-least-once Pulsar consumer with plan-bound semantic-event deduplication;
  broker receipts remain separate settlement identities.

## Cross-References

- [../../README.md](../../README.md)
- [Legacy Phase 1: Haskell CLI Surface](../../DEVELOPMENT_PLAN/README.md#legacy-to-new-phase-map)
- [Legacy Phase 5: `jitml service` Daemon](../../DEVELOPMENT_PLAN/README.md#legacy-to-new-phase-map)
- [daemon_architecture.md](daemon_architecture.md)
- [run_contract.md](run_contract.md)
- [../documentation_standards.md](../documentation_standards.md)
