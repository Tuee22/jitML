# Phase 21: Structured Subprocess Outcomes

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Structured Subprocess Outcomes. Originally migrated from legacy Sprint 1.18 in the 2026-07-24 phase renumber; see the old→new map in [README.md](README.md).

## Current execution ownership

**Historical record; no current execution gate.** Phases 1–289 retain their
original contracts, statuses and receipts below. Their former order, dependencies
and current-sounding statements are historical. They do not gate the new
[numerical execution sequence](ordered-execution-plan.md). No historical failure
is erased and no historical Done is promoted to current qualification.

Unfinished scope is **transferred, not completed**:

- Former sprint `21.2` → [294](phase-294-terminal-outcomes.md), [318](phase-318-cuda-runtime-engineering.md), [319](phase-319-apple-runtime-engineering.md).

The [transfer register](ordered-plan-transfers.md) assigns implementation and
real-input acceptance separately. The complete retained contract is inherited;
examples or wrappers do not replace its detailed unmet requirements.

## Historical plan and evidence

## Phase State

⏸️ **Blocked** for the expanded validation foundation in Sprint `21.2`.
The earlier Sprint `21.1` record below is retained on its original source and
scope; it does not validate this target or a current hardware lane. The execution
order and transition authority are [the validation-foundation refactor](README.md#validation-foundation-refactor).

The new source/catalogue, runner and hardware controls remain unimplemented.
Sprint `221.2` owns reconciliation of the existing checker with these documented
targets; this documentation-only change supplies no machine-validation receipt.

## Sprint 21.2: Durable failure observations and terminal outcomes [⏸️ Blocked]

**Status**: Blocked
**Implementation**: Target changes to `src/JitML/Sub/Outcome.hs`, `src/JitML/Sub/Stream.hs`, `src/JitML/AppError/Render.hs`.
**Blocked by**: Sprint `221.2`.
**Docs to update**: `../documents/engineering/execution_resources.md`, `../documents/engineering/validation_execution.md`, `../documents/engineering/run_contract.md`, `README.md`, `system-components.md`, `legacy-tracking-for-deletion.md`.

### Objective

Process and safety outcomes preserve the actual failed observation, terminal status and cleanup result across disconnects without converting missing evidence into success.

The target contracts are [execution resources](../documents/engineering/execution_resources.md)
and [validation execution](../documents/engineering/validation_execution.md).
Their acceptance requirements below are planned work, not implemented behavior.

### Deliverables

- Distinguish completed success, scientific refusal, operational timeout, resource refusal, incomplete measurement, capture failure, cancellation, and unobserved termination through typed outcomes.
- Preserve the triggering observation when available, both bounded output streams, invocation identity and timing. A last passing sample is never substituted for the failed sample.
- Keep body failure primary and retain diagnostic, capture, preservation and cleanup failures as additional facts. A shell pipeline must not replace the owned child exit with the formatter exit.
- Atomically publish durable terminal receipts with explicit completeness and recovery semantics; a partial or unreadable receipt cannot mint completion.

### Validation

1. Test signal exits, failed reads, missing/truncated streams, delayed results and interruption during receipt write. Reopening a partial record fails closed.
2. Exercise simultaneous body/diagnostic/cleanup failures and confirm the body result remains primary while every secondary failure and stop result survives.
3. Use a deliberately failing child behind a rendering stage and prove the actual child failure remains observable.

Closure requires the owned targeted/hermetic controls listed above, with a
nonempty independently enumerated test inventory and exact scoped transcripts.
The implementation publishes actual selectable groups in the existing stanzas
and uses the supported `--test-options` passthrough; no invented selector or
unfiltered full-matrix acquisition is an acceptable substitute. A scoped result
is recorded as scoped, never as a passing full stanza. Resource/live controls
also require the actual owned runtime observations named above.

Complete evidence-dependent unit/integration/negative-control transcripts belong
to Sprints `277.2` and `280.2`; cross-family convergence belongs to `283.2` and
`285.2`. Those downstream records are not prerequisites for this foundation or
readiness closure. Every original case remains registered with an explicit owner.
The existing documentation/code-quality commands below run after source parity
is implemented, inside the admitted profile; they do not execute these controls.

```bash
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml docs check
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml check-code
```

Cluster-running jobs use the separately admitted cluster/lifecycle overlays
instead of the stopped-cluster build profile. A real hardware lane is never
claimed by CPU fixtures; absent required runtime capability fails that lane.

### Remaining Work

- Implement and register the outcome variants and durable receipt boundary with finite fixture controls.
- Propagate the result through process, safety, lifecycle and campaign callers without reconstructing missing original outcomes.

## Retained Historical Scope

The following state, commands, measurements and closure statements describe the
original Sprint `21.1` surface only. New execution rules and acceptance
above supersede any conflicting operational instruction; old receipts are not
reinterpreted as current readiness.

### Historical Phase State

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

- `../documents/engineering/execution_resources.md`.
- `../documents/engineering/validation_execution.md`.
- `../documents/engineering/run_contract.md`.

**Product docs to create/update:**

- [Development-plan entry](README.md#validation-foundation-refactor), [component inventory](system-components.md), and [deletion ledger](legacy-tracking-for-deletion.md).

**Cross-references to add:**

- Link the target contracts, exact sprint dependencies and evidence pointers together when source implementation lands; update root summaries only in an authorized root-file change.
