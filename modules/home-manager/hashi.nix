{
  config,
  pkgs,
  ...
}: {
  home.packages = with pkgs; [
    consul
    # damon
    # levant
    # nomad
    # nomad-autoscaler
    # nomad-pack
    packer
    terraform
    terragrunt
    tflint
    vault
  ];
}
