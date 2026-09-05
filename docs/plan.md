# Lumquat Implementation Plan

## Overview

This plan details the implementation of the lumquat NixOS configuration following the dendritic pattern. Modules are organized around user goals rather than technical components.

## Module Summary

| Module       | Type  | Purpose                                    |
| ------------ | ----- | ------------------------------------------ |
| `base`       | NixOS | Server foundation, non-root user           |
| `llm`        | NixOS | LLM containers, Aperture config generation |
| `access`     | NixOS | Tailscale, firewall, SSH fallback          |
| `secrets`    | NixOS | SOPS-nix, secret declarations              |
| `monitoring` | NixOS | Cockpit web UI                             |
| `cli-tools`  | HM    | CLI tools (eza, bat, aliases)              |

---

## Module Specifications

### 1. base Module

**Purpose**: Server basics — the foundation for all hosts.

**Options**:

```nix
my.base = {
  # Required
  username = "podman";  # Non-root user for containers

  # Optional
  timezone = "America/Los_Angeles";  # Default
  enableRemoteBuild = false;      # For future Colmena use
  packages = [];                  # Additional system packages
}
```

**Implementation Notes**:

- Creates `username` user with sudo access
- Enables `wheel` group membership
- Sets timezone
- Adds optional packages via `environment.systemPackages`
- Enables common utilities (btop, htop, etc.)

**Dependencies**: None

---

### 2. llm Module

**Purpose**: Run LLM inference servers with GPU passthrough.

**Options**:

```nix
my.llm = {
  enable = true;

  # Container definitions
  containers = [
    # Qwen3-70B with Q5_K_M (good quality, fits in ~54GB)
    {
      name = "qwen-coder";
      model = "qwen3-70b";
      quant = "q5_k_m";         # Better quality
      port = 8080;
      ctxSize = 131072;          # 128K context
    }

    # DeepSeek v4 MOE (better coding, Q4 for active experts)
    {
      name = "deepseek";
      model = "deepseek-v4-moe";
      quant = "q4_k_m";
      port = 8081;
      ctxSize = 163840;          # 160K+ context
    }
  ];

  # Quantization presets (adjust based on available VRAM):
  #   q2_k: ~30GB    q4_0: ~40GB    q5_k_m: ~54GB    q8_0: ~70GB
  # With 128GB unified memory, can run Q5-Q8 comfortably

  # Aperture integration
  enableAperture = true;

  # Storage
  modelStorage = "/var/lib/llm-models";  # Read-only mount into containers
}
```

**Auto-generated Aperture Config**:

```nix
# For each container, generates:
{ url = "http://127.0.0.1:${port}"; }
```

**Implementation Notes**:

- Enables Podman with quadlets (`virtualisation.podman.containers`)
- GPU passthrough: `devices = ["/dev/dri"]`
- Each container binds to `127.0.0.1` (local only)
- Containers run as non-root user (from `my.base.username`)
- Volumes: `${modelStorage}:/models:ro`
- Auto-generates Aperture upstream config if `enableAperture = true`

**Dependencies**: `base` (for username)

---

### 3. access Module

**Purpose**: Secure remote access via Tailscale.

**Flags** (flat `my.*` booleans in `lib/my-options-module.nix`, NixOS hosts only):

```nix
my.access = true;                     # enable the access feature (servers)
my.accessTailnetName = "lumquat";     # hostname on the tailnet
my.accessEnableSSH = true;            # Tailscale SSH (--ssh)
my.accessEnableExitNode = false;      # advertise as exit node (--advertise-exit-node)
my.accessEnableSubnetRouting = false; # advertise subnet routes (--advertise-routes=...)
my.accessSubnetRoutes = [];           # CIDRs, e.g. ["192.168.1.0/24"]
my.accessEnableFallbackSSH = true;    # sshd on non-standard port when tailscale is down
my.accessFallbackPort = 2222;
```

**Implementation Notes**:

- NixOS (`modules/features/access.nix`): `services.tailscale` with the nixpkgs
  module's built-in `tailscaled-autoconnect` (SOPS `tailscale-auth-key`).
  `useRoutingFeatures` is `"both"` when exit-node or subnet-routing is enabled,
  else `"client"` — serving routes never disables client routing features.
  Firewall: `checkReversePath = "loose"`, `trustedInterfaces = ["tailscale0"]`.
- macOS hosts: tailscale installed via the official **`.pkg` installer**, not
  nix or Homebrew — the MAS/Homebrew build is sandboxed and can't do Tailscale
  SSH, and the nixpkgs package won't start. `my.access` stays `false` on the Macs.
- Fallback SSH: separate sshd on non-standard port, limited to specific key.

**Dependencies**: `secrets` (for Tailscale auth key)

---

### 4. secrets Module

**Purpose**: Declarative secret management with SOPS-nix.

**Options**:

```nix
my.secrets = {
  # No exposed options - pure setup
}
```

**Secret Declarations** (generated from `secrets/secrets.yaml`):

```nix
sops.secrets = {
  "tailscale-auth-key" = {
    mode = "0640";
    group = "root";
    key = "data";
  };
  # Additional secrets added as needed
};
```

**Implementation Notes**:

- Sets up `sops-nix` with age keys
- Declares secrets from `secrets/secrets.yaml`
- Age key path: `/etc/nix/secrets/${host}.age`
- Generates key if not exists

**Directory Structure**:

```
secrets/
├── secrets.yaml         # Encrypted values
└── keys/
    └── lumquat.age     # Generated
```

**Dependencies**: None

---

### 5. monitoring Module

**Purpose**: Web-based system monitoring.

**Options**:

```nix
my.monitoring = {
  enable = true;
  port = 9090;
  # Cockpit accessible via Tailscale only
}
```

**Implementation Notes**:

- Enables `services.cockpit`
- Includes `cockpit-podman` package
- Firewall: restrict to `127.0.0.1` or Tailscale interface
- Accessible at `https://lumquat.tailnet:9090`

**Dependencies**: `access` (for Tailscale interface)

---

### 6. cli-tools Module (Home Manager)

**Purpose**: Modern CLI tools for developer productivity.

**Options**:

```nix
my.cliTools = {
  enable = true;

  # Core tools
  tools = {
    eza = true;     # Modern ls
    bat = true;      # Cat with syntax
    fd = true;       # Modern find
    ripgrep = true;  # Modern grep
    fzf = true;      # Fuzzy finder
  };

  # Shell aliases
  aliases = {
    ll = "eza -la";
    cat = "bat";
  };
}
```

**Implementation Notes**:

- Installs tools via `home.packages`
- Defines aliases in shell config
- Works for user from `my.base.username`

**Dependencies**: None (standalone)

---

## Directory Structure

```
lumquat/
├── flake.nix                    # Entry point
├── flake.lock
├── justfile                     # Build commands
├── CLAUDE.md                    # Claude guidance
├── AGENTS.md                    # Agent skills
├── docs/
│   ├── architecture.md          # Architecture doc
│   └── plan.md                 # This plan
├── lib/
│   └── my-options-module.nix   # Capability flags + module options
├── modules/
│   ├── infra/                   # flake-parts plumbing
│   │   ├── module-containers.nix    # deferredModule containers
│   │   ├── nixos-infra.nix         # NixOS system builder
│   │   ├── hm-infra.nix             # HM builder
│   │   └── colmena-config.nix       # Colmena config (for future)
│   └── features/                # Dendritic feature modules
│       ├── base.nix             # Server basics
│       ├── llm.nix              # LLM serving
│       ├── access.nix            # Remote access
│       ├── secrets.nix           # Secrets management
│       ├── monitoring.nix        # Cockpit
│       └── cli-tools.nix         # CLI tools (HM)
└── hosts/
    └── lumquat/
        ├── configuration.nix     # Host composition
        └── hardware-configuration.nix  # Generated
```

---

## Implementation Order

### Phase 1: Infrastructure

1. **flake.nix** — Entry point with flake-parts + import-tree
2. **lib/my-options-module.nix** — All option definitions
3. **modules/infra/module-containers.nix** — deferredModule containers
4. **modules/infra/nixos-infra.nix** — System builder
5. **modules/infra/hm-infra.nix** — HM builder

### Phase 2: Core Modules

6. **modules/features/base.nix** — Server basics
7. **modules/features/secrets.nix** — SOPS setup
8. **modules/features/access.nix** — Tailscale + SSH

### Phase 3: Application Modules

9. **modules/features/llm.nix** — LLM containers
10. **modules/features/monitoring.nix** — Cockpit
11. **modules/features/cli-tools.nix** — HM CLI tools

### Phase 4: Host Composition

12. **hosts/lumquat/configuration.nix** — Compose all modules
13. **hosts/lumquat/hardware-configuration.nix** — Kernel params, filesystems
14. **secrets/secrets.yaml** — Initial secret placeholders
15. **justfile** — Build commands

---

## Capability Flags (in my-options-module.nix)

```nix
options.my = {
  # Host identity
  hostName = lib.mkOption {
    type = lib.types.str;
    description = "Hostname";
  };

  # Base options
  base.username = lib.mkOption { ... };
  base.timezone = lib.mkOption { ... };
  base.enableRemoteBuild = lib.mkOption { ... };

  # LLM options
  llm.enable = lib.mkOption { ... };
  llm.containers = lib.mkOption { ... };
  llm.enableAperture = lib.mkOption { ... };
  llm.modelStorage = lib.mkOption { ... };

  # Access options
  access.enable = lib.mkOption { ... };
  access.tailnetName = lib.mkOption { ... };
  access.enableFallbackSSH = lib.mkOption { ... };

  # Monitoring options
  monitoring.enable = lib.mkOption { ... };
  monitoring.port = lib.mkOption { ... };

  # CLI tools
  cliTools.enable = lib.mkOption { ... };
  cliTools.tools = lib.mkOption { ... };
  cliTools.aliases = lib.mkOption { ... };
};
```

---

## Host Configuration Example

```nix
# hosts/lumquat/configuration.nix
{inputs, ...}: {
  configurations.nixos.lumquat = {
    system = "x86_64-linux";
    modules = [
      inputs.self.nixosModules.nixos-infra
      inputs.self.nixosModules.hm-infra
      inputs.self.nixosModules.base
      inputs.self.nixosModules.secrets
      inputs.self.nixosModules.access
      inputs.self.nixosModules.llm
      inputs.self.nixosModules.monitoring
      ./hardware-configuration.nix
    ];
  };

  # Host-specific settings
  config.my = {
    hostName = "lumquat";
    base.username = "podman";
    base.timezone = "America/New_York";

    llm.containers = [
      { name = "qwen-coder"; model = "qwen3-70b"; quant = "q5_k_m"; port = 8080; }
      { name = "deepseek"; model = "deepseek-v4-moe"; quant = "q4_k_m"; port = 8081; }
    ];
    llm.enableAperture = true;

    access.tailnetName = "lumquat";
    access.enableFallbackSSH = true;

    monitoring.enable = true;

    cliTools.enable = true;
  };
}
```

---

## Key Design Decisions

1. **Module cohesion**: Each module maps to a user goal
2. **Options over hardcoding**: All host-specific values are options
3. **Auto-generation**: LLM module auto-generates Aperture config from container list
4. **Non-root containers**: Podman runs as `podman` user, not root
5. **Tailscale-first**: All access through Tailscale with limited fallback
6. **Secrets separate**: Values in `secrets/`, declarations in `secrets.nix`

---

## Testing Checklist

- [ ] `nix flake check` passes
- [ ] `nix build .#nixosConfigurations.lumquat` builds
- [ ] User `podman` created with sudo access
- [ ] Podman containers start with GPU access
- [ ] LLM endpoints respond locally
- [ ] Tailscale connects
- [ ] Cockpit accessible via Tailscale
- [ ] SSH fallback works (for testing)
- [ ] CLI tools available for user

---

## Future Considerations

1. **Colmena deployment**: `colmena-config.nix` ready but not active
2. **Additional hosts**: Add to `modules/hosts/` and `colmena/` when ready
3. **More LLM models**: Just add to `llm.containers` list
4. **GPU monitoring**: Extend `monitoring` with GPU metrics
