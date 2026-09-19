# Project Zomboid dedicated server (Steam app 380870), installed at build time so that a container
# start doesn't re-download ~7 GB of game content. That makes the image a complete copy of
# copyrighted game files, so - like the tug2 insurgency images - it must only ever be pushed to a
# private registry.

ARG STEAMCMD_IMAGE=ghcr.io/gameservermanagers/steamcmd:ubuntu-24.04
ARG RUNTIME_IMAGE=ubuntu:24.04

FROM ${STEAMCMD_IMAGE} AS server-builder

# Branch names come from `steamcmd +login anonymous +app_info_print 380870 +quit`. `public` is the
# current build, `legacy41` is the build 41 line, and a point release like `42.19` pins one build.
ARG PZ_BRANCH=public

RUN \
    # The app is ~7 GB. Persisting the depot manifest cache and the in-progress chunks lets an
    # interrupted or failed app_update resume on the next build instead of starting from zero. A
    # clean install still clears `downloading`, so this speeds up resumes, not cache-miss builds.
    --mount=type=cache,id=steam-depotcache,target=/root/.local/share/Steam/depotcache,sharing=locked \
    --mount=type=cache,id=steam-downloading,target=/opt/pz-server/steamapps/downloading,sharing=locked \
    # Only needed for a password-protected beta branch. A build secret rather than a build arg so
    # that it stays out of the image history.
    --mount=type=secret,id=pz_branch_password \
    mkdir -p /opt/pz-server && \
    # steamcmd needs a run of its own to initialize before it will take an app_update, otherwise
    # that fails with "Missing configuration".
    steamcmd +login anonymous +quit && \
    branch_args="-beta ${PZ_BRANCH}" && \
    if [ -s /run/secrets/pz_branch_password ]; then \
        branch_args="${branch_args} -betapassword $(cat /run/secrets/pz_branch_password)"; \
    fi && \
    # "Error! App '380870' state is 0x202 after update job" means the builder ran out of disk.
    steamcmd +force_install_dir /opt/pz-server +login anonymous \
        +app_update 380870 ${branch_args} validate +quit

# Same trick the insurgency image uses: copying this empty directory with `--chown` into the
# runtime stage sets the owner of a directory there without making the files copied into it
# afterwards writable by the server.
RUN mkdir /empty-directory

FROM ${RUNTIME_IMAGE} AS gameserver

# The server brings its own JRE (jre64/) and its own native libraries (linux64/), so all the base
# image has to provide is what those link against.
RUN \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
        ca-certificates \
        libstdc++6 \
        zlib1g \
        && \
    rm -rf /var/lib/apt/lists/*

COPY --from=server-builder /opt/pz-server/ /opt/pz-server/

# Steam stages and installs workshop mods under steamapps/, so that subtree belongs to the server.
# The rest of the install stays root-owned and read-only to it. A --chown on an empty directory is
# not enough here - the copy above brings steamapps/ and its contents with it - and without the
# chown the download fails with the Steam IO error `onItemNotDownloaded result=37`.
RUN chown -R 1000:1000 /opt/pz-server/steamapps

COPY --from=server-builder --chown=1000:1000 /empty-directory /var/lib/zomboid
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
