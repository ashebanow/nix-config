---
name: secrets
description: |
  Add, remove, or modify SOPS secrets. Use when: (1) Adding a new secret for
  a service or tool, (2) Removing a deprecated secret, (3) Wiring a secret
  into a configuration, (4) Understanding how secrets flow into the system.
---

# Secrets Management

## Architecture Overview

Secrets are managed with **sops-nix** directly in this flake (inline, no separate repo):

1. **Encrypted files**: `secrets/secrets.yaml` — encrypted YAML with secret values
2. **Age keys**: `secrets/keys/lumquat.age` — encryption key for this host
3. **Declarations**: NixOS modules declare `sops.secrets` to expose secrets

## Secrets Directory

```
secrets/
├── secrets.yaml         # Encrypted secret values
└── keys/
    └── lumquat.age      # Age key for lumquat
```

## Two Types of Secrets

### Service Secrets (NixOS)

Used for system services, mounted at `/run/secrets/`:

```nix
sops.secrets.my-service-secret = {
  mode = "0400";
  key = "data";  # Key in the YAML file
};
```

### Container Secrets

Used in podman containers via `environmentFile`:

```nix
virtualisation.podman.containers.my-app = {
  environmentFile = [config.sops.secrets.my-secret.path];
};
```

## Step-by-Step: Adding a New Secret

### 1. Edit Encrypted Secrets

```bash
# Decrypt and edit (requires SOPS_AGE_KEY_FILE)
SOPS_AGE_KEY_FILE=secrets/keys/lumquat.age sops secrets/secrets.yaml
```

Add the secret value:
```yaml
my-new-secret: |
  secret-value-here
```

### 2. Declare in Module

In the appropriate feature module:
```nix
sops.secrets.my-new-secret = {
  mode = "0400";
  key = "data";
};
```

### 3. Use the Secret

```nix
# As environment file
environmentFile = [config.sops.secrets.my-new-secret.path];

# Or in container
virtualisation.podman.containers.myapp = {
  environmentFile = [config.sops.secrets.my-new-secret.path];
};
```

### 4. Deploy

```bash
colmena apply --on lumquat --impure
```

## Step-by-Step: Removing a Secret

1. Remove the `sops.secrets.<name>` declaration from modules
2. Remove references to `config.sops.secrets.<name>`
3. Edit `secrets/secrets.yaml` to remove the entry
4. Deploy

## Age Key Management

### Generate Age Key

```bash
# From SSH key (preferred)
ssh-to-age -i ~/.ssh/id_ed25519 -private-key > secrets/keys/lumquat.age

# Or standalone
age-keygen -o secrets/keys/lumquat.age
```

### Verify Key

```bash
cat secrets/keys/lumquat.age
# Output should be: AGE-SECRET-KEY-1...
```

## Common Secrets for Lumquat

| Secret | Purpose |
|--------|---------|
| `tailscale-auth-key` | Tailscale VPN authentication |
| `llm-serve-env` | Environment variables for LLM containers |

## See Also

- [secrets-audit](/skill:secrets-audit) — Secrets auditing

## Important Notes

- Never output actual secret values
- Age keys must have `600` permissions
- Secrets at `/run/secrets/` are root-only readable
- Use `key = "data"` for single-value secrets
- Use descriptive names: `service-description-format`
