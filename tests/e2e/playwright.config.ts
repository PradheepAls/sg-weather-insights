import { defineConfig, devices } from '@playwright/test';

const baseURL = process.env.WEATHER_APP_URL; // e.g. https://weather-test.example.gov.sg/Weather/

export default defineConfig({
  testDir: './tests',
  timeout: 45_000,
  expect: { timeout: 10_000 },
  fullyParallel: true,
  retries: process.env.CI ? 1 : 0,
  reporter: [['list'], ['junit', { outputFile: 'results/junit.xml' }], ['html', { open: 'never', outputFolder: 'results/html' }]],
  use: {
    baseURL,
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    testIdAttribute: 'data-testid',
    timezoneId: 'Asia/Singapore',
  },
  projects: [
    { name: 'desktop-chrome', use: { ...devices['Desktop Chrome'] } },
  ],
});
