{
  config,
  pkgs,
  inputs,
  nixos-hardware,
  ...
}: {
  environment.systemPackages = with pkgs; [
    cifs-utils
    nfs-utils
    samba
  ];

  services.rpcbind.enable = true;
  services.gvfs.enable = true;

  # services.nfs.server.enable = true;
  # boot.initrd = {
  #   supportedFilesystems = [ "nfs" ];
  #   kernelModules = [ "nfs" ];
  # };

  # Mount SMB shares from storage machine. All of these are set to automount
  # on first use, and unmount after 10 minutes
  #
  # see example from https://fictionbecomesfact.com/nixos-server-configuration
  #
  # NOTE THAT YOU MUST CREATE/COPY the '/etc/nixos/smb-secrets' file to the
  # machine, with USERNAME, DOMAIN and PASSWORD defined on separate lines.
  # FIXME: replace with secrets
  #
  fileSystems = {
    # "/mnt/storage/appdata" = {
    #   device = "//storage.lan/appdata";
    #   fsType = "cifs";
    #   options = [
    #     # Prevent hanging on network loss
    #     "x-systemd.automount"
    #     "noauto"
    #     "x-systemd.idle-timeout=60"
    #     "x-systemd.device-timeout=5s"
    #     "x-systemd.mount-timeout=5s"

    #     # Specify location of credentials file
    #     "credentials=/etc/nixos/smb-secrets"

    #     # Default permissions and file encoding
    #     "file_mode=0777"
    #     "dir_mode=0777"
    #     "iocharset=utf8"
    #   ];
    # };
    # "/mnt/storage/backups" = {
    #   device = "//storage.lan/backups";
    #   fsType = "cifs";
    #   options = [
    #     # Prevent hanging on network loss
    #     "x-systemd.automount"
    #     "noauto"
    #     "x-systemd.idle-timeout=60"
    #     "x-systemd.device-timeout=5s"
    #     "x-systemd.mount-timeout=5s"

    #     # Specify location of credentials file
    #     "credentials=/etc/nixos/smb-secrets-ashebanow"

    #     # Default permissions and file encoding
    #     "file_mode=0777"
    #     "dir_mode=0777"
    #     "iocharset=utf8"

    #     # mount as user, not root
    #     "uid=1000"
    #     "gid=1000"
    #   ];
    # };
    # "/mnt/storage/isos" = {
    #   device = "//storage.lan/isos";
    #   fsType = "cifs";
    #   options = [
    #     # Prevent hanging on network loss
    #     "x-systemd.automount"
    #     "noauto"
    #     "x-systemd.idle-timeout=60"
    #     "x-systemd.device-timeout=5s"
    #     "x-systemd.mount-timeout=5s"

    #     # Specify location of credentials file
    #     "credentials=/etc/nixos/smb-secrets-ashebanow"

    #     # Default permissions and file encoding
    #     "file_mode=0777"
    #     "dir_mode=0777"
    #     "iocharset=utf8"

    #     # mount as user, not root
    #     "uid=1000"
    #     "gid=1000"
    #   ];
    # };
    # "/mnt/storage/media" = {
    #   device = "//storage.lan/media";
    #   fsType = "cifs";
    #   options = [
    #     # Prevent hanging on network loss
    #     "x-systemd.automount"
    #     "noauto"
    #     "x-systemd.idle-timeout=60"
    #     "x-systemd.device-timeout=5s"
    #     "x-systemd.mount-timeout=5s"

    #     # Specify location of credentials file
    #     "credentials=/etc/nixos/smb-secrets-ashebanow"

    #     # Default permissions and file encoding
    #     "file_mode=0777"
    #     "dir_mode=0777"
    #     "iocharset=utf8"

    #     # mount as user, not root
    #     "uid=1000"
    #     "gid=1000"
    #   ];
    # };
  };
}
