# Miraclemax host configuration — capability flags.
# Mac host: nix-darwin + Home Manager, restricted to declarative
# package/app lists only (see modules/infra/darwin-builder.nix for the
# scope rule). chezmoi still owns all dotfiles/config files.
{lib, ...}: {
  my.hostName = "miraclemax";

  # nix-darwin state version. Set once, don't change without reading
  # `darwin-rebuild changelog`. Confirm this is still current on first
  # real deploy — verify via `nix eval .#darwinConfigurations.miraclemax...`
  # or the nix-darwin manual before switching.
  system.stateVersion = 6;

  # bws (bitwarden-secrets-manager) is marked unfree in nixpkgs.
  nixpkgs.config.allowUnfree = true;

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

  # Homebrew: casks (GUI apps) and Mac App Store apps only — CLI tools
  # come from nix above. `brews` is for the small number of formulae
  # with no nixpkgs equivalent.
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      # Do NOT set cleanup = "zap"/"uninstall" until casks/masApps below
      # are fully populated and verified — with empty lists, aggressive
      # cleanup would uninstall every cask/app currently on this machine
      # on first activation.
      cleanup = "none";
    };
    brews = [
      "alerter" # vjeantet/tap/alerter — mac notification tool, no nix package
    ];
    # TODO: populate once you provide `brew list --cask` output for this
    # machine (add to the same mac-packages/ directory).
    casks = [];
    # TODO: populate once you provide `mas list` output for this machine.
    masApps = {};
  };
}
