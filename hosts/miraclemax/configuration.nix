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

  # Homebrew: casks (GUI apps) only — CLI tools come from nix above.
  # `brews` is for the small number of formulae with no nixpkgs
  # equivalent. Mac App Store apps are NOT managed here — nix-darwin's
  # homebrew.masApps runs `brew bundle` under sudo during activation,
  # but mas/installd needs the logged-in user's session and fails
  # under root. See scripts/darwin-migration/mas-sync.sh and
  # hosts/miraclemax/mas-apps.txt instead (run directly, not via
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
      "1password-cli"
      "arc"
      "arto"
      "betterdisplay"
      "bitwarden"
      "claude"
      "devtoys"
      "discord"
      "disk-diet"
      "dolphin"
      "firefox"
      "font-fira-mono"
      "font-jetbrains-mono"
      "font-meslo-lg-nerd-font"
      "font-monaspace-nerd-font"
      "font-monaspice-nerd-font"
      "font-powerline-symbols"
      "font-sauce-code-pro-nerd-font"
      "font-symbols-only-nerd-font"
      "ghostty"
      "google-chrome"
      "google-drive"
      "logseq"
      "microsoft-auto-update"
      "microsoft-office"
      "mist"
      "monitorcontrol"
      "parsec"
      "pinta"
      "postico"
      "postman"
      "raycast"
      "retrobatch"
      "sf-symbols"
      "signal"
      "slack"
      "soundsource"
      "stats"
      "steam"
      # "tailscale" (plain, no "-app" suffix) is unusual as a cask token
      # — worth double-checking this isn't a stray formula-vs-cask mixup
      # from list generation. tailscale-app is the known GUI cask; the
      # CLI is already provided by the nix cli-network-tools module.
      "tailscale"
      "tailscale-app"
      "temurin"
      "tg-pro"
      "utm"
      "visual-studio-code"
      "vlc"
      "warp"
      "zed"
      "zen"
      "zoom"
    ];
  };
}
