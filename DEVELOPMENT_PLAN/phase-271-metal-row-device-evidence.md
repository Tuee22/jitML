# Phase 271: Metal Row Device Evidence

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Metal Row Device Evidence. Single-session phase migrated from legacy Sprint 30.2 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done** (2026-08-28). Every Apple-supported row now carries execution-derived
Metal evidence, the corrected complete producer admitted all 55 product rows,
and the final Apple doctor, backend, and e2e validation passed on the current
source.

## Sprint 271.1: Metal Row Device Evidence [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Product/Matrix.hs`, `src/JitML/Codegen/MetalLayerTraining.hs`, `src/JitML/Engines/MetalBridge.hs`, `src/JitML/Engines/MetalRuntime.hs`, `src/JitML/Numerics/LayerGraphDevice.hs`, `test/backends/Main.hs`
**Docs to update**: `../documents/engineering/apple_silicon_metal_headless_builds.md`, `../documents/engineering/jit_codegen_architecture.md`

### Objective

Every `apple-silicon`-supported product row records real Metal device evidence
that the row's update-critical kernels compiled and dispatched on the host GPU
through the fixed bridge. Runtime absence fails up front, and no Apple row is
scheduled into a Linux pod as fake evidence.

### Deliverables

- Every `apple-silicon`-supported `ProductRow` records Metal `deviceEvidence`
  naming the Metal device and the compiled-and-dispatched update-critical kernels
  for that row.
- Absence of a Metal-capable GPU or the host Metal runtime fails the lane up front
  with a named error; no Apple row passes vacuously and no row is marked supported
  without real device evidence.
- No Apple product row is scheduled onto a Linux pod or `linux-cpu` engine as a
  substitute for Metal device evidence; the matrix classifies such a row as
  unsupported on this lane rather than counting host-only execution as proof.
- The report distinguishes unsupported rows from failed supported rows and pins
  each supported row's device evidence to the real bridge compile/dispatch.

### Validation

```bash
./bootstrap/apple-silicon.sh doctor
PATH=/opt/homebrew/opt/llvm@19/bin:$PATH cabal test jitml-backends --test-show-details=direct --test-options='-p apple-silicon'
PATH=/opt/homebrew/opt/llvm@19/bin:$PATH cabal test jitml-e2e --test-show-details=direct
docker compose build jitml
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
docker compose run --rm jitml jitml test jitml-unit --linux-cpu --test-options='-p "Product phase status registry" --hide-successes --color=never'
```

### 2026-08-26 Continuation Checkpoint

- A fresh `./bootstrap/apple-silicon.sh up` completed its **111-step** rollout,
  and all twelve canonical dataset objects were SHA-verified and staged in the
  live publication, including CIFAR-10
  (`c4a38c50a1bc5f3a1c5537f2155ab9d68f9f25eb67e78cec56e0c6d114c91ca1`)
  and CIFAR-100
  (`58a81ae192c23a4be8b1804d68e518ed807d710a4eb253b1f2a199162a40d8ec`).
- The first full-budget producer attempt exposed a real fixed-bridge throughput
  defect: dense and spatial-convolution callbacks each invoked a serial
  complete-operator opcode three times per batch. Production callbacks now use
  staged element-parallel Metal opcodes for forward, backward-data, and
  backward-weights results while preserving ascending inner-reduction order;
  the serial complete-operator opcodes remain as the reference path.
- The producer also exposed a per-batch `system_profiler` subprocess. Successful
  Metal visibility probes are now cached for the life of the producer process;
  failed probes retry, and explicit diagnostics continue to perform fresh
  probes.
- The real Apple backend lane passed **22 / 22**, including the Phase `270`
  all-operator numerical oracle and a new staged-dispatch regression gate.
- A fixed-budget `mnist-deep-mlp` smoke row processed **70,000** training
  examples, measured **0.934** test accuracy, and was admitted with execution
  witness
  `ac4137b7c8c283f5d100a46670a6076d89f0d4668c91a297615e842482b67ff4`.
- A subsequent producer attempt exposed the remaining batch multiplier: spatial
  convolution and correct-operator block/norm paths folded 128 examples into
  separate bridge calls. Conv2D/Conv3D now dispatch the whole batch, block
  affine/projection stages use batched dense callbacks, and Metal opcode `31`
  batches normalization while preserving per-example statistics and
  ascending-order gamma/beta reductions. The direct three-example
  Conv2D/Conv3D/block/norm oracle passed against the summed pure gradient in
  **0.05 s**, and the expanded real Apple backend lane passed **23 / 23**.
- That interrupted aggregate completed and admitted the first five supervised
  rows through `fashion-mnist-resnet`; it is not a substitute for the required
  single complete 55-row producer summary.
- The first uninterrupted 55-row producer completed on **2026-08-28** after
  **33 h 03 min 51 s** and reported `rows: 55`, `eligible: 47`,
  `unsupported: 0`, `errors: 8`, `admitted-inventory-entries: 47`, and
  `tune-trials-v2-transcripts: 1`. All eleven supervised rows, HER, all four
  AlphaZero rows, and tuning published. The eight rejected RL rows were
  `A2C/mountain-car`, `A2C/lunar-lander`, `MaskablePPO/mountain-car`,
  `MaskablePPO/key-door-grid`, `RecurrentPPO/cartpole`,
  `RecurrentPPO/mountain-car`, `QR-DQN/mountain-car`, and
  `SAC/lunar-lander`; each completed its exact fixed schedule and then failed
  the unchanged cohort threshold, so none was falsely admitted.
- That cross-algorithm failure pattern exposed the same shared-arithmetic seam
  Phase `265` had closed between the Linux lanes: Metal still used MSL's native
  `tanh` and permitted multiply-add contraction, while oneDNN and CUDA use the
  aligned glibc flt-32 activation and explicitly non-contracted arithmetic.
  `MlpMetal` now renders the same glibc operation sequence and
  `#pragma clang fp contract(off)`; no threshold or substrate-specific trainer
  hyperparameter changed. A 32 x 64 hidden-activation real-Metal regression
  compares all four summed gradient tensors bit-for-bit against an aligned
  float32 oracle and passes in **0.11 s**. The source guard also rejects native
  `tanh` call sites or removal of the contraction pragma.
- The corrected aggregate started on **2026-08-28** against the retained live
  publication and its 47 admitted artifacts. Its first fresh row,
  `A2C/mountain-car`, wrote a latest pointer, committed snapshot, manifest, and
  trajectory artifact at **08:20:47 UTC**; `A2C/lunar-lander` followed at
  **09:21:43 UTC**, and `MaskablePPO/mountain-car` at **09:51:27 UTC**. None of
  these rows had an admitted checkpoint after the diagnostic aggregate.
  `MaskablePPO/key-door-grid` followed at **10:53:29 UTC**, closing the four
  formerly rejected A2C/MaskablePPO rows, and `RecurrentPPO/cartpole` admitted
  at **11:41:22 UTC**. `RecurrentPPO/mountain-car` followed at **12:29:25 UTC**,
  closing both formerly rejected recurrent rows, and `QR-DQN/mountain-car`
  admitted at **12:41:16 UTC**. The final fresh `SAC/lunar-lander` row admitted
  at **13:03:32 UTC**.
- The corrected producer exited `0` after **5 h 12 min 41.62 s** and reported
  `rows: 55`, `eligible: 55`, `unsupported: 0`, `errors: 0`,
  `admitted-inventory-entries: 55`, and `tune-trials-v2-transcripts: 1`. Its
  inventory identifies the 47 content-addressed reuses and all eight fresh RL
  policy/trajectory admissions. This is the required complete aggregate audit;
  the complete row-device evidence gate.
- Final source validation passed on **2026-08-28**: the Apple stage-0 doctor
  exited `0`; `jitml-backends -p apple-silicon` passed **25 / 25** in
  **28.34 s**; `jitml-e2e` passed **30 / 30** in **0.40 s**; clean image
  `jitml:local@sha256:95e7786b0cd49b99ec26c8ffd0f18aa8b3d8956f163ec533972c7326fbf0df91`
  built with its embedded `check-code` and 611-module PureScript build passing;
  the independent mounted-worktree `jitml check-code` and `jitml docs check`
  gates passed; and the focused Product phase-status registry passed all
  **6 / 6** cases in its Linux-CPU unit invocation.

### 2026-08-24 Pause Checkpoint

The Phase `270` fixed-bridge layer-training implementation is now available to
mint the execution witnesses this phase requires. Validation completed before
this session paused:

- `./bootstrap/apple-silicon.sh doctor` passed.
- `jitml-backends` passed **21 / 21** on `apple-silicon`, including the
  all-operator fixed-bridge layer-training oracle.
- `jitml-e2e` passed **30 / 30**.
- `./bootstrap/apple-silicon.sh up` completed its **111-step** live rollout.
  The image build passed the container-only `jitml check-code` gate, and the
  live status reported registry, MinIO, Pulsar, observability, coordinator,
  demo, and edge all Ready.
- Ten of the twelve canonical dataset objects were SHA-verified and staged:
  MNIST and Fashion-MNIST train/test images and labels, Tiny ImageNet, and
  California Housing. The canonical CIFAR-100 archive was also downloaded and
  verified locally as
  `58a81ae192c23a4be8b1804d68e518ed807d710a4eb253b1f2a199162a40d8ec`,
  but was not staged before the pause. The CIFAR-10 transfer is incomplete and
  its partial file is not evidence.

No product-row publisher run was started, so this phase remains **Active** and
no row-complete claim is made. At the user's pause request all active transfers
were stopped and `./bootstrap/apple-silicon.sh down` deleted the two-node Kind
cluster. A continuation must recreate the publication and re-stage all twelve
objects before running the 55-row publisher.

2026-07-06 closing validation: the `apple-silicon` backend lane proves Metal
runtime absence fails before product-row evidence is accepted, and the real
windowed kernels compile and dispatch through the fixed bridge on the host GPU.
The row-complete attestation is preserved as the Phase `30` lane fragment, but
final product aggregation remains blocked by Phase `29`.

### Historical Validation

- **Closed Exit-Definition obligation**: every `apple-silicon`-supported product row
  must record real Metal device evidence for the row's real per-operation
  update-critical kernels and a genuinely trained model, not aggregated fabricated
  per-row eligibility over identity-copy kernels; runtime absence must still fail
  the lane up front.
- **Closing validation**: the per-model `jitml-model-convergence` suite (Phase `33`,
  [phase-33-per-model-convergence-and-inference-tests.md](README.md#legacy-to-new-phase-map))
  must train every `ProductRow` for real through the production device seam and
  clear its external bar, and the fabricated-evidence controls in the
  `jitml-negative-controls` stanza (Phase `32`,
  [phase-32-external-truth-realness-harness.md](README.md#legacy-to-new-phase-map))
  must reject the withdrawn device evidence — exercised via
  `docker compose run --rm jitml jitml test jitml-model-convergence --linux-cpu`
  and `docker compose run --rm jitml jitml test jitml-negative-controls --linux-cpu`,
  before the Metal row evidence is re-minted on the `apple-silicon` lane
  (`apple-silicon` plus `linux-cpu` only, never `linux-cuda`).

### Historical Phase State

> ✅ **Done**.

*(Retained as historical evidence for the surface it exercised; superseded by the 2026-08-12 reopen above.)*

## Documentation Requirements

**Engineering docs to create/update:**

- `../documents/engineering/apple_silicon_metal_headless_builds.md` — record the
  batched supervised fixed-bridge path, process-cached successful visibility
  probe, and aligned trainer-MLP arithmetic.
- `../documents/engineering/jit_codegen_architecture.md` — align the Metal
  layer-training dispatch, batch boundary, execution-witness, and determinism
  descriptions with the implemented path.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
