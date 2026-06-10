{
  inputs,
  lib,
  config,
  pkgs,
  ...
}:
let
  # Import the teleport package with BPF support
  teleportPkgs = import ./modules/teleport { inherit pkgs; };

  # Import the compose watcher derivation
  composeWatcher = import ./modules/compose-watcher { inherit pkgs; };

  dockerCredentialsDir = "/mnt/docker-pull-credentials";
in
{
  nixpkgs = {
    hostPlatform = "x86_64-linux";
    config = {
      allowUnfree = true;
    };
  };

  nix = {
    settings = {
      # Enable flakes and new 'nix' command
      experimental-features = "nix-command flakes";
    };
  };

  # Lets the unprivileged kube-sa-bindfs service use the allow_other mount option
  # so root (teleport) can read the bindfs overlay it mounts as uid 107.
  programs.fuse.userAllowOther = true;

  fileSystems = {
    # Stage the raw Kubernetes service account virtiofs share here. virtiofsd runs
    # unprivileged as the host qemu uid (107) and only serves a guest reader whose
    # uid is also 107, so even root in the guest is denied. The canonical path that
    # teleport reads is instead provided by the kube-sa-bindfs overlay (which runs
    # as uid 107) from this staging mount.
    "/run/kubesaraw" = {
      device = "serviceaccount";
      fsType = "virtiofs";
      options = [
        "ro"
        "nofail"
      ];
    };

    # Mount the root CA into the VM
    "/mnt/root-ca" = {
      device = "root-ca";
      fsType = "virtiofs";
      options = [
        "ro"
        "nofail"
      ];
    };

    # Mount the docker pull credentials into the VM
    "${dockerCredentialsDir}" = {
      device = "docker-pull-credentials";
      fsType = "virtiofs";
      options = [
        "ro"
        "nofail"
      ];
    };

    # Mount the docker compose configuration into the VM
    "/mnt/docker-compose" = {
      device = "docker-compose";
      fsType = "virtiofs";
      options = [
        "ro"
        "nofail"
      ];
    };

    # Mount the Postgres TLS secrets into the VM
    "/mnt/postgres" = {
      device = "insurgency-postgres-insurgency-user";
      fsType = "virtiofs";
      options = [
        "ro"
        "nofail"
      ];
    };

    # Mount the Discord webhook secret into the VM
    "/mnt/discord-webhook" = {
      device = "discord-webhook";
      fsType = "virtiofs";
      options = [
        "ro"
        "nofail"
      ];
    };
  };

  environment = {
    systemPackages = [
      pkgs.inetutils # Needed for telnet for server access
      pkgs.htop # Useful for quick view of system resources
      pkgs.iotop-c
      pkgs.docker # Container management
      pkgs.docker-compose # Docker compose for container orchestration
      teleportPkgs.withBPF # Remote access
    ];

    variables = {
      # Point Docker to the pull credentials
      DOCKER_CONFIG = dockerCredentialsDir;
    };

    etc = {
      # Copy all configuration files to /etc/nixos/ in the image
      "nixos".source = ./.;

      # Add the root CA to the system trusted certificates directories
      "ssl/certs/root-ca.crt".source = "/mnt/root-ca/ca.crt";
      "pki/tls/certs/root-ca.crt".source = "/mnt/root-ca/ca.crt";
    };
  };

  # cspell:words virtualisation
  virtualisation = {
    docker = {
      autoPrune = {
        enable = true;
        dates = "daily";
      };
      daemon.settings = {
        live-restore = true;
        # Enable user namespaces for container isolation
        userns-remap = "default";
      };
      enable = true;
      enableOnBoot = true;
      rootless = {
        enable = true;
        setSocketVariable = true;
        daemon.settings = {
          userland-proxy = false;
          # metrics-addr = "0.0.0.0:9323";
        };
      };
      storageDriver = "overlay2";
    };
  };

  # This will be overridden by cloud-init on boot
  networking.hostName = "insurgency-server";

  users = {
    users = {
      admin = {
        # Start with no password login. This will be set via cloud-init upon startup.
        hashedPassword = "";
        isNormalUser = true;

        extraGroups = [
          "wheel"
          "docker"
        ];
      };

      compose-watcher = {
        isSystemUser = true;
        group = "compose-watcher";
        extraGroups = [ "docker" ];
        description = "Docker Compose Watcher Service User";
      };

      # Docker user namespace remapping user
      dockremap = {
        isSystemUser = true;
        group = "dockremap";
        description = "Docker user namespace remapping";
        # Docker needs a wide range of subordinate UIDs/GIDs
        subUidRanges = [
          {
            startUid = 100000;
            count = 65536;
          }
        ];
        subGidRanges = [
          {
            startGid = 100000;
            count = 65536;
          }
        ];
      };

      # Runs the kube-sa-bindfs overlay. The uid MUST be 107 —
      # virtiofsd runs unprivileged as the host qemu uid (107) and only serves a
      # guest reader whose uid matches, so this is the only uid that can read the
      # token. 107 is unassigned in nixpkgs' static id list.
      virtiofs = {
        uid = 107;
        group = "virtiofs";
        isSystemUser = true;
        description = "virtiofs SA share reader (matches host qemu uid 107)";
      };
    };

    groups = {
      compose-watcher = { };
      dockremap = { };
      virtiofs.gid = 107;
    };
  };

  services = {
    cloud-init = {
      enable = true;
      settings = {
        datasource_list = [ "NoCloud" ];
      };
    };

    # Not needed, Teleport is used for access
    openssh.enable = lib.mkForce false;

    teleport = {
      package = teleportPkgs.withBPF;
      enable = true;

      # This follows the teleport config file structure
      settings = {
        version = "v3";
        teleport = {
          proxy_server = "teleport-cluster.security.svc.cluster.local:443";
          join_params = {
            method = "kubernetes";
            token_name = "insurgency-server";
          };
        };
        auth_service.enabled = false;
        proxy_service.enabled = false;
        ssh_service = {
          enabled = true;
          labels = {
            type = "vm";
            purpose = "insurgency-server";
          };
          enhanced_recording = {
            enabled = true;
          };
        };
      };
    };
  };

  systemd.services = {
    "serial-getty@ttyS0" = {
      # Restart the serial console on ttyS0 on failure or when it exits
      serviceConfig = {
        Restart = "always";
      };
    };

    docker-compose-watcher = composeWatcher.systemdUnit {
      composeFilePath = "/mnt/docker-compose/docker-compose.yaml";
      extraServiceConfig = {
        User = "compose-watcher";
        Environment = [ "DOCKER_CONFIG=${dockerCredentialsDir}" ];
      };
    };

    # virtiofsd serves the SA share (/run/kubesaraw) only to uid 107 (it runs
    # unprivileged as the host qemu uid and cannot assume another uid), so teleport
    # — which runs as root — is denied reading it directly. bindfs runs as uid 107
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

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "25.05";
}
