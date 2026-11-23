# What metrics do llama.cpp and the Strix Halo GPU expose?

Research for BOX-315 (map BOX-311, observability). Research date: 2026-11-23. Sources are
listed at the end. Lumquat is an AMD Strix Halo (RDNA 3.5, gfx1151 iGPU, 128 GB unified
memory), running llama.cpp in rootless podman containers (`modules/features/llm.nix`).

**Short answer.** llama.cpp's `--metrics` endpoint (already on in `llm.nix`) gives prompt and
generation token counters and times, throughput gauges, requests in flight and deferred
(queue), slot busyness, and speculative-decode acceptance. It no longer exposes KV-cache use.
For the GPU, node_exporter's `drm` collector (off by default) plus its `hwmon` collector (on by
default) read the amdgpu sysfs files and give busy %, VRAM/GTT used and total, temperature and
power. That is the low-maintenance path, already packaged in nixpkgs. AMD's
device-metrics-exporter targets Instinct and "Radeon AI" platforms, not APUs; amd-smi only
gained gfx1151 APU metrics in ROCm 7.13/7.14 while nixpkgs ships 7.2.4; `amdgpu_top` is a good
interactive tool but has no Prometheus exporter. `llm.nix` needs one change for a host-side
collector: the qwen container publishes no host port, so it must publish a loopback-only port
(or the collector must join the `llm-internal` network).

---

## 1. llama.cpp server `/metrics`

Verified against `ggml-org/llama.cpp` master, `tools/server/server-task.cpp`
(`server_task_result_metrics::to_metrics()`, last changed in commit `9197945`, 2026-11-20;
latest release tag `v1.0.0`, 2026-11-13) and `tools/server/README.md`.

Enabled by `--metrics` (env `LLAMA_ARG_ENDPOINT_METRICS`). Prometheus text format
(`text/plain; version=0.0.4`), no labels except the per-position spec-decode counter. Every
name has the `llamacpp:` prefix (a colon, which Prometheus allows in metric names but reserves
for recording rules by convention; scrapers accept it).

### Counters

| Metric | Meaning |
| --- | --- |
| `llamacpp:prompt_tokens_total` | Prompt tokens processed, excluding cache hits |
| `llamacpp:prompt_tokens_cached_total` | Prompt tokens reused from the cache (in source, missing from the README table) |
| `llamacpp:prompt_seconds_total` | Time spent on prompt processing |
| `llamacpp:tokens_predicted_total` | Generated tokens |
| `llamacpp:tokens_predicted_seconds_total` | Time spent generating |
| `llamacpp:n_decode_total` | `llama_decode()` calls (excludes speculative and multimodal decode) |
| `llamacpp:n_tokens_max` | Largest sequence length seen (prompt + generation). Typed `counter` but it is a high-water mark |
| `llamacpp:spec_decode_num_draft_tokens_total` | Draft tokens generated (0 when spec-decode is off) |
| `llamacpp:spec_decode_num_accepted_tokens_total` | Draft tokens accepted |
| `llamacpp:spec_decode_num_drafts_total` | Speculative verification steps |
| `llamacpp:spec_decode_num_accepted_tokens_per_pos_total{position="N"}` | Accepted tokens per draft position; absent until the first speculative request |

The spec-decode counters matter for us: the qwen model uses MTP (multi-token prediction), so
accepted/draft gives the MTP acceptance rate.

### Gauges

| Metric | Meaning |
| --- | --- |
| `llamacpp:prompt_tokens_seconds` | Average prompt throughput, tokens/s |
| `llamacpp:predicted_tokens_seconds` | Average generation throughput, tokens/s |
| `llamacpp:requests_processing` | Requests currently in a slot |
| `llamacpp:requests_deferred` | Requests waiting for a free slot (the queue depth) |
| `llamacpp:n_busy_slots_per_decode` | Average busy slots per decode call |

### Behaviour that affects collection

- **The throughput gauges reset on every scrape.** The handler calls `reset_bucket()` with the
  comment "the gauges are averaged over the window between two scrapes". With two scrapers
  (or a human `curl`) each sees a shorter window. Have exactly one scraper, and prefer
  `rate(llamacpp:tokens_predicted_total[5m]) / rate(llamacpp:tokens_predicted_seconds_total[5m])`
  over the gauges for dashboards.
- **No KV-cache metric.** `llamacpp:kv_cache_usage_ratio` and `llamacpp:kv_cache_tokens` were
  removed with llama.cpp PR #13660 ("kv-cache : simplify the interface"); the README was
  corrected in PR #22879 (2026-05). The nearest substitutes: `n_tokens_max` against the
  configured `-c`, and the `/slots` JSON endpoint (on by default, `--no-slots` disables it),
  which reports per-slot `n_ctx`, `is_processing` and token counts. `/slots` is JSON, so it
  would need a JSON exporter; not worth it for v1.
- **Sleep.** With `--sleep-idle-seconds` the server answers `/metrics` from cached values while
  asleep. `llm.nix` does not set it.
- **Several model containers.** Each container is its own llama-server with its own `/metrics`,
  and the output carries no model label. The collector must add one per target (e.g.
  `model="qwen-35b-a3b"`). In router mode (one llama-server, `--models-dir`/`--models-preset`)
  `/metrics` requires `?model=<id>` and returns 400 without it, so each model is still a
  separate scrape target.
- **Auth.** `/metrics` is unauthenticated here because `llm.nix` sets no `--api-key`.
- **Version drift.** The container is `kyuz0/amd-strix-halo-toolboxes:rocm-10.0`, which builds
  llama.cpp at some commit, not necessarily master. `prompt_tokens_cached_total` and the
  per-position spec-decode counter are recent; confirm with `curl` against the running
  container (section 4).

## 2. Strix Halo GPU

### What the kernel exposes (amdgpu sysfs)

From the kernel amdgpu docs (`driver-misc`, `thermal`), under `/sys/class/drm/cardN/device/`:

- `gpu_busy_percent`, `mem_busy_percent`: load percentages computed by SMU firmware.
- `mem_info_vram_total` / `_used`, `mem_info_vis_vram_total` / `_used`,
  `mem_info_gtt_total` / `_used`: bytes.
- `gpu_metrics`: binary snapshot of temps, clocks, engine use, power, throttle status; on
  APUs it also has CPU core stats. Needs a decoder (amdgpu_top, amd-smi).
- hwmon (`.../hwmon/hwmonN/`): `temp1_input` (on-die GPU temp; `temp2`/`temp3` are dGPU only),
  `in0_input` (GPU voltage), `in1_input` (northbridge voltage, APU only),
  `power1_average` / `power1_input` (microwatts; **"On APUs this includes the CPU"**),
  `freq1_input` (gfx clock; `freq2_input` memory clock is dGPU only). No fan on the iGPU.

**Unified memory caveat.** On an APU the model weights and KV cache mostly live in GTT
(system RAM mapped into the GPU), not in the BIOS carve-out that `mem_info_vram_*` normally
describes. Lumquat sets `amdgpu.vis_vramlimit=102400` and `ttm.pages_limit=27787264`
(`docs/lumquat-hardware.md`), so which counter actually moves when qwen loads (VRAM, visible
VRAM or GTT) is **not verified**; collect all six and check on the box. The ROCm Strix Halo
page describes GTT as the shared pool (default about 50% of RAM, raised via the TTM page limit)
and recommends a small carve-out. Also, `power1_*` is whole-package power, CPU included.

### Exporter candidates

| Candidate | What it gives | gfx1151 under NixOS | Verdict |
| --- | --- | --- | --- |
| **node_exporter `drm` + `hwmon` collectors** | `node_drm_gpu_busy_percent`, `node_drm_memory_vram_{size,used}_bytes`, `node_drm_memory_vis_vram_{size,used}_bytes`, `node_drm_memory_gtt_{size,used}_bytes`, `node_drm_card_info{chip,unique_id,...}`; hwmon gives `node_hwmon_temp_celsius`, `node_hwmon_power_average_watt` / `node_hwmon_power_input_watt`, `node_hwmon_in_volts`, `node_hwmon_freq_freq_mhz` labelled `chip="..."` | Reads only generic amdgpu sysfs files and skips any that are missing (procfs `class_drm_amdgpu.go` ignores read errors per field), so no ROCm or per-chip support needed. nixpkgs `prometheus-node-exporter` 1.12.1; NixOS `services.prometheus.exporters.node.enabledCollectors = [ "drm" ]` | **Use this.** Zero extra software; the node agent is wanted anyway for host health |
| AMD device-metrics-exporter (`ROCm/device-metrics-exporter`) | Rich `gpu_*` metrics via amd-smi/gpuagent | Docs list MI2xx/MI3xx (ROCm 6.2+) and "MI350P or Radeon AI platform" (ROCm 7.13+), Ubuntu 22.04/24.04, Helm/Slurm/container deploy. No APU mention. Not in nixpkgs | **No.** Wrong target hardware, heavy |
| `amdgpu_top` | Decodes `gpu_metrics`, GRBM counters, per-process VRAM/GTT via fdinfo; `-J`/`--json`, `--json_fifo`, `--smi`; has `--apu` | Reads the amdgpu driver directly, so no ROCm needed; nixpkgs `amdgpu_top` 0.11.5. README does not mention gfx1151 | **Keep as the interactive tool.** No Prometheus mode; only reachable via a JSON-to-textfile script, and the README warns that GRBM counter reads can stop the GPU power-saving (`--no-pc` disables them) |
| amd-smi / rocm-smi | Decoded metrics incl. APU table | amdsmi changelog: APU metrics added in ROCm 7.13 (gpu_metrics tables 2.4/3.0), APU temp/clock fallbacks in 7.14, and a 7.13 fix for N/A clocks "on gfx1151-class APUs". nixpkgs `rocmPackages.amdsmi` is 7.2.4, older than all of that | **No for v1.** Would mean a host ROCm userspace newer than nixpkgs carries, or running it inside the toolbox container |

## 3. Does `llm.nix` need changes?

Yes, one: the qwen container sets `ports = [ ]` and is reachable only as `qwen-35b-a3b:8080`
on the rootless `llm-internal` bridge. Rootless podman bridges live in the podman user's
network namespace, so a collector running on the host cannot reach that address. Options:

1. **Publish loopback-only**, e.g. `ports = [ "127.0.0.1:<port>:8080" ]`, and scrape
   `127.0.0.1:<port>/metrics` from the host collector. Smallest change; still not on the LAN
   or tailnet. Each model container needs its own host port. (Recommended.)
2. Run the collector agent as a container on `llm-internal`. Ties the collector to podman.
3. Scrape through bifrost. Bifrost proxies the OpenAI API, not `/metrics`; not an option.

`--metrics` is already in `baseFlags`, so no flag change is needed. GPU metrics need no
container change; they come from host sysfs.

This change belongs to the implementation ticket, not this research. `llm.nix` was not changed.

## 4. Verify on lumquat before relying on this

None of the following was run on the hardware; do it during implementation:

```sh
# llama.cpp: which metric names this image's build exposes
podman exec qwen-35b-a3b curl -s http://127.0.0.1:8080/metrics | grep '^llamacpp'
# GPU: which files exist and which counter moves when the model loads
cd /sys/class/drm/card*/device && grep . gpu_busy_percent mem_busy_percent mem_info_*
grep . hwmon/hwmon*/{name,temp*_input,temp*_label,power1_*,in*_input,freq*_input} 2>/dev/null
amdgpu_top -d -gm   # decoded gpu_metrics, to see what the SMU reports on gfx1151
```

Run the first command as the podman user (rootless). Check `gpu_busy_percent` is non-zero
under load; on some APUs it reads 0.

## Unverified

- That `gpu_busy_percent`, `mem_busy_percent` and the hwmon temp/power files are populated on
  gfx1151 (SMU 14). Kernel docs describe them generically; no gfx1151-specific source found.
- Which of VRAM / visible VRAM / GTT counters reflects the model's memory under lumquat's
  `vis_vramlimit` + `ttm.pages_limit` settings.
- The llama.cpp commit inside `kyuz0/amd-strix-halo-toolboxes:rocm-10.0`, and so the exact
  metric set.
- Whether newer amd-smi (7.14+) gives anything node_exporter does not, e.g. separate GPU vs CPU
  power from the APU metrics table.
- node_exporter `drm` collector names were read from master; the collector predates 1.12.1 but
  the name set in 1.12.1 itself was not diffed.

## Sources

- llama.cpp `tools/server/server-task.cpp` (`to_metrics`) and `tools/server/server-context.cpp`
  (`get_metrics` handler):
  https://github.com/ggml-org/llama.cpp/tree/master/tools/server
- llama.cpp server README, `/metrics`, `/slots`, router mode, sleeping:
  https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md
- llama.cpp PR #22879 (README fix, lists removed KV metrics and PR #13660):
  https://github.com/ggml-org/llama.cpp/pull/22879
- Kernel amdgpu docs: https://docs.kernel.org/gpu/amdgpu/driver-misc.html and
  https://docs.kernel.org/gpu/amdgpu/thermal.html
- node_exporter `collector/drm_linux.go`, `collector/hwmon_linux.go`:
  https://github.com/prometheus/node_exporter/tree/master/collector
- prometheus/procfs `sysfs/class_drm_amdgpu.go`:
  https://github.com/prometheus/procfs/blob/master/sysfs/class_drm_amdgpu.go
- AMD device-metrics-exporter: https://github.com/ROCm/device-metrics-exporter and
  https://instinct.docs.amd.com/projects/device-metrics-exporter/en/latest/
- amdgpu_top README: https://github.com/Umio-Yasuno/amdgpu_top
- AMD SMI changelog (ROCm 10.0 docs):
  https://rocm.docs.amd.com/projects/amdsmi/en/docs-10.0.0/reference/changelog.html
- ROCm Strix Halo system optimization:
  https://rocm.docs.amd.com/en/docs-10.0.0/how-to/system-optimization/strixhalo.html
- nixpkgs versions (unstable, via search.nixos.org): `prometheus-node-exporter` 1.12.1,
  `amdgpu_top` 0.11.5, `rocmPackages.amdsmi` 7.2.4
