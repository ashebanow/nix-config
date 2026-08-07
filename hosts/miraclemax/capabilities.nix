# Miraclemax capability flags — split out from configuration.nix
# because this needs to be imported into BOTH the top-level darwin
# module list AND home-manager.users.<user>.imports (see
# darwin-builder.nix). The topical CLI/GUI modules gate their
# home.packages contributions with lib.mkIf config.my.<flag>, and that
# config.my is the Home Manager submodule's own separate options
# instance — it does not inherit values set only at the darwin/system
# scope. configuration.nix itself can't be imported into the HM
# submodule because it also sets darwin-only options (homebrew.*,
# system.stateVersion) that Home Manager's module system doesn't know
# about and would error on.
_: {
  # Capability flags — enable topical CLI package modules.
  my.cliSystemTools = true;
  my.cliProductivityTools = true;
  my.cliVcsTools = true;
  my.cliSecurityTools = true;
  my.cliNetworkTools = true;
  my.cliContainerTools = true;
  my.cliMacOnlyTools = true;
  my.cliAiTools = true;
  my.cliBuildEssentials = true;

  # Capability flags — enable topical GUI app modules. Priority order
  # for macOS apps is nix > Homebrew cask > Mac App Store; these used
  # to be casks (see homebrew.casks in configuration.nix for what's
  # left because it has no real nixpkgs darwin package).
  my.guiTerminals = true;
  my.guiCommunication = true;
  my.guiCoreApps = true;
  my.guiDevApps = true;
  my.guiMediaApps = true;
  my.guiProductivityApps = true;
  my.guiFonts = true;
}
