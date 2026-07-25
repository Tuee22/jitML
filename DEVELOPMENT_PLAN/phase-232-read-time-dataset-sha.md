# Phase 232: Read-Time Dataset SHA

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Read-Time Dataset SHA. Single-session phase migrated from legacy Sprint 22.3 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 232.1: Read-Time Dataset SHA [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/SL/Dataset.hs`, `src/JitML/App.hs`, `test/integration/Main.hs`, `test/sl-canonicals/Main.hs`
**Docs to update**: `../documents/engineering/training_workloads.md`, `../documents/engineering/training_metrics_and_splits.md`, `../documents/engineering/checkpoint_format.md`

### Objective

Every product dataset fetch verifies the pinned SHA at read time, not only at
upload time. The bytes handed to a decoder are the exact pinned bytes, and any
substituted, truncated, or corrupted payload fails closed with a typed error
before decode or training.

### Deliverables

- `src/JitML/SL/Dataset.hs` verifies the pinned dataset SHA when the bytes are
  read from MinIO or a local mirror, and `src/JitML/App.hs` routes every product
  training fetch through that read-time check before decode; upload-time
  verification alone no longer satisfies the boundary.
- Canonical dataset keys cannot be populated by synthetic tiny payloads in live
  workflow tests that claim product training evidence; such fixtures use test-only
  row ids or real verified data.
- Negative integration and canonical tests corrupt staged bytes and observe a
  typed fail-closed error (`test/integration/Main.hs`, `test/sl-canonicals/Main.hs`)
  before any decode or training step runs, and the checkpoint manifest records the
  read-time SHA observed for the row.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-integration --linux-cpu
docker compose run --rm jitml jitml test jitml-sl-canonicals --linux-cpu
docker compose run --rm jitml jitml check-code
```

**Result (2026-07-02)**:
- `docker compose run --rm jitml jitml test jitml-sl-canonicals --linux-cpu` —
  passed, 25 / 25 tests.
- `docker compose run --rm jitml jitml test jitml-integration --linux-cpu` —
  passed, 79 / 79 tests.
- `docker compose run --rm jitml jitml check-code` — passed.

### Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
