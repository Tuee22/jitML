# Phase 233: Typed Layer IR + Reverse-Mode Autodiff

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Typed Layer IR + Reverse-Mode Autodiff. Single-session phase migrated from legacy Sprint 23.1 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done** (closed 2026-08-14). The graph is the sole representation of every
supervised architecture, and every path to it fails closed. A canonical row
carries its executed `problemFamily` directly, so an unrecognised model string
can no longer resolve to the dense family; the claimed-feature table switches on
that family rather than re-matching the model string, so it can no longer answer
`[FeatureDense]` for an unknown row; a literal builder that fails its
smart-constructor shape checks now propagates the failure instead of
substituting the legacy decorative graph; and `weightPlan` names the four
genuinely weightless operators explicitly, so a new operator can no longer
receive zero trainable parameters and silently train nothing.

Those first two fallbacks were a conspiracy, not two independent bugs: an
unknown model resolved to dense **and** claimed only dense features, so the
feature-parity gate held vacuously and a degraded architecture passed its own
check.

## Sprint 233.1: Typed Layer IR + Reverse-Mode Autodiff [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Numerics/LayerGraph.hs`, `src/JitML/Numerics/Autodiff.hs`, `src/JitML/Numerics/Mlp.hs`, `src/JitML/Numerics/LayerGraphOneDnn.hs`, `src/JitML/SL/Architecture.hs`, `src/JitML/Checkpoint/Store.hs`, `src/JitML/SL/ConvergenceThresholds.hs`, `src/JitML/Test/NegativeControls.hs`, `test/unit/Main.hs`, `test/sl-canonicals/Main.hs`
**Docs to update**: `../documents/engineering/numerical_core.md`, `../documents/engineering/determinism_contract.md`

**Planning note (2026-07-22)**: A multi-agent design pass produced an
implementable blueprint at
[phase-23-sprint-23.1-blueprint.md](phase-23-sprint-23.1-blueprint.md). Two
findings reshape execution: (1) **a checkpoint-format wall** — the frozen V2
supervised slice contract (`RuntimeArtifact.deriveLayerSlices`,
`Architecture.hs:1739`) forces every serialized SL operator to be exactly one
`MlpParams (W1,b1,W2,b2)`, so 23.1 builds the correct Tier-2 autodiff node
library (conv/pool/norm/attention/geglu/residual) with finite-difference
verification and lands only param-neutral Tier-1 fixes on the served path;
wiring the real architectures into the serialized/served path needs a format
version bump and is Sprint 23.2. (2) **The convergence go/no-go is
`cifar10-vit`** — swapping to the real self-attention architecture moves it in
the wrong direction (already 0.218 < the 0.25 bar under the easier proxy), while
conv rows are helped by real convolution; honest mitigations (warmup+cosine
schedule, zero-init-residual, more real data/epochs — no bar weakening) plus the
vacuous `tiny-imagenet-resnet50` (0.00) / `cifar100-wide-resnet` (0.04) bars
must be resolved here so Sprint 24.2 is a real go.

### Objective

Generalize the single-hidden-layer hand-backprop in
`src/JitML/Numerics/Mlp.hs` into a reverse-mode autodiff pass over a typed layer
graph. The graph is the sole representation of every supervised architecture;
`src/JitML/SL/Architecture.hs` builds each family (`DenseFamily`,
`DeepDenseFamily`, `Conv2DLeNetFamily`, the ResNet and ViT families) as a real
`LayerGraph` instead of a composition of `DenseSpec` MLP blocks.

### Deliverables

- A `LayerGraph` IR whose nodes cover the full layer catalog: `Dense`, `Conv2D`,
  `Conv3D`, `MaxPool`, `AvgPool`, `GlobalAvgPool`, `BatchNorm`, `LayerNorm`,
  `GroupNorm`, `Dropout`, `Residual`, `BasicBlock`, `BottleneckBlock`,
  `MultiHeadAttention`, `GeGLU`, and patch-embed, each carrying its typed shape,
  parameter tensors, and training-vs-inference mode flag.
- A reverse-mode `Autodiff` pass that records a forward tape and replays a
  backward pass, so each layer node contributes a real forward and a real
  gradient (`backward_data` for inputs, `backward_weights` for parameters) rather
  than a hand-derived chain specialized to one hidden layer.
- `src/JitML/Numerics/Mlp.hs` is expressed as the two-layer special case of the
  general graph; the AlphaZero policy/value heads and the RL network seam consume
  the same `LayerGraph`/`Autodiff` surface.
- A unit test asserts finite-difference gradient checks pass for every layer node
  type and for at least one full ResNet-shaped and one ViT-shaped graph, and that
  the same seed and same substrate produce bit-identical gradients.

### Completed in this sprint

- The typed `LayerGraph` IR carries real operator geometry per node via a
  `layerNodeOp :: LayerOp` field (`ConvSpec`, `SpatialShape`/`PoolSpec`,
  `NormSpec`, `AttentionSpec`, `GeGLUSpec`, `AffineSpec`/`Shortcut`,
  `BlockSpec`, `PatchSpec`). Multi-tensor parameters pack into the existing flat
  `layerWeights`/`layerBias` with the segment layout recovered from
  `opWeightSegments`/`opBiasSegments`, so `graphParameterVector` /
  `replaceGraphParameterVector` stay operator-agnostic.
- Correct forward + `backward_data` + `backward_weights` for every catalog node:
  `Conv2D`, `Conv3D` (one N-D path), `MaxPool` (argmax-routed), `AvgPool`,
  `GlobalAvgPool` (per-channel), `LayerNorm`, `GroupNorm`, `BatchNorm`
  (batch-axis coupling), `MultiHeadAttention` (with residual add and `W_O`),
  `PatchEmbed` (shared projection + col2im), `GeGLU` (exact-erf GELU), and
  `Residual`/`BasicBlock`/`Bottleneck` (typed identity/projection shortcut).
  Backward recomputes forward internals from the stored node input, so no tape
  enrichment is required and gradients are deterministic for a fixed seed.
- The finite-difference suite covers **both** parameter and input gradients for
  every node kind plus full ResNet-shaped and ViT-shaped composed graphs, via the
  new `maxInputFiniteDifferenceError` oracle. Smart constructors reject shape and
  operation mismatches (identity shortcut on differing widths, `C mod G /= 0`,
  `embedDim mod heads /= 0`, non-composing block stages) instead of silently
  collapsing, and the `jitml-negative-controls` `conv2d-not-dense` gate now runs
  a genuine 3×3 convolution.

### Convergence go/no-go — GO

The dry median(k=5) for `cifar10-vit` was run through the production path
(`Architecture.architectureSpecForProblem` → `VisionTransformerFamily`,
`trainCanonicalArchitectureWithDeviceSelected` on the real oneDNN device, the
SHA-verified canonical CIFAR-10 binary archive, the current product budget of
2000 train / 5 epochs / batch 128 / lr `1.5e-3`), with a held-out 500-example
validation slice for epoch selection and the disjoint 1000-example CIFAR-10 test
split for the reported accuracy. The five seeds returned `0.275, 0.279, 0.281,
0.287, 0.275` for a **median `0.279`**, clearing the `0.25` effective bar under
the current regime with no warmup/cosine mitigation required — **GO**. The
measurement was run in-container against real oneDNN with no cluster (a
throwaway harness driving the production `Architecture` training path over the
on-disk canonical CIFAR-10 archive); Sprint `24.2` owns the permanent per-row
convergence-validation harness.

The vacuous-bar realness holes are resolved in
`src/JitML/SL/ConvergenceThresholds.hs`: `tiny-imagenet-resnet50`'s slack was
tightened (`0.64 → 0.62`) so its effective bar is `0.02` (above the `1/200`
random floor) rather than the vacuous `0.00`; `cifar100-wide-resnet`'s `0.04`
was confirmed above its `1/100` floor. A permanent anti-vacuity invariant
(`slBarIsNonVacuous`, requiring every effective bar to exceed its
random-classification baseline) is enforced by a `jitml-sl-canonicals` unit
assertion.

### Deferred to Sprint 23.3 (not a Sprint 23.1 gap)

- **Served-path Tier-2 wiring + the attention residual add.** The executed
  supervised operators are byte-frozen against the Sprint `10.6` V2 contract:
  `test/unit/SupervisedRuntimeArtifact.hs` asserts the generated CPU token-mix
  and attention execute the **exact pre-23.1 semantics** and explicitly that the
  token-mix **"must not add an implicit residual."** Landing the attention
  residual add (`Y = X + O`), dropping the spurious outer `tanh`, and wiring the
  verified Tier-2 nodes into the executed/serialized path therefore require a
  checkpoint format version bump and are owned by Sprint `23.3`; the decorative
  `archLayerGraph` and the executed `[LayerState]` path remain until then.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Sprint 23.1 Validation Evidence

Landed 2026-07-22 on `linux-cpu` (in the `jitml:local` container): `jitml-unit`
passed **763 / 763** (24 new Sprint 23.1 per-node parameter+input
finite-difference cases covering all fourteen catalog nodes, full ResNet-shaped
and ViT-shaped composed graphs, and four explicit shape/operation-failure
controls); `jitml-negative-controls` passed **3 / 3** (including the
real-convolution `conv2d-not-dense` gate); `jitml-model-convergence` passed
**111 / 111**; `jitml docs check` and `jitml check-code` both exited `0`. The
convergence go/no-go returned **GO** (`cifar10-vit` median(k=5) `0.279 ≥ 0.25`,
see [Convergence go/no-go — GO](#convergence-gono-go--go)) and the vacuous
`tiny-imagenet-resnet50` / `cifar100-wide-resnet` bars were resolved with a
permanent anti-vacuity invariant asserted in `jitml-sl-canonicals`. The
served-path Tier-2 wiring and the attention residual add remain owned by Sprint
`23.2` (byte-frozen pre-23.1-semantics contract).

### Historical Validation

The initial 2026-07-02 validation was withdrawn by the 2026-07-05 realness
audit because its oracle shared the dense stand-in. The 2026-07-06 reclosure
replaced that stand-in with kind-specific forward/backward transforms,
normalization, pooling, attention/gating, patch, and residual semantics and
reran the unit and canonical-SL gates recorded in [Phase State](#phase-state).
The cross-row mutation proof is now a separate downstream contract obligation
owned by Phase `32`; it does not turn the retired dense alias into current
Phase `23` state.

### Closure Evidence

Closed 2026-08-14 from one source state, inside `jitml:local`:

- `jitml lint haskell` → `ok`.
- `jitml docs check` → `ok`.
- `jitml test jitml-unit --linux-cpu` → **883 / 883 passed**, including the
  six-case "Fail-closed architecture resolution (Phase 233)" group.
- `jitml test jitml-sl-canonicals --linux-cpu` → the canonical rows still build
  and train their literal graphs.
- `jitml check-code` → `ok`.

### Completed in this sprint

- `src/JitML/SL/Canonicals.hs`: `ArchitectureFamily` moved here so a
  `CanonicalProblem` carries its executed `problemFamily` as a closed value.
  `problemModel` stays as the wire-facing name; a unit case asserts the two
  agree for every canonical row, so the carried family cannot drift from it.
- `familyForModel` returns `Maybe ArchitectureFamily`. It is no longer on the
  executed path at all — it survives as the wire-boundary parser and as that
  drift guard.
- `architectureClaimedFeaturesForProblem` switches on the family, total, with no
  `_ -> [FeatureDense]` arm.
- `graphNodes`, `architectureLayerGraphForFamily`, `architectureSpecForProblem`,
  and `allCanonicalArchitectureSpecs` return `Either Text`. The former
  `fallbackIdentity` — which substituted a parameterless `IdentityOp` for any
  rejected node — and `literal = fromRight legacyGraph` are both deleted.
- `LayerGraph.weightPlan`'s `_ -> []` replaced by explicit `DenseOp`,
  `IdentityOp`, `DropoutOp`, and `PoolOp` arms. Its entry in
  `failOpenPendingRegistry` (which named Sprint `233.1` as owner) is dropped;
  the Phase `7` lint detected the stale registration itself.
- `layerCountForFamily` gives seed-headroom bounds a total layer count without
  building a spec, with a unit case pinning it to the built topology.

The remaining `failOpenPendingRegistry` entries are all owned by Sprint `241.1`.

### Deferred with a named owner

Consuming the Dhall-described graph that Sprint `77.1` landed
(`LayerGraphDescription` / `buildLayerGraph`) is the natural continuation of
this sprint's third bullet, but the canonical architectures are still built by
Haskell topology functions parameterised on the training config's widths.
Migrating them to described data is Phases `242`–`244`'s literal-architecture
work, which owns the per-family topologies; this sprint owns making every path
to those topologies fail closed.

### Historical Phase State

> ✅ **Done**.

*(Retained as historical evidence for the surface it exercised; superseded by the 2026-08-12 reopen above.)*

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
