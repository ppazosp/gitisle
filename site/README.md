# GitIsle website

The landing page for GitIsle: Astro (static) and GSAP, in the style of the app.

```sh
cd site
npm install
npm run dev      # http://localhost:4321
npm run build    # writes dist/
```

## How the page works

- The hero pins while you scroll, and a MacBook screen rises from the bottom.
  Its island morphs between real captures of the app in
  `src/assets/island/`, with a caption for each state
  (`src/scripts/landing.ts`). The banner state plays several announcements in
  turn under one caption. On phones the view zooms onto the island
  instead of shrinking the whole screen.
- With reduced motion, the page shows the expanded island and every caption
  without animation.

## Refreshing the island captures

The captures come from the app's own preview mode, in an English locale:

```sh
bash scripts/build-app.sh
GITISLE_PREVIEW_LABEL="Updated just now" dist/GitIsle.app/Contents/MacOS/GitIsle \
  --snapshot "$PWD/.artifacts/list.png" -AppleLocale en_US -AppleLanguages "(en)"
```

Use `--collapsed`, `--board`, or `--stats` for the other states. The banner
step plays five announcements; capture each with `--event opened`, `ready`,
`merged`, `failed`, and `review`, saved as `banner-<kind>.png`. Then crop each capture to the island body: 52 px from each side and 32 px from
the bottom (the capture's margin plus the notch corners), and update
`src/assets/island/sizes.json` with the cropped size in points.

## Social image and icons

`public/og.png`, the link preview for X, LinkedIn and the rest, is rendered
from `og/og.html` with headless Chrome at 2x:

```bash
./og/render.sh
```

`public/favicon.ico` (16, 32 and 48 px), `apple-touch-icon.png`, and the web
manifest's `icon-192.png` and `icon-512.png` are made from `../assets/logo.png`.

## Deploying

The site lives at <https://gitisle.ppazosp.dev>. `.github/workflows/site.yml`
deploys it to Vercel whenever a change under `site/` lands on `main`; app-only
changes never trigger it, and pull requests only check that it builds. The site is
built on GitHub and uploaded prebuilt, so `VERCEL_TOKEN` can be a token scoped to
just this Vercel project; `VERCEL_ORG_ID` and `VERCEL_PROJECT_ID` identify it.
The Vercel project's Root Directory is `site`, and `vercel.json` turns off
Vercel's own Git deployments, so the workflow is the only deployer.

The site is static, so any host works: build it and serve `site/dist`.
Canonical and Open Graph URLs point at the production domain; set `SITE_URL` at
build time to use another.
