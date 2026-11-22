# The ci-tools image: the shared Tekton CI's own steps (bin/) and their tools
# (flake.nix). The shared Pipelines in ci-tekton run it, pinned by digest, on
# each run's dind: it clones nothing and builds nothing of its own; it builds
# the project's CI image from the project's flake.nix and runs the project's
# stages (ci.yaml) in it.
FROM ghcr.io/nixos/nix:2.36.0@sha256:746280551ddc1c72177d1a597c05eacac86dfaa18d5d649bf86411278bcd5470
ENV NIX_CONFIG="experimental-features = nix-command flakes"
COPY flake.nix flake.lock /build/
# The flake refuses a path source, so it goes into a throwaway git repository.
RUN cd /build && git init -q && git add -A && git -c user.email=ci@ci -c user.name=ci commit -qm tools \
 && nix profile add --profile /nix/var/nix/profiles/ci-tools 'git+file:///build' \
 && rm -rf /build && nix-collect-garbage >/dev/null
ENV PATH=/ci-tools/bin:/nix/var/nix/profiles/ci-tools/bin:/root/.nix-profile/bin:/nix/var/nix/profiles/default/bin \
    SSL_CERT_FILE=/nix/var/nix/profiles/ci-tools/etc/ssl/certs/ca-bundle.crt \
    NIX_SSL_CERT_FILE=/nix/var/nix/profiles/ci-tools/etc/ssl/certs/ca-bundle.crt
COPY bin /ci-tools/bin
COPY lib /ci-tools/lib
COPY tests /ci-tools/tests
WORKDIR /ci-tools
