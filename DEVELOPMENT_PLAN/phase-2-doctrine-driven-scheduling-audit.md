# Phase 2: Doctrine-Driven Scheduling Audit

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Doctrine-Driven Scheduling Audit. Single-session phase migrated from legacy Sprint 0.2 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 2.1: Doctrine-Driven Scheduling Audit [✅ Done]

**Status**: Done
**Implementation**: `DEVELOPMENT_PLAN/phase-0-planning-documentation.md`,
`DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md`,
`DEVELOPMENT_PLAN/phase-2-bootstrap-reconciler-and-jit-cache.md`,
`DEVELOPMENT_PLAN/phase-3-cluster-substrate-and-routing.md`,
`DEVELOPMENT_PLAN/phase-4-stateful-platform-services.md`,
`DEVELOPMENT_PLAN/phase-5-jitml-service-daemon.md`,
`DEVELOPMENT_PLAN/phase-6-numerical-core.md`,
`DEVELOPMENT_PLAN/phase-7-jit-codegen-and-substrates.md`,
`DEVELOPMENT_PLAN/phase-8-supervised-and-rl-framework.md`,
`DEVELOPMENT_PLAN/phase-9-rl-catalog-alphazero-and-tuning.md`,
`DEVELOPMENT_PLAN/phase-10-checkpointing-and-inference.md`,
`DEVELOPMENT_PLAN/phase-11-purescript-frontend-and-demo.md`,
`DEVELOPMENT_PLAN/phase-12-test-stanzas-and-cross-cluster.md`,
`DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`,
`DEVELOPMENT_PLAN/system-components.md`,
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`
**Docs to update**: every file listed above.

### Objective

Confirm that every in-scope identifier from
[../README.md](../README.md) is owned by an explicit sprint
deliverable in Phases `1`–`12`. Any unowned identifier is scheduled by extending an
existing sprint's `Deliverables` block (or, if no existing sprint is a natural
home, adding a new sprint). The audit's purpose is to ensure no in-scope doctrine
prescription gets silently adopted at code-write time without a plan-level binding,
per standards rule L.

### Deliverables

- A grep audit of [../README.md](../README.md) enumerates
  every prescriptive identifier from the in-scope sections. The expected
  identifier list (non-exhaustive) is:
  - **Toolchain pinning**: `GHC 9.12.4`, `Cabal 3.16.1.0`,
    `tested-with: ghc ==9.12.4`, `with-compiler: ghc-9.12.4`. Per-substrate
    codegen pins: LLVM, NVCC (`--use_fast_math=false`, baseline `sm_70`),
    Metal/`swiftc`, oneDNN (AVX2 baseline), `kindest/node` pinned in the Kind
    config and mirror-pinned as a comment in `cabal.project`.
  - **Project Structure**: `app/Main.hs` thin shim into the one supported
    `jitml` executable, `src/JitML/` library-first layout, and the Webapp role
    selected by typed `jitml service` Dhall rather than a separate demo binary.
  - **Command Topology / CommandSpec**: `Command`, `CommandSpec`, `OptionSpec`,
    `Example`, `name`, `summary`, `description`, `children`, `options`,
    `examples`, `longName`, `shortName`, `metavar`, `required`.
  - **GADT-Indexed State Machines**: `TrainingLifecycle`, `RLRunLifecycle`,
    `TuneSweepLifecycle` (training lifecycle, RL run lifecycle, tuning sweep
    lifecycle); singleton witnesses; the forbidden runtime-status-enum-with-
    manual-validation pattern.
  - **Progressive Introspection**: `jitml commands`, `--tree`, `--json`,
    `jitml help <subcommand>`.
  - **Generated Artifacts**: `GeneratedSectionRule`, `trackingGeneratedPaths`,
    `jitml docs check`, `jitml docs generate`, marker conventions
    `<!-- jitml:<key>:start -->` (Markdown), `// jitml:<key>:start` (Haskell /
    C / C++ / Rust), `# jitml:<key>:start` (YAML); paired check/write commands;
    three-element error message contract on drift. Current generated artefacts
    include route tables, Grafana dashboards, the Prometheus scrape config,
    PureScript contracts, CLI help, markdown command reference, manpages, shell
    completions, and chart YAML rendered from Haskell registries. Proto schema
    files remain lint-owned unless a future generated-binding path is added to
    the registries.
  - **Subprocesses as Typed Values**: `Subprocess`, `subprocessPath`,
    `subprocessArguments`, `subprocessWorkingDirectory`, optional stdin payload,
    `renderSubprocess`, `runStreaming`,
    `capture`; forbidden primitives `callProcess`, `readCreateProcess`,
    `System.Process`, `typed-process` smart constructors. Wrapped subprocesses
    must include `kubectl`, `helm`, `kind`, `docker`, `metal`, `nvcc`, `g++`
    (over oneDNN), `tart`, and the per-substrate kernel compilers.
  - **Plan / Apply**: `Plan`, `build`, `apply`, `--dry-run`, `--plan-file
    <path>`. Owning Plan/Apply commands: `jitml bootstrap`, `jitml train`,
    `jitml tune`, `jitml cluster up`, `jitml test all`, `jitml service`
    startup-as-plan, `jitml internal gc`.
  - **Standard Flag Families**: Plan/Apply, Daemon, Output families per
    [../README.md → Standard flag families](../README.md#standard-flag-families).
  - **Output Rules**: `--format json|table|plain`, default `table` on TTY else
    `plain`, `--color auto|always|never`, `--no-color`.
  - **Error Handling**: single `AppError` ADT, `renderError :: AppError ->
    Text`, forbidden `print`, `exitFailure`, direct terminal formatting outside
    the output layer. The audit confirms the canonical 20-variant list from
    [system-components.md → CLI Doctrine
    Components](system-components.md#cli-doctrine-components) is named in
    [phase-1-haskell-cli-surface.md → Sprint
    1.9](README.md#legacy-to-new-phase-map): `PrerequisiteUnmet`,
    `SubprocessFailed`, `MinIOFailed`, `PulsarFailed`, `HarborFailed`,
    `KubectlFailed`, `DocsCheckDrift`, `UnknownCommand`, `InvalidConfig`,
    `DhallTypeError`, `ChartLintFailed`, `RouteRegistryDrift`, `JitCacheMiss`,
    `CheckpointFormatUnsupported`,
    `CheckpointWriteConflict`, `InferenceCheckpointMissing`,
    `InferenceManifestShaMismatch`, `TrainingPrerequisiteUnmet`,
    `ReconcilerNoop`. Exit code `3` for `ReconcilerNoop`.
  - **Capability Classes and Service Errors**: `HasMinIO`, `HasPulsar`,
    `HasHarbor`, `HasKubectl`. Service errors `SEConflict`, `SEUnauthorized`,
    `SETimeout`, `SETransient`.
  - **Retry Policy as First-Class Values**: `RetryPolicy` typed value with
    named strategies; `retryServiceAction` harness per
    [../README.md → MinIO concurrency
    model](../README.md#concurrency-model).
  - **Prerequisites as Typed Effects**: `prerequisiteRegistry`, `nodeId`,
    `nodeDescription`, remedy hint, `AppError PrerequisiteUnmet`. Stage-0
    scripts perform only host gates and delegate to `jitml bootstrap
    --<substrate>`; package remediation belongs to the Haskell typed DAG.
  - **Application Environment**: `ReaderT Env IO`, single `Env` record.
  - **Long-Running Daemons in the Same Binary**: `BootConfig`, `LiveConfig`,
    SIGHUP hot reload, `/healthz`, `/readyz`, `/metrics`, structured JSON
    stderr logging, recoverable-vs-fatal error kinds.
  - **At-Least-Once Event Processing**: protobuf-message-hash deduplication
    keys; Pulsar consumer semantics; idempotent application of `gc_reaped` and
    `CheckpointDone` events.
  - **Reconcilers: Idempotent Mutation as a Single Command**: `jitml bootstrap`,
    `jitml cluster up`, `jitml docs generate`, `jitml lint --write`, `jitml internal gc
    <experiment-hash>`. Exit code `3` on no-op.
  - **Lint, Format, Code-Quality Stack**: `fourmolu.yaml`, the thirteen settings
    (`indentation`, `column-limit`, `function-arrows`, `comma-style`,
    `import-export-style`, `indent-wheres`, `record-brace-space`,
    `newlines-between-decls`, `haddock-style`, `let-style`, `in-style`,
    `unicode`), container-exclusive style/code-quality gate for the mandatory
    `jitml:local` image, `hlint`, `cabal format` temp-file round-trip byte-equality,
    `forbiddenPathRegistry` refusing `.github/workflows/`, `.husky/`,
    `.githooks/`, root `Makefile` / `justfile` / `Taskfile.yml`. Plus chart
    lint refusing freestanding PVCs, non-`kubernetes.io/no-provisioner`
    StorageClasses, and PVs without explicit `claimRef` or a registered
    Percona `volumeName` binding.
  - **Testing Doctrine, Standard Testing Stack, Test Categories, Test
    Organization**: per-tier stanza model, `type: exitcode-stdio-1.0`,
    `tasty`, `execParserPure`, property invariants `decode . encode == id`,
    `render is deterministic`, `parser roundtrips`, snapshot tests for
    pure-renderer output only (with sentinel placeholders for
    non-deterministic content) and an explicit prohibition on numerical
    fixtures per [../README.md → Snapshot targets → Numerical-fixture
    prohibition](../README.md#snapshot-targets), daemon-lifecycle
    tests, ephemeral-cluster infrastructure tests. Ten `jitml-*` stanzas:
    `jitml-unit`, `jitml-integration`, `jitml-sl-canonicals`,
    `jitml-rl-canonicals`, `jitml-hyperparameter`, `jitml-cross-backend`,
    `jitml-daemon-lifecycle`, `jitml-e2e`, `jitml lint haskell`,
    `jitml lint purescript`.
  - **Project-level documentation standards**: the six elements (marker
    convention; authoritative list/pointer of generated-region files;
    `jitml docs generate`; per-file `**Generated sections**:`; five-step
    extension protocol; fully-generated do-not-hand-edit rule).
- Every identifier above is found at least once across the phase docs as an
  owned deliverable. Identifiers without a current owner enqueue an extension
  to the closest natural sprint.
- A second project-README identifier audit (separate from the doctrine audit
  above) confirms every normative term in the project [../README.md](../README.md)
  has an owning sprint. The classes of identifier and the required hits in
  `DEVELOPMENT_PLAN/*.md` and `documents/engineering/*.md`:
  - **Substrate identifiers**: `apple-silicon`, `linux-cpu`, `linux-cuda`
    appear in [system-components.md → Substrates](system-components.md#substrates),
    [phase-2-bootstrap-reconciler-and-jit-cache.md](README.md#legacy-to-new-phase-map),
    [phase-3-cluster-substrate-and-routing.md](README.md#legacy-to-new-phase-map),
    [phase-7-jit-codegen-and-substrates.md](README.md#legacy-to-new-phase-map),
    and [phase-12-test-stanzas-and-cross-cluster.md](README.md#legacy-to-new-phase-map).
    A counter-grep for `linux-opencl` (the future-extension fourth substrate)
    must produce **zero** hits outside an explicit "future extension /
    informational only" sentence.
  - **Daemon Dhall fields**: `residency : Cluster | Host`, `inferenceMode :
    SelfInference | ForwardToHost`. Both must be cited in
    [phase-5-jitml-service-daemon.md](README.md#legacy-to-new-phase-map).
  - **Pulsar topics**: every topic family from
    [system-components.md → Pulsar Topic
    Family](system-components.md#pulsar-topic-family) appears in the owning
    phase doc.
  - **MinIO buckets**: `harbor-registry`, `jitml-checkpoints`, `jitml-datasets`,
    `jitml-transcripts`, `jitml-trials`, `jitml-tensorboard`, `jitml-artifacts`
    each appear in their owning phase doc.
  - **Cluster invariants**: `kubernetes.io/no-provisioner`, `jitml-manual`
    StorageClass, `127.0.0.1:<edge-port>`, `NodePort 30090`,
    `./.build/jitml.kubeconfig` each appear in
    [phase-3-cluster-substrate-and-routing.md](README.md#legacy-to-new-phase-map).
  - **JIT cache invariants**: `./.build/jit/<substrate>/<hash>.<ext>`,
    `./.build/host/apple-silicon/`, the cache key
    `(canonical-cbor(KernelSpec), kind, substrate, toolchain-fingerprint,
    rendered-source-payload, tuning-choice)`,
    and the lazy-tart contract appear in
    [phase-2-bootstrap-reconciler-and-jit-cache.md](README.md#legacy-to-new-phase-map)
    and
    [phase-7-jit-codegen-and-substrates.md](README.md#legacy-to-new-phase-map).
  - **Checkpoint format**: `.jmw1`, `blobs/<sha256>`, `manifests/<sha256>`,
    `pointers/{latest,best/<metric>,trial/<trial-hash>/...}`, `If-None-Match:
    *`, `If-Match: <etag>`, `advanceLatest`, `advanceBestMaximised`,
    `advanceBestMinimised` each appear in
    [phase-10-checkpointing-and-inference.md](README.md#legacy-to-new-phase-map).
  - **Report-card knobs**: each of the nine knobs in
    [system-components.md → POC Report-Card
    Knobs](system-components.md#poc-report-card-knobs) appears in
    `cabal.project` (Sprint `1.1`) and in the report-card sprint
    (Sprint `12.9`).
- An out-of-scope counter-grep confirms no sprint schedules adoption of any
  out-of-scope doctrine section. The following identifier must produce **zero**
  hits in `DEVELOPMENT_PLAN/*.md` except inside an explicit "out of scope" or
  "informational only" sentence: `Smart Constructors for Paired Resources`.
- `system-components.md` is reviewed against the audit findings; any newly
  identified CLI doctrine component is added as a row with owning sprint and
  status.
- `legacy-tracking-for-deletion.md` enqueues a `Pending Removal` row for any
  identified doctrine deviation that the current plan text claims to honor in
  scope but does not (this is expected to be empty at first audit because no
  implementation code exists yet — the row appears only if Sprint `0.2` finds a
  plan-text contradiction).
- `00-overview.md` and `README.md` retain the unchanged Phase `0` overview text;
  Sprint `0.2`'s outputs are documentation refinements to phase docs and
  `system-components.md`, not architectural pivots.

### Audit Evidence

Sprint `0.2` replays the audit with `grep -RInE` against `DEVELOPMENT_PLAN/`,
`documents/engineering/`, and `documents/documentation_standards.md`. Every command
below returns at least the cited file:line evidence; no owner gaps, new sprint
blocks, or cleanup-ledger rows are required.

- Toolchain pinning:
  `grep -RInE 'GHC|9\.14\.1|Cabal|3\.16\.1\.0|tested-with: ghc ==9\.14\.1|with-compiler: ghc-9\.14\.1|LLVM|NVCC|--use_fast_math=false|sm_70|Xcode/Metal|Metal/swiftc|oneDNN|AVX2|kindest/node' DEVELOPMENT_PLAN documents/engineering`
  Evidence: [phase-1-haskell-cli-surface.md](README.md#legacy-to-new-phase-map) lines
  `57` and `62`-`65`; [system-components.md](system-components.md) lines `360`-`366`.
- Project structure:
  `grep -RInE 'app/Main\.hs|src/JitML/' DEVELOPMENT_PLAN documents/engineering`
  Evidence: [phase-1-haskell-cli-surface.md](README.md#legacy-to-new-phase-map) lines
  `58`-`69`; [system-components.md](system-components.md) lines `404`-`405`.
- `CommandSpec` and command topology:
  `grep -RInE 'CommandSpec|OptionSpec|Example|name|summary|description|children|options|examples|longName|shortName|metavar|required|jitml commands|--tree|--json|jitml help <subcommand>' DEVELOPMENT_PLAN documents/engineering`
  Evidence: [phase-1-haskell-cli-surface.md](README.md#legacy-to-new-phase-map) lines
  `112`-`145`; [documents/engineering/cli_command_surface.md](../documents/engineering/cli_command_surface.md)
  lines `13`, `14`, `16`, `17`, `18`, `19`, `20`, `21`, `22`, `23`, `24`, `25`, `26`, `27`, `28`, `29`, `30`, and `31`.
- GADT-indexed lifecycle state:
  `grep -RInE 'TrainingLifecycle|RLRunLifecycle|TuneSweepLifecycle|singleton witnesses|runtime-status-enum-with-manual-validation' DEVELOPMENT_PLAN documents/engineering`
  Evidence: [phase-8-supervised-and-rl-framework.md](README.md#legacy-to-new-phase-map)
  lines `60`-`62`, `184`, and `258`;
  [phase-9-rl-catalog-alphazero-and-tuning.md](README.md#legacy-to-new-phase-map)
  line `261`; [documents/engineering/haskell_code_guide.md](../documents/engineering/haskell_code_guide.md)
  lines `55`-`60`.
- Generated artifacts:
  `grep -RInE 'GeneratedSectionRule|trackingGeneratedPaths|jitml docs check|jitml docs generate|<!-- jitml:<key>:start -->|// jitml:<key>:start|# jitml:<key>:start|route table|Grafana dashboards|Prometheus scrape config|PureScript contracts|CLI help|manpages|shell completions' DEVELOPMENT_PLAN documents`
  Evidence: [phase-1-haskell-cli-surface.md](README.md#legacy-to-new-phase-map) lines
  `171`-`211`; [documents/documentation_standards.md](../documents/documentation_standards.md)
  lines `304`-`357`.
- Typed subprocess boundary:
  `grep -RInE 'Subprocess|subprocessPath|subprocessArguments|subprocessWorkingDirectory|subprocessStdin|renderSubprocess|runStreaming|capture|callProcess|readCreateProcess|System\.Process|typed-process|kubectl|helm|kind|docker|metal|nvcc|g\+\+|tart' DEVELOPMENT_PLAN documents/engineering`
  Evidence: [phase-1-haskell-cli-surface.md](README.md#legacy-to-new-phase-map) lines
  `322`-`339`; [documents/engineering/haskell_code_guide.md](../documents/engineering/haskell_code_guide.md)
  lines `100`-`120`.
- Plan / Apply:
  `grep -RInE 'Plan|build|apply|--dry-run|--plan-file <path>|jitml train|jitml tune|jitml cluster up|jitml test all|jitml service|jitml internal gc' DEVELOPMENT_PLAN documents/engineering`
  Evidence: [phase-1-haskell-cli-surface.md](README.md#legacy-to-new-phase-map) lines
  `286`-`304`; [phase-12-test-stanzas-and-cross-cluster.md](README.md#legacy-to-new-phase-map)
  lines `378`-`391`.
- Output rules and standard flag families:
  `grep -RInE '--format json\|table\|plain|default .*table.*TTY.*plain|--color auto\|always\|never|--no-color|Standard Flag Families' DEVELOPMENT_PLAN documents/engineering`
  Evidence: [phase-1-haskell-cli-surface.md](README.md#legacy-to-new-phase-map) lines
  `438`-`442`; [00-overview.md](00-overview.md) lines `271`-`274`.
- Error handling:
  `grep -RInE 'AppError|renderError :: AppError -> Text|PrerequisiteUnmet|SubprocessFailed|MinIOFailed|PulsarFailed|HarborFailed|KubectlFailed|DocsCheckDrift|UnknownCommand|InvalidConfig|DhallTypeError|ChartLintFailed|RouteRegistryDrift|JitCacheMiss|JitToolchainDrift|CheckpointFormatUnsupported|CheckpointWriteConflict|ReconcilerNoop|exit code' DEVELOPMENT_PLAN documents/engineering`
  Evidence: [phase-1-haskell-cli-surface.md](README.md#legacy-to-new-phase-map) lines
  `428`-`442`; [system-components.md](system-components.md) lines `264`-`283`.
- Capability classes, service errors, retry policy, prerequisites, and `Env`:
  `grep -RInE 'HasMinIO|HasPulsar|HasHarbor|HasKubectl|SEConflict|SEUnauthorized|SETimeout|SETransient|RetryPolicy|retryServiceAction|prerequisiteRegistry|nodeId|nodeDescription|remedy hint|ReaderT Env IO|Env' DEVELOPMENT_PLAN documents/engineering`
  Evidence: [phase-5-jitml-service-daemon.md](README.md#legacy-to-new-phase-map)
  lines `172`-`197`; [phase-1-haskell-cli-surface.md](README.md#legacy-to-new-phase-map)
  lines `357`-`407`; [system-components.md](system-components.md) lines `170`-`174`
  and `282`-`283`.
- Long-running daemon, at-least-once events, and reconcilers:
  `grep -RInE 'BootConfig|LiveConfig|SIGHUP|/healthz|/readyz|/metrics|structured JSON|recoverable-vs-fatal|protobuf-message-hash|gc_reaped|CheckpointDone|jitml cluster up|jitml docs generate|jitml lint --write|jitml internal gc' DEVELOPMENT_PLAN documents/engineering`
  Evidence: [phase-5-jitml-service-daemon.md](README.md#legacy-to-new-phase-map)
  lines `88`-`148` and `218`-`240`; [system-components.md](system-components.md)
  lines `162`-`178` and `298`-`300`.
- Lint stack and test organization:
  `grep -RInE 'fourmolu\.yaml|indentation|column-limit|function-arrows|comma-style|import-export-style|indent-wheres|record-brace-space|newlines-between-decls|haddock-style|let-style|in-style|unicode|hlint|cabal format|forbiddenPathRegistry|\.github/workflows/|\.husky/|\.githooks/|Makefile|justfile|Taskfile\.yml|freestanding PVCs|kubernetes\.io/no-provisioner|claimRef|exitcode-stdio-1\.0|tasty|execParserPure|decode \. encode == id|render is deterministic|parser roundtrips|snapshot tests|numerical-fixture prohibition|sentinel placeholders|daemon-lifecycle|Ephemeral-Cluster Infrastructure|jitml-unit|jitml-integration|jitml-sl-canonicals|jitml-rl-canonicals|jitml-hyperparameter|jitml-cross-backend|jitml-daemon-lifecycle|jitml-e2e|jitml lint haskell|jitml lint purescript' DEVELOPMENT_PLAN documents/engineering`
  Evidence: [phase-1-haskell-cli-surface.md](README.md#legacy-to-new-phase-map)
  lines `235`-`267`; [system-components.md](system-components.md) lines `308`-`336`.
- Project-level documentation standards:
  `grep -RInE 'marker convention|GeneratedSectionRule|jitml docs generate|\*\*Generated sections\*\*|five-step extension protocol|Do-Not-Hand-Edit|trackingGeneratedPaths' DEVELOPMENT_PLAN documents`
  Evidence: [documents/documentation_standards.md](../documents/documentation_standards.md)
  lines `304`-`357`; [phase-1-haskell-cli-surface.md](README.md#legacy-to-new-phase-map)
  lines `171`-`211`.
- Substrate identifiers and `linux-opencl` counter-grep:
  `grep -RInE 'apple-silicon|linux-cpu|linux-cuda' DEVELOPMENT_PLAN documents/engineering`
  and `grep -RInE 'linux-opencl' DEVELOPMENT_PLAN documents/engineering README.md`.
  Evidence: [system-components.md](system-components.md) lines `43`-`47`;
  [phase-2-bootstrap-reconciler-and-jit-cache.md](README.md#legacy-to-new-phase-map),
  [phase-3-cluster-substrate-and-routing.md](README.md#legacy-to-new-phase-map),
  [phase-7-jit-codegen-and-substrates.md](README.md#legacy-to-new-phase-map),
  and [phase-12-test-stanzas-and-cross-cluster.md](README.md#legacy-to-new-phase-map)
  all name the three supported substrates. The `linux-opencl` hits are limited
  to future-extension / informational-only prose.
- Daemon Dhall fields:
  `grep -RInE 'residency : Cluster \| Host|inferenceMode : SelfInference \| ForwardToHost' DEVELOPMENT_PLAN documents/engineering`
  Evidence: [phase-5-jitml-service-daemon.md](README.md#legacy-to-new-phase-map)
  lines `36`-`37`; [00-overview.md](00-overview.md) lines `344`-`346`.
- Pulsar topics:
  `grep -RInE 'training\.command\.<mode>|training\.event\.<mode>|tune\.command\.<mode>|tune\.event\.<mode>|rl\.command\.<mode>|rl\.event\.<mode>|inference\.request\.<mode>|inference\.result\.<mode>|inference\.command\.apple-silicon|inference\.event\.apple-silicon' DEVELOPMENT_PLAN documents/engineering`
  Evidence: [system-components.md](system-components.md) lines `147`-`156`;
  [phase-5-jitml-service-daemon.md](README.md#legacy-to-new-phase-map) lines `218`-`224`.
- MinIO buckets:
  `grep -RInE 'harbor-registry|jitml-checkpoints|jitml-datasets|jitml-transcripts|jitml-trials|jitml-tensorboard|jitml-artifacts' DEVELOPMENT_PLAN documents/engineering`
  Evidence: [system-components.md](system-components.md) lines `132`-`138`;
  [phase-4-stateful-platform-services.md](README.md#legacy-to-new-phase-map)
  and [phase-10-checkpointing-and-inference.md](README.md#legacy-to-new-phase-map)
  own the service-specific bucket work.
- Cluster invariants:
  `grep -RInE 'kubernetes\.io/no-provisioner|jitml-manual|127\.0\.0\.1:<edge-port>|NodePort 30090|\./\.build/jitml\.kubeconfig' DEVELOPMENT_PLAN documents/engineering`
  Evidence: [phase-3-cluster-substrate-and-routing.md](README.md#legacy-to-new-phase-map)
  lines `88`-`149`; [system-components.md](system-components.md) lines `99`-`111`.
- JIT cache invariants:
  `grep -RInE '\./\.build/jit/<substrate>/<hash>\.<ext>|\./\.build/host/apple-silicon/|\(canonical-cbor\(KernelSpec\), kind, substrate, toolchain-fingerprint\)|lazy-tart' DEVELOPMENT_PLAN documents/engineering`
  Evidence: [phase-2-bootstrap-reconciler-and-jit-cache.md](README.md#legacy-to-new-phase-map)
  lines `133`-`153`; [phase-7-jit-codegen-and-substrates.md](README.md#legacy-to-new-phase-map)
  lines `50`-`82`.
- Checkpoint format:
  `grep -RInE '\.jmw1|blobs/<sha256>|manifests/<sha256>|pointers/\{latest,best/<metric>,trial/<trial-hash>/\.\.\.\}|If-None-Match: \*|If-Match: <etag>|advanceLatest|advanceBestMaximised|advanceBestMinimised' DEVELOPMENT_PLAN documents/engineering`
  Evidence: [phase-10-checkpointing-and-inference.md](README.md#legacy-to-new-phase-map)
  lines `13`, `14`, `17`, `18`, and `19`, `55`-`78`, and `107`-`125`;
  [documents/engineering/checkpoint_format.md](../documents/engineering/checkpoint_format.md)
  lines `136`-`146`.
- Report-card knobs:
  `grep -RInE 'sl_epochs|sl_batch|rl_steps|rl_eval_episodes|az_games|az_sims|tune_trials|tune_budget_per_trial|xcluster_kind_nodes' DEVELOPMENT_PLAN/system-components.md DEVELOPMENT_PLAN/phase-12-test-stanzas-and-cross-cluster.md`
  Evidence: [system-components.md](system-components.md) lines `346`-`354`;
  [phase-12-test-stanzas-and-cross-cluster.md](README.md#legacy-to-new-phase-map)
  lines `395`-`397`.
- Out-of-scope doctrine counter-grep:
  `grep -RInE 'Smart Constructors for Paired Resources' DEVELOPMENT_PLAN/*.md`.
  Evidence: hits are limited to [00-overview.md](00-overview.md) line `316`
  (`Out of scope`), [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
  line `51` (conditional future scope), and this sprint's audit text.

### Validation

1. Manual grep-audit replay against `DEVELOPMENT_PLAN/*.md` confirms every
   doctrine identifier named above appears at least once. The audit is recorded
   inside this sprint's body when it lands, including the literal `grep -E`
   command for each class of identifier and the file:line evidence.
2. Counter-grep confirms zero out-of-scope adoption-style hits per the list
   above.
3. Each new sprint block introduced by Sprint `0.2` (if any) follows the rule H
   sprint format (Status / Implementation / Docs to update / Objective /
   Deliverables / Validation / Remaining Work).
4. Each new deliverable cites the [../README.md](../README.md)
   section it implements by section heading per standards rule L.
5. Mermaid render pass (standards rule K) is a no-op — Sprint `0.2` introduces
   no diagrams.
6. Plan-level lint pass: the manual `fourmolu --mode check` and `hlint` runs
   are no-ops (no Haskell code yet); the plan-level checks reduce to the
   cross-reference resolution, metadata-block consistency, and identifier-audit
   checks named above.

### Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
