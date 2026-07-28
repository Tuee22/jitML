# Phase 235: One Self-Describing Checkpoint Envelope

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Collapse the V1/V2/V3 checkpoint wire versions into a single self-describing envelope carrying a typed payload variant, retiring the byte-freeze and the parallel canonicalizers.

## Phase State

✅ **Done** (closed 2026-07-27). The checkpoint wire is consolidated into one
self-describing envelope carrying the typed `RawCheckpointBody` payload sum
(weight-only vs supervised-graph); the byte-freeze golden, the dead V3
`LayerGraph` encoder, the retained legacy decoder, and the parallel canonicalizer
are retired. This anchors the IR-single-owner redesign before
serving/training/construction land on the typed `LayerGraph` IR in Phases
`237`–`239`. Phase `236` (checkpoint admission single-path) is the next frontier;
see the dated renumber note and old→new map in [README.md](README.md).

## Sprint 235.1: One Self-Describing Checkpoint Envelope [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Checkpoint/Format.hs`, `test/unit/SupervisedCheckpointV2.hs`, `test/unit/Main.hs`
**Docs to update**: `../documents/engineering/checkpoint_format.md`, `../documents/engineering/determinism_contract.md`

### Objective

Replace the three accreted checkpoint wire versions — V1 (byte-frozen, SHA-256
`30db4da5…`), V2 (supervised, embedding the `SupervisedRuntime`), and the dead V3
`LayerGraph` encoder — with **one** self-describing outer envelope carrying a
typed payload sum. Every one of the 55 product rows serializes through the single
envelope; the multi-version dispatch, the dual canonicalizers, and the byte-freeze
golden are removed, because checkpoints are regenerated deterministically from
current source (no persisted bytes are reinterpreted).

### Deliverables

- `src/JitML/Checkpoint/Format.hs` defines one outer envelope and a payload sum
  with two variants — a weight-only payload (RL, AlphaZero, tuning) and a
  supervised-graph payload carrying the trained typed `LayerGraph`. `encodeManifestCbor`
  collapses to a single arm, `decodeAddressedManifestCbor` to a single decode
  (the V2→V1→legacy cascade is deleted), and `canonicalManifest` /
  `canonicalManifestV2` collapse to one canonicalizer.
- The frozen-V1 golden encoder and the dead `RawV3*` DTOs /
  `encodeV3Checkpoint` / `decodeV3Checkpoint` are deleted; the byte-freeze
  contract is retired and product checkpoints are republished deterministically
  under the one envelope.
- Round-trip unit tests prove a weight-only payload and a supervised-graph
  payload each survive encode/decode exactly, and that a supervised-graph
  envelope is never mis-decoded as weight-only (or vice versa).
- The retired multi-version wire, byte-freeze golden, and canonicalizer pair are
  recorded in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) under this
  sprint.

### Closure Evidence

All [Deliverables](#deliverables) are met. `src/JitML/Checkpoint/Format.hs`
defines one `RawCheckpointEnvelope` carrying the typed `RawCheckpointBody`
payload sum (`RawWeightOnlyBody` vs `RawSupervisedGraphBody`); `encodeManifestCbor`
is a single arm, `decodeAddressedManifestCbor` a single decode that dispatches on
the payload sum with no version cascade, and `canonicalManifest` is the one
canonicalizer. The frozen-V1 golden (SHA `30db4da5…`) and its byte-freeze, the
dead `RawV3*` / `encode`/`decodeV3Checkpoint` DTOs, and the retained legacy
decoder cascade are deleted. `test/unit/SupervisedCheckpointV2.hs` proves a
weight-only payload and a supervised-graph payload each round-trip exactly and
that the two variants are never mis-classified; the removed surfaces are recorded
in [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) under this
sprint. Validated by the `### Validation` gate below (`jitml test jitml-unit
--linux-cpu` **771 / 771**, `jitml check-code`, `jitml docs check`).

### Validation

```bash
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml check-code
docker compose run --rm jitml jitml docs check
```

## Documentation Requirements

**Engineering docs to create/update:**

- `../documents/engineering/checkpoint_format.md` — rewrite the version model to
  one envelope + payload sum; **rename** the `## Frozen V1 and Exact Supervised V2`
  heading (e.g. to `## The Self-Describing Checkpoint Envelope`) and update the
  four deep-linkers (`run_contract.md`, `determinism_contract.md`,
  `training_workloads.md`, `product_completion_contract.md`) plus their
  `Referenced by` lines.
- `../documents/engineering/determinism_contract.md` — fold the V1/V2 origin
  determinism into the single-envelope contract.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
