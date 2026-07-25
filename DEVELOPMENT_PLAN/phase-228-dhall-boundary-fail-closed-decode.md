# Phase 228: Dhall Boundary & Fail-Closed Decode

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Dhall Boundary & Fail-Closed Decode. Single-session phase migrated from legacy Sprint 21.3 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 228.1: Dhall Boundary & Fail-Closed Decode [✅ Done]

**Status**: Done
**Implementation**: `dhall/project/Schema.dhall`, `dhall/run/Schema.dhall`, `src/JitML/Service/RunConfig.hs`, `src/JitML/Service/DhallSchema.hs`, `src/JitML/Project/Config.hs`, `src/JitML/Checkpoint/Format.hs`, `src/JitML/Checkpoint/Store.hs`, `src/JitML/Service/Workload.hs`, `src/JitML/Web/Contracts.hs`, `web/src/Generated/Contracts.purs`, `web/src/Panels/Checkpoints.purs`, `test/unit/Main.hs`, `test/integration/Main.hs`
**Docs to update**: `../documents/engineering/durable_state_dsl.md`, `../documents/engineering/product_completion_contract.md`

### Objective

The Dhall configuration surface mirrors the Haskell state boundary. A manifest
with missing, partial, synthetic, seeded, or failed-training provenance cannot
decode as an inference target, and the browser renders a fail-closed state
instead of substituting a fabricated artifact.

### Deliverables

- Dhall schemas under `dhall/project/Schema.dhall` and `dhall/run/Schema.dhall`
  distinguish declared experiments, completed-training witnesses, and inference
  selectors, mirroring the `ModelState` boundary from Sprint `21.2`.
  `JitML.Service.RunConfig.tryLoadInferenceSelectorConfig` decodes and validates
  selector facts at the Dhall boundary.
- `src/JitML/Checkpoint/Store.hs` exposes known-address and stable-latest
  admission followed by `requireAdmittedCompletedCheckpoint`, and rejects any
  manifest missing the weight-delta evidence fields, carrying
  synthetic/seeded provenance, or carrying a failing convergence outcome before
  weight blobs are read or an inference runner is invoked.
- `JitML.Service.Workload.renderCheckpointListResult`, the generated browser
  contracts, and `web/src/Panels/Checkpoints.purs` carry
  `selector-state: fail-closed:no-inference-eligible-artifact` when no row has
  an inference-eligible artifact, so the browser shows an explicit fail-closed
  state rather than falling back to seeded or synthetic data.
- Unit and integration tests assert that declared, partial, synthetic, seeded,
  zero-update, unchanged-weight, and failed-training selectors/manifests fail
  closed with typed errors, that invalid manifests are rejected before blob or
  runner IO, and that a valid completed manifest decodes as an inference target.

### Validation

```bash
docker compose build jitml                                                        # passed; refreshed image, embedded check-code: ok
docker compose run --rm -e JITML_BOOTSTRAP_SKIP_IMAGE_BUILD=1 jitml jitml bootstrap --linux-cpu # passed, 105 rollout steps
docker compose run --rm jitml jitml docs check                                    # passed
docker compose run --rm jitml jitml check-code                                    # passed
docker compose run --rm jitml jitml test jitml-unit --linux-cpu                   # passed, 258/258 tests
docker compose run --rm jitml jitml test jitml-integration --linux-cpu            # passed, 78/78 tests
```

The 2026-07-05 realness audit found decode trusted the stored `coPassed` boolean
and the stored weight hashes, so the "unchanged-weight / failed-training" rejections
above never fired for an untrained random-init manifest whose all-zeros init hash
differs from its nonzero final hash.

### Closure Evidence

closed obligation (Exit Definition — fail-closed decode): the decode surface trusts
the stored `coPassed` boolean and the stored weight hashes, so an untrained
random-init manifest decodes as an inference target instead of failing closed.

- **Re-derive `coPassed` at persisted admission against the external bar.**
  The `src/JitML/Checkpoint/Store.hs` admission path and downstream provenance
  gate must recompute the convergence
  verdict from the served metrics against the frozen external constants
  ([Phase 32](README.md#legacy-to-new-phase-map) Sprint `32.2` decode
  change), not accept the boolean the manifest carries, and must assert the
  served-weights hash equals the checkpoint hash.

Closed by the [Phase 32](README.md#legacy-to-new-phase-map)
negative-control suite (`jitml-negative-controls`, Sprint `32.1`) that an untrained
random-init checkpoint is rejected at decode.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
