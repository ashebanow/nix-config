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
      # "uninstall" removes stray casks/brews/mas apps not declared
      # below but leaves app data/preferences alone. Not "zap" — that
      # also wipes app data, which is a bigger blast radius than we
      # want as a default. Verify the lists below are complete before
      # the first real `darwin-rebuild switch`.
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
    masApps = {
      ColorSlurp = 1287239339;
      Compressor = 6746516157;
      Developer = 640199958;
      "Final Cut Pro" = 1631624924;
      GarageBand = 682658836;
      Keynote = 361285480;
      "Logic Pro" = 1615087040;
      MainStage = 6746637089;
      Motion = 6746637149;
      mymind = 1532801185;
      Numbers = 361304891;
      Pages = 361309726;
      "Paprika Recipe Manager 3" = 1303222628;
      "Remote Desktop" = 409907375;
      Slack = 803453959;
      "Swift Playground" = 1496833156;
      TestFlight = 899247664;
      Xcode = 497799835;
    };
  };
}
