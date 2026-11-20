# Source research

Reviewed on 11 October 2026.

| Project | Relevant parts | Source license | Decision |
| --- | --- | --- | --- |
| [Agents Island](https://github.com/mustafahalabi/agents-island) | native island window and notch geometry | MIT | adapt window geometry |
| [Magpie](https://github.com/fmguerreiro/magpie) | native GitHub notification UI using an existing gh login | MIT | use the authentication approach; keep GitIsle queries read-only |
| [Boring Notch](https://github.com/TheBoredTeam/boring.notch) | general notch interaction and display behavior | GPL-3.0 | visual reference only; no source copied |

[GitHub's PR schema](https://docs.github.com/en/graphql/reference/pulls) exposes
mergeability, reviews, queue position, and merge time separately. These fields
inform the normalized state; a green check or a missing search row is not
sufficient evidence of a merge.
