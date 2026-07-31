# Phase 240: Layer-Graph Checkpoints + Inference

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Reload the single supervised-graph checkpoint envelope and execute the reloaded typed `LayerGraph` for inference, with strict refinement and tamper rejection.

## Phase State

✅ **Done** (closed 2026-07-30; gate-validated on the live linux-cpu cluster).
The inference read path reloads the single supervised-graph checkpoint envelope
and executes the reloaded typed `LayerGraph` on the device via
`runLayerGraphForwardOneDnn` (device fp32); refinement fails closed on tamper,
shape, and parameter-count inconsistencies. The admitted-inventory-55 and
tamper-rejection integration cases pass.

## Sprint 240.1: Layer-Graph Checkpoints + Inference [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Numerics/LayerGraphOneDnn.hs`, `src/JitML/Engines/Local.hs`, `src/JitML/Inference/Command.hs`, `test/integration/Main.hs`
**Docs to update**: `../documents/engineering/checkpoint_format.md`, `../documents/engineering/determinism_contract.md`

### Objective

Execute inference by reloading the supervised-graph payload of the single
envelope and running the reloaded typed `LayerGraph` — there is no separate
served representation to reconstruct. The reloaded graph is refined (topology,
typed shapes, edges, operations, and stable node/parameter identities validated)
by `refineReloadedLayerGraph`, then executed through the pure reference executor
`LayerGraph.runLayerGraph` (via `RuntimeArtifact.executeSupervisedGraphRuntime`),
which handles every correct operator and is substrate-independent. Tamper, shape,
or parameter-count inconsistencies fail closed.

### Deliverables

- Graph refinement rejects duplicate nodes, dangling edges, impossible shapes,
  and parameter identities inconsistent with the graph, while serving every
  correct operator (conv/norm/attention/geglu/patch/residual/block, not only
  dense).
- The pure reference executor `LayerGraph.runLayerGraph` (via
  `RuntimeArtifact.executeSupervisedGraphRuntime`) executes the refined, reloaded
  graph and its parameters; the inference read path (`Engines/Local.hs`,
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

### Closure Evidence

Validated 2026-07-30 (container `jitml:local`, live linux-cpu cluster):
jitml-backends 35/35, jitml-unit passed (0 failures, incl. the Product phase
status registry guard and the reloaded-graph serving tests), jitml-sl-canonicals
36/36, jitml-integration 157/157 (incl. "ProductRow admitted-inventory-55 is
exact and unique" and "Phase 240: linux-cpu serves the reloaded supervised
graph …"), `jitml check-code` ok, `jitml docs check` ok, and
`jitml internal train-and-publish-product-rows --linux-cpu` exit 0 with 55/55
admitted.

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
