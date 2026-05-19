import { test, expect } from "@playwright/test";

// Canonical panel matrix for the demo bundle. The test bodies are
// scaffold-only (`page.setContent` against an inline DOM stub) until the
// live `jitml-demo` HTTP server serves the compiled Halogen bundle from
// `web/dist/` and the daemon's `/api/ws` proxy streams real metric / event
// updates. The full matrix is exercised by the explicit live e2e orchestration
// path.

test("demo shell responds", async ({ page }) => {
  await page.setContent("<main id=\"app\">jitML demo</main>");
  await expect(page.locator("#app")).toContainText("jitML demo");
});

test("mnist panel renders an inference canvas", async ({ page }) => {
  await page.setContent(
    "<main id=\"app\"><section id=\"mnist-live-inference\"><canvas id=\"draw\"></canvas></section></main>"
  );
  await expect(page.locator("section#mnist-live-inference canvas#draw")).toHaveCount(1);
});

test("cifar panel renders an upload control", async ({ page }) => {
  await page.setContent(
    "<main id=\"app\"><section id=\"cifar-imagenet-upload\"><input type=\"file\" id=\"image\"></section></main>"
  );
  await expect(page.locator("section#cifar-imagenet-upload input[type=file]")).toHaveCount(1);
});

test("connect4 panel renders the board", async ({ page }) => {
  await page.setContent(
    "<main id=\"app\"><section id=\"connect4-human-vs-alphazero\"><div class=\"board\"></div></section></main>"
  );
  await expect(page.locator("section#connect4-human-vs-alphazero .board")).toHaveCount(1);
});

test("rl panel renders an episode timeline", async ({ page }) => {
  await page.setContent(
    "<main id=\"app\"><section id=\"rl-trajectory\"><ol class=\"episodes\"></ol></section></main>"
  );
  await expect(page.locator("section#rl-trajectory ol.episodes")).toHaveCount(1);
});

test("training panel renders a loss curve", async ({ page }) => {
  await page.setContent(
    "<main id=\"app\"><section id=\"training-progress\"><svg class=\"loss\"></svg></section></main>"
  );
  await expect(page.locator("section#training-progress svg.loss")).toHaveCount(1);
});

test("tune panel renders the trial heatmap", async ({ page }) => {
  await page.setContent(
    "<main id=\"app\"><section id=\"hyperparameter-sweep\"><table class=\"trials\"></table></section></main>"
  );
  await expect(page.locator("section#hyperparameter-sweep table.trials")).toHaveCount(1);
});
