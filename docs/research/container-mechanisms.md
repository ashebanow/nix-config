# Replacing `podman-compose` / `virtualisation.oci-containers` with Nix-native mechanisms

Research date: 2026-09-19. Evaluated against four workloads on lumquat (Strix Halo, gfx1151):
GPU LLM model server, gateway, web UI, memory service. Source list at the end.

---

## 1. quadlet-nix, two implementations

Two independent modules, same name and goal. mirkolenz's README says it was "inspired by
the excellent work of SEIAROTg, but rewritten from scratch".

| | SEIAROTg | mirkolenz |
|---|---|---|
| Created / stars | 2023-08-28 / 395 | 2025-01-10 / 13 |
| Last commit | 2026-08-02 | 2026-09-14 |
| Releases | **none — `git ls-remote --tags` returns zero tags** | semver `v1.2`…`v1.5.2`, latest 2026-09-02 |
| Open issues | 3 human (#63, #62, #42) | 2, both bots |
| Validation | typed options at eval; units written to `/etc/containers/systemd`, **generator runs at boot** | **build-time**: patched `quadlet` generator runs in a derivation and asserts every expected `.service` was emitted |
| Rootless | via Home Manager; in-system-systemd mode marked "not officially supported by Podman" | directly from the NixOS module via `uid` (`systemd.user.services` + `ConditionUser=`) |
| Images | `images`/`builds` units, `dockerTools` via `docker-archive:` | `imageFile`/`imageStream` (Nix-built), `image`, experimental `artifact` |
| Networking | typed `networks`/`pods`, `X.ref` cross-refs, `ShmSize`, `UserNS` | freeform `Network`/`Pod` sections; refs scoped per `uid` |

SEIAROTg's open issues are narrow: `podman-user-wait-network-online.service` broken off-NixOS
(#63), a race with ephemeral root filesystems (#62), unit specifiers (#42).

**Validation detail that matters.** SEIAROTg writes plain files and lets Podman's generator
run at boot; that generator *logs and skips* invalid units, so a rejected unit silently does
not exist (it patches around change detection with `X-QuadletNixConfigHash`). mirkolenz runs
the generator at build time and aborts if a unit is missing. Its freeform PascalCase keys give
full upstream coverage (`AddDevice`, `ShmSize`, `SecurityLabelDisable`) at the cost of per-field
type checking.

**Recommendation: mirkolenz**, for three reasons tied to this repo. (1) lumquat's switches are
scripted (`just switch` → `nh os switch`) rather than watched, so build-time validation turns a
silently-missing service into a failed build. (2) `modules/features/llm.nix` already runs rootless Podman as `cfg.baseUsername` from
a *system* service — mirkolenz supports that with a plain `uid`, while SEIAROTg's equivalent
is explicitly unsupported by its own README. (3) Semver tags and a changelog give a pinnable
dependency; SEIAROTg has none.

Caveat, stated plainly: 13 stars, eight months of history, one maintainer, no typed options.
SEIAROTg is the conservative choice (three years, 395 stars, much larger test suite). Both
expose `rawConfig`, so trying one and falling back is cheap.

---

## 2. microvm.nix for GPU compute: no

**This is not known to work for ROCm on gfx1151 anywhere I could find, and the blocker is
structural rather than incidental.**

- microvm.nix passthrough is **PCI or USB only** (`microvm.devices = [ { bus = "pci"; path = "…"; } ]`).
  There is no way to share `/dev/dri` or `/dev/kfd`; a repo-wide grep for `kfd` finds nothing.
- PCI passthrough unbinds the device from `amdgpu`, binds `vfio-pci`, and the setup script does
  `[[ -e iommu_group ]] || exit 1` — it hard-fails without an IOMMU. The host loses the GPU
  entirely while the VM runs.
- **AMD documents ROCm virtualization only for Instinct GPUs.** The ROCm 10.0 compatibility
  matrix's "GPU virtualization support" table (KVM/ESXi passthrough, SR-IOV + GIM driver) lists
  MI355X/350X/350P/325X/300X only. ROCm's GPU-isolation page describes VM passthrough as PCIe
  passthrough and says "ROCm supports VMware ESXi for select GPUs". Nothing covers an APU iGPU
  in a KVM guest.
- Strix Halo compounds this: the iGPU shares the die with the CPU. A Qubes report on a
  Ryzen AI MAX+ 395 shows `AMD-Vi: Error initialization` and states no IOMMU devices can be
  passed through (Xen, same silicon). microvm.nix #410 shows Intel iGPU passthrough hitting
  QEMU's iGPU special-casing — precedent that iGPU passthrough is not the generic PCI case.
- **This repo's kernel params conflict with VFIO.** AGENTS.md mandates `amd_iommu=off`;
  nix-strix-halo defaults `requireIommuOff = true` because "IOMMU translation measurably slows
  GPU-memory workloads". VFIO without IOMMU needs `enable_unsafe_noiommu_mode`, which the kernel
  docs call "unsafe DMA … w/o physical IOMMU protection" — the guest gets unrestricted DMA into
  host memory, destroying the isolation you wanted. microvm.nix does not expose it.

**Counter-evidence, for honesty:** `antirez/ds4` PR #871 runs successfully on Strix Halo with
`iommu.passthrough=0` (IOMMU *active*), arguing `amd_iommu=off` is unnecessary and costs you the
NPU. So "IOMMU must be off" is contested — but IOMMU-group assignment and iGPU passthrough are
the unproven parts regardless.

**Isolation boundary.** microvm.nix's own framing: VMs "run their own OS kernel, reducing the
attack surface to the hypervisor and its device drivers", and the project is "intended to
provide a more isolated alternative to `nixos-container`". That is a real kernel boundary — but
VFIO passthrough reintroduces a guest→host DMA path, and microvm.nix's only GPU-adjacent feature
is `microvm.qemu.vulkan = "venus"` (virtio-gpu, display/Vulkan, no HIP), which itself drew a
report (#431) of GL/Vulkan falling back to CPU `llvmpipe`.

---

## 3. bubblewrap / systemd sandboxing

**Device access works; bwrap is the weaker tool here, and systemd directives are the cleaner
declarative pattern.**

- bwrap mounts a fresh devtmpfs via `--dev`; device access must be granted with
  `--dev-bind SRC DEST` ("Bind mount the host path SRC on DEST, allowing device access").
- Flatpak — bwrap for long-running GPU apps — `--dev-bind`s `/dev/dri`, `/dev/udmabuf`, `/dev/kfd`
  (plus Nvidia nodes) under `FLATPAK_CONTEXT_DEVICE_DRI`, and `--bind`s the realpath of `/dev/shm`
  under `FLATPAK_CONTEXT_DEVICE_SHM`. So `/dev/dri`, `/dev/kfd`, `/dev/shm` are all fine.
- The host's ROCm userspace is a non-issue: bwrap does not virtualize libraries, and the sandbox
  shares the host kernel, so the same `amdgpu`/KFD driver is reached through the bound node. That
  makes it a **filesystem/permission boundary, not a kernel boundary** — comparable to a container.
  Note the workload currently needs `--security-opt seccomp=unconfined`; a tighter filter would be
  new work. bwrap also requires unprivileged user namespaces (setuid mode removed), exposed on
  NixOS as `security.allowUserNamespaces` (default true).
- **There is no NixOS module for a long-running bwrap service.** nixpkgs uses bwrap for build FHS
  environments, Flatpak/Steam wrappers, and a session script in `programs/opengamepadui.nix`.
  The clean declarative pattern for *services* is systemd itself, via freeform
  `systemd.services.<n>.serviceConfig`: `DeviceAllow=` filters device access with eBPF and accepts
  `char-<group>` names. The kernel registers char regions named `drm` and `kfd`, so
  `DeviceAllow=char-drm rw` / `char-kfd rw` are the specifiers. Do **not** set `PrivateDevices=yes`
  for GPU units — it creates a `/dev` with only API pseudo devices and removes `/dev/dri` and
  `/dev/kfd`; the docs say to use `DeviceAllow=` instead "when access to some but not all devices
  must be possible". Combine with `BindReadOnlyPaths=`, `TemporaryFileSystem=`, `PrivateTmp=`.

---

## 4. Per-workload recommendation

| Workload | Mechanism | Confidence |
|---|---|---|
| GPU LLM model server (llama.cpp/ROCm) | **Quadlet** — `AddDevice=/dev/dri`, `AddDevice=/dev/kfd`, `GroupAdd=video`/`render`, `ShmSize` | High — already proven on this box |
| Gateway (bifrost + tailscale) | **Quadlet Pod** — `network_mode: service:tailscale` maps to a shared netns | High |
| Web UI (open-webui + tailscale) | **Quadlet Pod** | High |
| Memory service (mnemosyne + tailscale) | **Quadlet Pod + Nix-built image** | High — replaces unpinned `:latest` |

Podman/Quadlet wins for all four because it is the only mechanism already demonstrated on
gfx1151, and because ROCm's own docs give it the strongest documented GPU-isolation guarantee
short of a VM: container isolation "applies to all programs that use the `amdgpu` kernel module
interfaces", and "even programs that don't use the ROCm runtime … can only access the GPUs
exposed to the container". It also maps 1:1 onto the existing compose files and removes the
`restartTriggers`/symlinked-compose fragility noted in `modules/features/llm.nix`. microvm.nix
is not a candidate for any of them.

Two design consequences: the tailscale sidecar's `cap_add: NET_ADMIN` and `/dev/net/tun` become
`AddCapability=`/`AddDevice=` (both modules pass these through, but see below); and quadlet units
have no wrapper for `secretspec run`, which today wraps `podman-compose` in `ExecStart` — that
needs a decision (`Secret=` + systemd credential, or a small `ExecStartPre`).

### Unproven / needs a spike

1. **ROCm in a microVM on gfx1151 — unproven, no report found.** Blocked on IOMMU/VFIO, and AMD
   documents virtualization for Instinct only. Do not plan around it.
2. **Whether IOMMU can stay enabled on lumquat while ROCm performs acceptably.** Repo says off;
   a community report on the same silicon says active IOMMU works. Measure it.
3. **`DeviceAllow=char-kfd` / `char-drm` on this kernel.** Mechanism documented; specifier names
   inferred from the kernel's `register_chrdev` calls, not verified here. Spike: `grep -E 'drm|kfd'
   /proc/devices`, then a test unit with `DevicePolicy=closed` running `rocminfo`.
4. **HIP under bwrap.** Flatpak proves `/dev/dri` + `/dev/kfd` binding for *graphics*; Flatpak does
   not run HIP and I found no report of HIP under bwrap. Spike: `bwrap --dev-bind /dev/kfd …
   rocminfo`.
5. **Quadlet parity for the sidecar** (`AddCapability=NET_ADMIN`, `AddDevice=/dev/net/tun`,
   persistent state volume) — neither module documents this combination.
6. **Destructive risk of PCI passthrough trials**: attempting a microVM spike unbinds the GPU from
   the host, so it must not be attempted on the production host without a rollback path.

---

## Sources

quadlet-nix
- https://github.com/SEIAROTg/quadlet-nix · /blob/main/README.md · /blob/main/nixos-module.nix · /blob/main/options.nix · /issues/63 · /issues/62 · /issues/42
- https://github.com/mirkolenz/quadlet-nix · /blob/main/README.md · /blob/main/lib.nix · /blob/main/pkgs/quadlet.nix · /blob/main/modules/nixos.nix · /blob/main/dev/tests/nixos.nix · /releases · /issues/25 · /issues/79
- https://mirkolenz.github.io/quadlet-nix/index.html
- https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html

microvm.nix
- https://github.com/microvm-nix/microvm.nix · /blob/main/doc/src/devices.md · /blob/main/doc/src/options.md · /blob/main/doc/src/intro.md · /blob/main/nixos-modules/microvm/pci-devices.nix · /issues/431 · /issues/410 · /issues/57

ROCm / AMD
- https://rocm.docs.amd.com/en/latest/compatibility/compatibility-matrix.html
- https://rocm.docs.amd.com/en/latest/about/release-notes.html
- https://github.com/ROCm/rocm-docs/blob/develop/docs/reference/system-optimization/gpu-isolation.md
- https://github.com/amd/MxGPU-Virtualization

VFIO / kernel
- https://www.kernel.org/doc/html/latest/driver-api/vfio.html
- https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/amd/amdkfd/kfd_chardev.c
- https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/drm_drv.c

Strix Halo community evidence
- https://github.com/QubesOS/qubes-issues/issues/10931
- https://github.com/hellas-ai/nix-strix-halo/blob/main/modules/benchmark-runner.nix
- https://github.com/hellas-ai/nix-strix-halo/blob/main/modules/fastflowlm.nix
- https://github.com/antirez/ds4/pull/871
- https://github.com/kyuz0/amd-strix-halo-toolboxes

bubblewrap / systemd
- https://github.com/containers/bubblewrap/blob/main/README.md · /blob/main/bwrap.xml
- https://github.com/flatpak/flatpak/blob/main/common/flatpak-run.c
- https://www.freedesktop.org/software/systemd/man/latest/systemd.exec.html
- https://www.freedesktop.org/software/systemd/man/latest/systemd.resource-control.html
- https://github.com/NixOS/nixpkgs/blob/master/pkgs/build-support/build-fhsenv-bubblewrap/default.nix
- https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/security/misc.nix

NixOS containers
- https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/virtualisation/oci-containers.nix
- https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/virtualisation/podman/default.nix
