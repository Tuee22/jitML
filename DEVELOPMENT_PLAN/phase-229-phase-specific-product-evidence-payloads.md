# Phase 229: Phase-Specific Product Evidence Payloads

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Phase-Specific Product Evidence Payloads. Single-session phase migrated from legacy Sprint 21.4 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done** (closed 2026-08-15). Every artifact a witness reads exports the
executed identity it is asked for, the persisted-evidence migration is stated in
the decoder itself, and the MLP device path is validated on the lane that
exercises it — `jitml test jitml-sl-canonicals --linux-cpu` **36 / 36**,
including `all eleven trained canonical programs equal Store-loaded V2 inference
on the same substrate`.

## Sprint 229.1: Phase-Specific Product Evidence Payloads [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Product/DeviceWitness.hs`,
`src/JitML/Product/Matrix.hs`, `src/JitML/Product/Pipeline.hs`,
`src/JitML/Product/Evidence.hs`, `src/JitML/Product/Completion.hs`,
`src/JitML/Product/Publisher/Runtime.hs`,
`src/JitML/Product/Publisher/{Supervised,RL,AlphaZero,Tuning}.hs`,
`src/JitML/Numerics/MlpDevice.hs`, `src/JitML/Numerics/LayerGraphOneDnn.hs`,
`src/JitML/SL/Architecture.hs`, `src/JitML/SL/TrainingExecution.hs`,
`src/JitML/Training/Budget.hs`, `src/JitML/Checkpoint/Format.hs`,
`src/JitML/Checkpoint/Store.hs`, `src/JitML/Test/Report.hs`,
`src/JitML/Test/DeviceWitnessFixture.hs`, `test/unit/Main.hs`
**Docs to update**: `../README.md`,
`../documents/engineering/product_completion_contract.md`,
`../documents/engineering/checkpoint_format.md`,
`../documents/engineering/durable_state_dsl.md`,
`../documents/engineering/run_contract.md`, `system-components.md`,
`legacy-tracking-for-deletion.md`

### Objective

Store only the payload legal for each product lifecycle state, so contradictory
optional evidence cannot be constructed even inside the module. This sprint
owns the product type-state portions of
[Exit Definition](README.md#exit-definition) items `30` and `31`.
The binding design is
[README.md → Typed run contracts](../README.md#typed-run-contracts).

### Deliverables

- Replace phase-independent records containing `Maybe` evidence with GADT or
  data-family constructors whose payload is specific to `Declared`, `Running`,
  `Completed`, and `InferenceEligible` states.
- Hide constructors for product rows, model references, training evidence,
  passing measurements, and eligibility proofs; expose total smart constructors
  and legal state transitions only.
- Remove redundant fields whose values are derivable from the state witness,
  including stored completion/pass booleans and optional manifests in completed
  states.
- Decode raw Haskell/Dhall/browser DTOs into validation errors or a legal state;
  no decoder constructs a proof-bearing value directly.
- Add compile-time legal-path fixtures and runtime negative tests for every
  invalid transition and mismatched plan/evidence pair.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml test jitml-negative-controls --linux-cpu
docker compose run --rm jitml jitml test jitml-sl-canonicals --linux-cpu
docker compose run --rm jitml jitml test jitml-integration --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

Measured on `linux-cpu` on 2026-08-15 in the `jitml:local` container against the
live nine-component publication (retained transcript
`.build/gate-logs/phase229-241-263-gate.log`, SHA-256
`2cfca808b1c33ef6e4e03928f7b5d180443315a8c7a7ec2ca8470e8aeb2cae25`):

| Gate | Result |
|------|--------|
| `jitml lint haskell` | exit `0` |
| `jitml docs check` | exit `0` |
| `jitml test jitml-unit --linux-cpu` | **887 / 887** (46.48s) |
| `jitml test jitml-backends --linux-cpu` | **36 / 36** (1.54s) |
| `jitml test jitml-negative-controls --linux-cpu` | **3 / 3** |
| `jitml test jitml-sl-canonicals --linux-cpu` | **36 / 36** (7,769.90s) |
| `jitml check-code` | exit `0` |

`jitml test jitml-integration --linux-cpu` is recorded with Sprint `263.1`,
which owns the lane re-issue this sprint's evidence depends on: the same run
that measured the witnesses above reported them as drift against a committed
fragment that predated them. That fragment is re-issued and re-measured in
Sprint `263.1`'s gate.

### Completed in the 2026-08-15 closure

- **The MLP artifact exports the identity the witness reads.**
  `JitML.Codegen.MlpOneDnn` and `JitML.Codegen.MlpCuda` emit
  `jitml_kernel_family_name`, returning the shared MLP program tag
  `mlp-forward-backward-tanh-linear` — the same string the Apple metadata's
  `family` field already carried. `Fingerprint.mlpHostEntryPoints` names the
  symbol, so Sprint `78.1`'s standing case (every named entry point exists in
  the source its lane renders) fails closed if a renderer drops it again.
  Before this, `mlpDeviceExecutionWitness` resolved a symbol only the
  family-kernel renderer emitted, so every MLP-path witness failed at `dlsym`
  and `california-housing-mlp` could not produce one at all. It now does: the
  measured lane fragment records
  `device:linux-cpu:onednn:mlp-forward-backward-tanh-linear:ef7ebe1dc3f02cbb`
  for that row.
- **The persisted-evidence migration is in the decoder.** The hand-written
  `Serialise TrainingEvidence` instance accepts the pre-witness five-field
  shape and fills the witness with `Nothing`. That does not weaken the
  contract: a witnessless evidence value is exactly what checkpoint admission
  rejects, so a pre-witness checkpoint now fails at the admission gate naming
  the missing device witness rather than at CBOR with
  `Wrong number of fields: expected=6 got=5`. The re-issue of the live
  `linux-cpu` store is Sprint `263.1`'s under rule `M(a)`.
- **Validated on the lane that exercises the MLP device path.**
  `jitml test jitml-sl-canonicals --linux-cpu` passed **36 / 36** in 7,769.90s,
  including both `all eleven trained canonical programs equal Store-loaded V2
  inference on the same substrate (Sprint 10.6)` and `all eleven live
  supervised latest pointers load exact V2 runtime identity (Sprint 10.6
  Live)`.

### Historical Validation

Validated on `linux-cpu` on 2026-07-22 (the refactor is pure type-level with no
runtime-path change, so it was validated from source without a cluster reload):

- **`Pipeline.ModelRef` is a hidden-constructor GADT.** `DeclaredModelRef` /
  `TrainingStartedModelRef` carry only the experiment hash;
  `TrainingCompletedModelRef` adds the completed-training witness;
  `InferenceEligibleModelRef` adds the admitted manifest SHA. The module exports
  only `ModelRef` (opaque), the smart transitions (`declareModel`,
  `startTraining`, `train`, `completeTraining`, `markInferenceEligible`), and
  total accessors — a contradictory state payload is unconstructible.
- **`Matrix.ProductRow` dropped its optional evidence.** The four
  `Maybe (EvidenceHandle state kind)` fields, the `EvidenceHandle`/`EvidenceKind`
  types, the `validateDeclaredEvidenceBoundary` projection guard, and the
  `DeclaredProductCarriesEvidence` error are removed. The former runtime
  fabrication negative control is now a compile-time impossibility (documented in
  `test/unit/Main.hs`).
- **Suites** (new code): `jitml-unit` **739 / 739**, `jitml-negative-controls`
  **3 / 3**, `jitml-model-convergence` **111 / 111**, `jitml-integration`
  **156 / 156** (runtime unchanged; live `-p Live` cases pass on the current
  cluster image). `jitml docs check` and `jitml check-code` both exited `0`
  (the `-Werror` build is clean with the retained `ProductRow` phantom), and the
  phase-status parity test agrees with the typed registry.

### Completed before the 2026-08-14 reopen

- **`DeviceExecutionWitness` is unconstructible without an artifact.**
  `JitML.Product.DeviceWitness` exports the type opaquely and offers exactly one
  mint, `witnessDeviceExecution`, which runs in `IO`. It fails closed on an
  absent or unreadable artifact, a non-hex cache key, or a blank backend /
  executed identity, and records the SHA-256 of the bytes it read. Values off the
  wire re-enter through `refineRawDeviceExecutionWitness`, which re-checks every
  property that survives serialization, so a hand-authored journal row does not
  refine.
- **The executed identity is read back, not asserted.** The layer-graph oneDNN
  witness asks the loaded artifact for `jitml_layer_training_backend` and
  `jitml_layer_forward_primitive`; `mlpDeviceExecutionWitness` resolves
  `jitml_kernel_family_name` from the loadable backends. The `apple-silicon`
  path previously attributed a run to `familyNameText family` — the value the
  host had just asked for, which could not disagree with itself — and now parses
  the `family` field out of the `<hash>.metal.json` artifact the renderer wrote.
- **Every product family records a witness after its loop returns.**
  Supervised training threads it through `SlRunMetrics.slmDeviceWitness` →
  `TrainingMetrics.tmDeviceWitness` → `SupervisedPublishRun`; the RL, AlphaZero,
  and tuning publishers (and the matching CLI/daemon paths) mint from
  `mlpdExecutionWitness` once their training call has succeeded. The pure
  reference device compiles nothing and yields `Right Nothing`, an honest
  absence rather than a fabricated claim.
- **The witness is part of being admitted.**
  `TrainingEvidence` carries it across `revalidateEvidence`, and
  `requireAdmittedCompletedCheckpoint` refuses a completion without one. The
  witness is therefore a field of `AdmittedCompletedCheckpoint`, so
  `admittedCompletedDeviceWitness` and
  `Report.completedProductScenarioDeviceWitness` are total and
  `renderProductLaneAttestationFragment` renders the cell with no no-evidence
  branch.
- **The declaration-derived path is deleted.**
  `deviceEvidenceForClaim`, `productRowDeviceEvidenceForSubstrate`,
  `substrateDeviceRuntime`, and `deviceClaimKernelSummary` are removed from
  `JitML.Product.Matrix` with their exports. The unit case that pinned the two
  composers against each other is replaced by four cases that pin the witness
  contract: the rendered cell names the lane, the artifact's backend, the
  executed identity and the artifact digest; two lanes cannot share a cell; the
  mint fails closed on an absent artifact; and a tampered wire witness fails
  refinement.
- **Manifest cross-check compares observations.** The checkpoint manifest stores
  the four observations but not the witness, so
  `validateCheckpointCompletion` compares `evidenceObservationsMatch` rather
  than whole evidence records.

### Historical Phase State

> ✅ **Done**.

*(Retained as historical evidence for the surface it exercised; superseded by the 2026-08-12 reopen, which this 2026-08-13 closure resolves.)*

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
