#!/usr/bin/env bash
# provision-host.sh — turn a minimal NixOS install into a configured host.
#
# Run from a dev machine. The target needs nothing but stock NixOS: no just,
# no dotfiles, no checkout, no root SSH, and no key for the operator user yet.
# That is the whole point — see docs/runbooks/provision-new-host.md.
#
# Usage:
#   scripts/provision-host.sh --host <name> --address <ip-or-name>
#                              [--branch <ref>] [--dry-run]
#                              [--skip-switch] [--skip-token]
#
# What it does, in order, and why each step is where it is:
#
#   1. Open ONE ssh connection to the operator account. If a key already works
#      it is used silently; otherwise ssh prompts for the password and the
#      connection is kept open as a ControlMaster, so every later step reuses
#      it. The password is therefore typed by the operator into ssh's own
#      prompt — never stored, never passed as an argument, never in a file.
#   2. Confirm the target really is a bare install, not a live host that already
#      has our tree; provisioning the wrong machine is the one mistake that
#      cannot be undone from here.
#   3. Install the BWS token at /var/lib/secrets/bws-access-token, root-only,
#      with no trailing newline (bws rejects one).
#   4. Switch the host from the flake by git reference, so no checkout is needed
#      on the target. This is what makes the whole thing repeatable.
#   5. Verify: key auth works on a fresh connection, password auth over SSH is
#      refused, the console password is untouched, and the host is on the
#      tailnet.
#
# Everything after step 3 is derived by the host from that one token: the
# tailscale node key, the FlakeHub and Cachix tokens, and (on hosts that turn
# chezmoiActivation on) the dotfiles. The token is the only secret the operator
# supplies, and it is the only one that cannot be derived.
set -euo pipefail

host=""
address=""
branch="main"
dry_run=false
skip_switch=false
skip_token=false

die() { echo "provision: $*" >&2; exit 1; }
say() { printf '\n==> %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }

usage() {
  sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) host="${2:-}"; shift 2 ;;
    --address) address="${2:-}"; shift 2 ;;
    --branch) branch="${2:-}"; shift 2 ;;
    --dry-run) dry_run=true; shift ;;
    --skip-switch) skip_switch=true; shift ;;
    --skip-token) skip_token=true; shift ;;
    -h | --help) usage 0 ;;
    *) die "unknown argument: $1 (try --help)" ;;
  esac
done

[[ -n "$host" ]] || die "--host is required (the flake attribute, e.g. calamansi)"
[[ -n "$address" ]] || die "--address is required (IP or name reachable from here)"

# The operator account these hosts use. Kept as one variable because the
# fallback-port and key checks below need it too.
operator_user="podman"
ssh_base=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)

# A control socket makes the password prompt happen exactly once. Everything
# after first contact runs over the multiplexed connection, so sudo's
# timestamp and the established session are reused rather than re-authenticated.
ctl_dir="$(mktemp -d 2>/dev/null || mktemp -d -t provision)"
ctl_sock="${ctl_dir}/ssh"
cleanup() {
  ssh -o ControlPath="${ctl_sock}" -O exit "${operator_user}@${address}" 2>/dev/null || true
  rm -rf "${ctl_dir}"
}
trap cleanup EXIT

run_target() {
  ssh -o ControlPath="${ctl_sock}" "${operator_user}@${address}" "$@"
}

say "target ${operator_user}@${address} (flake attribute: ${host})"
if $dry_run; then
  info "DRY RUN — nothing will be changed on the target."
fi

# ── 1. One connection, authenticated once ───────────────────────────────────
#
# BatchMode first: if a key already works there is no prompt at all. Only when
# that fails do we open an interactive session, where ssh asks for the password
# on the operator's own terminal. Nothing here reads or stores the password.
say "connecting"
#
# Detect an existing key with a command that cannot be satisfied by a
# multiplexed master. A plain `ssh host true` is NOT a usable test: if a
# ControlMaster for that host already exists (Rex, an editor, another terminal,
# or an earlier run of this script), ssh rides it and returns success without
# authenticating anything. That produced a false "authenticated with a key" on
# the first real dry-run against calamansi. `ControlMaster=no` plus an explicit
# ControlPath that does not exist forbids reuse, so this really authenticates.
probe_sock="${ctl_dir}/probe"
if ssh "${ssh_base[@]}" -o BatchMode=yes -o PasswordAuthentication=no \
  -o ControlMaster=no -o "ControlPath=${probe_sock}" \
  "${operator_user}@${address}" true 2>/dev/null; then
  info "authenticated with a key"
  ssh_extra=(-o BatchMode=yes -o PasswordAuthentication=no)
else
  info "no key accepted yet; ssh will ask for the password once."
  info "For a bare install that password is the BWS item ${host}-podman-user-password."
  # Password-only for the interactive hop. Without this, ssh offers each key
  # first, and a bare box rejects them all; OpenSSH counts those against
  # MaxAuthTries and disconnects with "Too many authentication failures" before
  # it ever shows a password prompt. Observed against calamansi.
  ssh_extra=(-o PubkeyAuthentication=no -o PreferredAuthentications=password
    -o NumberOfPasswordPrompts=3)
fi

# `ControlMaster=yes` on a socket nothing else owns. `control` (not `auto`) so an
# unrelated master in ~/.ssh/config cannot be mistaken for ours.
ssh "${ssh_base[@]}" "${ssh_extra[@]}" \
  -o ControlMaster=yes -o ControlPath="${ctl_sock}" -o ControlPersist=600 \
  "${operator_user}@${address}" true \
  || die "could not establish a session to ${operator_user}@${address}"
info "session established and multiplexed"

target_info=$(run_target 'printf "%s|%s|%s" "$(hostname)" "$(cat /etc/hostname 2>/dev/null || echo -)" "$(test -f /var/lib/secrets/bws-access-token && echo token-present || echo no-token)"') \
  || die "connected but could not read target state"
target_hostname="${target_info%%|*}"
rest="${target_info#*|}"
configured_hostname="${rest%%|*}"
token_state="${rest#*|}"
info "kernel hostname: ${target_hostname}"
info "configured hostname: ${configured_hostname}"
info "BWS token: ${token_state}"

# A bare install is hostnamed `nixos` (the installer default) and has no
# checkout of our tree. If either is already true of this machine, it has been
# provisioned before and re-running blindly could clobber a live host.
if [[ "$target_hostname" != "nixos" && "$configured_hostname" != "$host" ]]; then
  info "note: hostname is '${target_hostname}', not 'nixos' and not '${host}' — this"
  info "      machine has been configured before. Re-provisioning it will overwrite"
  info "      its BWS token. Pass --skip-token to keep the existing one."
fi

if $dry_run; then
  say "would install the BWS token (${token_state}) and switch to ${branch}"
  exit 0
fi
# ── Helper: privileged commands ──────────────────────────────────────────────
#
# sudo caches "already authenticated" PER TTY by default (timestamp_type=tty).
# The obvious approach — `ssh -t host sudo -v`, then `sudo -n` afterwards — does
# not work, and it is what broke the first real run:
#
#   `ssh -t CMD` allocates a PTY for that one command and destroys it on exit,
#   so the cached timestamp is keyed to a terminal that no longer exists. The
#   next connection gets a new PTY, sudo sees no timestamp, and every later
#   `sudo -n` fails with "a password is required" even though the password was
#   typed correctly seconds earlier.
#
#   `sudo -v -t global` looks like the fix but is not: `-t` is a Defaults
#   setting, not a flag, and sudo 1.9.17 rejects it on `-v` with a usage error
#   (verified on calamansi and lumquat). Writing `Defaults timestamp_type=global`
#   into sudoers would work, but permanently loosens the host to speed up a
#   one-time bootstrap — the wrong trade.
#
#   `sudo -S` reads the password from stdin and needs no TTY at all. Verified
#   against calamansi: it consumes the piped password and reports a wrong one
#   correctly ("1 incorrect password attempt"). So the password is read once,
#   interactively, and piped to sudo per command. It never enters the
#   environment, a file, an argument list, or a shell history.
sudo_pw=""

# Run a command as root, feeding the cached sudo password on stdin.
as_root() {
  [[ -n "$sudo_pw" ]] || die "internal: sudo password not set"
  run_target "sudo -S -p '' $1" <<<"$sudo_pw"
}

ask_sudo_password() {
  local attempts=0
  while (( attempts < 3 )); do
    read -rsp "sudo password for ${operator_user}@${address}: " sudo_pw; echo
    [[ -n "$sudo_pw" ]] || { info "empty password"; continue; }
    if as_root true >/dev/null 2>&1; then
      info "sudo: authorised"
      return 0
    fi
    ((attempts++)) || true
    info "sudo: rejected (attempt ${attempts} of 3)"
    sudo_pw=""
  done
  die "could not obtain sudo"
}

# ── 2 & 3. The BWS token ────────────────────────────────────────────────────
#
# One token, written root-only, with no trailing newline. Everything the host
# needs is resolved from it at boot by host-secrets-populate.
if $skip_token || [[ "$token_state" == "token-present" ]]; then
  if $skip_token; then
    info "note: --skip-token given, so an existing token will not be replaced."
  else
    say "BWS token already present — leaving it alone"
  fi
  # The switch below still needs root, so sudo has to be obtained even when the
  # token step is skipped.
  if ! $skip_switch; then
    say "obtaining sudo on the target"
    ask_sudo_password
  fi
else
  # Obtain sudo BEFORE asking for the token. The first real run asked for the
  # token and then died in sudo, wasting a paste of a secret BWS shows once.
  say "obtaining sudo on the target"
  ask_sudo_password

  say "installing the BWS access token"
  info "paste it at the prompt. BWS shows a token once, so this comes from the"
  info "personal Bitwarden vault: item 'BWS Chezmoi Access Token'."
  read -rsp "BWS access token: " token; echo
  token="${token#"${token%%[![:space:]]*}"}"
  token="${token%"${token##*[![:space:]]}"}"
  token="${token#\"}"; token="${token%\"}"
  [[ -n "$token" ]] || die "empty token"
  # 0.<uuid>.<client_secret>:<base64-key> — the key half is *standard* base64 so
  # it may contain +, / and =; the client-secret half is base64url.
  [[ "$token" =~ ^0\.[A-Za-z0-9-]+\.[A-Za-z0-9_-]+:[A-Za-z0-9+/=]+$ ]] \
    || die "that does not look like a BWS access token (expected 0.<uuid>.<secret>:<base64>)"

  # base64 so the token survives the hop unchanged: no newline ambiguity, and
  # only [A-Za-z0-9+/=] characters, so it is safe as a quoted shell argument.
  #
  # It is passed as an ARGUMENT rather than on stdin on purpose: stdin is
  # carrying the sudo password (`sudo -S`). An earlier draft used two herestring
  # redirections, which does not work — the second silently replaces the first,
  # so the token would have been fed to sudo as the password.
  #
  # A brief appearance in the remote shell's argv is the acceptable cost; it is
  # not written to disk anywhere and is unset immediately after.
  token_b64=$(printf '%s' "$token" | base64 | tr -d '\n')
  as_root "sh -c 'printf %s \"\$1\" | base64 -d | install -m 0600 -o root -g root /dev/stdin /var/lib/secrets/bws-access-token' _ '${token_b64}'" \
    || die "could not install the BWS token"
  unset token token_b64

  # Verify what actually landed, rather than trusting the pipeline: mode, owner,
  # size, and that the file ends in a base64 character rather than a newline
  # (bws rejects a trailing newline, and the failure it reports is about a MAC
  # mismatch, which points nowhere useful).
  verify=$(as_root "sh -c '
    f=/var/lib/secrets/bws-access-token
    [ -f \"\$f\" ] || { echo MISSING; exit 1; }
    printf \"mode=%s owner=%s:%s bytes=%s last=%s first=%s\\n\" \\
      \"\$(stat -c %a \"\$f\")\" \"\$(stat -c %U \"\$f\")\" \"\$(stat -c %G \"\$f\")\" \\
      \"\$(wc -c < \"\$f\")\" \"\$(tail -c1 \"\$f\" | od -An -tx1 | tr -d \" \\n\")\" \\
      \"\$(head -c2 \"\$f\")\"
  '") || die "token verification failed"
  info "${verify}"
  echo "$verify" | grep -q 'mode=600 owner=root:root' \
    || die "token file has the wrong mode or owner"
  echo "$verify" | grep -q 'first=0\.' \
    || die "token file does not start with the expected '0.' prefix"
  echo "$verify" | grep -q 'last=0a' \
    && die "token file ends in a newline, which bws rejects"
  say "BWS token installed"
fi

# ── 4. Switch ───────────────────────────────────────────────────────────────
if $skip_switch; then
  say "skipping the switch (--skip-switch)"
else
  # By git reference: the target fetches the flake itself, so no checkout and no
  # rsync of the tree. This is what makes provisioning a bare host one command.
  flake="git+https://github.com/ashebanow/nix-config?ref=${branch}"
  say "switching ${host} to ${flake}"
  info "this is the point where password-only SSH stops working"
  info "(PasswordAuthentication=false) and the operator key takes over."

  # `sudo -S` with `-p ''`: the password comes on stdin, so this needs no TTY
  # and works through the multiplexed connection. Note `-S` reads exactly one
  # line for the password and leaves the rest of stdin alone, and
  # nixos-rebuild does not read stdin itself, so the two do not compete.
  #
  # The switch restarts sshd. That kills the ControlMaster, so the verification
  # below opens fresh connections (it does anyway) and a failure here is
  # reported rather than retried blindly: `nixos-rebuild` is atomic per
  # generation, so the host is either fully on the new generation or fully on
  # the old one.
  as_root "nixos-rebuild switch --flake '${flake}#${host}'" \
    || die "nixos-rebuild switch failed — the host is still on its previous generation"

  say "generation list"
  as_root 'nix-env --list-generations --profile /nix/var/nix/profiles/system' 2>/dev/null | tail -3 || true
fi

# ── 5. Verify ───────────────────────────────────────────────────────────────
say "verifying"

# Key access, freshly, in a NEW connection that cannot be multiplexed: this is
# the credential the switch was supposed to put in place. Every check in this
# section pins ControlMaster=no to a socket that does not exist, for the reason
# given at the connection step — a reused master would report whatever the
# original session negotiated, not what a stranger gets today.
fresh_sock="${ctl_dir}/fresh"
fresh_ssh() {
  ssh "${ssh_base[@]}" -o ControlMaster=no -o "ControlPath=${fresh_sock}" "$@"
}

if fresh_ssh -o BatchMode=yes -o PasswordAuthentication=no -o PubkeyAuthentication=yes \
  "${operator_user}@${address}" true 2>/dev/null; then
  info "operator key: accepted"
else
  info "operator key: NOT accepted (the switch may still be settling, or the key"
  info "               is not in base.nix's authorizedKeys)"
fi

# Password auth over SSH must now be refused. Offering only the password method
# with zero prompts makes the server state its answer instead of hanging on a
# prompt nobody will answer.
if fresh_ssh -o BatchMode=yes -o PubkeyAuthentication=no \
  -o PreferredAuthentications=password -o NumberOfPasswordPrompts=0 \
  "${operator_user}@${address}" true 2>&1 | grep -qi "permission denied"; then
  info "SSH password auth: refused (correct — key only)"
else
  info "SSH password auth: still accepted — expected to be off after the switch"
fi

# The console password is a different credential and must survive. Check the
# shadow entry has a real hash; this is what break-glass depends on.
console=$(as_root "getent shadow ${operator_user}" 2>/dev/null | cut -d: -f2 | cut -c1-3 || echo "?")
case "$console" in
  '$y$' | '$6$' | '$2*') info "console password: present (hash prefix ${console}) — break-glass intact" ;;
  '' | '!'* | '*'*) info "console password: ABSENT — no break-glass login on the console" ;;
  *) info "console password: could not read (prefix '${console}')" ;;
esac

# Tailnet, if this host enables access. Absence is not fatal to the switch but
# means the host has no tailnet identity yet.
tn=$(run_target 'tailscale ip -4 2>/dev/null | head -1 || echo -' 2>/dev/null || echo "-")
if [[ "$tn" != "-" && -n "$tn" ]]; then
  info "tailnet address: ${tn}"
else
  info "tailnet address: none yet — check 'systemctl status host-secrets-populate'"
  info "                 (it must succeed before tailscaled-autoconnect can enrol)"
fi

# Do not leave the password cached in this shell.
unset sudo_pw

say "done"
info "next: confirm the host is healthy, then record its address in docs/network.md"
