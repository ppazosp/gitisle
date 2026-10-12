// @ts-check
import { defineConfig } from 'astro/config';

// https://astro.build/config
export default defineConfig({
  // Canonical and Open Graph URLs are absolute; SITE_URL overrides the production domain.
  site: process.env.SITE_URL || 'https://gitisle.ppazosp.dev',
  trailingSlash: 'ignore',
  build: { inlineStylesheets: 'always' },
});
