# Secrets Management

## Architecture

Values live in **Bitwarden Secrets Manager (BWS)** — project **Homelab**.
Requirements are declared in the repo-root [`secretspec.toml`](../../../secretspec.toml).
There is no encrypted file in the repo and no sops-nix.

```
secretspec.toml                          # declarations + scopes
/var/lib/secrets/bws-access-token        # out-of-band bootstrap (root-only, 0600)
scripts/populate-host-secrets.sh         # host-scope file materialization
```

## Manifest format

```toml
[project]
name = "nix-config"
revision = "1.0"

[profiles.production]
DEEPSEEK_API_KEY = { description = "DeepSeek API key", required = true, ref = { item = "deepseek-api-key" } }

[scopes.litellm]
secrets = ["DEEPSEEK_API_KEY"]
```

## Adding a New Secret

1. Create the value in BWS (Homelab project), lowercased/dashed name.
2. Declare it in `secretspec.toml` under `[profiles.production]` with a `ref.item`.
3. Add it to the relevant `[scopes.<name>].secrets` allowlist.
4. Consume it via `secretspec run -P production -S <scope> -- …`.
5. Verify with `just secrets-check`.

## Scopes

| Scope | Consumer |
|-------|----------|
| `host` | `host-secrets-populate.service` |
| `litellm` | `litellm-compose.service` |
| `openwebui` | `openwebui-compose.service` |
| `memory` | `memory-compose.service`, `memory-health-check.service` |

## Security Notes

- Never commit plaintext secrets.
- The bootstrap token file is root-only (0600); provision via `just bootstrap-bws`.
- Prefer `secretspec run` (env injection) over `.env` files or podman-secret readback.
- File-backed consumers (tailscale, determinate-nixd) are the only secrets written to disk.
