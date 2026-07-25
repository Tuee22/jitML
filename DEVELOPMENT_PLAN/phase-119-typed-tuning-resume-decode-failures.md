# Phase 119: Typed Tuning Resume Decode Failures

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Typed Tuning Resume Decode Failures. Single-session phase migrated from legacy Sprint 9.15 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 119.1: Typed Tuning Resume Decode Failures [✅ Done]

**Status**: Done (reopened 2026-06-29; re-closed 2026-06-30)
**Implementation**: `src/JitML/Tune/Resume.hs`, `src/JitML/Tune/Catalog.hs`,
`test/hyperparameter/Main.hs`, `test/integration/Main.hs`
**Docs to update**: `documents/engineering/training_workloads.md`,
`documents/engineering/haskell_code_guide.md`,
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`, `system-components.md`

### Objective

Make tuning resume/replay audit data total. A missing transcript remains a
service read failure; a corrupt transcript is a decode failure with a concrete
message, not a bottom hidden inside `resumeReadFailures`.

### Deliverables

- Introduce a resume-read failure type that distinguishes `ServiceError` from
  transcript decode failure.
- Make `ResumeOutcome` `Show` / `Eq` total even when one or more transcripts are
  corrupt.
- Ensure callers can decide whether to abort or rerun a corrupt trial from the
  structured failure data.
- Add tests that write invalid transcript bytes and assert a typed decode
  failure.

### Validation

- `docker compose run --rm jitml jitml test jitml-hyperparameter --linux-cpu`
  passed **17 / 17**.
- `docker compose run --rm jitml jitml bootstrap --linux-cpu` reconciled the
  live cluster in **105 steps** after a fresh `jitml` image build
  (`sha256:918cab6b7d7e703716404f04b7ac4d0acda97e2feeed230a8636db0a802da445`).
- `docker compose run --rm jitml jitml test jitml-integration --linux-cpu`
  passed **77 / 77**, including **19 / 19** `Live` cases and the corrupt
  transcript decode-failure regression.
- `docker compose run --rm jitml jitml check-code` passed (`check-code: ok`).

### Remaining Work

- None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
