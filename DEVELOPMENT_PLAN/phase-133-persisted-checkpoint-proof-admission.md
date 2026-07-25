# Phase 133: Persisted Checkpoint Proof Admission

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Persisted Checkpoint Proof Admission. Single-session phase migrated from legacy Sprint 10.12 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 133.1: Persisted Checkpoint Proof Admission [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Checkpoint/{Store,Writer}.hs`,
`src/JitML/Product/Pipeline.hs`, completed/candidate checkpoint call sites,
`test/unit/{Main,ProtocolCodec}.hs`, `test/integration/Main.hs`
**Docs to update**: `README.md`, `00-overview.md`, `../README.md`,
`../documents/engineering/checkpoint_format.md`,
`../documents/engineering/training_metrics_and_splits.md`,
`../documents/engineering/training_workloads.md`,
`../documents/engineering/run_contract.md`, `system-components.md`,
`legacy-tracking-for-deletion.md`

### Objective

Completion and inference eligibility are admitted only from an exact, stable
persisted checkpoint snapshot. `Store` owns reading and verifying the pointer,
exact manifest envelope/body, and physical payloads, then returns an opaque
admitted artifact. `Pipeline` consumes that value and cannot mint eligibility
from caller-supplied or merely in-memory values. Candidate persistence and
completed persistence are distinct APIs, and completed persistence cannot omit
`CompletedTraining`. This sprint owns the persisted-checkpoint portion of
[Exit Definition](README.md#exit-definition) item `31`; its previously closed
canonical supervised-plan and measured-completion refinements remain retained.

### Deliverables

- `Store` performs manifest-body stability reads: read latest pointer `P1`,
  fetch and verify the exact addressed outer bytes and embedded body, read
  latest pointer `P2`, and proceed only when `P1 == P2`. A changed pointer
  produces a typed retry/conflict result and never admits the body read between
  two different pointers. Physical blob verification is an independent
  content-addressed binding step, not part of the `P1`/`P2` body-stability
  interval.
- Admission verifies the outer address against the exact fetched outer bytes,
  canonical V1 structure or the V2 body address/exact embedded body bytes, and
  all manifest/refinement invariants before Store can construct its opaque
  admitted-completed artifact. Completed V1 refinement is restricted to
  canonical non-supervised ProductRows; supervised V1 remains inspection/resume
  only. Pure manifest completion validation is explicitly structural and cannot
  stand in for persisted admission.
- Blob binding verifies the exact object key, fetched bytes, byte length/content
  SHA, `.jmw1` decoding, `supervised.weights` identity, flat-vector length,
  virtual-slice bounds/coverage/shapes, and completed run's final-weight and
  plan identity. Manifest metadata alone cannot stand in for fetched payload
  evidence.
- Candidate and completed writer APIs are separate. Candidate writers carry no
  completion proof and cannot publish an inference-eligible latest pointer.
  Completed writers require a non-optional `CompletedTraining`; no completed
  boundary accepts `Maybe CompletedTraining` or a caller-asserted eligible flag.
- A content-addressed object write succeeds only when the object is absent or
  its existing bytes are exactly identical. Existing different bytes at the
  same key produce a typed conflict. Latest-pointer updates use exact
  compare-and-swap and cannot overwrite a concurrently changed value.
- Dependency direction is `Pipeline -> Store admission`: `Pipeline` requests
  admission and consumes the opaque artifact returned by `Store`. It cannot
  construct, alter, or relabel a manifest/proof before or after admission, and
  `Store` never accepts an eligibility value minted by `Pipeline`.
- Candidate/completed, pointer-race, object-conflict, byte-tamper,
  body/blob-substitution, malformed-`.jmw1`, slice-mismatch,
  plan/final-weight-mismatch, and successful stable-admission regressions cover
  local and MinIO-backed behavior.

### Retained Completed Surface

- The resolved supervised plan has positive unit-indexed training/evaluation
  budgets, canonical versioned transport, and a derived `PlanId`; local, Linux
  worker, and Apple host paths consume that same plan without primitive budget
  reinterpretation.
- Raw completion values re-run hidden smart constructors, require finite passing
  measurements plus exact budget completion, and cannot mint
  `CompletedTraining` through generic deserialization.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml test jitml-sl-canonicals --linux-cpu
docker compose run --rm jitml jitml test jitml-rl-canonicals --linux-cpu
docker compose run --rm jitml jitml test jitml-hyperparameter --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Closure Validation Evidence (2026-07-20)

- `jitml-unit --linux-cpu` passed **719 / 719** in **39.18s** on the
  post-transition worktree.
- `jitml-sl-canonicals --linux-cpu` passed **36 / 36**; the container exited
  `0` after **7,209.943s** wall time.
- `jitml-rl-canonicals --linux-cpu` passed **40 / 40** in **162.30s**, including
  the real AlphaZero completed-checkpoint path.
- `jitml-hyperparameter --linux-cpu` passed **26 / 26** in **0.38s**.
- Focused Store admission passed **8 / 8**; candidate persistence passed
  **1 / 1**; typed unsafe/unreadable write conflicts passed **1 / 1**.
- The library, unit, integration, and RL target compile sweep exited `0`;
  `jitml docs check`, `jitml check-code`, and `git diff --check` passed.
- Rule-M deterministic scans found **0** backward dependency edges across 45
  formal references, **0** dual-accelerator gates across 282 validation
  sections, and **0** accelerator invocations across the 20 validation
  sections in aggregation phases `17`, `18`, and `31`.

### Historical Validation Evidence (2026-07-14; retained surface only)

- `jitml-unit --linux-cpu` passed **411 / 411** in **37.11s**; its focused
  `ProtocolCodec` group passed **12 / 12**.
- `jitml-sl-canonicals --linux-cpu` passed **31 / 31** in **286.64s**.
- `jitml-rl-canonicals --linux-cpu` passed **40 / 40** in **224.50s**.
- `jitml-hyperparameter --linux-cpu` passed **21 / 21** in **0.23s**.
- The rebuilt `jitml:local` image passed its embedded strict build and
  `check-code`; the public container gates then passed with `docs check: ok`
  and `check-code: ok`.
- Rule-M deterministic scans found **0** backward dependency edges across 45
  formal references, **0** dual-accelerator gates across 284 validation
  sections, and **0** accelerator invocations across the 20 validation
  sections in aggregation phases `17`, `18`, and `31`.

### Remaining Work

- None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
