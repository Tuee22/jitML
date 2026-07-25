# Phase 272: External Bars, No-Self-Referential-Gate Lint, and Exact Served-Byte Provenance

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: External Bars, No-Self-Referential-Gate Lint, and Exact Served-Byte Provenance. Single-session phase migrated from legacy Sprint 32.2 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

⏸️ **Blocked**. Blocked by Phase 270 (Sprint 270.1).

## Sprint 272.1: External Bars, No-Self-Referential-Gate Lint, and Exact Served-Byte Provenance [⏸️ Blocked]

**Status**: Blocked
**Implementation**: `src/JitML/Product/ExternalBars.hs`, `src/JitML/Lint/ProductTruth.hs`, `src/JitML/Checkpoint/Format.hs`, `test/unit/Main.hs`
**Blocked by**: Sprint `270.1`
**Docs to update**: `../documents/engineering/product_completion_contract.md`, `../documents/engineering/determinism_contract.md`, `system-components.md`

### Objective

Convergence bars are frozen external literature constants and a lint bans any
threshold derived from the value it checks. Persisted artifact binding is
implemented by Sprints `127.1`/`133.1`; this sprint owns the independent
external-truth predicates used to grade that boundary and, after aggregation,
the proof that a reported measurement was recomputed from the exact admitted
bytes subsequently served.

### Deliverables

- `src/JitML/Product/ExternalBars.hs` holds the literature convergence targets,
  dataset SHAs, and arena baselines as immutable constants with a "do not derive from
  measurements" invariant.
- A lint (`ProductTruth.hs`) statically rejects the `mkConvergenceBar … measuredValue 0.0`
  / `threshold = measured` pattern anywhere on a product path.
- The external-bar predicate re-derives `coPassed` from finite measurements
  rather than trusting a stored boolean. Current served-weight, manifest, blob,
  and dataset binding is not minted here; Sprint `133.1` exposes only an opaque
  admitted artifact for this harness to challenge.
- Bind the aggregated ProductRow claim to that opaque admitted manifest address
  and its exact served `supervised.weights` bytes, recompute the reported metric
  through the admitted runtime, and reject metadata-consistent byte
  substitution.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Historical Closure Evidence

- Implemented the module and lint and exercised the former decode-time check.
  That old re-encoded-manifest/served-weight assertion is historical and does
  not close exact V2 persistence or admission; the retained closure here is the
  external-bar and no-self-reference grader.

### Remaining Work

- Blocked until Sprint `270.1` produces the versioned aggregate evidence bound to
  Sprint `133.1`'s opaque admitted artifact.
- Recompute the external-bar measurement from the exact admitted manifest and
  served weight bytes, then add substitution controls that retain matching
  metadata while changing either byte object.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
