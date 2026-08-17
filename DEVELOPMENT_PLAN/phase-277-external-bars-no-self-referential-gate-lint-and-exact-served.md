# Phase 277: External Bars, No-Self-Referential-Gate Lint, and Exact Served-Byte Provenance

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: External Bars, No-Self-Referential-Gate Lint, and Exact Served-Byte Provenance. Single-session phase migrated from legacy Sprint 32.2 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

⏸️ **Blocked**. Blocked by Phase 275 (Sprint 275.1).

## Sprint 277.1: External Bars, No-Self-Referential-Gate Lint, and Exact Served-Byte Provenance [⏸️ Blocked]

**Status**: Blocked
**Implementation**: `src/JitML/Product/ExternalBars.hs`, `src/JitML/Lint/ProductTruth.hs`, `src/JitML/Checkpoint/Format.hs`, `test/unit/Main.hs`
**Blocked by**: Sprint `275.1`
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

- Blocked until Sprint `275.1` produces the versioned aggregate evidence bound to
  Sprint `133.1`'s opaque admitted artifact.
- Recompute the external-bar measurement from the exact admitted manifest and
  served weight bytes, then add substitution controls that retain matching
  metadata while changing either byte object.
- **Restore the self-reference check this sprint owns.**
  [Exit Definition](README.md#exit-definition) item `26` requires that no
  threshold be a function of the value it checks, and
  `src/JitML/Product/ExternalBars.hs` still promises exactly that in its module
  comment. The predicate no longer implements it:
  `barIsSelfReferential bar _measuredValue = convergenceSlack bar <= 0.0`
  discards the measured value, so a positive-slack bar set equal to the measured
  value passes. Only the slack-positivity half of item `26` is enforced today.
- **Make the frozen-bar membership check cohort-specific.**
  `frozenRlRewardThresholds` is a flat list of every cohort's
  `literatureTarget - slack`, and the assertion is list membership, so an
  observation carrying a *different* cohort's anchor is accepted as externally
  anchored.
- **Retire the vacuous bars.** Three rows are unfalsifiable or near it against
  their own environments: `PPO/key-door-grid` and `A2C/key-door-grid` carry bars
  of `-2.8` and `-3.3` on an environment whose success reward is `1.0`, so a
  policy scoring below zero "converges"; `TRPO/cartpole` carries a bar of `185`
  against literature target `475`. Positive slack alone does not make a bar
  external, which is the same defect class item `26` was written to prevent.
- **State the bars' real provenance in code.** The `literatureTarget` values are
  external constants, but `slack` is project-calibrated —
  `src/JitML/RL/ConvergenceThresholds.hs` says so itself ("Some rows use wider
  slack where the deterministic jitML implementation is materially weaker than
  the external reference"). The governed docs are corrected to match; the
  in-code assertion that these are "fixed product bars" should follow.
- **Fix the module's broken references.** `ExternalBars.hs` links resolve one
  directory too high, and it cites
  `DEVELOPMENT_PLAN/phase-32-external-truth-realness-harness.md`, which no
  longer exists — the 2026-07-24 renumber renamed it to this document.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
