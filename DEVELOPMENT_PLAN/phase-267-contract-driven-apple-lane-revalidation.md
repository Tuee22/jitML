# Phase 267: Contract-Driven Apple Lane Revalidation

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Contract-Driven Apple Lane Revalidation. Single-session phase migrated from legacy Sprint 30.4 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

⏸️ **Blocked**. Blocked by Phase 263 (Sprint 263.1).

## Sprint 267.1: Contract-Driven Apple Lane Revalidation [⏸️ Blocked]

**Status**: Blocked
**Implementation**: `src/JitML/Test/RunContract.hs`,
`src/JitML/Test/Report.hs`, `test/integration/Main.hs`,
`DEVELOPMENT_PLAN/attestations/apple-silicon-report-card.md`
**Blocked by**: Sprint `263.1`
**Docs to update**: `../README.md`,
`../documents/engineering/product_completion_contract.md`,
`../documents/engineering/unit_testing_policy.md`,
`../documents/engineering/run_contract.md`,
`../documents/engineering/apple_silicon_metal_headless_builds.md`,
`system-components.md`

### Objective

Revalidate the full row-complete workflow contract on the real Apple host and
replace the `apple-silicon` fragment with journal-derived evidence. This sprint
owns the Apple-lane portions of
[Exit Definition](README.md#exit-definition) items `31`, `32`, and `34`.
The binding design is
[README.md → Typed run contracts](../README.md#typed-run-contracts).

### Deliverables

- Run every supported Apple product scenario through the validated plan, exact
  evidence reducer, and scoped lifecycle while preserving host-resident Metal
  placement.
- Prove each completed row journal carries the Apple/Metal device witness,
  host-command placement evidence, exact terminal evidence, trained artifact
  hash, and measured inference result.
- Assert no Metal-backed training, RL, or tuning workload Job is created in the
  cluster; failures retain host-daemon and cluster-forwarder diagnostics.
- Replace the committed `apple-silicon` fragment only after the complete live
  lifecycle passes, with explicit failed/not-run cells otherwise.
- Keep this phase independent of `linux-cuda` execution: validation uses only
  `apple-silicon` plus the host's `linux-cpu` support surface.

### Validation

```bash
./bootstrap/apple-silicon.sh up
./bootstrap/apple-silicon.sh test
./bootstrap/apple-silicon.sh down
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Remaining Work

- Blocked until Sprint `263.1` closes in numerical order with the CUDA lane
  fragment required by downstream aggregation.
- Execute the real Apple lifecycle and regenerate the lane journal/attestation.
- Reconfirm host placement, Metal execution, and cleanup before returning this
  phase to Done.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
