{
  lib,
  config,
  pkgs,
  ...
}:
# Single-persistent-disk impermanence.
#
# The system root is an ephemeral containerDisk overlay (reset from the image on
# every boot), so updating the base image is just a tag bump. All state that
# should survive lives on ONE persistent block disk (the RWX-block PVC attached
# by vm.tf, surfaced in the guest as /dev/disk/by-id/virtio-persistent):
#
#   - /home/coder and /workspace   -> bind mounts via the impermanence module
#   - /nix/store user-installed paths -> overlayfs (image store + persistent upper)
#
# The persistent disk is formatted on first boot (systemd-makefs) and mounted at
# /persist.
let
  persistDevice = "/dev/disk/by-id/virtio-persistent";
in
{
  # systemd in the initrd so the /nix/store overlay can be assembled before the
  # system switches root onto it.
  boot.initrd.systemd.enable = true;

  fileSystems."/persist" = {
    device = persistDevice;
    fsType = "ext4";
    # systemd-makefs formats the disk on first boot if it has no filesystem.
    options = [ "x-systemd.makefs" ];
    # Mounted in the initrd (at /sysroot/persist) so the overlay below can use it.
    neededForBoot = true;
  };

  # Persist user data. The impermanence module creates the backing dirs under
  # /persist and bind-mounts them, with correct mount ordering.
  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
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

  # ---------------------------------------------------------------------------
  # /nix/store overlay
  # ---------------------------------------------------------------------------
  # EXPERIMENTAL - validate on-cluster before relying on it. The intent: user-
  # installed store paths (`nix profile install`, `nix develop` deps) land in the
  # overlay upperdir on the persistent disk and survive reboots; on a base-image
  # bump the read-only lowerdir is replaced wholesale, which is conflict-free
  # because store paths are content-addressed and additive.
  #
  # Caveat (documented in the README): the nix database (/nix/var) is on the
  # ephemeral root and resets each boot, so persisted paths are present at the
  # file level (the ~/.nix-profile symlinks in the persistent home resolve) but
  # are not DB-registered. Do not run `nix-collect-garbage` in this workspace,
  # and prefer adding durable tooling declaratively in the image flake.
  #
  # The overlay is mounted over its own lowerdir: the kernel opens the lower
  # (the image's /nix/store) before the mount shadows it, a pattern NixOS
  # impermanence setups use for /nix.
  boot.initrd.systemd.services.nix-store-overlay-prep = {
    description = "Create /nix/store overlay dirs on the persistent disk";
    wantedBy = [ "initrd.target" ];
    requires = [ "sysroot-persist.mount" ];
    after = [
      "sysroot.mount"
      "sysroot-persist.mount"
    ];
    before = [ "sysroot-nix-store.mount" ];
    unitConfig.DefaultDependencies = false;
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.coreutils}/bin/mkdir -p /sysroot/persist/nix/store/upper /sysroot/persist/nix/store/work";
    };
  };

  boot.initrd.systemd.mounts = [
    {
      what = "overlay";
      where = "/sysroot/nix/store";
      type = "overlay";
      options = lib.concatStringsSep "," [
        "lowerdir=/sysroot/nix/store"
        "upperdir=/sysroot/persist/nix/store/upper"
        "workdir=/sysroot/persist/nix/store/work"
      ];
      wantedBy = [ "initrd.target" ];
      requires = [ "nix-store-overlay-prep.service" ];
      after = [
        "sysroot.mount"
        "nix-store-overlay-prep.service"
      ];
      before = [ "initrd-fs.target" ];
      unitConfig.DefaultDependencies = false;
    }
  ];
}
