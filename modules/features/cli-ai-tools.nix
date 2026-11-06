# AI-agent CLI tools — Home Manager package list.
#
# Both agents here are universal rather than project-specific: you want them
# whether you are in a Rust repo, a Python repo, or this one. They were
# previously reachable only inside this repo's dev shell, which made them
# unavailable for every other project on the same machine.
_: {
  my.modules.home-manager.cli-ai-tools =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    {
      config = lib.mkIf config.my.cliAiTools {
        home.packages = with pkgs; [
          claude-code
          llmfit
          opencode
          # pi.nix's build, not nixpkgs': nixpkgs' expects to install/update
          # under its own prefix at runtime and so does not work in NixOS's
          # read-only store. `pkgs.pi-coding-agent` exists only where the pi
          # overlay (lib/overlays/pi.nix) is applied — every host and the dev
          # shell. Do not `pi update`; the binary is in the store and moves via
          # `nix flake update pi-nix` plus a rebuild.
          pi-coding-agent
        ];
      };
    };
}
