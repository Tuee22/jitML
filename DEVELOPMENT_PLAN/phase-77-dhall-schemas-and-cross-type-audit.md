# Phase 77: Dhall Schemas and Cross-Type Audit

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Dhall Schemas and Cross-Type Audit. Single-session phase migrated from legacy Sprint 6.6 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done** (closed 2026-08-14). The layer vocabulary is a __parameterised Dhall
union reflected off the real decoder__: `dhall/numerics/LayerOp.dhall` and
`dhall/numerics/LayerGraph.dhall` are read back off the live `Dhall.Decoder`
with `Dhall.expected`, are tracked generated paths, and carry each operator's
real geometry rather than a bare constructor name. The cross-type audit now
covers the executed `LayerOp` — the reflected union's alternatives are exactly
the `LayerOp` constructors, each projecting onto exactly one `Catalog.Layer` —
and `decode . render` is the identity over every operator witness.
`LayerGraphDescription` makes a whole architecture data, and `buildLayerGraph`
fails closed on a description whose declared shapes disagree with the geometry
its operators produce. `substrate` is absent from every ML-describing Dhall file
and a standing lint rule keeps it out.

## Sprint 77.1: Dhall Schemas and Cross-Type Audit [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Numerics/LayerDhall.hs`,
`src/JitML/Dhall/Reflect.hs`, `src/JitML/Numerics/LayerGraph.hs`,
`src/JitML/Numerics/Catalog.hs`, `src/JitML/Lint/DhallNumerics.hs`,
`src/JitML/Service/DhallSchema.hs`, `src/JitML/Generated/Paths.hs`,
`dhall/numerics/LayerOp.dhall`, `dhall/numerics/LayerGraph.dhall`,
`experiments/`, `test/unit/Main.hs`
**Docs to update**: `../documents/engineering/numerical_core.md`

### Objective

Make the numerical Dhall surface a projection of the executed vocabulary rather
than a hand-maintained name list beside it: every layer is a first-class
parameterised Dhall constructor carrying its real geometry, the schema is
reflected off the decoder that reads it, and the cross-type audit covers the
operator that actually executes.

### Deliverables

- `experiments/mnist.dhall`, `experiments/mnist-tune.dhall`, and
  `experiments/cartpole.dhall` are present as the current configuration-as-code
  fixtures.
- `dhall/numerics/Schema.dhall` re-exports the current constructor-name lists
  for layers, activations, spectral ops, optimizers, schedulers, and losses.
- `src/JitML/Numerics/Schema.hs` decodes the Dhall schema and validates it
  against the Haskell catalog.
- `src/JitML/Numerics/LayerDhall.hs` expresses `LayerOp` as a parameterised
  Dhall union — each alternative carries the operator's real geometry
  (convolution input/kernel/stride/padding dimensions, pooling window,
  normalization flavor and channel counts, attention sequence length, embedding
  width and head count, GeGLU and patch widths, residual and block topology) —
  and decodes it back to the executed operator.
- `dhall/numerics/LayerOp.dhall` and `dhall/numerics/LayerGraph.dhall` are
  emitted from those decoders through `Dhall.expected`, never hand-written, and
  are registered as tracked generated paths (`numerics.layer-op.schema`,
  `numerics.layer-graph.schema`) so `jitml docs check` fails on drift.
- `src/JitML/Dhall/Reflect.hs` owns the two reflection primitives
  (`reflectedSchemaText`, `canonicalDhallType`) shared by the numerical DSL and
  the daemon config surfaces, so the convention is stated once.
- `LayerGraph.layerOpName` is total over `LayerOp`, so a new operator fails
  `-Werror=incomplete-patterns` there exactly as it does in `opKind` / `opLayer`
  and the Dhall vocabulary cannot fall behind the executed set.
- `LayerGraphDescription` describes a whole architecture as data — named nodes,
  declared shapes, mode, activation, and the seed that fixes deterministic
  initialization. `buildLayerGraph` realizes it through the correctness-checked
  smart constructors (`layerNodeFromOp` is total over `LayerOp`) and fails
  closed on a declared shape that disagrees with the operator's real geometry,
  on nodes that do not chain, and on graph ends that do not match.
- `src/JitML/Lint/DhallNumerics.hs` plugs four rules into `jitml lint haskell`:
  catalog drift, executed-operator drift, reflected-type-file drift, and
  `substrate` appearing in an ML-describing Dhall file.

### Validation

1. The three current `experiments/*.dhall` fixtures exist in the worktree.
2. The catalog is renderable through `renderNumericalCatalog`.
3. `jitml test jitml-unit --linux-cpu` passes, including the nine-case
   "Layer vocabulary as parameterised Dhall (Phase 77)" group.
4. `jitml lint haskell` includes the Dhall numerical drift audit, now extended
   to the executed operator, the reflected type files, and the ML-DSL substrate
   rule.
5. `jitml docs check` reports `ok`, including the two new tracked generated
   paths.
6. `jitml check-code` exits `0` inside `jitml:local`.

### Closure Evidence

Closed 2026-08-14 from one source state, inside `jitml:local`:

- `jitml lint haskell` → `ok`, with the audit extended to the executed operator,
  the reflected type files, and the ML-DSL substrate rule.
- `jitml docs check` → `ok`, including the two new tracked generated paths.
- `jitml test jitml-unit --linux-cpu` → **855 / 855 passed**, including the
  nine-case "Layer vocabulary as parameterised Dhall (Phase 77)" group.
- `jitml check-code` → `ok` (fourmolu, hlint, docs, chart, PureScript, plus the
  warning-clean `cabal build all --ghc-options=-Werror`).

### Completed in this sprint

- `src/JitML/Numerics/LayerDhall.hs` (new): the parameterised `LayerOp` decoder
  and every nested spec decoder; the `LayerNodeDescription` /
  `LayerGraphDescription` architecture-as-data surface; `buildLayerGraph` and
  the total `layerNodeFromOp` dispatcher; `renderLayerOp` /
  `renderLayerGraphDescription` as the writer half; and
  `layerOpAuditMismatches`, which reads the union's alternatives out of the
  reflected expression rather than restating them.
- `src/JitML/Dhall/Reflect.hs` (new): `reflectedSchemaText` and
  `canonicalDhallType` lifted out of `JitML.Service.DhallSchema`, which now
  imports and re-exports them, so the numerical DSL reflects its schema through
  the same primitive as `BootConfig` instead of a copy.
- `src/JitML/Numerics/LayerGraph.hs`: `layerOpName` added and exported.
- `src/JitML/Service/DhallSchema.hs`: `configSchemas` gains the `LayerOp` and
  `LayerGraph` entries, so `jitml internal dhall-schema --config LayerOp`
  prints the reflected ML vocabulary.
- `src/JitML/Generated/Paths.hs`: the two reflected numerical type files are
  tracked generated paths.
- `src/JitML/Lint/DhallNumerics.hs`: the audit extended from one rule to four,
  plus `mlDslDhallFiles` naming the ML-describing file set
  (`dhall/numerics`, `experiments`) — deliberately excluding `dhall/service`,
  `dhall/cluster`, and `dhall/run`, which are the plan/CLI seam and legitimately
  carry a substrate.
- `test/unit/Main.hs`: the "Layer vocabulary as parameterised Dhall (Phase 77)"
  group — audit cleanliness, the 28-witness `decode . render == id` round trip,
  alternative coverage, checked-in-file parity, description round-trip plus
  execution, three fail-closed cases, and the ML-DSL substrate rule.

The architecture-as-data surface this sprint lands is what Phase `233` consumes
to retire the hardcoded literal builders; this sprint owns the vocabulary and
the audit, not the migration of the existing architectures onto it.

### Historical Validation

Evidence for the surface this sprint actually exercised before the 2026-08-12 reopen:

> ✅ **Done**.

## Documentation Requirements

**Engineering docs to create/update:**

- `../documents/engineering/numerical_core.md` — the new
  `Parameterized Layer Vocabulary` section.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
