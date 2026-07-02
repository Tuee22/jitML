# Phase 22: Canonical Matrix & Dataset Integrity

**Status**: Blocked
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [development_plan_standards.md](development_plan_standards.md), [phase-21-type-state-dsl-and-inference-eligibility.md](phase-21-type-state-dsl-and-inference-eligibility.md), [phase-23-general-differentiable-layer-engine.md](phase-23-general-differentiable-layer-engine.md), [../documents/engineering/product_completion_contract.md](../documents/engineering/product_completion_contract.md), [../documents/engineering/training_workloads.md](../documents/engineering/training_workloads.md), [../documents/engineering/training_metrics_and_splits.md](../documents/engineering/training_metrics_and_splits.md), [../documents/engineering/checkpoint_format.md](../documents/engineering/checkpoint_format.md)
**Generated sections**: none

> **Purpose**: Make the documented model matrix, the typed Haskell registry, the
> Dhall experiment configs, and the verified dataset bytes one non-divergent
> surface.

## Phase State

⏸️ **Blocked by** Phase `21`. This phase starts only after inference eligibility
is a type-state property and training evidence is non-fabricable.

**Validation substrate**: `linux-cpu` only.

## Objective

The documented model matrix, the typed Haskell product registry, the checked-in
Dhall experiment configs, and the verified dataset bytes are one non-divergent
surface. Every README supervised, reinforcement-learning, AlphaZero, and tuning
row resolves to exactly one `ProductRow` in `src/JitML/Product/Matrix.hs`; every
product row carries a Dhall `experimentConfig` that runs through `jitml`; and
every product training fetch verifies the pinned dataset SHA at read time before
any decode or training step. A row cannot exist only in README prose, a
generated PureScript constant, or a test helper, and product training bytes
cannot be substituted, truncated, or corrupted without a typed fail-closed
error observed before decode.

## Sprint 22.1: Matrix Parity [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Phase `21`
**Implementation**: `src/JitML/Product/Matrix.hs`, `src/JitML/SL/Canonicals.hs`, `src/JitML/RL/ConvergenceThresholds.hs`, `test/unit/Main.hs`
**Docs to update**: `../README.md`, `../documents/engineering/training_workloads.md`

### Objective

The documented matrix and the typed registry compare equal in both directions.
README supervised rows, README reinforcement-learning environment rows, the RL
convergence algorithm/environment rows, AlphaZero games, and the tuning/demo
rows each resolve to exactly one `ProductRow` `rowId`, and every registry row is
documented.

### Deliverables

- A parity test compares the README supervised/reinforcement-learning/AlphaZero/
  tuning rows against `Product.Matrix` `rowId`s and fails on any documented row
  missing from the registry, any registry row missing from the docs, and any
  generated PureScript matrix constant that diverges from the registry.
- Missing reinforcement-learning environments (`Acrobot`, `GridWorld`,
  `Pendulum`) are explicit parity failures until a later real-RL-model phase
  implements them or they are typed as non-product rows; the parity test names
  each missing environment rather than passing vacuously.
- A row that is research-only or optional is typed as a non-product row and
  cannot appear in the product matrix, and mismatched algorithm/environment
  pairings surface as named failures.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Remaining Work

- Implement the bidirectional README-vs-registry parity test and the generated
  PureScript matrix comparison.
- Classify or schedule every missing/mismatched environment row so the parity
  scan reports its zero-tolerance count.

## Sprint 22.2: Per-Row Runnable Dhall [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Sprint `22.1`
**Implementation**: `experiments/mnist.dhall`, `experiments/cartpole.dhall`, `src/JitML/Experiment/Overrides.hs`, `test/unit/Main.hs`
**Docs to update**: `../documents/engineering/training_workloads.md`

### Objective

Every product row has a checked-in or reflected Dhall `experimentConfig` that is
addressable and runnable through `jitml`. A row's `experimentConfig` field in the
registry points at a config that resolves, type-checks, and drives the row's
training command without a missing-file reference.

### Deliverables

- Every `ProductRow` resolves an `experimentConfig` runnable through
  `jitml train`, `jitml rl train`, `jitml rl alphazero self-play`, or
  `jitml tune`, checked into `experiments/` or produced by a reflected config
  generator over the registry.
- A unit test loads and type-checks the config for every product row and fails on
  a row whose config is missing, unparseable, or references a non-existent
  dataset/environment key; generated command examples never reference a missing
  file.
- CLI overrides in `src/JitML/Experiment/Overrides.hs` apply to the resolved
  config without replacing the surrounding Dhall record, so a row runs with its
  documented defaults unless a flag overrides a single field.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Remaining Work

- Add or generate the missing per-row Dhall configs and wire each to its registry
  row.
- Add the load-and-type-check-per-row test and the override-preserves-record
  assertions.

## Sprint 22.3: Read-Time Dataset SHA [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Sprint `22.2`
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

### Remaining Work

- Replace unverified product fetches with SHA-checking reads at the read
  boundary.
- Replace canonical-key synthetic live fixtures with test-only row ids or real
  verified data.
- Add the corrupt-bytes negative tests and thread the read-time SHA into the
  checkpoint manifest.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/training_workloads.md` — canonical matrix, per-row Dhall
  config surface, and the read-time dataset SHA boundary.
- `documents/engineering/training_metrics_and_splits.md` — dataset SHA and split
  provenance recorded per row.
- `documents/engineering/checkpoint_format.md` — read-time dataset SHA field in
  the checkpoint manifest.
- `documents/engineering/product_completion_contract.md` — single non-divergent
  matrix/config/dataset surface as product evidence.

**Product docs to create/update:**
- `README.md` — dataset sources and pinned SHAs for the canonical rows.

**Cross-references to add:**
- Link this phase from the control docs `README.md`, `00-overview.md`,
  `system-components.md`, and `development_plan_standards.md`.
