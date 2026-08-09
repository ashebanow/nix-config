# zmx — session persistence and workflow tool for terminal sessions.
# Registered as a NixOS module gated by my.zmx capability flag.
# Uses the nixpkgs-packaged zmx (pinned release tag, vendored zig deps)
# rather than the upstream flake input — the upstream flake's zig pin
# lags its code and fails to build in the sandbox.
_: {
  my.modules.nixos.zmx = {
    lib,
    config,
    pkgs,
    ...
  }: {
    config = lib.mkIf config.my.zmx {
      environment.systemPackages = [
        pkgs.zmx
      ];
    };
  };
}
