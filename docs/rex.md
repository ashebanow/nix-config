# Rex — the terminal multiplexer

Rex plays three independent roles in this config. They are layers, not
alternatives: **the two server modes are the only mutually exclusive pair.**

| Role | Scope | Flag | What it is |
| --- | --- | --- | --- |
| client | Home Manager | `my.rexClient` | `rex`, the `xterm-rex` terminfo entry, the ssh guard |
| login server | NixOS | `my.rexLoginServer` | one root process, one server per account, caller identity from Tailscale |
| shared server | NixOS | `my.rexServer` | one server for this host's own account, reachable over the tailnet |

| Host | client | server | why |
| --- | --- | --- | --- |
| lumquat | via `installClient` | login server, Serve on 443 | multi-account allowlist |
| yuzu | `my.rexClient` | shared server, `tailnet://:7297` as `ashebanow` | the machine other devices attach to |
| bergamot, miraclemax | `my.rexClient` | none — the Rex **app** runs it | macOS |

## Why the client flag is not set on lumquat

The Rex NixOS module installs the client into `environment.systemPackages` for
every user (`installClient`, default true), so the login server host already
has `rex` — the same binary `programs.rex` would put in `home.packages`. The
Home Manager module only adds three things on top: the terminfo copy in
`~/.terminfo`, the ssh guard in `programs.ssh.includes`, and
`~/.config/rex/init.lua`. On lumquat the NixOS module already supplies the
terminfo for the service and the ssh guard for `/etc/ssh/ssh_config`, so the
Home Manager half would be duplication.

Note that lumquat has no `hosts/lumquat/capabilities.nix`, so Home Manager
scopes there do not see its `my.*` flags at all. That is **intent**, not a gap:
lumquat is a deliberately minimal headless host, and its topical tool modules
(including anything driven by a `my.cli*` flag) live in the dev shell rather
than in the profile. Rex is unaffected because its client arrives through
`installClient` — a NixOS-scope mechanism — rather than a Home Manager flag.

## Access policy on lumquat

**The tailnet is the only door.** The login server's only listener is Tailscale
Serve, so "use the multiplexer without Tailscale" is not a rule anyone can break
— there is no socket to connect to. There is deliberately no `extraListen`
entry, no plain `host:port`, and `allowAnonymous` stays false.

`my.rexAccounts` is the allowlist. A local account not named there cannot be
reached, whatever groups it is in; the shared server's `rex` group does not
exist on lumquat at all.

## Identity, passwords, and what "logged in to Tailscale" means

Two independent auth planes, neither of which involves a Unix password:

1. **Machine → tailnet.** `services.tailscale.authKeyFile`, already part of
   `my.access`. `tailscaled` is a *system* service with its state in
   `/var/lib/tailscale/tailscaled.state`; it runs at boot regardless of who is
   logged in at the console. "The host must be logged in to Tailscale" means
   the node is enrolled and `BackendState == Running` — **not** that a person
   has a shell open.
2. **Caller → login server.** Tailscale Serve forwards the calling node's
   identity over a root-owned `0600` Unix socket. The login server matches it
   against `accounts.<user>.principals`.

PAM is on (`loginServer.pam` defaults true), but not to authenticate anyone:
Rex proves identity first, and the module sets `unixAuth = false`. PAM opens a
real logind session so the account's terminals get its limits and environment —
the same model as Tailscale SSH.

## Prerequisites

- **HTTPS certificates enabled for the tailnet** (admin console: DNS → HTTPS
  Certificates), for `tailscaleServe`. Without it `rex-tailscale-serve` fails
  to get a certificate. Check with
  `tailscale cert <host>.<tailnet>.ts.net`.
- **`my.access`** on every host that runs a server. Asserted by the modules.
- Tailnet ACLs must permit the `tailnet://` port (7297) for yuzu's shared
  server.

## Connecting

```sh
# lumquat's login server — no port needed, Serve owns 443
rex --server lumquat.fluffy-walleye.ts.net ls

# yuzu's shared server — 7297 is also tried automatically
rex --server yuzu.fluffy-walleye.ts.net ls
```

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

## Updating

The input is the `snapshot` channel (every change). `flake.lock` records the
release's immutable URL, so a lock keeps working after newer releases ship;
`nix flake update rex` moves to the newest.

```sh
nix flake update rex
```

A version bump restarts the servers. On a shared server that ends every
session, so restart deliberately rather than as a side effect.
