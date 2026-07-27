# Phase 236: Checkpoint Admission Single-Path

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Collapse the checkpoint store's version-gated admission into a single path that dispatches on the envelope's typed payload variant.

## Phase State

⏸️ **Blocked**. Blocked by Phase 235 (Sprint 235.1). Once the single envelope
exists, the store's admission gates and load paths are unified onto it; see the
old→new renumber map in [README.md](README.md).

## Sprint 236.1: Checkpoint Admission Single-Path [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Sprint `235.1`
**Implementation**: `src/JitML/Checkpoint/Store.hs`, `test/unit/Main.hs`, `test/unit/SupervisedCheckpointV2.hs`
**Docs to update**: `../documents/engineering/checkpoint_format.md`

### Objective

Retire the version allow-list and the dual admission-scope validators in the
checkpoint store, replacing them with one admission path that reads the single
envelope once and distinguishes the two payload variants — weight-only (an RL,
AlphaZero, or tuning row, admitted against its ProductRow companion pointer) and
supervised-graph (a supervised row, admitted with no companion). The dormant
`LayerGraph`-from-checkpoint reconstruction helpers and the V2 `SupervisedRuntime`
load path are deleted.

### Deliverables

- `src/JitML/Checkpoint/Store.hs` exposes one admission path: the per-version
  allow-list and the `validateCompletedAdmissionScope` V1/V2 split collapse to a
  single decode-then-classify on the payload variant, preserving the weight-only
  vs supervised-graph distinction and their companion-pointer rules.
- The dormant `layerGraphFromCheckpoint` / `rebuildLayerGraph` helpers and the V2
  `SupervisedRuntime` load path are removed (recorded in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) under this
  sprint).
- Unit tests admit one weight-only and one supervised-graph envelope through the
  single path, and reject a supervised-graph envelope carrying a companion
  pointer (and a weight-only envelope missing one).

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
