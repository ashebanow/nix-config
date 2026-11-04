# Gaming on NixOS: Battle.net and Diablo IV via umu-launcher

Operating guide for `modules/features/gaming.nix`. Install, update, and the
recovery procedures — including what to do when a Wine prefix breaks, which is
the one failure mode that matters in practice.

The module itself explains _why_ it is shaped the way it is (that reasoning
lives as a header comment in the file, deliberately next to the code it
describes). This file is the _how_.

## What this is, in one paragraph

`pkgs.umu-launcher` runs a Windows program inside a **Wine prefix** — a
complete fake `C:` drive with its own registry and `system32` — using
`pkgs.proton-ge-bin` as the Proton build. Battle.net is installed into that
prefix, and Diablo IV is installed by Battle.net. Nothing is containerised and
nothing runs as root. Nix owns the wrappers and the desktop entries; **it does
not own the prefix**, which is ordinary mutable state under `$HOME`.

Everything is nixpkgs — there is no third-party flake input, and nothing in
`flake.lock` tracks gaming. `umu-launcher` (1.4.4) and `proton-ge-bin`
(GE-Proton11-11) are already packages of the pinned nixpkgs, so an update
arrives with `nix flake update nixpkgs`, not with a gaming-specific bump.

## Layout

One prefix per name listed in `my.gamingWinePrefixes` on the host
(`hosts/yuzu/capabilities.nix` sets `[ "yuzu" ]`):

```
~/.local/share/battlenet-umu/prefixes/yuzu/     ← the Wine prefix (the C: drive)
    drive_c/Program Files (x86)/Battle.net/     ← Battle.net itself
    drive_c/Program Files (x86)/Diablo IV/      ← where D4 ends up
    drive_c/windows/system32/                   ← Wine's own
    system.reg, user.reg, userdef.reg           ← the registry
```

The name you choose is the directory name and part of every command name, so
`ls ~/.local/share/battlenet-umu/prefixes/` answers "which C: drives exist on
this machine" without opening any of them.

| Command | What it does |
|---|---|
| `battlenet-umu-install-<name>` | Downloads Battle.net's installer and runs it. Once per prefix. |
| `battlenet-umu-<name>-<game>` | Launches a game through Proton. Also appears in the app menu. |

On yuzu that is `battlenet-umu-install-yuzu` and
`battlenet-umu-yuzu-battlenet`.

## Installing

Prerequisites, once per host: `my.gaming = true` and
`my.gamingWinePrefixes = [ "yuzu" ];` in `hosts/yuzu/capabilities.nix`, then
`just switch` (or `nh os switch`).

Then, as your normal user — **not** root, and from a terminal, because the
installer is interactive:

```bash
battlenet-umu-install-yuzu
```

It asks for confirmation, downloads
`Battle.net-Setup.exe`, and runs it under Proton. In the installer:

- **Leave the install location at the default.** It resolves to
  `C:/Program Files (x86)/Battle.net`, which is exactly where the launcher
  wrapper looks. Changing it means also setting
  `programs.gaming-umu.winePrefixes.<name>.games.*.exec`.
- When Battle.net opens, install **Diablo IV** from inside it. There is no
  separate Nix entry for D4 — Battle.net owns the download, the patching and
  the launcher, and the wrapper's whole job is to start Battle.net.

First run downloads two things beyond the installer: Battle.net itself, and
the Steam Linux Runtime that umu fetches on first use. Both are large; budget
time and disk.

### The one unpinned download, stated plainly

`Battle.net-Setup.exe` is fetched at runtime from
`https://downloader.battle.net/...` over TLS. It is **not** pinned or hashed,
and it cannot sanely be: Blizzard rotates the payload continuously, so a hash
committed here would pin a build that no longer exists within days. It runs
once, as the user, inside a Wine prefix, with no root involved — the same trust
decision installing Battle.net on Windows makes, just made in one visible
command instead of buried in a launcher's first-run branch.

### `programs.gaming-umu.winePrefixes` (optional)

Names in `my.gamingWinePrefixes` are enough to get a working default:
Battle.net launcher, `pkgs.proton-ge-bin`. Override per prefix from a
Home Manager module — note this option is **Home Manager only**, so it cannot
go in `capabilities.nix` (which is evaluated by the NixOS module system too):

```nix
programs.gaming-umu.winePrefixes = {
  yuzu = {
    proton = pkgs.proton-ge-bin;   # per-prefix, not per-game
    games = [ { name = "Battle.net"; gameId = "umu-battlenet"; } ];
  };
};
```

`proton` is per prefix because one prefix cannot sanely be driven by two Proton
builds — trying a new build is itself a reason to make a second prefix.

## Updating

Three things update on three different clocks. Keeping them apart is most of
what "updating" means here.

### 1. Diablo IV and Battle.net — not yours to manage

Battle.net patches D4 itself, in-app, exactly as on Windows. This is the
common case and needs nothing from Nix. Do not try to pin or freeze it.

### 2. umu-launcher and Proton-GE — with nixpkgs

```bash
nix flake update nixpkgs
just switch
```

Then **launch Battle.net and confirm it still opens before closing the door on
the previous generation.** A Proton major bump is the single most likely change
to require a prefix repair, and knowing that's the cause saves an hour of
confused debugging.

Check what you're on:

```bash
nix eval --raw .#nixosConfigurations.yuzu.pkgs.umu-launcher.version
nix eval --raw .#nixosConfigurations.yuzu.pkgs.proton-ge-bin.version
```

To try a new Proton **without risking the working install**, create a throwaway
prefix — this is the cheapest use of the multi-prefix design:

```nix
# hosts/yuzu/capabilities.nix, temporarily
my.gamingWinePrefixes = [ "yuzu" "probe" ];
```

```bash
just switch
battlenet-umu-install-probe     # install into the new prefix and test
```

If the new build misbehaves, drop `"probe"` from the list; `yuzu` was never
touched. Leave the directory behind until you're confident, then `rm -rf` it
("Fixing corruption" covers why deleting a prefix is safe).

### 3. The Steam Linux Runtime — umu's own download

umu fetches the runtime from Steam's CDN on first use, and re-checks it only
when none is installed. `UMU_RUNTIME_UPDATE` is deliberately left unset in the
module: setting it to `1` would put a network call in the launch hot path for a
component that changes rarely.

If a runtime update is actually wanted, removing the cached runtime makes umu
re-fetch it. The layout, read from `umu_consts.py` / `umu_runtime.py` in the
packaged 1.4.4 rather than guessed:

```
~/.local/share/umu/steamrt2/      ← Soldier runtime      (appid 1391110)
~/.local/share/umu/steamrt3/      ← Sniper runtime       (appid 1628350)
~/.local/share/umu/steamrt4/      ← SteamRT 4            (appid 4183110)
~/.local/share/umu/compatibilitytools/       ← UMU_COMPAT
~/.cache/umu/                                ← download staging (UMU_CACHE)
```

A runtime is considered installed when its directory contains `mtree.txt.gz`.
To force a re-fetch, remove just that one variant's directory:

```bash
rm -rf ~/.local/share/umu/steamrt3     # then launch; umu downloads it again
```

**Do not delete `~/.local/share/umu/` wholesale.** It is umu's own state, not
the game prefix — nothing about Battle.net lives there — and removing it cannot
fix a broken prefix.

## Fixing corruption

Wine prefixes break. That is normal, not a sign of a mistake: an update
half-applies, the registry accumulates junk, a Proton version change lands
badly, and Battle.net stops launching. **The fix is always the same, and it
always works: the prefix is disposable and rebuildable.**

The cost is the reinstall, which is why a second prefix is worth having (below).
There is no data in the prefix worth preserving — no saves, no configuration.
Diablo IV characters live on Blizzard's servers; the prefix holds only program
files and a Windows registry.

### Triage first

In rough order of how cheap the fix is. Stop as soon as one works.

**1. A game entry is missing but Battle.net is fine.** Not corruption. The game
isn't installed in that prefix, or `exec` points at the wrong path:

```bash
ls ~/.local/share/battlenet-umu/prefixes/yuzu/drive_c/Program\ Files\ \(x86\)/
```

**2. Nothing launches, or Battle.net exits immediately.** Confirm you're
hitting the module's own path and not a stale wrapper:

```bash
ls -l "$(readlink -f "$(command -v battlenet-umu-yuzu-battlenet)")"
battlenet-umu-yuzu-battlenet          # read the error it prints
```

Then check the graphics stack underneath. A broken host Vulkan looks exactly
like a broken prefix, and fixing the prefix would be wasted work:

```bash
vulkaninfo --summary | grep -i deviceName     # expect the Strix Halo iGPU
```

**3. It worked before a Proton bump.** The highest-value checkpoint — see "Updating", item 2.
Either go back (`git checkout` the previous `flake.lock`, `just switch`) or
start clean per below. Don't debug Proton internals.

**4. Battle.net launches but a specific game won't.** Almost always the game's
own files. Have Battle.net "Scan and Repair" the D4 install from its
`Options` menu before touching the prefix.

### Repairing: the actual procedure

Work up this ladder. Each step is strictly more work than the last.

```
a. Restart cleanly — no Wine processes left over
b. Clear the DXVK/VKD3D shader caches (they are corruptible and cheap to lose)
c. Remove Battle.net's own cache directories inside the prefix
d. Rebuild the prefix from scratch
```

**(a) Kill stragglers.** A Wine process that didn't die holds the prefix and
makes every later symptom lie:

```bash
wineserver -k 2>/dev/null || true
pgrep -af 'Battle.net|Agent.exe|wine' # should be empty
```

**(b) Clear shader caches.** DXVK/VKD3D caches live inside the prefix and
rebuild themselves; a corrupt one can crash a game that otherwise works.

Note the user directory: umu creates `drive_c/users/steamuser` and symlinks your
Unix login name to it (`umu_run.py`), so either name resolves. Glob it rather
than hardcoding one:

```bash
P=~/.local/share/battlenet-umu/prefixes/yuzu
rm -rf "$P"/drive_c/users/*/AppData/Local/D3DSCache
find "$P" -maxdepth 2 -name '*.dxvk-cache' -delete
```

**(c) Remove Battle.net's caches.** Battle.net keeps an `Agent` directory and a
cache; removing them forces a re-sync without reinstalling anything. Both
locations are worth clearing because which one holds state depends on how far
it got:

```bash
P=~/.local/share/battlenet-umu/prefixes/yuzu
rm -rf "$P"/drive_c/ProgramData/Battle.net/Agent \
       "$P"/drive_c/ProgramData/Battle.net/Cache \
       "$P"/drive_c/users/*/AppData/Local/Battle.net
battlenet-umu-yuzu-battlenet
```

**(d) Rebuild the prefix.** The guaranteed fix, and often faster than debugging.

```bash
# 1. Nothing may be holding it open.
wineserver -k 2>/dev/null || true
pgrep -af 'Battle.net|wine'

# 2. Move it aside rather than deleting — reversible, and you keep the
#    evidence if this happens again.
OLD=~/.local/share/battlenet-umu/prefixes/yuzu
mv "$OLD" "$OLD.broken-$(date +%F)"

# 3. Rebuild (re-downloads Battle.net; D4 comes back via Battle.net).
battlenet-umu-install-yuzu
```

Only once Battle.net and D4 work in the fresh prefix:

```bash
rm -rf ~/.local/share/battlenet-umu/prefixes/yuzu.broken-*
```

If the *rebuild* also fails, the prefix is not the problem — go back to triage
step 2 and look at the host's graphics stack, or step 3 at the Proton version.

### Making the rebuild cheap: the spare prefix

The reason a second prefix is worth its disk: if `yuzu` breaks at a bad moment,
the recovery is "switch to the other one", not "wait for a 100 GB download".

```nix
# hosts/yuzu/capabilities.nix
my.gamingWinePrefixes = [ "yuzu" "spare" ];
```

```bash
just switch
battlenet-umu-install-spare     # install + install D4 once, while nothing is wrong
```

It costs nothing until installed into, and its launcher is
`battlenet-umu-spare-battlenet`. To switch over permanently, rename the
directories rather than reinstalling:

```bash
cd ~/.local/share/battlenet-umu/prefixes
wineserver -k
mv yuzu yuzu.broken && mv spare yuzu    # names, not contents, are what matter
```

…then `nix` resumes using `yuzu` as if nothing happened. This is also the
answer to "can I have two Battle.net accounts": two prefixes, two installs,
two launchers.

### What not to do

- **Don't `nix-collect-garbage` expecting to fix anything.** The prefix is not
  in the Nix store; garbage collection cannot touch it.
- **Don't delete `~/.local/share/umu/`.** That is umu's own state (the Steam
  runtimes and compatibility tools), not the game prefix. Deleting it forces a
  runtime re-download and changes nothing about Battle.net.
- **Don't run these wrappers with `sudo`.** The prefix is owned by your user,
  and a root-owned prefix is the one corruption Nix cannot repair.
- **Don't put a prefix on a network share or a case-insensitive FS mount.**
  Wine's registry and D4's patching both break on them.

## Where things are

| What | Where |
|---|---|
| The module | `modules/features/gaming.nix` |
| The switches | `hosts/yuzu/capabilities.nix` (`my.gaming`, `my.gamingWinePrefixes`) |
| Option declarations | `lib/my-options-module.nix` (`my.gamingWinePrefixes`); `programs.gaming-umu.winePrefixes` in the module |
| Wine prefixes | `~/.local/share/battlenet-umu/prefixes/<name>/` |
| umu's own state | `~/.local/share/umu/` (runtimes), `~/.cache/umu/` (download staging) |
| Launchers | `<hm-profile>/bin/battlenet-umu-<name>-<game>` |
| Desktop entries | `<hm-profile>/share/applications/battlenet-umu-<name>-<game>.desktop` |

Nothing under `~/.local/share/battlenet-umu/` is tracked by Nix, backed up by
anything, or reproducible from this repo. Treat it as a cache: disposable,
rebuildable, and not worth preserving.
