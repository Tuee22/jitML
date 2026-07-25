# Phase 189: Linux-CUDA HA Cluster Revalidation

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Linux-CUDA HA Cluster Revalidation. Single-session phase migrated from legacy Sprint 15.22 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 189.1: Linux-CUDA HA Cluster Revalidation [✅ Done]

**Status**: Done (closed 2026-06-28 on the NVIDIA GeForce RTX 5090 host)
**Implementation**: `bootstrap/linux-cuda.sh`, `docker compose` `jitml-cuda`,
live `jitml test all --linux-cuda`, `DEVELOPMENT_PLAN/attestations/`
**Docs to update**: `system-components.md`,
`../documents/engineering/unit_testing_policy.md`

### Objective

Re-run the Linux CUDA live lane on real NVIDIA hardware after the HA Kind,
platform-service, and scoped one-numerical-worker-per-node topology sprints
close.

### Deliverables

- Bootstrap the HA `linux-cuda` topology with the real NVIDIA runtime.
- Validate the Engine/numerical compute placement invariant: at most one
  numerical ML worker per compute scope per Kubernetes node.
- Re-run the CUDA substrate test lane and live workflow/report-card matrix.
- Refresh the Linux CUDA attestation for the HA topology.

### Validation

- `docker compose build jitml` — PASS, including embedded `check-code: ok`,
  PureScript bundle build, and image manifest list
  `sha256:4357054cfac0135eccd06ddea37e4f0c4d9ed8d07abbe8cab9a278a98caa03b2`.
- `JITML_BOOTSTRAP_SKIP_IMAGE_BUILD=1 ./bootstrap/linux-cuda.sh up` — clean HA
  rollout PASS, **130 steps**, edge `9092`, all seven publication components
  Ready.
- Canonical dataset staging — all 12 canonical artifacts present in live MinIO
  with pinned SHA-256 verification from the Sprint `15.22` session.
- `docker compose run --rm jitml-cuda jitml test all --linux-cuda` — PASS,
  **8 / 8 stanzas**, including `jitml-integration` live WorkflowMatrix
  `880.86s`, live PPO convergence `264.46s`, and `jitml-backends` **20 / 20**
  on the RTX 5090.
- Focused regression checks during closure:
  `jitml-sl-canonicals` **24 / 24**, HA service cardinality and Pulsar PV/PVC
  integration checks, and the HA-aware duplicate `StartTraining` dedup log
  assertion.
- `docker compose run --rm jitml jitml internal seed-demo-checkpoints` — eight
  demo checkpoints seeded.
- Live Playwright product matrix against the published CUDA edge — clean
  **15 / 15 PASS** (`15 passed (17.4s)`) in
  `mcr.microsoft.com/playwright:v1.49.1-noble`.
- `docker compose run --rm jitml jitml docs check` — PASS (`docs check: ok`).
- `docker compose run --rm jitml jitml check-code` — PASS (`check-code: ok`).

### Remaining Work

None. The HA Linux-CUDA lane is closed. The separate Apple Silicon HA live
revalidation closed in Phase `16` Sprint `16.14`, and downstream aggregation
closed in Phases `17` / `18`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
