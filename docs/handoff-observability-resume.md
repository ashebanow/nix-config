# Resuming the observability work (BOX-311)

Written 2026-11-25, at the end of the session that fixed the build breakage and
closed BOX-338. Read this before touching anything.

## Where the branch is

Work is in **`wt-box338`** on branch **`feat/box-338-box338-overview`** @
`a04454d`, pushed to origin, tree clean.

```sh
cd /Users/ashebanow/Development/nix/nix-config/wt-box338
```

**Do not assume `main/` is on `main`.** The directory named `main/` is checked
out to `feat/box-311-observability`, and actual `main` is not checked out
anywhere. This caused confusion already.

The branch carries `004f602` + `a04454d` (the Darwin NLB fix) which are **also
on `main` now** via squash commit `cb04d37`. They will show as duplicates in a
PR. Rebase onto `cb04d37` to clear it — that is a history rewrite on a pushed
branch, so ask first.

## Build discipline — read this first

**The Macs cannot build Linux anymore.** BOX-343 disabled Determinate Nix's
Native Linux Builder on both, deliberately. Every attempt to `nix build` a
NixOS host from a Mac now fails with:

```
error: Cannot build '...drv'. Required system: 'x86_64-linux'
       Current system: 'aarch64-darwin'
```

This is correct, not a bug. Build Linux on Linux:

```sh
ssh lumquat 'cd ~/nix-config && nix build --no-link --print-out-paths \
  --impure .#nixosConfigurations.<host>.config.system.build.toplevel'
```

The contract test likewise:

```sh
ssh lumquat 'cd ~/nix-config && nix eval --impure --file lib/tests/observability-contract.nix --json'
```

That eval exits 0 regardless of content; the gate is the `assertions` array.
Parse it and check every `assertion` is `true`.

**Why this matters:** the previous session lost hours to ncurses 6.6 terminfo
corruption that only occurs when cross-building, because the case-hack renames
`a`→`a~nix~case~hack~1` on a case-insensitive store but not the symlinks
inside it. Native builds are clean (verified: 0 broken symlinks on lumquat vs
351 on the mis-built Mac path). Do not reintroduce cross-builds.

## Calamansi's state (given by the user, 2026-11-25)

Wiped, bare NixOS installed, **headless**.

| Fact | Value |
| --- | --- |
| LAN IP | **`10.40.0.61`** (confirmed live, responds to ping, SSH port 22 open) |
| Subnet | `10.40.0.0/24` — the servers/storage side |
| Tailscale | **not installed** |
| Root FS | **not encrypted** (no LUKS, no TPM2) |
| podman user | exists, **password only, no SSH key** |
| podman password | BWS item `calamansi-podman-user-password` |
| Tailscale auth key | BWS item `calamansi-tailscale-auth-key` |

## Discrepancy to resolve before deploying

The user said the IP "was noted in another branch". **It is not, anywhere I
could find.** I checked:

- every working tree (`main`, `original`, `wt-box335/336/337/338`)
- all 20 refs including `origin/*` and the 5 `origin/research/*` branches
- `git log --all -S "10.40.0.61"`
- 105 dangling commits from `git fsck --no-reflogs`

Zero hits. `docs/network.md:34` still says calamansi's address is unknown, and
`hosts/lumquat/configuration.nix:80` still has the placeholder
`my.observabilityHostAddress = "10.40.60.20"`.

Treat `10.40.0.61` as **new information from the user**, not something to look
for in history. Confirm with the user before writing it in.

## The work, in order

### Step 1 — BOX-324: install and deploy (do this first, it unblocks everything)

Only Backlog ticket that blocks verification of the others. Acceptance:

- [x] calamansi wiped and NixOS installed — **done by the user**
- [ ] Real hardware configuration committed, replacing the placeholder
- [ ] calamansi deploys from the repo the same way lumquat does
- [ ] calamansi is on the tailnet
- [ ] calamansi's LAN IP recorded

**Hardware config is still a placeholder.** `hosts/calamansi/hardware-configuration.nix`
says so at the top: placeholder UUIDs, "a system built from this file cannot
boot". Run `nixos-generate-config` on calamansi and commit the real output.
Note the user did **not** encrypt the filesystem, so the real file will have no
LUKS/TPM2 — which is why `hosts/lumquat/hardware-configuration.nix`'s LUKS
block must not be copied.

**Password gap.** `modules/features/base.nix:21` creates the podman user with
`openssh.authorizedKeys.keys` and **no password**. On a fresh headless box with
no key installed that is unreachable. `calamansi-podman-user-password` exists
in BWS but **nothing in `secretspec.toml` references it** — there is no
`hashedPassword` wiring anywhere in the repo. Decide how the password gets
set, then wire it. This is the first thing that will bite.

**Bootstrap order matters:** `my.access = true` is already set on calamansi, and
`host-secrets-populate.service` aborts without `CALAMANSI_TAILSCALE_AUTH_KEY`
(already declared in `secretspec.toml` scope `host-calamansi`, alongside
`FLAKEHUB_TOKEN` and `CACHIX_AUTH_TOKEN`). So the first switch needs those three
in BWS or the unit fails and tailscaled never comes up.

**Ways in on first deploy:** SSH port 22 is open with password auth for
`podman`. The repo expects port 2222 (`my.accessFallbackPort = 2222`) which is
currently closed, so the first install is over 22 with a password; 2222 comes up
after the first switch.

### Step 2 — write the IP into the two places that need it

1. `docs/network.md` — the calamansi line (~34) and the config table (~53).
2. `hosts/lumquat/configuration.nix:80` — replace the `10.40.60.20` placeholder
   with `10.40.0.61`, and update the comment above it that explains it is a
   placeholder.

Also check `my.observabilityHostAllowedSources` on calamansi (currently
`[ "10.40.0.87" ]`, lumquat's address) — if calamansi is now `10.40.0.61` the
*ingest* allow-list may need `10.40.0.59` (storage2) and `10.40.60.1` (gateway)
added for the syslog path.

### Step 3 — verify the in-review stack on real hardware

These are code-complete but were never run on a real observability host:

| Box | What it adds |
| --- | --- |
| BOX-326 | the `my.observability` option set |
| BOX-327 | remote agent, GPU telemetry, Host detail dashboard |
| BOX-329 | vmalert, Alertmanager, Pushover, watchdog |
| BOX-330 | journal shipping, VictoriaLogs |
| BOX-331 | container metrics, llama.cpp scrape targets |
| BOX-334 | storage2 over SNMPv3 |

Then the Backlog ones that unblock once calamansi exists:

| Box | What it adds |
| --- | --- |
| BOX-332 | textfile checks, bifrost log dashboard |
| BOX-335 | syslog/CEF from the gateway and storage2 |
| BOX-336 | metrics backup |
| BOX-337 | log archive to storage2 |
| BOX-340 | Todo |

**BOX-338 is Done** — Overview dashboard, verified building and 120/120
contract assertions on lumquat. Its one unfinished criterion is the
**on-host visual check on an iPhone-sized viewport**, which needed calamansi.
Worth confirming once Grafana is up, since it is the one thing code review could
not establish.

## Gotchas that cost real time last session

1. **`bws` takes ~40 minutes to build** (376 Rust crates). Prebuild it before
   any long build:
   ```sh
   nix build --no-link --print-out-paths --impure \
     --expr 'let f=(builtins.getFlake (toString ./.)); in f.nixosConfigurations.lumquat.pkgs.bws'
   ```
2. **A `nix build` with low CPU and no output is usually Rust compiling**, not a
   hang. Check with `-L` before concluding anything.
3. **`nix eval --file ... --json` exits 0 even when assertions fail.** Parse the
   JSON; do not trust the exit code.
4. **lumquat's working copy is on `feat/box-292-rex-login-server`** with a dirty
   `modules/infra/devshell.nix`. It is not a clean mirror. Stash carefully, and
   restore it when done — that was done last time, verify it still holds.
5. **The default Nix substituters stall occasionally.** 8 are configured; one
   going quiet costs up to 300s per attempt. If a build seems wedged, probe
   them rather than waiting.

## Ticket states as of this writing

Done: BOX-315, 319, 320, 322, 328, 338, 339, 341 (Won't Fix), 342 (Won't Fix),
343.
In Review: BOX-326, 327, 329, 330, 331, 334.
Backlog: BOX-324, 325, 332, 335, 336, 337.
Todo: BOX-340.
