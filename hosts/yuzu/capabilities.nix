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
}
