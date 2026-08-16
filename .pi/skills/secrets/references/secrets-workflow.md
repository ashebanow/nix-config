# Secrets Workflow (BWS + SecretSpec)

## Adding a Secret: Complete Flow

### Scenario: Add a Tailscale auth key for a new service

1. **Create the value in BWS** (user does outside of Nix):
   - BW web console → Secrets Manager → Homelab → create item
   - Name it with the convention: env var lowercased, service prefix, dashes
     (e.g. `my-service-tailscale-auth-key`)

2. **Declare it** in `secretspec.toml`:

   ```toml
   [profiles.production]
   MY_SERVICE_TS_AUTHKEY = { description = "Tailscale auth key for my-service", required = true, ref = { item = "my-service-tailscale-auth-key" } }

   [scopes.my-service]
   secrets = ["MY_SERVICE_TS_AUTHKEY"]
   ```

3. **Consume it** in the module. For a podman-compose service, wrap the start
   command in `secretspec run` so the value is injected as an env var:

   ```nix
   ExecStart = pkgs.writeShellScript "my-compose-start" ''
     set -e
     export XDG_RUNTIME_DIR="/run/user/$(id -u)"
     exec ${pkgs.secretspec}/bin/secretspec run -P production -S my-service -- \
       ${pkgs.podman-compose}/bin/podman-compose -f /etc/my/compose.yml up -d
   '';
   ```

4. **Verify**:

   ```bash
   just secrets-check   # resolves the full manifest against BWS
   ```

## Resolving a scope manually (operator)

```bash
SECRETSPEC_PROVIDER=bws secretspec run -f secretspec.toml -P production -S host -- env
```

## Bootstrap

The BWS access token is provisioned once, out-of-band:

```bash
just bootstrap-bws lumquat   # writes /var/lib/secrets/bws-access-token (0600)
```
