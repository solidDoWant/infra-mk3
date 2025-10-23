{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs =
    {
      self,
      nixpkgs,
      nixos-generators,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      packages.x86_64-linux = {
        kubevirt-qcow2 = nixos-generators.nixosGenerate {
          inherit system;
          modules = [
            ./configuration.nix
          ];
          format = "kubevirt";
        };

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
          cp "${self.packages.x86_64-linux.kubevirt-qcow2}"/*.qcow2 layer/disk/insurgency-server.qcow2

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
