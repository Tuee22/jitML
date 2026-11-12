# Phase 319: Apple runtime engineering

**Status**: Authoritative source
**Supersedes**: Current execution ownership for the mapped obligations; historical evidence remains scoped to its original source.
**Referenced by**: [ordered execution plan](ordered-execution-plan.md), [transfer register](ordered-plan-transfers.md), [README](README.md)
**Generated sections**: none

> **Purpose**: Engineering implementation for apple runtime engineering in the current numerical sequence.

## Phase State

**Blocked; implementation and validation are open.** This planning refactor supplies
no software, hardware, scientific or qualification pass.

**Validation hardware**: macOS Apple Silicon host + linux-cpu.
**Change boundary**: Engineering implementation.
**Inherited obligations**: [3.2](phase-3-governed-document-metadata-enforcement.md), [9.2](phase-9-subprocess-typed-values-runstreaming-capture-interpreter.md), [21.2](phase-21-structured-subprocess-outcomes.md), [29.2](phase-29-dhall-cluster-resource-profile-kind-node-cap-and-host-ram-pr.md), [43.2](phase-43-live-cluster-lifecycle-and-publication-truth.md), [51.2](phase-51-per-pod-resource-limits-and-right-sized-replicas-from-the-dh.md), [64.2](phase-64-workload-placement-planner-and-apple-host-workload-dispatch.md), [160.2](phase-160-functional-core-live-workflow-interpreter.md), [273.2](phase-273-contract-driven-apple-lane-revalidation.md), [278.1](phase-278-external-bars-no-self-referential-gate-lint-and-exact-served.md), [282.1](phase-282-runcontract-negative-controls-lifecycle-and-per-row-registra.md), [285.1](phase-285-contract-driven-per-model-evidence.md), [289.1](phase-289-evidence-typed-report-measurements.md).

The [execution contract](ordered-execution-plan.md#validation-contract) and
[transfer register](ordered-plan-transfers.md) define this phase's complete scope.
It closes before Phase 320 begins. Historical source receipts do not close it.

## Documentation Requirements

These are planned acceptance obligations; this planning edit does not mark any
documentation or implementation requirement complete.

**Engineering docs to create/update:**

- [apple_silicon_metal_headless_builds.md](../documents/engineering/apple_silicon_metal_headless_builds.md) — document real host Metal build/load/execute readiness.
- [jit_codegen_architecture.md](../documents/engineering/jit_codegen_architecture.md) — align fixed bridge and generated Metal metadata contracts.
- [execution_resources.md](../documents/engineering/execution_resources.md) — declare macOS host/GPU/client supervision and budget requirements.

**Product docs to create/update:**

- [Root README](../README.md) — state verified macOS Metal prerequisites and the Linux CPU support lane.

**Cross-references to add:**

- Reconcile this phase in the [ordered execution index](ordered-execution-plan.md) and [obligation transfer register](ordered-plan-transfers.md).
- Add or verify the relevant current-owner link from [apple_silicon_metal_headless_builds.md](../documents/engineering/apple_silicon_metal_headless_builds.md); retain historical source/evidence links with their original scope.
- Reconcile affected architecture and runtime ownership in [system-components.md](system-components.md).

## Sprint sizing

Every sprint targets **2–4 engineer-days**, with compute time recorded separately.
A sprint has one reviewable boundary and its own passing positive and negative
controls. If discovery makes it more than twice the peer median, split its
remaining scope prospectively before execution; never lower scientific budgets,
seed counts, assertions or acceptance bars to meet an effort estimate.


## Sprint 319.1: Actual host metal placement, admission and cancellation

**Status**: Blocked
**Implementation**: Planned targets: `src/JitML/Engines/MetalBridge.hs`, `src/JitML/Engines/MetalRuntime.hs`, `src/JitML/Codegen/MetalLayerTraining.hs`, with this sprint's selectable controls in `test/`; changes stay within its declared work package.
**Docs to update**: `phase-319-apple-runtime-engineering.md`, `ordered-execution-plan.md`, `ordered-plan-transfers.md`, and the governed owners listed in this phase's Documentation Requirements.
**Blocked by**: Sprint `318.3`.
**Effort**: 2–4 engineer-days; one bounded acceptance unit.
**Validation hardware**: macOS Apple Silicon host + linux-cpu.

### Objective

Implement and verify actual host Metal placement, admission and cancellation, preserving all earlier completed contracts.

### Deliverables

- Implement actual macOS host dispatch through the fixed Metal bridge and visible GPU; bind the native executable, bridge/runtime and host device identities to the invocation rather than treating a container probe as host execution.
- Admit native heap/CPU and measured process/unified-memory growth alongside the named VM, cluster, client and helper budgets. Verify actual limits and reserve readers; Docker quotas are not a native Metal memory ceiling.
- Exercise finite host dispatch and owned cancellation. Wrong residency/device, absent bridge/runtime, stale reserve observations, duplicate ownership and cancellation of an unowned identity must fail with bounded retirement and retained terminal outcomes.
- Implement this package and its independently enumerated selectable controls, including a real positive path and rejection of missing, malformed or misleading inputs.
- Update the maintained source, generated references and documentation together. Use independent fixture credentials and bounded runtime probes where applicable; preserve all original cases in the gate inventory.

### Validation

**Required result:** A finite workload is placed on the actual Mac Metal host with observed native/VM aggregate admission and bounded owned cancellation; wrong residency, missing bridge/device or failed reserve readers refuses launch.

1. Run the owned selectable hermetic controls and bounded real runtime observations on the declared hardware, after publishing their exact inventory and selectors in the existing command machinery.
2. Verify a positive implementation path and independent negative controls for this work package; a fixture cannot satisfy a real-hardware or scientific assertion.
3. Pass phase-scoped documentation, generated-source, lint/build and gate-inventory checks. Planned future owners may remain unimplemented; none of their real lane records or complete aggregate suites is a prerequisite here.

The scoped gate must be implemented in Phase 290 before it is invoked. Existing
`jitml test <stanza> --<substrate> --test-options=...` selectors remain the test
boundary; this plan does not invent an already-supported CLI flag. A scoped pass
never becomes a full-stanza pass. Every deferred assertion has an explicit later
owner in the transfer register, rather than a skip, allowlist or deleted case.

### Remaining Work

- Complete this work package and retain its declared acceptance evidence.
- Compare changed behavior with earlier contracts; reopen the earliest violated owner before continuing.

## Sprint 319.2: Metal numerical, storage and process controls

**Status**: Blocked
**Implementation**: Planned targets: `src/JitML/Engines/MetalBridge.hs`, `src/JitML/Engines/MetalRuntime.hs`, `src/JitML/Codegen/MetalLayerTraining.hs`, with this sprint's selectable controls in `test/`; changes stay within its declared work package.
**Docs to update**: `phase-319-apple-runtime-engineering.md`, `ordered-execution-plan.md`, `ordered-plan-transfers.md`, and the governed owners listed in this phase's Documentation Requirements.
**Blocked by**: Sprint `319.1`.
**Effort**: 2–4 engineer-days; one bounded acceptance unit.
**Validation hardware**: macOS Apple Silicon host + linux-cpu.

### Objective

Implement and verify Metal numerical, storage and process controls, preserving all earlier completed contracts.

### Deliverables

- Implement and exercise an actual host Metal cache miss, runtime MSL compilation and weight-dependent numerical execution, observing generated source/temporary/final paths and exact checkpoint publication/readback.
- Exercise real host forwarding and observer disconnect/reconnect, then controlled supervisor/safety-owner loss and bounded family retirement. Missing host handoff, stale identities, fabricated device evidence and substituted artifact bytes must be rejected without losing original application state.
- Audit retained retired-default-VM recovery data offline and verify replacement image/volume/host-state retention and restored readback under the policy below; retain failed migration evidence and never automatically start, recreate or purge the retired VM.
- Implement this package and its independently enumerated selectable controls, including a real positive path and rejection of missing, malformed or misleading inputs.
- Update the maintained source, generated references and documentation together. Use independent fixture credentials and bounded runtime probes where applicable; preserve all original cases in the gate inventory.

### Validation

**Required result:** Actual host Metal numerical, forwarding, publication/readback and process controls pass; tampered artifacts, stale handoffs and failed safety ownership refuse with retained cleanup outcomes. Recovery data is retained unless replacement retention/readback has been independently verified.

1. Run the owned selectable hermetic controls and bounded real runtime observations on the declared hardware, after publishing their exact inventory and selectors in the existing command machinery.
2. Verify a positive implementation path and independent negative controls for this work package; a fixture cannot satisfy a real-hardware or scientific assertion.
3. Pass phase-scoped documentation, generated-source, lint/build and gate-inventory checks. Planned future owners may remain unimplemented; none of their real lane records or complete aggregate suites is a prerequisite here.

The scoped gate must be implemented in Phase 290 before it is invoked. Existing
`jitml test <stanza> --<substrate> --test-options=...` selectors remain the test
boundary; this plan does not invent an already-supported CLI flag. A scoped pass
never becomes a full-stanza pass. Every deferred assertion has an explicit later
owner in the transfer register, rather than a skip, allowlist or deleted case.

### Remaining Work

- Complete this work package and retain its declared acceptance evidence.
- Compare changed behavior with earlier contracts; reopen the earliest violated owner before continuing.

## Sprint 319.3: Affected scientific readiness and frozen-schema measurement producers

**Status**: Blocked
**Implementation**: Planned targets: `src/JitML/Engines/MetalBridge.hs`, `src/JitML/Engines/MetalRuntime.hs`, `src/JitML/Codegen/MetalLayerTraining.hs`, with this sprint's selectable controls in `test/`; changes stay within its declared work package.
**Docs to update**: `phase-319-apple-runtime-engineering.md`, `ordered-execution-plan.md`, `ordered-plan-transfers.md`, and the governed owners listed in this phase's Documentation Requirements.
**Blocked by**: Sprint `319.2`.
**Effort**: 2–4 engineer-days; one bounded acceptance unit.
**Validation hardware**: macOS Apple Silicon host + linux-cpu.

### Objective

Implement and verify affected scientific readiness and frozen-schema measurement producers, preserving all earlier completed contracts.

### Deliverables

- Implement host Metal measurement producers for learning curves, final EvaluationSet, measured work, inference timings, same-seed reruns and invocation-journaled `/metrics` and `/healthz`, bound to actual source/device/recipe and trained artifacts.
- Run finite targeted readiness for affected SL, RL, AlphaZero and tuning paths, retaining known learning/timeout and allocation failures and the impact on earlier CPU/shared-path results. Preserve prescribed numerical work, seeds and acceptance predicates.
- Reject weight-independent output, missing invocation observations, substituted checkpoints and stale source/device bindings. Finish all Apple source/schema changes and affected readiness before the shared freeze; complete real cohort qualification remains with Phase 324.
- Implement this package and its independently enumerated selectable controls, including a real positive path and rejection of missing, malformed or misleading inputs.
- Update the maintained source, generated references and documentation together. Use independent fixture credentials and bounded runtime probes where applicable; preserve all original cases in the gate inventory.

### Validation

**Required result:** Current-source targeted Metal readiness and all required measurement producers pass; missing invocation observations or fabricated/stale device evidence refuse. Neither the common freeze nor the later Apple qualifying journal is a validation prerequisite.

1. Run the owned selectable hermetic controls and bounded real runtime observations on the declared hardware, after publishing their exact inventory and selectors in the existing command machinery.
2. Verify a positive implementation path and independent negative controls for this work package; a fixture cannot satisfy a real-hardware or scientific assertion.
3. Pass phase-scoped documentation, generated-source, lint/build and gate-inventory checks. Planned future owners may remain unimplemented; none of their real lane records or complete aggregate suites is a prerequisite here.

The scoped gate must be implemented in Phase 290 before it is invoked. Existing
`jitml test <stanza> --<substrate> --test-options=...` selectors remain the test
boundary; this plan does not invent an already-supported CLI flag. A scoped pass
never becomes a full-stanza pass. Every deferred assertion has an explicit later
owner in the transfer register, rather than a skip, allowlist or deleted case.

### Remaining Work

- Complete this work package and retain its declared acceptance evidence.
- Compare changed behavior with earlier contracts; reopen the earliest violated owner before continuing.

## Required inherited detail

Use the actual host Metal bridge and native process/resource limits, placement/cancellation and real forwarding observer controls. A Linux render of Metal source is not a Mac pass. Complete Apple code and measurement producers before shared freeze.

## Retained Mac recovery data

319.2 owns the actual audit of the retired default Colima data disk and private
OS/settings copy, including image/volume/host-state migration and restored
readback before any release. Never automatically start/recreate the retired
VM or purge recovery data. The human may retain verified recovery data under
an explicit retention policy; physical purge is not a required scientific or
phase-closing operation. Generic Linux preservation 296 does not certify this
Mac-host data boundary.
