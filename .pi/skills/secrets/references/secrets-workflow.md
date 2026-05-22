# Secrets Workflow

## Adding a Secret: Complete Flow

### Scenario: Add Tailscale auth key

1. **Create the secret value** (user does outside of Nix):
   ```bash
   # Get auth key from Tailscale admin console
   # Store temporarily (user's responsibility)
   ```

2. **Edit encrypted file**:
   ```bash
   export SOPS_AGE_KEY_FILE=$(cat secrets/keys/lumquat.age)
   sops secrets/secrets.yaml
   ```

3. **Add to YAML**:
   ```yaml
   tailscale-auth-key: |
     tskey-auth-k8sABC123XYZ...
   ```

4. **Declare in module** (`modules/features/tailscale.nix`):
   ```nix
   sops.secrets.tailscale-auth-key = {
     mode = "0640";
     group = "tailscale";
     key = "data";
   };
   ```

5. **Use in config**:
   ```nix
   services.tailscale = {
     enable = true;
     authKeyFile = config.sops.secrets.tailscale-auth-key.path;
   };
   ```

6. **Deploy**:
   ```bash
   colmena apply --on lumquat --impure
   ```

## SOPS Edit Mode

When editing `secrets.yaml`:

| Key | Action |
|-----|--------|
| `Ctrl+O` | Save |
| `Ctrl+X` | Exit |

The file is automatically re-encrypted on save.

## Validation

After deployment, verify:
```bash
ssh lumquat "ls -la /run/secrets/"
ssh lumquat "cat /run/secrets/tailscale-auth-key"
```
