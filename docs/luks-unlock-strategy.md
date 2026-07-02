# LUKS Unlock Strategy for Lumquat (and future servers)

## Summary

Lumquat's root disk is LUKS-encrypted. On every reboot, the LUKS passphrase
must be provided to unlock the root filesystem. Since lumquat is a headless
AI server, we need unattended reboots without sacrificing physical security.

## Threat Model

| Concern | Priority |
|---|---|
| Unattended reboots (power outage, kernel update) | **Must have** |
| Disk pulled from machine (NVMe theft) | Protected |
| Entire machine theft (mini PC is portable) | Medium — TPM helps minimally, Tang would cover this |

## Current Approach: TPM2 Auto-Unlock

**What it does:** The AMD fTPM on the Strix Halo SoC releases the LUKS key
only if the boot chain (firmware → bootloader) is untampered. The disk unlocks
automatically on every boot — no passphrase, no network, no human interaction.

**What it protects against:**
- Disk pulled from machine → useless without the TPM
- Tampered firmware/bootloader → PCR mismatch, TPM refuses to release key

**What it doesn't protect against:**
- Complete machine theft → disk decrypts on boot (TPM is in the stolen machine)

**PCR policy:** `0` (firmware). If Secure Boot is later enabled via lanzaboote,
re-enroll with `0+7` for added boot chain integrity verification.

### NixOS Configuration

Added to `hardware-configuration.nix`:

```nix
boot.initrd.systemd.enable = true;
boot.initrd.availableKernelModules = [ ... "tpm_tis" "r8169" ];
```

The `tpm_tis` module ensures TPM access in the initrd. The `r8169` module
was also added (previously missing, needed for future Tang networking).

### Enrollment

Run once on lumquat:

```bash
systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0 \
  /dev/disk/by-uuid/2363ecb6-9c4e-4c6a-a948-1e5e24089470
```

This adds a TPM2-protected keyslot to the existing LUKS2 header.
The original passphrase keyslot is **preserved** as a fallback.

### Verification

```bash
# List LUKS keyslots — should show a new systemd-tpm2 token
cryptsetup luksDump /dev/disk/by-uuid/2363ecb6-9c4e-4c6a-a948-1e5e24089470 | grep -A5 "Token"

# Test TPM unlock manually (before rebooting)
systemd-cryptsetup attach luks-root \
  /dev/disk/by-uuid/2363ecb6-9c4e-4c6a-a948-1e5e24089470 - tpm2-device=auto
```

## Future: Tang (Network-Bound Disk Encryption)

When a second NixOS server is online, Tang can provide theft protection:

```
Lumquat boots → contacts Tang server on second NixOS machine → key released
If stolen → no Tang access → disk stays locked
```

### Second NixOS server configuration (Tang server):

```nix
services.tang.enable = true;
# Tang listens on port 80 by default, keys at /var/db/tang
```

### Lumquat configuration changes (Tang client):

```nix
boot.initrd.network.enable = true;  # DHCP in initrd

boot.initrd.clevis = {
  enable = true;
  useTang = true;
  devices."luks-root" = {
    secretFile = ./luks-root.jwe;
  };
};
```

Then enroll:

```bash
# Generate random key, add to LUKS, encrypt with Tang
dd if=/dev/urandom bs=32 count=1 of=/tmp/luks-key
cryptsetup luksAddKey /dev/disk/by-uuid/2363ecb6-9c4e-4c6a-a948-1e5e24089470 /tmp/luks-key
clevis encrypt tang '{"url":"http://<tang-server-lan-ip>"}' < /tmp/luks-key > luks-root.jwe
rm /tmp/luks-key
```

Save `luks-root.jwe` alongside `hardware-configuration.nix` and reference it
in the config above. The JWE is safe to commit — it can only be decrypted
when Tang is reachable.

## Fallback

The original LUKS passphrase keyslot remains intact through all of this.
If TPM2 fails (firmware update changes PCRs), the system falls back to
the passphrase prompt. You can:

1. Attach a keyboard/monitor and type the passphrase at the console
2. (Future) Set up initrd SSH for remote passphrase entry via Tailscale

## Rollback

To undo TPM2 enrollment:

```bash
# Find and remove the TPM2 keyslot
systemd-cryptenroll /dev/disk/by-uuid/2363ecb6-9c4e-4c6a-a948-1e5e24089470 --wipe=tpm2
```

NixOS config rollback: remove `boot.initrd.systemd.enable = true` and rebuild.
