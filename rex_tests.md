Rex test checklist (BOX-292)

Both NixOS hosts run a Rex server published through Rex's own embedded Tailscale
node (tsnet). No Tailscale Serve, no raw listeners, no addresses to maintain.

## Before the first switch

- The BWS items `lumquat-rex-tailscale-auth-key` and
  `yuzu-rex-tailscale-auth-key` must exist. The keys are ONE-TIME: they are
  spent on first start, so a failed first start burns one and needs a fresh key.

## On yuzu

- `systemctl status host-secrets-populate` — must be active, and
  `/run/secrets/rex-tailscale-auth-key` must exist (0600 root).
- `systemctl status rex` — active (running), running as `ashebanow`.
- `journalctl -u rex` should show the tsnet node coming up. A failure here is
  almost always enrolment: a spent key, a revoked key, or no network.
- `systemctl status rex-tailscale-serve` should **not exist** — Serve is gone.
- `tailscale status | grep yuzu-rex` on yuzu should list the new node.

## On lumquat

- Same three checks, with the user `podman` and the node `lumquat-rex`.
- `systemctl status rex-login-server` should **not exist** — the login server is
  gone.

## From a Mac

```
  rex --server yuzu-rex.fluffy-walleye.ts.net ls
  rex --server lumquat-rex.fluffy-walleye.ts.net ls
```

Bare hostnames, no port. The same values go in the Rex app's "add remote host"
dialog.

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

## Local access on the server itself

`rex` run as `ashebanow` on yuzu prefers its personal socket and reports that
this machine also has a shared server. Use `-S /run/rex/server.sock` or
`REX_SERVER=/run/rex/server.sock`.
