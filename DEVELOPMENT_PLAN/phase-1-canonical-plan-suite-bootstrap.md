# Phase 1: Canonical Plan Suite Bootstrap

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Canonical Plan Suite Bootstrap. Single-session phase migrated from legacy Sprint 0.1 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 1.1: Canonical Plan Suite Bootstrap [✅ Done]

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
  live workflow matrix.
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

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
