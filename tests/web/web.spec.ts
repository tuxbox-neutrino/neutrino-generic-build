import { test, expect } from '@playwright/test';

const baseUrl = process.env.NEUTRINO_WEB_BASE_URL;
test.skip(!baseUrl, 'NEUTRINO_WEB_BASE_URL not defined – skipping web smoke test.');

test('loads dashboard', async ({ page }) => {
  await page.goto(baseUrl!);
  await expect(page).toHaveTitle(/neutrino/i);
});
