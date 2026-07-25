# Phase 222: Status Truth Enforcement

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Status Truth Enforcement. Single-session phase migrated from legacy Sprint 19.3 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 222.1: Status Truth Enforcement [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Lint/Docs.hs`, `src/JitML/Docs/Check.hs`, `test/unit/Main.hs`
**Docs to update**: `README.md`, `00-overview.md`, `system-components.md`, `../documents/engineering/unit_testing_policy.md`

### Objective

Governed documentation cannot claim product closure while any product phase is
unfinished. `src/JitML/Lint/Docs.hs` scans governed docs for closure language and
`src/JitML/Docs/Check.hs` rejects it through `jitml docs check` unless the typed
`PhaseStatus` registry reports every product phase (Phases `19`–`34`) Done.

### Deliverables

- `jitml docs check` scans governed docs for closure claims — for example "all
  phases done", "no-caveat product complete", and "production ready" — and
  rejects them unless `allProductPhasesDone` is true for Phases `19`–`34`.
- Dated historical-evidence blocks that explicitly describe themselves as
  historical are exempt from the closure-claim rejection.
- A unit test asserts the scanner flags closure language while a product phase is
  Active or Blocked and passes only when the registry reports full closure.

### Validation

```bash
docker compose build jitml                                      # passed, image built with embedded check-code: ok
docker compose run --rm jitml jitml docs check                  # passed
docker compose run --rm jitml jitml test jitml-unit --linux-cpu # passed, 246/246 tests
docker compose run --rm jitml jitml check-code                  # passed
```

### Closure Evidence

- **Closed obligation (reopened 2026-07-05):** the closure guard is
  non-falsifiable. `src/JitML/Docs/Check.hs` rejects a closure claim only when
  the hand-edited `src/JitML/Product/PhaseStatus.hs` registry reports an
  unfinished phase, so status is trusted from a literal rather than proven from
  evidence — an agent can flip the registry to satisfy the guard without any
  model actually converging. The guard must instead derive
  `allProductPhasesDone` from machine-checkable evidence.
- **Closed by:** Phase `34` (`phase-34-plan-truth-governance.md`, Sprint `34.1`)
  extends the typed guard through Phases `32`–`34` and keeps closure language tied
  to the standing realness gate. The product phase-status parity test now parses
  every governed product phase document, `jitml docs check` gates closure claims
  on the full Phase `19`–`34` predicate, and the required validation includes
  `jitml-negative-controls` plus `jitml-model-convergence`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
