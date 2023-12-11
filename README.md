# BOOTSTRAPPING

## nixOS Systems
1. Install nixos on device as normal. Choose your hostname and remember it. We'll refer to it as $HOST from now on in this doc.

2. Install our nix-config in your home directory.
    ```bash
    $ git clone git@github.com:ashebanow/nix-config.git
    $ cd nix-config
    ```

3. Edit /etc/nixos/configuration.nix to have hostname set to $HOST, and add this line to the top of the outputs section:

    ```bash
      nix.settings.experimental-features = [ "nix-command" "flakes" ];
    ```

    Do a ```sudo nixos-rebuild switch``` and then reboot the system.

4. Make a directory ```nix-config/hosts/$HOST```. Copy ```/etc/nixos/hardware-configuration.nix``` to ```nix-config/hosts/```. 

5. Edit the script ```~/nix-config/scripts/copy-ssh-keys.sh``` to understand your machine's hostnames and IP addresses if needed. Then run the script on a machine which has the necessary .ssh setup already, so that your private keys etc are transferred to the remote machine.

6. Set up the system to use our nix-config repo:
    ```bash
    # if you already have just installed, just run it within the nix-config
    # directory
    $ nix-shell -p just
    ```

    If you get errors complaining that nix-command and flakes features are not enabled, copy dotfiles/nix.conf to ~/.config/nix/. You'll need to delete it once the command above runs successfully, then run it again.

## Linux Systems
1. Install nix using the Deterministic Systems installer:

    ```bash
    $ curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
    ```

2. Install home manager. Then install our nix-config github repo in your home directory. Note that the home manager installer will create a basic configuration for you in ```~/.config/home-manager```, but you won't be using it since we have a more sophisticated setup in our repo.

    ```bash
    $ nix run home-manager/master -- init --switch
    $ git clone git@github.com:ashebanow/nix-config.git
    ```

3. Edit the script ```~/nix-config/scripts/copy-ssh-keys.sh``` to understand your machine's hostnames and IP addresses. Then run the script on a machine which has the necessary .ssh setup already, so that your private keys etc are transferred to the remote machine.

4. Set up the system to use our nix-config repo:

    ```bash
    # if you already have just installed, just run it within the nix-config
    # directory
    $ nix-shell -p just
    ```

## Mac Systems

Similar to Linux systems above, but you need to use Darwin. More details coming soon..

# WORK STILL NEEDED:
1. ssh config
2. git commit signing
3. secrets in general
4. vscode config

# GENERAL NOTES:

For debian:

```bash
sudo apt update && sudo apt install -y
apt install -y wget curl git vim zsh

sudo chsh -s $(which zsh) $USER

# WSL only:
sudo vim /etc/hostname
# edit the hostname to whatever you want. Make it different from the
# underlying windows hostname, though. I usually just append the distro name.


```

Add these lines to the /etc/wsl.conf (note you will need to run your editor
with sudo privileges, e.g: sudo nano /etc/wsl.conf):

```bash
[boot]
systemd=true
```

If using WSL, reboot it via ```wsl --shutdown``` in PowerShell and open a new terminal window. For non-WSL, just close down your terminal session and open a new one. You may get a prompt about creating zsh files, you can skip creating them since our next step will take care of them.

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
# you will need to provide sudo password and confirm default settings.

git clone https://github.com/ashebanow/nix-config.git
cd nix-config
```

