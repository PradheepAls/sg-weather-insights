import { expect, test } from '@playwright/test';
import { openScreen, requireBaseUrl } from './helpers';

test.beforeEach(requireBaseUrl);

test('range switch reloads the chart and the table alternative', async ({ page }) => {
  await openScreen(page, 'StationDetail?StationId=S24', 'screen-station-detail');
  await expect(page.getByTestId('station-name')).toContainText(/Changi/i);
  await expect(page.getByTestId('series-chart').locator('svg')).toBeVisible();

  for (const range of ['24 h', '7 d']) {
    await page.getByTestId('range-switch').getByRole('button', { name: range }).click();
    await expect(page.getByTestId('range-switch').getByRole('button', { name: range })).toHaveAttribute('aria-pressed', 'true');
  }
  await page.getByTestId('show-as-table').click();
  await expect(page.getByTestId('series-table').locator('tbody tr').first()).toBeVisible();
});

test('unknown station shows a friendly not-found state', async ({ page }) => {
  await page.goto('StationDetail?StationId=S99999');
  await expect(page.getByTestId('not-found')).toBeVisible();
});
