import { test, expect } from "@playwright/test";

test("demo shell responds", async ({ page }) => {
  await page.setContent("<main id=\"app\">jitML demo</main>");
  await expect(page.locator("#app")).toContainText("jitML demo");
});
