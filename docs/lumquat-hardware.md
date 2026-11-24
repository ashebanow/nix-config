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
> configured.

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

## GPU telemetry: what gfx1151 exposes to node_exporter

lumquat is an observability agent (BOX-327), so its GPU is monitored from the same
`prometheus-node-exporter` as its host health: the `drm` collector (turned on by
`my.observabilityGpuMetrics = true`) plus the `hwmon` collector every agent runs.
No ROCm, no `amd-smi`, no `amdgpu_top`, per BOX-315: the `drm` and `hwmon`
collectors read generic amdgpu sysfs and need no userspace GPU stack, whereas
nixpkgs' `rocmPackages.amdsmi` (7.2.4) predates gfx1151 APU metrics (ROCm
7.13/7.14) and `amdgpu_top` has no Prometheus mode.

### What the `drm` collector emits, generically

Read from the pinned `prometheus-node-exporter` **1.12.1** sources
(`collector/drm_linux.go`, `prometheus/procfs/sysfs/class_drm_amdgpu.go`), not
guessed. The collector globs `/sys/class/drm/card[0-9]`, keeps only cards whose
`device/uevent` contains `DRIVER=amdgpu`, and then **reads each field
independently, skipping any file that does not exist**. That last part is what
makes it safe on an APU: a missing file is a missing *metric*, never a failed
scrape.

| metric | sysfs file, under `/sys/class/drm/cardN/device/` | unit |
| --- | --- | --- |
| `node_drm_card_info{card,memory_vendor,power_performance_level,unique_id,vendor}` | `mem_info_vram_vendor`, `power_dpm_force_performance_level`, `unique_id` (value 1) | — |
| `node_drm_gpu_busy_percent{card}` | `gpu_busy_percent` | % |
| `node_drm_memory_gtt_size_bytes{card}` | `mem_info_gtt_total` | bytes |
| `node_drm_memory_gtt_used_bytes{card}` | `mem_info_gtt_used` | bytes |
| `node_drm_memory_vram_size_bytes{card}` | `mem_info_vram_total` | bytes |
| `node_drm_memory_vram_used_bytes{card}` | `mem_info_vram_used` | bytes |
| `node_drm_memory_vis_vram_size_bytes{card}` | `mem_info_vis_vram_total` | bytes |
| `node_drm_memory_vis_vram_used_bytes{card}` | `mem_info_vis_vram_used` | bytes |

All eight are emitted unconditionally from whatever the parse produced, so an
unreadable file shows up as `0`, **not as an absent series**. A `0` in
`gpu_busy_percent` is therefore ambiguous between "idle" and "the SMU does not
report it here" — which is exactly why the verification commands below exist.

From `hwmon` (labelled `chip="..."` and `sensor="..."`, which is why the names
are path-derived and not fixed):

| metric | source | note |
| --- | --- | --- |
| `node_hwmon_temp_celsius` | `temp1_input` | on-die GPU temperature; `temp2`/`temp3` are dGPU-only |
| `node_hwmon_power_average_watt` | `power1_average` | **whole package on an APU, CPU included** |
| `node_hwmon_power_input_watt` | `power1_input` | same caveat |
| `node_hwmon_in_volts` | `in0_input`, `in1_input` | GPU and northbridge (APU-only) |
| `node_hwmon_freq_freq_mhz` | `freq1_input` (+ `freq1_label`) | gfx clock; `freq2_input` (memory clock) is dGPU-only |

No fan metric: the iGPU has none, and the case fans are not on `amdgpu`'s hwmon.

### Expected to be absent or misleading on gfx1151 — needs on-host verification

**None of the following was observed on lumquat.** This was written on a Mac with
no access to the machine's sysfs, so each item is a prediction with the command
that settles it, not a finding. Do not put observed values in this table until
they have been read off the box.

| what | expectation | why | verify with |
| --- | --- | --- | --- |
| `gpu_busy_percent` | may read **0 always** | some APUs' SMU firmware does not populate it; values are SMU-computed | `cat /sys/class/drm/card*/device/gpu_busy_percent` idle, then under `llama-bench` load |
| which memory counter tracks the model | **unknown** out of VRAM / vis VRAM / GTT | on an APU the weights live in GTT (system RAM mapped for the GPU), not the BIOS carve-out `mem_info_vram_*` normally describes; `amdgpu.vis_vramlimit=102400` and `ttm.pages_limit=27787264` change what each reports | `grep . /sys/class/drm/card*/device/mem_info_*` before and after the qwen container loads |
| `mem_busy_percent` | present in sysfs, **not collected** | this version of node_exporter's `drm` collector does not read it | `cat /sys/class/drm/card*/device/mem_busy_percent` |
| per-engine utilisation, clocks, throttle reasons | **absent** | only in the binary `gpu_metrics` blob, which needs a decoder (`amdgpu_top`, `amd-smi`) — deliberately not deployed | `amdgpu_top -d -gm` on the box |
| GPU power alone | **absent** | `power1_*` is the whole APU package; there is no CPU/GPU split without the APU metrics table | compare `node_hwmon_power_average_watt` against an idle baseline |
| `freq2_input` (memory clock) | **absent** | dGPU-only in the kernel docs | `ls /sys/class/drm/card*/device/hwmon/hwmon*/freq*_input` |

When these are settled, record the **observed** values here and note the date and
kernel version; the table above is the list of questions, not the answers.

### Related

- `docs/architecture.md` — module layout (its kernel-parameter table is stale; see the drift note)
- `docs/plan.md` — the original build plan
- `docs/luks-unlock-strategy.md` — LUKS/TPM2 unlock
