# What UniFi devices send over syslog/SIEM (BOX-314)

Research for the observability map (BOX-311): can storage2 (UniFi UNAS Pro) and the UniFi gateway feed logs to calamansi, what arrives, and what covers NAS health that syslog does not. Checked 2026-11-23.

## Short answer

- **Both devices can export.** The gateway does it through the UniFi Network app's "SIEM Server" destination. The UNAS Pro gained "SIEM Server integration" in its own UniFi OS **4.2.8** (2025-04-28), the same feature Cloud Keys got in UniFi OS 4.2.9.
- **Format is CEF-in-syslog**, plain (no TLS), to a host and port you type in. UDP 514 is what everyone uses. TCP is reported by third parties but not confirmed by Ubiquiti.
- **Content is event-shaped, not metric-shaped.** Admin logins and config changes, device adopted/offline, client connect/roam, IPS threats, honeypot, firewall blocks, WAN failover and latency, PoE, updates, backups. Nothing documented carries SMART attributes, temperatures, capacity numbers, or pool state.
- **NAS health beyond syslog** comes from UniFi's own drive-health alerts (push/email; "Drive at Risk", "Drive Failure Detected") and possibly SNMP. Whether the UNAS SNMP agent exposes storage OIDs is **unverified**.
- **Volume is tiny** for a home network unless per-rule firewall logging is turned on.

For BOX-311: point both devices at a syslog listener on calamansi (UDP 514 or a high port), parse CEF there, and alert on the handful of storage/device events. Treat UNAS health as "events only" and decide separately whether SNMP is worth probing.

## Source trust

The official article (help.ui.com 33349041044119) returns HTTP 403 to automated fetches, so its content below comes from search-engine extracts of that page, not a full read. Ubiquiti's release-notes pages on community.ui.com render client-side and could not be read directly. The UNAS release lines come from a German fan forum that mirrors the official notes verbatim, and the Cloud Key line from Ubiquiti's own RSS feed. Third-party SIEM-vendor docs and GitHub projects are marked **(3rd party)**. Nothing was tested on the user's devices.

## 1. Which devices support it

| Device | Where | Version | Evidence |
|---|---|---|---|
| UniFi gateway (via UniFi Network app) | Settings, Control Plane > Integrations > Activity Logging (some versions: CyberSecure > Traffic Logging), destination "SIEM Server" | CEF export from Network **8.5.x**, full system-log export by **9.3.43** (3rd party, versions disagree); CEF format unchanged through **10.0.x** | Official article [1]; Graylog [5], RocketCyber [6], Wazuh-Unifi [7] (3rd party) |
| UNAS Pro (UniFi OS, NAS build) | UniFi OS settings (exact menu not verified) | UniFi OS - Network Attached Storage **4.2.8**, 2025-04-28: "Added support for SIEM Server integration." and "Improved System Logs." | Release notes mirrored at [3] |
| Cloud Key (for comparison) | | UniFi OS **4.2.9**, 2025-04-29, same wording | Ubiquiti RSS [2] |

The UNAS line is a UniFi OS feature, not a UniFi Network one, so the UNAS sends **UniFi OS** events (system, updates, admins, backups, users), not the Network app's client and firewall events. Third-party guides list UniFi OS categories as "System, Updates, Admins, Backups, Users" [8] (3rd party). A 2025 blog post noted that UniFi OS CEF events and UniFi Network CEF events used different timestamp conventions, which confirms both streams exist [9] (3rd party, low trust).

**Not verified:** whether the UNAS's SIEM categories include anything from the UniFi Drive app (storage pool, drive health, SMB, backup jobs). Drive release notes added admin usernames to Drive System Logs (Drive 4.0) and, per an aggregator, SMB system logs in Drive 4.5.7 [10] (3rd party), but no source says those Drive logs go out over SIEM.

## 2. Transport and format

- **Format:** CEF in a syslog message. "All logs are exported using the Common Event Format (CEF)" [1]. Header: `CEF:Version|Device Vendor|Device Product|Device Version|Device Event Class ID|Name|Severity|[Extension]`.
- Observed example (3rd party [7]): `CEF:0|Ubiquiti|UniFi Network|9.3.33|544|Admin Accessed UniFi Network|1|...`
- Extension keys seen: `src`, `UNIFIcategory`, `UNIFIsubCategory`, `UNIFIadmin`, `UNIFIclientMac`, `UNIFIclientIp`, `UNIFIdeviceName`, `UNIFIhost`, `UNIFIutcTime` [1][7].
- CrowdSec reports the output has CEF headers but not strictly conformant CEF, so stock CEF parsers may need tweaks [11] (3rd party).
- **Transport:** You enter an IP and port [1]. The official article does not say UDP or TCP. Third-party receivers all use UDP 514 by default [6][7]. Wazuh-Unifi mentions TCP "if your sender uses TCP" [7]; not confirmed for UniFi. **No TLS** is mentioned anywhere.
- **Timestamps:** Network 9.4.17 changed CEF syslog timestamps to local time zone; earlier they were UTC [9] (3rd party). Prefer `UNIFIutcTime` when parsing.

## 3. What is included

UniFi Network (gateway) categories and subcategories [7] (3rd party, matches the Network UI):

- **Monitoring:** Guest Hotspot, WiFi, Wired, Status
- **Internet:** Outage and Failover, Performance (latency, packet loss)
- **Power:** PoE, Redundancy
- **Security:** Firewall, Honeypot, Intrusion Prevention
- **System:** Admin Activity, Devices, Network, VPN, WiFi, Wired

UniFi OS categories (consoles and UNAS): System, Updates, Admins, Backups, Users [8] (3rd party).

**Not included / separate:**

- Traffic Flow (DPI) logs are not exported over CEF; they are CSV or NetFlow/IPFIX only [7] (3rd party).
- Per-rule firewall hits come as plain netfilter-style syslog (`[WAN_LOCAL-D-0] DESCR=... SRC=... DST=...`), a separate "remote syslog" stream from the CEF one [6][7] (3rd party).
- **Disk health, SMART, capacity, RAID/pool state, backup job results: no source says any of these appear in the SIEM stream.** Ubiquiti documents drive-health alerts ("Drive Failure Detected", "Drive at Risk of Failure", triggered partly by SMART) as UniFi notifications [4], and Drive 4.0 added a Health Monitor with SMART detail in the UI [12]. Whether these notifications are also emitted as UniFi OS "System" CEF events is **unverified**; the only way to know is to enable it and watch.

## 4. NAS health outside syslog

- **UniFi notifications:** push and email for drive at-risk or failed, and storage-pool warnings [4]. Email needs a UniFi account or custom SMTP; 4.3.6 fixed custom-SMTP email for local users [3]. This is the only documented, supported path for SMART-driven alerts today.
- **SNMP:** the UNAS has an SNMP agent. Release notes mention "Improved name and operating system reporting via SNMP" (4.1.9) and configurable Contact/Location (4.2.8) [3]. Ubiquiti's SNMP guide covers v1/v2c/v3 on UDP 161 for UniFi Network devices [13]. **Not verified:** whether the UNAS exposes HOST-RESOURCES-MIB `hrStorage` (volume capacity) or any disk/RAID OIDs. If it does, capacity can come from SNMP; SMART almost certainly will not.
- **UniFi API:** a Home Assistant integration's tracker states per-disk SMART, temperature and array status are not exposed by official public endpoints for UNAS/Drive [14] (3rd party, low trust). Not worth building on.
- **Worth it?** For "disk filling" on storage2, an SNMP probe is worth a 10-minute test (`snmpwalk` the UNAS for `hrStorage`). For drive failure, rely on UniFi's own push/email alert rather than reimplementing it.

## 5. Rate and volume

No official figures. Event categories are low-rate (tens to hundreds of events a day on a home network). The volume risks are: enabling per-rule firewall logging on busy rules, the WiFi client connect/roam subcategories, and double-sending the same categories from two syslog pages to one listener, which duplicates events (notably Updates) [8] (3rd party). UDP means silent loss if calamansi is down; the devices do not buffer, as far as any source says.

## Open items to verify on the devices

1. UNAS UniFi OS: exact menu and category list for SIEM, and whether drive-health and pool events appear as CEF.
2. Whether the gateway/UNAS offer TCP in the SIEM destination.
3. `snmpwalk` storage2 for HOST-RESOURCES-MIB storage and any disk OIDs.

## Sources

1. Ubiquiti, "UniFi System Logs & SIEM Integration", https://help.ui.com/hc/en-us/articles/33349041044119-UniFi-System-Logs-SIEM-Integration (403 to bots; content via search extracts)
2. Ubiquiti, UniFi OS - Cloud Keys release RSS, https://community.ui.com/rss/releases/UniFi-Cloud-Key-Firmware/c4ccd194-4cbf-4738-b07d-0aa6f04d178e
3. Mirror of UniFi OS - Network Attached Storage 4.x release notes, https://ubiquiti-networks-forum.de/board/thread/11275-final-unifi-os-network-attached-storage-4-x-x (originals: https://community.ui.com/releases/UniFi-OS-Network-Attached-Storage-4-2-9/74efa5d6-dd53-4dfa-8b15-42eeea4f1b37 and siblings)
4. Ubiquiti, "Understanding Drive and Storage Health in UniFi", https://help.ui.com/hc/en-us/articles/12395343519639-Understanding-Drive-and-Storage-Health-in-UniFi
5. Graylog, Ubiquiti UniFi content pack, https://go2docs.graylog.org/illuminate-current/content_packs/ubiquiti_unifi_content_pack.htm (3rd party)
6. RocketCyber, "Configuring Ubiquiti UniFi Gateways", https://help.rocketcyber.kaseya.com/help/Content/network-device-firewall/configure-network-device-ubiquiti-unifi-security-gateway-usg.html (3rd party)
7. Halino/Wazuh-Unifi, https://github.com/Halino/Wazuh-Unifi (3rd party; tested against Network 10.0.162)
8. jmasarweh/UniFi-Insights-Plus, https://github.com/jmasarweh/UniFi-Insights-Plus (3rd party)
9. mindthelog blog, https://mindthelog.blogspot.com/2025/08/unifi-network-application-9417-cef.html (3rd party, low trust)
10. Releasebot, Drive updates, https://releasebot.io/updates/ubiquiti/ubiquiti-drive (aggregator, low trust)
11. CrowdSec UniFi collection, https://app.crowdsec.net/hub/author/crowdsecurity/collections/unifi (3rd party)
12. Ubiquiti blog, "Introducing UniFi Drive 4.0", https://blog.ui.com/article/introducing-unifi-drive-4-0
13. Ubiquiti, "SNMP Monitoring in UniFi Network", https://help.ui.com/hc/en-us/articles/33502980942615-SNMP-Monitoring-in-UniFi-Network
14. ha-unifi-insights issue 281, https://github.com/tinkerologie/ha-unifi-insights/issues/281 (3rd party, low trust)
