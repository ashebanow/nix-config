# Container workloads move to Quadlet, via `mirkolenz/quadlet-nix`

Status: accepted (2026-09-19, BOX-141)

The four container surfaces — the local model server, the bifrost gateway, Open WebUI and the
memory stack — run today as `virtualisation.oci-containers` (the model) and three
`podman-compose` stacks driven by systemd units that read a symlinked compose file. They work,
but each is a third-party, opinionated configuration that must be managed on its own terms, and
they sit outside the module system: not expressible as Nix values, unable to cross-reference
networks or volumes, and invisible to capability flags. The compose stacks already needed a
`restartTriggers` workaround (BOX-139) because changing the symlinked YAML does not change the
unit text, leaving an old stack running.

The goal is declarativeness, not Quadlet for its own sake. Containers are the last part of this
configuration that is not Nix.

We decided: **all four surfaces move to Quadlet**, defined as NixOS module options, using
**`mirkolenz/quadlet-nix`**. The local model container goes first — it is the dependency whose
maintenance is most worrying — and it is a real migration rather than a spike: if we do it, we
do it completely. Done means the model still works through bifrost with equivalent performance,
measured with `llama-bench` before and after.

## Considered options

**microVM (`microvm.nix`).** Rejected: structurally impossible for this workload. Passthrough is
PCI/USB-only, with no way to share `/dev/dri` or `/dev/kfd`; the PCI path unbinds `amdgpu` in
favour of `vfio-pci` and hard-fails without an IOMMU group, and this host runs IOMMU-off; and AMD
documents ROCm virtualization for Instinct GPUs only. VFIO without an IOMMU would require the
kernel's unsafe no-IOMMU mode, which gives the guest unrestricted DMA into host memory — the
opposite of the isolation being sought.

**bubblewrap, or systemd sandboxing.** Device access is achievable — `--dev-bind` of `/dev/dri`
and `/dev/kfd` is what Flatpak does — but bwrap is a filesystem and permission boundary rather
than a kernel one, and there is no NixOS module for a long-running bwrap service. Where extra
isolation is wanted, systemd's own `DeviceAllow=char-drm rw` / `char-kfd rw` with
`DevicePolicy=closed` is the declarative mechanism, and it can be layered onto a Quadlet
container without changing the containerisation story.

**`SEIAROTg/quadlet-nix`.** Rejected despite far greater maturity — 395 stars and three years,
against thirteen stars and one maintainer. Two properties disqualify it here. It writes units for
Podman's generator to consume **at boot**, and that generator logs-and-skips units it cannot
parse, so an invalid unit silently does not exist — the worst available failure mode for a host
deployed unattended by Colmena. And its rootless support requires Home Manager; the
in-system-systemd mode it would need here is self-labelled "not officially supported by Podman".
The model container already runs rootless Podman as a non-root user from a *system* service,
which is exactly the shape `mirkolenz/quadlet-nix` supports natively.

**Leave the containers on compose and `oci-containers`.** Rejected: that is the condition this
decision exists to change.

## Consequences

- **Accepted risk: `mirkolenz/quadlet-nix` is small** — thirteen stars, one maintainer, eight
  months of history. Mitigations: pin a semver tag rather than the moving `v1` tag, so upstream
  releases arrive only when we take them; the module is pure Nix with no binary or daemon, so
  abandonment means forking a self-contained module rather than losing a runtime dependency; and
  both candidate modules expose `rawConfig`, so falling back to `SEIAROTg` is a mechanical
  rewrite of one module rather than a change of design.
- **`secretspec` has no wrapper in a Quadlet unit.** Today `ExecStart` wraps `podman-compose`
  with `secretspec run`; a generated unit has nothing to inject into. This must be settled before
  the first *compose* stack migrates — not before the model container, which consumes no secrets.
- **`docs/architecture.md` and `docs/plan.md` must be corrected.** Both describe a Quadlet
  architecture that was never built, including a `podman-base.nix` that does not exist.
- **The `podman-network-llm-internal` oneshot disappears**, replaced by a declaratively managed
  network, and the BOX-139 `restartTriggers` workaround becomes unnecessary for migrated stacks.
- **The other three surfaces follow.** This is the first of four, not a trial.
- **Performance is part of the contract.** `llama-bench` prefill and generation figures are taken
  before and after the model container migrates; a regression beyond measurement noise must be
  explained rather than absorbed.

Evidence for these choices: `docs/research/container-mechanisms.md`.
