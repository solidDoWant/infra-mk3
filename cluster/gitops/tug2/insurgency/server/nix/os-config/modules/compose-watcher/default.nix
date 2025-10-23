{ pkgs }:
let
  # Docker compose watcher script - single reusable derivation
  script = pkgs.writeShellApplication {
    name = "docker-compose-watcher";
    runtimeInputs = with pkgs; [
      docker-compose
      inotify-tools
      coreutils
    ];
    text = builtins.readFile ./docker-compose-watcher.sh;
  };

  # Function to create a systemd unit for a specific compose file
  systemdUnit =
    {
      composeFilePath,
      description ? "Docker Compose File Watcher for ${composeFilePath}",
      extraServiceConfig ? { },
    }:
    let
      serviceConfigDefaults = {
        Type = "exec";
        Restart = "always";
        RestartSec = "10s";
        WorkingDirectory = builtins.dirOf composeFilePath;
        ExecStart = "${script}/bin/docker-compose-watcher ${composeFilePath}";
      };
    in
    {
      inherit description;
      wantedBy = [ "multi-user.target" ];
      after = [ "docker.service" ];
      wants = [ "docker.service" ];
      serviceConfig = serviceConfigDefaults // extraServiceConfig;
    };
in
{
  inherit script systemdUnit;
}
