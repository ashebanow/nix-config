# Flake Structure

## Entry Point

```nix
# flake.nix
{
  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    import-tree.url = "github:vic/import-tree";
    import-tree.flake = false;
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    colmena = {
      url = "github:zhaofengli/colmena";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-hardware.url = "github:nixos/nixos-hardware";
  };

  outputs = inputs: let
    import-tree = import inputs.import-tree;
  in
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        (import-tree ./modules/infra)
        (import-tree ./modules/features)
        (import-tree ./modules/hosts)
      ];
    };
}
```

## Output Attributes

| Attribute | Description |
|-----------|-------------|
| `nixosConfigurations.lumquat` | The lumquat system |
| `packages.x86_64-linux.*` | Custom packages |
| `devShells.x86_64-linux.default` | Development environment |

## Import-Tree

`import-tree` auto-imports all `.nix` files from the specified directories.
This means NO manual import lists — every `.nix` file becomes a flake-parts module.

## Directory Auto-Import

```
modules/infra/      → imported automatically
modules/features/   → imported automatically  
modules/hosts/      → imported automatically
```

Files prefixed with `_` are excluded from auto-import.
