This is the nix-config for ashebanow. The initial version we are building only covers our server configuration for our AI server, lumquat. Eventually we will add other servers and our unix and mac desktop configurations. It uses the dendritic pattern as described below.

# Hardware for Lumquat

GMKTec Evo X2 (Strix Halo mini PC):

- CPU/APU: AMD Ryzen AI Max (Strix Halo), `x86_64-linux`
- RAM: 128 GB unified (CPU + GPU share the same pool)
- GPU: AMD RDNA 3.5 integrated (`amdgpu`)
- LUKS-encrypted root (`/dev/mapper/luks-...`)
- Boot: systemd-boot + EFI

Kernel params must be set in `hardware-configuration.nix` on order for the Strix Halo to run LLMs properly:

- `amd_iommu=off` — required for Strix Halo stability
- `amdgpu.gttsize=126976` — expose ~124 GB VRAM to the GPU
- `ttm.pages_limit=32505856` — allow TTM to use the full pool

See [nix-strix-halo on github](https://github.com/hellas-ai/nix-strix-halo) for a collection of useful platform specific modules.

# Important References

There is a very in-depth config that follows the dendritic patter in [Fred Drake's nix config](../../dendritic-configs/fred-drake-nix), and another one worth looking at is is in [Mango's nix config](../../dendritic-configs/mango-nix). Finally, another article in blog form worth looking at is [Fiction Becomes Fact: NixOS Server Configuration](https://fictionbecomesfact.com/notes/nixos-server-configuration/) - its much simpler than the other two but has nice podman support plus monitoring, rdp, and so forth.

The fred-drake-nix config is also interesting because it has an extensive set of Claude Code agents, skills, and so forth, including a per-agent memory system. It would be nice to bring as much forward to our config as possible, using the pi agent instead of Claude Code.

# Project Goals

These goals are the be attempted one at a time, in order, and work on subsequent goals should not be started until we agree that the previous one is completely done and reliable.

Our goals for the project are, in order:

- Understand and document the important parts of the config, using the references above as a guide. The agent should ask as many clarifying questions as necessary to understand the project without assuming anything about needs.
- Convert necessary agents and skills etc from Claude to Pi, again asking clarifying questions as needed rather than assuming needs.
- Prepare a plan for implementing the first version of the config for lumpquat. It should include running LLMs in a containerized environment using podman and quadlets, include tailscale for ssh and remote access, include monitoring and the appropriate web UI for tracking llamma-cpp performance within the container(s) running the LLMs. It is expected that we will run the latest version of qwen-27B to handle most coding, with deepseek v4 to handle deep planning and multimodal.
- Using that plan, implement the first version of the config for lumpquat.

# Pi Skills and Commands

This project includes custom skills and prompt templates for the pi coding agent.

## Skills

Skills are loaded on-demand via `/skill:<name>`. They provide specialized workflows,
reference documentation, and helper patterns.

| Skill | Invocation | Purpose |
|-------|------------|---------|
| Nix Module | `/skill:nix-module` | Nix language and module system expert |
| Deploy | `/skill:deploy` | Colmena remote deployment specialist |
| Container | `/skill:container` | Container image management |
| Nix Debug | `/skill:nix-debug` | Service debugging via SSH |
| Secrets Audit | `/skill:secrets-audit` | Secrets management auditing |
| Nix Flake | `/skill:nix-flake` | Flake dependency management |
| Secrets | `/skill:secrets` | SOPS secrets workflow |
| Dend Arch | `/skill:dend-arch` | Architecture compliance review |
| Dend Feature | `/skill:dend-feature` | Feature module compliance |
| Dend Services | `/skill:dend-services` | Services layer review |

## Prompt Templates

Prompt templates are quick-invoke commands via `/<name>`. They expand into guidance
for common workflows.

| Template | Invocation | Purpose |
|----------|------------|---------|
| Deploy All | `/deploy-all` | Deploy to all hosts via Colmena |
| Dend Review (Arch) | `/dend-review-arch` | Pre-implementation architecture check |
| Dend Review (Features) | `/dend-review-features` | Feature module compliance review |
| Health Check | `/health` | Run health checks on lumquat |
| Update Containers | `/update-containers` | Container image update workflow |

## Skill Structure

Each skill includes:
- `SKILL.md` — Main skill definition with workflows and responsibilities
- `references/` — Detailed reference documentation

See individual skill documentation for specific patterns and best practices.

## Agent skills

### Issue tracker

GitHub issues in this repo (`ashebanow/nix-config`), via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default matt pocock vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context layout: AGENTS.md + docs/ for the dendritic module/capability-flag model. See `docs/agents/domain.md`.
