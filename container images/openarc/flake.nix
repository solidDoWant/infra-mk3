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
            rev = "e3618c0719c59d05d904e315d453e403cf757e03";
            hash = "sha256-N932tjSjqxUfMeeRk7c6+gI6YXxA7et37Xfm7do/wZg=";
          };
          # Each entry is the .diff of an open upstream PR, fetched
          # straight from GitHub. When a PR is updated, the hash
          # changes — set `hash = lib.fakeHash;` to discover the new
          # value, then paste it back. Drop the entry once the PR
          # merges and the rev pin advances past it.
          patches = [
            # Fix wheel builds not containing any src/ files (uses
            # [tool.setuptools.packages.find] so subpackages are picked
            # up). Required — uv2nix builds the venv from a wheel.
            (pkgs.fetchpatch {
              name = "pr-113-wheel-build.patch";
              url = "https://github.com/SearchSavior/OpenArc/pull/113.diff";
              hash = "sha256-WG9qV43N6yWehSN5+DQATEbXAqG++4iN48g/Mcr0kaA=";
            })
            # Enable OpenVINO model caching: adds cache_dir +
            # runtime_config fields to ModelLoadConfig and threads
            # them through every engine's ov.Core.set_property call.
            (pkgs.fetchpatch {
              name = "pr-118-ov-caching.patch";
              url = "https://github.com/SearchSavior/OpenArc/pull/118.diff";
              hash = "sha256-wA720DAjkGOjvQt5Lzi+Mmwxf/iIU4ZaRDhZopTM86A=";
            })
            # Add Qwen3-ASR segments to verbose_json / diarized_json
            # responses; refactors transcribe() to return a tuple and
            # propagates segments through worker_registry.
            (pkgs.fetchpatch {
              name = "pr-130-qwen3-asr-segments.patch";
              url = "https://github.com/SearchSavior/OpenArc/pull/130.diff";
              hash = "sha256-S3NPr4E3E45nal7VkT32/Zn5tpQsnonUF+oKetS7Ah4=";
            })
            # Fix `openarc serve start` failing due to optimum/torch
            # version mismatch — full uv.lock regen with optimum 2.x
            # and optimum-onnx (the new split-out package).
            (pkgs.fetchpatch {
              name = "pr-120-uv-lock.patch";
              url = "https://github.com/SearchSavior/OpenArc/pull/120.diff";
              hash = "sha256-EG/05QepcIreBNQE9Gm5nkIFtdYfTzwuy7+v57ZP5X8=";
            })
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

        # gpu_metrics is an out-of-tree pybind11 extension shipped at
        # gpu-metrics/ in the OpenArc repo, but the root pyproject.toml
        # doesn't reference it (no workspace member, no path source), so
        # uv2nix never sees it. Build it as its own derivation here and
        # hand it to the image via PYTHONPATH. setup.py hardcodes
        # /usr/include for the Level Zero headers, which doesn't exist
        # in the Nix builder — substitute to pkgs.level-zero's prefix.
        gpuMetrics = python.pkgs.buildPythonPackage {
          pname = "gpu-metrics";
          version = "0.1.0";
          pyproject = true;
          src = "${openarcSrc}/gpu-metrics";
          build-system = with python.pkgs; [ setuptools pybind11 ];
          buildInputs = [ pkgs.level-zero ];
          postPatch = ''
            substituteInPlace setup.py \
              --replace-fail '"/usr/include"' '"${lib.getDev pkgs.level-zero}/include"'
          '';
          doCheck = false;
        };

        scripts = pkgs.runCommand "openarc-scripts" { } ''
          install -Dm755 ${./register-model.sh} $out/bin/register-model
          install -Dm755 ${./warm-cache.sh}     $out/bin/warm-cache
          install -Dm755 ${./start-openarc.sh}  $out/bin/start-openarc
          # The kernel resolves shebangs without consulting container PATH,
          # so `#!/usr/bin/env python3` can't find the venv interpreter at
          # exec time. Rewrite to the absolute venv path at build time so
          # the script is directly executable via `command:` in the pod
          # spec (kubelet exec()s the file rather than running it through
          # a shell).
          substitute ${./check-models-loaded.py} $out/bin/check-models-loaded \
            --replace-fail '#!/usr/bin/env python3' '#!${venv}/bin/python3'
          chmod +x $out/bin/check-models-loaded
        '';

        # OpenVINO's GPU plugin dlopens libze_loader / libze_intel_gpu at
        # runtime instead of RPATHing them, so they have to be on
        # LD_LIBRARY_PATH below. Same story for soundfile → libsndfile.so,
        # which optimum-intel pulls in transitively.
        gpuRuntime = [
          pkgs.intel-compute-runtime
          # Level Zero GPU backend driver (libze_intel_gpu.so.1) — lives
          # in the `drivers` output, not the default `out`. Required by
          # the gpu_metrics module so libze_loader.so can discover the
          # Intel L0 driver at zeInit time. The loader searches
          # LD_LIBRARY_PATH for libze_*.so.1 files.
          pkgs.intel-compute-runtime.drivers
          pkgs.level-zero
          pkgs.libsndfile.out
        ];
      in {
        packages.openarc-image = pkgs.dockerTools.streamLayeredImage {
          name = "openarc";
          tag = "latest";
          contents = [
            venv
            gpuMetrics
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
              # uv2nix venv's python only walks its own site-packages.
              # gpu_metrics lives in a separate derivation, so make it
              # discoverable by appending its site-packages to PYTHONPATH.
              "PYTHONPATH=${gpuMetrics}/${python.sitePackages}"
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
