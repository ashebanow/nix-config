# Bergamot host configuration — capability flags.
# Mac host: nix-darwin + Home Manager, restricted to declarative
# package/app lists only (see modules/infra/darwin-builder.nix for the
# scope rule). chezmoi still owns all dotfiles/config files.
{lib, ...}: {
  my.hostName = "bergamot";

  # nix-darwin state version. Set once, don't change without reading
  # `darwin-rebuild changelog`. Confirm this is still current on first
  # real deploy — verify via `nix eval .#darwinConfigurations.bergamot...`
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

  # Homebrew: casks (GUI apps) only — CLI tools come from nix above.
  # `brews` is for the small number of formulae with no nixpkgs
  # equivalent. Mac App Store apps are NOT managed here — nix-darwin's
  # homebrew.masApps runs `brew bundle` under sudo during activation,
  # but mas/installd needs the logged-in user's session and fails
  # under root. See scripts/darwin-migration/mas-sync.sh and
  # hosts/bergamot/mas-apps.txt instead (run directly, not via
  # darwin-rebuild).
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      # "uninstall" removes stray casks/brews not declared below but
      # leaves app data/preferences alone. Not "zap" — that also wipes
      # app data, which is a bigger blast radius than we want as a
      # default. Verify the lists below are complete before the first
      # real `darwin-rebuild switch`.
      cleanup = "uninstall";
    };
    brews = [
      "alerter" # vjeantet/tap/alerter — mac notification tool, no nix package
    ];
    casks = [
      "antigravity-cli"
      "bitwarden"
      "claude"
      "cmux"
      "discord"
      "dolphin"
      "firefox"
      "ghostty"
      "google-chrome"
      "kitty"
      "logseq"
      "parsec"
      "pinta"
      "resilio-sync"
      "signal"
      "slack"
      "tailscale-app"
      "visual-studio-code"
      "vlc"
      "warp"
      "zed"
      "zoom"
    ];
  };
}
