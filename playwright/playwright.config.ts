import { defineConfig, devices } from "@playwright/test";

// Sprint 13.14 — Playwright config for the canonical demo panel matrix.
// The spec (`jitml-demo.spec.ts`) reads
// `./.build/runtime/cluster-publication.json` to pick the live Envoy edge
// URL and fails fast when no live publication is available.
// Run from the repo root inside `jitml:local`:
//   cd playwright && npx playwright test
export default defineConfig({
  testDir: ".",
  testMatch: "*.spec.ts",
  timeout: 30000,
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
