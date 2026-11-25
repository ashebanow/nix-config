# Rex — "the multiplexer for all work", plus the servers that make sessions
# reachable from other machines.
#
# Two roles, in two deferred modules, plus a third fragment that installs the
# login server's accounts file. They are layers, not alternatives: the client is
# a prerequisite for the servers, and on macOS it is the whole story. The two
# server roles are the only mutually exclusive pair.
#
#   rex-client        Home Manager. programs.rex: the `rex` command, the
#                     xterm-rex terminfo entry, and the ssh guard. On macOS the
#                     Rex app runs the server, so nothing else applies there.
#
#   rex-server        NixOS. services.rex.enable: one server for this host's
#                     own account, published through Rex's OWN tailnet node
#                     (tsnet) as https://<host>-rex.<tailnet>.ts.net.
#
#   rex-login-server  NixOS. services.rex.loginServer.enable: root process that
#                     names each caller through the host's tailscaled, maps it
#                     to a local account with modules/features/rex/accounts.jsonc
#                     (installed as /etc/rex/accounts.jsonc), and runs one Rex
#                     server per account as that account. Published through
#                     Tailscale Serve as https://<host>.<tailnet>.ts.net.
#
# Yuzu runs the shared server (it serves `ashebanow`, the account other devices
# attach to); lumquat runs the login server (it has no interactive account of
# its own, and a caller must be able to pick which account to be).
#
# ## Why the shared server uses tsnet, and not every other approach that was
# ## tried
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
# So the shared server has no extraListen, no tailscaleServe, no address option.
#
# ## Why the login server accepts exactly that manual path
#
# `rex login-server` has no `--tailscale` flag, so it cannot have a tsnet node:
# it can only publish through the host's tailscaled plus Serve. It is the one
# role that needs what Serve carries — the caller's Tailscale identity, which
# is what it maps onto a local account — and Serve owns 443, so clients reach
# it as https://<host>.<tailnet>.ts.net with no port and no `-rex` node. The
# identity arrives over a root-owned 0600 socket; the accounts file is the
# allowlist, and it is installed by this module (see rex-login-server below);
# nothing is copied by hand onto the host.
#
# ## Why the shared server needs no accounts file
#
# The shared server maps no identities: it serves the one account it runs as,
# so its restriction is Tailscale's own (the node is owner-only). Only the login
# server needs an allowlist, which is why the accounts file below is gated by
# `my.rexLoginServer` and absent on yuzu.
#
# ## Notes
#
# The flake's modules are imported unconditionally and gated with mkIf, the
# same pattern as dank-material-shell.nix: a conditional import recurses,
# because the module system collects `imports` before it can settle `config`,
# and the Rex modules read `config` in turn. All are inert until enabled.
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
  my.modules.nixos.rex-module = {
    imports = [ inputs.rex.nixosModules.default ];
  };

  # The login server's accounts allowlist, as a file. One fragment for every
  # host, gated below by `my.rexLoginServer` — there is only ever one accounts
  # file per host, and it is the same shape everywhere.
  my.modules.nixos.rex-login-server =
    {
      lib,
      config,
      ...
    }:
    {
      # `local` rather than `config`: reading `config.environment.etc` while
      # defining that same option (for accountsFile and reloadTriggers) is
      # infinite recursion, because `environment.etc` is one option tree.
      config =
        let
          accountsFile = ./rex/accounts.jsonc;
        in
        lib.mkIf config.my.rexLoginServer {
          # Installed through `environment.etc` (the module's own target, see
          # below), not `home.file`: Home Manager only exists for hosts with an
          # interactive account (lumquat has none), it would still leave /etc to
          # root, and a home-manager activation failure under home-manager.service
          # fails silently while the Rex service needs the file present at start.
          #
          # `environment.etc` is the "exactly once per generation" mechanism:
          # each switch atomically symlinks /etc/rex/accounts.jsonc to the
          # current generation's copy, so editing the file in place — which is
          # what "it isn't saved anywhere" meant — is a change that the next
          # switch (or upgrade-rollback) discards rather than something nobody
          # notices. Nothing is copied, so there is no "install if missing".
          #
          # Rex's default is the same path, and its loader is not run per
          # generation, so an accounts change must reach the running process:
          # rex-login-server has Type=notify-reload, and `reloadTriggers` below
          # adds this derivation, so a changed file reloads the policy (existing
          # account servers and sessions keep running; only revoked connections
          # close).
          environment.etc."rex/accounts.jsonc" = {
            # HuJSON: JSON plus //-comments, which Rex accepts and Nix does not.
            # Left unparsed here on purpose — Rex's own loader is the single
            # validator, and the only pure-Nix check available (fromJSON) would
            # reject the comments this file type exists for.
            source = accountsFile;

            # 0644, not 0600. The file is not a credential: every value in it is
            # a tailnet login or a wildcard, readable from `tailscale status` by
            # any local user. The protection that matters is that only root can
            # change it — `environment.etc` gives root:root, and the Nix store
            # source is root-owned and read-only — because a writable accounts
            # file is privilege escalation to any account root can start a server
            # as. Rex runs as root and reads it at startup and on SIGHUP only, so
            # no account needs read access; 0644 is what a plain file needs for
            # "not writable by anyone else" without making diagnosis harder.
            #
            # Honoured (as a metadata-tracked file, accounts.jsonc.mode) only
            # because this entry has `source`; a `text`-only entry defaults to
            # mode "symlink" and ignores this.
            mode = "0644";
          };

          services.rex.loginServer = {
            enable = true;

            # `accountsFile` is how the file above is read: /etc/rex/accounts.jsonc
            # is Rex's default, but the module only appends `--accounts` when this
            # option is set (or generates its own file when it is not), and it
            # asserts that `accounts` and `defaults` stay empty alongside it.
            #
            # The alternative — the module's `accounts`/`defaults` options — would
            # generate /etc/rex/accounts.jsonc from Nix, but it cannot express the
            # wildcard account `*` (an attr name that `lib.mapAttrs` rejects as an
            # attribute path), and the wildcard is what lets a caller name a
            # transient account such as a systemd dynamic user.
            accountsFile = accountsFile;

            # The only listener is Tailscale Serve, on 443 rather than the
            # module's 7297 default: Serve owns its port for every tailnet
            # connection to this host, and the clients (the Rex app included)
            # reach the login server as https://<host>.<tailnet>.ts.net with no
            # port, selecting an account with https://<account>@<host>. The
            # caller's identity arrives over a root-owned 0600 socket, so the only
            # door is the tailnet: no extraListen, no plain host:port, and
            # allowAnonymous stays false.
            tailscaleServe = {
              enable = true;
              httpsPort = 443;
            };
          };

          # Reload the policy when the file's content changes. The module does
          # this itself for the files it generates; with `accountsFile` it cannot,
          # so the trigger is stated here.
          systemd.services.rex-login-server.reloadTriggers = [ accountsFile ];

          # The login server names Tailscale identities through the host's
          # tailscaled, so it needs the tailnet this config sets up.
          assertions = [
            {
              assertion = config.my.access;
              message = "my.rexLoginServer is enabled but my.access is not — the login server identifies callers through this host's tailscaled.";
            }
            {
              assertion = !config.my.rexServer;
              message = "my.rexLoginServer and my.rexServer are mutually exclusive: both own /run/rex and the Tailscale Serve mapping. The login server serves every account in its accounts file; the shared server serves one.";
            }
            {
              assertion = config.my.base;
              message = "my.rexLoginServer is enabled but my.base is not — the accounts file names a local account, and base is what creates it.";
            }
          ];
        };
    };
}
