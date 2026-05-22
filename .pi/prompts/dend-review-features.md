---
description: Review feature module for dendritic pattern compliance
---

# Feature Module Review

Review a feature module for dendritic pattern compliance.

## Quick Checklist

For each feature module in `modules/features/`:

### Signature
- [ ] Uses `_: { ... }` (flake-parts module signature)
- [ ] Ignores unused arguments

### Registration
- [ ] Registers into `my.modules.nixos.<name>` OR
- [ ] Registers into `my.modules.home-manager.<name>` OR
- [ ] Registers into both (cross-cutting)

### Guards
- [ ] Uses `lib.mkIf config.my.<flag>` for conditional logic
- [ ] No hardcoded hostname checks like `config.my.hostName == "lumquat"`

### Naming
- [ ] Container key matches filename: `llm-serve.nix` → `my.modules.nixos.llm-serve`
- [ ] Descriptive, lowercase names with hyphens

### Structure
- [ ] Single concern per file
- [ ] No duplicate functionality with other features
- [ ] Imports are explicit

## Common Issues to Flag

| Issue | Severity | Fix |
|-------|----------|-----|
| Missing registration | High | Add `my.modules.nixos.<name> = _: { ... }` |
| Hostname check | High | Replace with capability flag |
| Missing mkIf guard | Medium | Add `lib.mkIf config.my.<flag>` |
| Wrong container | Medium | Move to correct `my.modules.*` |
| Duplicate feature | Medium | Merge or consolidate |

## Example Review

### Before (Non-compliant)
```nix
# modules/features/bad-example.nix
{pkgs, ...}: {
  # Missing registration!
  services.example.enable = true;  # No guard
  # Should check config.my.hostName == "lumquat" here
}
```

### After (Compliant)
```nix
# modules/features/good-example.nix
_: {
  my.modules.nixos.example = lib.mkIf config.my.hasMonitoring _: {
    services.example.enable = true;
  };
}
```

## Reference

See `/skill:dend-feature` for deep-dive review.
