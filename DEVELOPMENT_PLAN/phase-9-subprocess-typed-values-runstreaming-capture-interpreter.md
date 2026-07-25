# Phase 9: `Subprocess` Typed Values, `runStreaming` / `capture` Interpreter

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Subprocess Typed Values, runStreaming / capture Interpreter. Single-session phase migrated from legacy Sprint 1.6 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 9.1: `Subprocess` Typed Values, `runStreaming` / `capture` Interpreter [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Sub/Subprocess.hs`, `src/JitML/Sub/Outcome.hs`,
`src/JitML/Sub/Stream.hs`, `src/JitML/Sub/Render.hs`
**Docs to update**: `documents/engineering/haskell_code_guide.md`

### Objective

Make `Subprocess` the only IO boundary for subprocess execution per doctrine
`Architecture → Subprocesses as Typed Values`. `kubectl`, `helm`, `kind`,
`docker`, `tart`, and the per-substrate kernel compilers all flow through it in
later phases.

### Deliverables

- `Subprocess` record in `src/JitML/Sub/Subprocess.hs` carrying
  `subprocessPath`, `subprocessArguments`, `subprocessWorkingDirectory`, and
  optional stdin payload. It deliberately does not carry process-environment
  overrides; command configuration is explicit in arguments, working directory,
  stdin, Dhall, or typed config.
- `renderSubprocess :: Subprocess -> Text` is pure and used by the Plan
  renderer and the structured logger.
- `runStreaming :: SubprocessEnv -> Subprocess -> IO ProcessOutcome` and
  `capture :: SubprocessEnv -> Subprocess -> IO ProcessOutcome` are the only IO
  interpreters. `ProcessOutcome` is defined in `JitML.Sub.Outcome` and retains a
  complete transcript for both success and failure.
- The Sprint `1.4` in-repo primitive scan refuses `callProcess`,
  `readCreateProcess`, `System.Process.*`, and `typed-process` smart
  constructors outside this module.

### Validation

1. `jitml lint haskell` reports zero violations of the forbidden subprocess
   primitives across `src/`.
2. `jitml-unit` exercises `renderSubprocess` snapshot tests for the Plan renderer.
3. `jitml-integration` exercises `runStreaming` against a fixture binary and
   asserts the typed `ProcessSucceeded ProcessTranscript` /
   `ProcessFailed ProcessFailure` shape.

### Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
