import { expect, Page, test } from '@playwright/test';

export const requireBaseUrl = () =>
  test.skip(!process.env.WEATHER_APP_URL, 'WEATHER_APP_URL not set');

/** OutSystems Reactive apps render client-side; wait for the screen container and no spinner. */
export async function openScreen(page: Page, path: string, screenTestId: string) {
  await page.goto(path);
  await expect(page.getByTestId(screenTestId)).toBeVisible();
  await expect(page.locator('.osui-loading, .feedback-message-loading')).toHaveCount(0);
}
