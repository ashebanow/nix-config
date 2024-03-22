{
  config,
  pkgs,
  ...
}: {
  environment.systemPackages = [
    pkgs.google-chrome
  ];
}
