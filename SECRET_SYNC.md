# Secrets: BWS + SecretSpec

nix-config no longer uses sops-nix. All secrets live in **Bitwarden Secrets Manager
(BWS)** (project: **Homelab**), declared in the single repo-root
[`secretspec.toml`](./secretspec.toml) and resolved at runtime with **SecretSpec**.
Nothing in git or the Nix store holds a secret value.

## Architecture

```
┌────────────────────────────────────────────────────────────────┐
│ BWS — "Homelab" project (single source of truth)              │
│   lumquat-tailscale-auth-key, litellm-tailscale-auth-key,     │
│   litellm-db-password, mnemosyne-mcp-token, deepseek-api-key, │
│   anthropic-api-key-pi, minimax-api-key, ...                  │
└───────────────────────────────┬────────────────────────────────┘
                                │ bws://vault.bitwarden.com@<project>
                                │
                    ┌───────────▼────────────┐
                    │  secretspec.toml (git) │  declarations + scopes only
                    │  [profiles.production] │
                    │  [scopes.*]            │
                    └───────────┬────────────┘
                                │ secretspec run -P production -S <scope>
                                │
        ┌───────────────────────┼───────────────────────────────┐
        │                       │
        ▼                       ▼
  host-secrets-populate   compose services
  (root, -S host)         (podman user)
  writes 2 files:         secretspec run injects
  /run/secrets/tailscale  env vars straight into
  /run/secrets/flakehub   podman-compose (no files)
        │                       │
        ▼                       ▼
  tailscale authKeyFile   litellm / openwebui /
  determinate-nixd token  mnemosyne containers
```

### Scopes (least privilege)

Each consumer resolves only its own scope of the shared `production` profile:

| Scope | Secrets | Consumer |
|-------|---------|----------|
| `host` | `TAILSCALE_AUTH_KEY`, `FLAKEHUB_TOKEN` | `host-secrets-populate.service` (root) |
| `litellm` | `TS_AUTHKEY`, `LITELLM_MASTER_KEY`, `LITELLM_DB_PASSWORD`, `DEEPSEEK_API_KEY`, `ANTHROPIC_API_KEY`, `MINIMAX_API_KEY` | `litellm-compose.service` |
| `openwebui` | `OPENWEBUI_TS_AUTHKEY`, `LITELLM_MASTER_KEY` | `openwebui-compose.service` |
| `memory` | `MEMORY_TS_AUTHKEY`, `MNEMOSYNE_MCP_TOKEN` | `memory-compose.service`, `memory-health-check.service` |

### Provider routing

No per-secret providers — chosen at invocation via `SECRETSPEC_PROVIDER`:

- **systemd services**: `SECRETSPEC_PROVIDER=bws-service`. The BWS access token is
  delivered as a systemd credential named `access_token` (via `LoadCredential`)
  from `/var/lib/secrets/bws-access-token`, read through the
  `systemd-credential://` bootstrap provider. See `[providers]` in
  `secretspec.toml`.
- **operator / dev shell**: `SECRETSPEC_PROVIDER=bws` + `BWS_ACCESS_TOKEN` in the
  environment.

## The BWS bootstrap token (the only local secret)

The BWS access token (a machine-account token for the **chezmoi** machine account
in the Homelab project) is the one secret that cannot itself come from BWS. It is
provisioned **once, out-of-band**, as a root-only file:

```
/var/lib/secrets/bws-access-token   (mode 0600, root:root)
```

It is **not** in git, not in the Nix store, and not in `/etc` at a glance-able
top level. Every secret-consuming systemd service loads it via
`LoadCredential=access_token:/var/lib/secrets/bws-access-token`.

### Bootstrap on a new machine

```bash
# from a dev machine (prompts for the token, never echoes it):
just bootstrap-bws lumquat

# or directly:
ssh root@lumquat 'install -d -m 0700 /var/lib/secrets && \
  install -m 0600 -o root -g root /dev/stdin /var/lib/secrets/bws-access-token' \
  < <(printf '%s' '0.abc123...')
```

The token is created in the BW web console: **Secrets Manager → Homelab →
Machine Accounts → chezmoi → Access Tokens**.

Until this file exists, `host-secrets-populate` (and the other secret-consuming
services) will fail loudly at boot — that is the intended fail-safe.

## How secrets flow (per service)

### Host secrets (tailscale, flakehub) — file-backed consumers

`tailscale` (`authKeyFile`) and `determinate-nixd` (`--token-file`) both require a
file interface, so these are the **only** two secrets written to disk:

`host-secrets-populate.service` (root, `modules/features/secrets.nix`) runs
`secretspec run -P production -S host -- scripts/populate-host-secrets.sh`, which
writes:

- `/run/secrets/tailscale-auth-key` (0600) → `services.tailscale.authKeyFile`
- `/run/secrets/flakehub-token` (0600) → `flakehub-nixd-auth.service --token-file`

### Container secrets (litellm, openwebui, memory) — no files

The podman-compose systemd services (`litellm-compose`, `openwebui-compose`,
`memory-compose`) run `secretspec run -P production -S <scope> -- podman-compose
up -d`. SecretSpec injects the scope's values straight into the process
environment; podman-compose substitutes them into `compose.yml`. **No `.env`
file, no podman-secret readback** — values exist only in the process env.

The periodic `memory-health-check` resolves `MNEMOSYNE_MCP_TOKEN` the same way.

## Dev shell

`shell.nix` / `modules/infra/devshell.nix` load API keys for the **dev machine**
(e.g. `DEEPSEEK_API_KEY`, `EXA_API_KEY`, `ANTHROPIC_API_KEY`) from BWS into a
24h-cached env file. There is no sops fallback — the shell hook requires
`BWS_ACCESS_TOKEN` in the environment (set by `~/.zshenv` via chezmoi) or a
prior `bws login`.

## Adding or rotating a secret

1. **Create/update the value in BWS** (Homelab project). Naming convention: env
   var lowercased, service prefix, underscores → dashes
   (e.g. `litellm-db-password`).
2. **Declare it** in `secretspec.toml` under `[profiles.production]`, and add it
   to the relevant `[scopes.<name>].secrets` list.
3. **Consume it** in the module via `secretspec run` (container service) or the
   host populate script (file-backed consumer).
4. **Verify**: `just secrets-check` (requires `BWS_ACCESS_TOKEN`).
5. **Rotate the bootstrap token**: re-run `just bootstrap-bws <host>` and
   `systemctl restart host-secrets-populate` (then restart the consuming
   services).

## BWS item inventory (Homelab project)

| BWS item key | Used by |
|--------------|---------|
| `lumquat-tailscale-auth-key` | host `tailscale` (node auth) |
| `flakehub_bergamot_token` | `determinate-nixd` cache auth |
| `litellm-tailscale-auth-key` | litellm tailscale sidecar |
| `LiteLLM Master Key` | litellm + openwebui |
| `litellm-db-password` | litellm postgres |
| `deepseek-api-key` | litellm |
| `anthropic-api-key-pi` | litellm |
| `minimax-api-key` | litellm |
| `OpenWebUI TS Auth Key` | openwebui tailscale sidecar |
| `mnemo-tailscale-auth-key` | mnemosyne tailscale sidecar |
| `mnemosyne-mcp-token` | mnemosyne MCP auth |

> The `LiteLLM Master Key` / `OpenWebUI TS Auth Key` / `anthropic-api-key-pi` /
> `flakehub_bergamot_token` names predate this migration; they are referenced
> as-is to avoid re-pointing the dev-shell and dotfiles UUIDs.
