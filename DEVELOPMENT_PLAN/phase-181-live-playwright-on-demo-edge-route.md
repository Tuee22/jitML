# Phase 181: Live Playwright on Demo Edge Route

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Live Playwright on Demo Edge Route. Single-session phase migrated from legacy Sprint 15.14 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 181.1: Live Playwright on Demo Edge Route [✅ Done]

**Status**: Done (re-validated 2026-06-06 on RTX 5090; previously Done on RTX 3090) (closed 2026-05-28)
**Blocked by**: Sprint `180.1`
**Implementation**: `playwright/jitml-demo.spec.ts`,
`src/JitML/Test/LivePlan.hs`
**Docs to update**: `documents/engineering/purescript_frontend.md`,
`documents/engineering/unit_testing_policy.md`

### Objective

Execute the live Playwright canonical panel matrix against the
`jitml-demo` service behind the Envoy edge route: the smoke shell,
portals link coverage, shared header coverage, and the six canonical panels
(`mnist-live-inference`, `cifar-imagenet-upload`,
`connect4-human-vs-alphazero`, `rl-trajectory`, `training-progress`,
`hyperparameter-sweep`). The REST panels click through to the live API and
assert rendered values. This replaces the former inline `page.setContent`
DOM stubs and closes Exit Definition item 8's Playwright slice plus item 9's
`jitml-e2e` Playwright slice.

### Deliverables

- `playwright/jitml-demo.spec.ts` reads the leased edge port from
  `cluster-publication.json` and loads
  `http://127.0.0.1:<edge-port>/...` for each panel test instead of
  using `page.setContent`.
- The typed `JitML.Test.LivePlan.liveE2EPlan` sequence drives `helm
  dependency build chart` → `jitml bootstrap` (ephemeral Kind + phased
  Helm rollout) → pinned Playwright browser-image run → `jitml cluster down` on
  Linux+Docker+NVIDIA.
- Post-teardown the explicit live e2e path leaves no Kind cluster, no
  Harbor project, no MinIO bucket, and no Docker volume on the host.

### Validation

1. The explicit live `jitml-e2e` orchestration command exits `0`,
   including the Playwright run.
2. Post-teardown grep for leaked resources returns empty.

### Code Surface Landed (2026-05-27, live edge selection)

- `playwright/jitml-demo.spec.ts` adds `loadLiveEdge()` that reads
  `./.build/runtime/cluster-publication.json` and returns
  `http://127.0.0.1:<edge-port>/`. Phase `17` Sprint `17.3` removed
  the offline fallback, so the current spec fails fast when the live
  publication is absent.
- Each canonical panel test now navigates to the live edge route and waits for
  the named panel to attach to the DOM (Halogen mount). The earlier inline-DOM
  branch was retired on 2026-06-04, and the 2026-06-11 rerun extended the suite
  to 9 / 9 with portals-link, shared-header, and REST rendered-value assertions.

### Live Validation Note (2026-05-27, fifth session — Playwright passes against the live cluster edge)

The seven-test canonical panel matrix ran against the live
`jitml-demo` behind the Envoy edge (RTX 3090 / CUDA 12.8 cluster) and
**passed 7 / 7**. The path:

1. The Dockerfile now bundles the spago CommonJS output into a
   browser-loadable IIFE (`web/dist/Main/bundle.js`, 225 KB) via
   esbuild; `JitML.Web.Server.loadBundleEntry` prefers it. The new
   image was tagged `jitml-demo:local`, `kind load`ed into the running
   cluster, and the `jitml-demo` Deployment rollout-restarted to pick
   it up. `curl http://127.0.0.1:9092/bundle/main.js` returns the
   225 KB IIFE (was the unresolvable 1616-byte CommonJS module before).
2. `playwright/jitml-demo.spec.ts`'s `loadPanel` now navigates to
   `LIVE_DEMO_URL#<panel-id>` per panel so `Main.main` mounts the
   matching `Panels.*` component; a new `playwright/package.json` +
   `playwright.config.ts` scaffold the run.
3. Inside `jitml:local`: `npm install @playwright/test@1.49.1` +
   `npx playwright install --with-deps chromium` +
   `playwright test --config=playwright/playwright.config.ts` (cwd
   `/jitml`, browsers cached under `./.build/ms-playwright`):

   ```
   Running 7 tests using 1 worker
     ✓ demo shell responds
     ✓ mnist panel renders an inference canvas
     ✓ cifar panel renders an upload control
     ✓ connect4 panel renders the board
     ✓ rl panel renders an episode timeline
     ✓ training panel renders a loss curve
     ✓ tune panel renders the trial heatmap
   7 passed (1.2s)
   ```

   Each panel mounts from the real bundle served through the live Envoy
   edge — this validates the Sprint 15.13 compiled-Halogen-bundle render
   deliverable end-to-end in a real browser (chromium headless).

### Remaining Work

- None remaining for Sprint 13.14. Sprint closed 2026-05-28 and revalidated
  on 2026-06-11. The Playwright panel matrix passed 9 / 9 against the live
  `jitml-demo` edge on the CUDA machine, including REST rendered-value
  assertions; the original 7 / 7 render-only validation note above remains as
  historical evidence. The ephemeral e2e orchestration is the `jitml bootstrap`
  + `jitml cluster down` path recorded in `JitML.Test.LivePlan.liveE2EPlan`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
