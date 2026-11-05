# Source research

Reviewed on 11 October 2026. A separate native app keeps GitHub as the main view
while reusing an established token-accounting library.

GitIsle later dropped agent usage to focus on GitHub, so it no longer depends on
CodexBar or reads Codex and Claude Code history. The notes below are kept as the
original research.

| Project | Relevant parts | Source license | Decision |
| --- | --- | --- | --- |
| [CodexBar](https://github.com/steipete/CodexBar) | public Swift usage library, model accounting, local history, cached tokens and fork handling | MIT | use CodexBarCore at `79831b47517f3e3e340886be63157f582ab13d41` |
| [Agents Island](https://github.com/mustafahalabi/agents-island) | native island window, notch geometry, local activity readers | MIT | adapt window geometry; desktop needs its own reader because the upstream monitor filters GUI helpers |
| [CodexIsland](https://github.com/ericjypark/codex-island) | island display selection and usage UI | MIT | reference for display behavior; avoid copying a second accounting engine |
| [CodeIsland](https://github.com/wxtsky/CodeIsland) | event hooks, session status, permission and terminal integrations | MIT | possible later source for reliable approval events; controls exceed the first version's monitoring scope |
| [Magpie](https://github.com/fmguerreiro/magpie) | native GitHub notification UI using an existing gh login | MIT | use the authentication approach; keep GitIsle queries read-only |
| [Boring Notch](https://github.com/TheBoredTeam/boring.notch) | general notch interaction and display behavior | GPL-3.0 | visual reference only; no source copied |

The inspected local Codex desktop records identify their originator as Codex
Desktop and contain token usage records. That establishes a local data source,
but its schema remains version-dependent. The
[official app-server documentation](https://learn.chatgpt.com/docs/app-server)
also defines status and token events for clients connected to that server.
It does not establish passive access to another application's running server.
GitIsle therefore reads existing records instead of resuming desktop threads.

[GitHub's PR schema](https://docs.github.com/en/graphql/reference/pulls) exposes
mergeability, reviews, queue position, and merge time separately. These fields
inform the normalized state; a green check or a missing search row is not
sufficient evidence of a merge.

[Claude Code hooks](https://code.claude.com/docs/en/hooks) offer more reliable
live events than transcript polling. Adding an optional hook adapter can improve
approval detection later without changing the island or usage-library contract.
