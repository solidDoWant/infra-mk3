{
  pkgs,
  ...
}:
# toolgate workspace attestation: gives the coder user read access to the VM's
# toolgate token, which the toolgate CLI sends to the gateway with each session.
#
# The token is a projected service-account token with audience `toolgate`,
# bound to this VM's virt-launcher pod. A MutatingAdmissionPolicy adds it to the
# launcher's compute container (development/coder/app/vm-workspace-tokens.yaml),
# and the template shares it with the guest as the `toolgate-token` virtiofs
# volume (a KubeVirt containerPath volume, only when toolgate is enabled).
#
# Like the service-account share in ../teleport-node, virtiofsd serves it only
# to uid 107, so a bindfs running as that uid re-presents it at
# /run/toolgate-attestation, owned by coder and readable by nobody else. The
# token rotates underneath this live passthrough. The template points the CLI
# at /run/toolgate-attestation/token (toolgate configure
# --attestation-token-file).
let
  raw = "/run/toolgatetokenraw";
  view = "/run/toolgate-attestation";
in
{
  # The `virtiofs` user (uid 107) and programs.fuse.userAllowOther come from
  # ../teleport-node.
  fileSystems.${raw} = {
    device = "toolgate-token";
    fsType = "virtiofs";
    options = [
      "ro"
      "nofail"
    ];
  };

  systemd.services.toolgate-attestation-bindfs = {
    description = "Expose the toolgate attestation token to the coder user via bindfs (virtiofsd uid 107 workaround)";
    wantedBy = [ "multi-user.target" ];
    # Ordered after the share's mount. Wants, not Requires: workspaces without
    # toolgate have no share, so the mount fails (nofail) and the condition then
    # skips this unit instead of failing it.
    unitConfig = {
      WantsMountsFor = raw;
      ConditionPathIsMountPoint = raw;
    };
    serviceConfig = {
      Type = "simple";
      User = "virtiofs";
      Group = "virtiofs";
      # libfuse looks up the setuid fusermount3 (from programs.fuse) on PATH.
      Environment = [ "PATH=/run/wrappers/bin" ];
      # Mountpoint, owned by uid 107 so this unprivileged service may mount on it.
      RuntimeDirectory = "toolgate-attestation";
      RuntimeDirectoryMode = "0755";
      ExecStartPre = "-/run/wrappers/bin/fusermount3 -uz ${view}";
      ExecStart = pkgs.writeShellScript "toolgate-attestation-bindfs" ''
        exec ${pkgs.bindfs}/bin/bindfs \
          -f \
          -o ro,allow_other,force-user=coder,force-group=coder,perms=u=rD:go= \
          ${raw} ${view}
      '';
      ExecStartPost = pkgs.writeShellScript "toolgate-attestation-bindfs-wait" ''
        for _ in $(${pkgs.coreutils}/bin/seq 1 100); do
          ${pkgs.util-linux}/bin/mountpoint -q ${view} && exit 0
          ${pkgs.coreutils}/bin/sleep 0.1
        done
        exit 1
      '';
      ExecStopPost = "-/run/wrappers/bin/fusermount3 -uz ${view}";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };
}
