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

  # Capability flags — enable topical GUI app modules. Priority order
  # for macOS apps is nix > Homebrew cask > Mac App Store; these used
  # to be casks (see homebrew.casks below for what's left because it
  # has no real nixpkgs darwin package). All enabled here too, even
  # though some weren't on bergamot's original cask list — reconciling
  # the two machines' environments was the point of this migration.
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
    # Everything else migrated to nix (see the gui-* modules above) —
    # these are what's left because nixpkgs has no real darwin package
    # for them. antigravity-cli/cmux moved to cli-ai-tools.nix (they're
    # CLI tools despite the "-cli" cask naming); bitwarden/discord/
    # dolphin/ghostty/google-chrome/kitty/pinta/signal/slack/
    # visual-studio-code/vlc/warp/zed all moved to gui-* modules.
    casks = [
      "claude" # Claude desktop app — no nixpkgs package found
      "firefox" # low priority to migrate, keeping on cask for now
      "logseq" # nixpkgs package pulls in an EOL/insecure Electron — not worth the tradeoff
      "parsec" # nixpkgs' parsec-bin is Linux-only
      "resilio-sync" # nixpkgs' resilio-sync is Linux-only
      "tailscale-app" # GUI menu bar app has no nix equivalent (CLI is nix-provided via cli-network-tools)
    ];
  };
}
