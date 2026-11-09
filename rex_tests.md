While you switch, a few things to watch — all from the module source, so these are what a failure
looks like rather than guesses:

On lumquat:

- systemctl status rex-login-server should show active (running) and Type=notify-reload.
- systemctl status rex-tailscale-serve — this is the one that would have failed without HTTPS
  certs. It runs tailscale wait then tailscale serve --https=443. Since you enabled certs, it
  should come up clean.
- cat /etc/rex/accounts.jsonc should show podman and ashebanow, both with
  tailscale:ashebanow@gmail.com.

On yuzu:

- systemctl status rex — now a system unit, not a user unit, running as ashebanow. If it failed,
  journalctl -u rex will say why; the most likely cause is the tailnet listener
  (`tailnet://100.127.173.24:7297`). If it says "cannot assign requested
  address", the tailnet IP has changed — run `tailscale ip -4` and update
  `my.rexServerTailnetAddress` in hosts/yuzu/configuration.nix. The bare
  `tailnet://:7297` form crash-loops on yuzu and is deliberately not used.
- systemctl --user status rex should fail to exist — if a stale user unit from a previous
  experiment is still around, it'd collide on the socket.

Then the real test, from a Mac:

```
  rex --server lumquat.fluffy-walleye.ts.net ls
  rex --server yuzu.fluffy-walleye.ts.net:7297 ls
```

If lumquat connects but yuzu times out, that's the tailnet:// listener rather than auth — and if
both prompt or refuse, it's identity, which would mean the principal doesn't match
ashebanow@gmail.com.

One caveat worth flagging now: on the Macs, rex won't be on PATH until darwin-rebuild switch runs,
and the ssh guard needs rex terminfo setup — but neither is needed to test connectivity, since rex
--server <host> uses the local rex you already have.

Ping me with whatever just switch reports, or if a service lands in failed.
