# Phase 197: Retired VM-path apple-silicon Workflow Attempt

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Retired VM-path apple-silicon Workflow Attempt. Single-session phase migrated from legacy Sprint 16.8 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 197.1: Retired VM-path apple-silicon Workflow Attempt [✅ Done]

**Status**: Done (closed as historical failure evidence; superseded by Sprint `16.9`)
**Docs to update**: `system-components.md`

### Objective

Record the final live attempt through the now-retired Tart VM path. The attempt
proved the VM architecture violates the true-headless requirement because
Virtualization.framework host-key creation depends on user keychain state in this
headless shell. Sprint `16.9` replaces this path with the fixed bridge and closes
the Apple workflow lane.

### Validation

- `jitml bootstrap --apple-silicon` and `jitml test jitml-e2e --apple-silicon`
  reached the live cluster.
- The `WorkflowMatrix` attempt failed closed at the Tart HostKey boundary, and
  that evidence is retained as the reason the VM path was removed.

### Remaining Work

- None. The live workflow obligation moved to and closed in Sprint `16.9` through
  the fixed bridge.

### Historical Evidence

- 2026-06-12 blocker re-check on this 64 GiB Apple Silicon host
  (`sysctl -n hw.memsize` → `68719476736`): `bootstrap/apple-silicon.sh doctor`
  passed; `bootstrap/apple-silicon.sh up` completed the live phased rollout
  (84 steps) and the image-local `jitml check-code` gate passed; the publication
  reports all seven components Ready on `edge_port: 9090`; and
  `jitml test jitml-e2e --apple-silicon` passed **20 / 20**. The focused live
  matrix invocation now preserves user test filters under substrate flags
  (`jitml-unit -p substrateTestInvocations` covers the regression) and reaches
  the real Apple training path, but `jitml-integration -p WorkflowMatrix` fails
  closed at the first `train experiments/mnist.dhall --substrate apple-silicon`
  cell because Tart cannot start `jitml-build`:
  `VZErrorDomain Code=-9 ... Failed to get current host key` /
  `Failed to create new HostKey`. Direct `tart run --no-graphics ... jitml-build`
  reproduces the same failure.
- Host diagnosis: `security list-keychains` and `security default-keychain`
  resolve to `/Library/Keychains/System.keychain`; the existing
  `~/Library/Keychains/login.keychain-db` is not usable headlessly
  (`security show-keychain-info` reports `User interaction is not allowed`, and
  `security unlock-keychain -p ''` rejects the passphrase). Creating a dedicated
  unlocked keychain and setting it as the search-list/default keychain was not
  sufficient for Virtualization.framework. Temporarily moving/replacing the real
  login keychain was not attempted because it is a sensitive user-state change.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
