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

# Development-safe: carries no production values.
[profiles.default]
DEVELOPMENT_PROFILE = { description = "Development profile marker", required = false, default = "development" }

# Every real secret. Standalone, so the development marker does not leak in.
[profiles.production.defaults]
inherit = false

[profiles.production]
DEEPSEEK_API_KEY = { description = "DeepSeek API key", required = true, ref = { item = "deepseek-api-key" } }
LUMQUAT_TAILSCALE_AUTH_KEY = { description = "Tailscale auth key for the lumquat node", required = true, ref = { item = "lumquat-tailscale-auth-key" } }

[scopes.bifrost]
secrets = ["DEEPSEEK_API_KEY"]

[scopes.host-lumquat]
secrets = ["LUMQUAT_TAILSCALE_AUTH_KEY", "FLAKEHUB_TOKEN", "CACHIX_AUTH_TOKEN"]
```

## Adding a New Secret

1. Create the value in BWS (Homelab project), lowercased/dashed name.
2. Declare it in `secretspec.toml` under `[profiles.production]` with a `ref.item`.
3. Add it to the relevant `[scopes.<name>].secrets` allowlist. A per-node secret
   gets a `<HOST>_...` name and its own `host-<host>` scope.
4. Consume it via `secretspec run -P production -S <scope> -- …`.
5. Verify with `just secrets-check "BOX-<n>: verify <secret>"` — agents must pass
   a reason (BOX-184); humans can omit it.

## Scopes

| Scope | Consumer |
|-------|----------|
| `host-<host>` | `host-secrets-populate.service` |
| `bifrost` | `bifrost-compose.service` |
| `openwebui` | `openwebui-compose.service` |
| `memory` | `memory-compose.service`, `memory-health-check.service` |

## Security Notes

- Never commit plaintext secrets.
- The bootstrap token file is root-only (0600); provision via `just bootstrap-bws`.
- Prefer `secretspec run` (env injection) over `.env` files or podman-secret readback.
- File-backed consumers (tailscale, determinate-nixd) are the only secrets written to disk.
