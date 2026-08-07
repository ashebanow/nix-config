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

  # Capability flags — enable topical GUI app modules. Priority order
  # for macOS apps is nix > Homebrew cask > Mac App Store; these used
  # to be casks (see homebrew.casks below for what's left because it
  # has no real nixpkgs darwin package).
  my.guiTerminals = true;
  my.guiCommunication = true;
  my.guiCoreApps = true;
  my.guiDevApps = true;
  my.guiMediaApps = true;
  my.guiProductivityApps = true;
  my.guiFonts = true;

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
    # Everything else migrated to nix (see the gui-* modules above, and
    # _1password-cli in cli-security-tools.nix) — these are what's left
    # because nixpkgs has no real darwin package for them.
    # font-monaspice-nerd-font dropped entirely — looks like a typo/
    # duplicate of font-monaspace-nerd-font (which did migrate).
    casks = [
      "arc" # removed from nixpkgs as unmaintained
      "arto" # no nixpkgs package found
      "claude" # Claude desktop app — no nixpkgs package found
      "devtoys" # no nixpkgs package found
      "disk-diet" # no nixpkgs package found
      "firefox" # low priority to migrate, keeping on cask for now
      "google-drive" # proprietary, no nixpkgs package
      "logseq" # nixpkgs package pulls in an EOL/insecure Electron — not worth the tradeoff
      "microsoft-auto-update" # proprietary Microsoft tooling
      "microsoft-office" # proprietary, licensed software
      "postico" # no nixpkgs package found
      "retrobatch" # no nixpkgs package found
      "sf-symbols" # Apple developer tool, proprietary
      "steam" # nixpkgs' steam is architecturally a Linux thing, not meaningful via nix on macOS
      # "tailscale" (plain, no "-app" suffix) is unusual as a cask token
      # — worth double-checking this isn't a stray formula-vs-cask mixup
      # from list generation. tailscale-app is the known GUI cask; the
      # CLI is already provided by the nix cli-network-tools module.
      "tailscale"
      "tailscale-app"
      "tg-pro" # no nixpkgs package found
      "zen" # Zen Browser — no nixpkgs package found
    ];
  };
}
