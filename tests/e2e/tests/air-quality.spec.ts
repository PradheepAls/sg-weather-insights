import { expect, test } from '@playwright/test';
import { openScreen, requireBaseUrl } from './helpers';

test.beforeEach(requireBaseUrl);

const BANDS = ['Good', 'Moderate', 'Unhealthy', 'Very unhealthy', 'Hazardous'];

test('five region cards, each with a text band (not colour alone)', async ({ page }) => {
  await openScreen(page, 'AirQuality', 'screen-air-quality');
  const cards = page.getByTestId('region-card');
  await expect(cards).toHaveCount(5);
  for (const card of await cards.all()) {
    const band = (await card.getByTestId('psi-band').textContent())?.trim() ?? '';
    expect(BANDS).toContain(band);
    await expect(card.getByTestId('psi-value')).toHaveText(/^\d+$/);
  }
});
