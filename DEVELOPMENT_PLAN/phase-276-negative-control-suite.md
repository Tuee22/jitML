# Phase 276: Negative-Control Suite

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Negative-Control Suite. Single-session phase migrated from legacy Sprint 32.1 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 276.1: Negative-Control Suite [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Test/NegativeControls.hs`, `test/negative-controls/Main.hs`, `jitml.cabal`
**Docs to update**: `../documents/engineering/unit_testing_policy.md`, `../documents/engineering/product_completion_contract.md`, `system-components.md`

### Objective

A committed set of known-fake artifacts, each paired with the gate that must reject
it. The `jitml-negative-controls` stanza (wired into `jitml test all`) fails the
build if any known-fake is accepted.

### Deliverables

- Known-fake fixtures and their required verdict: an untrained random-init checkpoint
  (must fail `InferenceEligible`); a below-threshold trained model (must fail the
  convergence bar); an RL reward trace produced by a scripted controller (must fail RL
  row evidence); a dense layer labelled as convolution (must fail the differential
  conv≠dense assertion).
- The stanza asserts each gate returns *reject* for its known-fake; a gate that cannot
  reject its known-fake is a failure, not a pass.
- The suite is enumerated from the `ProductRow` registry so a new row cannot ship
  without its negative control.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-negative-controls --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Closure Evidence

- Implemented `NegativeControls.hs` and the stanza; the committed known-fakes are rejected by the standing gate; `docker compose run --rm jitml env JITML_SUBSTRATE=linux-cpu cabal test jitml-negative-controls --test-options='--hide-successes --color=never'` passed 3/3 on 2026-07-06.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
