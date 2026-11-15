# tekton-mcp-server

Image of [tektoncd/mcp-server](https://github.com/tektoncd/mcp-server), the Tekton project's MCP
server, built from a pinned commit: upstream has no releases and publishes no image. A static
binary on an empty base, plus CA certificates.

Used by the `tekton` toolgate template (`cluster/gitops/ai/toolgate/catalog/tekton.yaml`).

## Building

```sh
make image             # build and push to ghcr.io/soliddowant/tekton-mcp-server
make image PUSH=false  # build and load locally
make print-image-name
```

The tag is `0.0.0-<short commit>-r<IMAGE_REVISION>`. Renovate follows upstream `main` and bumps
`MCP_SERVER_COMMIT`; push the new image, then update the digest-pinned reference in the template.
