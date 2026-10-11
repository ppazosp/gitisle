# Architecture

Activity is the default view: PRs grouped by repository, each showing its
state. Statistics have their own tab. The island window never starts an agent
or performs a GitHub write.

```mermaid
flowchart LR
  GH[GitHub API through gh] --> G[PR collector]
  LOG[Local agent history] --> C[CodexBarCore usage scanner]
  G --> S[Island store]
  C --> S
  S --> U[SwiftUI island in AppKit panel]
  S --> N[Local event ledger and notifications]
  U --> B[Open PR in browser]
```

`IslandCore` owns normalized PRs, PR grouping by state and repository, time
windows, GitHub queries, bounded subprocess execution, and event comparisons. Its tests use local fixtures.
`GitIsle` owns the usage-library adapter, UI, settings, cache, and notifications.

Each collector runs independently. GitHub queries have a process deadline and
an output limit. A failed query leaves the previous snapshot available. The
collector checks missing open PR identities before treating them as merged or
closed. Unknown mergeability and successful checks alone never imply readiness.

The event ledger suppresses repeated notifications across launches. Initial
connection and account or repository changes establish a new baseline. A new
requested review can notify after that baseline. Failed-check notifications are
identified by PR and commit. Merge notifications use the observed merge time.

The usage scanner reads Codex and Claude Code history and handles provider
accounting, caches, and fork history.

The island has three presentations: compact, a temporary event banner, and
expanded. One shape morphs between them with a spring; content fades in after
the shape starts growing and leaves before it shrinks. The expanded height
follows the measured content, and that measured size is also the hit-test area.
The store derives repository sections once per snapshot, so rendering never
re-filters the PR list. Collapsed repositories are remembered in user defaults.

The window targets a selected display. It uses a non-activating panel so hover
does not take keyboard focus. Mouse handling follows the visible island shape;
the rest of the transparent window passes clicks through. Full-screen visibility
is optional. The auto-hide menu bar can affect macOS full-screen detection;
enable Show in full screen if your menu bar is always hidden.

Caches and settings are local JSON files. Agent usage history stays in its
existing location. Changing a data source prevents an in-flight result from publishing
against the new selection.
