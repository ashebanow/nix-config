{
  config,
  pkgs,
  self,
  inputs,
  lib,
  ...
}: {
  options = {
    my.modules.firefox.enable = lib.mkEnableOption "Our customized firefox setup";
  };
  config = lib.mkIf config.my.modules.firefox.enable {
    programs.firefox = let
    in {
      enable = true;
      profiles.ashebanow = {
        isDefault = true;
        name = "ashebanow";
        id = 0;
        extraConfig = builtins.readFile ./prefs.js;
        extensions = with config.nur.repos.rycee.firefox-addons; [
          firefox-color
          languagetool
          onepassword-password-manager
          raindropio
          search-by-image
          ublock-origin
          unpaywall
          user-agent-string-switcher
          web-archives
          # darkreader
          # maya-dark
          # mullvad
          # ninja-cookie
          # privacy-badger
          # tampermonkey
          # wappalyzer
        ];
      };
    };
  };
}
