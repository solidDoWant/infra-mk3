# A project's CI image: the dev shell of its flake.nix, so CI uses exactly the
# agents' toolchain, plus the Docker CLI and buildx for stages that build
# images or run kind. The build context is only flake.nix, flake.lock and the
# ci.yaml `image.inputs` (bin/ci-image), so Docker's layer cache rebuilds it
# only when the toolchain changes.
FROM ghcr.io/nixos/nix:2.36.0@sha256:746280551ddc1c72177d1a597c05eacac86dfaa18d5d649bf86411278bcd5470
ENV NIX_CONFIG="experimental-features = nix-command flakes"
COPY . /src/
# The flake refuses a path source, so the files go into a throwaway git
# repository first.
RUN cd /src && git init -q && git add -A && git -c user.email=ci@ci -c user.name=ci commit -qm devshell \
 && nix develop --profile /nix/var/nix/profiles/devshell 'git+file:///src' -c true \
 && nix print-dev-env /nix/var/nix/profiles/devshell > /etc/devshell.sh \
 && nix profile add --profile /nix/var/nix/profiles/ci-stage-tools --inputs-from 'git+file:///src' nixpkgs#docker-client nixpkgs#docker-buildx \
 && mkdir -p /usr/local/lib/docker/cli-plugins \
 && ln -s /nix/var/nix/profiles/ci-stage-tools/libexec/docker/cli-plugins/docker-buildx /usr/local/lib/docker/cli-plugins/docker-buildx \
 && echo 'export PATH="/nix/var/nix/profiles/ci-stage-tools/bin:$PATH"' >> /etc/devshell.sh \
 && nix-collect-garbage >/dev/null
