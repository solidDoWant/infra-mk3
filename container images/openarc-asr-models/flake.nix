{
  description = "OpenArc ASR model image volumes (HF weights + openarc_config.json)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachSystem [ "x86_64-linux" ] (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        lib = pkgs.lib;

        # openarc resolves model_path as an absolute string, so the in-pod
        # image-volume mount path is baked into the configs. Keeping it
        # constant across images lets a single HelmRelease consume any of
        # them by swapping only the image tag.
        mountRoot = "/model";

        # FOD: snapshot-downloads `hfRepo` to <type>/<repo>/. First build
        # against lib.fakeHash fails with the real hash printed; substitute
        # it once the upload is stable on HF (the OpenVINO/ org repos are
        # static, the Echo9Zulu Qwen3-ASR README warns it may rev).
        mkAsrModel = { modelType, hfRepo, hfHash }: pkgs.stdenvNoCC.mkDerivation {
          pname = "openarc-asr-${lib.replaceStrings [ "/" ] [ "--" ] hfRepo}";
          version = "0";
          dontUnpack = true;
          dontInstall = true;
          nativeBuildInputs = [
            pkgs.python312Packages.huggingface-hub
            pkgs.cacert
          ];

          buildPhase = ''
            export HOME=$TMPDIR
            export HF_HOME=$TMPDIR/hf-home
            export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt

            mkdir -p "$out/${modelType}/${hfRepo}"
            hf download "${hfRepo}" \
              --local-dir "$out/${modelType}/${hfRepo}"
            # `hf download` leaves a .cache/ with refs back into HF_HOME
            # (gone after the build); strip it so the tree is self-contained.
            rm -rf "$out/${modelType}/${hfRepo}/.cache"
          '';

          outputHashAlgo = "sha256";
          outputHashMode = "recursive";
          outputHash = hfHash;
        };

        # Single-model openarc_config.json. Schema matches what
        # `openarc add` writes (see src/cli/groups/add.py in OpenArc).
        mkAsrConfig = { modelName, modelType, engine, device, hfRepo }:
          pkgs.writeText "openarc_config.json" (builtins.toJSON {
            models.${modelName} = {
              model_name = modelName;
              model_path = "${mountRoot}/${modelType}/${hfRepo}";
              model_type = modelType;
              engine = engine;
              device = device;
              runtime_config = { };
              vlm_type = null;
            };
          });

        mkAsrImage = { tag, modelName, modelType, engine, device, hfRepo, hfHash }:
          let
            model = mkAsrModel { inherit modelType hfRepo hfHash; };
            config = mkAsrConfig { inherit modelName modelType engine device hfRepo; };
          in pkgs.dockerTools.streamLayeredImage {
            name = "openarc-asr";
            inherit tag;
            # Materialize real files at /model — k8s image volumes mount only
            # /model into the consumer pod, so the default dockerTools layout
            # (which symlinks /model entries into /nix/store/... paths inside
            # the image) would expose dangling symlinks in the mounted volume.
            extraCommands = ''
              mkdir -p model
              cp -rL --no-preserve=mode ${model}/. model/
              install -m 0644 ${config} model/openarc_config.json
            '';
          };

        # All ASR models in OpenArc v2.0.4 docs/models.md. Engine + model_type
        # values come from the registry in src/server/model_registry.py
        # (EngineType/ModelType enums). Device is fixed to GPU — the only
        # consumer is the Arc Pro A40 in the bazarr namespace.
        models = {
          whisper-large-v3-int8 = {
            modelType = "whisper";
            engine = "ovgenai";
            hfRepo = "OpenVINO/whisper-large-v3-int8-ov";
            hfHash = "sha256-6BvZECaYswsc/2QRQ+YQoqjvEjz4SRajINVFo6SCUuE=";
          };
          # OpenArc docs list `OpenVINO/openai-whisper-large-v3-fp16-ov` but
          # that repo doesn't exist on HF; using the actual fp16 counterpart
          # of whisper-large-v3-int8-ov instead.
          whisper-large-v3-fp16 = {
            modelType = "whisper";
            engine = "ovgenai";
            hfRepo = "OpenVINO/whisper-large-v3-fp16-ov";
            hfHash = "sha256-iLInuiVokfKkf+O1BKUikQ1MLTgdwpSCKbe36oJUvLE=";
          };
          distil-whisper-large-v3-int8 = {
            modelType = "whisper";
            engine = "ovgenai";
            hfRepo = "OpenVINO/distil-whisper-large-v3-int8-ov";
            hfHash = "sha256-YxUKsWJLLFGHM1lPX3MDUrq60RpmFqBKDLeIpQGs+Hw=";
          };
          distil-whisper-large-v3-fp16 = {
            modelType = "whisper";
            engine = "ovgenai";
            hfRepo = "OpenVINO/distil-whisper-large-v3-fp16-ov";
            hfHash = "sha256-xzbyKYbJj0JYGKCNxZ4bEEUz1DMkmemvg9pqNlqmrR8=";
          };
          qwen3-asr-0_6b-int8-asym = {
            modelType = "qwen3_asr";
            engine = "openvino";
            hfRepo = "Echo9Zulu/Qwen3-ASR-0.6B-INT8_ASYM-OpenVINO";
            hfHash = "sha256-hK5ycGnY9zb9P0qGQPtXx5SjilyIRuDjPVKtouZ1x9s=";
          };
        };

        # Reuse the attr key as both image tag and openarc model_name so
        # the HelmRelease's OPENARC_AUTOLOAD_MODEL = image tag.
        toImage = name: m: mkAsrImage (m // {
          tag = name;
          modelName = name;
          device = "GPU";
        });
      in {
        packages = lib.mapAttrs' (name: m:
          lib.nameValuePair "image-${name}" (toImage name m)
        ) models;
      });
}
