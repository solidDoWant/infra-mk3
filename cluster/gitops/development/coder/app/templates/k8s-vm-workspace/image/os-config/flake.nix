{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    impermanence.url = "github:nix-community/impermanence";
  };
  outputs =
    {
      self,
      nixpkgs,
      nixos-generators,
      impermanence,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # Two image variants off one configuration: the base workspace, and the same
      # thing plus a headless Xfce desktop reachable over Teleport (./modules/desktop).
      #
      # Separate images rather than one image with a runtime switch, because the
      # desktop is not something that can be turned on at runtime: it is system
      # configuration (X, session files, the linux_desktop_service block in
      # Teleport's config file), all of which is baked into the closure. Keeping it
      # out of the base image also keeps the CDI import for non-desktop workspaces
      # small - the desktop closure is several GB, and every workspace imports the
      # whole root image on create and on every base-image bump.
      mkQcow2 =
        { desktop }:
        nixos-generators.nixosGenerate {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = [
            impermanence.nixosModules.impermanence
            ./configuration.nix
          ]
          ++ nixpkgs.lib.optional desktop ./modules/desktop;
          format = "kubevirt";
        };

      # The `dockerTools.buildImage` function considers the entire NixOS system
      # to be a runtime dependency of the qcow2, which bloats the resulting
      # image with a copy of the whole nix store. This builds a bare-bones OCI
      # image by hand, copying only the qcow2 into a single layer - the same
      # approach as the insurgency-server image build.
      mkContainer =
        qcow2:
        pkgs.runCommand "nixos-workspace-image.tar" { } ''
          # Create layer directory and copy the actual file
          mkdir -p layer/disk
          cp "${qcow2}"/*.qcow2 layer/disk/nixos-workspace.qcow2

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
            "RepoTags": ["nixos-workspace:latest"],
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
    in
    {
      packages.x86_64-linux = {
        kubevirt-qcow2 = mkQcow2 { desktop = false; };
        kubevirt-qcow2-desktop = mkQcow2 { desktop = true; };

        kubevirt-container = mkContainer self.packages.x86_64-linux.kubevirt-qcow2;
        kubevirt-container-desktop = mkContainer self.packages.x86_64-linux.kubevirt-qcow2-desktop;
      };
    };
}
