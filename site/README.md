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
  (`src/scripts/landing.ts`). On phones the view zooms onto the island
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

Use `--collapsed`, `--banner`, `--board`, or `--stats` for the other states,
then crop each capture to the island body: 52 px from each side and 32 px from
the bottom (the capture's margin plus the notch corners), and update
`src/assets/island/sizes.json` with the cropped size in points.

## Deploying

The site is static. Build it and serve `site/dist` from any static host. Set
`SITE_URL` (for example `https://gitisle.app`) at build time so canonical and
Open Graph URLs are absolute.
