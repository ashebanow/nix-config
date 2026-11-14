# Rex — the terminal multiplexer

Two roles, in two scopes. They are layers, not alternatives: the client is a
prerequisite for the server, and on macOS it is the whole story.

| Role | Scope | Flag | What it is |
| --- | --- | --- | --- |
| client | Home Manager | `my.rexClient` | `rex`, the `xterm-rex` terminfo entry, the ssh guard |
| server | NixOS | `my.rexServer` | one server for this host's own account, published through Rex's own tailnet node |

| Host | client | server | node |
| --- | --- | --- | --- |
| lumquat | via `installClient` | `my.rexServer` as `podman` | `lumquat-rex` |
| yuzu | `my.rexClient` | `my.rexServer` as `ashebanow` | `yuzu-rex` |
| bergamot, miraclemax | `my.rexClient` | none — the Rex **app** runs it | `<host>-rex` |

## Connecting

Every server publishes over its own embedded Tailscale node, so a hostname is
all a client needs — no port, no Serve mapping:

```sh
rex --server lumquat-rex.fluffy-walleye.ts.net ls
rex --server yuzu-rex.fluffy-walleye.ts.net ls
```

That same `https://<host>-rex.<tailnet>.ts.net` address is what goes in the Rex
app's "add remote host" dialog.

## Why the servers use an embedded node

Rex's native integration is tsnet: the server runs its own Tailscale node,
obtains its own HTTPS certificate, and publishes natively. No Tailscale Serve,
no `tailscale serve` command, no host `tailscaled` involvement.

Three earlier designs in this repo each failed for the same underlying reason —
they exposed the service **manually**:

1. `tailnet://:<port>` (empty host) crash-looped. Rex expands the empty host to
   every tailnet address; `tailscale0` has no IPv6 address; the IPv6 bind fails
   with `cannot assign requested address`, and systemd restarts forever.
2. Pinning the IPv4 address fixed the bind, but hardcoded an address that drifts
   when the node is re-authenticated — and left the listener as raw TCP with no
   TLS, so the app could not find the server at all.
3. Adding Tailscale Serve on top gave the app its HTTPS, but reintroduced
   exactly the manual exposure tsnet exists to remove.

So there is no `extraListen`, no `tailscaleServe`, and no address option.

## Why there is no login server

The Rex login server maps *many* Tailscale identities onto *many* local
accounts. It cannot use tsnet — `rex login-server` has no `--tailscale` flag,
only `rex server run` does — so it can only publish through the host's
`tailscaled` plus Serve, i.e. the manual path above.

On this tailnet each host serves one account, so the shared server is both
sufficient and the only one that can publish natively. Restriction is
Tailscale's job (the node is owner-only) rather than an accounts file.

**Consequence to remember:** anyone admitted to a Rex node acts as that host's
`my.rexServerUser` — `podman` on lumquat, `ashebanow` on yuzu. There is no
per-account mapping.

## Auth keys

Each tsnet node needs a Tailscale auth key at first enrolment only. They are in
BWS as:

| BWS item | Variable | Scope |
| --- | --- | --- |
| `lumquat-rex-tailscale-auth-key` | `REX_LUMQUAT_TS_AUTHKEY` | `host-lumquat` |
| `yuzu-rex-tailscale-auth-key` | `REX_YUZU_TS_AUTHKEY` | `host-yuzu` |

`host-secrets-populate` writes the host's key to
`/run/secrets/rex-tailscale-auth-key`, and the service reads it as a systemd
credential.

**These are non-reusable (one-time) keys**, deliberately: the key is spent at
first enrolment, after which the node identity persists under
`/var/lib/rex/tsnet/<hostname>`. A leaked key therefore enrols nothing. They are
per-node rather than shared so one leaked key cannot create a node named after
another host.

### Re-enrolling a node

A one-time key is **consumed on first start**, so these situations need a
freshly minted key:

- `/var/lib/rex` was wiped (a rebuild from scratch);
- the node was deleted in the Tailscale admin console.

Symptom: `rex.service` fails to start and the journal shows an enrolment error.
Mint a new key in the admin console, replace the BWS item value, then
`just switch` (or restart `host-secrets-populate` and `rex`).

Note the ordering: create the BWS item **before** the first switch that enables
the server, or the first start fails and wastes the key.

### Startup ordering

`rex.service` is `Requires=`/`After=host-secrets-populate.service`, because its
`LoadCredential` reads `/run/secrets/rex-tailscale-auth-key` — a tmpfs file the
populator writes at boot. Without that dependency the two start in parallel and
systemd can exec `rex` before the file exists:

```
rex.service: Failed to set up credentials: No such file or directory
rex.service: Failed at step CREDENTIALS (status=243)
```

That failed a whole `nixos-rebuild switch` on the first deploy. It does **not**
consume the one-time key (systemd aborts before exec), so a retry with the same
key works — but the switch itself reports failure.

## Local access

The server also listens on `/run/rex/server.sock`, mode `0660`, owned by
`my.rexServerUser` and the `rex` group. Members of `rex` (and the owning
account) can attach locally. A consequence to expect: `rex` run as the account
prefers its *personal* server socket and will report that this machine also has
a shared server, at `/run/rex/server.sock` — add `-S /run/rex/server.sock` or
set `REX_SERVER=/run/rex/server.sock`.

## Why lumquat sets no `my.rexClient`

The Rex NixOS module installs the client into `environment.systemPackages` for
every user (`installClient`, default true), so the server host already has
`rex` — the same binary `programs.rex` would put in `home.packages`. The Home
Manager module only adds the terminfo copy in `~/.terminfo`, the ssh guard in
`programs.ssh.includes`, and `~/.config/rex/init.lua`. The NixOS module already
supplies terminfo to the service and the ssh guard to `/etc/ssh/ssh_config`.

lumquat also has no `hosts/lumquat/capabilities.nix`, so Home Manager scopes
there do not see its `my.*` flags at all. That is **intent**: lumquat is a
deliberately minimal headless host, and its topical tool modules live in the dev
shell rather than in the profile. Rex is unaffected because its client arrives
through `installClient`.

## ssh guard on the macs

`programs.rex` adds the guard through `programs.ssh.includes`, which requires
`programs.ssh.enable`. That is **not** enabled on any host here: `~/.ssh/config`
is chezmoi's, and turning `programs.ssh` on would have Home Manager and chezmoi
write the same file in turn. The module prints a warning instead.

Until the dotfiles repo carries the guard, ssh from a Rex terminal on a Mac
forwards `TERM=xterm-rex` to hosts that may not know it. The fix belongs in
`private_dot_ssh/private_config.tmpl` in the dotfiles repo:

```
Include ~/.config/rex/ssh_config
```

plus a one-time `rex terminfo setup` to write `~/.config/rex/ssh_config`. Yuzu
and lumquat are unaffected — their guard comes from the NixOS module.

## Other services stay on Serve

Bifrost, Open WebUI and the LLM endpoints each run their own tailscaled sidecar
and serve through Serve/their own node. That is unrelated to Rex and unchanged —
Rex is an interactive session host, they are services.

## Updating

The input is the **`preview`** channel, which tracks the same `0.1.0` line as
the Rex app. `flake.lock` records the release's immutable URL, so a lock keeps
working after newer releases ship; `nix flake update rex` moves to the newest.
A version bump restarts the servers, which ends every session — restart
deliberately.

Updating does **not** require re-enrolling the tsnet node: its identity lives in
`/var/lib/rex/tsnet/node/tailscaled.state`, a systemd `StateDirectory` that
survives rebuilds, so the one-time auth key stays spent.

### Channel choice is a protocol decision, not a freshness preference

The channels are different version lines, not just different release cadences:

| channel | version shape | API revision (2026-11-14) |
| --- | --- | --- |
| `snapshot` | `0.0.<unix-ts>-g<sha>` | 12 |
| `preview` | `0.1.0-preview.N` | 14 |
| `stable` | — | nothing published (the blob 404s) |

The app is on the `0.1.0` line. Running a `snapshot` server against it broke the
**block data channel** while leaving the control channel working:

```
# server (snapshot, api revision 12)
data.connect          rpc_status=200
http: TLS handshake error from 100.109.50.42:59099: EOF    # ~5s later, forever
```

Symptom: the app connects, lists hosts, creates a session, and then **spins**
forever opening a terminal. The shell is actually running and healthy —
`rex send` / `rex capture` drive it fine — the app simply cannot establish the
block data stream.

The CLI masked the skew completely, because the pinned CLI was revision 12 too,
in step with the server. Only the app was ahead.

So: **if a terminal spins while the control plane works, check API revision
skew before touching configuration.** `rex version` prints it.
