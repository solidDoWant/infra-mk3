{
  lib,
  config,
  pkgs,
  ...
}:
# Joins the VM to the Teleport cluster as an SSH node on boot, using the
# kubernetes join method - the same approach as the insurgency server.
#
# The VM mounts the `coder-vm-workspace` ServiceAccount token via a KubeVirt
# serviceAccount volume (virtiofs; see vm.tf). Teleport's auth validates that
# token against the TeleportProvisionToken that allows
# development:coder-vm-workspace, then admits the node. The node registers under
# its hostname (set per-workspace by cloud-init), so `tsh ssh coder@<workspace>`
# works.
let
  teleportPkgs = import ../teleport { inherit pkgs; };
in
{
  # Lets the unprivileged kube-sa-bindfs service use the allow_other mount option
  # so root (teleport) can read the bindfs overlay it mounts as uid 107.
  programs.fuse.userAllowOther = true;

  # Stage the raw Kubernetes service account virtiofs share here. virtiofsd runs
  # unprivileged as the host qemu uid (107) and only serves a guest reader whose
  # uid is also 107, so even root in the guest is denied. The canonical path that
  # teleport reads is instead provided by the kube-sa-bindfs overlay (which runs
  # as uid 107) from this staging mount.
  fileSystems."/run/kubesaraw" = {
    device = "serviceaccount";
    fsType = "virtiofs";
    options = [
      "ro"
      "nofail"
    ];
  };

  # Persist teleport's state (host_uuid etc.) so a workspace restart re-registers
  # as the same node instead of leaking a duplicate into the cluster.
  environment.persistence."/persist".directories = [
    {
      directory = "/var/lib/teleport";
      mode = "0700";
    }
  ];

  users = {
    # Runs the kube-sa-bindfs overlay. The uid MUST be 107 - virtiofsd runs
    # unprivileged as the host qemu uid (107) and only serves a guest reader
    # whose uid matches, so this is the only uid that can read the token. 107 is
    # unassigned in nixpkgs' static id list.
    users.virtiofs = {
      uid = 107;
      group = "virtiofs";
      isSystemUser = true;
      description = "virtiofs SA share reader (matches host qemu uid 107)";
    };
    groups.virtiofs.gid = 107;
  };

  services.teleport = {
    package = teleportPkgs.withBPF;
    enable = true;

    # This follows the teleport config file structure.
    settings = {
      version = "v3";
      teleport = {
        proxy_server = "teleport-cluster.security.svc.cluster.local:443";
        join_params = {
          method = "kubernetes";
          token_name = "coder-vm-workspace";
        };
      };
      auth_service.enabled = false;
      proxy_service.enabled = false;
      ssh_service = {
        enabled = true;
        labels = {
          type = "coder-workspace";
        };
        enhanced_recording = {
          enabled = true;
        };
      };
    };
  };

  systemd.services = {
    # virtiofsd serves the SA share (/run/kubesaraw) only to uid 107 (it runs
    # unprivileged as the host qemu uid and cannot assume another uid), so teleport
    # - which runs as root - is denied reading it directly. bindfs runs as uid 107
    # (so it can read the share) and re-presents the tree at the canonical path as
    # root-owned, with allow_other so root can reach it. The token rotates beneath
    # this live passthrough transparently.
    kube-sa-bindfs = {
      description = "Expose the Kubernetes SA token to root via bindfs (virtiofsd uid 107 workaround)";
      requires = [ "run-kubesaraw.mount" ];
      after = [ "run-kubesaraw.mount" ];
      wantedBy = [ "multi-user.target" ];
      unitConfig.RequiresMountsFor = "/run/kubesaraw";
      serviceConfig = {
        Type = "simple";
        User = "virtiofs";
        Group = "virtiofs";
        # libfuse looks up the setuid fusermount3 (from programs.fuse) on PATH.
        Environment = [ "PATH=/run/wrappers/bin" ];
        # Mountpoint, owned by uid 107 so this unprivileged service may mount on it.
        RuntimeDirectory = "secrets/kubernetes.io/serviceaccount";
        RuntimeDirectoryMode = "0755";
        # Clear any stale mount left by an unclean exit before (re)mounting.
        ExecStartPre = "-/run/wrappers/bin/fusermount3 -uz /run/secrets/kubernetes.io/serviceaccount";
        ExecStart = pkgs.writeShellScript "kube-sa-bindfs" ''
          exec ${pkgs.bindfs}/bin/bindfs \
            -f \
            -o ro,allow_other,force-user=root,force-group=root \
            /run/kubesaraw /run/secrets/kubernetes.io/serviceaccount
        '';
        # Hold "activating" until the mount is actually live, so units ordered
        # after this one don't race the overlay.
        ExecStartPost = pkgs.writeShellScript "kube-sa-bindfs-wait" ''
          for _ in $(${pkgs.coreutils}/bin/seq 1 100); do
            ${pkgs.util-linux}/bin/mountpoint -q /run/secrets/kubernetes.io/serviceaccount && exit 0
            ${pkgs.coreutils}/bin/sleep 0.1
          done
          exit 1
        '';
        ExecStopPost = "-/run/wrappers/bin/fusermount3 -uz /run/secrets/kubernetes.io/serviceaccount";
        Restart = "on-failure";
        RestartSec = 2;
      };
    };

    # Teleport joins via the kubernetes method, reading the SA token at the
    # canonical path. Order it after the bindfs overlay (wants, not requires, so a
    # transient bindfs restart can't tear teleport down; teleport retries its join).
    teleport = {
      wants = [ "kube-sa-bindfs.service" ];
      after = [ "kube-sa-bindfs.service" ];
    };
  };
}
