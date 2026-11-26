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

# ── 2 & 3. The BWS token ────────────────────────────────────────────────────
#
# One token, written root-only, with no trailing newline. Everything the host
# needs is resolved from it at boot by host-secrets-populate.
if $skip_token; then
  info "note: --skip-token given, so an existing token will not be replaced."
elif [[ "$token_state" == "token-present" ]]; then
  say "BWS token already present — leaving it alone"
else
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

  # Prime sudo BEFORE any token is in flight.
  #
  # `sudo -v` needs a TTY to prompt, and a multiplexed session has none, so this
  # one call allocates `-t` and lets the operator type the sudo password into
  # ssh's own prompt. Doing it here — rather than inside the write below — is
  # what keeps sudo from ever seeing the token on its stdin: a password prompt
  # that appears mid-write could otherwise consume the token as the password,
  # which fails confusingly and pushes a real secret through PAM.
  say "obtaining sudo on the target"
  ssh -t "${ssh_base[@]}" -o ControlPath="${ctl_sock}" \
    "${operator_user}@${address}" \
    'if sudo -n true 2>/dev/null; then echo "sudo: already authorised"; else sudo -v; fi' \
    || die "could not obtain sudo"

  # The token travels base64-encoded on stdin: no shell quoting, no newline
  # ambiguity, and nothing on the command line that a process list could show.
  # sudo is invoked with `-n` so a surprise prompt fails loudly instead of
  # silently reading the token as a password.
  printf '%s' "$token" | base64 | run_target 'set -e
    sudo -n install -d -m 0700 /var/lib/secrets
    tmp=$(sudo -n mktemp /var/lib/secrets/.token.XXXXXX)
    sudo -n sh -c "base64 -d > \"$tmp\""
    # bws rejects a trailing newline. `base64 -d` reproduces the input exactly,
    # so none was added — assert that rather than assume it.
    if [ "$(sudo -n tail -c1 "$tmp" | xxd -p)" = "0a" ]; then
      sudo -n truncate -s -1 "$tmp"
    fi
    sudo -n chown root:root "$tmp"
    sudo -n chmod 0600 "$tmp"
    sudo -n mv -f "$tmp" /var/lib/secrets/bws-access-token
  ' || die "could not install the BWS token"
  unset token

  verify=$(run_target 'set -e
    f=/var/lib/secrets/bws-access-token
    sudo test -f "$f" || { echo MISSING; exit 1; }
    echo "mode=$(sudo stat -c %a "$f") owner=$(sudo stat -c %U:%G "$f") bytes=$(sudo wc -c < "$f")"
    # A token is `0.` + payload; check the two ends survive the round trip.
    sudo head -c2 "$f"; echo
  ' ) || die "token verification failed"
  info "${verify}"
  echo "$verify" | grep -q '^mode=600 owner=root:root' \
    || die "token file has the wrong mode or owner"
  echo "$verify" | grep -qx '0\.' \
    || die "token file does not start with the expected '0.' prefix"
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
  info "this is the point where the password-only SSH session stops being able to"
  info "authenticate (PasswordAuthentication=false) and the operator key takes over."

  # `-t` again: the rebuild is long-running and its progress output is worth
  # seeing live. sudo's timestamp was primed above, so this does not re-prompt.
  ssh -t "${ssh_base[@]}" -o ControlPath="${ctl_sock}" \
    "${operator_user}@${address}" \
    "set -e; sudo -n nixos-rebuild switch --flake '${flake}#${host}'" \
    || die "nixos-rebuild switch failed — the host is still on its previous generation"

  say "generation list"
  run_target 'sudo nix-env --list-generations --profile /nix/var/nix/profiles/system 2>/dev/null | tail -3'
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
console=$(run_target 'sudo getent shadow '"$operator_user"' | cut -d: -f2 | cut -c1-3' 2>/dev/null || echo "?")
case "$console" in
  '$y$' | '$6$' | '$2*') info "console password: present (hash prefix ${console}) — break-glass intact" ;;
  '' | '!'* | '*'*) info "console password: ABSENT — no break-glass login on the console" ;;
  *) info "console password: unrecognised hash prefix '${console}'" ;;
esac

# Tailnet, if this host enables access. Absence here is not fatal to the switch
# but means the host has no tailnet identity yet.
tn=$(run_target 'test -d /var/lib/tailscale && tailscale ip -4 2>/dev/null | head -1 || echo -' 2>/dev/null || echo "-")
if [[ "$tn" != "-" && -n "$tn" ]]; then
  info "tailnet address: ${tn}"
else
  info "tailnet address: none yet — check 'systemctl status host-secrets-populate'"
  info "                 (it must succeed before tailscaled-autoconnect can enrol)"
fi

say "done"
info "next: confirm the host is healthy, then record its address in docs/network.md"
