{ pkgs, ... }:
# Teleport for the workspace VM: the official release binaries, patched to run
# on NixOS.
#
# Not nixpkgs' source build, for two reasons:
#
#   1. Upstream stopped publishing source tags after v18.11.1 (later 18.11.x
#      tags and their GitHub archive tarballs return 404), so a source build
#      can't follow the cluster's version. The cluster runs 18.11.8.
#   2. The Linux desktop service (../desktop) needs Teleport >= 18.11.0, which
#      nixpkgs doesn't have, and building 18.11 from nixpkgs' builder needed a
#      vendored copy of it with several fixes.
#
# The official binaries are built with the `bpf` tag, so enhanced session
# recording (ssh_service.enhanced_recording in ../teleport-node) works without
# compiling the BPF bytecode here.
#
# nixpkgs also patches the PATH that Teleport gives sessions to include the
# NixOS profile directories. The official binary takes it from ENV_PATH and
# ENV_SUPATH in /etc/login.defs instead, set in ../teleport-node.
#
# UPGRADING: Renovate bumps `version` but can't update `hash`. Take the new
# hash from `nix store prefetch-file
# https://cdn.teleport.dev/teleport-v<version>-linux-amd64-bin.tar.gz` (it must
# match the sha256 published next to the tarball, at the same URL plus
# `.sha256`).
let
  # renovate: datasource=docker depName=public.ecr.aws/gravitational/teleport-distroless
  version = "18.11.8";
  hash = "sha256-5WV7hlTpfynvW2hEPqeGhoC/tD9iajnUISHxICirOp8=";
in
{
  package = pkgs.stdenv.mkDerivation {
    pname = "teleport";
    inherit version;

    src = pkgs.fetchurl {
      url = "https://cdn.teleport.dev/teleport-v${version}-linux-amd64-bin.tar.gz";
      inherit hash;
    };

    nativeBuildInputs = [ pkgs.autoPatchelfHook ];
    # The binaries link only glibc and libgcc_s.
    buildInputs = [ pkgs.stdenv.cc.cc.lib ];

    dontConfigure = true;
    dontBuild = true;
    # Go binaries: stripping can break them, and they carry no debug sections
    # worth removing.
    dontStrip = true;

    installPhase = ''
      runHook preInstall
      for bin in teleport tctl tsh tbot fdpass-teleport; do
        install -Dm755 "$bin" "$out/bin/$bin"
      done
      runHook postInstall
    '';

    doInstallCheck = true;
    installCheckPhase = ''
      $out/bin/teleport version | grep -F "v${version} "
    '';

    meta = {
      description = "Teleport (official release binaries)";
      homepage = "https://goteleport.com/";
      platforms = [ "x86_64-linux" ];
      mainProgram = "teleport";
    };
  };
}
