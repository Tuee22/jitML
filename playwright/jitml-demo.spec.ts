import { test, expect } from "@playwright/test";
import type { Locator, Page, Route } from "@playwright/test";
import * as fs from "fs";
import {
  PRODUCT_ROW_COUNT,
  loadBrowserCatalogue,
} from "./jitml-browser-evidence-reporter";
import type {
  BrowserCatalogueInput,
  BrowserCatalogueRow,
} from "./jitml-browser-evidence-reporter";

// Phase 262: the positive matrix is instantiated exclusively from the exact
// command-owned catalogue. The checked-in Generated.Contracts module is not an
// evidence source, and positive cases never route-mock the live API.
interface ClusterPublication {
  edge_port: number;
  substrate: string;
  pulsar_url: string;
  minio_url: string;
  components: Array<{ name: string; status: string }>;
  evidence: string | null;
}

const CATALOGUE: BrowserCatalogueInput = loadBrowserCatalogue();

function requiredEnvironment(name: string): string {
  const value = process.env[name];
  if (value === undefined || value.trim() === "") {
    throw new Error(`live demo Playwright requires ${name}`);
  }
  return value;
}

function loadLivePublication(): ClusterPublication {
  const publicationPath = requiredEnvironment("JITML_BROWSER_PUBLICATION_PATH");
  try {
    const decoded: unknown = JSON.parse(fs.readFileSync(publicationPath, "utf8"));
    if (typeof decoded !== "object" || decoded === null || Array.isArray(decoded)) {
      throw new Error("cluster publication must be an object");
    }
    const parsed = decoded as Record<string, unknown>;
    const expectedKeys = [
      "components",
      "edge_port",
      "evidence",
      "minio_url",
      "pulsar_url",
      "substrate",
    ];
    const observedKeys = Object.keys(parsed).sort();
    if (
      observedKeys.length !== expectedKeys.length ||
      observedKeys.some((key, index) => key !== expectedKeys[index])
    ) {
      throw new Error("cluster publication fields differ from the frozen wire");
    }
    if (
      !Number.isSafeInteger(parsed.edge_port) ||
      (parsed.edge_port as number) < 1 ||
      (parsed.edge_port as number) > 65535
    ) {
      throw new Error("cluster publication edge_port is not a valid TCP port");
    }
    for (const key of ["substrate", "pulsar_url", "minio_url"] as const) {
      const value = parsed[key];
      if (
        typeof value !== "string" ||
        value.length === 0 ||
        value.trim() !== value ||
        /\p{Cc}/u.test(value)
      ) {
        throw new Error(`cluster publication ${key} must be one non-empty canonical string`);
      }
    }
    const publicationSubstrate = parsed.substrate as string;
    const selectedSubstrate = requiredEnvironment("JITML_SUBSTRATE");
    if (
      publicationSubstrate !== selectedSubstrate ||
      publicationSubstrate !== CATALOGUE.substrate
    ) {
      throw new Error(
        `publication/catalogue substrate mismatch: publication=${publicationSubstrate}, catalogue=${CATALOGUE.substrate}, selected=${selectedSubstrate}`,
      );
    }
    if (!Array.isArray(parsed.components) || parsed.components.length === 0) {
      throw new Error("cluster publication components must be a non-empty array");
    }
    const requiredComponents = [
      "harbor",
      "minio",
      "pulsar",
      "postgres",
      "observability",
      ...(publicationSubstrate === "apple-silicon" ? [] : ["jitml-engine"]),
      "jitml-coordinator",
      "jitml-demo",
      "edge",
    ];
    const observedComponents: string[] = [];
    for (const component of parsed.components) {
      if (
        typeof component !== "object" || component === null || Array.isArray(component) ||
        Object.keys(component).sort().join(",") !== "name,status" ||
        typeof (component as Record<string, unknown>).name !== "string" ||
        (component as Record<string, unknown>).status !== "ready"
      ) {
        throw new Error("cluster publication contains a malformed or non-ready component");
      }
      observedComponents.push((component as Record<string, unknown>).name as string);
    }
    if (
      observedComponents.length !== requiredComponents.length ||
      new Set(observedComponents).size !== observedComponents.length ||
      requiredComponents.some((name) => !observedComponents.includes(name))
    ) {
      throw new Error("cluster publication component set is incomplete, duplicated, or unexpected");
    }
    if (parsed.evidence !== "live-readiness") {
      throw new Error("cluster publication lacks exact live-readiness evidence");
    }
    const publication = parsed as unknown as ClusterPublication;
    return publication;
  } catch (error) {
    throw error instanceof Error
      ? error
      : new Error("failed to read exact cluster publication");
  }
}

const PUBLICATION = loadLivePublication();
const LIVE_DEMO_URL = `http://127.0.0.1:${PUBLICATION.edge_port}/`;
const PRODUCT_ROWS = CATALOGUE.rows;
const EXPECTED_MODEL_NAMES = PRODUCT_ROWS.map((row) => row.row_id);

async function loadShell(page: Page): Promise<void> {
  await page.goto(LIVE_DEMO_URL);
  await page.locator("main#app").waitFor({ state: "attached", timeout: 10000 });
}

async function loadPanel(page: Page, panelId: string): Promise<void> {
  await page.goto(`${LIVE_DEMO_URL}#${panelId}`);
  await page.locator(`#${panelId}`).waitFor({ state: "attached", timeout: 10000 });
}

function artifactCard(page: Page, row: BrowserCatalogueRow): Locator {
  return page.locator(`#checkpoint-browse-artifact-${row.ordinal}`);
}

async function loadLiveProductRowArtifacts(page: Page): Promise<void> {
  const responsePromise = page.waitForResponse(
    (response) =>
      response.url().endsWith("/api/checkpoints") &&
      response.request().method() === "POST",
  );
  await loadPanel(page, "checkpoint-browse");
  const response = await responsePromise;
  expect(response.ok()).toBeTruthy();

  await expect(page.locator("#checkpoint-browse-status")).toHaveText(
    `Passed: ${PRODUCT_ROW_COUNT}; Failed: 0; NotRun: 0; complete publication-bound checkpoint evidence`,
  );
  await expect(page.locator("#checkpoint-browse-run-id")).toHaveText(`run-id: ${CATALOGUE.run_id}`);
  await expect(page.locator("#checkpoint-browse-substrate")).toHaveText(`substrate: ${CATALOGUE.substrate}`);
  await expect(page.locator("#checkpoint-browse-catalogue-sha256")).toHaveText(
    `catalogue-sha256: ${CATALOGUE.catalogue_sha256}`,
  );
  await expect(page.locator("#checkpoint-browse-source-journal-sha256")).toHaveText(
    `source-journal-sha256: ${CATALOGUE.source_journal_sha256}`,
  );
}

async function assertLiveProductRowArtifact(
  page: Page,
  row: BrowserCatalogueRow,
): Promise<void> {
  const prefix = `checkpoint-browse-artifact-${row.ordinal}`;
  const artifact = artifactCard(page, row);
  await expect(artifact).toBeVisible();
  await expect(artifact.locator(`#${prefix}-row-id`)).toHaveText(`row: ${row.row_id}`);
  await expect(artifact.locator(`#${prefix}-plan-id`)).toHaveText(`PlanId: ${row.plan_id}`);
  await expect(artifact.locator(`#${prefix}-experiment-hash`)).toHaveText(
    `experiment: ${row.experiment_hash}`,
  );
  await expect(artifact.locator(`#${prefix}-manifest-sha256`)).toHaveText(
    `manifest: ${row.manifest_sha256}`,
  );
  await expect(artifact.locator(`#${prefix}-status`)).toHaveText("status: Passed");
  await expect(artifact.locator(`#${prefix}-reason`)).toHaveText("reason: (none)");
  await expect(page.locator(`#checkpoint-browse-summary-${row.ordinal}-measured-result`)).toHaveText(
    `measured-result: ${row.measured_result}`,
  );
  await assertFamilyRenderer(row, artifact);
}

async function assertFamilyRenderer(row: BrowserCatalogueRow, artifact: Locator): Promise<void> {
  switch (rowFamily(row)) {
    case "supervised":
      await expect(artifact.locator(".artifact-supervised-renderer")).toBeVisible();
      await expect(artifact).toContainText("input:");
      await expect(artifact).toContainText(
        row.row_id === "california-housing-mlp"
          ? "output: regression value"
          : "output: class probabilities",
      );
      break;
    case "rl":
      await expect(artifact.locator(".artifact-rl-renderer")).toBeVisible();
      await expect(artifact).toContainText(`policy row: ${row.row_id}`);
      await expect(artifact).toContainText("action metadata:");
      break;
    case "alphazero":
      await expect(artifact.locator(".artifact-alphazero-renderer")).toBeVisible();
      await expect(artifact).toContainText("policy/value:");
      await expect(artifact).toContainText(`replay panel: ${row.demo_panel}`);
      break;
    case "tuning":
      await expect(artifact.locator(".artifact-tuning-renderer")).toBeVisible();
      await expect(artifact).toContainText(`sweep: ${row.row_id}`);
      await expect(artifact).toContainText("trial table:");
      break;
  }
}

function rowFamily(row: BrowserCatalogueRow): "supervised" | "rl" | "alphazero" | "tuning" {
  if (row.demo_panel === "rl-trajectory") return "rl";
  if (row.demo_panel === "connect4-human-vs-alphazero") return "alphazero";
  if (row.demo_panel === "hyperparameter-sweep") return "tuning";
  return "supervised";
}

function checkpointListFixture(
  mutateSelector?: (line: string, row: BrowserCatalogueRow) => string,
  mutateSummary?: (line: string, row: BrowserCatalogueRow) => string,
): string {
  const selectors = PRODUCT_ROWS.map((row) => {
    const line = [
      row.ordinal,
      row.row_id,
      row.plan_id,
      row.experiment_hash,
      row.manifest_sha256,
      rowFamily(row),
      "Passed",
      "",
      row.demo_panel,
    ].join("\t");
    return `row-selector: ${mutateSelector?.(line, row) ?? line}`;
  });
  const summaries = PRODUCT_ROWS.map((row) => {
    const line = [
      row.ordinal,
      row.row_id,
      row.plan_id,
      row.experiment_hash,
      row.manifest_sha256,
      1,
      rowFamily(row),
      1,
      "eligible",
      "bounded-live-budget",
      row.measured_result,
      `jitml-tensorboard/${row.experiment_hash}`,
    ].join("\t");
    return `checkpoint-summary: ${mutateSummary?.(line, row) ?? line}`;
  });
  return [
    "kind: CheckpointList",
    "call-id: playwright-negative-fixture",
    "panel: checkpoint-browse",
    "status: published",
    `run-id: ${CATALOGUE.run_id}`,
    `substrate: ${CATALOGUE.substrate}`,
    `catalogue-sha256: ${CATALOGUE.catalogue_sha256}`,
    `source-journal-sha256: ${CATALOGUE.source_journal_sha256}`,
    `count: ${PRODUCT_ROW_COUNT}`,
    "selector-state: ready",
    ...selectors,
    ...summaries,
    "",
  ].join("\n");
}

async function withCheckpointBrowseRoute(
  page: Page,
  status: number,
  body: string,
  assertion: () => Promise<void>,
): Promise<void> {
  const handler = async (route: Route): Promise<void> => {
    await route.fulfill({ status, contentType: "text/plain; charset=utf-8", body });
  };
  await page.route("**/api/checkpoints", handler);
  try {
    await page.goto(`${LIVE_DEMO_URL}#portals`);
    await loadPanel(page, "checkpoint-browse");
    await assertion();
  } finally {
    await page.unroute("**/api/checkpoints", handler);
  }
}

async function assertMissingClusterFailClosed(page: Page): Promise<void> {
  await withCheckpointBrowseRoute(
    page,
    503,
    [
      "checkpoint-required: checkpoint-browse",
      "reason: missing live cluster publication",
      "selector-state: fail-closed:missing-cluster",
      "status: failed",
      "",
    ].join("\n"),
    async () => {
      await expect(page.locator("#checkpoint-browse-error")).toContainText(
        "checkpoint-required: checkpoint-browse",
      );
      await expect(page.locator("#checkpoint-browse-error")).toContainText(
        "fail-closed:missing-cluster",
      );
    },
  );
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
  await page.locator("#mnist-live-inference-ink").fill("0.42");

  const responsePromise = page.waitForResponse(
    (response) =>
      response.url().endsWith("/api/inference") &&
      response.request().method() === "POST",
  );
  await page.locator("#mnist-live-inference-submit").click();
  const response = await responsePromise;
  const body = await response.text();
  expect(response.request().postData() ?? "").toContain("input: 0.42,0.42");
  expect(response.request().postData() ?? "").toContain(
    "experiment-hash: product-row-mnist-deep-mlp",
  );
  expect(response.request().postData() ?? "").not.toContain("-demo-weights");
  expect(response.ok()).toBeTruthy();
  expect(body).toContain("kind: InferenceResult");
  expect(body).toContain("checkpoint-sha:");
  expect(body).not.toContain("-demo-weights");
  await expect(page.locator("#mnist-live-inference-prediction")).toContainText(
    "predicted",
  );
  await expect(page.locator("#mnist-live-inference-distribution li")).toHaveCount(
    10,
  );
});

test("mnist panel renders checkpoint-required fail-closed responses", async ({
  page,
}) => {
  await page.route("**/api/inference", async (route) => {
    await route.fulfill({
      status: 503,
      contentType: "text/plain; charset=utf-8",
      body:
        "checkpoint-required: inference\n" +
        "reason: pointer read failed: missing latest pointer\n" +
        "selector-state: fail-closed:no-inference-eligible-artifact\n" +
        "status: failed\n",
    });
  });
  await loadPanel(page, "mnist-live-inference");
  await expect(page.locator("#mnist-live-inference")).toBeVisible();

  const responsePromise = page.waitForResponse(
    (response) =>
      response.url().endsWith("/api/inference") &&
      response.request().method() === "POST",
  );
  await page.locator("#mnist-live-inference-submit").click();
  const response = await responsePromise;
  expect(response.status()).toBe(503);
  await expect(page.locator("#mnist-live-inference-error")).toContainText(
    "checkpoint-required: inference",
  );
  await expect(page.locator("#mnist-live-inference-error")).toContainText(
    "fail-closed:no-inference-eligible-artifact",
  );
});

test("generic inference panel renders checkpoint output", async ({ page }) => {
  await loadPanel(page, "generic-inference-lab");
  await expect(page.locator("#generic-inference-lab")).toBeVisible();
  await page.locator("#generic-inference-lab-input-0").fill("0.9");

  const responsePromise = page.waitForResponse(
    (response) =>
      response.url().endsWith("/api/inference/generic") &&
      response.request().method() === "POST",
  );
  await page.locator("#generic-inference-lab-submit").click();
  const response = await responsePromise;
  const body = await response.text();
  expect(response.request().postData() ?? "").toContain(
    "experiment-hash: product-row-california-housing-mlp",
  );
  expect(response.request().postData() ?? "").toContain(
    "input: 0.9,-0.5,1.0,2.0,0.0,0.0,0.0,1.0",
  );
  expect(response.request().postData() ?? "").not.toContain("generic-tensor-demo");
  expect(response.ok()).toBeTruthy();
  expect(body).toContain("kind: GenericInferenceResult");
  expect(body).not.toContain("-demo-weights");
  await expect(page.locator("#generic-inference-lab-result")).toBeVisible();
  await expect(page.locator("#generic-inference-lab-output li")).toHaveCount(3);
});

test("cifar panel renders an upload control", async ({ page }) => {
  await loadPanel(page, "cifar-imagenet-upload");
  await expect(page.locator("#cifar-imagenet-upload")).toBeVisible();
  await page.locator("#cifar-imagenet-upload-file").setInputFiles({
    name: "sample-cifar.bin",
    mimeType: "application/octet-stream",
    buffer: Buffer.from([1, 2, 3, 4]),
  });

  const responsePromise = page.waitForResponse(
    (response) =>
      response.url().endsWith("/api/images") &&
      response.request().method() === "POST",
  );
  await page.locator("#cifar-imagenet-upload-submit").click();
  const response = await responsePromise;
  await expect(page.locator("#cifar-imagenet-upload-topk")).toBeVisible();
  await expect(page.locator("#cifar-imagenet-upload-topk li")).toHaveCount(10);
  expect(response.ok()).toBeTruthy();
  const postData = response.request().postData() ?? "";
  expect(postData).toContain("sample-cifar.bin");
  expect(postData).toContain("experiment-hash: product-row-cifar10-resnet20");
  expect(postData).not.toContain("experiment-hash: cifar-imagenet\n");
  expect(postData).not.toContain("-demo-weights");
  expect(postData).toContain("input: 1.0,1.0");
  const body = await response.text();
  expect(body).toContain("kind: ImageInferenceResult");
  expect(body).not.toContain("-demo-weights");
});

test("checkpoint compare panel renders output deltas", async ({ page }) => {
  await loadPanel(page, "checkpoint-compare-lab");
  await expect(page.locator("#checkpoint-compare-lab")).toBeVisible();
  await page.locator("#checkpoint-compare-lab-input-0").fill("0.7");

  const responsePromise = page.waitForResponse(
    (response) =>
      response.url().endsWith("/api/checkpoints/compare") &&
      response.request().method() === "POST",
  );
  await page.locator("#checkpoint-compare-lab-submit").click();
  const response = await responsePromise;
  const body = await response.text();
  // Both compared rows are MNIST classifiers, so every value must stay inside
  // the unit-image domain the trained runtime declares.
  expect(response.request().postData() ?? "").toContain("input: 0.7,0.5,1.0,0.0");
  expect(response.request().postData() ?? "").toContain(
    "baseline-experiment-hash: product-row-mnist-shallow-mlp",
  );
  expect(response.request().postData() ?? "").toContain(
    "candidate-experiment-hash: product-row-mnist-deep-mlp",
  );
  expect(response.request().postData() ?? "").not.toContain("generic-tensor-demo");
  expect(response.ok()).toBeTruthy();
  expect(body).toContain("kind: CheckpointCompareResult");
  expect(body).not.toContain("-demo-weights");
  await expect(page.locator("#checkpoint-compare-lab-result")).toBeVisible();
  await expect(page.locator("#checkpoint-compare-lab-baseline-output li")).toHaveCount(
    3,
  );
  await expect(page.locator("#checkpoint-compare-lab-candidate-output li")).toHaveCount(
    3,
  );
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
  expect(response.request().postData() ?? "").toContain(
    "experiment-hash: product-row-connect4",
  );
  expect(response.request().postData() ?? "").not.toContain("-demo-weights");
  // Sprint 16.11 — the converged Webapp publishes the move command and the
  // `AdversarialMoveResult` (carrying the AI's `chosen-column`) streams back over
  // `/api/ws/inference`; the POST returns the publish ack. Assert the result on the
  // websocket-rendered moves list — the human move `0` followed by the AI's chosen
  // numeric column — rather than reading the column from the synchronous ack body.
  const body = await response.text();
  expect(body).toContain("kind: AdversarialMoveResult");
  expect(body).not.toContain("-demo-weights");
  await expect(page.locator("#connect4-human-vs-alphazero-moves")).toContainText(
    /moves: \[0,\s*[0-9]+\]/,
  );
});

test("adversarial game selectors submit product-row policy-value hashes", async ({
  page,
}) => {
  await loadPanel(page, "connect4-human-vs-alphazero");
  const games: ReadonlyArray<{
    name: string;
    hash: string;
    move: number;
    cell: number;
  }> = [
    { name: "othello", hash: "product-row-othello", move: 19, cell: 19 },
    { name: "hex", hash: "product-row-hex", move: 0, cell: 0 },
    { name: "gomoku", hash: "product-row-gomoku", move: 0, cell: 0 },
  ];

  for (const game of games) {
    await page.locator(`#connect4-human-vs-alphazero-game-${game.name}`).click();
    const responsePromise = page.waitForResponse(
      (response) =>
        response.url().endsWith("/api/connect4/move") &&
        response.request().method() === "POST",
    );
    await page
      .locator("#connect4-human-vs-alphazero-grid button")
      .nth(game.cell)
      .click();
    const response = await responsePromise;
    const postData = response.request().postData() ?? "";
    expect(response.ok()).toBeTruthy();
    expect(postData).toContain(`game: ${game.name}`);
    expect(postData).toContain(`experiment-hash: ${game.hash}`);
    expect(postData).not.toContain("-demo-weights");
    expect(postData).toContain(`moves: ${game.move}`);
    await expect(page.locator("#connect4-human-vs-alphazero-moves")).toContainText(
      new RegExp(`moves: \\[${game.move},\\s*[0-9]+\\]`),
    );
  }
});

test("checkpoint browse panel lists eligible checkpoints and every model row", async ({ page }) => {
  const responsePromise = page.waitForResponse(
    (response) =>
      response.url().endsWith("/api/checkpoints") &&
      response.request().method() === "POST",
  );
  await loadPanel(page, "checkpoint-browse");
  await expect(page.locator("#checkpoint-browse")).toBeVisible();
  const response = await responsePromise;
  expect(response.ok()).toBeTruthy();
  await expect(page.locator("#checkpoint-browse-selector-state")).toHaveText(
    "selector-state: ready",
  );
  await expect(page.locator("#checkpoint-browse-row-count")).toHaveText(
    `count: ${PRODUCT_ROW_COUNT}`,
  );
  await expect(page.locator("#checkpoint-browse-list")).toBeVisible();
  const firstCheckpoint = page.locator("#checkpoint-browse-list li").first();
  await expect(firstCheckpoint).toBeVisible();
  await expect(firstCheckpoint).toContainText("eligibility: eligible");
  await expect(firstCheckpoint).toContainText("budget:");
  await expect(firstCheckpoint).toContainText("measured-result:");
  await expect(firstCheckpoint).toContainText("jitml-tensorboard/");
  await expect(firstCheckpoint.locator("a[href^='/tensorboard/#']")).toBeVisible();
  const checkpointText = (await page.locator("#checkpoint-browse-list").textContent()) ?? "";
  expect(checkpointText).not.toContain("partial");
  expect(checkpointText).not.toContain("untrained");
  expect(checkpointText).not.toContain("smoke");
  expect(checkpointText).not.toContain("fake-runtime");
  expect(checkpointText).not.toContain("-demo-weights");

  const modelRows = page.locator("#checkpoint-browse-model-matrix-list li");
  await expect(modelRows).toHaveCount(EXPECTED_MODEL_NAMES.length);
  const matrix = page.locator("#checkpoint-browse-model-matrix-list");
  for (const modelName of EXPECTED_MODEL_NAMES) {
    await expect(matrix).toContainText(`model: ${modelName}`);
  }
  await expect(matrix).toContainText("status: Passed");
  await expect(matrix).toContainText("experiment: product-row-mnist-deep-mlp");
  await expect(matrix).not.toContainText("-demo-weights");
  await expect(page.locator("#checkpoint-browse-artifact-renderers")).not.toContainText(
    "-demo-weights",
  );
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

test("hash navigation closes the disposed panel WebSocket", async ({ page }) => {
  await page.addInitScript(() => {
    const NativeWebSocket = window.WebSocket;
    const lifecycle = { opened: 0, closeCalls: 0, callbacksCleared: 0 };
    Object.defineProperty(window, "__jitmlWebSocketLifecycle", {
      configurable: true,
      value: lifecycle,
    });
    class TrackedWebSocket extends NativeWebSocket {
      constructor(url: string | URL, protocols?: string | string[]) {
        super(url, protocols);
        lifecycle.opened += 1;
      }

      override close(code?: number, reason?: string): void {
        lifecycle.closeCalls += 1;
        if (
          this.onmessage === null &&
          this.onerror === null &&
          this.onclose === null
        ) {
          lifecycle.callbacksCleared += 1;
        }
        super.close(code, reason);
      }
    }
    Object.defineProperty(window, "WebSocket", {
      configurable: true,
      value: TrackedWebSocket,
    });
  });
  await loadPanel(page, "mnist-live-inference");
  await expect
    .poll(() =>
      page.evaluate(() =>
        (window as typeof window & {
          __jitmlWebSocketLifecycle: {
            opened: number;
            closeCalls: number;
            callbacksCleared: number;
          };
        }).__jitmlWebSocketLifecycle.opened
      )
    )
    .toBeGreaterThan(0);
  await page.evaluate(() => {
    window.location.hash = "portals";
  });
  await expect(page.locator("#portals")).toBeVisible();
  await expect
    .poll(() =>
      page.evaluate(() =>
        (window as typeof window & {
          __jitmlWebSocketLifecycle: {
            opened: number;
            closeCalls: number;
            callbacksCleared: number;
          };
        }).__jitmlWebSocketLifecycle
      )
    )
    .toEqual({ opened: 1, closeCalls: 1, callbacksCleared: 1 });
});

test("tune panel renders the trial heatmap", async ({ page }) => {
  await loadPanel(page, "hyperparameter-sweep");
  await expect(page.locator("#hyperparameter-sweep")).toBeVisible();
});

test.describe("CheckpointList fail-closed contract fixtures", () => {
  test("rejects a full 55-row frame with an unknown field", async ({ page }) => {
    const body = checkpointListFixture().replace(
      "selector-state: ready\n",
      "selector-state: ready\nunexpected-field: forbidden\n",
    );
    await withCheckpointBrowseRoute(page, 200, body, async () => {
      await expect(page.locator("#checkpoint-browse-status")).toContainText("request: Failed");
      await expect(page.locator("#checkpoint-browse-error")).toContainText(
        "malformed CheckpointList frame",
      );
    });
  });

  test("rejects a full 55-row manifest identity mismatch", async ({ page }) => {
    const body = checkpointListFixture((line, row) =>
      row.ordinal === 0
        ? line.replace(row.manifest_sha256, "f".repeat(64))
        : line,
    );
    await withCheckpointBrowseRoute(page, 200, body, async () => {
      await expect(page.locator("#checkpoint-browse-status")).toContainText("Failed:");
      await expect(page.locator("#checkpoint-browse-error")).toContainText(
        "selectors and summaries are not an exact identity bijection",
      );
      await expect(page.locator("#checkpoint-browse-artifact-renderers")).toHaveCount(0);
    });
  });

  test("rejects full 55-row explicit Failed evidence", async ({ page }) => {
    const body = checkpointListFixture(
      (line, row) =>
        row.ordinal === 0
          ? line.replace("\tPassed\t\t", "\tFailed\tfixture source failure\t")
          : line,
      (line, row) =>
        row.ordinal === 0 ? line.replace("\teligible\t", "\tunavailable\t") : line,
    );
    await withCheckpointBrowseRoute(page, 200, body, async () => {
      await expect(page.locator("#checkpoint-browse-status")).toContainText("Failed:");
      await expect(page.locator("#checkpoint-browse-error")).toContainText(
        "non-Passed source evidence",
      );
    });
  });

  test("rejects full 55-row explicit NotRun evidence", async ({ page }) => {
    const body = checkpointListFixture(
      (line, row) =>
        row.ordinal === 0
          ? line.replace("\tPassed\t\t", "\tNotRun\tfixture was not executed\t")
          : line,
      (line, row) =>
        row.ordinal === 0 ? line.replace("\teligible\t", "\tunavailable\t") : line,
    );
    await withCheckpointBrowseRoute(page, 200, body, async () => {
      await expect(page.locator("#checkpoint-browse-status")).toContainText("Failed:");
      await expect(page.locator("#checkpoint-browse-error")).toContainText(
        "non-Passed source evidence",
      );
    });
  });

  test("renders a missing-cluster API failure without Passed fallback", async ({ page }) => {
    await assertMissingClusterFailClosed(page);
    await expect(page.locator("#checkpoint-browse-status")).toContainText("Failed:");
    await expect(page.locator("#checkpoint-browse-artifact-renderers")).toHaveCount(0);
  });
});

test.describe("ProductRow artifact-backed e2e matrix", () => {
  test.describe.configure({ mode: "serial" });

  let evidencePage: Page;

  test.beforeAll(async ({ browser }) => {
    evidencePage = await browser.newPage();
    await loadLiveProductRowArtifacts(evidencePage);
  });

  test.afterAll(async () => {
    await evidencePage?.close();
  });

  for (const row of PRODUCT_ROWS) {
    test(row.e2e_test, async () => {
      await assertLiveProductRowArtifact(evidencePage, row);
    });
  }
});
