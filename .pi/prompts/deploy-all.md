---
description: Deploy to all NixOS hosts via Colmena
---

Deploy the current configuration to all managed NixOS hosts.

## Pre-Deployment Checklist

Before deploying, verify:

- [ ] Flake evaluates cleanly: `nix flake check`
- [ ] Secrets are current
- [ ] No uncommitted changes to deploy (or intentionally deploying WIP)
- [ ] Target hosts are reachable

## Deployment Commands

### Single Host (Lumquat)

```bash
# Build first to catch eval errors
colmena build --on lumquat --impure

# Then deploy
colmena apply --on lumquat --impure
```

### All Hosts (Future)

When additional hosts are added:

```bash
# Deploy to multiple hosts
colmena apply --on host1,host2,host3 --impure
```

## Post-Deployment Verification

After deployment completes:

```bash
# Check for failed units
ssh lumquat "systemctl --failed"

# Verify key services
ssh lumquat "systemctl status podman.socket"
ssh lumquat "podman ps"

# Check LLM containers
ssh lumquat "podman logs qwen-27b --tail 20"
ssh lumquat "podman logs deepseek-v4 --tail 20"

# Verify Cockpit
ssh lumquat "systemctl status cockpit"
```

## Rollback

If deployment causes issues:

```bash
ssh lumquat "sudo nixos-rebuild switch --rollback"
```

## Deployment Report

After deployment, report:
- Which hosts were updated
- Any warnings or errors during activation
- Services that were restarted
- Verification results
