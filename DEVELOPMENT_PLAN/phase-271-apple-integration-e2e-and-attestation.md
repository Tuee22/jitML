# Phase 271: Apple Integration, E2E, and Attestation

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Apple Integration, E2E, and Attestation. Single-session phase migrated from legacy Sprint 30.3 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

⏸️ **Blocked** (reopened 2026-08-16 under standards rule `C`). This phase attests
that `jitml test all --apple-silicon` runs every Apple-supported product row for
real. It does not: supervised rows on this lane execute the `linux-cpu` oneDNN
layer-training artifact, which is the same defect that reopened Phases `269` and
`270` on 2026-08-12 and which the audit did not carry through to this phase.
Sprint `264.1` makes it visible rather than silent — `layerTrainingBackendFor`
now fails closed on `apple-silicon` naming Sprint `269.1` instead of executing
another lane's kernels and attributing the run to Apple hardware. The 2026-07-06
evidence remains historical evidence for the surface it exercised.

## Sprint 271.1: Apple Integration, E2E, and Attestation [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Sprints `269.1`, `270.1`
**Implementation**: `test/integration/Main.hs`, `test/e2e/Main.hs`, `playwright/jitml-demo.spec.ts`, `DEVELOPMENT_PLAN/attestations/`
**Docs to update**: `../documents/engineering/unit_testing_policy.md`, `../documents/engineering/purescript_frontend.md`

### Objective

`jitml test all --apple-silicon` runs every Apple-supported product row for real
on the Mac host, live Playwright hits the Apple edge and renders row-specific
trained artifacts, and the committed `apple-silicon` attestation records the
row-complete evidence for the lane.

### Deliverables

- `jitml test all --apple-silicon` runs every Apple-supported product row for real
  on the Mac host: real training/RL/tune/inference through host-daemon routing
  that fails closed if the host daemon or Metal runtime is absent.
- Live Playwright (`playwright/jitml-demo.spec.ts`) hits the Apple edge and
  renders row-specific trained artifacts, never a fake browser runtime or static
  generated row-name list.
- The `apple-silicon` report card includes row ids, Metal device evidence,
  integration evidence, and e2e evidence, distinguishing unsupported rows from
  failed supported rows.
- The refreshed `apple-silicon` attestation is committed under
  `DEVELOPMENT_PLAN/attestations/` for the aggregation phase to consume.

### Validation

```bash
./bootstrap/apple-silicon.sh doctor
PATH=/opt/homebrew/opt/llvm@19/bin:$PATH cabal test jitml-backends --test-show-details=direct --test-options='-p apple-silicon'
PATH=/opt/homebrew/opt/llvm@19/bin:$PATH cabal test jitml-e2e --test-show-details=direct
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

2026-07-06 closing validation: the refreshed Apple backend evidence validates the
fixed-bridge Metal kernel surface that underlies the committed
`apple-silicon` fragment. The Phase `30` lane is closed on its Apple-host
obligations, and Phase `31` now consumes this committed fragment alongside the
fresh `linux-cuda` and `linux-cpu` fragments.

### Closure Evidence

- **Closed Exit-Definition obligation**: `jitml test all --apple-silicon` must run
  every Apple-supported product row for real — real training/RL/tune/inference
  through host-daemon routing, live Playwright rendering of row-specific trained
  artifacts, and a refreshed 55 / 55 `apple-silicon` attestation whose per-row
  evidence is real — only after Phases `19`–`28` close the underlying model realness
  and Sprints `30.1`–`30.2` land real Metal kernels and real device evidence.
- **Closing validation**: once the `jitml-negative-controls` stanza (Phase `32`,
  [phase-32-external-truth-realness-harness.md](README.md#legacy-to-new-phase-map))
  and the per-model `jitml-model-convergence` suite (Phase `33`,
  [phase-33-per-model-convergence-and-inference-tests.md](README.md#legacy-to-new-phase-map)),
  governed by Phase `34`
  ([phase-34-plan-truth-governance.md](README.md#legacy-to-new-phase-map)), pass on
  `linux-cpu`, re-run `jitml test all --apple-silicon` and re-commit the refreshed
  attestation for Phase `31` aggregation — `apple-silicon` plus `linux-cpu` only,
  never `linux-cuda` in the same gate.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
