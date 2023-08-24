# BOOTSTRAPPING

## nixOS Systems
1. Install nixos on device as normal.
2. Install our nix-config in your home directory, then edit the files to match your own username, hostnames, etc. Note that the home manager installer will create a basic configuration for you in ```~/.config/home-manager```, but you won't be using it since we have a more sophisticated setup in our repo.
```zsh
$ nix run home-manager/master -- init --switch
$ git clone git@github.com:ashebanow/nix-config.git
```
3. Copy the configuration.nix and hardware.nix files to the nix-config/system in a new subdirectory named after your machine. Modify those files as needed to accomodate flakes and home-manager. Be sure to add the matching code in flake.nix to load your hardware-specific configuration.
4. Edit the script ```~/nix-config/scripts/copy-ssh-keys.sh``` to understand your machine's hostnames and IP addresses. Then run the script on a machine which has the necessary .ssh setup already, so that your private keys etc are transferred to the remote machine.
5. Set up the system to use our nix-config repo:
```zsh
$ ~/nix-config/scripts/flake-switch.sh
```

## Linux Systems
1. Install nix using the Deterministic Systems installer:

```zsh
$ curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

2. Install home manager. Then install our nix-config github repo in your home directory. Note that the home manager installer will create a basic configuration for you in ```~/.config/home-manager```, but you won't be using it since we have a more sophisticated setup in our repo.
```zsh
$ nix run home-manager/master -- init --switch
$ git clone git@github.com:ashebanow/nix-config.git
```
3. Edit the script ```~/nix-config/scripts/copy-ssh-keys.sh``` to understand your machine's hostnames and IP addresses. Then run the script on a machine which has the necessary .ssh setup already, so that your private keys etc are transferred to the remote machine.
4. Set up the system to use our nix-config repo:
```zsh
$ ~/nix-config/scripts/flake-switch.sh
```
## Mac Systems

Similar to Linux systems above, but you need to use Darwin. More details coming soon..

# WORK STILL NEEDED:
1. ssh config
2. git commit signing
3. secrets in general
4. vscode config