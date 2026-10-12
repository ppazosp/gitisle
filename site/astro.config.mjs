// @ts-check
import { defineConfig } from 'astro/config';

// https://astro.build/config
export default defineConfig({
  // Set SITE_URL when deploying so canonical and Open Graph URLs are absolute.
  site: process.env.SITE_URL || undefined,
  trailingSlash: 'ignore',
  build: { inlineStylesheets: 'always' },
});
