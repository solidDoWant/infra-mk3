# Project Zomboid dedicated server (Steam app 380870), installed at build time so that a container
# start doesn't re-download ~7 GB of game content. That makes the image a complete copy of
# copyrighted game files, so - like the tug2 insurgency images - it must only ever be pushed to a
# private registry.

ARG RUNTIME_IMAGE=public.ecr.aws/docker/library/ubuntu:26.04@sha256:6a06111c3b0a8600feadb270aec771dc239bf407b25625f93f44ab00e11f4d3c

# The game is downloaded with DepotDownloader (https://github.com/SteamRE/DepotDownloader), not
# steamcmd: steamcmd is a 32-bit program, and the CI builds run in kata VMs whose kernel has no
# 32-bit support ("cannot execute binary file: Exec format error"). DepotDownloader is a 64-bit,
# self-contained .NET program that downloads the same depots with the same anonymous login.
# The checksum is of the release's linux-x64 zip; update both together.
# renovate: datasource=github-releases depName=SteamRE/DepotDownloader extractVersion=^DepotDownloader_(?<version>.+)$
ARG DEPOTDOWNLOADER_VERSION=3.4.0
ARG DEPOTDOWNLOADER_SHA256=a999dec66b4850fc961bd50366696d23c2d0fad7b18790e6a5647b2f19097a53

# Only fetches DepotDownloader; the game itself is downloaded straight into the runtime stage, so
# the ~7 GB install isn't copied from one stage to another (~50s in CI).
FROM ${RUNTIME_IMAGE} AS depotdownloader

ARG DEPOTDOWNLOADER_VERSION
ARG DEPOTDOWNLOADER_SHA256
RUN \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
        ca-certificates \
        curl \
        unzip \
        && \
    rm -rf /var/lib/apt/lists/* && \
    curl -fsSL -o /tmp/depotdownloader.zip \
        "https://github.com/SteamRE/DepotDownloader/releases/download/DepotDownloader_${DEPOTDOWNLOADER_VERSION}/DepotDownloader-linux-x64.zip" && \
    echo "${DEPOTDOWNLOADER_SHA256}  /tmp/depotdownloader.zip" | sha256sum -c - && \
    unzip -q /tmp/depotdownloader.zip -d /opt/depotdownloader && \
    rm /tmp/depotdownloader.zip

# Same trick the insurgency image uses: copying this empty directory with `--chown` into the
# runtime stage sets the owner of a directory there without making the files copied into it
# afterwards writable by the server.
RUN mkdir /empty-directory

FROM ${RUNTIME_IMAGE} AS gameserver

# The server brings its own JRE (jre64/) and its own native libraries (linux64/), so all the base
# image has to provide is what those link against. ca-certificates (which brings OpenSSL) is also
# what DepotDownloader needs below.
RUN \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
        ca-certificates \
        libstdc++6 \
        zlib1g \
        && \
    rm -rf /var/lib/apt/lists/*

# Branch names are the app's Steam branches: `public` is the current build, `legacy41` is the
# build 41 line, and a point release like `42.19` pins one build.
ARG PZ_BRANCH=public

RUN \
    # DepotDownloader is mounted for this step only, so it doesn't end up in the image.
    --mount=type=bind,from=depotdownloader,source=/opt/depotdownloader,target=/opt/depotdownloader \
    # The app is ~7 GB. Keeping DepotDownloader's staging directory lets an interrupted download
    # resume on the next build instead of starting from zero.
    --mount=type=cache,id=depotdownloader-staging,target=/opt/pz-server/.DepotDownloader/staging,sharing=locked \
    # Only needed for a password-protected beta branch. A build secret rather than a build arg so
    # that it stays out of the image history.
    --mount=type=secret,id=pz_branch_password \
    branch_args="-branch ${PZ_BRANCH}" && \
    if [ -s /run/secrets/pz_branch_password ]; then \
        branch_args="${branch_args} -branchpassword $(cat /run/secrets/pz_branch_password)"; \
    fi && \
    # The Linux 64-bit depots: the game, its Linux files, and the Steamworks redistributable
    # (steamclient.so). No login means the anonymous dedicated-server account. It needs no ICU for
    # what it does here. Each Steam CDN connection is slow on its own, so the download time is set
    # by how many run at once: the default of 8 took ~210s here, 32 took ~90s and 64 took ~60s.
    DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1 /opt/depotdownloader/DepotDownloader \
        -app 380870 -os linux -osarch 64 ${branch_args} -dir /opt/pz-server -validate \
        -max-downloads 64 && \
    # Steam stages and installs workshop mods under steamapps/, so that subtree belongs to the
    # server. The rest of the install stays root-owned and read-only to it. Without this the mod
    # download fails with the Steam IO error `onItemNotDownloaded result=37`.
    mkdir -p /opt/pz-server/steamapps && \
    chown -R 1000:1000 /opt/pz-server/steamapps

COPY --from=depotdownloader --chown=1000:1000 /empty-directory /var/lib/zomboid
COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

# Steamworks loads the Steam client library from the home directory rather than from the server
# directory, and without it the server exits about a second after logging "SteamUtils initialised
# successfully", with nothing in the log to say why. Starting with EXTRA_SERVER_ARGS=-nosteam is
# the quick way to tell that failure apart from a real startup problem.
#
# The directory it looks in is the one in /etc/passwd for the UID it runs as, not $HOME, so this
# has to be uid 1000's home from the base image. HOME is set to match for anything that does read
# the environment.
ENV HOME=/home/ubuntu
RUN \
    mkdir -p /home/ubuntu/.steam/sdk64 && \
    ln -s /opt/pz-server/steamclient.so /home/ubuntu/.steam/sdk64/steamclient.so && \
    chown -R 1000:1000 /home/ubuntu

USER 1000:1000

ENV SERVER_NAME=pzserver
ENV ADMIN_USERNAME=admin
# ADMIN_PASSWORD has to be set the first time a server starts - the server asks for one on the
# console otherwise, and a container has nothing to answer the prompt with. It deliberately has no
# ENV default here so that a password can never end up baked into an image.

# Left empty on purpose: the server binds every interface without it, and `-ip 0.0.0.0` makes it
# exit about a second after Steam initialises, with nothing in the log to say why. Set it only to
# bind one specific address.
ENV BIND_IP=
ENV PORT=16261
# Everything the server persists: the server INI and sandbox settings, the save, the player
# database, the logs, and the workshop mods it downloads. Mount a volume here.
ENV DATA_DIR=/var/lib/zomboid
# Overrides the -Xmx8g that ships in ProjectZomboid64.json. The entrypoint passes it to the
# launcher as a VM arg, so nothing in the game directory has to be writable to change the heap.
ENV MAX_HEAP=
ENV EXTRA_JAVA_OPTS=
ENV EXTRA_SERVER_ARGS=
ENV STEAM_VAC=true
# How long the server gets to write the world out after `save`/`quit` before it is killed.
ENV SHUTDOWN_TIMEOUT=120

WORKDIR /opt/pz-server

# The game port, plus PORT+1 for the second UDP channel the client connects on.
EXPOSE 16261/udp 16262/udp

ENTRYPOINT [ "/usr/local/bin/entrypoint.sh" ]
