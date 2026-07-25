# Phase 205: Empty Legacy Ledger and Final Handoff

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Empty Legacy Ledger and Final Handoff. Single-session phase migrated from legacy Sprint 17.3 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 205.1: Empty Legacy Ledger and Final Handoff [✅ Done]

**Status**: Done
**Implementation**: `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`,
`cabal.project`, `src/JitML/Codegen/{Cuda,Metal}.hs`,
`src/JitML/Web/Server.hs`, `playwright/jitml-demo.spec.ts`,
`test/e2e/Main.hs`, `test/snapshots/`
**Docs to update**: `README.md`,
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`,
`DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`,
`DEVELOPMENT_PLAN/system-components.md`,
`documents/engineering/code_quality.md`,
`documents/engineering/purescript_frontend.md`,
`documents/engineering/unit_testing_policy.md`

### Objective

Resolve every remaining row in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
Pending Removal so the final handoff has no open legacy rows. Closes Exit
Definition item 18.

### Deliverables

- The dependency source-pin/vendor helper introduced by Phase `1` Sprint
  `1.10` is retired by Phase `1` Sprint `1.11`: GHC `9.12.4` / `base-4.21`
  solves from plain Hackage without source pins or local package patches.
- The copyright-free RL demo replacement row is completed: `KeyDoorGrid-v0`
  owns default visual discrete-control demos and the required algorithm matrix,
  while Atari/ALE is optional runtime support only and requires generated or
  externally supplied adapter support.
- Demo placeholder shell, local stream frames, and inline DOM stubs are
  removed. Plain HTTP stream routes now require a WebSocket upgrade,
  no-publication WebSocket bridges emit a terminal error frame, and
  Playwright requires the live cluster publication.
- The deletion ledger Pending Removal section is empty; every cleanup row lives
  in Completed. The superseded development ledger is deleted.

### Cleanup Landed (2026-06-03)

- The Metal kernel-family validation residue moved to Completed after
  the Apple host exported the Sprint `17.1` weighted bundle with all
  eight tensor families.
- The deterministic MCTS `priorFor` helper was removed; the default
  mechanics oracle is neutral uniform and production self-play consumes
  the policy/value network oracle.
- The target-stanza-only report-card row moved to Completed. `ReportCard`
  now carries `ReportMeasurements`, and `jitml test all --live` renders
  measured or `unavailable` fields.
- The Sprint `17.2` cache and daemon live-report probes now use
  host-reachable daemon edge routes instead of a cache placeholder or a
  publication-file-only health check.
- The committed numerical fixture tree under `test/golden/` was deleted.
  Pure renderer snapshots moved to `test/snapshots/`, numerical tests
  now use run-to-run/property assertions, and lint rejects
  `test/golden/`.

### Cleanup Landed (2026-06-04)

- The scoped `allow-newer` row moved to Completed. `cabal.project` now has no
  `allow-newer` stanza.
- The source-pin/vendor helper moved to Completed. Phase `1` Sprint `1.11`
  changed the project baseline to GHC `9.12.4` / `base-4.21`, removed the
  upstream source pins and local `third_party/haskell/lens-family-*` packages,
  and validated a plain-Hackage solve.
- The superseded reopened-phase development ledger was deleted; reopened-phase
  closure now lives in the owning phase documents, with cleanup residue tracked
  only in the deletion ledger.
- The demo placeholder shell/local stream/offline Playwright fallback
  row moved to Completed. `JitML.Web.Server` now serves the minimal
  compiled-bundle shell, loads only `web/dist/Main/bundle.js`, returns
  `503 live stream requires WebSocket upgrade` for plain HTTP
  `/api/ws*` requests, and emits a terminal error frame instead of a
  deterministic stream when no live publication exists.
- `playwright/jitml-demo.spec.ts` is live-only: it reads
  `.build/runtime/cluster-publication.json`, fails fast when the
  publication is absent, and navigates each panel through the live
  Envoy edge route.
- `JitML.Service.Http.serveHttpRoutesWithWebSockets` forks one worker
  per accepted connection; a held-open WebSocket bridge no longer
  serializes and blocks later HTTP or bundle requests. `jitml-e2e`
  covers both the plain HTTP 503 stream response and the non-blocking
  held-open WebSocket case.
- The browser-contract and route metadata include the live
  `/api/ws/rl` route used by the RL panel.
- The deterministic Atari-subset RAM-state stub row moved to Completed. Phase
  `8` Sprint `8.8` now keeps explicit uncommitted ROM inputs, ignored
  `./.roms/` storage, and the runtime-loaded `JitML.RL.ALE` boundary. The
  later static-foreign-source correction removed the checked-in ALE C++ shim,
  Dockerfile compile step, and lint allowlist; any future project-owned adapter
  must be Haskell-generated or supplied outside the repository.
- The copyright-free RL demo replacement row moved to Completed. Phase `8`
  Sprint `8.9` landed `KeyDoorGrid-v0`, the checked-in
  `experiments/key-door-grid.dhall` demo path, and unit/canonical coverage;
  Phase `9` Sprint `9.8` retargeted the required RL algorithm/convergence
  matrix away from `atari-subset`.

### Validation

1. `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md` Pending Removal
   table is empty, and the superseded reopened-phase development ledger has
   been removed.
2. `docker compose run --rm jitml jitml check-code` passes after every
   ledger removal.
3. The Closure Status section in
   [README.md](README.md) records the final handoff date and host
   details.
4. 2026-06-04 demo cleanup validation: mounted-container
   `jitml-e2e` passed 19 / 19; `jitml check-code` passed; the rebuilt
   image was loaded into the live Apple Silicon cluster as
   `jitml-demo:local`; the live Playwright matrix passed 7 / 7 against
   the published `127.0.0.1:9091` edge route.
5. 2026-06-04 dependency validation: after downgrading to GHC `9.12.4`,
   `cabal.project` has no `allow-newer`, no `source-repository-package`
   entries, and no local dependency packages. A container-local
   `ghcup run --ghc 9.12.4 -- cabal build all --dry-run --jobs=2` solves
   against plain Hackage.
6. 2026-06-04 ALE/foreign-source validation: `docker compose build jitml`
   passed with image-local `check-code: ok` and a rebuilt PureScript bundle;
   `docker compose run --rm jitml jitml check-code` passed; focused
  `jitml-unit` / `jitml-rl-canonicals` tests passed 184 / 184 and 27 / 27;
  `jitml rl train` with `JITML_ENVIRONMENT=atari-subset` and no ROM env
  failed closed with the ROM-policy diagnostic; and the static C++ shim was
  removed from the repository. ROM-backed ALE smoke is optional/manual and was
  not part of required validation.
7. 2026-06-04 KeyDoorGrid validation: `docker compose run --rm -e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0='*' jitml cabal test jitml-unit jitml-rl-canonicals --jobs=2`
   passed, and `docker compose run --rm -e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0='*' -e JITML_ENVIRONMENT=key-door-grid jitml jitml rl train experiments/key-door-grid.dhall`
   exited `0` with `environment: key-door-grid`.
8. 2026-06-04 source-pin/vendor retirement validation: `third_party/` is
   deleted, `cabal.project` references only the root package, and the plain
   Hackage solve selects `serialise-0.2.6.1`, `cborg-0.2.10.0`,
   `dhall-1.42.3`, `lens-family-2.1.3`, and `lens-family-core-2.1.3`.

### Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
