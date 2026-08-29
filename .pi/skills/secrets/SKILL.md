---
name: secrets
description: |
  Add, remove, or modify secrets in the BWS + SecretSpec setup. Use when:
  (1) Adding a new secret for a service or tool, (2) Removing a deprecated
  secret, (3) Wiring a secret into a configuration, (4) Understanding how
  secrets flow into the system.
---

# Secrets Management

## Architecture Overview

Secrets live in **Bitwarden Secrets Manager (BWS)** — project **Homelab** — and
are declared in the repo-root [`secretspec.toml`](../../../secretspec.toml).
There is no encrypted file in git and no sops-nix. Nothing in the Nix store or
git holds a secret value.

1. **Values**: BWS items (e.g. `litellm-db-password`).
2. **Declarations**: `secretspec.toml` — `[profiles.production]` declares each
   secret (`description`, `ref = { item = "<bws item key>" }`); `[scopes.*]`
   partitions them for least-privilege consumers.
3. **Bootstrap**: a single out-of-band BWS access token at
   `/var/lib/secrets/bws-access-token` (root-only, 0600), delivered to services
   via `LoadCredential` + the `systemd-credential://` provider.
4. **Consumption**: services run `secretspec run -P production -S <scope> -- …`.

See `SECRET_SYNC.md` for the full architecture and BWS item inventory.

## Scopes

Each consumer resolves only its own scope:

| Scope | Consumer |
|-------|----------|
| `host` | `host-secrets-populate.service` (tailscale + flakehub) |
| `litellm` | `litellm-compose.service` |
| `openwebui` | `openwebui-compose.service` |
| `memory` | `memory-compose.service`, `memory-health-check.service` |

## Step-by-Step: Adding a New Secret

### 1. Create the value in BWS

In the BW web console → **Secrets Manager → Homelab**, create an item. Naming
convention: env var lowercased, service prefix, underscores → dashes
(e.g. `my-service-api-key`).

### 2. Declare it in `secretspec.toml`

Add to `[profiles.production]`:

```toml
MY_SERVICE_API_KEY = { description = "My service API key", required = true, ref = { item = "my-service-api-key" } }
```

Add it to the relevant scope allowlist:

```toml
[scopes.my-service]
secrets = ["MY_SERVICE_API_KEY"]
```

### 3. Consume it

For a podman-compose stack (env injection, no files):

```nix
systemd.services.my-compose = {
  # … path = [ pkgs.podman-compose pkgs.secretspec pkgs.bws ];
  serviceConfig = {
    User = config.my.baseUsername;
    Environment = [
      "SECRETSPEC_FILE=${config.my.secretspecManifest}"
      "SECRETSPEC_PROVIDER=bws-service"
    ];
    LoadCredential = [ "access_token:${config.my.bwsAccessTokenFile}" ];
    ExecStart = pkgs.writeShellScript "my-compose-start" ''
      set -e
      export XDG_RUNTIME_DIR="/run/user/$(id -u)"
      exec ${pkgs.secretspec}/bin/secretspec run -P production -S my-service -- \
        ${pkgs.podman-compose}/bin/podman-compose -f /etc/my/compose.yml up -d
    '';
  };
};
```

For a file-backed root consumer (tailscale / determinate-nixd), add it to the
`host` scope and write it in `scripts/populate-host-secrets.sh`.

### 4. Verify

```bash
just secrets-check   # resolves every secret in the manifest against BWS
```

## Step-by-Step: Removing a Secret

1. Remove its declaration from `secretspec.toml` (`[profiles.production]` and any
   `[scopes.*]`).
2. Remove its consumption from the module / populate script.
3. Delete the value from BWS (only after the config no longer references it).
4. `just secrets-check` to confirm nothing is missing.

## Bootstrap Token (out-of-band)

The BWS access token is the one secret that cannot come from BWS. Provision it
once per host:

```bash
just bootstrap-bws lumquat
```

It is written to `/var/lib/secrets/bws-access-token` (0600, root). Rotate it by
re-running the recipe, then `systemctl restart host-secrets-populate` (and the
consuming services).

## Important Notes

- Never output actual secret values.
- Never commit a secret value to git or the Nix store.
- `secretspec run` injects values into the child process env only; prefer it over
  `.env` files or podman-secret readback.
- Use `required = true` in the manifest; missing values fail loudly at resolve time.

## See Also

- [secrets-audit](/skill:secrets-audit) — Secrets auditing
- `SECRET_SYNC.md` — full architecture + BWS inventory
