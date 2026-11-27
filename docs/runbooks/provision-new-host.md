# Provisioning a new NixOS host

How a bare `nixos-generate-config` install becomes a host this repo manages.
Written while bringing up calamansi (BOX-324), from the things that actually
went wrong rather than from what the design intended.

## The one idea

> The BWS access token is the only secret a host cannot derive for itself.

Everything else is computed from it at boot by `host-secrets-populate`:

| Derived at boot | From |
| --- | --- |
| `<HOST>_TAILSCALE_AUTH_KEY` → `/run/secrets/tailscale-auth-key` | BWS scope `host-<host>` |
| FlakeHub token → `/run/secrets/flakehub-token` | BWS |
| Cachix token | BWS |
| dotfiles clone + apply | chezmoi, **only if** `chezmoiActivation = true` |

So provisioning needs exactly one operator secret. Anything else you find
yourself pasting is a sign the bootstrap has grown a dependency it should not
have.

## What a bare install already has

Stock NixOS gives you `ssh`, `sudo`, `nix`, `git`, `ip`, and a password for the
installer's user. It does **not** have `just`, `~/.justfile`, a checkout of this
repo, or a key for the operator user. Anything the bootstrap needs must fit in
the first list.

This is why the recipe path is a dead end on a fresh box: this repo's `justfile`
starts with `import "~/.justfile"`, which chezmoi installs from the dotfiles
repo, which needs provisioning. Use `scripts/provision-host.sh`, which uses only
the first list.

### `/etc/nixos/` is installer scratch — the flake is authoritative

A bare install's `/etc/nixos/configuration.nix` is the stock `nixos-generate-config`
template plus whatever was hand-edited on the box. **Our flake never reads it:**
`nixos-rebuild switch --flake ...` builds from `hosts/<host>/`, and the box's own
`/etc/nixos/` is not an input. Nothing in it needs preserving, and anything
edited there is silently discarded by the first switch.

This is worth stating because it already cost a debugging round. Calamansi's
stock `configuration.nix` declares `boot.loader.systemd-boot.enable = true`, so
the machine booted fine and looked correctly configured — yet the flake failed
nixpkgs' boot-loader assertion, because `nixos-generate-config` writes only
`hardware-configuration.nix` and deliberately omits `boot.loader`. The file that
prevented the symptom was not in the flake at all.

Corollary: when a host fails to evaluate on an option the installer clearly set,
look at `hosts/<host>/`, not at `/etc/nixos/`.

## Steps

```sh
# From a dev machine. Password is typed once, into ssh's own prompt.
scripts/provision-host.sh \
  --host calamansi \
  --address 10.40.0.61 \
  --branch feat/box-311-integration
```

Or `just provision calamansi 10.40.0.61 <branch>`.

What it does:

1. **One connection.** Tries a key; if none is accepted, asks for the password
   (BWS item `<host>-podman-user-password`) and keeps the session open as a
   ControlMaster so nothing authenticates twice.
2. **Checks it is really a bare box.** A machine already named after a host, or
   already holding a token, gets a warning — re-provisioning overwrites the
   token.
3. **Primes sudo** with a TTY, *before* any token exists.
4. **Writes the token** to `/var/lib/secrets/bws-access-token`, root-only, mode
   0600, no trailing newline.
5. **Switches** from `git+https://github.com/ashebanow/nix-config?ref=<branch>`,
   so no checkout is needed on the target.
6. **Verifies** key auth, that password auth is refused, that the console
   password survives, and that the host is on the tailnet.

## Why the sequencing is what it is

- **sudo before the token.** A password prompt appearing while a token is on
  stdin can consume the token as the password: it fails confusingly and pushes a
  real secret through PAM. The script therefore runs `sudo -v` first and then
  every write uses `sudo -n`, so a surprise prompt fails loudly instead.
- **Switch by git reference.** Copying the tree (rsync, scp, a checkout on the
  target) is what makes first bring-up manual. A flake reference means the
  target fetches and builds its own config — and builds it *natively*, which
  matters: cross-building from a Darwin machine produces broken terminfo on a
  case-insensitive store (see `docs/handoff-observability-resume.md`).
- **The switch is the pivot.** `base.nix` sets `PasswordAuthentication = false`
  and installs the operator key, so password-over-SSH ends exactly here. The
  console password is a *separate* credential (PAM, `/etc/shadow`) and is
  untouched — that is the break-glass path. `users.mutableUsers = true`, so the
  install-time password persists across every later switch.

## Gotchas, all hit for real

1. **`ssh host true` is not a credential probe.** If a ControlMaster for that
   host already exists — Rex, an editor, another terminal, an earlier run — ssh
   rides it and succeeds without authenticating anything, so the script reports
   "authenticated with a key" when it did no such thing. Probes must pin
   `ControlMaster=no` with a socket path that does not exist.
2. **Keys before passwords exhaust MaxAuthTries.** On a bare box every offered
   key is rejected, and OpenSSH disconnects with "Too many authentication
   failures" *before* showing a password prompt. The password hop must pass
   `-o PubkeyAuthentication=no -o PreferredAuthentications=password`.
3. **Never compare `$(hostname)` to decide "is this the local host".** A bare
   install is hostnamed `nixos`; you will realistically name it by IP, because
   there is no DNS entry yet. Worse, `/etc/hostname` can already say `calamansi`
   while the running kernel hostname is still `nixos` — the file was edited but
   never applied. Match against the local IP set as well.
4. **Root SSH is closed by our own config** (`PermitRootLogin = "no"`). Any path
   shaped `ssh root@host` only works on a machine that has never had our config,
   and even then has no key. Do the work as the operator user with sudo.
5. **`sudo -v` + `ssh -t` does not persist a sudo timestamp.** sudo caches
   "already authenticated" per TTY (`timestamp_type` defaults to `tty`), and
   `ssh -t CMD` allocates a PTY for one command and destroys it on exit — so the
   timestamp is keyed to a terminal that no longer exists, and every later
   `sudo -n` fails with "a password is required" despite the password having
   just been typed. `sudo -v -t global` is not a fix: `-t` is a Defaults
   setting, not a flag, and sudo 1.9.17 rejects it on `-v`. Use `sudo -S`
   (password on stdin), which needs no TTY. Proven against calamansi: a wrong
   password exits 1, the right one runs as root.
6. **Do not put two herestrings on one command.** `cmd <<<"$a" <<<"$b"` keeps
   only the second — which in this script would have fed the BWS token to sudo
   as the password. When stdin carries the sudo password, pass everything else
   as quoted arguments.
7. **`-t` does not survive multiplexing** when stdin is not a terminal. Interactive
   steps need a real terminal; run the script from a shell, not from a harness
   that pipes stdin. (With `sudo -S` this now only affects the password `read`.)
8. **`/var/lib/secrets/bws-access-token` must have no trailing newline.** `bws`
   rejects the token otherwise, and the error is about a MAC mismatch, which
   does not point at the newline. The script asserts this after writing.
9. **Ask for sudo before asking for the token.** A failure after the token paste
   wastes a secret that BWS shows exactly once.

## If it goes wrong

- The switch fails: the host is still on its previous generation. Nothing is
  half-applied; `nixos-rebuild` is atomic per generation.
- The token is wrong: `systemctl status host-secrets-populate` shows why, and
  tailscale never enrols. Re-run the script (it will notice the token is
  present and leave it, unless you pass a fresh one).
- Locked out of SSH: the console password still works, because the switch does
  not touch it. That is the whole reason it is kept.
- Need to go back: `sudo nix-env --list-generations --profile
  /nix/var/nix/profiles/system`, then `sudo /nix/var/nix/profiles/system-<N>-link/bin/switch-to-configuration switch`.

## After it succeeds

- Record the address in `docs/network.md` and anything that references it.
- `ssh podman@<tailnet-name>` should work with no password from anywhere on the
  tailnet.
- The host now has `just`, `~/.justfile` and its checkout situation resolved,
  so `just bootstrap-bws` works there for any future re-keying.
