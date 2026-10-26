# Contributing to GitIsle

Thanks for helping. GitIsle is a small native macOS app, so most changes are
quick to build and check locally.

## Before you start

- For a bug, open an issue with the steps to reproduce it and your macOS
  version. Screenshots of the island help a lot.
- For a feature, open an issue first so we can agree on the behavior before
  you write code. GitIsle aims to stay small, calm, and read-only on GitHub.
- Small fixes, such as typos or obvious bugs, can go straight to a pull
  request.

## Set up

You need macOS 14 or later, Xcode 26 or later (Swift 6.2), and the
[GitHub CLI](https://cli.github.com/) signed in with `gh auth login`.

```sh
git clone https://github.com/ppazosp/gitisle.git
cd gitisle
bash scripts/build-app.sh
open dist/GitIsle.app
```

If `swift test` cannot find the `Testing` module, point the toolchain at Xcode:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

## Work on the UI without your account

Example data and preview flags make UI work repeatable:

```sh
dist/GitIsle.app/Contents/MacOS/GitIsle --demo --expanded   # open the island with example data
dist/GitIsle.app/Contents/MacOS/GitIsle --showcase          # play every banner in turn
dist/GitIsle.app/Contents/MacOS/GitIsle --snapshot "$PWD/.artifacts/activity.png"
```

Add `--stats`, `--board`, `--settings`, `--banner`, `--collapsed`,
`--states draft,merged`, `--repos orbit/web,orbit/api`, `--repo-picker`,
`--update`, `--event draft` (any announcement), `--details demo2` (a PR's page), `--share-card demo6 card.png` (writes a share card), `--story merged` (one PR's life,
as the website shows it), or `--chart area` to a snapshot
to render another view. Quit any running GitIsle first, since only one island fits the notch.

## Check your change

Run the same checks as CI before you open a pull request:

```sh
swift format lint --strict --recursive Sources Tests Package.swift
swift test --jobs 2
bash scripts/build-app.sh
```

`swift format format -i -r Sources Tests` fixes most formatting issues.

## Pull requests

- Keep each pull request to one change, and explain the problem and why the
  fix is right, not only what changed.
- Title it as a conventional commit, such as `fix: …` or `feat: …`. Pull
  requests are squash-merged, so the title becomes the commit on `main` and the
  line in the changelog.
- Add or update tests in `Tests/IslandCoreTests` for behavior in `IslandCore`,
  such as grouping, filtering, decoding, or change detection.
- Include a before and after screenshot for visual changes.
- Keep GitHub access read-only. GitIsle never merges, reviews, comments, or
  marks notifications as read.
- Don't add telemetry or network calls beyond GitHub through `gh` and GitHub's
  avatar host.

## Project layout

| Path | What lives there |
| --- | --- |
| `Sources/IslandCore` | Models, GitHub queries, grouping, and change detection. No UI. |
| `Sources/GitIsle` | The SwiftUI island, AppKit panel, settings, and statistics. |
| `Tests/IslandCoreTests` | Unit tests with local fixtures. |
| `assets` | Logo and app icon sources. |
| `scripts` | Build, packaging, install, and icon scripts. |
| `docs` | Architecture notes, research, and README images. |

See [the architecture](docs/architecture.md) for how the pieces fit together.

## Releases

Release Please keeps a release pull request open. Every `fix:` and `feat:`
merged to `main` lands in it with its changelog entry, and both bump the patch
version (0.1.3 to 0.1.4). Merging the release pull request tags the release;
the release workflow then tests, builds, and attaches `GitIsle.zip`,
`GitIsle.dmg`, and checksums. Installed copies offer the update within an hour.

Minor versions mark milestones. To make the next release one, give the
milestone's squash commit a `Release-As` footer when you merge it:

```sh
gh pr merge 42 --squash --body "Release-As: 0.2.0"
```

Releases are signed: the release workflow signs `GitIsle.zip` with the
`GITISLE_SIGNING_KEY` secret, and installed copies only update to an archive
that verifies against the public key in `Sources/IslandCore/AppRelease.swift`.
Signing runs in its own job from a clean checkout, because the build runs
third-party code and never sees the key.
The maintainer keeps a backup of the private key. Losing it means installed
copies can't verify new updates; replacing it means shipping the new public
key in a release signed with the old one.

Pushing a version tag by hand (`git tag v0.2.0 && git push origin v0.2.0`)
still publishes a release. To try a release build locally, run
`bash scripts/package-release.sh 0.2.0`.

## Code of conduct

Everyone taking part is expected to follow the
[code of conduct](CODE_OF_CONDUCT.md).
