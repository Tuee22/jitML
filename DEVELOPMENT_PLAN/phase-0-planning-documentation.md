# Phase 0: Planning and Documentation Topology

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md),
[development_plan_standards.md](development_plan_standards.md),
[system-components.md](system-components.md),
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md),
[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
**Generated sections**: none

> **Purpose**: Define the plan-ownership baseline for the jitML Haskell CLI so phase
> status, sequencing, doctrine-alignment, and documentation-topology work has one
> canonical home.

## Phase Status

🔄 **Active** — Sprint `0.1` (canonical plan suite bootstrap) is `🔄 Active` at
write time as the bootstrap commit lands; Sprint `0.2` (doctrine-driven scheduling
audit) is `📋 Planned`. The phase closes when Sprint `0.1` finishes the bootstrap
commit, Sprint `0.2` lands, and every in-scope doctrine identifier is bound to an
owned deliverable in Phases `1`–`12`.

## Phase Summary

This phase establishes the development plan as the canonical execution-ordered
record for the jitML repository, the governed `documents/` doctrine suite, the root-
file pointers that name [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md) as the
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

## Sprint 0.1: Canonical Plan Suite Bootstrap 🔄

**Status**: Active
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
`HASKELL_CLI_TOOL.md`, `README.md`, `AGENTS.md`, `CLAUDE.md`
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
  Pulumi cross-cluster.
- [development_plan_standards.md](development_plan_standards.md) declares rules
  A–L, including the CLI Doctrine Alignment rule L that requires phase docs to
  cite [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md) sections by name on
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
  Generated Sections elements per [../HASKELL_CLI_TOOL.md → Project-level
  documentation standards](../HASKELL_CLI_TOOL.md): marker convention with
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
- `HASKELL_CLI_TOOL.md` carries the standard `**Status**` / `**Supersedes**` /
  `**Referenced by**` metadata block plus a `> **Purpose**:` line. The doctrine
  body is verbatim authoritative; no other edits.
- `README.md` (project root) carries one added pointer paragraph linking to
  [README.md](README.md) and [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md) as
  the authoritative plan and doctrine entrypoints. No other content changes.
- `AGENTS.md` and `CLAUDE.md` (project root) carry two appended pointer lines
  below the existing git-restriction block: one to
  [`DEVELOPMENT_PLAN/README.md`](README.md) and one to
  [`HASKELL_CLI_TOOL.md`](../HASKELL_CLI_TOOL.md). Existing content unchanged.

### Validation

1. Every `[..](path)` link inside `DEVELOPMENT_PLAN/`, `documents/`, and the four
   root files resolves to a file that exists on disk.
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
9. Root `README.md`, `AGENTS.md`, and `CLAUDE.md` link to both
   `DEVELOPMENT_PLAN/README.md` and `HASKELL_CLI_TOOL.md`.
10. Mermaid render pass per standards rule K: `README.md`'s Sprint Dependencies
    flowchart is the only Mermaid block in `DEVELOPMENT_PLAN/` at Sprint `0.1`
    closure; it renders successfully.

### Remaining Work

- [ ] Bootstrap commit lands the eighteen `DEVELOPMENT_PLAN/`, fourteen
      `documents/`, and four edited root files in one atomic change.
- [ ] Mermaid render pass executed against `DEVELOPMENT_PLAN/README.md`.

## Sprint 0.2: Doctrine-Driven Scheduling Audit ⏸️

**Status**: Blocked
**Blocked by**: Sprint 0.1
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
[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md) is owned by an explicit sprint
deliverable in Phases `1`–`12`. Any unowned identifier is scheduled by extending an
existing sprint's `Deliverables` block (or, if no existing sprint is a natural
home, adding a new sprint). The audit's purpose is to ensure no in-scope doctrine
prescription gets silently adopted at code-write time without a plan-level binding,
per standards rule L.

### Deliverables

- A grep audit of [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md) enumerates
  every prescriptive identifier from the in-scope sections. The expected
  identifier list (non-exhaustive) is:
  - **Toolchain pinning**: `GHC 9.14.1`, `Cabal 3.16.1.0`,
    `tested-with: ghc ==9.14.1`, `with-compiler: ghc-9.14.1`. Per-substrate
    codegen pins: LLVM, NVCC (`--use_fast_math=false`, baseline `sm_70`),
    Xcode/Metal, oneDNN (AVX2 baseline), `kindest/node` pinned in the Kind
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
    three-element error message contract on drift. Generated artefacts include
    the route table, Grafana dashboards, protobuf schemas (Pulsar event
    schemas, vendored TensorBoard `event.proto`), PureScript contracts, CLI
    help, markdown command reference, manpages, shell completions.
  - **Subprocesses as Typed Values**: `Subprocess`, `subprocessPath`,
    `subprocessArguments`, `subprocessEnvironment`,
    `subprocessWorkingDirectory`, `renderSubprocess`, `runStreaming`,
    `capture`; forbidden primitives `callProcess`, `readCreateProcess`,
    `System.Process`, `typed-process` smart constructors. Wrapped subprocesses
    must include `kubectl`, `helm`, `kind`, `docker`, `metal`, `nvcc`, `g++`
    (over oneDNN), `tart`, and the per-substrate kernel compilers.
  - **Plan / Apply**: `Plan`, `build`, `apply`, `--dry-run`, `--plan-file
    <path>`. Owning Plan/Apply commands: `jitml train`, `jitml tune`,
    `jitml cluster up`, `jitml test all`, `jitml service` startup-as-plan,
    `jitml internal gc`.
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
    `nodeDescription`, remedy hint, `AppError PrerequisiteUnmet`. Bootstrap-
    script verbs `help | doctor | build | up | status | test | down | purge`
    (Linux adds `push`) reconcile against the same typed DAG.
  - **Application Environment**: `ReaderT Env IO`, single `Env` record.
  - **Long-Running Daemons in the Same Binary**: `BootConfig`, `LiveConfig`,
    SIGHUP hot reload, `/healthz`, `/readyz`, `/metrics`, structured JSON
    stderr logging, recoverable-vs-fatal error kinds.
  - **At-Least-Once Event Processing**: protobuf-message-hash deduplication
    keys; Pulsar consumer semantics; idempotent application of `gc_reaped` and
    `CheckpointDone` events.
  - **Reconcilers: Idempotent Mutation as a Single Command**: `jitml cluster
    up`, `jitml docs generate`, `jitml lint --write`, `jitml internal gc
    <experiment-hash>`. Exit code `3` on no-op.
  - **Lint, Format, Code-Quality Stack**: `fourmolu.yaml`, the twelve settings
    (`indentation`, `column-limit`, `function-arrows`, `comma-style`,
    `import-export-style`, `indent-wheres`, `record-brace-space`,
    `newlines-between-decls`, `haddock-style`, `let-style`, `in-style`,
    `unicode`), `hlint`, `cabal format` temp-file round-trip byte-equality,
    `forbiddenPathRegistry` refusing `.github/workflows/`, `.husky/`,
    `.githooks/`, root `Makefile` / `justfile` / `Taskfile.yml`. Plus chart
    lint refusing freestanding PVCs, non-`kubernetes.io/no-provisioner`
    StorageClasses, and PVs without explicit `claimRef`.
  - **Testing Doctrine, Standard Testing Stack, Test Categories, Test
    Organization**: per-tier stanza model, `type: exitcode-stdio-1.0`,
    `tasty`, `execParserPure`, property invariants `decode . encode == id`,
    `render is deterministic`, `parser roundtrips`, golden tests with
    sentinel placeholders for non-deterministic content, daemon-lifecycle
    tests, Pulumi-orchestrated infrastructure tests. Ten `jitml-*` stanzas:
    `jitml-unit`, `jitml-integration`, `jitml-sl-canonicals`,
    `jitml-rl-canonicals`, `jitml-hyperparameter`, `jitml-cross-backend`,
    `jitml-daemon-lifecycle`, `jitml-e2e`, `jitml-haskell-style`,
    `jitml-purescript-style`.
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
    `./.build/host/apple-silicon/`, the four-tuple cache key
    `(canonical-cbor(KernelSpec), kind, substrate, toolchain-fingerprint)`,
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
4. Each new deliverable cites the [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
   section it implements by section heading per standards rule L.
5. Mermaid render pass (standards rule K) is a no-op — Sprint `0.2` introduces
   no diagrams.
6. Plan-level lint pass: the manual `fourmolu --mode check` and `hlint` runs
   are no-ops (no Haskell code yet); the plan-level checks reduce to the
   cross-reference resolution, metadata-block consistency, and identifier-audit
   checks named above.

## Doctrine Sections Cited

Sprint `0.1` is structural rather than doctrine-adopting; it instantiates the
plan suite and the doctrine-citation contract but binds no specific doctrine
section to a code-level deliverable. Sprint `0.2` cites the doctrine globally —
its purpose is to audit every in-scope section. Phases `1`–`12` cite individual
doctrine sections at the deliverable level.

The Phase `0`-owned doctrine sections — the meta-rules under which later phases
adopt doctrine — are:

- [../HASKELL_CLI_TOOL.md → Project-level documentation
  standards](../HASKELL_CLI_TOOL.md) — instantiated by
  `documents/documentation_standards.md` (Sprint `0.1`).
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md) header — instantiated by the
  `**Status**` / `**Supersedes**` / `**Referenced by**` block added to
  `HASKELL_CLI_TOOL.md` itself (Sprint `0.1`).
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
  Gateway, route registry, no-kubeconfig-pollution invariant.
- `documents/engineering/daemon_architecture.md` — project-specific:
  `jitml service` lifecycle, `BootConfig` / `LiveConfig`, hot reload,
  `/healthz` / `/readyz` / `/metrics`, structured logging, recoverable vs
  fatal errors, at-least-once Pulsar consumer.
- `documents/engineering/jit_codegen_architecture.md` — project-specific:
  content-addressed cache, per-substrate compilers (Metal, oneDNN, CUDA),
  Apple Silicon hybrid pattern, hardware auto-tuning, FFI boundary.
- `documents/engineering/numerical_core.md` — project-specific: layer
  catalog, activations (real + complex), spectral ops, optimizers,
  schedulers, losses, Dhall types.
- `documents/engineering/training_workloads.md` — project-specific: SL
  training loops, RL framework primitives, RL algorithm catalog, AlphaZero /
  MCTS state, hyperparameter tuning. Owns the union of Phases `8` and `9`.
- `documents/engineering/checkpoint_format.md` — project-specific: split-blob
  layout, `.jmw1` wire format, manifest, inference-only read path.
- `documents/engineering/purescript_frontend.md` — project-specific:
  `src/JitML/Web/Contracts.hs` as source for `purescript-bridge`, Halogen
  panels, REST surfaces, Playwright E2E, demo HTTP server.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- Root guidance docs (`README.md`, `AGENTS.md`, `CLAUDE.md`) link to
  [README.md](README.md) and [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
  as the authoritative plan and CLI doctrine entrypoints (Sprint `0.1`).
- The doctrine itself lists every governed-doc and plan-file consumer in its
  `**Referenced by**` line (Sprint `0.1`).

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [development_plan_standards.md](development_plan_standards.md)
- [system-components.md](system-components.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
- [../documents/documentation_standards.md](../documents/documentation_standards.md)
