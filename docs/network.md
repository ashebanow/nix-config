# Home network addresses

The LAN addresses these hosts and devices actually use, so nobody has to infer
them from git history again. Three BOX-311 observability tickets independently
concluded that "lumquat's address appears nowhere in this repo" and each guessed
at one; the guesses were wrong, and wrong in a way that fails closed (a firewall
rule for the wrong subnet silently matches nothing).

Keep this file current. It is the source of truth for anything that writes an
address into a firewall rule or a remote-write URL.

## Two subnets, not one

The house runs two `/24`s, which is the thing that misled those tickets: git
history only ever mentions `10.40.60.0/24`, so it looks like the whole LAN.

**`10.40.0.0/24`** — the servers and storage side:

| Host | Address | Notes |
| --- | --- | --- |
| lumquat | `10.40.0.87` | the AI server; observability **agent**, remote-writes to calamansi |
| storage2 | `10.40.0.59` | UniFi UNAS Pro; SMB `smb://10.40.0.59`; SNMPv3 + CEF syslog source; archive |
| miraclemax (secondary) | `10.40.0.240` | macOS workstation; also on `.60` |

**`10.40.60.0/24`** — the workstation and device side:

| Host | Address | Notes |
| --- | --- | --- |
| gateway | `10.40.60.1` | UniFi gateway; CEF syslog source (BOX-335) |
| bergamot | `10.40.60.74` | macOS workstation |
| miracle_max | `10.40.60.97` | macOS workstation |
| printer | `10.40.60.111` | IPP Everywhere (`hosts/yuzu/configuration.nix`) |

**calamansi** — the observability host. Not yet on the network (installed by
BOX-324); its address is unknown and no code should assume it sits on either
subnet. Until it is recorded here, `my.observabilityHostAddress` on lumquat
remains a placeholder.

## Why the subnets are routed, not bridged

The observability design has hosts talking directly over the LAN with
per-source firewall rules rather than trusting a subnet, so a rule names a
`/32` for one machine wherever that is practical. That is also why a wrong
subnet is a silent failure rather than an obvious one: `iptables -s` against an
address the packet never had simply does not match, and the symptom is "the
ingest port is unreachable" rather than "the rule is wrong".

## Addresses this repo writes into config

| Appears in | Value | Set by |
| --- | --- | --- |
| `hosts/calamansi/configuration.nix` → `my.observabilityHostAllowedSources` | `10.40.0.87` | this file |
| `hosts/lumquat/configuration.nix` → `my.observabilityHostAddress` | placeholder `10.40.60.20` | **BOX-324**, to calamansi's real address |

When BOX-335 lands the CEF syslog path, `my.observabilityHostAllowedSources` on
calamansi gains the gateway (`10.40.60.1`) and storage2 (`10.40.0.59`).
