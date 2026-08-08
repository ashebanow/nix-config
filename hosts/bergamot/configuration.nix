# Bergamot host configuration — darwin-only settings.
# Mac host: nix-darwin + Home Manager, restricted to declarative
# package/app lists only (see modules/infra/darwin-builder.nix for the
# scope rule). chezmoi still owns all dotfiles/config files. Capability
# flags (my.cliXxx/guiXxx) live in ./capabilities.nix, not here — see
# that file for why.
{lib, ...}: {
  imports = [./capabilities.nix];

  my.base = true;
  my.hostName = "bergamot";
  my.baseTimezone = "America/Los_Angeles";

  my.cliAiTools = true;
  my.cliBuildEssentials = true;
  my.cliContainerTools = true;
  my.cliMacOnlyTools = true;
  my.cliNetworkTools = true;
  my.cliProductivityTools = true;
  my.cliSecurityTools = true;
  my.cliSystemTools = true;
  my.cliTools = true;
  my.cliVcsTools = true;
  my.guiCommunication = true;
  my.guiCoreApps = true;
  my.guiDevApps = true;
  my.guiFonts = true;
  my.guiMediaApps = true;
  my.guiProductivityApps = true;
  my.guiTerminals = true;

  # nix-darwin state version. Set once, don't change without reading
  # `darwin-rebuild changelog`. Confirm this is still current on first
  # real deploy — verify via `nix eval .#darwinConfigurations.bergamot...`
  # or the nix-darwin manual before switching.
  system.stateVersion = 6;

  # bws (bitwarden-secrets-manager) is marked unfree in nixpkgs.
  nixpkgs.config.allowUnfree = true;

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
      "mole" # nixpkgs marks this broken currently
      "oxker" # nixpkgs build fails a macOS-specific snapshot test
    ];
    # Everything else migrated to nix (see the gui-* modules above) —
    # these are what's left because nixpkgs has no real darwin package
    # for them, or the real build doesn't work on real hardware.
    # antigravity-cli/cmux moved to cli-ai-tools.nix (they're CLI tools
    # despite the "-cli" cask naming); discord/ghostty/google-chrome/
    # kitty/pinta/signal/slack/visual-studio-code/vlc/warp/zed all
    # moved to gui-* modules.
    casks = [
      # "arto" # no nixpkgs package found
      "bitwarden" # nixpkgs version uses dangerous version of electron
      "claude" # Claude desktop app — no nixpkgs package found
      "devtoys" # no nixpkgs package found
      "disk-diet" # no nixpkgs package found
      # "dolphin" # nixpkgs' dolphin-emu needs to build sfml from source, which crashes the linker on real hardware
      "firefox" # low priority to migrate, keeping on cask for now
      # "google-drive" # proprietary, no nixpkgs package
      "logseq" # nixpkgs package pulls in an EOL/insecure Electron — not worth the tradeoff
      "microsoft-auto-update" # proprietary Microsoft tooling
      "microsoft-office" # proprietary, licensed software
      # "pinta" # nixpkgs' pinta needs libadwaita built from source, which crashes the linker on real hardware
      "postico" # no nixpkgs package found
      "resilio-sync" # nixpkgs' resilio-sync is Linux-only
      "retrobatch" # no nixpkgs package found
      "sf-symbols" # Apple developer tool, proprietary
      "steam" # nixpkgs' steam is architecturally a Linux thing, not meaningful via nix on macOS
      # "tg-pro" # no nixpkgs package found
    ];
  };
}
