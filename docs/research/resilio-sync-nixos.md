# Resilio Sync on NixOS: peer discovery, `known_hosts`, and the system-vs-user-service question

Research date: 2026-09-25. Context: `modules/features/resilio.nix` (host `yuzu`, x86_64-linux,
nixpkgs unstable ~2026-09, Resilio Sync 3.1.1.1075) runs the stock `services.resilio` module. The
daemon adopts the folder correctly (same `share_id`, valid 33-char secret, listens on TCP 4444,
inbound reachable) but opens **zero outbound TCP connections** and never discovers the mac peer
`bergamot` on a **different subnet** (10.40.0.240/24 vs 10.40.60.74/24). `bergamot` ↔ `miracle_max`
sync fine. Source list at the end; first-hand vs. inferred is called out inline.

**Headline verdict: the tracker/relay infrastructure is still alive and reachable in 2026, the
endpoints are hard-coded IPv4+IPv6 addresses in the 3.1.1 binary and mirrored in a live first-party
config file — so the fix is almost certainly `known_hosts` (with a fixed listening port on both
ends), not a rewrite into a user service.** The user-service question is orthogonal: it would
remove ACL gymnastics but would *not* by itself fix peer discovery, because the daemon already
makes outbound connections regardless of which user it runs as.

---

## 1. Peer-discovery mechanisms, and what is still up in 2026

### The four (really three) mechanisms

Resilio Sync 3.x uses, in order of attempt (source: binary string `SyncDiscovery`, the "Peers aren't
connecting" KB article, and the "What is a Relay Server" article):

1. **LAN broadcast/multicast discovery** — UDP multicast to port **3838** (`use_lan_broadcast`,
   shared-folder key `search_lan`). Only works within one broadcast domain — rendered inert here by
   the two-subnet topology.
2. **Tracker server** (`use_tracker`) — a rendezvous directory: peers announce their
   `ip:listening_port` to the tracker; other peers ask it for that list and then connect **directly**
   peer-to-peer. This is what normally bridges subnets/NAT.
3. **Relay server** (`use_relay_server`) — a data-relay fallback when a direct connection cannot be
   established ("Sophisticated NATs, firewalls, proxy servers"). Traffic flows *through* the relay.
4. **DHT** (`folder_defaults.use_dht`) — see §3; effectively vestigial in 3.x.

### The actual endpoints (first-hand, verified)

The tracker and relay **infrastructure is up and reachable** as of this date. The addresses are
hard-coded in the 3.1.1 binary and identical to what the live first-party config file serves:

| Role | IPv4 endpoint (from binary + live `sync.conf`) | IPv6 endpoint | Port reachability (tested here) |
|---|---|---|---|
| Tracker 1 | `23.111.157.86:4000` | `[2604:4500:5:245::10]:4000` | **4000/TCP OPEN** |
| Tracker 2 | `66.165.233.194:4000` | `[2604:4500:9:58::10]:4000` | **4000/TCP OPEN** |
| Relay 1 | `66.206.5.74:3000` | `[2604:4500:3:80::10]:3000` | **3000/TCP OPEN** |
| Relay 1b | `66.206.5.74:3001` | `[2604:4500:3:80::10]:3001` | 3001/TCP (same host) |
| Relay 2 | `66.165.255.194:3000` | `[2604:4500:8:24a::10]:3000` | **3000/TCP OPEN** |
| Relay 2b | `66.165.255.194:3001` | `[2604:4500:8:24a::10]:3001` | 3001/TCP (same host) |

Verified first-hand in this session by:
- `strings` over the 3.1.1 binary → embedded JSON blob
  `{ "trackers": [{"addr":"66.165.233.194:4000",...},{"addr":"23.111.157.86:4000",...}], "relays": [...] }`.
- `curl https://config.resilio.com/sync.conf` → returns exactly those two trackers and four relays
  (with their `addr6`), live.
- TCP connect tests (`/dev/tcp`) → both tracker `:4000` and relay `:3000` endpoints **open**.

So `tracker.btorrent.xyz` (BitTorrent Inc's, unrelated) and `relay.resilio.com` (NXDOMAIN in our
test) are **both red herrings**; neither is what the daemon actually uses. The real relay hostnames
are not DNS names at all in this version — the binary and config file carry **literal IPs**.

### How the daemon learns the tracker/relay list

The binary embeds the JSON blob above as a bootstrap, and also fetches a live copy over HTTPS from a
config-discovery host. Both are present in the string table:

- `https://%S/sync.conf` (the live fetch path)
- `config.resilio.com`, `config.getsync.com`, `config.usyncapp.com` (the `%S` candidates).

`config.resilio.com/sync.conf` and `config.getsync.com/sync.conf` both return the same JSON today
(verified). The older KB article ("Cannot connect to trackers") documents `config.usyncapp.com/sync.conf`
over **HTTP** as the historical discovery URL; 3.1.1 uses HTTPS. The KB maps the failure mode
explicitly: **"Cannot get the list of trackers" = the daemon cannot reach the config host**, and
**"No tracker Connection Available" = it reached config but cannot connect to the trackers
themselves**. Both imply outbound connectivity to the internet is the gating factor.

### Ports the daemon needs outbound (first-party, from the KB)

The KB ("ports and protocols", mirrored in "Cannot connect to trackers") says open **80, 443, 4000,
3000, 3001, 3838, 1900, 5351** plus the app's own listening port, for **both TCP and UDP**.
Breakdown, inferred by correlating the KB with the binary:

| Port | Role |
|---|---|
| 443 (and legacy 80) | fetch `config.resilio.com/sync.conf` |
| 4000 TCP/UDP | tracker |
| 3000/3001 TCP/UDP | relay |
| 3838 UDP | LAN multicast discovery (`search_lan`) |
| 1900 UDP / 5351 UDP | UPnP/SSDP (`use_upnp`) — this repo sets `useUpnp = false` |

**Inference worth flagging for the "zero outbound" symptom:** `ss`/`netstat -t` only shows TCP.
Tracker/relay/DHT/SSDP traffic is heavily UDP, and UDP "outbound" does not appear as an outbound TCP
connection. So "zero outbound TCP" does not by itself prove the daemon is doing nothing on the
network — but combined with "never discovers a peer" it does mean discovery is failing end-to-end.
The single most likely single-point explanation is that the config-host fetch (TCP 443) or the
tracker announce (UDP/TCP 4000) is being blocked or is not attempted, which collapses discovery to
LAN-only before any peer handshake ever begins.

---

## 2. `known_hosts` — the recommended fix for cross-subnet / no-internet peers

**Yes, `known_hosts` is the supported mechanism, and it is almost certainly the right fix here.**

### Exact syntax and semantics (first-party)

- The binary's own embedded config example documents it verbatim:

  ```
  "known_hosts" : // specify hosts to attempt connection without additional search
  [
    "192.168.1.2:44444"
  ]
  ```

- The "Power user preferences" KB article (`folder_defaults.known_hosts`, `str`, default "not set"):

  > Hosts should be entered as a single line of IP:port pairs (or DNSname:port pairs*)
  > comma-separated (no other delimiters allowed)

  with the footnote **`* DNS name is resolved by OS means once per minute.`**

- The binary's phrase "attempt connection **without additional search**" is the point: a peer listed
  here is dialed directly, bypassing tracker/relay/DHT entirely. It also exposes the field through
  the v2 API (`/api/v2/folders/{fid}/knownhosts`) and a `setknownhosts`/`use_known_hosts` internal
  toggle, plus `folder_defaults.known_hosts`, `service_folders.known_hosts` (scope variants).

### Does it take host:port, and does the port need to be fixed?

- **It takes `host:port`** (or `dnsname:port`), comma-separated, one line. No other delimiter is
  allowed (spaces are the separator between `folder_defaults` fields in the *preferences* section,
  but within a `known_hosts` *value* the list is comma-separated).
- **The port must be the peer's actual listening port.** The binary's own resolver (`KnownHosts::Host::Resolve`
  → `DnsRequest`) resolves the hostname but *not* a service/port; the port is dialed as-given. There
  is no port negotiation for a `known_hosts` entry.
- **A random (unset / `0`) listening port breaks `known_hosts`.** `listening_port` defaults to `0`
  ("0 - randomize port", from the binary's embedded comment), and the daemon reports its live value
  as `actual_bind_port` (binary string). If the peer is on a random port, there is no stable
  `host:port` to put in `known_hosts`, because the number changes each start and the port is not
  the default.
- **The port must be fixed on BOTH ends** for the *direct* connection to complete: the dialer needs
  the peer's stable port (to put in `known_hosts`), and the peer needs that port reachable (minimally
  inbound firewalled-open). The dialer's *own* port can be random and `known_hosts` still works
  outbound; only the **target** peer's port must be fixed and known. But for *bidirectional*
  reconnect and for the tracker to re-advertise, both ends should be fixed. `external_port` (int,
  default `0`) is the related knob: it advertises the NAT-relative port to the tracker so peers
  behind NAT announce a reachable port — irrelevant at this scale.

`services.resilio.sharedFolders.<n>.knownHosts` in nixpkgs is a `listOf str` and is passed straight
through, so `knownHosts = [ "10.40.60.74:4444" ];` (or the peer's fixed port) is the one-line change.

**Setting the port on macOS is a verified UX trap (first-hand, 2026-09-25).** The Resilio desktop app
gives you no Apply or OK button for the listening port — it is a bare text field in Preferences →
Advanced. Editing it and closing the window **discards the change**. The sequence that actually
sticks is: **pause the folder's sync, edit the port, quit the app, relaunch it.** Confirmed on
`bergamot`, which then reported `TCP *:4444` and `UDP *:4444` in `lsof` and had released the previous
random port (`46654`). Worth knowing before touching a second machine, because the failure is silent:
the field shows the new number either way, and nothing reports that it was dropped.
Note the repo's module currently hard-sets `knownHosts = [ ]` and mounts nothing else — that empty
list is the hole.

---

## 3. DHT (`use_dht`) — can it bridge peers on its own?

**Almost certainly not, and it is effectively vestigial in 3.1.1.** Findings:

- The only occurrence of `use_dht` in the binary is `folder_defaults.use_dht` — there is **no**
  `use_dht` field in the shared-folder example (which lists `use_relay_server`, `use_tracker`,
  `search_lan`, `use_sync_trash`, `overwrite_changes`, `selective_sync`, `known_hosts`). So
  `use_dht` is a *global default*, not a per-folder flag.
- There is **no DHT bootstrap hostname/port/node list anywhere in the binary** (only the obfuscated
  fragments `dht[$`, `*dHtJ`, `Dhtw`, `searchdht` — no address literals, unlike tracker/relay which
  carry full IP:port JSON). A DHT that cannot bootstrap cannot find peers.
- No first-party DHT article exists in the archived help center (CDX search returns nothing for
  "dht"), and the "Power user preferences" article from 2017 does not even list `use_dht` — it was
  added later as a config knob but never documented as an operational discovery path.

**Inference, not verified:** DHT in Resilio Sync appears to be a leftover from the BitTorrent-shared
codebase, present as a config flag but with no working bootstrap infrastructure shipped in 3.x. At
best it is a no-op; at worst enabling it adds latency. Do **not** rely on `use_dht` to connect two
peers — use `known_hosts` (or the tracker/relay, which *are* alive).

**A separate point, since disproved:** the first draft of this note claimed nixpkgs' `services.resilio`
maps `useDHT` onto a shared-folder-level `use_dht` key that the binary silently ignores. **That was
wrong, and it was tested directly.** The daemon performs strict key validation on `shared_folders`
entries — an invented key (`totally_made_up`, `use_dht_bogus`) makes it refuse to start with
`Invalid key '<name>'`, while the same folder object carrying `use_dht` starts cleanly (0 validation
errors vs. 3). So folder-level `use_dht` is a **recognised** key, and the nixpkgs mapping is sound. It
is also present as `folder_defaults.use_dht` (the global default), so the key exists at both levels.
Test configs: `/run/rslsync/dht_a.json` (with `use_dht`) vs `dht_b.json` (made-up key).

---

## 4. Known issues running Resilio as a system service (no outbound / no peers)

**No first-party or widely-reported bug was found that makes a system-service rslsync unable to open
*outbound* connections specifically.** The known failure modes are all about *inbound* reachability
and *filesystem* permissions, plus one ordering footgun in the nixpkgs module itself. What follows
is a mix of verified module facts and documented KB guidance; I could not reach the Resilio forum
directly (Cloudflare challenge on `forum.resilio.com`), so bullet points below that cite "forum"
are inference from the KB and module rather than a first-hand forum thread.

Checked, in order of your list:

- **Non-login system user, no home/DBus session** — **not a cause of outbound failure.** The daemon
  is a headless network process; it needs neither a login session, nor DBus, nor a home directory to
  dial outbound. (It *does* need a writable `storage_path` — see below.) This is the strongest
  argument that moving to a user service (§5) would *not* by itself fix peer discovery.

- **systemd sandboxing / `RestrictAddressFamilies` / capabilities** — **not the cause here, and not
  even present.** Both the stock nixpkgs module and this repo's `modules/features/resilio.nix` set
  no sandboxing at all. The nixpkgs module's `serviceConfig` is only `Restart=on-abort`,
  `UMask=0002`, `User=rslsync`, `RuntimeDirectory=rslsync`, `ExecStartPre`, `ExecStart`. Verified
  by grep: no `Restrict*`, `ProtectSystem`, `PrivateTmp`, `CapabilityBoundingSet`, `NoNewPrivileges`,
  `PrivateNetwork`, `ProtectHome`. So the daemon is *not* being sandboxed out of the network; it has
  unrestricted AF_INET/AF_INET6 and full capabilities as the `rslsync` user. If you add hardening
  later, `RestrictAddressFamilies=AF_INET AF_INET6` (keep both, or omit IPv6 deliberately) and a
  missing `AF_UNIX` for the storage path are the classic ways to reintroduce exactly this symptom.

- **Starts before DNS/network is ready** — **this is a real, verified footgun and the only ordering
  issue present.** The nixpkgs module sets `after = [ "network.target" ]` — **not**
  `network-online.target`, and no `wants`/`requires` on it. `network.target` is reached by systemd
  *before* interfaces are configured, before DHCP, and before DNS is resolvable. A daemon that starts
  there can (a) fail its initial `config.resilio.com/sync.conf` HTTPS fetch, (b) fail to resolve any
  future hostname (the config host, and any DNS `known_hosts`), and — because the tracker/relay
  bootstrap is otherwise static IPs — (c) still be left with "Cannot get the list of trackers".
  **The log line `16TcpSocketWrapper::set_error[-1] 1 (hostname not found)` is consistent with a
  DNS resolution that failed because the resolver was not usable yet, or because the hostname
  (`i-2000.b-3-1-1.sync.bench.resilio.com`, see below) genuinely does not exist.**

- **`sync.bench.resilio.com` / `i-2000.b-3-1-1.…` NXDOMAIN — red herring, confirmed.** The binary
  associates `sync.bench.resilio.com` with `send_statistics`, `benchid`/`benchId`, and a default
  `send_statistics = false`. The `i-2000.b-3-1-1` subdomain is the retired telemetry/benchmark
  endpoint (the naming pattern is an AWS ELB host label). NXDOMAIN on it is expected and harmless —
  it is **not** the tracker, relay, or DHT. It does, however, show the daemon was at least *attempting*
  one outbound DNS resolution, which reinforces the DNS-timing hypothesis rather than "the daemon
  never dials out".

**Other first-party causes from the "Peers aren't connecting" KB, ranked for *our* symptoms:**

1. Firewall blocking TCP/UDP **3000/3001** and **4000** (tracker+relay) outbound, and the listening
   port inbound — the #1 documented cause of "peers in a different network don't show up".
2. **Unable to reach `config.<host>/sync.conf`** — "check with wget/curl". This is the config-host
   fetch, and it is the #2 documented cause.
3. Duplicate peer identity from a migration tool (same peer ID on two devices) — not our case
   (fresh NixOS host, fresh identity).
4. Multicast blocked (UDP 3838) — only matters within a LAN; already moot across subnets.

---

## 5. The user's actual question: system service vs. per-user (Home Manager / `systemd.user`)

**Verdict: running it as a user service would be a real *permission*/simplicity win for a desktop
whose synced tree is the user's own home — but it would almost certainly NOT fix the peer-discovery
problem, and there is no maintained, ready-made module for it. Fix discovery first (known_hosts +
fixed port + `network-online.target`), and treat the per-user migration as a separate, optional
cleanup.**

### Does nixpkgs ship a Home Manager module for resilio?

**No.** Verified first-hand: the current Home Manager module tree
(`/nix/store/736r632ffgw...home-manager-0-unstable-2026-08-06/modules/`) contains **no** resilio,
rslsync, or BitTorrent Sync file, and a repo-wide grep for `rslsync\|resilio` across HM modules
returns nothing. nixpkgs provides only (a) the `resilio-sync` package and (b) the `services.resilio`
**NixOS** (system-level) module examined above.

### Is there a commonly used community flake/module?

**No established one found.** GitHub search for `resilio` returns Docker images (linuxserver/docker-
resilio-sync, bt-sync/sync-docker, binhex/arch-resilio-sync) and CLI wrappers (PythonNut/resilio-
sync-cli), but **no Nix flake or HM module** with meaningful adoption. The established NixOS pattern
is either the stock `services.resilio` module or a hand-written `systemd.user.services.<n>` unit
around the `resilio-sync` binary. So if you go per-user, you are writing the unit yourself; there is
no upstream to lean on.

### What does Resilio's own "run as a user / add to autostart" guidance say?

The upstream Linux guidance (the help-center articles I could retrieve are pre-"Resilio" era and
Cloudflare-gated today; the authoritative bits are the binary's own flags and the package's
conventions) points at the headless mode the nixpkgs module already uses: `rslsync --config <file>`
(optionally `--nodaemon`), with `--generate-secret` for keys and `--identity` to select a per-user
identity. There is **no** distinct "user-session" mode: the Linux build is the same headless daemon
whether it is spawned by systemd or from a desktop-autostart `.desktop` entry. Autostart on a
graphical desktop is equivalent to a `systemd.user` service with `WantedBy=graphical-session.target`
— the daemon is the same, only the *spawner* and *environment* differ.

### Specific advantages of a per-user (Home Manager / `systemd.user.services`) setup

| Advantage | Why it matters in this repo |
|---|---|
| **Runs as the file owner** | Eliminates the setgid + default-ACL + traverse-ACL gymnastics in `applyPerms`, the `rslsync` group membership, and the `migrateHome` re-`chown` steps. The daemon reads/writes `~/Synced Files` as the operator directly. |
| **Real home & DBus session** | A GUI-launched or `graphical-session.target` unit runs in the user's session; DBus/`$XDG_*` and the home are correct. (Not actually needed for *networking*, but removes a whole class of path/env surprises.) |
| **No cross-user ACL on the tree** | No 0700-home traversal problem, no `setfacl g:rslsync:x` on ancestors (the very issue this repo's module comments call out as causing a silent SIGSEGV). |
| **Per-user storage path** | `storage_path` lives under the user's home (`~/.sync`) without a shared `/var/lib/rslsync`. |
| **Simpler secret handling** | The key file can be user-readable (the `0440 root:rslsync` + `ExecStartPre`-as-`rslsync` dance disappears); a per-user unit can read it directly. |

### Specific disadvantages

| Disadvantage | Why it matters |
|---|---|
| **Only runs when the user is logged in** (for `graphical-session.target`) | Sync stops at logout/lock unless you use `default.target`-style `systemd.user` + lingering (`loginctl enable-linger`), which is more moving parts. The synced tree is only live during the session. |
| **No system-wide startup** | A machine that boots headless (or `yuzu` before the operator logs in) has no running daemon, so it can't be a peer for others during that window. |
| **No maintained module** | You maintain the unit, its `ExecStart`, `condition`, and restart policy yourself. |
| **`systemd.user` network ordering is weaker** | `network-online.target` in the user manager is not as reliable as in the system manager; you inherit the same DNS-timing risk (§4) and have fewer knobs. |

**Net:** the per-user move is a *permissions* ergonomics win, not a *connectivity* fix. The blocker
is discovery, and discovery is driven by tracker/relay/known_hosts regardless of spawner.

---

## 6. Other explanations for "zero outbound connections" — ranked by likelihood

Ranked against this repo's concrete facts (no systemd sandboxing; `after = network.target` only;
two subnets; `knownHosts = []`; IPv6 disabled via sysctl; `useUpnp = false`; peer has working sync):

1. **`known_hosts` is empty AND tracker/relay discovery is not completing.** The folder config has no
   static peer, so the *only* paths are LAN broadcast (dead across subnets) and tracker/relay
   (requires a successful outbound config-host + tracker exchange). If the initial `sync.conf` fetch
   or the tracker announce is failing, the daemon has no address to dial, hence zero outbound
   connections. **This is the most likely root cause.**
2. **DNS/timing: the config-host (or tracker) hostname resolution failed at start.** The NXDOMAIN on
   `i-2000.b-3-1-1.sync.bench.resilio.com` proves a DNS attempt is being made; combined with
   `16TcpSocketWrapper::set_error[-1] 1 (hostname not found)` and `after = network.target` (not
   `network-online.target`), the daemon may have started before resolv.conf/DNS was usable and
   cached the failure. `config.resilio.com` only resolves to **IPv6 (A** and no A in our test — see
   note below), so on a host with IPv6 disabled, an un-cached fetch is a DNS dead-end. **High
   likelihood, and compounding #1.**
3. **IPv6-only config-host A record vs. disabled IPv6. — DISPROVED by direct test.** The original
   reasoning was that `getent hosts config.resilio.com` returns only IPv6 here, on a host with no
   IPv6, so the config fetch would be a dead end. Testing showed the premise is wrong. `getent hosts`
   is a *display* path; the resolver APIs the daemon actually uses all return IPv4 first:
   `gethostbyname("config.resilio.com")` → `13.226.38.26`, `getaddrinfo` with the repo's new
   `networking.getaddrinfo` label table → IPv4 first, `getaddrinfo` + `AI_ADDRCONFIG` → IPv4 first.
   The binary links both `getaddrinfo` and `gethostbyname`, and `strace` over a 3-minute run shows it
   resolves through the **nscd** `hosts` database only (3 lookups) with **no DNS traffic to port 53 at
   all** — so there is no AAAA-vs-A resolution failure to speak of. Enabling IPv6 on the host was
   also tried live: no global address appeared, no default route, `curl -6` still failed — the LAN
   provides no IPv6, so the stack being off is not the differentiator. See also §6.0 below, which
   supersedes this item.
4. **Firewall blocks outbound 4000/3000 UDP+TCP.** The daemon's own listening port (4444) is opened
   inbound by the repo module, but there is **no** outbound rule for 4000/3000 (NixOS' firewall is
   outbound-permissive by default, so this is normally a non-issue — but verify no `nftables`
   restrict-out rule or router ACL on `yuzu`'s side). **Lower likelihood given NixOS defaults, but
   cheapest to rule out.**
5. **Silently-empty secret → folder never "connects".** This repo's module comments already document
   a prior incident where a 0400 secret file caused `secret: ""` and the daemon "started happily and
   simply never synced." The current code uses `0440 root:rslsync`, but if the `resilio-populate-key`
   unit failed *silently* (it is `Type=oneshot` with `RemainAfterExit=yes` and the key write is not
   surfaced), the daemon could be running with an empty secret and doing local scans only. **Verify
   first-hand: `/run/secrets/resilio-synced-files-token` non-empty, mode `0440 root:rslsync`.**
6. **Duplicate/missing peer identity or a retired tracker bootstrap baked in.** Unlikely (fresh
   identity; trackers verified live), included for completeness.

**Recommended verification order** (all local, non-destructive):

```
# a. is the secret actually non-empty and group-readable?
ls -l /run/secrets/resilio-synced-files-token && sudo -u rslsync cat /run/secrets/resilio-synced-files-token | wc -c
# b. what config did the daemon actually get?
sudo cat /run/rslsync/config.json   # check "shared_folders"[0]["secret"], "use_tracker", "known_hosts"
# c. can the daemon reach the config host / trackers right now?
getent ahostsv4 config.resilio.com   # and ahostsv6
curl -v https://config.resilio.com/sync.conf
# d. (as the daemon user) prove outbound 4000/3000 TCP
sudo -u rslsync bash -c 'echo > /dev/tcp/66.165.233.194/4000' && echo tracker-ok
# e. is the listening port fixed on BOTH peers, and is known_hosts populated?
ss -tlnp | grep 4444      # yuzu
# on the peer: confirm its listening_port is fixed (not 0), then set knownHosts = [ "<peer-ip>:<peer-port>" ]
```

The deterministic fix regardless of the above: set a **fixed `listening_port` on the peer**, put
`knownHosts = [ "<peer-ip>:<peer-port>" ]` on `yuzu` (and the reciprocal on the peer), change
`after`/`wants` to include `network-online.target`, and re-test. `known_hosts` bypasses every one of
the tracker/relay/DNS failure modes.

## 6.0 Follow-up test session (2026-09-25): what was actually measured

Everything below was run against the live daemon on `yuzu`, and it eliminates most of §6's ranked
list. Recorded because these are the experiments that separate the surviving hypotheses from the
disproved ones.

### Eliminated by direct test

| Hypothesis | Test | Result |
|---|---|---|
| Firewall blocks outbound 4000/3000/3001 | `connect()` to all four tracker/relay IPs **as the `rslsync` user** | **All OPEN** (TCP and UDP) |
| Firewall blocks inbound listening port | `nc` from `bergamot` to `yuzu:4444` | **Reachable** |
| Secret empty / unreadable | inspect live `/run/rslsync/config.json` | `"secret"` = 33 chars, correct |
| Folder rejected (`.sync/ID` broken, error 32797) | cleared a corrupt `.sync`; daemon re-adopted | **Fixed** — error gone, folder adds |
| glibc prefers IPv6 (gai.conf) | `gethostbyname`, `getaddrinfo`, `+AI_ADDRCONFIG` | **All IPv4 first** |
| IPv6 stack disabled is the cause | enabled IPv6 live, waited for RA | No global addr, no route, `curl -6` still fails — **the LAN has no IPv6** |

### The surviving observation

Under `strace -f -e trace=connect` for **3 minutes**, the daemon:

- creates `AF_INET`/`AF_INET6` UDP and TCP sockets (2+2 listen, on the configured port),
- enumerates interfaces via netlink — which returns `127.0.0.1`, `10.40.0.240`,
  `100.127.173.24` (tailscale) and `fe80::` link-local IPv6,
- applies its config, opens the tree, spawns its worker threads,
- and issues **zero `connect()` calls to any `AF_INET`/`AF_INET6` address.**

Its only resolver interaction is **three requests to the nscd `hosts` database** — there is no DNS
traffic to port 53 at all, so it never reaches a nameserver. The single recurring diagnostic is
`16TcpSocketWrapper::set_error[-1] 1 (hostname not found)`, emitted once at startup and once at
shutdown, on a socket that is never retried.

### ROOT CAUSE FOUND (2026-09-25, later the same day): the owner license

The daemon had no owner license installed. **Without one it never attempts a
peer connection at all** -- and, critically, it gives no indication that this is
why. It binds its listen sockets, scans the folder, logs no error, and simply
never dials. That is the exact shape of every observation in this section.

The evidence is a single state field in `storagePath/.sync/sync.dat`:

    before the license:  ...pausedi0e7:stoppedi1e...
    after  the license:  ...pausedi0e7:stoppedi0e...

`stopped: 1` means the folder is not connected. Adding `stopped` or `sync_level`
to the shared-folders block in `config.json` is *accepted silently and then
overridden*, so this cannot be fixed declaratively -- it has to be licensed.
Within seconds of installing the license, peer tunnels opened:

    Found peer ... 10.40.60.74:4444 transport:TCP version: 3.1.2
    best tunnel now is 10.40.60.74:4444<->10.40.0.240:52908/TCP (TLS-PSK)

**The Web UI's licensing page cannot install the file.** It opens a folder
picker on a fixed, non-editable directory with no way to navigate, so a license
sitting in `~/Downloads` is unreachable. The CLI is the workable route and is
also the reproducible one:

    rslsync --license <path> --storage <storage_path>

which writes `storagePath/License/<slot>/license.bin` plus a bare-base32 key
file. Applied from the module (see `resilio-apply-license` in
`modules/features/resilio.nix`), run as the `rslsync` user before the daemon.

**This invalidates the ranked list below**, which is why it is left in place
rather than deleted: every item on it was a hypothesis about a daemon that was
never permitted to dial out. The local network, DNS, firewall and IPv6 were all
fine. The `known_hosts` recommendation in §2 turned out to be correct and does
work -- the tunnel above is to a `known_hosts` entry -- but it was not the
blocker.

### What this means

The daemon is not failing *at* a connection attempt — it never attempts. Combined with "no tracker
IPs cached in `sync.dat`" and "not one log line mentions the tracker", the evidence points at the
daemon declining to start peer discovery rather than being blocked from it. That is a different
failure shape from every item §6 ranks, and none of the local network/permission causes explain it.

**Therefore: stop diagnosing discovery and use `known_hosts`.** It bypasses tracker, relay, nscd and
DNS entirely. The prerequisite is a **fixed `listeningPort` on every peer** — `bergamot` currently
runs on a random port (`46654`), so `known_hosts` cannot address it until the macs are pinned too.
That change is outside this repo.

---

## Sources

First-party (Resilio):
- Embedded strings & config example in `resilio-sync-3.1.1.1075` binary
  (`/nix/store/84x8li…-resilio-sync-3.1.1.1075/bin/rslsync`) — authoritative for endpoint IPs,
  config keys (`use_tracker`, `use_relay_server`, `search_lan`, `known_hosts`, `folder_defaults.use_dht`,
  `listening_port`, `external_port`), and the `https://%S/sync.conf` discovery path.
- Live config file: `https://config.resilio.com/sync.conf` (same content at `https://config.getsync.com/sync.conf`)
  — the current tracker/relay list.
- Resilio Help Center (via Wayback Machine, live portal is Cloudflare-gated):
  - "Power user preferences" — article 207371636 (2017-05-20 snapshot) — `known_hosts` syntax and the
    `* DNS name is resolved by OS means once per minute` footnote; `folder_defaults.use_relay/use_tracker/use_lan_broadcast`.
  - "What is a Relay Server?" — article 204754779 (2016-05-06 snapshot) — relay semantics.
  - "Peers aren't connecting" — article 205450205 (2016-06-02 snapshot) — causes incl. port 3000/3838,
    config host unreachable, duplicate peer ID.
  - "Cannot connect to trackers" — article 210587126 (2017-07-04/2017-11-11 snapshots) — ports 80/443/4000/
    3000/3001/3838/1900/5351, `config.usyncapp.com/sync.conf`, "Cannot get the list of trackers" vs
    "No tracker Connection Available".

Nix ecosystem:
- nixpkgs module: `nixos/modules/services/networking/resilio.nix`
  (`/nix/store/ir5c6k27…-nixos-25.11.10470…/nixos/nixos/modules/services/networking/resilio.nix`) —
  option mapping, `after = ["network.target"]`, no sandboxing, `meta.maintainers = [ ]`.
- This repo: `/etc/nixos/modules/features/resilio.nix`.
- Home Manager module tree (`/nix/store/736r632ffgw…-home-manager-0-unstable-2026-08-06/modules/`) —
  confirmed absent of any resilio/rslsync module.
- GitHub repository search (API) for `resilio-sync` — Docker/CLI results only; no Nix flake/HM module.

Verification status:
- **First-hand verified here:** tracker/relay IPs and their live reachability (`/dev/tcp` + `curl
  sync.conf`), `config.resilio.com`/`config.getsync.com` serving `sync.conf`, binary config keys and
  the embedded example, the nixpkgs module's lack of sandboxing and its `network.target` ordering, the
  Home Manager absence, the `use_dht`-only-under-`folder_defaults` fact, `sync.bench.resilio.com` =
  `send_statistics` telemetry (retired), NXDOMAIN harmless.
- **Inference / not verified:** the exact reason this *specific* host dials nothing outbound (needs
  the local checks in §6); whether the forum has a dedicated "system service can't connect" thread
  (forum is Cloudflare-gated, could not enumerate); the DHT bootstrap being literally absent rather
  than runtime-loaded.
- **Disproved since first written** (see §6.0): the IPv6-preference hypothesis, and the firewall
  hypothesis. Both were tested directly and eliminated. The `use_dht`-is-ignored claim was also
  disproved (§3). The root cause of the daemon never dialing out remains **unidentified**.
