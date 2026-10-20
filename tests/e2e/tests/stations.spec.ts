import { expect, test } from '@playwright/test';
import { openScreen, requireBaseUrl } from './helpers';

test.beforeEach(requireBaseUrl);

test.describe('Stations list', () => {
  test('search narrows results and survives reload via URL', async ({ page }) => {
    await openScreen(page, 'Stations', 'screen-stations');
    const rows = page.getByTestId('stations-table').locator('tbody tr');
    const before = await rows.count();

    await page.getByTestId('search').fill('changi');
    await expect(rows).not.toHaveCount(before);
    await expect(rows.first()).toContainText(/changi/i);

    await page.reload();
    await expect(page.getByTestId('search')).toHaveValue('changi');
  });

  test('region filter and sort', async ({ page }) => {
    await openScreen(page, 'Stations', 'screen-stations');
    await page.getByTestId('filter-region').selectOption({ label: 'West' });
    const regions = page.getByTestId('stations-table').locator('tbody tr td[data-col="region"]');
    await expect(regions.first()).toHaveText('West');
    for (const text of await regions.allTextContents()) expect(text.trim()).toBe('West');

    await page.getByTestId('stations-table').getByRole('columnheader', { name: /Temperature/ }).click();
    const temps = (await page.locator('tbody td[data-col="air-temperature"]').allTextContents())
      .map((t) => parseFloat(t)).filter((n) => !Number.isNaN(n));
    expect(temps).toEqual([...temps].sort((a, b) => a - b));
  });

  test('pagination', async ({ page }) => {
    await openScreen(page, 'Stations', 'screen-stations');
    const first = await page.locator('tbody tr').first().textContent();
    await page.getByTestId('pagination').getByRole('button', { name: /next/i }).click();
    await expect(page.locator('tbody tr').first()).not.toHaveText(first ?? '');
  });

  test('CSV export downloads', async ({ page }) => {
    await openScreen(page, 'Stations', 'screen-stations');
    const download = page.waitForEvent('download');
    await page.getByTestId('export-csv').click();
    expect((await download).suggestedFilename()).toMatch(/stations.*\.csv$/i);
  });
});
