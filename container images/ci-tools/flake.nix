{
  # The tools of the ci-tools image (Dockerfile), pinned by flake.lock: what
  # the shared CI's own steps run with. A project's stages run in the
  # project's own CI image, built from the project's flake.nix.
  description = "ci-tools: the shared Tekton CI of the agent projects";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      packages.${system}.default = pkgs.buildEnv {
        name = "ci-tools-env";
        paths = with pkgs; [
          bashInteractive
          coreutils
          findutils
          gnugrep
          gnused
          gawk
          util-linux
          procps
          diffutils
          openssl
          gitMinimal
          curl
          jq
          yq-go
          crane
          kubernetes-helm
          docker-client
          shellcheck
          cacert
          (python3.withPackages (ps: [ ps.pyyaml ]))
        ];
      };
    };
}
