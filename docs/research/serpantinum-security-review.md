# Security Review: Serpantinum Wayland Desktop Shell

**Repository:** https://github.com/ilyamiro/serpantinum
**Pinned rev:** `86c3ee2f715c7f260ac000f44eac1529b64dd95e` (v2.2.12, branch `master`)
**Review date:** 2026-02
**Scope:** Security only. Formatting, style, architecture, naming, test coverage, docs quality and general code smells were explicitly excluded.

## Method

Full file tree enumerated via `GET /repos/ilyamiro/serpantinum/git/trees/86c3ee2...?recursive=1` (770 blobs, `truncated: false`). All 456 non-binary, non-asset files (excluding `src/assets/fonts|sounds|themes|languages|shaders` and `website/`) were fetched from `raw.githubusercontent.com` at the exact pinned rev. Every `*.sh`, `*.py`, `*.qml`, `*.js`, `*.nix`, PKGBUILD and installer module was read or grepped. 71 files initially failed to fetch in parallel and were re-fetched serially to completion; a `comm` diff against the manifest confirms a complete tree.

---

## Verdict

**Safe to run as a daily desktop shell, with caveats — and not free of genuine privacy compromises.** I found **no malware, no backdoor, no obfuscated payload, no remote code execution, and no credential theft**. There is no `base64 -d | sh`, no `eval` of network data, no read of `~/.ssh`/`~/.gnupg`/`~/.aws`/browser cookie stores, no keyring access, no rc-file or autostart tampering by the running shell. However, three things matter for a privacy-conscious user: (1) the **installer** ships undisclosed-in-README anonymous telemetry that POSTs a stable UUID plus OS/kernel/CPU/GPU/RAM/session details to the author's Cloudflare Worker, defaulting to **on**; (2) the **GitHub contributions widget falls back to your local `$USER`** and sends it to a third-party API (`github-contributions-api.jogruber.de`); and (3) the shell **maintains a persistent SQLite database of every application you use, with window titles**, plus a full clipboard history via `cliphist` — all local-only, never transmitted, but a real forensic artifact. The installer's `About → Update` button and `install/get.sh` are `curl | bash` from `master` (unpinned) executed with whatever privileges the installer needs (sudo for packages, SDDM, PAM). The command-injection sinks that do exist (`bash -c` string concatenation in ~50 places) are reachable only from locally-sourced, non-attacker-controlled values — this is unsafe-by-construction code, not an exploitable vulnerability in the shipped configuration. **My recommendation: fine to run; set `ENABLE_TELEMETRY=false` in `~/.local/state/serpantinum/version` before/after install, and decide deliberately whether the window-title database and clipboard history are acceptable on your machine.**

---

## Outbound network destinations

Every hardcoded network destination in executable code at the pinned rev (`src/`, `bin/`, `nix/`, `install/`, PKGBUILDs):

| Destination | Purpose | Data sent | Documented? |
|---|---|---|---|
| `https://dots-telemetry.ilyamiro-work.workers.dev` | Installer telemetry (POST) | **Stable UUID**, version, old version, install state, compositor(s), failed packages, OS, kernel, RAM, desktop env, **CPU model**, **GPU model**, arch, session type | **No** — absent from README and docs; only mentioned in a CHANGELOG line and an aside in `installation.md` |
| `https://ipapi.co/json/` | IP geolocation (primary) | Nothing but the request itself (your IP is the datum) | No |
| `http://ip-api.com/json/` | IP geolocation (fallback 1) | Same; **plaintext HTTP** | No |
| `https://ipwho.is/` | IP geolocation (fallback 2) | Same | No |
| `https://api.open-meteo.com/v1/forecast` | Weather | Lat/lon (from IP geolocation) | Expected |
| `https://api.bigdatacloud.net/data/reverse-geocode-client` | Reverse geocode of manual coords | Lat/lon you typed | Expected |
| `https://github-contributions-api.jogruber.de/v4/<user>` | GitHub contribution graph widget | **GitHub username** — falls back to local `$USER` | No |
| `https://lrclib.net/api/{get,search}` | Lyrics lookup | Track title, artist, duration | Expected |
| `https://music.163.com/api/...` | NetEase lyrics lookup (3 endpoints) | Track title + artist | Expected (undocumented third party) |
| `https://duckduckgo.com/` + `/i.js` | Wallpaper image search | Your search query | Expected |
| `https://i.ytimg.com/vi/<id>/...` | YouTube thumbnail upscale | Video ID from local MPRIS | Expected |
| `$RAW_URL` from MPRIS `trackArtUrl` | Album art fetch | Follows whatever the player supplies | Expected |
| `https://raw.githubusercontent.com/<slug>/master/version.txt` | Update check | Nothing (GET) | Expected |
| `https://raw.githubusercontent.com/<slug>/<branch>/install/install.sh` | **`curl \| bash` installer** | Nothing (GET), but **executes the response** | Documented as the install method |
| `https://api.github.com/repos/<slug>/commits/HEAD` | Installer version display | Nothing | Expected |
| `https://github.com/<slug>.git` | Installer `git clone` | Nothing | Expected |
| `https://aur.archlinux.org/yay-bin.git` | yay bootstrap (pacman path only) | Nothing | Expected |
| `https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Iosevka.zip` | Font download | Nothing | Expected |
| `https://repos.fyralabs.com/terra...` | Fedora COPR repo (**`--nogpgcheck`**) | Nothing | Partly (see F-9) |
| `http://nmcheck.gnome.org/check_network_status.txt` | Captive-portal detection; only opened via `xdg-open` on user click | Nothing | Expected |
| `https://<wallpaper_repo>` (installer arg) | Optional wallpaper pack clone | Nothing | Expected |

Nothing else. There is **no** `pip install`, `npm install`, `cargo`, `git clone` or package fetch at shell *runtime* — only in the installer. The Nix build (`nix/package.nix`) downloads nothing beyond nixpkgs inputs; `flake.nix` has exactly two inputs (`nixpkgs`, `serpantinum-wallpapers` as `flake = false`, i.e. a plain source tarball) and **no** fixed-output derivations, `fetchFromGitHub`, `fetchNpmDeps`, `cargoHash` or `pip` FOD.

---

## Findings, ranked

### F-1 — HIGH (privacy, "expected behaviour worth knowing" — but undisclosed): Installer telemetry with stable persistent identifier

`install/modules/telemetry.sh:3`, `:146`

```bash
WORKER_URL="https://dots-telemetry.ilyamiro-work.workers.dev"
...
curl -X POST -H "Content-Type: application/json" -d "$payload" "$WORKER_URL" -s -o /dev/null &
```

`install/modules/version.sh:28-50` derives `TELEMETRY_ID` from `uuidgen`, `/proc/sys/kernel/random/uuid`, or **`/etc/machine-id`**, persists it in `~/.local/state/serpantinum/version` as `TELEMETRY_ID=`, and reuses it on every subsequent install/update. `telemetry.sh:105-125` payload:

```json
{"type":"done","version":...,"old_version":...,"install_state":...,"compositor":...,
 "id":"<stable uuid>","telemetry_enabled":true,"failed_packages":...,
 "os":...,"kernel":...,"ram":...,"de":...,"cpu":...,"gpu":...,"arch":...,"session":...}
```

CPU/GPU model strings are quite identifying (e.g. a specific mainboard + GPU combination). There is no data-retention or privacy statement anywhere in the repo, and README never mentions telemetry. **Not malicious — it is a deliberate, coded, opt-out analytics feature.** But it is a **stable cross-install identifier** plus hardware fingerprint, sent silently at install time.

Mitigations present: default can be flipped to `false` via `ENABLE_TELEMETRY=false` in `~/.local/state/serpantinum/version`; when disabled, `sys`, `compositor`, hardware and arch are withheld (`telemetry.sh:127-140`); Fedora exits early (`telemetry.sh:75-77`); AUR package installs write `package-managed` and thus send none.

**For our config:** we install via Home Manager / NixOS modules, not the installer, so this path is not executed. If anyone ever runs `install/get.sh`, set `ENABLE_TELEMETRY=false` first.

### F-2 — HIGH (privacy, "expected behaviour worth knowing"): Persistent local database of every application + window titles

`src/quickshell/guide/wellbeing/focus_daemon.py:32-34,81-88,111-128`

```python
DB_DIR = os.environ.get("QS_STATE_FOCUSTIME", os.path.expanduser("~/.local/state/quickshell/focustime"))
DB_PATH = os.path.join(DB_DIR, "focustime.db")
...
c.execute('''CREATE TABLE IF NOT EXISTS focus_log (log_date TEXT, app_class TEXT, seconds INTEGER, app_title TEXT, PRIMARY KEY (log_date, app_class))''')
```

`resolve_app_name()` (line 77-85) reduces the raw window title to its last `-`/`—`/`|`-separated segment, then `flush()` (line 296) does `INSERT ... app_title = ?`. Tables `focus_log`, `focus_hourly`, `focus_intervals`, `focus_minutes` record per-app, per-minute, per-15-min and per-hour usage forever (no retention pruning anywhere in the file). A snapshot is also written to `$XDG_RUNTIME_DIR/serpantinum/focustime/focustime_state.json`.

**Answering the specific question in the brief:** yes, it collects app usage, window titles and timestamps; it stores them locally in SQLite under `~/.local/state/quickshell/focustime/focustime.db` plus a JSON state file in the runtime dir; and **it does not send them anywhere** — there is no socket, HTTP client, or URL in the file other than a local `AF_UNIX` connection to Hyprland's compositor IPC socket (`focus_daemon.py:214`). `get_stats.py` is read-only over the same DB.

Related, similar: `src/quickshell/launcher/app_rank.py` keeps a 60-day rolling per-app launch count in `launch_stats.json`. `src/scripts/current_focus.sh` writes window class+title pairs as JSONL to `$XDG_RUNTIME_DIR/serpantinum/focustime/focus_events.jsonl`, trimmed to 200 lines at startup and every 100 events — **tmpfs, so transient**. That is the better design; the SQLite DB is the durable one.

Clipboard: `cliphist` is started at compositor autostart (`compositors/niri/config/autostart.kdl:1-2`, `hyprland/config/autostart.lua:2-3`) and stores full clipboard history, including images (decoded to PNG cache by `clip_fetcher.py:57-66`). This is standard for a clipboard manager but means your clipboard history is on disk. `clip_fetcher.py` never transmits anything.

**Not malicious. Significant forensic surface. Document it, or disable wellbeing + cliphist if unacceptable.**

### F-3 — MEDIUM (`unsafe but not malicious`): GitHub widget sends local username to a third-party API when unconfigured

`src/quickshell/widgets/faces/github/GithubFace.qml:405-407` and `:292`

```javascript
if (u !== "") { root.loadUser(u, false); }
else if (typeof SystemInfo !== "undefined" && SystemInfo.username !== "") { root.loadUser(SystemInfo.username, false); }
...
let url = "https://github-contributions-api.jogruber.de/v4/" + encodeURIComponent(cleanUser) + "?" + queryParam;
```

`SystemInfo.qml:10` is `Quickshell.env("USER") || Quickshell.env("LOGNAME") || "user"`. So if you add the GitHub widget without ever typing a username, **your Linux login name is sent to a random third-party service** (jogruber.de — a hobby Heroku app, not GitHub). This is a genuine, non-obvious information leak, not an exploit. Also note `jogruber.de` was a request to GitHub's own contribution data, so the operator sees your account → IP mapping.

### F-4 — MEDIUM (`unsafe but not malicious`): Geolocation defaults to third-party IP lookup with no consent gate, including plaintext HTTP

`src/scripts/location.sh:44,72,100`

```bash
resp="$(curl -s --max-time 5 -H "User-Agent: serpantinum-location/1.0" "https://ipapi.co/json/" ...)"
resp="$(curl -s --max-time 5 "http://ip-api.com/json/?fields=..." ...)"   # HTTP
resp="$(curl -s --max-time 5 "https://ipwho.is/" ...)"
```

`weather.sh:88-96` calls `location.sh` implicitly when no location is set, and `weather.sh` is invoked from the bar widget and `serpantinum weather`. So the weather widget silently discloses your IP to one of three geolocation providers on first use, and the coordinates are then persisted in `settings.json`. The **plaintext HTTP** leg (`ip-api.com`) is tamperable on-path, though the parser is `jq`-based and not code-executing (see F-8). Documented only implicitly. Not malicious; a privacy trade-off the user should know about.

### F-5 — MEDIUM (`unsafe but not malicious`): Installer update path is unpinned `curl | bash` from `master`

`src/quickshell/guide/AboutTab.qml:206-207`

```javascript
let cmd = "if command -v kitty >/dev/null 2>&1; then kitty --hold bash -c 'eval \"$(curl -fsSL https://raw.githubusercontent.com/ilyamiro/serpantinum/master/install/install.sh)\"'; else ${TERM:-xterm} -hold -e bash -c 'eval \"$(curl -fsSL https://raw.githubusercontent.com/ilyamiro/serpantinum/master/install/install.sh)\"'; fi";
Quickshell.execDetached(["bash", "-c", cmd]);
```

and `install/get.sh:10` does the same from `SERPANTINUM_BRANCH` (default `master`). This is the standard, documented install/update mechanism for this project — **but** it fetches and executes whatever is at `master` *at click time*, with no signature, no checksum, no tag pin, no review window. A compromised GitHub account or a malicious force-push to `master` becomes code execution for every user who clicks Update. The update *checker* itself is harmless (`updater.py` only reads `version.txt` and never executes anything), so the notification is safe — the danger is only the human clicking through to the installer. Conventionally running a shell installer is a known trust decision, not a vulnerability in the code. Worth pinning/avoiding in our config; the AUR PKGBUILD does the right thing by pinning a tag tarball with a sha256.

### F-6 — MEDIUM (`unsafe but not malicious`): ~50 `bash -c` command strings built by concatenation

Representative instances:

```javascript
// src/quickshell/clipboard/Clipboard.qml:390
Quickshell.execDetached(["bash", "-c", "cliphist decode " + id + " | wl-copy && (... awk '{print $1}'); python3 " + Caching.qsDir + "/clipboard/clip_fetcher.py pin $NEW_ID " + Caching.getCacheDir("clipboard") + ") &"]);
// src/quickshell/guide/display/DisplayMainState.qml:387-389
Quickshell.execDetached(["bash", "-c", "niri msg output " + monName + " on"]);
Quickshell.execDetached(["bash", "-c", "swaymsg output " + monName + " (enable|disable)"]);
// :405  hyprctl eval '<lua built by string concat>'
// src/quickshell/screenshot/ScreenshotOverlay.qml:77  "rm -f " + img     (unquoted, 8 sites)
// src/quickshell/singletons/system/WindowTracker.qml:449,465,547-571  addr/nid/ws from compositor
// src/quickshell/singletons/audio/Sounds.qml:58-59  sound file path, single-quote escaped
```

Dozens more in `SysNotif.qml:76`, `Launcher.qml:56,1016,1025`, `Matugen.qml:296-298`, `GuidePopup.qml:928`, `Config.qml:63,200`, `NetworkPopup.qml:611`, and the `Theme*`/`Display*` guide files (these use a local `escapeBash` that escapes `"`, `\`, `$`, `` ` `` — correct for double-quoted context).

**Assessment: unsafe by construction, not currently exploitable.** I traced every interpolation to its source: `id` is a numeric cliphist index (`\d+\t` from `cliphist list`); `monName`/`modeStr`/`scaleVal` come from compositor monitor enumeration and UI sliders; `addr`/`nid`/`ws` are compositor-supplied window IDs/addresses; `img`/`filePath` are self-generated cache paths; `ws`/`titles` in WindowTracker are compositor state. None is attacker-controllable in the shipped configuration. **No MPRIS title, no notification body, no weather/JSON response, and no network SSID reaches any `bash -c` string.** (SSID/password go through Quickshell's native `NetworkManager` API — `NetworkPopup.qml:707-760` calls `targetNet.connectWithPsk(password)`; MPRIS metadata is only ever displayed or passed as list-args to `art_fetch.sh`, which quotes it.) If a future commit routes a window title, notification text, or network-derived string into one of these, it becomes exploitable immediately — see the watch list.

Counter-examples done right, for contrast: `Launcher.qml:998-1016` passes the file path as `"$1"` positional arg; `Config.qml:200` passes the payload as `"$2"`; `GithubFace.qml` uses `--` and `"$1"`. So the codebase knows the safe pattern — it just doesn't use it uniformly.

### F-7 — LOW (`unsafe but not malicious`): Launcher `>` deliberately executes arbitrary shell

`src/quickshell/launcher/Launcher.qml:868-880,1021-1026`

```javascript
if (rawTrimmed.startsWith(">")) { let cmd = rawTrimmed.substring(1).trim(); ... isCommand: true, command: cmd ...
...
Quickshell.execDetached(["bash", "-c", fullCmd]);
```

A documented-by-behaviour "run command" mode. This is intended functionality (like `dmenu_run`), and it runs as your user, from your own keyboard. Listed only so it's a conscious risk acceptance — any process that can open the launcher and type can run shell commands.

### F-8 — LOW: `jq` pipelines over remote JSON (no injection found)

The riskiest-looking site is `weather.sh:190-330`: a large `jq_filter` string is applied to the raw Open-Meteo response via `echo "$raw_api" | jq ... "$jq_filter"`. This is **safe**: the filter is a compile-time constant in the script, all interpolated values (`lat`, `lon`, `loc_ts`, `unit`, `unit_sym`, `is_kelvin`, `dates`, `i18n`) are passed as `--arg`/`--argjson` parameters, never spliced into the filter text, and the filter contains no `env`, `$ENV`, `input_filename`, `system`, or `@sh`. Same pattern in `location.sh` (all `--arg`), `location_manual.sh`, `i18n.sh` (`getpath($path)` with `--arg k`), `bluetooth_panel_logic.sh` (a constant pipeline over `pactl` output), and `current_focus.sh` (constant jq over compositor JSON). **No `jq` injection, no `awk`/`bc` fed remote strings.**

### F-9 — LOW: `--nogpgcheck` on a third-party Fedora COPR repo

`install/modules/pm/dnf.sh:180`

```bash
sudo dnf install -y --nogpgcheck --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' terra-release
```

Installing an entire package repo without signature verification, as root. Fedora-only path; not applicable to our NixOS/lumquat config. Genuine supply-chain weakening.

### F-10 — LOW: overly broad `pkill -f` patterns

`bin/serpantinum:210,216,223,225` and `bin/serpantinumd:171,175,182,186,235,237,241`

```bash
pkill -TERM -f "focus_daemon.py"
pkill -KILL  -f "focus_daemon.py"
pkill -TERM  -f "quickshell.*$MAIN_QML"
pkill -TERM  -f "serpantinumd"
```

`pkill -f focus_daemon.py` will kill *any* matching process including one belonging to another user in the same PID namespace (impossible on a normal desktop, relevant in shared containers), and `pkill -f serpantinumd` is a substring match. `-f "quickshell.*$MAIN_QML"` is the most concerning — it will match any process whose full command line contains `quickshell`, any characters, then your QML path. Scoped to the user's own UID by default (`pkill` without `-u` matches any user for signals the caller is permitted to send), so on a single-user desktop the practical blast radius is limited to the user's own quickshell instances — which is the intent. Not exploitable; note that these run on every `serpantinum kill` and daemon restart.

Also: `Matugen.qml:296-298` runs `killall -USR1 .kitty-wrapped || pkill -SIGUSR1 kitty` — `killall`/`pkill` without `-u`, so it signals any user's kitty.

### F-11 — LOW: `focus_daemon.py` lock file leaked to child processes and predictable `/tmp`

`src/quickshell/guide/wellbeing/focus_daemon.py:19-28`

```python
RUN_DIR = os.environ.get("QS_RUN_FOCUSTIME", "/tmp/quickshell/focustime")
os.makedirs(RUN_DIR, exist_ok=True)
LOCK_PATH = os.path.join(RUN_DIR, "focus_daemon.lock")
lock_fd = open(LOCK_PATH, "w")
```

Two issues, neither exploitable in the default config:

1. **`/tmp` fallback + predictable name.** With `QS_RUN_FOCUSTIME` unset *and* `XDG_RUNTIME_DIR` unset, `RUN_DIR` is the world-writable `/tmp/quickshell/focustime`. `os.makedirs` does not fail if another user pre-created it, and `open(..., "w")` follows symlinks — a local attacker on a multi-user box could pre-create that directory/symlink and truncate or redirect a file writable by the victim. In practice `caching.sh` always exports `QS_RUN_FOCUSTIME` under `$XDG_RUNTIME_DIR` (per-user, `0700`), and `launch_daemon.sh` sources `caching.sh` first, so the fallback is dead code in normal operation. Mitigated by deployment, not by code.
2. **`lock_fd` is opened without `O_CLOEXEC`** and never closed, so it is inherited by every child (`hyprctl`, `notify-send`, `niri msg`, …). Since the lock is an advisory `flock`, inheritance means a long-lived child could hold the lock and prevent a clean restart. Availability nit, not a security one.

### F-12 — INFORMATIONAL: `security.pam.services.serpantinum = { }` + `/etc/pam.d/serpantinum`

`nix/nixos-module.nix:19` and `packaging/aur/serpantinum/PKGBUILD:52-56`

```nix
security.pam.services.serpantinum = { };
```
```
-auth       sufficient   pam_fprintd.so
auth        include      system-auth
account     include      system-auth
```

This is the **correct, standard** way to give a lock screen a PAM service: it includes the distro's `system-auth`/`login` stack rather than inventing one, so it inherits password, fingerprint, faillock and account policy. It does **not** alter authentication for anything else, does not add `nullok`, `sufficient pam_permit.so`, or `@include common-auth` weakening. `install/modules/deploy.sh:305-334` generates the same content and skips entirely on NixOS (`[ -e /etc/NIXOS ] && return 0`). Purely declarative service definition — **no PAM manipulation beyond declaring a service.** The `sufficient pam_fprintd.so` prefix is added only if the distro base stack lacks it, which is a mild ordering choice (fingerprint short-circuits password) but matches distro convention.

### F-13 — INFORMATIONAL: Polkit agent is a normal, correct `PolkitAgent`

`src/quickshell/polkit/PolkitService.qml` instantiates Quickshell's `PolkitAgent` and forwards the response to `agent.flow.submit(response)`. This *is* a polkit authentication agent — it mediates privilege escalation prompts for the whole session. No pkexec wrapper, no sudo invocation, no policy files are shipped, and no password is retained. Correct implementation. Worth knowing because a compromised shell = a compromised polkit agent (it can lie about which action it is prompting for), which is inherent to any desktop polkit agent.

---

## Categories where I found nothing

To be explicit rather than padding:

- **Credential/secret access: none.** No reads of `~/.ssh`, `~/.gnupg`, `~/.aws`, `~/.config/gh`, `.netrc`, browser profiles/`Cookies`/`Login Data`, keyrings, or `/etc/shadow`. No environment variable containing a token is read, logged or transmitted. `Quickshell.env` is used for `HOME`, `USER`, `LOGNAME`, `XDG_*`, `HYPRLAND_INSTANCE_SIGNATURE`, `NIRI_SOCKET`, `SWAYSOCK`, `MANGO_INSTANCE_SIGNATURE`, `LANGUAGE`/`LANG` — all benign. Clipboard *contents* are never logged or sent; the only clipboard writes are `wl-copy` of a launcher calc result, an emoji, a screenshot QR text, and `settings.json` (a user-initiated "copy settings" button).
- **Obfuscation: none.** The only `base64` in the tree is `WidgetLoader.qml:100-112,165`, a hand-written JS base64 *encoder* used to pass `layout.json` through a shell argument safely (`printf '%s' '<b64>' | base64 -d > file`). No decoder-and-execute, no hex blobs, no minified code, no encoded strings.
- **Destructive operations:** no `dd`, no `mkfs`, no writes to block devices, no `/dev` writes. `rm -rf` sites are `install/install.sh:30` (`$CACHE_BASE`, derived from `XDG_CACHE_HOME`, guarded by a directory test), `install/get.sh:9` (`mktemp -d` in a trap), `deploy.sh:216-218` and `:362` (`$TARGET_BASE` = `$HOME/.local/share/serpantinum`), `pm/pacman.sh:21-25`, `deps.sh:131`, `deploy.sh:73` — all fixed or well-guarded paths. The unquoted `rm -f <var>` sites in QML (`ScreenshotOverlay.qml` ×8) take self-generated cache paths. No `rm -rf "$VAR"` with a possibly-empty variable.
- **`shell=True` / `os.system` in Python: none.** Every `subprocess.*` call across all seven Python files uses list form (`indexer.py:81,109,122`, `focus_daemon.py` throughout, `clip_fetcher.py`). No string commands.
- **MD5/SHA use:** `art_fetch.sh:38-46` and `theme_sorter.py` use `md5sum`/`hashlib.md5` for cache keys only — not for integrity or authentication.
- **Supply chain at runtime:** the running shell invokes only the ~45 PATH binaries you already enumerated (declared as `pathDeps` in `nix/package.nix:65-113` and as `depends` in the PKGBUILDs). No runtime package manager, no plugin fetcher, no downloaded extensions. All QML is loaded from the installed tree (`src/quickshell/**` via `qmldir` registries); `WidgetRegistry`/`WidgetLoader` load from a fixed set of built-in widget types, and there is **no plugin/extension loading from a URL or arbitrary path**.

---

## What to watch on updates

Ranked by "a malicious commit would most plausibly hide here":

1. **`install/modules/telemetry.sh`** — already the one place that ships user data off-box. Any change to `WORKER_URL`, to the field list in `payload=`, or new `curl` calls. Also `install/modules/version.sh:28-50` (how `TELEMETRY_ID` is derived — a change to read more of `/etc/machine-id`, MAC addresses, or DMI would be a fingerprinting escalation) and `install/modules/ui.sh:508` (whether telemetry is on by default).
2. **`src/quickshell/widgets/faces/github/GithubFace.qml:285-401`** — already sends a locally-derived value (`$USER`) to a third party. A one-line change to append hostname or another identifier is invisible at a glance, and the URL is an unremarkable hobby domain nobody would re-inspect.
3. **`src/scripts/location.sh` / `location_manual.sh` / `weather.sh`** — already exfiltrate geolocation. Watch for new fields added to the outbound URL query, a new provider, or a switch from `/json/?fields=` to a POST.
4. **`src/quickshell/singletons/audio/Lyrics.qml:704-780, 820-910`** — three NetEase + two Lrclib endpoints. Song title/artist is already sent; a change appending `SystemInfo.username` or a device ID, or a new `xhr.open("POST", ...)`, is the most plausible "AI feature" style cover.
5. **`src/scripts/updater.py`** — currently read-only and harmless. Any addition of `subprocess`, `os.system`, `exec`, or a write outside `state_dir` turns the update *check* into an update *installer*.
6. **`src/quickshell/guide/AboutTab.qml:206`** — the unpinned `curl | bash`. Watch for the URL host changing (typosquat: `raw.githubusercontent.com` → a lookalike), or for `master` being replaced with a user-controlled variable.
7. **The ~50 `bash -c` concatenation sites** (`Clipboard.qml:390`, `WindowTracker.qml:449/465/547-571`, `DisplayMainState.qml:387-389/405-424`, `Launcher.qml:1016/1025`, `SysNotif.qml:76`, `GuidePopup.qml:928`, `NetworkPopup.qml:611`, `Sounds.qml:58`, `Matugen.qml:296-298`). The specific tripwire: **any of these gaining an interpolation of a window title, notification `body`/`summary`, MPRIS field, network SSID, weather/i18n string, or any network response.** Each of those strings currently reaches only display code or `--arg`/positional-arg paths.
8. **`src/quickshell/clipboard/clip_fetcher.py`** — the one file that legitimately reads the entire clipboard history. Any new `import` of `urllib.request`/`socket`/`requests` (today it imports `urllib.parse` only, for `unquote`), any new `stdout` writing of `content`, or any write outside `cache_dir`.
9. **`src/quickshell/guide/wellbeing/focus_daemon.py`** — same logic: today the only network is a local `AF_UNIX` socket to Hyprland IPC. A new outbound socket, a new table containing more of the raw title, or `DB_DIR` moved off the user's state dir.
10. **`src/scripts/current_focus.sh`** — window titles → JSONL. Watch for a change of `RUN_DIR`/`LOG_FILE` from `$XDG_RUNTIME_DIR` (tmpfs) to a persistent path, or an increase of the 200-line trim.
11. **`flake.nix` / `nix/package.nix`** — today: two inputs, one `flake = false`, zero FODs. A new `fetchFromGitHub`, `fetchurl`, `fetchNpmDeps`, `cargoHash`, `pip install`, or `postBuild`/`patchPhase` would be the supply-chain insertion point. Also watch `pathDeps` for a new binary.
12. **`install/modules/pm/dnf.sh:180`** `--nogpgcheck`, and `packaging/aur/*/PKGBUILD` `sha256sums` — a wrong hash or a `source=` pointing at `master`/a branch instead of a tag.

---

## What I could NOT verify

- **Runtime network behaviour.** This is a static read of the pinned tree. I did not execute the shell, so I cannot prove no request is made by a transitive dependency (Quickshell itself, `quickshell-git`, Qt6 `qtwebsockets`, `matugen`, or the ~45 PATH binaries). The flags `python-websockets`, `qt6-websockets` and `python-jeepney` are declared as dependencies and imported nowhere in this repo's own code — they may be for Quickshell's own IPC/DBus, but I only verified that *Serpantinum's* code does not open a WebSocket.
- **The build outputs.** I did not build the flake nor inspect the resulting store paths, so I cannot confirm the compiled `.qsb` shader binaries in `src/assets/shaders/**` correspond to the checked-in `.frag` sources. Those are binary blobs; a malicious shader is a far-fetched but unexamined vector, and shaders here are only visual effects invoked with simple uniforms.
- **Quickshell upstream.** The behaviour of `Quickshell.execDetached`, `Quickshell.Services.Pam`, `Quickshell.Services.Polkit`, `DesktopEntries`, `Quickshell.env` and `FileView` is taken as documented-by-usage. If Quickshell itself is compromised, most guarantees above are moot.
- **The Cloudflare Worker backend.** I cannot see what `dots-telemetry.ilyamiro-work.workers.dev` does with the payload, whether it logs IPs, or its retention. I did not send a request to it (deliberately — that would be emitting the very telemetry I'm auditing).
- **Server-side endpoints** — `jogruber.de`, `ipapi.co`, `ipwho.is`, `ip-api.com`, `lrclib.net`, `music.163.com`, `open-meteo.com`: their privacy practices are out of scope; I only established what Serpantinum sends them.
- **`git` history / intent.** I reviewed one commit, not the history. I cannot say whether any past version contained something worse, nor whether the shipped binary release artifacts (if any) match this source. There are no release binaries in the tree — installation is from source.
- **`docs/` and `website/`** were excluded from the code assessment per the "documentation quality out of scope" instruction, beyond grepping them for telemetry disclosures (found none in README; one CHANGELOG line and one aside in `docs/installation/installation.md:96`).
- **The Fedora, dinit/runit/s6/OpenRC installer branches** were read but not executed; the NixOS and systemd paths are the ones relevant to lumquat.

---

## Bottom line for our config

We install via `nix/home-manager` + `nix/nixos-module.nix`, so:

- **The installer, and therefore all installer telemetry (F-1) and all `curl | bash` (F-5), never runs.** Good.
- The `nixos-module.nix` enables `networkmanager`, `bluetooth`, `i2c`, `power-profiles-daemon`, `rtkit`, `pipewire` and declares `security.pam.services.serpantinum` — all `mkDefault`, all standard, no surprises.
- Remaining live concerns are the **runtime** ones: the window-title database (F-2), clipboard history (F-2), the GitHub-widget username leak (F-3), and IP geolocation on first weather fetch (F-4). These are all disable-able via the settings file (`general`, `wellbeing.*`, and simply not adding the GitHub widget); F-3 and F-4 are the two I would gate explicitly in `settings.json` rather than leave to a user clicking around the Guide.
- F-12 (PAM) is correct as-is and needs no change.

---

## Addenda — verified during implementation review

Three corrections/confirmations from re-checking the subagent report against the
pinned source at `86c3ee2`, recorded because two of them change the severity
picture and one changes what our config should do.

### A-1: the telemetry endpoint is absent from the packaged shell (F-1 downgraded for us)

`F-1` is real but is **installer-only**. `nix/package.nix:123-127` builds from

```nix
src = lib.fileset.toSource {
  root = ../.;
  fileset = lib.fileset.unions (
    map (p: ../. + "/${p}") [ "bin" "src" "config" "compositors" "version.txt" ]
  );
};
```

`install/` is not in that union, so `telemetry.sh`, `install.sh` and `get.sh` are
**not in the store path**. Verified two ways: `grep -rn 'workers.dev\|ilyamiro-work' bin src config compositors`
returns nothing, and the only `telemetry` string in the shipped assets is the
translation key `/installer/ui/menu_telemetry = "Anonymous telemetry"` — a menu
label for the installer that never runs under Nix. **The shell we run cannot
phone home.** F-1 stands as a criticism of their installer, not as risk to this
host.

### A-2: the telemetry UUID is random in practice, not machine-derived (F-1 refined)

`F-1` said the stable ID "may derive from `/etc/machine-id`". Read in full,
`install/modules/version.sh:38-49` tries in order: `uuidgen` →
`/proc/sys/kernel/random/uuid` → `/etc/machine-id` → `/dev/urandom`. The first
two are random and present on any normal Linux box, so machine-id is a
last-resort fallback. The identifier is still *stable across updates* (persisted
in `~/.local/state/serpantinum/version`), which is the privacy point — but it is
not a hardware fingerprint, and the report's phrasing overstates it.

### A-3: `focus_daemon.py` has no network capability at all (F-2 confirmed, tightened)

`F-2` called the window-title database "local only". Stronger than that: the
file's **only** `socket` use is

```python
client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
client.connect(sock_path)   # $XDG_RUNTIME_DIR/hypr/<sig>/.socket2.sock
```

an `AF_UNIX` connection to Hyprland's local IPC socket. No `urllib`, `requests`,
`http` or IP-socket constructor is imported anywhere in the file. F-2 is a real
forensic artifact (`~/.local/state/quickshell/focustime/focustime.db`, app +
window title, per-minute) and a legitimate privacy decision to make, but it is
not an exfiltration path.

### A-4: the `serpantinum-wallpapers` input is locked but never fetched

`serpantinum/flake.nix:7` makes `ilyamiro/shell-wallpapers` a mandatory input
(150MB, 149 images) and passes it to a module argument at `:57` that
`nix/hm-module.nix` accepts and then **ignores**. It therefore sits in
`flake.lock` with a `narHash` but is never realised — no `*shell-wallpapers*`
path exists in `/nix/store`. It cannot be dropped from the lockfile without
breaking resolution.

Consequence for this repo: keep it inert. Our `programs.serpantinum.settings`
sets no `wallpaperDir`, so the module's `mkDefault` applies
(`~/Pictures/Wallpapers`), which on yuzu is the Resilio-synced tree — the
operator's own archive, parallel to the dotfiles, rather than 150MB of upstream
images re-downloaded on every `nix flake update serpantinum`.
