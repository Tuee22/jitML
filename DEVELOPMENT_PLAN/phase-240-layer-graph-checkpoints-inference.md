# Phase 240: Layer-Graph Checkpoints + Inference

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Reload the single supervised-graph checkpoint envelope and execute the reloaded typed `LayerGraph` for inference, with strict refinement and tamper rejection.

## Phase State

⏸️ **Blocked**. Blocked by Phase 239 (Sprint 239.1). With the envelope
(Phase `235`), unified admission (Phase `236`), IR serving/training
(Phases `237`–`238`), and graph-fed construction (Phase `239`) in place, the
inference read path executes the reloaded graph directly. See the old→new
renumber map in [README.md](README.md).

## Sprint 240.1: Layer-Graph Checkpoints + Inference [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Sprint `239.1`
**Implementation**: `src/JitML/Numerics/LayerGraphOneDnn.hs`, `src/JitML/Engines/Local.hs`, `src/JitML/Inference/Command.hs`, `test/integration/Main.hs`
**Docs to update**: `../documents/engineering/checkpoint_format.md`, `../documents/engineering/determinism_contract.md`

### Objective

Execute inference by reloading the supervised-graph payload of the single
envelope and running the reloaded typed `LayerGraph` — there is no separate
served representation to reconstruct. The reloaded graph is refined (topology,
typed shapes, edges, operations, and stable node/parameter identities validated),
then executed through `runLayerGraphForwardOneDnn` on the Phase `234` batched
oneDNN primitives. Tamper, shape, or operation inconsistencies fail closed.

### Deliverables

- Graph refinement rejects duplicate nodes, dangling edges, impossible shapes,
  unknown operations, and parameter identities inconsistent with the graph.
- `runLayerGraphForwardOneDnn` executes the refined, reloaded graph and its
  parameters; the inference read path (`Engines/Local.hs`,
  `Inference/Command.hs`) resolves the latest supervised-graph envelope and serves
  predictions from the executed graph — no `SupervisedRuntime` executor and no
  fallback graph.
- An integration case reloads a supervised-graph checkpoint end to end and
  asserts the served predictions match the trained graph, with strict rejection
  of a tampered envelope.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-integration --linux-cpu
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

## Documentation Requirements

**Engineering docs to create/update:**

- `../documents/engineering/checkpoint_format.md` — the inference-only read path
  executes the reloaded graph from the single envelope.
- `../documents/engineering/determinism_contract.md` — reloaded-graph execution
  determinism.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
