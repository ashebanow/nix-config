# GDM — the gruvbox greeter theme. That GDM is the display manager at all is
# desktop.nix's decision (see docs/adr/0003 for why it is GDM and not
# DankGreeter); this module only makes the login screen look like the session.
# GNOME-specific session tuning lives in gnome.nix.
_: {
  my.modules.nixos.gdm = {
    lib,
    config,
    pkgs,
    ...
  }: {
    config = lib.mkIf config.my.desktop {
      # The greeter only sees themes on its own XDG_DATA_DIRS, which GDM's
      # environment does not otherwise include.
      services.displayManager.gdm.extraPackages = [
        pkgs.gruvbox-gtk-theme
        pkgs.gruvbox-plus-icons
        # Provides the User Themes extension that GDM's gnome-shell would need in
        # order to load a shell theme at all. Unverified — GDM may ignore user
        # extensions, in which case the greeter keeps the gruvbox GTK theme and
        # icons and the shell stays Adwaita. Recorded as best-effort in
        # docs/adr/0003; if it does not take, drop this package and the two
        # org/gnome/shell settings below.
        pkgs.gnome-shell-extensions
      ];

      # programs.dconf.profiles.gdm is the greeter's own dconf database. The GDM
      # module in nixpkgs already writes to it, so this list is merged with it.
      programs.dconf.profiles.gdm.databases = [
        {
          settings."org/gnome/desktop/interface" = {
            gtk-theme = "Gruvbox-Dark";
            icon-theme = "Gruvbox-Plus-Dark";
          };
          # The extension UUID is gnome-shell-extensions'; see
          # pkgs.gnome-shell-extensions for the user-theme extension it ships.
          settings."org/gnome/shell" = {
            enabled-extensions = ["user-theme@gnome-shell-extensions.gcampax.github.com"];
          };
          settings."org/gnome/shell/extensions/user-theme" = {
            name = "Gruvbox-Dark";
          };
        }
      ];
    };
  };
}
