# Secrets: BWS + SecretSpec

nix-config no longer uses sops-nix. All secrets live in **Bitwarden Secrets Manager
(BWS)** (project: **Homelab**), declared in the single repo-root
[`secretspec.toml`](./secretspec.toml) and resolved at runtime with **SecretSpec**.
Nothing in git or the Nix store holds a secret value.

## Architecture

```
┌────────────────────────────────────────────────────────────────┐
│ BWS — "Homelab" project (single source of truth)              │
│   lumquat-tailscale-auth-key, bifrost-tailscale-auth-key,     │
│   mnemosyne-mcp-token, deepseek-api-key, anthropic-api-key-pi,│
│   minimax-api-key, ...                                        │
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
  (root, -S host then     (podman user)
   -S dev)                secretspec run injects
  writes 3 files:         env vars straight into
  /run/secrets/tailscale  podman-compose (no files)
  /run/secrets/flakehub           │
  /run/secrets/linear-api-key     │
        │                         ▼
        ▼                 bifrost / openwebui /
  tailscale authKeyFile   mnemosyne containers
  determinate-nixd token
  `linear` CLI wrapper (operator user)
```

### Profiles (environments)

`[profiles.default]` (and its explicit alias `development`) is
development-safe and carries no production values — a developer's
`~/.config/secretspec/config.toml` defaults to the `development` profile, so a
bare `secretspec` invocation cannot resolve a production secret. Everything
real lives in `[profiles.production]`, declared standalone (`inherit = false`)
and selected explicitly with `-P production` by every host and container stack.

### Scopes (least privilege)

Each consumer resolves only its own scope of the `production` profile. A
Tailscale auth key is issued per node, so the host scope is per node
(`host-<host>`):

| Scope | Secrets | Consumer |
|-------|---------|----------|
| `host-lumquat` | `LUMQUAT_TAILSCALE_AUTH_KEY`, `FLAKEHUB_TOKEN`, `CACHIX_AUTH_TOKEN` | `host-secrets-populate.service` (root) — root-only files |
| `host-yuzu` | `YUZU_TAILSCALE_AUTH_KEY`, `FLAKEHUB_TOKEN`, `CACHIX_AUTH_TOKEN` | `host-secrets-populate.service` (root) — root-only files |
| `dev` | `LINEAR_API_KEY` | `host-secrets-populate.service` (root) — files readable by the operator user; see [ADR 0001](./docs/adr/0001-operator-tool-secrets-via-run-secrets.md) |
| `openwebui` | `OPENWEBUI_TS_AUTHKEY`, `WEBUI_SECRET_KEY` | `openwebui-compose.service` |
| `memory` | `MEMORY_TS_AUTHKEY`, `MNEMOSYNE_MCP_TOKEN` | `memory-compose.service`, `memory-health-check.service` |
| `bifrost` | `BIFROST_TS_AUTHKEY`, `DEEPSEEK_API_KEY`, `ANTHROPIC_API_KEY`, `MINIMAX_API_KEY` | `bifrost-compose.service` |

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
file interface, so these are written to disk (tmpfs):

`host-secrets-populate.service` (root, `modules/features/secrets.nix`) runs
`secretspec run -P production -S host-<host> -- scripts/populate-host-secrets.sh
host <HOST>_TAILSCALE_AUTH_KEY`, which writes:

- `/run/secrets/tailscale-auth-key` (0600 root) → `services.tailscale.authKeyFile`
- `/run/secrets/flakehub-token` (0600 root) → `flakehub-nixd-auth.service --token-file`

### Dev secrets (linear) — operator-tool consumers

The same unit then runs a **second** `secretspec run -P production -S dev --
scripts/populate-host-secrets.sh dev <operator-user>` (separate invocation, so
neither subprocess sees the other scope), which writes:

- `/run/secrets/linear-api-key` (0400, owned by `my.baseUsername`) → read by the
  `linear` CLI's Nix wrapper (`lib/overlays/linear-cli.nix`) when
  `LINEAR_API_KEY` is not already in the environment.

`dev` secrets are optional: an absent value skips the file with a notice and
does not fail the unit. Why operator tools get their secrets this way rather
than through a user-level BWS token or a keyring:
[ADR 0001](./docs/adr/0001-operator-tool-secrets-via-run-secrets.md).

### Home Manager activation (chezmoi) — systemd-credential consumer

`home-manager-podman.service` runs the `chezmoiApply` activation on every
`nh os switch`; the `gh` token template needs the BWS token, so the unit gets
`LoadCredential=access_token:${my.bwsAccessTokenFile}` and the activation script
reads `${CREDENTIALS_DIRECTORY}/access_token` into `BWS_ACCESS_TOKEN`.

The token is not the whole story: the template resolves the value by shelling
out to the `bws` CLI (chezmoi's `output "bws" "secret" get …`), and the
activation's `PATH` is nix-store coreutils/findutils/… only — neither the system
profile nor `/run/wrappers/bin` is on it. `my.bwsBinDir` (set by the NixOS layer
to the `bws` store path, default `/run/current-system/sw/bin`) is prepended to
the activation `PATH` so the template can actually call it (BOX-174).

This deliberately goes through `LoadCredential` rather than reading the
root-only file directly: the activation's `PATH` is nix-store paths only, so
`sudo` (which NixOS installs in `/run/wrappers/bin`) is not found, and the
earlier `sudo -n cat … 2>/dev/null || true` silently produced an empty token
for every activation (BOX-174).

Failure is loud in both directions the activation can distinguish: an absent
credential (or no `${CREDENTIALS_DIRECTORY}` at all, as under standalone
`home-manager switch` or a VM test) keeps the intended token-less apply, while a
credential that exists but cannot be read or is empty aborts the activation
instead of degrading to an empty `BWS_ACCESS_TOKEN`.

### Container secrets (bifrost, openwebui, memory) — no files

The podman-compose systemd services (`bifrost-compose`, `openwebui-compose`,
`memory-compose`) run `secretspec run -P production -S <scope> -- podman-compose
up -d`. SecretSpec injects the scope's values straight into the process
environment; podman-compose substitutes them into `compose.yml`. **No `.env`
file, no podman-secret readback** — values exist only in the process env.

The periodic `memory-health-check` resolves `MNEMOSYNE_MCP_TOKEN` the same way.

## Dev shell

The devshell lives in `modules/infra/devshell.nix` (the flake's
`devShells.default`); the legacy root `shell.nix` was removed. It does **not**
fetch secrets from BWS — API keys are expected in the environment already:

- **darwin (bergamot, miraclemax)**: `~/.zshenv` (chezmoi) reads the BWS token
  from the macOS keychain and refreshes `~/.cache/env/bws_env.sh` (8h cache),
  exporting `DEEPSEEK_API_KEY`, `ANTHROPIC_API_KEY`, `EXA_API_KEY`,
  `GEMINI_API_KEY`, `MINIMAX_API_KEY`, `ZED_GITHUB_PERSONAL_ACCESS_TOKEN`,
  `FLAKEHUB_TOKEN` (item `NIX_FLAKEHUB_CACHE_TOKEN`), and more. `nix develop`
  inherits these from the parent shell.
- **NixOS (lumquat)**: secrets reach systemd services via `secretspec` +
  `LoadCredential` (above). The devshell still never talks to BWS; the one
  secret an interactive tool needs there (`LINEAR_API_KEY`) is read from
  `/run/secrets/linear-api-key` by the tool's own wrapper (dev scope, above),
  so `nix develop` needs nothing in its parent environment.

## Adding or rotating a secret

1. **Create/update the value in BWS** (Homelab project). Naming convention: env
   var lowercased, service prefix, underscores → dashes
   (e.g. `bifrost-tailscale-auth-key`).
2. **Declare it** in `secretspec.toml` under `[profiles.production]` (all real
   secrets live there; `default`/`development` are development-safe), and add it
   to the relevant `[scopes.<name>].secrets` list. A genuinely per-node secret
   gets a `<HOST>_...` name and its own `[scopes.host-<host>]` — the Tailscale
   auth key is the existing example.
3. **Consume it** in the module via `secretspec run` (container service) or the
   host populate script (file-backed consumer).
4. **Verify**: `just secrets-check` (requires `BWS_ACCESS_TOKEN`).
5. **Rotate the bootstrap token**: re-run `just bootstrap-bws <host>` and
   `systemctl restart host-secrets-populate` (then restart the consuming
   services).

## BWS item inventory (Homelab project)

| BWS item key | Used by |
|--------------|---------|
| `lumquat-tailscale-auth-key` | host `tailscale` on lumquat (`host-lumquat` scope) |
| `yuzu-tailscale-auth-key` | host `tailscale` on yuzu (`host-yuzu` scope) |
| `NIX_FLAKEHUB_CACHE_TOKEN` | `determinate-nixd` cache auth |
| `webui-secret-key` | openwebui session-signing key (`WEBUI_SECRET_KEY`) |
| `deepseek-api-key` | bifrost |
| `anthropic-api-key-pi` | bifrost |
| `minimax-api-key` | bifrost |
| `OpenWebUI TS Auth Key` | openwebui tailscale sidecar |
| `mnemo-tailscale-auth-key` | mnemosyne tailscale sidecar |
| `mnemosyne-mcp-token` | mnemosyne MCP auth |
| `bifrost-tailscale-auth-key` | bifrost tailscale sidecar (the `ai` node) |
| `linear-mcp-api-key` | `linear` CLI on lumquat (`dev` scope → `/run/secrets/linear-api-key`); also the Darwin `secrets.sh` cache (dotfiles). Name predates the MCP → CLI move. |

> The `OpenWebUI TS Auth Key` / `anthropic-api-key-pi` names predate this
> migration; they are referenced as-is to avoid re-pointing the dev-shell and
> dotfiles UUIDs. `webui-secret-key` holds the value the old `LiteLLM Master
> Key` item held — copied to a litellm-free name for BOX-138. `FLAKEHUB_TOKEN`
> was re-pointed from the legacy `flakehub_bergamot_token` item to
> `NIX_FLAKEHUB_CACHE_TOKEN` (the token formerly lived in the operator's
> personal Bitwarden vault).
>
> **Orphaned by BOX-138** — safe to delete in the BWS console once this branch
> is deployed: `LiteLLM Master Key`, `litellm-tailscale-auth-key`,
> `litellm-db-password`.

### Manual steps that git cannot record

Two pieces of the tailnet setup live only in the Tailscale admin console, so
nothing in this repo will recreate them:

- **Key expiry is disabled per node** for the server-side nodes (`lumquat`, and
  the sidecar nodes `openwebui`, `memory`, `ai`). The tailnet's
  `maxKeyDuration` is 180 days; without this, a sidecar silently drops off the
  tailnet twice a year and the service becomes unreachable with no local error.
  Check it whenever a new sidecar node joins.
- **`BIFROST_TS_AUTHKEY` is a reusable auth key**, so the bifrost sidecar
  re-authenticates cleanly whenever its container is recreated. If it is ever
  rotated to a single-use key, recreating the container will fail to join.
- **Retire the `litellm` tailnet node** (BOX-138): after the LiteLLM stack is
  gone from lumquat, delete the `litellm` node in the Tailscale admin console.
  Nothing recreates it.
