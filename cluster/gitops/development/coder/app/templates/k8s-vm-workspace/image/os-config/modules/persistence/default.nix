{
  lib,
  config,
  pkgs,
  ...
}:
# Single-persistent-disk impermanence.
#
# The system root is an ephemeral containerDisk overlay (reset from the image on
# every boot), so updating the base image is just a tag bump. State that should
# survive lives on ONE persistent block disk (the RWX-block PVC attached by
# vm.tf, surfaced in the guest as /dev/disk/by-id/virtio-persistent):
#
#   - /home/coder and /workspace -> bind mounts via the impermanence module
#   - /var/lib/nixos / /var/lib/teleport -> stable ids + teleport host identity
#
# The persistent disk is formatted on first boot (systemd-makefs) and mounted at
# /persist.
#
# NOTE: a persistent /nix/store overlay (so runtime `nix profile`/`nix develop`
# installs survive reboots) is intentionally NOT enabled here. The initrd
# overlay-over-its-own-lowerdir approach drops the VM to emergency mode ("Failed
# to mount /sysroot/nix/store" -> "Find NixOS closure" fails), so it needs the
# bind-the-lowerdir-first pattern and on-cluster iteration before it can ship.
# For now /nix comes from the image; durable tooling is added declaratively in
# the image flake (the intended workflow).
let
  persistDevice = "/dev/disk/by-id/virtio-persistent";
in
{
  fileSystems."/persist" = {
    device = persistDevice;
    fsType = "ext4";
    # systemd-makefs formats the disk on first boot if it has no filesystem.
    options = [ "x-systemd.makefs" ];
    # Required by the impermanence module (the persistent store must be mounted
    # early enough for the bind mounts below).
    neededForBoot = true;
  };

  # Persist user data. The impermanence module creates the backing dirs under
  # /persist and bind-mounts them, with correct mount ordering.
  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      # Stable dynamic uid/gid allocations across reboots (the root is
      # ephemeral). Without this, system users without static ids are reassigned
      # on every boot.
      "/var/lib/nixos"
      {
        directory = "/home/coder";
        user = "coder";
        group = "coder";
        mode = "0700";
      }
      {
        directory = "/workspace";
        user = "coder";
        group = "coder";
        mode = "0755";
      }
    ];
  };
}
