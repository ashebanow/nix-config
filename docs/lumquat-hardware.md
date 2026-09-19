# Lumquat hardware and LLM serving

Lumquat is the AI server. This document holds the hardware inventory and the GPU/LLM tuning
that used to live in `AGENTS.md`. It is reference material, not per-task context — nothing
here needs to be re-read to work on the config.

## Hardware

| | |
| --- | --- |
| Model | GMKTec Evo X2 (Strix Halo mini PC) |
| CPU/APU | AMD Ryzen AI Max (Strix Halo), `x86_64-linux` |
| GPU | AMD RDNA 3.5 integrated (`amdgpu`, gfx1151) |
| Memory | 128 GB unified — CPU and GPU share one pool |
| Root | LUKS-encrypted (`/dev/mapper/luks-...`) — see `docs/luks-unlock-strategy.md` |
| Boot | systemd-boot + EFI |

[hellas-ai/nix-strix-halo](https://github.com/hellas-ai/nix-strix-halo) collects platform-specific
modules for this hardware.

## Kernel parameters

Set in `hosts/lumquat/hardware-configuration.nix`.

| Parameter | Value | Purpose |
| --- | --- | --- |
| `amd_iommu=off` | — | Contested; see "The IOMMU question" below |
| `ttm.pages_limit` | `27787264` | 106 GB TTM-managed pool (4 KB pages) |
| `amdgpu.vis_vramlimit` | `102400` | 100 GB of visible VRAM reported to ROCm and llama.cpp |

Memory layout, per the comments in that file: about 124 GB of the 128 GB is usable; 100 GB is
reported to ROCm and llama.cpp, 106 GB is the TTM-managed pool, and roughly 22 GB stays with the
OS for containers and the system. The model budget is a Q8 256K-context Qwen at about 89 GB,
leaving around 13 GB of GPU headroom for KV-cache bursts and future growth.

`vis_vramlimit` overrides the incorrect 64 GB VRAM figure the hardware otherwise reports. 100 GB
is 102,400 MiB; 106 GB is 27,787,264 four-kilobyte pages.

> **Doc drift to be aware of.** `AGENTS.md` and `docs/architecture.md` previously listed
> `amdgpu.gttsize=126976` and `ttm.pages_limit=32505856`. Neither matches the file above —
> `gttsize` is not set at all, and the page limit differs. The table here is what is actually
> configured. `.pi/skills/colmena-deployer/references/host-inventory.md` and
> `.../infrastructure.md` carry the same stale pair.

## The IOMMU question

`amd_iommu=off` is currently set, annotated in the file only as "required for Strix Halo
stability". [nix-strix-halo](https://github.com/hellas-ai/nix-strix-halo) defaults to IOMMU-off
on the grounds that IOMMU translation measurably slows GPU-memory workloads.

That justification is **contested**. A community report on the same silicon
([antirez/ds4#871](https://github.com/antirez/ds4/pull/871)) runs successfully with the IOMMU
active (`iommu.passthrough=0`) and argues the flag is unnecessary and costs access to the NPU.
What is *not* contested is that turning the IOMMU off gives up device isolation — which is the
reason it blocks GPU passthrough to a VM (`docs/research/container-mechanisms.md`).

This is recorded as an open question rather than a settled requirement. The parameter has **not**
been changed. Settling it means measuring throughput with and without the flag, the same way any
other kernel-parameter change should be justified.

## Where the LLM stack is configured

- Model catalog, model container: `modules/features/llm.nix`, `lib/models.nix`
- Gateway: `modules/features/bifrost.nix`, `compose/llm/bifrost-config.json`
- Browser client: `compose/llm/openwebui-compose.yml`
- Reliability gate: `docs/bifrost-reliability-gate.md`

## Related

- `docs/architecture.md` — module layout (its kernel-parameter table is stale; see the drift note)
- `docs/plan.md` — the original build plan
- `docs/luks-unlock-strategy.md` — LUKS/TPM2 unlock
