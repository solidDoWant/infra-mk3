{
  pkgs,
  ...
}:
# The workspace's SSH signing key for git commits, from a mounted Secret.
#
# The template makes a new key at every start, registers it on the owner's
# GitHub account through githubgate and deletes it at stop (template
# signing-keys.tf). The private key is in a per-workspace Secret that the VM
# gets as the `git-signing-key` virtiofs share; it is never written in the
# guest. While the workspace is stopped the Secret doesn't exist, and with it
# goes the key.
#
# Like ../toolgate-attestation, virtiofsd serves the share only to uid 107, so
# a bindfs running as that uid re-presents it at /run/coder-git-signing, owned
# by coder and readable by nobody else (ssh-keygen refuses a private key that
# others can read). The template's coder_script points git at
# /run/coder-git-signing/key.
let
  raw = "/run/gitsigningkeyraw";
  view = "/run/coder-git-signing";
in
{
  # The `virtiofs` user (uid 107) and programs.fuse.userAllowOther come from
  # ../teleport-node.
  fileSystems.${raw} = {
    device = "git-signing-key";
    fsType = "virtiofs";
    options = [
      "ro"
      "nofail"
    ];
  };

  systemd.services.git-signing-key-bindfs = {
    description = "Expose the git signing key to the coder user via bindfs (virtiofsd uid 107 workaround)";
    wantedBy = [ "multi-user.target" ];
    # Before the agent, which runs the script that points git at the key.
    before = [ "coder-agent.service" ];
    # Wants, not Requires: without the share the mount fails (nofail) and the
    # condition skips this unit instead of failing it.
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
      RuntimeDirectory = "coder-git-signing";
      RuntimeDirectoryMode = "0755";
      ExecStartPre = "-/run/wrappers/bin/fusermount3 -uz ${view}";
      ExecStart = pkgs.writeShellScript "git-signing-key-bindfs" ''
        exec ${pkgs.bindfs}/bin/bindfs \
          -f \
          -o ro,allow_other,force-user=coder,force-group=coder,perms=u=rD:go= \
          ${raw} ${view}
      '';
      ExecStartPost = pkgs.writeShellScript "git-signing-key-bindfs-wait" ''
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
