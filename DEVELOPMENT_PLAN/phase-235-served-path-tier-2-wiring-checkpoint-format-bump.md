# Phase 235: Served-Path Tier-2 Wiring + Checkpoint Format Bump

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Served-Path Tier-2 Wiring + Checkpoint Format Bump. Single-session phase migrated from legacy Sprint 23.3 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

⏸️ **Blocked**. Blocked by Phase 234 (Sprint 234.1).

## Sprint 235.1: Served-Path Tier-2 Wiring + Checkpoint Format Bump [⏸️ Blocked]

**Status**: Blocked
**Implementation**: `src/JitML/SL/Architecture.hs`, `src/JitML/Checkpoint/Format.hs`, `src/JitML/Checkpoint/Store.hs`, `src/JitML/SL/RuntimeArtifact.hs`, `test/unit/SupervisedRuntimeArtifact.hs`, `test/integration/Main.hs`
**Blocked by**: Sprint `234.1`
**Docs to update**: `../documents/engineering/checkpoint_format.md`, `../documents/engineering/numerical_core.md`

### Objective

Wire the Sprint `233.1` verified Tier-2 autodiff nodes and the attention residual
add into the executed and serialized supervised path. Sprint `127.1` froze the
current served operators byte-for-byte (`test/unit/SupervisedRuntimeArtifact.hs`
asserts the generated CPU token-mix/attention execute the exact pre-23.1
semantics and "must not add an implicit residual"), so admitting the correct
nodes requires a checkpoint format version bump behind that frozen V1 boundary.

### Deliverables

- The executed supervised graph replaces the decorative `archLayerGraph` plus the
  parallel `[LayerSpec]` / `[LayerState]` program with the one typed `LayerGraph`
  IR, so training, inference, and graph-ordered parameter identity have a single
  owner.
- The served attention operator adds the transformer residual (`Y = X + O`) and
  drops the spurious outer `tanh`/`SiLU`; the served token-mix and normalization
  operators execute the Sprint `233.1` correct forward/backward.
- A new checkpoint format version serializes the Tier-2 operator nodes and their
  multi-tensor parameters; the frozen V1 SHA-256 fingerprint stays
  byte-compatible for existing product-row checkpoints, and the pre-23.1-semantics
  guards are updated in lockstep to assert the new residual-bearing semantics
  under the bumped version while V1 admission is unchanged.

### Remaining Work

- Land the format version bump and served-path unification without breaking V1
  admission of the frozen product-row checkpoints.
- Re-run the `jitml-sl-canonicals` convergence lane to re-baseline the rows whose
  served numerics change (attention residual, dropped `tanh`).

### Validation

```bash
docker compose run --rm jitml jitml test jitml-integration --linux-cpu
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml test jitml-sl-canonicals --linux-cpu
docker compose run --rm jitml jitml check-code
```

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
