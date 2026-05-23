---
description: Quick architectural review before implementation
---

# Pre-Implementation Architecture Review

Before implementing a new feature or significant change, review the architecture:

## Questions to Answer

### 1. Dendritic Pattern Fit

- Is this a cross-cutting concern or host-specific?
- Should it live in `modules/features/` or `modules/hosts/`?
- Does it span NixOS, Home Manager, or both?

### 2. Capability Flags

- Does this feature need a new capability flag?
- Can it reuse an existing flag (`hasDesktop`, `hasMonitoring`, etc.)?
- Where should the flag be defined (`lib/my-options-module.nix`)?

### 3. Module Registration

- Which container should it register into?
  - `my.modules.nixos.<name>` for system-level config
  - `my.modules.home-manager.<name>` for user-level config
- What is the feature signature?

### 4. Dependencies

- Does this feature depend on other features?
- Should other features depend on this one?
- Are there ordering constraints?

### 5. Secrets

- Does this feature need secrets?
- Are secrets already defined, or need new ones?
- Where should secrets be declared?

### 6. Services

- Does this start a new system service?
- Should it use NixOS module options or podman containers?
- What ports does it need?

## Quick Audit Checklist

- [ ] Feature module uses `_: { ... }` signature
- [ ] Registers into correct `my.modules.*` container
- [ ] Uses `lib.mkIf` with capability flag (if conditional)
- [ ] No hardcoded hostnames
- [ ] Secrets declared correctly with sops
- [ ] No circular dependencies

## Reference

See `/dend-review-features` for deep-dive review.
