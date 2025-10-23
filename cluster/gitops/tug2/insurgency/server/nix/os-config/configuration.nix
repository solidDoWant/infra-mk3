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

  fileSystems = {
    # Mount the Kubernetes service account into the VM
    "/var/run/secrets/kubernetes.io/serviceaccount" = {
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

    # Mount the docker compose configuration into the VM
    "/mnt/docker-compose" = {
      device = "docker-compose";
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
    };

    groups = {
      compose-watcher = { };
      dockremap = { };
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
      };
    };
  };

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "25.05";
}
