import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: '.',
  reporter: [['list'], ['html', { open: 'never' }]],
  use: {
    baseURL: process.env.NEUTRINO_WEB_BASE_URL,
    trace: 'on-first-retry',
  },
});
