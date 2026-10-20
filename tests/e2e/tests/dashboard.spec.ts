import { expect, test } from '@playwright/test';
import { openScreen, requireBaseUrl } from './helpers';

test.beforeEach(requireBaseUrl);

test.describe('Dashboard', () => {
  test('shows island statistics and a freshness badge', async ({ page }) => {
    await openScreen(page, '', 'screen-dashboard');
    for (const id of ['stat-min', 'stat-avg', 'stat-max']) {
      await expect(page.getByTestId(id)).toContainText(/\d/);
    }
    await expect(page.getByTestId('freshness-badge')).toHaveText(/Updated|Stale/);
    await expect(page.getByTestId('as-of')).toContainText(/\d{1,2}:\d{2}/);
  });

  test('switching metric updates unit and markers', async ({ page }) => {
    await openScreen(page, '', 'screen-dashboard');
    await page.getByTestId('metric-switch').getByRole('button', { name: /Humidity/i }).click();
    await expect(page.getByTestId('stat-avg')).toContainText('%');
    await expect(page.getByTestId('map').locator('.station-marker').first()).toBeVisible();

    await page.getByTestId('metric-switch').getByRole('button', { name: /Wind/i }).click();
    await expect(page.getByTestId('stat-avg')).toContainText(/km\/h|kn/);
  });

  test('marker opens station detail', async ({ page }) => {
    await openScreen(page, '', 'screen-dashboard');
    await page.getByTestId('map').locator('.station-marker').first().click();
    await page.getByTestId('marker-popup').getByRole('link', { name: /details/i }).click();
    await expect(page.getByTestId('screen-station-detail')).toBeVisible();
    await expect(page).toHaveURL(/StationDetail\?StationId=S\d+/);
  });
});
