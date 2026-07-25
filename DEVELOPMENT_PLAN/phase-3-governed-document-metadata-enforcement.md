# Phase 3: Governed-Document Metadata Enforcement

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Governed-Document Metadata Enforcement. Single-session phase migrated from legacy Sprint 0.3 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 3.1: Governed-Document Metadata Enforcement [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Docs/Check.hs`, `src/JitML/Lint/Stack.hs`,
`DEVELOPMENT_PLAN/attestations/*.md`,
`documents/documentation_standards.md`
**Docs to update**: `README.md`, `DEVELOPMENT_PLAN/README.md`,
`DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`,
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`,
`documents/engineering/code_quality.md`

### Objective

Make the documentation metadata contract executable instead of aspirational.
Owns the project-doctrine `Generated Artifacts` and documentation-standard
surfaces for governed Markdown files.

### Deliverables

- `jitml docs check` validates the required governed-document header fields:
  `Status`, `Supersedes`, `Referenced by`, `Generated sections`, and `Purpose`.
- The `Generated sections` metadata must agree with physical generated-region
  markers and with the `GeneratedSectionRule` registry.
- The three per-lane attestation documents carry `**Supersedes**: N/A`, matching
  [../documents/documentation_standards.md](../documents/documentation_standards.md).
- Documentation status lives in `DEVELOPMENT_PLAN/README.md`; engineering docs
  explain architecture and link back instead of maintaining a competing status
  ledger.

### Validation

- `docker compose run --rm jitml jitml docs check`
- `docker compose run --rm jitml jitml lint docs`
- `docker compose run --rm jitml jitml check-code`

### Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
