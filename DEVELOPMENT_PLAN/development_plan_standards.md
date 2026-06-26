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
[phase-13-no-caveat-model-runtime.md](phase-13-no-caveat-model-runtime.md),
[phase-14-interactive-demo-and-playwright-closure.md](phase-14-interactive-demo-and-playwright-closure.md),
[phase-15-linux-cuda-and-cluster-closure.md](phase-15-linux-cuda-and-cluster-closure.md),
[phase-16-apple-silicon-closure.md](phase-16-apple-silicon-closure.md),
[phase-17-cross-substrate-and-handoff.md](phase-17-cross-substrate-and-handoff.md),
[phase-18-no-caveat-product-handoff.md](phase-18-no-caveat-product-handoff.md),
[../documents/documentation_standards.md](../documents/documentation_standards.md),
[../README.md](../README.md)
**Generated sections**: none

> **Purpose**: Define the maintenance rules for the jitML development plan so the
> repository keeps one coherent, execution-ordered plan plus an explicit cleanup
> ledger across the CLI bootstrap, the three-substrate cluster buildout, the
> training and inference workloads, and the within-substrate test surface.

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
  PureScript frontend, and finally the test stanzas, live workflow matrix, and
  final handoff surface.
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
- Command examples must use the canonical binary name `jitml`. `jitml-demo`
  names only the Kubernetes Webapp workload, service, Helm release, and image
  tag for that same binary.
- Substrate identifiers are `apple-silicon`, `linux-cpu`, and `linux-cuda` on the CLI
  and in Dhall configuration. Substrate identifiers may not be renamed, abbreviated,
  or pluralised in plan or doctrine prose.
- JIT build source is not checked in as static substrate files. Any source code
  artefact needed to compile a JIT kernel, including CUDA `.cu`, C/C++ `.cc` /
  `.cpp`, generated Metal Shading Language, optional Swift package sources,
  native adapter shims, and per-substrate build `.sh` scripts, is generated on
  demand by the Haskell `jitml` binary into the content-addressed build/cache
  tree. Checked-in code may contain Haskell renderers, typed templates, the
  source for a fixed non-kernel host bridge, and tests for those renderers, but
  not ready-to-run per-kernel native/JIT source files, adapter shims, or build
  scripts. If a runtime path needs a per-kernel native adapter, it belongs in a
  Haskell renderer and is materialized under the generated build/cache tree;
  otherwise file lint rejects it. On `apple-silicon`, the core JIT cache-miss
  path renders MSL plus launch metadata into a content-addressed
  `<hash>.metal.json` source artifact and invokes a fixed host Metal bridge that
  calls `MTLDevice.makeLibrary(source:options:)` with fast math disabled before
  dispatching on the host GPU. The core path does **not** start Tart, require an
  unlocked keychain, invoke SwiftPM, require the offline `metal` compiler, or
  install full Xcode on the host. Optional generated Swift modules, if later
  enabled, are a separate capability gated by explicit `swiftc` + macOS SDK
  probes and are not the training/inference cache-miss path. Full detail lives in
  [../documents/engineering/apple_silicon_metal_headless_builds.md](../documents/engineering/apple_silicon_metal_headless_builds.md).
- Deprecated aliases or legacy command paths belong only in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

### C. Honest Completion Tracking

Status describes reality against the project's Exit Definition, not against an
intermediate scaffold layer. The Exit Definition is the eighteen-item list in
[README.md → Exit Definition](README.md#exit-definition). Each sprint owns a
subset of those Exit Definition obligations; that subset is named in the
sprint's `### Objective` and `### Deliverables` blocks.

| Status | Meaning | Emoji |
|--------|---------|-------|
| **Done** | Every Exit-Definition obligation the sprint owns is met in the worktree, validated by the sprint's `### Validation` commands, and the listed docs are aligned. A sprint whose entire obligation is documentation, typed scaffolding, schema/ADT, generated-section, or pure-Haskell catalog work is legitimately Done when that surface is in place and tested; a sprint whose obligation includes live runtime behaviour (cluster up, Helm apply, Pulsar subscribe, MinIO put, kernel compile-and-execute, browser interaction, etc.) is Done only after that live behaviour is exercised through the sprint's validation. | ✅ |
| **Active** | Work has started and at least one owned Exit-Definition obligation is unmet. The sprint body lists those gaps in an explicit `### Remaining Work` block. | 🔄 |
| **Planned** | All upstream sprint dependencies are Done. The sprint has not yet started. It must list no unmet blockers. | 📋 |
| **Blocked** | At least one upstream sprint or external prerequisite required for this sprint's owned obligations is not Done. The sprint body lists the blockers in a `**Blocked by**:` line. | ⏸️ |

- `Done` requires passing validation, aligned docs, and zero remaining
  sprint-owned obligations against the Exit Definition.
- `Active` requires a `### Remaining Work` block that enumerates the unmet
  Exit-Definition obligations the sprint still owns and the validation commands
  that would close them.
- `Blocked` requires a `**Blocked by**:` line naming the upstream sprint id(s)
  or external prerequisite.
- `Planned` means dependencies are already satisfied; it must not list unmet
  blockers.
- Status applies to the full obligation, not to a checked-in scaffold layer.
  The plan does not distinguish a "local surface" Done from a "live runtime"
  Done — there is one Done bar, and it is the Exit Definition obligation.
- Primary unmet obligations do not flow into
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md); they
  remain in the owning sprint's `### Remaining Work` until closed. The legacy
  ledger tracks only doctrine deviations and temporary compatibility helpers
  per rule I.
- If Phase `0` is still open, later code-writing phases (Phases `1`–`12`) use
  `Blocked`, not `Planned`, since their owned surfaces depend on the
  doctrine-citation contract and the documentation-topology baseline that
  Phase `0` provides.
- If a previously Done phase reopens because the Exit Definition expands, the
  reopened phase moves back to `Active` and `README.md` and `00-overview.md`
  call the reopening out explicitly.

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
├── phase-12-test-stanzas-and-cross-cluster.md
├── phase-13-no-caveat-model-runtime.md
├── phase-14-interactive-demo-and-playwright-closure.md
├── phase-15-linux-cuda-and-cluster-closure.md
├── phase-16-apple-silicon-closure.md
├── phase-17-cross-substrate-and-handoff.md
└── phase-18-no-caveat-product-handoff.md
```

No phase may be skipped. No sprint may exist in two phases. CLI-surface ownership,
bootstrap-reconciler ownership, cluster-substrate ownership, platform-services
ownership, daemon ownership, numerical-core ownership, per-substrate JIT-codegen
ownership, SL/RL-framework ownership, RL-algorithm/AlphaZero/tuning ownership,
checkpointing ownership, frontend ownership, test-stanza ownership, no-caveat
model-runtime closure ownership, interactive-demo/Playwright closure ownership,
Linux-CUDA/cluster-closure ownership, Apple-Silicon-closure ownership,
cross-substrate-handoff ownership, and no-caveat product-handoff ownership each
live in one place only.

The closure phases form a **forward chain** (renumbered 2026-06-16 per the
forward-DAG doctrine in rule M): Phase `13` owns the full no-caveat model runtime
(consuming the reopened Phases `8`–`10`), Phase `14` owns the browser product
surface plus Playwright assertions for that runtime, and both close on the
always-available `linux-cpu` lane. Phases `15`–`17` then carry every live-runtime
obligation extracted from Phases `7`–`14` and consolidate it by machine-affinity
so each phase is independently closeable on a single host with **at most one**
accelerator plus `linux-cpu`: Phase `15` is the `linux-cuda` live lane (NVIDIA
host), Phase `16` is the `apple-silicon` live lane (Mac host, independent of Phase
`15`), and Phase `17` aggregates within-substrate reproducibility from the
committed per-lane artifacts on `linux-cpu`. Phase `18` is the final
`linux-cpu`-only handoff that merges the per-lane evidence into one no-caveat
report card. Every Blocked-by and dependency edge references a strictly
lower-numbered phase (rule M), so the plan is workable in numerical order.

### F. System Component Inventory

[system-components.md](system-components.md) is the authoritative component inventory
for:

- substrates and their JIT-cache homes
- CLI surfaces and runtime controls (subcommand families)
- stateful platform services (Harbor, MinIO, Pulsar, PostgreSQL, observability)
- the `jitml service` daemon (BootConfig / LiveConfig surfaces, capability classes)
- numerical-core ADTs (layer catalog, optimizers, schedulers, losses) and Dhall types
- per-substrate JIT source renderers, generated-on-demand codegen artefacts, and
  content-addressed cache layout
- training-workload surfaces (SL loops, RL framework, RL catalog, AlphaZero, tuning)
- checkpoint format and inference-only read path
- frontend bundle and generated browser-contract surfaces
- test stanzas, lint matrix, and ephemeral-cluster infrastructure surfaces
- toolchain prerequisites and pinned versions
- state locations (cache root, kubeconfig, Kind metadata, runtime metadata,
  manual PV root, snapshot roots)

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
- The ledger began empty during the clean-room planning pass. Once source code
  exists, the ledger must reflect the actual worktree: pending compatibility
  helpers, deprecated paths, and stand-ins are listed under `Pending Removal`, and
  completed removals are moved to `Completed`.

### J. Documentation Harmony

The plan and governed documents must agree.

- [README.md](README.md), [00-overview.md](00-overview.md), every phase file, and
  [system-components.md](system-components.md) must use the same phase names, sprint
  statuses, substrate identifiers, and dependency model.
- Governed docs under `documents/engineering/` must match the current architecture
  described by the plan.
- Root guidance docs `README.md`, `AGENTS.md`, and `CLAUDE.md` must point to the
  project [../README.md](../README.md) and
  [DEVELOPMENT_PLAN/README.md](README.md).

### K. Mermaid Rendering Contract

Mermaid diagrams in `DEVELOPMENT_PLAN/` must follow the repository-safe subset and
authoring rules defined in
[../documents/documentation_standards.md](../documents/documentation_standards.md).

If a change adds or edits a Mermaid block in this directory, closure requires:

1. Rendering every Mermaid block in `DEVELOPMENT_PLAN/` through a standalone
   renderer.
2. Failing the change on any render error.
3. Verifying the edited diagram in the repository's target Markdown viewer.
4. Running `jitml check-code` inside `jitml:local` after the documentation change
   (once Phase 1 lands the command; until then, the lint stack is run manually
   inside the container through `fourmolu --mode check`, `hlint`, and
   `cabal format`).

This standards document describes Mermaid rules with prose, inline code, or
`markdown` examples only. Do not add live Mermaid blocks here.

### L. Project Doctrine Alignment

[../README.md](../README.md) is the authoritative project and CLI doctrine.
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
  README's `Referenced by` line must defer to the README for the patterns it owns
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

### M. Forward-Only, Single-Accelerator, Numerically-Ordered Phases

This rule is the binding form of the project doctrine
[Substrate-Affinity Phasing](../README.md#substrate-affinity-phasing) (in the
[../README.md](../README.md) `Doctrine scope` registry). Its two primary
invariants are **(a) Forward-Only Phase Dependencies** and **(b)
Single-Accelerator Phase Validation**; **(c) numerical-order execution** and
**(d) single-host closeability** are corollaries. The phase graph is a strict
forward DAG that is workable in numerical order, and every phase closes on one
host with at most one accelerator. These four invariants are mandatory; any plan
change that would violate one is rejected, and the `### M. Enforcement` checks
below make the plan self-policing. Invariants (a) and (b) are shared verbatim with
the `infernix` sister project as the cross-project
[Pulsar ML-Workflow Contract](../documents/engineering/pulsar_ml_workflow.md)
(`Phasing rules`), so both repos converge on one forward-only,
single-accelerator-per-phase shape.

- **(a) Forward-only dependencies.** A phase's owned obligations, its sprints'
  `**Blocked by**:` lines, and every dependency edge it declares may reference
  only **equal-or-lower-numbered** phases and sprints. A later phase must never
  appear in an earlier phase's `Blocked by`. A later phase *may* own an obligation
  migrated out of an earlier phase — that is an ownership transfer (the earlier
  phase's `Done` is then defined on its retained surface only), not a blocker.
  Phases `0`–`12` retain forward "deferral" prose only as ownership transfers to
  the downstream owner, never as blockers.
- **(b) Single accelerator per phase.** No single phase's closure may require both
  `apple-silicon` and `linux-cuda`. A phase that needs an accelerator selects
  **exactly one** of `{linux-cuda, apple-silicon}` plus `linux-cpu`. A contract
  that must hold on both accelerators is split into two sibling phases (one per
  accelerator) or attested per-lane in independent sessions and aggregated by a
  later `linux-cpu`-only phase. A phase's `### Validation` block must not list a
  single must-pass-together gate spanning both accelerators.
- **(c) Numerical-order execution.** The plan is workable strictly in numerical
  order: every `Depends-On`/`Blocked by` edge references a strictly lower number
  (a consequence of (a)), and each phase is **fully validated** — its owned
  Exit-Definition obligations met per rule C — before the next phase begins.
- **(d) Single-host closeability.** Each phase is fully closeable in a single
  machine session on a single host: a `linux-cpu`-only phase closes on any Docker
  host; a `linux-cuda` phase closes on the NVIDIA host (which also provides
  `linux-cpu`); an `apple-silicon` phase closes on the Mac host (which also
  provides `linux-cpu`). No phase requires two hosts. Cross-substrate
  reproducibility and final handoff are therefore `linux-cpu`-only **aggregation**
  phases that consume per-lane artifacts committed by the earlier
  single-accelerator phases — they never re-run an accelerator lane.

Already-`Done` phases whose historical Validation listed all three substrates in
one block (for example, the per-lane SL/RL/e2e gates) are re-documented as
**validated per-lane in separate single-host sessions** to satisfy (b)/(d); this
is a documentation note, not a code change, and does not reopen them. When the
closure phases are renumbered to honor (a)–(d), the renumbering is recorded at the
top of [README.md](README.md) `Closure Status` with an explicit old→new map.

#### M. Enforcement

Invariants (a) and (b) are machine-checkable, so the plan polices itself rather
than relying on reviewer vigilance. A plan change closes only when all three
checks below report their zero-tolerance count, and the maintenance pass
(`Maintenance Guidelines`) runs them alongside `jitml check-code` / `jitml docs
check`. Each check is a deterministic scan over `phase-*.md` (no model judgement
required):

1. **Zero backward edges — enforces (a)/(c).** Build the dependency graph from
   every sprint `**Blocked by**:` line and every declared dependency edge; the
   pass condition is **0 edges** pointing from a lower-numbered phase/sprint to a
   higher-numbered one. Ownership-transfer prose is not an edge and is excluded by
   construction. (Reference scan: for each `phase-N-*.md`, every `N'.M` and
   `Phase N'` named in a `**Blocked by**:` line satisfies `N' <= N`.)
2. **No dual-accelerator validation gate — enforces (b).** For every phase, **no
   single `### Validation` gate** names both an `apple-silicon` lane
   (`--apple-silicon` / `apple-silicon.sh`) and a `linux-cuda` lane
   (`--linux-cuda` / `linux-cuda.sh` / `-fcuda`). A phase may name both
   accelerators only across *separate* per-lane gates, or as historical /
   aggregation prose — never in one must-pass-together gate. Pass condition:
   dual-accelerator-gate count == 0.
3. **Aggregation-phase no-rerun — enforces (d).** A `linux-cpu`-aggregation
   phase's `### Validation` contains only `--linux-cpu` invocations plus
   "merge committed per-lane fragment" steps — no `-fcuda` / `--apple-silicon`
   lane re-runs. Pass condition: per such phase, accelerator-invocation count == 0.

Any future automation (a `jitml docs check` lint or CI step) implements exactly
these three predicates; until then they are run as the documented deterministic
scan before closing a plan change.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
- [../README.md](../README.md)
- [../documents/documentation_standards.md](../documents/documentation_standards.md)

## Cross-Reference Conventions

- Links inside `DEVELOPMENT_PLAN/` use relative paths.
- Links to governed docs under `documents/` use repository-relative paths
  (`../documents/...`).
- Links to project doctrine use `../README.md`.
- File renames require same-change link updates everywhere the file is referenced.

## Maintenance Guidelines

1. Update the global control documents first: `README.md`, `00-overview.md`, and
   `system-components.md`.
2. Update the affected phase document next.
3. Update the governed engineering docs listed in `Docs to update`.
4. Update [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) whenever
   cleanup scope changes.
5. Run the three `### M. Enforcement` deterministic scans over `phase-*.md` and
   confirm each reports its zero-tolerance count (0 backward edges; 0
   dual-accelerator validation gates; 0 accelerator re-runs in an aggregation
   phase). A non-zero count blocks closure.
6. Run `jitml check-code` inside `jitml:local` before closing the work (once Phase
   1 lands the command; until then, run `fourmolu --mode check`, `hlint`, and
   `cabal format` manually inside the container).
7. If the change touched Mermaid, render every Mermaid block in `DEVELOPMENT_PLAN/`
   and verify the edited diagram in the target viewer before closing the work.
