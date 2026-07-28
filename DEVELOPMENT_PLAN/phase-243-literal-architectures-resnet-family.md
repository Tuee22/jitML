# Phase 243: Literal Architectures - ResNet Family

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Literal Architectures - ResNet Family. Single-session phase migrated from legacy Sprint 24.2 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

⏸️ **Blocked**. Blocked by Phase 242 (Sprint 242.1).

## Sprint 243.1: Literal Architectures - ResNet Family [⏸️ Blocked]

**Status**: Blocked
**Implementation**: `src/JitML/SL/Architecture.hs`, `src/JitML/Product/Matrix.hs`, `test/sl-canonicals/Main.hs`
**Blocked by**: Sprint `242.1`
**Docs to update**: `../documents/engineering/training_workloads.md`, `../documents/engineering/numerical_core.md`, `../README.md`

### Objective

The small ResNet, ResNet-20, ResNet-56, WideResNet-28-10, and the ResNet-50
bottleneck are each constructed as literal layer graphs over the Phase `233` typed
layer engine, so each residual/bottleneck row is its named architecture rather
than a shared residual-MLP over flattened pixels.

### Deliverables

- The small ResNet, ResNet-20, ResNet-56, WideResNet-28-10, and the ResNet-50
  bottleneck are each built in `src/JitML/SL/Architecture.hs` as literal layer
  graphs with the documented block counts, channel widths, residual connections,
  normalization (BatchNorm / GroupNorm), and Conv2D/pooling structure, and the
  ResNet-50 bottleneck is a genuinely distinct topology rather than a reuse of
  the ResNet-20/ResNet-56 template.
- Each of these supervised rows in `src/JitML/Product/Matrix.hs` binds to its
  constructing function and records the concrete architectural features it claims
  (Conv2D, BatchNorm, GroupNorm, residual).
- A test rejects any of these rows whose documented feature set exceeds the
  implemented layer graph; no simplified topology satisfies a row naming ResNet,
  WideResNet, Conv2D, GroupNorm, or residual structure.

### Remaining Work

- Implement each residual/bottleneck row as its literal named architecture on the
  typed `LayerGraph` IR (trained via Phase `238`), including real convolution, pooling,
  normalization, and residual/bottleneck depth and width rather than a shared
  residual-MLP approximation.
- Bind the registry's claimed features and block counts to that executed graph,
  and make a simplified or mislabeled topology fail the production-path test.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-sl-canonicals --linux-cpu
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml check-code
```

### Historical Validation

2026-07-05 realness-audit finding, closed 2026-07-06: the layer graph previously built and trained
by `layersForFamily` (`src/JitML/SL/Architecture.hs`~`249`) is a residual-MLP
over flattened pixels for every ResNet, WideResNet, ResNet-50, and LeNet row — a
`Dense` stem, `N` two-layer `ResidualSpec` blocks (`Architecture.hs`:`261`), and
a `Dense` classifier — with no `Conv2D`, pooling, normalization, or attention on
the trained path, and `ResNet-50` (`familyForModel "ResidualBlock50"`,
`Architecture.hs`:`445`) reuses the `ResNet-20`/`ResNet-56` residual-MLP template
with no bottleneck topology. The simplified-topology negative case passes only
because it inspects `architectureLayerGraphForFamily`
(`Architecture.hs`:`484`,`:492`), which is never trained or served, so no
rejection actually guards the model that runs.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
