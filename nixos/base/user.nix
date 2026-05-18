{
  flake.nixosModules.base = {lib, ...}: {
    options.preferences = {
      user = {
        name = lib.mkOption {
          type = lib.types.str;
          default = "ashebanow";
        };
        email = lib.mkOption {
          type = lib.types.str;
          default = "ashebanow@gmail.com";
        };
        signingKey = lib.mkOption {
          type = lib.types.path;
          default = /home/ashebanow/.ssh/github_ed25519.pub;
          description = "Path to SSH public key for commit signing";
        };
      };
    };
  };
}
