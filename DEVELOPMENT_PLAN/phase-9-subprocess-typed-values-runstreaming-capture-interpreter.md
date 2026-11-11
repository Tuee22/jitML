# Phase 9: `Subprocess` Typed Values, `runStreaming` / `capture` Interpreter

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Subprocess Typed Values, runStreaming / capture Interpreter. Originally migrated from legacy Sprint 1.6 in the 2026-07-24 phase renumber; see the old→new map in [README.md](README.md).

## Phase State

⏸️ **Blocked** for the expanded validation foundation in Sprint `9.2`.
The earlier Sprint `9.1` record below is retained on its original source and
scope; it does not validate this target or a current hardware lane. The execution
order and transition authority are [the validation-foundation refactor](README.md#validation-foundation-refactor).

The new source/catalogue, runner and hardware controls remain unimplemented.
Sprint `221.2` owns reconciliation of the existing checker with these documented
targets; this documentation-only change supplies no machine-validation receipt.

## Sprint 9.2: Bounded owned process families and capture [⏸️ Blocked]

**Status**: Blocked
**Implementation**: Target changes to `src/JitML/Sub/Subprocess.hs`, `src/JitML/Sub/Stream.hs`, `src/JitML/Sub/Outcome.hs`.
**Blocked by**: Sprint `221.2`.
**Docs to update**: `../documents/engineering/execution_resources.md`, `../documents/engineering/validation_execution.md`, `../documents/engineering/run_contract.md`, `../documents/engineering/haskell_code_guide.md`, `README.md`, `system-components.md`, `legacy-tracking-for-deletion.md`.

### Objective

Every supported subprocess launch has explicit process-family ownership, bounded input/output and cancellation, while observation can disconnect without becoming execution authority.

The target contracts are [execution resources](../documents/engineering/execution_resources.md)
and [validation execution](../documents/engineering/validation_execution.md).
Their acceptance requirements below are planned work, not implemented behavior.

### Deliverables

- Extend the typed subprocess boundary with validated ownership and resource/capture policy. Preserve secret environment separation and actual executable identity; shell text and a reused PID do not prove ownership.
- Launch capture and cancellation through one maintained implementation. Cancel descendants as well as the original child, and never signal unrelated processes by image name.
- Write bounded streams to ignored disk-backed artifact homes with explicit overflow outcomes. A truncated tail, missing stream, or blocked reader cannot be rendered as a complete successful transcript.
- Keep operational process limits distinct from numerical training budgets and PlanIds; observe the actual launched limits before numerical work is admitted.

### Validation

1. Run real finite children that exit zero/nonzero, remain silent, flood both streams, create a descendant, exit during observation, and ignore TERM. Verify exact terminal status, bounded capture and KILL escalation.
2. Disconnect the observing client while an owned fixture continues; reconnect and retrieve the same child identity and result. Test wrong identity and stale PID refusal.
3. Exercise reader failure and disk/output exhaustion using small configured bounds; retain the primary child failure and stop result without exhausting the host.

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

- Implement the owned-family/capture contracts and register individually selectable non-training fixtures.
- Prove real child cleanup and observer independence before `160.2` uses this boundary for campaigns.

## Retained Historical Scope

The following state, commands, measurements and closure statements describe the
original Sprint `9.1` surface only. New execution rules and acceptance
above supersede any conflicting operational instruction; old receipts are not
reinterpreted as current readiness.

### Historical Phase State

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

- `../documents/engineering/execution_resources.md`.
- `../documents/engineering/validation_execution.md`.
- `../documents/engineering/run_contract.md`.
- `../documents/engineering/haskell_code_guide.md`.

**Product docs to create/update:**

- [Development-plan entry](README.md#validation-foundation-refactor), [component inventory](system-components.md), and [deletion ledger](legacy-tracking-for-deletion.md).

**Cross-references to add:**

- Link the target contracts, exact sprint dependencies and evidence pointers together when source implementation lands; update root summaries only in an authorized root-file change.
