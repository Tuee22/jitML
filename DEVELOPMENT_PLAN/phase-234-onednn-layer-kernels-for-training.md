# Phase 234: oneDNN Layer Kernels for Training

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: oneDNN Layer Kernels for Training. Single-session phase migrated from legacy Sprint 23.2 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

🔄 **Active** (reopened 2026-07-26). The per-example oneDNN layer kernels are in
place and were validated on the `linux-cpu` container lane 2026-07-25 (`jitml test
jitml-backends --linux-cpu` **24 / 24**, `jitml test jitml-unit --linux-cpu`
**766 / 766**, `jitml check-code` **ok**; retained under
[Historical Validation](#historical-validation)). The IR-single-owner redesign
adds a new obligation on this phase's owned surface — **batched** oneDNN
forward/backward — so that layer-graph training is tractable for the vision rows
once [Phase 235](phase-235-one-self-describing-checkpoint-envelope.md) onward make
the typed `LayerGraph` IR the supervised executor. The unmet obligation is
enumerated in [Remaining Work](#remaining-work). Reopening to `Active` (not
`Blocked`) because the prerequisite Phase `233` is Done.

## Sprint 234.1: oneDNN Layer Kernels for Training [🔄 Active]

**Status**: Active
**Implementation**: `src/JitML/Codegen/OneDnn.hs`, `src/JitML/Numerics/LayerGraphOneDnn.hs`, `src/JitML/Numerics/MlpOneDnn.hs`, `src/JitML/Numerics/MlpDevice.hs`, `src/JitML/Engines/OneDnnRuntime.hs`, `test/backends/Main.hs`
**Docs to update**: `../documents/engineering/jit_codegen_architecture.md`, `../documents/engineering/numerical_core.md`

### Objective

Wire the layer graph's parameterized forward pre-activation and backward
parameter/input-gradient operations to generated oneDNN kernels through the JIT
device. `src/JitML/Codegen/OneDnn.hs` renders the training ABI, and
`src/JitML/Numerics/LayerGraphOneDnn.hs` binds it to the pure `Autodiff` tape so
the backend computes update-critical gradients rather than only the pure oracle.

### Deliverables

- `src/JitML/Codegen/OneDnn.hs` renders a layer-graph training shared object
  with a stable `jitml_layer_forward`, `jitml_layer_backward_data`, and
  `jitml_layer_backward_weights` ABI. Dense and other affine graph nodes execute
  oneDNN matmul primitives; `Conv2D` and `Conv3D` execute real
  `convolution_forward` (`forward_training`),
  `convolution_backward_data`, and `convolution_backward_weights` primitives
  over the graph's flat 1x1 channel projection.
- `JitML.Numerics.LayerGraphOneDnn` dispatches each parameterized layer node to
  that generated oneDNN ABI, reusing the pure `Autodiff` tape for activation,
  residual, and parameterless graph semantics. The returned evidence records the
  backend, artifact, and primitive name used for every parameterized node.
- A backends test asserts backend-vs-pure-oracle agreement within tolerance for
  every layer node's forward and backward, and records that the oneDNN device
  executed the update-critical operations (device evidence for the product row).
- Runtime absence of `libdnnl` fails the lane up front; no layer kernel passes
  vacuously.

### Remaining Work

- **Batched oneDNN forward/backward kernels.** The current
  `JitML.Numerics.LayerGraphOneDnn` device path evaluates one example at a time.
  Extend the `jitml_layer_forward` / `jitml_layer_backward_data` /
  `jitml_layer_backward_weights` ABI and its `LayerGraphOneDnn` dispatch to run
  over a batch dimension (oneDNN batched primitives), so IR training converges the
  vision rows within the single-threaded `linux-cpu` lane's time budget once the
  IR becomes the supervised executor downstream. Backend-vs-pure-oracle agreement
  and per-node device evidence must continue to hold, now over a batch. This is
  the only unmet obligation; the per-example kernels above stay valid for the
  surface they exercised. Close with the `### Validation` gate below.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-backends --linux-cpu
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml check-code
```

### Historical Validation

The initial 2026-07-02 backend comparison was withdrawn when the audit found
that its reference shared the same dense approximation. The 2026-07-06
reclosure moved Conv2D/Conv3D update-critical work through real oneDNN
convolution training primitives and compared the backend against the corrected
per-kind reference algebra. The retained validation is summarized in
[Phase State](#phase-state); absence of `libdnnl` still fails the lane up front.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
