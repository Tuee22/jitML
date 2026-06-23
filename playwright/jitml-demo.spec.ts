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
    "generic-inference-lab",
    "cifar-imagenet-upload",
    "checkpoint-compare-lab",
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

  const responsePromise = page.waitForResponse(
    (response) =>
      response.url().endsWith("/api/inference") &&
      response.request().method() === "POST",
  );
  await page.locator("#mnist-live-inference-submit").click();
  const response = await responsePromise;
  const body = await response.text();
  expect(response.ok()).toBeTruthy();
  expect(body).toContain("kind: InferenceResult");
  expect(body).toContain("checkpoint-sha:");
  await expect(page.locator("#mnist-live-inference-prediction")).toContainText(
    "predicted",
  );
});

test("generic inference panel renders checkpoint output", async ({ page }) => {
  await loadPanel(page, "generic-inference-lab");
  await expect(page.locator("#generic-inference-lab")).toBeVisible();

  const responsePromise = page.waitForResponse(
    (response) =>
      response.url().endsWith("/api/inference/generic") &&
      response.request().method() === "POST",
  );
  await page.locator("#generic-inference-lab-submit").click();
  const response = await responsePromise;
  const body = await response.text();
  expect(response.ok()).toBeTruthy();
  expect(body).toContain("kind: GenericInferenceResult");
  await expect(page.locator("#generic-inference-lab-result")).toBeVisible();
});

test("cifar panel renders an upload control", async ({ page }) => {
  await loadPanel(page, "cifar-imagenet-upload");
  await expect(page.locator("#cifar-imagenet-upload")).toBeVisible();

  const responsePromise = page.waitForResponse(
    (response) =>
      response.url().endsWith("/api/images") &&
      response.request().method() === "POST",
  );
  await page.locator("#cifar-imagenet-upload-submit").click();
  const response = await responsePromise;
  await expect(page.locator("#cifar-imagenet-upload-topk")).toBeVisible();
  await expect(page.locator("#cifar-imagenet-upload-topk li").first()).toBeVisible();
  expect(response.ok()).toBeTruthy();
  expect(await response.text()).toContain("kind: ImageInferenceResult");
});

test("checkpoint compare panel renders output deltas", async ({ page }) => {
  await loadPanel(page, "checkpoint-compare-lab");
  await expect(page.locator("#checkpoint-compare-lab")).toBeVisible();

  const responsePromise = page.waitForResponse(
    (response) =>
      response.url().endsWith("/api/checkpoints/compare") &&
      response.request().method() === "POST",
  );
  await page.locator("#checkpoint-compare-lab-submit").click();
  const response = await responsePromise;
  const body = await response.text();
  expect(response.ok()).toBeTruthy();
  expect(body).toContain("kind: CheckpointCompareResult");
  await expect(page.locator("#checkpoint-compare-lab-result")).toBeVisible();
});

test("connect4 panel renders the board", async ({ page }) => {
  await loadPanel(page, "connect4-human-vs-alphazero");
  await expect(page.locator("#connect4-human-vs-alphazero")).toBeVisible();

  const responsePromise = page.waitForResponse(
    (response) =>
      response.url().endsWith("/api/connect4/move") &&
      response.request().method() === "POST",
  );
  await page.locator("#connect4-human-vs-alphazero-move-0").click();
  const response = await responsePromise;
  expect(response.ok()).toBeTruthy();
  // Sprint 16.11 — the converged Webapp publishes the move command and the
  // `AdversarialMoveResult` (carrying the AI's `chosen-column`) streams back over
  // `/api/ws/inference`; the POST returns the publish ack. Assert the result on the
  // websocket-rendered moves list — the human move `0` followed by the AI's chosen
  // numeric column — rather than reading the column from the synchronous ack body.
  expect(await response.text()).toContain("kind: AdversarialMoveResult");
  await expect(page.locator("#connect4-human-vs-alphazero-moves")).toContainText(
    /moves: \[0,\s*[0-9]+\]/,
  );
});

test("checkpoint browse panel lists seeded checkpoints", async ({ page }) => {
  // Sprint 14.1 (Feature A) — the panel POSTs `/api/checkpoints` on init; the
  // Engine lists the five seeded experiments' manifests from MinIO and replies
  // with a `CheckpointList` frame over `/api/ws/inference`, which the panel
  // renders as a list. Assert at least one item appears.
  const responsePromise = page.waitForResponse(
    (response) =>
      response.url().endsWith("/api/checkpoints") &&
      response.request().method() === "POST",
  );
  await loadPanel(page, "checkpoint-browse");
  await expect(page.locator("#checkpoint-browse")).toBeVisible();
  const response = await responsePromise;
  expect(response.ok()).toBeTruthy();
  expect(await response.text()).toContain("kind: CheckpointList");
  await expect(page.locator("#checkpoint-browse-list")).toBeVisible();
  await expect(
    page.locator("#checkpoint-browse-list li").first(),
  ).toBeVisible();
});

test("workflow status panel renders a live status table", async ({ page }) => {
  // Sprint 14.1 (Feature C) — the panel subscribes to `/api/ws/workflow` and
  // renders the Engine's reconciled `WorkflowStatus` frames as a live table.
  await loadPanel(page, "workflow-status");
  await expect(page.locator("#workflow-status")).toBeVisible();
  await expect(page.locator("#workflow-status-table")).toBeVisible();
});

test("transcript replay scrubs a persisted adversarial game", async ({
  page,
}) => {
  // Sprint 14.1 (Feature B) — play a connect4 move to completion, capture the
  // persisted `transcript-id` streamed back on the websocket move frame, load it
  // in the replay panel, and assert the scrubber steps through the persisted
  // moves.
  await loadPanel(page, "connect4-human-vs-alphazero");
  await expect(page.locator("#connect4-human-vs-alphazero")).toBeVisible();

  // Play a move; the panel renders the AI's `AdversarialMoveResult`, which
  // carries the real persisted `transcript-id` (the MinIO object key). Read it
  // from the panel DOM — reliable, since the panel's own websocket subscription
  // receives the frame, and tolerant of the cold-JIT first-move latency via the
  // expect timeout.
  await page.locator("#connect4-human-vs-alphazero-move-0").click();
  const transcriptLocator = page.locator(
    "#connect4-human-vs-alphazero-transcript",
  );
  // A real persisted transcript id is the content-addressed MinIO key
  // (`transcripts/<hash>.cbor`), not the synthesized fallback string.
  await expect(transcriptLocator).toContainText("transcripts/");
  const transcriptText = (await transcriptLocator.textContent()) ?? "";
  const transcriptId = transcriptText.replace(/^\s*transcript:\s*/, "").trim();
  expect(transcriptId.length).toBeGreaterThan(0);

  // Load the captured transcript in the replay panel and scrub it.
  const replayResponsePromise = page.waitForResponse(
    (response) =>
      response.url().endsWith("/api/transcripts/replay") &&
      response.request().method() === "POST",
  );
  await loadPanel(page, "transcript-replay");
  await expect(page.locator("#transcript-replay")).toBeVisible();
  await page.locator("#transcript-replay-transcript-id").fill(transcriptId);
  await page.locator("#transcript-replay-transcript-load").click();
  const replayResponse = await replayResponsePromise;
  expect(replayResponse.ok()).toBeTruthy();

  // The streamed `TranscriptReplay` populates the persisted moves; stepping the
  // scrubber advances the cursor through them.
  await expect(page.locator("#transcript-replay-moves")).toContainText("moves:");
  await page.locator("#transcript-replay-replay-next").click();
  await expect(page.locator("#transcript-replay-replay-cursor")).toContainText(
    "/",
  );
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
