# Phase 202: Apple-Silicon HA Cluster Revalidation

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Apple-Silicon HA Cluster Revalidation. Single-session phase migrated from legacy Sprint 16.14 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 202.1: Apple-Silicon HA Cluster Revalidation [✅ Done]

**Status**: Done (opened 2026-06-27; HA implementation unblocked 2026-06-28
after Sprints `3.6`, `4.10`, and `5.16` closed; re-closed 2026-06-29 after the
host LLVM and Docker/Colima capacity blockers were removed)
**Implementation**: `bootstrap/apple-silicon.sh`, host Metal bridge,
live `jitml test all --apple-silicon`, `DEVELOPMENT_PLAN/attestations/`
**Docs to update**: `system-components.md`,
`../documents/engineering/unit_testing_policy.md`

### Objective

Re-run the Apple Silicon live lane on real Apple hardware after the HA Kind,
platform-service, and scoped one-numerical-worker-per-node topology sprints
close.

### Deliverables

- Bootstrap the HA `apple-silicon` topology and run the host Metal daemon.
- Validate that in-cluster replicas do not multiply host Metal compute and that
  numerical compute remains bounded by host/node topology.
- Re-run the Apple substrate test lane and live workflow/report-card matrix.
- Refresh the Apple Silicon attestation for the HA topology.

### Validation

- Clean Docker/Colima capacity reset (authorized development VM/container wipe):
  Colima restarted with 8 CPU, 12 GiB memory, and 512 GiB disk; Docker reported
  roughly 503 GiB available.
- `./bootstrap/apple-silicon.sh doctor` — passed.
- `./bootstrap/apple-silicon.sh build` — passed with Homebrew `llvm@19`
  selected for GHC-compatible `opt`/`llc`; `.build/jitml` was written as a real
  arm64 Mach-O binary.
- `./bootstrap/apple-silicon.sh up` — HA rollout PASS, **131** steps, edge
  `9090`, all seven publication components ready.
- `./bootstrap/apple-silicon.sh run-daemon` — host daemon acquired
  `apple.metal-runtime=yes`, `apple.metal-bridge=yes`, and all four host command
  topics (`inference`, `training`, `tune`, `rl`).
- `./bootstrap/apple-silicon.sh test` — **8 / 8** stanzas passed on the real
  Apple lane, including the `jitml-backends --apple-silicon` Metal cases.
- `jitml internal seed-demo-checkpoints` — seeded all eight demo checkpoints.
- Direct edge inference probe — `POST http://127.0.0.1:9090/api/inference`
  returned `HTTP 200` with `kind: InferenceResult`; Pulsar `jitml-host` backlog
  was `0`.
- Live Playwright product matrix — **15 / 15 PASS** against the Apple edge in
  the pinned Playwright container.

### Remaining Work

None. The HA Apple Silicon lane is closed, and Phases `17` / `18` consume this
refreshed fragment on `linux-cpu` without re-running the accelerator lane.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
