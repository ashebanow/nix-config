---
description: Run health checks on lumquat server
---

# Lumquat Health Check

Run these checks to verify the system is healthy.

## Quick Status

```bash
# System health
ssh lumquat "systemctl --failed"
ssh lumquat "systemctl is-system-running"

# Containers
ssh lumquat "podman ps"
ssh lumquat "podman ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"

# Listening ports
ssh lumquat "ss -tlnp | grep LISTEN"
```

## Service Checklist

- [ ] No failed systemd units
- [ ] System running state is "running"
- [ ] All expected containers are running

## Container Health

Expected containers:
| Container | Purpose | Port |
|----------|---------|------|
| qwen-27b | Coding LLM | 8080 |
| deepseek-v4 | Planning LLM | 8081 |

```bash
# Check container logs
ssh lumquat "podman logs qwen-27b --tail 20"
ssh lumquat "podman logs deepseek-v4 --tail 20"

# Restart a container if needed
ssh lumquat "podman restart qwen-27b"
```

## Resource Usage

```bash
# Disk space
ssh lumquat "df -h"

# Memory
ssh lumquat "free -h"

# CPU
ssh lumquat "top -bn1 | head -20"
```

## GPU Check

```bash
# Verify /dev/dri accessible
ssh lumquat "ls -la /dev/dri/"

# Check GPU memory (if needed)
ssh lumquat "cat /sys/class/drm/card0/device/mem_info_vram_total"
```

## Cockpit

```bash
# Cockpit should be running
ssh lumquat "systemctl status cockpit"

# Test web access (via Tailscale)
curl -k https://lumquat.tailnet:9090 2>/dev/null | head -5
```

## Tailscale

```bash
# Check Tailscale status
ssh lumquat "tailscale status"

# Verify LLM access routes through Tailscale
ssh lumquat "curl -s http://127.0.0.1:8080/health 2>/dev/null || echo 'No health endpoint'"
```

## NixOS Generation

```bash
# Check current generation
ssh lumquat "nixos-version"
ssh lumquat "readlink /run/current-system"

# Last boot time
ssh lumquat "who -b"
```

## Quick Fixes

```bash
# Restart failed services
ssh lumquat "systemctl restart \$(systemctl --failed --no-legend | awk '{print \$1}')"

# Restart all containers
ssh lumquat "podman restart \$(podman ps -q)"
```

## Report Format

```
=== Lumquat Health Report ===

System: [OK/WARN/FAIL]
- Failed units: [count]
- Running since: [date]

Containers: [OK/WARN/FAIL]
- qwen-27b: [running/stopped]
- deepseek-v4: [running/stopped]

Resources:
- Disk: [usage%]
- Memory: [usage%]

Cockpit: [OK/FAIL]
Tailscale: [OK/FAIL]
```
