import { test, expect } from "@playwright/test";
import * as fs from "fs";

// Canonical live panel matrix for the demo bundle. Each test reads the
// published live `jitml-demo` edge from
// `./.build/runtime/cluster-publication.json` and navigates through the
// real browser bundle.
//
// Sprint 15.3 — the previous inline DOM fallback is retired; this matrix
// now requires the typed
// `JitML.Test.LivePlan` orchestration that drives `helm dependency
// build chart` + `jitml bootstrap` (ephemeral Kind + phased Helm
// rollout) + `npx playwright test` + `jitml cluster down`.

interface ClusterPublication {
  edge_port: number;
  substrate: string;
}

function loadLiveEdge(): string {
  const path = "./.build/runtime/cluster-publication.json";
  if (!fs.existsSync(path)) {
    throw new Error("live demo Playwright requires ./.build/runtime/cluster-publication.json");
  }
  try {
    const raw = fs.readFileSync(path, "utf-8");
    const parsed = JSON.parse(raw) as ClusterPublication;
    if (typeof parsed.edge_port !== "number") {
      throw new Error("cluster-publication.json is missing numeric edge_port");
    }
    return `http://127.0.0.1:${parsed.edge_port}/`;
  } catch (err) {
    if (err instanceof Error) {
      throw err;
    }
    throw new Error("failed to read cluster-publication.json");
  }
}

const LIVE_DEMO_URL = loadLiveEdge();

async function loadShell(page: import("@playwright/test").Page): Promise<void> {
  await page.goto(LIVE_DEMO_URL);
  await page
    .locator("main#app")
    .waitFor({ state: "attached", timeout: 10000 });
}

async function loadPanel(
  page: import("@playwright/test").Page,
  panelId: string
): Promise<void> {
  // `Main.main` mounts the panel selected by `location.hash`; the bare
  // demo URL mounts the portals home, so each test navigates to its
  // own `#<panel-id>` hash to drive the matching `Panels.*` mount.
  await page.goto(`${LIVE_DEMO_URL}#${panelId}`);
  await page
    .locator(`#${panelId}`)
    .waitFor({ state: "attached", timeout: 10000 });
}

test("demo shell responds and renders the portals home", async ({ page }) => {
  await loadShell(page);
  await expect(page.locator("main#app")).toBeAttached();
  await expect(page.locator("#portals")).toBeVisible();
  await expect(page.locator("#jitml-portals-panels")).toBeVisible();
  await expect(page.locator("#jitml-portals-admin")).toBeVisible();
});

test("portals home links to every bundled admin portal", async ({ page }) => {
  await loadShell(page);
  const expected: ReadonlyArray<readonly [string, string]> = [
    ["jitml-portals-admin-grafana", "/grafana"],
    ["jitml-portals-admin-prometheus", "/prometheus"],
    ["jitml-portals-admin-tensorboard", "/tensorboard"],
    ["jitml-portals-admin-harbor-portal", "/harbor"],
    ["jitml-portals-admin-minio-console", "/minio/console"],
    ["jitml-portals-admin-pulsar-admin", "/pulsar/admin"],
  ];
  for (const [id, href] of expected) {
    await expect(page.locator(`#${id}`)).toHaveAttribute("href", href);
  }
});

test("shared header is present on every panel", async ({ page }) => {
  const panels = [
    "mnist-live-inference",
    "cifar-imagenet-upload",
    "training-progress",
    "hyperparameter-sweep",
    "rl-trajectory",
    "connect4-human-vs-alphazero",
  ];
  for (const panelId of panels) {
    await loadPanel(page, panelId);
    await expect(page.locator("#jitml-chrome")).toBeVisible();
    await expect(page.locator("#jitml-chrome-home")).toHaveAttribute(
      "href",
      "#portals",
    );
  }
});

test("mnist panel renders an inference canvas", async ({ page }) => {
  await loadPanel(page, "mnist-live-inference");
  await expect(page.locator("#mnist-live-inference")).toBeVisible();
  await expect(page.locator("#mnist-live-inference canvas")).toHaveCount(1);
});

test("cifar panel renders an upload control", async ({ page }) => {
  await loadPanel(page, "cifar-imagenet-upload");
  await expect(page.locator("#cifar-imagenet-upload")).toBeVisible();
});

test("connect4 panel renders the board", async ({ page }) => {
  await loadPanel(page, "connect4-human-vs-alphazero");
  await expect(page.locator("#connect4-human-vs-alphazero")).toBeVisible();
});

test("rl panel renders an episode timeline", async ({ page }) => {
  await loadPanel(page, "rl-trajectory");
  await expect(page.locator("#rl-trajectory")).toBeVisible();
});

test("training panel renders a loss curve", async ({ page }) => {
  await loadPanel(page, "training-progress");
  await expect(page.locator("#training-progress")).toBeVisible();
});

test("tune panel renders the trial heatmap", async ({ page }) => {
  await loadPanel(page, "hyperparameter-sweep");
  await expect(page.locator("#hyperparameter-sweep")).toBeVisible();
});
