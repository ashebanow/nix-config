# Yuzu capability flags — split out from configuration.nix because this needs
# to be imported into BOTH the NixOS/system module list AND
# home-manager.users.<user>.imports (see modules/infra/nixos-builder.nix). The
# topical CLI/GUI modules gate their home.packages contributions with
# lib.mkIf config.my.<flag>, and that config.my is the Home Manager
# submodule's own separate options instance — it does not inherit values set
# only at the NixOS/system scope. configuration.nix itself can't be imported
# into the HM submodule because it also sets system.stateVersion, a NixOS
# option Home Manager's module system doesn't know about and would error on.
_: {
  # Capability flags — enable topical CLI package modules.
  my.cliSystemTools = true;
  my.cliProductivityTools = true;
  my.cliVcsTools = true;
  my.cliSecurityTools = true;
  my.cliNetworkTools = true;
  my.cliContainerTools = true;
  my.cliAiTools = true;
  my.cliBuildEssentials = true;
  my.cliTools = true;

  # Capability flags — enable topical GUI app modules. Apps come from nix on
  # yuzu (no Homebrew, no Mac App Store). The mac-only flags
  # (cliMacOnlyTools, guiProductivityApps) are deliberately off: every package
  # in those modules is macOS-only.
  my.guiTerminals = true;
  my.guiCommunication = true;
  my.guiCoreApps = true;
  my.guiDevApps = true;
  my.guiMediaApps = true;
  my.guiFonts = true;

  # Desktop session model. It lives here rather than in configuration.nix
  # because the niri session is configured by a Home Manager module, and Home
  # Manager evaluates its own `config.my` (see the file header and CONTEXT.md).
  # niri is the default session; GNOME stays installed and selectable as the
  # emergency session (docs/adr/0003).
  my.desktopSessions = [
    "niri"
    "gnome"
  ];
  my.desktopDefaultSession = "niri";

  # Where the weather widget thinks it is. Set here — not derived from
  # my.baseTimezone — because baseTimezone is NixOS-scope only (it is set in
  # configuration.nix) and Home Manager evaluates its own config.my, so deriving
  # from it here silently yields the option's America/New_York default. The
  # coordinates exist to keep the widget off Serpantinum's IP-geolocation path
  # (see modules/features/serpantinum.nix), not as a fact other modules read.
  my.desktopShellLocation = {
    city = "San Jose";
    timezone = "America/Los_Angeles";
    latitude = 37.3382;
    longitude = -121.8863;
  };

  # The shell drawn on top of niri. One master switch, and each shell's module
  # enables itself when it matches — see lib/my-options-module.nix and
  # docs/adr/0004. Values: "dank" (DankMaterialShell), "noctalia",
  # "serpantinum", or null for a bare niri session. Do not enable two: they
  # would both claim org.freedesktop.Notifications and both draw a bar.
  my.desktopShell = "dank";
}
