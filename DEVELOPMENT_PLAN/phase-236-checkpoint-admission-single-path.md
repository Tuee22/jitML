# Phase 236: Checkpoint Admission Single-Path

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Collapse the checkpoint store's version-gated admission into a single path that dispatches on the envelope's typed payload variant.

## Phase State

✅ **Done** (closed 2026-07-27). The store's per-version admission allow-list and
the `validateCompletedAdmissionScope` V1/V2 split are collapsed onto a single
decode-then-classify path over the typed `RawCheckpointBody` payload variant, and
the dormant `LayerGraph`-from-checkpoint reconstruction chain is deleted. Phase
`237` (supervised serving on the Layer-Graph IR) is the next frontier — it also
inherits the removal of the live V2 `SupervisedRuntime` read/serving path (an
ownership transfer, see [Deliverables](#deliverables)); see the old→new renumber
map in [README.md](README.md).

## Sprint 236.1: Checkpoint Admission Single-Path [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Checkpoint/Store.hs`, `test/unit/Main.hs`, `test/unit/SupervisedCheckpointV2.hs`
**Docs to update**: `../documents/engineering/checkpoint_format.md`

### Objective

Retire the version allow-list and the dual admission-scope validators in the
checkpoint store, replacing them with one admission path that reads the single
envelope once and distinguishes the two payload variants — weight-only (an RL,
AlphaZero, or tuning row, admitted against its ProductRow companion pointer) and
supervised-graph (a supervised row, admitted with no companion). The dormant
`LayerGraph`-from-checkpoint reconstruction helpers are deleted. Removal of the
live V2 `SupervisedRuntime` read/serving path is transferred to Phase `237`
(rule M(a) ownership transfer): that function still backs the Local/CUDA/Metal
engines' serving until Phase `237` rewires serving onto the IR, so it cannot be
deleted here without breaking serving.

### Deliverables

- `src/JitML/Checkpoint/Store.hs` exposes one admission path: the per-version
  allow-list and the `validateCompletedAdmissionScope` V1/V2 split collapse to a
  single decode-then-classify on the payload variant, preserving the weight-only
  vs supervised-graph distinction and their companion-pointer rules.
- The dormant `layerGraphFromCheckpoint` / `rebuildLayerGraph` helpers (and their
  `layerKind`/`Mode`/`Activation`/`ParametersFromMetadata` chain), the
  `JitML.Engines.LayerGraphCheckpoint` module, and the `Local.hs` graph-rebuild
  serving fallback are removed (recorded in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) under this
  sprint). Removal of the live V2 `SupervisedRuntime` read/serving path
  (`loadSupervisedRuntimeFromCheckpoint`) is **transferred to Phase `237`**, where
  supervised serving is rewired onto the IR — it cannot be deleted here without
  breaking the Local/CUDA/Metal engines' serving.
- Unit tests admit one weight-only and one supervised-graph envelope through the
  single path, and reject a supervised-graph envelope carrying a companion
  pointer (and a weight-only envelope missing one).

### Closure Evidence

`src/JitML/Checkpoint/Store.hs` now admits through one path:
`decodeAddressedForAdmission` carries no per-version allow-list, and
`validateCompletedAdmissionScope` classifies once on the payload variant —
supervised-graph is admissible only with no companion pointer, weight-only routes
through the authoritative-ProductRow-companion rules. The dormant
`layerGraphFromCheckpoint` chain, `JitML.Engines.LayerGraphCheckpoint`, and the
`Local.hs` graph-rebuild fallback are deleted (they never fired for real rows,
whose `architectureLayerGraph` is `Nothing`). `test/unit/SupervisedCheckpointV2.hs`
adds the supervised-graph companion-rejection test; existing
`CheckpointV1Admission` and Store-admission tests cover weight-only admit/missing-
companion and supervised-graph admit. Validated by the `### Validation` gate below
(`jitml test jitml-unit --linux-cpu`, `jitml check-code`, `jitml docs check`).

### Validation

```bash
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml check-code
docker compose run --rm jitml jitml docs check
```

## Documentation Requirements

**Engineering docs to create/update:**

- `../documents/engineering/checkpoint_format.md` — update the admission /
  inference-eligibility sections to the single payload-classifying path.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
