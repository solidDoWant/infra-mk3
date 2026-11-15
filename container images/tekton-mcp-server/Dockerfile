# tektoncd/mcp-server publishes no image (upstream deploys it with `ko` from a
# checkout), so build one from a pinned commit.

ARG BUILD_IMAGE

FROM ${BUILD_IMAGE} AS build

ARG MCP_SERVER_COMMIT

RUN apk add --no-cache git
RUN git init -q /src && cd /src && \
    git fetch -q --depth 1 https://github.com/tektoncd/mcp-server "${MCP_SERVER_COMMIT}" && \
    git checkout -q FETCH_HEAD
WORKDIR /src
# Dependencies are vendored upstream.
RUN CGO_ENABLED=0 go build \
        -mod=vendor \
        -trimpath \
        -ldflags "-s -w" \
        -o /out/tekton-mcp-server \
        ./cmd/tekton-mcp-server

# Static binary; it only needs CA certificates for the Kubernetes API (from
# the kubeconfig it's given) and Artifact Hub.
FROM scratch

COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=build /out/tekton-mcp-server /usr/local/bin/tekton-mcp-server
USER 65532:65532
ENTRYPOINT ["/usr/local/bin/tekton-mcp-server"]
