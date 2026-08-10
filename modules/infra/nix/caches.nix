let
  substituters = [
    "https://cache.flakehub.com"
    "https://nix-community.cachix.org"
    "https://cache.nixos.org/"
    "https://cache.numtide.com"
    "https://pi.cachix.org"
  ];
  keys = [
    "cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM="
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    # Current cache.nixos.org signing key (rotated Jan 2020). The pre-2020
    # key was `hydra.nixos.org-1:CNHJZBh9K4tP3EKF6FkkgeVYsS3ohTl+oS0Qa8bezVs=`
    # and no longer matches any narinfo on the cache.
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    "pi.cachix.org-1:lGeoGJaZ5ZDabuRzkcD5EBTNnDM4HJ1vqeOxlWk1Flk="
  ];
in {
  nix.settings = {
    inherit substituters;
    trusted-substituters = substituters;
    trusted-public-keys = keys;
  };
}
