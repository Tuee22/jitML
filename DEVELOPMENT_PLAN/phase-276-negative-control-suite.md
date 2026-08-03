# Phase 276: Negative-Control Suite

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Negative-Control Suite. Single-session phase migrated from legacy Sprint 32.1 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done** for the retained pure gate-soundness scope. Production-path
request/event, journal/reducer, lifecycle, and mandatory per-row controls were
transferred to Phases `279`–`281`; this phase does not claim those later gates.

## Sprint 276.1: Negative-Control Suite [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Test/NegativeControls.hs`, `test/negative-controls/Main.hs`, `jitml.cabal`
**Docs to update**: `../documents/engineering/unit_testing_policy.md`, `../documents/engineering/product_completion_contract.md`, `system-components.md`

### Objective

A committed set of hand-built known-fake records, each paired with the pure gate
that must reject it. The `jitml-negative-controls` stanza (wired into
`jitml test all`) fails the build if any retained gate-soundness fake is
accepted and separately requires the transferred production-path work to remain
explicitly enumerated.

### Deliverables

- Retain pure known-fake records for untrained learned state, self-referential or
  below-threshold convergence, synthetic RL evidence, invalid supervised
  evidence, collapsed operators, and algorithm-specific gate violations.
- Assert each pure gate returns *reject* for its known-fake; a gate that cannot
  reject its known-fake is a failure, not a pass.
- Keep the outstanding production-path categories non-empty and explicit.
  Phases `279`–`281` own invalid request/event fixtures, journal/reducer
  properties, lifecycle failures, and mandatory per-ProductRow registration.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-negative-controls --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Closure Evidence

- Implemented `NegativeControls.hs` and the retained pure gate-soundness stanza;
  the committed known-fakes were rejected and the transferred production-path
  work remained explicitly non-empty. `docker compose run --rm jitml env
  JITML_SUBSTRATE=linux-cpu cabal test jitml-negative-controls
  --test-options='--hide-successes --color=never'` passed **3 / 3** on
  2026-07-06. This evidence does not satisfy Phases `279`–`281`.

## Documentation Requirements

**Engineering docs to create/update:**

- `../documents/engineering/unit_testing_policy.md`
- `../documents/engineering/product_completion_contract.md`

**Product docs to create/update:**

- `system-components.md`

**Cross-references to add:**

- Link the retained pure gate-soundness scope to the production-path controls
  owned by [Phase 279](phase-279-runcontract-negative-controls-request-and-event-fixtures.md),
  [Phase 280](phase-280-runcontract-negative-controls-journal-fixtures-and-reducer-p.md),
  and [Phase 281](phase-281-runcontract-negative-controls-lifecycle-and-per-row-registra.md).
