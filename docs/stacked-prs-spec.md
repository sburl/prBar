# prBar: Stacked PR support (feature spec)

**Created:** 2026-08-28
**Status:** Proposed — pending Linear project

## Why

GitHub shipped stacked pull requests in public preview on 2026-07-30. prBar
currently renders each repo's open PRs as a flat list; stacked PRs from the
same series appear as unrelated rows.

## What GitHub exposes

- GraphQL (read-only): pull requests that belong to a stack carry a `stack`
  object — stack number, size, and the PR's position and base.
- REST: a dedicated Stacks API (list/read/create/extend/dissolve) plus a
  `stack` property on pull_request webhook payloads.
- Reference: https://docs.github.com/en/pull-requests/reference/stacked-pull-requests-apis-and-webhooks
- Announcement: https://github.blog/changelog/2026-07-30-stacked-pull-requests-are-now-in-public-preview/

## Proposed behavior

1. Extend the batched GraphQL query in `GitHubClient.repoFragment` to request
   the `stack` fields on each PR node (feature is in preview — verify the
   final schema field names when implementing).
2. Model: add optional stack info to `PullRequest` (stack id/number, position,
   size).
3. Menu rendering (`StatusItemController.repoSubmenu`): group PRs belonging to
   the same stack — the stack's bottom PR at the top level with the rest
   indented beneath it, each row marked with its position, e.g. `2/4`.
   Non-stacked PRs keep the current flat rows.
4. Counting: stacked PRs still count individually in the menu-bar totals.

## Open questions

- Public-preview schema may change before GA; gate on a schema probe or
  tolerate missing fields (decode as optional, degrade to flat list).
- Whether a stack row needs its own submenu vs. indented flat rows.
