# Phase 27: Bootstrap Script Wrappers and Status

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Bootstrap Script Wrappers and Status. Single-session phase migrated from legacy Sprint 2.6 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 27.1: Bootstrap Script Wrappers and Status [✅ Done]

**Status**: Done
**Implementation**: `bootstrap/apple-silicon.sh`, `bootstrap/linux-cpu.sh`,
`bootstrap/linux-cuda.sh`
**Docs to update**: `documents/engineering/cluster_topology.md`

### Objective

Wire script-side wrapper subcommands after the Haskell bootstrap exists. Cluster
lifecycle, Dhall rendering, image upload, and daemon launch are owned by
`jitml bootstrap --<substrate>`; this sprint owns only the script-side glue and
status presentation.

### Deliverables

- `up` delegates to `jitml bootstrap --apple-silicon`, or to
  `docker compose run --rm jitml jitml bootstrap --linux-cpu|--linux-cuda`.
- `status` reads `./.build/runtime/cluster-publication.json` and prints
  `edge_port`, Pulsar URLs, MinIO URL, plus a per-component health summary.
- `test` is a thin wrapper for `jitml test all` from outside the container.

### Historical Validation

- `bash -n bootstrap/_lib.sh bootstrap/apple-silicon.sh` exits `0`.
- `bash -n bootstrap/_lib.sh bootstrap/linux-cpu.sh` exits `0`.
- `bash -n bootstrap/_lib.sh bootstrap/linux-cuda.sh` exits `0`.
- `bootstrap/apple-silicon.sh status` reads
  `./.build/runtime/cluster-publication.json`.
- Cabal test stanzas cover the registered test and script surfaces.

### Target Integration Notes

- End-to-end `bootstrap/<substrate>.sh up` followed by a populated live
  cluster-publication status depends on the target live cluster apply path.
- Starting a host-native `jitml service` after Apple bootstrap is closed by
  Phase `5` daemon runtime validation.

### Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
