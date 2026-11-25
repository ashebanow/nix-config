Rex test checklist (BOX-292)

yuzu runs a Rex server published through Rex's own embedded Tailscale node
(tsnet): no Tailscale Serve, no raw listeners, no addresses to maintain.
lumquat runs the **login server**, which cannot use tsnet (no `--tailscale`) and
therefore publishes through the host's tailscaled plus Serve on 443, with
`/etc/rex/accounts.jsonc` as the allowlist.

## Before the first switch

- yuzu only: the BWS item `yuzu-rex-tailscale-auth-key` must exist. The key is
  ONE-TIME: it is spent on first start, so a failed first start burns one and
  needs a fresh key. `lumquat-rex-tailscale-auth-key` was removed from
  `secretspec.toml` (declaration and `host-lumquat` scope entry) because
  lumquat's login server uses the host's own tailscaled; delete the BWS item too
  when convenient — nothing reads it.

## On yuzu

- `systemctl status host-secrets-populate` — must be active, and
  `/run/secrets/rex-tailscale-auth-key` must exist (0600 root).
- `systemctl status rex` — active (running), running as `ashebanow`.
- `journalctl -u rex` should show the tsnet node coming up. A failure here is
  almost always enrolment: a spent key, a revoked key, or no network.
- `systemctl status rex-tailscale-serve` should **not exist** — Serve is gone.
- `tailscale status | grep yuzu-rex` on yuzu should list the new node.

## On lumquat

lumquat runs the **login server**, not the shared server: no tsnet node, no
`rex.service`, no `lumquat-rex`.

- `systemctl status rex-login-server` — active (running), as root.
- `systemctl status rex-tailscale-serve` — the unit owning the 443 mapping.
- `systemctl status rex` and `rex.service`'s credentials — **must not exist**
  (that was the tsnet design, and `lumquat-rex` should be deleted from the
  tailnet admin console once the old generation is gone).
- `/etc/rex/accounts.jsonc` exists, and its permissions are the configured ones:

  ```
  stat -c '%a %U:%G %n' /etc/rex/accounts.jsonc   # expect 644 root:root
  ls -l /etc/rex/accounts.jsonc                   # a regular file, not a symlink
  ```

  A hand-edited copy is what this replaces: if `/etc/rex/` still holds a plain
  file with older content, the switch did not install it. (The device number
  being huge is normal — `etc-activate` replaces `/etc` with the generation's
  copy on switch.)
- The file the service actually reads is the one in `ExecStart`:

  ```
  systemctl cat rex-login-server | grep -- --accounts
  ```

- `journalctl -u rex-login-server` — `login server starting`, then
  `Account policy reloaded` after a change so the `SIGHUP` path is exercised.
- `journalctl -u rex-tailscale-serve` — no certificate or 443 conflict errors.

## From a Mac

```
  rex --server yuzu-rex.fluffy-walleye.ts.net ls
  rex --server lumquat.fluffy-walleye.ts.net ls       # login server, default account
  rex --server https://podman@lumquat.fluffy-walleye.ts.net ls
```

Bare hostnames, no port. The same values go in the Rex app's "add remote host"
dialog. On lumquat, `https://<account>@lumquat…` with an account the file does
not grant must be refused by the login server (not by Tailscale) — that is the
accounts file being read at all.

Note: the Rex *app* on a Mac creates its own node (`miraclemax-rex`,
`bergamot-rex`). Those are separate from the NixOS servers and appear in the
tailnet only while the Mac is awake with Rex running.

## What a failure looks like

| Symptom | Cause |
| --- | --- |
| rex.service restart loop, "cannot assign requested address" | cannot happen any more — that was the raw-listener design; if seen, the deployed generation is old |
| rex.service fails at start, enrolment error | auth key spent/revoked; mint a new one and update BWS |
| node appears but the app cannot connect | `allowTailnetMembers` is false (owner-only) and the app is signed into a different Tailscale account |
| `rex -S … ls` works locally but not from the Mac | the app/Mac is using a different tailnet identity |
| lumquat: every account refused, including `podman` | the principal in the file does not match this node's login — `tailscale status --json` shows `Self.LoginName`/`Self.Tags`, and the key must be `tailscale:<that login>` or `tailscale:tag:*` |
| lumquat: `rex-login-server` exits with `loading accounts file` | the accounts file is invalid HuJSON or names an unknown field; rex validates at startup, so the journal names the offending entry |

## Changing the accounts file

Edit `modules/features/rex/accounts.jsonc` in this repo and switch — never
`/etc/rex/accounts.jsonc` on the host, which is a symlink into the generation
and will be replaced. A content change adds the derivation to
`reloadTriggers`, so `rex-login-server` reloads the policy; account servers and
their sessions keep running.

To reload by hand after a manual edit (temporary, unsupported):

```
sudo systemctl reload rex-login-server
```

## Local access on the server itself

`rex` run as `ashebanow` on yuzu prefers its personal socket and reports that
this machine also has a shared server. Use `-S /run/rex/server.sock` or
`REX_SERVER=/run/rex/server.sock`.
