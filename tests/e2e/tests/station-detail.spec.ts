import { expect, test } from '@playwright/test';
import { openScreen, requireBaseUrl } from './helpers';

test.beforeEach(requireBaseUrl);

test('chart renders and range can be changed', async ({ page }) => {
  await openScreen(page, 'StationDetail?StationId=S24', 'screen-station-detail');
  await expect(page.getByTestId('station-name')).toContainText(/Changi/i);
  await expect(page.getByTestId('series-chart').locator('svg').first()).toBeVisible();
  await page.getByTestId('range-switch').getByRole('button', { name: '7 d' }).click();
  await expect(page.getByTestId('series-chart').locator('svg').first()).toBeVisible();
});

test('unknown station shows a friendly empty state', async ({ page }) => {
  await page.goto('StationDetail?StationId=S99999');
  await expect(page.getByTestId('not-found')).toBeVisible();
});
