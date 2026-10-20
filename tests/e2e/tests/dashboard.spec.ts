import { expect, test } from '@playwright/test';
import { openScreen, requireBaseUrl } from './helpers';

test.beforeEach(requireBaseUrl);

test('shows island statistics and when the data is from', async ({ page }) => {
  await openScreen(page, '', 'screen-dashboard');
  for (const id of ['stat-min', 'stat-avg', 'stat-max']) {
    await expect(page.getByTestId(id)).toContainText(/\d/);
  }
  await expect(page.getByTestId('as-of')).toContainText(/\d{1,2}:\d{2}/);
});

test('switching metric changes the unit', async ({ page }) => {
  await openScreen(page, '', 'screen-dashboard');
  await page.getByTestId('metric-switch').getByRole('button', { name: /Humidity/i }).click();
  await expect(page.getByTestId('stat-avg')).toContainText('%');
});

test('search narrows the station table', async ({ page }) => {
  await openScreen(page, '', 'screen-dashboard');
  const rows = page.getByTestId('stations-table').locator('tbody tr');
  const before = await rows.count();
  await page.getByTestId('search').fill('changi');
  await expect(rows).not.toHaveCount(before);
  await expect(rows.first()).toContainText(/changi/i);
});

test('row opens station detail', async ({ page }) => {
  await openScreen(page, '', 'screen-dashboard');
  await page.getByTestId('stations-table').locator('tbody tr').first().click();
  await expect(page.getByTestId('screen-station-detail')).toBeVisible();
});
