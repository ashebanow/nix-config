# Secrets Management

## Architecture

This project uses **inline SOPS** — secrets are managed directly in the
NixOS flake, NOT in a separate secrets repository.

```
secrets/
├── secrets.yaml         # Encrypted secret values
└── keys/
    └── lumquat.age      # Age key for this host
```

## SOPS YAML Format

```yaml
tailscale-auth-key: |
  tskey-auth-k8sABC123...
llm-serve-env: |
  API_KEY=secret123
```

## Adding a New Secret

1. **Create the secret file** (encrypted):
   ```bash
   # Edit encrypted secrets
   sops secrets/secrets.yaml
   ```

2. **Declare in module**:
   ```nix
   sops.secrets.my-new-secret = {
     mode = "0400";
     key = "data";
   };
   ```

3. **Use at runtime**:
   ```nix
   # Via environmentFile
   environmentFile = [config.sops.secrets.my-new-secret.path];

   # Via template
   content = "API_KEY=${config.sops.placeholder.my-new-secret}";
   ```

## Age Key Management

```bash
# Generate new age key
ssh-to-age -i ~/.ssh/id_ed25519 > secrets/keys/lumquat.age

# Or generate standalone key
age-keygen -o secrets/keys/lumquat.age
```

## Common Secret Names

| Secret | Purpose |
|--------|---------|
| `tailscale-auth-key` | Tailscale authentication |
| `llm-serve-env` | Environment for LLM containers |

## Security Notes

- Never commit plaintext secrets
- Age keys should have restrictive permissions: `600`
- Secrets at `/run/secrets/` are readable by root only
