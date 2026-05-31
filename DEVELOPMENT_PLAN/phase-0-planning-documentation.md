# Phase 0: Planning and Documentation Topology

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md),
[development_plan_standards.md](development_plan_standards.md),
[system-components.md](system-components.md),
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md),
[../README.md](../README.md)
**Generated sections**: none

> **Purpose**: Define the plan-ownership baseline for the jitML Haskell CLI so phase
> status, sequencing, doctrine-alignment, and documentation-topology work has one
> canonical home.

## Phase Status

✅ **Done**. The phase establishes the doctrine envelope and plan topology
that every Exit-Definition obligation refers back to. Sprint `0.1`
(canonical plan suite bootstrap) and Sprint `0.2` (doctrine-driven
scheduling audit) are implemented and validated; every in-scope doctrine
identifier is bound to an owned deliverable in Phases `1`–`12`.

## Phase Summary

This phase establishes the development plan as the canonical execution-ordered
record for the jitML repository, the governed `documents/` doctrine suite, the root-
file pointers that name [../README.md](../README.md) as the
authoritative CLI doctrine, and the in-scope vs out-of-scope doctrine envelope
inherited verbatim from the project [../README.md → Doctrine
scope](../README.md#doctrine-scope). It owns the phase model, the top-level control
documents, the cleanup ledger that later phases populate, and the standards-rule-L
doctrine-citation contract that every doctrine-adoption sprint must follow.

The phase does not write Haskell, Dhall, Helm, PureScript, shell, or YAML source.
Every implementation surface — the CLI, the bootstrap reconciler, the cluster
substrate, the platform services, the daemon, the numerical core, the JIT codegen,
the SL/RL/AlphaZero/tuning surfaces, the checkpoint store, the PureScript frontend,
and the test stanzas — is scheduled by this phase but executed by Phases `1`–`12`.

## Sprint 0.1: Canonical Plan Suite Bootstrap ✅

**Status**: Done
**Implementation**: `DEVELOPMENT_PLAN/README.md`,
`DEVELOPMENT_PLAN/00-overview.md`,
`DEVELOPMENT_PLAN/development_plan_standards.md`,
`DEVELOPMENT_PLAN/system-components.md`,
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`,
`DEVELOPMENT_PLAN/phase-0-planning-documentation.md`,
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
`documents/documentation_standards.md`,
`documents/engineering/README.md`,
`documents/engineering/cli_command_surface.md`,
`documents/engineering/code_quality.md`,
`documents/engineering/unit_testing_policy.md`,
`documents/engineering/haskell_code_guide.md`,
`documents/engineering/determinism_contract.md`,
`documents/engineering/cluster_topology.md`,
`documents/engineering/daemon_architecture.md`,
`documents/engineering/jit_codegen_architecture.md`,
`documents/engineering/numerical_core.md`,
`documents/engineering/training_workloads.md`,
`documents/engineering/checkpoint_format.md`,
`documents/engineering/purescript_frontend.md`,
`README.md`, `README.md`, `AGENTS.md`, `CLAUDE.md`
**Docs to update**: every file listed above.

### Objective

Stand up the canonical plan suite, the governed `documents/` doctrine suite, and
the root-file doctrine pointers so every later phase can cite a single execution-
ordered plan, a single doctrine, and a single governed-documents home with no
ambiguity about where the source of truth lives.

### Deliverables

- The `DEVELOPMENT_PLAN/` directory exists with the eighteen files named above.
  Every file carries the standard `**Status**` / `**Supersedes**` / `**Referenced
  by**` / `**Generated sections**` metadata block plus a `> **Purpose**:` line per
  [../documents/documentation_standards.md → Required Header
  Metadata](../documents/documentation_standards.md#3-required-header-metadata).
- The phase model is the thirteen-phase substrate-then-workload decomposition
  declared in [README.md → Phase Overview](README.md#phase-overview): Phase `0`
  documentation/planning, Phase `1` Haskell CLI surface, Phase `2` bootstrap
  reconciler + prerequisite DAG + JIT cache + outer-container Linux builds, Phase
  `3` Kind cluster substrate + Helm umbrella chart + Envoy Gateway + route
  registry, Phase `4` Harbor + MinIO + Pulsar + Postgres + observability, Phase
  `5` `jitml service` daemon, Phase `6` numerical core, Phase `7` per-substrate
  JIT codegen, Phase `8` SL training and RL framework, Phase `9` RL algorithm
  catalog + AlphaZero + tuning, Phase `10` checkpointing + inference-only read
  path, Phase `11` PureScript frontend + `jitml-demo`, Phase `12` test stanzas +
  cross-cluster parity surface.
- [development_plan_standards.md](development_plan_standards.md) declares rules
  A–L, including the CLI Doctrine Alignment rule L that requires phase docs to
  cite [../README.md](../README.md) sections by name on
  doctrine-adoption deliverables.
- [00-overview.md](00-overview.md) inherits the project README's `Doctrine scope`
  in-scope and out-of-scope splits verbatim. The in-scope set covers Toolchain
  pinning, Project Structure, Command Topology, GADT-Indexed State Machines,
  Progressive Introspection, Automatically Generated Documentation, Generated
  Artifacts, Architecture (including Subprocesses as Typed Values), Plan / Apply,
  Output Rules, Standard Flag Families, Error Handling (extended with exit code
  `3` for reconciler no-op-on-match), Capability Classes and Service Errors, Retry
  Policy as First-Class Values, Prerequisites as Typed Effects, Application
  Environment, Long-Running Daemons in the Same Binary (jitML opts in), At-Least-
  Once Event Processing, Reconcilers: Idempotent Mutation as a Single Command,
  Lint, Format, and Code-Quality Stack, Testing Doctrine, Standard Testing Stack,
  Test Categories, and Test Organization. The out-of-scope set covers Smart
  Constructors for Paired Resources (no paired infra resources at present) and
  the doctrine's closing Architecture capsule (informational summary only).
- [system-components.md](system-components.md) lists the planned substrates,
  bootstrap reconciler, cluster substrate, stateful platform services, daemon
  components, numerical-core ADTs, JIT codegen artefacts, training workload
  surfaces, checkpoint and inference components, frontend components, CLI
  doctrine components, test stanzas, doctrine test-category mapping, report-card
  knobs, toolchain pins, state locations, and artefact locations with owning
  sprint / status for each row.
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) is empty in
  both `Pending Removal` and `Completed` sections at write time, with the
  doctrine-deviation-residue and stand-in-residue classes named for later
  population.
- `documents/documentation_standards.md` carries the six doctrine-mandated
  Generated Sections elements per [../README.md](../README.md): marker convention with
  literal `<!-- jitml:<key>:start -->` / `<!-- jitml:<key>:end -->` examples per
  file type, an authoritative pointer to the `GeneratedSectionRule` registry, a
  "How to regenerate" instruction naming `jitml docs generate` literally, a per-
  file `**Generated sections**:` metadata field with lint contract, the five-step
  extension protocol, and the "fully generated, do-not-hand-edit" rule cross-
  referencing the `trackingGeneratedPaths` registry.
- `documents/engineering/` carries the thirteen scaffolded engineering docs named
  under Implementation above. The four doctrine-overlap docs
  (`cli_command_surface.md`, `code_quality.md`, `unit_testing_policy.md`,
  `haskell_code_guide.md`) defer to the doctrine sections they implement by name
  and retain only project-specific elaborations. The eight project-specific docs
  (`determinism_contract.md`, `cluster_topology.md`, `daemon_architecture.md`,
  `jit_codegen_architecture.md`, `numerical_core.md`, `training_workloads.md`,
  `checkpoint_format.md`, `purescript_frontend.md`) own their content outright
  with no doctrine overlap. The `engineering/README.md` is a one-line-per-file
  index.
- `documents/engineering/cluster_topology.md` owns the Helm-values ownership
  guideline: `chart/templates/` is manifest-only, umbrella values belong in
  `chart/values.yaml`, and separate `chart/<subchart>-values.yaml` files require
  a documented typed Helm `--values` invocation or become cleanup candidates.
  `documents/engineering/code_quality.md` mirrors the enforcement direction for
  the chart lint surface.
- `../README.md` carries the standard `**Status**` / `**Supersedes**` /
  `**Referenced by**` metadata block plus a `> **Purpose**:` line and owns the
  project/CLI doctrine.
- `README.md` carries the execution-ordered development plan, and the
  project-root README links back to it as the authoritative sprint-status
  entrypoint.
- `AGENTS.md` and `CLAUDE.md` (project root) carry two appended pointer lines
  below the existing git-restriction block: one to
  [`DEVELOPMENT_PLAN/README.md`](README.md) and one to
  [../README.md](../README.md). Existing content unchanged.

### Validation

1. Every Markdown link inside `DEVELOPMENT_PLAN/`, `documents/`, and the four root
   files resolves to a file that exists on disk.
2. Every file under `DEVELOPMENT_PLAN/` opens with `**Status**:` / `**Supersedes**:`
   / `**Referenced by**:` / `**Generated sections**:` / `> **Purpose**:` lines per
   the convention.
3. The four-row Done/Active/Planned/Blocked status-vocabulary table is identical in
   `README.md`, `development_plan_standards.md`, and `00-overview.md`.
4. The Phase Overview table in `README.md` names exactly thirteen phases (0–12)
   with names matching the `phase-N-*.md` titles letter-for-letter.
5. The doctrine-scope subsection in `00-overview.md` covers every in-scope and
   out-of-scope item declared by the project README's `Doctrine scope` section.
6. The Sprint Dependencies Mermaid flowchart in `README.md` renders without error
   in a standalone Mermaid renderer (e.g.
   `npx @mermaid-js/mermaid-cli@latest -i DEVELOPMENT_PLAN/README.md -o /tmp/r.svg`)
   per standards rule K.
7. `documents/documentation_standards.md` covers every one of the six doctrine-
   mandated Generated Sections elements; a diff against the doctrine's
   `Project-level documentation standards` subsection shows no missing item.
8. Each `documents/engineering/*` file that overlaps with the doctrine either
   cites a doctrine section by name or shrinks to a doctrine pointer.
9. The Helm-values ownership guideline is present in
   `documents/engineering/cluster_topology.md`, and any chart-lint enforcement
   direction is cross-referenced from `documents/engineering/code_quality.md`.
10. Root `README.md`, `AGENTS.md`, and `CLAUDE.md` link to both
   `DEVELOPMENT_PLAN/README.md` and `README.md`.
11. Mermaid render pass per standards rule K: `README.md`'s Sprint Dependencies
    flowchart is the only Mermaid block in `DEVELOPMENT_PLAN/` at Sprint `0.1`
    closure; it renders successfully.

### Remaining Work

None.

## Sprint 0.2: Doctrine-Driven Scheduling Audit ✅

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
  - **Toolchain pinning**: `GHC 9.14.1`, `Cabal 3.16.1.0`,
    `tested-with: ghc ==9.14.1`, `with-compiler: ghc-9.14.1`. Per-substrate
    codegen pins: LLVM, NVCC (`--use_fast_math=false`, baseline `sm_70`),
    Metal/`swiftc`, oneDNN (AVX2 baseline), `kindest/node` pinned in the Kind
    config and mirror-pinned as a comment in `cabal.project`.
  - **Project Structure**: `app/Main.hs` thin shim, `app/Demo.hs` thin shim,
    `src/JitML/` library-first layout.
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
    the output layer. The audit confirms the canonical 17-variant list from
    [system-components.md → CLI Doctrine
    Components](system-components.md#cli-doctrine-components) is named in
    [phase-1-haskell-cli-surface.md → Sprint
    1.9](phase-1-haskell-cli-surface.md): `PrerequisiteUnmet`,
    `SubprocessFailed`, `MinIOFailed`, `PulsarFailed`, `HarborFailed`,
    `KubectlFailed`, `DocsCheckDrift`, `UnknownCommand`, `InvalidConfig`,
    `DhallTypeError`, `ChartLintFailed`, `RouteRegistryDrift`, `JitCacheMiss`,
    `JitToolchainDrift`, `CheckpointFormatUnsupported`,
    `CheckpointWriteConflict`, `ReconcilerNoop`. Exit code `3` for
    `ReconcilerNoop`.
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
    [phase-2-bootstrap-reconciler-and-jit-cache.md](phase-2-bootstrap-reconciler-and-jit-cache.md),
    [phase-3-cluster-substrate-and-routing.md](phase-3-cluster-substrate-and-routing.md),
    [phase-7-jit-codegen-and-substrates.md](phase-7-jit-codegen-and-substrates.md),
    and [phase-12-test-stanzas-and-cross-cluster.md](phase-12-test-stanzas-and-cross-cluster.md).
    A counter-grep for `linux-opencl` (the future-extension fourth substrate)
    must produce **zero** hits outside an explicit "future extension /
    informational only" sentence.
  - **Daemon Dhall fields**: `residency : Cluster | Host`, `inferenceMode :
    SelfInference | ForwardToHost`. Both must be cited in
    [phase-5-jitml-service-daemon.md](phase-5-jitml-service-daemon.md).
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
    [phase-3-cluster-substrate-and-routing.md](phase-3-cluster-substrate-and-routing.md).
  - **JIT cache invariants**: `./.build/jit/<substrate>/<hash>.<ext>`,
    `./.build/host/apple-silicon/`, the cache key
    `(canonical-cbor(KernelSpec), kind, substrate, toolchain-fingerprint,
    rendered-source-payload, tuning-choice)`,
    and the lazy-tart contract appear in
    [phase-2-bootstrap-reconciler-and-jit-cache.md](phase-2-bootstrap-reconciler-and-jit-cache.md)
    and
    [phase-7-jit-codegen-and-substrates.md](phase-7-jit-codegen-and-substrates.md).
  - **Checkpoint format**: `.jmw1`, `blobs/<sha256>`, `manifests/<sha256>`,
    `pointers/{latest,best/<metric>,trial/<trial-hash>/...}`, `If-None-Match:
    *`, `If-Match: <etag>`, `advanceLatest`, `advanceBestMaximised`,
    `advanceBestMinimised` each appear in
    [phase-10-checkpointing-and-inference.md](phase-10-checkpointing-and-inference.md).
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
  Evidence: [phase-1-haskell-cli-surface.md](phase-1-haskell-cli-surface.md) lines
  `57` and `62`-`65`; [system-components.md](system-components.md) lines `360`-`366`.
- Project structure:
  `grep -RInE 'app/Main\.hs|app/Demo\.hs|src/JitML/' DEVELOPMENT_PLAN documents/engineering`
  Evidence: [phase-1-haskell-cli-surface.md](phase-1-haskell-cli-surface.md) lines
  `58`-`69`; [system-components.md](system-components.md) lines `404`-`405`.
- `CommandSpec` and command topology:
  `grep -RInE 'CommandSpec|OptionSpec|Example|name|summary|description|children|options|examples|longName|shortName|metavar|required|jitml commands|--tree|--json|jitml help <subcommand>' DEVELOPMENT_PLAN documents/engineering`
  Evidence: [phase-1-haskell-cli-surface.md](phase-1-haskell-cli-surface.md) lines
  `112`-`145`; [documents/engineering/cli_command_surface.md](../documents/engineering/cli_command_surface.md)
  lines `14`-`31`.
- GADT-indexed lifecycle state:
  `grep -RInE 'TrainingLifecycle|RLRunLifecycle|TuneSweepLifecycle|singleton witnesses|runtime-status-enum-with-manual-validation' DEVELOPMENT_PLAN documents/engineering`
  Evidence: [phase-8-supervised-and-rl-framework.md](phase-8-supervised-and-rl-framework.md)
  lines `60`-`62`, `184`, and `258`;
  [phase-9-rl-catalog-alphazero-and-tuning.md](phase-9-rl-catalog-alphazero-and-tuning.md)
  line `261`; [documents/engineering/haskell_code_guide.md](../documents/engineering/haskell_code_guide.md)
  lines `55`-`60`.
- Generated artifacts:
  `grep -RInE 'GeneratedSectionRule|trackingGeneratedPaths|jitml docs check|jitml docs generate|<!-- jitml:<key>:start -->|// jitml:<key>:start|# jitml:<key>:start|route table|Grafana dashboards|Prometheus scrape config|PureScript contracts|CLI help|manpages|shell completions' DEVELOPMENT_PLAN documents`
  Evidence: [phase-1-haskell-cli-surface.md](phase-1-haskell-cli-surface.md) lines
  `171`-`211`; [documents/documentation_standards.md](../documents/documentation_standards.md)
  lines `304`-`357`.
- Typed subprocess boundary:
  `grep -RInE 'Subprocess|subprocessPath|subprocessArguments|subprocessWorkingDirectory|subprocessStdin|renderSubprocess|runStreaming|capture|callProcess|readCreateProcess|System\.Process|typed-process|kubectl|helm|kind|docker|metal|nvcc|g\+\+|tart' DEVELOPMENT_PLAN documents/engineering`
  Evidence: [phase-1-haskell-cli-surface.md](phase-1-haskell-cli-surface.md) lines
  `322`-`339`; [documents/engineering/haskell_code_guide.md](../documents/engineering/haskell_code_guide.md)
  lines `100`-`120`.
- Plan / Apply:
  `grep -RInE 'Plan|build|apply|--dry-run|--plan-file <path>|jitml train|jitml tune|jitml cluster up|jitml test all|jitml service|jitml internal gc' DEVELOPMENT_PLAN documents/engineering`
  Evidence: [phase-1-haskell-cli-surface.md](phase-1-haskell-cli-surface.md) lines
  `286`-`304`; [phase-12-test-stanzas-and-cross-cluster.md](phase-12-test-stanzas-and-cross-cluster.md)
  lines `378`-`391`.
- Output rules and standard flag families:
  `grep -RInE '--format json\|table\|plain|default .*table.*TTY.*plain|--color auto\|always\|never|--no-color|Standard Flag Families' DEVELOPMENT_PLAN documents/engineering`
  Evidence: [phase-1-haskell-cli-surface.md](phase-1-haskell-cli-surface.md) lines
  `438`-`442`; [00-overview.md](00-overview.md) lines `271`-`274`.
- Error handling:
  `grep -RInE 'AppError|renderError :: AppError -> Text|PrerequisiteUnmet|SubprocessFailed|MinIOFailed|PulsarFailed|HarborFailed|KubectlFailed|DocsCheckDrift|UnknownCommand|InvalidConfig|DhallTypeError|ChartLintFailed|RouteRegistryDrift|JitCacheMiss|JitToolchainDrift|CheckpointFormatUnsupported|CheckpointWriteConflict|ReconcilerNoop|exit code' DEVELOPMENT_PLAN documents/engineering`
  Evidence: [phase-1-haskell-cli-surface.md](phase-1-haskell-cli-surface.md) lines
  `428`-`442`; [system-components.md](system-components.md) lines `264`-`283`.
- Capability classes, service errors, retry policy, prerequisites, and `Env`:
  `grep -RInE 'HasMinIO|HasPulsar|HasHarbor|HasKubectl|SEConflict|SEUnauthorized|SETimeout|SETransient|RetryPolicy|retryServiceAction|prerequisiteRegistry|nodeId|nodeDescription|remedy hint|ReaderT Env IO|Env' DEVELOPMENT_PLAN documents/engineering`
  Evidence: [phase-5-jitml-service-daemon.md](phase-5-jitml-service-daemon.md)
  lines `172`-`197`; [phase-1-haskell-cli-surface.md](phase-1-haskell-cli-surface.md)
  lines `357`-`407`; [system-components.md](system-components.md) lines `170`-`174`
  and `282`-`283`.
- Long-running daemon, at-least-once events, and reconcilers:
  `grep -RInE 'BootConfig|LiveConfig|SIGHUP|/healthz|/readyz|/metrics|structured JSON|recoverable-vs-fatal|protobuf-message-hash|gc_reaped|CheckpointDone|jitml cluster up|jitml docs generate|jitml lint --write|jitml internal gc' DEVELOPMENT_PLAN documents/engineering`
  Evidence: [phase-5-jitml-service-daemon.md](phase-5-jitml-service-daemon.md)
  lines `88`-`148` and `218`-`240`; [system-components.md](system-components.md)
  lines `162`-`178` and `298`-`300`.
- Lint stack and test organization:
  `grep -RInE 'fourmolu\.yaml|indentation|column-limit|function-arrows|comma-style|import-export-style|indent-wheres|record-brace-space|newlines-between-decls|haddock-style|let-style|in-style|unicode|hlint|cabal format|forbiddenPathRegistry|\.github/workflows/|\.husky/|\.githooks/|Makefile|justfile|Taskfile\.yml|freestanding PVCs|kubernetes\.io/no-provisioner|claimRef|exitcode-stdio-1\.0|tasty|execParserPure|decode \. encode == id|render is deterministic|parser roundtrips|snapshot tests|numerical-fixture prohibition|sentinel placeholders|daemon-lifecycle|Ephemeral-Cluster Infrastructure|jitml-unit|jitml-integration|jitml-sl-canonicals|jitml-rl-canonicals|jitml-hyperparameter|jitml-cross-backend|jitml-daemon-lifecycle|jitml-e2e|jitml lint haskell|jitml lint purescript' DEVELOPMENT_PLAN documents/engineering`
  Evidence: [phase-1-haskell-cli-surface.md](phase-1-haskell-cli-surface.md)
  lines `235`-`267`; [system-components.md](system-components.md) lines `308`-`336`.
- Project-level documentation standards:
  `grep -RInE 'marker convention|GeneratedSectionRule|jitml docs generate|\*\*Generated sections\*\*|five-step extension protocol|Do-Not-Hand-Edit|trackingGeneratedPaths' DEVELOPMENT_PLAN documents`
  Evidence: [documents/documentation_standards.md](../documents/documentation_standards.md)
  lines `304`-`357`; [phase-1-haskell-cli-surface.md](phase-1-haskell-cli-surface.md)
  lines `171`-`211`.
- Substrate identifiers and `linux-opencl` counter-grep:
  `grep -RInE 'apple-silicon|linux-cpu|linux-cuda' DEVELOPMENT_PLAN documents/engineering`
  and `grep -RInE 'linux-opencl' DEVELOPMENT_PLAN documents/engineering README.md`.
  Evidence: [system-components.md](system-components.md) lines `43`-`47`;
  [phase-2-bootstrap-reconciler-and-jit-cache.md](phase-2-bootstrap-reconciler-and-jit-cache.md),
  [phase-3-cluster-substrate-and-routing.md](phase-3-cluster-substrate-and-routing.md),
  [phase-7-jit-codegen-and-substrates.md](phase-7-jit-codegen-and-substrates.md),
  and [phase-12-test-stanzas-and-cross-cluster.md](phase-12-test-stanzas-and-cross-cluster.md)
  all name the three supported substrates. The `linux-opencl` hits are limited
  to future-extension / informational-only prose.
- Daemon Dhall fields:
  `grep -RInE 'residency : Cluster \| Host|inferenceMode : SelfInference \| ForwardToHost' DEVELOPMENT_PLAN documents/engineering`
  Evidence: [phase-5-jitml-service-daemon.md](phase-5-jitml-service-daemon.md)
  lines `36`-`37`; [00-overview.md](00-overview.md) lines `344`-`346`.
- Pulsar topics:
  `grep -RInE 'training\.command\.<mode>|training\.event\.<mode>|tune\.command\.<mode>|tune\.event\.<mode>|rl\.command\.<mode>|rl\.event\.<mode>|inference\.request\.<mode>|inference\.result\.<mode>|inference\.command\.apple-silicon|inference\.event\.apple-silicon' DEVELOPMENT_PLAN documents/engineering`
  Evidence: [system-components.md](system-components.md) lines `147`-`156`;
  [phase-5-jitml-service-daemon.md](phase-5-jitml-service-daemon.md) lines `218`-`224`.
- MinIO buckets:
  `grep -RInE 'harbor-registry|jitml-checkpoints|jitml-datasets|jitml-transcripts|jitml-trials|jitml-tensorboard|jitml-artifacts' DEVELOPMENT_PLAN documents/engineering`
  Evidence: [system-components.md](system-components.md) lines `132`-`138`;
  [phase-4-stateful-platform-services.md](phase-4-stateful-platform-services.md)
  and [phase-10-checkpointing-and-inference.md](phase-10-checkpointing-and-inference.md)
  own the service-specific bucket work.
- Cluster invariants:
  `grep -RInE 'kubernetes\.io/no-provisioner|jitml-manual|127\.0\.0\.1:<edge-port>|NodePort 30090|\./\.build/jitml\.kubeconfig' DEVELOPMENT_PLAN documents/engineering`
  Evidence: [phase-3-cluster-substrate-and-routing.md](phase-3-cluster-substrate-and-routing.md)
  lines `88`-`149`; [system-components.md](system-components.md) lines `99`-`111`.
- JIT cache invariants:
  `grep -RInE '\./\.build/jit/<substrate>/<hash>\.<ext>|\./\.build/host/apple-silicon/|\(canonical-cbor\(KernelSpec\), kind, substrate, toolchain-fingerprint\)|lazy-tart' DEVELOPMENT_PLAN documents/engineering`
  Evidence: [phase-2-bootstrap-reconciler-and-jit-cache.md](phase-2-bootstrap-reconciler-and-jit-cache.md)
  lines `133`-`153`; [phase-7-jit-codegen-and-substrates.md](phase-7-jit-codegen-and-substrates.md)
  lines `50`-`82`.
- Checkpoint format:
  `grep -RInE '\.jmw1|blobs/<sha256>|manifests/<sha256>|pointers/\{latest,best/<metric>,trial/<trial-hash>/\.\.\.\}|If-None-Match: \*|If-Match: <etag>|advanceLatest|advanceBestMaximised|advanceBestMinimised' DEVELOPMENT_PLAN documents/engineering`
  Evidence: [phase-10-checkpointing-and-inference.md](phase-10-checkpointing-and-inference.md)
  lines `15`-`19`, `55`-`78`, and `107`-`125`;
  [documents/engineering/checkpoint_format.md](../documents/engineering/checkpoint_format.md)
  lines `136`-`146`.
- Report-card knobs:
  `grep -RInE 'sl_epochs|sl_batch|rl_steps|rl_eval_episodes|az_games|az_sims|tune_trials|tune_budget_per_trial|xcluster_kind_nodes' DEVELOPMENT_PLAN/system-components.md DEVELOPMENT_PLAN/phase-12-test-stanzas-and-cross-cluster.md`
  Evidence: [system-components.md](system-components.md) lines `346`-`354`;
  [phase-12-test-stanzas-and-cross-cluster.md](phase-12-test-stanzas-and-cross-cluster.md)
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

## Doctrine Sections Cited

Sprint `0.1` is structural rather than doctrine-adopting; it instantiates the
plan suite and the doctrine-citation contract but binds no specific doctrine
section to a code-level deliverable. Sprint `0.2` cites the doctrine globally —
its purpose is to audit every in-scope section. Phases `1`–`12` cite individual
doctrine sections at the deliverable level.

The Phase `0`-owned doctrine sections — the meta-rules under which later phases
adopt doctrine — are:

- [../README.md → Documentation metadata contract](../README.md) — instantiated by
  `documents/documentation_standards.md` (Sprint `0.1`).
- [../README.md → README metadata header](../README.md) — instantiated by the
  `**Status**` / `**Supersedes**` / `**Referenced by**` block added to
  `README.md` itself (Sprint `0.1`).
- Standards rule L of [development_plan_standards.md](development_plan_standards.md)
  is the project-internal CLI doctrine alignment contract that every later phase
  follows.

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/documentation_standards.md` — add the six Generated Sections
  elements named by the doctrine's `Project-level documentation standards`
  subsection.
- `documents/engineering/README.md` — index of the twelve scaffolded engineering
  docs named in this phase, with one-line purpose each.
- `documents/engineering/cli_command_surface.md` — defer to the doctrine's
  `Command Topology`, `CommandSpec`, and `Progressive Introspection` sections;
  retain only the jitML-specific command matrix.
- `documents/engineering/code_quality.md` — defer to the doctrine's `Lint,
  Format, and Code-Quality Stack` and `Forbidden Surfaces` plus
  `Generated Artifacts → The generated-section registry` and the paired
  `jitml docs check` / `jitml docs generate` contract; add the chart-lint and
  route-registry-drift project-specific rules.
- `documents/engineering/unit_testing_policy.md` — defer to the doctrine's
  `Testing Doctrine`, `Test Categories`, and `Test Organization` for the tasty
  stanza model; name the ten jitML stanzas.
- `documents/engineering/haskell_code_guide.md` — defer to the doctrine for
  GADT state machines, `Subprocess` values, `Plan / Apply`, prerequisites,
  application environment, error handling, capability classes, retry policy,
  long-running daemons, at-least-once event processing, and reconcilers.
- `documents/engineering/determinism_contract.md` — project-specific: per-
  substrate floating-point semantics (Metal single-stream, oneDNN blocked
  reduction, CUDA warp-shuffle), RNG split, per-experiment seed derivation,
  JIT cache content-addressing, bit-determinism envelope, cross-substrate
  tolerance methodology.
- `documents/engineering/cluster_topology.md` — project-specific: Kind cluster
  shapes per substrate, Helm umbrella chart, storage discipline, Envoy
  Gateway, route registry, Helm-values ownership, no-kubeconfig-pollution
  invariant.
- `documents/engineering/daemon_architecture.md` — project-specific:
  `jitml service` lifecycle, `BootConfig` / `LiveConfig`, hot reload,
  `/healthz` / `/readyz` / `/metrics`, structured logging, recoverable vs
  fatal errors, at-least-once Pulsar consumer.
- `documents/engineering/jit_codegen_architecture.md` — project-specific:
  content-addressed cache, per-substrate compilers (Metal, oneDNN, CUDA),
  Apple Silicon hybrid pattern, hardware auto-tuning, FFI boundary.
- `documents/engineering/numerical_core.md` — project-specific: current local
  layer / activation / spectral / optimizer / scheduler / loss catalog, Dhall
  mirrors, and cross-type audit.
- `documents/engineering/training_workloads.md` — project-specific: current
  local SL summaries, RL framework metadata, RL algorithm catalog, AlphaZero /
  Connect 4 helpers, and hyperparameter tuning catalogs; target daemon-backed
  workloads. Owns the union of Phases `8` and `9`.
- `documents/engineering/checkpoint_format.md` — project-specific: split-blob
  layout, `.jmw1` wire format, manifest, inference-only read path.
- `documents/engineering/purescript_frontend.md` — project-specific:
  current PureScript shell, local browser-contract renderer, bundle, panel, and
  demo-route metadata, Playwright scaffold, and demo shim; target Halogen
  panels, live REST / WebSocket surfaces, compiled bundle serving, and
  Playwright E2E.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- Root guidance docs (`README.md`, `AGENTS.md`, `CLAUDE.md`) link to
  [README.md](README.md) and [../README.md](../README.md)
  as the authoritative plan and project/CLI doctrine entrypoints (Sprint `0.1`).
- The project-root README lists every governed-doc and plan-file consumer in
  its `**Referenced by**` line (Sprint `0.1`).

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [development_plan_standards.md](development_plan_standards.md)
- [system-components.md](system-components.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
- [../README.md](../README.md)
- [../documents/documentation_standards.md](../documents/documentation_standards.md)
