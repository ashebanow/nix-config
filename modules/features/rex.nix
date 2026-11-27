# Rex — "the multiplexer for all work", plus the servers that make sessions
# reachable from other machines.
#
# Two roles, in two deferred modules. They are layers, not alternatives: the
# client is a prerequisite for the server, and on macOS it is the whole story.
#
#   rex-client   Home Manager. programs.rex: the `rex` command, the xterm-rex
#                terminfo entry, and the ssh guard. On macOS the Rex app runs
#                the server, so nothing else applies there.
#
#   rex-server   NixOS. services.rex.enable: one server for this host's own
#                account, published through Rex's OWN tailnet node (tsnet) as
#                https://<host>-rex.<tailnet>.ts.net.
#
# Both NixOS hosts run the same shape — lumquat serves `podman`, yuzu serves
# `ashebanow` — because on a single-operator tailnet the useful distinction is
# "which account does this box serve", not "which account may reach it".
#
# ## Why tsnet, and not every other approach that was tried
#
# Rex's native integration is the embedded node: `services.rex.tailscale`
# makes the server run its own Tailscale node, obtain its own HTTPS
# certificate, and publish natively. That is exactly what the Rex app — the
# primary client — requires, and it means the operator never exposes the
# service by hand.
#
# The earlier designs in this repo each failed for the same underlying reason:
# they made the service available manually.
#
#   1. `tailnet://:<port>` (empty host) crash-looped. Rex expands the empty
#      host to every tailnet address; `tailscale0` has no IPv6; the IPv6 bind
#      fails with "cannot assign requested address" and systemd restarts it
#      forever.
#   2. Pinning the IPv4 address fixed the bind, but hardcoded an address that
#      drifts on re-auth — and left the listener as raw TCP with no TLS.
#   3. Adding Tailscale Serve gave the app its HTTPS, but reintroduced manual
#      exposure, which is the thing tsnet exists to remove.
#
# So: no extraListen, no tailscaleServe, no address option, no accounts file.
#
# ## Why there is no login server
#
# The Rex login server maps *many* Tailscale identities onto *many* local
# accounts. It cannot use tsnet at all — `rex login-server` has no
# `--tailscale` flag; only `rex server run` does — so it can only publish via
# the host's tailscaled plus Serve, i.e. exactly the manual path above. On this
# tailnet every host serves one account, so the shared server is both
# sufficient and the only one that can publish natively. Account restriction
# comes from Tailscale itself (owner-only on the node) rather than an accounts
# file.
#
# ## Notes
#
# The flake's modules are imported unconditionally and gated with mkIf, the
# same pattern as dank-material-shell.nix: a conditional import recurses,
# because the module system collects `imports` before it can settle `config`,
# and the Rex modules read `config` in turn. Both are inert until enabled.
#
# Why lumquat sets no `my.rexClient`: it is a deliberately minimal headless
# host whose Home Manager profile carries only the baseline CLI set (everything
# else appears in the dev shell on demand), and it has no capabilities.nix for
# Home Manager to read flags from. Its `rex` binary comes from the NixOS
# module's `installClient` instead — same package, system profile — so the
# minimalism costs nothing here. Do not "fix" that by adding a Home Manager
# fragment to lumquat; see docs/rex.md.
{ inputs, ... }: {
  my.modules.home-manager.rex-client =
    {
      lib,
      config,
      ...
    }:
    {
      imports = [ inputs.rex.homeManagerModules.default ];

      config = lib.mkIf config.my.rexClient {
        programs.rex.enable = true;

        # Deliberately not set:
        #
        # * services.rex (the personal user server). A host that must be
        #   attachable from elsewhere runs the NixOS `my.rexServer` instead,
        #   which survives logout and reuses the system tailscaled; a second
        #   per-account server on the same socket would just be a second answer
        #   to the same question. On the Macs there is no systemd at all.
        # * programs.rex.config — ~/.config/rex/init.lua stays hand-managed
        #   until there is a keybinding set worth declaring.
        #
        # programs.ssh.enable is also not set here: the Rex modules add their
        # guard to `programs.ssh.includes`, and ~/.ssh/config is chezmoi's on
        # these hosts. Setting it would have Home Manager and chezmoi write the
        # same file in turn. The module prints a warning instead; the dotfiles
        # repo carries the guard. See docs/rex.md.
      };
    };

  my.modules.nixos.rex-server =
    {
      lib,
      config,
      ...
    }:
    {
      # No import for the Rex module here — it is imported once, by the
      # flag-agnostic fragment at the end of this file. `services.rex` is a
      # single option tree, so importing it twice re-declares it and the module
      # system rejects the duplicate.

      config = lib.mkIf config.my.rexServer {
        services.rex = {
          enable = true;

          # The server serves exactly one account, so it runs as that account
          # rather than the module's `rex` system user. The account must already
          # exist; this only points at it.
          user = config.my.rexServerUser;
          group = "rex";

          # Local access: the default `/run/rex/server.sock`, group-readable so
          # a member of the rex group (and the owning account, which owns it)
          # reaches it. 0660 is the module default; stated because the group
          # matters as much as the owner.
          socketMode = "0660";

          # Remote access is Rex's OWN tailnet node (tsnet), not the host's
          # tailscaled. This is the integration Rex is built around: the server
          # embeds a node, obtains HTTPS certificates itself, and serves at
          # https://<hostname>.<tailnet>.ts.net with no port.
          #
          # That is what the Rex app and any bare-hostname client require. The
          # earlier designs here failed in sequence for the same underlying
          # reason — they made the service available *manually*:
          #
          #   1. `tailnet://:<port>` (empty host) crash-looped: Rex expands the
          #      empty host to every tailnet address, `tailscale0` has no IPv6,
          #      and the IPv6 bind fails with "cannot assign requested address".
          #   2. Pinning the IPv4 address fixed the bind but hardcoded an
          #      address that drifts on re-auth, and left the listener as raw
          #      TCP with no TLS.
          #   3. Adding Tailscale Serve on top gave the app its HTTPS, but that
          #      is exactly the manual exposure tsnet exists to remove.
          #
          # So: no extraListen, no tailscaleServe, no address to maintain.
          tailscale = {
            enable = true;

            # <host>-rex, never the module's `rex` default: two hosts with the
            # default would fight over one node name, and this matches the
            # convention the Rex app already uses on the Macs
            # (miraclemax-rex, bergamot-rex).
            hostname = "${config.my.hostName}-rex";

            # A one-time (non-reusable) key per node, so a leaked key enrolls
            # nothing. Written by host-secrets-populate from the host scope's
            # REX_<HOST>_TS_AUTHKEY. The key is spent at first enrollment; the
            # identity then persists under /var/lib/rex/tsnet/<hostname>.
            authKeyFile = "/run/secrets/rex-tailscale-auth-key";

            # Owner-only (the default): just the Tailscale account that
            # enrolled the node. Turning this on would admit every tailnet
            # member the ACLs allow, which is broader than a personal machine
            # needs. A tagged node has no owner and would require it.
            allowTailnetMembers = false;
          };

          # Unused with a tsnet node, but harmless to leave unset; stated for
          # searchability: nothing else listens on the tailnet.
          extraListen = [ ];
        };

        # Group for local socket access. Creating it here rather than relying on
        # the module keeps the membership explicit and lets my.rexServerUser be
        # any account.
        users.groups.rex = { };

        # The account the server runs as is also the account most likely to
        # attach locally. The server's own User= is enough for it to *own* the
        # socket; group membership makes the 0660 mode meaningful when Rex runs
        # a terminal under a different effective group.
        users.users.${config.my.rexServerUser}.extraGroups = [ "rex" ];

        # Order the service after the key it needs.
        #
        # services.rex declares LoadCredential from
        # /run/secrets/rex-tailscale-auth-key, and /run/secrets is tmpfs that
        # host-secrets-populate fills at boot. The Rex module knows nothing
        # about that unit, so the two start in parallel and systemd can try to
        # exec rex before the file exists:
        #
        #   rex.service: Failed to set up credentials: No such file or directory
        #   rex.service: Failed at step CREDENTIALS
        #
        # That failed the whole activation on the first switch. The one-time
        # auth key was NOT spent (systemd aborted before exec), but a retry loop
        # that lost the race twice in a row would leave a confusing state, so
        # depend on it properly rather than relying on the restart to fix it.
        #
        # Requires= as well as After= — without the key the service cannot
        # enroll, so a missing populator is a hard failure, not something to
        # start optimistically against. Restart=on-failure in the Rex module
        # then covers the case where the key exists but enrolment fails.
        systemd.services.rex = {
          requires = [ "host-secrets-populate.service" ];
          after = [ "host-secrets-populate.service" ];
        };

        assertions = [
          {
            assertion = config.my.rexServerUser != "";
            message = "my.rexServer is enabled but my.rexServerUser is empty — set it to the account whose sessions the server should serve.";
          }
        ];
      };
    };

  # The Rex NixOS module, imported exactly once. `services.rex` is a single
  # option tree, so importing it from more than one fragment re-declares it and
  # evaluation fails. It is inert here — every option keeps its default until
  # rex-server sets it.
  #
  # BOX-339 — `package` is overridden HERE, not by a nixpkgs overlay.
  #
  # Rex's release archive has no enclosing directory, and its flake sets
  # `sourceRoot = "."` to match. stdenv then runs `chmod -R u+w -- .`, which
  # walks into Nix's own root-owned, read-only `builder.json` and `env-vars` and
  # dies with EPERM — breaking `nix build` of every host with Rex enabled, for
  # any non-root builder user. lib/overlays/rex.nix carries the patch and the
  # full explanation.
  #
  # It has to be applied on the option because the Rex module resolves its
  # default package from its *own* flake (`self.packages.<system>.rex`), not
  # from `pkgs`, so a package-set overlay never reaches it.
  my.modules.nixos.rex-module = { pkgs, ... }: {
    imports = [ inputs.rex.nixosModules.default ];

    services.rex.package = pkgs.rex-patched;
  };
}
