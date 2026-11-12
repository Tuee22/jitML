# Phase 318: CUDA runtime engineering

**Status**: Authoritative source
**Supersedes**: Current execution ownership for the mapped obligations; historical evidence remains scoped to its original source.
**Referenced by**: [ordered execution plan](ordered-execution-plan.md), [transfer register](ordered-plan-transfers.md), [README](README.md)
**Generated sections**: none

> **Purpose**: Engineering implementation for cuda runtime engineering in the current numerical sequence.

## Phase State

**Blocked; implementation and validation are open.** This planning refactor supplies
no software, hardware, scientific or qualification pass.

**Validation hardware**: NVIDIA Linux host + linux-cpu.
**Change boundary**: Engineering implementation.
**Inherited obligations**: [3.2](phase-3-governed-document-metadata-enforcement.md), [9.2](phase-9-subprocess-typed-values-runstreaming-capture-interpreter.md), [21.2](phase-21-structured-subprocess-outcomes.md), [29.2](phase-29-dhall-cluster-resource-profile-kind-node-cap-and-host-ram-pr.md), [43.2](phase-43-live-cluster-lifecycle-and-publication-truth.md), [51.2](phase-51-per-pod-resource-limits-and-right-sized-replicas-from-the-dh.md), [64.2](phase-64-workload-placement-planner-and-apple-host-workload-dispatch.md), [160.2](phase-160-functional-core-live-workflow-interpreter.md), [268.2](phase-268-contract-driven-cuda-lane-revalidation.md), [278.1](phase-278-external-bars-no-self-referential-gate-lint-and-exact-served.md), [279.1](phase-279-measured-declared-type-split-behavioral-scaffold-lint.md), [285.1](phase-285-contract-driven-per-model-evidence.md), [289.1](phase-289-evidence-typed-report-measurements.md).

The [execution contract](ordered-execution-plan.md#validation-contract) and
[transfer register](ordered-plan-transfers.md) define this phase's complete scope.
It closes before Phase 319 begins. Historical source receipts do not close it.

## Documentation Requirements

These are planned acceptance obligations; this planning edit does not mark any
documentation or implementation requirement complete.

**Engineering docs to create/update:**

- [jit_codegen_architecture.md](../documents/engineering/jit_codegen_architecture.md) — document real native Linux CUDA build/load/execute readiness.
- [execution_resources.md](../documents/engineering/execution_resources.md) — declare NVIDIA host/toolchain/CPU support and runtime budgets.
- [determinism_contract.md](../documents/engineering/determinism_contract.md) — record the device-specific correctness and reproducibility contract.

**Product docs to create/update:**

- [Root README](../README.md) — state verified native NVIDIA prerequisites and the Linux CPU support lane.

**Cross-references to add:**

- Reconcile this phase in the [ordered execution index](ordered-execution-plan.md) and [obligation transfer register](ordered-plan-transfers.md).
- Add or verify the relevant current-owner link from [jit_codegen_architecture.md](../documents/engineering/jit_codegen_architecture.md); retain historical source/evidence links with their original scope.
- Reconcile affected architecture and runtime ownership in [system-components.md](system-components.md).

## Sprint sizing

Every sprint targets **2–4 engineer-days**, with compute time recorded separately.
A sprint has one reviewable boundary and its own passing positive and negative
controls. If discovery makes it more than twice the peer median, split its
remaining scope prospectively before execution; never lower scientific budgets,
seed counts, assertions or acceptance bars to meet an effort estimate.


## Sprint 318.1: Actual nvidia toolchain, device and aggregate admission

**Status**: Blocked
**Implementation**: Planned targets: `src/JitML/Engines/CudaRuntime.hs`, `src/JitML/Engines/CublasBindings.hs`, `src/JitML/Engines/CudnnBindings.hs`, with this sprint's selectable controls in `test/`; changes stay within its declared work package.
**Docs to update**: `phase-318-cuda-runtime-engineering.md`, `ordered-execution-plan.md`, `ordered-plan-transfers.md`, and the governed owners listed in this phase's Documentation Requirements.
**Blocked by**: Sprint `317.3`.
**Effort**: 2–4 engineer-days; one bounded acceptance unit.
**Validation hardware**: NVIDIA Linux host + linux-cpu.

### Objective

Implement and verify actual NVIDIA toolchain, device and aggregate admission, preserving all earlier completed contracts.

### Deliverables

- Implement the NVIDIA-host prerequisite and admission path: identify the actual GPU/driver, CUDA toolkit, cuBLAS/cuDNN and attached GPU-container runtime, and bind their identities to the owned invocation.
- Compare requested and effective host/container/node/helper CPU, memory, swap, PID and scratch/output budgets before releasing numerical work; account for overlap and retain failed or incomplete observations.
- Exercise a finite admitted device allocation/launch and bounded retirement. Missing GPU/runtime, wrong device identity, effective-limit mismatch and stale/missing reserve readers must refuse admission without exhausting the host. WSL2 and CPU-only execution cannot satisfy this device probe.
- Implement this package and its independently enumerated selectable controls, including a real positive path and rejection of missing, malformed or misleading inputs.
- Update the maintained source, generated references and documentation together. Use independent fixture credentials and bounded runtime probes where applicable; preserve all original cases in the gate inventory.

### Validation

**Required result:** A real admitted NVIDIA launch passes with recorded effective budgets; missing hardware/toolchain, wrong identity, reserve-reader failure or quota mismatch refuses before numerical release. No CUDA work runs in WSL2.

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

## Sprint 318.2: CUDA producer, numerical and process controls

**Status**: Blocked
**Implementation**: Planned targets: `src/JitML/Engines/CudaRuntime.hs`, `src/JitML/Engines/CublasBindings.hs`, `src/JitML/Engines/CudnnBindings.hs`, with this sprint's selectable controls in `test/`; changes stay within its declared work package.
**Docs to update**: `phase-318-cuda-runtime-engineering.md`, `ordered-execution-plan.md`, `ordered-plan-transfers.md`, and the governed owners listed in this phase's Documentation Requirements.
**Blocked by**: Sprint `318.1`.
**Effort**: 2–4 engineer-days; one bounded acceptance unit.
**Validation hardware**: NVIDIA Linux host + linux-cpu.

### Objective

Implement and verify CUDA producer, numerical and process controls, preserving all earlier completed contracts.

### Deliverables

- Implement and exercise actual CUDA cache-miss compilation, cuBLAS/cuDNN execution and weight-dependent inference/training controls; retain source, temporary/final artifact paths, device identity and exact invocation observations.
- Verify snapshot/object publication and exact-byte readback through the existing storage contract, including stale identity, changed weights and substituted artifacts as independent negatives; rendered CUDA source alone supplies no execution proof.
- Integrate owned process-family capture, observer disconnect/reconnect, cancellation and supervisor/safety-reader failure with the real GPU workload. Bound retirement and preserve primary/cleanup failures and original application-state readback.
- Implement this package and its independently enumerated selectable controls, including a real positive path and rejection of missing, malformed or misleading inputs.
- Update the maintained source, generated references and documentation together. Use independent fixture credentials and bounded runtime probes where applicable; preserve all original cases in the gate inventory.

### Validation

**Required result:** The selected real CUDA compile/numerical/storage/process controls pass on the declared GPU and exact bytes; tampered artifacts, constant-output fakes and broken ownership/retirement fail for their named reasons. Preserve stopped workload and original-data readback receipts.

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

## Sprint 318.3: Affected scientific readiness and frozen-schema measurement producers

**Status**: Blocked
**Implementation**: Planned targets: `src/JitML/Engines/CudaRuntime.hs`, `src/JitML/Engines/CublasBindings.hs`, `src/JitML/Engines/CudnnBindings.hs`, with this sprint's selectable controls in `test/`; changes stay within its declared work package.
**Docs to update**: `phase-318-cuda-runtime-engineering.md`, `ordered-execution-plan.md`, `ordered-plan-transfers.md`, and the governed owners listed in this phase's Documentation Requirements.
**Blocked by**: Sprint `318.2`.
**Effort**: 2–4 engineer-days; one bounded acceptance unit.
**Validation hardware**: NVIDIA Linux host + linux-cpu.

### Objective

Implement and verify affected scientific readiness and frozen-schema measurement producers, preserving all earlier completed contracts.

### Deliverables

- Implement CUDA measurement producers for learning curves, final EvaluationSet, measured work, inference timings, same-seed reruns and invocation-journaled `/metrics` and `/healthz`; bind every field to the actual source, device, recipe and trained artifacts.
- Run finite targeted readiness for affected SL, RL, AlphaZero and tuning paths under the admitted envelope, starting with known failures and recording the impact on earlier CPU/shared-path passes. Preserve prescribed numerical work, seeds and acceptance predicates.
- Reject absent/fabricated counters, stale device/source identity, weight-independent output and missing invocation measurements. Complete all CUDA code/schema corrections here before the shared freeze; complete real cohort qualification remains with Phase 323.
- Implement this package and its independently enumerated selectable controls, including a real positive path and rejection of missing, malformed or misleading inputs.
- Update the maintained source, generated references and documentation together. Use independent fixture credentials and bounded runtime probes where applicable; preserve all original cases in the gate inventory.

### Validation

**Required result:** Current-source targeted CUDA readiness and all required measurement producers pass; missing, fabricated or stale observations refuse readiness. No Phase 320 epoch or Phase 323 qualifying journal is needed to validate this sprint.

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

Use a real NVIDIA Linux host, CUDA/cuBLAS/cuDNN/toolchain and resource admission. WSL2 cannot run this phase. Complete all CUDA source/runner/schema fixes and genuine readiness before shared freeze; CPU support alone cannot pass the device controls.
