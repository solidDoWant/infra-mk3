{
  lib,
  config,
  pkgs,
  ...
}:
# Single-persistent-disk impermanence + persistent /nix/store overlay.
#
# The system root is an ephemeral containerDisk overlay (reset from the image on
# every boot), so updating the base image is just a tag bump. Durable state lives
# on ONE persistent block disk (the RWX-block PVC attached by vm.tf, surfaced in
# the guest as /dev/disk/by-id/virtio-persistent). It is formatted on first boot
# (systemd-makefs) and mounted at /persist:
#
#   - /home/coder, /workspace            -> user data (impermanence bind mounts)
#   - /var/lib/nixos                     -> stable dynamic uid/gid allocations
#   - /nix/store (overlay upper)         -> packages installed at runtime, so
#                                           `nix develop` / `nix profile` results
#                                           survive a restart with no recompile
#                                           and no re-download (the whole point)
#   - /nix/var/nix/gcroots               -> keep those packages rooted so the
#                                           automatic GC does not reap them
#
# --- persistent /nix/store (late initrd overlay) -----------------------------
# The store is an overlayfs: read-only lower = the image's OWN /nix/store, writable
# upper on /persist. Content-addressed store paths are additive, so the upper never
# conflicts with a newer image's lower -> base-image bumps stay clean (the new
# system boots from the new lower while user-installed paths in the upper survive).
# We overlay /nix/store (not all of /nix) precisely so a bump can't shadow the new
# image's paths.
#
# TIMING is the crux. /nix/store is hard-coded `neededForBoot`, so the native
# `fileSystems.<>.overlay` option assembles the overlay in early stage-1 - which
# runs BEFORE `initrd-find-nixos-closure`. That finder resolves the system closure
# under /sysroot/nix/store with openat2(RESOLVE_IN_ROOT); it cannot resolve the
# toplevel through an overlay whose lower is a bind of the very store it overlays,
# so the VM drops to emergency mode. (An earlier attempt that overlaid /nix/store
# onto its own lowerdir failed even sooner, at the mount itself.)
#
# So instead of the native option we assemble the overlay OURSELVES in the initrd,
# ordered AFTER the closure finder (which therefore sees the plain image store and
# succeeds) and BEFORE switch-root (so nothing is using /nix/store yet - the final
# system has not started, making the remount safe; unlike a true stage-2 remount
# of an in-use store). systemd's switch-root moves the /sysroot mount subtree to
# /, carrying our overlay (and the /nix/.ro-store bind) into the running system.
# If our setup fails for any reason, it is a *wanted* (not required) unit, so the
# VM still boots - just from the plain store, without persistence, rather than to
# emergency mode.
#
# --- the validity DB ---------------------------------------------------------
# /nix/var/nix/db decides which paths nix treats as real; a path present on disk
# but absent from the DB gets re-realized (re-downloaded / rebuilt), which would
# defeat the persistent upper. The DB lives on the ephemeral root, so on every
# boot it is the image's own DB - correct for the image's paths, and always fresh
# across image bumps. We do NOT bind-persist it: an empty persisted DB would
# shadow the image paths (forcing nix to re-fetch the whole system) and a stale
# one would break image bumps. Instead the nix-db-* units below persist a *dump*
# of the registrations and merge it back into the image DB on boot.
let
  persistDevice = "/dev/disk/by-id/virtio-persistent";

  dbDump = "/persist/nix/db-dump";
  # NIX_REMOTE= forces nix-store to read/write the local DB directly instead of
  # going through nix-daemon. This matters on shutdown: the ExecStop save runs
  # after nix-daemon has stopped, and a daemon-routed dump-db there silently
  # produces an empty file.
  saveDb = pkgs.writeShellScript "nix-db-save" ''
    set -eu
    export NIX_REMOTE=
    mkdir -p /persist/nix
    ${config.nix.package}/bin/nix-store --dump-db > ${dbDump}.tmp
    mv -f ${dbDump}.tmp ${dbDump}
  '';

  # Assembles the /nix/store overlay in the initrd, against the real root at
  # /sysroot, after the closure finder and before switch-root. All the dirs we
  # create live under /sysroot/persist (the writable disk) - /sysroot itself is
  # mounted read-only in the initrd, so we cannot mkdir under /sysroot/nix. The
  # overlay mountpoint /sysroot/nix/store already exists (no mkdir needed) and
  # mounting over a read-only dir is fine.
  setupOverlay = pkgs.writeShellScript "setup-nix-store-overlay" ''
    set -eu
    export PATH=${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.util-linux
      ]
    }
    mkdir -p /sysroot/persist/nix/store /sysroot/persist/nix/work /sysroot/persist/.ro-store
    # Capture the pristine image store as the overlay's read-only lower BEFORE we
    # mount the overlay over /sysroot/nix/store.
    mount --bind /sysroot/nix/store /sysroot/persist/.ro-store
    mount -t overlay overlay \
      -o lowerdir=/sysroot/persist/.ro-store,upperdir=/sysroot/persist/nix/store,workdir=/sysroot/persist/nix/work \
      /sysroot/nix/store
    echo "setup-nix-store-overlay: /nix/store overlay assembled"
  '';
in
{
  boot.initrd = {
    # systemd stage-1 is required: the closure finder we order against is a
    # systemd-initrd unit, and our overlay-setup service lives there too.
    systemd = {
      enable = true;

      # The setup script + the binaries it needs, copied into the (minimal)
      # initrd. The script itself MUST be listed: the initrd builder does not
      # pull a service's ExecStart closure automatically, so without this the
      # unit fails with status=203/EXEC ("Unable to locate executable").
      storePaths = [
        setupOverlay
        pkgs.bash
        pkgs.coreutils
        pkgs.util-linux
      ];

      services.setup-nix-store-overlay = {
        description = "Assemble the persistent /nix/store overlay (after closure-find, before switch-root)";
        # Wanted, not required: if this fails the VM still boots from the plain
        # image store (no persistence) instead of dropping to emergency mode.
        wantedBy = [ "initrd-switch-root.target" ];
        after = [ "initrd-find-nixos-closure.service" ];
        before = [
          "initrd-switch-root.target"
          "initrd-switch-root.service"
        ];
        unitConfig = {
          DefaultDependencies = false;
          # Ensure the root and the persistent disk are mounted first.
          RequiresMountsFor = [
            "/sysroot/nix/store"
            "/sysroot/persist"
          ];
        };
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          TimeoutStartSec = "30s";
          # Surface success/failure on the serial console (virt-launcher
          # guest-console-log) since the initrd journal isn't otherwise visible.
          StandardOutput = "journal+console";
          StandardError = "journal+console";
          ExecStart = setupOverlay;
        };
      };
    };

    # We mount the overlay by hand (not via fileSystems), so pull the module in.
    kernelModules = [ "overlay" ];
    availableKernelModules = [ "overlay" ];
  };

  # The persistent disk. neededForBoot so it is mounted in stage-1, ready for the
  # overlay-setup service and the impermanence bind mounts.
  fileSystems."/persist" = {
    device = persistDevice;
    fsType = "ext4";
    # systemd-makefs formats the disk on first boot if it has no filesystem.
    options = [ "x-systemd.makefs" ];
    neededForBoot = true;
  };

  # Persist user data + the per-user nix gcroots (so automatic GC does not reap
  # packages a user installed at runtime - their profile gcroots land here). The
  # impermanence module creates the backing dirs under /persist and bind-mounts
  # them with correct ordering.
  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      # Stable dynamic uid/gid allocations across reboots (the root is
      # ephemeral). Without this, system users without static ids are reassigned
      # on every boot.
      "/var/lib/nixos"
      # GC roots for runtime-installed packages. Empty on first boot (the running
      # system is always rooted via /run, so shadowing this is harmless).
      "/nix/var/nix/gcroots"
      # Docker daemon state (images, containers, volumes, overlay2). The root is
      # ephemeral, so without persisting this every build/pull would be lost on
      # each reboot. dockerd manages ownership/permissions inside this dir.
      "/var/lib/docker"
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

  # Bound the upper's growth: weekly GC of unreferenced paths older than 30 days.
  # Runtime-installed packages stay rooted via the persisted gcroots above, so
  # they survive; only genuinely orphaned paths are collected.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  systemd = {
    services = {
      # Restore the persisted runtime registrations on top of the image's DB,
      # before anything uses nix. The image DB already knows the image paths;
      # this re-validates the paths in the persistent upper so nix does not
      # re-realize them.
      nix-db-restore = {
        description = "Restore persisted Nix store DB registrations";
        wantedBy = [ "multi-user.target" ];
        # Before the daemon serves requests and before the agent / user touch
        # nix. NOT before nix-daemon.socket: the socket is ordered early (via
        # sockets.target), so adding it here creates an ordering cycle.
        before = [
          "nix-daemon.service"
          "coder-agent.service"
        ];
        after = [ "local-fs.target" ];
        unitConfig.RequiresMountsFor = [
          "/persist"
          "/nix/store"
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = pkgs.writeShellScript "nix-db-restore" ''
            set -eu
            export NIX_REMOTE=
            [ -f ${dbDump} ] || exit 0
            [ -s ${dbDump} ] || exit 0
            ${config.nix.package}/bin/nix-store --load-db < ${dbDump}
          '';
        };
      };

      # Snapshot the registrations to /persist. Driven periodically by the timer
      # below; a restart loses at most the interval's worth of installs, which
      # simply get re-realized and re-registered.
      nix-db-save = {
        description = "Snapshot Nix store DB registrations to /persist";
        after = [ "nix-db-restore.service" ];
        unitConfig.RequiresMountsFor = [
          "/persist"
          "/nix/store"
        ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = saveDb;
        };
      };

      # Also snapshot on a clean shutdown, so the latest installs are captured.
      nix-db-save-shutdown = {
        description = "Snapshot Nix store DB registrations on shutdown";
        wantedBy = [ "multi-user.target" ];
        after = [ "nix-db-restore.service" ];
        unitConfig.RequiresMountsFor = [
          "/persist"
          "/nix/store"
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.coreutils}/bin/true";
          ExecStop = saveDb;
        };
      };
    };

    timers.nix-db-save = {
      description = "Periodically snapshot Nix store DB registrations";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "3min";
        OnUnitActiveSec = "3min";
      };
    };
  };
}
