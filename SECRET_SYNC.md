# BWS Integration for Devshell Secrets

## Goal

Replace SOPS-backed API key loading in `shell.nix` and `modules/infra/devshell.nix`
with a BWS-backed approach that uses a local cache to avoid slowing down direnv.
SOPS remains as a **read-only bootstrap token store** — never write to it via scripts.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ PRIMARY PATH (dev machine with zshenv loaded, e.g. macOS+zsh)   │
│                                                                 │
│  $BWS_ACCESS_TOKEN  ← already in env from ~/.zshenv (chezmoi)   │
│         │                                                       │
│         └──→ bws secret get <uuid>  →  cache  →  done           │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│ FALLBACK PATH (cold start: bash, no zshenv, new machine)        │
│                                                                 │
│  secrets/secrets.yaml (SOPS)                                    │
│  └─ bws-access-token  ← decrypt via _setup_sops_key             │
│         │                                                       │
│         └──→ bws secret get <uuid>  →  cache  →  done           │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│ SERVER (unchanged — SOPS remains the source of truth for NixOS) │
│                                                                 │
│  secrets/secrets.yaml (SOPS)                                    │
│  ├─ tailscale-auth-key      → /run/secrets/  → tailscale        │
│  ├─ deepseek-api-key        → /run/secrets/  → litellm container│
│  ├─ anthropic-api-key       → /run/secrets/  → litellm container│
│  ├─ minimax-api-key         → /run/secrets/  → litellm container│
│  └─ litellm-*               → /run/secrets/  → litellm container│
│                                                                 │
│  Declared in modules/features/secrets.nix, consumed by llm.nix  │
└─────────────────────────────────────────────────────────────────┘

BWS Homelab project           (single source of truth for API keys)
├─ deepseek-api-key          fdf38fc5-3f26-446f-9808-b47701346a5d
├─ minimax-api-key           3a5ac53a-8af5-4277-a86e-b47701341630
├─ gemini-api-key            3dbd4b26-485f-44d5-abc6-b477013544b4
├─ anthropic-api-key         28893b82-be1f-407c-aa2d-b4770134fcc1
├─ exa-api-key               52eba787-8cb2-41b7-87b1-b4770134b198  (BWS-only)
└─ zed-github-pat            2bc9244b-acf0-4620-8e29-b4770132e6f9  (BWS-only)

    ↓ shellHook fetches via `bws secret get <uuid>`
    ↓ cached to ${XDG_CACHE_HOME:-$HOME/.cache}/nix-bws/env.sh
    ↓ 24-hour TTL; subsequent direnv loads are instant
```

## Cache Strategy

A cache file at `${XDG_CACHE_HOME:-$HOME/.cache}/nix-bws/env.sh` with 24-hour TTL.
On macOS+zsh (the common case), `$BWS_ACCESS_TOKEN` is already in the environment
from `.zshenv` — no SOPS is involved at all. Cache-miss costs ~3–5s (6 bws calls);
cache-hit is a single `stat` + `source` (instant). On cold-start machines (bash, no
zshenv), add one SOPS decrypt (~1s) to extract the bootstrap token.

| Variable | Value |
|---|---|
| Cache path | `${XDG_CACHE_HOME:-$HOME/.cache}/nix-bws/env.sh` |
| TTL | 86400 seconds (24 hours) — API keys change rarely; 24h avoids daily network calls while still picking up rotations within a day. (The zshenv `bw_env.sh` uses 8h for tighter rotation coverage of personal vault items.) |
| Permissions | `chmod 600` on creation |
| Invalidation | `rm "$CACHE_FILE"` to force re-fetch |

The cache is a shell-sourcable file containing export statements, same pattern as
`~/.cache/env/bw_env.sh` used by the dotfiles `.zshenv`.

## Secret IDs (BWS Homelab Project, Chezmoi machine account)

Copied from `private_dot_zshenv.tmpl` in the dotfiles repo.

| Env var | BWS Secret UUID |
|---|---|
| `DEEPSEEK_API_KEY` | `fdf38fc5-3f26-446f-9808-b47701346a5d` |
| `MINIMAX_API_KEY` | `3a5ac53a-8af5-4277-a86e-b47701341630` |
| `GEMINI_API_KEY` | `3dbd4b26-485f-44d5-abc6-b477013544b4` |
| `ANTHROPIC_API_KEY` | `28893b82-be1f-407c-aa2d-b4770134fcc1` |
| `EXA_API_KEY` | `52eba787-8cb2-41b7-87b1-b4770134b198` |
| `ZED_GITHUB_PERSONAL_ACCESS_TOKEN` | `2bc9244b-acf0-4620-8e29-b4770132e6f9` |

## Manual Step: Prepare secrets.yaml

**Do this once, manually, before editing any nix files.**

```bash
cd ~/Development/nix/nix-config/lumquat

# 1. Decrypt current secrets
sops secrets/secrets.yaml

# 2. Add the BWS access token (get it from chezmoi data or BW web console)
#    Add this key to the YAML:
#
#      bws-access-token: "0.abc123..."
#
#    The token is from the "chezmoi" machine account in the BW Secrets Manager
#    Homelab project. Find it at: BW web console → Secrets Manager → Homelab →
#    Machine Accounts → chezmoi → Access Tokens

# 3. Keep the existing API key entries — they remain in secrets.yaml for
#    future server-side improvements and backward compatibility.
#    The server (litellm container) still reads these from /run/secrets/.
#    The devshell will load the same keys from BWS instead.
#
#    DO NOT DELETE: deepseek-api-key, minimax-api-key, anthropic-api-key
#    (Also keep: tailscale-auth-key, litellm-tailscale-auth-key,
#     litellm-master-key, litellm-db-password)
#
#    Note: gemini-api-key exists in secrets.yaml but is undeclared in
#    modules/features/secrets.nix (orphaned). It can be cleaned up in a
#    separate pass or kept for future use — BWS will be the authoritative
#    source regardless.

# 4. The only NEW key to add is bws-access-token:
#
#      bws-access-token: "0.abc123..."
#
#    The token is from the "chezmoi" machine account in the BW Secrets Manager
#    Homelab project. Find it at: BW web console → Secrets Manager → Homelab →
#    Machine Accounts → chezmoi → Access Tokens

# 5. Save and re-encrypt
```

After this, `secrets/secrets.yaml` should contain all existing keys plus one new one:

```yaml
tailscale-auth-key: tskey-auth-...
deepseek-api-key: sk-...
minimax-api-key: ...
gemini-api-key: ...          # orphaned, kept for reference
anthropic-api-key: sk-...
litellm-tailscale-auth-key: tskey-auth-...
litellm-master-key: sk-...
litellm-db-password: ...
bws-access-token: "0.abc123..."   # NEW — bootstrap token for devshell
```

## Changes to shell.nix

### 1. Add `bws` to nativeBuildInputs

Add `bws` to the existing `nativeBuildInputs` list (it may or may not be in nixpkgs —
check and add a flake input or custom derivation if needed).

```nix
nativeBuildInputs = with pkgs; [
    # ... existing entries (alejandra, colmena, sops, etc.) ...
    bws   # CLI for Bitwarden Secrets Manager
];
```

### 2. Replace the secret-loading block in shellHook

**Remove** the current block that does `sops -d --extract` for each API key:

```bash
if _setup_sops_key; then
  # Decrypt individual secrets (one sops call each)
  if DEEPSEEK_API_KEY=$(sops -d --extract ...) && ...; then
    ...
  fi
  if MINIMAX_API_KEY=$(sops -d --extract ...) && ...; then
    ...
  fi
fi
```

**Replace with** a single function that:
1. Prefers `$BWS_ACCESS_TOKEN` from the environment (already set by `.zshenv` on
   zsh login shells — the common case on macOS and configured Linux machines).
2. Falls back to decrypting `bws-access-token` from SOPS if the env var is unset
   (cold start: bash, no zshenv, new machine).
3. Uses `bws` to fetch secrets, writing them to a cache file.
4. Sources the cache file.

The function:

```bash
_bws_load_secrets() {
  local CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/nix-bws"
  local CACHE_FILE="$CACHE_DIR/env.sh"
  local CACHE_MAX_AGE=86400  # 24 hours

  # If cache exists and is fresh, just source it
  if [[ -f "$CACHE_FILE" ]]; then
    local cache_mtime now
    if [[ "$(uname)" == "Darwin" ]]; then
      cache_mtime=$(stat -f %m "$CACHE_FILE" 2>/dev/null)
    else
      cache_mtime=$(stat -c %Y "$CACHE_FILE" 2>/dev/null)
    fi
    now=$(date +%s)
    if (( now - cache_mtime < CACHE_MAX_AGE )); then
      source "$CACHE_FILE"
      return 0
    fi
  fi

  # Resolve BWS access token: env first (zshenv), then SOPS fallback
  local _bws_token="${BWS_ACCESS_TOKEN:-}"
  if [[ -z "$_bws_token" ]]; then
    if command -v sops >/dev/null 2>&1 && _setup_sops_key; then
      _bws_token=$(sops -d --extract '["bws-access-token"]' secrets/secrets.yaml 2>/dev/null)
    fi
  fi
  if [[ -z "$_bws_token" ]]; then
    echo "  [bws] WARNING: No BWS_ACCESS_TOKEN (env or SOPS)" >&2
    echo "  [bws] Set BWS_ACCESS_TOKEN in your environment, or" >&2
    echo "  [bws] add bws-access-token to secrets/secrets.yaml" >&2
    return 1
  fi

  # Fetch all secrets from BWS (UUIDs from private_dot_zshenv.tmpl)
  mkdir -p "$CACHE_DIR"
  {
    echo "# Auto-generated — do not edit"
    echo "export DEEPSEEK_API_KEY=\"$(BWS_ACCESS_TOKEN=\"$_bws_token\" bws secret get fdf38fc5-3f26-446f-9808-b47701346a5d 2>/dev/null || true)\""
    echo "export MINIMAX_API_KEY=\"$(BWS_ACCESS_TOKEN=\"$_bws_token\" bws secret get 3a5ac53a-8af5-4277-a86e-b47701341630 2>/dev/null || true)\""
    echo "export GEMINI_API_KEY=\"$(BWS_ACCESS_TOKEN=\"$_bws_token\" bws secret get 3dbd4b26-485f-44d5-abc6-b477013544b4 2>/dev/null || true)\""
    echo "export ANTHROPIC_API_KEY=\"$(BWS_ACCESS_TOKEN=\"$_bws_token\" bws secret get 28893b82-be1f-407c-aa2d-b4770134fcc1 2>/dev/null || true)\""
    echo "export EXA_API_KEY=\"$(BWS_ACCESS_TOKEN=\"$_bws_token\" bws secret get 52eba787-8cb2-41b7-87b1-b4770134b198 2>/dev/null || true)\""
    echo "export ZED_GITHUB_PERSONAL_ACCESS_TOKEN=\"$(BWS_ACCESS_TOKEN=\"$_bws_token\" bws secret get 2bc9244b-acf0-4620-8e29-b4770132e6f9 2>/dev/null || true)\""
  } > "$CACHE_FILE.tmp" && mv "$CACHE_FILE.tmp" "$CACHE_FILE"
  chmod 600 "$CACHE_FILE"

  source "$CACHE_FILE"
  echo "  [bws] Secrets loaded and cached"
  return 0
}
```

### 3. Call the function in shellHook

After `_setup_sops_key` is defined, replace the old per-key decryption block with:

```bash
_bws_load_secrets || {
  echo "  [bws] WARNING: BWS secrets unavailable" >&2
  echo "  [bws] Ensure BWS_ACCESS_TOKEN is set, or" >&2
  echo "  [bws] add bws-access-token to secrets/secrets.yaml" >&2
}
```

### 4. Full shellHook (for reference)

```bash
shellHook = ''
  echo "Lumquat dev shell"

  # Load API keys and other secrets from BWS via SOPS-bootstrapped access token.
  # Also makes SOPS_AGE_KEY available for manual sops use.
  if [ -f secrets/secrets.yaml ] && command -v sops >/dev/null 2>&1; then
    _setup_sops_key() {
      # (KEEP THIS FUNCTION EXACTLY AS-IS — UNTOUCHED)
      # 1. Already set via environment
      if [ -n "$SOPS_AGE_KEY" ] || [ -n "$SOPS_AGE_KEY_FILE" ]; then
        return 0
      fi
      # 2. Repo-local age key (secrets/keys/lumquat.age)
      if [ -f secrets/keys/lumquat.age ]; then
        export SOPS_AGE_KEY_FILE="$(realpath secrets/keys/lumquat.age)"
        return 0
      fi
      # 3. macOS dev machine: ~/.config/sops/age/keys.txt
      if [ -f "$HOME/.config/sops/age/keys.txt" ]; then
        export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
        return 0
      fi
      # 4. NixOS: derive from SSH host key via ssh-to-age
      if [ -f /etc/ssh/ssh_host_ed25519_key ] && command -v ssh-to-age >/dev/null 2>&1; then
        export SOPS_AGE_KEY="$(sudo cat /etc/ssh/ssh_host_ed25519_key 2>/dev/null | ssh-to-age -private-key 2>/dev/null)"
        [ -n "$SOPS_AGE_KEY" ] && return 0
      fi
      return 1
    }

    _bws_load_secrets() {
      # (INSERT THE FUNCTION FROM SECTION 2 ABOVE)
      ...
    }

    _bws_load_secrets || {
      echo "  [bws] WARNING: BWS secrets unavailable" >&2
    }
  fi
'';
```

## Changes to modules/infra/devshell.nix

This file is the flakes-based equivalent of `shell.nix`. Apply the **exact same changes**:

1. Add `bws` to the `packages` list (note: `packages` not `nativeBuildInputs` in this context)
2. Replace the per-key `sops -d --extract` block with `_bws_load_secrets` and its call
3. Keep `_setup_sops_key` exactly as-is

The `_setup_sops_key` function is identical in both files — it tries:
1. `$SOPS_AGE_KEY` / `$SOPS_AGE_KEY_FILE` (environment)
2. `secrets/keys/lumquat.age` (repo-local, generated on first devshell run)
3. `~/.config/sops/age/keys.txt` (macOS dev machine)
4. SSH host key → ssh-to-age (NixOS server, requires sudo)

## Performance Note

**Primary path** (macOS+zsh or any machine with `$BWS_ACCESS_TOKEN` from `.zshenv`):
- Cache hit: instant — a single `stat` + `source`
- Cache miss: ~3–5s — 6 parallel-feel `bws secret get` calls (each a network round-trip)

**Fallback path** (cold start: bash, no zshenv, new machine):
- Add ~1s for one SOPS decrypt to extract the bootstrap token

In practice, the fallback path is rarely taken — most dev sessions hit the primary path.

## Requirements Checklist

- [ ] `bws` available in nixpkgs (confirmed: `nixpkgs#bws` at version 2.1.0). Use `pkgs.bws` directly.
- [ ] Secrets are fetched **read-only** from SOPS — no `sops --set`, no `sops exec-file` with writes.
- [ ] Cache file is mode `600`.
- [ ] `XDG_CACHE_HOME` fallback is `${XDG_CACHE_HOME:-$HOME/.cache}` for macOS compatibility.
- [ ] `_setup_sops_key` is left untouched (it handles age key discovery for all platforms).
- [ ] On macOS dev machines: `~/.config/sops/age/keys.txt` should work for SOPS decryption. If it doesn't, the `bws-access-token` fetch will fail silently and the fallback message prints.
- [ ] On the server: the `sudo cat` for host key may require passwordless sudo for that specific command. Should already be handled by existing setup.
- [ ] Both `shell.nix` and `devshell.nix` get the same treatment.
- [ ] Test: `rm -f ~/.cache/nix-bws/env.sh && direnv allow` — first load should show `[bws] Secrets loaded and cached`.
- [ ] Test: subsequent `direnv` loads should be silent and instant (cache hit).
- [ ] Test: after 24h, cache expires and re-fetches silently.

## Follow-up (future work, not in scope)

- Build a minimal chezmoi branch for the podman user on lumquat that sources `.zshenv`,
  eliminating the need for BWS in the devshell entirely. At that point the devshell can
  drop all secret loading and just rely on the inherited environment.
