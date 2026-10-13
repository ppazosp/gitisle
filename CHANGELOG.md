# Changelog

Notable changes to GitIsle. Releases follow [semantic versioning](https://semver.org).

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
