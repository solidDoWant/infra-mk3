{
  description = "OpenArc container image for Qwen3-ASR on Intel Arc GPU";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, pyproject-nix, uv2nix, pyproject-build-systems }:
    flake-utils.lib.eachSystem [ "x86_64-linux" ] (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        lib = pkgs.lib;

        openarcSrc = pkgs.applyPatches {
          src = pkgs.fetchFromGitHub {
            owner = "SearchSavior";
            repo = "OpenArc";
            rev = "v2.0.4";
            hash = "sha256-9TNWbOePpIAmZIYe7OlnDJwVI4GNPi9KROpHEH0uLY8=";
          };
          # Adds OPENARC_CONFIG_FILE env override and resolves relative
          # model_path values against the config file's directory, so a
          # single image volume containing both the config and the model
          # files can be mounted at any path in the pod.
          patches = [ ./openarc-config-path.patch ];
        };

        python = pkgs.python312;

        workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = openarcSrc; };
        pyprojectOverlay = workspace.mkPyprojectOverlay { sourcePreference = "wheel"; };

        pythonSet = (pkgs.callPackage pyproject-nix.build.packages { inherit python; }).overrideScope (
          lib.composeManyExtensions [
            pyproject-build-systems.overlays.default
            pyprojectOverlay
            (final: prev: {
              # OpenArc reads/writes its config at
              # Path(__file__).parent.parent.parent.parent / "openarc_config.json",
              # which resolves to <venv>/site-packages — read-only here. Symlink
              # that path to the /app/config PVC mount instead of patching source.
              openarc = prev.openarc.overrideAttrs (old: {
                postInstall = (old.postInstall or "") + ''
                  ln -s /app/config/openarc_config.json \
                    $out/${python.sitePackages}/openarc_config.json
                '';
              });

              # libopenvino_intel_gpu_plugin.so in the openvino wheel needs
              # libOpenCL.so.1, which comes from ocl-icd.
              openvino = prev.openvino.overrideAttrs (old: {
                buildInputs = (old.buildInputs or [ ]) ++ [ pkgs.ocl-icd ];
              });
            })
            # These wheels link to libopenvino.so.2530 (bundled in the openvino
            # wheel under .../site-packages/openvino/libs) and libtbb.so.12.
            # appendRunpaths bakes the right RPATH for runtime; auto-patchelf's
            # build-time scan can't see into nested site-packages dirs, so the
            # symbol it'll never find at check time is in the ignore list.
            (final: prev: lib.genAttrs [
              "openvino-genai"
              "openvino-tokenizers"
            ] (name: prev.${name}.overrideAttrs (old: {
              buildInputs = (old.buildInputs or [ ]) ++ [ pkgs.tbb ];
              appendRunpaths = (old.appendRunpaths or [ ]) ++ [
                "${final.openvino}/lib/python3.12/site-packages/openvino/libs"
              ];
              autoPatchelfIgnoreMissingDeps = (old.autoPatchelfIgnoreMissingDeps or [ ]) ++ [
                "libopenvino.so.2530"
              ];
            })))
            # Same shape, but for wheels linking into torch's bundled libs.
            (final: prev: lib.genAttrs [
              "torchvision"
            ] (name: prev.${name}.overrideAttrs (old: {
              appendRunpaths = (old.appendRunpaths or [ ]) ++ [
                "${final.torch}/lib/python3.12/site-packages/torch/lib"
              ];
              autoPatchelfIgnoreMissingDeps = (old.autoPatchelfIgnoreMissingDeps or [ ]) ++ [
                "libc10.so"
                "libtorch.so"
                "libtorch_cpu.so"
                "libtorch_python.so"
              ];
            })))
            # Older sdists predate PEP 518 and don't declare setuptools in
            # build-system.requires; uv2nix builds without isolation and can't
            # auto-resolve the missing build dep.
            (final: prev: lib.genAttrs [
              "docopt"
              "grapheme"
            ] (name: prev.${name}.overrideAttrs (old: {
              nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.setuptools ];
            })))
          ]
        );

        # Several deps each ship a top-level LICENSE / README; the venv builder
        # would otherwise refuse the merge. Keep the first-seen copy.
        venv = (pythonSet.mkVirtualEnv "openarc-env" workspace.deps.default).overrideAttrs (old: {
          mkVirtualenvFlags = lib.concatStringsSep " " (map (p: "--ignore-collisions ${p}") [
            "LICENSE"
            "LICENSE.txt"
            "LICENSE.md"
            "LICENSE.rst"
            "NOTICE"
            "NOTICE.txt"
            "AUTHORS"
            "AUTHORS.rst"
            "README"
            "README.md"
            "README.rst"
            "COPYING"
          ]);
        });

        scripts = pkgs.runCommand "openarc-scripts" { } ''
          install -Dm755 ${./setup-model.sh}   $out/bin/setup-model
          install -Dm755 ${./start-openarc.sh} $out/bin/start-openarc
        '';

        # OpenVINO's GPU plugin dlopens libze_loader / libze_intel_gpu at
        # runtime instead of RPATHing them, so they have to be on
        # LD_LIBRARY_PATH below. Same story for soundfile → libsndfile.so,
        # which optimum-intel pulls in transitively.
        gpuRuntime = [
          pkgs.intel-compute-runtime
          pkgs.level-zero
          pkgs.libsndfile.out
        ];
      in {
        packages.openarc-image = pkgs.dockerTools.streamLayeredImage {
          name = "openarc";
          tag = "latest";
          contents = [
            venv
            scripts
            pkgs.cacert
            pkgs.bashInteractive
            pkgs.coreutils
            pkgs.curl
          ] ++ gpuRuntime;
          config = {
            Entrypoint = [ "/bin/start-openarc" ];
            User = "1000:1000";
            WorkingDir = "/app";
            ExposedPorts = { "8000/tcp" = { }; };
            Env = [
              "PATH=${venv}/bin:${pkgs.curl}/bin:${pkgs.coreutils}/bin:/bin:/usr/bin"
              "LD_LIBRARY_PATH=${lib.makeLibraryPath gpuRuntime}"
            ];
          };
        };

        packages.default = self.packages.${system}.openarc-image;
      });
}
