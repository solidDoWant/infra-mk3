# couchgres publishes no image (CI only runs tests), so build one from the tagged source.

ARG BUILD_IMAGE

FROM ${BUILD_IMAGE} AS build

ARG COUCHGRES_VERSION
ARG COUCHGRES_COMMIT

RUN git clone --depth 1 --branch "${COUCHGRES_VERSION}" https://github.com/couchgres/couchgres /src
WORKDIR /src
# Tags can be moved; refuse to build anything other than the reviewed commit.
RUN test "$(git rev-parse HEAD)" = "${COUCHGRES_COMMIT}"
# Downloads the CouchDB source tarball (sha256-pinned by the script) for the embedded Fauxton UI.
RUN make fauxton
# QuickJS is pure Go (modernc.org/quickjs), so the binary can be fully static.
RUN CGO_ENABLED=0 go build \
        -trimpath \
        -buildvcs=true \
        -ldflags "-s -w -X github.com/couchgres/couchgres/internal/buildinfo.Version=${COUCHGRES_VERSION}" \
        -o /out/couchgres \
        ./cmd/couchgres

# Nothing at runtime needs a base: Postgres is plaintext to the Envoy sidecar,
# no time zones are loaded, the UID is numeric and nothing is written to disk.
# Enabling the replicator against https peers would need CA certs added.
FROM scratch

COPY --from=build /out/couchgres /usr/local/bin/couchgres
USER 65532:65532
EXPOSE 5984
ENTRYPOINT ["/usr/local/bin/couchgres"]
