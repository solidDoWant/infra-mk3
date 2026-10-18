# livesync-bridge publishes no image. This follows upstream's Dockerfile, plus a wrapper
# (discover.ts) that builds the peer list from the vault databases on the server.

ARG BASE_IMAGE

FROM ${BASE_IMAGE}

ARG LIVESYNC_BRIDGE_COMMIT

USER root
RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates git && \
    git clone https://github.com/vrtmrz/livesync-bridge /app && \
    git -C /app checkout --detach "${LIVESYNC_BRIDGE_COMMIT}" && \
    rm -rf /app/.git && \
    apt-get purge -y git && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /deno-dir/location_data && \
    chown -R deno:deno /app /deno-dir

USER deno
WORKDIR /app

RUN deno install --frozen

COPY --chown=deno:deno discover.ts healthcheck.sh /app/
# Compile everything ahead of time so a read-only root filesystem is fine at runtime.
RUN deno cache discover.ts main.ts

CMD ["deno", "run", "-A", "discover.ts"]
