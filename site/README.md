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

`.github/workflows/site.yml` deploys the site to Vercel
(<https://gitisle.ppazosp.dev>) whenever a change under `site/` lands on `main`.
App-only changes never trigger it. Pull requests that touch the site only check
that it builds.

The workflow needs three repository secrets: `VERCEL_TOKEN`, `VERCEL_ORG_ID`, and
`VERCEL_PROJECT_ID` (the last two are in `.vercel/project.json` after
`vercel link`). The Vercel project's Root Directory is `site`, and
`site/vercel.json` turns off Vercel's own Git deployments so only this workflow
deploys.

The site is static, so any other host works too: build it and serve `site/dist`.
Set `SITE_URL` at build time so canonical and Open Graph URLs are absolute.
