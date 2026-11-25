# Shared options module providing config.my.* for host metadata.
# Following the dendritic pattern: capability flags defined centrally.
#
# `config` is in scope because the desktop-shell predicates are derived from
# `my.desktopShell` rather than set independently — see the shell option below.
{ lib, config, ... }: {
  options.my = {
    # Identity
    hostName = lib.mkOption {
      type = lib.types.str;
      description = "The hostname of the current system being configured.";
    };

    # Base feature
    base = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable base server configuration.";
    };
    baseUsername = lib.mkOption {
      type = lib.types.str;
      default = "podman";
      description = "Non-root user for container operations.";
    };
    baseUserFullName = lib.mkOption {
      type = lib.types.str;
      default = config.my.baseUsername;
      defaultText = lib.literalExpression "config.my.baseUsername";
      description = ''
        Display name (GECOS field) for the base user, shown by greeters on the
        login screen. Defaults to baseUsername, so the login screen shows the
        login name unless a real name is set.
      '';
    };
    baseTimezone = lib.mkOption {
      type = lib.types.str;
      default = "America/New_York";
      description = "System timezone.";
    };
    baseAllowSuspend = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether the host may suspend/hibernate. Defaults to false: a host that
        must be reachable over the network (a server, or a remote-accessed
        desktop) should not sleep out from under its clients. Turn it on for a
        desktop only once its resume path is known to bring networking back —
        e.g. after the r8169 workaround in hosts/yuzu/hardware-configuration.nix
        is verified on real hardware.
      '';
    };

    # LLM feature
    llm = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable LLM inference servers with GPU passthrough.";
    };
    llmModelStorage = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/llm-models";
      description = "Read-only mount path for model files in containers.";
    };
    llmServe = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Tailscale Serve to publish LLM endpoints as paths on this node (not Tailscale Services — see TS-SERVE.MD).";
    };
    bifrostServe = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable the Bifrost LLM gateway compose stack, served at ai.<tailnet> via its own Tailscale sidecar node.";
    };

    # Access feature
    access = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable remote access via Tailscale.";
    };
    accessTailnetName = lib.mkOption {
      type = lib.types.str;
      default = "lumquat";
      description = "Hostname on the tailnet.";
    };
    accessEnableSSH = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Tailscale SSH.";
    };
    accessEnableExitNode = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Act as a Tailscale exit node.";
    };
    accessEnableSubnetRouting = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Advertise local subnets via Tailscale subnet routes.";
    };
    accessSubnetRoutes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "CIDR ranges to advertise when accessEnableSubnetRouting is enabled (e.g. [ \"192.168.1.0/24\" ]).";
    };
    accessEnableFallbackSSH = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable SSH fallback on non-standard port when Tailscale is down.";
    };
    accessFallbackPort = lib.mkOption {
      type = lib.types.port;
      default = 2222;
      description = "Fallback SSH port.";
    };

    # Cockpit feature (web UI for system administration). Named for the tool,
    # not for "monitoring": that word belongs to observability (see CONTEXT.md).
    # Cockpit is administration, not observability — do not fold it in here.
    cockpit = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Cockpit web UI for system administration.";
    };
    cockpitPort = lib.mkOption {
      type = lib.types.port;
      default = 9090;
      description = "Cockpit web interface port.";
    };

    # ── Observability ────────────────────────────────────────────────────
    #
    # Two roles, two flags. They are separate roles, not alternatives: the
    # observability host stores, queries, alerts on and displays; an
    # observability agent only collects the machine it runs on. calamansi is
    # both (and so sets both). Vocabulary is CONTEXT.md's Observability
    # section, and these are NixOS-scope only — Home Manager has no opinion.
    #
    # Declaring a source is the `my.observability` option set below, not the
    # flags: a feature module registers its scrape target or dashboard
    # whether or not it knows which host it is running on.
    # see docs/adr/0006-observability-runs-as-native-services.md
    observabilityTailnetDomain = lib.mkOption {
      type = lib.types.str;
      default = "fluffy-walleye.ts.net";
      example = "fluffy-walleye.ts.net";
      description = ''
        This tailnet's MagicDNS domain, without a leading `https://`.

        Needed because a service published through Tailscale Serve has to be
        told its own public URL — Grafana builds its asset and redirect links
        from it, and a wrong value gives a page that half-loads rather than an
        error that says so. Keeping it as an option rather than a literal in
        the host module means a tailnet rename is one edit, and it pairs with
        `accessTailnetName` to form the full `<host>.<tailnet>.ts.net`.

        Not a secret: the tailnet name appears in every ts.net hostname and is
        discoverable by anyone already on the tailnet. ACLs restrict access,
        not the name.
      '';
    };
    observabilityHost = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        This host is the **observability host**: the one machine that stores,
        queries, alerts on and displays every server's logs and metrics.

        It runs VictoriaMetrics, VictoriaLogs, vmalert, Alertmanager and
        Grafana as native NixOS services (ADR 0006), and gathers every agent
        host's rules, dashboards and redactions at build time. Exactly one
        host should set this; the ticket that installs a second one gets to
        add the assertion.
      '';
    };
    observabilityAgent = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        This host runs an **observability agent**: the set of collector
        processes (node_exporter, vmagent, later `systemd-journal-upload`)
        that gathers this machine's logs and metrics and ships them to the
        observability host.

        There is one agent per machine, shared by every service on it — a
        service never brings its own collector. Setting this flag is also how
        the observability host discovers which hosts' `my.observability`
        collections to gather, so an agent host with rules or dashboards
        contributes them automatically.
      '';
    };
    observabilityGatheredHosts = lib.mkOption {
      type = lib.types.attrsOf lib.types.unspecified;
      default = { };
      description = ''
        **Test hook. Never set this in a host configuration.**

        The set of hosts whose `my.observability` collections the observability
        host gathers, as an attrset shaped like `nixosConfigurations`. Empty (the
        default) means "the committed flake's `nixosConfigurations`", which is
        what every real deployment does.

        It exists because the gather reads `inputs.self`, and an
        `extendModules`-ed configuration is not in `inputs.self`: without a seam
        there is no way to demonstrate "a rule declared on lumquat reaches
        calamansi" before the rule itself is committed. A test sets this to an
        attrset of extended hosts; nothing else does.
      '';
    };
    observabilityVmalertPort = lib.mkOption {
      type = lib.types.port;
      default = 8880;
      description = ''
        Loopback port vmalert serves its own `/metrics` and web UI on, so the
        observability host's agent can scrape the alert engine and a silent
        vmalert is visible. vmalert's upstream default; nothing is published.
      '';
    };
    observabilityAlertmanagerPort = lib.mkOption {
      type = lib.types.port;
      default = 9093;
      description = ''
        Loopback port Alertmanager listens on, which is where vmalert sends
        alerts and where Grafana's Alertmanager datasource sends silences.
        Alertmanager's upstream default.

        Never published: no Tailscale Serve entry, no firewall rule. Silences
        are made through Grafana, so there is no reason for a second, uglier
        UI to be reachable at all.
      '';
    };
    observabilityHostAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      example = "10.40.60.20";
      description = ''
        Where a non-host agent remote-writes its metrics: the observability
        host's address, as `<host>` or `<host>:<port>`.

        Set on **agent hosts that are not the observability host**. The
        default, loopback, is right for the observability host itself (it
        both scrapes and stores locally) and wrong for every other machine,
        where it would silently buffer forever — so a remote agent must set
        it. A later ticket can derive it from the tailnet instead of a literal
        LAN address; today it is a plain shared value, deliberately, because
        reading another host's config from this module would be a dependency
        in the wrong direction.
      '';
    };
    observabilityIngestPort = lib.mkOption {
      type = lib.types.port;
      default = 8428;
      description = ''
        TCP port the observability host listens on for VictoriaMetrics ingest
        (vmagent's remote-write) and query traffic. This is upstream
        VictoriaMetrics' default, kept so the binary and the firewall agree
        without anyone having to remember a number.

        The host binds this port on `observabilityIngestAddress`; every other
        VictoriaMetrics listener stays on loopback.
      '';
    };
    observabilityIngestAddress = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = ''
        Address the observability host binds the VictoriaMetrics HTTP listener
        to. The default is every interface; the firewall, not the bind, is
        what restricts who may reach it.
      '';
    };
    observabilityHostAllowedSources = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = lib.literalExpression ''[ "10.40.60.20" ]'';
      description = ''
        Source IP addresses allowed to reach the observability host's ingest
        port (`observabilityIngestPort`): the LAN addresses of the agent hosts.

        **An empty list opens nothing**, which is the deliberate default — an
        ingest port reachable from a wrong address is either useless (the
        agent that needs it is refused) or too broad (the whole LAN). The
        observability host's own agent writes over loopback and needs no
        entry here.

        The value is per-install, not per-repo: BOX-324 sets it from the real
        LAN addresses once calamansi is on the network. Until then,
        `hosts/calamansi/configuration.nix` carries a documented placeholder.
      '';
    };

    # ── my.observability: how a feature declares its observability ───────
    #
    # Five **named** collections (named, not lists: an entry cannot silently
    # duplicate, and a host can override one by name). This is the option set
    # every service uses to say "here is how to watch me"; adding a source to
    # a host is then a feature-module change, not an observability change.
    #
    # Who reads what, per BOX-318:
    #
    #   scrapeTargets, textfileChecks   the machine's own agent
    #   rules, dashboards, redactions   the observability host, gathered at
    #                                   build time from every host whose
    #                                   observabilityAgent flag is on
    #
    # The gather is one-way (servers never read calamansi's config), so it
    # cannot cycle; the cost is that changing a lumquat feature's rule means
    # redeploying calamansi.
    #
    # `scrapeTargets`, `dashboards` and `rules` are consumed (BOX-326, BOX-329);
    # `textfileChecks` (BOX-332) and `redactions` (BOX-337) are declared with
    # their real types so those tickets extend this set rather than reshape it.
    # Setting one of those two is inert today.
    observability = lib.mkOption {
      default = { };
      description = ''
        What this host's services contribute to observability. Every
        collection is keyed by a name the contributor chooses; the convention
        is to prefix with the owning feature (`llama-qwen`, `bifrost-logs-db`)
        so the origin is obvious in Grafana and in the rendered agent config.

        Feature modules write these through `config.my.observability` guarded
        by their own flag, e.g.
        `lib.mkIf config.my.bifrost { my.observability.scrapeTargets.bifrost = { ... }; }`.
        Logs need no declaration: every service's output already reaches the
        journal, and VictoriaLogs indexes the journal's own fields.
      '';
      type = lib.types.submodule {
        options = {
          scrapeTargets = lib.mkOption {
            default = { };
            description = ''
              Endpoints this host's agent scrapes, in Prometheus format, keyed
              by a name this host chooses. The entry's name becomes the
              rendered config's `job_name`, so it is what a Grafana query
              filters on: keep it stable, and name it for the *thing scraped*
              rather than for the feature that scrapes it where those differ.

              Consumed by the observability agent (`my.observabilityAgent`).
            '';
            type = lib.types.attrsOf (
              lib.types.submodule {
                options = {
                  address = lib.mkOption {
                    type = lib.types.str;
                    example = "127.0.0.1:8080";
                    description = ''
                      What to scrape: `host:port`, a URL, or — for a
                      multi-instance service — a list joined with commas, as
                      Prometheus' `targets` accepts. A loopback address means
                      the service publishes a metrics port only to this host,
                      which is the usual arrangement for a container: bind the
                      published port to 127.0.0.1 and scrape it here rather
                      than exposing it on the LAN.
                    '';
                  };
                  metricsPath = lib.mkOption {
                    type = lib.types.str;
                    default = "/metrics";
                    description = ''
                      Path the metrics are served from. Defaults to the
                      Prometheus convention; set it for a service that serves
                      them elsewhere.
                    '';
                  };
                  labels = lib.mkOption {
                    type = lib.types.attrsOf lib.types.str;
                    default = { };
                    example = lib.literalExpression ''{ model = "qwen-27b"; }'';
                    description = ''
                      Extra labels attached to every sample from this target,
                      alongside the automatic `instance` and `job`. This is
                      where a service's own identity goes — the model name for
                      an inference server, the database for an exporter — so
                      dashboards can group by it.

                      `instance` and `job` are reserved: the agent sets them
                      and the rendered config would not survive a second
                      definition of either.
                    '';
                  };
                  interval = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                    example = "60s";
                    description = ''
                      How often to scrape, as a Prometheus duration. `null`
                      takes the agent's default (15s), which is right for a
                      host-local exporter and too eager for a service whose
                      counters move slowly.
                    '';
                  };
                  scrapeTimeout = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                    example = "10s";
                    description = ''
                      Per-scrape timeout, as a Prometheus duration. `null`
                      takes the agent's default, which is derived from the
                      scrape interval.
                    '';
                  };
                };
              }
            );
          };

          dashboards = lib.mkOption {
            default = { };
            description = ''
              Grafana dashboards this host contributes, keyed by a file name
              that is also what Grafana displays in its dashboard list (the
              `title` inside the JSON is what a reader sees, so keep the two
              close).

              Bodies are **JSON files**, one per dashboard, committed next to
              the module that owns the service (e.g.
              `modules/features/llm.json`). Panels are never written in Nix:
              hundreds of lines of nested config read worse than JSON and
              cannot round-trip through Grafana's own editor. The loop is: edit
              in the UI, export JSON, commit, `nixos-rebuild switch`. Grafana
              runs with `allowUiUpdates = false`, so a UI edit is discarded
              rather than silently drifting from the repo.

              Gathered by the observability host. A prebuilt community or
              upstream dashboard is not declared here — it is fetched pinned
              by hash in `modules/features/observability-host.nix`, because it
              has no owning feature module to sit beside.
            '';
            type = lib.types.attrsOf (
              lib.types.submodule {
                options = {
                  path = lib.mkOption {
                    type = lib.types.path;
                    description = ''
                      Path to the dashboard's JSON file, relative to the module
                      declaring it (a bare `./llm.json` is the normal form).
                    '';
                  };
                  # Grafana's own dashboard list has no folders here (BOX-322: flat
                  # list), so there is deliberately no `folder` option. Add one
                  # when a second consumer needs grouping — not before.
                };
              }
            );
          };

          # Consumed by the observability host (BOX-329). See the collection's
          # own description for the contract.
          rules = lib.mkOption {
            default = { };
            description = ''
              Alerting and recording rules, as **native vmalert YAML files**
              — one entry per feature, beside the module that owns the thing
              being alerted on (e.g. `my.observability.rules.bifrost = {
              files = [ ./bifrost.rules.yaml ]; }`).

              A ruleset is a *list of files* rather than a single path because
              one owning feature can legitimately need more than one: a shared
              feature's rules, and separately the rules for a specific
              service. `files` is concatenated, so adding a file never means
              rewriting the entry that was already there.

              Not Nix attrsets: rule expressions are a language of their own,
              and keeping them as YAML lets them be copied from documentation
              and checked with `vmalert -dryRun` unchanged. The rendered files
              are copied verbatim into vmalert's rule directory; only their
              names are chosen here (`<ruleset>.<n>.yaml`).

              **A malformed file fails the build**, not the service: the
              observability host loads the whole directory into
              `vmalert -dryRun` as part of the derivation's own build.

              Gathered by the observability host from every agent host at
              build time, so a rule added on lumquat means redeploying
              calamansi (one-way dependency by design).
            '';
            type = lib.types.attrsOf (
              lib.types.submodule {
                options = {
                  files = lib.mkOption {
                    type = lib.types.listOf lib.types.path;
                    default = [ ];
                    example = lib.literalExpression "[ ./bifrost.rules.yaml ]";
                    description = ''
                      Paths to the vmalert rule files (YAML), relative to the
                      module declaring them. Each is loaded as its own group
                      file, so files do not participate in each other's group
                      names.
                    '';
                  };
                  type = lib.mkOption {
                    type = lib.types.enum [
                      "metrics"
                      "logs"
                    ];
                    default = "metrics";
                    description = ''
                      Which datasource the rules query: `metrics` against
                      VictoriaMetrics, `logs` against VictoriaLogs. vmalert
                      runs one instance per type, so this decides which one
                      loads the files.

                      **`logs` is reserved and not implemented**: VictoriaLogs
                      arrives with BOX-330, and until it does a `logs` ruleset
                      would query a store that does not exist. Declaring one
                      now is a build error naming the ticket, not a silently
                      dead rule (see `modules/features/observability-host.nix`).
                    '';
                  };
                };
              }
            );
          };

          textfileChecks = lib.mkOption {
            default = { };
            description = ''
              Periodic checks whose result node_exporter exposes as metrics: a
              systemd timer runs the check and atomically writes `<name>.prom`
              into node_exporter's textfile directory. The answer to "a number
              only a shell command knows" (a database size, a certificate's
              remaining days) without writing an exporter.

              **Not implemented yet (BOX-332 adds the runner and the
              `lib/observability.nix` builder helpers such as
              `obs.sqliteCheck`).** Declared with its final type so BOX-332
              adds a reader, not a reshape.

              The `user` option is the point of the shape, not an
              afterthought: a check that reads another service's file runs as
              that file's **owning** user, so it can be given read permission
              rather than being run as root (the BOX-202 trap — a check that
              ran as the wrong user crash-looped bifrost).
            '';
            type = lib.types.attrsOf (
              lib.types.submodule {
                options = {
                  script = lib.mkOption {
                    type = lib.types.lines;
                    description = ''
                      Shell script producing the check's metrics on stdout, in
                      Prometheus text exposition format. The runner writes it
                      to `<name>.prom` in node_exporter's textfile directory.
                    '';
                  };
                  interval = lib.mkOption {
                    type = lib.types.str;
                    default = "15m";
                    example = "5m";
                    description = ''
                      How often the check runs, as a systemd timer duration.
                      Checks read a file or query a database, so they are far
                      less frequent than a scrape.
                    '';
                  };
                  user = lib.mkOption {
                    type = lib.types.str;
                    description = ''
                      The account the check runs as. This is the owning user of
                      whatever the check reads — the service's own user
                      (`podman` for a container's data file) — so the check
                      needs read permission rather than privilege.
                    '';
                  };
                };
              }
            );
          };

          redactions = lib.mkOption {
            default = { };
            description = ''
              Patterns to strip from log lines before they reach the archive:
              the daily export applies them so a secret that was logged by
              accident does not land in long-term off-host storage.

              A feature declares the patterns only it knows about (a bearer
              token shape, an API key format); the export job carries a
              generic list of its own.

              **Not implemented yet (BOX-337 adds the archive export).**
              Declared with its final type so BOX-337 adds a reader, not a
              reshape.
            '';
            type = lib.types.attrsOf (
              lib.types.submodule {
                options = {
                  patterns = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                    example = lib.literalExpression ''[ "sk-[A-Za-z0-9]{32,}" ]'';
                    description = ''
                      Regular expressions to match against exported log lines;
                      matches are replaced before the line is written.
                    '';
                  };
                };
              }
            );
          };
        };
      };
    };

    # Printing feature (CUPS). The service is declarative; so are the queues:
    # nixpkgs has no option for a CUPS queue, so modules/features/printing.nix
    # renders my.printers into an lpadmin oneshot that re-creates them on every
    # boot.
    printing = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable CUPS printing with HP driver support.";
    };

    # Declarative CUPS queues. CUPS keeps its queues in /etc/cups/printers.conf,
    # which NixOS regenerates on every activation, so a queue added by hand
    # vanishes at the next rebuild. Each entry here is re-applied idempotently
    # by lpadmin at boot instead.
    printers = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "CUPS queue name (as shown in print dialogs).";
            };
            uri = lib.mkOption {
              type = lib.types.str;
              description = ''
                Device URI. For an IPP Everywhere printer use
                ipp://<host-or-ip>/ipp/print; a literal IP is preferred because
                CUPS resolves <name>.local mDNS names unreliably.
              '';
            };
            description = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "Human-readable description shown in print dialogs.";
            };
            location = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "Free-form location string.";
            };
            isDefault = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Make this queue the system default destination.";
            };
            drivers = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ "everywhere" ];
              description = ''
                PPD source passed to lpadmin -m. The default "everywhere"
                selects the driverless IPP Everywhere PPD and is correct for any
                printer advertising IPP Everywhere (HP LaserJet 2016+).
              '';
            };
          };
        }
      );
      default = [ ];
      description = "Declarative CUPS printer queues, re-applied at boot.";
    };

    # zmx feature
    zmx = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable zmx session persistence tool.";
    };

    # Rex — the terminal multiplexer, in two roles. A host picks the ones it
    # plays; they are separate flags because they are separate layers, not
    # alternatives (see modules/features/rex.nix):
    #
    #   my.rexClient  Home Manager. The `rex` command, the xterm-rex terminfo
    #                 entry and the ssh guard for one account.
    #   my.rexServer  NixOS. A server for this host's own account, reachable
    #                 from other tailnet machines through Rex's own tsnet node.
    #
    # There is deliberately no login-server flag. The Rex login server exists to
    # map *many* Tailscale identities onto *many* local accounts, and it has no
    # tsnet support at all (`rex login-server` has no --tailscale; only
    # `rex server run` does), so it cannot publish the native
    # https://<host>-rex.<tailnet> endpoint that the Rex app requires. A
    # single-account host — which is every host here, including lumquat — is
    # served by my.rexServer with a tsnet node instead, and gets the account
    # restriction from Tailscale's own ACLs rather than an accounts file.
    rexClient = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Install the Rex client for this account (programs.rex): the `rex`
        command, Rex's terminfo entry in ~/.terminfo, and its ssh guard.

        The whole story on macOS, where the Rex app runs the server itself.
      '';
    };
    rexServer = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Run a Rex server for this host (NixOS only), reachable from other
        machines on the tailnet as https://<my.hostName>-rex.<tailnet>.ts.net.

        The server runs as `my.rexServerUser` and serves that one account, so a
        caller attaching over the tailnet gets a shell as that user. It
        publishes through Rex's own embedded Tailscale node (tsnet), which
        obtains its own HTTPS certificate — no Tailscale Serve, and no
        involvement from the host's tailscaled.

        Access is owner-only by default: just the Tailscale account that
        enrolled the node. Members of the `rex` group can also connect locally
        over the Unix socket.
      '';
    };
    rexServerUser = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        The account `my.rexServer` runs as, and whose sessions it serves. Must
        be an existing user. The server has no accounts file: it serves exactly
        this one account.
      '';
    };

    # Resilio Sync feature (NixOS desktops only).
    #
    # The nixpkgs service module is NixOS-only, so this flag is meaningless on
    # the Darwin hosts — the macs run Resilio from the upstream Homebrew cask
    # and configure it by hand. It is also not wanted on lumquat, which has no
    # interactive user account to own the synced tree (the daemon there would
    # run as `rslsync` with nobody to read the result).
    resilio = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Resilio Sync for this desktop's Synced Files tree.";
    };
    resilioDeviceName = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        Name other peers see for this node. Empty means use the hostname
        (my.hostName); the macs show up as `miracle_max`/`bergamot`, so a
        short, stable, distinctive name is worth setting explicitly.
      '';
    };
    resilioUser = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        The interactive user who owns the synced tree. The NixOS service runs
        the daemon as the `rslsync` system user, so the shared folder has to be
        group-writable by that user while remaining the operator's own files —
        this is the user whose home holds the tree.
      '';
    };
    resilioDirectory = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        Absolute path to the synced folder root (the local mirror of the
        remote "Synced Files" folder). Its subdirectories are symlinked into
        the owner's home by `resilioHomeLinks`.
      '';
    };
    resilioHomeLinks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Subdirectory names of `resilioDirectory` to symlink into the owner's
        home, replacing a same-named real directory. The remote folder's
        top-level layout is the source of truth (see modules/features/resilio.nix).
      '';
    };
    resilioKnownHosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "10.40.60.74:4444" ];
      description = ''
        Peers to dial directly, as `host:port`, bypassing tracker, relay, DHT
        and LAN discovery entirely. Use literal LAN addresses: a name is
        resolved by the OS, and on a host whose name resolves to a Tailscale
        address this would hand Resilio an address it cannot use, since it does
        not traverse Tailscale.

        The port must be the peer's **fixed** listening port -- a peer left on
        the default random port has no stable address to name here, so pinning
        it on that peer is a prerequisite, not an optional tidy-up.

        UNUSED as of the move to UI-managed folders: the folder (and therefore
        its known-hosts list) is no longer declared in the generated config, so
        nothing reads this. Retained because it is the natural home for the
        value if the folder ever becomes declarative again; a host that sets it
        today would get no effect, which is a trap worth deleting rather than
        leaving, so it is kept only with this note attached.
      '';
    };

    # Memory feature (Mnemosyne)
    memory = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Mnemosyne memory layer for AI agents.";
    };

    # Desktop workstation feature (NixOS hosts with a graphical session).
    # Distinct from `access`/`llm`: a desktop can also be an SSH target, but
    # this flag is what switches the host to workstation user defaults (zsh
    # login shell, NetworkManager group) and turns on a desktop environment.
    # It does NOT affect suspend — that is my.baseAllowSuspend, which is opt-in.
    desktop = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable desktop-workstation configuration (graphical session, desktop power/user defaults).";
    };
    desktopSessions = lib.mkOption {
      type = lib.types.listOf (
        lib.types.enum [
          "gnome"
          "niri"
        ]
      );
      default = [ ];
      description = ''
        The graphical sessions this host offers at the login screen, named by
        compositor or desktop environment. Distinct from the display manager
        (GDM for every desktop here) and from `desktopDefaultSession`: a host
        may offer several sessions and start one of them.

        Set in the host's capabilities.nix, not configuration.nix: the niri
        session is configured by a Home Manager module, and Home Manager
        evaluates its own `config.my` instance (see CONTEXT.md).
      '';
    };
    # Location for desktop-shell weather/widgets. Optional; a host that leaves
    # it null gets no weather configuration at all, and a shell that would
    # IP-geolocate will do so.
    #
    # Set in capabilities.nix, like `desktopShell`, because the consumers are
    # Home Manager modules and `my.baseTimezone` is NixOS-scope only.
    desktopShellLocation = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.submodule {
          options = {
            city = lib.mkOption {
              type = lib.types.str;
              description = "City name shown by weather widgets.";
            };
            timezone = lib.mkOption {
              type = lib.types.str;
              description = "IANA timezone for the location.";
            };
            latitude = lib.mkOption {
              type = lib.types.float;
              description = "Latitude in decimal degrees.";
            };
            longitude = lib.mkOption {
              type = lib.types.float;
              description = "Longitude in decimal degrees.";
            };
          };
        }
      );
      default = null;
      description = ''
        Location used by desktop-shell weather widgets, and whatever else a
        shell wants to know where the machine is. Purely presentational: it is
        not the system timezone (`baseTimezone` is, and that is NixOS-scope).
      '';
    };
    desktopDefaultSession = lib.mkOption {
      type = lib.types.enum [
        "gnome"
        "niri"
      ];
      default = "gnome";
      description = ''
        The session the display manager starts when nobody chooses one. Must
        appear in `desktopSessions`; desktop.nix asserts that.
      '';
    };
    # ── Shell on top of the niri session ────────────────────────────────
    #
    # One master switch, not three booleans. `desktopShell` names the shell the
    # host installs and starts; each shell's module (dank-material-shell.nix,
    # noctalia.nix) enables itself when this equals its own
    # name, so the choice is exclusive by construction — two shells would both
    # claim org.freedesktop.Notifications and both draw a bar. See
    # docs/adr/0004.
    #
    # `null` means "no shell": the compositor runs bare. That is a real choice
    # (a niri-only debug session), so it is not an error.
    desktopShell = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum [
          "dank"
          "noctalia"
        ]
      );
      default = null;
      example = "noctalia";
      description = ''
        The desktop shell drawn on top of the niri session: bar, launcher,
        notifications, clipboard, lock screen and OSD. A shell is not a
        session, so this is separate from `desktopSessions`.

        Exactly one shell may be selected. Each shell lives in its own module
        and installs the optional dependencies its own features need
        (screenshots, clipboard, media keys, brightness) with its
        upstream-recommended tools.

        Set in the host's capabilities.nix, not configuration.nix: the shells
        are configured by Home Manager modules, and Home Manager evaluates its
        own `config.my` instance (see CONTEXT.md).
      '';
    };
    # Convenience predicates for the shell modules. Derived, not settable: the
    # point of the master switch is that a host never sets these.
    desktopShellIsDankMaterialShell = lib.mkOption {
      type = lib.types.bool;
      readOnly = true;
      default = config.my.desktopShell == "dank";
      description = "Derived from `desktopShell`; do not set.";
    };
    desktopShellIsNoctalia = lib.mkOption {
      type = lib.types.bool;
      readOnly = true;
      default = config.my.desktopShell == "noctalia";
      description = "Derived from `desktopShell`; do not set.";
    };

    # Secrets (secretspec + BWS) — shared paths used by every secret consumer.
    secretspecManifest = lib.mkOption {
      type = lib.types.str;
      default = "/etc/secretspec.toml";
      description = "Absolute path to the shared secretspec.toml (symlinked from the repo root).";
    };
    bwsAccessTokenFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/secrets/bws-access-token";
      description = "Root-only BWS bootstrap access token file (provisioned out-of-band; never in the store or git).";
    };
    bwsBinDir = lib.mkOption {
      type = lib.types.str;
      default = "/run/current-system/sw/bin";
      description = ''
        Directory containing the `bws` CLI, prepended to the Home Manager
        activation's PATH. The chezmoi `gh` hosts.yml template resolves the
        GitHub token by invoking `bws secret get`, and the activation's PATH
        does not otherwise include the system profile (BOX-174).
      '';
    };

    # CLI tools feature (Home Manager)
    cliTools = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable modern CLI tools.";
    };

    # Topical CLI package modules (Home Manager, Darwin hosts).
    # Each is a curated package list gated by its own toggle — hosts
    # opt into the topics they want. No generic "extras" catch-all.
    cliSystemTools = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable system monitoring/diagnostics CLI tools (btop, htop, glances, ...).";
    };
    cliProductivityTools = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable everyday shell/productivity CLI tools (fzf, zoxide, starship, ...).";
    };
    cliVcsTools = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable git and git-adjacent CLI tools (gh, lazygit, git-lfs, ...).";
    };
    cliSecurityTools = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable secrets/crypto/vuln-scanning CLI tools (gitleaks, cosign, gnupg, ...).";
    };
    cliNetworkTools = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable networking/remote-access/download CLI tools (aria2, tailscale, caddy, ...).";
    };
    cliContainerTools = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable container/Docker ecosystem CLI tools (docker, colima, lazydocker, ...).";
    };
    cliMacOnlyTools = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable macOS-specific CLI tools (dockutil, xcodes, pinentry_mac).";
    };
    cliAiTools = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable AI-agent CLI tools (opencode, ...).";
    };
    cliBuildEssentials = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable global build toolchain needed to rebuild other packages from source (gcc, make, llvm, direnv, uv, nodejs). Most dev tooling stays devenv-only; this is the deliberate global exception.";
    };

    # GUI app modules (Home Manager, Darwin hosts). Priority order for
    # macOS apps is nix > Homebrew cask > Mac App Store — these are apps
    # that used to be Homebrew casks but have a real, darwin-buildable
    # nixpkgs package. Requires mac-app-util (wired in darwin-builder.nix)
    # for Spotlight/Launchpad to actually see them.
    guiTerminals = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable terminal emulator GUI apps (kitty, ghostty-bin, warp-terminal).";
    };
    guiCommunication = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable communication GUI apps (discord, signal-desktop, slack, zoom-us).";
    };
    guiCoreApps = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable core GUI apps common to every host (google-chrome, bitwarden-desktop).";
    };
    guiDevApps = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable development GUI apps (vscode, zed-editor, delta).";
    };
    guiMediaApps = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable media GUI apps (pinta, vlc-bin, dolphin-emu).";
    };
    guiProductivityApps = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable productivity/utility GUI apps (raycast, stats, monitorcontrol, betterdisplay, soundsource, mist, postman, utm, temurin-bin).";
    };
    guiFonts = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable GUI fonts (nerd-fonts, fira-mono, jetbrains-mono, powerline-symbols).";
    };

    # Gaming is its own flag rather than part of guiMediaApps: it pulls in a
    # multi-GB Proton build and creates non-declarative Wine prefixes under
    # $HOME, which is a very different commitment from "vlc is installed".
    #
    # One flag covers all three storefronts — Steam (`programs.steam`), GOG
    # (Heroic, in Home Manager) and Battle.net (the umu-launcher wrappers, via
    # `gamingWinePrefixes`). They share the same host prerequisites — 32-bit
    # Vulkan, gamemode, gamescope — so a host that games wants all of them and a
    # host that does not wants none. A per-storefront flag would add switches
    # with no configuration behind them. See modules/features/gaming.nix.
    gaming = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable gaming on this host: Steam, GOG through Heroic, and Battle.net
        through umu-launcher + Proton-GE (with the Diablo IV launcher).

        Steam and GOG need nothing further. Battle.net is only instantiated for
        prefixes named in `gamingWinePrefixes`.
      '';
    };

    # Which Wine prefixes this host manages. Names only — the per-prefix
    # settings (games, Proton build) live in programs.gaming-umu.winePrefixes,
    # which modules/features/gaming.nix turns each of these into. Split that way
    # because `programs.*` is Home Manager-only: this file is in both module
    # lists, so it can carry the switch, but the options with defaults must live
    # on the side that owns them.
    gamingWinePrefixes = lib.mkOption {
      type = lib.types.listOf (lib.types.strMatching "[A-Za-z0-9_-]+");
      default = [ ];
      description = ''
        Wine prefixes to create for Battle.net. Name each one for what it is —
        typically the host (`yuzu`), or a role (`ptr`, `probe`). The name becomes
        the prefix's directory (`~/.local/share/battlenet-umu/prefixes/<name>`)
        and part of its launcher names (`battlenet-umu-<name>-<game>`).

        One prefix is the normal case. Add a second on demand to test a Proton
        release without risking the working install, or for a separate account;
        a pre-installed `spare` kept purely as recovery is optional and costs a
        full install's disk. See "What a second prefix is actually for" in
        docs/gaming.md.

        Per-prefix configuration goes in programs.gaming-umu.winePrefixes.
      '';
      example = lib.literalExpression ''[ "yuzu" ]'';
    };
  };
}
