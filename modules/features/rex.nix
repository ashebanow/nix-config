# Rex — "the multiplexer for all work", plus the servers that make sessions
# reachable from other machines.
#
# Three independent roles, in three separate deferred modules. They are layers,
# not alternative setups: the two server modes are the only mutually exclusive
# pair, and the client is a prerequisite for either.
#
#   rex-client        Home Manager. programs.rex: the `rex` command, the
#                     xterm-rex terminfo entry, and the ssh guard. On macOS
#                     this is the whole story — the Rex app runs the server.
#
#   rex-login-server  NixOS. services.rex.loginServer: one root process that
#                     names each caller through tailscaled, maps them to local
#                     accounts, and runs one server per account as that
#                     account. Root-only, so it cannot live in Home Manager.
#
#   rex-server        NixOS. services.rex.enable: ONE shared server for this
#                     host's own account, reachable from the rest of the
#                     tailnet. This is yuzu's role — a desktop other devices
#                     attach to. It carries no caller identity at all, so it
#                     trusts the host's existing tailscaled rather than
#                     embedding a second Rex-owned Tailscale node (which is
#                     what the home-manager `services.rex.tailscale` would do:
#                     a separate tailnet node with its own hostname and auth
#                     key). The listener is `tailnet://`, which only the NixOS
#                     module supports — that is why this role is NixOS-scope
#                     even though the equivalent home-manager service exists.
#
# Where lumquat differs: it needs an allowlist of *who* may attach, so it runs
# the login server. That mode's only listener is Tailscale Serve, so a caller
# tailscaled did not identify has no way in at all — "use the multiplexer
# without Tailscale" is not something there is a socket to connect to.
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

  my.modules.nixos.rex-login-server =
    {
      lib,
      config,
      ...
    }:
    {
      # The Rex NixOS module is imported once, by the flag-agnostic fragment at
      # the end of this file. Importing it here as well would declare its whole
      # `services.rex` option tree a second time (the login server's options are
      # nested inside that same declaration), and the module system rejects the
      # duplicate.

      config = lib.mkIf config.my.rexLoginServer {
        # The two modes own /run/rex and the Serve mapping between them; the
        # Rex module asserts this too. Stated here so the intent is ours.
        # (`services.rex.enable` is the shared server; my.rexServer, which
        # would be the other occupant, is rejected by the assertion below.)
        services.rex.enable = false;

        services.rex.loginServer = {
          enable = true;

          # Local account -> the Tailscale identities allowed to act as it.
          accounts = lib.mapAttrs (_: principals: { inherit principals; }) config.my.rexAccounts;

          # The only listener. Tailscale Serve forwards each caller's identity
          # over its own root-owned 0600 socket, so the login server can map a
          # caller to an account; a bare socket would carry no identity at all.
          #
          # 443 rather than the module's 7297 default: Serve owns its port for
          # *every* tailnet connection to this host, so 7297 exists to avoid
          # colliding with a web server on 443. Nothing on this host serves
          # HTTPS to the tailnet (Open WebUI and bifrost are separate tailscaled
          # sidecar nodes), and the module's own Serve unit removes only the
          # mapping on the port it manages. Claiming 443 means clients need only
          # the hostname and no port.
          tailscaleServe = {
            enable = true;
            httpsPort = 443;
          };

          # PAM stays on (the default): each login opens a real logind session
          # for the account, which is what gives its terminals the account's
          # limits and environment. It never prompts for a password — Rex
          # proves identity through Tailscale first, and the module's PAM
          # service sets unixAuth = false.
        };

        assertions = [
          {
            assertion = config.my.access;
            message = "my.rexLoginServer requires my.access: Tailscale Serve is the login server's only listener, and my.access is what enrolls the host.";
          }
          {
            assertion = config.my.rexAccounts != { };
            message = "my.rexLoginServer is enabled but my.rexAccounts is empty — the login server would admit nobody. Set my.rexAccounts in the host's configuration.nix.";
          }
          {
            assertion = !config.my.rexServer;
            message = "my.rexLoginServer and my.rexServer are mutually exclusive: both own /run/rex and the Tailscale Serve mapping. Run the login server where callers must be mapped to accounts (a multi-user host), and the shared server on a machine that serves only its own account.";
          }
        ];
      };
    };

  my.modules.nixos.rex-server =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    {
      # No import here — see the note in rex-login-server above.

      config = lib.mkIf config.my.rexServer {
        services.rex = {
          enable = true;

          # The shared server serves exactly one account, so it runs as that
          # account rather than the module's `rex` system user. The account must
          # already exist; this only points at it.
          user = config.my.rexServerUser;
          group = "rex";

          # Local access: the default socket, group-readable so `rex` run by a
          # member of the rex group (and by the owning account itself) reaches
          # it. 0660 is the module default; stated here because the group
          # matters as much as the owner.
          socketMode = "0660";

          # Remote access reuses THIS host's tailscaled instead of embedding a
          # Rex-owned node.
          #
          # The address binds only when `my.rexServerTailnetAddress` is set. The
          # tempting empty-host form `tailnet://:<port>` was tried first and
          # crash-loops on this host: Rex expands an empty host to every tailnet
          # address, including the IPv6 one, and `tailscale0` carries only IPv4
          # here — so the IPv6 bind fails with "cannot assign requested address",
          # the server exits 1, and systemd restarts it endlessly. See the
          # option's description; the Rex module's own docs use the broken form.
          #
          # `tailnet://` is not in the module's managedServeFlags list, so it
          # must arrive through extraListen rather than a dedicated option.
          #
          # Plain TCP/HTTP endpoints would need tailnetAllowIdentified plus
          # allowAnonymous, i.e. no identity check at all — the tailnet listener
          # is deliberately the only remote one.
          extraListen = lib.optionals (config.my.rexServerTailnetAddress != null) [
            "tailnet://${config.my.rexServerTailnetAddress}:${toString config.my.rexServerPort}"
          ];

          # Default false: only the tailnet node's owning login is admitted.
          # Turning it on would admit every caller the tailnet's ACLs allow,
          # which for a shared server on a personal machine is broader than we
          # want. A tagged caller would need this (Serve does not forward tags,
          # but a tailnet:// listener does).
          tailnetAllowIdentified = false;

          # Do NOT combine with tailscaleServe.enable: that maps HTTPS through
          # Serve and requires tailscaled on the host, but it is a second
          # listener for the same server, and Serve forwards no tag identity.
        };

        # Group for local socket access. Creating it here rather than relying on
        # the module keeps the membership explicit and lets `my.rexServerUser`
        # be any account.
        users.groups.rex = { };

        # The account the server runs as is also the account most likely to
        # attach locally, so put it in the group. The server's own User= is
        # enough for it to *own* the socket; group membership is what makes the
        # 0660 mode meaningful for the same person when Rex runs the terminal
        # under a different effective group.
        users.users.${config.my.rexServerUser}.extraGroups = [ "rex" ];

        assertions = [
          {
            assertion = config.my.rexServerUser != "";
            message = "my.rexServer is enabled but my.rexServerUser is empty — set it to the account whose sessions the shared server should serve.";
          }
          {
            assertion = config.my.access;
            message = "my.rexServer requires my.access: its only remote listener is tailnet://, which needs this host enrolled in Tailscale.";
          }
          {
            assertion = !config.my.rexLoginServer;
            message = "my.rexServer and my.rexLoginServer are mutually exclusive: both own /run/rex.";
          }
        ];

        # Turning the address trap into a visible warning rather than a
        # silently local-only server: with no address the server still runs,
        # but nothing remote can reach it, which looks exactly like a client-side
        # problem from another machine.
        warnings = lib.optional (config.my.rexServerTailnetAddress == null) ''
          my.rexServer is enabled but my.rexServerTailnetAddress is null, so the
          tailnet listener is off: sessions are reachable only over the local
          Unix socket. Set it to the output of `tailscale ip -4`.
        '';
      };
    };

  # The Rex NixOS module, imported exactly once. Registering it as its own
  # flag-agnostic deferred module is what lets the two server roles above stay
  # separate fragments: `services.rex` is a single option tree (the login
  # server's options are nested inside that same declaration), so the module
  # cannot be imported by both roles. It is inert here — every option keeps its
  # default until a role sets it.
  my.modules.nixos.rex-module = {
    imports = [ inputs.rex.nixosModules.default ];
  };
}
