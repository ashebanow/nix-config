# Handoff — nix-config overlay audit (BOX-240 … BOX-243)

Written at end of session. A fresh agent can continue from here without re-deriving
anything. Everything below was verified in-session; anything *not* verified is called
out explicitly.

**Repo:** `/home/podman/nix-config` (remote `origin`, GitHub `ashebanow/nix-config`)
**Secondary repo touched:** `/home/podman/.local/share/chezmoi` (dotfiles)
**Issue tracker:** Linear, team `BOX`, project `Nix-Config` — via the `linear` CLI, never MCP

---

## 1. What the task was

Audit every overlay under `lib/overlays/`. For each:

- If code comments or a referenced Linear issue discussed a problem that *forced* the
  overlay, check whether that issue is resolved. If resolved → file an issue to **remove**
  the overlay, then dispatch a subagent to implement it.
- Otherwise → check for a newer upstream version. File an issue to **bump**, then dispatch
  a subagent.

All four subagents were dispatched in parallel and have all completed.

---

## 2. Outcome at a glance

| Overlay | Decision | Issue | State | Branch / tip |
|---|---|---|---|---|
| `devenv.nix` | **Retired** — was provably a no-op | BOX-240 | `In Review` | `box-240-retire-devenv-overlay` @ `3972104` |
| `worktrunk.nix` | **Bump** `v0.78.0` → `v0.80.0`; overlay stays | BOX-241 | `In Review` | `box-241-bump-worktrunk-0.80.0` @ `d6e8d0f` |
| `linear-cli.nix` | **Bump** `2.6.0` → `3.0.0` (major; Rust rewrite) | BOX-242 | `In Progress` | `box-242-bump-linear-cli-3.0.0` @ `5661aaf` + dotfiles `box-242-linear-cli-skill-3.0.0` @ `3e0f71a` |
| `claude-code.nix` | **Bump** manifest `2.1.299` → `2.1.302` | BOX-243 | `In Progress` | `box-243-claude-code-2.1.302` @ `24debd6` |

`main` is untouched at `a7aba25` in both repos. **No PRs were opened** — the global
AGENTS.md requires explicit approval before opening/updating a PR, and this session never
had it.

All four branches are pushed. Working tree is clean. No stray worktrees remain
(`git worktree list` shows only the primary checkout).

### Why 242 and 243 are still `In Progress`, not `In Review`

Identical, and **not fixable on lumquat**: neither was *built* for `aarch64-darwin`, and no
host has been `switch`ed. Both evaluate cleanly on the Macs and their source hashes
validate; a build plus a `darwin-rebuild switch` on bergamot or miraclemax is what closes
them. Do not move these to `In Review` on evaluation evidence alone — that was a deliberate
call, not an oversight.

---

## 3. Non-obvious findings the next agent must not lose

### 3.1 BOX-245 is a dangling Linear reference

`lib/overlays/devenv.nix` (now deleted on the BOX-240 branch) said "Tracked in BOX-245",
and `flake.nix` and `docs/` repeated it. **BOX-245 does not exist** — `linear issue view
BOX-245` → "Could not find referenced Issue". BOX-240 is the replacement. If any `BOX-245`
reference survives anywhere, it is stale.

### 3.2 The devient overlay was a literal no-op (strongest evidence of the batch)

Stock nixpkgs devenv and the `devenvUnstable` overlay source produced the **same
drvPath** on both platforms:

- aarch64-darwin `0ng3fgs2…-devenv-2.4.0.drv`
- x86_64-linux `cplv08n8…`

The Darwin and lumquat drvPaths after removal are byte-identical to `main`. So BOX-240
changes no built closure at all. Retirement condition was: nixpkgs devenv >= 2.4.0 **and**
its bundled `secretspec` >= 0.21.0 — both true (`devenv 2.4.0`, `secretspec 0.21.0`).

`flake.lock`'s `devenvUnstable` node was hand-pruned (17 lines), **not** via an unscoped
`nix flake lock`, deliberately so as not to churn inputs shared with BOX-241. A follow-up
`nix flake lock` found nothing further to do.

### 3.3 worktrunk: the fork is already retired — `~/Development/tools/worktrunk` does not exist

The user asked mid-session whether the bump had "updated the patched fork" or dropped the
overlay. Answer: **neither** — BOX-241 repoints the flake input at upstream
`max-sixty/worktrunk` `v0.80.0`; the fork is not involved.

Repo history establishes the fork was deliberately retired *before* this session:

- `2c964bf` (BOX-145) — pinned `ashebanow/worktrunk` `feat/pi-and-omp-plugin-targets`
  because upstream's `pi` target wrote an oh-my-pi hook at
  `~/.omp/agent/hooks/pre/worktrunk.ts`, which earendil pi never reads.
- `1acf99d` — split the PR branch from an append-only `nix-pin` branch so a force-push
  could not break `flake.lock`.
- `909d16d` — both fixes landed upstream (#4135 the Pi/oh-my-pi split, #4132 the
  `stdenv.hostPlatform.isDarwin` fix); the pin became a hold-until-release.
- `29f6574` — **`nix-pin` retired**, input repointed at upstream `v0.78.0`.

There is no `~/Development` directory on lumquat at all; the only `worktrunk` path present
is `~/.config/worktrunk` (config, not a clone). If the user has a *newer* fork carrying
something beyond those two upstreamed fixes, it lives on another machine and BOX-241's
approach is wrong — **ask before assuming**, and note the branch is not merged so
repointing is still cheap.

Verified against the real `v0.80.0` build (`wt b49ca7e`, store path
`…-worktrunk-0.80.0`): `wt config plugins` lists `claude, codex, omp, opencode, pi`, with
`pi` = "Pi activity extension" distinct from `omp` = "oh-my-pi activity hook". The split
the fork existed to provide is native upstream. Commented on BOX-190; that removes the last
functional reason to keep the fork branches, leaving only cosmetic cleanup.

### 3.4 A verification trap I fell into — do not repeat it

`flake.nix` on `main` is pinned at `v0.78.0`, so **evaluating `inputs.worktrunk` from
`main` yields 0.78.0** (`wt bd49d14`) regardless of what a branch says. I initially
"confirmed" the 0.80.0 plugin surface against a 0.78.0 binary. To test a pinned-input bump
you must evaluate from that branch's flake (a throwaway `git worktree` is the clean way).

### 3.5 linear-cli 3.0.0 is a Rust rewrite, not `deno compile`

The BOX-242 ticket I wrote assumed the risk was "did the deno payload layout change". Wrong
premise. 3.0.0 is a Rust rewrite; the Linux asset is a plain dynamically-linked PIE.

Independently verified by downloading the asset:

- `last 16 bytes` → `01 00 00 …`; magic as u32 → **1** (the libsui trailer magic would be 20510 decimal = `0x501e`)
- tarball sha256 matches upstream's published `.sha256` exactly (`5064a63a…`)

The old libsui guard fired with `no libsui trailer at EOF (magic=1)` — it worked exactly as
designed. The correct response was to remove the split/patch/rejoin, *not* weaken the guard.
The guard's value is now demonstrated rather than asserted; if a future release reintroduces
an embedded payload, that failure is the signal.

### 3.6 linear-cli 3.0.0 CLI surface changes (all verified against the live 2.6.0 binary)

| Aspect | 2.6.0 | 3.0.0 |
|---|---|---|
| `issue view --json` `labels` / `children` | `{nodes}` wrappers | plain arrays |
| `issue comment list --json` | `{nodes, pageInfo}` | plain array |
| `--limit 0` | unlimited | usage error, exit 2 → use `--limit all` |
| `--no-interactive` | real flag | removed → `--no-input` |
| exit codes | always 1 | 2/3/4/5/130 |
| `linear api` | raw GraphQL | unchanged — keeps `{nodes}` from your query |

`--no-interactive` **still parses today** via the argument parser's unambiguous-prefix
matching. That is the sharpest item in the docs diff: it works now and breaks silently later.

`docs/agents/issue-tracker.md` on the BOX-242 branch documents all of the above, including
the `linear api` exception. `label list`, `team states`, `issue query`, `relation add/list`,
`--assignee self`, `--add-label`, `--state`, `--priority`, `--parent`, `--project`,
`--body-file` are all intact.

### 3.7 claude-code: the overlay's rationale quoted a dead baseline

`flake.lock` is `c5c4a43`, not `e554fab`; stock nixpkgs ships `2.1.292`, not `2.1.272`. Both
were corrected in the overlay header, `darwin-builder.nix`, `nixos-builder.nix`, and
`devshell.nix` (the last carried the same wrong pair but was not in the ticket's file list).
The "2.1.296 vs 2.1.287" channel note now says to fetch both pointers instead of quoting a
number that re-rots every release.

Shim verified: `claude update` and `claude upgrade` both exit **1** with the managed-by-Nix
message; `claude --version` → `2.1.302`; `--help` passes through; `claude doctor` shows
`Auto-update channel: latest` with no false nag. Release notes 2.1.300–302 touch nothing
around update/install/autoupdate, and the native-installer markers the shim's rationale rests
on are still present in the payload.

---

## 4. Mess caused by shared-checkout concurrency (all resolved — verify before trusting)

All four subagents shared **one** working tree, and several ran `git checkout` in it. This
produced real cross-contamination. Current true state:

- **Fixed:** BOX-241's commits had landed on local `box-243`'s branch, dragging in BOX-240's
  lockfile changes and foreign `docs/agents/issue-tracker.md` edits. Local `box-243` was
  reset to its clean remote tip `24debd6`.
- **Fixed:** a working-tree-only deletion of `lib/overlays/devenv.nix` was left on top of
  `box-243` after BOX-240's agent ran `git rm`. Restored; the file is present again on
  branches where it should be.
- **Fixed:** accidental Linear issue **BOX-244** (title `x`, empty body) was created while a
  subagent probed `--no-interactive` with a live `issue create`. The agent reported it
  deleted; it was not (`linear issue delete` needs `--confirm`, and its first attempts
  failed silently). Deleted properly by the orchestrator. Absent from `issue query`
  listings; `issue view BOX-244` may still resolve from cache for a while.

**Lesson for the next agent:** do not run multiple branch-switching subagents in one
checkout. Give each a `git worktree`, and verify branch *contents* (`git diff --stat
origin/main..origin/<branch>`) rather than trusting commit messages or reports.

---

## 5. Merge instructions

Only one conflict exists across all four branches:

- **`modules/infra/darwin-builder.nix`, BOX-240 vs BOX-243** — adjacent comment block.
  BOX-240 deletes the `devenvOverlay` binding; BOX-243 rewrites the `claude-code` comment
  beside it.

**Merge order: BOX-240 first, then BOX-243.** Resolve by keeping BOX-243's corrected
claude-code comment and dropping the devenv paragraph. All other pairs merge cleanly.

Both repos need coordinating for BOX-242: `lib/overlays/linear-cli.nix` +
`docs/agents/issue-tracker.md` in nix-config, and the re-vendored `linear-cli` skill in
dotfiles. They are pinned to the same tag and must land together (BOX-177 decision 9).

---

## 6. Remaining work

1. **Build on a Mac** — BOX-242 and BOX-243 both need an `aarch64-darwin` build plus
   `darwin-rebuild switch` on bergamot and/or miraclemax. Then `claude --version` →
   2.1.302, `claude update` → exit 1, `linear --version` → `linear 3.0.0`.
2. **Resolve the fork question** (§3.3) before merging BOX-241.
3. **Merge the branches** in the order in §5, with explicit approval — merging to `main` is
   one of the two things the global AGENTS.md requires asking about.
4. **Open PRs** only if the user wants them; also gated on approval.
5. Optional cleanup: BOX-190's fork-branch deletion is now purely cosmetic (§3.3).

---

## 7. Suggested skills

Call the Skill tool for these before proceeding:

- **`nix-debug`** — for building/verifying on the remote Macs and correlating module config
  with runtime behaviour once a `switch` happens.
- **`code-review`** — run the two-axis (Standards + Spec) review against `origin/main` for
  each branch before merging; this diff spans Nix overlays, agent docs, and a lockfile.
- **`nix-flake`** — for the `flake.lock` seams: BOX-240 pruned a node, BOX-241 moved one,
  and they must stay independently valid.
- **`container-manager`** / **`nix-module`** — only if the follow-up work drifts into
  module or image territory; not needed for the merge itself.

Also worth reading, without a skill invocation:

- `/home/podman/nix-config/AGENTS.md` — Linear-not-GitHub, conventional commits, push
  feature branches freely, **ask before `main` and before PRs**.
- `/home/podman/nix-config/docs/agents/issue-tracker.md` — note the 3.0.0 write-up on the
  BOX-242 branch **is not yet on `main`**; commands against the old 2.6.0 surface still work
  until it merges.
- `/home/podman/nix-config/lib/overlays/claude-code.nix` — the reasoning for keeping that
  overlay permanent ("NOT self-terminating … Keep it.").

---

## 8. Redactions

No credentials, tokens, or personal identifiers are reproduced here. Secret references are
by **name and file path only**: the Linear API key reaches the CLI via
`/run/secrets/linear-api-key` populated by `host-secrets-populate` (BOX-179, see
`SECRET_SYNC.md` and `docs/adr/0001-operator-tool-secrets-via-run-secrets.md`), and on the
Darwin hosts via the chezmoi secrets cache. Nothing in this document should be pasted into
an issue or a commit message.
