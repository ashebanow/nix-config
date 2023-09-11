# BOOTSTRAPPING

## nixOS Systems
1. Install nixos on device as normal. Choose your hostname and remember it. We'll refer to it as $HOST from now on in this doc.
2. Install our nix-config in your home directory.
```zsh
$ git clone git@github.com:ashebanow/nix-config.git
```
3. Edit /etc/nixos/configuration.nix to have hostname set to $HOST, and add this line to the top of the outputs section:
```zsh
  nix.settings.experimental-features = [ "nix-command", "flakes" ];
```
Do a ```sudo nixos-rebuild switch``` and then reboot the system.
4. Copy ```/etc/nixos/hardware-configuration.nix``` to ```nix-config/system/nixos/$HOST-hardware-configuration.nix```. 
5. Edit the script ```~/nix-config/scripts/copy-ssh-keys.sh``` to understand your machine's hostnames and IP addresses if needed. Then run the script on a machine which has the necessary .ssh setup already, so that your private keys etc are transferred to the remote machine.
6. Set up the system to use our nix-config repo:
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