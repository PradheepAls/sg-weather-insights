import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';
import { openScreen, requireBaseUrl } from './helpers';

test.beforeEach(requireBaseUrl);

const screens: Array<[string, string]> = [
  ['', 'screen-dashboard'],
  ['StationDetail?StationId=S24', 'screen-station-detail'],
  ['AirQuality', 'screen-air-quality'],
];

for (const [path, id] of screens) {
  test(`no serious WCAG 2.1 AA violations on ${id}`, async ({ page }) => {
    await openScreen(page, path, id);
    const { violations } = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa'])
      .analyze();
    const serious = violations.filter((v) => ['serious', 'critical'].includes(v.impact ?? ''));
    expect(serious.map((v) => `${v.id}: ${v.nodes.length} nodes`)).toEqual([]);
  });
}
