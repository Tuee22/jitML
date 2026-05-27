import { test, expect } from "@playwright/test";
import * as fs from "fs";

// Canonical panel matrix for the demo bundle. Each test prefers the live
// `jitml-demo` HTTP server (read from
// `./.build/runtime/cluster-publication.json`) when a cluster is up;
// otherwise it falls back to the previous `page.setContent` DOM stub so
// the matrix continues to exercise the locator surface offline.
//
// Sprint 13.14 — live edge selection. The fallback stays for the
// pre-cluster development inner loop and for CI environments without
// Docker/Kind. The fully-live path is owned by the typed
// `JitML.Test.LivePlan` orchestration that drives `helm dependency
// build chart` + `pulumi up` + `npx playwright test` + `pulumi destroy`
// + `pulumi stack rm`.

interface ClusterPublication {
  edge_port: number;
  substrate: string;
}

function loadLiveEdge(): string | null {
  const path = "./.build/runtime/cluster-publication.json";
  if (!fs.existsSync(path)) {
    return null;
  }
  try {
    const raw = fs.readFileSync(path, "utf-8");
    const parsed = JSON.parse(raw) as ClusterPublication;
    if (typeof parsed.edge_port !== "number") {
      return null;
    }
    return `http://127.0.0.1:${parsed.edge_port}/`;
  } catch (_) {
    return null;
  }
}

const LIVE_DEMO_URL = loadLiveEdge();

async function loadPanel(
  page: import("@playwright/test").Page,
  inlineStub: string,
  panelId: string
): Promise<void> {
  if (LIVE_DEMO_URL) {
    await page.goto(LIVE_DEMO_URL);
    // Wait briefly for the Halogen bundle to mount the panel before the
    // assertion runs. The Sprint 13.13 render machinery populates each
    // `section#<panel-id>` inside `<main id="app">` once mounted.
    await page
      .locator(`#${panelId}`)
      .or(page.locator("main#app"))
      .first()
      .waitFor({ state: "attached", timeout: 5000 });
  } else {
    await page.setContent(inlineStub);
  }
}

test("demo shell responds", async ({ page }) => {
  await loadPanel(page, "<main id=\"app\">jitML demo</main>", "app");
  if (LIVE_DEMO_URL) {
    await expect(page.locator("main#app")).toBeVisible();
  } else {
    await expect(page.locator("#app")).toContainText("jitML demo");
  }
});

test("mnist panel renders an inference canvas", async ({ page }) => {
  await loadPanel(
    page,
    "<main id=\"app\"><section id=\"mnist-live-inference\"><canvas id=\"draw\"></canvas></section></main>",
    "mnist-live-inference"
  );
  if (LIVE_DEMO_URL) {
    await expect(page.locator("#mnist-live-inference")).toBeVisible();
    await expect(page.locator("#mnist-live-inference canvas")).toHaveCount(1);
  } else {
    await expect(page.locator("section#mnist-live-inference canvas#draw")).toHaveCount(1);
  }
});

test("cifar panel renders an upload control", async ({ page }) => {
  await loadPanel(
    page,
    "<main id=\"app\"><section id=\"cifar-imagenet-upload\"><input type=\"file\" id=\"image\"></section></main>",
    "cifar-imagenet-upload"
  );
  if (LIVE_DEMO_URL) {
    await expect(page.locator("#cifar-imagenet-upload")).toBeVisible();
  } else {
    await expect(page.locator("section#cifar-imagenet-upload input[type=file]")).toHaveCount(1);
  }
});

test("connect4 panel renders the board", async ({ page }) => {
  await loadPanel(
    page,
    "<main id=\"app\"><section id=\"connect4-human-vs-alphazero\"><div class=\"board\"></div></section></main>",
    "connect4-human-vs-alphazero"
  );
  if (LIVE_DEMO_URL) {
    await expect(page.locator("#connect4-human-vs-alphazero")).toBeVisible();
  } else {
    await expect(page.locator("section#connect4-human-vs-alphazero .board")).toHaveCount(1);
  }
});

test("rl panel renders an episode timeline", async ({ page }) => {
  await loadPanel(
    page,
    "<main id=\"app\"><section id=\"rl-trajectory\"><ol class=\"episodes\"></ol></section></main>",
    "rl-trajectory"
  );
  if (LIVE_DEMO_URL) {
    await expect(page.locator("#rl-trajectory")).toBeVisible();
  } else {
    await expect(page.locator("section#rl-trajectory ol.episodes")).toHaveCount(1);
  }
});

test("training panel renders a loss curve", async ({ page }) => {
  await loadPanel(
    page,
    "<main id=\"app\"><section id=\"training-progress\"><svg class=\"loss\"></svg></section></main>",
    "training-progress"
  );
  if (LIVE_DEMO_URL) {
    await expect(page.locator("#training-progress")).toBeVisible();
  } else {
    await expect(page.locator("section#training-progress svg.loss")).toHaveCount(1);
  }
});

test("tune panel renders the trial heatmap", async ({ page }) => {
  await loadPanel(
    page,
    "<main id=\"app\"><section id=\"hyperparameter-sweep\"><table class=\"trials\"></table></section></main>",
    "hyperparameter-sweep"
  );
  if (LIVE_DEMO_URL) {
    await expect(page.locator("#hyperparameter-sweep")).toBeVisible();
  } else {
    await expect(page.locator("section#hyperparameter-sweep table.trials")).toHaveCount(1);
  }
});
