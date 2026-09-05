{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };
  outputs =
    {
      nixpkgs,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # The KubeVirt image format lives in nixpkgs itself (it was upstreamed as
      # of NixOS 25.05, which is what nix-community/nixos-generators wrapped and
      # is now deprecated in favor of). The module defines the
      # `system.build.kubevirtImage` output and the `image.*` options naming the
      # qcow2 it writes into that output directory.
      nixosSystem = nixpkgs.lib.nixosSystem {
        modules = [
          (
            { modulesPath, ... }:
            {
              imports = [ "${modulesPath}/virtualisation/kubevirt.nix" ];
            }
          )
          ./configuration.nix
        ];
      };
    in
    {
      packages.${system} = {
        kubevirt-qcow2 = nixosSystem.config.system.build.kubevirtImage;

        # This is really really stupid, but the `dockerTools.buildImage` function
        # does not have a way to break the linkage between a build output and it's
        # "dependencies". The built qcow2 image considers the entire NixOS system
        # as part of it's runtime dependencies, which makes the resulting docker
        # image unacceptably large, filled with a massive and unnecessary nix store.
        # This approach builds a bare-bones docker image manually, copying only the
        # qcow2 file into the image layer.
        kubevirt-container = pkgs.runCommand "insurgency-server-image.tar" { } ''
          # Create layer directory and copy the actual file
          mkdir -p layer/disk
          cp "${nixosSystem.config.system.build.kubevirtImage}/${nixosSystem.config.image.filePath}" layer/disk/insurgency-server.qcow2

          # Create layer tarball
          tar -C layer -cf layer.tar .

          # Calculate layer digest
          LAYER_DIGEST=$(sha256sum layer.tar | cut -d' ' -f1)

          # Create config.json
          cat > config.json <<EOF
          {
            "architecture": "amd64",
            "config": {},
            "rootfs": {
              "type": "layers",
              "diff_ids": ["sha256:$LAYER_DIGEST"]
            }
          }
          EOF

          CONFIG_DIGEST=$(sha256sum config.json | cut -d' ' -f1)

          # Create manifest.json
          cat > manifest.json <<EOF
          [{
            "Config": "$CONFIG_DIGEST.json",
            "RepoTags": ["insurgency-server-os:latest"],
            "Layers": ["$LAYER_DIGEST/layer.tar"]
          }]
          EOF

          # Assemble Docker image structure
          mkdir -p image/$LAYER_DIGEST
          mv layer.tar image/$LAYER_DIGEST/
          mv config.json image/$CONFIG_DIGEST.json
          mv manifest.json image/

          # Create final tarball, removing the ./ prefix
          tar -C image --transform='s/^\.\///' -cf $out .
        '';
      };
    };
}
