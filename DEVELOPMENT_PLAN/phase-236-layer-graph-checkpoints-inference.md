# Phase 236: Layer-Graph Checkpoints + Inference

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Layer-Graph Checkpoints + Inference. Single-session phase migrated from legacy Sprint 23.4 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

⏸️ **Blocked**. Blocked by Phase 235 (Sprint 235.1).

## Sprint 236.1: Layer-Graph Checkpoints + Inference [⏸️ Blocked]

**Status**: Blocked
**Implementation**: `src/JitML/Checkpoint/Format.hs`, `src/JitML/Checkpoint/Store.hs`, `src/JitML/Inference/Decode.hs`, `src/JitML/Engines/LayerGraphCheckpoint.hs`, `src/JitML/Engines/Local.hs`, `test/integration/Main.hs`
**Blocked by**: Sprint `235.1`
**Docs to update**: `../documents/engineering/checkpoint_format.md`, `../documents/engineering/determinism_contract.md`

### Objective

Provide layout-independent layer-graph metadata/refinement and a graph-forward
runner that a strict checkpoint runtime can consume. The retained V1 exercise
serialized the Phase `233.1` topology and reconstructed it from named per-node
tensors; that proves the graph primitive, not current supervised persistence or
inference eligibility. Sprint `127.1` owns the V2 physical layout, exact loaded
program, and no-fallback engine dispatch, while Sprint `133.1` owns persisted
admission.

### Deliverables

- `LayerGraphMetadata` represents topology, typed shapes, edges, operations,
  attributes, and stable node/parameter identities independently of whether a
  wire format uses named physical tensors or virtual slices into one flat blob.
- Graph refinement rejects duplicate nodes, dangling edges, impossible shapes,
  unknown operations, and parameter identities inconsistent with the graph.
- `JitML.Numerics.LayerGraphOneDnn.runLayerGraphForwardOneDnn` executes a
  supplied refined graph and parameters through the Phase `234.1` oneDNN
  primitives; it does not choose a checkpoint version, physical layout, or
  fallback policy.
- Unit coverage round-trips graph metadata and compares the refined graph runner
  with the per-kind reference algebra. The old named-tensor checkpoint case is
  retained as V1 inspection coverage only.

### Remaining Work

- Round-trip and execute the exact graph completed by Sprints `233.1` and
  `234.1`, preserving its operation order and parameter identities.
- Prove checkpoint reload and inference use that same graph with strict
  tamper/shape/operation rejection; no decorative metadata or fallback graph
  may satisfy the gate.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-integration --linux-cpu
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Historical Validation (retained primitive only)

`jitml-unit --linux-cpu` passed 270 / 270 on 2026-07-02,
including the LayerGraph checkpoint topology round-trip. The targeted
`jitml-integration` graph checkpoint inference case passed when run directly
with `cabal test jitml-integration --test-show-details=direct --test-options='-p loadInferenceCheckpointWithWeights'`.
`jitml docs check` and `jitml check-code` both passed after the Sprint `23.3`
implementation/docs update. After rebuilding `jitml:local` with Dockerfile
`check-code: ok`, deleting and recreating the `jitml-linux-cpu` Kind cluster,
and running `jitml cluster up --substrate linux-cpu` with
`JITML_BOOTSTRAP_SKIP_IMAGE_BUILD=1`, `jitml cluster status` reported every
component ready and `docker compose run --rm jitml jitml test jitml-integration
--linux-cpu` passed all 79 / 79 tests on 2026-07-02. The realness audit then
withdrew the inference claim until Sprints `23.1`/`23.2` corrected the per-kind
forward path. Those results predate V2 and do not establish the current
supervised physical layout, strict loaded execution, or eligibility. Sprint
`10.6` and Sprint `10.12` own those current obligations.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
