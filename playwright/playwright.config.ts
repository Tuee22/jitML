import { defineConfig, devices } from "@playwright/test";

const browserEvidenceEnvironment = [
  "JITML_BROWSER_CATALOGUE_PATH",
  "JITML_BROWSER_PUBLICATION_PATH",
  "JITML_BROWSER_RESULT_PATH",
  "JITML_BROWSER_RESULT_KEY_FILE",
] as const;

function configuredReporters(): [["list"], [string]] | [["list"]] {
  const configured = browserEvidenceEnvironment.filter((name) => {
    const value = process.env[name];
    return value !== undefined && value.trim() !== "";
  });
  if (configured.length !== 0 && configured.length !== browserEvidenceEnvironment.length) {
    const missing = browserEvidenceEnvironment.filter((name) => !configured.includes(name));
    throw new Error(
      `partial browser-evidence environment; missing ${missing.join(", ")}`,
    );
  }
  return configured.length === browserEvidenceEnvironment.length
    ? [["list"], ["./jitml-browser-evidence-reporter.ts"]]
    : [["list"]];
}

// Sprint 13.14 — Playwright config for the canonical demo panel matrix.
// The spec (`jitml-demo.spec.ts`) reads the individually mounted
// `JITML_BROWSER_PUBLICATION_PATH` to pick the live Envoy edge URL and fails
// fast when the exact publication or catalogue is unavailable.
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
  // Checkpoint-backed panels each drive a full async daemon round trip. The
  // evidence reporter retains the final attempt for every exact catalogue row;
  // a retry contributes Passed only when that final attempt actually passes.
  retries: 2,
  fullyParallel: false,
  reporter: configuredReporters(),
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
