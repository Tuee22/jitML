import { defineConfig, devices } from "@playwright/test";

// Sprint 13.14 — Playwright config for the canonical demo panel matrix.
// The spec (`jitml-demo.spec.ts`) reads
// `./.build/runtime/cluster-publication.json` to pick the live Envoy edge
// URL and fails fast when no live publication is available.
// Run from the repo root through `jitml test jitml-e2e --live --<substrate>`;
// the typed plan uses the pinned `mcr.microsoft.com/playwright:v1.49.1-noble`
// browser image.
export default defineConfig({
  testDir: ".",
  testMatch: "*.spec.ts",
  outputDir: process.env.PLAYWRIGHT_TEST_RESULTS_DIR ?? "playwright/test-results",
  timeout: 120000,
  // Sprint 16.11 — the converged demo is the Webapp role: each checkpoint-backed
  // panel publishes an inference WorkCommand to the Engine and renders the result
  // streamed back over `/api/ws/inference`. On the `apple-silicon` lane that round
  // trip is the full Webapp→cluster-forward→host-Metal-Engine→websocket path, and
  // the checkpoint-compare panel runs *two* inferences plus the delta, so the
  // per-assertion `expect` timeout is raised well above the 5s default to give the
  // async DOM render time to arrive on a loaded host.
  expect: { timeout: 45000 },
  // Sprint 16.11 — the checkpoint-backed panels each drive a full async
  // Webapp→cluster→host-Metal-Engine→websocket round trip; under a loaded host the
  // round-trip latency varies, so retry a panel whose async result is late rather
  // than fail the matrix on an environmental timing wobble (every panel serves its
  // result kind, as the report-card `browser_product_matrix` 5/5 probe confirms).
  retries: 2,
  fullyParallel: false,
  reporter: [["list"]],
  use: {
    ...devices["Desktop Chrome"],
    headless: true,
  },
  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
    },
  ],
});
