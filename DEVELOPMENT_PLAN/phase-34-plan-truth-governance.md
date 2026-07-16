# Phase 34: Plan-Truth Governance

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [development_plan_standards.md](development_plan_standards.md), [phase-32-external-truth-realness-harness.md](phase-32-external-truth-realness-harness.md), [phase-33-per-model-convergence-and-inference-tests.md](phase-33-per-model-convergence-and-inference-tests.md), [../README.md](../README.md), [../documents/documentation_standards.md](../documents/documentation_standards.md)
**Generated sections**: none

> **Purpose**: Make this the last truth reset. Replace the self-authored,
> per-commit closure narrative with evidence-derived status, a standing external
> audit gate, and a thinned plan, so status can no longer drift from reality.

## Phase State

⏸️ **Blocked** (reopened 2026-07-12 for Sprint `34.3`). Phase and suite
status still depend on a hand-maintained registry, post-run probes, and report
projections rather than the structured process and scenario journals that
produced the evidence. Sprint `34.3` is blocked by Sprint `33.3`. Sprints
`34.1`–`34.2` remain Done on their retained governance surface.

**Historical retained closure.** ✅ **Done**. The git history shows the closure narrative was rewritten in 95 of
109 commits while faking recurred — effort flowed into *asserting* done, not
*achieving* it. This phase changes what "Done" is graded against and who grades it, so
the cycle cannot repeat. It depends on Phases `32`–`33` (the evidence they produce is
what status now derives from).

**Validation substrate**: `linux-cpu` only.

## Objective

`jitml docs check`'s closure guard recomputes phase/sprint status from
machine-checkable evidence rather than a hand-edited `PhaseStatus.hs`. A recurring
adversarial realness audit, run by a process that does not own turning phases green,
is a required gate whose findings define status. The plan's `Closure Status` is a thin
pointer to that evidence, not a per-commit narrative. This closes Exit-Definition items
`27`–`28`.

## Sprint 34.1: Evidence-Derived Closure Guard [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Docs/Check.hs`, `src/JitML/Lint/Docs.hs`, `src/JitML/Product/PhaseStatus.hs`, `test/unit/Main.hs`
**Docs to update**: `development_plan_standards.md`, `../documents/documentation_standards.md`, `system-components.md`

### Objective

The docs-check closure guard derives phase status from evidence (negative-control pass,
per-model convergence pass, empty ledger) instead of trusting a hand-edited registry.

### Deliverables

- `allProductPhasesDone` is computed from the `jitml-negative-controls` and
  `jitml-model-convergence` results and the ledger state, not a literal in
  `PhaseStatus.hs`; a hand edit to the registry that contradicts the evidence fails the
  build (this closes the Sprint `19.3` non-falsifiability gap reopened by the audit).
- The closure-claim scanner additionally rejects any `Real`-tagged row whose negative
  control is not green.

### Validation

```bash
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml check-code
```

### Closure Evidence

- Implemented the evidence-derived guard.

## Sprint 34.2: Standing Adversarial Audit & Thin Plan [✅ Done]

**Status**: Done
**Implementation**: `DEVELOPMENT_PLAN/README.md`, `../documents/documentation_standards.md`, `development_plan_standards.md`
**Docs to update**: `README.md`, `00-overview.md`, `development_plan_standards.md`, `../documents/documentation_standards.md`

### Objective

A recurring adversarial realness audit is a required gate; the plan's `Closure Status`
becomes a thin pointer to evidence.

### Deliverables

- `development_plan_standards.md` adds a rule (N) requiring a periodic adversarial
  realness audit — authored/run by a process that does not own turning phases green —
  whose findings define status, and forbidding closure-narrative growth: `Closure
  Status` links to the machine-checkable evidence and does not accrete per-commit
  prose.
- The historical closure narrative is archived out of `README.md → Closure Status`
  into a dated appendix so the live status is short.

### Validation

```bash
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Closure Evidence

- Added rule N; archived the historical narrative; thinned `Closure Status`.

## Sprint 34.3: Journal-Derived Status and Reporting [⏸️ Blocked]

**Status**: Blocked
**Implementation**: `src/JitML/Product/PhaseStatus.hs`,
`src/JitML/Docs/Check.hs`, `src/JitML/Lint/Docs.hs`,
`src/JitML/Test/Report.hs`, `test/unit/Main.hs`
**Blocked by**: Sprint `33.3`
**Docs to update**: `../README.md`, `README.md`, `00-overview.md`,
`development_plan_standards.md`, `../documents/documentation_standards.md`,
`../documents/engineering/unit_testing_policy.md`,
`../documents/engineering/run_contract.md`, `system-components.md`,
`legacy-tracking-for-deletion.md`

### Objective

Derive suite, lane, phase, and product status from the structured process and
scenario journals that produced the evidence. This sprint owns the remaining
[Exit Definition](README.md#exit-definition) items `33` and `34`.
The binding design is
[README.md → Typed run contracts](../README.md#typed-run-contracts).

### Deliverables

- Replace the hand-maintained provisional phase/sprint registry with a projection
  over versioned validation evidence and explicit unmet/blocked obligations.
- Represent report measurements as
  `NotRequested | Unavailable reason | Available evidence`; remove overlapping
  `Maybe` fields and unavailable sentinels.
- Derive suite counts from `Passed | Failed | NotRun` invocation results and
  lane/product counts from validated scenario journals.
- Remove post-test probes that manufacture a second measurement path; reports
  are projections of execution evidence already captured by the interpreter.
- Make closure claims fail whenever required journals are missing, stale,
  mismatched, failed, or incomplete, even if prose/status literals say Done.
- Keep the live `Closure Status` narrative thin and point it to the derived
  evidence and outstanding sprint chain.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml test jitml-negative-controls --linux-cpu
docker compose run --rm jitml jitml test jitml-model-convergence --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Remaining Work

- Blocked until Sprint `33.3` emits contract-derived per-model evidence for the
  standing status gate.
- Replace the literal status registry, ambiguous measurements, post-run probes,
  and fabricated counts with journal projections.
- Re-run the complete standing evidence gate before restoring any product
  closure claim.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/run_contract.md` — journal-derived suite, lane, and
  phase status projection.
- `documents/documentation_standards.md` — the evidence-derived status discipline and
  the thin-plan rule.

**Product docs to create/update:**
- `README.md` — `Current product status` becomes a thin pointer to the plan's
  evidence-derived `Closure Status`.

**Cross-references to add:**
- Add this phase to `README.md`, `00-overview.md`, `system-components.md`, and
  `development_plan_standards.md §E`.
