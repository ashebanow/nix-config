---
description: Update container image digests and deploy to lumquat
---

Update container image digests and deploy affected NixOS hosts.

## Workflow

### 1. Check Current Container Definitions

Find all container image definitions in feature modules:

```bash
grep -r "image = " --include="*.nix" modules/features/
```

### 2. Identify Containers

List the containers used in this config:

| Container | Image | Purpose |
|-----------|-------|---------|
| qwen-27b | ghcr.io/ggerganov/llama.cpp | Coding LLM |
| deepseek-v4 | ghcr.io/ggerganov/llama.cpp | Planning LLM |

### 3. Check for Updates

For GitHub Container Registry images:
```bash
skopeo inspect docker://ghcr.io/ggerganov/llama.cpp:server
```

Compare with current digests (if any are stored).

### 4. Update If Needed

If updates are available:
1. Update the image reference in the Nix module
2. Verify GPU passthrough is still configured (`devices = ["/dev/dri"]`)
3. Run `nix flake check` to verify evaluation

### 5. Deploy

```bash
colmena apply --on lumquat --impure
```

### 6. Verify

```bash
ssh lumquat "podman ps"
ssh lumquat "systemctl status podman-qwen-27b"
ssh lumquat "systemctl status podman-deepseek-v4"
```
