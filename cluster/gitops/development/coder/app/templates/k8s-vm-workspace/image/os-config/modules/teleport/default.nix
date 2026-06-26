{ pkgs, ... }:
let
  # Build BPF bytecode separately
  bpfBytecode = pkgs.stdenv.mkDerivation {
    name = "teleport-bpf-bytecode-${pkgs.teleport_18.version}";
    src = pkgs.teleport_18.src;

    nativeBuildInputs = [
      pkgs.llvmPackages.clang-unwrapped
      pkgs.llvmPackages.bintools-unwrapped
    ];

    buildInputs = [
      pkgs.libbpf
      pkgs.elfutils
      pkgs.zlib
      pkgs.linuxHeaders
    ];

    buildPhase = ''
      # Compile BPF bytecode
      mkdir -p lib/bpf/bytecode

      KERNEL_ARCH=$(uname -m | sed 's/x86_64/x86/g; s/aarch64/arm64/g')

      pushd bpf/enhancedrecording
      for src in *.bpf.c; do
        clang -g -O2 -target bpf \
          -D__TARGET_ARCH_$KERNEL_ARCH \
          -I${pkgs.libbpf}/include \
          -I${pkgs.linuxHeaders}/include \
          -c "$src" -o "../../lib/bpf/bytecode/$(basename "$src" .c).o"
        llvm-strip -g "../../lib/bpf/bytecode/$(basename "$src" .c).o"
      done
      popd
    '';

    installPhase = ''
      mkdir -p $out
      cp -r lib/bpf/bytecode $out/
    '';
  };
in
{
  withBPF =
    (pkgs.teleport_18.override {
    }).overrideAttrs
      (oldAttrs: {
        tags = oldAttrs.tags ++ [ "bpf" ];

        buildInputs = oldAttrs.buildInputs ++ [
          pkgs.libbpf
          pkgs.elfutils
          pkgs.zlib
        ];

        # Copy BPF bytecode before building
        preBuild = oldAttrs.preBuild + ''
          mkdir -p lib/bpf/bytecode
          cp -r ${bpfBytecode}/bytecode/* lib/bpf/bytecode/
        '';

        CGO_CFLAGS = "-I${pkgs.libbpf}/include";
        CGO_LDFLAGS = "-L${pkgs.libbpf}/lib64 -lbpf -lelf -lz";
      });
}
