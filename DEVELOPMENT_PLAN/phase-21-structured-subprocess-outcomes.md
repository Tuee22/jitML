# Phase 21: Structured Subprocess Outcomes

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Structured Subprocess Outcomes. Single-session phase migrated from legacy Sprint 1.18 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 21.1: Structured Subprocess Outcomes [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Sub/Outcome.hs`, `src/JitML/Sub/Stream.hs`,
`src/JitML/Sub/Subprocess.hs`, `src/JitML/AppError/AppError.hs`,
`src/JitML/AppError/Render.hs`, `src/JitML/App.hs`, `test/unit/Main.hs`,
`test/integration/Main.hs`, `test/e2e/Main.hs`
**Docs to update**: `../README.md`,
`../documents/engineering/haskell_code_guide.md`,
`../documents/engineering/run_contract.md`, `system-components.md`,
`legacy-tracking-for-deletion.md`

### Objective

Make subprocess success and failure mutually exclusive typed values, and retain
the complete process transcript at every failure boundary. This sprint owns the
subprocess portion of [Exit Definition](README.md#exit-definition) item `33` and
implements `Subprocesses as Typed Values` without exposing raw result tuples to
callers.

### Deliverables

- Replace `(ExitCode, stdout, stderr)` results with a closed
  `ProcessSucceeded ProcessTranscript | ProcessFailed ProcessFailure` sum.
- Make `ProcessFailure` constructible only from a non-zero exit and retain the
  rendered command, stdout, stderr, working directory, and elapsed duration.
- Thread the structured result through Cabal, Playwright, bootstrap, lint, and
  other subprocess callers so no caller can silently discard stdout on failure.
- Refine `AppError` to carry the structured failure rather than an independently
  constructible exit code and stderr fragment.
- Add unit and property tests for success/failure exclusivity, transcript
  preservation, rendering, and non-zero failure construction.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-unit --linux-cpu  # passed, 284 / 284
docker compose run --rm jitml jitml docs check                  # exit 0
docker compose run --rm jitml jitml check-code                  # exit 0
```

### Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
