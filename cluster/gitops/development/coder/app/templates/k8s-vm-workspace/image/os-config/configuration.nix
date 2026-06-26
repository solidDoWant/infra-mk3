{
  lib,
  config,
  pkgs,
  ...
}:
{
  imports = [
    ./modules/ca-trust
    ./modules/git
    ./modules/persistence
    ./modules/teleport-node
  ];

  nixpkgs = {
    hostPlatform = "x86_64-linux";
    config = {
      allowUnfree = true;
    };
  };

  nix = {
    settings = {
      # Enable flakes and the new 'nix' command - projects in this workspace are
      # expected to ship flakes, and `nix develop` is the intended workflow.
      experimental-features = "nix-command flakes";
      # Let the coder user drive nix without sudo.
      trusted-users = [
        "root"
        "coder"
      ];
    };
  };

  boot = {
    # Stock kernel so users can build and load out-of-tree kernel modules - the
    # whole reason for a real VM over the Kata-container workspace. Module
    # signature enforcement is off in nixpkgs kernels by default, so `modprobe`
    # of unsigned/locally-built modules works.
    kernelPackages = pkgs.linuxPackages;
    # serial console for `kubectl virt console` / debugging.
    kernelParams = [ "console=ttyS0" ];
    # nfs client + overlay support for the persistent-disk /nix overlay.
    supportedFilesystems = [
      "nfs"
      "overlay"
    ];
  };

  # Run dynamically-linked, non-Nix binaries without patchelf. Claude Code (a
  # native binary downloaded at runtime by claude.ai/install.sh) would otherwise
  # fail to find an ELF interpreter on NixOS; nix-ld provides the shim + common
  # libraries so it runs as-is. (The Coder agent is the baked-in pkgs.coder, so
  # it does not rely on this.)
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      stdenv.cc.cc.lib
      zlib
      openssl
    ];
  };

  # Cluster PKI root CA trust is handled at runtime - see ./modules/ca-trust
  # (mounts the CA via virtiofs and builds a combined system+cluster bundle).

  networking = {
    # Empty so nothing here imposes a name; the hostname is set at runtime to the
    # Coder workspace name by the coder-set-hostname service below (so the VM, the
    # shell prompt, and the Teleport node all show the workspace name).
    hostName = lib.mkForce "";
    useDHCP = lib.mkForce true; # KubeVirt masquerade serves the guest via DHCP
    # KubeVirt's DHCP hands out the VM id as the hostname; don't let dhcpcd apply
    # it, or it would clobber the workspace name we set above.
    dhcpcd.extraConfig = "nohook hostname";
    # Outbound-only workload (the agent dials out and tunnels apps); the
    # CiliumNetworkPolicy is the real perimeter. Keep the host firewall simple.
    firewall.enable = false;
  };

  environment = {
    systemPackages = with pkgs; [
      # General workspace tooling (git itself comes from programs.git below)
      curl
      wget
      vim
      htop
      jq
      gnumake
      gcc
      # Required by the runtime workspace-setup scripts (which stay dynamic
      # because they consume per-user identity/tokens): gh for the GitHub
      # integration, openssh for ssh / ssh-keygen (git over SSH + commit-signing
      # key upload). The old Ubuntu base image preinstalled these; the minimal
      # NixOS image must bake them in.
      gh
      openssh
      # Kernel-module development / inspection
      kmod
      # NFS client helpers (for the optional bulk-pool mount)
      nfs-utils
      # The Coder agent/CLI. The coder-agent service runs `coder agent`; users
      # also get the `coder` CLI. Pinned via flake.lock - keep roughly in sync
      # with the Coder server version.
      coder
    ];

    # Keep a copy of the system config in the image for reference / rebuilds.
    etc."nixos".source = ./.;

    # The Coder modules install tools into ~/.local/bin (Claude Code) and
    # /usr/local/bin (AgentAPI); put both on interactive shells' PATH too so the
    # user can run them directly.
    localBinInPath = true;
    extraInit = ''
      export PATH="$PATH:/usr/local/bin"
    '';
  };

  # /usr/local/bin doesn't exist on NixOS; the AgentAPI installer does
  # `mv agentapi /usr/local/bin/` and fails without it. Create it (ephemeral root,
  # recreated each boot - the module reinstalls on start anyway).
  systemd.tmpfiles.rules = [ "d /usr/local/bin 0755 root root -" ];

  users = {
    # Coder workspace user. uid/gid 1000 to match the agent expectations and the
    # persistent /home/coder ownership.
    users.coder = {
      uid = 1000;
      isNormalUser = true;
      home = "/home/coder";
      shell = pkgs.bashInteractive;
      extraGroups = [
        "wheel" # passwordless sudo (below) - users need root for kernel modules
      ];
      # No password login; access is via the Coder agent (web terminal / SSH).
      hashedPassword = "";
    };
    groups.coder.gid = 1000;
  };

  # Passwordless sudo for the workspace user - loading kernel modules and
  # installing system packages is the point of this template.
  security.sudo = {
    enable = true;
    wheelNeedsPassword = false;
  };

  services = {
    # Serve /bin and /usr/bin from PATH (FUSE). Non-Nix tooling that hard-codes
    # `#!/bin/bash` - notably the Coder Claude Code / AgentAPI install scripts -
    # otherwise fails instantly (NixOS has no /bin/bash), so Claude never starts
    # and the app shows "unresponsive". envfs makes /bin/bash and friends resolve.
    envfs.enable = true;

    cloud-init = {
      enable = true;
      network.enable = false; # KubeVirt masquerade + DHCP handles networking
      settings = {
        datasource_list = [ "NoCloud" ];
      };
    };

    # Access is via the Coder agent, not SSH.
    openssh.enable = lib.mkForce false;
  };

  systemd.services = {
    # Restart the serial console on exit so `kubectl virt console` keeps working.
    "serial-getty@ttyS0".serviceConfig.Restart = "always";

    # Set the guest hostname to the Coder workspace name (written to
    # /etc/coder/hostname by cloud-init). Runs before Teleport and the agent so
    # the Teleport node and the agent see the right name. networking.hostName is
    # forced empty and dhcpcd's hostname hook is disabled (see networking above),
    # so this is the single authority for the hostname.
    coder-set-hostname = {
      description = "Set the hostname to the Coder workspace name";
      wantedBy = [ "multi-user.target" ];
      after = [ "cloud-init.service" ];
      wants = [ "cloud-init.service" ];
      before = [
        "teleport.service"
        "coder-agent.service"
      ];
      unitConfig.ConditionPathExists = "/etc/coder/hostname";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "coder-set-hostname" ''
          name=$(${pkgs.coreutils}/bin/tr -d '[:space:]' < /etc/coder/hostname)
          [ -n "$name" ] || exit 0
          # --transient only: /etc/hostname is a read-only Nix store path, so the
          # static hostname can't be written. The transient hostname is what
          # gethostname()/Teleport read, which is all we need.
          ${pkgs.systemd}/bin/hostnamectl --transient set-hostname "$name"
        '';
      };
    };

    # Teleport registers as a node under the OS hostname, so it must start after
    # the hostname has been set to the workspace name (merges with the ordering
    # in modules/teleport-node).
    teleport = {
      after = [ "coder-set-hostname.service" ];
      wants = [ "coder-set-hostname.service" ];
    };

    # The Coder agent. cloud-init writes /etc/coder/agent.env (token, server URL,
    # etc.) on boot, then starts this unit (see cloud-init.yaml.tftpl). Runs the
    # baked-in `coder agent` as the coder user; the agent then drives the
    # coder_script resources (clone repo, Claude Code, etc.).
    coder-agent = {
      description = "Coder Agent";
      # Not wantedBy multi-user.target: started by cloud-init once the env file
      # has been written, avoiding a boot-time race.
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      unitConfig.ConditionPathExists = "/etc/coder/agent.env";
      serviceConfig = {
        Type = "simple";
        User = "coder";
        Group = "coder";
        WorkingDirectory = "/home/coder";
        EnvironmentFile = "/etc/coder/agent.env";
        # Make system tooling + the sudo wrapper available to the agent and the
        # scripts it spawns.
        # Includes the dirs the Coder modules install into - ~/.local/bin (Claude
        # Code) and /usr/local/bin (AgentAPI) - so the scripts that later invoke
        # `claude` / `agentapi` find them on PATH.
        Environment = [
          "HOME=/home/coder"
          "PATH=/run/wrappers/bin:/home/coder/.nix-profile/bin:/home/coder/.local/bin:/run/current-system/sw/bin:/usr/local/bin:/usr/bin:/bin"
        ];
        ExecStart = "${pkgs.coder}/bin/coder agent";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };
  };

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "25.05";
}
