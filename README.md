# Lumquat — AI Server Provisioning Guide

GMKTec Evo X2 (Strix Halo) running NixOS. AMD Ryzen AI Max, 128 GB unified memory,
RDNA 3.5 GPU, LUKS-encrypted root.

## Table of Contents

1. [Pre-Flight](#pre-flight)
2. [Secrets Setup](#secrets-setup)
3. [Hardware Configuration](#hardware-configuration)
4. [Deploy](#deploy)
5. [Post-Deploy](#post-deploy)
6. [Model Downloads](#model-downloads)
7. [Backups](#backups)
8. [Future Work](#future-work)
9. [Daily Operations](#daily-operations)

---

## Pre-Flight

### 1. Verify SSH Access

```bash
ssh root@lumquat       # or the machine's current IP/hostname
ssh podman@lumquat
```

If not yet accessible, boot the machine with a NixOS ISO, set a root password,
and enable SSH:

```bash
# On the machine (from NixOS ISO)
passwd
systemctl start sshd
ip addr show  # note the IP
```

### 2. Confirm Hardware

On the machine, verify:

```bash
# GPU available
lspci | grep -i amd

# Memory (should be ~128 GB)
free -h

# Disks
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT
ls -la /dev/disk/by-uuid/
```

### 3. Disk Layout

The config expects three partitions:

| Mountpoint | Purpose | Filesystem |
|------------|---------|------------|
| `/` | Root (LUKS-encrypted) | ext4 |
| `/boot` | EFI system partition | vfat |
| `/var/lib/llm-models` | Model storage | ext4 |

If the machine doesn't have this layout yet, set it up with `parted`/`fdisk`
and `cryptsetup`. This is a one-time manual step not covered by the Nix config.

---

## Secrets Setup

### 4. Generate Machine SSH Key for SOPS

SOPS uses age encryption. We derive the age key from the machine's SSH host key.

**On lumquat:**

```bash
# Generate SSH host key if not already present
ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N ""

# Convert to age key
nix-shell -p ssh-to-age --run \
  "ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key > /tmp/lumquat-age-key.txt"

# Display the public age key (you'll need this for .sops.yaml)
ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub
# Output: age1...
```

### 5. Configure `.sops.yaml`

**On your local machine** (in the lumquat repo):

```bash
# Edit secrets/.sops.yaml to include all recipient keys:
#
# creation_rules:
#   - path_regex: secrets/secrets\.yaml$
#     age: |
#       age1...your-personal-key...
#       age1...lumquat-machine-key...
```

Add both:
- Your personal age key (from `~/.config/sops/age/keys.txt`)
- The lumquat machine age key (from step 4 above)

> **Work item**: Generate your personal age key if you don't have one:
> ```bash
> mkdir -p ~/.config/sops/age
> nix-shell -p age --run "age-keygen -o ~/.config/sops/age/keys.txt"
> ```

### 6. Fill In Secrets

**On your local machine:**

```bash
cd /path/to/lumquat

# Edit secrets/secrets.yaml with real values
# - tailscale-auth-key: get from https://login.tailscale.com/admin/settings/keys
#   (Create a reusable auth key, tag it for lumquat)

# Re-encrypt with all recipients
nix-shell -p sops --run "sops updatekeys secrets/secrets.yaml"
```

Verify:
```bash
nix-shell -p sops --run "sops -d secrets/secrets.yaml"
```

---

## Hardware Configuration

### 7. Fill In Disk UUIDs

**On lumquat**, get the UUIDs:

```bash
ls -la /dev/disk/by-uuid/
```

Then **on your local machine**, edit `hosts/lumquat/hardware-configuration.nix`:

```nix
# Replace these placeholders:
"/dev/disk/by-uuid/YOUR-LUKS-UUID-HERE"     → actual LUKS partition UUID
"/dev/disk/by-uuid/YOUR-EFI-UUID-HERE"      → actual EFI partition UUID
"/dev/disk/by-uuid/YOUR-MODELS-UUID-HERE"    → actual models partition UUID
```

> If you don't have a third partition for models, remove the
> `/var/lib/llm-models` entry from `fileSystems` and the `llmModelStorage`
> flag from `hosts/lumquat/configuration.nix`.

---

## Deploy

### 8. Build Configuration (from local)

```bash
# Verify configuration
nix flake check

# Build (optionally from macOS — uses remote builder or eval-only)
nix build .#nixosConfigurations.lumquat.config.system.build.toplevel
```

> If building from macOS, you need a remote builder or `--system x86_64-linux`
> with cross-compilation support.

### 9. Deploy to Lumquat (from Linux machine or lumquat itself)

**Option A: Deploy from lumquat itself** (recommended for first deploy):

```bash
# On lumquat, clone the repo
git clone <repo-url> /etc/nixos
cd /etc/nixos

# Build and switch
nixos-rebuild switch --flake .#lumquat
```

**Option B: Deploy remotely** (requires SSH to lumquat):

```bash
# From a Linux machine
nixos-rebuild switch \
  --flake .#lumquat \
  --target-host root@lumquat \
  --use-remote-sudo
```

### 10. Verify Deployment

```bash
# On lumquat
systemctl status tailscaled
systemctl status cockpit
systemctl status podman
systemctl status sshd

# Tailscale should be running
tailscale status

# Cockpit available at https://lumquat:9090
```

---

## Post-Deploy

### 11. Tailscale Authentication

If Tailscale doesn't auto-connect (auth key may need manual confirmation):

```bash
# On lumquat
tailscale up --ssh
```

Visit the URL it prints to authenticate. You should now be able to:

```bash
# From your machine
ssh podman@lumquat   # via Tailscale SSH
# or
ssh -p 2222 root@lumquat  # fallback SSH
```

### 12. Verify SOPS Decryption

```bash
# On lumquat
cat /run/secrets/tailscale-auth-key
# Should show your auth key
```

---

## Model Downloads

### 13. Models (Declarative — Doug Campos Approach)

Model catalog adapted from [Doug Campos' nixifying-local-llms](https://random.qmx.me/posts/2026/01/08/nixifying-local-llms/)
([source](https://github.com/qmx/dotfiles/blob/master/lib/models.nix)).

Models are defined in `lib/models.nix` with two tiers:

| Tier | Mechanism | Integrity |
|------|-----------|-----------|
| **Promoted** (`ggufs`) | `pkgs.fetchurl` with SHA256 → Nix store | ✅ Content-addressed |
| **Experimental** (`models`) | llama.cpp `-hf` flag → HF download | ❌ Best-effort |

Current catalog:

| Model | Tier | Purpose | Port | Context |
|-------|------|---------|------|---------|
| Qwen 3.6 35B-A3B Q8 | Experimental | Coding assistant (MTP) | 8080 | 256K |

### Promotion Workflow (from QMX blog)

1. Model starts in `models` section → llama.cpp downloads via `-hf` flag
2. After first successful deploy, compute SHA256 on lumquat:
   ```bash
   nix-hash --flat --type sha256 /root/.cache/llama.cpp/hf/<model>.gguf | nix-to-sri
   ```
3. Add `sha256 = "sha256-...";` to `lib/models.nix` under `ggufs`
4. Rebuild: model is now a Nix derivation, cached, and verified

Once promoted, models benefit from:
- Content-addressed storage in the Nix store
- Integrity verification on every build
- Shared cache across machines (LAN speed)

### Model Files

Models live at `/var/lib/llm-models` (used as HF download cache until promoted).
After promotion, they live at `/nix/store/...` (immutable, read-only).

---

## Backups

### 14. Back Up Machine Keys

**Critical:** Back up lumquat's SSH host keys and age identity so you can
decrypt SOPS secrets and rebuild the machine.

```bash
# On lumquat, back these up to a safe location:
/etc/ssh/ssh_host_ed25519_key
/etc/ssh/ssh_host_ed25519_key.pub

# Converted age key (from step 4)
/tmp/lumquat-age-key.txt  → save this somewhere safe
```

> **Work item**: Add automated key backup (e.g., to 1Password or a secure git
> repo). Currently manual.

### 15. Back Up Model Catalog

Model URLs and hashes are declared in `lib/models.nix` and tracked in git.
The promotion workflow (fill in SHA256) ensures full reproducibility.

For promoted models (SHA256 known), the model file is a Nix derivation —
no manual backup needed. Rebuilds fetch from Nix cache or HuggingFace.

For experimental models (no SHA256), the file lives in the HF cache at
`/var/lib/llm-models`. To recover, add the SHA256 to `lib/models.nix` and rebuild.

---

## Future Work

These items are planned but not yet implemented:

| Task | Priority | Notes |
|------|----------|-------|
| **Colmena deployment** | High | Replace manual `nixos-rebuild` with `colmena deploy` |
| **DeepSeek v4 container** | Medium | Add second container when model is released |
| **`system.stateVersion`** | Low | Add explicit state version to base config |
| **Automated key backup** | Medium | Backup SSH/age keys to secure storage |
| **Monitoring dashboards** | Low | Grafana/Prometheus for GPU and LLM metrics |
| **Firewall consolidation** | Low | Move all firewall rules to a single location |
| **Colmena health checks** | Low | Set up `colmena exec` health checks |

### Colmena Setup (Future)

When ready for Colmena:

```bash
# Add colmena input to flake.nix
# Create colmena config
# Deploy:
colmena deploy --on lumquat
colmena exec --on lumquat -- sudo systemctl status tailscaled
```

### LLM Containers

Two containers are defined in `modules/features/llm.nix` using
`virtualisation.oci-containers`:

| Container | Model | Port | Purpose |
|-----------|-------|------|---------|
| `qwen-35b-a3b` | Qwen 3.6 35B Q8 | 8080 | Coding (256K, MTP) |

To add a second model:

1. Add to `lib/models.nix` (ggufs + models sections)
2. Add a new entry under `virtualisation.oci-containers.containers`
3. Give it a unique port (e.g., `8082`)

---

## Daily Operations

### Check System Status

```bash
ssh podman@lumquat

# Service health
systemctl status tailscaled cockpit podman

# GPU status
nix-shell -p rocm-smi --run "rocm-smi"

# Memory
free -h

# Disk
df -h

# LLM containers
systemctl status podman-qwen-35b-a3b
podman logs qwen-35b-a3b

# Check model API
curl -s http://localhost:8080/health | jq   # Qwen (coding)
```

### Update Configuration

```bash
# Local: pull latest config changes
cd /path/to/lumquat && git pull
nix flake check

# Build & deploy (option B from step 9)
nixos-rebuild switch --flake .#lumquat --target-host root@lumquat
```

### Update Nixpkgs & Dependencies

```bash
nix flake update
nix flake check
# Deploy as above
```

### Format Code

```bash
# Auto-activated via direnv — just:
just fmt
```
