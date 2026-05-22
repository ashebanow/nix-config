# Host Inventory

## Lumquat

**Purpose**: AI server for running LLMs

**Hardware**:
- GMKTec Evo X2 (Strix Halo mini PC)
- AMD Ryzen AI Max (Strix Halo)
- 128 GB unified memory
- AMD RDNA 3.5 GPU

**Access**:
- SSH: `ssh root@lumquat` (via Tailscale)
- Cockpit: Port 9090 (Tailscale only)

**Services**:
- Podman containers (quadlets)
- Qwen-27B LLM
- DeepSeek v4 LLM
- Cockpit web UI

**Kernel Parameters**:
```
amd_iommu=off amdgpu.gttsize=126976 ttm.pages_limit=32505856
```

## Future Hosts

When adding new servers, update this file with:
- Hostname and purpose
- Hardware details
- Access information
- Running services
- Any special configuration notes
