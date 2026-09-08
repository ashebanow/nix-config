# Issue tracker: Linear

Issues, specs, and tickets for this repo live in **Linear**, not GitHub.

- **Team**: Boxbow (issue IDs look like `BOX-130`)
- **Project**: [Nix-Config](https://linear.app/boxbow/project/nix-config-3a7db48354b6)
- **Access**: the `linear-server` MCP (`mcp__linear-server__*` tools). It is OAuth-gated —
  if the tools are unavailable, run `mcp__linear-server__authenticate`, hand the user the
  URL, and wait for them to finish before retrying.

GitHub is used only for code (PRs against `ashebanow/nix-config`). GitHub Issues are **not**
a tracked surface here; do not create or triage them.

## Conventions

- **Fetch a ticket**: `get_issue` with the identifier (`BOX-130`). Read its description and,
  when history matters, `list_comments` for that issue. Design decisions are recorded in the
  ticket body — treat the body as the spec.
- **List tickets**: `list_issues` filtered by `team: "Boxbow"` and `project: "Nix-Config"`,
  plus `state` / `label` as needed. `list_my_issues` for the current user's assigned work.
- **Create a ticket**: `create_issue` with `team: "Boxbow"`, `project: "Nix-Config"`, a title,
  and a Markdown description. Set `parentId` for a sub-issue.
- **Comment**: `create_comment` with the issue id and a Markdown body.
- **Labels**: `update_issue` with the `labels` set. Discover the exact strings with
  `list_issue_labels`; the canonical triage roles map through `docs/agents/triage-labels.md`.
- **Triage state**: prefer a real workflow **state** (`list_issue_statuses` for the team's
  set) where one matches; use labels only for roles with no matching state.
- **Close**: `update_issue` moving the issue to a completed state (e.g. `Done` / `Canceled`);
  add a `create_comment` explaining why when closing without completing the work.

## When a skill says "publish to the issue tracker"

Create a Linear issue with `create_issue` under team Boxbow, project Nix-Config.

## When a skill says "fetch the relevant ticket"

`get_issue` on the identifier the user gave (`BOX-<n>`), then `list_comments` if the
conversation history is relevant.

## Blocking / dependencies

Linear models these as **issue relations** (`blocks` / `blocked by`). Set them in the Linear
app, or via `update_issue` if the relation field is exposed by the MCP build in use. Where
neither is available, fall back to a `Blocked by: BOX-<n>, BOX-<n>` line at the top of the
description. A ticket is unblocked when every blocker is in a completed state. The
`HANDOFF.md` at the repo root also carries the current dependency graph in prose.

## Wayfinding operations

Used by `/wayfinder`. The **map** is one issue; **child** tickets are its Linear sub-issues.

- **Map**: an issue with the `wayfinder:map` label holding the Notes / Decisions-so-far / Fog
  body.
- **Child ticket**: a sub-issue (`parentId` = the map) with the question in the body. Label
  `wayfinder:<type>` (`research` / `prototype` / `grilling` / `task`). Assign to the driving
  dev once claimed.
- **Blocking**: issue relations as above, else a `Blocked by:` line in the child body.
- **Frontier query**: `list_issues` scoped to the map's children, `state` = not-started or
  started; drop any with an open blocker or an assignee; first in map order wins.
- **Claim**: `update_issue` assigning the issue to the current user — the session's first write.
- **Resolve**: `create_comment` with the answer, `update_issue` to a completed state, then
  append a context pointer (gist + link) to the map's Decisions-so-far.
