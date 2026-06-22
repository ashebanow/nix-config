# Plan: Migrate from Tailscale Aperture to Tailscale Serve/ Services

## Why

Tailscale Aperture has been flaky for routing traffic to local LLM endpoints.
Tailscale **Serve** and the newer **Tailscale Services** provide a built-in,
more reliable alternative that also provides:

- Automatic TLS certs via Let's Encrypt (same as Aperture)
- Per-service subdomains (`<service>.fluffy-walleye.ts.net`)
- Declarative configuration via the `services.tailscale.serve` NixOS module
- No separate Aperture container/proxy to manage

Aperture can remain installed but unused on the client side — no need to
remove it now.

---

## Part 1: Fix Autoconnect (prerequisite)

### Problem

Our `access.nix` currently defines a custom `tailscale-autoconnect` service
using `lib.mkForce` on `ExecStart`. This:

- Overrides the **entire** nixpkgs built-in autoconnect service
- Loses `Type = notify` (proper readiness signaling)
- Loses the robust reconnect loop with state tracking
- Creates an unnecessary divergence from nixpkgs

### Solution: Use the built-in autoconnect

The nixpkgs tailscale module already provides everything we need:

| Option | Purpose | Our value |
|--------|---------|-----------|
| `services.tailscale.authKeyFile` | Path to file containing auth key | `/run/secrets/tailscale-auth-key` |
| `services.tailscale.extraUpFlags` | Extra flags for `tailscale up` | `["--ssh" "--hostname=lumquat"]` |

The built-in `tailscaled-autoconnect.service`:

1. Loops polling `tailscale status --json` until the backend state is `Running`
2. Calls `tailscale up --auth-key "$(cat ${authKeyFile})" ${extraUpFlags}` to authenticate
3. Calls `systemd-notify --ready` once connected (`Type = notify`)
4. Is a dependency of `tailscale-serve.service` (the serve module)

### What changes in access.nix

**Remove:**
- The entire custom `systemd.services.tailscale-autoconnect` definition with `lib.mkForce`

**Add to the `services.tailscale` block:**
```nix
services.tailscale = {
  enable = true;
  authKeyFile = "/run/secrets/tailscale-auth-key";
  extraUpFlags = [
    "--ssh"
    "--hostname=${config.my.accessTailnetName}"
  ];
  useRoutingFeatures = "client";
};
```

**Keep:**
- The `my.access` capability guard (`lib.mkIf config.my.access`)
- Firewall rules (`trustedInterfaces`, `checkReversePath`, fallback SSH port)
- The `networking.hostName` (already set in base.nix, used by tailscale)
- Fallback SSH on port 2222

### Effect on the serve module

By using the built-in autoconnect, the unit name `tailscaled-autoconnect.service`
matches exactly what the `tailscale-serve` module expects in its `after = [...]`
dependency list. Issue #4 from the original plan disappears entirely.

---

## Part 2: Add `my.llmServe` Capability Flag

**File:** `lib/my-options-module.nix`

Add alongside existing `my.llm`:

```nix
llmServe = lib.mkOption {
  type = lib.types.bool;
  default = false;
  description = "Enable Tailscale Serve to publish LLM endpoints via Tailscale Services.";
};
```

---

## Part 3: Integrate Serve Config into LLM Module

**File:** `modules/features/llm.nix`

### Approach

Add a `services.tailscale.serve` block at the end of the `config = lib.mkIf config.my.llm { ... }` section.
Iterate all models from `lib/models.nix` to generate one service per model.

### Why iterate all models

The user requested this approach. `llm.nix` already iterates models via
`modelsLib.models` to build container configs. We re-use the same iteration
to build serve endpoints.

If a model's container has `autoStart = false`, the serve endpoint will
simply return connection errors — this is harmless and means we don't need
an additional `enabled` flag in the model definitions. Harmless dead
endpoints are preferable to complexity.

### Serve config structure

```nix
services.tailscale.serve = lib.mkIf config.my.llmServe {
  enable = true;
  services = lib.mapAttrs' (
    name: model: {
      endpoints = {
        "tcp:443" = "http://localhost:${toString model.port}";
      };
    }
  ) modelsLib.models;
};
```

### Service naming and DNS

Each model key in `models.nix` becomes the Tailscale service name (auto-prefixed
with `svc:` by the nixpkgs module). DNS format:

```
https://<service-name>.fluffy-walleye.ts.net/
```

| models.nix key | Service name | Access URL | Container port |
|---|---|---|---|
| `qwen-35b-a3b` | `qwen-35b-a3b` | `https://qwen-35b-a3b.fluffy-walleye.ts.net/` | 8080 |
| `gemma-27b` | `gemma-27b` | `https://gemma-27b.fluffy-walleye.ts.net/` | 8081 |

The nixpkgs module generates JSON config of the form:

```json
{
  "version": "0.0.1",
  "services": {
    "svc:qwen-35b-a3b": {
      "advertised": true,
      "endpoints": {
        "tcp:443": "http://localhost:8080"
      }
    },
    "svc:gemma-27b": {
      "advertised": true,
      "endpoints": {
        "tcp:443": "http://localhost:8081"
      }
    }
  }
}
```

Each service gets its own dedicated subdomain with TLS termination on port 443,
so there's no port conflict.

---

## Part 4: Enable on Lumquat

**File:** `hosts/lumquat/configuration.nix`

Add:
```nix
my.llmServe = true;
```

---

## Full File Changes Summary

### `lib/my-options-module.nix`

Add one new option:
```nix
llmServe = lib.mkOption {
  type = lib.types.bool;
  default = false;
  description = "Enable Tailscale Serve to publish LLM endpoints via Tailscale Services.";
};
```

### `modules/features/access.nix`

Replace the custom autoconnect service with built-in options:

```diff
 services.tailscale = {
   enable = true;
+  authKeyFile = "/run/secrets/tailscale-auth-key";
+  extraUpFlags = [
+    "--ssh"
+    "--hostname=${config.my.accessTailnetName}"
+  ];
   useRoutingFeatures = "client";
-  extraUpFlags = [
-    "--hostname=${config.my.accessTailnetName}"
-  ] ++ lib.optionals config.my.accessEnableSSH [ "--ssh" ];
 };

- Remove entire custom systemd.services.tailscale-autoconnect with mkForce
```

### `modules/features/llm.nix`

Add to the `config = lib.mkIf config.my.llm` block:

```nix
services.tailscale.serve = lib.mkIf config.my.llmServe {
  enable = true;
  services = lib.mapAttrs' (
    name: model: {
      endpoints = {
        "tcp:443" = "http://localhost:${toString model.port}";
      };
    }
  ) modelsLib.models;
};
```

### `hosts/lumquat/configuration.nix`

Add:
```nix
my.llmServe = true;
```

---

## Systemd Dependency Chain

After the change, the boot-time ordering is:

```
tailscaled.service
  │
  ▼
tailscaled-autoconnect.service   (built-in, Type=notify)
  │
  ▼
tailscale-serve.service          (oneshot, runs set-config --all)
  │
  ▼
oci-containers@qwen-35b-a3b...   (podman containers, started by oci-containers)

multi-user.target
```

All clean — no `mkForce` needed, no custom unit definitions, no naming conflicts.

---

## Rollout & Verification

### Step 1: `nix build` to verify evaluation

```bash
nix build .#nixosConfigurations.lumquat.config.system.build.toplevel
```

### Step 2: Deploy

```bash
colmena apply --on lumquat
```

### Step 3: Verify autoconnect

```bash
# On lumquat, check systemd status
systemctl status tailscaled-autoconnect
# Should show: Active: active (running)  (Type=notify)
```

### Step 4: Verify serve services

```bash
# On lumquat
tailscale serve status

# Expected output:
# svc:qwen-35b-a3b    https://qwen-35b-a3b.fluffy-walleye.ts.net/    http://localhost:8080
# svc:gemma-27b       https://gemma-27b.fluffy-walleye.ts.net/       http://localhost:8081
```

### Step 5: Test from another tailnet device

```bash
# Health check
curl https://qwen-35b-a3b.fluffy-walleye.ts.net/health

# API call
curl https://qwen-35b-a3b.fluffy-walleye.ts.net/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen","messages":[{"role":"user","content":"Hello"}]}'
```

---

## Rollback Plan

If something goes wrong:

1. Revert the changes to `access.nix`, `llm.nix`, `my-options-module.nix`, and `configuration.nix`
2. Rebuild + redeploy:
   ```bash
   colmena apply --on lumquat
   ```
3. The old Aperture-based setup was never removed, so clients can continue using it

---

## Open Questions (Resolved)

| Question | Decision |
|----------|----------|
| New flag or reuse `my.llm`? | **New flag** `my.llmServe` |
| Module location? | **Part of `llm.nix`** — keeps LLM serving together |
| Which models to publish? | **All models** from `lib/models.nix` — inactive containers just return errors |
| Fix autoconnect? | **Yes** — use built-in `authKeyFile` + `extraUpFlags`, remove `mkForce` override |
