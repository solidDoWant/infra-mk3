{
  lib,
  config,
  pkgs,
  ...
}:
{
  imports = [
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

  # Mount the cluster root CA (virtiofs share from the root-ca-pub-cert secret)
  # and trust it system-wide.
  fileSystems."/mnt/root-ca" = {
    device = "root-ca";
    fsType = "virtiofs";
    options = [
      "ro"
      "nofail"
    ];
  };
  security.pki.certificateFiles = [ "/mnt/root-ca/ca.crt" ];

  networking = {
    hostName = lib.mkDefault "coder-workspace"; # overridden by cloud-init
    useDHCP = lib.mkForce true; # KubeVirt masquerade serves the guest via DHCP
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
  };

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
        Environment = [
          "HOME=/home/coder"
          "PATH=/run/wrappers/bin:/home/coder/.nix-profile/bin:/run/current-system/sw/bin:/usr/bin:/bin"
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
