# Changelog

Notable changes to GitIsle. Releases follow [semantic versioning](https://semver.org).

## [0.3.0](https://github.com/ppazosp/gitisle/compare/v0.2.2...v0.3.0) (2026-10-21)


### Features

* an activity row and inbox in the open island, and a cycling live bar ([#54](https://github.com/ppazosp/gitisle/issues/54)) ([bd2766c](https://github.com/ppazosp/gitisle/commit/bd2766c27258cb075da10fb1fb0f6b7ca9b0eb4e))


### Bug Fixes

* repositories order by the PRs the filters show ([#55](https://github.com/ppazosp/gitisle/issues/55)) ([550762c](https://github.com/ppazosp/gitisle/commit/550762cf9aa5d755038dae785776f166ee4d05db))

## [0.2.2](https://github.com/ppazosp/gitisle/compare/v0.2.1...v0.2.2) (2026-10-20)


### Features

* a PR's number links to it on GitHub ([#49](https://github.com/ppazosp/gitisle/issues/49)) ([29ebbe9](https://github.com/ppazosp/gitisle/commit/29ebbe91cc0aa5bd8376aff52861b6a5e939e973))
* Settings fits without scrolling, and every hover delay is yours ([#50](https://github.com/ppazosp/gitisle/issues/50)) ([1eedda4](https://github.com/ppazosp/gitisle/commit/1eedda4edec73d0bd60757897b9bd5384e76bddf))
* setup shows your screens, and how to make GitIsle yours ([#48](https://github.com/ppazosp/gitisle/issues/48)) ([ae07ec8](https://github.com/ppazosp/gitisle/commit/ae07ec81e885fa13c37484ebfcfd0339913dc1a2))


### Bug Fixes

* setup and Settings never freeze the island ([#47](https://github.com/ppazosp/gitisle/issues/47)) ([40bc145](https://github.com/ppazosp/gitisle/commit/40bc14523854e3395aaafc5b23f1b73c564459d5))

## [0.2.1](https://github.com/ppazosp/gitisle/compare/v0.2.0...v0.2.1) (2026-10-19)


### Features

* the island's own dropdowns replace native menus ([#45](https://github.com/ppazosp/gitisle/issues/45)) ([8b5004f](https://github.com/ppazosp/gitisle/commit/8b5004f6f24586491607a3aa0e52a30b8ff9b663))


### Bug Fixes

* Vercel previews show while they build ([#44](https://github.com/ppazosp/gitisle/issues/44)) ([ff4fdd2](https://github.com/ppazosp/gitisle/commit/ff4fdd251517b286560521bd0a87ca6ea94f3476))

## [0.2.0](https://github.com/ppazosp/gitisle/compare/v0.1.7...v0.2.0) (2026-10-18)


### Features

* a page for each PR, with the checks that failed and why ([#35](https://github.com/ppazosp/gitisle/issues/35)) ([446c9b6](https://github.com/ppazosp/gitisle/commit/446c9b600cc7ccd6fbb6453cfa6de6c09a08fac8))
* a PR's page shows its files beside its checks, and opens a file to its diff ([#40](https://github.com/ppazosp/gitisle/issues/40)) ([275884e](https://github.com/ppazosp/gitisle/commit/275884eab2d27ef10ab99cf8a818306ef40dcbd7))
* copy or save a share card for a merged PR ([#38](https://github.com/ppazosp/gitisle/issues/38)) ([4debb57](https://github.com/ppazosp/gitisle/commit/4debb571617d7d0c0779ba6e3bc9bfcedc0e62a3))
* open a PR's preview deploy from the island, and hear when it's ready ([#36](https://github.com/ppazosp/gitisle/issues/36)) ([2b4949e](https://github.com/ppazosp/gitisle/commit/2b4949e546c28b3502ae638b1667259937e1c957))
* PRs built on each other show as a stack ([#37](https://github.com/ppazosp/gitisle/issues/37)) ([5d1a7a5](https://github.com/ppazosp/gitisle/commit/5d1a7a54e075ae80b3762c33da752636b415dc50))


### Bug Fixes

* merging follows the merge queue, with its checks, a real start time, and failures ([#39](https://github.com/ppazosp/gitisle/issues/39)) ([fb0d55d](https://github.com/ppazosp/gitisle/commit/fb0d55d441b7e1c79dd983db2b04503611902c1b))

## [0.1.7](https://github.com/ppazosp/gitisle/compare/v0.1.6...v0.1.7) (2026-10-13)


### Features

* GitIsle tells you when one of your PRs is opened, as a new PR or a new draft, and when a draft is marked ready for review. Switch it off under Settings → Announce → New PR ([#32](https://github.com/ppazosp/gitisle/issues/32)) ([b49fb28](https://github.com/ppazosp/gitisle/commit/b49fb2891a0a27bbc49429dca1eabbe7319684d5))

## [0.1.6](https://github.com/ppazosp/gitisle/compare/v0.1.5...v0.1.6) (2026-10-13)


### Features

* Pick several repositories at once. Activity, the live bar, banners, and notifications all follow your pick ([#30](https://github.com/ppazosp/gitisle/issues/30)) ([733c572](https://github.com/ppazosp/gitisle/commit/733c572062da54c8c98715936606e958833320eb))


### Performance Improvements

* GitIsle uses about half as much of your GitHub API budget. A cheap check finds what changed before any full search, and PRs refresh less often while you're away from the Mac ([#29](https://github.com/ppazosp/gitisle/issues/29)) ([bbf7bcb](https://github.com/ppazosp/gitisle/commit/bbf7bcb385ea894c92d11937fb3405e7dbd2f020))

## [0.1.5](https://github.com/ppazosp/gitisle/compare/v0.1.4...v0.1.5) (2026-10-13)


### Bug Fixes

* GitIsle looks for updates every hour and when the Mac wakes ([#27](https://github.com/ppazosp/gitisle/issues/27)) ([f196982](https://github.com/ppazosp/gitisle/commit/f19698229c0ea80e7f1c940d9eafc443cdef828e))
* setup's buttons sit as close to the bottom as the app's footer ([#26](https://github.com/ppazosp/gitisle/issues/26)) ([b7f6d6f](https://github.com/ppazosp/gitisle/commit/b7f6d6f8be7422830221dcba8ef2e58098345af1))

## [0.1.4](https://github.com/ppazosp/gitisle/compare/v0.1.3...v0.1.4) (2026-10-13)

### Features

* GitIsle updates itself. When a new release is out, a blue download button appears at the bottom right of the island; click it to download, verify, and relaunch on the new version. Releases are signed, and GitIsle installs only updates that carry its signature. Builds from source update with `git pull`.
* Your own PRs announce when they're ready to merge: checks green, reviews done, nothing in the way. Switch it off under Settings → Announce.
* The refresh button now sits at the bottom left, next to when GitIsle last updated.

## [0.1.3](https://github.com/ppazosp/gitisle/compare/v0.1.2...v0.1.3) (2026-10-13)

### Bug Fixes

* Pressing a state filter in Activity (Draft, Open, Merging, or Merged) no longer quits GitIsle.

## [0.1.2](https://github.com/ppazosp/gitisle/compare/v0.1.1...v0.1.2) (2026-10-12)

### Features

* Displays without a notch, such as external monitors, get a drawn notch that the island grows out of.

### Bug Fixes

* Setup's buttons no longer crowd the island's rounded corners.

## [0.1.1](https://github.com/ppazosp/gitisle/compare/v0.1.0...v0.1.1) (2026-10-12)

### Features

* Step-by-step setup inside the island on first launch.
* PRs that are moving refresh every 10 seconds, and new PRs show up within a minute.
* Settings save as you change them.
* A branded disk image and a shorter install command.

## 0.1.0 (2026-10-12)

- A new app icon and logo.
- Install with a one-line script, a Homebrew cask, or a DMG from GitHub releases.
- Contributor guide, code of conduct, security policy, and issue templates.
- The island lives in the notch: invisible at rest, live while your PRs merge
  or run checks, and a banner for merges, failed checks, review requests, and
  merges starting.
- Activity shows PRs by repository or as a board of GitHub states, with
  filters for state, "needs you", repository, and time.
- Stats show GitHub activity and local Claude Code and Codex usage, with
  several chart styles and euros or dollars.
- Settings live inside the island; right-click it to quit.
