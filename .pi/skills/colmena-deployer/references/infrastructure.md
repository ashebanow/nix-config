# Infrastructure Reference

## Lumquat

- **Hardware**: GMKTec Evo X2 (Strix Halo)
- **CPU**: AMD Ryzen AI Max (Strix Halo)
- **RAM**: 128 GB unified (GPU + CPU share pool)
- **GPU**: AMD RDNA 3.5 integrated (amdgpu)
- **Boot**: systemd-boot + EFI
- **Disk**: LUKS-encrypted root

## Key Services

| Service | Port | Access |
|---------|------|--------|
| Cockpit | 9090 | Tailscale only |
| Podman containers | various | Via Cockpit or Tailscale |
| LLM APIs | via Tailscale | Through Aperture only |

## Kernel Parameters (Strix Halo)

Required for Strix Halo stability and full VRAM access:
- `amd_iommu=off`
- `amdgpu.gttsize=126976`
- `ttm.pages_limit=32505856`

## SSH Access

Connect via Tailscale:
```bash
ssh root@lumquat.tailnet
```

## Tailscale

- LLM access routed through Tailscale Aperture
- Cockpit accessible via Tailscale SSH tunnel
- No direct LLM exposure to internet
