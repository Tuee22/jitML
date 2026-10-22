# Phase 28: Bootstrap `down` and `purge`

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Bootstrap down and purge. Single-session phase migrated from legacy Sprint 2.7 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

This retained surface covers the original wrapper/cache boundaries. Phase
`278` owns the later node-local PV preservation regression: Kind deletion
removes anonymous volumes holding live data, so preserving HOST `.data` alone
does not establish down/up durability. The live repair and its real survival
validation belong to [Phase 278](phase-278-external-bars-no-self-referential-gate-lint-and-exact-served.md#remaining-work)
as an explicit ownership transfer, without a backward dependency.

## Sprint 28.1: Bootstrap `down` and `purge` [✅ Done]

**Status**: Done
**Implementation**: `bootstrap/apple-silicon.sh`, `bootstrap/linux-cpu.sh`,
`bootstrap/linux-cuda.sh`
**Docs to update**: `documents/engineering/cluster_topology.md`

### Objective

Wire `down`, `purge`, and `purge --full` semantics. `down` preserves both
`./.data/` and `./.build/` and leaves the Apple host daemon up; `purge` is
destructive but cache-preserving (`./.build/` survives, including the JIT
cache); `purge --full` additionally removes `./.build/` and (on Linux) the
substrate image.

### Deliverables

- `down`: `kind delete cluster --name jitml-<substrate>`, leave `./.data/` and
  `./.build/` intact, leave the host-native `jitml service` running on Apple
  (graceful shutdown via SIGTERM is owned by Phase `5`).
- `purge`: `down` plus `rm -rf ./.data/`; `./.build/` survives, including
  `./.build/jit/apple-silicon/`. Apple purge does not invoke Tart or delete a
  VM.
- `purge --full`: `purge` plus `rm -rf ./.build/`; on Linux, `docker compose
  down --rmi local --volumes`.
- Forbidden for stage-0 scripts: anything that touches `~/.kube/config`,
  `~/.docker/config.json`, the user's Homebrew prefix, or any global state
  outside the repo. Haskell `jitml` may install Homebrew packages only through
  typed lazy prerequisite remediation. `bash -n` plus a grep audit at CI time
  enforces the script boundary.

### Validation

- Script parsing validation (`bash -n`) covers all bootstrap wrappers.
- `down`, `purge`, and `purge --full` are repo-local and preserve the
  configured cache semantics; Linux `purge --full` additionally delegates to
  `docker compose down --rmi local --volumes`.
- The scripts contain no writes to `~/.kube/config`, `~/.docker/config.json`,
  Homebrew prefixes, or other global user state.

### Target Integration Notes

- Cache-preserving `purge` followed by live inference cache resolution depends
  on the future inference/JIT runtime path.
- Full byte-for-byte before/after validation of `~/.kube/config` and
  `~/.docker/config.json` belongs to the later live bootstrap test matrix; the
  current script boundary is covered by static and local wrapper tests.

### Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
