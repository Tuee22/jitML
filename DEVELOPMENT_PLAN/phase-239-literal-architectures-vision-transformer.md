# Phase 239: Literal Architectures - Vision Transformer

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Literal Architectures - Vision Transformer. Single-session phase migrated from legacy Sprint 24.3 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

⏸️ **Blocked**. Blocked by Phase 238 (Sprint 238.1).

## Sprint 239.1: Literal Architectures - Vision Transformer [⏸️ Blocked]

**Status**: Blocked
**Implementation**: `src/JitML/SL/Architecture.hs`, `src/JitML/Product/Matrix.hs`, `test/sl-canonicals/Main.hs`
**Blocked by**: Sprint `238.1`
**Docs to update**: `../documents/engineering/training_workloads.md`, `../documents/engineering/numerical_core.md`, `../README.md`

### Objective

The small ViT is constructed as a literal layer graph over the Phase `233` typed
layer engine — patch embedding, multi-head self-attention, GeGLU, and LayerNorm —
so the `cifar10-vit` row is its named Transformer architecture rather than a
widened patch/MLP-Mixer approximation.

### Deliverables

- The small ViT is built in `src/JitML/SL/Architecture.hs` as a literal layer
  graph with real patch embedding, multi-head self-attention, GeGLU feed-forward
  blocks, and LayerNorm at the documented depth and head count.
- The `cifar10-vit` row in `src/JitML/Product/Matrix.hs` binds to the
  constructing function and records the concrete architectural features it claims
  (attention, LayerNorm, patch embedding).
- A test rejects the `cifar10-vit` row when its documented feature set exceeds the
  implemented layer graph; no simplified topology satisfies a row naming ViT,
  attention, or LayerNorm.

### Remaining Work

- Implement the small ViT as its literal named architecture on the single
  executable Sprint `235.1` graph, including real patch/attention structure rather
  than a shared patch/MLP-Mixer approximation, and retire the untrained
  `architectureLayerGraphForFamily` parity stand-in so the completion boundary
  receives the graph that training executed.
- Bind the registry's claimed attention/LayerNorm features to that executed
  graph, and make a simplified or mislabeled topology fail the production-path
  test.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-sl-canonicals --linux-cpu
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml check-code
```

### Historical Closure Evidence (withdrawn by the 2026-07-18 audit)

- **Target Exit-Definition obligation**: each supervised row must be its literal
  named architecture on the *trained* path — real `Conv2D`/pooling and
  BatchNorm for LeNet-5, real residual convolutional blocks at the documented
  depths/widths for the small ResNet, ResNet-20, ResNet-56, and WideResNet-28-10,
  a genuinely distinct ResNet-50 bottleneck, and real patch-embedding plus
  self-attention for the ViT — not a residual-MLP over flattened pixels shared
  across families.
- Build the real topology in `src/JitML/SL/Architecture.hs` and train *that*
  graph, retiring the untrained `architectureLayerGraphForFamily` parity
  stand-in so the completion boundary receives the graph that training
  executed.
- **Closing validation**: the "dense layer labelled as convolution must be
  rejected" differential control and the untrained-graph controls in the
  `jitml-negative-controls` stanza (Phase `271`,
  [phase-32-external-truth-realness-harness.md](README.md#legacy-to-new-phase-map))
  must reject the current MLP-for-conv stand-in, exercised via
  `docker compose run --rm jitml jitml test jitml-negative-controls --linux-cpu`.

Historical 2026-07-10 closure claim: the trained architecture path implemented
the widened Mixer blocks and raised clamps then treated as the expanded end
state, and
`jitml-sl-canonicals --linux-cpu` passed **31 / 31**. The contemporaneous served
path claim is historical. Sprint `127.1` revalidates trained-versus-loaded V2
parity only for the exact current executable; it does not restore the withdrawn
literal-architecture claim.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
