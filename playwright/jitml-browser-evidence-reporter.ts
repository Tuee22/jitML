import type {
  FullConfig,
  FullResult,
  Reporter,
  Suite,
  TestCase,
  TestResult,
} from "@playwright/test/reporter";
import { createHmac } from "crypto";
import * as fs from "fs";
import * as path from "path";

export const BROWSER_CATALOGUE_FORMAT = "jitml-browser-catalogue-input";
export const BROWSER_RESULT_FORMAT = "jitml-browser-result-journal";
export const BROWSER_WIRE_VERSION = 1;
export const PRODUCT_ROW_COUNT = 55;

const RESULT_HMAC_DOMAIN = "jitml-browser-result-journal-hmac-v1";
const SHA256 = /^[0-9a-f]{64}$/;

export interface BrowserCatalogueRow {
  ordinal: number;
  row_id: string;
  plan_id: string;
  experiment_hash: string;
  manifest_sha256: string;
  contract_sha256: string;
  journal_sha256: string;
  measured_sha256: string;
  e2e_test: string;
  demo_panel: string;
  measured_result: string;
  status: "Passed";
}

export interface BrowserCatalogueInput {
  format: typeof BROWSER_CATALOGUE_FORMAT;
  version: typeof BROWSER_WIRE_VERSION;
  run_id: string;
  substrate: string;
  catalogue_sha256: string;
  source_journal_sha256: string;
  rows: BrowserCatalogueRow[];
}

type BrowserResultStatus = "Passed" | "Failed" | "NotRun";

interface BrowserResultRow {
  ordinal: number;
  row_id: string;
  plan_id: string;
  experiment_hash: string;
  manifest_sha256: string;
  e2e_test: string;
  status: BrowserResultStatus;
  detail: string;
}

interface BrowserResultJournal {
  format: typeof BROWSER_RESULT_FORMAT;
  version: typeof BROWSER_WIRE_VERSION;
  run_id: string;
  substrate: string;
  catalogue_sha256: string;
  source_journal_sha256: string;
  run_receipt_hmac_sha256: string;
  rows: BrowserResultRow[];
}

interface RetainedAttempt {
  retry: number;
  status: TestResult["status"];
  detail: string;
}

function requiredEnvironment(name: string): string {
  const value = process.env[name];
  if (value === undefined || value.trim() === "") {
    throw new Error(`live browser evidence requires ${name}`);
  }
  return value;
}

function exactObject(
  value: unknown,
  expectedKeys: readonly string[],
  label: string,
): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new Error(`${label} must be an object`);
  }
  const object = value as Record<string, unknown>;
  const observed = Object.keys(object).sort();
  const expected = [...expectedKeys].sort();
  if (observed.length !== expected.length || observed.some((key, index) => key !== expected[index])) {
    throw new Error(
      `${label} fields differ: expected ${expected.join(",")}; observed ${observed.join(",")}`,
    );
  }
  return object;
}

function exactString(object: Record<string, unknown>, key: string, label: string): string {
  const value = object[key];
  if (
    typeof value !== "string" ||
    value.length === 0 ||
    Array.from(value).length > 4096 ||
    value.trim() !== value ||
    /\p{Cc}/u.test(value)
  ) {
    throw new Error(
      `${label}.${key} must be one non-empty canonical string of at most 4096 Unicode code points`,
    );
  }
  return value;
}

function exactSha(object: Record<string, unknown>, key: string, label: string): string {
  const value = exactString(object, key, label);
  if (!SHA256.test(value)) {
    throw new Error(`${label}.${key} must be 64 lowercase hexadecimal characters`);
  }
  return value;
}

function exactOrdinal(object: Record<string, unknown>, expected: number, label: string): number {
  const value = object.ordinal;
  if (!Number.isSafeInteger(value) || value !== expected) {
    throw new Error(`${label}.ordinal must equal ${expected}`);
  }
  return value as number;
}

export function loadBrowserCatalogue(
  cataloguePath = requiredEnvironment("JITML_BROWSER_CATALOGUE_PATH"),
): BrowserCatalogueInput {
  let decoded: unknown;
  try {
    decoded = JSON.parse(fs.readFileSync(cataloguePath, "utf8"));
  } catch (error) {
    throw new Error(`could not decode browser catalogue input: ${errorDetail(error)}`);
  }

  const top = exactObject(
    decoded,
    [
      "format",
      "version",
      "run_id",
      "substrate",
      "catalogue_sha256",
      "source_journal_sha256",
      "rows",
    ],
    "browser catalogue input",
  );
  if (top.format !== BROWSER_CATALOGUE_FORMAT) {
    throw new Error(`browser catalogue input format must be ${BROWSER_CATALOGUE_FORMAT}`);
  }
  if (top.version !== BROWSER_WIRE_VERSION) {
    throw new Error(`browser catalogue input version must be ${BROWSER_WIRE_VERSION}`);
  }
  const runId = exactString(top, "run_id", "browser catalogue input");
  const substrate = exactString(top, "substrate", "browser catalogue input");
  if (!new Set(["linux-cpu", "linux-cuda", "apple-silicon"]).has(substrate)) {
    throw new Error(`browser catalogue input has unknown substrate ${substrate}`);
  }
  const catalogueSha = exactSha(top, "catalogue_sha256", "browser catalogue input");
  const sourceJournalSha = exactSha(
    top,
    "source_journal_sha256",
    "browser catalogue input",
  );
  if (!Array.isArray(top.rows) || top.rows.length !== PRODUCT_ROW_COUNT) {
    throw new Error(`browser catalogue input must contain exactly ${PRODUCT_ROW_COUNT} rows`);
  }

  const rows = top.rows.map((raw, ordinal) => {
    const label = `browser catalogue row ${ordinal}`;
    const row = exactObject(
      raw,
      [
        "ordinal",
        "row_id",
        "plan_id",
        "experiment_hash",
        "manifest_sha256",
        "contract_sha256",
        "journal_sha256",
        "measured_sha256",
        "e2e_test",
        "demo_panel",
        "measured_result",
        "status",
      ],
      label,
    );
    const status = exactString(row, "status", label);
    if (status !== "Passed") {
      throw new Error(`${label}.status must be Passed`);
    }
    return {
      ordinal: exactOrdinal(row, ordinal, label),
      row_id: exactString(row, "row_id", label),
      plan_id: exactSha(row, "plan_id", label),
      experiment_hash: exactString(row, "experiment_hash", label),
      manifest_sha256: exactSha(row, "manifest_sha256", label),
      contract_sha256: exactSha(row, "contract_sha256", label),
      journal_sha256: exactSha(row, "journal_sha256", label),
      measured_sha256: exactSha(row, "measured_sha256", label),
      e2e_test: exactString(row, "e2e_test", label),
      demo_panel: exactString(row, "demo_panel", label),
      measured_result: exactString(row, "measured_result", label),
      status: "Passed" as const,
    };
  });

  requireUnique(rows.map((row) => row.row_id), "row_id");
  requireUnique(rows.map((row) => `${row.row_id}\0${row.plan_id}`), "rowId+PlanId");
  requireUnique(rows.map((row) => row.experiment_hash), "experiment_hash");
  requireUnique(rows.map((row) => row.manifest_sha256), "manifest_sha256");
  requireUnique(rows.map((row) => row.e2e_test), "e2e_test");

  return {
    format: BROWSER_CATALOGUE_FORMAT,
    version: BROWSER_WIRE_VERSION,
    run_id: runId,
    substrate,
    catalogue_sha256: catalogueSha,
    source_journal_sha256: sourceJournalSha,
    rows,
  };
}

function requireUnique(values: readonly string[], label: string): void {
  if (new Set(values).size !== values.length) {
    throw new Error(`browser catalogue input contains duplicate ${label}`);
  }
}

function consumeSigningKey(): Buffer {
  const keyPath = requiredEnvironment("JITML_BROWSER_RESULT_KEY_FILE");
  let rendered: string;
  try {
    rendered = fs.readFileSync(keyPath, "utf8");
    fs.unlinkSync(keyPath);
  } catch (error) {
    throw new Error(`could not consume browser result signing key: ${errorDetail(error)}`);
  }
  if (!SHA256.test(rendered)) {
    throw new Error("browser result signing key must encode exactly 32 bytes as lowercase hex");
  }
  return Buffer.from(rendered, "hex");
}

function receiptField(label: string, value: string): string {
  return `${label}=${Buffer.byteLength(value, "utf8")}:${value}\n`;
}

function resultReceiptMaterial(journal: BrowserResultJournal): string {
  const fields: Array<readonly [string, string]> = [
    ["domain", RESULT_HMAC_DOMAIN],
    ["format", journal.format],
    ["version", String(journal.version)],
    ["run_id", journal.run_id],
    ["substrate", journal.substrate],
    ["catalogue_sha256", journal.catalogue_sha256],
    ["source_journal_sha256", journal.source_journal_sha256],
    ["row_count", String(journal.rows.length)],
  ];
  for (const row of journal.rows) {
    fields.push(
      ["ordinal", String(row.ordinal)],
      ["row_id", row.row_id],
      ["plan_id", row.plan_id],
      ["experiment_hash", row.experiment_hash],
      ["manifest_sha256", row.manifest_sha256],
      ["e2e_test", row.e2e_test],
      ["status", row.status],
      ["detail", row.detail],
    );
  }
  return fields.map(([label, value]) => receiptField(label, value)).join("");
}

function errorDetail(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function boundedDetail(raw: string): string {
  const canonical = raw.replace(/\p{Cc}+/gu, " ").trim();
  const retained = canonical === "" ? "Playwright did not retain failure detail" : canonical;
  return Array.from(retained).slice(0, 4096).join("");
}

function attemptDetail(result: TestResult): string {
  const errors = result.errors
    .map((error) => error.message ?? error.value ?? String(error))
    .filter((value) => value.trim() !== "");
  return boundedDetail(errors.join(" | ") || `Playwright final status was ${result.status}`);
}

class BrowserEvidenceReporter implements Reporter {
  private readonly catalogue: BrowserCatalogueInput;
  private readonly outputPath: string;
  private readonly signingKey: Buffer;
  private readonly attempts = new Map<string, RetainedAttempt>();
  private readonly testCardinality = new Map<string, number>();
  private configurationFailure: string | undefined;

  constructor() {
    this.catalogue = loadBrowserCatalogue();
    this.outputPath = requiredEnvironment("JITML_BROWSER_RESULT_PATH");
    if (fs.existsSync(this.outputPath)) {
      throw new Error("browser result path already exists; refusing stale journal overwrite");
    }
    const outputDirectory = path.dirname(this.outputPath);
    const stat = fs.statSync(outputDirectory);
    if (!stat.isDirectory()) {
      throw new Error("browser result parent is not a directory");
    }
    this.signingKey = consumeSigningKey();
  }

  onBegin(_config: FullConfig, suite: Suite): void {
    const expected = new Set(this.catalogue.rows.map((row) => row.e2e_test));
    for (const test of suite.allTests()) {
      if (expected.has(test.title)) {
        this.testCardinality.set(test.title, (this.testCardinality.get(test.title) ?? 0) + 1);
      }
    }
    const failures = this.catalogue.rows.flatMap((row) => {
      const count = this.testCardinality.get(row.e2e_test) ?? 0;
      return count === 1
        ? []
        : [`e2e_test ${row.e2e_test} has Playwright cardinality ${count}, expected 1`];
    });
    if (failures.length > 0) {
      this.configurationFailure = boundedDetail(failures.join(" | "));
    }
  }

  onTestEnd(test: TestCase, result: TestResult): void {
    if (!this.testCardinality.has(test.title)) {
      return;
    }
    const retained = this.attempts.get(test.title);
    if (retained === undefined || result.retry >= retained.retry) {
      this.attempts.set(test.title, {
        retry: result.retry,
        status: result.status,
        detail: result.status === "passed" ? "" : attemptDetail(result),
      });
    }
  }

  onEnd(_result: FullResult): void {
    const rows = this.catalogue.rows.map((source): BrowserResultRow => {
      if (this.configurationFailure !== undefined) {
        return resultRow(source, "NotRun", this.configurationFailure);
      }
      const attempt = this.attempts.get(source.e2e_test);
      if (attempt === undefined) {
        return resultRow(source, "NotRun", "Playwright did not run the planned browser row");
      }
      switch (attempt.status) {
        case "passed":
          return resultRow(source, "Passed", "");
        case "skipped":
        case "interrupted":
          return resultRow(source, "NotRun", attempt.detail);
        default:
          return resultRow(source, "Failed", attempt.detail);
      }
    });
    const unsigned: BrowserResultJournal = {
      format: BROWSER_RESULT_FORMAT,
      version: BROWSER_WIRE_VERSION,
      run_id: this.catalogue.run_id,
      substrate: this.catalogue.substrate,
      catalogue_sha256: this.catalogue.catalogue_sha256,
      source_journal_sha256: this.catalogue.source_journal_sha256,
      run_receipt_hmac_sha256: "",
      rows,
    };
    const tag = createHmac("sha256", this.signingKey)
      .update(resultReceiptMaterial(unsigned), "utf8")
      .digest("hex");
    this.signingKey.fill(0);
    const journal = { ...unsigned, run_receipt_hmac_sha256: tag };
    writeAtomicExclusive(this.outputPath, `${JSON.stringify(journal)}\n`);
  }
}

function resultRow(
  source: BrowserCatalogueRow,
  status: BrowserResultStatus,
  detail: string,
): BrowserResultRow {
  return {
    ordinal: source.ordinal,
    row_id: source.row_id,
    plan_id: source.plan_id,
    experiment_hash: source.experiment_hash,
    manifest_sha256: source.manifest_sha256,
    e2e_test: source.e2e_test,
    status,
    detail,
  };
}

function writeAtomicExclusive(outputPath: string, payload: string): void {
  const temporary = `${outputPath}.tmp-${process.pid}-${Date.now()}`;
  try {
    fs.writeFileSync(temporary, payload, { encoding: "utf8", flag: "wx", mode: 0o600 });
    // A same-directory hard link publishes the fully-written inode atomically
    // and, unlike rename(2), fails with EEXIST rather than replacing a result
    // that raced into place after the constructor's stale-output check.
    fs.linkSync(temporary, outputPath);
  } finally {
    if (fs.existsSync(temporary)) {
      fs.unlinkSync(temporary);
    }
  }
}

export default BrowserEvidenceReporter;
