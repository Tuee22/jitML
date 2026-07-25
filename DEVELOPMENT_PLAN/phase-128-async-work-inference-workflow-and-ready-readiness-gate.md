# Phase 128: Async `Work*` Inference Workflow and `.ready` Readiness Gate

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Async Work* Inference Workflow and .ready Readiness Gate. Single-session phase migrated from legacy Sprint 10.7 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 128.1: Async `Work*` Inference Workflow and `.ready` Readiness Gate [✅ Done]

**Status**: Done on its retained surface (Work* envelope family + `.ready`/
`ArtifactRef` readiness gate + single-Engine compute collapse — static + live
validated). The remaining **publish-only async behavior** (the CLI/demo publish a
`WorkCommand` and render the streamed `WorkResult` instead of computing locally)
is an ownership-transfer to Phase `11` Sprint `11.10`, which owns the
websocket/publish-only infrastructure that both the demo panels and the CLI share
(standards rule E — one obligation in one place; rule M — forward transfer to a
later phase).
**Depends-On**: Sprint `5.13` (Coordinator topic algebra), Sprint `5.14`
(one-binary role model — Engine is the sole compute role)
**Implementation**: `src/JitML/Work/Envelope.hs` (new), `src/JitML/App.hs`,
`src/JitML/Service/Workload.hs`, `src/JitML/Service/Runtime.hs`,
`src/JitML/Checkpoint/Format.hs`, `test/integration/Main.hs`,
`test/daemon-lifecycle/Main.hs`
**Docs to update**: `../documents/engineering/checkpoint_format.md`,
`../documents/engineering/training_workloads.md`,
`../documents/engineering/pulsar_ml_workflow.md`, `system-components.md`,
`legacy-tracking-for-deletion.md`

The retained `.ready`/`ArtifactRef` gate is transport readiness only. A
`step >= 1` manifest and resolvable pointer do not mint current inference
eligibility; Engine execution additionally requires Sprint `10.12`'s opaque
Store-admitted artifact.

### Objective

Recast inference as an **asynchronous `Work*` workflow** owned by the single
**Engine**, and make transport readiness unrepresentable unless it comes from a
completed derivation. Implements the `Work*` envelope family and the `Artifact +
readiness contract` of
[../documents/engineering/pulsar_ml_workflow.md](../documents/engineering/pulsar_ml_workflow.md),
and retires the "Triplicated inference path" ledger row. Adopts `At-Least-Once
Event Processing`, `Capability Classes and Service Errors`, and `Parse, don't
validate` from [../README.md](../README.md).

### Deliverables

- Add `JitML.Work.Envelope` with `WorkCommand { callId, workflow, lane,
  subjectRef, artifactRef?, payload, replyTopic }`, `WorkEvent { callId, workflow,
  progress }`, `WorkResult { callId, status, outputRefs }`, correlated by
  `callId`; training and inference share this shape.
- Collapse the triplicated load→pick-runner→run-kernel logic (demo
  `weightedInferenceForBrowser`, CLI `inferenceForSubstrate`/`runInference`, daemon
  `daemonWorkloadDispatcherWithWeightedInference`) into the single Engine consumer
  path; the CLI/demo publish a `WorkCommand` and render the streamed `WorkResult`.
- Make a transport-ready `ArtifactRef` obtainable **only** from a training `WorkResult`
  whose checkpoint manifest has `step ≥ 1` and a resolvable `latest` pointer; the
  coordinator writes a `.ready` sentinel **last**. A malformed wire command parses
  into a typed rejection event, never a silent bad state. Current serving still
  requires the admitted artifact owned by Sprint `10.12`.
- Move the "Triplicated inference path" ledger row to `Completed`.

### Validation

- `docker compose run --rm jitml jitml test jitml-daemon-lifecycle --linux-cpu`
  covers the `Work*` correlation, the `.ready` gate (infer-before-ready →
  typed rejection), and single-Engine dispatch.
- `docker compose run --rm jitml jitml test jitml-integration --linux-cpu`
  (live `Work*` inference round-trip through the Engine; per standards rule M(b)
  this `linux-cpu` lane is the closure gate, with the accelerator lanes attested
  in Phases `15`/`16`).
- `docker compose run --rm jitml jitml docs check` and `jitml check-code`.

### Historical Validation State (host-native, apple-silicon lane)

- **Landed and validated host-native.** `JitML.Work.Envelope` defines the
  `Work*` family (`WorkCommand`/`WorkEvent`/`WorkResult`/`WorkStatus`) correlated
  by `CallId`, the **parse-don't-validate** wire boundary (`parseWorkCommand` →
  typed `WorkRejection`), and the producer-side `dedupByCallId` pure fold, which
  suppresses duplicate semantic results without changing the broker's
  at-least-once guarantee. The **readiness gate** is enforced in the types: `ArtifactRef`
  is opaque and obtainable only via `mintArtifactRef` (`Just` iff checkpoint
  manifest `step ≥ 1`), with `readinessSentinelKey` naming the `.ready` witness —
  so the historical transport gate rejects `parseWorkCommand Infer` with no
  ready artifact as `ArtifactNotReady`. It is not current persisted admission.
- **Triplicated compute collapsed.** The per-substrate weighted-runner dispatch is
  single-sourced in `engineWeightedInference`; the demo handler, the `jitml
  inference run` CLI (`inferenceForSubstrate`), and the daemon consumer all route
  through it. The "Triplicated inference path" ledger row moved to `Completed`.
- `cabal build lib:jitml` warning-clean (`-Wall`); `jitml-unit` **206 / 206**
  (three new `Work*` cases: readiness gate, typed-rejection parse, and
  call-ID semantic dedup), `jitml-daemon-lifecycle` **35 / 35**
  (behavior-preserving).
- **Container gates pass authoritatively.** `docker compose build jitml` exits `0`
  with the baked `jitml check-code` layer clean (fourmolu + hlint + warning-clean
  `-fcuda` build) on the full Phase `5`+`10` change set; and against the built
  `jitml:local` image: `jitml docs check` → `docs check: ok`, `jitml test
  jitml-unit --linux-cpu` → **206 / 206**, `jitml test jitml-daemon-lifecycle
  --linux-cpu` → **35 / 35**.
- **Live `linux-cpu` validation.** Against a freshly bootstrapped cluster
  (`jitml bootstrap --linux-cpu`, 84 steps), `jitml test jitml-integration
  --linux-cpu` passes **71 / 71** including the `Live` inference round-trip, which
  exercises the single-sourced `engineWeightedInference` through the daemon —
  confirming the compute collapse is behavior-preserving and live-correct.

### Remaining Work

- None on the retained surface. The **publish-only async behavior** (`jitml
  inference run` and the demo publish a `WorkCommand` and render the streamed
  `WorkResult` instead of computing locally) is transferred to Phase `11` Sprint
  `11.10` (it shares that sprint's websocket/publish-only infrastructure; both the
  demo panels and the CLI become thin publishers). Wiring the live
  coordinator-written `.ready` sentinel into the Engine readiness path (the pure
  gate + `ArtifactRef` minting are landed and tested) likewise lands with the
  Coordinator-role serve path in Sprint `12.16`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
