# GitIsle

Your agents and PRs, in one island.

A native macOS companion that keeps GitHub pull requests at the top of your
screen, with Codex and Claude Code activity one interaction away.

Hover over the island briefly to expand it. Activity is the default view: PRs
grouped the way GitHub shows them, with your running Codex and Claude Code
sessions underneath. Stats shows GitHub activity, tokens, models, and estimated
API costs.

When a PR merges, fails its checks, receives your review request, or starts
merging, the island grows into a short banner. While one of your PRs is in the
merge queue or set to auto-merge, the closed island shows it.

## What it shows

- your open PRs, requested reviews, and any extra repositories you watch, grouped
  as needs you, merging, open, draft, and merged, filtered by today, 7 days, or all
- passed, failed, and running checks for each PR, conflicts, review decisions,
  auto-merge, and merge-queue position
- Codex desktop, Codex CLI, and Claude Code sessions on your Mac, with their titles
- PRs you opened, merged, and reviewed, and your daily GitHub contributions
- local token history, daily usage, and model breakdowns for today, 7 days, and 30 days

PR rows open GitHub in your browser. GitIsle uses read-only queries and does not
merge, review, comment, or mark GitHub notifications as read.

## Build and run

You need macOS 14 or later, Xcode 26 or later (Swift 6.2 or later), and the
[GitHub CLI](https://cli.github.com/). Sign in using `gh auth login`.
Codex and Claude Code keep managing their own sign-ins.

```sh
git clone https://github.com/ppazosp/gitisle.git
cd gitisle
bash scripts/build-app.sh
open dist/GitIsle.app
```

The app supports Macs with a notch and external displays. Choose the display,
hover delay, watched repositories, and local agent directories in Settings.
Notifications and launch at login are optional. Enable them in Settings.

For a repeatable preview using example data:

```sh
dist/GitIsle.app/Contents/MacOS/GitIsle --demo --expanded
dist/GitIsle.app/Contents/MacOS/GitIsle --snapshot /absolute/path/activity.png
dist/GitIsle.app/Contents/MacOS/GitIsle --snapshot /absolute/path/stats.png --stats
dist/GitIsle.app/Contents/MacOS/GitIsle --snapshot /absolute/path/banner.png --banner
```

To check your actual connections and local history:

```sh
dist/GitIsle.app/Contents/MacOS/GitIsle --diagnose
```

These are development builds signed locally without a Developer ID. Public
signed releases and notarization are not configured yet.

## How to read the statistics

Token totals cover locally recorded history. Deleted logs, other machines, and
unsupported records can leave gaps. Missing values stay unavailable. Incomplete
scans or unpriced requests show a partial-history label.

Dollar values estimate usage at API prices. They are separate from subscription
payments and remaining plan quota. Cache tokens use the provider's categories;
do not add the rows together to reconstruct a bill.

The activity view observes existing local records. It does not start or resume
agents or change their configuration. A working state older than 5 minutes
becomes unknown because a crashed process can leave an unfinished start event.
Long-running tasks with no new events can also show unknown. Claude approval
requests that are absent from its transcript are not detectable in this version.

GitHub refreshes every minute by default. GitHub statistics refresh every 10
minutes. Reviewed counts PRs by others that you reviewed and that changed during
the period. Errors retain the previous snapshot
with a cached label. Each search group is limited to 100 PRs; the app reports
when that limit is reached. GitHub.com is supported; GitHub Enterprise is not
included in this version.

## Development

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --jobs 2
python3 scripts/monitored.py build bash scripts/build-app.sh
```

The monitored wrapper writes `.artifacts/<name>.log` and a JSON result. It stops
its own job after 5 minutes without output or 20 minutes in total.

The app uses SwiftUI and AppKit. Provider work stays outside the UI. GitHub
queries, agent activity, and history scans run independently. See
[the architecture](docs/architecture.md) and [source research](docs/research.md).

## Privacy and compatibility

GitIsle talks to GitHub through your existing `gh` login. Local usage scans do
not query provider accounts; remote price refresh is disabled. There is no
telemetry or GitIsle cloud service.

Settings, GitHub snapshots, the event ledger, and usage caches stay under
`~/Library/Application Support/GitIsle/`. GitIsle does not write to agent
configuration, transcripts, authentication files, or credentials.

Existing agent installations keep working as before. Session formats are
version-dependent; unknown records are ignored, and uncertain activity is
shown as unknown. The usage library is pinned to an exact upstream revision.

## Credits and license

[CodexBar](https://github.com/steipete/CodexBar) provides the usage library.
[Agents Island](https://github.com/mustafahalabi/agents-island) provided the
notch geometry and window pattern. Pull request icons are GitHub
[Octicons](https://github.com/primer/octicons); provider marks come from
[Simple Icons](https://simpleicons.org). [Magpie](https://github.com/fmguerreiro/magpie)
informed the use of an existing GitHub CLI login.

GitIsle uses the MIT license. See [third-party notices](THIRD_PARTY_NOTICES.md).
