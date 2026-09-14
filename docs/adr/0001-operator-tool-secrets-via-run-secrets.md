# Operator-tool secrets on a headless host come from `/run/secrets`, not a user-level BWS token

Status: accepted (2026-09-14, BOX-179; decided in BOX-177)

Lumquat is headless: the only people on it are the operator account
(`my.baseUsername`, `podman`) over SSH and root. Until now every secret it
held was consumed by a *service* — tailscale, determinate-nixd, the compose
stacks — and reached that service through `secretspec run` under
`bws-service`, whose BWS access token is a root-only file delivered by
`LoadCredential`. The operator's own shell has no BWS token and no keyring
(no secret service, no `secret-tool`, no D-Bus session), and
`SECRET_SYNC.md` stated the dev shell is not a secret channel there.

Replacing the Linear MCP with the `linear` CLI (BOX-176) introduced the
first secret an *interactive tool* on lumquat needs: `LINEAR_API_KEY`, for
agents running in the dev shell. It is a production secret in the
dotfiles glossary's sense (it lives in BWS and bills ashebanow's account;
its blast radius does not reach him as a person), so headless may carry
it — the question was only how it gets to a user process.

We decided: `host-secrets-populate.service` resolves a new secretspec scope,
**`dev`**, in a second `secretspec run` invocation and writes each value to
`/run/secrets/<name>` (tmpfs) with mode `0400`, owned by the operator user.
The consuming tool's Nix wrapper reads the file when the variable is absent
from the environment (`lib/overlays/linear-cli.nix`). The dev shell still
never talks to BWS.

## Considered options

**A user-level BWS token plus a per-invocation `secretspec run -S dev --
linear` wrapper.** Rejected: it mints a second bootstrap secret to
provision, rotate and protect on the host, in exchange for per-process
scoping that the threat model does not need (see consequences). It also
puts a BWS round trip — several seconds cold — in front of every command an
agent runs, or asks secretspec's cache to hide that.

**`linear auth login` into an OS keyring.** Rejected: there is no secret
service on a headless host, so the CLI's keyring path is dead there; on the
Darwin workstations it would also create a second, non-BWS copy of a
production secret.

**Fold `LINEAR_API_KEY` into the existing `host` scope.** Rejected: `host`
is documented as root-only system-service secrets. A user-readable file is
a different trust class; giving it a scope of its own keeps that visible in
`secretspec.toml` and keeps the `host` resolver from ever seeing operator
secrets.

## Consequences

- Any process running as the operator user can read
  `/run/secrets/linear-api-key`. This is the same exposure the Darwin
  workstations already accept for `~/.cache/env/bws_env.sh`, and the same
  account already holds `sudo` without a password; per-process isolation
  buys nothing here.
- `dev` secrets are optional (`required = false`): an absent value skips
  the file with a notice and never fails the unit, because no service
  depends on them. `host` secrets stay mandatory.
- The file lives in tmpfs and is rewritten at every boot by the same unit
  that writes the tailscale and flakehub files, so rotation is "rotate in
  BWS, restart `host-secrets-populate`" — no new procedure.
- Future operator-tool secrets go into `[scopes.dev]` and a `write_user`
  line in `scripts/populate-host-secrets.sh`; nothing else changes.
