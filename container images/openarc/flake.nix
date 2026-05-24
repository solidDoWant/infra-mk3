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
            rev = "8856d1d9c2b8a04c1a03143ed0c633a9ebf40987";
            hash = "sha256-TiP+xSlkjvTmIACaDbAyA8rHwuS/yxpkZZFQy75dZQY=";
          };
          patches = [
            # Adds OPENARC_CONFIG_FILE env override and resolves relative
            # model_path values against the config file's directory, so a
            # single image volume containing both the config and the model
            # files can be mounted at any path in the pod.
            ./openarc-config-path.patch
            # Bumps optimum 1.27.0 -> 2.0.0 and adds optimum-onnx (the new
            # split-out package). Upstream bumped torch to 2.11 but kept
            # optimum 1.x in uv.lock, whose bundled onnx exporter imports
            # torch.onnx.symbolic_opset14._attention_scale — a private
            # symbol removed in torch 2.9+. optimum-onnx 0.0.3 guards that
            # import on torch version; optimum-intel 1.26.x targets the
            # split package. Drop this once upstream relocks.
            ./optimum-2x.patch
            # Runs the per-chunk Qwen3 ASR work (mel + encoder + decode)
            # on a thread executor instead of inline on the event loop.
            # Upstream declared audio_chunks() as `async def` but the body
            # is pure CPU-bound OpenVINO calls with no awaits, so each
            # chunk blocked the loop for its full runtime — concurrent
            # transcribe requests serialized end-to-end and the health
            # probes timed out mid-job. Drop once upstream fixes it.
            ./openarc-asr-thread-offload.patch
            # Adds SRT/VTT support to POST /v1/audio/transcriptions
            # (qwen3_asr only). Upstream's else-branch returns the
            # transcript as a JSON-quoted string for any non-json
            # response_format — bazarr's whisper provider (via the
            # bazarr-openai-whisperbridge sidecar) requests output=srt
            # and rejects the body as "not valid for this file" because
            # there are no cues. The patch surfaces per-chunk timings
            # from the qwen3_asr worker as metrics["segments"] and adds
            # srt/vtt/text branches that emit PlainTextResponse.
            ./openarc-srt-output.patch
          ];
        };

        python = pkgs.python312;

        workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = openarcSrc; };
        pyprojectOverlay = workspace.mkPyprojectOverlay { sourcePreference = "wheel"; };

        pythonSet = (pkgs.callPackage pyproject-nix.build.packages { inherit python; }).overrideScope (
          lib.composeManyExtensions [
            pyproject-build-systems.overlays.default
            pyprojectOverlay
            (final: prev: {
              # openarc_config.json is hardcoded under <venv>/site-packages
              # (read-only here). Symlink to /app/config; superseded by
              # OPENARC_CONFIG_FILE for the server path but kept for CLI
              # commands that still call ServerConfig() with no override.
              # The hardcoded log path is handled by openarc-config-path.patch
              # which makes it OPENARC_LOG_FILE-overridable.
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
          install -Dm755 ${./setup-cache.sh}   $out/bin/setup-cache
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
          # Workarounds for containerd 2.2's path-escape check, which
          # rejects /nix/store-targeted absolute symlinks during the
          # user-file lookup that runs before container start.
          # https://github.com/containerd/containerd/pull/13383
          extraCommands = ''
            # 1. Replace the /etc absolute symlink (streamLayeredImage's
            # single-input-per-/etc shortcut) with a real dir holding
            # stub nss files. /etc/{OpenCL,ssl} we'd lose are routed
            # via env vars below.
            rm -f etc
            mkdir etc
            printf 'root:x:0:0:root:/root:/sbin/nologin\nopenarc:x:1000:1000:openarc:/app:/sbin/nologin\nnobody:x:65534:65534:nobody:/var/empty:/sbin/nologin\n' > etc/passwd
            printf 'root:x:0:\nopenarc:x:1000:\nnobody:x:65534:\n' > etc/group

            # 2. Rewrite every remaining absolute symlink (mostly /bin/*,
            # /lib/*, /sbin/*, /share/* targeting /nix/store/...) to a
            # relative path. The targets are present in the image at
            # /nix/store/..., so relative paths resolve correctly without
            # any component looking absolute to containerd's check.
            find . -type l | while IFS= read -r link; do
              tgt=$(readlink "$link")
              case "$tgt" in
                /*)
                  img_dir="/$(dirname "''${link#./}")"
                  rel=$(realpath -m --relative-to="$img_dir" "$tgt")
                  rm "$link"
                  ln -s "$rel" "$link"
                  ;;
              esac
            done
          '';
          config = {
            Entrypoint = [ "/bin/start-openarc" ];
            User = "1000:1000";
            WorkingDir = "/app";
            ExposedPorts = { "8000/tcp" = { }; };
            Env = [
              "PATH=${venv}/bin:${pkgs.curl}/bin:${pkgs.coreutils}/bin:/bin:/usr/bin"
              "LD_LIBRARY_PATH=${lib.makeLibraryPath gpuRuntime}"
              # Bypass /etc lookup — extraCommands above replaced /etc
              # with a stub real dir, so these would otherwise be missing.
              "OCL_ICD_VENDORS=${pkgs.intel-compute-runtime}/etc/OpenCL/vendors"
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            ];
          };
        };

        packages.default = self.packages.${system}.openarc-image;
      });
}
