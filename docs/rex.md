# Rex — the terminal multiplexer

Three roles across two scopes. They are layers, not alternatives: the client is
a prerequisite for either server, and on macOS it is the whole story. The two
server roles are the only mutually exclusive pair — the Rex module asserts it,
because both own `/run/rex` and the Serve mapping.

| Role | Scope | Flag | What it is |
| --- | --- | --- | --- |
| client | Home Manager | `my.rexClient` | `rex`, the `xterm-rex` terminfo entry, the ssh guard |
| login server | NixOS | `my.rexLoginServer` | root process; one Rex server per account, caller identity from the host's `tailscaled`, allowlist in `/etc/rex/accounts.jsonc` |
| shared server | NixOS | `my.rexServer` | one server for this host's own account, published through Rex's own tailnet node |

| Host | client | server | address |
| --- | --- | --- | --- |
| lumquat | via `installClient` | `my.rexLoginServer` over Serve | `lumquat` (host tailnet name) |
| yuzu | `my.rexClient` | `my.rexServer` as `ashebanow` | `yuzu-rex` |
| bergamot, miraclemax | `my.rexClient` | none — the Rex **app** runs it | `<host>-rex` |

## Connecting

The shared server publishes over its own embedded Tailscale node, so a hostname
is all a client needs. The login server publishes through the host itself, so
its address is the host's own tailnet name, and the account is chosen in the
URL:

```sh
rex --server yuzu-rex.fluffy-walleye.ts.net ls
rex --server lumquat.fluffy-walleye.ts.net ls                      # default account
rex --server https://podman@lumquat.fluffy-walleye.ts.net ls       # explicit account
```

In the Rex app, add `yuzu-rex.fluffy-walleye.ts.net` (shared) or
`lumquat.fluffy-walleye.ts.net` (login server) as a remote host.

## Why the shared server uses an embedded node

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

So the *shared* server has no `extraListen`, no `tailscaleServe`, and no address
option. These are the lessons the login server's deployment inherits: it cannot
use tsnet, so it does exactly what failed here — `tailscaled` plus Serve — and
is accepted only because the caller's identity (which it needs and the shared
server does not) arrives with it.

## The login server on lumquat

lumquat runs `my.rexLoginServer`: root, serving `podman` as this host's
operator account and, through the wildcard, any other regular account a caller
names. yuzu runs the shared server instead, because it is the box other devices
attach to as one person.

The login server cannot use tsnet — `rex login-server` has no `--tailscale`
flag, only `rex server run` does — so it publishes through the host's
`tailscaled` plus Tailscale Serve, on **443** (Serve owns that port for every
tailnet connection, and the clients reach the host with no port). That is the
manual path the shared server exists to avoid, and it is the reason each host
picks one role rather than both.

Tailnet ACLs stay the outer door: only tailnet members can connect at all. The
accounts file is the inner one: it decides which local account each caller
becomes.

**Consequence to remember:** a caller who matches an account's principals acts
as that account — `podman` on lumquat. There is no per-session privilege drop.

## The accounts file

`/etc/rex/accounts.jsonc` is the login server's entire allowlist. It is installed
by `my.rexLoginServer` from `modules/features/rex/accounts.jsonc`, through
`environment.etc` — Rex's own default path, written atomically per generation
like every other `/etc` file NixOS manages, instead of being hand-edited on the
host (a change made on the host is discarded by the next switch, which is the
point).

Three options existed and only one fits:

- `services.rex.loginServer.accounts` / `defaults` generate the same file from
  Nix, but cannot express the wildcard account `*` (an attribute name
  `lib.mapAttrs`/`lib.mapAttrsToList` reject as an attribute path).
- `services.rex.loginServer.accountsFile` lets Rex read a file we install
  ourselves. That is what the module uses; it is mutually exclusive with the
  generated form.
- Editing the file on the host by hand — what it was before — is not
  reproducible and not recoverable after a rebuild.

The file is HuJSON (JSON plus `//` comments), because Rex parses it with
`github.com/tailscale/hujson`, and its loader is **strict**: unknown fields are
rejected, so only `version`, `accounts`, and `defaults` exist, and only
`principals` inside an account.

```json
{
  "version": 1,
  "accounts": {
    "podman": { "principals": ["tailscale:ashebanow@gmail.com"] },
    "*":      { "principals": ["tailscale:ashebanow@gmail.com"] }
  },
  "defaults": { "tailscale:ashebanow@gmail.com": "podman" }
}
```

What the shipped file grants:

| entry | why |
| --- | --- |
| `podman` | the only account lumquat has (there is no `ashebanow` account there), named explicitly |
| `*` | any regular account (UID ≥ 1000) the caller names — systemd/podman dynamic users come and go and cannot be listed statically. The same single principal, so it adds reach without widening *who* may act |
| `tailscale:<login>` | the owner, asserted by Tailscale login: `ashebanow@gmail.com` (check it with `.User` in `tailscale status --json`, not `.Self` — see below) |

**The principal is a login, not a tag.** lumquat's own node is tagged
(`tag:prod`), so `.Self.LoginName` is `null` and `.Self.Tags` is
`["tag:prod"]`. That describes the *server*; the principals in this file
describe the *callers*, and the owner's clients authenticate as
`ashebanow@gmail.com`. Reading `.Self` and concluding the login is unavailable
is the easy mistake here.

Deliberately absent:

| key | why not |
| --- | --- |
| `tailscale:tag:*` | matches any tag on any node — including lumquat's own `tag:prod` — so it is wider than one operator needs. Use `tailscale:tag:prod` (verified to parse; bare `tag:prod` and `tag:tag:prod` are rejected) if a tagged machine should attach |
| `root` | Rex maps UID 0 warily and nothing here needs it: account servers run as the account they serve |
| `anonymous` | valid, but it matches nobody while the only listener is Serve, and would match the moment a plain TCP listener were added. It is also rejected outright under the wildcard account `*` |

Principal keys are validated at startup; anything Rex cannot parse is a load
error, not a silent never-match. `anonymous` is a valid principal, so **never
put it in a file the tailnet ACLs cannot protect**: with Serve only, callers are
always identified by Tailscale and `anonymous` matches nobody, but it would
match the moment a plain TCP listener were added.

### Permissions

`0644 root:root`, stated explicitly in the module. Verified by building the
generation, not by reading `/etc` on the host:

```
$ grep accounts etc/systemd/system/rex-login-server.service
ExecStart=… /bin/rex login-server … --accounts /nix/store/…-source/modules/features/rex/accounts.jsonc …
$ cat etc/rex/accounts.jsonc.mode          # the metadata etc-activate applies
0644
$ cat etc/rex/accounts.jsonc.uid           # and its owner
+0
```

Why not `0600`: nothing in the file is a secret. Every value is a tailnet login,
a tag wildcard, or an account name — all discoverable from `tailscale status` by
any local user. The property that matters is that **only root can change it**,
because a writable accounts file is privilege escalation to any account root can
start a server as. `environment.etc` gives `root:root` from a read-only store
source, and the service only ever reads. 0600 would also make it unreadable to
`sudo -u` debugging and to anything that later needs a group read for no
security gain, since the content names logins rather than carrying capabilities.

The mode is only honoured because the entry has `source`: NixOS installs a
`source` entry whose mode is not `symlink` as a metadata-tracked file
(`accounts.jsonc.mode` / `.uid` / `.gid` beside it, applied by `etc-activate`).
A `text`-only entry defaults to `mode = "symlink"` and inherits whatever the
store file has, so setting `mode` there would be silently ignored.

### Reloading

Rex reads the file at startup and on SIGHUP. The module sets `reloadTriggers` to
the file, which with `accountsFile` it cannot do itself (it only tracks the
files it generates): the unit carries `X-Reload-Triggers=…`, and
`Type=notify-reload` means a switch whose generation changes the trigger
reloads the policy in place. Account servers and their sessions keep running;
only connections whose account is no longer allowed are closed.

An in-place edit of `/etc/rex/accounts.jsonc` does not trigger that, because the
installed file is a store path and /etc points at a new one each generation —
which is the reason the file lives in this repo. For a temporary manual edit:

```
sudo systemctl reload rex-login-server
```

## Auth keys

Only a host running the shared server (`my.rexServer`) has a tsnet node, and
that node needs a Tailscale auth key at first enrolment only. lumquat no longer
has one — its login server uses the host's `tailscaled`, enrolled by `my.access`
with the host's own key — so its key was removed from `secretspec.toml` as well
as from the docs. `secrets.nix` passes the variable only when `my.rexServer` is
true, so only yuzu's remains:

| BWS item | Variable | Scope |
| --- | --- | --- |
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

The shared server also listens on `/run/rex/server.sock`, mode `0660`, owned by
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
