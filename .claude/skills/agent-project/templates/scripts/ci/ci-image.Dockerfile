# The image every CI stage runs in on Tekton: the dev shell of flake.nix, so CI
# uses exactly the agents' toolchain, plus the Docker CLI and buildx for the
# e2e stage. The build context is only flake.nix, flake.lock and a go.mod cut
# to its module, go and toolchain lines (scripts/ci/ci-image.sh), so Docker's
# layer cache rebuilds it only when the toolchain changes.
FROM ghcr.io/nixos/nix:2.35.6@sha256:b49cb33f3a7e5cf3933ad8774529de0e3807ec5cf54987aa7ccdfb49f2fc55ed
ENV NIX_CONFIG="experimental-features = nix-command flakes"
COPY flake.nix flake.lock go.mod /src/
# The flake refuses a path source, so the three files go into a throwaway git
# repository first.
RUN cd /src && git init -q && git add -A && git -c user.email=ci@ci -c user.name=ci commit -qm devshell \
 && nix develop --profile /nix/var/nix/profiles/devshell 'git+file:///src' -c true \
 && nix print-dev-env /nix/var/nix/profiles/devshell > /etc/devshell.sh \
 && nix profile add --profile /nix/var/nix/profiles/ci-tools --inputs-from 'git+file:///src' nixpkgs#docker-client nixpkgs#docker-buildx \
 && mkdir -p /usr/local/lib/docker/cli-plugins \
 && ln -s /nix/var/nix/profiles/ci-tools/libexec/docker/cli-plugins/docker-buildx /usr/local/lib/docker/cli-plugins/docker-buildx \
 && echo 'export PATH="/nix/var/nix/profiles/ci-tools/bin:$PATH"' >> /etc/devshell.sh \
 && nix-collect-garbage >/dev/null
