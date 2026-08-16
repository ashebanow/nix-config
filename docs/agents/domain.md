# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Before exploring, read these

- **`AGENTS.md`** at the repo root — project goals, capability-flag model, and deployment conventions.
- **`docs/`** — architecture notes (`architecture.md`, `plan.md`) for the dendritic module layout.
- **`docs/adr/`** — read ADRs that touch the area you're about to work in.

If any of these files don't exist, **proceed silently**. Don't flag their absence; don't suggest creating them upfront.

## File structure

Single-context repo: one shared domain model for the whole config (module layout, capability flags, quadlet/secretspec patterns).

```
/
├── AGENTS.md
├── hosts/<host>/configuration.nix   ← capability flags per host
├── modules/features/<svc>.nix       ← feature modules (mkIf-guarded)
├── compose/<svc>/                   ← quadlet units, populate scripts, ts-serve
├── secretspec.toml                  ← shared BWS secret declarations + scopes
├── scripts/populate-host-secrets.sh ← host-secret file materialization
└── docs/                            ← architecture + plans
```

## Flag ADR conflicts

If your output contradicts an existing decision, surface it explicitly rather than silently overriding.
