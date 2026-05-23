---
description: Review feature module for dendritic pattern compliance
---

# Feature Module Review

Review a feature module for dendritic pattern compliance. Starting with a perfect score of 100, deduct points for each infraction below. After the review is done, attempt to fix as many infractions as possible, then re-evaluate the checklist. Repeat this process up to five times. If the score doesn't improve after each round, throw the results away and start over.

## Quick Checklist

For each feature module in `modules/features/`:

### Signature

- [ ] Uses `_: { ... }` (flake-parts module signature) [-10 points if not used]
- [ ] Ignores unused arguments [-1 point per infraction]

### Registration [-1 point per infraction]

- [ ] Registers into `my.modules.nixos.<name>` OR
- [ ] Registers into `my.modules.home-manager.<name>` OR
- [ ] Registers into both (cross-cutting)

### Guards

- [ ] Uses `lib.mkIf config.my.<flag>` for conditional logic [-1 point per infraction]
- [ ] No hardcoded hostname checks like `config.my.hostName == "lumquat"` [-1 point per infraction]
- [ ] No unused options [-1 point per infraction]

### Naming

- [ ] Container key matches filename: `llm-serve.nix` → `my.modules.nixos.llm-serve` [-1 point per infraction]
- [ ] Descriptive, lowercase names with hyphens [-1 point per infraction]

### Structure

- [ ] Single concern per file [-10 pointa per infraction]
- [ ] No duplicate functionality with other features [-1 point per infraction]
- [ ] Imports are explicit [-1 point per infraction]

## Common Issues to Flag

| Issue                | Severity | Fix                                        |
| -------------------- | -------- | ------------------------------------------ |
| Missing registration | High     | Add `my.modules.nixos.<name> = _: { ... }` |
| Hostname check       | High     | Replace with capability flag               |
| Missing mkIf guard   | Medium   | Add `lib.mkIf config.my.<flag>`            |
| Wrong container      | Medium   | Move to correct `my.modules.*`             |
| Duplicate feature    | Medium   | Merge or consolidate                       |

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

See `/dend-review-arch` for deep-dive review.
