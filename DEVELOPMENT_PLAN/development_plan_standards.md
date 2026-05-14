# Development Plan Standards

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md),
[system-components.md](system-components.md),
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md),
[phase-0-planning-documentation.md](phase-0-planning-documentation.md),
[phase-1-haskell-cli-surface.md](phase-1-haskell-cli-surface.md),
[phase-2-bootstrap-reconciler-and-jit-cache.md](phase-2-bootstrap-reconciler-and-jit-cache.md),
[phase-3-cluster-substrate-and-routing.md](phase-3-cluster-substrate-and-routing.md),
[phase-4-stateful-platform-services.md](phase-4-stateful-platform-services.md),
[phase-5-jitml-service-daemon.md](phase-5-jitml-service-daemon.md),
[phase-6-numerical-core.md](phase-6-numerical-core.md),
[phase-7-jit-codegen-and-substrates.md](phase-7-jit-codegen-and-substrates.md),
[phase-8-supervised-and-rl-framework.md](phase-8-supervised-and-rl-framework.md),
[phase-9-rl-catalog-alphazero-and-tuning.md](phase-9-rl-catalog-alphazero-and-tuning.md),
[phase-10-checkpointing-and-inference.md](phase-10-checkpointing-and-inference.md),
[phase-11-purescript-frontend-and-demo.md](phase-11-purescript-frontend-and-demo.md),
[phase-12-test-stanzas-and-cross-cluster.md](phase-12-test-stanzas-and-cross-cluster.md),
[../documents/documentation_standards.md](../documents/documentation_standards.md),
[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
**Generated sections**: none

> **Purpose**: Define the maintenance rules for the jitML development plan so the
> repository keeps one coherent, execution-ordered plan and one explicit ledger of
> cleanup work across the CLI bootstrap, the three-substrate cluster buildout, the
> training and inference workloads, and the parity-validated test surface.

## Core Principles

### A. Continuous Clean-Room Narrative

The plan must read as one sequential buildout from an empty checkout to the intended
repository end state — one Haskell CLI driving three substrates (`apple-silicon`,
`linux-cpu`, `linux-cuda`) behind a uniform command surface, the `jitml service`
daemon as the single Pulsar-subscribed worker, deterministic JIT-compiled execution
on each substrate, supervised and reinforcement learning training pipelines including
AlphaZero-style self-play, and a PureScript frontend driven from generated browser
contracts.

- Every phase assumes the previous phase has already closed.
- The plan flows from documentation topology to the CLI surface, to bootstrap
  reconcilers and JIT cache discipline, to cluster substrate and stateful platform
  services, to the long-running daemon, then through the numerical core and per-
  substrate JIT codegen, the SL/RL framework and algorithm catalog, AlphaZero and
  hyperparameter tuning, checkpointing and the inference-only read path, the
  PureScript frontend, and finally the test stanzas and Pulumi-orchestrated
  cross-cluster parity surface.
- A reader unfamiliar with the repository must be able to follow the plan top to
  bottom without reconstructing hidden dependencies from multiple documents.
- If a previously closed phase reopens because the repository end state expands later,
  the top-level docs must say exactly which earlier phase reopened, which later phases
  remain closed on their owned surfaces, and why the overall handoff is still
  incomplete.

### B. Detailed, Implementation-Oriented Content

The plan is intentionally specific. It should not collapse into vague milestones or
project management summaries.

- Include concrete deliverables, canonical commands, validation gates, and exact
  blocked prerequisites when they materially clarify closure.
- Examples do not need to be verbatim copies of implementation files, but they must
  not contradict the supported architecture or command surface.
- Command examples must use the canonical binary name `jitml` (or `jitml-demo` for the
  bundled HTTP server).
- Substrate identifiers are `apple-silicon`, `linux-cpu`, and `linux-cuda` on the CLI
  and in Dhall configuration. Substrate identifiers may not be renamed, abbreviated,
  or pluralised in plan or doctrine prose.
- Deprecated aliases or legacy command paths belong only in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

### C. Honest Completion Tracking

Status must describe reality, not intent.

| Indicator | Meaning |
|-----------|---------|
| ✅ | Completed and validated |
| 🔄 | Active and partially complete |
| 📋 | Planned and ready to start |
| ⏸️ | Blocked by an unmet prerequisite |

- `Done` requires passing validation, aligned docs, and no remaining sprint-owned
  work.
- `Active` requires a `Remaining Work` section.
- `Blocked` requires a `Blocked by` line.
- `Planned` means dependencies are already satisfied; it must not list unmet
  blockers.
- Status is always scoped to the sprint or phase-owned surface. A later phase may
  remain `Done` when an earlier phase reopens, but the reopened dependency must be
  called out explicitly in `README.md` and `00-overview.md`.
- If Phase `0` is still open, later code-writing phases (Phases `1`–`12`) use
  `Blocked`, not `Planned`, since their owned surfaces depend on the doctrine-
  citation contract and the documentation-topology baseline that Phase `0` provides.

### D. Declarative Plan Language

Phase documents describe the intended architecture in present-tense declarative
language.

- Say what the repository uses, owns, validates, and removes.
- Do not turn phase docs into migration diaries.
- Cleanup history and compatibility residue belong in the explicit legacy-removal
  ledger, not as the main narrative of a phase.
- Active sprint bodies describe the end state in present tense; only the
  `### Remaining Work` subsection uses future/incomplete language.

### E. One Canonical Phase Model

The development plan uses exactly this document structure:

```text
DEVELOPMENT_PLAN/
├── development_plan_standards.md
├── README.md
├── 00-overview.md
├── system-components.md
├── legacy-tracking-for-deletion.md
├── phase-0-planning-documentation.md
├── phase-1-haskell-cli-surface.md
├── phase-2-bootstrap-reconciler-and-jit-cache.md
├── phase-3-cluster-substrate-and-routing.md
├── phase-4-stateful-platform-services.md
├── phase-5-jitml-service-daemon.md
├── phase-6-numerical-core.md
├── phase-7-jit-codegen-and-substrates.md
├── phase-8-supervised-and-rl-framework.md
├── phase-9-rl-catalog-alphazero-and-tuning.md
├── phase-10-checkpointing-and-inference.md
├── phase-11-purescript-frontend-and-demo.md
└── phase-12-test-stanzas-and-cross-cluster.md
```

No phase may be skipped. No sprint may exist in two phases. CLI-surface ownership,
bootstrap-reconciler ownership, cluster-substrate ownership, platform-services
ownership, daemon ownership, numerical-core ownership, per-substrate JIT-codegen
ownership, SL/RL-framework ownership, RL-algorithm/AlphaZero/tuning ownership,
checkpointing ownership, frontend ownership, and test-stanza ownership each live in
one place only.

### F. System Component Inventory

[system-components.md](system-components.md) is the authoritative component inventory
for:

- substrates and their JIT-cache homes
- CLI surfaces and runtime controls (subcommand families)
- stateful platform services (Harbor, MinIO, Pulsar, PostgreSQL, observability)
- the `jitml service` daemon (BootConfig / LiveConfig surfaces, capability classes)
- numerical-core ADTs (layer catalog, optimizers, schedulers, losses) and Dhall types
- per-substrate JIT codegen artefacts and content-addressed cache layout
- training-workload surfaces (SL loops, RL framework, RL catalog, AlphaZero, tuning)
- checkpoint format and inference-only read path
- frontend bundle and generated browser-contract surfaces
- test stanzas, lint matrix, and Pulumi-orchestrated infrastructure surfaces
- toolchain prerequisites and pinned versions
- state locations (cache root, kubeconfig, kind state, runtime spool, golden roots)

When a phase changes the supported architecture, update the inventory in the same
change.

### G. Phase Documentation Requirements

Every phase document must contain a `Documentation Requirements` section that lists
which governed documents need creation or update under
[../documents/documentation_standards.md](../documents/documentation_standards.md).

Use this format:

```markdown
## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/X.md` — [description]

**Product docs to create/update:**
- None.

**Cross-references to add:**
- Add backlink from Z.md
```

Rules:

- Architecture, command-surface, determinism-contract, daemon-architecture,
  cluster-topology, JIT-codegen, numerical-core, training-workload, checkpoint-format,
  and frontend changes require engineering-document updates.
- The plan must not claim a sprint is done if the listed docs are stale.
- If the repository has no product-doc ownership for a phase, say `None.` explicitly.

### H. Sprint Status Format

Every sprint uses the same basic structure:

```markdown
## Sprint X.Y: Name [STATUS]

**Status**: Done | Active | Planned | Blocked
**Implementation**: `path/to/file` (required for Done, recommended otherwise)
**Blocked by**: sprint id(s) or external prerequisite (required for Blocked)
**Docs to update**: `file.md`, `other.md`

### Objective

### Deliverables

### Validation

### Remaining Work
```

Additional sections such as `Current Validation State`, `Current Blockers`,
`Architecture`, `Schema`, or `Substrate Notes` are encouraged when they clarify
design or closure.

### I. Explicit Cleanup and Removal Ledger

[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) is mandatory and
comprehensive. It is the authoritative list of all known compatibility helpers,
deprecated paths, duplicate surfaces, and stale tooling residue that still need
removal.

- If a deprecated or compatibility feature exists anywhere in the repository, it must
  appear in the ledger.
- Each ledger item must name its location, why it is slated for removal, and the
  sprint that owns the cleanup.
- When the cleanup lands, move the item from `Pending Removal` to `Completed`.
- Phase docs reference the owning sprint, not duplicate the full cleanup ledger.
- The ledger is empty in both sections at write time because the repository contains
  no source code yet; rows are enqueued by Sprint `0.2`'s doctrine-driven scheduling
  audit and by every later sprint that introduces a deviation or stand-in.

### J. Documentation Harmony

The plan and governed documents must agree.

- [README.md](README.md), [00-overview.md](00-overview.md), every phase file, and
  [system-components.md](system-components.md) must use the same phase names, sprint
  statuses, substrate identifiers, and dependency model.
- Governed docs under `documents/engineering/` must match the current architecture
  described by the plan.
- Root guidance docs `README.md`, `AGENTS.md`, and `CLAUDE.md` must point to both
  [README.md](README.md) and [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md).

### K. Mermaid Rendering Contract

Mermaid diagrams in `DEVELOPMENT_PLAN/` must follow the repository-safe subset and
authoring rules defined in
[../documents/documentation_standards.md](../documents/documentation_standards.md).

If a change adds or edits a Mermaid block in this directory, closure requires:

1. Rendering every Mermaid block in `DEVELOPMENT_PLAN/` through a standalone
   renderer.
2. Failing the change on any render error.
3. Verifying the edited diagram in the repository's target Markdown viewer.
4. Running `jitml check-code` after the documentation change (once Phase 1 lands the
   command; until then, the lint stack is run manually through `fourmolu --mode
   check`, `hlint`, and `cabal format`).

This standards document describes Mermaid rules with prose, inline code, or
`markdown` examples only. Do not add live Mermaid blocks here.

### L. CLI Doctrine Alignment

[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md) is the authoritative CLI doctrine.
Phase documents and sprint blocks that schedule adoption work must cite the doctrine
sections they implement by name (for example, `CommandSpec`, `Plan / Apply`,
`Subprocesses as Typed Values`, `Prerequisites as Typed Effects`, `Application
Environment`, `Long-Running Daemons in the Same Binary`, `Reconcilers: Idempotent
Mutation as a Single Command`, `At-Least-Once Event Processing`, `Capability Classes
and Service Errors`, `Retry Policy as First-Class Values`, `Lint, Format, and
Code-Quality Stack`, `Generated Artifacts → The generated-section registry`,
`Test Organization`, `Output Rules`, `Error Handling`, `Toolchain pinning`, `Project
Structure`).

- Governed engineering docs under `documents/engineering/` referenced from the
  doctrine's `Referenced by` line must defer to the doctrine for the patterns it owns
  and retain only project-specific elaborations such as substrate identifiers,
  Pulsar topic names, the Envoy Gateway socket convention, JIT-cache content-
  addressing, RL-algorithm identifiers, AlphaZero loop, or the checkpoint wire
  format.
- The jitML adoption envelope of the doctrine is bounded: the in-scope and
  out-of-scope splits live in [00-overview.md](00-overview.md) `Doctrine Scope` and
  are inherited verbatim from the project [../README.md](../README.md) `Doctrine
  scope` section. No sprint may schedule adoption of an out-of-scope doctrine
  section.
- When the doctrine prescribes a behavior that the implemented worktree does not yet
  honor and the section is in scope, the gap is scheduled through a sprint
  deliverable in the appropriate phase. Closing the gap silently without a sprint
  binding is forbidden.
- Doctrine-driven removals — superseded helpers, deprecated CLI flags, parallel
  workflow surfaces — flow through
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) like any other
  cleanup.
- If a doctrine section changes, the same change updates every governed doc that
  references it.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
- [../documents/documentation_standards.md](../documents/documentation_standards.md)

## Cross-Reference Conventions

- Links inside `DEVELOPMENT_PLAN/` use relative paths.
- Links to governed docs under `documents/` use repository-relative paths
  (`../documents/...`).
- Links to the doctrine use `../HASKELL_CLI_TOOL.md`.
- File renames require same-change link updates everywhere the file is referenced.

## Maintenance Guidelines

1. Update the global control documents first: `README.md`, `00-overview.md`, and
   `system-components.md`.
2. Update the affected phase document next.
3. Update the governed engineering docs listed in `Docs to update`.
4. Update [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) whenever
   cleanup scope changes.
5. Run `jitml check-code` before closing the work (once Phase 1 lands the command;
   until then, run `fourmolu --mode check`, `hlint`, and `cabal format` manually).
6. If the change touched Mermaid, render every Mermaid block in `DEVELOPMENT_PLAN/`
   and verify the edited diagram in the target viewer before closing the work.
